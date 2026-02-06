//! Native Driver Tests
//!
//! Tests for the native driver implementations.
//! Some tests require hardware to be connected, others can run without hardware.

use nightshade_native::traits::{
    NativeCamera, NativeDevice, NativeFilterWheel, NativeFocuser, NativeMount,
};
use nightshade_native::vendor::ioptron;
use nightshade_native::vendor::lx200;
use nightshade_native::vendor::qhy;
use nightshade_native::vendor::skywatcher;
use nightshade_native::vendor::svbony;
use nightshade_native::vendor::zwo;

// =============================================================================
// SDK LOADING TESTS (No Hardware Required)
// =============================================================================

/// Test that ZWO ASI Camera SDK status can be checked
#[test]
fn test_zwo_camera_sdk_status() {
    let (available, message) = zwo::get_sdk_status();
    println!(
        "ZWO Camera SDK: available={}, message={}",
        available, message
    );
    // We don't assert availability since SDK may not be installed
    assert!(!message.is_empty());
}

/// Test that ZWO EAF SDK status can be checked
#[test]
fn test_zwo_eaf_sdk_status() {
    let (available, message) = zwo::get_eaf_sdk_status();
    println!("ZWO EAF SDK: available={}, message={}", available, message);
    assert!(!message.is_empty());
}

/// Test that ZWO EFW SDK status can be checked
#[test]
fn test_zwo_efw_sdk_status() {
    let (available, message) = zwo::get_efw_sdk_status();
    println!("ZWO EFW SDK: available={}, message={}", available, message);
    assert!(!message.is_empty());
}

/// Test that SVBony Camera SDK status can be checked
#[test]
fn test_svbony_camera_sdk_status() {
    let (available, message) = svbony::get_sdk_status();
    println!(
        "SVBony Camera SDK: available={}, message={}",
        available, message
    );
    // We don't assert availability since SDK may not be installed
    assert!(!message.is_empty());
}

// =============================================================================
// DISCOVERY TESTS (No Hardware Required - Returns Empty If No Devices)
// =============================================================================

/// Test that camera discovery doesn't crash even without hardware
#[tokio::test]
async fn test_zwo_camera_discovery_no_crash() {
    let result = zwo::discover_devices().await;
    assert!(
        result.is_ok(),
        "Discovery should not error even without devices"
    );
    let devices = result.unwrap();
    println!("Found {} ZWO cameras", devices.len());
    for dev in &devices {
        println!(
            "  - {} (ID: {}, index: {})",
            dev.name, dev.camera_id, dev.discovery_index
        );
    }
}

/// Test that focuser discovery doesn't crash even without hardware
#[tokio::test]
async fn test_zwo_focuser_discovery_no_crash() {
    let result = zwo::discover_focusers().await;
    assert!(
        result.is_ok(),
        "Discovery should not error even without devices"
    );
    let devices = result.unwrap();
    println!("Found {} ZWO EAF focusers", devices.len());
    for dev in &devices {
        println!(
            "  - {} (ID: {}, SN: {:?})",
            dev.name, dev.focuser_id, dev.serial_number
        );
    }
}

/// Test that filter wheel discovery doesn't crash even without hardware
#[tokio::test]
async fn test_zwo_filter_wheel_discovery_no_crash() {
    let result = zwo::discover_filter_wheels().await;
    assert!(
        result.is_ok(),
        "Discovery should not error even without devices"
    );
    let devices = result.unwrap();
    println!("Found {} ZWO EFW filter wheels", devices.len());
    for dev in &devices {
        println!(
            "  - {} (ID: {}, slots: {}, SN: {:?})",
            dev.name, dev.filterwheel_id, dev.slot_count, dev.serial_number
        );
    }
}

