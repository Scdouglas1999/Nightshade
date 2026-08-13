use super::*;

#[derive(Debug)]
struct FakeNativeRotator;

#[async_trait::async_trait]
impl nightshade_native::traits::NativeDevice for FakeNativeRotator {
    fn id(&self) -> &str {
        "native:zwo:900001"
    }

    fn name(&self) -> &str {
        "Fake Native Rotator"
    }

    fn vendor(&self) -> nightshade_native::NativeVendor {
        nightshade_native::NativeVendor::Other("Test".to_string())
    }

    fn is_connected(&self) -> bool {
        true
    }

    async fn connect(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }
}

#[async_trait::async_trait]
impl nightshade_native::traits::NativeRotator for FakeNativeRotator {
    async fn move_to(
        &mut self,
        _position: f64,
    ) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    async fn get_position(&self) -> Result<f64, nightshade_native::traits::NativeError> {
        Ok(12.5)
    }

    async fn get_mechanical_position(&self) -> Result<f64, nightshade_native::traits::NativeError> {
        Ok(14.0)
    }

    async fn is_moving(&self) -> Result<bool, nightshade_native::traits::NativeError> {
        Ok(true)
    }

    async fn halt(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    async fn sync(&mut self, _position: f64) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    fn can_reverse(&self) -> bool {
        true
    }

    async fn set_reverse(
        &mut self,
        _reverse: bool,
    ) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    async fn get_reverse(&self) -> Result<bool, nightshade_native::traits::NativeError> {
        Ok(true)
    }
}

#[derive(Debug)]
struct FakeNativeSwitch;

#[async_trait::async_trait]
impl nightshade_native::traits::NativeDevice for FakeNativeSwitch {
    fn id(&self) -> &str {
        "native:qhy:900002"
    }

    fn name(&self) -> &str {
        "Fake Native Switch"
    }

    fn vendor(&self) -> nightshade_native::NativeVendor {
        nightshade_native::NativeVendor::Other("Test".to_string())
    }

    fn is_connected(&self) -> bool {
        true
    }

    async fn connect(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }
}

#[async_trait::async_trait]
impl nightshade_native::traits::NativeSwitch for FakeNativeSwitch {
    async fn get_switch_count(&self) -> Result<i32, nightshade_native::traits::NativeError> {
        Ok(1)
    }

    async fn get_switches(
        &self,
    ) -> Result<
        Vec<nightshade_native::traits::NativeSwitchChannel>,
        nightshade_native::traits::NativeError,
    > {
        Ok(vec![nightshade_native::traits::NativeSwitchChannel {
            id: 0,
            name: "Relay".to_string(),
            description: "Dew heater".to_string(),
            state: true,
            value: 0.75,
            min_value: 0.0,
            max_value: 1.0,
            step: 0.05,
            can_write: true,
            is_boolean: false,
        }])
    }

    async fn get_switch_state(
        &self,
        _switch_id: i32,
    ) -> Result<bool, nightshade_native::traits::NativeError> {
        Ok(true)
    }

    async fn set_switch_state(
        &mut self,
        _switch_id: i32,
        _state: bool,
    ) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    async fn get_switch_value(
        &self,
        _switch_id: i32,
    ) -> Result<f64, nightshade_native::traits::NativeError> {
        Ok(0.75)
    }

    async fn set_switch_value(
        &mut self,
        _switch_id: i32,
        _value: f64,
    ) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    async fn get_switch_name(
        &self,
        _switch_id: i32,
    ) -> Result<String, nightshade_native::traits::NativeError> {
        Ok("Relay".to_string())
    }

    async fn get_switch_description(
        &self,
        _switch_id: i32,
    ) -> Result<String, nightshade_native::traits::NativeError> {
        Ok("Dew heater".to_string())
    }

    async fn get_switch_min_value(
        &self,
        _switch_id: i32,
    ) -> Result<f64, nightshade_native::traits::NativeError> {
        Ok(0.0)
    }

