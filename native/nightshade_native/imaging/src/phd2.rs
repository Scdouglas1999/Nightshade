//! Real PHD2 Guiding Integration
//!
//! Implements the PHD2 server protocol for communication with PHD2.
//! PHD2 uses a JSON-RPC style protocol over TCP on port 4400.
//!
//! Reference: https://github.com/OpenPHDGuiding/phd2/wiki/EventMonitoring

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::thread;
use std::time::Duration;

/// PHD2 connection state
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Phd2State {
    /// Not connected to PHD2
    Disconnected,
    /// Connected but not guiding
    Connected,
    /// Calibrating
    Calibrating,
    /// Guiding
    Guiding,
    /// Looping (exposures without guiding)
    Looping,
    /// Paused
    Paused,
    /// Settling after dither
    Settling,
    /// Lost lock on guide star
    LostLock,
    /// PHD2 reported a state name we do not recognise. Preserves the raw
    /// string so callers can log or surface it instead of being lied to with
    /// a synthesised `Connected`.
    ///
    /// Why: PHD2 has historically added states (e.g. `GuidingPaused`,
    /// `StarFound`); silently mapping the unknown to `Connected` masked real
    /// guiding regressions until a session-end review.
    Unknown(String),
}

/// PHD2 guide statistics
#[derive(Debug, Clone, Default)]
pub struct GuideStats {
    /// RMS error in RA (arcseconds)
    pub rms_ra: f64,
    /// RMS error in Dec (arcseconds)
    pub rms_dec: f64,
    /// Total RMS error (arcseconds)
    pub rms_total: f64,
    /// Peak RA error (arcseconds)
    pub peak_ra: f64,
    /// Peak Dec error (arcseconds)
    pub peak_dec: f64,
    /// Number of guide frames
    pub frame_count: u32,
    /// SNR of guide star
    pub snr: f64,
    /// Guide star mass (brightness)
    pub star_mass: f64,
}

/// Star image data from PHD2
#[derive(Debug, Clone)]
pub struct StarImageData {
    /// Frame number
    pub frame: u32,
    /// Image width in pixels
    pub width: u32,
    /// Image height in pixels
    pub height: u32,
    /// Star centroid X position within the subframe
    pub star_x: f64,
    /// Star centroid Y position within the subframe
    pub star_y: f64,
    /// Raw pixel data (16-bit grayscale, row-major)
    pub pixels: Vec<u8>,
}

/// PHD2 Brain algorithm parameter
#[derive(Debug, Clone)]
pub struct AlgoParam {
    /// Parameter name
    pub name: String,
    /// Parameter value
    pub value: f64,
}

/// Rolling statistics calculator for guide frames
/// Uses Welford's online algorithm for numerically stable variance calculation
#[derive(Debug, Clone)]
pub struct RollingGuideStats {
    /// Maximum number of samples to keep
    max_samples: usize,
    /// Recent RA errors
    ra_samples: Vec<f64>,
    /// Recent Dec errors
    dec_samples: Vec<f64>,
    /// Recent SNR values
    snr_samples: Vec<f64>,
    /// Running count of all frames
    total_frame_count: u32,
    /// Peak RA error seen
    peak_ra: f64,
    /// Peak Dec error seen
    peak_dec: f64,
    /// Last calculated stats
    cached_stats: GuideStats,
    /// Whether cache is valid
    cache_valid: bool,
}

impl Default for RollingGuideStats {
    fn default() -> Self {
        Self::new(100) // Default to 100 sample window
    }
}

impl RollingGuideStats {
    /// Create a new rolling stats calculator with specified window size
    pub fn new(max_samples: usize) -> Self {
        Self {
            max_samples,
            ra_samples: Vec::with_capacity(max_samples),
            dec_samples: Vec::with_capacity(max_samples),
            snr_samples: Vec::with_capacity(max_samples),
            total_frame_count: 0,
            peak_ra: 0.0,
            peak_dec: 0.0,
            cached_stats: GuideStats::default(),
            cache_valid: false,
        }
    }

    /// Add a new guide frame to the rolling statistics
    pub fn add_frame(&mut self, frame: &GuideFrame) {
        self.total_frame_count += 1;
        self.cache_valid = false;

        // Add samples, removing oldest if at capacity
        if self.ra_samples.len() >= self.max_samples {
            self.ra_samples.remove(0);
            self.dec_samples.remove(0);
            self.snr_samples.remove(0);
        }

        self.ra_samples.push(frame.ra_distance);
        self.dec_samples.push(frame.dec_distance);
        self.snr_samples.push(frame.snr);

        // Track peak errors
        let ra_abs = frame.ra_distance.abs();
        let dec_abs = frame.dec_distance.abs();
        if ra_abs > self.peak_ra {
            self.peak_ra = ra_abs;
        }
        if dec_abs > self.peak_dec {
            self.peak_dec = dec_abs;
        }
    }

    /// Calculate current statistics
    pub fn get_stats(&mut self) -> GuideStats {
        if self.cache_valid {
            return self.cached_stats.clone();
        }

        let n = self.ra_samples.len();
        if n == 0 {
            return GuideStats::default();
        }

        // Calculate RMS for RA
        let ra_sum_sq: f64 = self.ra_samples.iter().map(|x| x * x).sum();
        let rms_ra = (ra_sum_sq / n as f64).sqrt();

        // Calculate RMS for Dec
        let dec_sum_sq: f64 = self.dec_samples.iter().map(|x| x * x).sum();
        let rms_dec = (dec_sum_sq / n as f64).sqrt();

        // Total RMS (pythagorean)
        let rms_total = (rms_ra * rms_ra + rms_dec * rms_dec).sqrt();

        // Average SNR
        let snr = self.snr_samples.iter().sum::<f64>() / n as f64;

        self.cached_stats = GuideStats {
            rms_ra,
            rms_dec,
            rms_total,
            peak_ra: self.peak_ra,
            peak_dec: self.peak_dec,
            frame_count: self.total_frame_count,
            snr,
            star_mass: 0.0, // Not tracked in guide frames
        };
        self.cache_valid = true;

        self.cached_stats.clone()
    }

    /// Reset all statistics
    pub fn reset(&mut self) {
        self.ra_samples.clear();
        self.dec_samples.clear();
        self.snr_samples.clear();
        self.total_frame_count = 0;
        self.peak_ra = 0.0;
        self.peak_dec = 0.0;
        self.cache_valid = false;
    }

    /// Get the number of samples in the rolling window
    pub fn sample_count(&self) -> usize {
        self.ra_samples.len()
    }
}

/// Connection configuration for auto-reconnect
#[derive(Debug, Clone)]
pub struct Phd2ConnectionConfig {
    /// Maximum number of reconnection attempts
    pub max_reconnect_attempts: u32,
    /// Initial delay between reconnection attempts (ms)
    pub initial_reconnect_delay_ms: u64,
    /// Maximum delay between reconnection attempts (ms)
    pub max_reconnect_delay_ms: u64,
    /// Whether to auto-reconnect on disconnect
    pub auto_reconnect: bool,
}