/// Test that SVBony camera discovery doesn't crash even without hardware
#[tokio::test]
async fn test_svbony_camera_discovery_no_crash() {
    let result = svbony::discover_devices().await;
    assert!(
        result.is_ok(),
        "Discovery should not error even without devices"
    );
    let devices = result.unwrap();
    println!("Found {} SVBony cameras", devices.len());
    for dev in &devices {
        println!(
            "  - {} (ID: {}, SN: {:?}, index: {})",
            dev.name, dev.camera_id, dev.serial_number, dev.discovery_index
        );
    }
}

// =============================================================================
// HARDWARE INTEGRATION TESTS (Require ZWO Devices Connected)
// =============================================================================
// These tests are ignored by default and can be run with:
// cargo test --test native_driver_tests -- --ignored

/// Test connecting to a ZWO camera (requires hardware)
#[tokio::test]
#[ignore = "Requires ZWO camera connected"]
async fn test_zwo_camera_connect_disconnect() {
    let devices = zwo::discover_devices()
        .await
        .expect("Discovery should work");
    if devices.is_empty() {
        panic!("No ZWO cameras found - connect a camera to run this test");
    }

    let first_device = &devices[0];
    println!(
        "Testing with camera: {} (ID: {})",
        first_device.name, first_device.camera_id
    );

    let mut camera = zwo::ZwoCamera::new(first_device.camera_id);

    // Connect
    camera.connect().await.expect("Should connect successfully");
    assert!(camera.is_connected(), "Should be connected");

    // Get device info
    let name = camera.name();
    let vendor = camera.vendor();
    println!("Connected to: {} ({})", name, vendor.as_str());

    // Disconnect
    camera
        .disconnect()
        .await
        .expect("Should disconnect successfully");
    assert!(!camera.is_connected(), "Should be disconnected");
}

/// Test ZWO EAF focuser operations (requires hardware)
#[tokio::test]
#[ignore = "Requires ZWO EAF focuser connected"]
async fn test_zwo_focuser_operations() {
    let devices = zwo::discover_focusers()
        .await
        .expect("Discovery should work");
    if devices.is_empty() {
        panic!("No ZWO EAF focusers found - connect a focuser to run this test");
    }

    let first_device = &devices[0];
    println!(
        "Testing with focuser: {} (ID: {})",
        first_device.name, first_device.focuser_id
    );

    let mut focuser = zwo::ZwoFocuser::new(first_device.focuser_id);

    // Connect
    focuser
        .connect()
        .await
        .expect("Should connect successfully");
    assert!(focuser.is_connected(), "Should be connected");

    // Get position
    let position = focuser.get_position().await.expect("Should get position");
    println!("Current position: {}", position);

    // Get temperature
    let temp = focuser
        .get_temperature()
        .await
        .expect("Should get temperature");
    println!("Temperature: {:?}", temp);

    // Test movement (move 100 steps and back)
    let target = position + 100;
    let max_pos = focuser.get_max_position();
    if target < max_pos {
        println!("Moving to position {}...", target);
        focuser.move_to(target).await.expect("Should move");

        // Wait for movement to complete
        while focuser.is_moving().await.unwrap_or(false) {
            tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
        }

        let new_position = focuser.get_position().await.expect("Should get position");
        println!("New position: {}", new_position);
        assert!(
            (new_position - target).abs() <= 5,
            "Should be at target position (within tolerance)"
        );

        // Move back
        println!("Moving back to position {}...", position);
        focuser.move_to(position).await.expect("Should move back");
        while focuser.is_moving().await.unwrap_or(false) {
            tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
        }
    } else {
        println!(
            "Skipping movement test - position {} would exceed max {}",
            target, max_pos
        );
    }

    // Disconnect
    focuser
        .disconnect()
        .await
        .expect("Should disconnect successfully");
}

