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
// Device Connection
// =============================================================================

/// Try to construct a DeviceInfo from a device ID string without running discovery.
/// This avoids opening/closing hardware (e.g. ZWO EFW) which can interfere with
/// subsequent position reads.
pub(crate) fn device_info_from_id(device_id: &str, device_type: DeviceType) -> Option<DeviceInfo> {
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

pub(crate) fn is_phd2_device_id(device_id: &str) -> bool {
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
// ALPACA DEVICE CONNECTION (Cross-platform)
// =============================================================================

pub mod alpaca_connections {
    use super::*;
    // Re-export AlpacaClient for FRB bindings
    pub use nightshade_alpaca::AlpacaClient;
    use nightshade_alpaca::{AlpacaDevice, AlpacaDeviceType};
    use std::collections::HashMap;

    // Storage for active Alpaca connections using Arc to share ownership.
    //
    // Lifecycle invariant: `disconnect_alpaca_device` removes the entry before
    // returning, so this map is bounded by the count of currently-connected
    // Alpaca devices. Verified in audit-rust §3.5 (CQ-W1-UNIFIED-IMG): the
    // legacy direct-API `connect_alpaca_device` / `disconnect_alpaca_device`
    // pair is the only writer and the only reader. The unified
    // `api_disconnect_device` path uses the per-type maps inside
    // `DeviceManager` (devices.rs) which evict on disconnect as well.
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