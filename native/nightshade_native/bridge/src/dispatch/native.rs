//! Native (vendor SDK) driver dispatch helpers.
//!
//! Methods in this module are additional impl blocks on `DeviceManager` and
//! provide native-SDK-only connect logic. Invoked from the dispatcher methods
//! in `crate::device_manager`. No behavior or signature has changed relative to the
//! previous monolithic `devices.rs`.

use crate::device::*;
use crate::device_manager::DeviceManager;
use nightshade_native::traits::{
    NativeCamera, NativeDevice, NativeFilterWheel, NativeFocuser, NativeMount,
};
use nightshade_native::vendor::atik::AtikCamera;
use nightshade_native::vendor::fli::{FliCamera, FliFilterWheel, FliFocuser};
use nightshade_native::vendor::gphoto2::GPhoto2Camera;
use nightshade_native::vendor::ioptron::IOptronMount;
use nightshade_native::vendor::lx200::{Lx200Mount, Lx200MountType};
use nightshade_native::vendor::moravian::MoravianCamera;
use nightshade_native::vendor::player_one::PlayerOneCamera;
use nightshade_native::vendor::qhy::{QhyCamera, QhyFilterWheel};
use nightshade_native::vendor::skywatcher::SkyWatcherMount;
use nightshade_native::vendor::svbony::SvbonyCamera;
use nightshade_native::vendor::touptek::TouptekCamera;
use nightshade_native::vendor::zwo::{ZwoCamera, ZwoFilterWheel, ZwoFocuser};