/// Test ZWO EFW filter wheel operations (requires hardware)
#[tokio::test]
#[ignore = "Requires ZWO EFW filter wheel connected"]
async fn test_zwo_filter_wheel_operations() {
    let devices = zwo::discover_filter_wheels()
        .await
        .expect("Discovery should work");
    if devices.is_empty() {
        panic!("No ZWO EFW filter wheels found - connect a filter wheel to run this test");
    }

    let first_device = &devices[0];
    println!(
        "Testing with filter wheel: {} (ID: {}, {} slots)",
        first_device.name, first_device.filterwheel_id, first_device.slot_count
    );

    let mut fw = zwo::ZwoFilterWheel::new(first_device.filterwheel_id);

    // Connect
    fw.connect().await.expect("Should connect successfully");
    assert!(fw.is_connected(), "Should be connected");

    // Get current position
    let position = fw.get_position().await.expect("Should get position");
    println!("Current position: {}", position);

    // Get filter names
    let names = fw
        .get_filter_names()
        .await
        .expect("Should get filter names");
    println!("Filter names: {:?}", names);

    // Get filter count
    let count = fw.get_filter_count();
    println!("Filter count: {}", count);
    assert!(count > 0, "Should have at least one filter slot");

    // Test movement to next position (with wraparound)
    let target = (position + 1) % count;
    println!("Moving to position {}...", target);
    fw.move_to_position(target).await.expect("Should move");

    // Wait for movement to complete
    while fw.is_moving().await.unwrap_or(false) {
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    }

    let new_position = fw.get_position().await.expect("Should get position");
    println!("New position: {}", new_position);
    assert_eq!(new_position, target, "Should be at target position");

    // Move back to original position
    println!("Moving back to position {}...", position);
    fw.move_to_position(position)
        .await
        .expect("Should move back");
    while fw.is_moving().await.unwrap_or(false) {
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    }

    // Disconnect
    fw.disconnect()
        .await
        .expect("Should disconnect successfully");
}

// =============================================================================
// SVBONY HARDWARE INTEGRATION TESTS (Require SVBony Devices Connected)
// =============================================================================
// These tests are ignored by default and can be run with:
// cargo test --test native_driver_tests -- --ignored

/// Test connecting to a SVBony camera (requires hardware)
#[tokio::test]
#[ignore = "Requires SVBony camera connected"]
async fn test_svbony_camera_connect_disconnect() {
    let devices = svbony::discover_devices()
        .await
        .expect("Discovery should work");
    if devices.is_empty() {
        panic!("No SVBony cameras found - connect a camera to run this test");
    }

    let first_device = &devices[0];
    println!(
        "Testing with camera: {} (ID: {})",
        first_device.name, first_device.camera_id
    );

    let mut camera = svbony::SvbonyCamera::new(first_device.camera_id);

    // Connect
    camera.connect().await.expect("Should connect successfully");
    assert!(camera.is_connected(), "Should be connected");

    // Get device info
    let name = camera.name();
    let vendor = camera.vendor();
    println!("Connected to: {} ({})", name, vendor.as_str());

    // Get capabilities
    let caps = camera.capabilities();
    println!(
        "Capabilities: can_cool={}, can_set_gain={}, max_bin={}x{}",
        caps.can_cool, caps.can_set_gain, caps.max_bin_x, caps.max_bin_y
    );

    // Get sensor info
    let sensor = camera.get_sensor_info();
    println!(
        "Sensor: {}x{}, {}-bit, color={}, pixel size={:.2}um",
        sensor.width, sensor.height, sensor.bit_depth, sensor.color, sensor.pixel_size_x
    );

    // Disconnect
    camera
        .disconnect()
        .await
        .expect("Should disconnect successfully");
    assert!(!camera.is_connected(), "Should be disconnected");
}

