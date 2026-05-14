//! Native Driver Tests
//!
//! Tests for the native driver implementations.
//! Some tests require hardware to be connected, others can run without hardware.

use nightshade_native::traits::{
    NativeCamera, NativeDevice, NativeFilterWheel, NativeFocuser, NativeMount,
};
use nightshade_native::vendor::atik;
use nightshade_native::vendor::ioptron;
use nightshade_native::vendor::lx200;
use nightshade_native::vendor::player_one;
use nightshade_native::vendor::qhy;
use nightshade_native::vendor::skywatcher;
use nightshade_native::vendor::svbony;
use nightshade_native::vendor::zwo;
use nightshade_native::ExposureParams;

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

#[cfg(windows)]
mod fake_sdk_contract {
    use super::*;
    use std::env;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::process::Command;

    #[tokio::test]
    #[ignore = "software-only fake SDK contract; run explicitly from compatibility matrix"]
    async fn test_fake_sdk_shims_exercise_camera_focuser_filterwheel() {
        let shim_dir = build_fake_sdks();
        let old_dir = env::current_dir().expect("read current dir");
        let old_path = env::var("PATH").unwrap_or_default();
        env::set_current_dir(&shim_dir).expect("switch to fake SDK dir");
        env::set_var("PATH", format!("{};{}", shim_dir.display(), old_path));

        let cameras = zwo::discover_devices().await.expect("camera discovery");
        assert_eq!(cameras.len(), 1);
        assert_eq!(cameras[0].name, "Nightshade Fake ASI2600MM Pro");

        let mut camera = zwo::ZwoCamera::new(cameras[0].camera_id);
        camera.connect().await.expect("camera connect");
        assert!(camera.is_connected());
        assert!(camera.capabilities().can_cool);
        camera.set_gain(42).await.expect("set gain");
        camera.set_offset(8).await.expect("set offset");
        camera.set_binning(2, 2).await.expect("set binning");
        camera.set_cooler(true, -12.0).await.expect("set cooler");
        let status = camera.get_status().await.expect("camera status");
        assert!(status.cooler_on);
        assert_eq!(status.gain, 42);
        assert_eq!(status.offset, 8);
        camera
            .start_exposure(ExposureParams {
                duration_secs: 0.01,
                gain: Some(55),
                offset: Some(9),
                bin_x: 2,
                bin_y: 2,
                subframe: None,
                readout_mode: None,
            })
            .await
            .expect("start exposure");
        assert!(camera
            .is_exposure_complete()
            .await
            .expect("exposure complete"));
        let image = camera.download_image().await.expect("download image");
        assert_eq!((image.width, image.height), (32, 24));
        assert_eq!(image.bits_per_pixel, 16);
        assert_eq!(image.data[0], 1000);
        camera.abort_exposure().await.expect("abort exposure");
        camera.disconnect().await.expect("camera disconnect");

        let focusers = zwo::discover_focusers().await.expect("focuser discovery");
        assert_eq!(focusers.len(), 1);
        let mut focuser = zwo::ZwoFocuser::new(focusers[0].focuser_id);
        focuser.connect().await.expect("focuser connect");
        assert_eq!(focuser.get_max_position(), 60_000);
        focuser.move_to(12_345).await.expect("focuser move");
        assert_eq!(
            focuser.get_position().await.expect("focuser position"),
            12_345
        );
        assert!(!focuser.is_moving().await.expect("focuser moving"));
        assert_eq!(
            focuser.get_temperature().await.expect("focuser temp"),
            Some(21.5)
        );
        focuser.halt().await.expect("focuser halt");
        focuser.disconnect().await.expect("focuser disconnect");

        let wheels = zwo::discover_filter_wheels()
            .await
            .expect("filter wheel discovery");
        assert_eq!(wheels.len(), 1);
        let mut wheel = zwo::ZwoFilterWheel::new(wheels[0].filterwheel_id);
        wheel.connect().await.expect("filter wheel connect");
        assert_eq!(wheel.get_filter_count(), 7);
        wheel.move_to_position(3).await.expect("move filter");
        assert_eq!(wheel.get_position().await.expect("moved filter"), 3);
        wheel.disconnect().await.expect("filter wheel disconnect");

        env::set_current_dir(old_dir).expect("restore current dir");
        env::set_var("PATH", old_path);
    }