    async fn get_switch_max_value(
        &self,
        _switch_id: i32,
    ) -> Result<f64, nightshade_native::traits::NativeError> {
        Ok(1.0)
    }

    async fn get_switch_step(
        &self,
        _switch_id: i32,
    ) -> Result<f64, nightshade_native::traits::NativeError> {
        Ok(0.05)
    }

    async fn can_write(
        &self,
        _switch_id: i32,
    ) -> Result<bool, nightshade_native::traits::NativeError> {
        Ok(true)
    }
}

#[derive(Debug)]
struct FakeNativeCoverCalibrator;

#[async_trait::async_trait]
impl nightshade_native::traits::NativeDevice for FakeNativeCoverCalibrator {
    fn id(&self) -> &str {
        "native:player_one:900003"
    }

    fn name(&self) -> &str {
        "Fake Native Cover"
    }

    fn vendor(&self) -> nightshade_native::NativeVendor {
        nightshade_native::NativeVendor::Other("Test".to_string())
    }

    fn is_connected(&self) -> bool {
        true
    }

    async fn connect(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }
}

#[async_trait::async_trait]
impl nightshade_native::traits::NativeCoverCalibrator for FakeNativeCoverCalibrator {
    async fn open_cover(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    async fn close_cover(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    async fn halt_cover(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    async fn calibrator_on(
        &mut self,
        _brightness: i32,
    ) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    async fn calibrator_off(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }

    async fn get_cover_state(
        &self,
    ) -> Result<nightshade_native::traits::NativeCoverState, nightshade_native::traits::NativeError>
    {
        Ok(nightshade_native::traits::NativeCoverState::Open)
    }

    async fn get_calibrator_state(
        &self,
    ) -> Result<
        nightshade_native::traits::NativeCalibratorState,
        nightshade_native::traits::NativeError,
    > {
        Ok(nightshade_native::traits::NativeCalibratorState::Ready)
    }

    async fn get_brightness(&self) -> Result<i32, nightshade_native::traits::NativeError> {
        Ok(42)
    }

    async fn get_max_brightness(&self) -> Result<i32, nightshade_native::traits::NativeError> {
        Ok(255)
    }
}

fn native_test_info(id: &str, device_type: crate::device::DeviceType) -> crate::device::DeviceInfo {
    crate::device::DeviceInfo {
        id: id.to_string(),
        name: id.to_string(),
        device_type,
        driver_type: crate::device::DriverType::Native,
        description: "Fake native test device".to_string(),
        driver_version: "test".to_string(),
        serial_number: None,
        unique_id: None,
        display_name: id.to_string(),
    }
}

async fn register_native_test_device(id: &str, device_type: crate::device::DeviceType) {
    let manager = crate::api::get_device_manager();
    manager.devices.write().await.insert(
        id.to_string(),
        crate::device_manager::ManagedDevice {
            info: native_test_info(id, device_type),
            connection_state: crate::device::ConnectionState::Connected,
            last_error: None,
            reconnect_attempts: 0,
            auto_reconnect: false,
            last_successful_comm: None,
            heartbeat_active: false,
            api_version: None,
            desired_cooler: None,
            desired_tracking: None,
        },
    );
    invalidate_capability_cache_for_device(id).await;
}

#[test]
fn indi_sensor_type_color_detection_is_conservative() {
    assert!(indi_sensor_type_is_color("COLOR"));
    assert!(indi_sensor_type_is_color("Bayer RGGB"));
    assert!(indi_sensor_type_is_color("OSC"));
    assert!(!indi_sensor_type_is_color("MONOCHROME"));
    assert!(!indi_sensor_type_is_color("CCD_SENSOR_MONO"));
}

#[test]
fn indi_readout_mode_label_falls_back_to_element_name() {
    let labeled = nightshade_indi::IndiReadoutMode {
        element: "MODE_0".to_string(),
        label: "High Gain".to_string(),
    };
    let unlabeled = nightshade_indi::IndiReadoutMode {
        element: "MODE_1".to_string(),
        label: String::new(),
    };

    assert_eq!(indi_readout_mode_label(&labeled), "High Gain");
    assert_eq!(indi_readout_mode_label(&unlabeled), "MODE_1");
}

#[tokio::test]
async fn capability_cache_stores_and_invalidates_by_device() {
    let device_id = "simulator:camera:0";
    invalidate_capability_cache().await;

    let caps = get_device_capabilities(device_id)
        .await
        .expect("simulator capabilities should resolve");
    assert!(matches!(caps, DeviceCapabilities::Camera(_)));
    assert_eq!(capability_cache().lock().await.len(), 1);

    invalidate_capability_cache_for_device(device_id).await;
    assert_eq!(capability_cache().lock().await.len(), 0);
}

#[cfg(windows)]
#[test]
fn capability_probe_only_owns_known_disconnected_session() {
    assert!(capability_probe_should_own_connection(Ok(false)));
    assert!(!capability_probe_should_own_connection(Ok(true)));
    assert!(!capability_probe_should_own_connection(Err(
        "Connected property unavailable".to_string(),
    )));
}

#[cfg(windows)]
#[test]
fn ascom_device_type_normalization_requires_exact_device_type() {
    assert_eq!(
        normalize_ascom_capability_device_type("Camera"),
        Some(AscomCapabilityDeviceType::Camera)
    );
    assert_eq!(
        normalize_ascom_capability_device_type("Telescope"),
        Some(AscomCapabilityDeviceType::Mount)
    );
    assert_eq!(
        normalize_ascom_capability_device_type("CoverCalibrator"),
        Some(AscomCapabilityDeviceType::CoverCalibrator)
    );
    assert_eq!(normalize_ascom_capability_device_type("CameraGuard"), None);
}

#[tokio::test]
async fn native_rotator_capabilities_use_connected_trait_object() {
    let device_id = "native:zwo:900001";
    register_native_test_device(device_id, crate::device::DeviceType::Rotator).await;
    crate::api::get_device_manager()
        .native_rotators
        .write()
        .await
        .insert(device_id.to_string(), Box::new(FakeNativeRotator));

    let caps = get_device_capabilities(device_id)
        .await
        .expect("native rotator capabilities should resolve");

    match caps {
        DeviceCapabilities::Rotator(caps) => {
            assert_eq!(caps.position, Some(12.5));
            assert_eq!(caps.mechanical_position, Some(14.0));
            assert!(caps.is_moving);
            assert!(caps.can_reverse);
            assert!(caps.reverse);
            assert!(caps.can_move_absolute);
            assert!(caps.can_halt);
            assert!(caps.can_sync);
            // The NativeRotator trait exposes no angle-range accessor, so the
            // probe must surface an honest "unknown" rather than a clamp.
            assert_eq!(caps.min_angle_deg, None);
            assert_eq!(caps.max_angle_deg, None);
        }
        other => panic!("expected rotator capabilities, got {other:?}"),
    }

    crate::api::get_device_manager()
        .native_rotators
        .write()
        .await
        .remove(device_id);
    crate::api::get_device_manager()
        .devices
        .write()
        .await
        .remove(device_id);
    invalidate_capability_cache_for_device(device_id).await;
}

#[tokio::test]
async fn native_switch_capabilities_use_connected_trait_object() {
    let device_id = "native:qhy:900002";
    register_native_test_device(device_id, crate::device::DeviceType::Switch).await;
    crate::api::get_device_manager()
        .native_switches
        .write()
        .await
        .insert(device_id.to_string(), Box::new(FakeNativeSwitch));

    let caps = get_device_capabilities(device_id)
        .await
        .expect("native switch capabilities should resolve");

    match caps {
        DeviceCapabilities::Switch(caps) => {
            assert_eq!(caps.switch_count, 1);
            assert_eq!(caps.switches.len(), 1);
            assert_eq!(caps.switches[0].name, "Relay");
            assert_eq!(caps.switches[0].description, "Dew heater");
            assert_eq!(caps.switches[0].value, 0.75);
            assert!(caps.switches[0].can_write);
        }
        other => panic!("expected switch capabilities, got {other:?}"),
    }

    crate::api::get_device_manager()
        .native_switches
        .write()
        .await
        .remove(device_id);
    crate::api::get_device_manager()
        .devices
        .write()
        .await
        .remove(device_id);
    invalidate_capability_cache_for_device(device_id).await;
}

#[tokio::test]
async fn native_cover_capabilities_use_connected_trait_object() {
    let device_id = "native:player_one:900003";
    register_native_test_device(device_id, crate::device::DeviceType::CoverCalibrator).await;
    crate::api::get_device_manager()
        .native_cover_calibrators
        .write()
        .await
        .insert(device_id.to_string(), Box::new(FakeNativeCoverCalibrator));

    let caps = get_device_capabilities(device_id)
        .await
        .expect("native cover capabilities should resolve");

    match caps {
        DeviceCapabilities::CoverCalibrator(caps) => {
            assert_eq!(caps.max_brightness, 255);
            assert_eq!(caps.brightness, Some(42));
            assert_eq!(caps.cover_state, Some(CoverState::Open));
            assert_eq!(caps.calibrator_state, Some(CalibratorState::Ready));
            assert!(caps.cover_present);
            assert!(caps.calibrator_present);
        }
        other => panic!("expected cover calibrator capabilities, got {other:?}"),
    }

    crate::api::get_device_manager()
        .native_cover_calibrators
        .write()
        .await
        .remove(device_id);
    crate::api::get_device_manager()
        .devices
        .write()
        .await
        .remove(device_id);
    invalidate_capability_cache_for_device(device_id).await;
}

#[tokio::test]
async fn native_cover_switch_rotator_operations_dispatch_to_trait_objects() {
    let manager = crate::api::get_device_manager();
    let rotator_id = "native:zwo:900011";
    let switch_id = "native:qhy:900012";
    let cover_id = "native:player_one:900013";

    register_native_test_device(rotator_id, crate::device::DeviceType::Rotator).await;
    register_native_test_device(switch_id, crate::device::DeviceType::Switch).await;
    register_native_test_device(cover_id, crate::device::DeviceType::CoverCalibrator).await;

    manager
        .native_rotators
        .write()
        .await
        .insert(rotator_id.to_string(), Box::new(FakeNativeRotator));
    manager
        .native_switches
        .write()
        .await
        .insert(switch_id.to_string(), Box::new(FakeNativeSwitch));
    manager
        .native_cover_calibrators
        .write()
        .await
        .insert(cover_id.to_string(), Box::new(FakeNativeCoverCalibrator));

    assert_eq!(
        manager.rotator_get_position(rotator_id).await.unwrap(),
        12.5
    );
    manager
        .rotator_move_absolute(rotator_id, 45.0)
        .await
        .unwrap();
    manager.rotator_halt(rotator_id).await.unwrap();

    assert_eq!(manager.switch_get_max(switch_id).await.unwrap(), 1);
    assert!(manager.switch_get_state(switch_id, 0).await.unwrap());
    assert_eq!(manager.switch_get_value(switch_id, 0).await.unwrap(), 0.75);
    assert!(manager.switch_can_write(switch_id, 0).await.unwrap());
    manager.switch_set_state(switch_id, 0, false).await.unwrap();
    manager.switch_set_value(switch_id, 0, 0.25).await.unwrap();

    manager.cover_calibrator_open_cover(cover_id).await.unwrap();
    manager
        .cover_calibrator_calibrator_on(cover_id, 42)
        .await
        .unwrap();
    let status = manager.cover_calibrator_get_status(cover_id).await.unwrap();
    assert_eq!(status.cover_state, CoverState::Open);
    assert_eq!(status.calibrator_state, CalibratorState::Ready);
    assert_eq!(status.brightness, 42);
    assert_eq!(status.max_brightness, 255);

    manager.native_rotators.write().await.remove(rotator_id);
    manager.native_switches.write().await.remove(switch_id);
    manager
        .native_cover_calibrators
        .write()
        .await
        .remove(cover_id);
    let mut devices = manager.devices.write().await;
    devices.remove(rotator_id);
    devices.remove(switch_id);
    devices.remove(cover_id);
    drop(devices);
    invalidate_capability_cache_for_device(rotator_id).await;
    invalidate_capability_cache_for_device(switch_id).await;
    invalidate_capability_cache_for_device(cover_id).await;
}

// ---------------------------------------------------------------------
// C1: cooler-range / pulse-guide-range / angle-range capability fields
// ---------------------------------------------------------------------

/// Minimal native camera whose SDK exposes a regulated-cooling range but no
/// recommended setpoint — mirrors the ZWO shape that C2 will wire through
/// the real driver. Only the methods `get_native_capabilities` touches need
/// realistic values; the rest return benign defaults.
#[derive(Debug)]
struct FakeRangedCamera;

#[async_trait::async_trait]
impl nightshade_native::traits::NativeDevice for FakeRangedCamera {
    fn id(&self) -> &str {
        "native:zwo:900021"
    }
    fn name(&self) -> &str {
        "Fake Ranged Camera"
    }
    fn vendor(&self) -> nightshade_native::NativeVendor {
        nightshade_native::NativeVendor::Other("Test".to_string())
    }
    fn is_connected(&self) -> bool {
        true
    }
    async fn connect(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }
    async fn disconnect(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }
}

#[async_trait::async_trait]
impl nightshade_native::traits::NativeCamera for FakeRangedCamera {
    fn capabilities(&self) -> nightshade_native::camera::CameraCapabilities {
        nightshade_native::camera::CameraCapabilities {
            can_cool: true,
            ..Default::default()
        }
    }

    async fn get_status(
        &self,
    ) -> Result<nightshade_native::camera::CameraStatus, nightshade_native::traits::NativeError>
    {
        Ok(nightshade_native::camera::CameraStatus {
            state: nightshade_native::camera::CameraState::Idle,
            sensor_temp: Some(-5.0),
            cooler_power: Some(40.0),
            target_temp: Some(-10.0),
            cooler_on: true,
            gain: 100,
            offset: 30,
            bin_x: 1,
            bin_y: 1,
            exposure_remaining: None,
        })
    }

    async fn start_exposure(
        &mut self,
        _params: nightshade_native::camera::ExposureParams,
    ) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }
    async fn abort_exposure(&mut self) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }
    async fn is_exposure_complete(&self) -> Result<bool, nightshade_native::traits::NativeError> {
        Ok(true)
    }
    async fn download_image(
        &mut self,
    ) -> Result<nightshade_native::camera::ImageData, nightshade_native::traits::NativeError> {
        Err(nightshade_native::traits::NativeError::NotSupported)
    }
    async fn set_cooler(
        &mut self,
        _enabled: bool,
        _target_temp: Option<f64>,
    ) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }
    async fn get_temperature(&self) -> Result<f64, nightshade_native::traits::NativeError> {
        Ok(-5.0)
    }
    async fn get_cooler_power(&self) -> Result<f64, nightshade_native::traits::NativeError> {
        Ok(40.0)
    }
    async fn set_gain(&mut self, _gain: i32) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }
    async fn get_gain(&self) -> Result<i32, nightshade_native::traits::NativeError> {
        Ok(100)
    }
    async fn set_offset(
        &mut self,
        _offset: i32,
    ) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }
    async fn get_offset(&self) -> Result<i32, nightshade_native::traits::NativeError> {
        Ok(30)
    }
    async fn set_binning(
        &mut self,
        _bin_x: i32,
        _bin_y: i32,
    ) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }
    async fn get_binning(&self) -> Result<(i32, i32), nightshade_native::traits::NativeError> {
        Ok((1, 1))
    }
    async fn set_subframe(
        &mut self,
        _subframe: Option<nightshade_native::camera::SubFrame>,
    ) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }
    fn get_sensor_info(&self) -> nightshade_native::camera::SensorInfo {
        nightshade_native::camera::SensorInfo {
            width: 6248,
            height: 4176,
            pixel_size_x: 3.76,
            pixel_size_y: 3.76,
            max_adu: 65535,
            bit_depth: 16,
            color: false,
            bayer_pattern: None,
        }
    }
    async fn get_readout_modes(
        &self,
    ) -> Result<Vec<nightshade_native::camera::ReadoutMode>, nightshade_native::traits::NativeError>
    {
        Ok(Vec::new())
    }
    async fn set_readout_mode(
        &mut self,
        _mode: &nightshade_native::camera::ReadoutMode,
    ) -> Result<(), nightshade_native::traits::NativeError> {
        Ok(())
    }
    async fn get_vendor_features(
        &self,
    ) -> Result<nightshade_native::camera::VendorFeatures, nightshade_native::traits::NativeError>
    {
        Ok(nightshade_native::camera::VendorFeatures::default())
    }
    async fn get_gain_range(&self) -> Result<(i32, i32), nightshade_native::traits::NativeError> {
        Ok((0, 600))
    }
    async fn get_offset_range(&self) -> Result<(i32, i32), nightshade_native::traits::NativeError> {
        Ok((0, 255))
    }

    // The seam C1 adds and C2 will override for real ZWO hardware: report a
    // concrete achievable cooling range.
    async fn get_cooler_temp_range(
        &self,
    ) -> Result<Option<(f64, f64)>, nightshade_native::traits::NativeError> {
        Ok(Some((-45.0, 35.0)))
    }
}

