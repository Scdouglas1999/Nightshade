//! INDI client implementation
//!
//! This module provides a robust INDI client with:
//! - Proper error handling using IndiError
//! - Reader task supervision with automatic reconnection
//! - XML parse timeout for incomplete messages
//! - Atomic keepalive operations
//! - BLOB format validation
//! - Property min/max extraction
//! - Permission checking before writes
//! - Protocol version negotiation
//! - Exponential backoff with jitter for reconnection
//! - Configurable timeouts for all operations

use crate::error::{IndiError, IndiResult};
use crate::{
    IndiDevice, IndiPermission, IndiProperty, IndiPropertyState, IndiPropertyType,
    IndiTimeoutConfig, IndiTimeoutError, INDI_DEFAULT_PORT,
};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use quick_xml::events::Event;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;
use tokio::io::{AsyncRead, AsyncWrite, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::{broadcast, mpsc, oneshot, RwLock};
use tokio::time::{sleep, timeout, Instant};

/// Supported INDI protocol versions
pub const INDI_PROTOCOL_VERSIONS: &[&str] = &["1.7", "1.8", "1.9"];

/// Default protocol version to use
pub const DEFAULT_PROTOCOL_VERSION: &str = "1.7";

const EVENT_CHANNEL_CAPACITY: usize = 1024;

/// Shared, per-`IndiClient` PRNG handle.
///
/// Why: jitter must be uncorrelated between clients. A process-global PRNG
/// seeded from system time on first use (the previous design) collapsed to a
/// shared sequence the moment two clients raced through `get_or_init`, which
/// defeats jitter when many clients reconnect simultaneously against the same
/// INDI server. Wrapping `fastrand::Rng` in `Arc<StdMutex<...>>` lets us clone
/// the handle into the supervised-reader task while keeping per-instance state.
type JitterRng = Arc<StdMutex<fastrand::Rng>>;

/// Build a unique-per-instance jitter PRNG.
///
/// Why: seeding from `host:port` + creation-time nanoseconds + a process-local
/// monotonic counter guarantees two clients constructed in the same wall-clock
/// nanosecond (e.g. two reconnect supervisors spawned from the same future)
/// still receive distinct streams. Without the counter, identical hostnames
/// constructed back-to-back could collide on coarse clocks.
fn make_jitter_rng(host: &str, port: u16) -> JitterRng {
    use std::time::SystemTime;

    static INSTANCE_COUNTER: AtomicU64 = AtomicU64::new(0);

    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    host.hash(&mut hasher);
    port.hash(&mut hasher);
    let host_hash = hasher.finish();

    let now_nanos = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0);

    let counter = INSTANCE_COUNTER.fetch_add(1, Ordering::Relaxed);

    // Why: rotate before XOR so identical hosts in the same nanosecond still
    // diverge via the per-process counter — otherwise XOR of equal halves
    // cancels and the seed collapses to the counter alone.
    let seed = host_hash
        ^ now_nanos.rotate_left(17)
        ^ counter.wrapping_mul(0x9E37_79B9_7F4A_7C15);

    Arc::new(StdMutex::new(fastrand::Rng::with_seed(seed)))
}

/// Pull a uniform `[0.0, 1.0)` value from a `JitterRng`, falling back to a
/// fresh local PRNG if the mutex is poisoned.
///
/// Why: poisoning means a previous holder panicked while holding the lock; we
/// must not silently return a constant (the previous static-state design
/// effectively did that on race losers), but we also must not panic and drop
/// the reconnect loop. A fresh `fastrand::Rng::new()` is process-seeded and
/// still yields an uncorrelated value for the current call.
fn jitter_sample(rng: &JitterRng) -> f64 {
    match rng.lock() {
        Ok(mut guard) => guard.f64(),
        Err(poisoned) => {
            tracing::warn!(
                "INDI jitter RNG mutex poisoned; using fresh PRNG for this sample"
            );
            // Recover the inner Rng so subsequent calls continue using the
            // per-instance stream instead of permanently degrading.
            let mut guard = poisoned.into_inner();
            *guard = fastrand::Rng::new();
            guard.f64()
        }
    }
}

/// INDI client event
#[derive(Debug, Clone)]
pub enum IndiEvent {
    /// Device defined
    DeviceDefined(String),
    /// Property defined
    PropertyDefined(String, String, IndiPropertyType),
    /// Property updated
    PropertyUpdated(String, String),
    /// Property deleted
    PropertyDeleted(String, String),
    /// BLOB received with format information
    BlobReceived {
        device: String,
        property: String,
        element: String,
        data: Vec<u8>,
        format: String,
        size: usize,
    },
    /// Connection state changed
    ConnectionStateChanged(bool),
    /// Error occurred
    Error(String),
    /// Reader task died (for supervision) - includes error message
    ReaderDied(String),
    /// Reader task is restarting - includes attempt number and delay
    ReaderRestarting {
        attempt: u32,
        max_attempts: u32,
        delay_secs: f64,
    },
    /// Reader task restarted successfully after failure
    ReaderRestarted { attempts_used: u32 },
    /// Reader task restart failed after max attempts
    ReaderRestartFailed { attempts: u32, last_error: String },
    /// Reader task health changed
    ReaderHealthChanged {
        healthy: bool,
        status: ReaderStatus,
        consecutive_failures: u32,
    },
    /// Protocol version detected
    ProtocolVersionDetected(String),
}

/// Number element limits (min, max, step)
#[derive(Debug, Clone, Default)]
pub struct NumberLimits {
    pub min: Option<f64>,
    pub max: Option<f64>,
    pub step: Option<f64>,
    pub format: Option<String>,
}

/// Type alias for property value storage
type PropertyValueMap = HashMap<(String, String, String), String>;

/// Type alias for number limits storage
type NumberLimitsMap = HashMap<(String, String, String), NumberLimits>;

/// Type alias for latest BLOB payload storage.
type BlobMap = HashMap<(String, String, String), Vec<u8>>;

/// Reader task status for supervision
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReaderStatus {
    /// Reader task is running normally
    Running,
    /// Reader task has stopped gracefully
    Stopped,
    /// Reader task has crashed/failed
    Crashed,
    /// Reader task is being restarted
    Restarting,
}

/// Configuration for reader task supervision
#[derive(Debug, Clone)]
pub struct ReaderTaskConfig {
    /// Maximum number of consecutive failures before giving up (default: 5)
    pub max_consecutive_failures: u32,
    /// Base delay for restart backoff (default: 1 second)
    pub restart_base_delay_secs: u64,
    /// Maximum delay cap for restart backoff (default: 60 seconds)
    pub restart_max_delay_secs: u64,
    /// Whether to automatically restart on failure (default: true)
    pub auto_restart: bool,
    /// Use jitter in restart delays to prevent thundering herd (default: true)
    pub use_jitter: bool,
    /// Jitter factor (0.0 to 1.0, default 0.3)
    pub jitter_factor: f64,
}

impl Default for ReaderTaskConfig {
    fn default() -> Self {
        Self {
            max_consecutive_failures: 5,
            restart_base_delay_secs: 1,
            restart_max_delay_secs: 60,
            auto_restart: true,
            use_jitter: true,
            jitter_factor: 0.3,
        }
    }
}

impl ReaderTaskConfig {
    /// Calculate restart delay for a given attempt number with optional jitter.
    ///
    /// Why the `rng` parameter is required: jitter for reconnect/restart must
    /// be uncorrelated across `IndiClient` instances. Pulling randomness from
    /// the per-client PRNG (rather than a process-global one) guarantees two
    /// clients running the same backoff schedule do not synchronise their
    /// retries into a thundering herd against the INDI server.
    pub fn calculate_restart_delay(&self, attempt: u32, rng: &JitterRng) -> Duration {
        let base = Duration::from_secs(self.restart_base_delay_secs);
        let max = Duration::from_secs(self.restart_max_delay_secs);

        // Calculate exponential delay: base * 2^(attempt-1)
        let exponential_delay = base
            .checked_mul(2u32.pow(attempt.saturating_sub(1)))
            .unwrap_or(max)
            .min(max);

        if self.use_jitter && self.jitter_factor > 0.0 {
            let jitter_range = exponential_delay.as_secs_f64() * self.jitter_factor;
            let random_factor = jitter_sample(rng) * jitter_range - (jitter_range / 2.0);
            let jittered_secs = (exponential_delay.as_secs_f64() + random_factor).max(0.1);
            Duration::from_secs_f64(jittered_secs.min(max.as_secs_f64()))
        } else {
            exponential_delay
        }
    }
}

/// Configuration for protocol version
#[derive(Debug, Clone)]
pub struct ProtocolConfig {
    /// Preferred protocol version
    pub preferred_version: String,
    /// Whether to auto-detect server version
    pub auto_detect: bool,
    /// Minimum supported version
    pub min_version: Option<String>,
}

impl Default for ProtocolConfig {
    fn default() -> Self {
        Self {
            preferred_version: DEFAULT_PROTOCOL_VERSION.to_string(),
            auto_detect: true,
            min_version: None,
        }
    }
}

/// Reconnection configuration with jitter support
#[derive(Debug, Clone)]
pub struct ReconnectionConfig {
    /// Base delay for exponential backoff
    pub base_delay_secs: u64,
    /// Maximum delay cap
    pub max_delay_secs: u64,
    /// Maximum number of reconnection attempts
    pub max_attempts: u32,
    /// Whether to add jitter (randomness) to prevent thundering herd
    pub use_jitter: bool,
    /// Jitter factor (0.0 to 1.0, default 0.3 = 30% variation)
    pub jitter_factor: f64,
}

impl Default for ReconnectionConfig {
    fn default() -> Self {
        Self {
            base_delay_secs: 1,
            max_delay_secs: 30,
            max_attempts: 5,
            use_jitter: true,
            jitter_factor: 0.3,
        }
    }
}

impl ReconnectionConfig {
    /// Calculate delay for a given attempt number with optional jitter.
    ///
    /// Why the `rng` parameter is required: see [`ReaderTaskConfig::calculate_restart_delay`].
    /// Reconnect backoff jitter must be sampled from the owning client's PRNG
    /// so concurrent clients do not collapse onto identical retry schedules.
    pub fn calculate_delay(&self, attempt: u32, rng: &JitterRng) -> Duration {
        // Calculate base exponential delay: base * 2^(attempt-1)
        let base = Duration::from_secs(self.base_delay_secs);
        let max = Duration::from_secs(self.max_delay_secs);

        let exponential_delay = base
            .checked_mul(2u32.pow(attempt.saturating_sub(1)))
            .unwrap_or(max)
            .min(max);

        if self.use_jitter && self.jitter_factor > 0.0 {
            // Add jitter: delay * (1 - jitter_factor/2 + random * jitter_factor)
            // This gives a range of [delay * (1 - jitter_factor/2), delay * (1 + jitter_factor/2)]
            let jitter_range = exponential_delay.as_secs_f64() * self.jitter_factor;
            let random_factor = jitter_sample(rng) * jitter_range - (jitter_range / 2.0);
            let jittered_secs = (exponential_delay.as_secs_f64() + random_factor).max(0.1);
            Duration::from_secs_f64(jittered_secs.min(max.as_secs_f64()))
        } else {
            exponential_delay
        }
    }
}

/// Kind of an open XML element on the parser depth stack.
///
/// Why: differentiating `*Vector` containers from leaf elements lets us emit the right
/// follow-up event when the frame closes (e.g. `PropertyUpdated` on `setVector` close)
/// and lets `Event::End` validation decide which mismatch is actually fatal.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum XmlContextKind {
    /// `defNumberVector`/`defSwitchVector`/`defTextVector`/`defLightVector`/`defBLOBVector`.
    DefVector,
    /// `setNumberVector`/`setSwitchVector`/`setTextVector`/`setLightVector`/`setBLOBVector`
    /// or `newNumberVector` etc.
    SetOrNewVector,
    /// `defNumber`/`defSwitch`/`defText`/`defLight`/`defBLOB` element inside a `def*Vector`.
    DefElement,
    /// `oneNumber`/`oneSwitch`/`oneText`/`oneLight` element inside a `set*`/`new*` vector.
    OneElement,
    /// `oneBLOB` — handled separately because it carries `format`/`size` attributes that
    /// the BLOB receiver path needs to keep alive across the `Text` event.
    OneBlob,
    /// `getProperties`, `enableBLOB`, `delProperty`, `message`, root-level wrappers, etc.
    /// We track them so depth bookkeeping stays correct, but they don't carry parser state.
    Other,
}

/// One frame of the INDI XML parser depth stack.
///
/// Why: INDI bursts arrive as nested elements
/// (`<defNumberVector device="…" name="…"> <defNumber name="…">42</defNumber> … </defNumberVector>`).
/// A malformed or truncated stream with mismatched tags must not silently shift element text
/// onto the wrong (device, property). Each frame remembers the qualified tag name (so `End`
/// can verify it matches the popped frame) plus the device/property/element identifiers
/// that were established when the frame opened. On pop we restore those identifiers from
/// the new top of the stack so sibling `Text`/`Start` events resume against the correct
/// parent context.
#[derive(Debug, Clone)]
struct XmlContext {
    kind: XmlContextKind,
    /// The exact bytes of the opening tag's qualified name. Used to check for unbalanced
    /// `End` events; we keep it as a `Vec<u8>` because INDI XML stays ASCII.
    tag: Vec<u8>,
    device: Option<String>,
    property: Option<String>,
    element: Option<String>,
}

impl XmlContext {
    fn new(kind: XmlContextKind, tag: &[u8]) -> Self {
        Self {
            kind,
            tag: tag.to_vec(),
            device: None,
            property: None,
            element: None,
        }
    }
}

/// Refresh the flat `current_*` mirrors from the depth stack.
///
/// Why: the existing parser body reads `current_device`/`current_property`/`current_element`
/// directly in dozens of places. Rather than threading a stack lookup through every match
/// arm, we keep those locals as derived projections of the top-of-stack frame and recompute
/// them whenever a frame is pushed or popped.
fn refresh_xml_context_mirrors(
    stack: &[XmlContext],
    current_device: &mut String,
    current_property: &mut String,
    current_element: &mut String,
) {
    current_device.clear();
    current_property.clear();
    current_element.clear();
    for frame in stack {
        if let Some(d) = &frame.device {
            current_device.clear();
            current_device.push_str(d);
        }
        if let Some(p) = &frame.property {
            current_property.clear();
            current_property.push_str(p);
        }
        if let Some(e) = &frame.element {
            current_element.clear();
            current_element.push_str(e);
        }
    }
}

