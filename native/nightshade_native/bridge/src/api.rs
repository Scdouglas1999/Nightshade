//! Public API exposed to Dart via flutter_rust_bridge
//!
//! This module contains all the functions that can be called from Dart.
//! Each function is marked with the appropriate flutter_rust_bridge attributes.

use crate::adaptive_polling::{AdaptivePoller, PollerPreset};
use crate::device::*;
use crate::devices::DeviceManager;
use crate::error::*;
use crate::event::*;
use crate::filter_matching::find_filter_match;
use crate::state::*;
use crate::storage::{AppSettings, ObserverLocation};
use crate::unified_device_ops::create_unified_device_ops;
use nightshade_imaging::{
    calculate_airmass, validate_fits_header, validate_image, write_fits, BayerPattern,
    DebayerAlgorithm, FitsHeader, ImageData,
};
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::sync::RwLock;

/// Global application state singleton
static APP_STATE: OnceLock<SharedAppState> = OnceLock::new();

/// Get or initialize the global application state
#[flutter_rust_bridge::frb(ignore)]
pub fn get_state() -> &'static SharedAppState {
    APP_STATE.get_or_init(AppState::new)
}

/// Global device manager singleton
static DEVICE_MANAGER: OnceLock<Arc<DeviceManager>> = OnceLock::new();

/// Get or initialize the global device manager
#[flutter_rust_bridge::frb(ignore)]
pub fn get_device_manager() -> &'static Arc<DeviceManager> {
    DEVICE_MANAGER.get_or_init(|| DeviceManager::new(get_state().clone()))
}

// =============================================================================
// Unified Discovery Cache (ASCOM + Alpaca + Native + INDI)
// =============================================================================

/// Unified cache for ALL discovered devices across every discovery source.
/// When `api_discover_devices()` is called for any device type, the first call
/// runs full discovery for all sources (ASCOM, Alpaca, Native, INDI) and caches
/// every result. Subsequent calls within the TTL just filter by device_type.
struct DiscoveryCache {
    /// All discovered devices from every source, unfiltered
    all_devices: Vec<DeviceInfo>,
    /// When the cache was last populated
    timestamp: Instant,
}

/// Global unified discovery cache
static DISCOVERY_CACHE: OnceLock<Mutex<Option<DiscoveryCache>>> = OnceLock::new();

// =============================================================================
// Event Stream Overflow Tracking
// =============================================================================

use std::sync::atomic::AtomicU64;

/// Global counter for total events dropped across all event streams.
/// This is incremented when a receiver falls behind and events are skipped.
static TOTAL_DROPPED_EVENTS: AtomicU64 = AtomicU64::new(0);
static TEMP_FITS_FILE_COUNTER: AtomicU64 = AtomicU64::new(0);

/// How long to cache unified discovery results (60 seconds)
const DISCOVERY_CACHE_TTL: Duration = Duration::from_secs(60);

/// Get or initialize the discovery cache
fn get_discovery_cache() -> &'static Mutex<Option<DiscoveryCache>> {
    DISCOVERY_CACHE.get_or_init(|| Mutex::new(None))
}

/// Discovery state to prevent concurrent discovery operations
static DISCOVERY_IN_PROGRESS: OnceLock<Mutex<bool>> = OnceLock::new();

fn get_discovery_lock() -> &'static Mutex<bool> {
    DISCOVERY_IN_PROGRESS.get_or_init(|| Mutex::new(false))
}

pub(crate) fn create_unique_temp_fits_path(prefix: &str) -> std::path::PathBuf {
    let counter = TEMP_FITS_FILE_COUNTER.fetch_add(1, Ordering::Relaxed);
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    std::env::temp_dir().join(format!(
        "{}_{}_{}_{}.fits",
        prefix,
        std::process::id(),
        timestamp,
        counter
    ))
}

/// Invalidate the unified discovery cache, forcing fresh discovery on next call.
/// Also invalidates the native SDK discovery cache so vendor SDKs are re-queried.
/// Called when user explicitly requests a rescan.
pub async fn api_invalidate_discovery_cache() {
    // Invalidate the unified cache
    let mut cache = get_discovery_cache().lock().await;
    *cache = None;
    // Also invalidate the native vendor SDK cache so it re-queries all SDKs
    nightshade_native::invalidate_discovery_cache().await;
    tracing::info!("Discovery cache invalidated");
}

// =============================================================================
// Initialization
// =============================================================================

/// Initialize the native bridge with optional file logging
/// Must be called once at app startup before any other API calls
///
/// # Arguments
/// * `log_directory` - Optional path to store log files. If None, logs only to console.
#[flutter_rust_bridge::frb(sync)]
pub fn api_init_with_logging(log_directory: Option<String>) -> Result<(), NightshadeError> {
    // Initialize logging (with file output if directory provided)
    crate::init_native_with_logging(log_directory)?;

    tracing::info!("Nightshade Native API initialized");

    // Initialize the app state
    let _ = get_state();

    // Initialize device manager (this will spawn Tokio tasks, so runtime must exist)
    let _ = get_device_manager();

    // Publish system initialized event
    get_state().publish_system_event(SystemEvent::Initialized);

    Ok(())
}

/// Initialize the native bridge and return success (console logging only)
/// Must be called once at app startup before any other API calls
#[flutter_rust_bridge::frb(sync)]
pub fn api_init() -> Result<(), NightshadeError> {
    api_init_with_logging(None)
}

/// Get the version of the native library
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Get the current log directory path
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_log_directory() -> Option<String> {
    crate::get_log_directory()
}

/// Get the current log file path (today's log)
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_current_log_file() -> Option<String> {
    crate::get_current_log_file()
}

/// List all available log files
pub fn api_list_log_files() -> Vec<String> {
    crate::list_log_files()
}

/// Read a log file's contents
pub fn api_read_log_file(path: String) -> Result<String, NightshadeError> {
    crate::read_log_file(path)
}

/// Export all logs to a single file for diagnostics
pub fn api_export_logs(output_path: String) -> Result<(), NightshadeError> {
    crate::export_logs_to_file(output_path)
}

// =============================================================================
// Event Stream
// =============================================================================

/// Stream of events from the native side
/// The Dart side should listen to this stream for UI updates
///
/// # Overflow Handling
///
/// If the Dart side falls behind in consuming events (e.g., during heavy UI work),
/// the event stream will skip lagged events and send an `EventsDropped` notification
/// so the Dart side knows to refresh its state. The total number of dropped events
/// is tracked for diagnostics.
pub async fn api_event_stream(
    sink: crate::frb_generated::StreamSink<NightshadeEvent>,
) -> anyhow::Result<()> {
    tracing::info!(
        "[API_EVENT_STREAM] Starting event stream function (buffer size: {})",
        crate::event::DEFAULT_EVENT_BUFFER_SIZE
    );

    let mut rx = get_state().event_bus.subscribe();
    tracing::info!("[API_EVENT_STREAM] Subscribed to event bus");

    // Send a ready signal so Dart knows the subscription is active
    // This prevents race conditions where events are published before we're subscribed
    if let Err(err) = sink.add(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::System,
        EventPayload::System(SystemEvent::Notification {
            title: "EventStreamReady".to_string(),
            message: "Event stream subscription is active".to_string(),
            level: "debug".to_string(),
        }),
    )) {
        tracing::warn!("[API_EVENT_STREAM] Failed to send ready signal: {}", err);
        return Ok(());
    }
    tracing::info!("[API_EVENT_STREAM] Sent ready signal to Dart");

    loop {
        match rx.recv().await {
            Ok(event) => {
                tracing::debug!(
                    "[API_EVENT_STREAM] Forwarding event to Dart: {:?}",
                    std::mem::discriminant(&event.payload)
                );
                if let Err(err) = sink.add(event) {
                    tracing::warn!("[API_EVENT_STREAM] Failed to send event to Dart: {}", err);
                    break;
                }
            }
            Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                // Update the global dropped event counter
                let previous_total = TOTAL_DROPPED_EVENTS.fetch_add(n, Ordering::Relaxed);
                let new_total = previous_total + n;

                tracing::warn!(
                    "[API_EVENT_STREAM] Event stream lagged! Skipped {} events (total dropped: {}). \
                    Consider increasing DEFAULT_EVENT_BUFFER_SIZE or optimizing Dart event handling.",
                    n, new_total
                );

                // Send a notification to Dart so it knows events were dropped
                // This allows the UI to refresh its state from the source of truth
                if let Err(err) = sink.add(create_event_auto_id(
                    EventSeverity::Warning,
                    EventCategory::System,
                    EventPayload::System(SystemEvent::EventsDropped {
                        dropped_count: n,
                        total_dropped: new_total,
                    }),
                )) {
                    tracing::warn!(
                        "[API_EVENT_STREAM] Failed to send dropped-events notice: {}",
                        err
                    );
                    break;
                }
            }
            Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                tracing::info!("[API_EVENT_STREAM] Event bus closed, stopping stream");
                break;
            }
        }
    }

    Ok(())
}

/// Get the total number of events dropped since app start.
/// Useful for diagnostics and monitoring event stream health.
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_dropped_event_count() -> u64 {
    TOTAL_DROPPED_EVENTS.load(Ordering::Relaxed)
}

// =============================================================================
// Device Discovery - ASCOM and ALPACA IMPLEMENTATION
// =============================================================================

/// Discover available Alpaca devices on the network
pub async fn api_discover_alpaca_devices() -> Result<Vec<DeviceInfo>, NightshadeError> {
    use nightshade_alpaca::{discover_all_devices, AlpacaDeviceType};
    use std::time::Duration;

    tracing::debug!("Discovering Alpaca devices on network...");

    let alpaca_devices = discover_all_devices(Duration::from_secs(3)).await;

    let mut devices = Vec::new();
    for alpaca_dev in alpaca_devices {
        let device_type = match alpaca_dev.device_type {
            AlpacaDeviceType::Camera => DeviceType::Camera,
            AlpacaDeviceType::Telescope => DeviceType::Mount,
            AlpacaDeviceType::Focuser => DeviceType::Focuser,
            AlpacaDeviceType::FilterWheel => DeviceType::FilterWheel,
            AlpacaDeviceType::Rotator => DeviceType::Rotator,
            AlpacaDeviceType::Dome => DeviceType::Dome,
            AlpacaDeviceType::SafetyMonitor => DeviceType::SafetyMonitor,
            AlpacaDeviceType::ObservingConditions => DeviceType::Weather,
            AlpacaDeviceType::Switch => DeviceType::Switch,
            AlpacaDeviceType::CoverCalibrator => DeviceType::CoverCalibrator,
        };

        tracing::debug!(
            "Found Alpaca device: {} at {} (unique_id: {})",
            alpaca_dev.device_name,
            alpaca_dev.base_url,
            alpaca_dev.unique_id
        );

        // Generate display name using unique_id for disambiguation
        let unique_id = if alpaca_dev.unique_id.is_empty() {
            None
        } else {
            Some(alpaca_dev.unique_id.clone())
        };
        let display_name = DeviceInfo::generate_display_name(
            &alpaca_dev.device_name,
            None, // No serial number from Alpaca
            unique_id.as_deref(),
            None, // No index needed
        );

        devices.push(DeviceInfo {
            id: alpaca_dev.id(),
            name: alpaca_dev.device_name.clone(),
            device_type,
            driver_type: DriverType::Alpaca,
            description: format!("Alpaca device at {}", alpaca_dev.base_url),
            driver_version: "Alpaca".to_string(),
            serial_number: None,
            unique_id,
            display_name,
        });
    }

    tracing::debug!("Found {} Alpaca devices", devices.len());
    Ok(devices)
}

/// Discover Alpaca devices at a specific server address
pub async fn api_discover_alpaca_at_address(
    host: String,
    port: u16,
) -> Result<Vec<DeviceInfo>, NightshadeError> {
    use nightshade_alpaca::{get_configured_devices, AlpacaDeviceType};

    tracing::debug!("Discovering Alpaca devices at {}:{}", host, port);

    let alpaca_devices = get_configured_devices(&host, port).await.map_err(|e| {
        NightshadeError::connection_failed(
            format!("{}:{}", host, port),
            format!("Failed to connect to Alpaca server: {}", e),
        )
    })?;

    let mut devices = Vec::new();
    for alpaca_dev in alpaca_devices {
        let device_type = match alpaca_dev.device_type {
            AlpacaDeviceType::Camera => DeviceType::Camera,
            AlpacaDeviceType::Telescope => DeviceType::Mount,
            AlpacaDeviceType::Focuser => DeviceType::Focuser,
            AlpacaDeviceType::FilterWheel => DeviceType::FilterWheel,
            AlpacaDeviceType::Rotator => DeviceType::Rotator,
            AlpacaDeviceType::Dome => DeviceType::Dome,
            AlpacaDeviceType::SafetyMonitor => DeviceType::SafetyMonitor,
            AlpacaDeviceType::ObservingConditions => DeviceType::Weather,
            AlpacaDeviceType::Switch => DeviceType::Switch,
            AlpacaDeviceType::CoverCalibrator => DeviceType::CoverCalibrator,
        };

        // Generate display name using unique_id for disambiguation
        let unique_id = if alpaca_dev.unique_id.is_empty() {
            None
        } else {
            Some(alpaca_dev.unique_id.clone())
        };
        let display_name = DeviceInfo::generate_display_name(
            &alpaca_dev.device_name,
            None,
            unique_id.as_deref(),
            None,
        );

        devices.push(DeviceInfo {
            id: alpaca_dev.id(),
            name: alpaca_dev.device_name.clone(),
            device_type,
            driver_type: DriverType::Alpaca,
            description: format!("Alpaca device at {}", alpaca_dev.base_url),
            driver_version: "Alpaca".to_string(),
            serial_number: None,
            unique_id,
            display_name,
        });
    }

    Ok(devices)
}

/// Discover INDI devices at a specific server address
pub async fn api_discover_indi_at_address(
    host: String,
    port: u16,
) -> Result<Vec<DeviceInfo>, NightshadeError> {
    tracing::debug!("Discovering INDI devices at {}:{}", host, port);

    get_device_manager()
        .discover_indi_devices(&host, port)
        .await
        .map_err(|e| {
            NightshadeError::connection_failed(
                format!("{}:{}", host, port),
                format!("Failed to connect to INDI server: {}", e),
            )
        })
}

async fn query_indi_device_serial_from_client(
    client: &nightshade_indi::IndiClient,
    device_name: &str,
) -> Option<String> {
    const SERIAL_CANDIDATES: [(&str, &str); 8] = [
        ("DEVICE_INFO", "DEVICE_SERIAL"),
        ("DEVICE_INFO", "SERIAL"),
        ("EQUIPMENT_INFO", "SERIAL"),
        ("DRIVER_INFO", "SERIAL"),
        ("INFO", "SERIAL"),
        ("DEVICE", "SERIAL"),
        ("DEVICE_INFO", "SN"),
        ("INFO", "SN"),
    ];

    for (property, element) in SERIAL_CANDIDATES {
        if let Some(value) = client
            .get_property_value(device_name, property, element)
            .await
        {
            let trimmed = value.trim();
            if !trimmed.is_empty() {
                return Some(trimmed.to_string());
            }
        }
    }

    let properties = client.get_properties(device_name).await;
    for property in properties {
        let property_upper = property.name.to_uppercase();
        if !(property_upper.contains("INFO") || property_upper.contains("DEVICE")) {
            continue;
        }

        for element in property.elements {
            let element_upper = element.to_uppercase();
            if element_upper.contains("SERIAL") || element_upper == "SN" {
                if let Some(value) = client
                    .get_property_value(device_name, &property.name, &element)
                    .await
                {
                    let trimmed = value.trim();
                    if !trimmed.is_empty() {
                        return Some(trimmed.to_string());
                    }
                }
            }
        }
    }

    None
}

async fn query_indi_serials_for_server(
    host: &str,
    port: u16,
    device_names: &[String],
) -> HashMap<String, String> {
    let mut serials = HashMap::new();
    let mut client = nightshade_indi::IndiClient::new(host, Some(port));

    let mut timeout_config = client.timeout_config().clone();
    timeout_config.connection_timeout_secs = 3;
    timeout_config.property_timeout_secs = 2;
    timeout_config.message_timeout_secs = 5;
    client.set_timeout_config(timeout_config);

    if let Err(e) = client.connect().await {
        tracing::debug!(
            "Unable to query INDI serials from {}:{} ({}). Continuing without serial metadata.",
            host,
            port,
            e
        );
        return serials;
    }

    tokio::time::sleep(Duration::from_millis(500)).await;

    for device_name in device_names {
        if let Some(serial) = query_indi_device_serial_from_client(&client, device_name).await {
            serials.insert(device_name.clone(), serial);
        }
    }

    if let Err(e) = client.disconnect().await {
        tracing::debug!(
            "INDI serial query disconnect warning for {}:{}: {}",
            host,
            port,
            e
        );
    }

    serials
}

/// Auto-discover INDI servers on localhost
pub async fn api_discover_indi_localhost() -> Result<Vec<DeviceInfo>, NightshadeError> {
    use nightshade_indi::{discover_localhost, IndiDeviceType as IndiType};

    tracing::debug!("Auto-discovering INDI servers on localhost...");

    let mut all_devices = Vec::new();

    if let Some(server) = discover_localhost().await {
        tracing::debug!(
            "Found INDI server at {}:{} with {} devices",
            server.host,
            server.port,
            server.devices.len()
        );
        let device_names = server
            .devices
            .iter()
            .map(|d| d.name.clone())
            .collect::<Vec<_>>();
        let serials = query_indi_serials_for_server(&server.host, server.port, &device_names).await;

        for device in server.devices {
            let device_type = match device.device_type {
                IndiType::Camera => DeviceType::Camera,
                IndiType::Telescope => DeviceType::Mount,
                IndiType::Focuser => DeviceType::Focuser,
                IndiType::FilterWheel => DeviceType::FilterWheel,
                IndiType::Dome => DeviceType::Dome,
                IndiType::Rotator => DeviceType::Rotator,
                IndiType::Guider => DeviceType::Guider,
                IndiType::Weather => DeviceType::Weather,
                IndiType::SafetyMonitor => DeviceType::SafetyMonitor,
                IndiType::CoverCalibrator => DeviceType::CoverCalibrator,
                IndiType::Unknown => continue,
            };

            let device_id = format!("indi:{}:{}:{}", server.host, server.port, device.name);
            let serial_number = serials.get(&device.name).cloned();
            let unique_id = serial_number.clone();

            all_devices.push(DeviceInfo {
                id: device_id,
                name: device.name.clone(),
                device_type,
                driver_type: DriverType::Indi,
                description: format!("INDI device at {}:{}", server.host, server.port),
                driver_version: "INDI".to_string(),
                serial_number,
                unique_id,
                display_name: device.name.clone(),
            });
        }
    }

    tracing::debug!("Found {} INDI devices on localhost", all_devices.len());
    Ok(all_devices)
}

/// Auto-discover INDI servers on common hostnames (localhost, raspberrypi, stellarmate, etc.)
pub async fn api_discover_indi_common_hosts() -> Result<Vec<DeviceInfo>, NightshadeError> {
    use nightshade_indi::{discover_common_hosts, IndiDeviceType as IndiType};

    tracing::debug!("Auto-discovering INDI servers on common hosts...");

    let mut all_devices = Vec::new();
    let servers = discover_common_hosts().await;

    tracing::debug!("Found {} INDI servers on common hosts", servers.len());

    for server in servers {
        let device_names = server
            .devices
            .iter()
            .map(|d| d.name.clone())
            .collect::<Vec<_>>();
        let serials = query_indi_serials_for_server(&server.host, server.port, &device_names).await;
        for device in server.devices {
            let device_type = match device.device_type {
                IndiType::Camera => DeviceType::Camera,
                IndiType::Telescope => DeviceType::Mount,
                IndiType::Focuser => DeviceType::Focuser,
                IndiType::FilterWheel => DeviceType::FilterWheel,
                IndiType::Dome => DeviceType::Dome,
                IndiType::Rotator => DeviceType::Rotator,
                IndiType::Guider => DeviceType::Guider,
                IndiType::Weather => DeviceType::Weather,
                IndiType::SafetyMonitor => DeviceType::SafetyMonitor,
                IndiType::CoverCalibrator => DeviceType::CoverCalibrator,
                IndiType::Unknown => continue,
            };

            let device_id = format!("indi:{}:{}:{}", server.host, server.port, device.name);
            let serial_number = serials.get(&device.name).cloned();
            let unique_id = serial_number.clone();

            all_devices.push(DeviceInfo {
                id: device_id,
                name: device.name.clone(),
                device_type,
                driver_type: DriverType::Indi,
                description: format!("INDI device at {}:{}", server.host, server.port),
                driver_version: "INDI".to_string(),
                serial_number,
                unique_id,
                display_name: device.name.clone(),
            });
        }
    }

    tracing::debug!("Found {} INDI devices total", all_devices.len());
    Ok(all_devices)
}

/// Auto-discover INDI servers on the local network (scans subnet)
pub async fn api_discover_indi_network() -> Result<Vec<DeviceInfo>, NightshadeError> {
    use nightshade_indi::{discover_local_network, IndiDeviceType as IndiType};
    use std::time::Duration;

    tracing::debug!("Scanning local network for INDI servers...");

    let mut all_devices = Vec::new();
    let servers = discover_local_network(Duration::from_millis(200)).await;

    tracing::debug!("Found {} INDI servers on local network", servers.len());

    for server in servers {
        let device_names = server
            .devices
            .iter()
            .map(|d| d.name.clone())
            .collect::<Vec<_>>();
        let serials = query_indi_serials_for_server(&server.host, server.port, &device_names).await;
        for device in server.devices {
            let device_type = match device.device_type {
                IndiType::Camera => DeviceType::Camera,
                IndiType::Telescope => DeviceType::Mount,
                IndiType::Focuser => DeviceType::Focuser,
                IndiType::FilterWheel => DeviceType::FilterWheel,
                IndiType::Dome => DeviceType::Dome,
                IndiType::Rotator => DeviceType::Rotator,
                IndiType::Guider => DeviceType::Guider,
                IndiType::Weather => DeviceType::Weather,
                IndiType::SafetyMonitor => DeviceType::SafetyMonitor,
                IndiType::CoverCalibrator => DeviceType::CoverCalibrator,
                IndiType::Unknown => continue,
            };

            let device_id = format!("indi:{}:{}:{}", server.host, server.port, device.name);
            let serial_number = serials.get(&device.name).cloned();
            let unique_id = serial_number.clone();

            all_devices.push(DeviceInfo {
                id: device_id,
                name: device.name.clone(),
                device_type,
                driver_type: DriverType::Indi,
                description: format!("INDI device at {}:{}", server.host, server.port),
                driver_version: "INDI".to_string(),
                serial_number,
                unique_id,
                display_name: device.name.clone(),
            });
        }
    }

    tracing::debug!("Found {} INDI devices on network", all_devices.len());
    Ok(all_devices)
}

/// Discover available devices of a specific type.
/// Queries Windows-only ASCOM COM drivers, Alpaca network devices or bridges,
/// Native SDK paths bundled for the current release, simulator paths where
/// enabled, and reachable INDI servers. All results are cached for 60 seconds -- the FIRST call to this
/// function runs full discovery for every source and every device type, and subsequent
/// calls within the TTL simply filter the cached results by the requested `device_type`.
pub async fn api_discover_devices(
    device_type: DeviceType,
) -> Result<Vec<DeviceInfo>, NightshadeError> {
    tracing::debug!("Discovering {} devices", device_type.as_str());

    // =====================================================
    // CHECK UNIFIED CACHE
    // =====================================================
    {
        let cache = get_discovery_cache().lock().await;
        if let Some(ref cached) = *cache {
            if cached.timestamp.elapsed() < DISCOVERY_CACHE_TTL {
                tracing::debug!(
                    "Using cached discovery results ({} total devices, {:.1}s old)",
                    cached.all_devices.len(),
                    cached.timestamp.elapsed().as_secs_f32()
                );
                let filtered: Vec<DeviceInfo> = cached
                    .all_devices
                    .iter()
                    .filter(|d| d.device_type == device_type)
                    .cloned()
                    .collect();
                return Ok(filtered);
            }
        }
    }

    // =====================================================
    // ACQUIRE LOCK & DOUBLE-CHECK CACHE
    // =====================================================
    let mut in_progress = get_discovery_lock().lock().await;

    // Another concurrent caller may have populated the cache while we waited
    {
        let cache = get_discovery_cache().lock().await;
        if let Some(ref cached) = *cache {
            if cached.timestamp.elapsed() < DISCOVERY_CACHE_TTL {
                let filtered: Vec<DeviceInfo> = cached
                    .all_devices
                    .iter()
                    .filter(|d| d.device_type == device_type)
                    .cloned()
                    .collect();
                return Ok(filtered);
            }
        }
    }

    // =====================================================
    // RUN FULL DISCOVERY (all sources, all types)
    // =====================================================
    *in_progress = true;
    let mut all_devices: Vec<DeviceInfo> = Vec::new();

    let mut ascom_count: usize = 0;
    let mut alpaca_count: usize = 0;
    let mut native_count: usize = 0;
    let mut indi_count: usize = 0;

    // ----- ASCOM discovery (Windows only) -----
    #[cfg(windows)]
    {
        use nightshade_ascom::{discover_devices as ascom_discover, AscomDeviceType};

        let ascom_types = [
            (AscomDeviceType::Camera, DeviceType::Camera),
            (AscomDeviceType::Telescope, DeviceType::Mount),
            (AscomDeviceType::Focuser, DeviceType::Focuser),
            (AscomDeviceType::FilterWheel, DeviceType::FilterWheel),
            (AscomDeviceType::Rotator, DeviceType::Rotator),
            (AscomDeviceType::Dome, DeviceType::Dome),
            (AscomDeviceType::ObservingConditions, DeviceType::Weather),
            (AscomDeviceType::SafetyMonitor, DeviceType::SafetyMonitor),
            (
                AscomDeviceType::CoverCalibrator,
                DeviceType::CoverCalibrator,
            ),
        ];

        for (ascom_type, dev_type) in ascom_types {
            let ascom_devs = ascom_discover(ascom_type);
            for ascom_dev in ascom_devs {
                let prog_id_lower = ascom_dev.prog_id.to_lowercase();
                let name_lower = ascom_dev.name.to_lowercase();

                // Filter out simulators and diagnostic tools
                let is_simulator = prog_id_lower.contains("simulator")
                    || name_lower.contains("simulator")
                    || prog_id_lower.contains("sim.")
                    || prog_id_lower.ends_with("sim")
                    || prog_id_lower.starts_with("ccdsim")
                    || prog_id_lower.starts_with("scopesim")
                    || prog_id_lower.starts_with("focussim")
                    || prog_id_lower.starts_with("domesim")
                    || prog_id_lower.starts_with("filterwheelsim")
                    || name_lower == "simulator";

                let is_diagnostic = prog_id_lower.contains("hub.")
                    || prog_id_lower.contains("pipe.")
                    || prog_id_lower.contains("poth.")
                    || prog_id_lower.starts_with("hub.")
                    || prog_id_lower.starts_with("pipe.")
                    || prog_id_lower.starts_with("poth.");

                if is_simulator || is_diagnostic {
                    tracing::trace!(
                        "Filtering out ASCOM device: {} ({})",
                        ascom_dev.name,
                        ascom_dev.prog_id
                    );
                    continue;
                }
                all_devices.push(DeviceInfo {
                    id: format!("ascom:{}", ascom_dev.prog_id),
                    name: ascom_dev.name.clone(),
                    device_type: dev_type,
                    driver_type: DriverType::Ascom,
                    description: ascom_dev.description,
                    driver_version: "ASCOM".to_string(),
                    serial_number: None,
                    unique_id: None,
                    display_name: ascom_dev.name.clone(),
                });
                ascom_count += 1;
            }
        }
    }

    // ----- Alpaca discovery -----
    {
        use nightshade_alpaca::{discover_all_devices, AlpacaDeviceType};

        let alpaca_devs = discover_all_devices(Duration::from_secs(2)).await;
        for alpaca_dev in alpaca_devs {
            let dev_type = match alpaca_dev.device_type {
                AlpacaDeviceType::Camera => DeviceType::Camera,
                AlpacaDeviceType::Telescope => DeviceType::Mount,
                AlpacaDeviceType::Focuser => DeviceType::Focuser,
                AlpacaDeviceType::FilterWheel => DeviceType::FilterWheel,
                AlpacaDeviceType::Rotator => DeviceType::Rotator,
                AlpacaDeviceType::Dome => DeviceType::Dome,
                AlpacaDeviceType::SafetyMonitor => DeviceType::SafetyMonitor,
                AlpacaDeviceType::ObservingConditions => DeviceType::Weather,
                AlpacaDeviceType::CoverCalibrator => DeviceType::CoverCalibrator,
                _ => continue,
            };

            let unique_id = if alpaca_dev.unique_id.is_empty() {
                None
            } else {
                Some(alpaca_dev.unique_id.clone())
            };
            let display_name = DeviceInfo::generate_display_name(
                &alpaca_dev.device_name,
                None,
                unique_id.as_deref(),
                None,
            );

            all_devices.push(DeviceInfo {
                id: alpaca_dev.id(),
                name: alpaca_dev.device_name.clone(),
                device_type: dev_type,
                driver_type: DriverType::Alpaca,
                description: format!("Alpaca device at {}", alpaca_dev.base_url),
                driver_version: "Alpaca".to_string(),
                serial_number: None,
                unique_id,
                display_name,
            });
            alpaca_count += 1;
        }
    }

    // ----- Native vendor SDK discovery -----
    {
        use nightshade_native::discover_all_devices as native_discover_all;

        if let Ok(native_devices) = native_discover_all().await {
            for native_dev in native_devices {
                let dev_type = match native_dev.device_type {
                    nightshade_native::DeviceType::Camera => DeviceType::Camera,
                    nightshade_native::DeviceType::Mount => DeviceType::Mount,
                    nightshade_native::DeviceType::Focuser => DeviceType::Focuser,
                    nightshade_native::DeviceType::FilterWheel => DeviceType::FilterWheel,
                    nightshade_native::DeviceType::Rotator => DeviceType::Rotator,
                };
                tracing::debug!(
                    "Found native device: {} ({})",
                    native_dev.display_name,
                    native_dev.vendor.as_str()
                );
                all_devices.push(DeviceInfo {
                    id: native_dev.id,
                    name: native_dev.name.clone(),
                    device_type: dev_type,
                    driver_type: DriverType::Native,
                    description: format!("{} native driver", native_dev.vendor.as_str()),
                    driver_version: native_dev
                        .sdk_version
                        .unwrap_or_else(|| "Native".to_string()),
                    serial_number: native_dev.serial_number,
                    unique_id: None,
                    display_name: native_dev.display_name,
                });
                native_count += 1;
            }
        }
    }

    // ----- INDI discovery -----
    {
        let indi_devices = get_device_manager().get_all_indi_devices().await;
        for dev in indi_devices {
            tracing::debug!("Found INDI device: {} ({:?})", dev.name, dev.device_type);
            indi_count += 1;
            all_devices.push(dev);
        }
    }

    // ----- Built-in Guider (always available) -----
    all_devices.push(DeviceInfo {
        id: crate::builtin_guider::device_id().to_string(),
        name: "Built-in Multi-Star Guider".to_string(),
        device_type: DeviceType::Guider,
        driver_type: DriverType::Native,
        description: "Software guider using Nightshade star tracking and mount pulse guide"
            .to_string(),
        driver_version: "Nightshade".to_string(),
        serial_number: None,
        unique_id: Some("builtin_multi_star_guider".to_string()),
        display_name: "Built-in Multi-Star Guider".to_string(),
    });

    // ----- PHD2 discovery -----
    {
        let is_running = nightshade_imaging::is_phd2_running();
        let is_installed = nightshade_imaging::is_phd2_installed();

        if is_running || is_installed {
            tracing::debug!(
                "Found PHD2 Guiding (Running: {}, Installed: {})",
                is_running,
                is_installed
            );
            all_devices.push(DeviceInfo {
                id: "phd2_guider".to_string(),
                name: "PHD2 Guiding".to_string(),
                device_type: DeviceType::Guider,
                driver_type: DriverType::Native,
                description: if is_running {
                    "PHD2 Guiding (Running)"
                } else {
                    "PHD2 Guiding (Installed)"
                }
                .to_string(),
                driver_version: "PHD2".to_string(),
                serial_number: None,
                unique_id: None,
                display_name: "PHD2 Guiding".to_string(),
            });
        }
    }

    // ----- Simulator (always available) -----
    all_devices.push(DeviceInfo {
        id: "sim_camera_1".to_string(),
        name: "Simulated Camera".to_string(),
        device_type: DeviceType::Camera,
        driver_type: DriverType::Simulator,
        description: "Internal Simulator".to_string(),
        driver_version: "1.0.0".to_string(),
        serial_number: Some("SIM-123".to_string()),
        unique_id: Some("sim_camera_1".to_string()),
        display_name: "Simulated Camera".to_string(),
    });

    // ----- Summary log line -----
    tracing::info!(
        "Discovery complete: {} ASCOM, {} Alpaca, {} Native, {} INDI devices",
        ascom_count,
        alpaca_count,
        native_count,
        indi_count
    );

    // ----- Cache ALL results -----
    {
        let mut cache = get_discovery_cache().lock().await;
        *cache = Some(DiscoveryCache {
            all_devices: all_devices.clone(),
            timestamp: Instant::now(),
        });
    }

    *in_progress = false;

    // Filter by requested device type
    let filtered: Vec<DeviceInfo> = all_devices
        .into_iter()
        .filter(|d| d.device_type == device_type)
        .collect();

    Ok(filtered)
}

// =============================================================================
// Device Connection
// =============================================================================

/// Try to construct a DeviceInfo from a device ID string without running discovery.
/// This avoids opening/closing hardware (e.g. ZWO EFW) which can interfere with
/// subsequent position reads.
fn device_info_from_id(device_id: &str, device_type: DeviceType) -> Option<DeviceInfo> {
    if device_id.starts_with("native:") {
        let parts: Vec<&str> = device_id.split(':').collect();
        if parts.len() >= 3 {
            let vendor = parts[1];
            let name = match vendor {
                "builtin_guider" => "Built-in Multi-Star Guider".to_string(),
                "zwo" => format!("ZWO Camera {}", parts[2]),
                "zwo_eaf" => format!("ZWO EAF {}", parts[2]),
                "zwo_efw" => format!("ZWO EFW {}", parts[2]),
                "qhy" => format!("QHY {}", parts[2]),
                "qhy_cfw" => format!("QHY CFW ({})", parts[2]),
                "fli" | "fli_fw" | "fli_focuser" => format!("FLI {}", parts[2]),
                "player_one" | "playerone" => format!("Player One {}", parts[2]),
                "svbony" => format!("SVBony {}", parts[2]),
                "atik" => format!("Atik {}", parts[2]),
                "moravian" => format!("Moravian {}", parts[2]),
                "touptek" => format!("Touptek {}", parts.get(2).unwrap_or(&"")),
                _ => format!("{} {}", vendor, parts[2]),
            };
            return Some(DeviceInfo {
                id: device_id.to_string(),
                name: name.clone(),
                device_type,
                driver_type: DriverType::Native,
                description: format!("Native {} driver", vendor),
                driver_version: "Native".to_string(),
                serial_number: None,
                unique_id: None,
                display_name: name,
            });
        }
    } else if device_id.starts_with("ascom:") {
        let prog_id = &device_id[6..]; // strip "ascom:"
        let name = prog_id.split('.').skip(1).collect::<Vec<_>>().join(" ");
        let name = if name.is_empty() {
            prog_id.to_string()
        } else {
            name
        };
        return Some(DeviceInfo {
            id: device_id.to_string(),
            name: name.clone(),
            device_type,
            driver_type: DriverType::Ascom,
            description: format!("ASCOM driver: {}", prog_id),
            driver_version: "ASCOM".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: name,
        });
    } else if device_id.starts_with("alpaca:") {
        return Some(DeviceInfo {
            id: device_id.to_string(),
            name: "Alpaca Device".to_string(),
            device_type,
            driver_type: DriverType::Alpaca,
            description: "Alpaca device".to_string(),
            driver_version: "Alpaca".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: "Alpaca Device".to_string(),
        });
    } else if device_id.starts_with("indi:") {
        let parts: Vec<&str> = device_id.split(':').collect();
        let name = if parts.len() >= 4 {
            parts[3..].join(":")
        } else {
            device_id.to_string()
        };
        return Some(DeviceInfo {
            id: device_id.to_string(),
            name: name.clone(),
            device_type,
            driver_type: DriverType::Indi,
            description: "INDI device".to_string(),
            driver_version: "INDI".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: name,
        });
    }
    None
}

/// Connect to a device
pub async fn api_connect_device(
    device_type: DeviceType,
    device_id: String,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Connecting to {} device: {}",
        device_type.as_str(),
        device_id
    );

    tracing::info!(
        "Connecting to {} device: {}",
        device_type.as_str(),
        device_id
    );

    // Special handling for PHD2 auto-launch
    if is_phd2_device_id(&device_id) {
        if !nightshade_imaging::is_phd2_running() {
            tracing::info!("PHD2 not running, attempting to launch...");
            if let Err(e) = nightshade_imaging::launch_phd2() {
                tracing::error!("Failed to launch PHD2: {}", e);
                return Err(NightshadeError::connection_failed(
                    &device_id,
                    format!("Failed to launch PHD2: {}", e),
                ));
            }

            // Wait for it to start
            tracing::info!("Waiting for PHD2 to start...");
            let mut started = false;
            for _ in 0..20 {
                // Wait up to 10 seconds
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                if nightshade_imaging::is_phd2_running() {
                    started = true;
                    break;
                }
            }

            if !started {
                return Err(NightshadeError::connection_failed(
                    &device_id,
                    "Timed out waiting for PHD2 to start",
                ));
            }
        }
    }

    // Check if device is registered in DeviceManager, if not, discover and register it
    let device_manager = get_device_manager();

    // Check if device is already registered
    let is_registered = device_manager.is_device_registered(&device_id).await;

    // If not registered, register it so the DeviceManager can connect.
    // Try to construct DeviceInfo from the device ID first (avoids running
    // native discovery which opens/closes hardware and can interfere with
    // subsequent position reads on filter wheels).
    if !is_registered {
        tracing::info!("Device {} not registered, registering...", device_id);

        let device_info = device_info_from_id(&device_id, device_type.clone());
        if let Some(info) = device_info {
            device_manager.register_device(info.clone(), false).await;
            tracing::info!("Registered device from ID: {} ({})", info.name, device_id);
        } else {
            // Fallback: run full discovery to find the device
            tracing::info!(
                "Could not construct DeviceInfo from ID, running discovery for {}",
                device_id
            );
            let discovered_devices = api_discover_devices(device_type.clone()).await?;
            if let Some(info) = discovered_devices.iter().find(|d| d.id == device_id) {
                device_manager.register_device(info.clone(), false).await;
                tracing::info!(
                    "Registered device via discovery: {} ({})",
                    info.name,
                    device_id
                );
            } else {
                return Err(NightshadeError::connection_failed(
                    &device_id,
                    "Device not found during discovery",
                ));
            }
        }
    }

    // Use the DeviceManager to handle the connection
    device_manager
        .connect_device(&device_id)
        .await
        .map_err(|e| NightshadeError::connection_failed(&device_id, e))
}

fn is_phd2_device_id(device_id: &str) -> bool {
    device_id == "phd2_guider"
        || device_id == "phd2"
        || device_id.starts_with("phd2:")
        || device_id.starts_with("phd2://")
}

/// Get the display name for a device that's already registered in the device manager.
/// Returns None if the device isn't registered.
/// This avoids running a full discovery just to resolve a device name.
pub async fn api_get_device_display_name(device_id: String) -> Option<String> {
    get_device_manager()
        .get_device_display_name(&device_id)
        .await
}

/// Disconnect from a device
pub async fn api_disconnect_device(
    device_type: DeviceType,
    device_id: String,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Disconnecting from {} device: {}",
        device_type.as_str(),
        device_id
    );

    tracing::info!(
        "Disconnecting from {} device: {}",
        device_type.as_str(),
        device_id
    );

    // Use the DeviceManager to handle disconnection
    get_device_manager()
        .disconnect_device(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Check if a device is connected
pub async fn api_is_device_connected(device_type: DeviceType, device_id: String) -> bool {
    get_state()
        .is_device_connected(device_type, &device_id)
        .await
}

/// Get list of connected devices
pub async fn api_get_connected_devices() -> Vec<DeviceInfo> {
    let state = get_state();
    let mut devices = Vec::new();

    for device_type in [
        DeviceType::Camera,
        DeviceType::Mount,
        DeviceType::Focuser,
        DeviceType::FilterWheel,
        DeviceType::Guider,
        DeviceType::Rotator,
        DeviceType::Dome,
        DeviceType::Weather,
    ] {
        devices.extend(state.get_devices(device_type).await);
    }

    devices
}

// =============================================================================
// Device Heartbeat Monitoring
// =============================================================================

/// Start heartbeat monitoring for a device
///
/// This will poll the device status at the specified interval and emit
/// a Disconnected event if the device becomes unresponsive.
///
/// # Arguments
/// * `device_type` - The type of device to monitor (used for validation)
/// * `device_id` - The unique identifier for the device
/// * `interval_ms` - Heartbeat interval in milliseconds (recommended: 10000)
pub async fn api_start_device_heartbeat(
    device_type: DeviceType,
    device_id: String,
    interval_ms: u64,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Starting heartbeat monitoring for {} device: {} (interval: {}ms)",
        device_type.as_str(),
        device_id,
        interval_ms
    );

    // Validate device type matches
    if let Some(device) = get_device_manager().get_device(&device_id).await {
        if device.info.device_type != device_type {
            return Err(NightshadeError::InvalidParameter(format!(
                "Device {} is type {:?}, not {:?}",
                device_id, device.info.device_type, device_type
            )));
        }
    }

    get_device_manager()
        .start_heartbeat(&device_id, std::time::Duration::from_millis(interval_ms))
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Stop heartbeat monitoring for a device
///
/// # Arguments
/// * `device_id` - The unique identifier for the device
pub async fn api_stop_device_heartbeat(device_id: String) -> Result<(), NightshadeError> {
    tracing::info!("Stopping heartbeat monitoring for device: {}", device_id);

    get_device_manager()
        .stop_heartbeat(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Start heartbeat monitoring with custom configuration
///
/// This allows full control over the heartbeat behavior including:
/// - Check interval and maximum interval after backoff
/// - Number of failures before marking device as disconnected
/// - Whether to attempt auto-reconnection
/// - Reconnection attempt limits and delays
///
/// # Arguments
/// * `device_id` - The unique identifier for the device
/// * `interval_secs` - Base interval between heartbeats in seconds
/// * `failure_threshold` - Number of consecutive failures before disconnect
/// * `auto_reconnect` - Whether to attempt automatic reconnection
/// * `max_reconnect_attempts` - Maximum reconnection attempts (0 = unlimited)
pub async fn api_start_device_heartbeat_with_config(
    device_id: String,
    interval_secs: u64,
    failure_threshold: u32,
    auto_reconnect: bool,
    max_reconnect_attempts: u32,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Starting heartbeat with config for device: {} (interval={}s, threshold={}, auto_reconnect={}, max_attempts={})",
        device_id,
        interval_secs,
        failure_threshold,
        auto_reconnect,
        max_reconnect_attempts
    );

    let config = crate::devices::HeartbeatConfig {
        base_interval_secs: interval_secs,
        max_interval_secs: interval_secs * 6, // 6x base for max backoff
        failure_threshold,
        backoff_multiplier: 2.0,
        auto_reconnect,
        max_reconnect_attempts,
        reconnect_delay_secs: 5,
    };

    get_device_manager()
        .start_heartbeat_with_config(&device_id, config)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get the default heartbeat configuration for a device type
///
/// Returns the recommended heartbeat settings for the specified device type.
/// Different device types have different optimal configurations based on
/// their operational characteristics.
///
/// # Arguments
/// * `device_type` - The type of device to get configuration for
///
/// # Returns
/// A tuple of (interval_secs, max_interval_secs, failure_threshold, auto_reconnect)
pub fn api_get_heartbeat_config_for_type(device_type: DeviceType) -> (u64, u64, u32, bool) {
    let config = match device_type {
        DeviceType::Camera => crate::devices::HeartbeatConfig::for_camera(),
        DeviceType::Mount => crate::devices::HeartbeatConfig::for_mount(),
        DeviceType::Focuser => crate::devices::HeartbeatConfig::for_focuser(),
        DeviceType::FilterWheel => crate::devices::HeartbeatConfig::for_filter_wheel(),
        DeviceType::Dome => crate::devices::HeartbeatConfig::for_dome(),
        DeviceType::Rotator => crate::devices::HeartbeatConfig::for_rotator(),
        DeviceType::Weather => crate::devices::HeartbeatConfig::for_weather(),
        DeviceType::SafetyMonitor => crate::devices::HeartbeatConfig::for_safety_monitor(),
        _ => crate::devices::HeartbeatConfig::default(),
    };

    (
        config.base_interval_secs,
        config.max_interval_secs,
        config.failure_threshold,
        config.auto_reconnect,
    )
}

/// Check device health status
///
/// Returns the last successful communication timestamp and whether
/// the device is currently responding to heartbeat checks.
///
/// # Arguments
/// * `device_id` - The unique identifier for the device
///
/// # Returns
/// A tuple of (last_successful_timestamp_ms, is_healthy)
pub async fn api_get_device_health(device_id: String) -> Result<(i64, bool), NightshadeError> {
    get_device_manager()
        .get_device_health(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Detailed heartbeat status for a device
#[derive(Debug, Clone)]
#[flutter_rust_bridge::frb]
pub struct DeviceHeartbeatInfo {
    /// Device ID
    pub device_id: String,
    /// Device type (e.g., "Camera", "Mount")
    pub device_type: String,
    /// Whether heartbeat monitoring is currently active
    pub heartbeat_active: bool,
    /// Last successful communication timestamp (milliseconds since epoch)
    pub last_successful_comm_ms: Option<i64>,
    /// Current heartbeat interval in seconds
    pub interval_secs: u64,
    /// Maximum interval after backoff in seconds
    pub max_interval_secs: u64,
    /// Number of failures before marking disconnected
    pub failure_threshold: u32,
    /// Whether auto-reconnect is enabled
    pub auto_reconnect: bool,
    /// Maximum reconnection attempts (0 = unlimited)
    pub max_reconnect_attempts: u32,
}

/// Get detailed heartbeat status for a device
///
/// Returns comprehensive information about the heartbeat monitoring status
/// including configuration, last successful communication, and whether
/// monitoring is active.
///
/// # Arguments
/// * `device_id` - The unique identifier for the device
///
/// # Returns
/// DeviceHeartbeatInfo with all heartbeat details
pub async fn api_get_device_heartbeat_info(
    device_id: String,
) -> Result<DeviceHeartbeatInfo, NightshadeError> {
    let manager = get_device_manager();

    // Check if device exists and get its info using the public API
    let device = manager
        .get_device(&device_id)
        .await
        .ok_or_else(|| NightshadeError::DeviceNotFound(device_id.clone()))?;

    let device_type_enum = device.info.device_type.clone();

    // Get device-type specific configuration
    let config = crate::devices::HeartbeatConfig::for_device_type(&device_type_enum);

    Ok(DeviceHeartbeatInfo {
        device_id,
        device_type: device_type_enum.as_str().to_string(),
        heartbeat_active: device.heartbeat_active,
        last_successful_comm_ms: device.last_successful_comm,
        interval_secs: config.base_interval_secs,
        max_interval_secs: config.max_interval_secs,
        failure_threshold: config.failure_threshold,
        auto_reconnect: config.auto_reconnect,
        max_reconnect_attempts: config.max_reconnect_attempts,
    })
}

/// Check if heartbeat monitoring is active for a device
pub async fn api_is_heartbeat_active(device_id: String) -> Result<bool, NightshadeError> {
    Ok(get_device_manager().is_heartbeat_active(&device_id).await)
}

// =============================================================================
// Device API Version Negotiation
// =============================================================================

/// Get the API version information for a connected device.
///
/// This queries the device's interface version, driver version, and supported actions.
/// For Alpaca devices, this uses the InterfaceVersion property.
/// For ASCOM devices, this uses the InterfaceVersion COM property.
/// For INDI devices, this returns the protocol version from the server greeting.
///
/// Returns cached version info if available and fresh (less than 5 minutes old),
/// otherwise queries the device directly.
pub async fn api_get_device_api_version(
    device_id: String,
) -> Result<DeviceApiVersion, NightshadeError> {
    // First check cached version
    if let Some(cached) = get_device_manager()
        .get_device_api_version(&device_id)
        .await
    {
        if cached.is_fresh() {
            return Ok(cached);
        }
    }

    // Query fresh version info
    get_device_manager()
        .query_device_api_version(&device_id)
        .await
        .map_err(|e| NightshadeError::DeviceNotFound(e))
}

/// Check if a device supports a specific interface version.
///
/// This is useful for checking if newer API methods are available before calling them.
/// Returns true if the device reports an interface version >= the required version,
/// and false when version information is unavailable.
pub async fn api_device_supports_version(
    device_id: String,
    required_version: u32,
) -> Result<bool, NightshadeError> {
    Ok(get_device_manager()
        .device_supports_version(&device_id, required_version)
        .await)
}

/// Check if a device supports a specific action.
///
/// For ASCOM/Alpaca devices, checks the SupportedActions list.
/// Returns true only when the action is explicitly reported as supported.
pub async fn api_device_supports_action(
    device_id: String,
    action: String,
) -> Result<bool, NightshadeError> {
    Ok(get_device_manager()
        .device_supports_action(&device_id, &action)
        .await)
}

// =============================================================================
// Camera Control (Simulator implementation)
// =============================================================================

/// Simulated camera state
static SIM_CAMERA: OnceLock<Arc<RwLock<SimulatedCamera>>> = OnceLock::new();

#[flutter_rust_bridge::frb]
pub struct SimulatedCamera {
    pub status: CameraStatus,
}

impl Default for SimulatedCamera {
    fn default() -> Self {
        Self {
            status: CameraStatus {
                connected: false,
                state: CameraState::Idle,
                sensor_temp: Some(20.0),
                cooler_power: Some(0.0),
                target_temp: Some(-10.0),
                cooler_on: false,
                gain: 100,
                offset: 10,
                bin_x: 1,
                bin_y: 1,
                sensor_width: 4144,
                sensor_height: 2822,
                pixel_size_x: 3.76,
                pixel_size_y: 3.76,
                max_adu: 65535,
                can_cool: true,
                can_set_gain: true,
                can_set_offset: true,
            },
        }
    }
}

fn get_sim_camera() -> &'static Arc<RwLock<SimulatedCamera>> {
    SIM_CAMERA.get_or_init(|| Arc::new(RwLock::new(SimulatedCamera::default())))
}

/// Get camera status
pub async fn api_get_camera_status(device_id: String) -> Result<CameraStatus, NightshadeError> {
    // Handle simulator devices with local simulated state
    if device_id.starts_with("sim_") {
        let camera = get_sim_camera().read().await;
        return Ok(camera.status.clone());
    }

    // Route real devices through the DeviceManager
    let mgr = get_device_manager();
    mgr.camera_get_status(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set camera cooling target
pub async fn api_set_camera_cooler(
    device_id: String,
    enabled: u8,
    target_temp: Option<f64>,
) -> Result<(), NightshadeError> {
    // Handle simulator devices with local simulated state
    if device_id.starts_with("sim_") {
        let mut camera = get_sim_camera().write().await;
        camera.status.cooler_on = enabled != 0;
        if let Some(temp) = target_temp {
            camera.status.target_temp = Some(temp);
        }
        tracing::info!(
            "Simulator camera cooler: enabled={}, target={:?}",
            enabled,
            target_temp
        );
        return Ok(());
    }

    // Route real devices through the DeviceManager
    tracing::info!(
        "Setting camera cooler for {}: enabled={}, target={:?}",
        device_id,
        enabled,
        target_temp
    );
    let mgr = get_device_manager();
    mgr.camera_set_cooler(&device_id, enabled != 0, target_temp)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set camera gain
pub async fn api_set_camera_gain(device_id: String, gain: i32) -> Result<(), NightshadeError> {
    // Handle simulator devices with local simulated state
    if device_id.starts_with("sim_") {
        let mut camera = get_sim_camera().write().await;
        camera.status.gain = gain;
        tracing::info!("Simulator camera gain set to: {}", gain);
        return Ok(());
    }

    // Route real devices through the DeviceManager
    tracing::info!("Setting camera gain for {}: {}", device_id, gain);
    let mgr = get_device_manager();
    mgr.camera_set_gain(&device_id, gain)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set camera offset
pub async fn api_set_camera_offset(device_id: String, offset: i32) -> Result<(), NightshadeError> {
    // Handle simulator devices with local simulated state
    if device_id.starts_with("sim_") {
        let mut camera = get_sim_camera().write().await;
        camera.status.offset = offset;
        tracing::info!("Simulator camera offset set to: {}", offset);
        return Ok(());
    }

    // Route real devices through the DeviceManager
    tracing::info!("Setting camera offset for {}: {}", device_id, offset);
    let mgr = get_device_manager();
    mgr.camera_set_offset(&device_id, offset)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Camera Exposure Control (Real Cameras)
// =============================================================================

/// Start camera exposure
/// This delegates to api_camera_start_exposure which handles the full exposure
/// workflow including waiting for completion, image processing, and storage.
pub async fn start_exposure(
    device_id: String,
    duration_secs: f64,
    gain: i32,
    offset: i32,
    bin_x: i32,
    bin_y: i32,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "API: start_exposure called for {} duration={}",
        device_id,
        duration_secs
    );

    // Delegate to the full implementation which handles:
    // - Starting the exposure
    // - Publishing progress events
    // - Waiting for completion
    // - Downloading and processing the image
    // - Storing the result for get_last_image()
    api_camera_start_exposure(device_id, duration_secs, gain, offset, bin_x, bin_y).await
}

/// Abort/cancel camera exposure
pub async fn cancel_exposure(device_id: String) -> Result<(), NightshadeError> {
    tracing::info!("API: cancel_exposure called for {}", device_id);

    let mgr = get_device_manager();
    mgr.camera_abort_exposure(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))?;

    // Publish ExposureCancelled event
    let state = get_state();
    let event = crate::event::create_event_auto_id(
        crate::event::EventSeverity::Info,
        crate::event::EventCategory::Imaging,
        crate::event::EventPayload::Imaging(crate::event::ImagingEvent::ExposureCancelled),
    );
    state.event_bus.publish(event);

    Ok(())
}

/// Get camera status
pub async fn get_camera_status(device_id: String) -> Result<CameraStatus, NightshadeError> {
    let mgr = get_device_manager();
    mgr.camera_get_status(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set camera cooler
pub async fn set_camera_cooler(
    device_id: String,
    enabled: u8,
    target_temp: Option<f64>,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.camera_set_cooler(&device_id, enabled != 0, target_temp)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Mount Control
// =============================================================================

/// Slew mount to coordinates
pub async fn mount_slew(device_id: String, ra: f64, dec: f64) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_slew(&device_id, ra, dec)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Sync mount to coordinates
pub async fn mount_sync(device_id: String, ra: f64, dec: f64) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_sync(&device_id, ra, dec)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Park mount
pub async fn mount_park(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_park(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Unpark mount
pub async fn mount_unpark(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_unpark(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get mount coordinates
pub async fn mount_get_coordinates(device_id: String) -> Result<(f64, f64), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_get_coordinates(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Abort mount slew
pub async fn mount_abort(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_abort(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Stop mount motion (abort slew without disconnecting)
pub async fn mount_stop(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_stop(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Query whether a mount supports parking
pub async fn mount_can_park(device_id: String) -> Result<bool, NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_can_park(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set mount tracking
pub async fn mount_set_tracking(device_id: String, enabled: u8) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_set_tracking(&device_id, enabled != 0)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set mount tracking rate (0=Sidereal, 1=Lunar, 2=Solar, 3=King)
pub async fn mount_set_tracking_rate(device_id: String, rate: i32) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_set_tracking_rate(&device_id, rate)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Pulse guide mount
pub async fn mount_pulse_guide(
    device_id: String,
    direction: String,
    duration_ms: u32,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_pulse_guide(&device_id, direction, duration_ms)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get mount status
pub async fn mount_get_status(device_id: String) -> Result<MountStatus, NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_get_status(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get mount tracking rate (0=Sidereal, 1=Lunar, 2=Solar, 3=King)
pub async fn mount_get_tracking_rate(device_id: String) -> Result<i32, NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_get_tracking_rate(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Move mount axis at specified rate (degrees/second)
/// axis: 0=RA/Azimuth (primary), 1=Dec/Altitude (secondary)
/// rate: degrees per second (positive = N/E, negative = S/W), 0 to stop
pub async fn mount_move_axis(
    device_id: String,
    axis: i32,
    rate: f64,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_move_axis(&device_id, axis, rate)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Slew mount to alt/az coordinates (altitude in degrees, azimuth in degrees)
pub async fn mount_slew_alt_az(
    device_id: String,
    altitude: f64,
    azimuth: f64,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_slew_alt_az(&device_id, altitude, azimuth)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Find mount home position
pub async fn mount_find_home(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.mount_find_home(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Focuser Control
// =============================================================================

/// Move focuser to absolute position
pub async fn focuser_move_abs(device_id: String, position: i32) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_move_abs(&device_id, position)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Move focuser relative
pub async fn focuser_move_rel(device_id: String, steps: i32) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_move_rel(&device_id, steps)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Halt focuser
pub async fn focuser_halt(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_halt(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get focuser position
pub async fn focuser_get_position(device_id: String) -> Result<i32, NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_get_position(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get focuser temperature
pub async fn focuser_get_temp(device_id: String) -> Result<Option<f64>, NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_get_temp(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get focuser details (max pos, step size)
pub async fn focuser_get_details(device_id: String) -> Result<(i32, f64), NightshadeError> {
    let mgr = get_device_manager();
    mgr.focuser_get_details(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Filter Wheel Control
// =============================================================================

/// Set filter wheel position
pub async fn filter_wheel_set_position(
    device_id: String,
    position: i32,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        let mut fw = get_sim_filterwheel().write().await;
        fw.status.position = position;
        Ok(())
    } else {
        let mgr = get_device_manager();
        mgr.filter_wheel_set_position(&device_id, position)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Get filter wheel position
pub async fn filter_wheel_get_position(device_id: String) -> Result<i32, NightshadeError> {
    if device_id.starts_with("sim_") {
        let fw = get_sim_filterwheel().read().await;
        Ok(fw.status.position)
    } else {
        let mgr = get_device_manager();
        mgr.filter_wheel_get_position(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Get filter wheel configuration (count, names)
pub async fn filter_wheel_get_config(
    device_id: String,
) -> Result<(i32, Vec<String>), NightshadeError> {
    if device_id.starts_with("sim_") {
        let fw = get_sim_filterwheel().read().await;
        Ok((fw.status.filter_count, fw.status.filter_names.clone()))
    } else {
        let mgr = get_device_manager();
        mgr.filter_wheel_get_config(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Set camera gain
pub async fn set_camera_gain(device_id: String, gain: i32) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.camera_set_gain(&device_id, gain)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set camera offset
pub async fn set_camera_offset(device_id: String, offset: i32) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.camera_set_offset(&device_id, offset)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Camera Readout Mode
// =============================================================================

/// Set camera readout mode by index
///
/// mode_index: 0 = default/high quality, 1 = fast readout, etc.
/// The available modes are camera-dependent.
pub async fn api_camera_set_readout_mode(
    device_id: String,
    mode_index: i32,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Simulator camera readout mode set to index: {}", mode_index);
        return Ok(());
    }

    tracing::info!(
        "Setting camera readout mode for {}: index={}",
        device_id,
        mode_index
    );
    let mgr = get_device_manager();
    mgr.camera_set_readout_mode(&device_id, mode_index)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Camera Binning (Legacy API - keeping for compatibility)
// =============================================================================

/// Set camera binning
pub async fn api_set_camera_binning(
    device_id: String,
    bin_x: i32,
    bin_y: i32,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        let mut camera = get_sim_camera().write().await;
        camera.status.bin_x = bin_x;
        camera.status.bin_y = bin_y;
        tracing::info!("Camera binning set to: {}x{}", bin_x, bin_y);
        Ok(())
    } else {
        let mgr = get_device_manager();
        mgr.camera_set_binning(&device_id, bin_x, bin_y)
            .await
            .map_err(NightshadeError::OperationFailed)
    }
}

// =============================================================================
// Dome Control
// =============================================================================

/// Get dome status
pub async fn api_get_dome_status(device_id: String) -> Result<DomeStatus, NightshadeError> {
    let mgr = get_device_manager();
    mgr.dome_get_status(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Open dome shutter
pub async fn api_dome_open_shutter(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.dome_open_shutter(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Close dome shutter
pub async fn api_dome_close_shutter(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.dome_close_shutter(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Slew dome to azimuth
pub async fn api_dome_slew_to_azimuth(
    device_id: String,
    azimuth: f64,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.dome_slew_to_azimuth(&device_id, azimuth)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Park dome
pub async fn api_dome_park(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.dome_park(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get dome azimuth
pub async fn api_dome_get_azimuth(device_id: String) -> Result<f64, NightshadeError> {
    let mgr = get_device_manager();
    mgr.dome_get_azimuth(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get dome shutter status
pub async fn api_dome_get_shutter_status(device_id: String) -> Result<i32, NightshadeError> {
    let mgr = get_device_manager();
    mgr.dome_get_shutter_status(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Check if dome is slewing
pub async fn api_dome_is_slewing(device_id: String) -> Result<bool, NightshadeError> {
    let mgr = get_device_manager();
    mgr.dome_is_slewing(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Switch Control
// =============================================================================

/// Get the number of switches exposed by a switch device
pub async fn api_switch_get_max(device_id: String) -> Result<i32, NightshadeError> {
    let mgr = get_device_manager();
    mgr.switch_get_max(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get the boolean state of a switch
pub async fn api_switch_get_state(
    device_id: String,
    switch_id: i32,
) -> Result<bool, NightshadeError> {
    let mgr = get_device_manager();
    mgr.switch_get_state(&device_id, switch_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set the boolean state of a switch
pub async fn api_switch_set_state(
    device_id: String,
    switch_id: i32,
    state: bool,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.switch_set_state(&device_id, switch_id, state)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get the name of a switch
pub async fn api_switch_get_name(
    device_id: String,
    switch_id: i32,
) -> Result<String, NightshadeError> {
    let mgr = get_device_manager();
    mgr.switch_get_name(&device_id, switch_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get the description of a switch
pub async fn api_switch_get_description(
    device_id: String,
    switch_id: i32,
) -> Result<String, NightshadeError> {
    let mgr = get_device_manager();
    mgr.switch_get_description(&device_id, switch_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get the numeric value of a switch
pub async fn api_switch_get_value(
    device_id: String,
    switch_id: i32,
) -> Result<f64, NightshadeError> {
    let mgr = get_device_manager();
    mgr.switch_get_value(&device_id, switch_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set the numeric value of a switch
pub async fn api_switch_set_value(
    device_id: String,
    switch_id: i32,
    value: f64,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.switch_set_value(&device_id, switch_id, value)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get the minimum value for a switch
pub async fn api_switch_get_min_value(
    device_id: String,
    switch_id: i32,
) -> Result<f64, NightshadeError> {
    let mgr = get_device_manager();
    mgr.switch_get_min_value(&device_id, switch_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get the maximum value for a switch
pub async fn api_switch_get_max_value(
    device_id: String,
    switch_id: i32,
) -> Result<f64, NightshadeError> {
    let mgr = get_device_manager();
    mgr.switch_get_max_value(&device_id, switch_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Check if a switch can be written to
pub async fn api_switch_can_write(
    device_id: String,
    switch_id: i32,
) -> Result<bool, NightshadeError> {
    let mgr = get_device_manager();
    mgr.switch_can_write(&device_id, switch_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Cover Calibrator Control (Flat Panel / Dust Cover)
// =============================================================================

/// Open cover calibrator dust cover
pub async fn api_cover_calibrator_open_cover(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.cover_calibrator_open_cover(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Close cover calibrator dust cover
pub async fn api_cover_calibrator_close_cover(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.cover_calibrator_close_cover(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Halt cover calibrator cover movement
pub async fn api_cover_calibrator_halt_cover(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.cover_calibrator_halt_cover(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Turn on cover calibrator light at specified brightness
pub async fn api_cover_calibrator_calibrator_on(
    device_id: String,
    brightness: i32,
) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.cover_calibrator_calibrator_on(&device_id, brightness)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Turn off cover calibrator light
pub async fn api_cover_calibrator_calibrator_off(device_id: String) -> Result<(), NightshadeError> {
    let mgr = get_device_manager();
    mgr.cover_calibrator_calibrator_off(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get cover calibrator cover state (0=NotPresent, 1=Closed, 2=Moving, 3=Open, 4=Unknown, 5=Error)
pub async fn api_cover_calibrator_get_cover_state(
    device_id: String,
) -> Result<i32, NightshadeError> {
    let mgr = get_device_manager();
    mgr.cover_calibrator_get_cover_state(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get cover calibrator calibrator state (0=NotPresent, 1=Off, 2=NotReady, 3=Ready, 4=Unknown, 5=Error)
pub async fn api_cover_calibrator_get_calibrator_state(
    device_id: String,
) -> Result<i32, NightshadeError> {
    let mgr = get_device_manager();
    mgr.cover_calibrator_get_calibrator_state(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get cover calibrator current brightness
pub async fn api_cover_calibrator_get_brightness(
    device_id: String,
) -> Result<i32, NightshadeError> {
    let mgr = get_device_manager();
    mgr.cover_calibrator_get_brightness(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get cover calibrator maximum brightness
pub async fn api_cover_calibrator_get_max_brightness(
    device_id: String,
) -> Result<i32, NightshadeError> {
    let mgr = get_device_manager();
    mgr.cover_calibrator_get_max_brightness(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get cover calibrator full status
pub async fn api_cover_calibrator_get_status(
    device_id: String,
) -> Result<crate::device::CoverCalibratorStatus, NightshadeError> {
    let mgr = get_device_manager();
    mgr.cover_calibrator_get_status(&device_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Mount Control (Simulator implementation)
// =============================================================================

/// Simulated mount state
static SIM_MOUNT: OnceLock<Arc<RwLock<SimulatedMount>>> = OnceLock::new();

#[flutter_rust_bridge::frb]
pub struct SimulatedMount {
    pub status: MountStatus,
}

impl Default for SimulatedMount {
    fn default() -> Self {
        // Simulator pretends to be a fully-capable mount: every optional field
        // is reported `Available` so UI rendering paths exercise the populated
        // case during development without needing real hardware.
        use crate::device::{mount_status_field as f, FieldAvailability};
        let mut availability = std::collections::HashMap::new();
        availability.insert(f::AT_HOME.to_string(), FieldAvailability::Available);
        availability.insert(f::SIDE_OF_PIER.to_string(), FieldAvailability::Available);
        availability.insert(f::ALTITUDE.to_string(), FieldAvailability::Available);
        availability.insert(f::AZIMUTH.to_string(), FieldAvailability::Available);
        availability.insert(f::SIDEREAL_TIME.to_string(), FieldAvailability::Available);
        availability.insert(f::TRACKING_RATE.to_string(), FieldAvailability::Available);
        Self {
            status: MountStatus {
                connected: false,
                tracking: false,
                slewing: false,
                parked: true,
                at_home: Some(false),
                side_of_pier: Some(PierSide::Unknown),
                right_ascension: 0.0,
                declination: 0.0,
                altitude: Some(0.0),
                azimuth: Some(0.0),
                sidereal_time: Some(0.0),
                tracking_rate: Some(TrackingRate::Sidereal),
                can_park: true,
                can_slew: true,
                can_sync: true,
                can_pulse_guide: true,
                can_set_tracking_rate: true,
                availability,
            },
        }
    }
}

fn get_sim_mount() -> &'static Arc<RwLock<SimulatedMount>> {
    SIM_MOUNT.get_or_init(|| Arc::new(RwLock::new(SimulatedMount::default())))
}

/// Get mount status
pub async fn api_get_mount_status(device_id: String) -> Result<MountStatus, NightshadeError> {
    if device_id.starts_with("sim_") {
        let mount = get_sim_mount().read().await;
        Ok(mount.status.clone())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.mount_get_status(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Slew mount to coordinates
pub async fn api_mount_slew_to_coordinates(
    device_id: String,
    ra: f64,
    dec: f64,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Slewing to RA: {:.4}h, Dec: {:.4}°", ra, dec);

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = true;
        }

        // Simulate slew time
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = false;
            mount.status.right_ascension = ra;
            mount.status.declination = dec;
            mount.status.parked = false;
        }

        tracing::info!("Slew complete");
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.mount_slew(&device_id, ra, dec)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Sync mount to coordinates
pub async fn api_mount_sync_to_coordinates(
    device_id: String,
    ra: f64,
    dec: f64,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Syncing to RA: {:.4}h, Dec: {:.4}°", ra, dec);

        let mut mount = get_sim_mount().write().await;
        mount.status.right_ascension = ra;
        mount.status.declination = dec;

        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.mount_sync(&device_id, ra, dec)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Park the mount
pub async fn api_mount_park(device_id: String) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Parking mount");

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = true;
        }

        // Simulate park time
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = false;
            mount.status.parked = true;
            mount.status.tracking = false;
        }

        tracing::info!("Mount parked");
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.mount_park(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Unpark the mount
pub async fn api_mount_unpark(device_id: String) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        let mut mount = get_sim_mount().write().await;
        mount.status.parked = false;

        tracing::info!("Mount unparked");
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.mount_unpark(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Set mount tracking
pub async fn api_mount_set_tracking(device_id: String, enabled: u8) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        let mut mount = get_sim_mount().write().await;
        mount.status.tracking = enabled != 0;

        tracing::info!("Mount tracking: {}", enabled);
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.mount_set_tracking(&device_id, enabled != 0)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Slew mount to alt/az coordinates (simulator handler)
pub async fn api_mount_slew_alt_az(
    device_id: String,
    altitude: f64,
    azimuth: f64,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Slewing to Alt: {:.4}°, Az: {:.4}°", altitude, azimuth);

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = true;
        }

        // Simulate slew time
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = false;
            mount.status.altitude = Some(altitude);
            mount.status.azimuth = Some(azimuth);
            mount.status.parked = false;
        }

        tracing::info!("Alt/Az slew complete");
        Ok(())
    } else {
        let mgr = get_device_manager();
        mgr.mount_slew_alt_az(&device_id, altitude, azimuth)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Find mount home position (simulator handler)
pub async fn api_mount_find_home(device_id: String) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Finding mount home position");

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = true;
        }

        // Simulate home-finding time
        tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;

        {
            let mut mount = get_sim_mount().write().await;
            mount.status.slewing = false;
            mount.status.at_home = Some(true);
            mount.status.parked = false;
        }

        tracing::info!("Mount home found");
        Ok(())
    } else {
        let mgr = get_device_manager();
        mgr.mount_find_home(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Pulse guide the mount in a direction for a duration
pub async fn api_mount_pulse_guide(
    device_id: String,
    direction: String,
    duration_ms: i32,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Pulse guiding {} for {}ms in direction {}",
        device_id,
        duration_ms,
        direction
    );

    // Validate direction
    match direction.to_lowercase().as_str() {
        "north" | "n" | "south" | "s" | "east" | "e" | "west" | "w" => {}
        _ => {
            return Err(NightshadeError::InvalidParameter(format!(
                "Unknown direction: {}",
                direction
            )))
        }
    };

    // For simulator, just wait the duration
    if device_id.starts_with("sim_") {
        tokio::time::sleep(std::time::Duration::from_millis(duration_ms as u64)).await;
        tracing::info!("Pulse guide complete");
        return Ok(());
    }

    // Route real devices through DeviceManager
    let mgr = get_device_manager();
    mgr.mount_pulse_guide(&device_id, direction, duration_ms as u32)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// Focuser Control (Simulator implementation)
// =============================================================================

/// Simulated focuser state
static SIM_FOCUSER: OnceLock<Arc<RwLock<SimulatedFocuser>>> = OnceLock::new();

#[flutter_rust_bridge::frb]
pub struct SimulatedFocuser {
    pub status: FocuserStatus,
}

impl Default for SimulatedFocuser {
    fn default() -> Self {
        Self {
            status: FocuserStatus {
                connected: false,
                position: 25000,
                moving: false,
                temperature: Some(20.0),
                max_position: 50000,
                step_size: 1.0,
                is_absolute: true,
                has_temperature: true,
            },
        }
    }
}

#[flutter_rust_bridge::frb(ignore)]
pub fn get_sim_focuser() -> &'static Arc<RwLock<SimulatedFocuser>> {
    SIM_FOCUSER.get_or_init(|| Arc::new(RwLock::new(SimulatedFocuser::default())))
}

/// Get focuser status
pub async fn api_get_focuser_status(device_id: String) -> Result<FocuserStatus, NightshadeError> {
    if device_id.starts_with("sim_") {
        let focuser = get_sim_focuser().read().await;
        Ok(focuser.status.clone())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();

        // Get all focuser status components
        let position = mgr
            .focuser_get_position(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        let moving = mgr
            .focuser_is_moving(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        let temperature = mgr.focuser_get_temp(&device_id).await.unwrap_or(None);
        let (max_position, step_size) = match mgr.focuser_get_details(&device_id).await {
            Ok(details) => details,
            Err(e) => {
                tracing::warn!(
                    "Failed to get focuser details for {}: {:?}. Returning unknown max/step values.",
                    device_id,
                    e
                );
                (0, 0.0)
            }
        };
        let is_absolute = mgr
            .focuser_is_absolute(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;

        Ok(FocuserStatus {
            connected: true,
            position,
            moving,
            temperature,
            max_position,
            step_size,
            is_absolute,
            has_temperature: temperature.is_some(),
        })
    }
}

/// Move focuser to position
pub async fn api_focuser_move_to(device_id: String, position: i32) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Moving simulator focuser to position: {}", position);

        {
            let mut focuser = get_sim_focuser().write().await;
            focuser.status.moving = true;
        }

        // Simulate move time based on distance
        let current_pos = {
            let focuser = get_sim_focuser().read().await;
            focuser.status.position
        };
        let distance = (position - current_pos).abs();
        let move_time = (distance as f64 / 1000.0).max(0.5);

        tokio::time::sleep(tokio::time::Duration::from_secs_f64(move_time)).await;

        {
            let mut focuser = get_sim_focuser().write().await;
            focuser.status.moving = false;
            focuser.status.position = position;
        }

        tracing::info!("Focuser move complete");
        Ok(())
    } else {
        // Real device - use DeviceManager for proper driver routing
        let mgr = get_device_manager();
        mgr.focuser_move_abs(&device_id, position)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Move focuser by relative amount
pub async fn api_focuser_move_relative(
    device_id: String,
    delta: i32,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        // Atomically read current position and set target while under write lock
        // This prevents race conditions where two relative moves could read the same position
        let (current_pos, target_pos) = {
            let mut focuser = get_sim_focuser().write().await;
            let current = focuser.status.position;
            let target = current + delta;
            // Set moving=true and update position atomically while we hold the lock
            // This ensures another move_relative sees the updated position
            focuser.status.moving = true;
            focuser.status.position = target; // Pre-commit the target position
            (current, target)
        };

        // Simulate move time based on distance (lock released during sleep)
        let distance = delta.abs();
        let move_time = (distance as f64 / 1000.0).max(0.5);
        tokio::time::sleep(tokio::time::Duration::from_secs_f64(move_time)).await;

        // Mark move as complete
        {
            let mut focuser = get_sim_focuser().write().await;
            focuser.status.moving = false;
            // Position was already set above, no need to set again
        }

        tracing::info!(
            "Focuser relative move complete: {} + {} = {}",
            current_pos,
            delta,
            target_pos
        );
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.focuser_move_rel(&device_id, delta)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Halt focuser
pub async fn api_focuser_halt(device_id: String) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        // For simulator, just stop moving
        let mut focuser = get_sim_focuser().write().await;
        focuser.status.moving = false;
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.focuser_halt(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

// =============================================================================
// Filter Wheel Control (Simulator implementation)
// =============================================================================

/// Simulated filter wheel state
static SIM_FILTERWHEEL: OnceLock<Arc<RwLock<SimulatedFilterWheel>>> = OnceLock::new();

#[flutter_rust_bridge::frb]
pub struct SimulatedFilterWheel {
    pub status: FilterWheelStatus,
}

impl Default for SimulatedFilterWheel {
    fn default() -> Self {
        Self {
            status: FilterWheelStatus {
                connected: false,
                position: 1,
                moving: false,
                filter_count: 7,
                filter_names: vec![
                    "L".to_string(),
                    "R".to_string(),
                    "G".to_string(),
                    "B".to_string(),
                    "Ha".to_string(),
                    "OIII".to_string(),
                    "SII".to_string(),
                ],
            },
        }
    }
}

fn get_sim_filterwheel() -> &'static Arc<RwLock<SimulatedFilterWheel>> {
    SIM_FILTERWHEEL.get_or_init(|| Arc::new(RwLock::new(SimulatedFilterWheel::default())))
}

/// Get filter wheel status
pub async fn api_get_filterwheel_status(
    device_id: String,
) -> Result<FilterWheelStatus, NightshadeError> {
    if device_id.starts_with("sim_") {
        let fw = get_sim_filterwheel().read().await;
        Ok(fw.status.clone())
    } else {
        // Real device - use DeviceManager for proper driver routing
        let mgr = get_device_manager();
        let position = mgr
            .filter_wheel_get_position(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        tracing::info!(
            "[api_get_filterwheel_status] device={}, raw position from SDK={}",
            device_id,
            position
        );
        let is_moving = mgr
            .filter_wheel_is_moving(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        let (filter_count, filter_names) = mgr
            .filter_wheel_get_config(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;

        tracing::info!(
            "[api_get_filterwheel_status] Returning: position={}, moving={}, filter_count={}, names={:?}",
            position,
            is_moving,
            filter_count,
            filter_names
        );

        Ok(FilterWheelStatus {
            connected: true,
            position,
            moving: is_moving,
            filter_count,
            filter_names,
        })
    }
}

/// Set filter wheel position
pub async fn api_filterwheel_set_position(
    device_id: String,
    position: i32,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "[API] api_filterwheel_set_position called: device_id={}, position={}",
        device_id,
        position
    );
    if device_id.starts_with("sim_") {
        tracing::info!("[API] Using simulator filter wheel");
        let mut fw = get_sim_filterwheel().write().await;

        // Simulate move
        fw.status.moving = true;
        fw.status.position = -1; // Unknown while moving

        // Instant move for sim
        fw.status.moving = false;
        fw.status.position = position;

        Ok(())
    } else {
        // Real device - use DeviceManager for proper driver routing
        tracing::info!("[API] Using real device via DeviceManager");
        let mgr = get_device_manager();
        let result = mgr
            .filter_wheel_set_position(&device_id, position)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e));
        match &result {
            Ok(_) => tracing::info!("[API] Filter wheel position set successfully"),
            Err(e) => tracing::error!("[API] Filter wheel set position failed: {:?}", e),
        }
        result
    }
}

/// Get filter names
pub async fn api_filterwheel_get_names(device_id: String) -> Result<Vec<String>, NightshadeError> {
    if device_id.starts_with("sim_") {
        let fw = get_sim_filterwheel().read().await;
        Ok(fw.status.filter_names.clone())
    } else {
        // Real device - use DeviceManager for proper driver routing
        let mgr = get_device_manager();
        let (_, filter_names) = mgr
            .filter_wheel_get_config(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        Ok(filter_names)
    }
}

/// Set filter by name
pub async fn api_filterwheel_set_by_name(
    device_id: String,
    name: String,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        let position = {
            let fw = get_sim_filterwheel().read().await;
            fw.status.filter_names.iter().position(|n| n == &name)
        };

        if let Some(pos) = position {
            api_filterwheel_set_position(device_id, pos as i32).await
        } else {
            Err(NightshadeError::OperationFailed(format!(
                "Filter {} not found",
                name
            )))
        }
    } else {
        // Real device - find position by name and use DeviceManager
        let mgr = get_device_manager();

        // Get filter names from device
        let (_, filter_names) = mgr.filter_wheel_get_config(&device_id).await.map_err(|e| {
            NightshadeError::OperationFailed(format!("Failed to get filter config: {}", e))
        })?;

        // Find filter position by name (case-insensitive)
        let position = find_filter_match(&filter_names, &name)
            .map(|p| p as i32)
            .ok_or_else(|| {
                NightshadeError::OperationFailed(format!(
                    "Filter '{}' not found. Available: {:?}",
                    name, filter_names
                ))
            })?;

        // Set the filter position
        mgr.filter_wheel_set_position(&device_id, position)
            .await
            .map_err(|e| {
                NightshadeError::OperationFailed(format!("Failed to set filter: {}", e))
            })?;

        Ok(())
    }
}

/// Set filter names on a filter wheel
/// This pushes user-defined filter names from the equipment profile to the hardware driver.
pub async fn api_filterwheel_set_filter_names(
    device_id: String,
    names: Vec<String>,
) -> Result<(), NightshadeError> {
    tracing::info!("API: Setting filter names for '{}': {:?}", device_id, names);

    if device_id.starts_with("sim_") {
        // Simulator - update the simulated filter wheel's names
        let mut fw = get_sim_filterwheel().write().await;
        // Only update up to the existing count
        let count = fw.status.filter_names.len().min(names.len());
        for i in 0..count {
            fw.status.filter_names[i] = names[i].clone();
        }
        tracing::info!("API: Set {} filter names on simulator", count);
        Ok(())
    } else {
        // Real device - use DeviceManager
        let mgr = get_device_manager();
        mgr.filter_wheel_set_filter_names(&device_id, names)
            .await
            .map_err(|e| {
                NightshadeError::OperationFailed(format!("Failed to set filter names: {}", e))
            })?;
        Ok(())
    }
}

// =============================================================================
// Rotator Control (Simulator implementation)
// =============================================================================

/// Simulated rotator state
static SIM_ROTATOR: OnceLock<Arc<RwLock<SimulatedRotator>>> = OnceLock::new();

#[flutter_rust_bridge::frb]
pub struct SimulatedRotator {
    pub status: RotatorStatus,
}

impl Default for SimulatedRotator {
    fn default() -> Self {
        Self {
            status: RotatorStatus {
                connected: false,
                position: 0.0,
                moving: false,
                mechanical_position: 0.0,
                is_moving: false,
                can_reverse: true,
            },
        }
    }
}

#[flutter_rust_bridge::frb(ignore)]
pub fn get_sim_rotator() -> &'static Arc<RwLock<SimulatedRotator>> {
    SIM_ROTATOR.get_or_init(|| Arc::new(RwLock::new(SimulatedRotator::default())))
}

/// Get rotator status
pub async fn api_get_rotator_status(device_id: String) -> Result<RotatorStatus, NightshadeError> {
    if device_id.starts_with("sim_") {
        let rotator = get_sim_rotator().read().await;
        Ok(rotator.status.clone())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();

        let position = mgr
            .rotator_get_position(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        let is_moving = mgr
            .rotator_is_moving(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        let can_reverse = match api_get_rotator_capabilities(device_id.clone()).await {
            Ok(caps) => caps.can_reverse,
            Err(e) => {
                tracing::warn!(
                    "Failed to query rotator capabilities for {}: {:?}. Treating reverse as unsupported.",
                    device_id,
                    e
                );
                false
            }
        };

        Ok(RotatorStatus {
            connected: true,
            position,
            moving: is_moving,
            mechanical_position: position,
            is_moving,
            can_reverse,
        })
    }
}

/// Move rotator to angle
pub async fn api_rotator_move_to(device_id: String, angle: f64) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        tracing::info!("Moving simulator rotator to {}°", angle);

        {
            let mut rotator = get_sim_rotator().write().await;
            rotator.status.moving = true;
            rotator.status.is_moving = true;
        }

        // Simulate move time
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

        {
            let mut rotator = get_sim_rotator().write().await;
            rotator.status.moving = false;
            rotator.status.is_moving = false;
            rotator.status.position = angle;
            rotator.status.mechanical_position = angle;
        }

        Ok(())
    } else {
        // Real device - use DeviceManager for proper driver routing
        let mgr = get_device_manager();
        mgr.rotator_move_absolute(&device_id, angle)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Move rotator relative
pub async fn api_rotator_move_relative(
    device_id: String,
    delta: f64,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        let current = {
            let rotator = get_sim_rotator().read().await;
            rotator.status.position
        };
        let target = (current + delta) % 360.0;
        let target = if target < 0.0 { target + 360.0 } else { target };

        api_rotator_move_to(device_id, target).await
    } else {
        // Real device - calculate target angle and use DeviceManager
        let mgr = get_device_manager();
        let current = mgr
            .rotator_get_position(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        let target = (current + delta) % 360.0;
        let target = if target < 0.0 { target + 360.0 } else { target };
        mgr.rotator_move_absolute(&device_id, target)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Halt rotator
pub async fn api_rotator_halt(device_id: String) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        // For simulator, just stop moving
        let mut rotator = get_sim_rotator().write().await;
        rotator.status.moving = false;
        rotator.status.is_moving = false;
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.rotator_halt(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Sync rotator's reported sky angle to the supplied position angle without
/// moving the hardware. Used by the "Sync to image PA" workflow after a plate
/// solve: the solver returns the astrometric PA of the captured frame and
/// this call aligns the rotator's reported PA so subsequent absolute moves
/// land at the correct sky angle.
pub async fn api_rotator_sync_to_pa(
    device_id: String,
    pa: f64,
) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        // Simulator has no mechanical offset — just snap the reported angle.
        let mut rotator = get_sim_rotator().write().await;
        rotator.status.position = pa;
        rotator.status.mechanical_position = pa;
        Ok(())
    } else {
        let mgr = get_device_manager();
        mgr.rotator_sync(&device_id, pa)
            .await
            .map_err(NightshadeError::OperationFailed)
    }
}

// =============================================================================
// Camera Exposure & Image Capture
// =============================================================================

/// Global cancellation token for autofocus
static AUTOFOCUS_CANCEL_TOKEN: OnceLock<Arc<AtomicBool>> = OnceLock::new();

fn get_autofocus_cancel_token() -> &'static Arc<AtomicBool> {
    // OnceLock is immutable after initialization, so reuse one persistent token
    // and reset its flag between autofocus runs.
    AUTOFOCUS_CANCEL_TOKEN.get_or_init(|| Arc::new(AtomicBool::new(false)))
}

/// Autofocus configuration for API
#[derive(Debug, Clone)]
pub struct AutofocusConfigApi {
    pub exposure_time: f64,
    pub step_size: i32,
    pub steps_out: i32,
    pub method: String, // "VCurve", "Hyperbolic", "Parabolic"
    pub binning: i32,
}

/// A single focus data point (position and HFR)
#[derive(Debug, Clone)]
pub struct FocusDataPoint {
    pub position: i32,
    pub hfr: f64,
    pub fwhm: Option<f64>,
    pub star_count: u32,
}

/// Autofocus result containing all data for display and analysis
#[derive(Debug, Clone)]
pub struct AutofocusResultApi {
    pub best_position: i32,
    pub best_hfr: f64,
    pub focus_data: Vec<FocusDataPoint>,
    pub method: String,
    pub temperature: Option<f64>,
    pub timestamp: i64,
    pub curve_fit_quality: f64,
    pub backlash_applied: bool,
}

/// Run autofocus
pub async fn api_run_autofocus(
    device_id: String, // Focuser ID
    camera_id: String,
    config: AutofocusConfigApi,
) -> Result<AutofocusResultApi, NightshadeError> {
    tracing::info!(
        "Starting autofocus with camera {} and focuser {}",
        camera_id,
        device_id
    );

    use nightshade_sequencer::instructions::{execute_autofocus, InstructionContext};
    use nightshade_sequencer::{AutofocusConfig, AutofocusMethod, Binning, NodeStatus};
    use serde::Deserialize;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[derive(Debug, Deserialize)]
    struct LegacyAutofocusPayload {
        best_position: i32,
        best_hfr: f64,
        r_squared: f64,
        focus_data: Vec<(i32, f64)>,
    }

    // Reset cancellation token
    let cancel_token = get_autofocus_cancel_token();
    cancel_token.store(false, Ordering::Relaxed);

    // Store the method string for result
    let method_str = config.method.clone();

    // Map method string to enum
    let method = match config.method.as_str() {
        "Hyperbolic" => AutofocusMethod::Hyperbolic,
        "Parabolic" => AutofocusMethod::Quadratic,
        _ => AutofocusMethod::VCurve,
    };

    // Map binning
    let binning = match config.binning {
        2 => Binning::Two,
        3 => Binning::Three,
        4 => Binning::Four,
        _ => Binning::One,
    };

    let af_config = AutofocusConfig {
        exposure_duration: config.exposure_time,
        step_size: config.step_size,
        steps_out: config.steps_out as u32,
        method,
        binning,
        filter: None, // Optional: add filter support
        max_duration_secs: 600.0,
        ..AutofocusConfig::default()
    };

    // Create context - use UnifiedDeviceOps which routes through DeviceManager
    let device_ops = create_unified_device_ops();

    // Try to get focuser temperature before autofocus
    let temperature = device_ops
        .focuser_get_temperature(&device_id)
        .await
        .ok()
        .flatten();

    let ctx = InstructionContext {
        target_ra: None,
        target_dec: None,
        target_name: None,
        current_filter: None,
        current_binning: Binning::One,
        cancellation_token: cancel_token.clone(),
        camera_id: Some(camera_id),
        mount_id: None,
        focuser_id: Some(device_id),
        filterwheel_id: None,
        dome_id: None,
        rotator_id: None,
        cover_calibrator_id: None,
        save_path: None,
        latitude: None,
        longitude: None,
        device_ops,
        trigger_state: None,
        filter_focus_offsets: std::collections::HashMap::new(),
    };

    // Execute (no progress callback when called directly from API)
    let result = execute_autofocus(&af_config, &ctx, None).await;

    // Get current timestamp
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    match result.status {
        NodeStatus::Success => {
            let data = result.data.ok_or_else(|| {
                NightshadeError::OperationFailed(
                    "Autofocus completed without a result payload".to_string(),
                )
            })?;

            // Canonical payload (nightshade_sequencer::AutofocusResult)
            if let Ok(af_result) =
                serde_json::from_value::<nightshade_sequencer::AutofocusResult>(data.clone())
            {
                let focus_data: Vec<FocusDataPoint> = af_result
                    .data_points
                    .iter()
                    .map(|dp| FocusDataPoint {
                        position: dp.position,
                        hfr: dp.hfr,
                        fwhm: dp.fwhm,
                        star_count: dp.star_count,
                    })
                    .collect();

                return Ok(AutofocusResultApi {
                    best_position: af_result.best_position,
                    best_hfr: af_result.best_hfr,
                    focus_data,
                    method: method_str,
                    temperature: af_result.temperature_celsius.or(temperature),
                    timestamp,
                    curve_fit_quality: af_result.curve_fit_quality,
                    backlash_applied: af_result.backlash_applied,
                });
            }

            // Backward compatibility for legacy tuple payloads
            if let Ok(legacy) = serde_json::from_value::<LegacyAutofocusPayload>(data.clone()) {
                let focus_data = legacy
                    .focus_data
                    .into_iter()
                    .map(|(position, hfr)| FocusDataPoint {
                        position,
                        hfr,
                        fwhm: None,
                        star_count: 0,
                    })
                    .collect();
                return Ok(AutofocusResultApi {
                    best_position: legacy.best_position,
                    best_hfr: legacy.best_hfr,
                    focus_data,
                    method: method_str,
                    temperature,
                    timestamp,
                    curve_fit_quality: legacy.r_squared,
                    backlash_applied: false,
                });
            }

            Err(NightshadeError::OperationFailed(
                "Autofocus completed but returned an unrecognized payload format".to_string(),
            ))
        }
        NodeStatus::Failure => Err(NightshadeError::OperationFailed(
            result.message.unwrap_or("Autofocus failed".to_string()),
        )),
        NodeStatus::Cancelled => Err(NightshadeError::Cancelled),
        _ => Err(NightshadeError::OperationFailed(
            "Unknown error".to_string(),
        )),
    }
}

/// Cancel autofocus
pub async fn api_cancel_autofocus() -> Result<(), NightshadeError> {
    tracing::info!("Cancelling autofocus...");
    let cancel_token = get_autofocus_cancel_token();
    cancel_token.store(true, Ordering::Relaxed);
    Ok(())
}

// =============================================================================
// Camera Exposure & Image Capture
// =============================================================================

/// Captured image result containing display-ready data
#[derive(Debug, Clone)]
pub struct CapturedImageResult {
    pub width: u32,
    pub height: u32,
    pub display_data: Vec<u8>, // Always RGBA (width*height*4), alpha=255
    pub histogram: Vec<u32>,   // 256-bin histogram (computed from pre-RGBA pixel values)
    pub stats: ImageStatsResult,
    pub exposure_time: f64,
    pub timestamp: String,
    pub is_color: bool, // true if source was color (RGB), false if grayscale — retained for stretch/analysis paths
}

/// Convert grayscale (1 byte/pixel) or RGB (3 bytes/pixel) display data to RGBA (4 bytes/pixel).
/// Uses rayon for parallel conversion on large images.
pub(crate) fn display_data_to_rgba(data: &[u8], is_color: bool) -> Vec<u8> {
    if is_color {
        // RGB -> RGBA
        let num_pixels = data.len() / 3;
        let mut rgba = vec![0u8; num_pixels * 4];
        rgba.par_chunks_exact_mut(4)
            .zip(data.par_chunks_exact(3))
            .for_each(|(dst, src)| {
                dst[0] = src[0]; // R
                dst[1] = src[1]; // G
                dst[2] = src[2]; // B
                dst[3] = 255; // A
            });
        rgba
    } else {
        // Grayscale -> RGBA
        let num_pixels = data.len();
        let mut rgba = vec![0u8; num_pixels * 4];
        rgba.par_chunks_exact_mut(4)
            .zip(data.par_iter())
            .for_each(|(dst, &gray)| {
                dst[0] = gray; // R
                dst[1] = gray; // G
                dst[2] = gray; // B
                dst[3] = 255; // A
            });
        rgba
    }
}

/// Image statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageStatsResult {
    pub min: f64,
    pub max: f64,
    pub mean: f64,
    pub median: f64,
    pub std_dev: f64,
    pub hfr: Option<f64>,
    pub star_count: u32,
}

/// Raw image info with metadata - used by sequencer for actual image analysis
/// This preserves the original 16-bit sensor data needed for HFR calculation, plate solving, etc.
#[derive(Debug, Clone)]
pub struct RawImageInfo {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u16>,                   // Raw 16-bit sensor data
    pub sensor_type: Option<String>,      // "Monochrome" or "Color"
    pub bayer_offset: Option<(i32, i32)>, // Bayer pattern offset for color sensors
}

/// Unified captured image data - contains all image data for atomic updates
/// This ensures the UI never sees inconsistent state between raw data and display data
#[derive(Debug, Clone)]
pub struct CapturedImageData {
    /// Display-ready image result (8-bit for UI)
    pub display: CapturedImageResult,
    /// Raw 16-bit image info with metadata (for FITS saving, HFR, etc.)
    pub raw_info: RawImageInfo,
}

/// Per-device image storage - keyed by device ID to support multi-camera operation
/// Each camera's image data is stored independently, preventing race conditions
/// where concurrent cameras could overwrite each other's captured images.
static UNIFIED_IMAGE_STORAGE: OnceLock<Arc<RwLock<HashMap<String, CapturedImageData>>>> =
    OnceLock::new();

fn get_unified_image_storage() -> &'static Arc<RwLock<HashMap<String, CapturedImageData>>> {
    UNIFIED_IMAGE_STORAGE.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
}

/// Store captured image data atomically for a specific device
/// This ensures all image-related data (display, raw, metadata) is updated together,
/// preventing race conditions where the UI could see inconsistent state.
pub(crate) async fn store_captured_image_atomically(
    device_id: &str,
    display: CapturedImageResult,
    raw_info: RawImageInfo,
) {
    let mut storage = get_unified_image_storage().write().await;
    storage.insert(
        device_id.to_string(),
        CapturedImageData { display, raw_info },
    );
}

/// Start a camera exposure
/// Returns progress updates via events, final image available via api_get_last_image
pub async fn api_camera_start_exposure(
    device_id: String,
    duration_secs: f64,
    gain: i32,
    offset: i32,
    bin_x: i32,
    bin_y: i32,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Starting {}s exposure with gain={}, offset={}, bin={}x{}",
        duration_secs,
        gain,
        offset,
        bin_x,
        bin_y
    );

    // Check if simulator or real device
    if device_id.starts_with("sim_") {
        // Simulator path (existing code)
        // Update camera state to exposing
        {
            let mut camera = get_sim_camera().write().await;
            camera.status.state = CameraState::Exposing;
        }

        // Publish exposure started event
        get_state().publish_imaging_event(
            ImagingEvent::ExposureStarted {
                duration_secs,
                frame_type: crate::device::FrameType::Light,
            },
            EventSeverity::Info,
        );

        // Simulate exposure with progress updates using adaptive polling
        // This reduces CPU overhead for long simulated exposures while maintaining
        // responsiveness for progress updates
        let start_time = std::time::Instant::now();
        let duration = std::time::Duration::from_secs_f64(duration_secs);
        let mut poller: AdaptivePoller<String> =
            AdaptivePoller::from_preset(PollerPreset::Exposure);

        while start_time.elapsed() < duration {
            let progress = start_time.elapsed().as_secs_f64() / duration_secs;
            let progress_bucket = format!("{:.1}", progress); // Bucket progress for change detection

            get_state().publish_imaging_event(
                ImagingEvent::ExposureProgress {
                    progress,
                    remaining_secs: duration_secs - start_time.elapsed().as_secs_f64(),
                },
                EventSeverity::Info,
            );

            // Adaptive polling: backs off when progress isn't changing significantly
            let poll_interval = poller.tick(&progress_bucket);
            tokio::time::sleep(poll_interval).await;
        }

        // Update camera state to reading
        {
            let mut camera = get_sim_camera().write().await;
            camera.status.state = CameraState::Reading;
        }

        // Generate simulated image
        let sensor_width = 4144 / bin_x as u32;
        let sensor_height = 2822 / bin_y as u32;

        let (raw_data, display_data_raw, histogram, stats, star_count) =
            generate_simulated_image(sensor_width, sensor_height, gain, duration_secs);

        // Convert grayscale display data to RGBA for Flutter rendering
        let display_data = display_data_to_rgba(&display_data_raw, false);

        // Store all image data atomically to prevent race conditions
        // This ensures the UI never sees inconsistent state between raw and display data
        let display_result = CapturedImageResult {
            width: sensor_width,
            height: sensor_height,
            display_data,
            histogram,
            stats: ImageStatsResult {
                min: stats.min,
                max: stats.max,
                mean: stats.mean,
                median: stats.median,
                std_dev: stats.std_dev,
                hfr: Some(2.5 + (rand::random::<f64>() - 0.5) * 0.5), // Simulated HFR
                star_count,
            },
            exposure_time: duration_secs,
            timestamp: chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S").to_string(),
            is_color: false, // Simulated images are grayscale
        };

        let raw_info = RawImageInfo {
            width: sensor_width,
            height: sensor_height,
            data: raw_data,
            sensor_type: Some("Monochrome".to_string()), // Simulated camera is mono
            bayer_offset: None,
        };

        store_captured_image_atomically(&device_id, display_result, raw_info).await;

        // Update camera state back to idle
        {
            let mut camera = get_sim_camera().write().await;
            camera.status.state = CameraState::Idle;
        }

        // Publish exposure complete event
        get_state().publish_imaging_event(
            ImagingEvent::ExposureComplete { success: true },
            EventSeverity::Info,
        );

        tracing::info!("Exposure complete");
        Ok(())
    } else {
        // Real camera path - use UnifiedDeviceOps which routes through DeviceManager
        // Events (ExposureStarted, ExposureProgress, ExposureComplete) are published by UnifiedDeviceOps
        let device_ops = create_unified_device_ops();

        // Start exposure and get raw data (blocks until complete, events published by UnifiedDeviceOps)
        let seq_image = device_ops
            .camera_start_exposure(
                &device_id,
                duration_secs,
                Some(gain),
                Some(offset),
                bin_x,
                bin_y,
            )
            .await
            .map_err(|e| NightshadeError::OperationFailed(e.to_string()))?;

        // Convert SeqImageData to ImageData for processing
        let image = ImageData::from_u16(seq_image.width, seq_image.height, 1, &seq_image.data);

        // DIAGNOSTIC: Log raw data statistics to debug mid-gray image issue
        {
            let raw_data = &seq_image.data;
            if !raw_data.is_empty() {
                let min_val = raw_data.iter().min().copied().unwrap_or(0);
                let max_val = raw_data.iter().max().copied().unwrap_or(0);
                let sum: u64 = raw_data.iter().map(|&v| v as u64).sum();
                let mean_val = sum / raw_data.len() as u64;
                let unique_vals: std::collections::HashSet<_> =
                    raw_data.iter().take(10000).collect();
                tracing::info!(
                    "[DIAGNOSTIC] Raw image data: size={}, min={}, max={}, mean={}, unique_sample_count={}",
                    raw_data.len(), min_val, max_val, mean_val, unique_vals.len()
                );
                if max_val == min_val {
                    tracing::error!("[DIAGNOSTIC] WARNING: All pixels have same value! Data appears uniform/invalid.");
                } else if max_val < 100 {
                    tracing::warn!("[DIAGNOSTIC] WARNING: Max value is very low ({}), image may be underexposed or data corrupted.", max_val);
                } else if min_val > 60000 {
                    tracing::warn!("[DIAGNOSTIC] WARNING: Min value is very high ({}), image may be saturated.", min_val);
                }
            } else {
                tracing::error!("[DIAGNOSTIC] WARNING: Raw data is empty!");
            }
        }

        // Automatic color detection from camera metadata
        let is_color =
            seq_image.sensor_type.as_deref() == Some("Color") && seq_image.bayer_offset.is_some();

        // Determine Bayer pattern from offsets (if color)
        let bayer_pattern = if is_color {
            match seq_image.bayer_offset {
                Some((0, 0)) => BayerPattern::RGGB, // RGGB
                Some((1, 0)) => BayerPattern::GRBG, // GRBG
                Some((0, 1)) => BayerPattern::GBRG, // GBRG
                Some((1, 1)) => BayerPattern::BGGR, // BGGR
                _ => BayerPattern::RGGB,            // Default
            }
        } else {
            BayerPattern::RGGB // Doesn't matter for mono
        };

        let display_data_raw: Vec<u8>;

        if is_color {
            // Color debayering path
            let algorithm = DebayerAlgorithm::Bilinear;

            tracing::info!("Debayering color image with pattern {:?}", bayer_pattern);

            // 2. Debayer to RGB16 (if color)
            // Safe conversion from u8 buffer to u16 values
            if image.data.len() % 2 != 0 {
                return Err(NightshadeError::ImageError(
                    "Odd byte count in image data — cannot convert to u16 pixels".to_string(),
                ));
            }
            let u16_data: Vec<u16> = image
                .data
                .chunks_exact(2)
                .map(|b| u16::from_ne_bytes([b[0], b[1]]))
                .collect();

            let mut rgb_data = nightshade_imaging::debayer_to_rgb16(
                &u16_data,
                seq_image.width,
                seq_image.height,
                bayer_pattern,
                algorithm,
            );

            // 2.5. Apply Auto White Balance (Histogram Peak Alignment)
            apply_auto_white_balance(&mut rgb_data);

            // 3. Auto-stretch RGB (unified params for simplicity)
            let rgb_pixels: Vec<f64> = rgb_data.par_iter().map(|&v| v as f64 / 65535.0).collect();
            let mut sorted = rgb_pixels.clone();
            // Use unwrap_or for float comparison to handle NaN safely
            // NaN values are treated as equal to avoid panics
            sorted
                .par_sort_unstable_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
            if sorted.is_empty() {
                return Err(NightshadeError::ImageError(
                    "Empty image data for median calculation".to_string(),
                ));
            }
            let median = median_from_sorted_f64(&sorted).ok_or_else(|| {
                NightshadeError::ImageError("Empty image data for median calculation".to_string())
            })?;
            let unified_params = nightshade_imaging::StretchParams {
                shadows: (median - 0.1).max(0.0),
                highlights: (median + 0.3).min(1.0),
                midtones: 0.5,
            };

            // 4. Apply stretch to convert RGB u16 -> RGB u8
            display_data_raw = nightshade_imaging::apply_stretch_rgb(
                &rgb_data,
                seq_image.width,
                seq_image.height,
                &unified_params,
            );
        } else {
            // Grayscale: auto-stretch to u8
            let stretch_params = nightshade_imaging::auto_stretch_stf(&image);
            tracing::info!(
                "[DIAGNOSTIC] Stretch params: shadows={:.6}, highlights={:.6}, midtones={:.6}",
                stretch_params.shadows,
                stretch_params.highlights,
                stretch_params.midtones
            );
            display_data_raw = nightshade_imaging::apply_stretch(&image, &stretch_params);

            // Check display data distribution
            let display_min = display_data_raw.iter().min().copied().unwrap_or(0);
            let display_max = display_data_raw.iter().max().copied().unwrap_or(0);
            let display_sum: u64 = display_data_raw.iter().map(|&v| v as u64).sum();
            let display_mean = display_sum / display_data_raw.len() as u64;
            tracing::info!(
                "[DIAGNOSTIC] Display data after stretch: min={}, max={}, mean={}",
                display_min,
                display_max,
                display_mean
            );
        }

        // Calculate statistics
        let stats = nightshade_imaging::calculate_stats_u16(&image);
        let stars = nightshade_imaging::detect_stars(
            &image,
            &nightshade_imaging::StarDetectionConfig::default(),
        );
        let star_count = stars.len() as u32;

        // Compute median HFR from detected stars (top 50% brightest, capped at 50)
        let median_hfr = if !stars.is_empty() {
            let count = (stars.len() / 2).clamp(1, 50);
            let mut hfrs: Vec<f64> = stars
                .iter()
                .take(count)
                .map(|s| s.hfr)
                .filter(|&h| h > 0.0 && h < 20.0)
                .collect();
            if hfrs.is_empty() {
                None
            } else {
                hfrs.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                Some(hfrs[hfrs.len() / 2])
            }
        } else {
            None
        };
        tracing::info!(
            "Star detection: {} stars found, median HFR: {:?}",
            star_count,
            median_hfr
        );

        // Calculate histogram from pre-RGBA display data (256 bins for u8 pixel values)
        let mut histogram = vec![0u32; 256];
        for &pixel in &display_data_raw {
            histogram[pixel as usize] += 1;
        }

        // Convert to RGBA for Flutter rendering (parallel, fast in Rust)
        let display_data = display_data_to_rgba(&display_data_raw, is_color);

        // Store all image data atomically to prevent race conditions
        // This ensures the UI never sees inconsistent state between raw and display data
        let display_result = CapturedImageResult {
            width: seq_image.width,
            height: seq_image.height,
            display_data,
            histogram,
            stats: ImageStatsResult {
                min: stats.min,
                max: stats.max,
                mean: stats.mean,
                median: stats.median,
                std_dev: stats.std_dev,
                hfr: median_hfr,
                star_count,
            },
            exposure_time: duration_secs,
            timestamp: chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S").to_string(),
            is_color,
        };

        let raw_info = RawImageInfo {
            width: seq_image.width,
            height: seq_image.height,
            data: seq_image.data.clone(),
            sensor_type: seq_image.sensor_type.clone(),
            bayer_offset: seq_image.bayer_offset,
        };

        store_captured_image_atomically(&device_id, display_result, raw_info).await;

        // Note: ExposureComplete event is published by UnifiedDeviceOps
        tracing::info!(
            "Real camera exposure complete, {} stars detected",
            star_count
        );
        Ok(())
    }
}

/// Get the last captured image for a specific device (display-ready format)
/// Reads from per-device atomic storage to ensure consistency with raw data
pub async fn api_get_last_image(device_id: String) -> Result<CapturedImageResult, NightshadeError> {
    tracing::info!("API: api_get_last_image called for device: {}", device_id);
    let storage = get_unified_image_storage().read().await;
    match storage.get(&device_id) {
        Some(data) => {
            tracing::info!(
                "API: Returning stored image {}x{}, display_data size: {} bytes",
                data.display.width,
                data.display.height,
                data.display.display_data.len()
            );
            Ok(data.display.clone())
        }
        None => {
            tracing::warn!("API: No image available for device: {}", device_id);
            Err(NightshadeError::NoImageAvailable)
        }
    }
}

/// Get the last captured raw image data (u16) for a specific device
/// This is used for saving FITS files with original bit depth
/// Reads from per-device atomic storage to ensure consistency with display data
pub async fn api_get_last_raw_image_data(device_id: String) -> Result<Vec<u16>, NightshadeError> {
    let storage = get_unified_image_storage().read().await;
    storage
        .get(&device_id)
        .map(|data| data.raw_info.data.clone())
        .ok_or(NightshadeError::NoImageAvailable)
}

/// Get the last captured raw image info with full metadata for a specific device
/// This is used by the sequencer for HFR calculation, plate solving, and other analysis
/// that requires original 16-bit sensor data (not display-stretched 8-bit data)
/// Reads from per-device atomic storage to ensure consistency with display data
#[flutter_rust_bridge::frb(ignore)]
pub async fn get_last_raw_image_info(
    device_id: &str,
) -> Result<Option<RawImageInfo>, NightshadeError> {
    let storage = get_unified_image_storage().read().await;
    Ok(storage.get(device_id).map(|data| data.raw_info.clone()))
}

/// Clear stored image data for a specific device
/// This is used to free memory when a camera is disconnected or when explicitly requested
pub async fn api_clear_device_image(device_id: String) -> Result<(), NightshadeError> {
    tracing::info!("API: Clearing stored image for device: {}", device_id);
    let mut storage = get_unified_image_storage().write().await;
    storage.remove(&device_id);
    Ok(())
}

/// Cancel current exposure
pub async fn api_camera_cancel_exposure(device_id: String) -> Result<(), NightshadeError> {
    if device_id.starts_with("sim_") {
        let mut camera = get_sim_camera().write().await;
        camera.status.state = CameraState::Idle;
        tracing::info!("Exposure cancelled");
        Ok(())
    } else {
        // Route real devices through DeviceManager
        let mgr = get_device_manager();
        mgr.camera_abort_exposure(&device_id)
            .await
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Generate a simulated star field image
fn generate_simulated_image(
    width: u32,
    height: u32,
    gain: i32,
    exposure_time: f64,
) -> (
    Vec<u16>,
    Vec<u8>,
    Vec<u32>,
    nightshade_imaging::ImageStats,
    u32,
) {
    let mut rng = rand::thread_rng();
    let pixel_count = (width * height) as usize;

    // Create raw 16-bit image data
    let mut raw_data: Vec<u16> = vec![0u16; pixel_count];

    // Background level based on gain and exposure
    let base_background = 500 + (gain as f64 * 5.0 + exposure_time * 10.0) as u16;
    let noise_level = (50.0 + gain as f64 * 0.5) as u16;

    // Fill with background + noise
    for pixel in &mut raw_data {
        let noise = (rng.gen::<f64>() * noise_level as f64) as i32;
        *pixel = (base_background as i32 + noise - noise_level as i32 / 2).clamp(0, 65535) as u16;
    }

    // Add stars (more with longer exposure)
    let num_stars = (100.0 + exposure_time * 50.0).min(500.0) as u32;
    let mut star_count = 0u32;

    for _ in 0..num_stars {
        let x = rng.gen_range(5..width - 5);
        let y = rng.gen_range(5..height - 5);
        let brightness = rng.gen_range(5000u16..60000u16);
        let size = rng.gen_range(1.5f64..4.0f64);

        // Draw Gaussian star profile
        let radius = (size * 3.0) as i32;
        for dy in -radius..=radius {
            for dx in -radius..=radius {
                let px = (x as i32 + dx) as u32;
                let py = (y as i32 + dy) as u32;

                if px < width && py < height {
                    let dist_sq = (dx * dx + dy * dy) as f64;
                    let sigma_sq = size * size;
                    let intensity = brightness as f64 * (-dist_sq / (2.0 * sigma_sq)).exp();

                    let idx = (py * width + px) as usize;
                    raw_data[idx] = (raw_data[idx] as f64 + intensity).min(65535.0) as u16;
                }
            }
        }
        star_count += 1;
    }

    // Add some hot pixels
    for _ in 0..20 {
        let idx = rng.gen_range(0..pixel_count);
        raw_data[idx] = rng.gen_range(40000u16..65535u16);
    }

    // Create ImageData for stats calculation
    let image_bytes: Vec<u8> = raw_data.iter().flat_map(|&val| val.to_le_bytes()).collect();

    let image_data = nightshade_imaging::ImageData {
        width,
        height,
        channels: 1,
        pixel_type: nightshade_imaging::PixelType::U16,
        data: image_bytes.clone(),
    };

    // Calculate stats
    let stats = nightshade_imaging::calculate_stats_u16(&image_data);

    // Auto stretch for display
    let stretch_params = nightshade_imaging::auto_stretch_stf(&image_data);
    let display_data = nightshade_imaging::apply_stretch(&image_data, &stretch_params);

    // Calculate histogram from display data
    let mut histogram = vec![0u32; 256];
    for &pixel in &display_data {
        histogram[pixel as usize] += 1;
    }

    (raw_data, display_data, histogram, stats, star_count)
}

/// Internal random utilities - not exposed to Dart FFI
#[flutter_rust_bridge::frb(ignore)]
pub mod rand {
    use std::time::{SystemTime, UNIX_EPOCH};

    // Note: Range is NOT re-exported because FRB generates invalid code for Range<Self>
    // The gen_range function is marked as ignored by FRB anyway

    #[flutter_rust_bridge::frb(ignore)]
    pub fn random<T: RandomValue>() -> T {
        T::random()
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub trait RandomValue {
        fn random() -> Self;
    }

    #[flutter_rust_bridge::frb(ignore)]
    impl RandomValue for f64 {
        fn random() -> Self {
            // Use unwrap_or with a fallback value to avoid panic
            // SystemTime::now() can fail if system clock is set before UNIX_EPOCH
            let seed = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or(std::time::Duration::from_secs(0))
                .as_nanos() as u64;
            // Simple LCG - even with seed=0, this produces valid output
            let x = seed
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            (x as f64) / (u64::MAX as f64)
        }
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub struct Rng {
        pub state: u64,
    }

    #[flutter_rust_bridge::frb(ignore)]
    impl Rng {
        pub fn gen<T: RandomValue>(&mut self) -> T {
            T::random()
        }

        pub fn gen_range<T: RandomRange>(&mut self, range: std::ops::Range<T>) -> T {
            // Use unwrap_or with a fallback to avoid panic on clock issues
            let seed = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or(std::time::Duration::from_secs(0))
                .as_nanos() as u64;
            self.state = self
                .state
                .wrapping_mul(6364136223846793005)
                .wrapping_add(seed);
            T::in_range(self.state, range)
        }
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub trait RandomRange: Sized {
        fn in_range(seed: u64, range: std::ops::Range<Self>) -> Self;
    }

    #[flutter_rust_bridge::frb(ignore)]
    impl RandomRange for u32 {
        fn in_range(seed: u64, range: std::ops::Range<Self>) -> Self {
            let span = range.end - range.start;
            range.start + (seed as u32 % span)
        }
    }

    #[flutter_rust_bridge::frb(ignore)]
    impl RandomRange for u16 {
        fn in_range(seed: u64, range: std::ops::Range<Self>) -> Self {
            let span = range.end - range.start;
            range.start + (seed as u16 % span)
        }
    }

    #[flutter_rust_bridge::frb(ignore)]
    impl RandomRange for f64 {
        fn in_range(seed: u64, range: std::ops::Range<Self>) -> Self {
            let t = (seed as f64) / (u64::MAX as f64);
            range.start + t * (range.end - range.start)
        }
    }

    #[flutter_rust_bridge::frb(ignore)]
    impl RandomRange for usize {
        fn in_range(seed: u64, range: std::ops::Range<Self>) -> Self {
            let span = range.end - range.start;
            range.start + (seed as usize % span)
        }
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub fn thread_rng() -> Rng {
        // Use unwrap_or with a fallback to avoid panic on clock issues
        let seed = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or(std::time::Duration::from_secs(0))
            .as_nanos() as u64;
        Rng { state: seed }
    }
}

// =============================================================================
// Session Management
// =============================================================================

/// Get current session state
pub async fn api_get_session_state() -> SessionState {
    get_state().get_session().await
}

/// Start a new imaging session
pub async fn api_start_session(
    target_name: Option<String>,
    ra: Option<f64>,
    dec: Option<f64>,
) -> Result<(), NightshadeError> {
    get_state().start_session(target_name, ra, dec).await;
    tracing::info!("Session started");
    Ok(())
}

/// End the current session
pub async fn api_end_session() -> Result<(), NightshadeError> {
    get_state().end_session().await;
    tracing::info!("Session ended");
    Ok(())
}

// =============================================================================
// REAL FITS FILE OPERATIONS
// =============================================================================

/// Result from reading a FITS file
#[derive(Debug, Clone)]
pub struct FitsReadResult {
    pub width: u32,
    pub height: u32,
    pub bitpix: i32,
    pub display_data: Vec<u8>, // Always RGBA (width*height*4), alpha=255
    pub histogram: Vec<u32>,
    pub stats: ImageStatsResult,
    pub object_name: Option<String>,
    pub exposure_time: Option<f64>,
    pub filter: Option<String>,
    pub ra: Option<f64>,
    pub dec: Option<f64>,
    pub date_obs: Option<String>,
    pub bayer_pattern: Option<String>,
}

/// Result from reading FITS file linear pixel data.
/// This is intended for scientific workflows that require unstretched values.
#[derive(Debug, Clone)]
pub struct FitsLinearReadResult {
    pub width: u32,
    pub height: u32,
    pub bitpix: i32,
    pub linear_data: Vec<f64>,
    pub object_name: Option<String>,
    pub exposure_time: Option<f64>,
    pub filter: Option<String>,
    pub ra: Option<f64>,
    pub dec: Option<f64>,
    pub date_obs: Option<String>,
    pub bayer_pattern: Option<String>,
}

/// Frame-level quality metrics for Science visualizations.
#[derive(Debug, Clone)]
pub struct QualityFrameMetricsApi {
    pub median: f64,
    pub mean: f64,
    pub std_dev: f64,
    pub mad: f64,
    pub background: f64,
    pub noise: f64,
    pub snr: f64,
    pub dynamic_range_p1_p99: f64,
    pub low_clip_percent: f64,
    pub high_clip_percent: f64,
    pub uniformity_cv: f64,
    pub gradient_x: f64,
    pub gradient_y: f64,
    pub processing_tier: String,
    pub processing_ms: u32,
}

/// Tile-level quality metrics for Science overlays/surfaces.
#[derive(Debug, Clone)]
pub struct QualityTileMetricApi {
    pub layer_type: String,
    pub tile_row: u32,
    pub tile_col: u32,
    pub sample_count: u32,
    pub value: f64,
    pub p05: f64,
    pub p50: f64,
    pub p95: f64,
    pub aux_value: f64,
}

/// Result container for quality map computation endpoints.
#[derive(Debug, Clone)]
pub struct QualityMapsResultApi {
    pub frame: QualityFrameMetricsApi,
    pub tiles: Vec<QualityTileMetricApi>,
}

fn image_data_to_linear_f64(image_data: &ImageData) -> Vec<f64> {
    match image_data.pixel_type {
        nightshade_imaging::PixelType::U8 => image_data
            .data
            .iter()
            .map(|&value| value as f64)
            .collect::<Vec<f64>>(),
        nightshade_imaging::PixelType::U16 => image_data
            .data
            .chunks_exact(2)
            .map(|chunk| u16::from_be_bytes([chunk[0], chunk[1]]) as f64)
            .collect::<Vec<f64>>(),
        nightshade_imaging::PixelType::U32 => image_data
            .data
            .chunks_exact(4)
            .map(|chunk| u32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]) as f64)
            .collect::<Vec<f64>>(),
        nightshade_imaging::PixelType::F32 => image_data
            .data
            .chunks_exact(4)
            .map(|chunk| f32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]) as f64)
            .collect::<Vec<f64>>(),
        nightshade_imaging::PixelType::F64 => image_data
            .data
            .chunks_exact(8)
            .map(|chunk| {
                f64::from_be_bytes([
                    chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6], chunk[7],
                ])
            })
            .collect::<Vec<f64>>(),
    }
}

/// Read a FITS file from disk
pub async fn api_read_fits_file(file_path: String) -> Result<FitsReadResult, NightshadeError> {
    use std::path::Path;

    tracing::info!("Reading FITS file: {}", file_path);

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    // Read the actual FITS file
    let (image_data, header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    // Extract header keywords
    let object_name = header.get_string("OBJECT").map(|s| s.to_string());
    let exposure_time = header.get_float("EXPTIME");
    let filter = header.get_string("FILTER").map(|s| s.to_string());
    let ra = header.get_float("RA");
    let dec = header.get_float("DEC");
    let date_obs = header.get_string("DATE-OBS").map(|s| s.to_string());
    let bitpix = header.get_int("BITPIX").unwrap_or(16) as i32;
    let bayer_pattern = header.get_string("BAYERPAT").map(|s| s.to_string());

    // Calculate statistics
    let stats = nightshade_imaging::calculate_stats_u16(&image_data);

    // Auto stretch for display
    let stretch_params = nightshade_imaging::auto_stretch_stf(&image_data);
    let display_data_raw = nightshade_imaging::apply_stretch(&image_data, &stretch_params);

    // Calculate histogram from pre-RGBA data
    let mut histogram = vec![0u32; 256];
    for &pixel in &display_data_raw {
        histogram[pixel as usize] += 1;
    }

    // Convert grayscale to RGBA for Flutter rendering
    let display_data = display_data_to_rgba(&display_data_raw, false);

    tracing::info!(
        "FITS file loaded: {}x{}, {} pixels",
        image_data.width,
        image_data.height,
        image_data.width * image_data.height
    );

    Ok(FitsReadResult {
        width: image_data.width,
        height: image_data.height,
        bitpix,
        display_data,
        histogram,
        stats: ImageStatsResult {
            min: stats.min,
            max: stats.max,
            mean: stats.mean,
            median: stats.median,
            std_dev: stats.std_dev,
            hfr: None,
            star_count: 0,
        },
        object_name,
        exposure_time,
        filter,
        ra,
        dec,
        date_obs,
        bayer_pattern,
    })
}

/// Read a FITS file and return unstretched linear pixel values for science analysis.
pub async fn api_read_fits_linear_data(
    file_path: String,
) -> Result<FitsLinearReadResult, NightshadeError> {
    use std::path::Path;

    tracing::info!("Reading FITS linear data: {}", file_path);

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    let (image_data, header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    let object_name = header.get_string("OBJECT").map(|s| s.to_string());
    let exposure_time = header.get_float("EXPTIME");
    let filter = header.get_string("FILTER").map(|s| s.to_string());
    let ra = header.get_float("RA");
    let dec = header.get_float("DEC");
    let date_obs = header.get_string("DATE-OBS").map(|s| s.to_string());
    let bitpix = header.get_int("BITPIX").unwrap_or(16) as i32;
    let bayer_pattern = header.get_string("BAYERPAT").map(|s| s.to_string());
    let linear_data = image_data_to_linear_f64(&image_data);

    Ok(FitsLinearReadResult {
        width: image_data.width,
        height: image_data.height,
        bitpix,
        linear_data,
        object_name,
        exposure_time,
        filter,
        ra,
        dec,
        date_obs,
        bayer_pattern,
    })
}

fn percentile_sorted(sorted_values: &[f64], p: f64) -> f64 {
    if sorted_values.is_empty() {
        return 0.0;
    }
    let q = p.clamp(0.0, 1.0);
    let pos = ((sorted_values.len() - 1) as f64) * q;
    let lo = pos.floor() as usize;
    let hi = pos.ceil() as usize;
    if lo == hi {
        return sorted_values[lo];
    }
    let t = pos - lo as f64;
    sorted_values[lo] * (1.0 - t) + sorted_values[hi] * t
}

fn percentile(values: &[f64], p: f64) -> f64 {
    let mut sorted = values
        .iter()
        .copied()
        .filter(|value| value.is_finite())
        .collect::<Vec<_>>();
    if sorted.is_empty() {
        return 0.0;
    }
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    percentile_sorted(&sorted, p)
}

fn median(values: &[f64]) -> f64 {
    percentile(values, 0.5)
}

fn median_from_sorted_f64(sorted: &[f64]) -> Option<f64> {
    if sorted.is_empty() {
        return None;
    }

    let mid = sorted.len() / 2;
    if sorted.len() % 2 == 0 {
        Some((sorted[mid - 1] + sorted[mid]) / 2.0)
    } else {
        Some(sorted[mid])
    }
}

fn mad(values: &[f64], median_value: f64) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    let deviations = values
        .iter()
        .copied()
        .filter(|value| value.is_finite())
        .map(|value| (value - median_value).abs())
        .collect::<Vec<_>>();
    median(&deviations)
}

fn compute_quality_maps_from_linear_data(
    width: usize,
    height: usize,
    linear_data: &[f64],
    grid_rows: u32,
    grid_cols: u32,
    low_clip_adu: u32,
    high_clip_adu: u32,
    processing_tier: &str,
) -> Result<QualityMapsResultApi, NightshadeError> {
    if width == 0 || height == 0 {
        return Err(NightshadeError::InvalidInput(
            "Image dimensions must be non-zero".to_string(),
        ));
    }

    let expected = width.saturating_mul(height);
    if linear_data.len() < expected {
        return Err(NightshadeError::InvalidInput(format!(
            "Linear buffer too small: {} < {}",
            linear_data.len(),
            expected
        )));
    }

    let rows = grid_rows.clamp(2, 128) as usize;
    let cols = grid_cols.clamp(2, 128) as usize;
    let low_clip = low_clip_adu as f64;
    let high_clip = high_clip_adu as f64;

    let mut tile_metrics = Vec::with_capacity(rows * cols * 5);
    let mut tile_medians = Vec::with_capacity(rows * cols);
    let mut tile_noises = Vec::with_capacity(rows * cols);
    let mut tile_p05 = Vec::with_capacity(rows * cols);
    let mut tile_p95 = Vec::with_capacity(rows * cols);
    let mut tile_grad_x = Vec::with_capacity(rows * cols);
    let mut tile_grad_y = Vec::with_capacity(rows * cols);

    let mut global_count: usize = 0;
    let mut global_sum = 0.0;
    let mut global_sum_sq = 0.0;
    let mut global_low_clip: usize = 0;
    let mut global_high_clip: usize = 0;

    let image_mid_x = width / 2;
    let image_mid_y = height / 2;

    for row in 0..rows {
        let y_start = (row * height) / rows;
        let mut y_end = ((row + 1) * height) / rows;
        if y_end <= y_start {
            y_end = (y_start + 1).min(height);
        }

        for col in 0..cols {
            let x_start = (col * width) / cols;
            let mut x_end = ((col + 1) * width) / cols;
            if x_end <= x_start {
                x_end = (x_start + 1).min(width);
            }

            let mut samples = Vec::new();
            let mut sum = 0.0;
            let mut sum_sq = 0.0;
            let mut tile_low_clip: usize = 0;
            let mut tile_high_clip: usize = 0;
            let mut left_sum = 0.0;
            let mut right_sum = 0.0;
            let mut top_sum = 0.0;
            let mut bottom_sum = 0.0;
            let mut left_count: usize = 0;
            let mut right_count: usize = 0;
            let mut top_count: usize = 0;
            let mut bottom_count: usize = 0;

            for y in y_start..y_end {
                let is_top = y < image_mid_y;
                let row_base = y * width;
                for x in x_start..x_end {
                    let value = linear_data[row_base + x];
                    if !value.is_finite() {
                        continue;
                    }

                    samples.push(value);
                    sum += value;
                    sum_sq += value * value;
                    global_sum += value;
                    global_sum_sq += value * value;
                    global_count += 1;

                    if value <= low_clip {
                        tile_low_clip += 1;
                        global_low_clip += 1;
                    }
                    if value >= high_clip {
                        tile_high_clip += 1;
                        global_high_clip += 1;
                    }

                    if x < image_mid_x {
                        left_sum += value;
                        left_count += 1;
                    } else {
                        right_sum += value;
                        right_count += 1;
                    }

                    if is_top {
                        top_sum += value;
                        top_count += 1;
                    } else {
                        bottom_sum += value;
                        bottom_count += 1;
                    }
                }
            }

            if samples.is_empty() {
                continue;
            }

            samples.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

            let count = samples.len();
            let count_f64 = count as f64;
            let mean_value = sum / count_f64;
            let variance = ((sum_sq / count_f64) - (mean_value * mean_value)).max(0.0);
            let std_dev = variance.sqrt();
            let p05 = percentile_sorted(&samples, 0.05);
            let p50 = percentile_sorted(&samples, 0.50);
            let p95 = percentile_sorted(&samples, 0.95);
            let cv = if mean_value.abs() < 1e-6 {
                0.0
            } else {
                std_dev / mean_value.abs()
            };
            let low_clip_percent = 100.0 * (tile_low_clip as f64) / count_f64;
            let high_clip_percent = 100.0 * (tile_high_clip as f64) / count_f64;
            let snr = if std_dev <= 0.0 {
                0.0
            } else {
                mean_value / std_dev
            };

            let left_mean = if left_count == 0 {
                mean_value
            } else {
                left_sum / left_count as f64
            };
            let right_mean = if right_count == 0 {
                mean_value
            } else {
                right_sum / right_count as f64
            };
            let top_mean = if top_count == 0 {
                mean_value
            } else {
                top_sum / top_count as f64
            };
            let bottom_mean = if bottom_count == 0 {
                mean_value
            } else {
                bottom_sum / bottom_count as f64
            };
            let grad_x = right_mean - left_mean;
            let grad_y = bottom_mean - top_mean;
            let grad_mag = (grad_x * grad_x + grad_y * grad_y).sqrt();

            tile_medians.push(p50);
            tile_noises.push(std_dev);
            tile_p05.push(p05);
            tile_p95.push(p95);
            tile_grad_x.push(grad_x);
            tile_grad_y.push(grad_y);

            let tile_row = row as u32;
            let tile_col = col as u32;
            let sample_count = count.min(u32::MAX as usize) as u32;
            tile_metrics.push(QualityTileMetricApi {
                layer_type: "uniformity".to_string(),
                tile_row,
                tile_col,
                sample_count,
                value: cv,
                p05,
                p50,
                p95,
                aux_value: grad_mag,
            });
            tile_metrics.push(QualityTileMetricApi {
                layer_type: "clip_low".to_string(),
                tile_row,
                tile_col,
                sample_count,
                value: low_clip_percent,
                p05: low_clip_percent,
                p50: low_clip_percent,
                p95: low_clip_percent,
                aux_value: tile_low_clip as f64,
            });
            tile_metrics.push(QualityTileMetricApi {
                layer_type: "clip_high".to_string(),
                tile_row,
                tile_col,
                sample_count,
                value: high_clip_percent,
                p05: high_clip_percent,
                p50: high_clip_percent,
                p95: high_clip_percent,
                aux_value: tile_high_clip as f64,
            });
            tile_metrics.push(QualityTileMetricApi {
                layer_type: "background".to_string(),
                tile_row,
                tile_col,
                sample_count,
                value: p50,
                p05,
                p50,
                p95,
                aux_value: std_dev,
            });
            tile_metrics.push(QualityTileMetricApi {
                layer_type: "snr".to_string(),
                tile_row,
                tile_col,
                sample_count,
                value: snr,
                p05: 0.0,
                p50: snr,
                p95: snr,
                aux_value: std_dev,
            });
        }
    }

    let safe_count = global_count.max(1) as f64;
    let global_mean = global_sum / safe_count;
    let global_std_dev = ((global_sum_sq / safe_count) - (global_mean * global_mean))
        .max(0.0)
        .sqrt();
    let median_value = if tile_medians.is_empty() {
        0.0
    } else {
        median(&tile_medians)
    };
    let mad_value = if tile_medians.is_empty() {
        0.0
    } else {
        mad(&tile_medians, median_value)
    };
    let background = if tile_medians.is_empty() {
        global_mean
    } else {
        median(&tile_medians)
    };
    let noise = if tile_noises.is_empty() {
        global_std_dev
    } else {
        median(&tile_noises)
    };
    let snr = if noise <= 0.0 {
        0.0
    } else {
        global_mean / noise
    };
    let p1 = if tile_p05.is_empty() {
        0.0
    } else {
        percentile(&tile_p05, 0.2)
    };
    let p99 = if tile_p95.is_empty() {
        0.0
    } else {
        percentile(&tile_p95, 0.8)
    };
    let dynamic_range = (p99 - p1).max(0.0);
    let gradient_x = if tile_grad_x.is_empty() {
        0.0
    } else {
        tile_grad_x.iter().sum::<f64>() / tile_grad_x.len() as f64
    };
    let gradient_y = if tile_grad_y.is_empty() {
        0.0
    } else {
        tile_grad_y.iter().sum::<f64>() / tile_grad_y.len() as f64
    };

    Ok(QualityMapsResultApi {
        frame: QualityFrameMetricsApi {
            median: median_value,
            mean: global_mean,
            std_dev: global_std_dev,
            mad: mad_value,
            background,
            noise,
            snr,
            dynamic_range_p1_p99: dynamic_range,
            low_clip_percent: 100.0 * (global_low_clip as f64) / safe_count,
            high_clip_percent: 100.0 * (global_high_clip as f64) / safe_count,
            uniformity_cv: if background.abs() < 1e-6 {
                0.0
            } else {
                global_std_dev / background.abs()
            },
            gradient_x,
            gradient_y,
            processing_tier: processing_tier.to_string(),
            processing_ms: 0,
        },
        tiles: tile_metrics,
    })
}

/// Compute quality maps from the last captured image in memory for a device.
pub async fn api_compute_last_capture_quality_maps(
    device_id: String,
    grid_rows: u32,
    grid_cols: u32,
    low_clip_adu: u32,
    high_clip_adu: u32,
) -> Result<QualityMapsResultApi, NightshadeError> {
    let started = Instant::now();
    let raw_info = get_last_raw_image_info(&device_id)
        .await?
        .ok_or(NightshadeError::NoImageAvailable)?;

    let width = raw_info.width as usize;
    let height = raw_info.height as usize;
    let linear_data = raw_info
        .data
        .iter()
        .map(|value| *value as f64)
        .collect::<Vec<_>>();

    let mut result = compute_quality_maps_from_linear_data(
        width,
        height,
        &linear_data,
        grid_rows,
        grid_cols,
        low_clip_adu,
        high_clip_adu,
        "live",
    )?;
    result.frame.processing_ms = started.elapsed().as_millis().min(u32::MAX as u128) as u32;
    Ok(result)
}

/// Compute quality maps directly from a FITS file.
pub async fn api_compute_fits_quality_maps(
    file_path: String,
    grid_rows: u32,
    grid_cols: u32,
    low_clip_adu: u32,
    high_clip_adu: u32,
) -> Result<QualityMapsResultApi, NightshadeError> {
    use std::path::Path;

    let started = Instant::now();
    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;
    let linear_data = image_data_to_linear_f64(&image_data);

    let mut result = compute_quality_maps_from_linear_data(
        image_data.width as usize,
        image_data.height as usize,
        &linear_data,
        grid_rows,
        grid_cols,
        low_clip_adu,
        high_clip_adu,
        "deferred",
    )?;
    result.frame.processing_ms = started.elapsed().as_millis().min(u32::MAX as u128) as u32;
    Ok(result)
}

#[cfg(test)]
mod quality_map_tests {
    use super::compute_quality_maps_from_linear_data;

    fn approx_eq(actual: f64, expected: f64, tolerance: f64) {
        assert!(
            (actual - expected).abs() <= tolerance,
            "expected {expected}, got {actual} (tol={tolerance})"
        );
    }

    #[test]
    fn computes_expected_clip_metrics_for_uniform_black_frame() {
        let data = vec![0.0; 16];
        let result =
            compute_quality_maps_from_linear_data(4, 4, &data, 2, 2, 0, 65535, "live").unwrap();

        approx_eq(result.frame.low_clip_percent, 100.0, 1e-9);
        approx_eq(result.frame.high_clip_percent, 0.0, 1e-9);
        assert_eq!(result.frame.processing_tier, "live");
        assert_eq!(result.tiles.len(), 20); // 2x2 tiles * 5 layers
    }

    #[test]
    fn computes_expected_clip_metrics_for_ramp_frame() {
        let data = (0..16).map(|value| value as f64).collect::<Vec<_>>();
        let result =
            compute_quality_maps_from_linear_data(4, 4, &data, 2, 2, 0, 15, "deferred").unwrap();

        // One sample clipped low (0), one clipped high (15) out of 16 total.
        approx_eq(result.frame.low_clip_percent, 6.25, 1e-9);
        approx_eq(result.frame.high_clip_percent, 6.25, 1e-9);
        assert_eq!(result.frame.processing_tier, "deferred");
        assert_eq!(result.tiles.len(), 20);
    }
}

/// FITS header for writing
// =============================================================================
// STAR DETECTION AND IMAGE ANALYSIS
// =============================================================================

/// Detected star information
#[derive(Debug, Clone)]
pub struct DetectedStarInfo {
    pub x: f64,
    pub y: f64,
    pub flux: f64,
    pub hfr: f64,
    pub fwhm: f64,
    pub peak: f64,
    pub background: f64,
    pub snr: f64,
    /// Eccentricity: 0 = perfect circle, 1 = line (elongated)
    pub eccentricity: f64,
    /// Sharpness: ratio of peak to spread - hot pixels have high sharpness
    pub sharpness: f64,
}

/// Star detection result
#[derive(Debug, Clone)]
pub struct StarDetectionResultApi {
    pub stars: Vec<DetectedStarInfo>,
    pub star_count: u32,
    pub median_hfr: f64,
    pub median_fwhm: f64,
    pub median_snr: f64,
    pub background: f64,
    pub noise: f64,
}

/// Star detection configuration
#[derive(Debug, Clone)]
#[flutter_rust_bridge::frb]
pub struct StarDetectionConfigApi {
    pub detection_sigma: f64,
    pub min_area: u32,
    pub max_area: u32,
    pub max_eccentricity: f64,
    pub saturation_limit: u32,
    pub hfr_radius: u32,
    /// Minimum HFR to be considered a real star (filters hot pixels)
    pub min_hfr: Option<f64>,
    /// Minimum SNR to be considered a valid detection
    pub min_snr: Option<f64>,
    /// Maximum sharpness (filters hot pixels which have very high sharpness)
    pub max_sharpness: Option<f64>,
}

impl Default for StarDetectionConfigApi {
    fn default() -> Self {
        Self {
            detection_sigma: 5.0,
            min_area: 9,
            max_area: 10000,
            max_eccentricity: 0.7,
            saturation_limit: 60000,
            hfr_radius: 20,
            min_hfr: Some(1.0), // Real stars have HFR > ~1.0; hot pixels < 0.8
            min_snr: Some(5.0), // Modest SNR threshold - real stars in short subs can be faint
            max_sharpness: Some(0.95), // Only reject extreme hot pixels (sharpness ~1.0)
        }
    }
}

/// Detect stars in a FITS file
pub async fn api_detect_stars_in_file(
    file_path: String,
    config: Option<StarDetectionConfigApi>,
) -> Result<StarDetectionResultApi, NightshadeError> {
    use std::path::Path;

    tracing::info!("Detecting stars in: {}", file_path);

    let path = Path::new(&file_path);
    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    let config = config.unwrap_or_default();
    let detection_config = nightshade_imaging::StarDetectionConfig {
        detection_sigma: config.detection_sigma,
        min_area: config.min_area,
        max_area: config.max_area,
        max_eccentricity: config.max_eccentricity,
        saturation_limit: config.saturation_limit as u16,
        hfr_radius: config.hfr_radius,
        min_hfr: config.min_hfr.unwrap_or(1.0),
        min_snr: config.min_snr.unwrap_or(5.0),
        max_sharpness: config.max_sharpness.unwrap_or(0.95),
        noise_model: None,
    };

    let result = nightshade_imaging::detect_stars_with_stats(&image_data, &detection_config);

    let stars: Vec<DetectedStarInfo> = result
        .stars
        .iter()
        .map(|s| DetectedStarInfo {
            x: s.x,
            y: s.y,
            flux: s.flux,
            hfr: s.hfr,
            fwhm: s.fwhm,
            peak: s.peak,
            background: s.background,
            snr: s.snr,
            eccentricity: s.eccentricity,
            sharpness: s.sharpness,
        })
        .collect();

    tracing::info!(
        "Detected {} stars, median HFR: {:.2}",
        result.star_count,
        result.median_hfr
    );

    Ok(StarDetectionResultApi {
        stars,
        star_count: result.star_count,
        median_hfr: result.median_hfr,
        median_fwhm: result.median_fwhm,
        median_snr: result.median_snr,
        background: result.background,
        noise: result.noise,
    })
}

/// Star crop data for UI display
#[derive(Debug, Clone)]
pub struct StarCropApi {
    /// Base64-encoded grayscale pixel data
    pub pixels_base64: String,
    /// Width of the crop
    pub width: u32,
    /// Height of the crop
    pub height: u32,
    /// HFR of this star
    pub hfr: f64,
    /// SNR of this star
    pub snr: f64,
}

/// Get star crops from the last captured image for a device
///
/// This extracts the top N brightest stars from the last image and returns
/// cropped 80x80 pixel regions centered on each star, auto-stretched for display.
/// Used by the autofocus UI to show star crops for visual feedback.
pub async fn api_get_star_crops_from_last_image(
    device_id: String,
    max_crops: u32,
) -> Result<Vec<StarCropApi>, NightshadeError> {
    use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};

    tracing::info!(
        "API: api_get_star_crops_from_last_image for device: {}, max_crops: {}",
        device_id,
        max_crops
    );

    // Get the last raw image for this device
    let storage = get_unified_image_storage().read().await;
    let image_data = storage
        .get(&device_id)
        .ok_or(NightshadeError::NoImageAvailable)?;

    // Convert to imaging format
    let img = nightshade_imaging::ImageData::from_u16(
        image_data.raw_info.width,
        image_data.raw_info.height,
        1,
        &image_data.raw_info.data,
    );

    // Detect stars
    let config = nightshade_imaging::StarDetectionConfig::default();
    let stars = nightshade_imaging::detect_stars(&img, &config);

    if stars.is_empty() {
        tracing::info!("No stars detected for star crop extraction");
        return Ok(vec![]);
    }

    // Extract top star crops (80x80 pixels each)
    let crops = nightshade_imaging::extract_top_star_crops(&img, &stars, max_crops as usize, 80);

    // Convert to API format
    let result: Vec<StarCropApi> = crops
        .iter()
        .map(|crop| StarCropApi {
            pixels_base64: BASE64.encode(&crop.pixels),
            width: crop.width,
            height: crop.height,
            hfr: crop.hfr,
            snr: crop.snr,
        })
        .collect();

    tracing::info!("Extracted {} star crops", result.len());
    Ok(result)
}

/// Calculate HFR for a FITS file
pub async fn api_calculate_hfr(file_path: String) -> Result<Option<f64>, NightshadeError> {
    use std::path::Path;

    let path = Path::new(&file_path);
    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    Ok(nightshade_imaging::calculate_median_hfr(&image_data))
}

/// Calculate histogram for a FITS file
pub async fn api_calculate_histogram(
    file_path: String,
    _bins: u32,
    logarithmic: u8,
) -> Result<Vec<f32>, NightshadeError> {
    use std::path::Path;

    let path = Path::new(&file_path);
    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    let logarithmic_bool = logarithmic != 0;
    let histogram = nightshade_imaging::calculate_display_histogram(&image_data, logarithmic_bool);
    Ok(histogram)
}

/// Stretch parameters for manual control
#[derive(Debug, Clone)]
pub struct StretchParamsApi {
    pub shadows: f64,
    pub highlights: f64,
    pub midtones: f64,
}

/// Auto-calculate stretch parameters for an image
pub async fn api_calculate_auto_stretch(
    file_path: String,
) -> Result<StretchParamsApi, NightshadeError> {
    use std::path::Path;

    let path = Path::new(&file_path);
    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    let params = nightshade_imaging::auto_stretch_stf(&image_data);

    Ok(StretchParamsApi {
        shadows: params.shadows,
        highlights: params.highlights,
        midtones: params.midtones,
    })
}

/// Apply stretch to a FITS file and return display data
pub async fn api_apply_stretch(
    file_path: String,
    params: StretchParamsApi,
) -> Result<Vec<u8>, NightshadeError> {
    use std::path::Path;

    let path = Path::new(&file_path);
    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    let stretch_params = nightshade_imaging::StretchParams {
        shadows: params.shadows,
        highlights: params.highlights,
        midtones: params.midtones,
    };

    let display_data_raw = nightshade_imaging::apply_stretch(&image_data, &stretch_params);
    // Convert grayscale to RGBA for Flutter rendering
    Ok(display_data_to_rgba(&display_data_raw, false))
}

// =============================================================================
// DEBAYERING (COLOR CAMERAS)
// =============================================================================

/// Bayer pattern type
#[derive(Debug, Clone, Copy)]
pub enum BayerPatternApi {
    RGGB,
    BGGR,
    GRBG,
    GBRG,
}

/// Debayer algorithm
#[derive(Debug, Clone, Copy)]
pub enum DebayerAlgorithmApi {
    Bilinear,
    VNG,
    SuperPixel,
}

/// Debayer a raw FITS image and return RGB display data
/// Debayer a raw FITS file and return RGB display data
pub async fn api_debayer_fits_file(
    file_path: String,
    pattern: BayerPatternApi,
    algorithm: DebayerAlgorithmApi,
) -> Result<Vec<u8>, NightshadeError> {
    use std::path::Path;

    let path = Path::new(&file_path);
    let (image_data, _header) = nightshade_imaging::read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {}", e)))?;

    let bayer_pattern = match pattern {
        BayerPatternApi::RGGB => nightshade_imaging::BayerPattern::RGGB,
        BayerPatternApi::BGGR => nightshade_imaging::BayerPattern::BGGR,
        BayerPatternApi::GRBG => nightshade_imaging::BayerPattern::GRBG,
        BayerPatternApi::GBRG => nightshade_imaging::BayerPattern::GBRG,
    };

    let debayer_alg = match algorithm {
        DebayerAlgorithmApi::Bilinear => nightshade_imaging::DebayerAlgorithm::Bilinear,
        DebayerAlgorithmApi::VNG => nightshade_imaging::DebayerAlgorithm::VNG,
        DebayerAlgorithmApi::SuperPixel => nightshade_imaging::DebayerAlgorithm::SuperPixel,
    };

    let rgb_image = nightshade_imaging::debayer(
        &image_data.data,
        image_data.width,
        image_data.height,
        bayer_pattern,
        debayer_alg,
    );

    // Return RGBA8 for Flutter display
    Ok(rgb_image.to_rgba8())
}

// =============================================================================
// XISF FILE SUPPORT
// =============================================================================

/// XISF file read result
#[derive(Debug, Clone)]
pub struct XisfReadResult {
    pub width: u32,
    pub height: u32,
    pub channels: u32,
    pub display_data: Vec<u8>, // Always RGBA (width*height*4), alpha=255
    pub histogram: Vec<u32>,
    pub stats: ImageStatsResult,
    pub properties: Vec<(String, String)>,
}

/// Read an XISF file
pub async fn api_read_xisf_file(file_path: String) -> Result<XisfReadResult, NightshadeError> {
    use std::path::Path;

    tracing::info!("Reading XISF file: {}", file_path);

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    let (image_data, metadata) = nightshade_imaging::read_xisf(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read XISF: {}", e)))?;

    // Calculate statistics
    let stats = nightshade_imaging::calculate_stats_u16(&image_data);

    // Auto stretch for display
    let stretch_params = nightshade_imaging::auto_stretch_stf(&image_data);
    let display_data_raw = nightshade_imaging::apply_stretch(&image_data, &stretch_params);

    // Calculate histogram from pre-RGBA data
    let mut histogram = vec![0u32; 256];
    for &pixel in &display_data_raw {
        histogram[pixel as usize] += 1;
    }

    // Convert grayscale to RGBA for Flutter rendering
    let display_data = display_data_to_rgba(&display_data_raw, false);

    // Convert properties to strings
    let properties: Vec<(String, String)> = metadata
        .properties
        .iter()
        .map(|(k, v)| (k.clone(), format!("{:?}", v)))
        .chain(
            metadata
                .fits_keywords
                .iter()
                .map(|(k, v)| (k.clone(), v.clone())),
        )
        .collect();

    tracing::info!(
        "XISF file loaded: {}x{}x{}",
        image_data.width,
        image_data.height,
        image_data.channels
    );

    Ok(XisfReadResult {
        width: image_data.width,
        height: image_data.height,
        channels: image_data.channels,
        display_data,
        histogram,
        stats: ImageStatsResult {
            min: stats.min,
            max: stats.max,
            mean: stats.mean,
            median: stats.median,
            std_dev: stats.std_dev,
            hfr: None,
            star_count: 0,
        },
        properties,
    })
}

/// Save image as XISF
pub async fn api_save_xisf_file(
    file_path: String,
    width: u32,
    height: u32,
    data: Vec<u16>,
    properties: Vec<(String, String)>,
) -> Result<(), NightshadeError> {
    use std::path::Path;

    tracing::info!("Saving XISF file: {}", file_path);

    let image_data = nightshade_imaging::ImageData::from_u16(width, height, 1, &data);

    let mut metadata = nightshade_imaging::XisfMetadata::default();
    for (key, value) in properties {
        metadata.fits_keywords.insert(key, value);
    }

    let path = Path::new(&file_path);
    nightshade_imaging::write_xisf(path, &image_data, &metadata)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to write XISF: {}", e)))?;

    tracing::info!("XISF file saved: {}", file_path);
    Ok(())
}

/// Save image as TIFF (16-bit preserving)
pub async fn api_save_tiff_file(
    file_path: String,
    width: u32,
    height: u32,
    data: Vec<u16>,
) -> Result<(), NightshadeError> {
    use std::path::Path;

    tracing::info!("Saving TIFF file: {}", file_path);

    let image_data = nightshade_imaging::ImageData::from_u16(width, height, 1, &data);

    let path = Path::new(&file_path);
    nightshade_imaging::write_tiff(path, &image_data)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to write TIFF: {}", e)))?;

    tracing::info!("TIFF file saved: {}", file_path);
    Ok(())
}

/// Save image as PNG (16-bit preserving, lossless)
pub async fn api_save_png_file(
    file_path: String,
    width: u32,
    height: u32,
    data: Vec<u16>,
) -> Result<(), NightshadeError> {
    use std::path::Path;

    tracing::info!("Saving PNG file: {}", file_path);

    let image_data = nightshade_imaging::ImageData::from_u16(width, height, 1, &data);

    let path = Path::new(&file_path);
    nightshade_imaging::write_png(path, &image_data)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to write PNG: {}", e)))?;

    tracing::info!("PNG file saved: {}", file_path);
    Ok(())
}

/// Save image as JPEG (8-bit, lossy - for previews)
pub async fn api_save_jpeg_file(
    file_path: String,
    width: u32,
    height: u32,
    data: Vec<u16>,
    quality: u8,
) -> Result<(), NightshadeError> {
    use std::path::Path;

    tracing::info!("Saving JPEG file: {} (quality: {})", file_path, quality);

    let image_data = nightshade_imaging::ImageData::from_u16(width, height, 1, &data);

    let path = Path::new(&file_path);
    nightshade_imaging::write_jpeg(path, &image_data, quality)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to write JPEG: {}", e)))?;

    tracing::info!("JPEG file saved: {}", file_path);
    Ok(())
}

// =============================================================================
// FILE NAMING PATTERNS
// =============================================================================

/// Frame type for file naming
#[derive(Debug, Clone, Copy)]
pub enum FrameTypeApi {
    Light,
    Dark,
    Flat,
    Bias,
    DarkFlat,
    Snapshot,
}

/// Generate a filename from pattern and context
pub async fn api_generate_filename(
    pattern: String,
    base_dir: String,
    target: Option<String>,
    filter: Option<String>,
    exposure_time: f64,
    frame_type: FrameTypeApi,
    frame_number: u32,
    gain: Option<i32>,
    offset: Option<i32>,
    temperature: Option<f64>,
    binning_x: u32,
    binning_y: u32,
    camera: Option<String>,
    telescope: Option<String>,
    extension: String,
) -> String {
    let frame_type_impl = match frame_type {
        FrameTypeApi::Light => nightshade_imaging::FrameType::Light,
        FrameTypeApi::Dark => nightshade_imaging::FrameType::Dark,
        FrameTypeApi::Flat => nightshade_imaging::FrameType::Flat,
        FrameTypeApi::Bias => nightshade_imaging::FrameType::Bias,
        FrameTypeApi::DarkFlat => nightshade_imaging::FrameType::DarkFlat,
        FrameTypeApi::Snapshot => nightshade_imaging::FrameType::Snapshot,
    };

    let mut context = nightshade_imaging::NamingContext::new()
        .with_current_time()
        .with_exposure(exposure_time)
        .with_frame_type(frame_type_impl)
        .with_frame_number(frame_number)
        .with_binning(binning_x, binning_y);

    if let Some(t) = target {
        context = context.with_target(t);
    }
    if let Some(f) = filter {
        context = context.with_filter(f);
    }
    if let Some(g) = gain {
        context = context.with_gain(g);
    }
    if let Some(o) = offset {
        context = context.with_offset(o);
    }
    if let Some(t) = temperature {
        context = context.with_temperature(t);
    }
    if let Some(c) = camera {
        context = context.with_camera(c);
    }
    if let Some(t) = telescope {
        context = context.with_telescope(t);
    }

    let naming_pattern = nightshade_imaging::NamingPattern::new(pattern)
        .with_base_dir(base_dir)
        .with_extension(extension);

    naming_pattern
        .generate(&context)
        .to_string_lossy()
        .to_string()
}

/// Get the next frame number for a directory
pub async fn api_get_next_frame_number(
    base_dir: String,
    pattern: String,
    target: Option<String>,
    filter: Option<String>,
    frame_type: FrameTypeApi,
) -> u32 {
    use std::path::Path;

    let frame_type_impl = match frame_type {
        FrameTypeApi::Light => nightshade_imaging::FrameType::Light,
        FrameTypeApi::Dark => nightshade_imaging::FrameType::Dark,
        FrameTypeApi::Flat => nightshade_imaging::FrameType::Flat,
        FrameTypeApi::Bias => nightshade_imaging::FrameType::Bias,
        FrameTypeApi::DarkFlat => nightshade_imaging::FrameType::DarkFlat,
        FrameTypeApi::Snapshot => nightshade_imaging::FrameType::Snapshot,
    };

    let mut context = nightshade_imaging::NamingContext::new().with_frame_type(frame_type_impl);

    if let Some(t) = target {
        context = context.with_target(t);
    }
    if let Some(f) = filter {
        context = context.with_filter(f);
    }

    let naming_pattern = nightshade_imaging::NamingPattern::new(pattern);
    let base_path = Path::new(&base_dir);

    nightshade_imaging::scan_for_next_frame_number(base_path, &naming_pattern, &context)
}

// =============================================================================
// REAL PLATE SOLVING
// =============================================================================

/// Plate solve result
#[derive(Debug, Clone)]
pub struct PlateSolveResult {
    pub success: bool,
    pub ra: f64,           // degrees
    pub dec: f64,          // degrees
    pub pixel_scale: f64,  // arcsec/pixel
    pub rotation: f64,     // degrees, East of North
    pub field_width: f64,  // degrees
    pub field_height: f64, // degrees
    pub solve_time_secs: f64,
    pub error: Option<String>,
}

/// Check if a plate solver is available
#[flutter_rust_bridge::frb(sync)]
pub fn api_is_plate_solver_available() -> bool {
    nightshade_imaging::is_solver_available()
}

/// Get the path to the installed plate solver
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_plate_solver_path() -> Option<String> {
    nightshade_imaging::get_solver_path().map(|p| p.to_string_lossy().to_string())
}

/// Plate solve an image file (blind solve)
pub async fn api_plate_solve_blind(file_path: String) -> Result<PlateSolveResult, NightshadeError> {
    use std::path::Path;

    tracing::info!("Blind plate solving: {}", file_path);

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    // Run actual plate solve using ASTAP
    let result = nightshade_imaging::blind_solve(path);

    Ok(PlateSolveResult {
        success: result.success,
        ra: result.ra,
        dec: result.dec,
        pixel_scale: result.pixel_scale,
        rotation: result.rotation,
        field_width: result.field_width,
        field_height: result.field_height,
        solve_time_secs: result.solve_time_secs,
        error: result.error,
    })
}

/// Plate solve an image with hint coordinates
pub async fn api_plate_solve_near(
    file_path: String,
    hint_ra: f64,
    hint_dec: f64,
    search_radius: f64,
) -> Result<PlateSolveResult, NightshadeError> {
    use std::path::Path;

    tracing::info!(
        "Plate solving near RA:{:.2}°, Dec:{:.2}°: {}",
        hint_ra,
        hint_dec,
        file_path
    );

    let path = Path::new(&file_path);
    if !path.exists() {
        return Err(NightshadeError::IoError(format!(
            "File not found: {}",
            file_path
        )));
    }

    // Run actual plate solve using ASTAP with hints
    let result = nightshade_imaging::solve_near(path, hint_ra, hint_dec, search_radius);

    Ok(PlateSolveResult {
        success: result.success,
        ra: result.ra,
        dec: result.dec,
        pixel_scale: result.pixel_scale,
        rotation: result.rotation,
        field_width: result.field_width,
        field_height: result.field_height,
        solve_time_secs: result.solve_time_secs,
        error: result.error,
    })
}

// =============================================================================
// PLATE SOLVER UX (detection / verification / config)
// =============================================================================

/// Detection snapshot returned to the settings UI. Contains everything
/// needed to render the "ASTAP detected at /path/to/astap.exe (catalog: V17
/// to mag 17)" status banner without further FFI round-trips.
#[derive(Debug, Clone)]
pub struct PlateSolverDetection {
    /// Detected ASTAP executable path. `None` when ASTAP is not installed.
    pub astap_path: Option<String>,
    /// Detected `solve-field` path. `None` when astrometry.net is not
    /// installed.
    pub astrometry_path: Option<String>,
    /// Detected ASTAP star catalog. `None` when ASTAP was detected but no
    /// catalog could be located (the user must point us at one).
    pub catalog_name: Option<String>,
    /// Approximate magnitude limit the detected catalog covers (e.g. 17.0
    /// for V17). `None` when the catalog flavour isn't recognised.
    pub catalog_magnitude_limit: Option<f32>,
    /// Directory containing the detected catalog.
    pub catalog_path: Option<String>,
}

/// Detailed information about a verified solver binary. See
/// `api_platesolve_verify`.
#[derive(Debug, Clone)]
pub struct PlateSolverInfo {
    /// Absolute path of the verified binary.
    pub path: String,
    /// `"ASTAP"`, `"Astrometry.net"`, or `"Unknown"`.
    pub flavour: String,
    /// First non-empty line of the binary's `--help` output, useful for
    /// surfacing the build version in the settings UI.
    pub version_line: String,
}

/// Persisted plate-solver UX configuration. Mirrors `storage::PlateSolverPreference`
/// 1:1; lives in this module so flutter_rust_bridge can generate Dart
/// bindings without exporting the storage internals.
#[derive(Debug, Clone)]
pub struct PlateSolverConfigPayload {
    pub astap_path: String,
    pub astrometry_path: String,
    pub catalog_path: String,
    pub solver_choice: String,
}

impl PlateSolverConfigPayload {
    fn into_pref(self) -> crate::storage::PlateSolverPreference {
        crate::storage::PlateSolverPreference {
            astap_path: self.astap_path,
            astrometry_path: self.astrometry_path,
            catalog_path: self.catalog_path,
            solver_choice: self.solver_choice,
        }
    }
}

impl From<crate::storage::PlateSolverPreference> for PlateSolverConfigPayload {
    fn from(pref: crate::storage::PlateSolverPreference) -> Self {
        Self {
            astap_path: pref.astap_path,
            astrometry_path: pref.astrometry_path,
            catalog_path: pref.catalog_path,
            solver_choice: pref.solver_choice,
        }
    }
}

/// Detect installed plate solvers and catalogs. Honours the user-configured
/// override paths from the persisted plate-solver preference, if any. Does
/// not run the binaries — that's `api_platesolve_verify`.
#[flutter_rust_bridge::frb(sync)]
pub fn api_platesolve_detect() -> Result<PlateSolverDetection, NightshadeError> {
    use std::path::Path;

    // Why: first-run / no-saved-prefs is the dominant case — return defaults
    // so detection still scans standard install paths. A storage IO error
    // here is non-fatal because the only state read is overlay-on-defaults;
    // the user can still set explicit paths in the Plate Solving settings.
    let pref = crate::state::get_platesolver_preference()
        .unwrap_or_else(|_| crate::storage::PlateSolverPreference::default());

    let configured_astap = if pref.astap_path.is_empty() {
        None
    } else {
        Some(pref.astap_path.clone())
    };
    let configured_astrometry = if pref.astrometry_path.is_empty() {
        None
    } else {
        Some(pref.astrometry_path.clone())
    };
    let configured_catalog = if pref.catalog_path.is_empty() {
        None
    } else {
        Some(pref.catalog_path.clone())
    };

    // Probing involves filesystem reads which are fast but blocking. The
    // function is sync — callers can wrap it if they need it off the UI
    // isolate.
    nightshade_imaging::invalidate_solver_availability_cache();

    let astap_path = nightshade_imaging::find_astap_with_override(
        configured_astap.as_deref().map(Path::new),
    );
    let astrometry_path = nightshade_imaging::find_astrometry_with_override(
        configured_astrometry.as_deref().map(Path::new),
    );

    let catalog = nightshade_imaging::detect_astap_catalog(
        astap_path.as_deref(),
        configured_catalog.as_deref().map(Path::new),
    );

    Ok(PlateSolverDetection {
        astap_path: astap_path.map(|p| p.to_string_lossy().to_string()),
        astrometry_path: astrometry_path.map(|p| p.to_string_lossy().to_string()),
        catalog_name: catalog.as_ref().and_then(|c| {
            if c.name.is_empty() {
                None
            } else {
                Some(c.name.clone())
            }
        }),
        catalog_magnitude_limit: catalog.as_ref().and_then(|c| c.magnitude_limit),
        catalog_path: catalog.as_ref().map(|c| c.path.to_string_lossy().to_string()),
    })
}

/// Run the supplied solver binary with `--help` to confirm it's healthy.
/// Returns a `PlateSolverInfo` with the detected flavour and version banner,
/// or a `NightshadeError` if the binary is missing / fails to spawn / exits
/// with non-zero status and empty output.
#[flutter_rust_bridge::frb(sync)]
pub fn api_platesolve_verify(executable_path: String) -> Result<PlateSolverInfo, NightshadeError> {
    use std::path::Path;
    let path = Path::new(&executable_path);
    match nightshade_imaging::verify_solver(path) {
        Ok(info) => Ok(PlateSolverInfo {
            path: info.path.to_string_lossy().to_string(),
            flavour: info.flavour,
            version_line: info.version_line,
        }),
        Err(e) => Err(NightshadeError::OperationFailed(e.to_string())),
    }
}

/// Read the persisted plate-solver configuration. Falls back to defaults if
/// the storage was never written.
#[flutter_rust_bridge::frb(sync)]
pub fn api_platesolve_get_config() -> Result<PlateSolverConfigPayload, NightshadeError> {
    let pref = crate::state::get_platesolver_preference()
        .map_err(NightshadeError::OperationFailed)?;
    Ok(pref.into())
}

/// Persist a new plate-solver configuration. Invalidates the solver
/// availability cache so the next `api_is_plate_solver_available()` call
/// re-probes the filesystem with the new paths.
#[flutter_rust_bridge::frb(sync)]
pub fn api_platesolve_set_config(
    config: PlateSolverConfigPayload,
) -> Result<(), NightshadeError> {
    let pref = config.into_pref();
    crate::state::save_platesolver_preference(&pref).map_err(NightshadeError::OperationFailed)?;
    nightshade_imaging::invalidate_solver_availability_cache();
    Ok(())
}

// =============================================================================
// REAL PHD2 GUIDING INTEGRATION
// =============================================================================

/// PHD2 connection state
#[derive(Debug, Clone)]
pub struct Phd2Status {
    pub connected: bool,
    pub state: String, // "Disconnected", "Connected", "Calibrating", "Guiding", "Looping", "Paused"
    pub rms_ra: f64,
    pub rms_dec: f64,
    pub rms_total: f64,
    pub snr: f64,
    pub star_mass: f64,
    pub pixel_scale: f64,
}

/// PHD2 calibration data
#[derive(Debug, Clone)]
pub struct Phd2CalibrationData {
    /// Whether the mount is calibrated
    pub is_calibrated: bool,
    /// RA axis rotation angle (degrees)
    pub ra_angle: Option<f64>,
    /// Dec axis rotation angle (degrees)
    pub dec_angle: Option<f64>,
    /// RA guide rate (pixels/second)
    pub ra_rate: Option<f64>,
    /// Dec guide rate (pixels/second)
    pub dec_rate: Option<f64>,
}

/// PHD2 star image data
#[derive(Debug, Clone)]
pub struct Phd2StarImage {
    /// Frame number
    pub frame: u32,
    /// Image width in pixels
    pub width: u32,
    /// Image height in pixels
    pub height: u32,
    /// Star centroid X position
    pub star_x: f64,
    /// Star centroid Y position
    pub star_y: f64,
    /// Raw pixel data (16-bit grayscale as bytes)
    pub pixels: Vec<u8>,
}

/// PHD2 Brain algorithm parameter
#[derive(Debug, Clone)]
pub struct Phd2AlgoParam {
    /// Parameter name
    pub name: String,
    /// Parameter value
    pub value: f64,
}

/// Check if PHD2 is running
#[flutter_rust_bridge::frb(sync)]
pub fn api_is_phd2_running() -> bool {
    nightshade_imaging::is_phd2_running()
}

/// Static PHD2 client storage
static PHD2_CLIENT: OnceLock<Arc<RwLock<Option<nightshade_imaging::Phd2Client>>>> = OnceLock::new();

#[flutter_rust_bridge::frb(ignore)]
pub fn get_phd2_storage() -> &'static Arc<RwLock<Option<nightshade_imaging::Phd2Client>>> {
    PHD2_CLIENT.get_or_init(|| Arc::new(RwLock::new(None)))
}

#[flutter_rust_bridge::frb(ignore)]
pub async fn get_active_guider_id_for_ops() -> Option<String> {
    if let Some(profile_guider) = get_state().get_profile_device_id(DeviceType::Guider).await {
        return Some(profile_guider);
    }
    if get_state()
        .is_device_connected(DeviceType::Guider, crate::builtin_guider::device_id())
        .await
    {
        return Some(crate::builtin_guider::device_id().to_string());
    }
    if get_state()
        .is_device_connected(DeviceType::Guider, "phd2_guider")
        .await
    {
        return Some("phd2_guider".to_string());
    }
    get_state()
        .get_devices(DeviceType::Guider)
        .await
        .into_iter()
        .map(|device| device.id)
        .next()
}

/// Connect to PHD2
pub async fn api_phd2_connect(
    host: Option<String>,
    port: Option<u16>,
) -> Result<(), NightshadeError> {
    let host = host.unwrap_or_else(|| "127.0.0.1".to_string());
    let port = port.unwrap_or(4400);

    tracing::info!("Connecting to PHD2 at {}:{}", host, port);

    let mut client = nightshade_imaging::Phd2Client::new(&host, port);

    // Set up event callback to forward PHD2 events to the main event stream.
    // This callback runs on the PHD2 reader std::thread, NOT on the tokio runtime.
    // It publishes to the broadcast channel which is picked up by api_event_stream.
    client.set_event_callback(move |event| {
        let subscriber_count = get_state().event_bus.subscriber_count();
        tracing::info!(
            "PHD2 event callback received: {:?} (event bus subscribers: {})",
            std::mem::discriminant(&event),
            subscriber_count
        );

        let guiding_event = match event {
            nightshade_imaging::Phd2Event::GuideStep(ref frame) => {
                tracing::info!(
                    "PHD2 GuideStep: RA={:.3}, Dec={:.3}, SNR={:.1}",
                    frame.ra_distance,
                    frame.dec_distance,
                    frame.snr
                );
                // Forward guide step correction data
                let event_id = get_state().publish_guiding_event(
                    GuidingEvent::Correction {
                        ra: frame.ra_distance,
                        dec: frame.dec_distance,
                        ra_raw: frame.ra_distance,
                        dec_raw: frame.dec_distance,
                    },
                    EventSeverity::Info,
                );
                tracing::info!("PHD2: Published Correction event (id={})", event_id);
                // Also forward guide stats (SNR and star mass)
                let stats_id = get_state().publish_guiding_event(
                    GuidingEvent::GuideStats {
                        snr: frame.snr,
                        star_mass: frame.star_mass,
                    },
                    EventSeverity::Info,
                );
                tracing::info!("PHD2: Published GuideStats event (id={})", stats_id);
                return;
            }
            nightshade_imaging::Phd2Event::StateChanged(state) => {
                tracing::info!("PHD2 state changed: {:?}", state);
                match state {
                    nightshade_imaging::Phd2State::Guiding => GuidingEvent::GuidingStarted,
                    nightshade_imaging::Phd2State::Connected => GuidingEvent::GuidingStopped,
                    nightshade_imaging::Phd2State::Disconnected => GuidingEvent::Disconnected,
                    nightshade_imaging::Phd2State::Paused => GuidingEvent::Paused,
                    nightshade_imaging::Phd2State::LostLock => GuidingEvent::LostStar,
                    nightshade_imaging::Phd2State::Looping => GuidingEvent::Looping,
                    nightshade_imaging::Phd2State::Calibrating => GuidingEvent::Calibrating,
                    nightshade_imaging::Phd2State::Settling => GuidingEvent::Settling,
                    // Why: PHD2 occasionally introduces new app-states; we
                    // forward the raw name as a generic `Disconnected` event
                    // (the safest superset for sequencer logic) but the
                    // warning is already emitted upstream in
                    // `parse_phd2_app_state`. Surfacing the literal string in
                    // the GuidingEvent stream would require extending the
                    // FFI enum, which is out of scope here.
                    nightshade_imaging::Phd2State::Unknown(raw) => {
                        tracing::warn!(
                            "PHD2: unrecognised state {:?} bubbled into bridge — \
                             treating as Disconnected for guiding-event mapping",
                            raw
                        );
                        GuidingEvent::Disconnected
                    }
                }
            }
            nightshade_imaging::Phd2Event::StarLost => GuidingEvent::LostStar,
            nightshade_imaging::Phd2Event::StarSelected { x, y } => {
                GuidingEvent::StarSelected { x, y }
            }
            nightshade_imaging::Phd2Event::SettleBegin => GuidingEvent::Settling,
            nightshade_imaging::Phd2Event::SettleDone {
                total_frames: _,
                dropped_frames: _,
            } => GuidingEvent::Settled { rms: 0.0 },
            nightshade_imaging::Phd2Event::CalibrationComplete => {
                tracing::info!("PHD2: Calibration complete");
                GuidingEvent::CalibrationComplete
            }
            nightshade_imaging::Phd2Event::Disconnected => GuidingEvent::Disconnected,
            nightshade_imaging::Phd2Event::Alert {
                message,
                alert_type,
            } => {
                tracing::warn!("PHD2 Alert [{}]: {}", alert_type, message);
                return; // Alerts are not forwarded as GuidingEvent
            }
            nightshade_imaging::Phd2Event::Error(msg) => {
                tracing::error!("PHD2 Error: {}", msg);
                return; // Errors are not forwarded as GuidingEvent
            }
        };

        let severity = match &guiding_event {
            GuidingEvent::LostStar | GuidingEvent::Disconnected => EventSeverity::Warning,
            _ => EventSeverity::Info,
        };

        let event_id = get_state().publish_guiding_event(guiding_event.clone(), severity);
        tracing::info!(
            "PHD2: Published {:?} to event bus (event_id={}, subscribers={})",
            guiding_event,
            event_id,
            subscriber_count
        );
    });

    client
        .connect()
        .map_err(|e| NightshadeError::connection_failed("phd2_guider", format!("PHD2: {}", e)))?;

    // Store the client
    let mut storage = get_phd2_storage().write().await;
    *storage = Some(client);

    // Register PHD2 as a connected guider device in AppState
    // This ensures api_get_connected_devices() returns the guider
    let phd2_device_info = DeviceInfo {
        id: "phd2_guider".to_string(),
        name: "PHD2".to_string(),
        device_type: DeviceType::Guider,
        driver_type: DriverType::Native,
        description: format!("PHD2 Guiding at {}:{}", host, port),
        driver_version: String::new(),
        serial_number: None,
        unique_id: None,
        display_name: "PHD2 Guiding".to_string(),
    };
    get_state()
        .register_device(phd2_device_info, ConnectionState::Connected)
        .await;

    // Publish event
    get_state().publish_guiding_event(GuidingEvent::Connected, EventSeverity::Info);

    Ok(())
}

/// Disconnect from PHD2
pub async fn api_phd2_disconnect() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    if let Some(mut client) = storage.take() {
        client.disconnect();
    }

    // Remove PHD2 from connected devices in AppState
    get_state()
        .remove_device(DeviceType::Guider, "phd2_guider")
        .await;

    get_state().publish_guiding_event(GuidingEvent::Disconnected, EventSeverity::Info);

    Ok(())
}

/// Start guiding in PHD2
pub async fn api_phd2_start_guiding(
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .guide(settle_pixels, settle_time, settle_timeout)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to start guiding: {}", e)))?;

    get_state().publish_guiding_event(GuidingEvent::GuidingStarted, EventSeverity::Info);

    Ok(())
}

/// Stop guiding in PHD2
pub async fn api_phd2_stop_guiding() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .stop_capture()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to stop guiding: {}", e)))?;

    get_state().publish_guiding_event(GuidingEvent::GuidingStopped, EventSeverity::Info);

    Ok(())
}

/// Dither in PHD2
pub async fn api_phd2_dither(
    amount: f64,
    ra_only: u8,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    let ra_only_bool = ra_only != 0;
    client
        .dither(
            amount,
            ra_only_bool,
            settle_pixels,
            settle_time,
            settle_timeout,
        )
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to dither: {}", e)))?;

    get_state().publish_guiding_event(
        GuidingEvent::DitherStarted { pixels: amount },
        EventSeverity::Info,
    );

    Ok(())
}

/// Get PHD2 status
pub async fn api_phd2_get_status() -> Result<Phd2Status, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    let state = client.get_app_state().map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get PHD2 state: {}", e))
    })?;

    let pixel_scale = client.get_pixel_scale().unwrap_or(0.0);

    // Why: forward the raw PHD2 state name when unrecognised so the desktop
    // UI can render "PHD2 says: GuidingPaused" instead of pretending
    // everything is fine. Known variants stay as &'static str literals;
    // Unknown owns its String, so we convert to String at the join point.
    let state_str: String = match state {
        nightshade_imaging::Phd2State::Disconnected => "Disconnected".to_string(),
        nightshade_imaging::Phd2State::Connected => "Connected".to_string(),
        nightshade_imaging::Phd2State::Calibrating => "Calibrating".to_string(),
        nightshade_imaging::Phd2State::Guiding => "Guiding".to_string(),
        nightshade_imaging::Phd2State::Looping => "Looping".to_string(),
        nightshade_imaging::Phd2State::Paused => "Paused".to_string(),
        nightshade_imaging::Phd2State::Settling => "Settling".to_string(),
        nightshade_imaging::Phd2State::LostLock => "LostLock".to_string(),
        nightshade_imaging::Phd2State::Unknown(raw) => raw,
    };

    Ok(Phd2Status {
        connected: true,
        state: state_str,
        rms_ra: 0.0, // Would need to track from events
        rms_dec: 0.0,
        rms_total: 0.0,
        snr: 0.0,
        star_mass: 0.0,
        pixel_scale,
    })
}

/// Get PHD2 star image with metadata
pub async fn api_phd2_get_star_image(size: u32) -> Result<Phd2StarImage, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    let image_data = client.get_star_image_data(size).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get star image: {}", e))
    })?;

    Ok(Phd2StarImage {
        frame: image_data.frame,
        width: image_data.width,
        height: image_data.height,
        star_x: image_data.star_x,
        star_y: image_data.star_y,
        pixels: image_data.pixels,
    })
}

/// Get PHD2 algorithm parameter names for an axis
pub async fn api_phd2_get_algo_param_names(axis: String) -> Result<Vec<String>, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client.get_algo_param_names(&axis).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get algo param names: {}", e))
    })
}

/// Get PHD2 algorithm parameter value
pub async fn api_phd2_get_algo_param(axis: String, name: String) -> Result<f64, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .get_algo_param(&axis, &name)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to get algo param: {}", e)))
}

/// Set PHD2 algorithm parameter value
pub async fn api_phd2_set_algo_param(
    axis: String,
    name: String,
    value: f64,
) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .set_algo_param(&axis, &name, value)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to set algo param: {}", e)))
}

/// Get all PHD2 algorithm parameters for an axis
pub async fn api_phd2_get_all_algo_params(
    axis: String,
) -> Result<Vec<Phd2AlgoParam>, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    let params = client.get_all_algo_params(&axis).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get all algo params: {}", e))
    })?;

    Ok(params
        .into_iter()
        .map(|p| Phd2AlgoParam {
            name: p.name,
            value: p.value,
        })
        .collect())
}

/// Pause or resume PHD2 guiding
pub async fn api_phd2_set_paused(paused: bool) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .set_paused(paused)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to set paused: {}", e)))?;

    get_state().publish_guiding_event(
        if paused {
            GuidingEvent::Paused
        } else {
            GuidingEvent::Resumed
        },
        EventSeverity::Info,
    );

    Ok(())
}

/// Clear PHD2 calibration
pub async fn api_phd2_clear_calibration(which: String) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client.clear_calibration(&which).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to clear calibration: {}", e))
    })
}

/// Flip PHD2 calibration (after meridian flip)
pub async fn api_phd2_flip_calibration() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .flip_calibration()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to flip calibration: {}", e)))
}

/// Get PHD2 calibration data
/// Returns calibration info including whether calibrated and calibration parameters
pub async fn api_phd2_get_calibration_data() -> Result<Phd2CalibrationData, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    // Get calibration data for both axes - "both" returns combined info
    let result = client.get_calibration_data("both").map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get calibration data: {}", e))
    })?;

    // PHD2 returns null if not calibrated, otherwise returns calibration parameters
    let is_calibrated = !result.is_null();

    // Extract calibration parameters if available
    let (ra_angle, dec_angle, ra_rate, dec_rate) = if is_calibrated {
        let xangle = result.get("xAngle").and_then(|v| v.as_f64());
        let yangle = result.get("yAngle").and_then(|v| v.as_f64());
        let xrate = result.get("xRate").and_then(|v| v.as_f64());
        let yrate = result.get("yRate").and_then(|v| v.as_f64());
        (xangle, yangle, xrate, yrate)
    } else {
        (None, None, None, None)
    };

    Ok(Phd2CalibrationData {
        is_calibrated,
        ra_angle,
        dec_angle,
        ra_rate,
        dec_rate,
    })
}

/// Find a guide star automatically
pub async fn api_phd2_find_star() -> Result<(f64, f64), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .find_star()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to find star: {}", e)))
}

/// Set guide star lock position
pub async fn api_phd2_set_lock_position(
    x: f64,
    y: f64,
    exact: bool,
) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client.set_lock_position(x, y, exact).map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to set lock position: {}", e))
    })
}

/// Get current guide star lock position
pub async fn api_phd2_get_lock_position() -> Result<(f64, f64), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client.get_lock_position().map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to get lock position: {}", e))
    })
}

/// Start looping exposures (without guiding)
pub async fn api_phd2_loop() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .loop_exposures()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to start looping: {}", e)))
}

/// Deselect the current guide star
pub async fn api_phd2_deselect_star() -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .deselect_star()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to deselect star: {}", e)))
}

/// Get PHD2 guide exposure time (ms)
pub async fn api_phd2_get_exposure() -> Result<u32, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .get_exposure()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to get exposure: {}", e)))
}

/// Set PHD2 guide exposure time (ms)
pub async fn api_phd2_set_exposure(exposure_ms: u32) -> Result<(), NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .set_exposure(exposure_ms)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to set exposure: {}", e)))
}

/// Get current PHD2 profile name
pub async fn api_phd2_get_profile() -> Result<String, NightshadeError> {
    let mut storage = get_phd2_storage().write().await;
    let client = storage
        .as_mut()
        .ok_or_else(|| NightshadeError::NotConnected("PHD2".to_string()))?;

    client
        .get_profile()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to get profile: {}", e)))
}

/// Launch PHD2 application
pub fn api_launch_phd2() -> Result<(), NightshadeError> {
    nightshade_imaging::launch_phd2()
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to launch PHD2: {}", e)))
}

pub async fn api_guider_start_guiding(
    device_id: String,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_start_guiding(settle_pixels, settle_time, settle_timeout).await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::start_guiding(settle_pixels, settle_time, settle_timeout)
            .await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_stop(device_id: String) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_stop_guiding().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::stop().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_dither(
    device_id: String,
    amount: f64,
    ra_only: u8,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_dither(amount, ra_only, settle_pixels, settle_time, settle_timeout).await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::dither(
            amount,
            ra_only != 0,
            settle_pixels,
            settle_time,
            settle_timeout,
        )
        .await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_loop(device_id: String) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_loop().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::loop_exposures().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_find_star(device_id: String) -> Result<(f64, f64), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_find_star().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::find_star().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_set_lock_position(
    device_id: String,
    x: f64,
    y: f64,
    exact: bool,
) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_set_lock_position(x, y, exact).await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::set_lock_position(x, y).await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_get_lock_position(
    device_id: String,
) -> Result<(f64, f64), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_get_lock_position().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::get_lock_position().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_deselect_star(device_id: String) -> Result<(), NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_deselect_star().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::deselect_star().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_get_star_image(
    device_id: String,
    size: u32,
) -> Result<Phd2StarImage, NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_get_star_image(size).await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::get_star_image(size).await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

pub async fn api_guider_get_status(device_id: String) -> Result<Phd2Status, NightshadeError> {
    if is_phd2_device_id(&device_id) {
        return api_phd2_get_status().await;
    }
    if device_id == crate::builtin_guider::device_id() {
        return crate::builtin_guider::get_status().await;
    }
    Err(NightshadeError::OperationFailed(format!(
        "Unsupported guider device: {}",
        device_id
    )))
}

// =============================================================================
// BUILT-IN GUIDER CONFIGURATION
// =============================================================================

/// Get the current built-in guider configuration.
/// Returns a flat struct with all configurable parameters.
pub async fn api_builtin_guider_get_config() -> Result<BuiltinGuiderConfig, NightshadeError> {
    let config = crate::builtin_guider::get_config().await;
    Ok(BuiltinGuiderConfig {
        exposure_secs: config.exposure_secs,
        gain: config.gain,
        offset: config.offset,
        binning: config.binning,
        calibration_ms: config.calibration_ms,
        settle_sleep_ms: config.settle_sleep_ms,
        min_pulse_ms: config.min_pulse_ms,
        max_pulse_ms: config.max_pulse_ms,
    })
}

/// Set the built-in guider configuration.
/// Can be called while guiding is active; changes apply to subsequent frames.
pub async fn api_builtin_guider_set_config(
    exposure_secs: f64,
    gain: i32,
    offset: i32,
    binning: i32,
    calibration_ms: u32,
    settle_sleep_ms: u64,
    min_pulse_ms: f64,
    max_pulse_ms: f64,
) -> Result<(), NightshadeError> {
    let config = crate::builtin_guider::GuiderConfig {
        exposure_secs,
        gain,
        offset,
        binning,
        calibration_ms,
        settle_sleep_ms,
        min_pulse_ms,
        max_pulse_ms,
    };
    crate::builtin_guider::set_config(config).await;
    Ok(())
}

/// FRB-friendly struct for the built-in guider configuration.
#[derive(Clone, Debug)]
pub struct BuiltinGuiderConfig {
    pub exposure_secs: f64,
    pub gain: i32,
    pub offset: i32,
    pub binning: i32,
    pub calibration_ms: u32,
    pub settle_sleep_ms: u64,
    pub min_pulse_ms: f64,
    pub max_pulse_ms: f64,
}

// =============================================================================
// ALPACA DEVICE CONNECTION (Cross-platform)
// =============================================================================

pub mod alpaca_connections {
    use super::*;
    // Re-export AlpacaClient for FRB bindings
    pub use nightshade_alpaca::AlpacaClient;
    use nightshade_alpaca::{AlpacaDevice, AlpacaDeviceType};
    use std::collections::HashMap;

    // Storage for active Alpaca connections using Arc to share ownership
    static ALPACA_CLIENTS: OnceLock<Arc<RwLock<HashMap<String, Arc<AlpacaClient>>>>> =
        OnceLock::new();

    fn get_alpaca_clients() -> &'static Arc<RwLock<HashMap<String, Arc<AlpacaClient>>>> {
        ALPACA_CLIENTS.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
    }

    /// Parse an Alpaca device ID into its components
    /// Format: "alpaca:{base_url}:{device_type}:{device_number}"
    fn parse_alpaca_id(device_id: &str) -> Option<(String, AlpacaDeviceType, u32)> {
        let id_part = device_id.strip_prefix("alpaca:")?;

        // The format is: http://host:port:device_type:device_number
        // We need to carefully parse this since base_url contains colons

        // Find the last two colons which separate device_type and device_number
        let mut parts: Vec<&str> = id_part.rsplitn(3, ':').collect();
        parts.reverse();

        if parts.len() < 3 {
            return None;
        }

        let base_url = parts[0].to_string();
        let device_type = AlpacaDeviceType::from_str(parts[1])?;
        let device_number: u32 = parts[2].parse().ok()?;

        Some((base_url, device_type, device_number))
    }

    /// Connect to an Alpaca device
    pub async fn connect_alpaca_device(
        device_type: DeviceType,
        device_id: &str,
    ) -> Result<(), NightshadeError> {
        let (base_url, alpaca_type, device_number) =
            parse_alpaca_id(device_id).ok_or_else(|| {
                NightshadeError::invalid_device_id(device_id, "Failed to parse Alpaca device ID")
            })?;

        // Create the device struct
        let device = AlpacaDevice {
            device_type: alpaca_type,
            device_number,
            server_name: base_url.clone(),
            manufacturer: String::new(),
            device_name: format!("Alpaca {}", device_type.as_str()),
            unique_id: device_id.to_string(),
            base_url: base_url.clone(),
        };

        // Create and connect the client
        let client = AlpacaClient::new(&device);

        client.connect().await.map_err(|e| {
            NightshadeError::connection_failed(
                device_id,
                format!("Alpaca connection failed: {}", e),
            )
        })?;

        let name = client
            .get_name()
            .await
            .unwrap_or_else(|_| device_id.to_string());
        tracing::info!("Connected to Alpaca device: {}", name);

        // Store the client wrapped in Arc
        let mut clients = get_alpaca_clients().write().await;
        clients.insert(device_id.to_string(), Arc::new(client));

        Ok(())
    }

    /// Disconnect from an Alpaca device
    pub async fn disconnect_alpaca_device(device_id: &str) -> Result<(), NightshadeError> {
        let mut clients = get_alpaca_clients().write().await;

        if let Some(client) = clients.get(device_id) {
            client.disconnect().await.map_err(|e| {
                NightshadeError::OperationFailed(format!("Alpaca disconnect failed: {}", e))
            })?;
        }

        clients.remove(device_id);
        Ok(())
    }

    /// Get an Alpaca client
    pub async fn get_alpaca_client(device_id: &str) -> Option<Arc<AlpacaClient>> {
        let clients = get_alpaca_clients().read().await;
        clients.get(device_id).cloned()
    }

    /// Check if Alpaca is connected
    pub async fn is_connected(device_id: &str) -> bool {
        let clients = get_alpaca_clients().read().await;
        if let Some(client) = clients.get(device_id) {
            match client.is_connected().await {
                Ok(connected) => connected,
                Err(e) => {
                    tracing::warn!(
                        "Failed to query Alpaca connection state for {}: {}",
                        device_id,
                        e
                    );
                    false
                }
            }
        } else {
            false
        }
    }
}

// =============================================================================
// REAL ASCOM DEVICE CONNECTION
// =============================================================================

// =============================================================================
// SEQUENCER API
// =============================================================================

use nightshade_sequencer::{
    mosaic::calculate_mosaic_panels, mosaic::MosaicPanel, AutofocusConfig, AutofocusMethod,
    Binning, CenterConfig, CoolConfig, DelayConfig, DitherConfig, DitherPattern, ExecutorEvent,
    ExecutorState, ExposureConfig, FilterConfig, LoopCondition, LoopConfig, MosaicConfig,
    NodeDefinition, NodeStatus, NodeType, NotificationConfig, NotificationLevel, RotatorConfig,
    ScriptConfig, SequenceDefinition, SequenceProgress, SlewConfig, TargetGroupConfig,
    TargetHeaderConfig, TwilightType, WaitTimeConfig, WarmConfig,
};

/// Get the global sequence executor instance
fn get_sequence_executor(
) -> &'static std::sync::Arc<tokio::sync::RwLock<nightshade_sequencer::SequenceExecutor>> {
    nightshade_sequencer::get_executor()
}

/// Sequencer state for Flutter
#[derive(Debug, Clone)]
pub struct SequencerState {
    pub state: String,
    pub current_node_id: Option<String>,
    pub current_node_name: Option<String>,
    pub total_exposures: u32,
    pub completed_exposures: u32,
    pub total_integration_secs: f64,
    pub elapsed_secs: f64,
    pub estimated_remaining_secs: Option<f64>,
    pub current_target: Option<String>,
    pub current_filter: Option<String>,
    pub message: Option<String>,
}

impl From<SequenceProgress> for SequencerState {
    fn from(p: SequenceProgress) -> Self {
        let state_str = match p.state {
            ExecutorState::Idle => "idle",
            ExecutorState::Running => "running",
            ExecutorState::Paused => "paused",
            ExecutorState::Stopping => "stopping",
            ExecutorState::Cancelled => "cancelled",
            ExecutorState::Completed => "completed",
            ExecutorState::Failed => "failed",
        };
        Self {
            state: state_str.to_string(),
            current_node_id: p.current_node_id,
            current_node_name: p.current_node_name,
            total_exposures: p.total_exposures,
            completed_exposures: p.completed_exposures,
            total_integration_secs: p.total_integration_secs,
            elapsed_secs: p.elapsed_secs,
            estimated_remaining_secs: p.estimated_remaining_secs,
            current_target: p.current_target,
            current_filter: p.current_filter,
            message: p.message,
        }
    }
}

/// Sequence definition for Flutter
#[derive(Debug, Clone)]
pub struct SequenceDefinitionApi {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub nodes: Vec<NodeDefinitionApi>,
    pub root_node_id: Option<String>,
}

/// Node definition for Flutter
#[derive(Debug, Clone)]
pub struct NodeDefinitionApi {
    pub id: String,
    pub name: String,
    pub node_type: String,
    pub enabled: bool,
    pub children: Vec<String>,
    pub config_json: String,
}

impl From<&NodeDefinition> for NodeDefinitionApi {
    fn from(n: &NodeDefinition) -> Self {
        let node_type = match &n.node_type {
            NodeType::TargetGroup(_) => "target_group",
            NodeType::TargetHeader(_) => "target_header",
            NodeType::Loop(_) => "loop",
            NodeType::Parallel(_) => "parallel",
            NodeType::Conditional(_) => "conditional",
            NodeType::Recovery(_) => "recovery",
            NodeType::SlewToTarget(_) => "slew",
            NodeType::CenterTarget(_) => "center",
            NodeType::TakeExposure(_) => "exposure",
            NodeType::Autofocus(_) => "autofocus",
            NodeType::Dither(_) => "dither",
            NodeType::ChangeFilter(_) => "filter_change",
            NodeType::CoolCamera(_) => "cool_camera",
            NodeType::WarmCamera(_) => "warm_camera",
            NodeType::PolarAlignment(_) => "polar_alignment",
            NodeType::MoveRotator(_) => "rotator",
            NodeType::Park => "park",
            NodeType::Unpark => "unpark",
            NodeType::WaitForTime(_) => "wait_time",
            NodeType::Delay(_) => "delay",
            NodeType::Notification(_) => "notification",
            NodeType::RunScript(_) => "script",
            NodeType::MeridianFlip(_) => "meridian_flip",
            NodeType::OpenDome(_) => "open_dome",
            NodeType::CloseDome(_) => "close_dome",
            NodeType::ParkDome(_) => "park_dome",
            NodeType::StartGuiding(_) => "start_guiding",
            NodeType::StopGuiding => "stop_guiding",
            NodeType::TemperatureCompensation(_) => "temperature_compensation",
            NodeType::Mosaic(_) => "mosaic",
            NodeType::FlatWizard(_) => "flat_wizard",
            NodeType::OpenCover(_) => "open_cover",
            NodeType::CloseCover(_) => "close_cover",
            NodeType::CalibratorOn(_) => "calibrator_on",
            NodeType::CalibratorOff(_) => "calibrator_off",
        };

        let config_json = match serde_json::to_string(&n.node_type) {
            Ok(json) => json,
            Err(e) => {
                tracing::error!("Failed to serialize node type for node '{}': {}", n.id, e);
                format!("{{\"error\":\"serialization failed: {}\"}}", e)
            }
        };

        Self {
            id: n.id.clone(),
            name: n.name.clone(),
            node_type: node_type.to_string(),
            enabled: n.enabled,
            children: n.children.clone(),
            config_json,
        }
    }
}

/// Load a sequence from JSON
pub async fn api_sequencer_load_json(json: String) -> Result<(), NightshadeError> {
    tracing::info!("Loading sequence from JSON");

    let definition: SequenceDefinition = serde_json::from_str(&json).map_err(|e| {
        NightshadeError::InvalidInput(format!("Failed to parse sequence JSON: {}", e))
    })?;

    let mut executor = get_sequence_executor().write().await;
    executor
        .load_sequence(definition)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to load sequence: {}", e)))?;

    tracing::info!("Sequence loaded successfully");
    Ok(())
}

/// Load a sequence from a definition struct
pub async fn api_sequencer_load(definition: SequenceDefinitionApi) -> Result<(), NightshadeError> {
    tracing::info!("Loading sequence: {}", definition.name);

    // Convert API nodes to internal nodes
    let nodes: Result<Vec<NodeDefinition>, NightshadeError> = definition
        .nodes
        .iter()
        .map(|n| {
            let node_type: NodeType = serde_json::from_str(&n.config_json).map_err(|e| {
                NightshadeError::InvalidInput(format!("Invalid node config: {}", e))
            })?;

            Ok(NodeDefinition {
                id: n.id.clone(),
                name: n.name.clone(),
                node_type,
                enabled: n.enabled,
                children: n.children.clone(),
            })
        })
        .collect();

    let internal_definition = SequenceDefinition {
        id: definition.id,
        name: definition.name,
        description: definition.description,
        nodes: nodes?,
        root_node_id: definition.root_node_id,
        metadata: std::collections::HashMap::new(),
    };

    let mut executor = get_sequence_executor().write().await;
    executor
        .load_sequence(internal_definition)
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to load sequence: {}", e)))?;

    Ok(())
}

/// Start the sequence executor
pub async fn api_sequencer_start() -> Result<(), NightshadeError> {
    tracing::info!("Starting sequence execution");

    let mut executor = get_sequence_executor().write().await;
    executor.start().await.map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to start sequence: {}", e))
    })?;

    // Publish event
    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::Sequencer,
        EventPayload::Sequencer(SequencerEvent::Started {
            sequence_name: "Sequence".to_string(),
        }),
    ));

    Ok(())
}

/// Pause the sequence executor
pub async fn api_sequencer_pause() -> Result<(), NightshadeError> {
    tracing::info!("Pausing sequence execution");

    let executor = get_sequence_executor().read().await;
    executor.pause().await.map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to pause sequence: {}", e))
    })?;

    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::Sequencer,
        EventPayload::Sequencer(SequencerEvent::Paused),
    ));

    Ok(())
}

/// Resume the sequence executor
pub async fn api_sequencer_resume() -> Result<(), NightshadeError> {
    tracing::info!("Resuming sequence execution");

    let executor = get_sequence_executor().read().await;
    executor.resume().await.map_err(|e| {
        NightshadeError::OperationFailed(format!("Failed to resume sequence: {}", e))
    })?;

    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::Sequencer,
        EventPayload::Sequencer(SequencerEvent::Resumed),
    ));

    Ok(())
}

/// Stop the sequence executor
pub async fn api_sequencer_stop() -> Result<(), NightshadeError> {
    tracing::info!("Stopping sequence execution");

    let mut executor = get_sequence_executor().write().await;
    executor
        .stop()
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to stop sequence: {}", e)))?;

    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::Sequencer,
        EventPayload::Sequencer(SequencerEvent::Stopped),
    ));

    Ok(())
}

/// Skip to the next instruction
pub async fn api_sequencer_skip() -> Result<(), NightshadeError> {
    tracing::info!("Skipping current instruction");

    let executor = get_sequence_executor().read().await;
    executor
        .skip()
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to skip: {}", e)))?;

    Ok(())
}

/// Reset the sequence executor
pub async fn api_sequencer_reset() -> Result<(), NightshadeError> {
    tracing::info!("Resetting sequence executor");

    let mut executor = get_sequence_executor().write().await;
    executor.reset().await;

    Ok(())
}

/// Get the current sequencer state
pub async fn api_sequencer_get_state() -> SequencerState {
    let executor = get_sequence_executor().read().await;
    let progress = executor.get_progress();
    SequencerState::from(progress)
}

/// Subscribe to sequencer events and forward them to the main event stream
pub async fn api_sequencer_subscribe_events() -> Result<(), NightshadeError> {
    let executor = get_sequence_executor().read().await;
    let mut rx = executor.subscribe();
    let state = get_state().clone();

    tracing::info!("[EVENT_SUB] Sequencer event subscription started");

    tokio::spawn(async move {
        tracing::info!("[EVENT_SUB] Event listener task spawned");
        while let Ok(event) = rx.recv().await {
            tracing::debug!(
                "[EVENT_SUB] Received event: {:?}",
                std::mem::discriminant(&event)
            );
            let nightshade_event = match &event {
                ExecutorEvent::StateChanged(s) => {
                    let _state_str = match s {
                        ExecutorState::Running => "running",
                        ExecutorState::Paused => "paused",
                        ExecutorState::Cancelled => "cancelled",
                        ExecutorState::Completed => "completed",
                        _ => continue,
                    };
                    Some(create_event_auto_id(
                        EventSeverity::Info,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(match s {
                            ExecutorState::Paused => SequencerEvent::Paused,
                            ExecutorState::Cancelled => SequencerEvent::Stopped,
                            ExecutorState::Completed => SequencerEvent::Completed,
                            _ => continue,
                        }),
                    ))
                }
                ExecutorEvent::NodeStarted { id, name } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::NodeStarted {
                        node_id: id.clone(),
                        node_type: name.clone(),
                    }),
                )),
                ExecutorEvent::NodeCompleted { id, status } => {
                    let status_str = match status {
                        NodeStatus::Success => "success",
                        NodeStatus::Failure => "failed",
                        NodeStatus::Skipped => "skipped",
                        _ => "failed",
                    };
                    let severity = match status {
                        NodeStatus::Failure => EventSeverity::Warning,
                        _ => EventSeverity::Info,
                    };
                    Some(create_event_auto_id(
                        severity,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::NodeCompleted {
                            node_id: id.clone(),
                            status: status_str.to_string(),
                        }),
                    ))
                }
                ExecutorEvent::ProgressUpdated(progress) => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::Progress {
                        current: progress.completed_exposures,
                        total: progress.total_exposures,
                    }),
                )),
                ExecutorEvent::SequenceCompleted => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::Completed),
                )),
                ExecutorEvent::SequenceFailed { error } => Some(create_event_auto_id(
                    EventSeverity::Error,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::Error {
                        message: error.clone(),
                    }),
                )),
                ExecutorEvent::ExposureStarted {
                    frame,
                    total,
                    filter,
                    duration_secs,
                } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::ExposureStarted {
                        frame: *frame,
                        total: *total,
                        filter: filter.clone(),
                        duration_secs: *duration_secs,
                    }),
                )),
                ExecutorEvent::ExposureCompleted {
                    frame,
                    total,
                    duration_secs,
                } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::ExposureCompleted {
                        frame: *frame,
                        total: *total,
                        duration_secs: *duration_secs,
                    }),
                )),
                ExecutorEvent::TargetStarted { name, ra, dec } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::TargetChanged {
                        target_name: name.clone(),
                        ra: Some(*ra),
                        dec: Some(*dec),
                    }),
                )),
                ExecutorEvent::TargetCompleted { name } => Some(create_event_auto_id(
                    EventSeverity::Info,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::TargetCompleted {
                        target_name: name.clone(),
                    }),
                )),
                ExecutorEvent::NodeProgress {
                    node_id,
                    instruction,
                    progress_percent,
                    detail,
                } => {
                    tracing::info!(
                        "[EVENT_SUB] NodeProgress received: node={}, instruction={}, progress={}%",
                        node_id,
                        instruction,
                        progress_percent
                    );
                    Some(create_event_auto_id(
                        EventSeverity::Info,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::InstructionProgress {
                            node_id: node_id.clone(),
                            instruction: instruction.clone(),
                            progress_percent: *progress_percent,
                            detail: detail.clone(),
                        }),
                    ))
                }
                ExecutorEvent::Error { message } => Some(create_event_auto_id(
                    EventSeverity::Error,
                    EventCategory::Sequencer,
                    EventPayload::Sequencer(SequencerEvent::Error {
                        message: message.clone(),
                    }),
                )),
                ExecutorEvent::TriggerFired {
                    trigger_id,
                    trigger_name,
                    action,
                } => {
                    tracing::info!(
                        "Trigger fired: {} ({}) - {}",
                        trigger_name,
                        trigger_id,
                        action
                    );
                    Some(create_event_auto_id(
                        EventSeverity::Info,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::TriggerFired {
                            trigger_id: trigger_id.clone(),
                            trigger_name: trigger_name.clone(),
                            action: action.clone(),
                        }),
                    ))
                }
                ExecutorEvent::RuntimeConfigUpdated { what } => {
                    // Audit §1.8: surface runtime-config updates as a generic
                    // sequencer Error event with informational severity so the
                    // existing UI subscriber sees the change without needing
                    // a new typed payload (a typed payload would require an
                    // FRB regen).
                    tracing::info!("[EVENT_SUB] Runtime config updated: {}", what);
                    Some(create_event_auto_id(
                        EventSeverity::Info,
                        EventCategory::Sequencer,
                        EventPayload::Sequencer(SequencerEvent::Error {
                            message: format!("Runtime config updated: {}", what),
                        }),
                    ))
                }
            };

            if let Some(e) = nightshade_event {
                state.publish_event(e);
            }
        }
    });

    Ok(())
}

/// Stream of sequencer events (separate from main event stream for real-time progress)
#[flutter_rust_bridge::frb(ignore)]
pub fn api_sequencer_event_stream() -> impl futures::Stream<Item = String> {
    let rx = {
        let executor = get_sequence_executor().blocking_read();
        executor.subscribe()
    };

    async_stream::stream! {
        let mut rx = rx;
        loop {
            match rx.recv().await {
                Ok(event) => {
                    if let Ok(json) = serde_json::to_string(&event) {
                        yield json;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    // Update the global dropped event counter
                    let previous_total = TOTAL_DROPPED_EVENTS.fetch_add(n, Ordering::Relaxed);
                    let new_total = previous_total + n;

                    tracing::warn!(
                        "[SEQUENCER_EVENT_STREAM] Event stream lagged! Skipped {} events (total dropped: {}). \
                        Consider increasing buffer size or optimizing event handling.",
                        n, new_total
                    );
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    break;
                }
            }
        }
    }
}

// =============================================================================
// SEQUENCER CHECKPOINT / CRASH RECOVERY
// =============================================================================

/// Checkpoint info returned to Dart
#[derive(Debug, Clone)]
pub struct CheckpointInfoApi {
    pub sequence_name: String,
    pub timestamp: String,
    pub completed_exposures: u32,
    pub completed_integration_secs: f64,
    pub can_resume: bool,
    pub age_seconds: i64,
}

/// Set the checkpoint directory for crash recovery
pub async fn api_sequencer_set_checkpoint_dir(path: String) -> Result<(), NightshadeError> {
    tracing::info!("Setting checkpoint directory to: {}", path);
    let mut executor = get_sequence_executor().write().await;
    executor.set_checkpoint_dir(path);
    Ok(())
}

/// Check if a recoverable checkpoint exists
pub fn api_sequencer_has_checkpoint() -> bool {
    let executor = get_sequence_executor().blocking_read();
    executor.has_recoverable_checkpoint()
}

/// Get info about the current checkpoint
pub fn api_sequencer_get_checkpoint_info() -> Option<CheckpointInfoApi> {
    let executor = get_sequence_executor().blocking_read();
    executor
        .get_checkpoint_info()
        .map(|info| CheckpointInfoApi {
            sequence_name: info.sequence_name,
            timestamp: info.timestamp.to_rfc3339(),
            completed_exposures: info.completed_exposures,
            completed_integration_secs: info.completed_integration_secs,
            can_resume: info.can_resume,
            age_seconds: info.age_seconds,
        })
}

/// Resume sequence from checkpoint
pub async fn api_sequencer_resume_from_checkpoint() -> Result<(), NightshadeError> {
    tracing::info!("Resuming sequence from checkpoint");
    let mut executor = get_sequence_executor().write().await;

    // Set up device ops before resume - use UnifiedDeviceOps which routes through DeviceManager
    let ops = create_unified_device_ops();
    executor.set_device_ops(ops);

    executor
        .resume_from_checkpoint()
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Save current execution state as checkpoint
pub async fn api_sequencer_save_checkpoint() -> Result<(), NightshadeError> {
    tracing::info!("Saving checkpoint");
    let executor = get_sequence_executor().read().await;
    executor
        .save_checkpoint()
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Clear/discard checkpoint (call when sequence completes normally or user discards)
pub fn api_sequencer_clear_checkpoint() -> Result<(), NightshadeError> {
    tracing::info!("Clearing checkpoint");
    let executor = get_sequence_executor().blocking_read();
    executor
        .clear_checkpoint()
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set simulation mode (use mock devices instead of real hardware)
pub async fn api_sequencer_set_simulation_mode(enabled: bool) -> Result<(), NightshadeError> {
    tracing::info!("Setting sequencer simulation mode: {}", enabled);
    let mut executor = get_sequence_executor().write().await;

    // Production/release artifacts must not execute simulated hardware paths.
    if enabled && !cfg!(debug_assertions) {
        return Err(NightshadeError::NotSupported {
            device_id: "sequencer".to_string(),
            operation: "set_simulation_mode(true)".to_string(),
        });
    }

    if enabled {
        // Use NullDeviceOps for simulation
        executor.set_device_ops(std::sync::Arc::new(nightshade_sequencer::NullDeviceOps));
    } else {
        // Use UnifiedDeviceOps which routes through DeviceManager for real hardware
        let ops = create_unified_device_ops();
        executor.set_device_ops(ops);
    }

    Ok(())
}

/// Set connected devices for the sequencer
pub async fn api_sequencer_set_devices(
    camera_id: Option<String>,
    mount_id: Option<String>,
    focuser_id: Option<String>,
    filterwheel_id: Option<String>,
    rotator_id: Option<String>,
    filter_names: Option<Vec<String>>,
    filter_focus_offsets: Option<std::collections::HashMap<String, i32>>,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Setting sequencer devices: camera={:?}, mount={:?}, focuser={:?}, filterwheel={:?}, rotator={:?}, filter_names={:?}, filter_focus_offsets={:?}",
        camera_id, mount_id, focuser_id, filterwheel_id, rotator_id, filter_names, filter_focus_offsets
    );
    let filterwheel_for_names = filterwheel_id.clone();
    {
        let mut executor = get_sequence_executor().write().await;
        executor.set_devices(camera_id, mount_id, focuser_id, filterwheel_id, rotator_id);
        if let Some(offsets) = filter_focus_offsets {
            executor.set_filter_focus_offsets(offsets);
        }
    }

    if let Some(names) = filter_names {
        if names.is_empty() {
            return Err(NightshadeError::InvalidParameter(
                "filter_names was provided but empty; provide at least one name or pass null."
                    .to_string(),
            ));
        }

        let filterwheel_id = filterwheel_for_names.ok_or_else(|| {
            NightshadeError::InvalidParameter(
                "filter_names was provided but filterwheel_id is null. Provide a filter wheel ID before setting filter names."
                    .to_string(),
            )
        })?;

        let mgr = get_device_manager();
        mgr.filter_wheel_set_filter_names(&filterwheel_id, names)
            .await
            .map_err(|e| {
                NightshadeError::OperationFailed(format!(
                    "Failed to apply filter names to '{}': {}",
                    filterwheel_id, e
                ))
            })?;
    }

    Ok(())
}

/// Set the safety fail mode for the sequencer.
/// This determines behavior when safety devices fail or are unavailable:
/// - "fail_closed": Treat unavailable safety data as unsafe (enforced)
/// - "fail_open"/"warn_only": accepted for backward compatibility and coerced to fail_closed
pub async fn api_sequencer_set_safety_fail_mode(mode: String) -> Result<(), NightshadeError> {
    use nightshade_sequencer::SafetyFailMode;

    let mode_lower = mode.to_lowercase();
    let fail_mode = match mode_lower.as_str() {
        "fail_closed" | "failclosed" => SafetyFailMode::FailClosed,
        "fail_open" | "failopen" | "warn_only" | "warnonly" => {
            tracing::warn!(
                "Safety fail mode '{}' requested, but strict fail-closed is enforced; using fail_closed",
                mode
            );
            SafetyFailMode::FailClosed
        }
        _ => {
            return Err(NightshadeError::InvalidParameter(format!(
                "Invalid safety fail mode: '{}'. Must be 'fail_closed' (legacy aliases: 'fail_open', 'warn_only').",
                mode
            )));
        }
    };

    tracing::info!("Setting sequencer safety fail mode: {:?}", fail_mode);
    let mut executor = get_sequence_executor().write().await;
    executor.set_safety_fail_mode(fail_mode);

    Ok(())
}

/// Set the save path for sequencer images.
/// This is the base directory where captured images will be saved.
/// If not set (or set to None), images will NOT be saved to disk.
pub async fn api_sequencer_set_save_path(path: Option<String>) -> Result<(), NightshadeError> {
    let path_display = path.as_deref().unwrap_or("<none>");
    tracing::info!("Setting sequencer save path: {}", path_display);

    let mut executor = get_sequence_executor().write().await;
    executor.set_save_path(path.map(std::path::PathBuf::from));

    Ok(())
}

// =============================================================================
// SEQUENCER RUNTIME SETTINGS PROPAGATION
// =============================================================================

/// Update dither configuration at runtime while a sequence is running or paused.
/// The updated values are stored on the executor and will be used by subsequent
/// trigger-initiated dithers and checkpoint resumes.
pub async fn api_sequencer_update_dither_config(
    pixels: f64,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
    ra_only: bool,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Updating sequencer dither config: pixels={}, settle_pixels={}, settle_time={}, settle_timeout={}, ra_only={}",
        pixels, settle_pixels, settle_time, settle_timeout, ra_only
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_dither_config(pixels, settle_pixels, settle_time, settle_timeout, ra_only);
    Ok(())
}

/// Update observer location at runtime while a sequence is running or paused.
/// Updates the executor's stored latitude/longitude so altitude-based triggers
/// use the correct location on their next evaluation.
pub async fn api_sequencer_update_location(
    latitude: Option<f64>,
    longitude: Option<f64>,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Updating sequencer location: lat={:?}, lon={:?}",
        latitude,
        longitude
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_location(latitude, longitude);
    Ok(())
}

/// Update filter focus offsets at runtime while a sequence is running or paused.
/// Updates the executor's stored offsets so subsequent filter changes apply
/// the correct focus compensation.
pub async fn api_sequencer_update_filter_offsets(
    offsets: std::collections::HashMap<String, i32>,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Updating sequencer filter focus offsets: {} entries",
        offsets.len()
    );
    let mut executor = get_sequence_executor().write().await;
    executor.update_filter_offsets(offsets);
    Ok(())
}

// =============================================================================
// SEQUENCER NODE FACTORY - Create nodes programmatically
// =============================================================================

fn serialize_node_definition(node: &NodeDefinition) -> Result<String, NightshadeError> {
    serde_json::to_string(node).map_err(|e| {
        NightshadeError::SerializationError(format!(
            "Failed to serialize node '{}' ({}): {}",
            node.name, node.id, e
        ))
    })
}

fn serialize_sequence_definition(
    definition: &SequenceDefinition,
) -> Result<String, NightshadeError> {
    serde_json::to_string(definition).map_err(|e| {
        NightshadeError::SerializationError(format!(
            "Failed to serialize sequence '{}' ({}): {}",
            definition.name, definition.id, e
        ))
    })
}

/// Create an exposure node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_exposure_node(
    id: String,
    name: String,
    duration_secs: f64,
    count: u32,
    filter: Option<String>,
    filter_index: Option<i32>,
    gain: Option<i32>,
    offset: Option<i32>,
    binning: i32,
    dither_every: Option<u32>,
) -> Result<String, NightshadeError> {
    let binning_enum = match binning {
        1 => Binning::One,
        2 => Binning::Two,
        3 => Binning::Three,
        4 => Binning::Four,
        _ => Binning::One,
    };

    let config = ExposureConfig {
        duration_secs,
        count,
        filter,
        filter_index,
        gain,
        offset,
        binning: binning_enum,
        dither_every,
        dither_pixels: 5.0,
        dither_settle_pixels: 1.5,
        dither_settle_time: 30.0,
        dither_settle_timeout: 120.0,
        dither_ra_only: false,
        save_to: None,
        triggers: Vec::new(),
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::TakeExposure(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a slew node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_slew_node(
    id: String,
    name: String,
    use_target_coords: u8,
    custom_ra: Option<f64>,
    custom_dec: Option<f64>,
) -> Result<String, NightshadeError> {
    let config = SlewConfig {
        use_target_coords: use_target_coords != 0,
        custom_ra,
        custom_dec,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::SlewToTarget(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a center node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_center_node(
    id: String,
    name: String,
    use_target_coords: u8,
    accuracy_arcsec: f64,
    max_attempts: u32,
    exposure_duration: f64,
) -> Result<String, NightshadeError> {
    let config = CenterConfig {
        use_target_coords: use_target_coords != 0,
        custom_ra: None,
        custom_dec: None,
        accuracy_arcsec,
        max_attempts,
        exposure_duration,
        filter: None,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::CenterTarget(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create an autofocus node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_autofocus_node(
    id: String,
    name: String,
    step_size: i32,
    steps_out: u32,
    exposure_duration: f64,
    method: String,
) -> Result<String, NightshadeError> {
    let method_enum = match method.as_str() {
        "vcurve" => AutofocusMethod::VCurve,
        "quadratic" => AutofocusMethod::Quadratic,
        "hyperbolic" => AutofocusMethod::Hyperbolic,
        _ => AutofocusMethod::VCurve,
    };

    let config = AutofocusConfig {
        method: method_enum,
        step_size,
        steps_out,
        exposure_duration,
        filter: None,
        binning: Binning::One,
        max_duration_secs: 600.0,
        ..AutofocusConfig::default()
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Autofocus(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a filter change node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_filter_node(
    id: String,
    name: String,
    filter_name: String,
) -> Result<String, NightshadeError> {
    let config = FilterConfig {
        filter_name,
        filter_index: None,
        timeout_secs: None, // Use default timeout
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::ChangeFilter(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a target group node configuration (legacy - use target_header instead)
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_target_group_node(
    id: String,
    name: String,
    target_name: String,
    ra_hours: f64,
    dec_degrees: f64,
    rotation: Option<f64>,
    min_altitude: Option<f64>,
    max_altitude: Option<f64>,
    priority: i32,
    children: Vec<String>,
) -> Result<String, NightshadeError> {
    let config = TargetGroupConfig {
        target_name,
        ra_hours,
        dec_degrees,
        rotation,
        min_altitude,
        max_altitude,
        priority,
        ..Default::default()
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::TargetGroup(config),
        enabled: true,
        children,
    };

    serialize_node_definition(&node)
}

/// Create a target header node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_target_header_node(
    id: String,
    name: String,
    target_name: String,
    ra_hours: f64,
    dec_degrees: f64,
    rotation: Option<f64>,
    min_altitude: Option<f64>,
    max_altitude: Option<f64>,
    priority: i32,
    start_after: Option<i64>,
    end_before: Option<i64>,
    mosaic_panel_json: Option<String>,
    children: Vec<String>,
) -> Result<String, NightshadeError> {
    let mosaic_panel = mosaic_panel_json
        .map(|json| {
            serde_json::from_str(&json).map_err(|e| {
                NightshadeError::SerializationError(format!(
                    "Invalid target header mosaic panel JSON: {}",
                    e
                ))
            })
        })
        .transpose()?;

    let config = TargetHeaderConfig {
        target_name,
        ra_hours,
        dec_degrees,
        rotation,
        min_altitude,
        max_altitude,
        priority,
        start_after,
        end_before,
        mosaic_panel,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::TargetHeader(config),
        enabled: true,
        children,
    };

    serialize_node_definition(&node)
}

/// Create a loop node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_loop_node(
    id: String,
    name: String,
    iterations: Option<u32>,
    condition: String,
    children: Vec<String>,
) -> Result<String, NightshadeError> {
    let condition_enum = match condition.as_str() {
        "count" => LoopCondition::Count,
        "until_time" => LoopCondition::UntilTime,
        "altitude_below" => LoopCondition::AltitudeBelow,
        "altitude_above" => LoopCondition::AltitudeAbove,
        "integration_time" => LoopCondition::IntegrationTime,
        _ => LoopCondition::Count,
    };

    let config = LoopConfig {
        iterations,
        condition: condition_enum,
        condition_value: None,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Loop(config),
        enabled: true,
        children,
    };

    serialize_node_definition(&node)
}

/// Create a delay node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_delay_node(
    id: String,
    name: String,
    seconds: f64,
) -> Result<String, NightshadeError> {
    let config = DelayConfig { seconds };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Delay(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a park node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_park_node(id: String, name: String) -> Result<String, NightshadeError> {
    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Park,
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create an unpark node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_unpark_node(id: String, name: String) -> Result<String, NightshadeError> {
    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Unpark,
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a cool camera node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_cool_camera_node(
    id: String,
    name: String,
    target_temp: f64,
    duration_mins: Option<f64>,
) -> Result<String, NightshadeError> {
    let config = CoolConfig {
        target_temp,
        duration_mins,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::CoolCamera(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a warm camera node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_warm_camera_node(
    id: String,
    name: String,
    rate_per_min: f64,
    target_temp: Option<f64>,
) -> Result<String, NightshadeError> {
    let config = WarmConfig {
        rate_per_min,
        target_temp,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::WarmCamera(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a dither node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_dither_node(
    id: String,
    name: String,
    pixels: f64,
    settle_pixels: f64,
    settle_time: f64,
    settle_timeout: f64,
    ra_only: u8,
) -> Result<String, NightshadeError> {
    let config = DitherConfig {
        pixels,
        settle_pixels,
        settle_time,
        settle_timeout,
        ra_only: ra_only != 0,
        pattern: DitherPattern::default(),
        grid_size: 3,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Dither(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a wait time node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_wait_time_node(
    id: String,
    name: String,
    wait_until: Option<i64>,
    twilight_type: Option<String>,
) -> Result<String, NightshadeError> {
    let twilight = twilight_type.and_then(|t| match t.as_str() {
        "civil" => Some(TwilightType::Civil),
        "nautical" => Some(TwilightType::Nautical),
        "astronomical" => Some(TwilightType::Astronomical),
        _ => None,
    });

    let config = WaitTimeConfig {
        wait_until,
        wait_for_twilight: twilight,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::WaitForTime(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a notification node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_notification_node(
    id: String,
    name: String,
    title: String,
    message: String,
    level: String,
) -> Result<String, NightshadeError> {
    let level_enum = match level.as_str() {
        "info" => NotificationLevel::Info,
        "warning" => NotificationLevel::Warning,
        "error" => NotificationLevel::Error,
        "success" => NotificationLevel::Success,
        _ => NotificationLevel::Info,
    };

    let config = NotificationConfig {
        title,
        message,
        level: level_enum,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::Notification(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a script node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_script_node(
    id: String,
    name: String,
    script_path: String,
    arguments: Vec<String>,
    timeout_secs: Option<u32>,
) -> Result<String, NightshadeError> {
    let config = ScriptConfig {
        script_path,
        arguments,
        timeout_secs,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::RunScript(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Create a rotator node configuration
#[flutter_rust_bridge::frb(sync)]
pub fn api_create_rotator_node(
    id: String,
    name: String,
    target_angle: f64,
    relative: u8,
) -> Result<String, NightshadeError> {
    let config = RotatorConfig {
        target_angle,
        relative: relative != 0,
    };

    let node = NodeDefinition {
        id,
        name,
        node_type: NodeType::MoveRotator(config),
        enabled: true,
        children: vec![],
    };

    serialize_node_definition(&node)
}

/// Build a complete sequence definition from nodes
#[flutter_rust_bridge::frb(sync)]
pub fn api_build_sequence(
    id: String,
    name: String,
    description: Option<String>,
    node_jsons: Vec<String>,
    root_node_id: Option<String>,
) -> Result<String, NightshadeError> {
    let nodes: Result<Vec<NodeDefinition>, NightshadeError> = node_jsons
        .iter()
        .enumerate()
        .map(|(index, json)| {
            serde_json::from_str(json).map_err(|e| {
                NightshadeError::SerializationError(format!(
                    "Failed to deserialize node_jsons[{}]: {}",
                    index, e
                ))
            })
        })
        .collect();

    let definition = SequenceDefinition {
        id,
        name,
        description,
        nodes: nodes?,
        root_node_id,
        metadata: std::collections::HashMap::new(),
    };

    serialize_sequence_definition(&definition)
}

#[cfg(test)]
mod sequencer_node_factory_tests {
    use super::{
        api_build_sequence, api_create_filter_node, api_create_target_header_node, NodeDefinition,
        SequenceDefinition,
    };

    #[test]
    fn build_sequence_returns_error_for_invalid_node_json() {
        let err = api_build_sequence(
            "seq-1".to_string(),
            "Test".to_string(),
            None,
            vec!["{not-json}".to_string()],
            None,
        )
        .expect_err("invalid node JSON should be rejected");

        assert!(err
            .to_string()
            .contains("Failed to deserialize node_jsons[0]"));
    }

    #[test]
    fn target_header_rejects_invalid_mosaic_panel_json() {
        let err = api_create_target_header_node(
            "node-1".to_string(),
            "Target".to_string(),
            "M31".to_string(),
            0.5,
            41.0,
            None,
            None,
            None,
            1,
            None,
            None,
            Some("{invalid}".to_string()),
            vec![],
        )
        .expect_err("invalid mosaic JSON should be rejected");

        assert!(err
            .to_string()
            .contains("Invalid target header mosaic panel JSON"));
    }

    #[test]
    fn build_sequence_preserves_valid_nodes() {
        let filter_json =
            api_create_filter_node("node-1".to_string(), "Filter".to_string(), "L".to_string())
                .expect("filter node should serialize");

        let sequence_json = api_build_sequence(
            "seq-1".to_string(),
            "Test".to_string(),
            None,
            vec![filter_json],
            Some("node-1".to_string()),
        )
        .expect("valid sequence should serialize");

        let sequence: SequenceDefinition =
            serde_json::from_str(&sequence_json).expect("sequence JSON should deserialize");
        assert_eq!(sequence.nodes.len(), 1);

        let node: &NodeDefinition = &sequence.nodes[0];
        assert_eq!(node.id, "node-1");
    }
}

// =============================================================================
// Mosaic Calculation
// =============================================================================

/// Result structure for mosaic panel calculations (FFI-safe)
#[derive(Debug, Clone)]
pub struct MosaicPanelResult {
    pub ra_hours: f64,
    pub dec_degrees: f64,
    pub panel_index: u32,
    pub row: u32,
    pub col: u32,
}

impl From<MosaicPanel> for MosaicPanelResult {
    fn from(panel: MosaicPanel) -> Self {
        Self {
            ra_hours: panel.ra_hours,
            dec_degrees: panel.dec_degrees,
            panel_index: panel.panel_index,
            row: panel.row,
            col: panel.col,
        }
    }
}

/// Calculate mosaic panel positions given center coordinates and configuration
///
/// # Arguments
/// * `center_ra` - Center RA in hours (0-24)
/// * `center_dec` - Center Dec in degrees (-90 to +90)
/// * `panel_width_arcmin` - Panel width in arcminutes
/// * `panel_height_arcmin` - Panel height in arcminutes
/// * `overlap_percent` - Overlap percentage (0-50)
/// * `rotation` - Rotation angle in degrees
/// * `panels_horizontal` - Number of horizontal panels
/// * `panels_vertical` - Number of vertical panels
///
/// # Returns
/// Vector of MosaicPanelResult with calculated RA/Dec for each panel
#[flutter_rust_bridge::frb(sync)]
pub fn api_calculate_mosaic_panels(
    center_ra: f64,
    center_dec: f64,
    panel_width_arcmin: f64,
    panel_height_arcmin: f64,
    overlap_percent: f64,
    rotation: f64,
    panels_horizontal: u32,
    panels_vertical: u32,
) -> Vec<MosaicPanelResult> {
    let config = MosaicConfig {
        center_ra,
        center_dec,
        panel_width_arcmin,
        panel_height_arcmin,
        overlap_percent,
        rotation,
        panels_horizontal,
        panels_vertical,
        ..MosaicConfig::default()
    };

    calculate_mosaic_panels(&config)
        .into_iter()
        .map(MosaicPanelResult::from)
        .collect()
}

/// Calculate total mosaic coverage area in square degrees
#[flutter_rust_bridge::frb(sync)]
pub fn api_calculate_mosaic_area(
    panel_width_arcmin: f64,
    panel_height_arcmin: f64,
    panels_horizontal: u32,
    panels_vertical: u32,
) -> f64 {
    let total_width_arcmin = panel_width_arcmin * panels_horizontal as f64;
    let total_height_arcmin = panel_height_arcmin * panels_vertical as f64;
    // Return in square degrees
    (total_width_arcmin / 60.0) * (total_height_arcmin / 60.0)
}

/// Estimate total imaging time for mosaic in seconds
///
/// # Arguments
/// * `total_panels` - Total number of panels
/// * `exposure_secs` - Exposure time per frame
/// * `exposures_per_panel` - Number of exposures per panel
/// * `overhead_per_panel_secs` - Overhead per panel (slew, center, settle) - defaults to 60s if 0
#[flutter_rust_bridge::frb(sync)]
pub fn api_estimate_mosaic_time(
    total_panels: u32,
    exposure_secs: f64,
    exposures_per_panel: u32,
    overhead_per_panel_secs: f64,
) -> f64 {
    let overhead = if overhead_per_panel_secs <= 0.0 {
        60.0
    } else {
        overhead_per_panel_secs
    };
    let time_per_panel = exposure_secs * exposures_per_panel as f64 + overhead;
    total_panels as f64 * time_per_panel
}

/// Calculate altitude for a target at a specific time and observer location
///
/// # Arguments
/// * `ra_hours` - Right Ascension in hours (0-24)
/// * `dec_degrees` - Declination in degrees (-90 to +90)
/// * `latitude` - Observer's latitude in degrees (-90 to +90, positive is north)
/// * `longitude` - Observer's longitude in degrees (-180 to +180, positive is east)
/// * `time_unix_millis` - UTC time as Unix timestamp in milliseconds
///
/// # Returns
/// Altitude in degrees above the horizon (-90 to +90)
#[flutter_rust_bridge::frb(sync)]
pub fn api_calculate_altitude(
    ra_hours: f64,
    dec_degrees: f64,
    latitude: f64,
    longitude: f64,
    time_unix_millis: i64,
) -> f64 {
    use chrono::{TimeZone, Utc};

    // Convert Unix milliseconds to DateTime<Utc>
    let time = Utc
        .timestamp_millis_opt(time_unix_millis)
        .single()
        .unwrap_or_else(|| Utc::now());

    nightshade_sequencer::meridian::calculate_altitude(
        ra_hours,
        dec_degrees,
        latitude,
        longitude,
        time,
    )
}

// =============================================================================
// Polar Alignment
// =============================================================================

use std::sync::atomic::{AtomicBool as PolarAtomicBool, Ordering as PolarOrdering};

/// Track whether polar alignment is running
static POLAR_ALIGN_RUNNING: OnceLock<PolarAtomicBool> = OnceLock::new();
static POLAR_ALIGN_CANCEL: OnceLock<PolarAtomicBool> = OnceLock::new();

fn get_polar_align_flag() -> &'static PolarAtomicBool {
    POLAR_ALIGN_RUNNING.get_or_init(|| PolarAtomicBool::new(false))
}

fn get_polar_align_cancel() -> &'static PolarAtomicBool {
    POLAR_ALIGN_CANCEL.get_or_init(|| PolarAtomicBool::new(false))
}

/// Emit a polar alignment status update (JSON-serializable for Dart)
fn emit_polar_status(status: &str, phase: &str, point: i32) {
    tracing::info!(
        "Polar alignment: {} (phase={}, point={})",
        status,
        phase,
        point
    );
    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::PolarAlignment,
        EventPayload::PolarAlignmentStatus(PolarAlignmentStatus {
            status: status.to_string(),
            phase: phase.to_string(),
            point,
        }),
    ));
}

/// Emit polar alignment error update
fn emit_polar_error(
    az: f64,
    alt: f64,
    total: f64,
    cur_ra: f64,
    cur_dec: f64,
    tgt_ra: f64,
    tgt_dec: f64,
) {
    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::PolarAlignment,
        EventPayload::PolarAlignment(PolarAlignmentEvent {
            azimuth_error: az,
            altitude_error: alt,
            total_error: total,
            current_ra: cur_ra,
            current_dec: cur_dec,
            target_ra: tgt_ra,
            target_dec: tgt_dec,
        }),
    ));
}

/// Emit polar alignment image for UI display
/// Encodes the display data to JPEG for efficient transmission
fn emit_polar_image(
    image: &CapturedImageResult,
    point: i32,
    phase: &str,
    solved_ra: Option<f64>,
    solved_dec: Option<f64>,
) {
    use image::ImageEncoder;

    // Encode display_data (RGBA) to JPEG
    let mut buffer = Vec::new();
    {
        let mut cursor = std::io::Cursor::new(&mut buffer);
        let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut cursor, 85);
        if let Err(e) = encoder.write_image(
            &image.display_data,
            image.width as u32,
            image.height as u32,
            image::ColorType::Rgba8,
        ) {
            tracing::warn!("Failed to encode polar alignment image: {}", e);
            return;
        }
    }
    let color_type = image::ColorType::Rgba8;
    let jpeg_data = buffer;

    tracing::debug!(
        "Emitting polar alignment image: {}x{}, {:?}, point={}, phase={}, solved={:?}",
        image.width,
        image.height,
        color_type,
        point,
        phase,
        solved_ra.is_some()
    );

    get_state().publish_event(create_event_auto_id(
        EventSeverity::Info,
        EventCategory::PolarAlignment,
        EventPayload::PolarAlignmentImage(PolarAlignmentImageEvent {
            image_data: jpeg_data,
            width: image.width as u32,
            height: image.height as u32,
            solved_ra,
            solved_dec,
            point,
            phase: phase.to_string(),
        }),
    ));
}

/// Start three-point polar alignment
///
/// This initiates the polar alignment process which will:
/// 1. Capture 3 images at different mount rotations
/// 2. Plate solve each image
/// 3. Calculate the center of rotation
/// 4. Enter adjustment mode with real-time error updates
///
/// Note: Requires connected camera and mount devices.
pub async fn api_start_polar_alignment(
    exposure_time: f64,
    step_size: f64,
    binning: i32,
    is_north: bool,
    manual_rotation: bool,
    rotate_east: bool,
    gain: Option<i32>,
    offset: Option<i32>,
    solve_timeout: Option<f64>,
    start_from_current: Option<bool>,
    auto_complete_threshold: Option<f64>,
) -> Result<(), NightshadeError> {
    // Check if already running
    if get_polar_align_flag().load(PolarOrdering::Relaxed) {
        return Err(NightshadeError::OperationFailed(
            "Polar alignment already running".to_string(),
        ));
    }

    get_polar_align_flag().store(true, PolarOrdering::Relaxed);
    get_polar_align_cancel().store(false, PolarOrdering::Relaxed);

    tracing::info!(
        "Starting polar alignment: exposure={}s, step={}°, binning={}, north={}, manual={}, east={}",
        exposure_time, step_size, binning, is_north, manual_rotation, rotate_east
    );

    // Get connected devices using existing API
    let connected = api_get_connected_devices().await;

    // Find connected camera
    let camera_id = connected
        .iter()
        .find(|d| d.device_type == DeviceType::Camera)
        .map(|d| d.id.clone());

    // Find connected mount
    let mount_id = connected
        .iter()
        .find(|d| d.device_type == DeviceType::Mount)
        .map(|d| d.id.clone());

    let camera_id = camera_id.ok_or_else(|| {
        get_polar_align_flag().store(false, PolarOrdering::Relaxed);
        NightshadeError::DeviceNotFound("No camera connected".to_string())
    })?;

    let mount_id = mount_id.ok_or_else(|| {
        get_polar_align_flag().store(false, PolarOrdering::Relaxed);
        NightshadeError::DeviceNotFound("No mount connected".to_string())
    })?;

    // Spawn background task for polar alignment
    let gain_val = gain.unwrap_or(0);
    let offset_val = offset.unwrap_or(0);
    let solve_timeout_val = solve_timeout.unwrap_or(60.0);
    let start_from_current_val = start_from_current.unwrap_or(true);
    let auto_complete_threshold_val = auto_complete_threshold.unwrap_or(1.0); // Default 1 arcminute

    tokio::spawn(async move {
        let result = run_polar_alignment(
            camera_id,
            mount_id,
            exposure_time,
            step_size,
            binning,
            is_north,
            manual_rotation,
            rotate_east,
            start_from_current_val,
            gain_val,
            offset_val,
            solve_timeout_val,
            auto_complete_threshold_val,
        )
        .await;

        if let Err(e) = result {
            tracing::error!("Polar alignment failed: {}", e);
            emit_polar_status(&format!("Error: {}", e), "error", 0);
        }

        get_polar_align_flag().store(false, PolarOrdering::Relaxed);
    });

    Ok(())
}

/// Internal function to run the polar alignment process
async fn run_polar_alignment(
    camera_id: String,
    mount_id: String,
    exposure_time: f64,
    step_size: f64,
    binning: i32,
    is_north: bool,
    manual_rotation: bool,
    rotate_east: bool,
    start_from_current: bool,
    gain: i32,
    offset: i32,
    solve_timeout_secs: f64,
    auto_complete_threshold: f64,
) -> Result<(), String> {
    if !start_from_current {
        return Err(
            "Polar alignment with start_from_current=false is not supported by this workflow"
                .to_string(),
        );
    }

    let mut solved_points: Vec<(f64, f64)> = Vec::new();

    // Phase 1: Capture and solve 3 points
    for point in 1..=3 {
        // Check for cancellation
        if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
            emit_polar_status("Cancelled by user", "idle", 0);
            return Ok(());
        }

        emit_polar_status(
            &format!("Capturing point {}/3...", point),
            "measuring",
            point as i32,
        );

        // Capture image using existing API
        // api_camera_start_exposure(device_id, duration_secs, gain, offset, bin_x, bin_y)
        api_camera_start_exposure(
            camera_id.clone(),
            exposure_time,
            gain,
            offset,
            binning,
            binning,
        )
        .await
        .map_err(|e| format!("Failed to capture: {:?}", e))?;

        if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
            emit_polar_status("Cancelled by user", "idle", 0);
            return Ok(());
        }

        emit_polar_status(
            &format!("Plate solving point {}/3...", point),
            "measuring",
            point as i32,
        );

        // Get the captured image
        let image = api_get_last_image(camera_id.clone())
            .await
            .map_err(|e| format!("Failed to get image: {:?}", e))?;

        // Emit polar alignment image (before plate solve, no coordinates yet)
        emit_polar_image(&image, point as i32, "measuring", None, None);

        // Save temp file for plate solving
        let temp_path = create_unique_temp_fits_path(&format!("polar_align_point_{}", point));
        let temp_path_str = temp_path.to_string_lossy().to_string();

        // Write FITS file for plate solving
        if let Err(e) = write_temp_fits_for_solve(&image, &temp_path_str) {
            return Err(format!("Failed to write temp FITS: {}", e));
        }

        // Plate solve with configurable timeout
        let solve_future = api_plate_solve_blind(temp_path_str.clone());
        let solve_result = match tokio::time::timeout(
            tokio::time::Duration::from_secs_f64(solve_timeout_secs),
            solve_future,
        )
        .await
        {
            Ok(Ok(result)) => result,
            Ok(Err(e)) => {
                let _ = std::fs::remove_file(&temp_path);
                return Err(format!("Plate solve error: {:?}", e));
            }
            Err(_) => {
                let _ = std::fs::remove_file(&temp_path);
                return Err(format!(
                    "Plate solve timed out after {:.1} seconds for point {}",
                    solve_timeout_secs, point
                ));
            }
        };

        // Clean up temp file
        let _ = std::fs::remove_file(&temp_path);

        if solve_result.success {
            let ra_degrees = solve_result.ra * 15.0; // RA hours to degrees
            solved_points.push((ra_degrees, solve_result.dec));
            tracing::info!(
                "Point {} solved: RA={:.4}h ({:.4}°), Dec={:.4}°",
                point,
                solve_result.ra,
                ra_degrees,
                solve_result.dec
            );

            // Emit image again with plate solve coordinates
            emit_polar_image(
                &image,
                point as i32,
                "measuring",
                Some(ra_degrees),
                Some(solve_result.dec),
            );
        } else {
            return Err(format!(
                "Plate solve failed for point {}: {:?}",
                point, solve_result.error
            ));
        }

        // Rotate mount for next point (if not last point)
        if point < 3 {
            if manual_rotation {
                emit_polar_status(
                    &format!("Rotate mount {}° and wait...", step_size as i32),
                    "measuring",
                    point as i32,
                );
                // Wait for user to rotate manually
                tokio::time::sleep(tokio::time::Duration::from_secs(15)).await;
            } else {
                emit_polar_status(
                    &format!("Slewing to point {}...", point + 1),
                    "measuring",
                    point as i32,
                );

                // Calculate new position (in degrees)
                // Safe to get last() because we just pushed to solved_points above
                let (current_ra_deg, current_dec) = match solved_points.last() {
                    Some(coords) => coords,
                    None => {
                        return Err("No solved points available for slew calculation".to_string());
                    }
                };
                let move_amount = if rotate_east { step_size } else { -step_size };
                let target_ra_deg = (current_ra_deg + move_amount + 360.0) % 360.0;

                // Slew mount (API takes RA in hours, Dec in degrees)
                api_mount_slew_to_coordinates(mount_id.clone(), target_ra_deg / 15.0, *current_dec)
                    .await
                    .map_err(|e| format!("Failed to slew: {:?}", e))?;

                // Wait for slew to complete
                tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
            }
        }
    }

    // Phase 2: Calculate center of rotation
    emit_polar_status("Calculating polar alignment error...", "adjusting", 3);

    let (mut center_ra, mut center_dec) = calculate_rotation_center(&solved_points);
    let pole_dec = if is_north { 90.0 } else { -90.0 };

    tracing::info!(
        "Rotation center: RA={:.4}°, Dec={:.4}°",
        center_ra,
        center_dec
    );

    // Geometric validation: check if calculated center is within 15° of expected pole
    let dec_diff = (center_dec - pole_dec).abs();
    if dec_diff > 15.0 {
        let error_msg = format!(
            "Calculated rotation center (Dec={:.2}°) is {:.1}° away from expected pole (Dec={:.0}°). \
            This suggests poor plate solves or insufficient mount rotation. \
            Please ensure: 1) Clear view of pole area, 2) Mount rotates at least {}° between points, \
            3) Plate solving is accurate. Try increasing step size or checking camera focus.",
            center_dec, dec_diff, pole_dec, step_size
        );
        tracing::error!("{}", error_msg);
        emit_polar_status(&format!("Error: {}", error_msg), "error", 0);
        return Err(error_msg);
    }

    // Phase 3: Adjustment loop - continuously update error with rolling recalculation
    emit_polar_status("Adjustment mode - make corrections", "adjusting", 0);

    // Auto-complete timer: tracks when error first dropped below threshold
    let mut auto_complete_start: Option<std::time::Instant> = None;
    const AUTO_COMPLETE_DURATION_SECS: u64 = 3;

    let mut consecutive_failures = 0;
    const MAX_FAILURES: i32 = 5;

    loop {
        if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
            emit_polar_status("Stopped", "idle", 0);
            return Ok(());
        }

        // Capture and solve to get current position
        emit_polar_status("Capturing...", "adjusting", 0);
        if let Err(e) = api_camera_start_exposure(
            camera_id.clone(),
            exposure_time,
            gain,
            offset,
            binning,
            binning,
        )
        .await
        {
            consecutive_failures += 1;
            tracing::warn!("Capture failed in adjustment loop: {:?}", e);
            emit_polar_status(
                &format!(
                    "Capture failed: {:?} (retry {}/{})",
                    e, consecutive_failures, MAX_FAILURES
                ),
                "adjusting",
                0,
            );
            if consecutive_failures >= MAX_FAILURES {
                return Err(format!(
                    "Too many consecutive failures ({}) in adjustment loop",
                    MAX_FAILURES
                ));
            }
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
            continue;
        }

        if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
            emit_polar_status("Stopped", "idle", 0);
            return Ok(());
        }

        // Get the captured image
        let image = match api_get_last_image(camera_id.clone()).await {
            Ok(img) => img,
            Err(e) => {
                consecutive_failures += 1;
                tracing::warn!("Failed to get image in adjustment loop: {:?}", e);
                emit_polar_status(
                    &format!(
                        "Image retrieval failed (retry {}/{})",
                        consecutive_failures, MAX_FAILURES
                    ),
                    "adjusting",
                    0,
                );
                if consecutive_failures >= MAX_FAILURES {
                    return Err(format!(
                        "Too many consecutive failures ({}) in adjustment loop",
                        MAX_FAILURES
                    ));
                }
                tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                continue;
            }
        };

        // Emit polar alignment image (adjustment phase, no coordinates yet)
        emit_polar_image(&image, 0, "adjusting", None, None);

        let temp_path = create_unique_temp_fits_path("polar_align_adjust");
        let temp_path_str = temp_path.to_string_lossy().to_string();

        if let Err(e) = write_temp_fits_for_solve(&image, &temp_path_str) {
            consecutive_failures += 1;
            tracing::warn!("Failed to write temp FITS: {}", e);
            emit_polar_status(
                &format!(
                    "FITS write failed (retry {}/{})",
                    consecutive_failures, MAX_FAILURES
                ),
                "adjusting",
                0,
            );
            if consecutive_failures >= MAX_FAILURES {
                return Err(format!(
                    "Too many consecutive failures ({}) in adjustment loop",
                    MAX_FAILURES
                ));
            }
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
            continue;
        }

        emit_polar_status("Solving...", "adjusting", 0);

        // Plate solve with 30 second timeout (shorter for adjustment loop)
        let solve_future = api_plate_solve_blind(temp_path_str.clone());
        let solve_result =
            match tokio::time::timeout(tokio::time::Duration::from_secs(30), solve_future).await {
                Ok(Ok(result)) => {
                    let _ = std::fs::remove_file(&temp_path);
                    result
                }
                Ok(Err(e)) => {
                    let _ = std::fs::remove_file(&temp_path);
                    consecutive_failures += 1;
                    tracing::warn!("Plate solve error in adjustment loop: {:?}", e);
                    emit_polar_status(
                        &format!(
                            "Solve failed: {:?} (retry {}/{})",
                            e, consecutive_failures, MAX_FAILURES
                        ),
                        "adjusting",
                        0,
                    );
                    if consecutive_failures >= MAX_FAILURES {
                        return Err(format!(
                            "Too many consecutive failures ({}) in adjustment loop",
                            MAX_FAILURES
                        ));
                    }
                    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                    continue;
                }
                Err(_) => {
                    let _ = std::fs::remove_file(&temp_path);
                    consecutive_failures += 1;
                    tracing::warn!("Plate solve timed out in adjustment loop");
                    emit_polar_status(
                        &format!(
                            "Solve timed out (retry {}/{})",
                            consecutive_failures, MAX_FAILURES
                        ),
                        "adjusting",
                        0,
                    );
                    if consecutive_failures >= MAX_FAILURES {
                        return Err(format!(
                            "Too many consecutive failures ({}) in adjustment loop",
                            MAX_FAILURES
                        ));
                    }
                    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
                    continue;
                }
            };

        if solve_result.success {
            // Reset failure counter on success
            consecutive_failures = 0;

            let ra_degrees = solve_result.ra * 15.0; // hours to degrees

            // Emit image again with plate solve coordinates
            emit_polar_image(
                &image,
                0,
                "adjusting",
                Some(ra_degrees),
                Some(solve_result.dec),
            );

            // Rolling 3-point recalculation: add new point and keep only last 3
            solved_points.push((ra_degrees, solve_result.dec));
            if solved_points.len() > 3 {
                solved_points.remove(0); // Remove oldest point to maintain sliding window
            }

            // Recalculate rotation center from updated points (requires at least 3 points)
            if solved_points.len() >= 3 {
                let (new_center_ra, new_center_dec) = calculate_rotation_center(&solved_points);
                center_ra = new_center_ra;
                center_dec = new_center_dec;
                tracing::debug!(
                    "Updated rotation center: RA={:.4}°, Dec={:.4}°",
                    center_ra,
                    center_dec
                );
            }

            // Calculate error relative to recalculated pole position
            let alt_error = (pole_dec - center_dec) * 60.0; // arcminutes
            let az_error = (0.0 - center_ra) * center_dec.to_radians().cos() * 60.0;
            let total_error = (az_error.powi(2) + alt_error.powi(2)).sqrt();

            // Auto-complete logic: check if error is below threshold
            if total_error <= auto_complete_threshold {
                match auto_complete_start {
                    Some(start_time) => {
                        let elapsed = start_time.elapsed();
                        if elapsed.as_secs() >= AUTO_COMPLETE_DURATION_SECS {
                            // Error has been below threshold for required duration
                            tracing::info!(
                                "Polar alignment complete! Total error {:.2} arcmin below threshold {:.2} for {} seconds",
                                total_error, auto_complete_threshold, AUTO_COMPLETE_DURATION_SECS
                            );
                            emit_polar_status(
                                &format!(
                                    "Complete! Error {:.2}' below threshold for {}s",
                                    total_error, AUTO_COMPLETE_DURATION_SECS
                                ),
                                "complete",
                                0,
                            );
                            emit_polar_error(
                                az_error,
                                alt_error,
                                total_error,
                                ra_degrees,
                                solve_result.dec,
                                center_ra,
                                center_dec,
                            );
                            return Ok(());
                        } else {
                            // Still within threshold, update status with countdown
                            let remaining = AUTO_COMPLETE_DURATION_SECS - elapsed.as_secs();
                            emit_polar_status(
                                &format!("Below threshold - completing in {}s...", remaining),
                                "adjusting",
                                0,
                            );
                        }
                    }
                    None => {
                        // First time below threshold, start timer
                        auto_complete_start = Some(std::time::Instant::now());
                        tracing::info!(
                            "Error {:.2} arcmin dropped below threshold {:.2}, starting auto-complete timer",
                            total_error, auto_complete_threshold
                        );
                        emit_polar_status(
                            &format!(
                                "Below threshold - completing in {}s...",
                                AUTO_COMPLETE_DURATION_SECS
                            ),
                            "adjusting",
                            0,
                        );
                    }
                }
            } else {
                // Error above threshold, reset timer if it was running
                if auto_complete_start.is_some() {
                    tracing::debug!(
                        "Error {:.2} arcmin went back above threshold {:.2}, resetting auto-complete timer",
                        total_error, auto_complete_threshold
                    );
                    auto_complete_start = None;
                }
                emit_polar_status("Adjusting - make corrections", "adjusting", 0);
            }

            emit_polar_error(
                az_error,
                alt_error,
                total_error,
                ra_degrees,
                solve_result.dec,
                center_ra,
                center_dec,
            );
        } else {
            consecutive_failures += 1;
            // Failed solve means we can't track error, reset auto-complete timer
            auto_complete_start = None;
            emit_polar_status(
                &format!(
                    "Solve unsuccessful (retry {}/{})",
                    consecutive_failures, MAX_FAILURES
                ),
                "adjusting",
                0,
            );
            if consecutive_failures >= MAX_FAILURES {
                return Err(format!(
                    "Too many consecutive failures ({}) in adjustment loop",
                    MAX_FAILURES
                ));
            }
        }

        // Brief pause before next update
        tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
    }
}

/// Helper to write a temp FITS file for plate solving
fn write_temp_fits_for_solve(image: &CapturedImageResult, path: &str) -> Result<(), String> {
    use nightshade_imaging::{write_fits, FitsHeader, ImageData, PixelType};
    use std::path::Path;

    // Convert RGBA display_data to grayscale 16-bit for FITS plate solving.
    // display_data is always RGBA (4 bytes per pixel).
    let raw_bytes: Vec<u8> = if image.is_color {
        // For color RGBA, convert to grayscale (luminance) and scale to 16-bit
        image
            .display_data
            .chunks(4)
            .flat_map(|rgba| {
                let lum = ((rgba[0] as u32 + rgba[1] as u32 + rgba[2] as u32) / 3) as u16 * 256;
                lum.to_le_bytes().to_vec()
            })
            .collect()
    } else {
        // For grayscale RGBA, take the R channel (all RGB channels are the same) and scale to 16-bit
        image
            .display_data
            .chunks(4)
            .flat_map(|rgba| {
                let scaled = (rgba[0] as u16) * 256;
                scaled.to_le_bytes().to_vec()
            })
            .collect()
    };

    let mut image_data = ImageData::new(
        image.width as u32,
        image.height as u32,
        1, // grayscale
        PixelType::U16,
    );
    image_data.data = raw_bytes;

    let header = FitsHeader::new();

    write_fits(Path::new(path), &image_data, &header)
        .map_err(|e| format!("FITS write error: {:?}", e))
}

/// Calculate the center of rotation from 3 solved points using 3D plane fitting
fn calculate_rotation_center(points: &[(f64, f64)]) -> (f64, f64) {
    if points.len() < 3 {
        return (0.0, 90.0);
    }

    // Convert spherical (RA, Dec) to Cartesian unit vectors
    let vectors: Vec<(f64, f64, f64)> = points
        .iter()
        .map(|(ra, dec)| {
            let ra_rad = ra.to_radians();
            let dec_rad = dec.to_radians();
            (
                dec_rad.cos() * ra_rad.cos(),
                dec_rad.cos() * ra_rad.sin(),
                dec_rad.sin(),
            )
        })
        .collect();

    // The three points define a plane. The rotation axis is the normal to this plane.
    let p1 = vectors[0];
    let p2 = vectors[1];
    let p3 = vectors[2];

    let v1 = (p2.0 - p1.0, p2.1 - p1.1, p2.2 - p1.2);
    let v2 = (p3.0 - p1.0, p3.1 - p1.1, p3.2 - p1.2);

    // Cross product for normal
    let nx = v1.1 * v2.2 - v1.2 * v2.1;
    let ny = v1.2 * v2.0 - v1.0 * v2.2;
    let nz = v1.0 * v2.1 - v1.1 * v2.0;

    // Normalize
    let mag = (nx * nx + ny * ny + nz * nz).sqrt();
    if mag < 1e-9 {
        return (0.0, 90.0);
    }

    let nx = nx / mag;
    let ny = ny / mag;
    let nz = nz / mag;

    // Convert back to RA/Dec
    let center_dec_rad = nz.asin();
    let mut center_ra_rad = ny.atan2(nx);

    if center_ra_rad < 0.0 {
        center_ra_rad += 2.0 * std::f64::consts::PI;
    }

    (center_ra_rad.to_degrees(), center_dec_rad.to_degrees())
}

/// Stop the polar alignment process
pub async fn api_stop_polar_alignment() -> Result<(), NightshadeError> {
    if !get_polar_align_flag().load(PolarOrdering::Relaxed) {
        return Ok(()); // Already stopped
    }

    // Signal cancellation
    get_polar_align_cancel().store(true, PolarOrdering::Relaxed);

    tracing::info!("Stopping polar alignment");

    // Give the background task time to clean up
    tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;

    get_polar_align_flag().store(false, PolarOrdering::Relaxed);

    emit_polar_status("Stopped", "idle", 0);

    Ok(())
}

// =============================================================================
// All-Sky Polar Alignment (Sharpcap-style)
// =============================================================================

/// Polar alignment mode selector.
///
/// The traditional `ThreePoint` mode (TPPA) requires a clear view of the
/// celestial pole region. `AllSky` mode performs Sharpcap-style polar
/// alignment from any point in the sky using a single solved frame plus
/// live drift feedback.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PolarAlignmentMode {
    /// Three-Point Polar Alignment — requires pole region visible.
    ThreePoint,
    /// Sharpcap-style all-sky polar alignment — works from any sky direction.
    AllSky,
}

/// Start all-sky polar alignment.
///
/// Unlike TPPA this routine does not require the celestial pole region to
/// be visible. It takes a single exposure anywhere in the sky, plate-solves
/// it to anchor a baseline, then re-solves every `iteration_cadence_secs`
/// to measure drift relative to that baseline. From the drift signature
/// and the observer's geographic location it recovers the polar-axis
/// azimuth and altitude error.
///
/// # Arguments
/// * `exposure_time` — exposure duration per frame, seconds.
/// * `solve_timeout` — plate-solve timeout per frame, seconds.
/// * `binning` — camera binning factor (1, 2, or 4 typical).
/// * `is_north` — northern hemisphere observer flag.
/// * `acceptance_threshold_arcsec` — alignment auto-completes when the
///   total error stays below this for 3 seconds (default 30″ = good for
///   ~3-minute unguided subs).
/// * `iteration_cadence_secs` — re-solve cadence (default 3s).
/// * `gain`, `offset` — optional camera parameters.
///
/// # Errors
/// Returns `NightshadeError::OperationFailed` if a plate solver is not
/// available (the user must install ASTAP), if no camera/mount is
/// connected, or if the observer location is not configured.
pub async fn api_start_all_sky_polar_alignment(
    exposure_time: f64,
    solve_timeout: f64,
    binning: i32,
    is_north: bool,
    acceptance_threshold_arcsec: f64,
    iteration_cadence_secs: f64,
    gain: Option<i32>,
    offset: Option<i32>,
) -> Result<(), NightshadeError> {
    use nightshade_sequencer::all_sky_polar::{
        perform_all_sky_polar_alignment, AllSkyPolarAlignConfig, PolarAlignError,
    };
    use nightshade_sequencer::{Binning, InstructionContext};

    // Reject re-entrant starts.
    if get_polar_align_flag().load(PolarOrdering::Relaxed) {
        return Err(NightshadeError::OperationFailed(
            "Polar alignment already running".to_string(),
        ));
    }

    // Fail loudly if the plate solver isn't installed — the all-sky
    // algorithm is plate-solve-only by design.
    if !nightshade_imaging::is_solver_available() {
        return Err(NightshadeError::OperationFailed(
            "Plate solver required — install ASTAP and re-run all-sky polar alignment"
                .to_string(),
        ));
    }

    get_polar_align_flag().store(true, PolarOrdering::Relaxed);
    get_polar_align_cancel().store(false, PolarOrdering::Relaxed);

    tracing::info!(
        "Starting all-sky polar alignment: exposure={}s, threshold={}\", cadence={}s, north={}",
        exposure_time,
        acceptance_threshold_arcsec,
        iteration_cadence_secs,
        is_north
    );

    // Resolve connected devices.
    let connected = api_get_connected_devices().await;
    let camera_id = connected
        .iter()
        .find(|d| d.device_type == DeviceType::Camera)
        .map(|d| d.id.clone())
        .ok_or_else(|| {
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
            NightshadeError::DeviceNotFound("No camera connected".to_string())
        })?;
    let mount_id = connected
        .iter()
        .find(|d| d.device_type == DeviceType::Mount)
        .map(|d| d.id.clone())
        .ok_or_else(|| {
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
            NightshadeError::DeviceNotFound("No mount connected".to_string())
        })?;

    // Observer location is mandatory for the horizontal-frame projection.
    let location = get_state()
        .get_observer_location()
        .map_err(|e| {
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
            NightshadeError::OperationFailed(format!("Failed to read observer location: {}", e))
        })?
        .ok_or_else(|| {
            get_polar_align_flag().store(false, PolarOrdering::Relaxed);
            NightshadeError::OperationFailed(
                "Observer latitude/longitude is required for all-sky polar alignment".to_string(),
            )
        })?;

    let config = AllSkyPolarAlignConfig {
        exposure_time,
        solve_timeout,
        gain,
        offset,
        binning: Some(binning),
        is_north,
        acceptance_threshold_arcsec,
        iteration_cadence_secs,
    };

    // Spawn the alignment task. Errors are emitted on the polar alignment
    // event stream so the UI can present them clearly.
    let cancel_flag = Arc::new(AtomicBool::new(false));
    let cancel_flag_outer = cancel_flag.clone();

    // Bridge between the global cancel flag (set by `api_stop_polar_alignment`)
    // and the per-task cancellation token used by InstructionContext.
    tokio::spawn(async move {
        loop {
            if get_polar_align_cancel().load(PolarOrdering::Relaxed) {
                cancel_flag_outer.store(true, Ordering::Relaxed);
                break;
            }
            if !get_polar_align_flag().load(PolarOrdering::Relaxed) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(250)).await;
        }
    });

    let device_ops = create_unified_device_ops();

    tokio::spawn(async move {
        let ctx = InstructionContext {
            target_ra: None,
            target_dec: None,
            target_name: None,
            current_filter: None,
            current_binning: Binning::One,
            cancellation_token: cancel_flag,
            camera_id: Some(camera_id.clone()),
            mount_id: Some(mount_id.clone()),
            focuser_id: None,
            filterwheel_id: None,
            rotator_id: None,
            dome_id: None,
            cover_calibrator_id: None,
            save_path: None,
            latitude: Some(location.latitude),
            longitude: Some(location.longitude),
            device_ops,
            trigger_state: None,
            filter_focus_offsets: std::collections::HashMap::new(),
        };

        let status_cb = |status: String, _progress: Option<f64>| {
            emit_polar_status(&status, "adjusting", 0);
        };
        let image_cb = |image_data: nightshade_sequencer::PolarAlignmentImageData| {
            get_state().publish_event(create_event_auto_id(
                EventSeverity::Info,
                EventCategory::PolarAlignment,
                EventPayload::PolarAlignmentImage(PolarAlignmentImageEvent {
                    image_data: image_data.image_data,
                    width: image_data.width,
                    height: image_data.height,
                    solved_ra: image_data.solved_ra,
                    solved_dec: image_data.solved_dec,
                    point: image_data.point,
                    phase: image_data.phase,
                }),
            ));
        };
        let error_cb = |result: &nightshade_sequencer::PolarAlignResult| {
            emit_polar_error(
                result.azimuth_error,
                result.altitude_error,
                result.total_error,
                result.current_ra,
                result.current_dec,
                result.target_ra,
                result.target_dec,
            );
        };

        let result =
            perform_all_sky_polar_alignment(&config, &ctx, status_cb, image_cb, error_cb).await;

        match result {
            Ok(()) => {
                emit_polar_status("All-sky polar alignment complete", "complete", 0);
            }
            Err(PolarAlignError::Cancelled) => {
                emit_polar_status("Stopped", "idle", 0);
            }
            Err(PolarAlignError::SolverUnavailable) => {
                emit_polar_status(
                    "Plate solver required — install ASTAP and re-run all-sky polar alignment",
                    "error",
                    0,
                );
                tracing::error!(
                    "All-sky polar alignment aborted: plate solver not available"
                );
            }
            Err(e) => {
                emit_polar_status(&format!("Error: {}", e), "error", 0);
                tracing::error!("All-sky polar alignment failed: {}", e);
            }
        }

        get_polar_align_flag().store(false, PolarOrdering::Relaxed);
    });

    Ok(())
}

// =============================================================================
// Equipment Profiles
// =============================================================================

/// Initialize profile storage
#[flutter_rust_bridge::frb(sync)]
pub fn api_init_profile_storage(storage_path: String) -> Result<(), NightshadeError> {
    crate::state::init_profile_storage(std::path::PathBuf::from(storage_path))
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get all equipment profiles
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_profiles() -> Result<Vec<EquipmentProfile>, NightshadeError> {
    get_state()
        .load_profiles()
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Save an equipment profile
#[flutter_rust_bridge::frb(sync)]
pub fn api_save_profile(profile: EquipmentProfile) -> Result<(), NightshadeError> {
    get_state()
        .save_profile_to_storage(&profile)
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Delete an equipment profile
#[flutter_rust_bridge::frb(sync)]
pub fn api_delete_profile(profile_id: String) -> Result<(), NightshadeError> {
    get_state()
        .delete_profile_from_storage(&profile_id)
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Load a profile and set as active
pub async fn api_load_profile(profile_id: String) -> Result<(), NightshadeError> {
    get_state()
        .load_and_set_profile(&profile_id)
        .await
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get the currently active profile
pub async fn api_get_active_profile() -> Result<Option<EquipmentProfile>, NightshadeError> {
    Ok(get_state().get_profile().await)
}

// =============================================================================
// Settings & Location
// =============================================================================

/// Initialize settings storage and load observer location into memory
#[flutter_rust_bridge::frb(sync)]
pub fn api_init_settings_storage(storage_path: String) -> Result<(), NightshadeError> {
    let path = std::path::PathBuf::from(storage_path);
    crate::state::init_settings_storage(path.clone())
        .map_err(|e| NightshadeError::OperationFailed(e))?;
    // Plate-solver preferences share the settings directory. Errors here are
    // not fatal — the API falls back to in-memory defaults if storage is
    // unavailable — but a hard failure to initialise still surfaces.
    crate::state::init_platesolver_storage(path)
        .map_err(|e| NightshadeError::OperationFailed(e))?;

    // Load observer location from persisted settings into in-memory state
    // This ensures the sequencer and other Rust components have access to location
    get_state().load_observer_location_from_settings();

    Ok(())
}

/// Get application settings
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_settings() -> Result<AppSettings, NightshadeError> {
    get_state()
        .get_settings()
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Update application settings
#[flutter_rust_bridge::frb(sync)]
pub fn api_update_settings(settings: AppSettings) -> Result<(), NightshadeError> {
    get_state()
        .update_settings(&settings)
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Get observer location
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_location() -> Result<Option<ObserverLocation>, NightshadeError> {
    get_state()
        .get_observer_location()
        .map_err(|e| NightshadeError::OperationFailed(e))
}

/// Set observer location
#[flutter_rust_bridge::frb(sync)]
pub fn api_set_location(location: Option<ObserverLocation>) -> Result<(), NightshadeError> {
    match &location {
        Some(loc) => {
            tracing::info!(
                "[API] api_set_location called with lat={}, lon={}, elev={}",
                loc.latitude,
                loc.longitude,
                loc.elevation
            );
        }
        None => {
            tracing::info!("[API] api_set_location called with None");
        }
    }
    let result = get_state().set_observer_location(location);
    match &result {
        Ok(_) => {
            tracing::debug!("[API] api_set_location succeeded");
        }
        Err(ref e) => {
            tracing::error!("[API] api_set_location failed: {}", e);
        }
    }
    result.map_err(|e| NightshadeError::OperationFailed(e))
}

// =============================================================================
// FITS File Saving
// =============================================================================

/// Header data for FITS file writing
#[derive(Debug, Clone)]
pub struct FitsWriteHeader {
    pub object_name: Option<String>,
    pub exposure_time: f64,
    pub capture_timestamp: String,
    pub frame_type: String,
    pub filter: Option<String>,
    pub gain: Option<i32>,
    pub offset: Option<i32>,
    pub ccd_temp: Option<f64>,
    pub ra: Option<f64>,
    pub dec: Option<f64>,
    pub altitude: Option<f64>,
    pub telescope: Option<String>,
    pub instrument: Option<String>,
    pub observer: Option<String>,
    pub bin_x: i32,
    pub bin_y: i32,
    pub focal_length: Option<f64>,
    pub aperture: Option<f64>,
    pub pixel_size_x: Option<f64>,
    pub pixel_size_y: Option<f64>,
    pub site_latitude: Option<f64>,
    pub site_longitude: Option<f64>,
    pub site_elevation: Option<f64>,
}

/// Save image data to FITS file
pub async fn api_save_fits_file(
    file_path: String,
    width: u32,
    height: u32,
    data: Vec<u16>,
    header_data: FitsWriteHeader,
) -> Result<(), NightshadeError> {
    tracing::info!("Saving FITS file to: {}", file_path);

    // Create ImageData
    let image = ImageData::from_u16(width, height, 1, &data);

    // Validate image data
    let validation = validate_image(&image, Some(width), Some(height));
    if !validation.is_valid {
        tracing::warn!("Image validation failed: {:?}", validation.errors);
    }
    for warning in &validation.warnings {
        tracing::warn!("Image validation warning: {}", warning);
    }

    // Create FitsHeader
    let mut header = FitsHeader::new();

    // Core observation metadata
    header.set_float("EXPTIME", header_data.exposure_time);
    header.set_string("DATE-OBS", &header_data.capture_timestamp);
    header.set_string("IMAGETYP", &header_data.frame_type);

    if let Some(name) = header_data.object_name {
        header.set_string("OBJECT", &name);
    }
    if let Some(filter) = header_data.filter {
        header.set_string("FILTER", &filter);
    }

    // Camera settings
    if let Some(gain) = header_data.gain {
        header.set_int("GAIN", gain as i64);
    }
    if let Some(offset) = header_data.offset {
        header.set_int("OFFSET", offset as i64);
    }
    if let Some(temp) = header_data.ccd_temp {
        header.set_float("CCD-TEMP", temp);
    }

    header.set_int("XBINNING", header_data.bin_x as i64);
    header.set_int("YBINNING", header_data.bin_y as i64);

    // Pixel size information
    if let Some(pixel_x) = header_data.pixel_size_x {
        header.set_float("PIXSIZE1", pixel_x);
        header.set_float("XPIXSZ", pixel_x * header_data.bin_x as f64);
    }
    if let Some(pixel_y) = header_data.pixel_size_y {
        header.set_float("PIXSIZE2", pixel_y);
        header.set_float("YPIXSZ", pixel_y * header_data.bin_y as f64);
    }

    // Telescope/optics information
    if let Some(focal_length) = header_data.focal_length {
        header.set_float("FOCALLEN", focal_length);
    }
    if let Some(aperture) = header_data.aperture {
        header.set_float("APTDIA", aperture);
    }
    if let Some(telescope) = header_data.telescope {
        header.set_string("TELESCOP", &telescope);
    }
    if let Some(instrument) = header_data.instrument {
        header.set_string("INSTRUME", &instrument);
    }

    // Observer information
    if let Some(observer) = header_data.observer {
        header.set_string("OBSERVER", &observer);
    }

    // Observer location
    if let Some(lat) = header_data.site_latitude {
        header.set_float("SITELAT", lat);
    }
    if let Some(long) = header_data.site_longitude {
        header.set_float("SITELONG", long);
    }
    if let Some(elev) = header_data.site_elevation {
        header.set_float("SITEELEV", elev);
    }

    // Target coordinates and airmass
    if let Some(ra) = header_data.ra {
        header.set_float("RA", ra);
    }
    if let Some(dec) = header_data.dec {
        header.set_float("DEC", dec);
    }
    if let Some(altitude) = header_data.altitude {
        // Why: airmass returns Err for below-horizon inputs (audit §6.14). Surface
        // that as an OperationFailed so the caller knows the frame metadata was
        // attempted with an invalid altitude rather than silently writing a
        // sentinel value or omitting the keyword.
        let airmass = calculate_airmass(altitude).map_err(|e| {
            NightshadeError::OperationFailed(format!(
                "Cannot compute AIRMASS for altitude {}°: {}",
                altitude, e
            ))
        })?;
        header.set_float("AIRMASS", airmass);
    }

    // Validate header completeness
    let header_validation = validate_fits_header(&header);
    for warning in &header_validation.warnings {
        tracing::debug!("FITS header warning: {}", warning);
    }

    // Ensure directory exists
    if let Some(parent) = std::path::Path::new(&file_path).parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            NightshadeError::OperationFailed(format!("Failed to create directory: {}", e))
        })?;
    }

    // Write file
    // write_fits is blocking, so execute it in spawn_blocking.

    let path = std::path::PathBuf::from(file_path);

    tokio::task::spawn_blocking(move || write_fits(&path, &image, &header))
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("Task join error: {}", e)))?
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to write FITS: {}", e)))?;

    Ok(())
}

/// Save FITS file directly from the last captured image stored in Rust
/// This eliminates the need to transfer raw pixel data across the FFI boundary
/// by using the image data already stored from the last exposure.
///
/// Returns an error if no image has been captured yet for the specified device.
pub async fn api_save_fits_from_last_capture(
    device_id: String,
    file_path: String,
    header_data: FitsWriteHeader,
) -> Result<(), NightshadeError> {
    tracing::info!(
        "Saving FITS from last capture for device {} to: {}",
        device_id,
        file_path
    );

    // Get the stored raw image data for this device
    let storage = get_unified_image_storage().read().await;
    let captured_data = storage.get(&device_id).ok_or_else(|| {
        NightshadeError::OperationFailed(format!(
            "No captured image available for device {}. Please capture an image first.",
            device_id
        ))
    })?;

    // Clone the data we need so we can release the lock before the blocking write
    let width = captured_data.raw_info.width;
    let height = captured_data.raw_info.height;
    let data = captured_data.raw_info.data.clone();
    drop(storage); // Release the read lock

    // Now save using the existing logic
    tracing::info!("Saving {}x{} image ({} pixels)", width, height, data.len());

    // Create ImageData
    let image = ImageData::from_u16(width, height, 1, &data);

    // Validate image data
    let validation = validate_image(&image, Some(width), Some(height));
    if !validation.is_valid {
        tracing::warn!("Image validation failed: {:?}", validation.errors);
    }
    for warning in &validation.warnings {
        tracing::warn!("Image validation warning: {}", warning);
    }

    // Create FitsHeader
    let mut header = FitsHeader::new();

    // Core observation metadata
    header.set_float("EXPTIME", header_data.exposure_time);
    header.set_string("DATE-OBS", &header_data.capture_timestamp);
    header.set_string("IMAGETYP", &header_data.frame_type);

    if let Some(name) = header_data.object_name {
        header.set_string("OBJECT", &name);
    }
    if let Some(filter) = header_data.filter {
        header.set_string("FILTER", &filter);
    }

    // Camera settings
    if let Some(gain) = header_data.gain {
        header.set_int("GAIN", gain as i64);
    }
    if let Some(offset) = header_data.offset {
        header.set_int("OFFSET", offset as i64);
    }
    if let Some(temp) = header_data.ccd_temp {
        header.set_float("CCD-TEMP", temp);
    }

    header.set_int("XBINNING", header_data.bin_x as i64);
    header.set_int("YBINNING", header_data.bin_y as i64);

    // Pixel size information
    if let Some(pixel_x) = header_data.pixel_size_x {
        header.set_float("PIXSIZE1", pixel_x);
        header.set_float("XPIXSZ", pixel_x * header_data.bin_x as f64);
    }
    if let Some(pixel_y) = header_data.pixel_size_y {
        header.set_float("PIXSIZE2", pixel_y);
        header.set_float("YPIXSZ", pixel_y * header_data.bin_y as f64);
    }

    // Telescope/optics information
    if let Some(focal_length) = header_data.focal_length {
        header.set_float("FOCALLEN", focal_length);
    }
    if let Some(aperture) = header_data.aperture {
        header.set_float("APTDIA", aperture);
    }
    if let Some(telescope) = header_data.telescope {
        header.set_string("TELESCOP", &telescope);
    }
    if let Some(instrument) = header_data.instrument {
        header.set_string("INSTRUME", &instrument);
    }

    // Observer information
    if let Some(observer) = header_data.observer {
        header.set_string("OBSERVER", &observer);
    }

    // Observer location
    if let Some(lat) = header_data.site_latitude {
        header.set_float("SITELAT", lat);
    }
    if let Some(long) = header_data.site_longitude {
        header.set_float("SITELONG", long);
    }
    if let Some(elev) = header_data.site_elevation {
        header.set_float("SITEELEV", elev);
    }

    // Target coordinates and airmass
    if let Some(ra) = header_data.ra {
        header.set_float("RA", ra);
    }
    if let Some(dec) = header_data.dec {
        header.set_float("DEC", dec);
    }
    if let Some(altitude) = header_data.altitude {
        // Why: airmass returns Err for below-horizon inputs (audit §6.14). Surface
        // that as an OperationFailed so the caller knows the frame metadata was
        // attempted with an invalid altitude rather than silently writing a
        // sentinel value or omitting the keyword.
        let airmass = calculate_airmass(altitude).map_err(|e| {
            NightshadeError::OperationFailed(format!(
                "Cannot compute AIRMASS for altitude {}°: {}",
                altitude, e
            ))
        })?;
        header.set_float("AIRMASS", airmass);
    }

    // Validate header completeness
    let header_validation = validate_fits_header(&header);
    for warning in &header_validation.warnings {
        tracing::debug!("FITS header warning: {}", warning);
    }

    // Ensure directory exists
    if let Some(parent) = std::path::Path::new(&file_path).parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            NightshadeError::OperationFailed(format!("Failed to create directory: {}", e))
        })?;
    }

    // Write file using spawn_blocking
    let path = std::path::PathBuf::from(file_path);

    tokio::task::spawn_blocking(move || write_fits(&path, &image, &header))
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("Task join error: {}", e)))?
        .map_err(|e| NightshadeError::OperationFailed(format!("Failed to write FITS: {}", e)))?;

    tracing::info!("FITS file saved successfully from last capture");
    Ok(())
}

// =============================================================================
// Image Processing
// =============================================================================

/// Calculate image statistics
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_image_stats(
    width: u32,
    height: u32,
    data: Vec<u16>,
) -> Result<ImageStatsResult, NightshadeError> {
    let stats = crate::imaging_ops::get_image_stats(width, height, data);
    Ok(ImageStatsResult {
        min: stats.min,
        max: stats.max,
        mean: stats.mean,
        median: stats.median,
        std_dev: stats.std_dev,
        hfr: None,
        star_count: 0,
    })
}

/// Auto-stretch image for display
#[flutter_rust_bridge::frb(sync)]
pub fn api_auto_stretch_image(
    width: u32,
    height: u32,
    data: Vec<u16>,
) -> Result<Vec<u8>, NightshadeError> {
    Ok(crate::imaging_ops::auto_stretch_image(width, height, data))
}

/// Debayer image
#[flutter_rust_bridge::frb(sync)]
pub fn api_debayer_image(
    width: u32,
    height: u32,
    data: Vec<u16>,
    pattern_str: String,
    algo_str: String,
) -> Result<Vec<u8>, NightshadeError> {
    let pattern = BayerPattern::from_str(&pattern_str).ok_or_else(|| {
        NightshadeError::InvalidParameter(format!("Invalid bayer pattern: {}", pattern_str))
    })?;

    let algorithm = match algo_str.to_lowercase().as_str() {
        "bilinear" => DebayerAlgorithm::Bilinear,
        "vng" => DebayerAlgorithm::VNG,
        "superpixel" => DebayerAlgorithm::SuperPixel,
        _ => DebayerAlgorithm::Bilinear,
    };

    Ok(crate::imaging_ops::debayer_image(
        width, height, data, pattern, algorithm,
    ))
}

/// Generate thumbnail from FITS file
/// Returns JPEG-encoded thumbnail data (~512x512 pixels)
#[flutter_rust_bridge::frb(sync)]
pub fn api_generate_fits_thumbnail(
    file_path: String,
    max_size: u32,
) -> Result<Vec<u8>, NightshadeError> {
    use nightshade_imaging::read_fits;
    use std::path::Path;

    // Read FITS file
    let path = Path::new(&file_path);
    let (image_data, _header) = read_fits(path)
        .map_err(|e| NightshadeError::ImageError(format!("Failed to read FITS: {:?}", e)))?;

    // Convert to u16 data
    let data_u16 = match image_data.pixel_type {
        nightshade_imaging::PixelType::U8 => {
            // Convert u8 to u16
            image_data
                .data
                .iter()
                .map(|&b| (b as u16) << 8)
                .collect::<Vec<u16>>()
        }
        nightshade_imaging::PixelType::U16 => {
            // Already u16, convert bytes to u16 values
            image_data
                .data
                .chunks_exact(2)
                .map(|chunk| u16::from_be_bytes([chunk[0], chunk[1]]))
                .collect::<Vec<u16>>()
        }
        nightshade_imaging::PixelType::U32 => {
            // Convert u32 to u16 (downscale)
            image_data
                .data
                .chunks_exact(4)
                .map(|chunk| {
                    let val = u32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                    (val >> 16) as u16 // Take high 16 bits
                })
                .collect::<Vec<u16>>()
        }
        nightshade_imaging::PixelType::F32 => {
            // Convert f32 to u16 (scale 0.0-1.0 to 0-65535)
            image_data
                .data
                .chunks_exact(4)
                .map(|chunk| {
                    let val = f32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                    (val.clamp(0.0, 1.0) * 65535.0) as u16
                })
                .collect::<Vec<u16>>()
        }
        nightshade_imaging::PixelType::F64 => {
            // Convert f64 to u16 (scale 0.0-1.0 to 0-65535)
            image_data
                .data
                .chunks_exact(8)
                .map(|chunk| {
                    let val = f64::from_be_bytes([
                        chunk[0], chunk[1], chunk[2], chunk[3], chunk[4], chunk[5], chunk[6],
                        chunk[7],
                    ]);
                    (val.clamp(0.0, 1.0) * 65535.0) as u16
                })
                .collect::<Vec<u16>>()
        }
    };

    let width = image_data.width;
    let height = image_data.height;

    // Calculate downscale factor
    let scale = ((width.max(height) as f32) / max_size as f32).ceil() as u32;
    let scale = scale.max(1);

    // Downscale image
    let new_width = width / scale;
    let new_height = height / scale;
    let mut downscaled = Vec::with_capacity((new_width * new_height) as usize);

    for y in 0..new_height {
        for x in 0..new_width {
            let src_x = x * scale;
            let src_y = y * scale;
            let idx = (src_y * width + src_x) as usize;
            if idx < data_u16.len() {
                downscaled.push(data_u16[idx]);
            } else {
                downscaled.push(0);
            }
        }
    }

    // Auto-stretch for display
    let stretched = crate::imaging_ops::auto_stretch_image(new_width, new_height, downscaled);

    // Encode as JPEG
    use image::{GrayImage, ImageEncoder};
    use std::io::Cursor;

    let gray_img = GrayImage::from_raw(new_width, new_height, stretched).ok_or_else(|| {
        NightshadeError::ImageError("Failed to create grayscale image".to_string())
    })?;

    let mut jpeg_data = Vec::new();
    let mut cursor = Cursor::new(&mut jpeg_data);
    let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut cursor, 85);
    encoder
        .write_image(
            gray_img.as_raw(),
            new_width,
            new_height,
            image::ColorType::L8,
        )
        .map_err(|e| NightshadeError::ImageError(format!("JPEG encoding failed: {}", e)))?;

    Ok(jpeg_data)
}

#[cfg(windows)]
pub mod ascom_connections {
    use super::*;
    use std::collections::HashMap;

    // Storage for active ASCOM connections
    static ASCOM_CAMERAS: OnceLock<Arc<RwLock<HashMap<String, nightshade_ascom::AscomCamera>>>> =
        OnceLock::new();
    static ASCOM_MOUNTS: OnceLock<Arc<RwLock<HashMap<String, nightshade_ascom::AscomMount>>>> =
        OnceLock::new();
    static ASCOM_FOCUSERS: OnceLock<Arc<RwLock<HashMap<String, nightshade_ascom::AscomFocuser>>>> =
        OnceLock::new();

    fn get_ascom_cameras() -> &'static Arc<RwLock<HashMap<String, nightshade_ascom::AscomCamera>>> {
        ASCOM_CAMERAS.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
    }

    fn get_ascom_mounts() -> &'static Arc<RwLock<HashMap<String, nightshade_ascom::AscomMount>>> {
        ASCOM_MOUNTS.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
    }

    fn get_ascom_focusers() -> &'static Arc<RwLock<HashMap<String, nightshade_ascom::AscomFocuser>>>
    {
        ASCOM_FOCUSERS.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
    }

    /// Connect to a real ASCOM camera
    pub async fn connect_ascom_camera(prog_id: &str) -> Result<(), NightshadeError> {
        let mut camera = nightshade_ascom::AscomCamera::new(prog_id)
            .map_err(|e| NightshadeError::connection_failed(prog_id, e))?;

        camera
            .connect()
            .map_err(|e| NightshadeError::connection_failed(prog_id, e))?;

        let name = camera.name().unwrap_or_else(|_| prog_id.to_string());
        tracing::info!("Connected to ASCOM camera: {}", name);

        // Store the connection
        let mut cameras = get_ascom_cameras().write().await;
        cameras.insert(prog_id.to_string(), camera);

        Ok(())
    }

    /// Connect to a real ASCOM mount
    pub async fn connect_ascom_mount(prog_id: &str) -> Result<(), NightshadeError> {
        let mut mount = nightshade_ascom::AscomMount::new(prog_id)
            .map_err(|e| NightshadeError::connection_failed(prog_id, e))?;

        mount
            .connect()
            .map_err(|e| NightshadeError::connection_failed(prog_id, e))?;

        let name = mount.name().unwrap_or_else(|_| prog_id.to_string());
        tracing::info!("Connected to ASCOM mount: {}", name);

        // Store the connection
        let mut mounts = get_ascom_mounts().write().await;
        mounts.insert(prog_id.to_string(), mount);

        Ok(())
    }

    /// Connect to a real ASCOM focuser
    pub async fn connect_ascom_focuser(prog_id: &str) -> Result<(), NightshadeError> {
        let mut focuser = nightshade_ascom::AscomFocuser::new(prog_id)
            .map_err(|e| NightshadeError::connection_failed(prog_id, e))?;

        focuser
            .connect()
            .map_err(|e| NightshadeError::connection_failed(prog_id, e))?;

        tracing::info!("Connected to ASCOM focuser: {}", prog_id);

        // Store the connection
        let mut focusers = get_ascom_focusers().write().await;
        focusers.insert(prog_id.to_string(), focuser);

        Ok(())
    }

    /// Get real ASCOM camera temperature
    pub async fn get_ascom_camera_temp(prog_id: &str) -> Result<f64, NightshadeError> {
        let cameras = get_ascom_cameras().read().await;
        let camera = cameras
            .get(prog_id)
            .ok_or_else(|| NightshadeError::NotConnected(prog_id.to_string()))?;

        camera
            .ccd_temperature()
            .map_err(|e| NightshadeError::OperationFailed(e))
    }

    /// Get real ASCOM mount coordinates
    pub async fn get_ascom_mount_coords(prog_id: &str) -> Result<(f64, f64), NightshadeError> {
        let mounts = get_ascom_mounts().read().await;
        let mount = mounts
            .get(prog_id)
            .ok_or_else(|| NightshadeError::NotConnected(prog_id.to_string()))?;

        let ra = mount
            .right_ascension()
            .map_err(|e| NightshadeError::OperationFailed(e))?;
        let dec = mount
            .declination()
            .map_err(|e| NightshadeError::OperationFailed(e))?;

        Ok((ra, dec))
    }

    /// Slew real ASCOM mount
    pub async fn slew_ascom_mount(prog_id: &str, ra: f64, dec: f64) -> Result<(), NightshadeError> {
        let mut mounts = get_ascom_mounts().write().await;
        let mount = mounts
            .get_mut(prog_id)
            .ok_or_else(|| NightshadeError::NotConnected(prog_id.to_string()))?;

        mount
            .slew_to_coordinates_async(ra, dec)
            .map_err(|e| NightshadeError::OperationFailed(e))
    }

    /// Get real ASCOM focuser position
    pub async fn get_ascom_focuser_position(prog_id: &str) -> Result<i32, NightshadeError> {
        let focusers = get_ascom_focusers().read().await;
        let focuser = focusers
            .get(prog_id)
            .ok_or_else(|| NightshadeError::NotConnected(prog_id.to_string()))?;

        focuser
            .position()
            .map_err(|e| NightshadeError::OperationFailed(e))
    }

    /// Move real ASCOM focuser
    pub async fn move_ascom_focuser(prog_id: &str, position: i32) -> Result<(), NightshadeError> {
        let mut focusers = get_ascom_focusers().write().await;
        let focuser = focusers
            .get_mut(prog_id)
            .ok_or_else(|| NightshadeError::NotConnected(prog_id.to_string()))?;

        focuser
            .move_to(position)
            .map_err(|e| NightshadeError::OperationFailed(e))
    }
}

/// Apply Auto White Balance using Histogram Peak Alignment
/// This aligns the background sky peak of R and B channels to the G channel
fn apply_auto_white_balance(image: &mut [u16]) {
    if image.len() % 3 != 0 {
        return;
    }

    let mut hist_r = vec![0u32; 65536];
    let mut hist_g = vec![0u32; 65536];
    let mut hist_b = vec![0u32; 65536];

    // 1. Compute histograms
    for chunk in image.chunks(3) {
        hist_r[chunk[0] as usize] += 1;
        hist_g[chunk[1] as usize] += 1;
        hist_b[chunk[2] as usize] += 1;
    }

    // 2. Find peaks (modes), ignoring bottom 1% to avoid clipping noise
    // A simple mode might be noisy, so let's find the max bin
    // We start searching from a small offset to avoid black clipping
    let start_idx = 100; // arbitrary small offset

    let get_peak = |hist: &[u32]| -> u16 {
        let mut max_count = 0;
        let mut peak_idx = 0;
        for (i, &count) in hist.iter().enumerate().skip(start_idx) {
            if count > max_count {
                max_count = count;
                peak_idx = i;
            }
        }
        peak_idx as u16
    };

    let peak_r = get_peak(&hist_r);
    let peak_g = get_peak(&hist_g);
    let peak_b = get_peak(&hist_b);

    tracing::info!("AWB Peaks: R={}, G={}, B={}", peak_r, peak_g, peak_b);

    if peak_r == 0 || peak_g == 0 || peak_b == 0 {
        tracing::warn!("AWB failed: peak is 0");
        return;
    }

    // 3. Calculate scaling factors to align to Green
    let target = peak_g as f32;
    let scale_r = target / peak_r as f32;
    let scale_b = target / peak_b as f32;

    tracing::info!("AWB Scales: R={:.3}, B={:.3}", scale_r, scale_b);

    // 4. Apply scaling
    // Use parallel iterator for speed if possible, but slice is mutable
    // Rayon's par_chunks_mut is perfect
    use rayon::prelude::*;
    image.par_chunks_mut(3).for_each(|pixel| {
        // R
        pixel[0] = (pixel[0] as f32 * scale_r).min(65535.0) as u16;
        // G (unchanged)
        // B
        pixel[2] = (pixel[2] as f32 * scale_b).min(65535.0) as u16;
    });
}

// =============================================================================
// INDI Autofocus
// =============================================================================

/// INDI autofocus configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IndiAutofocusConfigApi {
    pub method: String, // "vcurve", "quadratic", "hyperbolic"
    pub step_size: i32,
    pub steps_out: u32,
    pub exposure_duration: f64,
    pub backlash_compensation: i32,
    pub use_temperature_prediction: bool,
    pub max_star_count_change: Option<f64>,
    pub outlier_rejection_sigma: f64,
    pub binning: i32,
    pub move_timeout_secs: u64,
    pub settling_time_ms: u64,
}

impl Default for IndiAutofocusConfigApi {
    fn default() -> Self {
        Self {
            method: "vcurve".to_string(),
            step_size: 100,
            steps_out: 7,
            exposure_duration: 3.0,
            backlash_compensation: 50,
            use_temperature_prediction: true,
            max_star_count_change: Some(0.5),
            outlier_rejection_sigma: 3.0,
            binning: 1,
            move_timeout_secs: 120,
            settling_time_ms: 500,
        }
    }
}

/// INDI autofocus result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IndiAutofocusResultApi {
    pub best_position: i32,
    pub best_hfr: f64,
    pub curve_fit_quality: f64,
    pub method_used: String,
    pub data_points: Vec<FocusDataPointApi>,
    pub temperature_celsius: Option<f64>,
    pub backlash_applied: bool,
    pub success: bool,
    pub error_message: Option<String>,
}

/// Focus data point for autofocus curve
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FocusDataPointApi {
    pub position: i32,
    pub hfr: f64,
    pub fwhm: Option<f64>,
    pub star_count: u32,
}

/// Run INDI autofocus routine
///
/// # Arguments
/// * `camera_id` - INDI camera device ID (format: "indi:host:port:device_name")
/// * `focuser_id` - INDI focuser device ID (format: "indi:host:port:device_name")
/// * `config` - Autofocus configuration
///
/// # Returns
/// Autofocus result with best focus position and curve data
pub async fn api_run_indi_autofocus(
    camera_id: String,
    focuser_id: String,
    config: IndiAutofocusConfigApi,
) -> Result<IndiAutofocusResultApi, NightshadeError> {
    tracing::info!(
        "Starting INDI autofocus: camera={}, focuser={}, method={}",
        camera_id,
        focuser_id,
        config.method
    );

    // Validate device IDs are INDI
    if !camera_id.starts_with("indi:") || !focuser_id.starts_with("indi:") {
        return Err(NightshadeError::InvalidParameter(
            "Both camera and focuser must be INDI devices".to_string(),
        ));
    }

    // Get INDI clients for camera and focuser
    let device_manager = get_device_manager();

    let camera_client = device_manager
        .get_indi_client(&camera_id)
        .await
        .ok_or_else(|| {
            NightshadeError::NotConnected(format!("INDI camera not connected: {}", camera_id))
        })?;

    let focuser_client = device_manager
        .get_indi_client(&focuser_id)
        .await
        .ok_or_else(|| {
            NightshadeError::NotConnected(format!("INDI focuser not connected: {}", focuser_id))
        })?;

    // Extract device names from IDs (format: "indi:host:port:device_name")
    let camera_parts: Vec<&str> = camera_id.split(':').collect();
    let camera_device_name = camera_parts[3..].join(":");

    let focuser_parts: Vec<&str> = focuser_id.split(':').collect();
    let focuser_device_name = focuser_parts[3..].join(":");

    // Create INDI camera and focuser wrappers
    let camera = Arc::new(nightshade_indi::IndiCamera::new(
        camera_client,
        &camera_device_name,
    ));

    let focuser = Arc::new(nightshade_indi::IndiFocuser::new(
        focuser_client,
        &focuser_device_name,
    ));

    // Convert config
    let method = match config.method.as_str() {
        "vcurve" => nightshade_indi::autofocus::AutofocusMethod::VCurve,
        "quadratic" => nightshade_indi::autofocus::AutofocusMethod::Quadratic,
        "hyperbolic" => nightshade_indi::autofocus::AutofocusMethod::Hyperbolic,
        _ => nightshade_indi::autofocus::AutofocusMethod::VCurve,
    };

    let af_config = nightshade_indi::autofocus::IndiAutofocusConfig {
        method,
        step_size: config.step_size,
        steps_out: config.steps_out,
        exposure_duration: config.exposure_duration,
        backlash_compensation: config.backlash_compensation,
        use_temperature_prediction: config.use_temperature_prediction,
        max_star_count_change: config.max_star_count_change,
        outlier_rejection_sigma: config.outlier_rejection_sigma,
        binning: config.binning,
        move_timeout_secs: config.move_timeout_secs,
        settling_time_ms: config.settling_time_ms,
    };

    // Create autofocus engine
    let autofocus = nightshade_indi::autofocus::IndiAutofocus::new(camera, focuser, af_config);

    // Run autofocus
    let result = autofocus
        .run()
        .await
        .map_err(|e| NightshadeError::OperationFailed(format!("INDI autofocus failed: {}", e)))?;

    // Convert result
    let method_str = match result.method_used {
        nightshade_indi::autofocus::AutofocusMethod::VCurve => "vcurve",
        nightshade_indi::autofocus::AutofocusMethod::Quadratic => "quadratic",
        nightshade_indi::autofocus::AutofocusMethod::Hyperbolic => "hyperbolic",
    };

    let data_points: Vec<FocusDataPointApi> = result
        .data_points
        .iter()
        .map(|dp| FocusDataPointApi {
            position: dp.position,
            hfr: dp.hfr,
            fwhm: dp.fwhm,
            star_count: dp.star_count,
        })
        .collect();

    Ok(IndiAutofocusResultApi {
        best_position: result.best_position,
        best_hfr: result.best_hfr,
        curve_fit_quality: result.curve_fit_quality,
        method_used: method_str.to_string(),
        data_points,
        temperature_celsius: result.temperature_celsius,
        backlash_applied: result.backlash_applied,
        success: result.success,
        error_message: result.error_message,
    })
}

// =============================================================================
// DEVICE CAPABILITY REPORTING API
// =============================================================================

/// Get capabilities for any device by its device ID.
///
/// This function queries the actual device to determine what features it supports.
/// The result varies by device type (camera, mount, focuser, filter wheel).
///
/// # Arguments
/// * `device_id` - The full device ID string (e.g., "ascom:ASCOM.Camera.Simulator")
///
/// # Returns
/// * `DeviceCapabilities` - An enum containing the appropriate capability struct
///
/// # Errors
/// * Returns error if device type is unsupported or device cannot be queried
pub async fn api_get_device_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::DeviceCapabilities, NightshadeError> {
    crate::device_capabilities::get_device_capabilities(&device_id).await
}

/// Get camera capabilities for a specific camera device.
///
/// This is a convenience wrapper that returns only camera capabilities.
///
/// # Arguments
/// * `device_id` - The camera device ID
///
/// # Returns
/// * `CameraCapabilities` - Camera-specific capability information
pub async fn api_get_camera_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::CameraCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Camera(c) => Ok(c),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a camera",
        )),
    }
}

/// Get mount capabilities for a specific mount device.
///
/// This is a convenience wrapper that returns only mount capabilities.
///
/// # Arguments
/// * `device_id` - The mount/telescope device ID
///
/// # Returns
/// * `MountCapabilities` - Mount-specific capability information
pub async fn api_get_mount_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::MountCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Mount(m) => Ok(m),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a mount",
        )),
    }
}

/// Get focuser capabilities for a specific focuser device.
///
/// This is a convenience wrapper that returns only focuser capabilities.
///
/// # Arguments
/// * `device_id` - The focuser device ID
///
/// # Returns
/// * `FocuserCapabilities` - Focuser-specific capability information
pub async fn api_get_focuser_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::FocuserCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Focuser(f) => Ok(f),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a focuser",
        )),
    }
}

/// Get filter wheel capabilities for a specific filter wheel device.
///
/// This is a convenience wrapper that returns only filter wheel capabilities.
///
/// # Arguments
/// * `device_id` - The filter wheel device ID
///
/// # Returns
/// * `FilterWheelCapabilities` - Filter wheel-specific capability information
pub async fn api_get_filterwheel_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::FilterWheelCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::FilterWheel(fw) => Ok(fw),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a filter wheel",
        )),
    }
}

/// Get rotator capabilities for a specific rotator device.
///
/// This is a convenience wrapper that returns only rotator capabilities.
///
/// # Arguments
/// * `device_id` - The rotator device ID
///
/// # Returns
/// * `RotatorCapabilities` - Rotator-specific capability information
pub async fn api_get_rotator_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::RotatorCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Rotator(r) => Ok(r),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a rotator",
        )),
    }
}

/// Get dome capabilities for a specific dome device.
///
/// This is a convenience wrapper that returns only dome capabilities.
///
/// # Arguments
/// * `device_id` - The dome device ID
///
/// # Returns
/// * `DomeCapabilities` - Dome-specific capability information
pub async fn api_get_dome_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::DomeCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Dome(d) => Ok(d),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a dome",
        )),
    }
}

/// Get cover calibrator capabilities for a specific cover calibrator device.
///
/// This is a convenience wrapper that returns only cover calibrator capabilities.
///
/// # Arguments
/// * `device_id` - The cover calibrator device ID
///
/// # Returns
/// * `CoverCalibratorCapabilities` - Cover calibrator-specific capability information
pub async fn api_get_cover_calibrator_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::CoverCalibratorCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::CoverCalibrator(cc) => Ok(cc),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a cover calibrator",
        )),
    }
}

/// Get weather capabilities for a specific weather/observing conditions device.
///
/// This is a convenience wrapper that returns only weather capabilities.
///
/// # Arguments
/// * `device_id` - The weather device ID
///
/// # Returns
/// * `WeatherCapabilities` - Weather-specific capability information
pub async fn api_get_weather_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::WeatherCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Weather(w) => Ok(w),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a weather station",
        )),
    }
}

/// Get safety monitor capabilities for a specific safety monitor device.
///
/// This is a convenience wrapper that returns only safety monitor capabilities.
///
/// # Arguments
/// * `device_id` - The safety monitor device ID
///
/// # Returns
/// * `SafetyMonitorCapabilities` - Safety monitor-specific capability information
pub async fn api_get_safety_monitor_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::SafetyMonitorCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::SafetyMonitor(sm) => Ok(sm),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a safety monitor",
        )),
    }
}

/// Get switch capabilities for a specific switch device.
///
/// This is a convenience wrapper that returns only switch capabilities.
///
/// # Arguments
/// * `device_id` - The switch device ID
///
/// # Returns
/// * `SwitchCapabilities` - Switch-specific capability information
pub async fn api_get_switch_capabilities(
    device_id: String,
) -> Result<crate::device_capabilities::SwitchCapabilities, NightshadeError> {
    let caps = crate::device_capabilities::get_device_capabilities(&device_id).await?;
    match caps {
        crate::device_capabilities::DeviceCapabilities::Switch(s) => Ok(s),
        _ => Err(NightshadeError::not_supported(
            &device_id,
            "Device is not a switch",
        )),
    }
}

// =============================================================================
// DEVICE QUIRKS
// =============================================================================

/// Information about a known device quirk, suitable for UI display.
pub struct QuirkInfo {
    /// Quirk category (e.g. "Temperature", "Timing", "Discovery")
    pub category: String,
    /// Human-readable description of the quirk
    pub description: String,
}

/// Get known quirks for a connected device.
///
/// Returns a list of known device characteristics and workarounds that are
/// automatically applied. This information can be displayed in the equipment
/// screen to inform users about device-specific behaviors.
///
/// # Arguments
/// * `device_id` - The device identifier (e.g., "native:zwo:ASI294MC Pro")
///
/// # Returns
/// * `Vec<QuirkInfo>` - List of quirks with categories and descriptions
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_device_quirks(device_id: String) -> Vec<QuirkInfo> {
    let quirks = nightshade_native::quirks::get_quirks_for_device(&device_id);
    quirks
        .into_iter()
        .map(|q| QuirkInfo {
            category: q.category().to_string(),
            description: q.description(),
        })
        .collect()
}

// =============================================================================
// QHY DISCOVERY CONTROL
// =============================================================================

/// Check if QHY camera discovery is enabled.
///
/// QHY discovery can be disabled if the QHY SDK causes crashes or hangs on the
/// user's system. When disabled, QHY cameras will not appear in device discovery.
///
/// # Returns
/// * `true` - QHY discovery is enabled (default)
/// * `false` - QHY discovery is disabled
#[flutter_rust_bridge::frb(sync)]
pub fn api_is_qhy_discovery_enabled() -> bool {
    nightshade_native::vendor::qhy::is_qhy_discovery_enabled()
}

/// Enable or disable QHY camera discovery.
///
/// Use this function to disable QHY discovery if it causes problems:
/// - SDK crashes during enumeration
/// - Discovery hangs and never completes
/// - Conflicts with other camera SDKs
///
/// When disabled:
/// - `discover_devices()` returns empty for QHY cameras/filter wheels
/// - Existing QHY camera connections are not affected
/// - The setting persists for the session but resets on restart
///
/// # Arguments
/// * `enabled` - Whether to enable QHY discovery
///
/// # Example Use Cases
/// 1. Disable if QHY SDK not installed to speed up discovery
/// 2. Disable if QHY SDK crashes on this system
/// 3. Disable temporarily to troubleshoot conflicts
#[flutter_rust_bridge::frb(sync)]
pub fn api_set_qhy_discovery_enabled(enabled: bool) {
    nightshade_native::vendor::qhy::set_qhy_discovery_enabled(enabled);
}

/// Get information about QHY SDK availability and discovery status.
///
/// # Returns
/// * `QhyDiscoveryStatus` - Status information about QHY discovery
#[flutter_rust_bridge::frb(sync)]
pub fn api_get_qhy_discovery_status() -> QhyDiscoveryStatus {
    QhyDiscoveryStatus {
        sdk_available: nightshade_native::vendor::qhy::is_sdk_available(),
        discovery_enabled: nightshade_native::vendor::qhy::is_qhy_discovery_enabled(),
        timeout_ms: get_qhy_discovery_timeout_ms(),
    }
}

/// Helper to get the QHY discovery timeout from quirks
fn get_qhy_discovery_timeout_ms() -> u64 {
    use nightshade_native::quirks::{get_quirks_for_vendor, DiscoveryQuirk, Quirk};
    use nightshade_native::NativeVendor;

    let quirks = get_quirks_for_vendor(&NativeVendor::Qhy);
    for quirk in quirks {
        if let Quirk::Discovery(DiscoveryQuirk::DiscoveryTimeoutMs(timeout)) = quirk {
            return timeout;
        }
    }
    10000 // Default timeout
}

/// Status information about QHY discovery
#[derive(Debug, Clone)]
pub struct QhyDiscoveryStatus {
    /// Whether the QHY SDK DLL/SO was loaded successfully
    pub sdk_available: bool,
    /// Whether QHY discovery is currently enabled
    pub discovery_enabled: bool,
    /// The timeout for discovery operations in milliseconds
    pub timeout_ms: u64,
}

// =============================================================================
// Image Calibration
// =============================================================================

/// Calibrate an image file using dark, flat, and/or bias calibration frames.
///
/// Loads the light frame and any provided calibration frames from disk,
/// applies the calibration pipeline, and saves the result to `output_path`.
///
/// The calibration order is:
/// 1. Subtract bias from dark and flat (if bias provided)
/// 2. Subtract dark from light
/// 3. Divide light by normalized flat
///
/// Any calibration frame path can be empty/None to skip that correction.
pub fn api_calibrate_image_file(
    light_path: String,
    dark_path: Option<String>,
    flat_path: Option<String>,
    bias_path: Option<String>,
    output_path: String,
) -> Result<(), NightshadeError> {
    use nightshade_imaging::{calibration, read_image, write_fits, FitsHeader, ImageFormat};
    use std::path::Path;

    // Load light frame
    let light_result = read_image(Path::new(&light_path)).map_err(|e| {
        NightshadeError::ImageError(format!(
            "Failed to read light frame '{}': {}",
            light_path, e
        ))
    })?;

    // Load optional calibration frames
    let dark = match &dark_path {
        Some(p) if !p.is_empty() => {
            let result = read_image(Path::new(p)).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to read dark frame '{}': {}", p, e))
            })?;
            Some(result.image)
        }
        _ => None,
    };

    let flat = match &flat_path {
        Some(p) if !p.is_empty() => {
            let result = read_image(Path::new(p)).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to read flat frame '{}': {}", p, e))
            })?;
            Some(result.image)
        }
        _ => None,
    };

    let bias = match &bias_path {
        Some(p) if !p.is_empty() => {
            let result = read_image(Path::new(p)).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to read bias frame '{}': {}", p, e))
            })?;
            Some(result.image)
        }
        _ => None,
    };

    // Run calibration pipeline
    let calibrated = calibration::calibrate_frame(
        &light_result.image,
        dark.as_ref(),
        flat.as_ref(),
        bias.as_ref(),
    )
    .map_err(|e| NightshadeError::ImageError(format!("Calibration failed: {}", e)))?;

    // Save calibrated image, preserving original format
    let out = Path::new(&output_path);
    let ext = out.extension().and_then(|e| e.to_str()).unwrap_or("fits");
    let out_format = ImageFormat::from_extension(ext).unwrap_or(ImageFormat::Fits);

    match out_format {
        ImageFormat::Fits => {
            // Carry over header from original light, add calibration note
            let mut header = FitsHeader::new();
            for (key, value) in &light_result.header {
                header.set_string(key, value);
            }
            header.set_string("CALSTAT", "calibrated by Nightshade");
            if let Some(ref path) = dark_path {
                if !path.is_empty() {
                    header.set_string("DARKFILE", path);
                }
            }
            if let Some(ref path) = flat_path {
                if !path.is_empty() {
                    header.set_string("FLATFILE", path);
                }
            }
            if let Some(ref path) = bias_path {
                if !path.is_empty() {
                    header.set_string("BIASFILE", path);
                }
            }

            write_fits(out, &calibrated, &header).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to write calibrated FITS: {:?}", e))
            })?;
        }
        ImageFormat::Xisf => {
            nightshade_imaging::write_xisf(
                out,
                &calibrated,
                &nightshade_imaging::XisfMetadata::default(),
            )
            .map_err(|e| {
                NightshadeError::ImageError(format!("Failed to write calibrated XISF: {:?}", e))
            })?;
        }
        ImageFormat::Tiff => {
            nightshade_imaging::write_tiff(out, &calibrated).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to write calibrated TIFF: {}", e))
            })?;
        }
        ImageFormat::Png => {
            nightshade_imaging::write_png(out, &calibrated).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to write calibrated PNG: {}", e))
            })?;
        }
        _ => {
            // Default to FITS for unsupported output formats
            let header = FitsHeader::new();
            write_fits(out, &calibrated, &header).map_err(|e| {
                NightshadeError::ImageError(format!("Failed to write calibrated file: {:?}", e))
            })?;
        }
    }

    tracing::info!(
        "Calibrated image saved to: {} (dark={}, flat={}, bias={})",
        output_path,
        dark_path
            .as_ref()
            .map_or("none", |p| if p.is_empty() { "none" } else { p.as_str() }),
        flat_path
            .as_ref()
            .map_or("none", |p| if p.is_empty() { "none" } else { p.as_str() }),
        bias_path
            .as_ref()
            .map_or("none", |p| if p.is_empty() { "none" } else { p.as_str() }),
    );

    Ok(())
}

/// Calibrate raw pixel data in memory (u16).
///
/// Takes pixel data directly rather than file paths. Returns calibrated pixel data.
/// All frames must have the same dimensions and be single-channel u16.
#[flutter_rust_bridge::frb(sync)]
pub fn api_calibrate_image_data(
    width: u32,
    height: u32,
    light_data: Vec<u16>,
    dark_data: Option<Vec<u16>>,
    flat_data: Option<Vec<u16>>,
    bias_data: Option<Vec<u16>>,
) -> Result<Vec<u16>, NightshadeError> {
    use nightshade_imaging::{calibration, ImageData};

    let light = ImageData::from_u16(width, height, 1, &light_data);

    let dark = dark_data.map(|d| ImageData::from_u16(width, height, 1, &d));
    let flat = flat_data.map(|f| ImageData::from_u16(width, height, 1, &f));
    let bias = bias_data.map(|b| ImageData::from_u16(width, height, 1, &b));

    let calibrated =
        calibration::calibrate_frame(&light, dark.as_ref(), flat.as_ref(), bias.as_ref())
            .map_err(|e| NightshadeError::ImageError(format!("Calibration failed: {}", e)))?;

    calibrated.as_u16().ok_or_else(|| {
        NightshadeError::ImageError(
            "Failed to extract u16 pixel data from calibrated image".to_string(),
        )
    })
}

// =============================================================================
// Live Stacking API
// =============================================================================

/// Live stacking configuration exposed to Dart
pub struct ApiLiveStackingConfig {
    pub sigma_clip_enabled: bool,
    pub sigma_clip_threshold: f64,
    pub max_match_stars: u32,
    pub match_radius_px: f64,
    pub match_flux_tolerance: f64,
    pub min_matched_pairs: u32,
}

impl Default for ApiLiveStackingConfig {
    fn default() -> Self {
        Self {
            sigma_clip_enabled: true,
            sigma_clip_threshold: 2.5,
            max_match_stars: 100,
            match_radius_px: 50.0,
            match_flux_tolerance: 0.7,
            min_matched_pairs: 5,
        }
    }
}

/// Live stacking statistics returned to Dart
pub struct ApiLiveStackingStats {
    pub stacked_frame_count: u32,
    pub total_frames_attempted: u32,
    pub rejected_alignment_failures: u32,
    pub avg_matched_pairs: f64,
    pub avg_alignment_residual: f64,
    pub total_sigma_rejected_pixels: u64,
}

/// Result from adding a frame to the live stack
pub struct ApiLiveStackingResult {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u16>,
    pub stats: ApiLiveStackingStats,
}

fn convert_config(config: ApiLiveStackingConfig) -> crate::stacking_api::LiveStackingConfigApi {
    crate::stacking_api::LiveStackingConfigApi {
        sigma_clip_enabled: config.sigma_clip_enabled,
        sigma_clip_threshold: config.sigma_clip_threshold,
        max_match_stars: config.max_match_stars,
        match_radius_px: config.match_radius_px,
        match_flux_tolerance: config.match_flux_tolerance,
        min_matched_pairs: config.min_matched_pairs,
    }
}

fn convert_stats(stats: crate::stacking_api::LiveStackingStatsApi) -> ApiLiveStackingStats {
    ApiLiveStackingStats {
        stacked_frame_count: stats.stacked_frame_count,
        total_frames_attempted: stats.total_frames_attempted,
        rejected_alignment_failures: stats.rejected_alignment_failures,
        avg_matched_pairs: stats.avg_matched_pairs,
        avg_alignment_residual: stats.avg_alignment_residual,
        total_sigma_rejected_pixels: stats.total_sigma_rejected_pixels,
    }
}

fn convert_result(
    result: crate::stacking_api::LiveStackingAddFrameResult,
) -> ApiLiveStackingResult {
    ApiLiveStackingResult {
        width: result.width,
        height: result.height,
        data: result.data,
        stats: convert_stats(result.stats),
    }
}

/// Start live stacking with a reference image file.
///
/// All subsequent frames will be aligned to this reference.
pub fn api_stacking_start(
    reference_image_path: String,
    config: ApiLiveStackingConfig,
) -> Result<ApiLiveStackingStats, NightshadeError> {
    let result = crate::stacking_api::stacking_start(reference_image_path, convert_config(config))
        .map_err(|e| NightshadeError::ImageError(e))?;
    Ok(convert_stats(result))
}

/// Start live stacking from raw pixel data in memory.
pub fn api_stacking_start_from_data(
    width: u32,
    height: u32,
    data: Vec<u16>,
    config: ApiLiveStackingConfig,
) -> Result<ApiLiveStackingStats, NightshadeError> {
    let result =
        crate::stacking_api::stacking_start_from_data(width, height, data, convert_config(config))
            .map_err(|e| NightshadeError::ImageError(e))?;
    Ok(convert_stats(result))
}

/// Add a frame to the live stack from a file path.
///
/// Returns the current stacked result.
pub fn api_stacking_add_frame(
    image_path: String,
) -> Result<ApiLiveStackingResult, NightshadeError> {
    let result = crate::stacking_api::stacking_add_frame(image_path)
        .map_err(|e| NightshadeError::ImageError(e))?;
    Ok(convert_result(result))
}

/// Add a frame to the live stack from raw pixel data.
pub fn api_stacking_add_frame_from_data(
    width: u32,
    height: u32,
    data: Vec<u16>,
) -> Result<ApiLiveStackingResult, NightshadeError> {
    let result = crate::stacking_api::stacking_add_frame_from_data(width, height, data)
        .map_err(|e| NightshadeError::ImageError(e))?;
    Ok(convert_result(result))
}

/// Get the current stacked result without adding a frame.
pub fn api_stacking_get_result() -> Result<ApiLiveStackingResult, NightshadeError> {
    let result =
        crate::stacking_api::stacking_get_result().map_err(|e| NightshadeError::ImageError(e))?;
    Ok(convert_result(result))
}

/// Get the current stacking statistics.
pub fn api_stacking_get_stats() -> Result<ApiLiveStackingStats, NightshadeError> {
    let result =
        crate::stacking_api::stacking_get_stats().map_err(|e| NightshadeError::ImageError(e))?;
    Ok(convert_stats(result))
}

/// Reset the live stacker, clearing accumulated data but keeping the reference.
pub fn api_stacking_reset() -> Result<(), NightshadeError> {
    crate::stacking_api::stacking_reset().map_err(|e| NightshadeError::ImageError(e))
}

/// Stop live stacking and release all resources.
pub fn api_stacking_stop() -> Result<(), NightshadeError> {
    crate::stacking_api::stacking_stop().map_err(|e| NightshadeError::ImageError(e))
}

/// Check if live stacking is currently active.
#[flutter_rust_bridge::frb(sync)]
pub fn api_stacking_is_active() -> bool {
    crate::stacking_api::stacking_is_active()
}

/// Get the current stacked frame count.
#[flutter_rust_bridge::frb(sync)]
pub fn api_stacking_frame_count() -> u32 {
    crate::stacking_api::stacking_frame_count()
}

// =============================================================================
// Defect-Map / Bad-Pixel Cosmetic Correction API
// =============================================================================

/// Status of a stored defect map for a given camera / sensor / temperature.
pub struct ApiDefectMapStatus {
    pub camera_id: String,
    pub width: u32,
    pub height: u32,
    pub temperature_bucket_decicelsius: i16,
    pub defective_pixel_count: u32,
    pub last_rebuilt_unix_seconds: i64,
    pub apply_during_capture: bool,
    pub stored_on_disk: bool,
}

fn defect_maps_root() -> std::path::PathBuf {
    // Why: NIGHTSHADE_DATA_DIR is the standard per-platform application
    // data path set by the Flutter shell on launch (see main_headless.dart
    // and the FFI bridge startup). The temp_dir fallback exists for unit
    // tests and for headless invocations where the env var hasn't been
    // populated yet — for those callers the defect maps are session-scoped
    // and don't need to survive a reboot. Production hosts hit the env-var
    // branch first.
    let base = std::env::var_os("NIGHTSHADE_DATA_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::env::temp_dir().join("nightshade"));
    base.join("defect_maps")
}

fn sanitize_camera_id(camera_id: &str) -> String {
    camera_id
        .chars()
        .map(|c| match c {
            'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' => c,
            _ => '_',
        })
        .collect()
}

fn defect_map_path(
    camera_id: &str,
    width: u32,
    height: u32,
    bucket_decicelsius: i16,
) -> std::path::PathBuf {
    defect_maps_root().join(format!(
        "{}_{}x{}_{:+05}.ndm",
        sanitize_camera_id(camera_id),
        width,
        height,
        bucket_decicelsius
    ))
}

/// Tracks whether the user has enabled per-capture defect correction for
/// each camera_id. The bool is the toggle state; the runtime cache of the
/// map itself is loaded on demand by the capture pipeline.
static DEFECT_APPLY_FLAGS: OnceLock<Mutex<HashMap<String, bool>>> = OnceLock::new();

fn defect_apply_flags() -> &'static Mutex<HashMap<String, bool>> {
    DEFECT_APPLY_FLAGS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Build a defect map for a camera from a set of dark frames provided as
/// FITS/XISF file paths. Frames must all share dimensions and pixel type.
///
/// The resulting map is written to disk under
/// `$NIGHTSHADE_DATA_DIR/defect_maps/` keyed by camera id, sensor size and
/// temperature bucket, and the status is returned.
pub async fn api_defect_map_build(
    camera_id: String,
    dark_frame_paths: Vec<String>,
    sensor_temperature_celsius: f64,
) -> Result<ApiDefectMapStatus, NightshadeError> {
    if camera_id.trim().is_empty() {
        return Err(NightshadeError::InvalidParameter(
            "camera_id is empty".to_string(),
        ));
    }
    if dark_frame_paths.len() < nightshade_imaging::defect_map::MIN_CONSISTENCY_FRAMES {
        return Err(NightshadeError::InvalidParameter(format!(
            "defect map build requires at least {} dark frames; got {}",
            nightshade_imaging::defect_map::MIN_CONSISTENCY_FRAMES,
            dark_frame_paths.len()
        )));
    }

    let darks: Vec<ImageData> = tokio::task::spawn_blocking(move || {
        let mut frames = Vec::with_capacity(dark_frame_paths.len());
        for path in &dark_frame_paths {
            let result = nightshade_imaging::read_image(std::path::Path::new(path))
                .map_err(|e| format!("failed to read {}: {}", path, e))?;
            frames.push(result.image);
        }
        Ok::<_, String>(frames)
    })
    .await
    .map_err(|e| NightshadeError::ImageError(format!("join error reading darks: {}", e)))?
    .map_err(NightshadeError::ImageError)?;

    let bucket = nightshade_imaging::defect_map::bucket_temperature(sensor_temperature_celsius);
    let dark_refs: Vec<&ImageData> = darks.iter().collect();
    let map = nightshade_imaging::defect_map::build_defect_map(&dark_refs, bucket)
        .map_err(|e| NightshadeError::ImageError(e.to_string()))?;

    let path = defect_map_path(&camera_id, map.width, map.height, bucket);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            NightshadeError::ImageError(format!(
                "failed to create defect map directory {}: {}",
                parent.display(),
                e
            ))
        })?;
    }
    map.write_to_file(&path)
        .map_err(|e| NightshadeError::ImageError(e.to_string()))?;

    let apply_during_capture = {
        // Why: absence of a flag for this camera id is the canonical "off"
        // state — apply-during-capture is opt-in and the map is only written
        // when the user toggles it on for a specific (camera, temperature)
        // pair. No need to surface this as an error.
        let flags = defect_apply_flags().lock().await;
        flags.get(&camera_id).copied().unwrap_or(false)
    };

    Ok(ApiDefectMapStatus {
        camera_id,
        width: map.width,
        height: map.height,
        temperature_bucket_decicelsius: bucket,
        defective_pixel_count: map.defective_count(),
        last_rebuilt_unix_seconds: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0),
        apply_during_capture,
        stored_on_disk: true,
    })
}

/// Toggle whether the defect map for this camera is applied to lights
/// during capture. The map must already exist on disk for the toggle to
/// take effect at the next capture; this call only updates the user's
/// preference.
pub async fn api_defect_map_apply(
    camera_id: String,
    apply_during_capture: bool,
) -> Result<(), NightshadeError> {
    if camera_id.trim().is_empty() {
        return Err(NightshadeError::InvalidParameter(
            "camera_id is empty".to_string(),
        ));
    }
    let mut flags = defect_apply_flags().lock().await;
    flags.insert(camera_id, apply_during_capture);
    Ok(())
}

/// Delete the defect map stored on disk for the given camera, sensor
/// dimensions and temperature bucket. Also resets the apply-during-
/// capture flag for that camera.
pub async fn api_defect_map_clear(
    camera_id: String,
    width: u32,
    height: u32,
    sensor_temperature_celsius: f64,
) -> Result<(), NightshadeError> {
    if camera_id.trim().is_empty() {
        return Err(NightshadeError::InvalidParameter(
            "camera_id is empty".to_string(),
        ));
    }
    let bucket = nightshade_imaging::defect_map::bucket_temperature(sensor_temperature_celsius);
    let path = defect_map_path(&camera_id, width, height, bucket);
    if path.exists() {
        std::fs::remove_file(&path).map_err(|e| {
            NightshadeError::ImageError(format!(
                "failed to delete defect map {}: {}",
                path.display(),
                e
            ))
        })?;
    }
    let mut flags = defect_apply_flags().lock().await;
    flags.remove(&camera_id);
    Ok(())
}

/// Look up the status of the stored defect map for a camera at the given
/// sensor size and temperature. Returns `Ok(None)` if no map is stored
/// for that combination.
pub async fn api_defect_map_get_status(
    camera_id: String,
    width: u32,
    height: u32,
    sensor_temperature_celsius: f64,
) -> Result<Option<ApiDefectMapStatus>, NightshadeError> {
    if camera_id.trim().is_empty() {
        return Err(NightshadeError::InvalidParameter(
            "camera_id is empty".to_string(),
        ));
    }
    let bucket = nightshade_imaging::defect_map::bucket_temperature(sensor_temperature_celsius);
    let path = defect_map_path(&camera_id, width, height, bucket);
    if !path.exists() {
        return Ok(None);
    }
    let map = nightshade_imaging::defect_map::DefectMap::read_from_file(&path)
        .map_err(|e| NightshadeError::ImageError(e.to_string()))?;
    let metadata = std::fs::metadata(&path).map_err(|e| {
        NightshadeError::ImageError(format!(
            "failed to stat defect map {}: {}",
            path.display(),
            e
        ))
    })?;
    let last_rebuilt = metadata
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);

    let apply_during_capture = {
        // Why: absence of a flag for this camera id is the canonical "off"
        // state — apply-during-capture is opt-in and the map is only written
        // when the user toggles it on for a specific (camera, temperature)
        // pair. No need to surface this as an error.
        let flags = defect_apply_flags().lock().await;
        flags.get(&camera_id).copied().unwrap_or(false)
    };

    Ok(Some(ApiDefectMapStatus {
        camera_id,
        width: map.width,
        height: map.height,
        temperature_bucket_decicelsius: map.temperature_bucket_decicelsius,
        defective_pixel_count: map.defective_count(),
        last_rebuilt_unix_seconds: last_rebuilt,
        apply_during_capture,
        stored_on_disk: true,
    }))
}