#[tokio::test]
async fn native_camera_capabilities_map_cooler_temp_range_from_trait() {
    let device_id = "native:zwo:900021";
    register_native_test_device(device_id, crate::device::DeviceType::Camera).await;
    crate::api::get_device_manager()
        .native_cameras
        .write()
        .await
        .insert(device_id.to_string(), Box::new(FakeRangedCamera));

    let caps = get_device_capabilities(device_id)
        .await
        .expect("native camera capabilities should resolve");

    match caps {
        DeviceCapabilities::Camera(caps) => {
            // The trait override flows through get_native_capabilities into
            // the bridge struct.
            assert_eq!(caps.cooler_min_temp_c, Some(-45.0));
            assert_eq!(caps.cooler_max_temp_c, Some(35.0));
            assert!(caps.can_set_ccd_temperature);
        }
        other => panic!("expected camera capabilities, got {other:?}"),
    }

    crate::api::get_device_manager()
        .native_cameras
        .write()
        .await
        .remove(device_id);
    crate::api::get_device_manager()
        .devices
        .write()
        .await
        .remove(device_id);
    invalidate_capability_cache_for_device(device_id).await;
}

#[test]
fn camera_capabilities_roundtrip_preserves_cooler_range() {
    let caps = CameraCapabilities {
        can_set_ccd_temperature: true,
        cooler_min_temp_c: Some(-40.0),
        cooler_max_temp_c: Some(40.0),
        ..Default::default()
    };
    let json = serde_json::to_string(&caps).expect("serialize");
    let back: CameraCapabilities = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(back.cooler_min_temp_c, Some(-40.0));
    assert_eq!(back.cooler_max_temp_c, Some(40.0));
    assert!(back.can_set_ccd_temperature);
}