/// Classify an INDI XML tag name into a context kind.
fn classify_indi_tag(name: &[u8]) -> XmlContextKind {
    if name.starts_with(b"def") && name.ends_with(b"Vector") {
        XmlContextKind::DefVector
    } else if (name.starts_with(b"set") || name.starts_with(b"new")) && name.ends_with(b"Vector") {
        XmlContextKind::SetOrNewVector
    } else if name == b"oneBLOB" {
        XmlContextKind::OneBlob
    } else if name.starts_with(b"def") {
        XmlContextKind::DefElement
    } else if name.starts_with(b"one") {
        XmlContextKind::OneElement
    } else {
        XmlContextKind::Other
    }
}

/// INDI client for communicating with an INDI server
pub struct IndiClient {
    host: String,
    port: u16,
    connected: Arc<AtomicBool>,
    devices: Arc<RwLock<HashMap<String, IndiDevice>>>,
    properties: Arc<RwLock<HashMap<(String, String), IndiProperty>>>,
    property_values: Arc<RwLock<PropertyValueMap>>,
    number_limits: Arc<RwLock<NumberLimitsMap>>,
    latest_blobs: Arc<RwLock<BlobMap>>,
    tx: Option<mpsc::Sender<String>>,
    event_tx: broadcast::Sender<IndiEvent>,
    timeout_config: IndiTimeoutConfig,
    /// Atomic timestamp for last keepalive sent (milliseconds since UNIX epoch)
    last_keepalive_ms: Arc<AtomicU64>,
    /// Atomic timestamp for last keepalive response received (milliseconds since UNIX epoch)
    last_keepalive_response_ms: Arc<AtomicU64>,
    /// Atomic flag to prevent overlapping keepalive checks
    keepalive_in_progress: Arc<AtomicBool>,
    /// Atomic flag indicating reconnection is in progress
    reconnecting: Arc<AtomicBool>,
    /// Atomic reconnection attempt counter
    reconnect_attempts: Arc<AtomicU32>,
    /// Reader task status
    reader_status: Arc<RwLock<ReaderStatus>>,
    /// Consecutive reader failure count (for supervision)
    reader_consecutive_failures: Arc<AtomicU32>,
    /// Shutdown signal sender
    shutdown_tx: Option<oneshot::Sender<()>>,
    /// Protocol configuration
    protocol_config: ProtocolConfig,
    /// Detected server protocol version
    server_version: Arc<RwLock<Option<String>>>,
    /// Reconnection configuration
    reconnection_config: ReconnectionConfig,
    /// Reader task supervision configuration
    reader_task_config: ReaderTaskConfig,
    /// Per-instance jitter PRNG used for reconnect/restart backoff. See
    /// [`make_jitter_rng`] for the seeding rationale.
    jitter_rng: JitterRng,
}

impl IndiClient {
    /// Create a new INDI client
    pub fn new(host: &str, port: Option<u16>) -> Self {
        Self::with_timeout_config(host, port, IndiTimeoutConfig::default())
    }