/// Test SVBony camera exposure (requires hardware)
#[tokio::test]
#[ignore = "Requires SVBony camera connected"]
async fn test_svbony_camera_exposure() {
    use nightshade_native::camera::ExposureParams;

    let devices = svbony::discover_devices()
        .await
        .expect("Discovery should work");
    if devices.is_empty() {
        panic!("No SVBony cameras found - connect a camera to run this test");
    }

    let first_device = &devices[0];
    let mut camera = svbony::SvbonyCamera::new(first_device.camera_id);

    // Connect
    camera.connect().await.expect("Should connect successfully");

    // Take a short exposure
    let params = ExposureParams {
        duration_secs: 0.1, // 100ms exposure
        gain: Some(100),
        offset: Some(10),
        bin_x: 1,
        bin_y: 1,
        subframe: None,
        readout_mode: None,
    };

    println!("Starting 0.1s exposure...");
    camera
        .start_exposure(params)
        .await
        .expect("Should start exposure");

    // Wait for exposure to complete
    while !camera.is_exposure_complete().await.unwrap_or(true) {
        tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
    }

    println!("Downloading image...");
    let image = camera
        .download_image()
        .await
        .expect("Should download image");
    println!(
        "Image: {}x{}, {}-bit, {} pixels",
        image.width,
        image.height,
        image.bits_per_pixel,
        image.data.len()
    );

    // Verify metadata
    assert!(
        image.metadata.exposure_time > 0.0,
        "Should have exposure time"
    );
    println!(
        "Metadata: exposure={:.3}s, gain={}, offset={}",
        image.metadata.exposure_time, image.metadata.gain, image.metadata.offset
    );

    // Disconnect
    camera
        .disconnect()
        .await
        .expect("Should disconnect successfully");
}

// =============================================================================
// QHY CFW FILTER WHEEL TESTS
// =============================================================================

/// Test that QHY CFW discovery doesn't crash even without hardware
#[tokio::test]
async fn test_qhy_cfw_discovery_no_crash() {
    let result = qhy::discover_filter_wheels().await;
    // QHY filter wheel discovery requires opening cameras, so may fail if SDK not installed
    // We just ensure it doesn't panic
    match result {
        Ok(devices) => {
            println!("Found {} QHY CFW filter wheels", devices.len());
            for dev in &devices {
                println!(
                    "  - {} (camera: {}, {} slots)",
                    dev.name, dev.camera_id, dev.slot_count
                );
            }
        }
        Err(e) => {
            println!(
                "QHY CFW discovery returned error (SDK may not be installed): {}",
                e
            );
        }
    }
}

/// Test QHY CFW filter wheel operations (requires hardware)
#[tokio::test]
#[ignore = "Requires QHY camera with CFW connected"]
async fn test_qhy_cfw_operations() {
    let devices = qhy::discover_filter_wheels()
        .await
        .expect("Discovery should work");
    if devices.is_empty() {
        panic!("No QHY CFW filter wheels found - connect a QHY camera with CFW to run this test");
    }

    let first_device = &devices[0];
    println!(
        "Testing with filter wheel: {} (camera: {}, {} slots)",
        first_device.name, first_device.camera_id, first_device.slot_count
    );

    let mut fw = qhy::QhyFilterWheel::new(first_device.camera_id.clone());

    // Connect
    fw.connect().await.expect("Should connect successfully");
    assert!(fw.is_connected(), "Should be connected");

    // Get current position
    let position = fw.get_position().await.expect("Should get position");
    println!("Current position: {}", position);

    // Get filter count
    let count = fw.get_filter_count();
    println!("Filter count: {}", count);
    assert!(count > 0, "Should have at least one filter slot");

    // Get filter names
    let names = fw
        .get_filter_names()
        .await
        .expect("Should get filter names");
    println!("Filter names: {:?}", names);

    // Test movement to next position (with wraparound)
    let target = (position + 1) % count;
    println!("Moving to position {}...", target);
    fw.move_to_position(target).await.expect("Should move");

    let new_position = fw.get_position().await.expect("Should get position");
    println!("New position: {}", new_position);
    assert_eq!(new_position, target, "Should be at target position");

    // Move back to original position
    println!("Moving back to position {}...", position);
    fw.move_to_position(position)
        .await
        .expect("Should move back");

    // Disconnect
    fw.disconnect()
        .await
        .expect("Should disconnect successfully");
}

// =============================================================================
// UNIFIED DISCOVERY TEST
// =============================================================================

