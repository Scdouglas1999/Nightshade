//! Device Discovery for Native Drivers
//!
//! Discovers devices by querying vendor SDKs directly.
//! Each vendor SDK provides its own discovery mechanism.
//!
//! IMPORTANT: Most vendor SDKs are NOT thread-safe. This module uses a mutex
//! to ensure only one discovery operation runs at a time, plus caching to
//! avoid redundant SDK queries.

use crate::traits::NativeError;
use crate::NativeVendor;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

/// Global mutex to serialize all native SDK discovery calls.
/// Most vendor SDKs (ZWO, QHY, etc.) are NOT thread-safe and will crash
/// if called concurrently from multiple threads.
static DISCOVERY_MUTEX: OnceLock<Mutex<()>> = OnceLock::new();

fn get_discovery_mutex() -> &'static Mutex<()> {
    DISCOVERY_MUTEX.get_or_init(|| Mutex::new(()))
}

/// Cached discovery results with timestamp
struct DiscoveryCache {
    devices: Vec<NativeDeviceInfo>,
    timestamp: Instant,
}

/// Global cache for discovery results (protected by DISCOVERY_MUTEX)
static DISCOVERY_CACHE: OnceLock<Mutex<Option<DiscoveryCache>>> = OnceLock::new();

fn get_discovery_cache() -> &'static Mutex<Option<DiscoveryCache>> {
    DISCOVERY_CACHE.get_or_init(|| Mutex::new(None))
}

/// How long to cache discovery results before re-querying SDKs
/// Set to 60 seconds to avoid redundant discovery during the same session.
/// Discovery can still be triggered manually via the UI refresh button.
const CACHE_TTL: Duration = Duration::from_secs(60);

/// Information about a discovered native device
#[derive(Debug, Clone)]
pub struct NativeDeviceInfo {
    pub id: String,
    pub name: String,
    pub vendor: NativeVendor,
    pub device_type: DeviceType,
    pub serial_number: Option<String>,
    pub sdk_version: Option<String>,
    /// Human-readable name for UI display (includes serial/index for disambiguation)
    pub display_name: String,
}

impl NativeDeviceInfo {
    /// Generate a display name with disambiguation info
    /// Priority: serial_number > discovery_index > plain name
    fn generate_display_name(name: &str, serial_number: Option<&str>, discovery_index: Option<usize>) -> String {
        if let Some(serial) = serial_number {
            if !serial.is_empty() {
                return format!("{} ({})", name, serial);
            }
        }
        if let Some(idx) = discovery_index {
            return format!("{} #{}", name, idx + 1);
        }
        name.to_string()
    }
}

/// Device types supported by native drivers
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeviceType {
    Camera,
    Mount,
    Focuser,
    FilterWheel,
    Rotator,
}