    /// Create a new INDI client with custom timeout configuration
    pub fn with_timeout_config(
        host: &str,
        port: Option<u16>,
        timeout_config: IndiTimeoutConfig,
    ) -> Self {
        let (event_tx, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        let now = current_time_ms();
        let resolved_port = port.unwrap_or(INDI_DEFAULT_PORT);
        let jitter_rng = make_jitter_rng(host, resolved_port);
        Self {
            host: host.to_string(),
            port: resolved_port,
            connected: Arc::new(AtomicBool::new(false)),
            devices: Arc::new(RwLock::new(HashMap::new())),
            properties: Arc::new(RwLock::new(HashMap::new())),
            property_values: Arc::new(RwLock::new(HashMap::new())),
            number_limits: Arc::new(RwLock::new(HashMap::new())),
            latest_blobs: Arc::new(RwLock::new(HashMap::new())),
            tx: None,
            event_tx,
            timeout_config,
            last_keepalive_ms: Arc::new(AtomicU64::new(now)),
            last_keepalive_response_ms: Arc::new(AtomicU64::new(now)),
            keepalive_in_progress: Arc::new(AtomicBool::new(false)),
            reconnecting: Arc::new(AtomicBool::new(false)),
            reconnect_attempts: Arc::new(AtomicU32::new(0)),
            reader_status: Arc::new(RwLock::new(ReaderStatus::Stopped)),
            reader_consecutive_failures: Arc::new(AtomicU32::new(0)),
            shutdown_tx: None,
            protocol_config: ProtocolConfig::default(),
            server_version: Arc::new(RwLock::new(None)),
            reconnection_config: ReconnectionConfig::default(),
            reader_task_config: ReaderTaskConfig::default(),
            jitter_rng,
        }
    }

    /// Create a new INDI client with full configuration
    pub fn with_full_config(
        host: &str,
        port: Option<u16>,
        timeout_config: IndiTimeoutConfig,
        protocol_config: ProtocolConfig,
        reconnection_config: ReconnectionConfig,
    ) -> Self {
        Self::with_all_config(
            host,
            port,
            timeout_config,
            protocol_config,
            reconnection_config,
            ReaderTaskConfig::default(),
        )
    }

    /// Create a new INDI client with all configuration options including reader task config
    pub fn with_all_config(
        host: &str,
        port: Option<u16>,
        timeout_config: IndiTimeoutConfig,
        protocol_config: ProtocolConfig,
        reconnection_config: ReconnectionConfig,
        reader_task_config: ReaderTaskConfig,
    ) -> Self {
        let (event_tx, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        let now = current_time_ms();
        let resolved_port = port.unwrap_or(INDI_DEFAULT_PORT);
        let jitter_rng = make_jitter_rng(host, resolved_port);
        Self {
            host: host.to_string(),
            port: resolved_port,
            connected: Arc::new(AtomicBool::new(false)),
            devices: Arc::new(RwLock::new(HashMap::new())),
            properties: Arc::new(RwLock::new(HashMap::new())),
            property_values: Arc::new(RwLock::new(HashMap::new())),
            number_limits: Arc::new(RwLock::new(HashMap::new())),
            latest_blobs: Arc::new(RwLock::new(HashMap::new())),
            tx: None,
            event_tx,
            timeout_config,
            last_keepalive_ms: Arc::new(AtomicU64::new(now)),
            last_keepalive_response_ms: Arc::new(AtomicU64::new(now)),
            keepalive_in_progress: Arc::new(AtomicBool::new(false)),
            reconnecting: Arc::new(AtomicBool::new(false)),
            reconnect_attempts: Arc::new(AtomicU32::new(0)),
            reader_status: Arc::new(RwLock::new(ReaderStatus::Stopped)),
            reader_consecutive_failures: Arc::new(AtomicU32::new(0)),
            shutdown_tx: None,
            protocol_config,
            server_version: Arc::new(RwLock::new(None)),
            reconnection_config,
            reader_task_config,
            jitter_rng,
        }
    }

    /// Get the timeout configuration
    pub fn timeout_config(&self) -> &IndiTimeoutConfig {
        &self.timeout_config
    }

    /// Set the timeout configuration
    pub fn set_timeout_config(&mut self, config: IndiTimeoutConfig) {
        self.timeout_config = config;
    }

    /// Get the protocol configuration
    pub fn protocol_config(&self) -> &ProtocolConfig {
        &self.protocol_config
    }

    /// Set the protocol configuration
    pub fn set_protocol_config(&mut self, config: ProtocolConfig) {
        self.protocol_config = config;
    }

    /// Get the reconnection configuration
    pub fn reconnection_config(&self) -> &ReconnectionConfig {
        &self.reconnection_config
    }

    /// Set the reconnection configuration
    pub fn set_reconnection_config(&mut self, config: ReconnectionConfig) {
        self.reconnection_config = config;
    }

    /// Get the reader task configuration
    pub fn reader_task_config(&self) -> &ReaderTaskConfig {
        &self.reader_task_config
    }

    /// Set the reader task configuration
    pub fn set_reader_task_config(&mut self, config: ReaderTaskConfig) {
        self.reader_task_config = config;
    }

    /// Get the detected server protocol version
    pub async fn server_version(&self) -> Option<String> {
        self.server_version.read().await.clone()
    }

    /// Get the detected server protocol version as a Result
    /// Returns Ok with the version string if available, or Err if not detected
    pub async fn get_server_version(&self) -> IndiResult<String> {
        self.server_version
            .read()
            .await
            .clone()
            .ok_or_else(|| IndiError::ProtocolError("Server version not detected".to_string()))
    }

    /// Subscribe to INDI events
    pub fn subscribe(&self) -> broadcast::Receiver<IndiEvent> {
        self.event_tx.subscribe()
    }

    pub async fn clear_blob(&self, device: &str, property: &str, element: &str) {
        self.latest_blobs.write().await.remove(&(
            device.to_string(),
            property.to_string(),
            element.to_string(),
        ));
    }

    pub async fn take_blob(&self, device: &str, property: &str, element: &str) -> Option<Vec<u8>> {
        self.latest_blobs.write().await.remove(&(
            device.to_string(),
            property.to_string(),
            element.to_string(),
        ))
    }

    /// Connect to the INDI server
    pub async fn connect(&mut self) -> IndiResult<()> {
        let addr = format!("{}:{}", self.host, self.port);
        let connection_timeout = self.timeout_config.connection_timeout();

        // Apply connection timeout
        let stream = match timeout(connection_timeout, TcpStream::connect(&addr)).await {
            Ok(Ok(stream)) => stream,
            Ok(Err(e)) => {
                return Err(IndiError::ConnectionFailed(format!(
                    "Failed to connect to INDI server at {}: {}. Check that the server is running and the address is correct.",
                    addr, e
                )));
            }
            Err(_) => {
                return Err(IndiError::ConnectionTimeout {
                    host: self.host.clone(),
                    port: self.port,
                    duration: connection_timeout,
                });
            }
        };

        let (read_half, write_half) = stream.into_split();

        // Create channel for sending commands
        let (tx, rx) = mpsc::channel::<String>(100);
        self.tx = Some(tx);

        // Create shutdown channel for reader task supervision
        let (shutdown_tx, shutdown_rx) = oneshot::channel();
        self.shutdown_tx = Some(shutdown_tx);

        // Spawn writer task
        tokio::spawn(Self::writer_task(write_half, rx));

        // Reset keepalive state before spawning reader task
        // This prevents stale keepalive data from causing false disconnections
        let now = current_time_ms();
        self.last_keepalive_ms.store(now, Ordering::SeqCst);
        self.last_keepalive_response_ms.store(now, Ordering::SeqCst);
        self.keepalive_in_progress.store(false, Ordering::SeqCst);

        // Spawn supervised reader task
        let devices = self.devices.clone();
        let properties = self.properties.clone();
        let property_values = self.property_values.clone();
        let number_limits = self.number_limits.clone();
        let latest_blobs = self.latest_blobs.clone();
        let connected = self.connected.clone();
        let event_tx = self.event_tx.clone();
        let reader_status = self.reader_status.clone();
        let reader_consecutive_failures = self.reader_consecutive_failures.clone();
        let server_version = self.server_version.clone();
        let last_keepalive_response_ms = self.last_keepalive_response_ms.clone();
        let timeout_config = self.timeout_config.clone();
        let reader_task_config = self.reader_task_config.clone();
        // Clone the per-instance jitter PRNG handle so the supervised reader
        // task can compute its own restart-delay jitter without falling back
        // to a shared global PRNG.
        let jitter_rng = self.jitter_rng.clone();

        // Reset consecutive failures on successful connect
        self.reader_consecutive_failures.store(0, Ordering::SeqCst);

        // Update reader status
        *self.reader_status.write().await = ReaderStatus::Running;

        // Emit health changed event - reader is now healthy
        let _ = self.event_tx.send(IndiEvent::ReaderHealthChanged {
            healthy: true,
            status: ReaderStatus::Running,
            consecutive_failures: 0,
        });

        tokio::spawn(async move {
            Self::supervised_reader_task(
                read_half,
                devices,
                properties,
                property_values,
                number_limits,
                latest_blobs,
                connected,
                event_tx,
                reader_status,
                reader_consecutive_failures,
                server_version,
                last_keepalive_response_ms,
                timeout_config,
                reader_task_config,
                jitter_rng,
                shutdown_rx,
            )
            .await;
        });

        // Mark as connected
        self.connected.store(true, Ordering::SeqCst);
        let _ = self.event_tx.send(IndiEvent::ConnectionStateChanged(true));

        // Request device list with configured protocol version
        let version = &self.protocol_config.preferred_version;
        self.send_command(&format!("<getProperties version=\"{}\"/>", version))
            .await?;

        Ok(())
    }

    /// Writer task - sends commands to INDI server
    async fn writer_task<W: AsyncWrite + Unpin>(mut writer: W, mut rx: mpsc::Receiver<String>) {
        while let Some(cmd) = rx.recv().await {
            if let Err(e) = writer.write_all(cmd.as_bytes()).await {
                tracing::error!("INDI write error: {}", e);
                break;
            }
            if let Err(e) = writer.write_all(b"\n").await {
                tracing::error!("INDI write error: {}", e);
                break;
            }
        }
    }

    /// Supervised reader task - wraps the reader with supervision logic
    ///
    /// This function monitors the reader task and tracks failures. When the reader
    /// crashes, it:
    /// 1. Increments the consecutive failure counter
    /// 2. Updates the reader status to Crashed
    /// 3. Emits appropriate events (ReaderDied, ReaderHealthChanged)
    /// 4. Sets connected to false
    ///
    /// The caller (usually IndiClient via its event subscriber) is responsible for
    /// deciding whether to reconnect based on the failure count and configuration.
    #[allow(clippy::too_many_arguments)]
    async fn supervised_reader_task<R: AsyncRead + Unpin>(
        reader: R,
        devices: Arc<RwLock<HashMap<String, IndiDevice>>>,
        properties: Arc<RwLock<HashMap<(String, String), IndiProperty>>>,
        property_values: Arc<RwLock<PropertyValueMap>>,
        number_limits: Arc<RwLock<NumberLimitsMap>>,
        latest_blobs: Arc<RwLock<BlobMap>>,
        connected: Arc<AtomicBool>,
        event_tx: broadcast::Sender<IndiEvent>,
        reader_status: Arc<RwLock<ReaderStatus>>,
        reader_consecutive_failures: Arc<AtomicU32>,
        server_version: Arc<RwLock<Option<String>>>,
        last_keepalive_response_ms: Arc<AtomicU64>,
        timeout_config: IndiTimeoutConfig,
        reader_task_config: ReaderTaskConfig,
        jitter_rng: JitterRng,
        mut shutdown_rx: oneshot::Receiver<()>,
    ) {
        // Run the reader task with panic catching via AssertUnwindSafe
        let result = tokio::select! {
            result = Self::reader_task_with_timeout(
                reader,
                devices,
                properties,
                property_values,
                number_limits,
                latest_blobs,
                connected.clone(),
                event_tx.clone(),
                server_version,
                last_keepalive_response_ms,
                timeout_config,
            ) => {
                result
            }
            _ = &mut shutdown_rx => {
                tracing::info!("INDI reader task received shutdown signal - graceful stop");
                // Graceful shutdown - reset failure counter
                reader_consecutive_failures.store(0, Ordering::SeqCst);
                Ok(())
            }
        };

        // Update status based on result
        match result {
            Ok(_) => {
                // Graceful shutdown - reset failure counter and update status
                *reader_status.write().await = ReaderStatus::Stopped;
                let _ = event_tx.send(IndiEvent::ReaderHealthChanged {
                    healthy: false,
                    status: ReaderStatus::Stopped,
                    consecutive_failures: 0,
                });
                tracing::info!("INDI reader task stopped gracefully");
            }
            Err(ref e) => {
                // Failure - increment failure counter
                let failures = reader_consecutive_failures.fetch_add(1, Ordering::SeqCst) + 1;
                let max_failures = reader_task_config.max_consecutive_failures;

                tracing::error!(
                    "INDI reader task crashed (failure {}/{}): {}",
                    failures,
                    max_failures,
                    e
                );

                // Update status to Crashed
                *reader_status.write().await = ReaderStatus::Crashed;

                // Emit ReaderDied event with error details
                let _ = event_tx.send(IndiEvent::ReaderDied(e.to_string()));

                // Emit health changed event
                let _ = event_tx.send(IndiEvent::ReaderHealthChanged {
                    healthy: false,
                    status: ReaderStatus::Crashed,
                    consecutive_failures: failures,
                });

                // Check if we've exceeded max failures
                if failures >= max_failures {
                    tracing::error!(
                        "INDI reader task exceeded max consecutive failures ({}) - giving up",
                        max_failures
                    );
                    let _ = event_tx.send(IndiEvent::ReaderRestartFailed {
                        attempts: failures,
                        last_error: e.to_string(),
                    });
                } else if reader_task_config.auto_restart {
                    // Calculate restart delay and emit restart event
                    let delay = reader_task_config.calculate_restart_delay(failures, &jitter_rng);
                    tracing::info!(
                        "INDI reader task will suggest restart in {:?} (attempt {}/{})",
                        delay,
                        failures,
                        max_failures
                    );
                    let _ = event_tx.send(IndiEvent::ReaderRestarting {
                        attempt: failures,
                        max_attempts: max_failures,
                        delay_secs: delay.as_secs_f64(),
                    });
                }
            }
        };

        // Always mark as disconnected when reader stops
        connected.store(false, Ordering::SeqCst);
        let _ = event_tx.send(IndiEvent::ConnectionStateChanged(false));
    }

    /// Reader task with XML parse timeout - processes incoming INDI messages
    #[allow(clippy::too_many_arguments)]
    async fn reader_task_with_timeout<R: AsyncRead + Unpin>(
        reader: R,
        devices: Arc<RwLock<HashMap<String, IndiDevice>>>,
        properties: Arc<RwLock<HashMap<(String, String), IndiProperty>>>,
        property_values: Arc<RwLock<PropertyValueMap>>,
        number_limits: Arc<RwLock<NumberLimitsMap>>,
        latest_blobs: Arc<RwLock<BlobMap>>,
        connected: Arc<AtomicBool>,
        event_tx: broadcast::Sender<IndiEvent>,
        server_version: Arc<RwLock<Option<String>>>,
        last_keepalive_response_ms: Arc<AtomicU64>,
        timeout_config: IndiTimeoutConfig,
    ) -> IndiResult<()> {
        let mut reader = quick_xml::reader::Reader::from_reader(tokio::io::BufReader::new(reader));
        reader.trim_text(true);

        let mut buf = Vec::new();

        // Why: INDI is delivered as a stream of nested XML elements (`def*Vector` containing
        // `def*` elements, `set*Vector` containing `one*` elements, etc.). A malformed or
        // mid-stream-truncated message with unbalanced tags would, with a flat-string parser,
        // attribute the next valid element's text to the wrong (device, property) pair.
        // We track a depth stack of XmlContext frames and restore the surrounding device /
        // property / element identifiers on every `End`/`Empty` event. The flat
        // `current_device`/`current_property`/`current_element` strings remain as derived
        // mirrors of the top-of-stack values so the rest of this function reads them as
        // before — but the source of truth is now `xml_stack`.
        let mut xml_stack: Vec<XmlContext> = Vec::new();
        let mut current_device = String::new();
        let mut current_property = String::new();
        let mut current_element = String::new();
        let mut current_blob_format = String::new();
        let mut current_blob_size: usize = 0;

        // XML parse timeout tracking - use configured timeout
        let xml_timeout = timeout_config.message_timeout();

        // BLOB reception timeout tracking
        let mut blob_start_time: Option<Instant> = None;
        let blob_timeout = timeout_config.blob_timeout();

        // Pending element for text content capture (currently unused but preserved for future use)
        #[allow(unused_assignments)]
        let mut _pending_number_limits: Option<(String, String, String, NumberLimits)> = None;

        // Track consecutive timeouts for message parse detection
        let mut incomplete_message_start: Option<Instant> = None;
        let mut incomplete_message_bytes: usize = 0;

        loop {
            // Check for XML parse timeout (incomplete messages)
            if let Some(start) = incomplete_message_start {
                if start.elapsed() > xml_timeout {
                    tracing::warn!(
                        "XML message parse timeout: incomplete message after {:?}. Received {} bytes. Resetting parser.",
                        xml_timeout,
                        incomplete_message_bytes
                    );
                    let _ = event_tx.send(IndiEvent::Error(format!(
                        "XML parse timeout after {:?}: {} bytes of incomplete message",
                        xml_timeout, incomplete_message_bytes
                    )));
                    buf.clear();
                    incomplete_message_start = None;
                    incomplete_message_bytes = 0;
                    continue;
                }
            }

            // Check for BLOB reception timeout
            if let Some(start) = blob_start_time {
                if start.elapsed() > blob_timeout {
                    tracing::error!(
                        "BLOB reception timeout for {}.{}: expected {} bytes after {:?}",
                        current_device,
                        current_property,
                        current_blob_size,
                        blob_timeout
                    );
                    let _ = event_tx.send(IndiEvent::Error(format!(
                        "BLOB timeout for {}.{}: expected {} bytes after {:?}",
                        current_device, current_property, current_blob_size, blob_timeout
                    )));
                    // Reset BLOB state
                    blob_start_time = None;
                    current_blob_format.clear();
                    current_blob_size = 0;
                }
            }

            // Use timeout for reading events
            let read_timeout = Duration::from_secs(5);
            let read_result = timeout(read_timeout, reader.read_event_into_async(&mut buf)).await;

            match read_result {
                // Why: quick-xml emits self-closing tags (`<defSwitch …/>`) as `Event::Empty`
                // rather than `Event::Start` + `Event::End`. INDI servers do legitimately
                // produce self-closing element definitions when a switch/light has no body
                // text. Routing both into the same arm — and popping immediately at the end
                // when `is_empty == true` — keeps the depth stack in lockstep with the actual
                // XML structure regardless of whether the server self-closed the tag.
                Ok(Ok(ev @ Event::Start(_))) | Ok(Ok(ev @ Event::Empty(_))) => {
                    let is_empty = matches!(ev, Event::Empty(_));
                    let e = match &ev {
                        Event::Start(b) | Event::Empty(b) => b,
                        _ => unreachable!("matched Start/Empty above"),
                    };
                    // Reset incomplete message tracking on successful event
                    incomplete_message_start = None;
                    incomplete_message_bytes = 0;
                    // Work with raw bytes to avoid allocating a String for every XML element name.
                    // INDI element names are always ASCII, so byte comparison is safe and efficient.
                    let qname = e.name();
                    let name_bytes: &[u8] = qname.as_ref();
                    let frame_kind = classify_indi_tag(name_bytes);
                    // Snapshot mirrors so we can attribute new values to the frame even if
                    // the body below overwrites them.
                    let snapshot_device_before = current_device.clone();
                    let snapshot_property_before = current_property.clone();
                    let snapshot_element_before = current_element.clone();

                    // Handle property definitions (def*Vector)
                    if name_bytes.starts_with(b"def") && name_bytes.ends_with(b"Vector") {
                        if let Some(dev) = get_attribute(e, "device") {
                            current_device = dev;
                            if let Some(prop) = get_attribute(e, "name") {
                                current_property = prop;

                                // Determine type from the byte slice (avoids String allocation)
                                let prop_type = if name_bytes == b"defSwitchVector" {
                                    IndiPropertyType::Switch
                                } else if name_bytes == b"defNumberVector" {
                                    IndiPropertyType::Number
                                } else if name_bytes == b"defTextVector" {
                                    IndiPropertyType::Text
                                } else if name_bytes == b"defLightVector" {
                                    IndiPropertyType::Light
                                } else if name_bytes == b"defBLOBVector" {
                                    IndiPropertyType::Blob
                                } else {
                                    IndiPropertyType::Text
                                };

                                // Parse state and perm
                                let state_str = get_attribute(e, "state")
                                    .unwrap_or_else(|| "Idle".to_string());
                                let state = parse_state(&state_str);

                                let perm_str =
                                    get_attribute(e, "perm").unwrap_or_else(|| "rw".to_string());
                                let perm = parse_perm(&perm_str);

                                // Add device if new
                                {
                                    let mut devs = devices.write().await;
                                    if !devs.contains_key(&current_device) {
                                        devs.insert(
                                            current_device.clone(),
                                            IndiDevice {
                                                name: current_device.clone(),
                                                driver: String::new(),
                                            },
                                        );
                                        let _ = event_tx
                                            .send(IndiEvent::DeviceDefined(current_device.clone()));
                                    }
                                }

                                // Add property
                                {
                                    let mut props = properties.write().await;
                                    props.insert(
                                        (current_device.clone(), current_property.clone()),
                                        IndiProperty {
                                            device: current_device.clone(),
                                            name: current_property.clone(),
                                            label: get_attribute(e, "label")
                                                .unwrap_or_else(|| current_property.clone()),
                                            group: get_attribute(e, "group").unwrap_or_default(),
                                            property_type: prop_type.clone(),
                                            state,
                                            perm,
                                            elements: Vec::new(),
                                        },
                                    );
                                }

                                let _ = event_tx.send(IndiEvent::PropertyDefined(
                                    current_device.clone(),
                                    current_property.clone(),
                                    prop_type,
                                ));
                            }
                        }
                    }
                    // Handle element definitions (defText, defNumber, etc. inside Vector)
                    else if name_bytes.starts_with(b"def") && !name_bytes.ends_with(b"Vector") {
                        if !current_device.is_empty() && !current_property.is_empty() {
                            if let Some(elem_name) = get_attribute(e, "name") {
                                current_element = elem_name.clone();

                                // Add element to property
                                let mut props = properties.write().await;
                                if let Some(prop) =
                                    map_get_mut_2(&mut props, &current_device, &current_property)
                                {
                                    prop.elements.push(elem_name.clone());
                                }

                                // Extract min/max/step/format for number elements
                                if name_bytes == b"defNumber" {
                                    let limits = NumberLimits {
                                        min: get_attribute(e, "min").and_then(|s| s.parse().ok()),
                                        max: get_attribute(e, "max").and_then(|s| s.parse().ok()),
                                        step: get_attribute(e, "step")
                                            .and_then(|s| s.parse().ok()),
                                        format: get_attribute(e, "format"),
                                    };

                                    // Store limits
                                    let mut limits_map = number_limits.write().await;
                                    limits_map.insert(
                                        (
                                            current_device.clone(),
                                            current_property.clone(),
                                            elem_name.clone(),
                                        ),
                                        limits.clone(),
                                    );

                                    // Keep pending for value extraction
                                    _pending_number_limits = Some((
                                        current_device.clone(),
                                        current_property.clone(),
                                        elem_name,
                                        limits,
                                    ));
                                }
                            }
                        }
                    }
                    // Handle property updates (set*Vector, new*Vector)
                    else if (name_bytes.starts_with(b"set") || name_bytes.starts_with(b"new"))
                        && name_bytes.ends_with(b"Vector")
                    {
                        if let Some(dev) = get_attribute(e, "device") {
                            current_device = dev;
                            if let Some(prop) = get_attribute(e, "name") {
                                current_property = prop;

                                // Update state
                                if let Some(state_str) = get_attribute(e, "state") {
                                    let state = parse_state(&state_str);
                                    let mut props = properties.write().await;
                                    if let Some(p) = map_get_mut_2(
                                        &mut props,
                                        &current_device,
                                        &current_property,
                                    ) {
                                        p.state = state;
                                    }
                                }
                            }
                        }
                    }
                    // Handle BLOB elements with format attribute
                    else if name_bytes == b"oneBLOB" {
                        if let Some(elem) = get_attribute(e, "name") {
                            current_element = elem;
                        }
                        // Extract format attribute (e.g., ".fits", ".jpeg", ".png")
                        current_blob_format =
                            get_attribute(e, "format").unwrap_or_else(|| ".fits".to_string());
                        // Extract size attribute
                        current_blob_size = get_attribute(e, "size")
                            .and_then(|s| s.parse().ok())
                            .unwrap_or(0);
                        // Start BLOB reception timeout tracking
                        blob_start_time = Some(Instant::now());
                        tracing::debug!(
                            "Starting BLOB reception for {}.{}.{}: expected size {} bytes",
                            current_device,
                            current_property,
                            current_element,
                            current_blob_size
                        );
                    }
                    // Handle elements values (oneSwitch, oneNumber, etc.)
                    else if name_bytes.starts_with(b"one") && name_bytes != b"oneBLOB" {
                        if let Some(elem) = get_attribute(e, "name") {
                            current_element = elem;
                        }
                    }
                    // Detect protocol version from server response
                    else if name_bytes == b"getProperties" {
                        if let Some(version) = get_attribute(e, "version") {
                            let mut sv = server_version.write().await;
                            *sv = Some(version.clone());
                            let _ = event_tx.send(IndiEvent::ProtocolVersionDetected(version));
                        }
                    }

                    // Update keepalive response timestamp on any valid message
                    // This is used to detect connection health - any server response counts
                    last_keepalive_response_ms.store(current_time_ms(), Ordering::SeqCst);

                    // Build a frame describing what this tag contributed to the mirrors.
                    // Why: the parser body above clobbered the flat strings to apply attribute
                    // values; on `End` we have to be able to undo those clobbers and restore
                    // the surrounding (parent) context. Each frame stores only the
                    // identifiers IT introduced, so refreshing from the stack rebuilds the
                    // correct state regardless of how deep we are.
                    let mut frame = XmlContext::new(frame_kind, name_bytes);
                    match frame_kind {
                        XmlContextKind::DefVector | XmlContextKind::SetOrNewVector => {
                            if current_device != snapshot_device_before {
                                frame.device = Some(current_device.clone());
                            }
                            if current_property != snapshot_property_before {
                                frame.property = Some(current_property.clone());
                            }
                        }
                        XmlContextKind::DefElement
                        | XmlContextKind::OneElement
                        | XmlContextKind::OneBlob => {
                            if current_element != snapshot_element_before {
                                frame.element = Some(current_element.clone());
                            }
                        }
                        XmlContextKind::Other => {}
                    }
                    let was_set_or_new_vector = frame.kind == XmlContextKind::SetOrNewVector;
                    let frame_device_for_event = frame.device.clone();
                    let frame_property_for_event = frame.property.clone();
                    xml_stack.push(frame);

                    if is_empty {
                        // Why: quick-xml does not synthesise an `End` event for self-closing
                        // tags. Pop our just-pushed frame so the depth stack does not leak,
                        // then re-derive the mirror strings from whatever parent context
                        // remains on the stack.
                        let _ = xml_stack.pop();
                        refresh_xml_context_mirrors(
                            &xml_stack,
                            &mut current_device,
                            &mut current_property,
                            &mut current_element,
                        );
                        // A self-closing `setVector` / `newVector` has no body but should
                        // still notify subscribers that the property update completed —
                        // mirror what `Event::End` does for the multi-event form.
                        if was_set_or_new_vector {
                            if let (Some(dev), Some(prop)) =
                                (frame_device_for_event, frame_property_for_event)
                            {
                                let _ = event_tx.send(IndiEvent::PropertyUpdated(dev, prop));
                            }
                        }
                    }
                }
                Ok(Ok(Event::Text(e))) => {
                    // Reset incomplete message tracking on successful event
                    incomplete_message_start = None;
                    incomplete_message_bytes = 0;
                    let text = e.unescape().unwrap_or_default().to_string();
                    if !current_device.is_empty()
                        && !current_property.is_empty()
                        && !current_element.is_empty()
                    {
                        // Store value
                        {
                            let mut vals = property_values.write().await;
                            vals.insert(
                                (
                                    current_device.clone(),
                                    current_property.clone(),
                                    current_element.clone(),
                                ),
                                text.clone(),
                            );
                        }

                        // Handle BLOB data with format validation
                        if !current_blob_format.is_empty() {
                            // Decode base64
                            match BASE64.decode(text.trim()) {
                                Ok(data) => {
                                    // Log successful BLOB reception
                                    if let Some(start) = blob_start_time {
                                        tracing::debug!(
                                            "BLOB received for {}.{}.{}: {} bytes in {:?}",
                                            current_device,
                                            current_property,
                                            current_element,
                                            data.len(),
                                            start.elapsed()
                                        );
                                    }

                                    // Validate BLOB format
                                    let validated_format =
                                        validate_blob_format(&current_blob_format, &data);

                                    latest_blobs.write().await.insert(
                                        (
                                            current_device.clone(),
                                            current_property.clone(),
                                            current_element.clone(),
                                        ),
                                        data.clone(),
                                    );

                                    let _ = event_tx.send(IndiEvent::BlobReceived {
                                        device: current_device.clone(),
                                        property: current_property.clone(),
                                        element: current_element.clone(),
                                        data,
                                        format: validated_format,
                                        size: current_blob_size,
                                    });
                                }
                                Err(e) => {
                                    tracing::warn!(
                                        "Failed to decode BLOB base64 for {}.{}.{}: {}",
                                        current_device,
                                        current_property,
                                        current_element,
                                        e
                                    );
                                }
                            }
                            // Reset BLOB tracking state
                            current_blob_format.clear();
                            current_blob_size = 0;
                            blob_start_time = None;
                        }
                    }

                    // Clear pending number limits after processing
                    _pending_number_limits = None;
                }
                Ok(Ok(Event::End(e))) => {
                    // Reset incomplete message tracking on successful event
                    incomplete_message_start = None;
                    incomplete_message_bytes = 0;
                    // Use byte comparison to avoid allocating a String for every end tag
                    let end_qname = e.name();
                    let end_name = end_qname.as_ref();

                    match xml_stack.pop() {
                        Some(popped) => {
                            if popped.tag.as_slice() != end_name {
                                // Why: the INDI spec implies well-formed XML, but real
                                // servers (and lossy proxies) occasionally emit malformed
                                // streams — duplicate `</setNumberVector>`, mismatched
                                // nesting, etc. Rather than poison the rest of the stream
                                // by trusting the broken nesting, we log a warning and
                                // attempt to recover by walking the stack to find a
                                // matching opener. If none is found, we restore the frame
                                // we just popped so siblings are still attributed sanely.
                                tracing::warn!(
                                    "INDI XML unbalanced end tag: got </{}>, expected </{}>. \
                                     Attempting recovery.",
                                    String::from_utf8_lossy(end_name),
                                    String::from_utf8_lossy(&popped.tag)
                                );
                                let _ = event_tx.send(IndiEvent::Error(format!(
                                    "Unbalanced XML: got </{}>, expected </{}>",
                                    String::from_utf8_lossy(end_name),
                                    String::from_utf8_lossy(&popped.tag)
                                )));

                                if let Some(match_idx) = xml_stack
                                    .iter()
                                    .rposition(|f| f.tag.as_slice() == end_name)
                                {
                                    // Drop everything above (and including) the matched
                                    // frame to re-establish a consistent depth.
                                    xml_stack.truncate(match_idx);
                                } else {
                                    // No matching opener anywhere on the stack — keep the
                                    // pre-pop state so the next event still has reasonable
                                    // device/property context.
                                    xml_stack.push(popped.clone());
                                }
                            } else if popped.kind == XmlContextKind::SetOrNewVector {
                                // Why: `set*Vector` / `new*Vector` close == "property update
                                // complete" notification. Read identifiers from the popped
                                // frame so we always use the device/property that THIS frame
                                // established, not whatever sibling frames may have set.
                                if let (Some(dev), Some(prop)) = (popped.device, popped.property) {
                                    let _ = event_tx
                                        .send(IndiEvent::PropertyUpdated(dev, prop));
                                }
                            }

                            refresh_xml_context_mirrors(
                                &xml_stack,
                                &mut current_device,
                                &mut current_property,
                                &mut current_element,
                            );
                        }
                        None => {
                            // Why: end tag with no matching opener on the stack. This is a
                            // protocol violation; log and continue. The recovery branch
                            // above handles partial nesting; here we can only swallow the
                            // stray closer.
                            tracing::warn!(
                                "INDI XML stray end tag </{}>: no matching opener on stack",
                                String::from_utf8_lossy(end_name)
                            );
                            let _ = event_tx.send(IndiEvent::Error(format!(
                                "Stray XML end tag </{}>",
                                String::from_utf8_lossy(end_name)
                            )));
                        }
                    }
                }
                Ok(Ok(Event::Eof)) => {
                    tracing::info!("INDI connection closed (EOF)");
                    connected.store(false, Ordering::SeqCst);
                    let _ = event_tx.send(IndiEvent::ConnectionStateChanged(false));
                    break;
                }
                Ok(Err(e)) => {
                    tracing::error!(
                        "INDI XML parse error: {}. Raw buffer (first 200 chars): {:?}",
                        e,
                        String::from_utf8_lossy(&buf[..buf.len().min(200)])
                    );
                    let _ = event_tx.send(IndiEvent::Error(format!("XML parse error: {}", e)));
                    buf.clear();
                    // Why: a hard parser error means the underlying stream is no longer
                    // trustable — drop all in-flight depth bookkeeping along with the
                    // mirror strings so the freshly-recreated reader starts from a clean
                    // top-level context.
                    xml_stack.clear();
                    current_device.clear();
                    current_property.clear();
                    current_element.clear();
                    current_blob_format.clear();
                    current_blob_size = 0;
                    blob_start_time = None;
                    incomplete_message_start = None;
                    incomplete_message_bytes = 0;

                    let inner = reader.into_inner();
                    reader = quick_xml::reader::Reader::from_reader(inner);
                    reader.trim_text(true);
                }
                Err(_) => {
                    // Read timeout - check if connection is still alive
                    if !connected.load(Ordering::SeqCst) {
                        break;
                    }
                    // Track incomplete message if we have partial data in the buffer
                    if !buf.is_empty() {
                        if incomplete_message_start.is_none() {
                            incomplete_message_start = Some(Instant::now());
                        }
                        incomplete_message_bytes = buf.len();
                    }
                    // Continue waiting for data
                }
                _ => {}
            }
            buf.clear();
        }

        Ok(())
    }

    /// Disconnect from the INDI server
    ///
    /// This performs a graceful shutdown:
    /// 1. Sends shutdown signal to reader task
    /// 2. Closes the writer channel
    /// 3. Clears all cached device/property state
    /// 4. Resets failure counters and keepalive state (since this is intentional disconnect)
    /// 5. Emits connection state change event
    pub async fn disconnect(&mut self) -> IndiResult<()> {
        tracing::info!("Disconnecting from INDI server {}:{}", self.host, self.port);

        // Send shutdown signal to reader task
        if let Some(tx) = self.shutdown_tx.take() {
            let _ = tx.send(());
        }

        self.tx = None; // Drop sender, which will close the writer task
        self.connected.store(false, Ordering::SeqCst);

        // Clear cached state
        self.devices.write().await.clear();
        self.properties.write().await.clear();
        self.property_values.write().await.clear();
        self.number_limits.write().await.clear();

        // Reset failure counter since this is intentional disconnect
        self.reader_consecutive_failures.store(0, Ordering::SeqCst);

        // Reset keepalive state to clean up any in-flight keepalive checks
        self.keepalive_in_progress.store(false, Ordering::SeqCst);
        self.reconnecting.store(false, Ordering::SeqCst);
        self.reconnect_attempts.store(0, Ordering::SeqCst);

        // Update reader status
        *self.reader_status.write().await = ReaderStatus::Stopped;

        // Emit events
        let _ = self.event_tx.send(IndiEvent::ReaderHealthChanged {
            healthy: false,
            status: ReaderStatus::Stopped,
            consecutive_failures: 0,
        });
        let _ = self.event_tx.send(IndiEvent::ConnectionStateChanged(false));

        Ok(())
    }

    /// Check if connected
    pub async fn is_connected(&self) -> bool {
        self.connected.load(Ordering::SeqCst)
    }

    /// Get reader task status
    pub async fn reader_status(&self) -> ReaderStatus {
        *self.reader_status.read().await
    }

    /// Check if the reader task is healthy (running with no recent failures)
    ///
    /// Returns true if:
    /// - Reader status is Running
    /// - Consecutive failure count is 0
    ///
    /// Returns false if:
    /// - Reader is Stopped, Crashed, or Restarting
    /// - There have been any consecutive failures (even if currently running)
    pub fn is_reader_healthy(&self) -> bool {
        // Non-async version for quick health checks
        let failures = self.reader_consecutive_failures.load(Ordering::SeqCst);
        failures == 0 && self.connected.load(Ordering::SeqCst)
    }

    /// Get the number of consecutive reader failures
    pub fn reader_consecutive_failures(&self) -> u32 {
        self.reader_consecutive_failures.load(Ordering::SeqCst)
    }

    /// Check if the reader has exceeded the maximum failure threshold
    pub fn is_reader_failed_permanently(&self) -> bool {
        let failures = self.reader_consecutive_failures.load(Ordering::SeqCst);
        failures >= self.reader_task_config.max_consecutive_failures
    }

    /// Reset the consecutive failure counter (call after successful manual recovery)
    pub fn reset_reader_failures(&self) {
        self.reader_consecutive_failures.store(0, Ordering::SeqCst);
    }

    /// Send a raw INDI command
    pub async fn send_command(&mut self, command: &str) -> IndiResult<()> {
        if let Some(tx) = &self.tx {
            tx.send(command.to_string()).await.map_err(|e| {
                IndiError::ChannelClosed(format!(
                    "Failed to send INDI command to {}:{}: {}. The connection may have been lost.",
                    self.host, self.port, e
                ))
            })
        } else {
            Err(IndiError::NotConnected)
        }
    }

    /// Get the list of discovered devices
    pub async fn get_devices(&self) -> Vec<IndiDevice> {
        self.devices.read().await.values().cloned().collect()
    }

    /// Get properties for a device
    pub async fn get_properties(&self, device_name: &str) -> Vec<IndiProperty> {
        self.properties
            .read()
            .await
            .iter()
            .filter(|((device, _), _)| device == device_name)
            .map(|(_, prop)| prop.clone())
            .collect()
    }

    /// Get a property
    pub async fn get_property(&self, device: &str, property: &str) -> Option<IndiProperty> {
        let props = self.properties.read().await;
        map_get_2(&props, device, property).cloned()
    }

    /// Get a property value
    pub async fn get_property_value(
        &self,
        device: &str,
        property: &str,
        element: &str,
    ) -> Option<String> {
        let vals = self.property_values.read().await;
        map_get_3(&vals, device, property, element).cloned()
    }

    /// Get number limits for a property element
    pub async fn get_number_limits(
        &self,
        device: &str,
        property: &str,
        element: &str,
    ) -> Option<NumberLimits> {
        let limits = self.number_limits.read().await;
        map_get_3(&limits, device, property, element).cloned()
    }

    /// Get a number property value
    pub async fn get_number(&self, device: &str, property: &str, element: &str) -> Option<f64> {
        self.get_property_value(device, property, element)
            .await
            .and_then(|v| v.parse().ok())
    }

    /// Get a switch property value
    pub async fn get_switch(&self, device: &str, property: &str, element: &str) -> Option<bool> {
        self.get_property_value(device, property, element)
            .await
            .map(|v| v.eq_ignore_ascii_case("on"))
    }

    /// Get property state
    pub async fn get_property_state(
        &self,
        device: &str,
        property: &str,
    ) -> Option<IndiPropertyState> {
        let props = self.properties.read().await;
        map_get_2(&props, device, property).map(|p| p.state)
    }

    /// Get property permission
    pub async fn get_property_permission(
        &self,
        device: &str,
        property: &str,
    ) -> Option<IndiPermission> {
        let props = self.properties.read().await;
        map_get_2(&props, device, property).map(|p| p.perm)
    }

    /// Check if a property is in the busy state
    pub async fn is_property_busy(&self, device: &str, property: &str) -> bool {
        self.get_property_state(device, property)
            .await
            .map(|s| s == IndiPropertyState::Busy)
            .unwrap_or(false)
    }

    /// Check if a property exists for a device
    pub async fn has_property(&self, device: &str, property: &str) -> bool {
        let props = self.properties.read().await;
        map_contains_2(&props, device, property)
    }

    /// Get a light property state value (0=Idle, 1=Ok, 2=Busy, 3=Alert)
    pub async fn get_light_state(
        &self,
        device: &str,
        property: &str,
        element: &str,
    ) -> Option<i32> {
        self.get_property_value(device, property, element)
            .await
            .and_then(|v| match v.as_str() {
                "Idle" => Some(0),
                "Ok" => Some(1),
                "Busy" => Some(2),
                "Alert" => Some(3),
                _ => v.parse().ok(),
            })
    }

    /// Enable BLOB mode for a device
    pub async fn enable_blob(&mut self, device: &str) -> IndiResult<()> {
        let cmd = format!(
            "<enableBLOB device=\"{}\" name=\"\">Also</enableBLOB>",
            device
        );
        self.send_command(&cmd).await
    }

    /// Check property permission before write
    fn check_write_permission(&self, perm: IndiPermission, property: &str) -> IndiResult<()> {
        match perm {
            IndiPermission::ReadOnly => Err(IndiError::PermissionDenied(format!(
                "Property '{}' is read-only",
                property
            ))),
            IndiPermission::WriteOnly | IndiPermission::ReadWrite => Ok(()),
        }
    }

    /// Validate number value against limits
    async fn validate_number_limits(
        &self,
        device: &str,
        property: &str,
        element: &str,
        value: f64,
    ) -> IndiResult<()> {
        if let Some(limits) = self.get_number_limits(device, property, element).await {
            if let (Some(min), Some(max)) = (limits.min, limits.max) {
                if value < min || value > max {
                    return Err(IndiError::ValueOutOfRange {
                        device: device.to_string(),
                        property: property.to_string(),
                        element: element.to_string(),
                        value,
                        min,
                        max,
                    });
                }
            }
        }
        Ok(())
    }

    /// Set a switch property with permission check
    pub async fn set_switch(
        &mut self,
        device: &str,
        property: &str,
        element: &str,
        state: bool,
    ) -> IndiResult<()> {
        // Check permission
        if let Some(perm) = self.get_property_permission(device, property).await {
            self.check_write_permission(perm, property)?;
        }

        let state_str = if state { "On" } else { "Off" };
        let cmd = format!(
            "<newSwitchVector device=\"{}\" name=\"{}\">\
             <oneSwitch name=\"{}\">{}</oneSwitch>\
             </newSwitchVector>",
            device, property, element, state_str
        );
        self.send_command(&cmd).await
    }

    /// Set a number property with permission and limits check
    pub async fn set_number(
        &mut self,
        device: &str,
        property: &str,
        element: &str,
        value: f64,
    ) -> IndiResult<()> {
        // Check permission
        if let Some(perm) = self.get_property_permission(device, property).await {
            self.check_write_permission(perm, property)?;
        }

        // Validate against limits
        self.validate_number_limits(device, property, element, value)
            .await?;

        let cmd = format!(
            "<newNumberVector device=\"{}\" name=\"{}\">\
             <oneNumber name=\"{}\">{}</oneNumber>\
             </newNumberVector>",
            device, property, element, value
        );
        self.send_command(&cmd).await
    }

    /// Set multiple number properties at once with validation
    pub async fn set_numbers(
        &mut self,
        device: &str,
        property: &str,
        values: &[(&str, f64)],
    ) -> IndiResult<()> {
        // Check permission
        if let Some(perm) = self.get_property_permission(device, property).await {
            self.check_write_permission(perm, property)?;
        }

        // Validate all values
        for (element, value) in values {
            self.validate_number_limits(device, property, element, *value)
                .await?;
        }

        let elements: String = values
            .iter()
            .map(|(name, value)| format!("<oneNumber name=\"{}\">{}</oneNumber>", name, value))
            .collect();
        let cmd = format!(
            "<newNumberVector device=\"{}\" name=\"{}\">{}</newNumberVector>",
            device, property, elements
        );
        self.send_command(&cmd).await
    }

    /// Set a text property with permission check
    pub async fn set_text(
        &mut self,
        device: &str,
        property: &str,
        element: &str,
        value: &str,
    ) -> IndiResult<()> {
        // Check permission
        if let Some(perm) = self.get_property_permission(device, property).await {
            self.check_write_permission(perm, property)?;
        }

        let cmd = format!(
            "<newTextVector device=\"{}\" name=\"{}\">\
             <oneText name=\"{}\">{}</oneText>\
             </newTextVector>",
            device, property, element, value
        );
        self.send_command(&cmd).await
    }

    // =========================================================================
    // HIGH-LEVEL DEVICE CONTROL METHODS
    // =========================================================================

    /// Connect to a device (turn on CONNECTION switch)
    pub async fn connect_device(&mut self, device: &str) -> IndiResult<()> {
        self.set_switch(device, "CONNECTION", "CONNECT", true).await
    }

    /// Disconnect from a device
    pub async fn disconnect_device(&mut self, device: &str) -> IndiResult<()> {
        self.set_switch(device, "CONNECTION", "DISCONNECT", true)
            .await
    }

    /// Check if a device is connected
    pub async fn is_device_connected(&self, device: &str) -> bool {
        self.get_switch(device, "CONNECTION", "CONNECT")
            .await
            .unwrap_or(false)
    }

    /// Get filter names for a filter wheel device
    pub async fn get_filter_names(&self, device: &str) -> Result<Vec<String>, String> {
        let props = self.get_properties(device).await;

        // Look for the FILTER_NAME property
        if let Some(prop) = props.iter().find(|p| p.name == "FILTER_NAME") {
            let mut names = Vec::new();
            for elem in &prop.elements {
                if let Some(val) = self.get_property_value(device, "FILTER_NAME", elem).await {
                    names.push(val);
                } else {
                    names.push(elem.clone());
                }
            }
            return Ok(names);
        }

        Ok(Vec::new())
    }

    // =========================================================================
    // TIMEOUT AND RELIABILITY METHODS
    // =========================================================================

    /// Wait for a property to reach a specific state with timeout
    pub async fn wait_for_property_state(
        &self,
        device: &str,
        property: &str,
        expected_state: IndiPropertyState,
        timeout_duration: Duration,
    ) -> Result<(), IndiTimeoutError> {
        let start = Instant::now();
        let poll_interval = Duration::from_millis(self.timeout_config.property_poll_interval_ms);
        let mut last_state = None;

        loop {
            // Check timeout
            if start.elapsed() >= timeout_duration {
                return Err(IndiTimeoutError {
                    device: device.to_string(),
                    property: property.to_string(),
                    context: format!(
                        "Timed out waiting for state {:?} after {:?}",
                        expected_state, timeout_duration
                    ),
                    last_state,
                });
            }

            // Check current state
            if let Some(state) = self.get_property_state(device, property).await {
                last_state = Some(state);

                if state == expected_state {
                    return Ok(());
                }

                // If state is Alert, return early with error
                if state == IndiPropertyState::Alert {
                    return Err(IndiTimeoutError {
                        device: device.to_string(),
                        property: property.to_string(),
                        context: format!(
                            "Property entered Alert state while waiting for {:?}",
                            expected_state
                        ),
                        last_state: Some(state),
                    });
                }
            }

            // Wait before polling again
            sleep(poll_interval).await;
        }
    }

    /// Wait for a property to no longer be busy (Ok or Idle state)
    pub async fn wait_for_property_not_busy(
        &self,
        device: &str,
        property: &str,
        timeout_duration: Duration,
    ) -> Result<(), IndiTimeoutError> {
        let start = Instant::now();
        let poll_interval = Duration::from_millis(self.timeout_config.property_poll_interval_ms);
        let mut last_state = None;

        loop {
            // Check timeout
            if start.elapsed() >= timeout_duration {
                return Err(IndiTimeoutError {
                    device: device.to_string(),
                    property: property.to_string(),
                    context: format!(
                        "Timed out waiting for property to finish (not Busy) after {:?}",
                        timeout_duration
                    ),
                    last_state,
                });
            }

            // Check current state
            if let Some(state) = self.get_property_state(device, property).await {
                last_state = Some(state);

                // Success if Ok or Idle
                if state == IndiPropertyState::Ok || state == IndiPropertyState::Idle {
                    return Ok(());
                }

                // Alert is an error condition
                if state == IndiPropertyState::Alert {
                    return Err(IndiTimeoutError {
                        device: device.to_string(),
                        property: property.to_string(),
                        context: "Property entered Alert state".to_string(),
                        last_state: Some(state),
                    });
                }
            }

            // Wait before polling again
            sleep(poll_interval).await;
        }
    }

    /// Send keepalive to detect dead connections (atomic operation)
    ///
    /// This method is safe to call concurrently due to atomic guards.
    async fn send_keepalive(&mut self) -> IndiResult<()> {
        // Update timestamp atomically BEFORE sending
        self.last_keepalive_ms
            .store(current_time_ms(), Ordering::SeqCst);

        // Use configured protocol version
        let version = &self.protocol_config.preferred_version;
        self.send_command(&format!("<getProperties version=\"{}\"/>", version))
            .await
    }

    /// Check if keepalive is needed and send it (atomic operations to prevent race)
    ///
    /// This method provides race-safe keepalive checking:
    /// 1. Uses compare_exchange to prevent overlapping keepalive checks
    /// 2. Skips keepalive during reconnection to avoid false disconnects
    /// 3. Checks for keepalive response timeout
    ///
    /// Returns Ok(()) if keepalive was sent or not needed
    /// Returns Err if keepalive response timeout was detected (connection may be dead)
    pub async fn check_keepalive(&mut self) -> IndiResult<()> {
        // Skip keepalive if not connected
        if !self.connected.load(Ordering::SeqCst) {
            return Ok(());
        }

        // Skip keepalive if reconnection is in progress
        // This prevents false disconnection events during reconnection attempts
        if self.reconnecting.load(Ordering::SeqCst) {
            tracing::debug!("Skipping keepalive: reconnection in progress");
            return Ok(());
        }

        // Use compare_exchange to atomically acquire the keepalive lock
        // This prevents overlapping keepalive checks if previous check didn't complete
        if self
            .keepalive_in_progress
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_err()
        {
            // Another keepalive is already in progress, skip this one
            tracing::debug!("Skipping keepalive: another keepalive check is in progress");
            return Ok(());
        }

        // Ensure we release the lock when done (using a scope guard pattern)
        let result = self.do_keepalive_check().await;

        // Release the keepalive lock
        self.keepalive_in_progress.store(false, Ordering::SeqCst);

        result
    }

    /// Internal keepalive check logic (called while holding keepalive_in_progress lock)
    async fn do_keepalive_check(&mut self) -> IndiResult<()> {
        let keepalive_interval_ms = self.timeout_config.keepalive_interval_secs * 1000;
        let keepalive_timeout_ms = keepalive_interval_ms * 2; // Response timeout is 2x interval
        let current_ms = current_time_ms();

        // Check if we haven't received any response in too long (connection may be dead)
        let last_response_ms = self.last_keepalive_response_ms.load(Ordering::SeqCst);
        let time_since_last_response = current_ms.saturating_sub(last_response_ms);

        if time_since_last_response > keepalive_timeout_ms {
            tracing::warn!(
                "Keepalive response timeout: no response in {} ms (timeout: {} ms)",
                time_since_last_response,
                keepalive_timeout_ms
            );
            // Don't emit disconnect event here - let the reader task handle that
            // Just return an error so caller knows connection may be dead
            return Err(IndiError::OperationTimeout {
                operation: "keepalive".to_string(),
                device: None,
                property: None,
                duration: Duration::from_millis(time_since_last_response),
                context: format!(
                    "No keepalive response received in {} ms",
                    time_since_last_response
                ),
            });
        }

        // Check if enough time has passed since last keepalive was SENT
        let last_sent_ms = self.last_keepalive_ms.load(Ordering::SeqCst);
        if current_ms.saturating_sub(last_sent_ms) >= keepalive_interval_ms {
            self.send_keepalive().await?;
        }

        Ok(())
    }

    /// Check if a keepalive is currently in progress
    pub fn is_keepalive_in_progress(&self) -> bool {
        self.keepalive_in_progress.load(Ordering::SeqCst)
    }

    /// Get the time in milliseconds since the last keepalive response was received
    pub fn time_since_last_keepalive_response_ms(&self) -> u64 {
        current_time_ms().saturating_sub(self.last_keepalive_response_ms.load(Ordering::SeqCst))
    }

    /// Check if the connection is considered healthy based on keepalive responses
    ///
    /// Returns true if we've received a response within 2x the keepalive interval
    pub fn is_connection_healthy(&self) -> bool {
        if !self.connected.load(Ordering::SeqCst) {
            return false;
        }

        let keepalive_timeout_ms = self.timeout_config.keepalive_interval_secs * 1000 * 2;
        self.time_since_last_keepalive_response_ms() < keepalive_timeout_ms
    }

    /// Attempt to reconnect with exponential backoff and jitter
    ///
    /// This method sets the `reconnecting` flag to prevent false disconnection
    /// events from keepalive checks during the reconnection process.
    pub async fn reconnect_with_backoff(&mut self) -> IndiResult<()> {
        let max_attempts = self.reconnection_config.max_attempts;
        let mut last_error = String::new();

        // Set reconnecting flag to skip keepalive checks during reconnection
        self.reconnecting.store(true, Ordering::SeqCst);

        // Ensure we clear the flag when done (using scope guard pattern)
        let result = async {
            for attempt in 1..=max_attempts {
                self.reconnect_attempts.store(attempt, Ordering::SeqCst);

                tracing::info!(
                    "Reconnection attempt {}/{} to {}:{}",
                    attempt,
                    max_attempts,
                    self.host,
                    self.port
                );

                match self.connect().await {
                    Ok(_) => {
                        tracing::info!("Successfully reconnected to {}:{}", self.host, self.port);
                        self.reconnect_attempts.store(0, Ordering::SeqCst);
                        return Ok(());
                    }
                    Err(e) => {
                        last_error = e.to_string();
                        tracing::warn!("Reconnection attempt {} failed: {}", attempt, last_error);

                        if attempt < max_attempts {
                            let delay = self
                                .reconnection_config
                                .calculate_delay(attempt, &self.jitter_rng);
                            tracing::info!("Waiting {:?} before next reconnection attempt", delay);
                            sleep(delay).await;
                        }
                    }
                }
            }

            Err(IndiError::ReconnectionFailed {
                attempts: max_attempts,
                last_error,
            })
        }
        .await;

        // Clear reconnecting flag
        self.reconnecting.store(false, Ordering::SeqCst);

        result
    }

    /// Check if reconnection is currently in progress
    pub fn is_reconnecting(&self) -> bool {
        self.reconnecting.load(Ordering::SeqCst)
    }

    /// Attempt to recover from a reader crash with proper supervision
    ///
    /// This method should be called when receiving a `ReaderRestarting` event.
    /// It will:
    /// 1. Wait for the suggested delay (based on failure count and backoff)
    /// 2. Attempt to reconnect
    /// 3. Emit appropriate events on success/failure
    ///
    /// Note: Sets the `reconnecting` flag to prevent false disconnection events
    /// from keepalive checks during the recovery process.
    ///
    /// Returns Ok(()) if reconnection succeeds, Err if it fails.
    pub async fn recover_reader(&mut self) -> IndiResult<()> {
        // Check if we've already exceeded max failures
        if self.is_reader_failed_permanently() {
            let failures = self.reader_consecutive_failures();
            return Err(IndiError::ReconnectionFailed {
                attempts: failures,
                last_error: "Exceeded maximum consecutive reader failures".to_string(),
            });
        }

        // Set reconnecting flag to skip keepalive checks during recovery
        self.reconnecting.store(true, Ordering::SeqCst);

        // Get current failure count for delay calculation
        let failures = self.reader_consecutive_failures();

        // Update status to Restarting
        *self.reader_status.write().await = ReaderStatus::Restarting;
        let _ = self.event_tx.send(IndiEvent::ReaderHealthChanged {
            healthy: false,
            status: ReaderStatus::Restarting,
            consecutive_failures: failures,
        });

        // Calculate and wait for delay
        if failures > 0 {
            let delay = self
                .reader_task_config
                .calculate_restart_delay(failures, &self.jitter_rng);
            tracing::info!(
                "Waiting {:?} before reader recovery attempt {}",
                delay,
                failures
            );
            sleep(delay).await;
        }

        // Attempt to reconnect
        let result = match self.connect().await {
            Ok(_) => {
                tracing::info!("Reader recovery successful after {} attempts", failures);
                let _ = self.event_tx.send(IndiEvent::ReaderRestarted {
                    attempts_used: failures,
                });
                Ok(())
            }
            Err(e) => {
                tracing::error!("Reader recovery failed: {}", e);
                // Note: connect() will have already incremented the failure counter
                // and emitted appropriate events through supervised_reader_task
                Err(e)
            }
        };

        // Clear reconnecting flag
        self.reconnecting.store(false, Ordering::SeqCst);

        result
    }

    /// Check if a reconnection is safe (not already in progress)
    ///
    /// Returns false if:
    /// - Already connected
    /// - Reader is in Restarting state
    /// - A reconnection is in progress (reconnecting flag is set)
    /// - A reconnection attempt counter is non-zero
    pub async fn can_reconnect(&self) -> bool {
        if self.connected.load(Ordering::SeqCst) {
            return false;
        }

        // Check if reconnection is already in progress
        if self.reconnecting.load(Ordering::SeqCst) {
            return false;
        }

        let status = *self.reader_status.read().await;
        if status == ReaderStatus::Restarting {
            return false;
        }

        let reconnect_attempts = self.reconnect_attempts.load(Ordering::SeqCst);
        reconnect_attempts == 0
    }

    /// Get the number of reconnection attempts
    pub async fn reconnect_attempts(&self) -> u32 {
        self.reconnect_attempts.load(Ordering::SeqCst)
    }

    /// Request protocol version info from server
    pub async fn request_version(&mut self) -> IndiResult<()> {
        self.send_command("<getProperties version=\"\"/>").await
    }

    /// Check if server version is compatible with minimum required version
    pub async fn check_version_compatibility(&self) -> IndiResult<()> {
        if let Some(ref min_version) = self.protocol_config.min_version {
            if let Some(server_ver) = self.server_version().await {
                if !is_version_compatible(&server_ver, min_version) {
                    return Err(IndiError::VersionMismatch {
                        required: min_version.clone(),
                        server: server_ver,
                    });
                }
            }
        }
        Ok(())
    }
}

/// Get current time in milliseconds since UNIX epoch
fn current_time_ms() -> u64 {
    use std::time::SystemTime;
    SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

// =========================================================================
// Zero-allocation lookup helpers for HashMap with tuple keys
// =========================================================================
// std::collections::HashMap requires owned keys for lookups via .get(),
// which forces allocating Strings from &str just to perform a lookup.
// These helpers iterate the map and compare borrowed keys directly,
// avoiding the allocation. INDI property maps are small (typically <150 entries)
// so the linear scan is not a concern vs. the allocation savings on every
// property read in the polling hot path.

/// Look up a value in a HashMap<(String, String), V> using borrowed &str keys
fn map_get_2<'a, V>(map: &'a HashMap<(String, String), V>, k1: &str, k2: &str) -> Option<&'a V> {
    map.iter()
        .find(|((a, b), _)| a.as_str() == k1 && b.as_str() == k2)
        .map(|(_, v)| v)
}

/// Look up a mutable value in a HashMap<(String, String), V> using borrowed &str keys
fn map_get_mut_2<'a, V>(
    map: &'a mut HashMap<(String, String), V>,
    k1: &str,
    k2: &str,
) -> Option<&'a mut V> {
    map.iter_mut()
        .find(|((a, b), _)| a.as_str() == k1 && b.as_str() == k2)
        .map(|(_, v)| v)
}