/// Test that the unified discovery finds all device types
#[tokio::test]
async fn test_unified_discovery() {
    use nightshade_native::discovery::{discover_all_devices, DeviceType};

    let devices = discover_all_devices().await.expect("Discovery should work");
    println!("Unified discovery found {} total devices:", devices.len());

    let cameras: Vec<_> = devices
        .iter()
        .filter(|d| d.device_type == DeviceType::Camera)
        .collect();
    let focusers: Vec<_> = devices
        .iter()
        .filter(|d| d.device_type == DeviceType::Focuser)
        .collect();
    let filter_wheels: Vec<_> = devices
        .iter()
        .filter(|d| d.device_type == DeviceType::FilterWheel)
        .collect();

    println!("  Cameras: {}", cameras.len());
    println!("  Focusers: {}", focusers.len());
    println!("  Filter Wheels: {}", filter_wheels.len());

    for dev in &devices {
        println!(
            "  - {} ({:?}, {})",
            dev.display_name,
            dev.device_type,
            dev.vendor.as_str()
        );
    }
}

// =============================================================================
// MOUNT DISCOVERY TESTS (No Hardware Required - Scans Serial Ports)
// =============================================================================

/// Test that Sky-Watcher mount discovery doesn't crash
#[tokio::test]
async fn test_skywatcher_mount_discovery_no_crash() {
    let result = skywatcher::discover_mounts().await;
    assert!(
        result.is_ok(),
        "Discovery should not error even without devices"
    );
    let mounts = result.unwrap();
    println!("Found {} Sky-Watcher mounts:", mounts.len());
    for mount in &mounts {
        println!("  - {} (port: {})", mount.name, mount.port);
    }
}

/// Test that iOptron mount discovery doesn't crash
#[tokio::test]
async fn test_ioptron_mount_discovery_no_crash() {
    let result = ioptron::discover_mounts().await;
    assert!(
        result.is_ok(),
        "Discovery should not error even without devices"
    );
    let mounts = result.unwrap();
    println!("Found {} iOptron mounts:", mounts.len());
    for mount in &mounts {
        println!("  - {} (port: {})", mount.name, mount.port);
    }
}

/// Test that LX200 mount discovery doesn't crash
#[tokio::test]
async fn test_lx200_mount_discovery_no_crash() {
    let result = lx200::discover_mounts().await;
    assert!(
        result.is_ok(),
        "Discovery should not error even without devices"
    );
    let mounts = result.unwrap();
    println!("Found {} LX200-compatible mounts:", mounts.len());
    for mount in &mounts {
        println!(
            "  - {} (port: {}, type: {:?})",
            mount.name, mount.port, mount.mount_type
        );
    }
}

/// Test that unified discovery includes mounts
#[tokio::test]
async fn test_unified_discovery_includes_mounts() {
    use nightshade_native::discovery::{discover_all_devices, DeviceType};

    let devices = discover_all_devices().await.expect("Discovery should work");
    let mounts: Vec<_> = devices
        .iter()
        .filter(|d| d.device_type == DeviceType::Mount)
        .collect();

    println!("Unified discovery found {} mounts:", mounts.len());
    for mount in &mounts {
        println!(
            "  - {} ({}, id: {})",
            mount.display_name,
            mount.vendor.as_str(),
            mount.id
        );
    }
}

// =============================================================================
// MOUNT HARDWARE INTEGRATION TESTS (Require Mounts Connected)
// =============================================================================
// These tests are ignored by default and can be run with:
// cargo test --test native_driver_tests -- --ignored