impl Default for Phd2ConnectionConfig {
    fn default() -> Self {
        Self {
            max_reconnect_attempts: 5,
            initial_reconnect_delay_ms: 1000,
            max_reconnect_delay_ms: 30000,
            auto_reconnect: true,
        }
    }
}

/// PHD2 guide frame data
#[derive(Debug, Clone)]
pub struct GuideFrame {
    /// Frame number
    pub frame: u32,
    /// Timestamp
    pub timestamp: f64,
    /// RA offset in arcseconds
    pub ra_distance: f64,
    /// Dec offset in arcseconds
    pub dec_distance: f64,
    /// RA guide pulse duration (ms)
    pub ra_duration: i32,
    /// Dec guide pulse duration (ms)
    pub dec_duration: i32,
    /// RA guide direction ("East" or "West")
    pub ra_direction: String,
    /// Dec guide direction ("North" or "South")
    pub dec_direction: String,
    /// Guide star SNR
    pub snr: f64,
    /// Guide star mass (brightness)
    pub star_mass: f64,
    /// Star position X
    pub star_x: f64,
    /// Star position Y
    pub star_y: f64,
    /// Average distance (RMS)
    pub avg_dist: f64,
}

/// Events from PHD2
#[derive(Debug, Clone)]
pub enum Phd2Event {
    /// State changed
    StateChanged(Phd2State),
    /// New guide frame
    GuideStep(GuideFrame),
    /// Settling started
    SettleBegin,
    /// Settling complete
    SettleDone {
        total_frames: u32,
        dropped_frames: u32,
    },
    /// Star lost
    StarLost,
    /// Star selected
    StarSelected { x: f64, y: f64 },
    /// Calibration complete
    CalibrationComplete,
    /// Alert from PHD2
    Alert { message: String, alert_type: String },
    /// Connection lost
    Disconnected,
    /// Error occurred
    Error(String),
}

/// PHD2 JSON-RPC messages
#[derive(Serialize)]
struct JsonRpcRequest {
    method: String,
    params: Option<serde_json::Value>,
    id: u32,
}

#[derive(Deserialize, Debug)]
struct JsonRpcResponse {
    result: Option<serde_json::Value>,
    error: Option<JsonRpcError>,
}

#[derive(Deserialize, Debug)]
struct JsonRpcError {
    #[allow(dead_code)]
    code: i32,
    message: String,
}

#[derive(Deserialize, Debug)]
#[allow(dead_code)]
struct Phd2EventMessage {
    #[serde(rename = "Event")]
    event: String,
    #[serde(rename = "Timestamp")]
    timestamp: Option<f64>,
    #[serde(rename = "Host")]
    host: Option<String>,
    #[serde(rename = "Inst")]
    inst: Option<u32>,
    // Event-specific fields stored in remaining
    #[serde(flatten)]
    extra: serde_json::Value,
}

type Phd2EventCallback = Arc<Mutex<dyn Fn(Phd2Event) + Send>>;

/// PHD2 client for real guiding control.
///
/// Uses a single reader thread for the TCP socket to avoid race conditions
/// between event monitoring and RPC request/response handling.
/// The reader thread routes:
///   - JSON-RPC responses (messages with "id") to pending request waiters
///   - PHD2 events (messages with "Event") to the event callback
pub struct Phd2Client {
    /// Write half of the TCP stream for sending commands
    write_stream: Option<TcpStream>,
    host: String,
    port: u16,
    request_id: u32,
    running: Arc<AtomicBool>,
    event_callback: Option<Phd2EventCallback>,
    /// Rolling guide statistics
    rolling_stats: Arc<Mutex<RollingGuideStats>>,
    /// Connection configuration
    config: Phd2ConnectionConfig,
    /// Current connection state
    state: Arc<Mutex<Phd2State>>,
    /// Number of reconnection attempts
    reconnect_attempts: Arc<std::sync::atomic::AtomicU32>,
    /// Registry of pending RPC response senders, keyed by request ID.
    /// The reader thread sends response lines to the matching sender.
    response_registry: Arc<Mutex<HashMap<u32, mpsc::Sender<String>>>>,
}

