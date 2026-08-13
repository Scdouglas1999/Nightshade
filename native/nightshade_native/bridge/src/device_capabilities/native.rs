use super::*;

pub(crate) fn native_cover_state_to_capability(
    state: nightshade_native::traits::NativeCoverState,
) -> CoverState {
    match state {
        nightshade_native::traits::NativeCoverState::NotPresent => CoverState::NotPresent,
        nightshade_native::traits::NativeCoverState::Closed => CoverState::Closed,
        nightshade_native::traits::NativeCoverState::Moving => CoverState::Moving,
        nightshade_native::traits::NativeCoverState::Open => CoverState::Open,
        nightshade_native::traits::NativeCoverState::Unknown => CoverState::Unknown,
        nightshade_native::traits::NativeCoverState::Error => CoverState::Error,
    }
}

pub(crate) fn native_calibrator_state_to_capability(
    state: nightshade_native::traits::NativeCalibratorState,
) -> CalibratorState {
    match state {
        nightshade_native::traits::NativeCalibratorState::NotPresent => CalibratorState::NotPresent,
        nightshade_native::traits::NativeCalibratorState::Off => CalibratorState::Off,
        nightshade_native::traits::NativeCalibratorState::NotReady => CalibratorState::NotReady,
        nightshade_native::traits::NativeCalibratorState::Ready => CalibratorState::Ready,
        nightshade_native::traits::NativeCalibratorState::Unknown => CalibratorState::Unknown,
        nightshade_native::traits::NativeCalibratorState::Error => CalibratorState::Error,
    }
}