/// Test connecting to a Sky-Watcher mount (requires hardware)
#[tokio::test]
#[ignore = "Requires Sky-Watcher mount connected"]
async fn test_skywatcher_mount_connect_disconnect() {
    let mounts = skywatcher::discover_mounts()
        .await
        .expect("Discovery should work");
    if mounts.is_empty() {
        panic!("No Sky-Watcher mounts found - connect a mount to run this test");
    }

    let first_mount = &mounts[0];
    println!(
        "Testing with mount: {} (port: {})",
        first_mount.name, first_mount.port
    );

    let mut mount = skywatcher::SkyWatcherMount::new_serial(first_mount.port.clone(), Some(9600));

    // Connect
    mount.connect().await.expect("Should connect successfully");
    assert!(mount.is_connected(), "Should be connected");

    // Get device info
    let name = mount.name();
    let vendor = mount.vendor();
    println!("Connected to: {} ({})", name, vendor.as_str());

    // Get coordinates
    match mount.get_coordinates().await {
        Ok((ra, dec)) => println!("Current position: RA={:.4}h, Dec={:.4}°", ra, dec),
        Err(e) => println!("Could not get coordinates: {}", e),
    }

    // Get mount status using individual methods
    match mount.get_tracking().await {
        Ok(tracking) => println!("Tracking: {}", tracking),
        Err(e) => println!("Could not get tracking: {}", e),
    }
    match mount.is_slewing().await {
        Ok(slewing) => println!("Slewing: {}", slewing),
        Err(e) => println!("Could not get slewing: {}", e),
    }
    match mount.is_parked().await {
        Ok(parked) => println!("Parked: {}", parked),
        Err(e) => println!("Could not get parked: {}", e),
    }

    // Disconnect
    mount
        .disconnect()
        .await
        .expect("Should disconnect successfully");
    assert!(!mount.is_connected(), "Should be disconnected");
}

/// Test connecting to an iOptron mount (requires hardware)
#[tokio::test]
#[ignore = "Requires iOptron mount connected"]
async fn test_ioptron_mount_connect_disconnect() {
    let mounts = ioptron::discover_mounts()
        .await
        .expect("Discovery should work");
    if mounts.is_empty() {
        panic!("No iOptron mounts found - connect a mount to run this test");
    }

    let first_mount = &mounts[0];
    println!(
        "Testing with mount: {} (port: {})",
        first_mount.name, first_mount.port
    );

    let mut mount = ioptron::IOptronMount::new(
        first_mount.port.clone(),
        None, // Use default baud rate
    );

    // Connect
    mount.connect().await.expect("Should connect successfully");
    assert!(mount.is_connected(), "Should be connected");

    // Get device info
    let name = mount.name();
    let vendor = mount.vendor();
    println!("Connected to: {} ({})", name, vendor.as_str());

    // Get coordinates
    match mount.get_coordinates().await {
        Ok((ra, dec)) => println!("Current position: RA={:.4}h, Dec={:.4}°", ra, dec),
        Err(e) => println!("Could not get coordinates: {}", e),
    }

    // Check tracking status
    match mount.get_tracking().await {
        Ok(tracking) => println!("Tracking: {}", tracking),
        Err(e) => println!("Could not get tracking status: {}", e),
    }

    // Disconnect
    mount
        .disconnect()
        .await
        .expect("Should disconnect successfully");
    assert!(!mount.is_connected(), "Should be disconnected");
}

/// Test connecting to an LX200-compatible mount (requires hardware)
#[tokio::test]
#[ignore = "Requires LX200-compatible mount connected"]
async fn test_lx200_mount_connect_disconnect() {
    let mounts = lx200::discover_mounts()
        .await
        .expect("Discovery should work");
    if mounts.is_empty() {
        panic!("No LX200-compatible mounts found - connect a mount to run this test");
    }

    let first_mount = &mounts[0];
    println!(
        "Testing with mount: {} (port: {}, type: {:?})",
        first_mount.name, first_mount.port, first_mount.mount_type
    );

    let mut mount = lx200::Lx200Mount::new(
        first_mount.port.clone(),
        first_mount.mount_type.clone(),
        None, // Use default baud rate
    );

    // Connect
    mount.connect().await.expect("Should connect successfully");
    assert!(mount.is_connected(), "Should be connected");

    // Get device info
    let name = mount.name();
    let vendor = mount.vendor();
    println!("Connected to: {} ({})", name, vendor.as_str());

    // Get coordinates
    match mount.get_coordinates().await {
        Ok((ra, dec)) => println!("Current position: RA={:.4}h, Dec={:.4}°", ra, dec),
        Err(e) => println!("Could not get coordinates: {}", e),
    }

    // Check tracking status
    match mount.get_tracking().await {
        Ok(tracking) => println!("Tracking: {}", tracking),
        Err(e) => println!("Could not get tracking status: {}", e),
    }

    // Disconnect
    mount
        .disconnect()
        .await
        .expect("Should disconnect successfully");
    assert!(!mount.is_connected(), "Should be disconnected");
}