impl Phd2Client {
    /// Create a new PHD2 client
    pub fn new(host: &str, port: u16) -> Self {
        Self {
            write_stream: None,
            host: host.to_string(),
            port,
            request_id: 0,
            running: Arc::new(AtomicBool::new(false)),
            event_callback: None,
            rolling_stats: Arc::new(Mutex::new(RollingGuideStats::default())),
            config: Phd2ConnectionConfig::default(),
            state: Arc::new(Mutex::new(Phd2State::Disconnected)),
            reconnect_attempts: Arc::new(std::sync::atomic::AtomicU32::new(0)),
            response_registry: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Create a new PHD2 client with custom configuration
    pub fn with_config(host: &str, port: u16, config: Phd2ConnectionConfig) -> Self {
        Self {
            write_stream: None,
            host: host.to_string(),
            port,
            request_id: 0,
            running: Arc::new(AtomicBool::new(false)),
            event_callback: None,
            rolling_stats: Arc::new(Mutex::new(RollingGuideStats::default())),
            config,
            state: Arc::new(Mutex::new(Phd2State::Disconnected)),
            reconnect_attempts: Arc::new(std::sync::atomic::AtomicU32::new(0)),
            response_registry: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Connect to PHD2 on localhost with default port
    pub fn localhost() -> Self {
        Self::new("127.0.0.1", 4400)
    }

    /// Get rolling guide statistics
    pub fn get_rolling_stats(&self) -> GuideStats {
        // Why: §audit-rust 4.3 — `std::sync::Mutex::lock()` only fails on
        // *poison* (a previous holder panicked while the guard was live).
        // The lock holders here (`add_frame`, `get_stats`, `reset`) are pure
        // arithmetic — none can panic in production. If poison ever does
        // occur the runtime is already in an unrecoverable state; returning
        // default zeroed stats keeps the UI from crashing while the warning
        // emitted at the poison site (reader thread) surfaces the cause.
        match self.rolling_stats.lock() {
            Ok(mut s) => s.get_stats(),
            Err(poison) => {
                tracing::error!(
                    "PHD2: rolling_stats mutex poisoned: {} — returning zeroed GuideStats",
                    poison
                );
                GuideStats::default()
            }
        }
    }

    /// Reset rolling guide statistics
    pub fn reset_stats(&self) {
        if let Ok(mut stats) = self.rolling_stats.lock() {
            stats.reset();
        }
    }

    /// Get current connection state
    pub fn get_state(&self) -> Phd2State {
        // Why: §audit-rust 4.3 — Mutex poison here would mean the reader
        // thread crashed mid-update. The TCP connection is therefore
        // effectively dead from our side regardless of the device's view;
        // reporting `Disconnected` matches reality. We log so the operator
        // can correlate the poison with whatever caused the reader panic.
        match self.state.lock() {
            Ok(s) => s.clone(),
            Err(poison) => {
                tracing::error!(
                    "PHD2: state mutex poisoned: {} — reporting Disconnected",
                    poison
                );
                Phd2State::Disconnected
            }
        }
    }

    /// Set event callback
    pub fn set_event_callback<F>(&mut self, callback: F)
    where
        F: Fn(Phd2Event) + Send + 'static,
    {
        self.event_callback = Some(Arc::new(Mutex::new(callback)));
    }

    /// Attempt to reconnect with exponential backoff
    pub fn reconnect(&mut self) -> Result<(), String> {
        if !self.config.auto_reconnect {
            return Err("Auto-reconnect is disabled".to_string());
        }

        let max_attempts = self.config.max_reconnect_attempts;
        let mut delay = self.config.initial_reconnect_delay_ms;

        for attempt in 1..=max_attempts {
            self.reconnect_attempts
                .store(attempt, std::sync::atomic::Ordering::SeqCst);
            tracing::info!("PHD2 reconnection attempt {}/{}", attempt, max_attempts);

            match self.connect() {
                Ok(()) => {
                    self.reconnect_attempts
                        .store(0, std::sync::atomic::Ordering::SeqCst);
                    tracing::info!("PHD2 reconnection successful");
                    return Ok(());
                }
                Err(e) => {
                    tracing::warn!("PHD2 reconnection failed: {}", e);
                    if attempt < max_attempts {
                        std::thread::sleep(Duration::from_millis(delay));
                        // Exponential backoff with cap
                        delay = (delay * 2).min(self.config.max_reconnect_delay_ms);
                    }
                }
            }
        }

        Err(format!(
            "Failed to reconnect after {} attempts",
            max_attempts
        ))
    }

    /// Connect to PHD2
    pub fn connect(&mut self) -> Result<(), String> {
        let addr = format!("{}:{}", self.host, self.port);
        tracing::info!("Connecting to PHD2 at {}", addr);

        let stream = TcpStream::connect_timeout(
            &addr
                .parse()
                .map_err(|e| format!("Invalid address: {}", e))?,
            Duration::from_secs(5),
        )
        .map_err(|e| format!("Failed to connect to PHD2: {}", e))?;

        // Clone the stream: one for reading (event listener), one for writing (commands)
        let read_stream = stream
            .try_clone()
            .map_err(|e| format!("Failed to clone stream for reader: {}", e))?;
        read_stream
            .set_read_timeout(Some(Duration::from_millis(100)))
            .map_err(|e| format!("Failed to set read timeout: {}", e))?;

        self.write_stream = Some(stream);
        self.running.store(true, Ordering::SeqCst);

        // Update connection state
        if let Ok(mut state) = self.state.lock() {
            *state = Phd2State::Connected;
        }

        // Start event listener thread with the dedicated read stream
        self.start_event_listener(read_stream);

        tracing::info!("Connected to PHD2");
        Ok(())
    }

    /// Disconnect from PHD2
    pub fn disconnect(&mut self) {
        self.running.store(false, Ordering::SeqCst);
        self.write_stream = None;

        // Clear any pending response waiters so they don't hang
        if let Ok(mut registry) = self.response_registry.lock() {
            registry.clear();
        }

        // Update connection state
        if let Ok(mut state) = self.state.lock() {
            *state = Phd2State::Disconnected;
        }

        tracing::info!("Disconnected from PHD2");
    }

    /// Check if connected
    pub fn is_connected(&self) -> bool {
        self.write_stream.is_some() && self.running.load(Ordering::SeqCst)
    }

    /// Start the event listener thread.
    ///
    /// This single thread owns the read side of the TCP stream and routes
    /// all incoming lines:
    ///   - JSON-RPC responses (lines containing "id") -> pending request waiter
    ///   - PHD2 events (lines containing "Event") -> event callback
    ///
    /// Uses manual line reading instead of BufReader::lines() to avoid data
    /// loss when read timeouts occur mid-line. A persistent line buffer
    /// accumulates bytes across read calls until a complete newline-terminated
    /// line is available.
    fn start_event_listener(&self, read_stream: TcpStream) {
        let running = Arc::clone(&self.running);
        let callback = self.event_callback.clone();
        let rolling_stats = Arc::clone(&self.rolling_stats);
        let state = Arc::clone(&self.state);
        let response_registry = Arc::clone(&self.response_registry);

        thread::spawn(move || {
            tracing::info!("PHD2: Reader thread started");
            let mut reader = BufReader::new(read_stream);
            // Persistent line buffer: survives across read timeouts so partial
            // lines are not lost when the 100ms read timeout fires mid-line.
            // read_line() appends to this buffer; we only clear it after
            // successfully processing a complete line.
            let mut line_buf = String::new();

            loop {
                if !running.load(Ordering::SeqCst) {
                    tracing::info!("PHD2: Reader thread stopping (running=false)");
                    break;
                }

                match reader.read_line(&mut line_buf) {
                    Ok(0) => {
                        // EOF - connection closed
                        tracing::info!("PHD2: Reader thread got EOF, connection closed");
                        if let Ok(mut s) = state.lock() {
                            *s = Phd2State::Disconnected;
                        }
                        if let Some(ref cb) = callback {
                            if let Ok(cb) = cb.lock() {
                                cb(Phd2Event::Disconnected);
                            }
                        }
                        break;
                    }
                    Ok(_n) => {
                        // read_line returns Ok(n) where n includes the \n.
                        // Only process if we have a complete line (ends with \n).
                        if !line_buf.ends_with('\n') {
                            // Partial line in buffer - keep accumulating
                            continue;
                        }

                        // Got a complete line (terminated by \n)
                        let json = line_buf.trim();
                        if json.is_empty() {
                            line_buf.clear();
                            continue;
                        }

                        // Process the complete line
                        Self::process_line(
                            json,
                            &response_registry,
                            &rolling_stats,
                            &state,
                            &callback,
                        );

                        // Clear buffer for next line
                        line_buf.clear();
                    }
                    Err(e) => {
                        if e.kind() == std::io::ErrorKind::WouldBlock
                            || e.kind() == std::io::ErrorKind::TimedOut
                        {
                            // Read timeout - normal polling interval.
                            // IMPORTANT: Do NOT clear line_buf here. If read_line()
                            // already moved bytes from BufReader's internal buffer
                            // into line_buf before the timeout, those bytes are
                            // preserved. On the next read_line() call, it will
                            // continue appending to line_buf.
                            continue;
                        }

                        tracing::warn!("PHD2: Read error (kind={:?}): {}", e.kind(), e);

                        // Update state to disconnected
                        if let Ok(mut s) = state.lock() {
                            *s = Phd2State::Disconnected;
                        }

                        if let Some(ref cb) = callback {
                            if let Ok(cb) = cb.lock() {
                                cb(Phd2Event::Disconnected);
                            }
                        }
                        break;
                    }
                }
            }

            tracing::info!("PHD2: Reader thread exited");
        });
    }

    /// Process a single complete JSON line from the PHD2 TCP stream.
    ///
    /// Routes the line to either the response registry (for JSON-RPC responses)
    /// or the event callback (for PHD2 events).
    fn process_line(
        json: &str,
        response_registry: &Arc<Mutex<HashMap<u32, mpsc::Sender<String>>>>,
        rolling_stats: &Arc<Mutex<RollingGuideStats>>,
        state: &Arc<Mutex<Phd2State>>,
        callback: &Option<Phd2EventCallback>,
    ) {
        // Parse JSON
        let parsed: serde_json::Value = match serde_json::from_str(json) {
            Ok(v) => v,
            Err(e) => {
                tracing::warn!("PHD2: Failed to parse JSON line: {} (line: {})", e, json);
                return;
            }
        };

        // Check for JSON-RPC response (has "id" field that is a number)
        if let Some(id_val) = parsed.get("id") {
            if let Some(id) = id_val.as_u64() {
                let id = id as u32;
                if let Ok(mut registry) = response_registry.lock() {
                    if let Some(sender) = registry.remove(&id) {
                        if let Err(e) = sender.send(json.to_string()) {
                            tracing::warn!("PHD2: Failed to send response for id {}: {}", id, e);
                        }
                    } else {
                        tracing::debug!("PHD2: Received response for unknown id {}", id);
                    }
                }
                return;
            }
        }

        // Otherwise treat as event message
        match serde_json::from_str::<Phd2EventMessage>(json) {
            Ok(event_msg) => {
                tracing::info!("PHD2: Received event: {}", event_msg.event);
                if let Some(event) = parse_phd2_event(&event_msg) {
                    // Update rolling stats for guide frames
                    if let Phd2Event::GuideStep(ref frame) = event {
                        if let Ok(mut stats) = rolling_stats.lock() {
                            stats.add_frame(frame);
                        }
                    }

                    // Update state for state change events
                    if let Phd2Event::StateChanged(ref new_state) = event {
                        if let Ok(mut s) = state.lock() {
                            *s = new_state.clone();
                        }
                    }

                    // Call user callback
                    if let Some(ref cb) = callback {
                        tracing::info!("PHD2: Dispatching event to callback: {:?}", event);
                        match cb.lock() {
                            Ok(cb) => {
                                cb(event);
                                tracing::info!("PHD2: Event callback completed successfully");
                            }
                            Err(e) => {
                                tracing::error!("PHD2: Event callback mutex poisoned: {}", e);
                            }
                        }
                    } else {
                        tracing::warn!("PHD2: No event callback registered, dropping event");
                    }
                } else {
                    tracing::debug!("PHD2: Unhandled event type: {}", event_msg.event);
                }
            }
            Err(e) => {
                tracing::warn!(
                    "PHD2: Failed to parse event message: {} (line: {})",
                    e,
                    json
                );
            }
        }
    }

    /// Send a JSON-RPC request and wait for the response.
    ///
    /// The write half of the stream is used to send the request.
    /// A one-shot channel is registered in the response registry so the
    /// reader thread can route the matching response back to us.
    fn send_request(
        &mut self,
        method: &str,
        params: Option<serde_json::Value>,
    ) -> Result<serde_json::Value, String> {
        let stream = self
            .write_stream
            .as_mut()
            .ok_or_else(|| "Not connected to PHD2".to_string())?;

        self.request_id += 1;
        let request_id = self.request_id;
        let request = JsonRpcRequest {
            method: method.to_string(),
            params,
            id: request_id,
        };

        // Register a response channel BEFORE sending so there is no race window
        let (tx, rx) = mpsc::channel::<String>();
        {
            let mut registry = self
                .response_registry
                .lock()
                .map_err(|e| format!("Failed to lock response registry: {}", e))?;
            registry.insert(request_id, tx);
        }

        let json = serde_json::to_string(&request)
            .map_err(|e| format!("Failed to serialize request: {}", e))?;

        tracing::debug!("PHD2 send_request: {} (id={})", method, request_id);

        stream
            .write_all(json.as_bytes())
            .map_err(|e| format!("Failed to send request: {}", e))?;
        stream
            .write_all(b"\r\n")
            .map_err(|e| format!("Failed to send newline: {}", e))?;
        stream
            .flush()
            .map_err(|e| format!("Failed to flush: {}", e))?;

        // Wait for the response from the reader thread with a timeout
        let response_line = rx
            .recv_timeout(Duration::from_secs(10))
            .map_err(|e| match e {
                mpsc::RecvTimeoutError::Timeout => {
                    // Clean up the registry entry on timeout
                    if let Ok(mut registry) = self.response_registry.lock() {
                        registry.remove(&request_id);
                    }
                    format!("Request '{}' timed out (id={})", method, request_id)
                }
                mpsc::RecvTimeoutError::Disconnected => {
                    format!(
                        "Response channel disconnected for '{}' (id={})",
                        method, request_id
                    )
                }
            })?;

        // Parse the response
        let resp: JsonRpcResponse = serde_json::from_str(&response_line)
            .map_err(|e| format!("Failed to parse response: {}", e))?;

        if let Some(error) = resp.error {
            return Err(format!("PHD2 error: {}", error.message));
        }

        // Why: §audit-rust 4.3 — per JSON-RPC 2.0, a response with no `error`
        // is REQUIRED to contain `result`, but PHD2 RPC methods that semantically
        // return void (`set_connected`, `loop`, `stop_capture`, etc.) ship
        // `{"jsonrpc":"2.0","result":0,"id":N}` — or, on older builds, just
        // omit `result`. Substituting `Null` here is the documented contract:
        // void-returning callers ignore the value, value-returning callers
        // immediately downcast (`.as_str()`/`.as_array()` etc.) and would
        // already fail on `Null` with a clear "expected …" error rather than
        // bubbling a confusing "missing result" message.
        Ok(resp.result.unwrap_or(serde_json::Value::Null))
    }

    // ========================================================================
    // PHD2 Commands
    // ========================================================================

    /// Get PHD2 application state
    pub fn get_app_state(&mut self) -> Result<Phd2State, String> {
        let result = self.send_request("get_app_state", None)?;
        let state_str = result
            .as_str()
            .ok_or_else(|| format!("get_app_state: expected string, got {}", result))?;
        Ok(parse_phd2_app_state(state_str))
    }

    /// Get connected equipment
    pub fn get_connected(&mut self) -> Result<bool, String> {
        let result = self.send_request("get_connected", None)?;
        // §audit-rust 4.3 — previously `.as_bool().unwrap_or(false)` silently
        // reported "not connected" whenever PHD2 returned a non-bool (e.g.
        // protocol corruption, schema drift). Propagate the type mismatch.
        result
            .as_bool()
            .ok_or_else(|| format!("get_connected: expected bool, got {}", result))
    }

    /// Connect PHD2 to equipment
    pub fn set_connected(&mut self, connected: bool) -> Result<(), String> {
        self.send_request("set_connected", Some(serde_json::json!(connected)))?;
        Ok(())
    }

    /// Start guiding
    pub fn guide(
        &mut self,
        settle_pixels: f64,
        settle_time: f64,
        settle_timeout: f64,
    ) -> Result<(), String> {
        let params = serde_json::json!({
            "settle": {
                "pixels": settle_pixels,
                "time": settle_time,
                "timeout": settle_timeout
            }
        });
        self.send_request("guide", Some(params))?;
        Ok(())
    }

    /// Stop guiding
    pub fn stop_capture(&mut self) -> Result<(), String> {
        self.send_request("stop_capture", None)?;
        Ok(())
    }

    /// Pause guiding
    pub fn set_paused(&mut self, paused: bool) -> Result<(), String> {
        self.send_request("set_paused", Some(serde_json::json!([paused, "full"])))?;
        Ok(())
    }

    /// Dither the guide star
    pub fn dither(
        &mut self,
        amount: f64,
        ra_only: bool,
        settle_pixels: f64,
        settle_time: f64,
        settle_timeout: f64,
    ) -> Result<(), String> {
        let params = serde_json::json!({
            "amount": amount,
            "raOnly": ra_only,
            "settle": {
                "pixels": settle_pixels,
                "time": settle_time,
                "timeout": settle_timeout
            }
        });
        self.send_request("dither", Some(params))?;
        Ok(())
    }

    /// Set lock position (guide star position)
    pub fn set_lock_position(&mut self, x: f64, y: f64, exact: bool) -> Result<(), String> {
        self.send_request("set_lock_position", Some(serde_json::json!([x, y, exact])))?;
        Ok(())
    }

    /// Clear calibration
    pub fn clear_calibration(&mut self, which: &str) -> Result<(), String> {
        self.send_request("clear_calibration", Some(serde_json::json!(which)))?;
        Ok(())
    }

    /// Flip calibration (after meridian flip)
    pub fn flip_calibration(&mut self) -> Result<(), String> {
        self.send_request("flip_calibration", None)?;
        Ok(())
    }

    /// Get current guide star position
    pub fn get_lock_position(&mut self) -> Result<(f64, f64), String> {
        let result = self.send_request("get_lock_position", None)?;
        let arr = result
            .as_array()
            .ok_or_else(|| format!("get_lock_position: expected array, got {}", result))?;

        // §audit-rust 4.3 — PHD2 contract: `[x, y]` floats. A missing element
        // or non-numeric value means schema drift or no star locked; surface
        // it instead of silently reporting "guide star at origin (0, 0)".
        let x = arr
            .first()
            .and_then(|v| v.as_f64())
            .ok_or_else(|| "get_lock_position: missing or non-numeric X".to_string())?;
        let y = arr
            .get(1)
            .and_then(|v| v.as_f64())
            .ok_or_else(|| "get_lock_position: missing or non-numeric Y".to_string())?;

        Ok((x, y))
    }

    /// Get exposure time
    pub fn get_exposure(&mut self) -> Result<u32, String> {
        let result = self.send_request("get_exposure", None)?;
        // §audit-rust 4.3 — PHD2 always returns the exposure as an unsigned
        // integer (milliseconds). A non-integer or negative value is a
        // protocol violation; surface it rather than silently reporting 0ms
        // which the caller would interpret as "no exposure set".
        let exposure = result
            .as_u64()
            .ok_or_else(|| format!("get_exposure: expected unsigned integer, got {}", result))?;
        u32::try_from(exposure)
            .map_err(|_| format!("get_exposure: value {} exceeds u32::MAX", exposure))
    }

    /// Set exposure time (milliseconds)
    pub fn set_exposure(&mut self, exposure_ms: u32) -> Result<(), String> {
        self.send_request("set_exposure", Some(serde_json::json!(exposure_ms)))?;
        Ok(())
    }

    /// Get pixel scale (arcsec/pixel)
    pub fn get_pixel_scale(&mut self) -> Result<f64, String> {
        let result = self.send_request("get_pixel_scale", None)?;
        // §audit-rust 4.3 — pixel scale of 0 is physically meaningless and
        // would silently break every downstream RA/Dec-to-pixel conversion.
        // Propagate the parse failure so the caller knows the value is
        // unavailable (e.g. PHD2 has no profile loaded).
        result
            .as_f64()
            .ok_or_else(|| format!("get_pixel_scale: expected number, got {}", result))
    }

    /// Get current star image (raw bytes only - deprecated, use get_star_image_data instead)
    pub fn get_star_image(&mut self) -> Result<Vec<u8>, String> {
        let data = self.get_star_image_data(32)?;
        Ok(data.pixels)
    }

    /// Get current star image with full metadata
    /// size: requested size of the subframe (minimum 15, default 32)
    pub fn get_star_image_data(&mut self, size: u32) -> Result<StarImageData, String> {
        let params = serde_json::json!({ "size": size });
        let result = self.send_request("get_star_image", Some(params))?;

        // §audit-rust 4.3 — `frame`, `width`, and `height` are REQUIRED fields
        // per the PHD2 `get_star_image` schema. A missing/non-integer value
        // means the response is malformed (or PHD2 changed schema); previously
        // we silently produced a 0x0 image with frame=0, which downstream star
        // analysis would happily process and report bogus results.
        let frame = result
            .get("frame")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| "get_star_image: missing or non-integer 'frame'".to_string())?
            as u32;

        let width = result
            .get("width")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| "get_star_image: missing or non-integer 'width'".to_string())?
            as u32;

        let height = result
            .get("height")
            .and_then(|v| v.as_u64())
            .ok_or_else(|| "get_star_image: missing or non-integer 'height'".to_string())?
            as u32;

        // star_pos is [x, y] array. PHD2 documents the field as optional
        // when no star is locked (returned `null` / absent), so treating
        // "no star_pos" as `(0.0, 0.0)` is the documented fallback. A
        // present-but-malformed array, however, is a protocol violation
        // and must surface — `.unwrap_or(0.0)` previously hid that.
        let star_pos = result.get("star_pos").and_then(|v| v.as_array());
        let (star_x, star_y) = match star_pos {
            Some(arr) => {
                let x = arr.first().and_then(|v| v.as_f64()).ok_or_else(|| {
                    "get_star_image: 'star_pos' present but X missing/non-numeric".to_string()
                })?;
                let y = arr.get(1).and_then(|v| v.as_f64()).ok_or_else(|| {
                    "get_star_image: 'star_pos' present but Y missing/non-numeric".to_string()
                })?;
                (x, y)
            }
            // Why: per PHD2 protocol, absent `star_pos` indicates no star is
            // currently locked. The subframe pixels are still valid; (0, 0)
            // is the canonical "unset" marker that callers already check for.
            None => (0.0, 0.0),
        };

        // Decode base64 pixel data
        let pixels_b64 = result
            .get("pixels")
            .and_then(|v| v.as_str())
            .ok_or_else(|| "No pixel data in response".to_string())?;
        let pixels = base64_decode(pixels_b64)?;

        Ok(StarImageData {
            frame,
            width,
            height,
            star_x,
            star_y,
            pixels,
        })
    }

    /// Loop exposures (without guiding)
    pub fn loop_exposures(&mut self) -> Result<(), String> {
        self.send_request("loop", None)?;
        Ok(())
    }

    /// Find a guide star automatically
    pub fn find_star(&mut self) -> Result<(f64, f64), String> {
        let result = self.send_request("find_star", None)?;
        let arr = result
            .as_array()
            .ok_or_else(|| format!("find_star: expected array, got {}", result))?;

        // §audit-rust 4.3 — PHD2 contract: `[x, y]` floats of the chosen star.
        // (0, 0) was indistinguishable from "no star found"; surface the parse
        // failure so callers can fall back instead of slewing to the origin.
        let x = arr
            .first()
            .and_then(|v| v.as_f64())
            .ok_or_else(|| "find_star: missing or non-numeric X".to_string())?;
        let y = arr
            .get(1)
            .and_then(|v| v.as_f64())
            .ok_or_else(|| "find_star: missing or non-numeric Y".to_string())?;

        Ok((x, y))
    }

    // ========================================================================
    // PHD2 Brain API - Algorithm Parameters
    // ========================================================================

    /// Get available algorithm parameter names for an axis
    /// axis: "ra" or "dec" (also accepts "x" or "y")
    pub fn get_algo_param_names(&mut self, axis: &str) -> Result<Vec<String>, String> {
        let params = serde_json::json!({ "axis": axis });
        let result = self.send_request("get_algo_param_names", Some(params))?;

        let arr = result
            .as_array()
            .ok_or_else(|| "Invalid response: expected array".to_string())?;

        let names: Vec<String> = arr
            .iter()
            .filter_map(|v| v.as_str().map(|s| s.to_string()))
            .collect();

        Ok(names)
    }

    /// Get the value of an algorithm parameter
    /// axis: "ra" or "dec" (also accepts "x" or "y")
    /// name: parameter name (from get_algo_param_names)
    pub fn get_algo_param(&mut self, axis: &str, name: &str) -> Result<f64, String> {
        let params = serde_json::json!({
            "axis": axis,
            "name": name
        });
        let result = self.send_request("get_algo_param", Some(params))?;

        result
            .as_f64()
            .ok_or_else(|| format!("Invalid response for parameter {}: expected number", name))
    }

    /// Set the value of an algorithm parameter
    /// axis: "ra" or "dec" (also accepts "x" or "y")
    /// name: parameter name (from get_algo_param_names)
    /// value: new parameter value
    pub fn set_algo_param(&mut self, axis: &str, name: &str, value: f64) -> Result<(), String> {
        let params = serde_json::json!({
            "axis": axis,
            "name": name,
            "value": value
        });
        let result = self.send_request("set_algo_param", Some(params))?;

        // Result should be 0 on success
        // Why: §audit-rust 4.3 — `-1` is a deliberate sentinel meaning "couldn't
        // even parse a status code". PHD2 returns `0` on success and a positive
        // error code otherwise, so any non-zero value (including the sentinel)
        // correctly triggers the error branch below. Replacing with `?` would
        // strip the helpful "Failed to set parameter X" prefix.
        let code = result.as_i64().unwrap_or(-1);
        if code != 0 {
            return Err(format!(
                "Failed to set parameter {}: error code {}",
                name, code
            ));
        }

        Ok(())
    }

    /// Get all algorithm parameters for an axis
    pub fn get_all_algo_params(&mut self, axis: &str) -> Result<Vec<AlgoParam>, String> {
        let names = self.get_algo_param_names(axis)?;
        let mut params = Vec::with_capacity(names.len());

        for name in names {
            let value = self.get_algo_param(axis, &name)?;
            params.push(AlgoParam { name, value });
        }

        Ok(params)
    }

    /// Get the current calibration data
    pub fn get_calibration_data(&mut self, which: &str) -> Result<serde_json::Value, String> {
        let params = serde_json::json!({ "which": which });
        self.send_request("get_calibration_data", Some(params))
    }

    /// Deselect the current guide star
    pub fn deselect_star(&mut self) -> Result<(), String> {
        self.send_request("deselect_star", None)?;
        Ok(())
    }

    /// Get current camera frame dimensions
    pub fn get_camera_frame_size(&mut self) -> Result<(u32, u32), String> {
        let result = self.send_request("get_camera_frame_size", None)?;
        let arr = result
            .as_array()
            .ok_or_else(|| format!("get_camera_frame_size: expected array, got {}", result))?;

        // §audit-rust 4.3 — width/height of 0 silently produced division-by-zero
        // downstream in pixel-scale and binning logic. Surface the parse error.
        let width = arr
            .first()
            .and_then(|v| v.as_u64())
            .ok_or_else(|| "get_camera_frame_size: missing or non-integer width".to_string())?
            as u32;
        let height = arr
            .get(1)
            .and_then(|v| v.as_u64())
            .ok_or_else(|| "get_camera_frame_size: missing or non-integer height".to_string())?
            as u32;

        Ok((width, height))
    }

    /// Get guide output enabled status
    pub fn get_guide_output_enabled(&mut self) -> Result<bool, String> {
        let result = self.send_request("get_guide_output_enabled", None)?;
        // §audit-rust 4.3 — see `get_connected`. A non-bool means protocol
        // corruption; "guide output disabled" is the wrong default to assume
        // because callers may rely on this to gate dither/pulse commands.
        result
            .as_bool()
            .ok_or_else(|| format!("get_guide_output_enabled: expected bool, got {}", result))
    }

    /// Set guide output enabled status
    pub fn set_guide_output_enabled(&mut self, enabled: bool) -> Result<(), String> {
        self.send_request("set_guide_output_enabled", Some(serde_json::json!(enabled)))?;
        Ok(())
    }

    /// Get current profile name
    pub fn get_profile(&mut self) -> Result<String, String> {
        let result = self.send_request("get_profile", None)?;
        // §audit-rust 4.3 — the previous `unwrap_or("Unknown")` papered over
        // schema drift (the field used to be `name`; new builds may rename it).
        // Surface the absence so we notice during dev rather than always
        // displaying "Unknown" in the UI.
        let profile = result
            .get("name")
            .and_then(|v| v.as_str())
            .ok_or_else(|| format!("get_profile: missing 'name' field in {}", result))?;
        Ok(profile.to_string())
    }
}

impl Drop for Phd2Client {
    fn drop(&mut self) {
        self.disconnect();
    }
}

/// Parse a PHD2 event message.
///
/// Returns `None` only when the event name is unknown OR a *critical* field
/// is missing (e.g. `GuideStep` without `RADistanceRaw`/`DECDistanceRaw`).
/// Critical-field absence is logged at `warn` level so schema drift surfaces
/// in operator logs instead of producing zeroed-out guide frames that would
/// silently degrade tracking accuracy.
fn parse_phd2_event(msg: &Phd2EventMessage) -> Option<Phd2Event> {
    match msg.event.as_str() {
        "GuideStep" => {
            let extra = &msg.extra;

            // Why: §audit-rust 4.3 — RA/Dec distance are the LOAD-BEARING
            // values of every guide frame. Defaulting them to 0.0 used to
            // mark every malformed/dropped event as "perfect guiding" and
            // poisoned the rolling RMS. If either is missing or non-numeric
            // we now drop the whole frame and log so we can detect drift.
            let ra_distance = match extra.get("RADistanceRaw").and_then(|v| v.as_f64()) {
                Some(v) => v,
                None => {
                    tracing::warn!(
                        "PHD2: GuideStep missing RADistanceRaw — dropping frame ({})",
                        msg.extra
                    );
                    return None;
                }
            };
            let dec_distance = match extra.get("DECDistanceRaw").and_then(|v| v.as_f64()) {
                Some(v) => v,
                None => {
                    tracing::warn!(
                        "PHD2: GuideStep missing DECDistanceRaw — dropping frame ({})",
                        msg.extra
                    );
                    return None;
                }
            };

            // Why: §audit-rust 4.3 — `Frame` (sequence number) and
            // `timestamp` may legitimately be absent in older PHD2 builds
            // that predate Event-monitoring schema v1.7; the rolling-stats
            // window keeps its own counter, so 0 here is a recoverable
            // default rather than a silent error.
            let frame = extra.get("Frame").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
            let timestamp = msg.timestamp.unwrap_or(0.0);

            // Why: §audit-rust 4.3 — pulse durations and directions ARE
            // absent in real PHD2 traffic when no correction was issued
            // for the axis (zero-duration step). Defaulting to 0 ms and
            // "" matches PHD2's own "no pulse" semantics; the UI checks
            // duration > 0 before drawing the direction arrow.
            let ra_duration = extra
                .get("RADuration")
                .and_then(|v| v.as_i64())
                .unwrap_or(0) as i32;
            let dec_duration = extra
                .get("DECDuration")
                .and_then(|v| v.as_i64())
                .unwrap_or(0) as i32;
            let ra_direction = extra
                .get("RADirection")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let dec_direction = extra
                .get("DECDirection")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            // Why: §audit-rust 4.3 — SNR, StarMass, StarX, StarY, AvgDist
            // are PHD2 "optional" fields per the EventMonitoring wiki:
            // they may be absent during calibration steps, settling, or
            // very early frames before the rolling stats stabilise. 0.0
            // is the documented "not yet measured" sentinel and the
            // dashboard already filters frame_count < 5 before display.
            let snr = extra.get("SNR").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let star_mass = extra
                .get("StarMass")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0);
            let star_x = extra.get("StarX").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let star_y = extra.get("StarY").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let avg_dist = extra.get("AvgDist").and_then(|v| v.as_f64()).unwrap_or(0.0);

            Some(Phd2Event::GuideStep(GuideFrame {
                frame,
                timestamp,
                ra_distance,
                dec_distance,
                ra_duration,
                dec_duration,
                ra_direction,
                dec_direction,
                snr,
                star_mass,
                star_x,
                star_y,
                avg_dist,
            }))
        }
        "AppState" => {
            // Why: §audit-rust 4.3 — an `AppState` event with no `State`
            // field is malformed; routing it through `parse_phd2_app_state`
            // would yield `Phd2State::Unknown("")` and spam the warn log.
            // Drop the event instead and log once with the offending blob.
            let Some(state_str) = msg.extra.get("State").and_then(|v| v.as_str()) else {
                tracing::warn!(
                    "PHD2: AppState event missing 'State' field — dropping ({})",
                    msg.extra
                );
                return None;
            };
            Some(Phd2Event::StateChanged(parse_phd2_app_state(state_str)))
        }
        "StartCalibration" => Some(Phd2Event::StateChanged(Phd2State::Calibrating)),
        "CalibrationComplete" => Some(Phd2Event::CalibrationComplete),
        "StartGuiding" => Some(Phd2Event::StateChanged(Phd2State::Guiding)),
        "GuidingStopped" => Some(Phd2Event::StateChanged(Phd2State::Connected)),
        "Paused" => Some(Phd2Event::StateChanged(Phd2State::Paused)),
        "LoopingExposures" => Some(Phd2Event::StateChanged(Phd2State::Looping)),
        "LoopingExposuresStopped" => Some(Phd2Event::StateChanged(Phd2State::Connected)),
        "StarLost" => Some(Phd2Event::StarLost),
        "StarSelected" => {
            // Why: §audit-rust 4.3 — `X` and `Y` are REQUIRED by the
            // PHD2 protocol for `StarSelected`. (0,0) was indistinguishable
            // from a valid lock at the origin; drop the malformed event.
            let Some(x) = msg.extra.get("X").and_then(|v| v.as_f64()) else {
                tracing::warn!(
                    "PHD2: StarSelected event missing X — dropping ({})",
                    msg.extra
                );
                return None;
            };
            let Some(y) = msg.extra.get("Y").and_then(|v| v.as_f64()) else {
                tracing::warn!(
                    "PHD2: StarSelected event missing Y — dropping ({})",
                    msg.extra
                );
                return None;
            };
            Some(Phd2Event::StarSelected { x, y })
        }
        "SettleBegin" => Some(Phd2Event::SettleBegin),
        "Settling" => Some(Phd2Event::StateChanged(Phd2State::Settling)),
        "SettleDone" => {
            // Why: §audit-rust 4.3 — `TotalFrames`/`DroppedFrames` may
            // legitimately be 0 when settling completes on the first
            // frame; absence (`None`) is also documented as "no frames
            // tracked", so 0 is the protocol-defined fallback rather than
            // a swallowed parse error. Both branches collapse to identical
            // UI semantics ("no drops").
            let total = msg
                .extra
                .get("TotalFrames")
                .and_then(|v| v.as_u64())
                .unwrap_or(0) as u32;
            let dropped = msg
                .extra
                .get("DroppedFrames")
                .and_then(|v| v.as_u64())
                .unwrap_or(0) as u32;
            Some(Phd2Event::SettleDone {
                total_frames: total,
                dropped_frames: dropped,
            })
        }
        "Alert" => {
            // Why: §audit-rust 4.3 — an Alert with no `Msg`/`Type` is
            // useless to the operator; surface the malformed event in the
            // log and drop it rather than synthesising an empty alert that
            // would mask whatever PHD2 actually wanted to warn us about.
            let Some(message) = msg.extra.get("Msg").and_then(|v| v.as_str()) else {
                tracing::warn!(
                    "PHD2: Alert event missing 'Msg' field — dropping ({})",
                    msg.extra
                );
                return None;
            };
            let Some(alert_type) = msg.extra.get("Type").and_then(|v| v.as_str()) else {
                tracing::warn!(
                    "PHD2: Alert event missing 'Type' field — dropping ({})",
                    msg.extra
                );
                return None;
            };
            Some(Phd2Event::Alert {
                message: message.to_string(),
                alert_type: alert_type.to_string(),
            })
        }
        _ => None,
    }
}

/// Map a PHD2 application-state string to a `Phd2State`.
///
/// PHD2's documented states are `Stopped`, `Selected`, `Calibrating`,
/// `Guiding`, `Looping`, `Paused`, and `LostLock`; the `Settling` state shows
/// up via dedicated events. Newer PHD2 builds occasionally introduce
/// additional state names (e.g. `GuidingPaused`, `StarFound`). When we see an
/// unrecognised value, we **must not** silently coerce it to `Connected` —
/// that masked guiding regressions for the duration of an entire imaging
/// session. Instead, surface it as `Phd2State::Unknown(raw)` and emit a
/// warn-level log so the operator (and our diagnostics) can react.
fn parse_phd2_app_state(state_str: &str) -> Phd2State {
    match state_str {
        "Stopped" => Phd2State::Connected,
        "Selected" => Phd2State::Connected,
        "Calibrating" => Phd2State::Calibrating,
        "Guiding" => Phd2State::Guiding,
        "Looping" => Phd2State::Looping,
        "Paused" => Phd2State::Paused,
        "LostLock" => Phd2State::LostLock,
        other => {
            tracing::warn!(
                "PHD2: unrecognised app-state {:?} — preserving as Phd2State::Unknown",
                other
            );
            Phd2State::Unknown(other.to_string())
        }
    }
}

/// Simple base64 decoder
fn base64_decode(input: &str) -> Result<Vec<u8>, String> {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    let input = input.trim().replace(['\n', '\r'], "");
    let mut output = Vec::with_capacity(input.len() * 3 / 4);

    let mut buf = 0u32;
    let mut bits = 0;

    for c in input.bytes() {
        if c == b'=' {
            break;
        }

        let val = ALPHABET
            .iter()
            .position(|&x| x == c)
            .ok_or_else(|| format!("Invalid base64 character: {}", c as char))?;

        buf = (buf << 6) | (val as u32);
        bits += 6;

        if bits >= 8 {
            bits -= 8;
            output.push((buf >> bits) as u8);
            buf &= (1 << bits) - 1;
        }
    }

    Ok(output)
}

/// Check if PHD2 is running
pub fn is_phd2_running() -> bool {
    let Ok(addr) = "127.0.0.1:4400".parse() else {
        return false;
    };
    TcpStream::connect_timeout(&addr, Duration::from_millis(500)).is_ok()
}

/// Check if PHD2 is installed
pub fn is_phd2_installed() -> bool {
    #[cfg(target_os = "windows")]
    {
        use std::process::Command;
        // Check registry for PHD2 installation
        let output = Command::new("reg")
            .args(["query", "HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\PHD 2_is1", "/v", "InstallLocation"])
            .output();

        match output {
            Ok(o) => o.status.success(),
            Err(_) => false,
        }
    }
    #[cfg(not(target_os = "windows"))]
    {
        use std::path::Path;
        use std::process::Command;

        #[cfg(target_os = "macos")]
        {
            if Path::new("/Applications/PHD2.app").exists()
                || Path::new("/Applications/PHD2.app/Contents/MacOS/PHD2").exists()
            {
                return true;
            }
        }

        for candidate in [
            "/usr/bin/phd2",
            "/usr/local/bin/phd2",
            "/snap/bin/phd2",
            "/opt/homebrew/bin/phd2",
        ] {
            if Path::new(candidate).exists() {
                return true;
            }
        }

        // PATH-based check for Linux/macOS.
        // Why: §audit-rust 4.3 — `is_phd2_installed` returns `bool` and is a
        // purely best-effort heuristic before the launcher tries fallbacks.
        // If we cannot even spawn `sh` (sandboxed environment, missing
        // /bin/sh on a stripped container, OS errno EPERM), treating that
        // as "not installed via PATH" is the correct answer because we
        // simultaneously couldn't run `phd2` from PATH either. The other
        // (well-known-path) branches above already returned `true` early
        // if PHD2 was found, so reaching this line means PATH is the only
        // remaining option.
        Command::new("sh")
            .args(["-lc", "command -v phd2 >/dev/null 2>&1"])
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    }
}

/// Launch PHD2 application
pub fn launch_phd2() -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        use std::process::Command;