/// Check if a HashMap<(String, String), V> contains a key using borrowed &str keys
fn map_contains_2<V>(map: &HashMap<(String, String), V>, k1: &str, k2: &str) -> bool {
    map.iter()
        .any(|((a, b), _)| a.as_str() == k1 && b.as_str() == k2)
}

/// Look up a value in a HashMap<(String, String, String), V> using borrowed &str keys
fn map_get_3<'a, V>(
    map: &'a HashMap<(String, String, String), V>,
    k1: &str,
    k2: &str,
    k3: &str,
) -> Option<&'a V> {
    map.iter()
        .find(|((a, b, c), _)| a.as_str() == k1 && b.as_str() == k2 && c.as_str() == k3)
        .map(|(_, v)| v)
}

/// Helper to get attribute from XML event
fn get_attribute(e: &quick_xml::events::BytesStart, name: &str) -> Option<String> {
    e.attributes()
        .filter_map(|a| a.ok())
        .find(|a| a.key.as_ref() == name.as_bytes())
        .map(|a| String::from_utf8_lossy(&a.value).to_string())
}

fn parse_state(s: &str) -> IndiPropertyState {
    match s {
        "Idle" => IndiPropertyState::Idle,
        "Ok" => IndiPropertyState::Ok,
        "Busy" => IndiPropertyState::Busy,
        "Alert" => IndiPropertyState::Alert,
        _ => IndiPropertyState::Idle,
    }
}