    #[tokio::test]
    #[ignore = "software-only fake SDK contract; run explicitly from compatibility matrix"]
    async fn test_atik_fake_sdk_shim_exercises_camera_flow() {
        let shim_dir =
            build_single_fake_sdk("atik", "atik_fake.rs", "AtikCameras.dll", ATIK_FAKE_SDK);
        let old_dir = env::current_dir().expect("read current dir");
        let old_path = env::var("PATH").unwrap_or_default();
        env::set_current_dir(&shim_dir).expect("switch to fake SDK dir");
        env::set_var("PATH", format!("{};{}", shim_dir.display(), old_path));

        let devices = atik::discover_devices().await.expect("Atik discovery");
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].name, "Nightshade Fake Atik Horizon II");

        let mut camera = atik::AtikCamera::new(devices[0].device_index);
        camera.connect().await.expect("Atik connect");
        assert!(camera.is_connected());
        assert!(camera.capabilities().can_cool);
        camera.set_gain(17).await.expect("Atik set gain");
        camera.set_offset(4).await.expect("Atik set offset");
        camera.set_binning(2, 2).await.expect("Atik set binning");
        camera
            .set_cooler(true, -10.0)
            .await
            .expect("Atik set cooler");
        assert!(camera
            .is_exposure_complete()
            .await
            .expect("Atik initial ready"));
        camera
            .start_exposure(ExposureParams {
                duration_secs: 0.01,
                gain: Some(21),
                offset: Some(5),
                bin_x: 2,
                bin_y: 2,
                subframe: None,
                readout_mode: None,
            })
            .await
            .expect("Atik start exposure");
        assert!(camera
            .is_exposure_complete()
            .await
            .expect("Atik exposure complete"));
        let image = camera.download_image().await.expect("Atik image download");
        assert_eq!((image.width, image.height), (16, 12));
        assert_eq!(image.bits_per_pixel, 16);
        assert_eq!(image.data[0], 2000);
        camera.abort_exposure().await.expect("Atik abort");
        camera.disconnect().await.expect("Atik disconnect");

        env::set_current_dir(old_dir).expect("restore current dir");
        env::set_var("PATH", old_path);
    }

    #[tokio::test]
    #[ignore = "software-only fake SDK contract; run explicitly from compatibility matrix"]
    async fn test_svbony_fake_sdk_shim_exercises_camera_flow() {
        let shim_dir = build_single_fake_sdk(
            "svbony",
            "svbony_fake.rs",
            "SVBCameraSDK.dll",
            SVBONY_FAKE_SDK,
        );
        let old_dir = env::current_dir().expect("read current dir");
        let old_path = env::var("PATH").unwrap_or_default();
        env::set_current_dir(&shim_dir).expect("switch to fake SDK dir");
        env::set_var("PATH", format!("{};{}", shim_dir.display(), old_path));

        let devices = svbony::discover_devices().await.expect("SVBONY discovery");
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].name, "Fake SV605CC");

        let mut camera = svbony::SvbonyCamera::new(devices[0].camera_id);
        camera.connect().await.expect("SVBONY connect");
        assert!(camera.is_connected());
        assert!(camera.capabilities().can_cool);
        camera.set_gain(33).await.expect("SVBONY set gain");
        camera.set_offset(6).await.expect("SVBONY set offset");
        camera.set_binning(2, 2).await.expect("SVBONY set binning");
        camera
            .set_cooler(true, -8.0)
            .await
            .expect("SVBONY set cooler");
        camera
            .start_exposure(ExposureParams {
                duration_secs: 0.0,
                gain: Some(44),
                offset: Some(7),
                bin_x: 2,
                bin_y: 2,
                subframe: None,
                readout_mode: None,
            })
            .await
            .expect("SVBONY start exposure");
        assert!(camera
            .is_exposure_complete()
            .await
            .expect("SVBONY exposure complete"));
        let image = camera
            .download_image()
            .await
            .expect("SVBONY image download");
        assert_eq!((image.width, image.height), (20, 15));
        assert_eq!(image.bits_per_pixel, 16);
        assert_eq!(image.data[0], 3000);
        camera.abort_exposure().await.expect("SVBONY abort");
        camera.disconnect().await.expect("SVBONY disconnect");

        env::set_current_dir(old_dir).expect("restore current dir");
        env::set_var("PATH", old_path);
    }

    #[tokio::test]
    #[ignore = "software-only fake SDK contract; run explicitly from compatibility matrix"]
    async fn test_player_one_fake_sdk_shim_exercises_model_and_edge_flows() {
        let shim_dir = build_single_fake_sdk(
            "player-one",
            "player_one_fake.rs",
            "PlayerOneCamera.dll",
            PLAYER_ONE_FAKE_SDK,
        );
        let old_dir = env::current_dir().expect("read current dir");
        let old_path = env::var("PATH").unwrap_or_default();
        let old_not_ready = env::var("NS_POA_NOT_READY").ok();
        let old_start_error = env::var("NS_POA_START_ERROR").ok();
        let old_image_error = env::var("NS_POA_IMAGE_ERROR").ok();
        env::set_current_dir(&shim_dir).expect("switch to fake SDK dir");
        env::set_var("PATH", format!("{};{}", shim_dir.display(), old_path));
        env::remove_var("NS_POA_NOT_READY");
        env::remove_var("NS_POA_START_ERROR");
        env::remove_var("NS_POA_IMAGE_ERROR");

        let devices = player_one::discover_devices()
            .await
            .expect("Player One discovery");
        assert_eq!(devices.len(), 2);
        assert_eq!(devices[0].name, "Nightshade Fake Poseidon-M Pro");
        assert_eq!(devices[1].name, "Nightshade Fake Neptune-C II");

        let mut cooled = player_one::PlayerOneCamera::new(devices[0].camera_id);
        cooled.connect().await.expect("Player One cooled connect");
        assert!(cooled.is_connected());
        assert!(cooled.capabilities().can_cool);
        assert!(cooled.capabilities().has_guider_port);
        let sensor = cooled.get_sensor_info();
        assert_eq!((sensor.width, sensor.height), (64, 48));
        assert_eq!(sensor.bit_depth, 16);
        assert!(!sensor.color);
        cooled.set_gain(73).await.expect("Player One set gain");
        cooled.set_offset(11).await.expect("Player One set offset");
        cooled
            .set_binning(2, 2)
            .await
            .expect("Player One set binning");
        cooled
            .set_cooler(true, -14.0)
            .await
            .expect("Player One set cooler");
        let status = cooled.get_status().await.expect("Player One status");
        assert!(status.cooler_on);
        assert_eq!(status.gain, 73);
        assert_eq!(status.offset, 11);

        env::set_var("NS_POA_NOT_READY", "1");
        assert!(!cooled
            .is_exposure_complete()
            .await
            .expect("Player One not-ready poll"));
        env::remove_var("NS_POA_NOT_READY");

        env::set_var("NS_POA_START_ERROR", "1");
        let start_error = cooled
            .start_exposure(ExposureParams {
                duration_secs: 0.01,
                gain: Some(74),
                offset: Some(12),
                bin_x: 2,
                bin_y: 2,
                subframe: None,
                readout_mode: None,
            })
            .await
            .expect_err("undocumented Player One SDK error should propagate");
        assert!(format!("{start_error}").contains("Unknown POA error code"));
        env::remove_var("NS_POA_START_ERROR");

        cooled
            .start_exposure(ExposureParams {
                duration_secs: 0.01,
                gain: Some(75),
                offset: Some(13),
                bin_x: 2,
                bin_y: 2,
                subframe: None,
                readout_mode: None,
            })
            .await
            .expect("Player One start exposure");
        assert!(cooled
            .is_exposure_complete()
            .await
            .expect("Player One exposure complete"));

        env::set_var("NS_POA_IMAGE_ERROR", "1");
        cooled
            .download_image()
            .await
            .expect_err("Player One image transfer error should propagate");
        env::remove_var("NS_POA_IMAGE_ERROR");

        let image = cooled
            .download_image()
            .await
            .expect("Player One image download");
        assert_eq!((image.width, image.height), (32, 24));
        assert_eq!(image.bits_per_pixel, 16);
        assert_eq!(image.data[0], 5000);
        cooled.abort_exposure().await.expect("Player One abort");
        cooled
            .disconnect()
            .await
            .expect("Player One cooled disconnect");

        let mut planetary = player_one::PlayerOneCamera::new(devices[1].camera_id);
        planetary
            .connect()
            .await
            .expect("Player One planetary connect");
        assert!(!planetary.capabilities().can_cool);
        let planetary_sensor = planetary.get_sensor_info();
        assert!(planetary_sensor.color);
        assert_eq!(planetary_sensor.bit_depth, 12);
        planetary
            .set_cooler(true, -5.0)
            .await
            .expect_err("uncooled Player One camera should reject cooler control");
        planetary
            .disconnect()
            .await
            .expect("Player One planetary disconnect");

        restore_env_var("NS_POA_NOT_READY", old_not_ready);
        restore_env_var("NS_POA_START_ERROR", old_start_error);
        restore_env_var("NS_POA_IMAGE_ERROR", old_image_error);
        env::set_current_dir(old_dir).expect("restore current dir");
        env::set_var("PATH", old_path);
    }

    #[tokio::test]
    #[ignore = "software-only fake SDK contract; run explicitly from compatibility matrix"]
    async fn test_qhy_fake_sdk_shim_exercises_camera_filterwheel_and_model_flows() {
        let shim_dir = build_single_fake_sdk("qhy", "qhy_fake.rs", "qhyccd.dll", QHY_FAKE_SDK);
        let old_dir = env::current_dir().expect("read current dir");
        let old_path = env::var("PATH").unwrap_or_default();
        let old_exposure_error = env::var("NS_QHY_EXPOSURE_ERROR").ok();
        env::set_current_dir(&shim_dir).expect("switch to fake SDK dir");
        env::set_var("PATH", format!("{};{}", shim_dir.display(), old_path));
        env::remove_var("NS_QHY_EXPOSURE_ERROR");

        let devices = qhy::discover_devices().await.expect("QHY discovery");
        assert_eq!(devices.len(), 2);
        assert_eq!(devices[0].name, "QHY268M");
        assert_eq!(devices[1].name, "QHY5III462C");

        let mut cooled = qhy::QhyCamera::new(devices[0].camera_id.clone());
        cooled.connect().await.expect("QHY cooled connect");
        assert!(cooled.is_connected());
        assert!(cooled.capabilities().can_cool);
        assert!(cooled.capabilities().has_guider_port);
        let sensor = cooled.get_sensor_info();
        assert_eq!((sensor.width, sensor.height), (64, 48));
        assert_eq!(sensor.bit_depth, 16);
        assert!(!sensor.color);
        let modes = cooled.get_readout_modes().await.expect("QHY read modes");
        assert_eq!(modes.len(), 2);
        cooled
            .set_readout_mode(&modes[1])
            .await
            .expect("QHY set readout mode");
        cooled.set_gain(81).await.expect("QHY set gain");
        cooled.set_offset(14).await.expect("QHY set offset");
        cooled.set_binning(2, 2).await.expect("QHY set binning");
        cooled
            .set_cooler(true, -18.0)
            .await
            .expect("QHY set cooler");
        let status = cooled.get_status().await.expect("QHY status");
        assert!(status.cooler_on);
        assert_eq!(status.target_temp, Some(-18.0));
        assert_eq!(status.gain, 81);
        assert_eq!(status.offset, 14);

        env::set_var("NS_QHY_EXPOSURE_ERROR", "1");
        cooled
            .start_exposure(ExposureParams {
                duration_secs: 0.01,
                gain: Some(82),
                offset: Some(15),
                bin_x: 2,
                bin_y: 2,
                subframe: None,
                readout_mode: None,
            })
            .await
            .expect_err("QHY SDK exposure failure should propagate");
        env::remove_var("NS_QHY_EXPOSURE_ERROR");

        cooled
            .start_exposure(ExposureParams {
                duration_secs: 0.01,
                gain: Some(83),
                offset: Some(16),
                bin_x: 2,
                bin_y: 2,
                subframe: None,
                readout_mode: None,
            })
            .await
            .expect("QHY start exposure");
        let image = cooled.download_image().await.expect("QHY image download");
        assert_eq!((image.width, image.height), (32, 24));
        assert_eq!(image.bits_per_pixel, 16);
        assert_eq!(image.data[0], 6000);
        cooled.abort_exposure().await.expect("QHY abort");
        cooled.disconnect().await.expect("QHY cooled disconnect");

        let wheels = qhy::discover_filter_wheels()
            .await
            .expect("QHY CFW discovery");
        assert_eq!(wheels.len(), 1);
        assert_eq!(wheels[0].slot_count, 7);
        let mut wheel = qhy::QhyFilterWheel::new(wheels[0].camera_id.clone());
        wheel.connect().await.expect("QHY CFW connect");
        assert_eq!(wheel.get_filter_count(), 7);
        wheel.move_to_position(2).await.expect("QHY CFW move");
        assert_eq!(wheel.get_position().await.expect("QHY CFW position"), 2);
        wheel.disconnect().await.expect("QHY CFW disconnect");

        let mut guide = qhy::QhyCamera::new(devices[1].camera_id.clone());
        guide.connect().await.expect("QHY guide connect");
        assert!(!guide.capabilities().can_cool);
        let guide_sensor = guide.get_sensor_info();
        assert!(guide_sensor.color);
        assert_eq!(
            guide_sensor.bayer_pattern,
            Some(nightshade_native::BayerPattern::Bggr)
        );
        guide
            .set_cooler(true, -5.0)
            .await
            .expect_err("uncooled QHY guide camera should reject cooler control");
        guide.disconnect().await.expect("QHY guide disconnect");

        restore_env_var("NS_QHY_EXPOSURE_ERROR", old_exposure_error);
        env::set_current_dir(old_dir).expect("restore current dir");
        env::set_var("PATH", old_path);
    }

    fn build_fake_sdks() -> PathBuf {
        let root = env::temp_dir().join(format!("nightshade-zwo-fake-sdk-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).expect("create fake SDK dir");
        compile_cdylib(&root, "asi_fake.rs", "ASICamera2.dll", ASI_FAKE_SDK);
        compile_cdylib(&root, "eaf_fake.rs", "EAF_focuser.dll", EAF_FAKE_SDK);
        compile_cdylib(&root, "efw_fake.rs", "EFW_filter.dll", EFW_FAKE_SDK);
        root
    }

    fn build_single_fake_sdk(
        vendor: &str,
        source_name: &str,
        output_name: &str,
        source: &str,
    ) -> PathBuf {
        let root = env::temp_dir().join(format!(
            "nightshade-{}-fake-sdk-{}",
            vendor,
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).expect("create fake SDK dir");
        compile_cdylib(&root, source_name, output_name, source);
        root
    }

    fn restore_env_var(name: &str, value: Option<String>) {
        if let Some(value) = value {
            env::set_var(name, value);
        } else {
            env::remove_var(name);
        }
    }

    fn compile_cdylib(root: &Path, source_name: &str, output_name: &str, source: &str) {
        let source_path = root.join(source_name);
        let output_path = root.join(output_name);
        fs::write(&source_path, source).expect("write fake SDK source");
        let rustc = env::var("RUSTC").unwrap_or_else(|_| "rustc".to_string());
        let output = Command::new(rustc)
            .arg("--crate-type")
            .arg("cdylib")
            .arg("--edition")
            .arg("2021")
            .arg(&source_path)
            .arg("-o")
            .arg(&output_path)
            .output()
            .expect("run rustc for fake SDK");
        assert!(
            output.status.success(),
            "fake SDK build failed for {}:\nstdout:\n{}\nstderr:\n{}",
            output_name,
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }

    const ASI_FAKE_SDK: &str = r#"
#![allow(non_snake_case)]
use std::ffi::{c_char, c_int, c_long, c_uchar};
use std::sync::atomic::{AtomicI32, AtomicI64, Ordering};
static WIDTH: AtomicI32 = AtomicI32::new(64);
static HEIGHT: AtomicI32 = AtomicI32::new(48);
static BIN: AtomicI32 = AtomicI32::new(1);
static IMG_TYPE: AtomicI32 = AtomicI32::new(2);
static GAIN: AtomicI64 = AtomicI64::new(0);
static OFFSET: AtomicI64 = AtomicI64::new(0);
static TARGET_TEMP: AtomicI64 = AtomicI64::new(-10);
static COOLER_ON: AtomicI64 = AtomicI64::new(0);
#[repr(C)]
struct ASICameraInfo{ name:[c_char;64], camera_id:c_int, max_height:c_long, max_width:c_long, is_color_cam:c_int, bayer_pattern:c_int, supported_bins:[c_int;16], supported_video_format:[c_int;8], pixel_size:f64, mechanical_shutter:c_int, st4_port:c_int, is_cooler_cam:c_int, is_usb3_host:c_int, is_usb3_camera:c_int, elec_per_adu:f32, bit_depth:c_int, is_trigger_cam:c_int, unused:[c_char;16] }
#[repr(C)]
struct ASIControlCaps{ name:[c_char;64], description:[c_char;128], max_value:c_long, min_value:c_long, default_value:c_long, is_auto_supported:c_int, is_writable:c_int, control_type:c_int, unused:[c_char;32] }
fn write_cstr(buf:&mut [c_char], text:&[u8]){ for slot in buf.iter_mut(){*slot=0;} for i in 0..text.len().min(buf.len().saturating_sub(1)){buf[i]=text[i] as c_char;} }
#[no_mangle] pub extern "C" fn ASIGetNumOfConnectedCameras()->c_int{1}
#[no_mangle] pub unsafe extern "C" fn ASIGetCameraProperty(info:*mut ASICameraInfo,index:c_int)->c_int{ if info.is_null()||index!=0{return 1;} let mut value:ASICameraInfo=std::mem::zeroed(); write_cstr(&mut value.name,b"Nightshade Fake ASI2600MM Pro"); value.camera_id=0; value.max_width=64; value.max_height=48; value.supported_bins[0]=1; value.supported_bins[1]=2; value.supported_bins[2]=4; value.supported_video_format[0]=0; value.supported_video_format[1]=2; value.supported_video_format[2]=-1; value.pixel_size=3.76; value.st4_port=1; value.is_cooler_cam=1; value.is_usb3_host=1; value.is_usb3_camera=1; value.elec_per_adu=0.8; value.bit_depth=16; *info=value; 0 }
#[no_mangle] pub extern "C" fn ASIOpenCamera(id:c_int)->c_int{if id==0{0}else{2}}
#[no_mangle] pub extern "C" fn ASIInitCamera(id:c_int)->c_int{if id==0{0}else{2}}
#[no_mangle] pub extern "C" fn ASICloseCamera(_id:c_int)->c_int{0}
#[no_mangle] pub unsafe extern "C" fn ASIGetControlValue(_id:c_int,control:c_int,value:*mut c_long,is_auto:*mut c_int)->c_int{ if value.is_null()||is_auto.is_null(){return 16;} *is_auto=0; let v=match control{0=>GAIN.load(Ordering::SeqCst),1=>10_000,5=>OFFSET.load(Ordering::SeqCst),6=>40,8=>-105,15=>37,16=>TARGET_TEMP.load(Ordering::SeqCst),17=>COOLER_ON.load(Ordering::SeqCst),21=>1,_=>return 3}; *value=v as c_long; 0 }
#[no_mangle] pub extern "C" fn ASISetControlValue(_id:c_int,control:c_int,value:c_long,_is_auto:c_int)->c_int{ match control{0=>GAIN.store(value as i64,Ordering::SeqCst),5=>OFFSET.store(value as i64,Ordering::SeqCst),16=>TARGET_TEMP.store(value as i64,Ordering::SeqCst),17=>COOLER_ON.store(value as i64,Ordering::SeqCst),_=>{}} 0 }
#[no_mangle] pub extern "C" fn ASISetROIFormat(_id:c_int,width:c_int,height:c_int,bin:c_int,img_type:c_int)->c_int{WIDTH.store(width,Ordering::SeqCst); HEIGHT.store(height,Ordering::SeqCst); BIN.store(bin,Ordering::SeqCst); IMG_TYPE.store(img_type,Ordering::SeqCst); 0}
#[no_mangle] pub extern "C" fn ASISetStartPos(_id:c_int,_x:c_int,_y:c_int)->c_int{0}
#[no_mangle] pub unsafe extern "C" fn ASIGetROIFormat(_id:c_int,width:*mut c_int,height:*mut c_int,bin:*mut c_int,img_type:*mut c_int)->c_int{ if width.is_null()||height.is_null()||bin.is_null()||img_type.is_null(){return 16;} *width=WIDTH.load(Ordering::SeqCst); *height=HEIGHT.load(Ordering::SeqCst); *bin=BIN.load(Ordering::SeqCst); *img_type=IMG_TYPE.load(Ordering::SeqCst); 0 }
#[no_mangle] pub extern "C" fn ASIStartExposure(_id:c_int,_dark:c_int)->c_int{0}
#[no_mangle] pub extern "C" fn ASIStopExposure(_id:c_int)->c_int{0}
#[no_mangle] pub unsafe extern "C" fn ASIGetExpStatus(_id:c_int,status:*mut c_int)->c_int{ if status.is_null(){return 16;} *status=2; 0 }
#[no_mangle] pub unsafe extern "C" fn ASIGetDataAfterExp(_id:c_int,buffer:*mut c_uchar,size:c_long)->c_int{ if buffer.is_null()||size<0{return 13;} for i in 0..((size as usize)/2){let value=1000u16.wrapping_add(i as u16); *buffer.add(i*2)=(value&0xff) as u8; *buffer.add(i*2+1)=(value>>8) as u8;} 0 }
#[no_mangle] pub unsafe extern "C" fn ASIGetNumOfControls(_id:c_int,count:*mut c_int)->c_int{ if count.is_null(){return 16;} *count=7; 0 }
#[no_mangle] pub unsafe extern "C" fn ASIGetControlCaps(_id:c_int,index:c_int,caps:*mut ASIControlCaps)->c_int{ if caps.is_null(){return 16;} let controls=[(0,b"Gain".as_slice(),0,600,0),(1,b"Exposure".as_slice(),1,60_000_000,10_000),(5,b"Offset".as_slice(),0,100,0),(8,b"Temperature".as_slice(),-500,500,-105),(15,b"Cooler Power".as_slice(),0,100,37),(16,b"Target Temp".as_slice(),-40,30,-10),(17,b"Cooler On".as_slice(),0,1,0)]; if index<0||index as usize>=controls.len(){return 1;} let (control_type,name,min,max,default_value)=controls[index as usize]; let mut value:ASIControlCaps=std::mem::zeroed(); write_cstr(&mut value.name,name); write_cstr(&mut value.description,b"Nightshade fake SDK control"); value.min_value=min; value.max_value=max; value.default_value=default_value; value.is_writable=1; value.control_type=control_type; *caps=value; 0 }
"#;

    const EAF_FAKE_SDK: &str = r#"
#![allow(non_snake_case)]
use std::ffi::{c_char,c_int,c_uchar};
use std::sync::atomic::{AtomicBool,AtomicI32,Ordering};
static POSITION:AtomicI32=AtomicI32::new(1_000); static MAX_STEP:AtomicI32=AtomicI32::new(60_000); static REVERSE:AtomicBool=AtomicBool::new(false); static BEEP:AtomicBool=AtomicBool::new(false); static BACKLASH:AtomicI32=AtomicI32::new(0);
#[repr(C)] struct EAFInfo{ id:c_int, name:[c_char;64], max_step:c_int }
#[repr(C)] struct EAFSerialNumber{ id:[c_uchar;8] }
fn write_cstr(buf:&mut [c_char], text:&[u8]){ for slot in buf.iter_mut(){*slot=0;} for i in 0..text.len().min(buf.len().saturating_sub(1)){buf[i]=text[i] as c_char;} }
#[no_mangle] pub extern "C" fn EAFGetNum()->c_int{1}
#[no_mangle] pub unsafe extern "C" fn EAFGetID(index:c_int,id:*mut c_int)->c_int{ if id.is_null()||index!=0{return 1;} *id=0; 0}
#[no_mangle] pub extern "C" fn EAFOpen(id:c_int)->c_int{if id==0{0}else{2}}
#[no_mangle] pub extern "C" fn EAFClose(_id:c_int)->c_int{0}
#[no_mangle] pub unsafe extern "C" fn EAFGetProperty(id:c_int,info:*mut EAFInfo)->c_int{ if info.is_null()||id!=0{return 2;} let mut value:EAFInfo=std::mem::zeroed(); value.id=id; value.max_step=MAX_STEP.load(Ordering::SeqCst); write_cstr(&mut value.name,b"ZWO EAF"); *info=value; 0}
#[no_mangle] pub extern "C" fn EAFMove(_id:c_int,position:c_int)->c_int{POSITION.store(position,Ordering::SeqCst);0}
#[no_mangle] pub extern "C" fn EAFStop(_id:c_int)->c_int{0}
#[no_mangle] pub unsafe extern "C" fn EAFIsMoving(_id:c_int,moving:*mut bool,hand_control:*mut bool)->c_int{ if moving.is_null()||hand_control.is_null(){return 7;} *moving=false; *hand_control=false; 0}
#[no_mangle] pub unsafe extern "C" fn EAFGetPosition(_id:c_int,position:*mut c_int)->c_int{ if position.is_null(){return 7;} *position=POSITION.load(Ordering::SeqCst); 0}
#[no_mangle] pub unsafe extern "C" fn EAFGetTemp(_id:c_int,temp:*mut f32)->c_int{ if temp.is_null(){return 7;} *temp=21.5; 0}
#[no_mangle] pub extern "C" fn EAFSetMaxStep(_id:c_int,max_step:c_int)->c_int{MAX_STEP.store(max_step,Ordering::SeqCst);0}
#[no_mangle] pub unsafe extern "C" fn EAFGetMaxStep(_id:c_int,max_step:*mut c_int)->c_int{ if max_step.is_null(){return 7;} *max_step=MAX_STEP.load(Ordering::SeqCst); 0}
#[no_mangle] pub extern "C" fn EAFSetBacklash(_id:c_int,backlash:c_int)->c_int{BACKLASH.store(backlash,Ordering::SeqCst);0}
#[no_mangle] pub unsafe extern "C" fn EAFGetBacklash(_id:c_int,backlash:*mut c_int)->c_int{ if backlash.is_null(){return 7;} *backlash=BACKLASH.load(Ordering::SeqCst); 0}
#[no_mangle] pub extern "C" fn EAFSetReverse(_id:c_int,reverse:bool)->c_int{REVERSE.store(reverse,Ordering::SeqCst);0}
#[no_mangle] pub unsafe extern "C" fn EAFGetReverse(_id:c_int,reverse:*mut bool)->c_int{ if reverse.is_null(){return 7;} *reverse=REVERSE.load(Ordering::SeqCst); 0}
#[no_mangle] pub extern "C" fn EAFSetBeep(_id:c_int,beep:bool)->c_int{BEEP.store(beep,Ordering::SeqCst);0}
#[no_mangle] pub unsafe extern "C" fn EAFGetBeep(_id:c_int,beep:*mut bool)->c_int{ if beep.is_null(){return 7;} *beep=BEEP.load(Ordering::SeqCst); 0}
#[no_mangle] pub extern "C" fn EAFGetSDKVersion()->*const c_char{b"fake-eaf-1.0\0".as_ptr() as *const c_char}
#[no_mangle] pub unsafe extern "C" fn EAFGetFirmwareVersion(_id:c_int,major:*mut c_uchar,minor:*mut c_uchar,build:*mut c_uchar)->c_int{ if !major.is_null(){*major=1;} if !minor.is_null(){*minor=2;} if !build.is_null(){*build=3;} 0}
#[no_mangle] pub unsafe extern "C" fn EAFGetSerialNumber(_id:c_int,serial:*mut EAFSerialNumber)->c_int{ if serial.is_null(){return 7;} (*serial).id=[0xEA,0xF0,1,2,0,0,0,0]; 0}
#[no_mangle] pub extern "C" fn EAFResetPostion(_id:c_int,position:c_int)->c_int{POSITION.store(position,Ordering::SeqCst);0}
"#;

    const EFW_FAKE_SDK: &str = r#"
#![allow(non_snake_case)]
use std::ffi::{c_char,c_int,c_uchar};
use std::sync::atomic::{AtomicBool,AtomicI32,Ordering};
static POSITION:AtomicI32=AtomicI32::new(0); static DIRECTION:AtomicBool=AtomicBool::new(false);
#[repr(C)] struct EFWInfo{ id:c_int, name:[c_char;64], slot_num:c_int }
#[repr(C)] struct EFWSerialNumber{ id:[c_uchar;8] }
fn write_cstr(buf:&mut [c_char], text:&[u8]){ for slot in buf.iter_mut(){*slot=0;} for i in 0..text.len().min(buf.len().saturating_sub(1)){buf[i]=text[i] as c_char;} }
#[no_mangle] pub extern "C" fn EFWGetNum()->c_int{1}
#[no_mangle] pub unsafe extern "C" fn EFWGetID(index:c_int,id:*mut c_int)->c_int{ if id.is_null()||index!=0{return 1;} *id=0; 0}
#[no_mangle] pub extern "C" fn EFWOpen(id:c_int)->c_int{if id==0{0}else{2}}
#[no_mangle] pub extern "C" fn EFWClose(_id:c_int)->c_int{0}
#[no_mangle] pub unsafe extern "C" fn EFWGetProperty(id:c_int,info:*mut EFWInfo)->c_int{ if info.is_null()||id!=0{return 2;} let mut value:EFWInfo=std::mem::zeroed(); value.id=id; value.slot_num=7; write_cstr(&mut value.name,b"Nightshade Fake EFW 7x36"); *info=value; 0}
#[no_mangle] pub unsafe extern "C" fn EFWGetPosition(_id:c_int,position:*mut c_int)->c_int{ if position.is_null(){return 7;} *position=POSITION.load(Ordering::SeqCst); 0}
#[no_mangle] pub extern "C" fn EFWSetPosition(_id:c_int,position:c_int)->c_int{POSITION.store(position,Ordering::SeqCst);0}
#[no_mangle] pub extern "C" fn EFWSetDirection(_id:c_int,direction:bool)->c_int{DIRECTION.store(direction,Ordering::SeqCst);0}
#[no_mangle] pub unsafe extern "C" fn EFWGetDirection(_id:c_int,direction:*mut bool)->c_int{ if direction.is_null(){return 7;} *direction=DIRECTION.load(Ordering::SeqCst); 0}
#[no_mangle] pub extern "C" fn EFWCalibrate(_id:c_int)->c_int{0}
#[no_mangle] pub extern "C" fn EFWGetSDKVersion()->*const c_char{b"fake-efw-1.0\0".as_ptr() as *const c_char}
#[no_mangle] pub unsafe extern "C" fn EFWGetHWErrorCode(_id:c_int,code:*mut c_int)->c_int{ if !code.is_null(){*code=0;} 0}
#[no_mangle] pub unsafe extern "C" fn EFWGetFirmwareVersion(_id:c_int,major:*mut c_uchar,minor:*mut c_uchar,build:*mut c_uchar)->c_int{ if !major.is_null(){*major=4;} if !minor.is_null(){*minor=5;} if !build.is_null(){*build=6;} 0}
#[no_mangle] pub unsafe extern "C" fn EFWGetSerialNumber(_id:c_int,serial:*mut EFWSerialNumber)->c_int{ if serial.is_null(){return 7;} (*serial).id=[0xEF,0xF0,1,2,0,0,0,0]; 0}
"#;

    const PLAYER_ONE_FAKE_SDK: &str = r#"
#![allow(non_snake_case)]
use std::ffi::{c_char,c_int,c_long};
use std::sync::atomic::{AtomicI32,AtomicI64,Ordering};
static CURRENT_ID:AtomicI32=AtomicI32::new(101); static WIDTH:AtomicI32=AtomicI32::new(64); static HEIGHT:AtomicI32=AtomicI32::new(48); static BIN:AtomicI32=AtomicI32::new(1);
static GAIN:AtomicI64=AtomicI64::new(0); static OFFSET:AtomicI64=AtomicI64::new(0); static COOLER:AtomicI64=AtomicI64::new(0); static TARGET_TEMP:AtomicI64=AtomicI64::new(-10); static FORMAT:AtomicI32=AtomicI32::new(1);
#[repr(C)] struct POACameraProperties{camera_model_name:[c_char;256],user_custom_id:[c_char;16],camera_id:c_int,max_width:c_int,max_height:c_int,bit_depth:c_int,is_color_camera:c_int,is_has_st4_port:c_int,is_has_cooler:c_int,is_usb3_speed:c_int,bayer_pattern:c_int,pixel_size:f64,sn:[c_char;64],sensor_model_name:[c_char;32],local_path:[c_char;256],bins:[c_int;8],img_formats:[c_int;8],is_support_hard_bin:c_int,p_id:c_int,reserved:[c_char;248]}
#[repr(C)] union POAConfigValue{int_value:c_long,float_value:f64,bool_value:c_int}
fn write_cstr(buf:&mut [c_char],text:&[u8]){for b in buf.iter_mut(){*b=0;} for i in 0..text.len().min(buf.len().saturating_sub(1)){buf[i]=text[i] as c_char;}}
fn fill_props(id:c_int,props:*mut POACameraProperties)->c_int{unsafe{if props.is_null(){return 4;} let mut p:POACameraProperties=std::mem::zeroed(); p.camera_id=id; p.max_width=64; p.max_height=48; p.is_usb3_speed=1; p.pixel_size=2.9; p.bins[0]=1; p.bins[1]=2; p.bins[2]=4; p.img_formats[0]=1; p.img_formats[1]=-1; p.is_support_hard_bin=1; match id{101=>{write_cstr(&mut p.camera_model_name,b"Nightshade Fake Poseidon-M Pro"); write_cstr(&mut p.sn,b"POA-COOLED-0001"); write_cstr(&mut p.sensor_model_name,b"IMX571"); p.bit_depth=16; p.is_color_camera=0; p.is_has_st4_port=1; p.is_has_cooler=1; p.bayer_pattern=-1; p.p_id=101;} 202=>{write_cstr(&mut p.camera_model_name,b"Nightshade Fake Neptune-C II"); write_cstr(&mut p.sn,b"POA-GUIDE-0002"); write_cstr(&mut p.sensor_model_name,b"IMX464"); p.bit_depth=12; p.is_color_camera=1; p.is_has_st4_port=0; p.is_has_cooler=0; p.bayer_pattern=1; p.p_id=202;} _=>return 1} *props=p; 0}}
#[no_mangle] pub extern "C" fn POAGetCameraCount()->c_int{2}
#[no_mangle] pub extern "C" fn POAGetCameraProperties(index:c_int,props:*mut POACameraProperties)->c_int{match index{0=>fill_props(101,props),1=>fill_props(202,props),_=>1}}
#[no_mangle] pub extern "C" fn POAGetCameraPropertiesByID(id:c_int,props:*mut POACameraProperties)->c_int{fill_props(id,props)}
#[no_mangle] pub extern "C" fn POAOpenCamera(id:c_int)->c_int{if id==101||id==202{CURRENT_ID.store(id,Ordering::SeqCst); 0}else{1}}
#[no_mangle] pub extern "C" fn POAInitCamera(_id:c_int)->c_int{0}
#[no_mangle] pub extern "C" fn POACloseCamera(_id:c_int)->c_int{0}
#[no_mangle] pub unsafe extern "C" fn POAGetConfig(_id:c_int,control:c_int,value:*mut POAConfigValue,is_auto:*mut c_int)->c_int{if value.is_null()||is_auto.is_null(){return 4;} *is_auto=0; match control{1=>(*value).int_value=GAIN.load(Ordering::SeqCst) as c_long,3=>(*value).float_value=-9.5,7=>(*value).int_value=OFFSET.load(Ordering::SeqCst) as c_long,12=>(*value).int_value=40,16=>(*value).int_value=38,17=>(*value).int_value=TARGET_TEMP.load(Ordering::SeqCst) as c_long,18=>(*value).bool_value=COOLER.load(Ordering::SeqCst) as c_int,20=>(*value).int_value=20,21=>(*value).int_value=55,_=>(*value).int_value=0}; 0}
#[no_mangle] pub unsafe extern "C" fn POASetConfig(_id:c_int,control:c_int,value:POAConfigValue,_is_auto:c_int)->c_int{match control{0=>{},1=>GAIN.store(value.int_value as i64,Ordering::SeqCst),7=>OFFSET.store(value.int_value as i64,Ordering::SeqCst),17=>TARGET_TEMP.store(value.int_value as i64,Ordering::SeqCst),18=>COOLER.store(value.bool_value as i64,Ordering::SeqCst),_=>{}} 0}
#[no_mangle] pub extern "C" fn POASetImageBin(_id:c_int,bin:c_int)->c_int{if bin<=0||bin>4{return 7;} BIN.store(bin,Ordering::SeqCst); 0}
#[no_mangle] pub extern "C" fn POASetImageSize(_id:c_int,width:c_int,height:c_int)->c_int{if width<=0||height<=0{return 4;} WIDTH.store(width,Ordering::SeqCst); HEIGHT.store(height,Ordering::SeqCst); 0}
#[no_mangle] pub extern "C" fn POASetImageStartPos(_id:c_int,_x:c_int,_y:c_int)->c_int{0}
#[no_mangle] pub extern "C" fn POASetImageFormat(_id:c_int,fmt:c_int)->c_int{FORMAT.store(fmt,Ordering::SeqCst); 0}
#[no_mangle] pub extern "C" fn POAStartExposure(_id:c_int,_snap:c_int)->c_int{if std::env::var("NS_POA_START_ERROR").is_ok(){13}else{0}}
#[no_mangle] pub extern "C" fn POAStopExposure(_id:c_int)->c_int{0}
#[no_mangle] pub unsafe extern "C" fn POAGetCameraState(_id:c_int,state:*mut c_int)->c_int{if state.is_null(){return 4;} *state=0; 0}
#[no_mangle] pub unsafe extern "C" fn POAGetImageData(_id:c_int,buf:*mut u8,size:c_long,_timeout_ms:c_int)->c_int{if std::env::var("NS_POA_IMAGE_ERROR").is_ok(){return 10;} if buf.is_null()||size<0{return 4;} for i in 0..((size as usize)/2){let v=5000u16.wrapping_add(i as u16); *buf.add(i*2)=(v&0xff) as u8; *buf.add(i*2+1)=(v>>8) as u8;} 0}
#[no_mangle] pub unsafe extern "C" fn POAGetImageSize(_id:c_int,width:*mut c_int,height:*mut c_int)->c_int{if width.is_null()||height.is_null(){return 4;} *width=WIDTH.load(Ordering::SeqCst); *height=HEIGHT.load(Ordering::SeqCst); 0}
#[no_mangle] pub unsafe extern "C" fn POAImageReady(_id:c_int,ready:*mut c_int)->c_int{if ready.is_null(){return 4;} *ready=if std::env::var("NS_POA_NOT_READY").is_ok(){0}else{1}; 0}
"#;

    const QHY_FAKE_SDK: &str = r#"
#![allow(non_snake_case)]
use std::ffi::{c_char,c_double,c_int,c_uint,c_void,CStr};
use std::sync::atomic::{AtomicI32,AtomicU32,AtomicU64,Ordering};
static CAMERA_KIND:AtomicI32=AtomicI32::new(1); static WIDTH:AtomicU32=AtomicU32::new(64); static HEIGHT:AtomicU32=AtomicU32::new(48); static BIN:AtomicU32=AtomicU32::new(1); static CFW_POS:AtomicI32=AtomicI32::new(0); static READ_MODE:AtomicU32=AtomicU32::new(0);
static GAIN_BITS:AtomicU64=AtomicU64::new(0); static OFFSET_BITS:AtomicU64=AtomicU64::new(0); static COOLER_BITS:AtomicU64=AtomicU64::new(0);
fn set_f64(slot:&AtomicU64,value:f64){slot.store(value.to_bits(),Ordering::SeqCst);} fn get_f64(slot:&AtomicU64)->f64{f64::from_bits(slot.load(Ordering::SeqCst))}
unsafe fn write_cstr(buf:*mut c_char,text:&[u8]){for i in 0..256{*buf.add(i)=0;} for i in 0..text.len(){*buf.add(i)=text[i] as c_char;}}
#[no_mangle] pub extern "C" fn InitQHYCCDResource()->c_uint{0}
#[no_mangle] pub extern "C" fn ReleaseQHYCCDResource()->c_uint{0}
#[no_mangle] pub extern "C" fn ScanQHYCCD()->c_uint{2}
#[no_mangle] pub unsafe extern "C" fn GetQHYCCDId(index:c_uint,id:*mut c_char)->c_uint{if id.is_null(){return 1;} match index{0=>write_cstr(id,b"QHY268M-FAKE0001"),1=>write_cstr(id,b"QHY5III462C-FAKE0002"),_=>return 1} 0}
#[no_mangle] pub unsafe extern "C" fn OpenQHYCCD(id:*const c_char)->*mut c_void{if id.is_null(){return std::ptr::null_mut();} let s=CStr::from_ptr(id).to_string_lossy(); if s.contains("QHY5III"){CAMERA_KIND.store(2,Ordering::SeqCst); WIDTH.store(48,Ordering::SeqCst); HEIGHT.store(32,Ordering::SeqCst);}else{CAMERA_KIND.store(1,Ordering::SeqCst); WIDTH.store(64,Ordering::SeqCst); HEIGHT.store(48,Ordering::SeqCst);} 1usize as *mut c_void}
#[no_mangle] pub extern "C" fn CloseQHYCCD(_handle:*mut c_void)->c_uint{0}
#[no_mangle] pub extern "C" fn SetQHYCCDStreamMode(_handle:*mut c_void,_mode:c_uint)->c_uint{0}
#[no_mangle] pub extern "C" fn InitQHYCCD(_handle:*mut c_void)->c_uint{0}
#[no_mangle] pub unsafe extern "C" fn GetQHYCCDChipInfo(_handle:*mut c_void,chip_w:*mut c_double,chip_h:*mut c_double,img_w:*mut c_uint,img_h:*mut c_uint,pixel_w:*mut c_double,pixel_h:*mut c_double,bpp:*mut c_uint)->c_uint{let kind=CAMERA_KIND.load(Ordering::SeqCst); if !chip_w.is_null(){*chip_w=if kind==1{23.5}else{5.6};} if !chip_h.is_null(){*chip_h=if kind==1{15.7}else{3.2};} if !img_w.is_null(){*img_w=WIDTH.load(Ordering::SeqCst);} if !img_h.is_null(){*img_h=HEIGHT.load(Ordering::SeqCst);} if !pixel_w.is_null(){*pixel_w=if kind==1{3.76}else{2.9};} if !pixel_h.is_null(){*pixel_h=if kind==1{3.76}else{2.9};} if !bpp.is_null(){*bpp=16;} 0}
#[no_mangle] pub extern "C" fn IsQHYCCDControlAvailable(_handle:*mut c_void,control:c_int)->c_uint{let kind=CAMERA_KIND.load(Ordering::SeqCst); match control{18|19=>if kind==1{0}else{1},59=>if kind==2{0}else{1},21|22|23|24|35=>0,_=>0}}
#[no_mangle] pub unsafe extern "C" fn GetQHYCCDEffectiveArea(_handle:*mut c_void,x:*mut c_uint,y:*mut c_uint,w:*mut c_uint,h:*mut c_uint)->c_uint{if !x.is_null(){*x=0;} if !y.is_null(){*y=0;} if !w.is_null(){*w=WIDTH.load(Ordering::SeqCst);} if !h.is_null(){*h=HEIGHT.load(Ordering::SeqCst);} 0}
#[no_mangle] pub extern "C" fn SetQHYCCDParam(_handle:*mut c_void,control:c_int,value:c_double)->c_uint{match control{6=>set_f64(&GAIN_BITS,value),7=>set_f64(&OFFSET_BITS,value),17=>CFW_POS.store((value as i32)-48,Ordering::SeqCst),18=>set_f64(&COOLER_BITS,value),_=>{}} 0}
#[no_mangle] pub extern "C" fn GetQHYCCDParam(_handle:*mut c_void,control:c_int)->c_double{match control{6=>get_f64(&GAIN_BITS),7=>get_f64(&OFFSET_BITS),12=>40.0,14=>-9.25,15=>35.0,17=>(CFW_POS.load(Ordering::SeqCst)+48) as f64,18=>get_f64(&COOLER_BITS),20=>4.0,44=>7.0,62=>23.0,63=>900.0,_=>0.0}}
#[no_mangle] pub unsafe extern "C" fn GetQHYCCDParamMinMaxStep(_handle:*mut c_void,_control:c_int,min:*mut c_double,max:*mut c_double,step:*mut c_double)->c_uint{if !min.is_null(){*min=0.0;} if !max.is_null(){*max=600.0;} if !step.is_null(){*step=1.0;} 0}
#[no_mangle] pub extern "C" fn SetQHYCCDResolution(_handle:*mut c_void,_x:c_uint,_y:c_uint,width:c_uint,height:c_uint)->c_uint{if width==0||height==0{return 1;} WIDTH.store(width,Ordering::SeqCst); HEIGHT.store(height,Ordering::SeqCst); 0}
#[no_mangle] pub extern "C" fn SetQHYCCDBinMode(_handle:*mut c_void,bin_x:c_uint,bin_y:c_uint)->c_uint{if bin_x==0||bin_x!=bin_y{return 1;} BIN.store(bin_x,Ordering::SeqCst); 0}
#[no_mangle] pub extern "C" fn SetQHYCCDBitsMode(_handle:*mut c_void,_bits:c_uint)->c_uint{0}
#[no_mangle] pub extern "C" fn ExpQHYCCDSingleFrame(_handle:*mut c_void)->c_uint{if std::env::var("NS_QHY_EXPOSURE_ERROR").is_ok(){99}else{0}}
#[no_mangle] pub unsafe extern "C" fn GetQHYCCDSingleFrame(_handle:*mut c_void,width:*mut c_uint,height:*mut c_uint,bpp:*mut c_uint,channels:*mut c_uint,buf:*mut u8)->c_uint{let w=WIDTH.load(Ordering::SeqCst); let h=HEIGHT.load(Ordering::SeqCst); if !width.is_null(){*width=w;} if !height.is_null(){*height=h;} if !bpp.is_null(){*bpp=16;} if !channels.is_null(){*channels=1;} if buf.is_null(){return 1;} for i in 0..((w*h) as usize){let v=6000u16.wrapping_add(i as u16); *buf.add(i*2)=(v&0xff) as u8; *buf.add(i*2+1)=(v>>8) as u8;} 0}
#[no_mangle] pub extern "C" fn CancelQHYCCDExposingAndReadout(_handle:*mut c_void)->c_uint{0}
#[no_mangle] pub extern "C" fn GetQHYCCDMemLength(_handle:*mut c_void)->c_uint{WIDTH.load(Ordering::SeqCst)*HEIGHT.load(Ordering::SeqCst)*2}
#[no_mangle] pub unsafe extern "C" fn GetQHYCCDReadModeName(_handle:*mut c_void,index:c_uint,name:*mut c_char)->c_uint{if name.is_null(){return 1;} match index{0=>write_cstr(name,b"Photographic DSO"),1=>write_cstr(name,b"High Gain"),_=>return 1} 0}
#[no_mangle] pub unsafe extern "C" fn GetQHYCCDNumberOfReadModes(_handle:*mut c_void,count:*mut c_uint)->c_uint{if count.is_null(){return 1;} *count=2; 0}
#[no_mangle] pub extern "C" fn SetQHYCCDReadMode(_handle:*mut c_void,mode:c_uint)->c_uint{if mode>1{return 1;} READ_MODE.store(mode,Ordering::SeqCst); 0}
#[no_mangle] pub unsafe extern "C" fn GetQHYCCDReadMode(_handle:*mut c_void,mode:*mut c_uint)->c_uint{if mode.is_null(){return 1;} *mode=READ_MODE.load(Ordering::SeqCst); 0}
#[no_mangle] pub extern "C" fn IsQHYCCDCFWPlugged(_handle:*mut c_void)->c_uint{if CAMERA_KIND.load(Ordering::SeqCst)==1{0}else{1}}
"#;

    const ATIK_FAKE_SDK: &str = r#"
#![allow(non_snake_case)]
use std::ffi::{c_char,c_float,c_int,c_void};
use std::sync::atomic::{AtomicI32,Ordering};
static GAIN:AtomicI32=AtomicI32::new(0); static OFFSET:AtomicI32=AtomicI32::new(0); static BIN_X:AtomicI32=AtomicI32::new(1); static BIN_Y:AtomicI32=AtomicI32::new(1); static SETPOINT:AtomicI32=AtomicI32::new(-1000);
static mut IMAGE:[u8;384]=[0;384];
#[repr(C)] struct ArtemisProperties{protocol:c_int,pixels_x:c_int,pixels_y:c_int,pixel_microns_x:c_float,pixel_microns_y:c_float,ccd_flags:c_int,camera_flags:c_int,description:[c_char;40],manufacturer:[c_char;40]}
fn write_cstr(buf:*mut c_char,text:&[u8]){unsafe{for i in 0..100{*buf.add(i)=0;} for i in 0..text.len(){*buf.add(i)=text[i] as c_char;}}}
fn write_fixed(buf:&mut [c_char],text:&[u8]){for b in buf.iter_mut(){*b=0;} for i in 0..text.len().min(buf.len().saturating_sub(1)){buf[i]=text[i] as c_char;}}
#[no_mangle] pub extern "C" fn ArtemisDeviceCount()->c_int{1}
#[no_mangle] pub extern "C" fn ArtemisDevicePresent(device:c_int)->c_int{if device==0{1}else{0}}
#[no_mangle] pub unsafe extern "C" fn ArtemisDeviceName(device:c_int,name:*mut c_char)->c_int{if device!=0||name.is_null(){return 0;} write_cstr(name,b"Nightshade Fake Atik Horizon II"); 1}
#[no_mangle] pub unsafe extern "C" fn ArtemisDeviceSerial(device:c_int,serial:*mut c_char)->c_int{if device!=0||serial.is_null(){return 0;} write_cstr(serial,b"ATIK-FAKE-0001"); 1}
#[no_mangle] pub extern "C" fn ArtemisDeviceIsCamera(device:c_int)->c_int{if device==0{1}else{0}}
#[no_mangle] pub extern "C" fn ArtemisConnect(device:c_int)->*mut c_void{if device==0{1usize as *mut c_void}else{std::ptr::null_mut()}}
#[no_mangle] pub extern "C" fn ArtemisDisconnect(_handle:*mut c_void)->c_int{1}
#[no_mangle] pub extern "C" fn ArtemisIsConnected(_handle:*mut c_void)->c_int{1}
#[no_mangle] pub unsafe extern "C" fn ArtemisProperties(_handle:*mut c_void,prop:*mut ArtemisProperties)->c_int{if prop.is_null(){return 1;} let mut p:ArtemisProperties=std::mem::zeroed(); p.pixels_x=32; p.pixels_y=24; p.pixel_microns_x=3.8; p.pixel_microns_y=3.8; p.camera_flags=16|32; p.ccd_flags=0; write_fixed(&mut p.description,b"Fake Horizon II"); write_fixed(&mut p.manufacturer,b"Atik"); *prop=p; 0}
#[no_mangle] pub unsafe extern "C" fn ArtemisColourProperties(_handle:*mut c_void,colour:*mut c_int,nx:*mut c_int,ny:*mut c_int,px:*mut c_int,py:*mut c_int)->c_int{if !colour.is_null(){*colour=0;} if !nx.is_null(){*nx=0;} if !ny.is_null(){*ny=0;} if !px.is_null(){*px=0;} if !py.is_null(){*py=0;} 0}
#[no_mangle] pub extern "C" fn ArtemisBin(_handle:*mut c_void,x:c_int,y:c_int)->c_int{BIN_X.store(x,Ordering::SeqCst); BIN_Y.store(y,Ordering::SeqCst); 0}
#[no_mangle] pub unsafe extern "C" fn ArtemisGetMaxBin(_handle:*mut c_void,x:*mut c_int,y:*mut c_int)->c_int{if !x.is_null(){*x=4;} if !y.is_null(){*y=4;} 0}
#[no_mangle] pub extern "C" fn ArtemisSubframe(_handle:*mut c_void,_x:c_int,_y:c_int,_w:c_int,_h:c_int)->c_int{0}
#[no_mangle] pub extern "C" fn ArtemisStartExposure(_handle:*mut c_void,_seconds:c_float)->c_int{0}
#[no_mangle] pub extern "C" fn ArtemisAbortExposure(_handle:*mut c_void)->c_int{0}
#[no_mangle] pub extern "C" fn ArtemisImageReady(_handle:*mut c_void)->c_int{1}
#[no_mangle] pub extern "C" fn ArtemisExposureTimeRemaining(_handle:*mut c_void)->c_float{0.0}
#[no_mangle] pub unsafe extern "C" fn ArtemisGetImageData(_handle:*mut c_void,x:*mut c_int,y:*mut c_int,w:*mut c_int,h:*mut c_int,binx:*mut c_int,biny:*mut c_int)->c_int{if !x.is_null(){*x=0;} if !y.is_null(){*y=0;} if !w.is_null(){*w=16;} if !h.is_null(){*h=12;} if !binx.is_null(){*binx=BIN_X.load(Ordering::SeqCst);} if !biny.is_null(){*biny=BIN_Y.load(Ordering::SeqCst);} for i in 0..192{let v=2000u16.wrapping_add(i as u16); IMAGE[i*2]=(v&0xff) as u8; IMAGE[i*2+1]=(v>>8) as u8;} 0}
#[no_mangle] pub extern "C" fn ArtemisImageBuffer(_handle:*mut c_void)->*mut c_void{unsafe{IMAGE.as_mut_ptr() as *mut c_void}}
#[no_mangle] pub extern "C" fn ArtemisSetCooling(_handle:*mut c_void,setpoint:c_int)->c_int{SETPOINT.store(setpoint,Ordering::SeqCst);0}
#[no_mangle] pub unsafe extern "C" fn ArtemisCoolingInfo(_handle:*mut c_void,flags:*mut c_int,level:*mut c_int,minlvl:*mut c_int,maxlvl:*mut c_int,setpoint:*mut c_int)->c_int{if !flags.is_null(){*flags=1;} if !level.is_null(){*level=35;} if !minlvl.is_null(){*minlvl=0;} if !maxlvl.is_null(){*maxlvl=100;} if !setpoint.is_null(){*setpoint=SETPOINT.load(Ordering::SeqCst);} 0}
#[no_mangle] pub extern "C" fn ArtemisCoolerWarmUp(_handle:*mut c_void)->c_int{0}
#[no_mangle] pub unsafe extern "C" fn ArtemisTemperatureSensorInfo(_handle:*mut c_void,_sensor:c_int,temp:*mut c_int)->c_int{if !temp.is_null(){*temp=-950;} 0}
#[no_mangle] pub extern "C" fn ArtemisSetGain(_handle:*mut c_void,_preview:c_int,gain:c_int,offset:c_int)->c_int{GAIN.store(gain,Ordering::SeqCst); OFFSET.store(offset,Ordering::SeqCst); 0}
#[no_mangle] pub unsafe extern "C" fn ArtemisGetGain(_handle:*mut c_void,_preview:c_int,gain:*mut c_int,offset:*mut c_int)->c_int{if !gain.is_null(){*gain=GAIN.load(Ordering::SeqCst);} if !offset.is_null(){*offset=OFFSET.load(Ordering::SeqCst);} 0}
#[no_mangle] pub extern "C" fn ArtemisAPIVersion()->c_int{66000}
#[no_mangle] pub extern "C" fn ArtemisSetDarkMode(_handle:*mut c_void,_enable:c_int)->c_int{0}
#[no_mangle] pub extern "C" fn ArtemisEightBitMode(_handle:*mut c_void,_eightbit:c_int)->c_int{0}
"#;

    const SVBONY_FAKE_SDK: &str = r#"
#![allow(non_snake_case)]
use std::ffi::{c_char,c_int,c_long};
use std::sync::atomic::{AtomicI32,AtomicI64,Ordering};
static WIDTH:AtomicI32=AtomicI32::new(40); static HEIGHT:AtomicI32=AtomicI32::new(30); static BIN:AtomicI32=AtomicI32::new(1); static IMG_TYPE:AtomicI32=AtomicI32::new(4); static GAIN:AtomicI64=AtomicI64::new(0); static OFFSET:AtomicI64=AtomicI64::new(0); static COOLER:AtomicI64=AtomicI64::new(0); static TARGET_TEMP:AtomicI64=AtomicI64::new(-100);
#[repr(C)] struct SvbCameraInfo{friendly_name:[c_char;32],camera_sn:[c_char;32],port_type:[c_char;32],device_id:c_int,camera_id:c_int}
#[repr(C)] struct SvbCameraProperty{max_height:c_long,max_width:c_long,is_color_cam:c_int,bayer_pattern:c_int,supported_bins:[c_int;16],supported_video_format:[c_int;8],pixel_size:f64,mechanical_shutter:c_int,st4_port:c_int,is_cooler_cam:c_int,is_usb3_host:c_int,is_usb3_camera:c_int,elec_per_adu:f32,bit_depth:c_int,is_trigger_cam:c_int}
#[repr(C)] struct SvbCameraPropertyEx{b_support_pulse_guide:c_int,b_support_control_temp:c_int,output_mode_support:[c_int;8]}
#[repr(C)] struct SvbControlCaps{name:[c_char;64],description:[c_char;128],max_value:c_long,min_value:c_long,default_value:c_long,is_auto_supported:c_int,is_writable:c_int,control_type:c_int}
fn write_cstr(buf:&mut [c_char],text:&[u8]){for b in buf.iter_mut(){*b=0;} for i in 0..text.len().min(buf.len().saturating_sub(1)){buf[i]=text[i] as c_char;}}
#[no_mangle] pub extern "C" fn SVBGetNumOfConnectedCameras()->c_int{1}
#[no_mangle] pub unsafe extern "C" fn SVBGetCameraInfo(info:*mut SvbCameraInfo,index:c_int)->c_int{if info.is_null()||index!=0{return 1;} let mut v:SvbCameraInfo=std::mem::zeroed(); write_cstr(&mut v.friendly_name,b"Fake SV605CC"); write_cstr(&mut v.camera_sn,b"SVB-FAKE-0001"); write_cstr(&mut v.port_type,b"USB3"); v.device_id=0; v.camera_id=0; *info=v; 0}
#[no_mangle] pub unsafe extern "C" fn SVBGetCameraProperty(_id:c_int,prop:*mut SvbCameraProperty)->c_int{if prop.is_null(){return 16;} let mut v:SvbCameraProperty=std::mem::zeroed(); v.max_width=40; v.max_height=30; v.is_color_cam=1; v.bayer_pattern=0; v.supported_bins[0]=1; v.supported_bins[1]=2; v.supported_bins[2]=4; v.supported_video_format[0]=0; v.supported_video_format[1]=4; v.supported_video_format[2]=-1; v.pixel_size=2.9; v.st4_port=1; v.is_cooler_cam=1; v.is_usb3_host=1; v.is_usb3_camera=1; v.elec_per_adu=1.0; v.bit_depth=16; *prop=v; 0}
#[no_mangle] pub unsafe extern "C" fn SVBGetCameraPropertyEx(_id:c_int,prop:*mut SvbCameraPropertyEx)->c_int{if prop.is_null(){return 16;} let mut v:SvbCameraPropertyEx=std::mem::zeroed(); v.b_support_pulse_guide=1; v.b_support_control_temp=1; v.output_mode_support[0]=4; *prop=v; 0}
#[no_mangle] pub extern "C" fn SVBOpenCamera(id:c_int)->c_int{if id==0{0}else{2}}
#[no_mangle] pub extern "C" fn SVBCloseCamera(_id:c_int)->c_int{0}
#[no_mangle] pub unsafe extern "C" fn SVBGetNumOfControls(_id:c_int,num:*mut c_int)->c_int{if num.is_null(){return 16;} *num=7; 0}
#[no_mangle] pub unsafe extern "C" fn SVBGetControlCaps(_id:c_int,index:c_int,caps:*mut SvbControlCaps)->c_int{if caps.is_null(){return 16;} let controls=[(0,b"Gain".as_slice(),0,600,0),(1,b"Exposure".as_slice(),1,60_000_000,10_000),(13,b"BlackLevel".as_slice(),0,100,0),(14,b"CoolerEnable".as_slice(),0,1,0),(15,b"TargetTemp".as_slice(),-400,300,-100),(16,b"CurrentTemp".as_slice(),-500,500,-95),(17,b"CoolerPower".as_slice(),0,100,40)]; if index<0||index as usize>=controls.len(){return 1;} let (control_type,name,min,max,default_value)=controls[index as usize]; let mut v:SvbControlCaps=std::mem::zeroed(); write_cstr(&mut v.name,name); write_cstr(&mut v.description,b"Nightshade fake SVBONY control"); v.min_value=min; v.max_value=max; v.default_value=default_value; v.is_writable=1; v.control_type=control_type; *caps=v; 0}
#[no_mangle] pub unsafe extern "C" fn SVBGetControlValue(_id:c_int,ctrl:c_int,value:*mut c_long,is_auto:*mut c_int)->c_int{if value.is_null()||is_auto.is_null(){return 16;} *is_auto=0; let v=match ctrl{0=>GAIN.load(Ordering::SeqCst),1=>10_000,13=>OFFSET.load(Ordering::SeqCst),14=>COOLER.load(Ordering::SeqCst),15=>TARGET_TEMP.load(Ordering::SeqCst),16=>-95,17=>42,_=>return 3}; *value=v as c_long; 0}
#[no_mangle] pub extern "C" fn SVBSetControlValue(_id:c_int,ctrl:c_int,value:c_long,_is_auto:c_int)->c_int{match ctrl{0=>GAIN.store(value as i64,Ordering::SeqCst),13=>OFFSET.store(value as i64,Ordering::SeqCst),14=>COOLER.store(value as i64,Ordering::SeqCst),15=>TARGET_TEMP.store(value as i64,Ordering::SeqCst),_=>{}} 0}
#[no_mangle] pub extern "C" fn SVBSetROIFormat(_id:c_int,_x:c_int,_y:c_int,width:c_int,height:c_int,bin:c_int)->c_int{WIDTH.store(width,Ordering::SeqCst); HEIGHT.store(height,Ordering::SeqCst); BIN.store(bin,Ordering::SeqCst); 0}
#[no_mangle] pub unsafe extern "C" fn SVBGetROIFormat(_id:c_int,x:*mut c_int,y:*mut c_int,width:*mut c_int,height:*mut c_int,bin:*mut c_int)->c_int{if !x.is_null(){*x=0;} if !y.is_null(){*y=0;} if !width.is_null(){*width=WIDTH.load(Ordering::SeqCst);} if !height.is_null(){*height=HEIGHT.load(Ordering::SeqCst);} if !bin.is_null(){*bin=BIN.load(Ordering::SeqCst);} 0}
#[no_mangle] pub extern "C" fn SVBSetOutputImageType(_id:c_int,img_type:c_int)->c_int{IMG_TYPE.store(img_type,Ordering::SeqCst); 0}
#[no_mangle] pub unsafe extern "C" fn SVBGetOutputImageType(_id:c_int,img_type:*mut c_int)->c_int{if !img_type.is_null(){*img_type=IMG_TYPE.load(Ordering::SeqCst);} 0}
#[no_mangle] pub extern "C" fn SVBStartVideoCapture(_id:c_int)->c_int{0}
#[no_mangle] pub extern "C" fn SVBStopVideoCapture(_id:c_int)->c_int{0}
#[no_mangle] pub unsafe extern "C" fn SVBGetVideoData(_id:c_int,buf:*mut u8,buf_size:c_long,_wait_ms:c_int)->c_int{if buf.is_null()||buf_size<0{return 13;} for i in 0..((buf_size as usize)/2){let v=3000u16.wrapping_add(i as u16); *buf.add(i*2)=(v&0xff) as u8; *buf.add(i*2+1)=(v>>8) as u8;} 0}
#[no_mangle] pub extern "C" fn SVBGetSDKVersion()->*const c_char{b"fake-svbony-1.0\0".as_ptr() as *const c_char}
"#;
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
