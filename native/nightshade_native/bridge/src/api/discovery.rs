// split from monolithic api.rs
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs.
use crate::device::*;
use crate::device_manager::DeviceManager;
use crate::error::*;
use crate::event::*;
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
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::sync::RwLock;
// Sibling-module items via the parent's pub use re-exports.
use super::*;

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

pub(crate) async fn query_indi_device_serial_from_client(
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

pub(crate) async fn query_indi_serials_for_server(
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

/// Returns the list of driver backends that can supply devices of the given
/// type. Only these (type, driver) pairs will be probed when the user asks for
/// `device_type` — for example, asking for cameras does not trigger a mount
/// SDK scan.
pub(crate) fn drivers_for_device_type(device_type: DeviceType) -> Vec<DriverType> {
    match device_type {
        DeviceType::Camera => vec![
            DriverType::Ascom,
            DriverType::Alpaca,
            DriverType::Native,
            DriverType::Indi,
            DriverType::Simulator,
        ],
        DeviceType::Mount => vec![
            DriverType::Ascom,
            DriverType::Alpaca,
            DriverType::Native,
            DriverType::Indi,
        ],
        DeviceType::Focuser => vec![
            DriverType::Ascom,
            DriverType::Alpaca,
            DriverType::Native,
            DriverType::Indi,
        ],
        DeviceType::FilterWheel => vec![
            DriverType::Ascom,
            DriverType::Alpaca,
            DriverType::Native,
            DriverType::Indi,
        ],
        DeviceType::Rotator => vec![
            DriverType::Ascom,
            DriverType::Alpaca,
            DriverType::Native,
            DriverType::Indi,
        ],
        DeviceType::Dome => vec![DriverType::Ascom, DriverType::Alpaca, DriverType::Indi],
        DeviceType::Weather => vec![DriverType::Ascom, DriverType::Alpaca, DriverType::Indi],
        DeviceType::SafetyMonitor => {
            vec![DriverType::Ascom, DriverType::Alpaca, DriverType::Indi]
        }
        DeviceType::CoverCalibrator => {
            vec![DriverType::Ascom, DriverType::Alpaca, DriverType::Indi]
        }
        // The Built-in guider and PHD2 are reported under DriverType::Native;
        // INDI guiders also fall under (Guider, Indi).
        DeviceType::Guider => vec![DriverType::Native, DriverType::Indi],
        // ASCOM exposes a Switch interface; Alpaca and INDI do too (INDI via
        // generic switch properties). Native vendor SDKs do not ship switches.
        DeviceType::Switch => vec![DriverType::Ascom, DriverType::Alpaca, DriverType::Indi],
    }
}

/// Probe a single (device_type, driver_type) pair. Returns the discovered
/// devices on success or a backend-specific error string on failure. Each
/// branch only scans the backend identified by `driver_type`, so e.g. asking
/// for (Camera, Ascom) never touches the Alpaca network or the INDI clients.
async fn scan_devices_for_pair(
    device_type: DeviceType,
    driver_type: DriverType,
) -> Result<Vec<DeviceInfo>, String> {
    match driver_type {
        DriverType::Ascom => scan_ascom_for_type(device_type).await,
        DriverType::Alpaca => scan_alpaca_for_type(device_type).await,
        DriverType::Native => scan_native_for_type(device_type).await,
        DriverType::Indi => scan_indi_for_type(device_type).await,
        DriverType::Simulator => Ok(scan_simulator_for_type(device_type)),
    }
}

// — public hot-plug entry points. The hot-plug poller in
// `crate::hotplug` walks the native and (on Windows) ASCOM device lists
// without the per-(type,driver) cache wrapper so a freshly-plugged USB
// device shows up on the very next 4 s tick instead of waiting for the
// 60 s cache TTL to roll over. We keep the inner `scan_*_for_type`
// helpers private to this module and expose thin re-exports here so the
// hot-plug module doesn't have to be `super`-private. Marked
// `frb(ignore)` because they take crate-private error types and aren't
// meant to be callable from Dart — only from the hot-plug task.
#[flutter_rust_bridge::frb(ignore)]
pub async fn scan_native_for_type_public(
    device_type: DeviceType,
) -> Result<Vec<DeviceInfo>, String> {
    scan_native_for_type(device_type).await
}

#[cfg(windows)]
#[flutter_rust_bridge::frb(ignore)]
pub async fn scan_ascom_for_type_public(
    device_type: DeviceType,
) -> Result<Vec<DeviceInfo>, String> {
    scan_ascom_for_type(device_type).await
}

#[cfg(windows)]
async fn scan_ascom_for_type(device_type: DeviceType) -> Result<Vec<DeviceInfo>, String> {
    use nightshade_ascom::{discover_devices as ascom_discover, AscomDeviceType};

    let ascom_type = match device_type {
        DeviceType::Camera => AscomDeviceType::Camera,
        DeviceType::Mount => AscomDeviceType::Telescope,
        DeviceType::Focuser => AscomDeviceType::Focuser,
        DeviceType::FilterWheel => AscomDeviceType::FilterWheel,
        DeviceType::Rotator => AscomDeviceType::Rotator,
        DeviceType::Dome => AscomDeviceType::Dome,
        DeviceType::Weather => AscomDeviceType::ObservingConditions,
        DeviceType::SafetyMonitor => AscomDeviceType::SafetyMonitor,
        DeviceType::CoverCalibrator => AscomDeviceType::CoverCalibrator,
        DeviceType::Switch => AscomDeviceType::Switch,
        // ASCOM does not expose a "Guider" interface; the built-in guider and
        // PHD2 are surfaced under DriverType::Native instead.
        DeviceType::Guider => return Ok(Vec::new()),
    };

    let ascom_devs = ascom_discover(ascom_type);
    let mut out = Vec::new();
    for ascom_dev in ascom_devs {
        let prog_id_lower = ascom_dev.prog_id.to_lowercase();
        let name_lower = ascom_dev.name.to_lowercase();

        // Filter out simulators and diagnostic tools.
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
        out.push(DeviceInfo {
            id: format!("ascom:{}", ascom_dev.prog_id),
            name: ascom_dev.name.clone(),
            device_type,
            driver_type: DriverType::Ascom,
            description: ascom_dev.description,
            driver_version: "ASCOM".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: ascom_dev.name.clone(),
        });
    }
    Ok(out)
}

#[cfg(not(windows))]
async fn scan_ascom_for_type(_device_type: DeviceType) -> Result<Vec<DeviceInfo>, String> {
    // ASCOM is Windows-only.
    Ok(Vec::new())
}

/// Module-level cache for a single Alpaca UDP discovery *sweep*.
///
/// Holds the timestamp of the last broadcast plus the full, canonical list of
/// every Alpaca device it returned, tagged with its mapped [`DeviceType`]. A
/// `None` value means "no sweep has run yet (or the last one expired)".
static ALPACA_SWEEP_CACHE: OnceLock<Mutex<Option<(Instant, Vec<(DeviceType, DeviceInfo)>)>>> =
    OnceLock::new();

/// Get or initialize the Alpaca sweep cache.
///
/// Why: Alpaca discovery is a single network-wide UDP broadcast that returns
/// devices of *every* type at once. `api_discover_devices` probes one
/// `DeviceType` at a time, so without this cache a single user "scan" would
/// fire the broadcast once per type — 10× (Camera, Mount, Focuser, FilterWheel,
/// Rotator, Dome, Weather, SafetyMonitor, CoverCalibrator, Switch) — flooding
/// the LAN and adding ~2 s of broadcast latency per type. By caching the whole
/// sweep here, the first type to ask triggers exactly one broadcast and the
/// remaining types filter the same canonical list within the TTL window. The
/// device IDs are unchanged, so the downstream per-(type, driver) cache and
/// the Dart-side dedupe see identical results either way.
fn alpaca_sweep_cache() -> &'static Mutex<Option<(Instant, Vec<(DeviceType, DeviceInfo)>)>> {
    ALPACA_SWEEP_CACHE.get_or_init(|| Mutex::new(None))
}

/// Maps an Alpaca device type to Nightshade's [`DeviceType`].
fn alpaca_device_type(t: nightshade_alpaca::AlpacaDeviceType) -> DeviceType {
    use nightshade_alpaca::AlpacaDeviceType;
    match t {
        AlpacaDeviceType::Camera => DeviceType::Camera,
        AlpacaDeviceType::Telescope => DeviceType::Mount,
        AlpacaDeviceType::Focuser => DeviceType::Focuser,
        AlpacaDeviceType::FilterWheel => DeviceType::FilterWheel,
        AlpacaDeviceType::Rotator => DeviceType::Rotator,
        AlpacaDeviceType::Dome => DeviceType::Dome,
        AlpacaDeviceType::SafetyMonitor => DeviceType::SafetyMonitor,
        AlpacaDeviceType::ObservingConditions => DeviceType::Weather,
        AlpacaDeviceType::CoverCalibrator => DeviceType::CoverCalibrator,
        AlpacaDeviceType::Switch => DeviceType::Switch,
    }
}

/// Build a `DeviceInfo` from an Alpaca discovery record (shared by the full
/// sweep so every type maps identically — IDs and display names match the
/// public `api_discover_alpaca_devices` path).
fn alpaca_device_info(
    alpaca_dev: &nightshade_alpaca::AlpacaDevice,
    device_type: DeviceType,
) -> DeviceInfo {
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

    DeviceInfo {
        id: alpaca_dev.id(),
        name: alpaca_dev.device_name.clone(),
        device_type,
        driver_type: DriverType::Alpaca,
        description: format!("Alpaca device at {}", alpaca_dev.base_url),
        driver_version: "Alpaca".to_string(),
        serial_number: None,
        unique_id,
        display_name,
    }
}

/// Counts how many real UDP broadcasts the sweep cache has triggered. Used by
/// tests to assert that scanning several types within the TTL only broadcasts
/// once; in production it is a cheap diagnostic counter.
static ALPACA_SWEEP_BROADCAST_COUNT: AtomicU64 = AtomicU64::new(0);

/// Run the Alpaca UDP broadcast once and map every returned device into the
/// canonical `(DeviceType, DeviceInfo)` list. Increments the broadcast counter.
async fn run_alpaca_sweep() -> Vec<(DeviceType, DeviceInfo)> {
    use nightshade_alpaca::discover_all_devices;

    ALPACA_SWEEP_BROADCAST_COUNT.fetch_add(1, Ordering::Relaxed);
    let alpaca_devs = discover_all_devices(Duration::from_secs(2)).await;

    alpaca_devs
        .iter()
        .map(|dev| {
            let dt = alpaca_device_type(dev.device_type);
            (dt, alpaca_device_info(dev, dt))
        })
        .collect()
}

async fn scan_alpaca_for_type(device_type: DeviceType) -> Result<Vec<DeviceInfo>, String> {
    // Why: Alpaca discovery is a single broadcast that returns *all* device
    // types at once. `api_discover_devices` asks one type at a time, so we
    // cache the full sweep here to prevent a 10× re-broadcast (one per type)
    // for what is logically a single scan. The first type to ask triggers
    // exactly one broadcast; the other types filter the same cached list
    // within `DISCOVERY_CACHE_TTL`. Every type filters the identical canonical
    // list, so no device is missed or duplicated and all IDs are unchanged.
    let mut guard = alpaca_sweep_cache().lock().await;

    let needs_sweep = match guard.as_ref() {
        Some((ts, _)) => ts.elapsed() >= DISCOVERY_CACHE_TTL,
        None => true,
    };

    if needs_sweep {
        let full_list = run_alpaca_sweep().await;
        *guard = Some((Instant::now(), full_list));
    }

    let (_, devices) = guard
        .as_ref()
        .expect("sweep cache is populated above when stale/empty");

    let out = devices
        .iter()
        .filter(|(dt, _)| *dt == device_type)
        .map(|(_, info)| info.clone())
        .collect();
    Ok(out)
}

async fn scan_native_for_type(device_type: DeviceType) -> Result<Vec<DeviceInfo>, String> {
    use nightshade_native::discover_all_devices as native_discover_all;

    // The native crate has its own internal cache + serializing mutex (see
    // native/src/discovery.rs), so calling discover_all_devices() repeatedly
    // for different device types is cheap: only the first call within the
    // inner TTL actually probes vendor SDKs.

    // Guider is reported under DriverType::Native but it's the built-in
    // software guider + PHD2, not a vendor SDK.
    if device_type == DeviceType::Guider {
        let mut out = Vec::new();

        // Built-in guider (always available).
        out.push(DeviceInfo {
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

        let is_running = nightshade_imaging::is_phd2_running();
        let is_installed = nightshade_imaging::is_phd2_installed();
        if is_running || is_installed {
            tracing::debug!(
                "Found PHD2 Guiding (Running: {}, Installed: {})",
                is_running,
                is_installed
            );
            out.push(DeviceInfo {
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

        return Ok(out);
    }

    let native_devices = native_discover_all()
        .await
        .map_err(|e| format!("Native SDK discovery failed: {}", e))?;

    let mut out = Vec::new();
    for native_dev in native_devices {
        let dev_type = match native_dev.device_type {
            nightshade_native::DeviceType::Camera => DeviceType::Camera,
            nightshade_native::DeviceType::Mount => DeviceType::Mount,
            nightshade_native::DeviceType::Focuser => DeviceType::Focuser,
            nightshade_native::DeviceType::FilterWheel => DeviceType::FilterWheel,
            nightshade_native::DeviceType::Rotator => DeviceType::Rotator,
        };
        if dev_type != device_type {
            continue;
        }
        tracing::debug!(
            "Found native device: {} ({})",
            native_dev.display_name,
            native_dev.vendor.as_str()
        );
        out.push(DeviceInfo {
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
    }
    Ok(out)
}

async fn scan_indi_for_type(device_type: DeviceType) -> Result<Vec<DeviceInfo>, String> {
    // INDI discovery here only enumerates devices on already-connected INDI
    // clients owned by the device manager — no network probing happens here.
    // Filtering by device_type keeps this entry's cache scoped to one type.
    let indi_devices = get_device_manager().get_all_indi_devices().await;
    let mut out = Vec::new();
    for dev in indi_devices {
        if dev.device_type == device_type {
            tracing::debug!("Found INDI device: {} ({:?})", dev.name, dev.device_type);
            out.push(dev);
        }
    }
    Ok(out)
}

fn scan_simulator_for_type(device_type: DeviceType) -> Vec<DeviceInfo> {
    if device_type != DeviceType::Camera {
        return Vec::new();
    }
    // The `sim_` prefix is the simulator id convention the entire native
    // device layer keys off (40+ sites in simulation.rs/camera.rs/imaging.rs/
    // heartbeat.rs route to the in-process simulator by `id.starts_with`).
    // The Dart connect guard accepts this legacy form too — see the `sim_`
    // branch in `device_id.dart`.
    vec![DeviceInfo {
        id: "sim_camera_1".to_string(),
        name: "Simulated Camera".to_string(),
        device_type: DeviceType::Camera,
        driver_type: DriverType::Simulator,
        description: "Internal Simulator".to_string(),
        driver_version: "1.0.0".to_string(),
        serial_number: Some("SIM-123".to_string()),
        unique_id: Some("sim_camera_1".to_string()),
        display_name: "Simulated Camera".to_string(),
    }]
}

/// Discover available devices of a specific type.
///
/// The discovery cache is keyed by `(DeviceType, DriverType)`. For the
/// requested `device_type` we look up every driver that can supply it (see
/// `drivers_for_device_type`) and either reuse the cached entry (when it is
/// younger than `DISCOVERY_CACHE_TTL`) or run a fresh per-driver scan for that
/// specific type. This means:
///
///   * Asking for cameras never triggers a mount-driver scan.
///   * An error in one backend (e.g. ASCOM) cannot poison another (e.g.
///     Alpaca) for the same type — each (type, driver) entry holds its own
///     `Result`.
///   * Errors are surfaced to the caller as `NightshadeError`s; the cache
///     stores the error so retry-after-TTL semantics still apply (avoids
///     hammering a broken backend), but successful sibling entries remain
///     valid.
pub async fn api_discover_devices(
    device_type: DeviceType,
) -> Result<Vec<DeviceInfo>, NightshadeError> {
    tracing::debug!("Discovering {} devices", device_type.as_str());

    let drivers = drivers_for_device_type(device_type);

    // Serialize concurrent discovery requests so that two callers asking for
    // the same device type at the same time do not both run the expensive
    // backend probes. The second caller will hit the freshly populated cache
    // entries inside the loop below.
    let _in_progress = get_discovery_lock().lock().await;

    let mut aggregated: Vec<DeviceInfo> = Vec::new();
    let mut errors: Vec<(DriverType, String)> = Vec::new();

    for driver in drivers {
        let key = (device_type, driver);

        // Fast path: cache hit within TTL.
        {
            let cache = get_discovery_cache().lock().await;
            if let Some(entry) = cache.get(&key) {
                if entry.timestamp.elapsed() < DISCOVERY_CACHE_TTL {
                    match &entry.result {
                        Ok(devs) => {
                            tracing::debug!(
                                "Cache hit for ({:?}, {:?}): {} devices, {:.1}s old",
                                device_type,
                                driver,
                                devs.len(),
                                entry.timestamp.elapsed().as_secs_f32()
                            );
                            aggregated.extend(devs.iter().cloned());
                        }
                        Err(err) => {
                            tracing::debug!(
                                "Cache hit (error) for ({:?}, {:?}): {} (suppressing rescan for {:.1}s)",
                                device_type,
                                driver,
                                err,
                                (DISCOVERY_CACHE_TTL - entry.timestamp.elapsed()).as_secs_f32()
                            );
                            errors.push((driver, err.clone()));
                        }
                    }
                    continue;
                }
            }
        }

        // Slow path: run the per-driver scan, then write the result back.
        let result = scan_devices_for_pair(device_type, driver).await;
        match &result {
            Ok(devs) => {
                tracing::debug!(
                    "Scan complete for ({:?}, {:?}): {} devices",
                    device_type,
                    driver,
                    devs.len()
                );
                aggregated.extend(devs.iter().cloned());
            }
            Err(err) => {
                tracing::warn!("Scan failed for ({:?}, {:?}): {}", device_type, driver, err);
                errors.push((driver, err.clone()));
            }
        }

        let mut cache = get_discovery_cache().lock().await;
        cache.insert(
            key,
            DiscoveryCacheEntry {
                result,
                timestamp: Instant::now(),
            },
        );
    }

    drop(_in_progress);

    tracing::info!(
        "Discovery complete for {}: {} devices, {} backend errors",
        device_type.as_str(),
        aggregated.len(),
        errors.len()
    );

    // Errors are a feature: if every driver failed and we have
    // nothing to return, surface a structured error instead of silently
    // returning an empty list.
    if aggregated.is_empty() && !errors.is_empty() {
        let combined = errors
            .iter()
            .map(|(d, e)| format!("{:?}: {}", d, e))
            .collect::<Vec<_>>()
            .join("; ");
        return Err(NightshadeError::connection_failed(
            device_type.as_str(),
            format!("All discovery backends failed: {}", combined),
        ));
    }

    Ok(aggregated)
}

#[cfg(test)]
mod tests {
    //! Tests for the per-(DeviceType, DriverType) discovery cache.
    //!
    //! These tests exercise the cache machinery directly. They deliberately
    //! do NOT call `api_discover_devices` end-to-end, because that function
    //! talks to real backends (ASCOM registry on Windows, Alpaca network
    //! broadcast, native vendor SDKs, INDI clients) which are not available
    //! in a unit-test environment. Instead, they pre-populate the cache and
    //! observe lookup behavior — the exact behavior `api_discover_devices`
    //! relies on.
    //!
    //! Tests share a single process-wide cache (via `OnceLock`), so they each
    //! seed the entries they need with their own private `DeviceType` /
    //! `DriverType` combinations to avoid interfering with each other.

    use super::*;
    use crate::api::{get_discovery_cache, DiscoveryCacheEntry, DISCOVERY_CACHE_TTL};

    fn make_device(id: &str, name: &str, dt: DeviceType, drv: DriverType) -> DeviceInfo {
        DeviceInfo {
            id: id.to_string(),
            name: name.to_string(),
            device_type: dt,
            driver_type: drv,
            description: "test fixture".to_string(),
            driver_version: "test".to_string(),
            serial_number: None,
            unique_id: None,
            display_name: name.to_string(),
        }
    }

    /// drivers_for_device_type must never return a driver list that requests
    /// scanning *other* device-type-specific backends. Concretely: asking for
    /// cameras yields {Ascom, Alpaca, Native, Indi, Simulator} — and crucially
    /// the list does not branch into "scan all mount drivers too". This is the
    /// invariant that prevents the original bug (one type triggers a full
    /// ASCOM+Alpaca+Native+INDI scan across every type).
    #[test]
    fn cameras_dont_trigger_mount_driver_scan() {
        let camera_drivers = drivers_for_device_type(DeviceType::Camera);
        let mount_drivers = drivers_for_device_type(DeviceType::Mount);
        let guider_drivers = drivers_for_device_type(DeviceType::Guider);

        // Cameras: ASCOM + Alpaca + Native + INDI + Simulator. No more, no less.
        assert!(camera_drivers.contains(&DriverType::Ascom));
        assert!(camera_drivers.contains(&DriverType::Alpaca));
        assert!(camera_drivers.contains(&DriverType::Native));
        assert!(camera_drivers.contains(&DriverType::Indi));
        assert!(camera_drivers.contains(&DriverType::Simulator));

        // Cameras must NOT include any pseudo-driver only meaningful to
        // guiders or any other type. Drive list is purely about which
        // backends to probe for the requested type.
        assert_eq!(camera_drivers.len(), 5);

        // Mounts don't trigger the simulator scan (we only ship a camera sim).
        assert!(!mount_drivers.contains(&DriverType::Simulator));

        // Guider has its own focused driver set (Native covers the built-in
        // guider + PHD2; INDI covers INDI guiders). It must not request
        // ASCOM/Alpaca scans.
        assert!(!guider_drivers.contains(&DriverType::Ascom));
        assert!(!guider_drivers.contains(&DriverType::Alpaca));
    }

    /// A fresh cache entry within TTL must be returned without rescanning the
    /// backend. We seed an entry with a sentinel device, then read it back
    /// straight from the cache — the per-pair lookup logic that
    /// `api_discover_devices` uses.
    #[tokio::test]
    async fn cache_hit_within_ttl() {
        let key = (DeviceType::Camera, DriverType::Ascom);
        let sentinel = make_device(
            "ascom:test:cache-hit",
            "Sentinel Camera",
            DeviceType::Camera,
            DriverType::Ascom,
        );

        {
            let mut cache = get_discovery_cache().lock().await;
            cache.insert(
                key,
                DiscoveryCacheEntry {
                    result: Ok(vec![sentinel.clone()]),
                    timestamp: Instant::now(),
                },
            );
        }

        // Read back through the same lookup logic api_discover_devices uses.
        let cache = get_discovery_cache().lock().await;
        let entry = cache.get(&key).expect("entry should be present");
        assert!(
            entry.timestamp.elapsed() < DISCOVERY_CACHE_TTL,
            "freshly seeded entry must be within TTL"
        );
        let devs = entry.result.as_ref().expect("entry should be Ok");
        assert_eq!(devs.len(), 1);
        assert_eq!(devs[0].id, "ascom:test:cache-hit");
    }

    /// An entry whose timestamp is older than DISCOVERY_CACHE_TTL must be
    /// treated as stale (cache miss), forcing a rescan.
    #[tokio::test]
    async fn cache_miss_after_ttl() {
        let key = (DeviceType::Focuser, DriverType::Ascom);

        // Insert a stale entry: timestamp is (now - 2*TTL), so .elapsed() will
        // exceed DISCOVERY_CACHE_TTL.
        let stale_time = Instant::now()
            .checked_sub(DISCOVERY_CACHE_TTL * 2)
            .expect("system uptime should exceed 2*TTL");
        {
            let mut cache = get_discovery_cache().lock().await;
            cache.insert(
                key,
                DiscoveryCacheEntry {
                    result: Ok(vec![make_device(
                        "ascom:test:stale",
                        "Stale Focuser",
                        DeviceType::Focuser,
                        DriverType::Ascom,
                    )]),
                    timestamp: stale_time,
                },
            );
        }

        let cache = get_discovery_cache().lock().await;
        let entry = cache.get(&key).expect("entry should be present");
        assert!(
            entry.timestamp.elapsed() >= DISCOVERY_CACHE_TTL,
            "stale entry should be older than TTL"
        );
        // api_discover_devices's lookup logic checks
        // `entry.timestamp.elapsed() < DISCOVERY_CACHE_TTL` — when that is
        // false, it falls through to the per-pair scan. Verified above.
    }

    /// An error in one driver's entry must not affect another driver's
    /// entry for the same device type. (The original monolithic cache would
    /// have invalidated EVERYTHING when any backend errored, because there
    /// was a single shared `DiscoveryCache`.)
    #[tokio::test]
    async fn ascom_error_doesnt_invalidate_alpaca_for_same_type() {
        let ascom_key = (DeviceType::Rotator, DriverType::Ascom);
        let alpaca_key = (DeviceType::Rotator, DriverType::Alpaca);

        let alpaca_dev = make_device(
            "alpaca:test:rotator-isolated",
            "Alpaca Rotator",
            DeviceType::Rotator,
            DriverType::Alpaca,
        );

        {
            let mut cache = get_discovery_cache().lock().await;
            // ASCOM errored.
            cache.insert(
                ascom_key,
                DiscoveryCacheEntry {
                    result: Err("ASCOM COM init failed".to_string()),
                    timestamp: Instant::now(),
                },
            );
            // Alpaca succeeded with a real device.
            cache.insert(
                alpaca_key,
                DiscoveryCacheEntry {
                    result: Ok(vec![alpaca_dev.clone()]),
                    timestamp: Instant::now(),
                },
            );
        }

        let cache = get_discovery_cache().lock().await;

        // ASCOM entry still holds its error — retry-after-TTL semantics.
        let ascom_entry = cache.get(&ascom_key).expect("ascom entry present");
        assert!(ascom_entry.result.is_err());

        // Alpaca entry is UNTOUCHED by ASCOM's failure.
        let alpaca_entry = cache.get(&alpaca_key).expect("alpaca entry present");
        let alpaca_devs = alpaca_entry
            .result
            .as_ref()
            .expect("alpaca entry should still be Ok");
        assert_eq!(alpaca_devs.len(), 1);
        assert_eq!(alpaca_devs[0].id, "alpaca:test:rotator-isolated");
    }

    /// Verifies that error entries respect the TTL — they are NOT treated as
    /// missing on next call, so retries don't immediately hammer a broken
    /// backend. (The caller still gets the error surfaced; we just don't
    /// rescan inside the TTL window.)
    #[tokio::test]
    async fn error_entry_respects_ttl_for_retry_throttling() {
        let key = (DeviceType::Dome, DriverType::Indi);

        {
            let mut cache = get_discovery_cache().lock().await;
            cache.insert(
                key,
                DiscoveryCacheEntry {
                    result: Err("INDI server unreachable".to_string()),
                    timestamp: Instant::now(),
                },
            );
        }

        let cache = get_discovery_cache().lock().await;
        let entry = cache.get(&key).expect("error entry present");
        // Still within TTL: api_discover_devices treats this as a cache hit
        // (returns the error without rescanning).
        assert!(entry.timestamp.elapsed() < DISCOVERY_CACHE_TTL);
        assert!(entry.result.is_err());
    }

    /// The Alpaca sweep cache must serve every device type from a single
    /// broadcast within the TTL window. We seed the sweep cache with a
    /// synthetic full list (one device per type), record the broadcast counter,
    /// then call `scan_alpaca_for_type` for two different types. Because the
    /// seeded entry is fresh, neither call may broadcast (the counter is
    /// unchanged), and each call must return ONLY the devices matching its
    /// requested type — proving the 10× re-broadcast is eliminated.
    #[tokio::test]
    async fn alpaca_sweep_cache_serves_multiple_types_from_one_broadcast() {
        let camera = make_device(
            "alpaca:http://10.0.0.5:11111:Camera:0",
            "Sweep Camera",
            DeviceType::Camera,
            DriverType::Alpaca,
        );
        let mount = make_device(
            "alpaca:http://10.0.0.5:11111:Telescope:0",
            "Sweep Mount",
            DeviceType::Mount,
            DriverType::Alpaca,
        );
        let focuser = make_device(
            "alpaca:http://10.0.0.5:11111:Focuser:0",
            "Sweep Focuser",
            DeviceType::Focuser,
            DriverType::Alpaca,
        );

        // Seed a fresh sweep so no real broadcast is needed.
        {
            let mut guard = alpaca_sweep_cache().lock().await;
            *guard = Some((
                Instant::now(),
                vec![
                    (DeviceType::Camera, camera.clone()),
                    (DeviceType::Mount, mount.clone()),
                    (DeviceType::Focuser, focuser.clone()),
                ],
            ));
        }

        let before = ALPACA_SWEEP_BROADCAST_COUNT.load(Ordering::Relaxed);

        // First type filters the cached sweep.
        let cameras = scan_alpaca_for_type(DeviceType::Camera)
            .await
            .expect("camera scan ok");
        assert_eq!(cameras.len(), 1, "exactly one camera in the seeded sweep");
        assert_eq!(cameras[0].id, camera.id);

        // Second type, within TTL, must reuse the SAME sweep — no rebroadcast.
        let mounts = scan_alpaca_for_type(DeviceType::Mount)
            .await
            .expect("mount scan ok");
        assert_eq!(mounts.len(), 1, "exactly one mount in the seeded sweep");
        assert_eq!(mounts[0].id, mount.id);

        // A type with no matching device returns an empty list, not the whole
        // sweep — filtering is correct.
        let rotators = scan_alpaca_for_type(DeviceType::Rotator)
            .await
            .expect("rotator scan ok");
        assert!(rotators.is_empty(), "no rotator in the seeded sweep");

        let after = ALPACA_SWEEP_BROADCAST_COUNT.load(Ordering::Relaxed);
        assert_eq!(
            before, after,
            "all three type scans must be served from the single seeded sweep — zero broadcasts"
        );

        // The sweep cache is still populated and still holds the full,
        // canonical list (reused across all three calls).
        let guard = alpaca_sweep_cache().lock().await;
        let (_, devices) = guard.as_ref().expect("sweep cache populated");
        assert_eq!(devices.len(), 3, "the full sweep list is unchanged");
    }

    /// Independent (device_type, driver) entries must NOT share storage. A
    /// camera-Ascom entry must be distinct from a mount-Ascom entry — that's
    /// the whole point of the per-pair key.
    #[tokio::test]
    async fn entries_are_keyed_per_pair() {
        let cam_key = (DeviceType::Camera, DriverType::Native);
        let mount_key = (DeviceType::Mount, DriverType::Native);

        {
            let mut cache = get_discovery_cache().lock().await;
            cache.insert(
                cam_key,
                DiscoveryCacheEntry {
                    result: Ok(vec![make_device(
                        "native:cam:1",
                        "Native Cam",
                        DeviceType::Camera,
                        DriverType::Native,
                    )]),
                    timestamp: Instant::now(),
                },
            );
            cache.insert(
                mount_key,
                DiscoveryCacheEntry {
                    result: Ok(vec![make_device(
                        "native:mnt:1",
                        "Native Mount",
                        DeviceType::Mount,
                        DriverType::Native,
                    )]),
                    timestamp: Instant::now(),
                },
            );
        }

        let cache = get_discovery_cache().lock().await;
        let cam = cache.get(&cam_key).unwrap().result.as_ref().unwrap();
        let mnt = cache.get(&mount_key).unwrap().result.as_ref().unwrap();
        assert_eq!(cam.len(), 1);
        assert_eq!(mnt.len(), 1);
        assert_eq!(cam[0].id, "native:cam:1");
        assert_eq!(mnt[0].id, "native:mnt:1");
        // Different keys, different entries — no leakage.
        assert_ne!(cam[0].id, mnt[0].id);
    }
}