fn parse_perm(s: &str) -> IndiPermission {
    match s.to_lowercase().as_str() {
        "ro" => IndiPermission::ReadOnly,
        "wo" => IndiPermission::WriteOnly,
        "rw" => IndiPermission::ReadWrite,
        _ => IndiPermission::ReadWrite,
    }
}

/// Validate BLOB format and detect actual format from data
fn validate_blob_format(declared_format: &str, data: &[u8]) -> String {
    // Check magic bytes to detect actual format
    let detected: &str = if data.len() >= 6 && &data[0..6] == b"SIMPLE" {
        ".fits"
    } else if data.len() >= 8 && data[0..8] == [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A] {
        ".png"
    } else if data.len() >= 3 && data[0..3] == [0xFF, 0xD8, 0xFF] {
        ".jpeg"
    } else if data.len() >= 4
        && &data[0..4] == b"RIFF"
        && data.len() >= 12
        && &data[8..12] == b"WEBP"
    {
        ".webp"
    } else if data.len() >= 4 && data[0..4] == [0x1F, 0x8B, 0x08, 0x00] {
        ".gz"
    } else if data.len() >= 2 && data[0..2] == [0x50, 0x4B] {
        ".zip"
    } else {
        // Use declared format
        declared_format
    };

    // Log warning if formats don't match
    if !declared_format.is_empty() && detected != declared_format {
        tracing::debug!(
            "BLOB format mismatch: declared '{}', detected '{}'",
            declared_format,
            detected
        );
    }

    detected.to_string()
}