impl DeviceManager {
    /// Connect to a Native device
    pub(crate) async fn connect_native(&self, info: &DeviceInfo) -> Result<(), String> {
        // Parse device ID: native:vendor:id
        let parts: Vec<&str> = info.id.split(':').collect();
        if parts.len() < 3 {
            return Err("Invalid native device ID format".to_string());
        }

        let vendor = parts[1];
        let id_str = parts[2];

        if info.device_type == DeviceType::Guider && vendor == "builtin_guider" {
            crate::builtin_guider::connect()
                .await
                .map_err(|e| format!("Failed to connect built-in guider: {}", e))?;
            tracing::info!("Connected to built-in multi-star guider");
            return Ok(());
        }

        // Handle cameras
        if info.device_type == DeviceType::Camera {
            let mut camera: Box<dyn NativeCamera + Send + Sync> = match vendor {
                "zwo" => {
                    let id = id_str.parse::<i32>().map_err(|_| "Invalid ZWO camera ID")?;
                    Box::new(ZwoCamera::new(id))
                }
                "qhy" => Box::new(QhyCamera::new(id_str.to_string())),
                "player_one" => {
                    let id = id_str
                        .parse::<i32>()
                        .map_err(|_| "Invalid Player One camera ID")?;
                    Box::new(PlayerOneCamera::new(id))
                }
                "svbony" => {
                    let id = id_str
                        .parse::<i32>()
                        .map_err(|_| "Invalid SVBony camera ID")?;
                    Box::new(SvbonyCamera::new(id))
                }
                "atik" => {
                    let id = id_str
                        .parse::<i32>()
                        .map_err(|_| "Invalid Atik camera ID")?;
                    Box::new(AtikCamera::new(id))
                }
                "fli" => {
                    // FLI uses device path as ID
                    Box::new(FliCamera::new(id_str.to_string()))
                }
                "touptek" => {
                    // ID format: native:touptek:{brand}:{index}
                    // parts[2] = brand, parts[3] = index
                    let brand = id_str; // parts[2] is the brand
                    let idx_str = parts
                        .get(3)
                        .ok_or("Invalid Touptek camera ID: missing index")?;
                    let idx = idx_str
                        .parse::<usize>()
                        .map_err(|_| "Invalid Touptek camera index")?;
                    Box::new(TouptekCamera::new(idx, brand))
                }
                "moravian" => {
                    let camera_id = id_str
                        .parse::<u32>()
                        .map_err(|_| "Invalid Moravian camera ID")?;
                    Box::new(MoravianCamera::new(camera_id))
                }
                "gphoto2" => {
                    // ID format: native:gphoto2:{index}:{port_hex}:{sanitized_model}
                    // Legacy IDs without a port component are still accepted.
                    let index = id_str
                        .parse::<usize>()
                        .map_err(|_| "Invalid gPhoto2 camera index")?;
                    // Why (audit-rust §4.3): `decode_port_component` returns
                    // None only when `encoded_port` is non-hex or odd length.
                    // We deliberately accept legacy IDs that pre-date the
                    // port-encoding scheme (per the comment above) by treating
                    // a decode failure the same as an absent port — empty
                    // string triggers libgphoto2's `gp_port_info_list_lookup`
                    // auto-detection by USB-bus enumeration. The index is the
                    // load-bearing identifier (and is validated by `?` above),
                    // so port-detection fallback is the SDK-correct path.
                    let port = if let Some(encoded_port) = parts.get(3) {
                        nightshade_native::vendor::gphoto2::decode_port_component(encoded_port)
                            .unwrap_or_default()
                    } else {
                        String::new()
                    };
                    Box::new(GPhoto2Camera::new(index, &info.name, &port))
                }
                _ => return Err(format!("Unknown native camera vendor: {}", vendor)),
            };

            // Connect
            camera.connect().await.map_err(|e| e.to_string())?;

            // Store in native_cameras for typed camera access
            let mut native_cameras = self.native_cameras.write().await;
            native_cameras.insert(info.id.clone(), camera);

            tracing::info!("Connected to native camera: {}", info.name);
            return Ok(());
        }

        // Handle focusers
        if info.device_type == DeviceType::Focuser {
            let mut focuser: Box<dyn NativeFocuser + Send + Sync> = match vendor {
                "zwo" | "zwo_eaf" => {
                    let id = id_str
                        .parse::<i32>()
                        .map_err(|_| "Invalid ZWO focuser ID")?;
                    Box::new(ZwoFocuser::new(id))
                }
                "fli_focuser" => {
                    // FLI uses device path as ID
                    Box::new(FliFocuser::new(id_str.to_string()))
                }
                _ => return Err(format!("Unknown native focuser vendor: {}", vendor)),
            };

            // Connect
            focuser.connect().await.map_err(|e| e.to_string())?;

            // Store in native_focusers for typed focuser access
            let mut native_focusers = self.native_focusers.write().await;
            native_focusers.insert(info.id.clone(), focuser);

            tracing::info!("Connected to native focuser: {}", info.name);
            return Ok(());
        }

        // Handle filter wheels
        if info.device_type == DeviceType::FilterWheel {
            // Disconnect and remove old native filter wheel before creating new one
            // to avoid leaving stale SDK handles open
            {
                let mut native_filter_wheels = self.native_filter_wheels.write().await;
                if let Some(mut old_fw) = native_filter_wheels.remove(&info.id) {
                    let _ = old_fw.disconnect().await;
                    tracing::info!("Disconnected old native filter wheel for {}", info.id);
                }
            }

            let mut filterwheel: Box<dyn NativeFilterWheel + Send + Sync> = match vendor {
                "zwo" | "zwo_efw" => {
                    let id = id_str
                        .parse::<i32>()
                        .map_err(|_| "Invalid ZWO filter wheel ID")?;
                    Box::new(ZwoFilterWheel::new(id))
                }
                "qhy_cfw" => {
                    // QHY CFW uses camera ID string directly
                    Box::new(QhyFilterWheel::new(id_str.to_string()))
                }
                "fli_fw" => {
                    // FLI uses device path as ID
                    Box::new(FliFilterWheel::new(id_str.to_string()))
                }
                _ => return Err(format!("Unknown native filter wheel vendor: {}", vendor)),
            };

            // Connect
            filterwheel.connect().await.map_err(|e| e.to_string())?;

            // Store in native_filter_wheels for typed filter wheel access
            let mut native_filter_wheels = self.native_filter_wheels.write().await;
            native_filter_wheels.insert(info.id.clone(), filterwheel);

            tracing::info!("Connected to native filter wheel: {}", info.name);
            return Ok(());
        }

        // Handle mounts
        if info.device_type == DeviceType::Mount {
            let mut mount: Box<dyn NativeMount + Send + Sync> = match vendor {
                "skywatcher" => {
                    // id_str is the serial port
                    Box::new(SkyWatcherMount::new_serial(id_str.to_string(), None))
                }
                "ioptron" => {
                    // id_str is the serial port
                    Box::new(IOptronMount::new(id_str.to_string(), None))
                }
                "onstep" | "pegasus" => {
                    // OnStep-based mounts (Pegasus NYX, DIY OnStep)
                    Box::new(Lx200Mount::new_onstep(id_str.to_string()))
                }
                "meade" | "lx200" => Box::new(Lx200Mount::new_meade(id_str.to_string())),
                "losmandy" => Box::new(Lx200Mount::new(
                    id_str.to_string(),
                    Lx200MountType::Losmandy,
                    None,
                )),
                "10micron" => Box::new(Lx200Mount::new(
                    id_str.to_string(),
                    Lx200MountType::TenMicron,
                    None,
                )),
                _ => return Err(format!("Unknown native mount vendor: {}", vendor)),
            };

            // Connect
            mount.connect().await.map_err(|e| e.to_string())?;

            // Store in native_mounts for typed mount access
            let mut native_mounts = self.native_mounts.write().await;
            native_mounts.insert(info.id.clone(), mount);

            tracing::info!("Connected to native mount: {}", info.name);
            return Ok(());
        }

        // For other device types, use the generic storage
        let mut device: Box<dyn NativeDevice> = match vendor {
            "zwo" => {
                let id = id_str.parse::<i32>().map_err(|_| "Invalid ZWO camera ID")?;
                Box::new(ZwoCamera::new(id))
            }
            "qhy" => Box::new(QhyCamera::new(id_str.to_string())),
            "player_one" => {
                let id = id_str
                    .parse::<i32>()
                    .map_err(|_| "Invalid Player One camera ID")?;
                Box::new(PlayerOneCamera::new(id))
            }
            "svbony" => {
                let id = id_str
                    .parse::<i32>()
                    .map_err(|_| "Invalid SVBony camera ID")?;
                Box::new(SvbonyCamera::new(id))
            }
            "atik" => {
                let id = id_str
                    .parse::<i32>()
                    .map_err(|_| "Invalid Atik camera ID")?;
                Box::new(AtikCamera::new(id))
            }
            "fli" => Box::new(FliCamera::new(id_str.to_string())),
            "touptek" => {
                // ID format: native:touptek:{brand}:{index}
                let brand = id_str; // parts[2] is the brand
                let idx_str = parts
                    .get(3)
                    .ok_or("Invalid Touptek device ID: missing index")?;
                let idx = idx_str
                    .parse::<usize>()
                    .map_err(|_| "Invalid Touptek device index")?;
                Box::new(TouptekCamera::new(idx, brand))
            }
            "moravian" => {
                let camera_id = id_str
                    .parse::<u32>()
                    .map_err(|_| "Invalid Moravian camera ID")?;
                Box::new(MoravianCamera::new(camera_id))
            }
            "gphoto2" => {
                let index = id_str
                    .parse::<usize>()
                    .map_err(|_| "Invalid gPhoto2 camera index")?;
                // Why (audit-rust §4.3): the index (parts[2]) is the
                // load-bearing identifier — libgphoto2 indexes its
                // detect-list strictly by enumeration order, so a valid
                // index suffices to open the camera. `model` (parts[3])
                // is a display-only label; "Unknown Camera" is the
                // safe cosmetic fallback for legacy IDs missing the
                // sanitized model suffix. `port` (parts[4]) empty
                // triggers gphoto2's USB-bus auto-detection by index,
                // matching the legacy-ID path above. Hard-erroring on
                // either of these would refuse to connect to cameras
                // discovered before the multi-part ID scheme rolled out.
                let model = parts.get(3).unwrap_or(&"Unknown Camera");
                let port = parts.get(4).unwrap_or(&"");
                Box::new(GPhoto2Camera::new(index, model, port))
            }
            _ => return Err(format!("Unknown native vendor: {}", vendor)),
        };

        // Connect
        device.connect().await.map_err(|e| e.to_string())?;

        // Store the connected device instance
        let mut native_devices = self.native_devices.write().await;
        native_devices.insert(info.id.clone(), device);

        tracing::info!("Connected to native device: {}", info.name);
        Ok(())
    }
}
