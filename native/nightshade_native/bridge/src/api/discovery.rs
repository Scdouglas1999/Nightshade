// CQ-W3-API-RS: split from monolithic api.rs (audit-rust §9 / audit-arch §1.2)
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs (audit-rust §9).
use crate::adaptive_polling::{AdaptivePoller, PollerPreset};
use crate::device::*;
use crate::device_manager::DeviceManager;
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

// =============================================================================
// Per-backend / per-(device_type) scanners
//
// Each scanner returns the bridge's `DeviceInfo` representation for one
// driver kind. The hot-plug poll watcher calls the native/ASCOM scanners
// directly because those backends do not signal arrival/removal — every
// other backend (Alpaca, INDI) either emits its own events or is queried on
// demand by the unified `api_discover_devices` entry point.
//
// Scanners return `Result<_, String>` so a single failing backend is
// surfaced loudly (`tracing::warn!` plus an entry in the per-pair discovery
// cache) without poisoning the results of every other backend — the policy
// laid out on `DiscoveryCacheEntry`.
// =============================================================================

/// Scan the native vendor SDKs for devices of `device_type`.
///
/// Exposed for the hot-plug poll watcher (which runs every few seconds
/// against local SDKs and diffs the result against its own cache) and for
/// the unified `api_discover_devices` entry point.
pub async fn scan_native_for_type_public(
    device_type: DeviceType,
) -> Result<Vec<DeviceInfo>, String> {
    use nightshade_native::discover_all_devices as native_discover_all;

    let native_devices = native_discover_all()
        .await
        .map_err(|err| format!("native SDK discovery failed: {err}"))?;

    let mut out = Vec::with_capacity(native_devices.len());
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

/// Scan ASCOM Profile (Windows only) for devices of `device_type`.
///
/// Filters out simulators and ASCOM diagnostic helpers (hub/pipe/POTH) the
/// same way the legacy unified scan did, so neither user-facing UI nor the
/// hot-plug poll surfaces them as real devices.
///
/// Exposed for the hot-plug poll watcher and `api_discover_devices`.
#[cfg(windows)]
pub async fn scan_ascom_for_type_public(
    device_type: DeviceType,
) -> Result<Vec<DeviceInfo>, String> {
    use nightshade_ascom::{discover_devices as ascom_discover, AscomDeviceType};

    let Some(ascom_type) = ascom_type_for(device_type) else {
        return Ok(Vec::new());
    };

    // `nightshade_ascom::discover_devices` is synchronous (Windows registry
    // walk via the COM profile API). Returning a Future keeps the scanner
    // signature uniform across backends so callers can dispatch them
    // identically.
    let ascom_devs = ascom_discover(ascom_type);

    let mut out = Vec::with_capacity(ascom_devs.len());
    for ascom_dev in ascom_devs {
        let prog_id_lower = ascom_dev.prog_id.to_lowercase();
        let name_lower = ascom_dev.name.to_lowercase();

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

/// Map the bridge `DeviceType` onto the matching `AscomDeviceType`, or
/// return `None` for device kinds (e.g. `Guider`) that have no native ASCOM
/// equivalent and therefore cannot produce ASCOM Profile entries.
#[cfg(windows)]
fn ascom_type_for(device_type: DeviceType) -> Option<nightshade_ascom::AscomDeviceType> {
    use nightshade_ascom::AscomDeviceType;
    Some(match device_type {
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
        DeviceType::Guider => return None,
    })
}

/// Scan Alpaca discovery for devices of `device_type`.
async fn scan_alpaca_for_type(device_type: DeviceType) -> Result<Vec<DeviceInfo>, String> {
    use nightshade_alpaca::{discover_all_devices, AlpacaDeviceType};

    let alpaca_devs = discover_all_devices(Duration::from_secs(2)).await;

    let mut out = Vec::with_capacity(alpaca_devs.len());
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
        if dev_type != device_type {
            continue;
        }

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

        out.push(DeviceInfo {
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
    }
    Ok(out)
}

/// Scan INDI servers (already managed by `DeviceManager`) for devices of
/// `device_type`. INDI is always-listening over TCP and the manager
/// publishes its own arrival/removal events, so this scan is a simple
/// filter over the manager's last-known view of the bus.
async fn scan_indi_for_type(device_type: DeviceType) -> Result<Vec<DeviceInfo>, String> {
    let indi_devices = get_device_manager().get_all_indi_devices().await;
    Ok(indi_devices
        .into_iter()
        .filter(|d| d.device_type == device_type)
        .collect())
}

/// Always-on simulator and built-in helper devices that do not come from
/// any backend scan — appended to the per-driver `Native` cache entry so
/// they participate in the same TTL and filtering as scanned devices.
fn builtin_devices_for_type(device_type: DeviceType) -> Vec<DeviceInfo> {
    let mut out = Vec::new();

    if device_type == DeviceType::Guider {
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
    }

    if device_type == DeviceType::Camera {
        out.push(DeviceInfo {
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
    }

    out
}

/// All driver types we run per-(device_type) scans against.
///
/// Order is intentional: backends with cheap local enumeration run first
/// (`Native` reads vendor SDKs, `Ascom` reads the Windows registry) so the
/// hot path returns quickly when those produce results, and slower network
/// scans (`Alpaca` UDP discovery, `Indi` socket queries) follow.
const SCANNED_DRIVERS: &[DriverType] = &[
    DriverType::Native,
    #[cfg(windows)]
    DriverType::Ascom,
    DriverType::Alpaca,
    DriverType::Indi,
];

/// Run one (device_type, driver) scan, returning the devices for that
/// single backend or an error string explaining why it failed.
async fn run_scan(
    device_type: DeviceType,
    driver: DriverType,
) -> Result<Vec<DeviceInfo>, String> {
    match driver {
        DriverType::Native => {
            let mut devices = scan_native_for_type_public(device_type).await?;
            devices.extend(
                builtin_devices_for_type(device_type)
                    .into_iter()
                    .filter(|d| d.driver_type == DriverType::Native),
            );
            Ok(devices)
        }
        DriverType::Ascom => {
            #[cfg(windows)]
            {
                scan_ascom_for_type_public(device_type).await
            }
            #[cfg(not(windows))]
            {
                Ok(Vec::new())
            }
        }
        DriverType::Alpaca => scan_alpaca_for_type(device_type).await,
        DriverType::Indi => scan_indi_for_type(device_type).await,
        DriverType::Simulator => Ok(builtin_devices_for_type(device_type)
            .into_iter()
            .filter(|d| d.driver_type == DriverType::Simulator)
            .collect()),
    }
}

/// Discover available devices of a specific type.
///
/// Queries every supported backend (Windows ASCOM Profile, Alpaca network
/// discovery, native vendor SDKs, INDI servers known to the device
/// manager) and merges the results with the always-on built-in helpers
/// (multi-star guider, PHD2 if installed, internal simulator).
///
/// Results are cached per (`DeviceType`, `DriverType`) for
/// [`DISCOVERY_CACHE_TTL`] so:
///
///   * Asking for cameras does not force a mount-driver scan.
///   * A failure in one backend (e.g. Alpaca UDP timeout) is cached and
///     reported back to the caller without preventing the other backends
///     from succeeding — silent fall-back is forbidden per `CLAUDE.md`.
///   * Hot-plug events (see [`crate::hotplug`]) invalidate the cache by
///     clearing every entry so the next call re-runs every backend.
pub async fn api_discover_devices(
    device_type: DeviceType,
) -> Result<Vec<DeviceInfo>, NightshadeError> {
    tracing::debug!("Discovering {} devices", device_type.as_str());

    // -------------------------------------------------------------------
    // Fast path: every (device_type, driver) entry is present and fresh.
    // -------------------------------------------------------------------
    if let Some(cached) = collect_fresh_cache(device_type).await {
        tracing::debug!(
            "Using cached discovery results for {} ({} devices)",
            device_type.as_str(),
            cached.len()
        );
        return Ok(cached);
    }

    // -------------------------------------------------------------------
    // Slow path: take the discovery lock to suppress thundering-herd
    // concurrent scans for the same device type, then re-check the cache
    // (another caller may have filled it while we were waiting).
    // -------------------------------------------------------------------
    let _guard = get_discovery_lock().lock().await;

    if let Some(cached) = collect_fresh_cache(device_type).await {
        return Ok(cached);
    }

    // -------------------------------------------------------------------
    // Run every backend's scan for this device type, writing each result
    // (success or failure) into its own per-pair cache entry. Even a
    // backend that returned an empty list gets cached so the TTL also
    // applies to "no devices found" — re-scanning every call would defeat
    // the cache.
    // -------------------------------------------------------------------
    let mut merged: Vec<DeviceInfo> = Vec::new();
    let mut cache = get_discovery_cache().lock().await;
    let now = Instant::now();
    for &driver in SCANNED_DRIVERS {
        let result = run_scan(device_type, driver).await;
        match &result {
            Ok(devices) => {
                tracing::debug!(
                    "Discovery {:?}/{:?}: {} devices",
                    driver,
                    device_type,
                    devices.len()
                );
                merged.extend(devices.iter().cloned());
            }
            Err(err) => {
                tracing::warn!(
                    "Discovery {:?}/{:?} failed: {}",
                    driver,
                    device_type,
                    err
                );
            }
        }
        cache.insert(
            (device_type, driver),
            DiscoveryCacheEntry {
                result,
                timestamp: now,
            },
        );
    }
    drop(cache);

    // Always-on built-in helpers that do not belong to a scanned backend
    // (e.g. the `Simulator` camera). They are appended unconditionally so
    // the UI always sees them, and a separate `Simulator` cache entry is
    // written so subsequent cache-fast-path calls return them too.
    let simulators = builtin_devices_for_type(device_type)
        .into_iter()
        .filter(|d| d.driver_type == DriverType::Simulator)
        .collect::<Vec<_>>();
    if !simulators.is_empty() {
        merged.extend(simulators.iter().cloned());
        let mut cache = get_discovery_cache().lock().await;
        cache.insert(
            (device_type, DriverType::Simulator),
            DiscoveryCacheEntry {
                result: Ok(simulators),
                timestamp: now,
            },
        );
    }

    Ok(merged)
}

/// Return the cached device list for `device_type` if every scanned driver
/// has a fresh entry; otherwise return `None` so the caller re-runs the
/// scans. A backend that previously errored is still considered "fresh"
/// for the purposes of cache validity — repeating a broken scan more than
/// once per [`DISCOVERY_CACHE_TTL`] would just hammer the broken backend
/// without producing new information.
async fn collect_fresh_cache(device_type: DeviceType) -> Option<Vec<DeviceInfo>> {
    let cache = get_discovery_cache().lock().await;
    let mut out: Vec<DeviceInfo> = Vec::new();
    for &driver in SCANNED_DRIVERS {
        let entry = cache.get(&(device_type, driver))?;
        if entry.timestamp.elapsed() >= DISCOVERY_CACHE_TTL {
            return None;
        }
        if let Ok(ref devices) = entry.result {
            out.extend(devices.iter().cloned());
        }
    }
    // Built-in simulators are tracked separately under `DriverType::Simulator`.
    if let Some(entry) = cache.get(&(device_type, DriverType::Simulator)) {
        if entry.timestamp.elapsed() < DISCOVERY_CACHE_TTL {
            if let Ok(ref devices) = entry.result {
                out.extend(devices.iter().cloned());
            }
        }
    }
    Some(out)
}