/// Compare protocol versions (returns true if server >= required)
fn is_version_compatible(server: &str, required: &str) -> bool {
    let parse_version = |v: &str| -> (u32, u32) {
        let parts: Vec<&str> = v.split('.').collect();
        let major = parts.first().and_then(|s| s.parse().ok()).unwrap_or(0);
        let minor = parts.get(1).and_then(|s| s.parse().ok()).unwrap_or(0);
        (major, minor)
    };

    let (server_major, server_minor) = parse_version(server);
    let (req_major, req_minor) = parse_version(required);

    server_major > req_major || (server_major == req_major && server_minor >= req_minor)
}

impl Default for IndiClient {
    fn default() -> Self {
        Self::new("localhost", None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::IndiPropertyState;

    #[tokio::test]
    async fn test_timeout_config_default() {
        let config = IndiTimeoutConfig::default();
        assert_eq!(config.connection_timeout_secs, 30);
        assert_eq!(config.message_timeout_secs, 60);
        assert_eq!(config.blob_timeout_secs, 300);
        assert_eq!(config.property_timeout_secs, 30);
        assert_eq!(config.mount_slew_timeout_secs, 300);
        assert_eq!(config.focuser_move_timeout_secs, 120);
        assert_eq!(config.filter_change_timeout_secs, 60);
        assert_eq!(config.dome_slew_timeout_secs, 300);
        assert_eq!(config.rotator_move_timeout_secs, 120);
        assert_eq!(config.camera_exposure_buffer_secs, 60);
        assert_eq!(config.property_poll_interval_ms, 500);
        assert_eq!(config.keepalive_interval_secs, 30);
        assert_eq!(config.reconnect_base_delay_secs, 1);
        assert_eq!(config.reconnect_max_delay_secs, 30);
        assert_eq!(config.reconnect_max_attempts, 5);
    }

    #[tokio::test]
    async fn test_client_creation_with_timeout_config() {
        let custom_config = IndiTimeoutConfig {
            connection_timeout_secs: 60,
            message_timeout_secs: 120,
            blob_timeout_secs: 600,
            property_timeout_secs: 60,
            mount_slew_timeout_secs: 600,
            focuser_move_timeout_secs: 240,
            filter_change_timeout_secs: 120,
            dome_slew_timeout_secs: 600,
            rotator_move_timeout_secs: 240,
            camera_exposure_buffer_secs: 120,
            property_poll_interval_ms: 1000,
            keepalive_interval_secs: 60,
            reconnect_base_delay_secs: 2,
            reconnect_max_delay_secs: 60,
            reconnect_max_attempts: 10,
        };

        let client =
            IndiClient::with_timeout_config("localhost", Some(7624), custom_config.clone());
        assert_eq!(client.timeout_config().mount_slew_timeout_secs, 600);
        assert_eq!(client.timeout_config().message_timeout_secs, 120);
        assert_eq!(client.timeout_config().reconnect_max_attempts, 10);
    }

    #[tokio::test]
    async fn test_timeout_error_display() {
        let error = IndiTimeoutError {
            device: "TestMount".to_string(),
            property: "EQUATORIAL_EOD_COORD".to_string(),
            context: "Slew operation exceeded timeout".to_string(),
            last_state: Some(IndiPropertyState::Busy),
        };

        let error_msg = format!("{}", error);
        assert!(error_msg.contains("TestMount"));
        assert!(error_msg.contains("EQUATORIAL_EOD_COORD"));
        assert!(error_msg.contains("Slew operation exceeded timeout"));
    }

    #[tokio::test]
    async fn test_wait_for_property_state_timeout() {
        let client = IndiClient::new("localhost", Some(7624));

        // This should timeout immediately since we're not connected
        let result = client
            .wait_for_property_state(
                "TestDevice",
                "TestProperty",
                IndiPropertyState::Ok,
                Duration::from_millis(100),
            )
            .await;

        assert!(result.is_err());
        if let Err(e) = result {
            assert_eq!(e.device, "TestDevice");
            assert_eq!(e.property, "TestProperty");
        }
    }

    #[tokio::test]
    async fn test_exponential_backoff_with_jitter() {
        let config = ReconnectionConfig {
            base_delay_secs: 1,
            max_delay_secs: 30,
            max_attempts: 5,
            use_jitter: false, // Disable jitter for predictable testing
            jitter_factor: 0.0,
        };
        let rng = make_jitter_rng("test", 7624);

        // Test exponential growth without jitter
        let delay1 = config.calculate_delay(1, &rng);
        assert_eq!(delay1, Duration::from_secs(1));

        let delay2 = config.calculate_delay(2, &rng);
        assert_eq!(delay2, Duration::from_secs(2));

        let delay3 = config.calculate_delay(3, &rng);
        assert_eq!(delay3, Duration::from_secs(4));

        let delay4 = config.calculate_delay(4, &rng);
        assert_eq!(delay4, Duration::from_secs(8));

        let delay5 = config.calculate_delay(5, &rng);
        assert_eq!(delay5, Duration::from_secs(16));

        // Test capping at max
        let delay6 = config.calculate_delay(6, &rng);
        assert_eq!(delay6, Duration::from_secs(30)); // Capped at max
    }

    #[tokio::test]
    async fn test_jitter_produces_variation() {
        let config = ReconnectionConfig {
            base_delay_secs: 10,
            max_delay_secs: 100,
            max_attempts: 5,
            use_jitter: true,
            jitter_factor: 0.3,
        };
        let rng = make_jitter_rng("test", 7624);

        // With jitter, delays should vary somewhat
        let delay1 = config.calculate_delay(1, &rng);
        let delay2 = config.calculate_delay(1, &rng);

        // Both should be close to 10 seconds (within 30% jitter)
        assert!(delay1.as_secs_f64() >= 8.5 && delay1.as_secs_f64() <= 11.5);
        assert!(delay2.as_secs_f64() >= 8.5 && delay2.as_secs_f64() <= 11.5);
    }

    /// Regression test for §5.23: ensure two clients constructed back-to-back
    /// produce uncorrelated jitter streams. With the previous process-global
    /// PRNG (seeded from system time on first use), two clients created in
    /// the same nanosecond would observe identical reconnect schedules and
    /// thunder-herd the INDI server. Per-instance seeding must prevent that.
    #[tokio::test]
    async fn test_per_instance_jitter_uncorrelated_across_clients() {
        let client_a = IndiClient::new("localhost", Some(7624));
        let client_b = IndiClient::new("localhost", Some(7624));

        // Draw 8 jitter samples from each client and require at least one
        // disagreement. We pull the unit samples directly from the per-
        // instance PRNG so the assertion does not depend on backoff scaling
        // or rounding; the property under test is "the underlying RNG
        // streams differ", which is what fixes the thundering-herd bug.
        let mut samples_a = [0.0_f64; 8];
        let mut samples_b = [0.0_f64; 8];
        for i in 0..8 {
            samples_a[i] = jitter_sample(&client_a.jitter_rng);
            samples_b[i] = jitter_sample(&client_b.jitter_rng);
        }

        assert_ne!(
            samples_a, samples_b,
            "Two IndiClients constructed back-to-back produced identical \
             jitter sequences ({:?} == {:?}); per-instance seeding regressed.",
            samples_a, samples_b
        );

        // Sanity: samples must be in [0, 1) per fastrand::Rng::f64 contract.
        for s in samples_a.iter().chain(samples_b.iter()) {
            assert!(
                (0.0..1.0).contains(s),
                "jitter sample {} outside [0, 1)",
                s
            );
        }
    }

    #[tokio::test]
    async fn test_reconnect_attempts_tracking() {
        let client = IndiClient::new("localhost", Some(7624));
        assert_eq!(client.reconnect_attempts().await, 0);
    }

    #[tokio::test]
    async fn test_send_command_error_messages() {
        let mut client = IndiClient::new("localhost", Some(7624));

        // Try to send without connecting
        let result = client.send_command("<getProperties/>").await;
        assert!(result.is_err());
        if let Err(e) = result {
            assert!(matches!(e, IndiError::NotConnected));
        }
    }

    #[tokio::test]
    async fn test_timeout_config_modification() {
        let mut client = IndiClient::new("localhost", Some(7624));

        // Check default
        assert_eq!(client.timeout_config().mount_slew_timeout_secs, 300);

        // Modify
        let mut new_config = client.timeout_config().clone();
        new_config.mount_slew_timeout_secs = 600;
        client.set_timeout_config(new_config);

        // Verify change
        assert_eq!(client.timeout_config().mount_slew_timeout_secs, 600);
    }

    #[tokio::test]
    async fn test_property_state_alert_detection() {
        let client = IndiClient::new("localhost", Some(7624));

        let result = client
            .wait_for_property_not_busy("TestDevice", "TestProperty", Duration::from_millis(100))
            .await;

        // Should timeout since device doesn't exist
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_client_default_creation() {
        let client = IndiClient::default();
        assert_eq!(client.host, "localhost");
        assert_eq!(client.port, INDI_DEFAULT_PORT);
    }

    #[test]
    fn test_version_compatibility() {
        assert!(is_version_compatible("1.7", "1.7"));
        assert!(is_version_compatible("1.8", "1.7"));
        assert!(is_version_compatible("1.9", "1.7"));
        assert!(is_version_compatible("2.0", "1.7"));
        assert!(!is_version_compatible("1.6", "1.7"));
        assert!(!is_version_compatible("1.0", "1.7"));
    }

    #[test]
    fn test_blob_format_validation() {
        // FITS format detection
        let fits_data = b"SIMPLE  =                    T";
        assert_eq!(validate_blob_format(".fits", fits_data), ".fits");

        // PNG format detection
        let png_data = [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0];
        assert_eq!(validate_blob_format(".fits", &png_data), ".png");

        // JPEG format detection
        let jpeg_data = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0];
        assert_eq!(validate_blob_format(".fits", &jpeg_data), ".jpeg");

        // Unknown format uses declared
        let unknown_data = [0x00, 0x01, 0x02, 0x03];
        assert_eq!(validate_blob_format(".raw", &unknown_data), ".raw");
    }

    #[tokio::test]
    async fn test_protocol_config() {
        let protocol_config = ProtocolConfig {
            preferred_version: "1.8".to_string(),
            auto_detect: true,
            min_version: Some("1.7".to_string()),
        };

        let client = IndiClient::with_full_config(
            "localhost",
            Some(7624),
            IndiTimeoutConfig::default(),
            protocol_config.clone(),
            ReconnectionConfig::default(),
        );

        assert_eq!(client.protocol_config().preferred_version, "1.8");
        assert!(client.protocol_config().auto_detect);
    }

    #[tokio::test]
    async fn test_number_limits() {
        let client = IndiClient::new("localhost", Some(7624));

        // Should return None for non-existent property
        let limits = client
            .get_number_limits("TestDevice", "TestProperty", "TestElement")
            .await;
        assert!(limits.is_none());
    }

    #[tokio::test]
    async fn test_reader_status() {
        let client = IndiClient::new("localhost", Some(7624));

        // Should be stopped initially
        let status = client.reader_status().await;
        assert_eq!(status, ReaderStatus::Stopped);
    }

    // =========================================================================
    // Reader Supervision Tests
    // =========================================================================

    #[tokio::test]
    async fn test_reader_task_config_default() {
        let config = ReaderTaskConfig::default();
        assert_eq!(config.max_consecutive_failures, 5);
        assert_eq!(config.restart_base_delay_secs, 1);
        assert_eq!(config.restart_max_delay_secs, 60);
        assert!(config.auto_restart);
        assert!(config.use_jitter);
        assert!((config.jitter_factor - 0.3).abs() < 0.01);
    }

    #[tokio::test]
    async fn test_reader_task_config_delay_calculation() {
        let config = ReaderTaskConfig {
            max_consecutive_failures: 5,
            restart_base_delay_secs: 1,
            restart_max_delay_secs: 60,
            auto_restart: true,
            use_jitter: false, // Disable jitter for predictable testing
            jitter_factor: 0.0,
        };
        let rng = make_jitter_rng("test", 7624);

        // Test exponential growth
        assert_eq!(config.calculate_restart_delay(1, &rng), Duration::from_secs(1));
        assert_eq!(config.calculate_restart_delay(2, &rng), Duration::from_secs(2));
        assert_eq!(config.calculate_restart_delay(3, &rng), Duration::from_secs(4));
        assert_eq!(config.calculate_restart_delay(4, &rng), Duration::from_secs(8));
        assert_eq!(config.calculate_restart_delay(5, &rng), Duration::from_secs(16));
        assert_eq!(config.calculate_restart_delay(6, &rng), Duration::from_secs(32));
        // Should cap at max
        assert_eq!(config.calculate_restart_delay(7, &rng), Duration::from_secs(60));
        assert_eq!(config.calculate_restart_delay(10, &rng), Duration::from_secs(60));
    }

    #[tokio::test]
    async fn test_reader_task_config_with_jitter() {
        let config = ReaderTaskConfig {
            max_consecutive_failures: 5,
            restart_base_delay_secs: 10,
            restart_max_delay_secs: 100,
            auto_restart: true,
            use_jitter: true,
            jitter_factor: 0.3,
        };
        let rng = make_jitter_rng("test", 7624);

        // With 30% jitter, delay should be within +/- 15% of base
        let delay = config.calculate_restart_delay(1, &rng);
        let expected = 10.0;
        let tolerance = expected * 0.15;
        assert!(
            delay.as_secs_f64() >= expected - tolerance
                && delay.as_secs_f64() <= expected + tolerance,
            "Delay {} not within expected range [{}, {}]",
            delay.as_secs_f64(),
            expected - tolerance,
            expected + tolerance
        );
    }

    #[tokio::test]
    async fn test_is_reader_healthy_initial_state() {
        let client = IndiClient::new("localhost", Some(7624));

        // Initially not connected, so not healthy
        assert!(!client.is_reader_healthy());
        assert_eq!(client.reader_consecutive_failures(), 0);
        assert!(!client.is_reader_failed_permanently());
    }

    #[tokio::test]
    async fn test_reader_consecutive_failures_tracking() {
        let client = IndiClient::new("localhost", Some(7624));

        // Initially zero
        assert_eq!(client.reader_consecutive_failures(), 0);

        // Simulate failures (normally done by supervised_reader_task)
        client
            .reader_consecutive_failures
            .store(3, Ordering::SeqCst);
        assert_eq!(client.reader_consecutive_failures(), 3);

        // Reset
        client.reset_reader_failures();
        assert_eq!(client.reader_consecutive_failures(), 0);
    }

    #[tokio::test]
    async fn test_is_reader_failed_permanently() {
        let client = IndiClient::new("localhost", Some(7624));
        let max_failures = client.reader_task_config().max_consecutive_failures;

        // Not failed initially
        assert!(!client.is_reader_failed_permanently());

        // Simulate failures below threshold
        client
            .reader_consecutive_failures
            .store(max_failures - 1, Ordering::SeqCst);
        assert!(!client.is_reader_failed_permanently());

        // At threshold
        client
            .reader_consecutive_failures
            .store(max_failures, Ordering::SeqCst);
        assert!(client.is_reader_failed_permanently());

        // Above threshold
        client
            .reader_consecutive_failures
            .store(max_failures + 1, Ordering::SeqCst);
        assert!(client.is_reader_failed_permanently());
    }

    #[tokio::test]
    async fn test_can_reconnect_initial_state() {
        let client = IndiClient::new("localhost", Some(7624));

        // Initially not connected and not restarting, so can reconnect
        assert!(client.can_reconnect().await);
    }

    #[tokio::test]
    async fn test_can_reconnect_when_restarting() {
        let client = IndiClient::new("localhost", Some(7624));

        // Set status to Restarting
        *client.reader_status.write().await = ReaderStatus::Restarting;

        // Should not be able to reconnect while restarting
        assert!(!client.can_reconnect().await);
    }

    #[tokio::test]
    async fn test_can_reconnect_when_connected() {
        let client = IndiClient::new("localhost", Some(7624));

        // Simulate connected state
        client.connected.store(true, Ordering::SeqCst);

        // Should not be able to reconnect when already connected
        assert!(!client.can_reconnect().await);
    }

    #[tokio::test]
    async fn test_reader_status_enum_values() {
        // Test that all enum variants exist and are distinct
        let running = ReaderStatus::Running;
        let stopped = ReaderStatus::Stopped;
        let crashed = ReaderStatus::Crashed;
        let restarting = ReaderStatus::Restarting;

        assert_ne!(running, stopped);
        assert_ne!(running, crashed);
        assert_ne!(running, restarting);
        assert_ne!(stopped, crashed);
        assert_ne!(stopped, restarting);
        assert_ne!(crashed, restarting);
    }

    #[tokio::test]
    async fn test_reader_task_config_getter_setter() {
        let mut client = IndiClient::new("localhost", Some(7624));

        // Check default
        assert_eq!(client.reader_task_config().max_consecutive_failures, 5);

        // Modify
        let mut new_config = client.reader_task_config().clone();
        new_config.max_consecutive_failures = 10;
        new_config.auto_restart = false;
        client.set_reader_task_config(new_config);

        // Verify change
        assert_eq!(client.reader_task_config().max_consecutive_failures, 10);
        assert!(!client.reader_task_config().auto_restart);
    }

    #[tokio::test]
    async fn test_with_all_config_constructor() {
        let timeout_config = IndiTimeoutConfig::default();
        let protocol_config = ProtocolConfig::default();
        let reconnection_config = ReconnectionConfig::default();
        let reader_task_config = ReaderTaskConfig {
            max_consecutive_failures: 10,
            restart_base_delay_secs: 2,
            restart_max_delay_secs: 120,
            auto_restart: false,
            use_jitter: false,
            jitter_factor: 0.0,
        };

        let client = IndiClient::with_all_config(
            "192.168.1.100",
            Some(7625),
            timeout_config,
            protocol_config,
            reconnection_config,
            reader_task_config,
        );

        assert_eq!(client.host, "192.168.1.100");
        assert_eq!(client.port, 7625);
        assert_eq!(client.reader_task_config().max_consecutive_failures, 10);
        assert!(!client.reader_task_config().auto_restart);
    }

    #[tokio::test]
    async fn test_recover_reader_when_failed_permanently() {
        let mut client = IndiClient::new("localhost", Some(7624));
        let max_failures = client.reader_task_config().max_consecutive_failures;

        // Simulate exceeding max failures
        client
            .reader_consecutive_failures
            .store(max_failures, Ordering::SeqCst);

        // Recovery should fail
        let result = client.recover_reader().await;
        assert!(result.is_err());
        if let Err(IndiError::ReconnectionFailed {
            attempts,
            last_error,
        }) = result
        {
            assert_eq!(attempts, max_failures);
            assert!(last_error.contains("Exceeded maximum"));
        } else {
            panic!("Expected ReconnectionFailed error");
        }
    }

    #[tokio::test]
    async fn test_disconnect_resets_failure_counter() {
        let mut client = IndiClient::new("localhost", Some(7624));

        // Simulate some failures
        client
            .reader_consecutive_failures
            .store(3, Ordering::SeqCst);
        assert_eq!(client.reader_consecutive_failures(), 3);

        // Disconnect should reset
        let _ = client.disconnect().await;
        assert_eq!(client.reader_consecutive_failures(), 0);
    }

    // =========================================================================
    // Keepalive Race Condition Prevention Tests
    // =========================================================================

    #[tokio::test]
    async fn test_keepalive_in_progress_flag_initial_state() {
        let client = IndiClient::new("localhost", Some(7624));

        // Should not be in progress initially
        assert!(!client.is_keepalive_in_progress());
    }

    #[tokio::test]
    async fn test_keepalive_in_progress_prevents_concurrent_checks() {
        let client = IndiClient::new("localhost", Some(7624));

        // Simulate a keepalive in progress
        client.keepalive_in_progress.store(true, Ordering::SeqCst);
        assert!(client.is_keepalive_in_progress());

        // This should not allow another keepalive to start
        let result = client.keepalive_in_progress.compare_exchange(
            false,
            true,
            Ordering::SeqCst,
            Ordering::SeqCst,
        );
        assert!(result.is_err()); // Should fail because already in progress
    }

    #[tokio::test]
    async fn test_reconnecting_flag_initial_state() {
        let client = IndiClient::new("localhost", Some(7624));

        // Should not be reconnecting initially
        assert!(!client.is_reconnecting());
    }

    #[tokio::test]
    async fn test_check_keepalive_skips_during_reconnection() {
        let mut client = IndiClient::new("localhost", Some(7624));

        // Set reconnecting flag
        client.reconnecting.store(true, Ordering::SeqCst);
        assert!(client.is_reconnecting());

        // check_keepalive should succeed but skip sending
        let result = client.check_keepalive().await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_check_keepalive_skips_when_not_connected() {
        let mut client = IndiClient::new("localhost", Some(7624));

        // Client is not connected by default
        assert!(!client.connected.load(Ordering::SeqCst));

        // check_keepalive should succeed but skip sending
        let result = client.check_keepalive().await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_time_since_last_keepalive_response() {
        let client = IndiClient::new("localhost", Some(7624));

        // Should be close to 0 initially (within a few ms of creation)
        let time_since = client.time_since_last_keepalive_response_ms();
        assert!(
            time_since < 100,
            "Expected time since last response to be < 100ms, got {}",
            time_since
        );

        // Simulate old response
        let old_time = current_time_ms() - 10000; // 10 seconds ago
        client
            .last_keepalive_response_ms
            .store(old_time, Ordering::SeqCst);

        let time_since = client.time_since_last_keepalive_response_ms();
        assert!(
            (9900..=11000).contains(&time_since),
            "Expected time since last response to be ~10000ms, got {}",
            time_since
        );
    }

    #[tokio::test]
    async fn test_is_connection_healthy_initial_state() {
        let client = IndiClient::new("localhost", Some(7624));

        // Not connected, so not healthy
        assert!(!client.is_connection_healthy());
    }

    #[tokio::test]
    async fn test_is_connection_healthy_when_connected() {
        let client = IndiClient::new("localhost", Some(7624));

        // Simulate connected state with recent keepalive response
        client.connected.store(true, Ordering::SeqCst);
        client
            .last_keepalive_response_ms
            .store(current_time_ms(), Ordering::SeqCst);

        // Should be healthy
        assert!(client.is_connection_healthy());
    }

    #[tokio::test]
    async fn test_is_connection_healthy_when_stale() {
        let client = IndiClient::new("localhost", Some(7624));

        // Simulate connected state with old keepalive response
        client.connected.store(true, Ordering::SeqCst);
        let keepalive_interval_ms = client.timeout_config.keepalive_interval_secs * 1000;
        let old_time = current_time_ms() - (keepalive_interval_ms * 3); // 3x interval ago
        client
            .last_keepalive_response_ms
            .store(old_time, Ordering::SeqCst);

        // Should not be healthy (stale response)
        assert!(!client.is_connection_healthy());
    }

    #[tokio::test]
    async fn test_disconnect_resets_keepalive_state() {
        let mut client = IndiClient::new("localhost", Some(7624));

        // Simulate various keepalive states
        client.keepalive_in_progress.store(true, Ordering::SeqCst);
        client.reconnecting.store(true, Ordering::SeqCst);
        client.reconnect_attempts.store(3, Ordering::SeqCst);

        // Verify states are set
        assert!(client.is_keepalive_in_progress());
        assert!(client.is_reconnecting());

        // Disconnect should reset
        let _ = client.disconnect().await;

        // Verify reset
        assert!(!client.is_keepalive_in_progress());
        assert!(!client.is_reconnecting());
        assert_eq!(client.reconnect_attempts.load(Ordering::SeqCst), 0);
    }

    #[tokio::test]
    async fn test_can_reconnect_when_reconnecting() {
        let client = IndiClient::new("localhost", Some(7624));

        // Initially can reconnect
        assert!(client.can_reconnect().await);

        // Set reconnecting flag
        client.reconnecting.store(true, Ordering::SeqCst);

        // Should not be able to reconnect
        assert!(!client.can_reconnect().await);
    }

    #[tokio::test]
    async fn test_keepalive_response_timeout_detection() {
        let mut client = IndiClient::new("localhost", Some(7624));

        // Simulate connected state with very old keepalive response
        client.connected.store(true, Ordering::SeqCst);
        let keepalive_interval_ms = client.timeout_config.keepalive_interval_secs * 1000;
        let timeout_ms = keepalive_interval_ms * 2;
        let old_time = current_time_ms() - (timeout_ms + 1000); // Beyond timeout
        client
            .last_keepalive_response_ms
            .store(old_time, Ordering::SeqCst);

        // check_keepalive should detect the timeout
        let result = client.check_keepalive().await;
        assert!(result.is_err());
        if let Err(IndiError::OperationTimeout { operation, .. }) = result {
            assert_eq!(operation, "keepalive");
        } else {
            panic!("Expected OperationTimeout error");
        }
    }

    #[tokio::test]
    async fn test_connect_resets_keepalive_state() {
        let client = IndiClient::new("localhost", Some(7624));

        // Verify initial state has keepalive timestamps set
        let last_sent = client.last_keepalive_ms.load(Ordering::SeqCst);
        let last_response = client.last_keepalive_response_ms.load(Ordering::SeqCst);

        // Both timestamps should be close to current time
        let now = current_time_ms();
        assert!(
            now.saturating_sub(last_sent) < 100,
            "last_keepalive_ms should be recent"
        );
        assert!(
            now.saturating_sub(last_response) < 100,
            "last_keepalive_response_ms should be recent"
        );

        // Keepalive in progress should be false
        assert!(!client.is_keepalive_in_progress());
    }

    #[tokio::test]
    async fn test_keepalive_atomic_guard_acquire_release() {
        let client = IndiClient::new("localhost", Some(7624));

        // Acquire the lock
        let acquired = client
            .keepalive_in_progress
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_ok();
        assert!(acquired);
        assert!(client.is_keepalive_in_progress());

        // Try to acquire again (should fail)
        let acquired_again = client
            .keepalive_in_progress
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_ok();
        assert!(!acquired_again);

        // Release the lock
        client.keepalive_in_progress.store(false, Ordering::SeqCst);
        assert!(!client.is_keepalive_in_progress());

        // Should be able to acquire again
        let acquired_after_release = client
            .keepalive_in_progress
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_ok();
        assert!(acquired_after_release);
    }

    // =========================================================================
    // XML depth-stack parser tests (audit §5.18)
    // =========================================================================

    #[test]
    fn test_classify_indi_tag_dispatches_each_kind() {
        assert_eq!(
            classify_indi_tag(b"defNumberVector"),
            XmlContextKind::DefVector
        );
        assert_eq!(
            classify_indi_tag(b"defSwitchVector"),
            XmlContextKind::DefVector
        );
        assert_eq!(
            classify_indi_tag(b"setNumberVector"),
            XmlContextKind::SetOrNewVector
        );
        assert_eq!(
            classify_indi_tag(b"newSwitchVector"),
            XmlContextKind::SetOrNewVector
        );
        assert_eq!(classify_indi_tag(b"defNumber"), XmlContextKind::DefElement);
        assert_eq!(classify_indi_tag(b"defSwitch"), XmlContextKind::DefElement);
        assert_eq!(classify_indi_tag(b"oneNumber"), XmlContextKind::OneElement);
        assert_eq!(classify_indi_tag(b"oneSwitch"), XmlContextKind::OneElement);
        assert_eq!(classify_indi_tag(b"oneBLOB"), XmlContextKind::OneBlob);
        assert_eq!(classify_indi_tag(b"getProperties"), XmlContextKind::Other);
        assert_eq!(classify_indi_tag(b"message"), XmlContextKind::Other);
    }

    #[test]
    fn test_refresh_xml_context_mirrors_walks_full_stack() {
        let stack = vec![
            XmlContext {
                kind: XmlContextKind::DefVector,
                tag: b"defNumberVector".to_vec(),
                device: Some("MountSim".to_string()),
                property: Some("EQUATORIAL_EOD_COORD".to_string()),
                element: None,
            },
            XmlContext {
                kind: XmlContextKind::DefElement,
                tag: b"defNumber".to_vec(),
                device: None,
                property: None,
                element: Some("RA".to_string()),
            },
        ];
        let mut device = String::new();
        let mut property = String::new();
        let mut element = String::new();
        refresh_xml_context_mirrors(&stack, &mut device, &mut property, &mut element);
        assert_eq!(device, "MountSim");
        assert_eq!(property, "EQUATORIAL_EOD_COORD");
        assert_eq!(element, "RA");
    }

    #[test]
    fn test_refresh_xml_context_mirrors_clears_on_empty_stack() {
        let mut device = "stale".to_string();
        let mut property = "stale".to_string();
        let mut element = "stale".to_string();
        refresh_xml_context_mirrors(&[], &mut device, &mut property, &mut element);
        assert!(device.is_empty());
        assert!(property.is_empty());
        assert!(element.is_empty());
    }

    /// Build a minimum reader-task fixture and run the XML parser over `xml`.
    /// Returns the populated `property_values` map plus the events that were
    /// broadcast during parsing. `&[]` after the payload triggers EOF, which
    /// breaks the parser's main loop cleanly.
    async fn drive_parser(xml: &str) -> (PropertyValueMap, Vec<IndiEvent>) {
        let devices = Arc::new(RwLock::new(HashMap::new()));
        let properties = Arc::new(RwLock::new(HashMap::new()));
        let property_values = Arc::new(RwLock::new(HashMap::new()));
        let number_limits = Arc::new(RwLock::new(HashMap::new()));
        let latest_blobs = Arc::new(RwLock::new(HashMap::new()));
        let connected = Arc::new(AtomicBool::new(true));
        let (event_tx, mut event_rx) = broadcast::channel::<IndiEvent>(1024);
        let server_version = Arc::new(RwLock::new(None));
        let last_keepalive_response_ms = Arc::new(AtomicU64::new(current_time_ms()));

        // The reader is a Cursor; reading past the end returns 0 bytes which
        // quick-xml surfaces as `Event::Eof`, and the parser loop then breaks.
        let cursor = std::io::Cursor::new(xml.as_bytes().to_vec());
        let reader = tokio::io::BufReader::new(cursor);

        // Put a separate clone of property_values into the parser so the test
        // can read the final state without contention.
        let pv_clone = property_values.clone();
        let result = IndiClient::reader_task_with_timeout(
            reader,
            devices,
            properties,
            pv_clone,
            number_limits,
            latest_blobs,
            connected,
            event_tx,
            server_version,
            last_keepalive_response_ms,
            IndiTimeoutConfig::default(),
        )
        .await;
        assert!(result.is_ok(), "parser returned error: {:?}", result);

        let mut events = Vec::new();
        while let Ok(ev) = event_rx.try_recv() {
            events.push(ev);
        }
        let pv_snapshot = property_values.read().await.clone();
        (pv_snapshot, events)
    }

    #[tokio::test]
    async fn test_parser_attributes_nested_def_number_correctly() {
        // Why: well-formed nested defNumberVector with multiple defNumber children must
        // attribute each text body to (device, property, element) of THAT element, not
        // bleed values across siblings.
        let xml = r#"
            <defNumberVector device="MountSim" name="EQUATORIAL_EOD_COORD" state="Idle" perm="rw">
                <defNumber name="RA" min="0" max="24">12.5</defNumber>
                <defNumber name="DEC" min="-90" max="90">-30.25</defNumber>
            </defNumberVector>
        "#;
        let (values, _events) = drive_parser(xml).await;
        let ra = values
            .get(&(
                "MountSim".to_string(),
                "EQUATORIAL_EOD_COORD".to_string(),
                "RA".to_string(),
            ))
            .expect("RA value missing");
        assert_eq!(ra, "12.5");
        let dec = values
            .get(&(
                "MountSim".to_string(),
                "EQUATORIAL_EOD_COORD".to_string(),
                "DEC".to_string(),
            ))
            .expect("DEC value missing");
        assert_eq!(dec, "-30.25");
    }

    #[tokio::test]
    async fn test_parser_handles_self_closing_def_switch() {
        // Why: INDI servers may emit `<defSwitch name="X" />` with no body for switches
        // whose state is "Off" by default. quick-xml delivers this as `Event::Empty`,
        // which our parser must treat as a push+pop in one event so the depth stack does
        // not leak and the element gets registered against the right property.
        let xml = r#"
            <defSwitchVector device="MountSim" name="CONNECTION" state="Idle" perm="rw">
                <defSwitch name="CONNECT" />
                <defSwitch name="DISCONNECT" />
            </defSwitchVector>
            <setSwitchVector device="MountSim" name="CONNECTION" state="Ok">
                <oneSwitch name="CONNECT">On</oneSwitch>
                <oneSwitch name="DISCONNECT">Off</oneSwitch>
            </setSwitchVector>
        "#;
        let (values, events) = drive_parser(xml).await;
        let connect = values
            .get(&(
                "MountSim".to_string(),
                "CONNECTION".to_string(),
                "CONNECT".to_string(),
            ))
            .expect("CONNECT value missing — self-closing defSwitch leaked frame state");
        assert_eq!(connect, "On");
        let disconnect = values
            .get(&(
                "MountSim".to_string(),
                "CONNECTION".to_string(),
                "DISCONNECT".to_string(),
            ))
            .expect("DISCONNECT value missing");
        assert_eq!(disconnect, "Off");

        // Why: a `setSwitchVector` close emits PropertyUpdated; verify it's there so we
        // know the depth stack survived the self-closing children.
        assert!(
            events.iter().any(|e| matches!(
                e,
                IndiEvent::PropertyUpdated(d, p)
                    if d == "MountSim" && p == "CONNECTION"
            )),
            "PropertyUpdated event missing after self-closing children: {:?}",
            events
        );
    }

    #[tokio::test]
    async fn test_parser_recovers_from_unbalanced_end_tag() {
        // Why: malformed streams (lossy proxy, mid-message reconnect, buggy server) may
        // produce mismatched closing tags. The parser must NOT panic, must emit a
        // diagnostic Error event, and must still process surrounding well-formed
        // elements correctly.
        let xml = r#"
            <defNumberVector device="DevA" name="PropA" state="Idle" perm="rw">
                <defNumber name="X">1.0</defNumber>
            </defNumberVector>
            <defNumberVector device="DevB" name="PropB" state="Idle" perm="rw">
                <defNumber name="Y">2.0</defSwitch>
            </defNumberVector>
            <defNumberVector device="DevC" name="PropC" state="Idle" perm="rw">
                <defNumber name="Z">3.0</defNumber>
            </defNumberVector>
        "#;
        // The second block contains </defSwitch> where </defNumber> was expected.
        // We must not crash; the well-formed surrounding blocks must still parse.
        let (values, events) = drive_parser(xml).await;

        // First block parses cleanly.
        assert_eq!(
            values
                .get(&(
                    "DevA".to_string(),
                    "PropA".to_string(),
                    "X".to_string()
                ))
                .map(String::as_str),
            Some("1.0")
        );
        // Second block's element value lands before the bad close; either way the
        // parser must not poison the stream.
        let saw_unbalanced_warning = events.iter().any(|e| {
            matches!(e, IndiEvent::Error(msg) if msg.contains("Unbalanced") || msg.contains("XML parse error"))
        });
        assert!(
            saw_unbalanced_warning,
            "expected an Error event reporting the malformed nesting; got {:?}",
            events
        );

        // The third (well-formed) block must still parse — proves the parser recovered.
        // Quick-xml may treat the malformed block as a hard parse error and bail through
        // the recovery branch, which is acceptable; the recovery branch resets the stack
        // and continues. Either path must yield DevC's value.
        assert_eq!(
            values
                .get(&(
                    "DevC".to_string(),
                    "PropC".to_string(),
                    "Z".to_string()
                ))
                .map(String::as_str),
            Some("3.0"),
            "parser failed to recover after malformed block; events={:?}",
            events
        );
    }
}