/// Get capabilities for a native SDK device
///
/// Native SDK devices (ZWO, QHY, PlayerOne, etc.) typically have well-defined
/// capabilities that can be queried from their SDK functions. This function
/// returns capability information based on the vendor and device type.
///
/// # Silent-fallback contract
///
/// Native vendor SDKs use their own `Result` types: failures here usually mean
/// "the SDK rejected the call because the camera/mount is mid-state-transition"
/// (e.g. querying `is_moving` while a homing routine is firing). The capability
/// struct is a SNAPSHOT — defaulting transient-state booleans to `false` and
/// missing-list queries to empty is acceptable because the equipment view
/// re-polls these values on a timer once the connection is established.
pub(crate) async fn get_native_capabilities(
    device_id: &str,
) -> Result<DeviceCapabilities, NightshadeError> {
    let mgr = crate::api::get_device_manager();

    // Look up the device in the device registry to determine its type
    let device_type = {
        let devices = mgr.devices.read().await;
        devices.get(device_id).map(|d| d.info.device_type.clone())
    };

    let device_type = device_type.ok_or_else(|| {
        NightshadeError::hardware_error(device_id, "Device not found in registry")
    })?;

    match device_type {
        crate::device::DeviceType::Camera => {
            let native_cameras = mgr.native_cameras.read().await;
            if let Some(camera) = native_cameras.get(device_id) {
                let native_caps = camera.capabilities();
                let sensor_info = camera.get_sensor_info();
                let gain_range = camera.get_gain_range().await.ok();
                let offset_range = camera.get_offset_range().await.ok();
                // Why: vendor SDK readout-mode enumeration is optional (only ZWO
                // and QHY expose multi-mode sensors). Empty vec → UI hides the
                // readout-mode selector, matching cameras that have a single
                // hard-coded mode.
                let readout_modes = camera.get_readout_modes().await.unwrap_or_default();
                let status = camera.get_status().await.ok();
                let cooler_power = status.as_ref().and_then(|s| s.cooler_power);
                // Why: the NativeCamera trait's get_cooler_temp_range default
                // returns Ok(None); only drivers that publish the achievable
                // regulated-cooling range (currently ZWO, via C2) override it.
                // `.ok().flatten()` collapses a transient SDK error to None
                // ("range unknown") — the equipment view re-probes on a timer,
                // and an unknown range simply leaves the setpoint field unclamped
                // rather than fabricating limits.
                let (cooler_min_temp_c, cooler_max_temp_c) = camera
                    .get_cooler_temp_range()
                    .await
                    .ok()
                    .flatten()
                    .map_or((None, None), |(min, max)| (Some(min), Some(max)));

                // Same contract as the cooler range: `None` means "this driver
                // does not publish the limits", never a guessed clamp. Without
                // these, `exposureMin`/`exposureMax` were always null, so no
                // client could validate an exposure before submitting it and an
                // out-of-range request failed deep in the SDK instead of being
                // refused up front. ZWO publishes them via ASIGetControlCaps.
                let (exposure_min, exposure_max) = camera
                    .get_exposure_range()
                    .await
                    .ok()
                    .flatten()
                    .map_or((None, None), |(min, max)| (Some(min), Some(max)));

                Ok(DeviceCapabilities::Camera(CameraCapabilities {
                    max_width: sensor_info.width,
                    max_height: sensor_info.height,
                    bit_depth: sensor_info.bit_depth,
                    has_shutter: native_caps.has_shutter,
                    can_set_ccd_temperature: native_caps.can_cool,
                    can_set_cooler: native_caps.can_cool,
                    can_get_cooler_power: cooler_power.is_some(),
                    can_bin: native_caps.can_set_binning,
                    max_bin_x: native_caps.max_bin_x,
                    max_bin_y: native_caps.max_bin_y,
                    can_set_gain: native_caps.can_set_gain,
                    gain_min: gain_range.map(|(min, _)| min),
                    gain_max: gain_range.map(|(_, max)| max),
                    can_set_offset: native_caps.can_set_offset,
                    offset_min: offset_range.map(|(min, _)| min),
                    offset_max: offset_range.map(|(_, max)| max),
                    can_abort_exposure: true,
                    can_subframe: native_caps.can_subframe,
                    pixel_size_x: Some(sensor_info.pixel_size_x),
                    pixel_size_y: Some(sensor_info.pixel_size_y),
                    is_color: sensor_info.color,
                    bayer_pattern: sensor_info.bayer_pattern.map(|bp| format!("{:?}", bp)),
                    readout_modes: readout_modes.into_iter().map(|m| m.name).collect(),
                    ccd_temperature: status.as_ref().and_then(|s| s.sensor_temp),
                    set_ccd_temperature: status.as_ref().and_then(|s| s.target_temp),
                    cooler_power,
                    cooler_on: status.as_ref().map(|s| s.cooler_on),
                    cooler_min_temp_c,
                    cooler_max_temp_c,
                    exposure_min,
                    exposure_max,
                    ..Default::default()
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native camera not connected",
                ))
            }
        }
        crate::device::DeviceType::Mount => {
            let native_mounts = mgr.native_mounts.read().await;
            if let Some(mount) = native_mounts.get(device_id) {
                let tracking = mount.get_tracking().await.ok();
                let can_set_tracking = tracking.is_some();
                let can_park = mount.is_parked().await.is_ok();
                let can_abort_slew = mount.is_slewing().await.is_ok();
                Ok(DeviceCapabilities::Mount(MountCapabilities {
                    can_slew: true,
                    can_slew_async: true,
                    can_sync: true,
                    can_park,
                    can_unpark: can_park,
                    can_pulse_guide: true,
                    can_set_tracking,
                    can_abort_slew,
                    is_equatorial: true,
                    tracking,
                    axis_count: 2,
                    ..Default::default()
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native mount not connected",
                ))
            }
        }
        crate::device::DeviceType::Focuser => {
            let native_focusers = mgr.native_focusers.read().await;
            if let Some(focuser) = native_focusers.get(device_id) {
                let position = focuser.get_position().await.ok();
                let temperature = focuser.get_temperature().await.ok().flatten();
                // Why: transient-state probe — if the focuser SDK is busy with
                // another command we treat the focuser as stationary in this
                // snapshot. The equipment poller re-reads on a 500 ms cadence,
                // so a false "stationary" reading self-corrects within a frame.
                let is_moving = focuser.is_moving().await.unwrap_or(false);
                Ok(DeviceCapabilities::Focuser(FocuserCapabilities {
                    max_position: focuser.get_max_position(),
                    step_size: Some(focuser.get_step_size()),
                    absolute: true,
                    position,
                    temperature,
                    is_moving,
                    can_halt: true,
                    ..Default::default()
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native focuser not connected",
                ))
            }
        }
        crate::device::DeviceType::FilterWheel => {
            let native_fws = mgr.native_filter_wheels.read().await;
            if let Some(fw) = native_fws.get(device_id) {
                // Why: vendor SDKs that don't persist filter labels (e.g. ZWO
                // EFW) return an error here on first connect. Empty vec → UI
                // renders generic "Filter 1, Filter 2..." labels indexed off
                // `get_filter_count()`, which is sufficient for slot selection.
                let names = fw.get_filter_names().await.unwrap_or_default();
                let position = fw.get_position().await.ok().map(|p| p as i32);
                // Why: same transient-state contract as focuser is_moving above.
                let is_moving = fw.is_moving().await.unwrap_or(false);
                Ok(DeviceCapabilities::FilterWheel(FilterWheelCapabilities {
                    position_count: fw.get_filter_count(),
                    current_position: position,
                    filter_names: names,
                    is_moving,
                    // The `NativeFilterWheel` trait requires `set_filter_name`,
                    // so every native wheel can be renamed. Leaving this at the
                    // `Default::default()` `false` under-reported a working
                    // feature: on the live rig a real ZWO EFW advertised
                    // `canSetFilterNames: false`, yet
                    // `POST /api/filter-wheel/names` with
                    // ["L","R","G","B","Ha","OIII","SII","Dark"] returned 200 and
                    // both `/api/filter-wheel/names` and
                    // `/api/equipment/filter-wheel/status` served the new labels
                    // back. Any UI that gates its rename control on this flag
                    // hides a feature the hardware supports.
                    can_set_filter_names: true,
                    ..Default::default()
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native filter wheel not connected",
                ))
            }
        }
        crate::device::DeviceType::Rotator => {
            let native_rotators = mgr.native_rotators.read().await;
            if let Some(rotator) = native_rotators.get(device_id) {
                let position = rotator.get_position().await.ok();
                let mechanical_position = rotator.get_mechanical_position().await.ok();
                let moving_result = rotator.is_moving().await;
                let can_halt = moving_result.is_ok();
                let is_moving = moving_result.unwrap_or(false);
                let can_reverse = rotator.can_reverse();
                let reverse = if can_reverse {
                    rotator.get_reverse().await.unwrap_or(false)
                } else {
                    false
                };

                Ok(DeviceCapabilities::Rotator(RotatorCapabilities {
                    can_reverse,
                    reverse,
                    step_size: None,
                    is_moving,
                    mechanical_position,
                    position,
                    can_move_absolute: true,
                    can_halt,
                    can_sync: true,
                    // Why: the NativeRotator trait exposes no angle-range accessor
                    // (vendor rotator SDKs do not publish mechanical min/max), so
                    // the range is genuinely unknown here. None = "unbounded by
                    // contract", never a fabricated 0–360 clamp.
                    min_angle_deg: None,
                    max_angle_deg: None,
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native rotator not connected",
                ))
            }
        }
        crate::device::DeviceType::Dome => {
            let native_domes = mgr.native_domes.read().await;
            if let Some(dome) = native_domes.get(device_id) {
                let azimuth = dome.get_azimuth().await.ok();
                let slewing_result = dome.is_slewing().await;
                let can_abort = slewing_result.is_ok();
                // Why: paired-probe pattern: the Result<bool> tells us BOTH whether
                // the capability exists (Ok = `can_abort`) and the current state
                // (false on Err is safe-default "not slewing"). The capability is
                // returned via `can_abort` so callers can distinguish "absent" from
                // "present and false" via the separate flag.
                let slewing = slewing_result.unwrap_or(false);
                let at_home_result = dome.is_at_home().await;
                let can_find_home = at_home_result.is_ok();
                let at_home = at_home_result.unwrap_or(false); // Why: same paired-probe pattern as `slewing` above
                let at_park_result = dome.is_parked().await;
                let can_park = at_park_result.is_ok();
                let at_park = at_park_result.unwrap_or(false); // Why: same paired-probe pattern as `slewing` above
                                                               // Why: NativeDome.is_slaved() failure is treated as "not slaved"
                                                               // because the slave-loop is a host-side process we control; if
                                                               // it's not visible to the device wrapper, it's not running.
                let slaved = dome.is_slaved().await.unwrap_or(false);
                let shutter_status =
                    dome.get_shutter_status()
                        .await
                        .ok()
                        .map(|status| match status {
                            nightshade_native::traits::ShutterState::Open => ShutterStatus::Open,
                            nightshade_native::traits::ShutterState::Closed => {
                                ShutterStatus::Closed
                            }
                            nightshade_native::traits::ShutterState::Opening => {
                                ShutterStatus::Opening
                            }
                            nightshade_native::traits::ShutterState::Closing => {
                                ShutterStatus::Closing
                            }
                            nightshade_native::traits::ShutterState::Error => {
                                ShutterStatus::Unknown
                            }
                            nightshade_native::traits::ShutterState::Unknown => {
                                ShutterStatus::Unknown
                            }
                        });

                Ok(DeviceCapabilities::Dome(DomeCapabilities {
                    can_set_azimuth: dome.can_set_azimuth(),
                    can_park,
                    can_find_home,
                    can_set_shutter: dome.can_set_shutter(),
                    can_sync_azimuth: false,
                    azimuth,
                    slewing,
                    at_home,
                    at_park,
                    shutter_status,
                    can_slave: dome.can_slave(),
                    slaved,
                    can_abort,
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native dome not connected",
                ))
            }
        }
        crate::device::DeviceType::Weather => {
            let native_weather = mgr.native_weather.read().await;
            if let Some(weather) = native_weather.get(device_id) {
                let has_cloud_cover = weather.get_cloud_cover().await.ok().flatten().is_some();
                let has_dew_point = weather.get_dew_point().await.ok().flatten().is_some();
                let has_humidity = weather.get_humidity().await.ok().flatten().is_some();
                let has_pressure = weather.get_pressure().await.ok().flatten().is_some();
                let has_rain_rate = weather.get_rain_rate().await.ok().flatten().is_some();
                let has_sky_quality = weather.get_sky_quality().await.ok().flatten().is_some();
                let has_temperature = weather.get_temperature().await.ok().flatten().is_some();
                let has_wind_direction =
                    weather.get_wind_direction().await.ok().flatten().is_some();
                let has_wind_speed = weather.get_wind_speed().await.ok().flatten().is_some();

                Ok(DeviceCapabilities::Weather(WeatherCapabilities {
                    has_cloud_cover,
                    has_dew_point,
                    has_humidity,
                    has_pressure,
                    has_rain_rate,
                    has_sky_quality,
                    has_temperature,
                    has_wind_direction,
                    has_wind_speed,
                    has_sky_brightness: false,
                    has_sky_temperature: false,
                    has_seeing: false,
                    has_wind_gust: false,
                    average_period: None,
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native weather station not connected",
                ))
            }
        }
        crate::device::DeviceType::SafetyMonitor => {
            let native_safety = mgr.native_safety_monitors.read().await;
            if let Some(safety) = native_safety.get(device_id) {
                // Why: SafetyMonitor "fail-closed" rule — a comms error from a
                // native safety driver MUST report "unsafe", never "safe".
                // Matches the ASCOM ISafetyMonitorV1 contract enforced at the
                // Alpaca/ASCOM branches above.
                let is_safe = safety.is_safe().await.unwrap_or(false);
                Ok(DeviceCapabilities::SafetyMonitor(
                    SafetyMonitorCapabilities {
                        is_safe,
                        safety_description: None,
                    },
                ))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native safety monitor not connected",
                ))
            }
        }
        crate::device::DeviceType::Switch => {
            let native_switches = mgr.native_switches.read().await;
            if let Some(switch) = native_switches.get(device_id) {
                let switch_count = switch.get_switch_count().await.unwrap_or(0);
                let switches = switch
                    .get_switches()
                    .await
                    .unwrap_or_default()
                    .into_iter()
                    .map(|channel| SwitchInfo {
                        index: channel.id,
                        name: channel.name,
                        description: channel.description,
                        is_boolean: channel.is_boolean,
                        min_value: channel.min_value,
                        max_value: channel.max_value,
                        step: channel.step,
                        can_write: channel.can_write,
                        value: channel.value,
                    })
                    .collect();

                Ok(DeviceCapabilities::Switch(SwitchCapabilities {
                    switch_count,
                    switches,
                }))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native switch not connected",
                ))
            }
        }
        crate::device::DeviceType::CoverCalibrator => {
            let native_covers = mgr.native_cover_calibrators.read().await;
            if let Some(cover) = native_covers.get(device_id) {
                let cover_state = cover
                    .get_cover_state()
                    .await
                    .ok()
                    .map(native_cover_state_to_capability);
                let calibrator_state = cover
                    .get_calibrator_state()
                    .await
                    .ok()
                    .map(native_calibrator_state_to_capability);
                let brightness = cover.get_brightness().await.ok();
                let max_brightness = cover.get_max_brightness().await.unwrap_or(0);

                Ok(DeviceCapabilities::CoverCalibrator(
                    CoverCalibratorCapabilities {
                        max_brightness,
                        cover_present: cover_state.map_or(false, |s| s != CoverState::NotPresent),
                        calibrator_present: calibrator_state
                            .map_or(false, |s| s != CalibratorState::NotPresent),
                        cover_state,
                        calibrator_state,
                        brightness,
                    },
                ))
            } else {
                Err(NightshadeError::hardware_error(
                    device_id,
                    "Native cover calibrator not connected",
                ))
            }
        }
        _ => Err(NightshadeError::not_supported(
            device_id,
            &format!(
                "Native capabilities are unavailable for device type {:?}",
                device_type
            ),
        )),
    }
}