#[test]
fn mount_capabilities_roundtrip_preserves_pulse_guide_range() {
    let caps = MountCapabilities {
        can_pulse_guide: true,
        min_pulse_guide_ms: Some(1.0),
        max_pulse_guide_ms: Some(8000.0),
        ..Default::default()
    };
    let json = serde_json::to_string(&caps).expect("serialize");
    let back: MountCapabilities = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(back.min_pulse_guide_ms, Some(1.0));
    assert_eq!(back.max_pulse_guide_ms, Some(8000.0));
    assert!(back.can_pulse_guide);
}

#[test]
fn rotator_capabilities_roundtrip_preserves_angle_range() {
    let caps = RotatorCapabilities {
        can_move_absolute: true,
        min_angle_deg: Some(0.0),
        max_angle_deg: Some(360.0),
        ..Default::default()
    };
    let json = serde_json::to_string(&caps).expect("serialize");
    let back: RotatorCapabilities = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(back.min_angle_deg, Some(0.0));
    assert_eq!(back.max_angle_deg, Some(360.0));
    assert!(back.can_move_absolute);
}

/// Serialize `value`, strip the named keys to simulate a JSON document
/// persisted before those keys existed, and return the re-encoded string.
/// This proves the back-compat contract without hard-coding the (large,
/// evolving) set of pre-existing mandatory fields into each test.
fn json_without_keys<T: Serialize>(value: &T, keys: &[&str]) -> String {
    let mut obj = match serde_json::to_value(value).expect("serialize to value") {
        serde_json::Value::Object(map) => map,
        other => panic!("expected a JSON object, got {other:?}"),
    };
    for key in keys {
        assert!(
            obj.remove(*key).is_some(),
            "expected new field {key} to be present before stripping"
        );
    }
    serde_json::to_string(&obj).expect("re-serialize")
}