/// Discover all native devices from all vendors
///
/// This function is protected by a mutex to ensure thread-safety since most
/// vendor SDKs are NOT thread-safe. Results are cached for CACHE_TTL seconds
/// to avoid redundant SDK queries when multiple device types are discovered.
pub async fn discover_all_devices() -> Result<Vec<NativeDeviceInfo>, NativeError> {
    // Acquire the discovery mutex to ensure only one discovery runs at a time
    let _guard = get_discovery_mutex().lock().await;

    // Check if we have a valid cached result
    {
        let cache = get_discovery_cache().lock().await;
        if let Some(ref cached) = *cache {
            if cached.timestamp.elapsed() < CACHE_TTL {
                tracing::debug!(
                    "Using cached discovery results ({} devices, {:.1}s old)",
                    cached.devices.len(),
                    cached.timestamp.elapsed().as_secs_f32()
                );
                return Ok(cached.devices.clone());
            }
        }
    }

    tracing::info!("Starting native device discovery sequence...");
    let mut devices = Vec::new();

    // Discover ZWO devices
    tracing::info!("Discovering ZWO cameras...");
    // ZWO SDK doesn't expose serial numbers, so we use discovery index for disambiguation
    if let Ok(zwo_devices) = crate::vendor::zwo::discover_devices().await {
        tracing::info!("Found {} ZWO cameras", zwo_devices.len());
        devices.extend(zwo_devices.into_iter().map(|info| {
            // ZWO doesn't have serial numbers, use index for disambiguation
            let display_name = NativeDeviceInfo::generate_display_name(
                &info.name,
                None,
                Some(info.discovery_index),
            );
            NativeDeviceInfo {
                id: format!("native:zwo:{}", info.camera_id),
                name: info.name,
                vendor: NativeVendor::Zwo,
                device_type: DeviceType::Camera,
                serial_number: None,
                sdk_version: None,
                display_name,
            }
        }));
    }
    tracing::info!("ZWO camera discovery complete.");

    // Discover QHY devices
    // Note: QHY SDK discovery was previously disabled due to initialization issues.
    // It has been re-enabled with proper error handling - discovery failures are
    // logged but don't prevent other vendors from being discovered.
    tracing::info!("Discovering QHY cameras...");
    // QHY ID format typically includes serial: "ModelName-SerialNumber"
    match crate::vendor::qhy::discover_devices().await {
        Ok(qhy_devices) => {
            tracing::info!("Found {} QHY cameras", qhy_devices.len());
            devices.extend(qhy_devices.into_iter().map(|info| {
                let display_name = NativeDeviceInfo::generate_display_name(
                    &info.name,
                    info.serial_number.as_deref(),
                    None,
                );
                NativeDeviceInfo {
                    id: format!("native:qhy:{}", info.camera_id),
                    name: info.name,
                    vendor: NativeVendor::Qhy,
                    device_type: DeviceType::Camera,
                    serial_number: info.serial_number,
                    sdk_version: None,
                    display_name,
                }
            }));
        }
        Err(e) => {
            // Log the error but continue with other vendors
            // This is expected if the QHY SDK is not installed
            tracing::debug!("QHY camera discovery skipped: {}", e);
        }
    }
    tracing::info!("QHY camera discovery complete.");

    // Discover Player One devices
    tracing::info!("Discovering Player One cameras...");
    // Player One SDK provides serial number in POACameraProperties.sn
    if let Ok(po_devices) = crate::vendor::player_one::discover_devices().await {
        tracing::info!("Found {} Player One cameras", po_devices.len());
        devices.extend(po_devices.into_iter().map(|info| {
            let display_name = NativeDeviceInfo::generate_display_name(
                &info.name,
                info.serial_number.as_deref(),
                None,
            );
            NativeDeviceInfo {
                id: format!("native:playerone:{}", info.camera_id),
                name: info.name,
                vendor: NativeVendor::PlayerOne,
                device_type: DeviceType::Camera,
                serial_number: info.serial_number,
                sdk_version: None,
                display_name,
            }
        }));
    }
    tracing::info!("Player One camera discovery complete.");

    // Discover ZWO EAF focusers
    tracing::info!("Discovering ZWO EAF focusers...");
    if let Ok(zwo_focusers) = crate::vendor::zwo::discover_focusers().await {
        tracing::info!("Found {} ZWO EAF focusers", zwo_focusers.len());
        devices.extend(zwo_focusers.into_iter().map(|info| {
            let display_name = NativeDeviceInfo::generate_display_name(
                &info.name,
                info.serial_number.as_deref(),
                Some(info.discovery_index),
            );
            NativeDeviceInfo {
                // Use zwo_eaf vendor to distinguish from cameras (which also use native:zwo:N format)
                id: format!("native:zwo_eaf:{}", info.focuser_id),
                name: info.name,
                vendor: NativeVendor::Zwo,
                device_type: DeviceType::Focuser,
                serial_number: info.serial_number,
                sdk_version: None,
                display_name,
            }
        }));
    }
    tracing::info!("ZWO EAF discovery complete.");

    // Discover ZWO EFW filter wheels
    tracing::info!("Discovering ZWO EFW filter wheels...");
    if let Ok(zwo_filterwheels) = crate::vendor::zwo::discover_filter_wheels().await {
        tracing::info!("Found {} ZWO EFW filter wheels", zwo_filterwheels.len());
        devices.extend(zwo_filterwheels.into_iter().map(|info| {
            let display_name = NativeDeviceInfo::generate_display_name(
                &info.name,
                info.serial_number.as_deref(),
                Some(info.discovery_index),
            );
            NativeDeviceInfo {
                // Use zwo_efw vendor to distinguish from cameras (which also use native:zwo:N format)
                id: format!("native:zwo_efw:{}", info.filterwheel_id),
                name: info.name,
                vendor: NativeVendor::Zwo,
                device_type: DeviceType::FilterWheel,
                serial_number: info.serial_number,
                sdk_version: None,
                display_name,
            }
        }));
    }
    tracing::info!("ZWO EFW discovery complete.");

    // Discover QHY CFW filter wheels (attached to cameras)
    // Note: QHY CFW discovery was previously disabled. Re-enabled with proper error handling.
    tracing::info!("Discovering QHY filter wheels...");
    match crate::vendor::qhy::discover_filter_wheels().await {
        Ok(qhy_filterwheels) => {
            tracing::info!("Found {} QHY filter wheels", qhy_filterwheels.len());
            devices.extend(qhy_filterwheels.into_iter().map(|info| {
                let display_name = format!("{} ({})", info.name, info.camera_id);
                NativeDeviceInfo {
                    // Use camera_id as the unique identifier for the CFW
                    id: format!("native:qhy_cfw:{}", info.camera_id),
                    name: info.name,
                    vendor: NativeVendor::Qhy,
                    device_type: DeviceType::FilterWheel,
                    serial_number: None, // CFW shares serial with camera
                    sdk_version: None,
                    display_name,
                }
            }));
        }
        Err(e) => {
            // Log the error but continue - this is expected if QHY SDK is not installed
            tracing::debug!("QHY CFW discovery skipped: {}", e);
        }
    }
    tracing::info!("QHY CFW discovery complete.");

    // Discover SVBony cameras
    tracing::info!("Discovering SVBony cameras...");
    // SVBony SDK provides serial number in camera properties
    if let Ok(svbony_devices) = crate::vendor::svbony::discover_devices().await {
        tracing::info!("Found {} SVBony cameras", svbony_devices.len());
        devices.extend(svbony_devices.into_iter().map(|info| {
            let display_name = NativeDeviceInfo::generate_display_name(
                &info.name,
                info.serial_number.as_deref(),
                Some(info.discovery_index),
            );
            NativeDeviceInfo {
                id: format!("native:svbony:{}", info.camera_id),
                name: info.name,
                vendor: NativeVendor::Svbony,
                device_type: DeviceType::Camera,
                serial_number: info.serial_number,
                sdk_version: None,
                display_name,
            }
        }));
    }
    tracing::info!("SVBony camera discovery complete.");

    // Discover Atik cameras
    tracing::info!("Discovering Atik cameras...");
    if let Ok(atik_devices) = crate::vendor::atik::discover_devices().await {
        tracing::info!("Found {} Atik cameras", atik_devices.len());
        devices.extend(atik_devices.into_iter().map(|info| {
            let display_name = NativeDeviceInfo::generate_display_name(
                &info.name,
                info.serial_number.as_deref(),
                Some(info.device_index as usize),
            );
            NativeDeviceInfo {
                id: format!("native:atik:{}", info.device_index),
                name: info.name,
                vendor: NativeVendor::Atik,
                device_type: DeviceType::Camera,
                serial_number: info.serial_number,
                sdk_version: None,
                display_name,
            }
        }));
    }
    tracing::info!("Atik camera discovery complete.");

    // Discover FLI cameras
    tracing::info!("Discovering FLI cameras...");
    if let Ok(fli_cameras) = crate::vendor::fli::discover_cameras().await {
        tracing::info!("Found {} FLI cameras", fli_cameras.len());
        devices.extend(fli_cameras.into_iter().map(|info| {
            let path_safe = info.device_path.replace("/", "_").replace("\\", "_");
            let display_name = NativeDeviceInfo::generate_display_name(
                &info.name,
                info.serial_number.as_deref(),
                None,
            );
            NativeDeviceInfo {
                id: format!("native:fli:{}", path_safe),
                name: info.name,
                vendor: NativeVendor::Fli,
                device_type: DeviceType::Camera,
                serial_number: info.serial_number,
                sdk_version: None,
                display_name,
            }
        }));
    }
    tracing::info!("FLI camera discovery complete.");

    // Discover FLI focusers
    tracing::info!("Discovering FLI focusers...");
    if let Ok(fli_focusers) = crate::vendor::fli::discover_focusers().await {
        tracing::info!("Found {} FLI focusers", fli_focusers.len());
        devices.extend(fli_focusers.into_iter().map(|info| {
            let path_safe = info.device_path.replace("/", "_").replace("\\", "_");
            let display_name = NativeDeviceInfo::generate_display_name(
                &info.name,
                info.serial_number.as_deref(),
                None,
            );
            NativeDeviceInfo {
                id: format!("native:fli_focuser:{}", path_safe),
                name: info.name,
                vendor: NativeVendor::Fli,
                device_type: DeviceType::Focuser,
                serial_number: info.serial_number,
                sdk_version: None,
                display_name,
            }
        }));
    }
    tracing::info!("FLI focuser discovery complete.");

    // Discover FLI filter wheels
    tracing::info!("Discovering FLI filter wheels...");
    if let Ok(fli_filterwheels) = crate::vendor::fli::discover_filter_wheels().await {
        tracing::info!("Found {} FLI filter wheels", fli_filterwheels.len());
        devices.extend(fli_filterwheels.into_iter().map(|info| {
            let path_safe = info.device_path.replace("/", "_").replace("\\", "_");
            let display_name = NativeDeviceInfo::generate_display_name(
                &info.name,
                info.serial_number.as_deref(),
                None,
            );
            NativeDeviceInfo {
                id: format!("native:fli_fw:{}", path_safe),
                name: info.name,
                vendor: NativeVendor::Fli,
                device_type: DeviceType::FilterWheel,
                serial_number: info.serial_number,
                sdk_version: None,
                display_name,
            }
        }));
    }
    tracing::info!("FLI filter wheel discovery complete.");

    // Discover Touptek/OGMA cameras
    tracing::info!("Discovering Touptek/OGMA cameras...");
    if let Ok(touptek_devices) = crate::vendor::touptek::discover_devices().await {
        tracing::info!("Found {} Touptek cameras", touptek_devices.len());
        devices.extend(touptek_devices.into_iter().map(|info| {
            let display_name = NativeDeviceInfo::generate_display_name(
                &info.name,
                info.serial_number.as_deref(),
                Some(info.discovery_index),
            );
            NativeDeviceInfo {
                id: format!("native:touptek:{}", info.discovery_index),
                name: info.name,
                vendor: NativeVendor::Touptek,
                device_type: DeviceType::Camera,
                serial_number: info.serial_number,
                sdk_version: None,
                display_name,
            }
        }));
    }
    tracing::info!("Touptek discovery complete.");

    // Discover Moravian cameras
    tracing::info!("Discovering Moravian cameras...");
    if let Ok(moravian_devices) = crate::vendor::moravian::discover_devices().await {
        tracing::info!("Found {} Moravian cameras", moravian_devices.len());
        devices.extend(moravian_devices.into_iter().map(|info| {
            let display_name = NativeDeviceInfo::generate_display_name(
                &info.name,
                info.serial_number.as_deref(),
                Some(info.discovery_index),
            );
            NativeDeviceInfo {
                id: format!("native:moravian:{}", info.camera_id),
                name: info.name,
                vendor: NativeVendor::Moravian,
                device_type: DeviceType::Camera,
                serial_number: info.serial_number,
                sdk_version: None,
                display_name,
            }
        }));
    }
    tracing::info!("Moravian discovery complete.");

    // Discover Fujifilm cameras (Windows only - X Acquire SDK)
    #[cfg(target_os = "windows")]
    {
        tracing::info!("Discovering Fujifilm cameras...");
        match crate::vendor::fujifilm::discover_devices().await {
            Ok(fuji_devices) => {
                tracing::info!("Found {} Fujifilm cameras", fuji_devices.len());
                devices.extend(fuji_devices.into_iter().map(|info| {
                    let display_name = NativeDeviceInfo::generate_display_name(
                        &info.name,
                        info.serial_number.as_deref(),
                        None,
                    );
                    NativeDeviceInfo {
                        id: format!("native:fujifilm:{}", info.serial_number.as_deref().unwrap_or(&info.name)),
                        name: info.name,
                        vendor: NativeVendor::Fujifilm,
                        device_type: DeviceType::Camera,
                        serial_number: info.serial_number,
                        sdk_version: info.firmware_version,
                        display_name,
                    }
                }));
            }
            Err(e) => {
                // Log the error but continue - this is expected if X Acquire SDK is not installed
                tracing::debug!("Fujifilm camera discovery skipped: {}", e);
            }
        }
        tracing::info!("Fujifilm camera discovery complete.");
    }

    // =========================================================================
    // MOUNT DISCOVERY (Serial Protocol Mounts)
    // =========================================================================

    // Discover Sky-Watcher mounts (SynScan protocol)
    tracing::info!("Discovering Sky-Watcher mounts...");
    if let Ok(skywatcher_mounts) = crate::vendor::skywatcher::discover_mounts().await {
        tracing::info!("Found {} Sky-Watcher mounts", skywatcher_mounts.len());
        devices.extend(skywatcher_mounts.into_iter().map(|info| {
            let port_safe = info.port.replace("/", "_").replace("\\", "_");
            // Include baud rate in the ID so we can use it when connecting
            // Format: native:skywatcher:<port>:<baud>
            NativeDeviceInfo {
                id: format!("native:skywatcher:{}:{}", port_safe, info.baud_rate),
                name: info.name.clone(),
                vendor: NativeVendor::SkyWatcher,
                device_type: DeviceType::Mount,
                serial_number: None,
                sdk_version: None,
                display_name: info.name,
            }
        }));
    }
    tracing::info!("Sky-Watcher discovery complete.");

    // Give Windows time to fully release COM ports before next vendor discovery
    // This prevents "Access denied" errors when the same ports are probed
    std::thread::sleep(std::time::Duration::from_millis(200));

    // Discover iOptron mounts
    tracing::info!("Discovering iOptron mounts...");
    if let Ok(ioptron_mounts) = crate::vendor::ioptron::discover_mounts().await {
        tracing::info!("Found {} iOptron mounts", ioptron_mounts.len());
        devices.extend(ioptron_mounts.into_iter().map(|info| {
            let port_safe = info.port.replace("/", "_").replace("\\", "_");
            // Include baud rate in the ID so we can use it when connecting
            // Format: native:ioptron:<port>:<baud>
            NativeDeviceInfo {
                id: format!("native:ioptron:{}:{}", port_safe, info.baud_rate),
                name: info.name.clone(),
                vendor: NativeVendor::IOptron,
                device_type: DeviceType::Mount,
                serial_number: None,
                sdk_version: None,
                display_name: info.name,
            }
        }));
    }
    tracing::info!("iOptron discovery complete.");

    // Give Windows time to fully release COM ports before next vendor discovery
    std::thread::sleep(std::time::Duration::from_millis(200));

    // Discover LX200-compatible mounts (Meade, OnStep/Pegasus, Losmandy, etc.)
    tracing::info!("Discovering LX200 mounts...");
    if let Ok(lx200_mounts) = crate::vendor::lx200::discover_mounts().await {
        tracing::info!("Found {} LX200 mounts", lx200_mounts.len());
        devices.extend(lx200_mounts.into_iter().map(|info| {
            let port_safe = info.port.replace("/", "_").replace("\\", "_");
            let vendor = info.mount_type.vendor();
            let type_prefix = match &info.mount_type {
                crate::vendor::lx200::Lx200MountType::Meade => "meade",
                crate::vendor::lx200::Lx200MountType::OnStep => "onstep",
                crate::vendor::lx200::Lx200MountType::Losmandy => "losmandy",
                crate::vendor::lx200::Lx200MountType::TenMicron => "10micron",
                crate::vendor::lx200::Lx200MountType::Generic => "lx200",
            };
            // Include baud rate in the ID so we can use it when connecting
            // Format: native:<type>:<port>:<baud>
            NativeDeviceInfo {
                id: format!("native:{}:{}:{}", type_prefix, port_safe, info.baud_rate),
                name: info.name.clone(),
                vendor,
                device_type: DeviceType::Mount,
                serial_number: None,
                sdk_version: None,
                display_name: info.name,
            }
        }));
    }
    tracing::info!("LX200 discovery complete.");

    tracing::info!("Native device discovery finished. Found {} total devices.", devices.len());

    // Cache the results for future calls
    {
        let mut cache = get_discovery_cache().lock().await;
        *cache = Some(DiscoveryCache {
            devices: devices.clone(),
            timestamp: Instant::now(),
        });
    }

    Ok(devices)
}

/// Invalidate the discovery cache, forcing the next discovery call to re-query all SDKs
pub async fn invalidate_discovery_cache() {
    let _guard = get_discovery_mutex().lock().await;
    let mut cache = get_discovery_cache().lock().await;
    *cache = None;
    tracing::debug!("Discovery cache invalidated");
}

/// Discover devices of a specific type
pub async fn discover_devices(device_type: DeviceType) -> Result<Vec<NativeDeviceInfo>, NativeError> {
    let all_devices = discover_all_devices().await?;
    Ok(all_devices
        .into_iter()
        .filter(|d| d.device_type == device_type)
        .collect())
}

/// Discover devices from a specific vendor
pub async fn discover_vendor_devices(vendor: NativeVendor) -> Result<Vec<NativeDeviceInfo>, NativeError> {
    let all_devices = discover_all_devices().await?;
    Ok(all_devices
        .into_iter()
        .filter(|d| d.vendor == vendor)
        .collect())
}

