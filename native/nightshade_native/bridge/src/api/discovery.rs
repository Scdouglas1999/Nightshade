// CQ-W3-API-RS: split from monolithic api.rs (audit-rust §9 / audit-arch §1.2)
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs (audit-rust §9).
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