#[test]
fn camera_capabilities_backcompat_missing_cooler_range_is_none() {
    // A persisted JSON object from before these fields existed must
    // deserialize cleanly with the new fields as None (back-compat).
    let json = json_without_keys(
        &CameraCapabilities {
            max_width: 4096,
            cooler_min_temp_c: Some(-40.0),
            cooler_max_temp_c: Some(40.0),
            ..Default::default()
        },
        &["cooler_min_temp_c", "cooler_max_temp_c"],
    );
    let caps: CameraCapabilities = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(caps.cooler_min_temp_c, None);
    assert_eq!(caps.cooler_max_temp_c, None);
    assert_eq!(caps.max_width, 4096);
}

#[test]
fn mount_capabilities_backcompat_missing_pulse_range_is_none() {
    let json = json_without_keys(
        &MountCapabilities {
            can_pulse_guide: true,
            min_pulse_guide_ms: Some(1.0),
            max_pulse_guide_ms: Some(8000.0),
            ..Default::default()
        },
        &["min_pulse_guide_ms", "max_pulse_guide_ms"],
    );
    let caps: MountCapabilities = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(caps.min_pulse_guide_ms, None);
    assert_eq!(caps.max_pulse_guide_ms, None);
    assert!(caps.can_pulse_guide);
}

#[test]
fn rotator_capabilities_backcompat_missing_angle_range_is_none() {
    let json = json_without_keys(
        &RotatorCapabilities {
            can_move_absolute: true,
            min_angle_deg: Some(0.0),
            max_angle_deg: Some(360.0),
            ..Default::default()
        },
        &["min_angle_deg", "max_angle_deg"],
    );
    let caps: RotatorCapabilities = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(caps.min_angle_deg, None);
    assert_eq!(caps.max_angle_deg, None);
    assert!(caps.can_move_absolute);
}

#[test]
fn recommended_settings_from_native_maps_cooling_setpoint() {
    let native = nightshade_native::camera::CameraRecommendedSettings {
        unity_gain: Some(100),
        hcg_gain: None,
        default_offset: Some(30),
        recommended_cooling_setpoint_c: Some(-10.0),
        notes: "test".to_string(),
    };
    let bridge: CameraRecommendedSettings = native.into();
    assert_eq!(bridge.unity_gain, Some(100));
    assert_eq!(bridge.default_offset, Some(30));
    assert_eq!(bridge.recommended_cooling_setpoint_c, Some(-10.0));
    assert_eq!(bridge.notes, "test");
}