/// Test Sky-Watcher mount slewing (requires hardware)
#[tokio::test]
#[ignore = "Requires Sky-Watcher mount connected - WILL MOVE MOUNT"]
async fn test_skywatcher_mount_slew() {
    let mounts = skywatcher::discover_mounts()
        .await
        .expect("Discovery should work");
    if mounts.is_empty() {
        panic!("No Sky-Watcher mounts found - connect a mount to run this test");
    }

    let first_mount = &mounts[0];
    let mut mount = skywatcher::SkyWatcherMount::new_serial(first_mount.port.clone(), Some(9600));

    mount.connect().await.expect("Should connect successfully");

    // Get current position
    let (start_ra, start_dec) = mount
        .get_coordinates()
        .await
        .expect("Should get coordinates");
    println!("Start position: RA={:.4}h, Dec={:.4}°", start_ra, start_dec);

    // Slew to a nearby position (add 0.01 hours to RA)
    let target_ra = start_ra + 0.01;
    let target_dec = start_dec;
    println!("Slewing to: RA={:.4}h, Dec={:.4}°", target_ra, target_dec);

    mount
        .slew_to_coordinates(target_ra, target_dec)
        .await
        .expect("Should start slew");

    // Wait for slew to complete (with timeout)
    let start = std::time::Instant::now();
    let timeout = std::time::Duration::from_secs(30);
    loop {
        if start.elapsed() > timeout {
            println!("Slew timeout - aborting");
            mount.abort_slew().await.ok();
            break;
        }
        let is_slewing = mount.is_slewing().await.unwrap_or(false);
        if !is_slewing {
            break;
        }
        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
    }

    // Get final position
    let (end_ra, end_dec) = mount
        .get_coordinates()
        .await
        .expect("Should get coordinates");
    println!("End position: RA={:.4}h, Dec={:.4}°", end_ra, end_dec);

    mount
        .disconnect()
        .await
        .expect("Should disconnect successfully");
}

/// Test mount tracking control (requires hardware)
#[tokio::test]
#[ignore = "Requires Sky-Watcher mount connected"]
async fn test_skywatcher_mount_tracking() {
    let mounts = skywatcher::discover_mounts()
        .await
        .expect("Discovery should work");
    if mounts.is_empty() {
        panic!("No Sky-Watcher mounts found");
    }

    let first_mount = &mounts[0];
    let mut mount = skywatcher::SkyWatcherMount::new_serial(first_mount.port.clone(), Some(9600));

    mount.connect().await.expect("Should connect successfully");

    // Get initial tracking state
    let tracking = mount.get_tracking().await.expect("Should get tracking");
    println!("Initial tracking state: {}", tracking);

    // Toggle tracking off
    mount
        .set_tracking(false)
        .await
        .expect("Should stop tracking");
    tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
    let tracking = mount.get_tracking().await.expect("Should get tracking");
    println!("After stop: tracking={}", tracking);

    // Toggle tracking on (sidereal)
    mount
        .set_tracking(true)
        .await
        .expect("Should start tracking");
    tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
    let tracking = mount.get_tracking().await.expect("Should get tracking");
    println!("After start: tracking={}", tracking);

    mount
        .disconnect()
        .await
        .expect("Should disconnect successfully");
}