        // Get install location
        let output = Command::new("reg")
            .args(["query", "HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\PHD 2_is1", "/v", "InstallLocation"])
            .output()
            .map_err(|e| format!("Failed to query registry: {}", e))?;

        if !output.status.success() {
            return Err("PHD2 not found in registry".to_string());
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        // Parse path from output
        let path_line = stdout
            .lines()
            .find(|l| l.contains("InstallLocation"))
            .ok_or("InstallLocation not found")?;
        let path_part = path_line
            .split("REG_SZ")
            .nth(1)
            .ok_or("Invalid registry output")?
            .trim();

        let exe_path = std::path::Path::new(path_part).join("phd2.exe");

        tracing::info!("Launching PHD2 from: {:?}", exe_path);

        Command::new(exe_path)
            .spawn()
            .map_err(|e| format!("Failed to launch PHD2: {}", e))?;

        Ok(())
    }
    #[cfg(not(target_os = "windows"))]
    {
        use std::path::Path;
        use std::process::Command;

        #[cfg(target_os = "macos")]
        {
            let status = Command::new("open")
                .args(["-a", "PHD2"])
                .status()
                .map_err(|e| format!("Failed to launch PHD2 via open: {}", e))?;
            if status.success() {
                return Ok(());
            }
        }

        for candidate in [
            "/usr/bin/phd2",
            "/usr/local/bin/phd2",
            "/snap/bin/phd2",
            "/opt/homebrew/bin/phd2",
        ] {
            if Path::new(candidate).exists() {
                Command::new(candidate)
                    .spawn()
                    .map_err(|e| format!("Failed to launch PHD2 from {}: {}", candidate, e))?;
                return Ok(());
            }
        }

        Command::new("phd2")
            .spawn()
            .map_err(|e| format!("Failed to launch PHD2: {}", e))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// §6.23: documented PHD2 app states map deterministically and
    /// unambiguously. Two of them (`Stopped`, `Selected`) collapse to
    /// `Connected` per PHD2's protocol semantics; the rest are 1:1.
    #[test]
    fn parses_known_phd2_app_states() {
        assert_eq!(parse_phd2_app_state("Stopped"), Phd2State::Connected);
        assert_eq!(parse_phd2_app_state("Selected"), Phd2State::Connected);
        assert_eq!(parse_phd2_app_state("Calibrating"), Phd2State::Calibrating);
        assert_eq!(parse_phd2_app_state("Guiding"), Phd2State::Guiding);
        assert_eq!(parse_phd2_app_state("Looping"), Phd2State::Looping);
        assert_eq!(parse_phd2_app_state("Paused"), Phd2State::Paused);
        assert_eq!(parse_phd2_app_state("LostLock"), Phd2State::LostLock);
    }

    /// §6.23: unknown PHD2 state names must surface as `Unknown(raw)` so the
    /// raw string is preserved end-to-end (logs, telemetry, UI). Previously
    /// we silently mapped them to `Connected`, hiding e.g. `GuidingPaused`.
    #[test]
    fn unknown_phd2_state_preserves_raw_string() {
        for sample in &["GuidingPaused", "StarFound", "", "TotallyMadeUpState"] {
            match parse_phd2_app_state(sample) {
                Phd2State::Unknown(raw) => assert_eq!(raw, *sample, "raw string must round-trip"),
                other => panic!(
                    "expected Phd2State::Unknown({:?}), got {:?}",
                    sample, other
                ),
            }
        }
    }
}
