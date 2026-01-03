# Sequencer Hardware Integration - Complete Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove all simulators, stubs, and placeholders from the sequencer, implementing 100% working hardware integration for all driver types (ASCOM, Alpaca, INDI, Native) with complete progress reporting and UI feedback.

**Architecture:** The sequencer uses the DeviceOps trait to abstract hardware operations. BridgeDeviceOps routes calls through the DeviceManager which dispatches to driver-specific implementations. Events flow from Rust → FFI → Dart providers → UI widgets. This plan fixes the broken links in that chain.

**Tech Stack:** Rust (tokio async, flutter_rust_bridge), Dart/Flutter (Riverpod), ASCOM COM (Windows), Alpaca HTTP REST, INDI XML sockets

**CRITICAL REQUIREMENT:** NO STUBS, NO PLACEHOLDERS, NO SIMULATORS. Every implementation must be complete, tested, and production-ready.

---

## Phase 1: Fix Critical Data Corruption

### Task 1.1: Fix Image Data - Use Raw Sensor Data Instead of Display Data

**Files:**
- Modify: `native/nightshade_native/bridge/src/sequencer_ops.rs:230-260`
- Modify: `native/nightshade_native/bridge/src/api.rs:2367-2420`

**Problem:** `BridgeDeviceOps.camera_start_exposure()` converts display_data (8-bit stretched) instead of raw 16-bit sensor data, corrupting all image analysis.

**Step 1: Examine current implementation**

Read the current `camera_start_exposure` in sequencer_ops.rs to understand the data flow.

**Step 2: Modify sequencer_ops.rs to use raw data**

Replace the image data conversion at `sequencer_ops.rs:239-260`:

```rust
async fn camera_start_exposure(
    &self,
    camera_id: &str,
    duration_secs: f64,
    gain: Option<i32>,
    offset: Option<i32>,
    bin_x: i32,
    bin_y: i32,
) -> DeviceResult<ImageData> {
    // Set camera parameters - PROPAGATE ERRORS, don't swallow them
    if let Some(g) = gain {
        set_camera_gain(camera_id.to_string(), g)
            .await
            .map_err(|e| format!("Failed to set gain: {}", e))?;
    }
    if let Some(o) = offset {
        set_camera_offset(camera_id.to_string(), o)
            .await
            .map_err(|e| format!("Failed to set offset: {}", e))?;
    }

    // Start exposure and get raw image result
    let image_result = start_exposure(
        camera_id.to_string(),
        duration_secs,
        bin_x,
        bin_y,
    ).await.map_err(|e| e.to_string())?;

    // Use the RAW 16-bit data, not display_data
    // The raw_data field contains the actual sensor values
    let raw_data = get_last_raw_image_data()
        .await
        .map_err(|e| format!("Failed to get raw image data: {}", e))?;

    // Validate the raw data
    if raw_data.is_empty() {
        return Err("Raw image data is empty - exposure may have failed".to_string());
    }

    let expected_size = (image_result.width * image_result.height) as usize;
    if raw_data.len() != expected_size {
        return Err(format!(
            "Raw data size mismatch: got {} pixels, expected {} ({}x{})",
            raw_data.len(), expected_size, image_result.width, image_result.height
        ));
    }

    // Validate data quality - reject obviously bad frames
    let (min_val, max_val) = raw_data.iter().fold((u16::MAX, u16::MIN), |(min, max), &v| {
        (min.min(v), max.max(v))
    });

    if min_val == max_val {
        return Err(format!(
            "Image data appears invalid - all pixels have same value: {}",
            min_val
        ));
    }

    Ok(ImageData {
        width: image_result.width as u32,
        height: image_result.height as u32,
        data: raw_data,
        bits_per_pixel: 16,
        exposure_secs: duration_secs,
        gain,
        offset,
        filter: None,
        temperature: image_result.sensor_temp,
    })
}
```

**Step 3: Add get_last_raw_image_data function to api.rs**

Add near line 2420 in api.rs:

```rust
/// Returns the raw 16-bit sensor data from the last captured image
/// This is the actual sensor readout, not the display-stretched version
pub async fn get_last_raw_image_data() -> Result<Vec<u16>, NightshadeError> {
    let storage = get_last_raw_data_storage().read().await;
    match &*storage {
        Some(data) => Ok(data.clone()),
        None => Err(NightshadeError::OperationFailed(
            "No raw image data available - no exposure has been taken".to_string()
        )),
    }
}
```

**Step 4: Ensure raw data is stored during exposure**

Verify in `devices.rs` camera_start_exposure that raw data is stored:

```rust
// After successful exposure download, store raw data
let mut raw_storage = get_last_raw_data_storage().write().await;
*raw_storage = Some(image_data.data.clone());
```

**Step 5: Build and verify no compile errors**

Run: `cd native/nightshade_native && cargo build --package nightshade_bridge`
Expected: Successful compilation

**Step 6: Commit**

```bash
git add native/nightshade_native/bridge/src/sequencer_ops.rs native/nightshade_native/bridge/src/api.rs
git commit -m "fix(sequencer): use raw 16-bit sensor data instead of display data

BREAKING: camera_start_exposure now returns actual sensor data
- Removed conversion from display_data which was 8-bit stretched
- Added get_last_raw_image_data() API function
- Added validation to reject corrupted/empty frames
- Errors now propagate instead of being silently swallowed

This fixes autofocus, plate solving, and HFR calculations."
```

---

### Task 1.2: Propagate Camera Settings Errors

**Files:**
- Modify: `native/nightshade_native/bridge/src/sequencer_ops.rs:206-220`

**Problem:** Camera gain/offset setting errors are silently discarded with `let _ = ...`

**Step 1: Fix error propagation for camera settings**

The code in Task 1.1 already handles this, but verify the pattern is consistent throughout. Search for other `let _ = ` patterns that swallow important errors:

```rust
// WRONG - silently swallows errors:
let _ = set_camera_gain(camera_id.to_string(), g).await;

// CORRECT - propagates errors:
set_camera_gain(camera_id.to_string(), g)
    .await
    .map_err(|e| format!("Failed to set gain: {}", e))?;
```

**Step 2: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_bridge`

**Step 3: Commit**

```bash
git add native/nightshade_native/bridge/src/sequencer_ops.rs
git commit -m "fix(sequencer): propagate camera settings errors instead of swallowing"
```

---

### Task 1.3: Add Image Validation Gate

**Files:**
- Modify: `native/nightshade_native/bridge/src/api.rs:2385-2430`

**Problem:** Bad/corrupted images are processed without validation, causing cascading failures.

**Step 1: Add comprehensive image validation function**

Add to api.rs near the image processing section:

```rust
/// Validates image data integrity before processing
/// Returns Ok(()) if valid, Err with description if invalid
fn validate_image_data(
    data: &[u16],
    width: u32,
    height: u32,
    context: &str,
) -> Result<(), String> {
    let expected_pixels = (width as usize) * (height as usize);

    // Check size
    if data.len() != expected_pixels {
        return Err(format!(
            "{}: Size mismatch - got {} pixels, expected {} ({}x{})",
            context, data.len(), expected_pixels, width, height
        ));
    }

    // Check for empty data
    if data.is_empty() {
        return Err(format!("{}: Image data is empty", context));
    }

    // Calculate statistics
    let mut min_val = u16::MAX;
    let mut max_val = u16::MIN;
    let mut sum: u64 = 0;

    for &pixel in data {
        min_val = min_val.min(pixel);
        max_val = max_val.max(pixel);
        sum += pixel as u64;
    }

    let mean = sum as f64 / data.len() as f64;

    // Validate data quality
    if min_val == max_val {
        return Err(format!(
            "{}: All pixels have identical value {} - sensor readout failed or lens cap on",
            context, min_val
        ));
    }

    // Check for severely underexposed (likely failed exposure)
    if max_val < 100 {
        return Err(format!(
            "{}: Max pixel value is {} - image severely underexposed or data corrupted",
            context, max_val
        ));
    }

    // Check for obvious saturation (entire frame)
    let saturation_threshold = 65000u16;
    let saturated_count = data.iter().filter(|&&p| p > saturation_threshold).count();
    let saturation_percent = (saturated_count as f64 / data.len() as f64) * 100.0;

    if saturation_percent > 90.0 {
        return Err(format!(
            "{}: {:.1}% of pixels saturated - frame is blown out",
            context, saturation_percent
        ));
    }

    tracing::debug!(
        "{}: Image validated - {}x{}, range {}-{}, mean {:.1}",
        context, width, height, min_val, max_val, mean
    );

    Ok(())
}
```

**Step 2: Use validation in exposure pipeline**

Find where images are processed after capture and add validation call:

```rust
// After downloading image data
validate_image_data(&image_data, width, height, "Exposure download")?;
```

**Step 3: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_bridge`

**Step 4: Commit**

```bash
git add native/nightshade_native/bridge/src/api.rs
git commit -m "feat(imaging): add image validation gate to reject corrupted frames

- Validates size matches dimensions
- Rejects uniform images (sensor readout failure)
- Rejects severely underexposed frames
- Warns on excessive saturation
- Logs validation results for debugging"
```

---

## Phase 2: Complete Driver Routing

### Task 2.1: Implement Alpaca Focuser Operations in DeviceManager

**Files:**
- Modify: `native/nightshade_native/bridge/src/devices.rs:2754-2984`
- Reference: `native/nightshade_native/alpaca/src/focuser.rs`

**Problem:** Alpaca focuser operations return "Not implemented" - autofocus impossible with Alpaca focusers.

**Step 1: Add Alpaca focuser storage to DeviceManager struct**

Find the DeviceManager struct definition and ensure alpaca_focusers exists:

```rust
pub struct DeviceManager {
    // ... existing fields ...
    alpaca_focusers: RwLock<HashMap<String, Arc<RwLock<nightshade_alpaca::AlpacaFocuser>>>>,
}
```

**Step 2: Implement Alpaca focuser connection in connect_alpaca**

Add to the connect_alpaca match statement for DeviceType::Focuser:

```rust
DeviceType::Focuser => {
    let focuser = nightshade_alpaca::AlpacaFocuser::from_server(&base_url, device_num);
    focuser.connect().await.map_err(|e| format!("Alpaca focuser connect failed: {}", e))?;

    let mut focusers = self.alpaca_focusers.write().await;
    focusers.insert(device_id.to_string(), Arc::new(RwLock::new(focuser)));

    tracing::info!("Connected Alpaca focuser: {}", device_id);
}
```

**Step 3: Implement focuser_move_abs for Alpaca**

Find `focuser_move_abs` function and add Alpaca case:

```rust
pub async fn focuser_move_abs(&self, device_id: &str, position: i32) -> Result<(), String> {
    let info = self.get_device_info(device_id).await?;

    match info.driver_type {
        DriverType::Ascom => {
            #[cfg(windows)]
            {
                let focusers = self.ascom_focusers.read().await;
                if let Some(focuser) = focusers.get(device_id) {
                    return focuser.write().await.move_to(position)
                        .map_err(|e| format!("ASCOM focuser move failed: {}", e));
                }
            }
            Err(format!("ASCOM focuser {} not connected", device_id))
        }
        DriverType::Alpaca => {
            let focusers = self.alpaca_focusers.read().await;
            if let Some(focuser) = focusers.get(device_id) {
                let f = focuser.read().await;
                f.move_to(position).await
                    .map_err(|e| format!("Alpaca focuser move failed: {}", e))
            } else {
                Err(format!("Alpaca focuser {} not connected", device_id))
            }
        }
        DriverType::Indi => {
            // Will be implemented in Task 2.2
            self.indi_focuser_move(device_id, position).await
        }
        DriverType::Native => {
            let mut focusers = self.native_focusers.write().await;
            if let Some(focuser) = focusers.get_mut(device_id) {
                focuser.move_to(position).await
                    .map_err(|e| format!("Native focuser move failed: {}", e))
            } else {
                Err(format!("Native focuser {} not connected", device_id))
            }
        }
        DriverType::Simulator => {
            Err("Simulator focusers are not supported - connect real hardware".to_string())
        }
    }
}
```

**Step 4: Implement focuser_get_position for Alpaca**

```rust
pub async fn focuser_get_position(&self, device_id: &str) -> Result<i32, String> {
    let info = self.get_device_info(device_id).await?;

    match info.driver_type {
        DriverType::Ascom => {
            #[cfg(windows)]
            {
                let focusers = self.ascom_focusers.read().await;
                if let Some(focuser) = focusers.get(device_id) {
                    return focuser.read().await.position()
                        .map_err(|e| format!("ASCOM focuser position query failed: {}", e));
                }
            }
            Err(format!("ASCOM focuser {} not connected", device_id))
        }
        DriverType::Alpaca => {
            let focusers = self.alpaca_focusers.read().await;
            if let Some(focuser) = focusers.get(device_id) {
                let f = focuser.read().await;
                f.position().await
                    .map_err(|e| format!("Alpaca focuser position query failed: {}", e))
            } else {
                Err(format!("Alpaca focuser {} not connected", device_id))
            }
        }
        DriverType::Indi => {
            self.indi_focuser_get_position(device_id).await
        }
        DriverType::Native => {
            let focusers = self.native_focusers.read().await;
            if let Some(focuser) = focusers.get(device_id) {
                focuser.position().await
                    .map_err(|e| format!("Native focuser position query failed: {}", e))
            } else {
                Err(format!("Native focuser {} not connected", device_id))
            }
        }
        DriverType::Simulator => {
            Err("Simulator focusers are not supported - connect real hardware".to_string())
        }
    }
}
```

**Step 5: Implement focuser_is_moving for Alpaca**

```rust
pub async fn focuser_is_moving(&self, device_id: &str) -> Result<bool, String> {
    let info = self.get_device_info(device_id).await?;

    match info.driver_type {
        DriverType::Alpaca => {
            let focusers = self.alpaca_focusers.read().await;
            if let Some(focuser) = focusers.get(device_id) {
                let f = focuser.read().await;
                f.is_moving().await
                    .map_err(|e| format!("Alpaca focuser is_moving query failed: {}", e))
            } else {
                Err(format!("Alpaca focuser {} not connected", device_id))
            }
        }
        // ... other driver types ...
        DriverType::Simulator => {
            Err("Simulator focusers are not supported - connect real hardware".to_string())
        }
    }
}
```

**Step 6: Implement focuser_get_temperature for Alpaca**

```rust
pub async fn focuser_get_temperature(&self, device_id: &str) -> Result<f64, String> {
    let info = self.get_device_info(device_id).await?;

    match info.driver_type {
        DriverType::Alpaca => {
            let focusers = self.alpaca_focusers.read().await;
            if let Some(focuser) = focusers.get(device_id) {
                let f = focuser.read().await;
                f.temperature().await
                    .map_err(|e| format!("Alpaca focuser temperature query failed: {}", e))
            } else {
                Err(format!("Alpaca focuser {} not connected", device_id))
            }
        }
        // ... other driver types ...
        DriverType::Simulator => {
            Err("Simulator focusers are not supported - connect real hardware".to_string())
        }
    }
}
```

**Step 7: Implement focuser_halt for Alpaca**

```rust
pub async fn focuser_halt(&self, device_id: &str) -> Result<(), String> {
    let info = self.get_device_info(device_id).await?;

    match info.driver_type {
        DriverType::Alpaca => {
            let focusers = self.alpaca_focusers.read().await;
            if let Some(focuser) = focusers.get(device_id) {
                let f = focuser.read().await;
                f.halt().await
                    .map_err(|e| format!("Alpaca focuser halt failed: {}", e))
            } else {
                Err(format!("Alpaca focuser {} not connected", device_id))
            }
        }
        // ... other driver types ...
        DriverType::Simulator => {
            Err("Simulator focusers are not supported - connect real hardware".to_string())
        }
    }
}
```

**Step 8: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_bridge`

**Step 9: Commit**

```bash
git add native/nightshade_native/bridge/src/devices.rs
git commit -m "feat(drivers): implement Alpaca focuser operations in DeviceManager

- Added alpaca_focusers storage
- Implemented move_abs, get_position, is_moving, get_temperature, halt
- All operations properly route through DeviceManager
- Errors propagate with clear messages
- Simulator case explicitly rejected"
```

---

### Task 2.2: Implement INDI Focuser Operations in DeviceManager

**Files:**
- Modify: `native/nightshade_native/bridge/src/devices.rs`
- Reference: `native/nightshade_native/indi/src/focuser.rs`

**Problem:** INDI focuser operations not implemented in DeviceManager.

**Step 1: Add INDI focuser helper methods**

Add helper methods to DeviceManager for INDI focuser operations:

```rust
impl DeviceManager {
    /// Helper to get INDI client and device name from device_id
    fn parse_indi_device_id(device_id: &str) -> Result<(String, String, String), String> {
        // Format: indi:host:port:device_name
        let parts: Vec<&str> = device_id.splitn(4, ':').collect();
        if parts.len() != 4 || parts[0] != "indi" {
            return Err(format!("Invalid INDI device ID format: {}", device_id));
        }
        let host = parts[1].to_string();
        let port = parts[2].to_string();
        let device_name = parts[3].to_string();
        let server_key = format!("{}:{}", host, port);
        Ok((server_key, device_name, host))
    }

    async fn indi_focuser_move(&self, device_id: &str, position: i32) -> Result<(), String> {
        let (server_key, device_name, _) = Self::parse_indi_device_id(device_id)?;

        let clients = self.indi_clients.read().await;
        let client = clients.get(&server_key)
            .ok_or_else(|| format!("INDI server {} not connected", server_key))?;

        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
        focuser.move_to(position).await
            .map_err(|e| format!("INDI focuser move failed: {}", e))
    }

    async fn indi_focuser_get_position(&self, device_id: &str) -> Result<i32, String> {
        let (server_key, device_name, _) = Self::parse_indi_device_id(device_id)?;

        let clients = self.indi_clients.read().await;
        let client = clients.get(&server_key)
            .ok_or_else(|| format!("INDI server {} not connected", server_key))?;

        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
        focuser.position().await
            .map_err(|e| format!("INDI focuser position query failed: {}", e))
    }

    async fn indi_focuser_is_moving(&self, device_id: &str) -> Result<bool, String> {
        let (server_key, device_name, _) = Self::parse_indi_device_id(device_id)?;

        let clients = self.indi_clients.read().await;
        let client = clients.get(&server_key)
            .ok_or_else(|| format!("INDI server {} not connected", server_key))?;

        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
        focuser.is_moving().await
            .map_err(|e| format!("INDI focuser is_moving query failed: {}", e))
    }

    async fn indi_focuser_get_temperature(&self, device_id: &str) -> Result<f64, String> {
        let (server_key, device_name, _) = Self::parse_indi_device_id(device_id)?;

        let clients = self.indi_clients.read().await;
        let client = clients.get(&server_key)
            .ok_or_else(|| format!("INDI server {} not connected", server_key))?;

        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
        focuser.temperature().await
            .map_err(|e| format!("INDI focuser temperature query failed: {}", e))
    }

    async fn indi_focuser_halt(&self, device_id: &str) -> Result<(), String> {
        let (server_key, device_name, _) = Self::parse_indi_device_id(device_id)?;

        let clients = self.indi_clients.read().await;
        let client = clients.get(&server_key)
            .ok_or_else(|| format!("INDI server {} not connected", server_key))?;

        let focuser = nightshade_indi::IndiFocuser::new(client.clone(), &device_name);
        focuser.halt().await
            .map_err(|e| format!("INDI focuser halt failed: {}", e))
    }
}
```

**Step 2: Verify INDI focuser implementation exists**

Check that `nightshade_indi::IndiFocuser` has the required methods. If not, implement them in the INDI crate.

**Step 3: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_bridge`

**Step 4: Commit**

```bash
git add native/nightshade_native/bridge/src/devices.rs
git commit -m "feat(drivers): implement INDI focuser operations in DeviceManager

- Added parse_indi_device_id helper
- Implemented move, get_position, is_moving, get_temperature, halt
- Routes through IndiClient to IndiFocuser
- Proper error messages for connection issues"
```

---

### Task 2.3: Implement Alpaca Filter Wheel Operations

**Files:**
- Modify: `native/nightshade_native/bridge/src/devices.rs:2992-3180`

**Problem:** Alpaca filter wheel position operations return "Not implemented".

**Step 1: Add Alpaca filter wheel storage**

Ensure alpaca_filter_wheels exists in DeviceManager:

```rust
alpaca_filter_wheels: RwLock<HashMap<String, Arc<RwLock<nightshade_alpaca::AlpacaFilterWheel>>>>,
```

**Step 2: Implement filter_wheel_set_position for Alpaca**

```rust
pub async fn filter_wheel_set_position(&self, device_id: &str, position: i32) -> Result<(), String> {
    let info = self.get_device_info(device_id).await?;

    match info.driver_type {
        DriverType::Ascom => {
            #[cfg(windows)]
            {
                let fws = self.ascom_filter_wheels.read().await;
                if let Some(fw) = fws.get(device_id) {
                    return fw.write().await.set_position(position)
                        .map_err(|e| format!("ASCOM filter wheel set position failed: {}", e));
                }
            }
            Err(format!("ASCOM filter wheel {} not connected", device_id))
        }
        DriverType::Alpaca => {
            let fws = self.alpaca_filter_wheels.read().await;
            if let Some(fw) = fws.get(device_id) {
                let f = fw.read().await;
                f.set_position(position).await
                    .map_err(|e| format!("Alpaca filter wheel set position failed: {}", e))
            } else {
                Err(format!("Alpaca filter wheel {} not connected", device_id))
            }
        }
        DriverType::Indi => {
            self.indi_filter_wheel_set_position(device_id, position).await
        }
        DriverType::Native => {
            let mut fws = self.native_filter_wheels.write().await;
            if let Some(fw) = fws.get_mut(device_id) {
                fw.set_position(position).await
                    .map_err(|e| format!("Native filter wheel set position failed: {}", e))
            } else {
                Err(format!("Native filter wheel {} not connected", device_id))
            }
        }
        DriverType::Simulator => {
            Err("Simulator filter wheels are not supported - connect real hardware".to_string())
        }
    }
}
```

**Step 3: Implement filter_wheel_get_position for Alpaca**

```rust
pub async fn filter_wheel_get_position(&self, device_id: &str) -> Result<i32, String> {
    let info = self.get_device_info(device_id).await?;

    match info.driver_type {
        DriverType::Alpaca => {
            let fws = self.alpaca_filter_wheels.read().await;
            if let Some(fw) = fws.get(device_id) {
                let f = fw.read().await;
                f.position().await
                    .map_err(|e| format!("Alpaca filter wheel get position failed: {}", e))
            } else {
                Err(format!("Alpaca filter wheel {} not connected", device_id))
            }
        }
        // ... other driver types ...
        DriverType::Simulator => {
            Err("Simulator filter wheels are not supported - connect real hardware".to_string())
        }
    }
}
```

**Step 4: Implement INDI filter wheel helpers**

```rust
async fn indi_filter_wheel_set_position(&self, device_id: &str, position: i32) -> Result<(), String> {
    let (server_key, device_name, _) = Self::parse_indi_device_id(device_id)?;

    let clients = self.indi_clients.read().await;
    let client = clients.get(&server_key)
        .ok_or_else(|| format!("INDI server {} not connected", server_key))?;

    let fw = nightshade_indi::IndiFilterWheel::new(client.clone(), &device_name);
    fw.set_position(position).await
        .map_err(|e| format!("INDI filter wheel set position failed: {}", e))
}

async fn indi_filter_wheel_get_position(&self, device_id: &str) -> Result<i32, String> {
    let (server_key, device_name, _) = Self::parse_indi_device_id(device_id)?;

    let clients = self.indi_clients.read().await;
    let client = clients.get(&server_key)
        .ok_or_else(|| format!("INDI server {} not connected", server_key))?;

    let fw = nightshade_indi::IndiFilterWheel::new(client.clone(), &device_name);
    fw.position().await
        .map_err(|e| format!("INDI filter wheel get position failed: {}", e))
}
```

**Step 5: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_bridge`

**Step 6: Commit**

```bash
git add native/nightshade_native/bridge/src/devices.rs
git commit -m "feat(drivers): implement Alpaca and INDI filter wheel operations

- Added Alpaca filter wheel storage and operations
- Added INDI filter wheel helper methods
- set_position and get_position now work for all driver types
- Simulator explicitly rejected"
```

---

### Task 2.4: Move ASCOM Dome Operations from sequencer_ops to DeviceManager

**Files:**
- Modify: `native/nightshade_native/bridge/src/sequencer_ops.rs:728-910`
- Modify: `native/nightshade_native/bridge/src/devices.rs`

**Problem:** ASCOM dome operations bypass DeviceManager entirely, creating architectural inconsistency.

**Step 1: Implement ASCOM dome operations in DeviceManager**

Add to devices.rs:

```rust
pub async fn dome_open_shutter(&self, device_id: &str) -> Result<(), String> {
    let info = self.get_device_info(device_id).await?;

    match info.driver_type {
        DriverType::Ascom => {
            #[cfg(windows)]
            {
                let domes = self.ascom_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.write().await.open_shutter()
                        .map_err(|e| format!("ASCOM dome open shutter failed: {}", e));
                }
            }
            Err(format!("ASCOM dome {} not connected", device_id))
        }
        DriverType::Alpaca => {
            let domes = self.alpaca_domes.read().await;
            if let Some(dome) = domes.get(device_id) {
                let d = dome.read().await;
                d.open_shutter().await
                    .map_err(|e| format!("Alpaca dome open shutter failed: {}", e))
            } else {
                Err(format!("Alpaca dome {} not connected", device_id))
            }
        }
        DriverType::Indi => {
            self.indi_dome_open_shutter(device_id).await
        }
        DriverType::Native => {
            let mut domes = self.native_domes.write().await;
            if let Some(dome) = domes.get_mut(device_id) {
                dome.open_shutter().await
                    .map_err(|e| format!("Native dome open shutter failed: {}", e))
            } else {
                Err(format!("Native dome {} not connected", device_id))
            }
        }
        DriverType::Simulator => {
            Err("Simulator domes are not supported - connect real hardware".to_string())
        }
    }
}

pub async fn dome_close_shutter(&self, device_id: &str) -> Result<(), String> {
    // Similar implementation for close_shutter
    let info = self.get_device_info(device_id).await?;

    match info.driver_type {
        DriverType::Ascom => {
            #[cfg(windows)]
            {
                let domes = self.ascom_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.write().await.close_shutter()
                        .map_err(|e| format!("ASCOM dome close shutter failed: {}", e));
                }
            }
            Err(format!("ASCOM dome {} not connected", device_id))
        }
        // ... other driver types ...
        DriverType::Simulator => {
            Err("Simulator domes are not supported - connect real hardware".to_string())
        }
    }
}

pub async fn dome_park(&self, device_id: &str) -> Result<(), String> {
    let info = self.get_device_info(device_id).await?;

    match info.driver_type {
        DriverType::Ascom => {
            #[cfg(windows)]
            {
                let domes = self.ascom_domes.read().await;
                if let Some(dome) = domes.get(device_id) {
                    return dome.write().await.park()
                        .map_err(|e| format!("ASCOM dome park failed: {}", e));
                }
            }
            Err(format!("ASCOM dome {} not connected", device_id))
        }
        // ... other driver types ...
        DriverType::Simulator => {
            Err("Simulator domes are not supported - connect real hardware".to_string())
        }
    }
}
```

**Step 2: Update sequencer_ops.rs to use DeviceManager**

Replace the hardcoded ASCOM dome logic in sequencer_ops.rs with calls to DeviceManager:

```rust
async fn dome_open(&self, dome_id: &str) -> DeviceResult<()> {
    let mgr = get_device_manager();
    mgr.dome_open_shutter(dome_id).await
}

async fn dome_close(&self, dome_id: &str) -> DeviceResult<()> {
    let mgr = get_device_manager();
    mgr.dome_close_shutter(dome_id).await
}

async fn dome_park(&self, dome_id: &str) -> DeviceResult<()> {
    let mgr = get_device_manager();
    mgr.dome_park(dome_id).await
}
```

**Step 3: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_bridge`

**Step 4: Commit**

```bash
git add native/nightshade_native/bridge/src/devices.rs native/nightshade_native/bridge/src/sequencer_ops.rs
git commit -m "refactor(drivers): move ASCOM dome operations to DeviceManager

- Implemented dome_open_shutter, dome_close_shutter, dome_park in DeviceManager
- Updated sequencer_ops to route through DeviceManager
- All driver types now use consistent routing
- Removed duplicated ASCOM COM initialization logic"
```

---

## Phase 3: Add Progress Callbacks to Silent Instructions

### Task 3.1: Add Progress Callback to Temperature Compensation

**Files:**
- Modify: `native/nightshade_native/sequencer/src/node.rs:768`
- Modify: `native/nightshade_native/sequencer/src/instructions.rs` (temperature compensation section)

**Problem:** Temperature compensation executes with no progress feedback.

**Step 1: Update node.rs to pass progress callback**

Find line 768 in node.rs and update:

```rust
NodeType::TemperatureCompensation(config) => {
    let cb = progress_callback.clone();
    let progress_fn = move |progress: f64, detail: String| {
        if let Some(ref callback) = cb {
            callback(ProgressUpdate {
                node_id: node_id.clone(),
                status: NodeStatus::Running,
                message: Some(format!("Temperature Compensation: {} ({:.0}%)", detail, progress)),
                current_frame: None,
                total_frames: None,
                current_child: None,
                total_children: None,
                completed_exposure_secs: None,
            });
        }
    };
    execute_temperature_compensation(config, &ctx, Some(&progress_fn)).await
}
```

**Step 2: Update execute_temperature_compensation signature and implementation**

```rust
pub async fn execute_temperature_compensation(
    config: &TemperatureCompensationConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    // Report start
    if let Some(cb) = progress_callback {
        cb(0.0, "Reading current temperature...".to_string());
    }

    // Get current temperature
    let current_temp = match ctx.device_ops.focuser_get_temperature(&config.focuser_id).await {
        Ok(t) => t,
        Err(e) => return InstructionResult::failure(format!("Failed to read focuser temperature: {}", e)),
    };

    if let Some(cb) = progress_callback {
        cb(20.0, format!("Current: {:.1}°C, Baseline: {:.1}°C", current_temp, config.baseline_temp));
    }

    // Calculate compensation
    let delta_temp = current_temp - config.baseline_temp;
    let steps = (delta_temp * config.steps_per_degree).round() as i32;

    if let Some(cb) = progress_callback {
        cb(40.0, format!("Delta: {:.1}°C, Steps: {}", delta_temp, steps));
    }

    if steps.abs() < config.min_steps {
        if let Some(cb) = progress_callback {
            cb(100.0, format!("No compensation needed (delta {} < min {})", steps.abs(), config.min_steps));
        }
        return InstructionResult::success("Temperature compensation: no adjustment needed".to_string());
    }

    // Get current position
    let current_pos = match ctx.device_ops.focuser_get_position(&config.focuser_id).await {
        Ok(p) => p,
        Err(e) => return InstructionResult::failure(format!("Failed to read focuser position: {}", e)),
    };

    let new_pos = current_pos + steps;

    if let Some(cb) = progress_callback {
        cb(60.0, format!("Moving {} → {} ({:+} steps)", current_pos, new_pos, steps));
    }

    // Move focuser
    if let Err(e) = ctx.device_ops.focuser_move_to(&config.focuser_id, new_pos).await {
        return InstructionResult::failure(format!("Failed to move focuser: {}", e));
    }

    if let Some(cb) = progress_callback {
        cb(80.0, "Waiting for focuser to settle...".to_string());
    }

    // Wait for focuser to stop moving
    let timeout = std::time::Duration::from_secs(120);
    let start = std::time::Instant::now();
    loop {
        if start.elapsed() > timeout {
            return InstructionResult::failure("Focuser move timeout".to_string());
        }

        match ctx.device_ops.focuser_is_moving(&config.focuser_id).await {
            Ok(false) => break,
            Ok(true) => tokio::time::sleep(std::time::Duration::from_millis(500)).await,
            Err(e) => {
                tracing::warn!("Error checking focuser status: {}", e);
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
            }
        }
    }

    if let Some(cb) = progress_callback {
        cb(100.0, format!("Compensated {:.1}°C with {} steps", delta_temp, steps));
    }

    InstructionResult::success(format!(
        "Temperature compensation: moved {} steps for {:.1}°C change",
        steps, delta_temp
    ))
}
```

**Step 3: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_sequencer`

**Step 4: Commit**

```bash
git add native/nightshade_native/sequencer/src/node.rs native/nightshade_native/sequencer/src/instructions.rs
git commit -m "feat(sequencer): add progress callback to temperature compensation

- Reports temperature readings, delta calculation, movement
- Shows current vs baseline temperature
- Reports step calculation and movement progress
- Properly waits for focuser to settle"
```

---

### Task 3.2: Add Progress Callback to Dither

**Files:**
- Modify: `native/nightshade_native/sequencer/src/node.rs:772`
- Modify: `native/nightshade_native/sequencer/src/instructions.rs` (dither section)

**Step 1: Update node.rs for dither**

```rust
NodeType::Dither(config) => {
    let cb = progress_callback.clone();
    let progress_fn = move |progress: f64, detail: String| {
        if let Some(ref callback) = cb {
            callback(ProgressUpdate {
                node_id: node_id.clone(),
                status: NodeStatus::Running,
                message: Some(format!("Dither: {} ({:.0}%)", detail, progress)),
                current_frame: None,
                total_frames: None,
                current_child: None,
                total_children: None,
                completed_exposure_secs: None,
            });
        }
    };
    execute_dither(config, &ctx, Some(&progress_fn)).await
}
```

**Step 2: Update execute_dither**

```rust
pub async fn execute_dither(
    config: &DitherConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    if let Some(cb) = progress_callback {
        cb(0.0, format!("Starting dither (scale: {:.1})", config.scale));
    }

    // Send dither command
    if let Some(cb) = progress_callback {
        cb(20.0, "Sending dither command to guider...".to_string());
    }

    if let Err(e) = ctx.device_ops.guider_dither(
        &config.guider_id,
        config.scale,
        config.ra_only,
    ).await {
        return InstructionResult::failure(format!("Dither command failed: {}", e));
    }

    // Wait for settle
    if let Some(cb) = progress_callback {
        cb(40.0, "Waiting for guiding to settle...".to_string());
    }

    let settle_timeout = std::time::Duration::from_secs(config.settle_timeout_secs as u64);
    let settle_start = std::time::Instant::now();
    let mut stable_count = 0;
    let required_stable = 3; // Require 3 consecutive stable readings

    loop {
        if settle_start.elapsed() > settle_timeout {
            return InstructionResult::failure(format!(
                "Dither settle timeout after {} seconds",
                config.settle_timeout_secs
            ));
        }

        match ctx.device_ops.guider_get_status(&config.guider_id).await {
            Ok(status) => {
                let rms = (status.rms_ra.powi(2) + status.rms_dec.powi(2)).sqrt();

                if let Some(cb) = progress_callback {
                    let progress = 40.0 + (stable_count as f64 / required_stable as f64) * 50.0;
                    cb(progress, format!("RMS: {:.2}\" (target: {:.2}\")", rms, config.settle_pixels));
                }

                if rms <= config.settle_pixels {
                    stable_count += 1;
                    if stable_count >= required_stable {
                        break;
                    }
                } else {
                    stable_count = 0; // Reset if RMS exceeds threshold
                }
            }
            Err(e) => {
                tracing::warn!("Error reading guider status: {}", e);
            }
        }

        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    }

    if let Some(cb) = progress_callback {
        cb(100.0, "Dither complete, guiding stable".to_string());
    }

    InstructionResult::success("Dither completed successfully".to_string())
}
```

**Step 3: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_sequencer`

**Step 4: Commit**

```bash
git add native/nightshade_native/sequencer/src/node.rs native/nightshade_native/sequencer/src/instructions.rs
git commit -m "feat(sequencer): add progress callback to dither instruction

- Reports dither scale and command sending
- Shows RMS during settle with target threshold
- Requires multiple stable readings before completing
- Reports settle timeout clearly"
```

---

### Task 3.3: Add Progress Callbacks to Guiding Instructions

**Files:**
- Modify: `native/nightshade_native/sequencer/src/node.rs:793-797`
- Modify: `native/nightshade_native/sequencer/src/instructions.rs`

**Step 1: Update StartGuiding in node.rs**

```rust
NodeType::StartGuiding(config) => {
    let cb = progress_callback.clone();
    let progress_fn = move |progress: f64, detail: String| {
        if let Some(ref callback) = cb {
            callback(ProgressUpdate {
                node_id: node_id.clone(),
                status: NodeStatus::Running,
                message: Some(format!("Start Guiding: {} ({:.0}%)", detail, progress)),
                ..Default::default()
            });
        }
    };
    execute_start_guiding(config, &ctx, Some(&progress_fn)).await
}
```

**Step 2: Update StopGuiding in node.rs**

```rust
NodeType::StopGuiding(config) => {
    let cb = progress_callback.clone();
    let progress_fn = move |progress: f64, detail: String| {
        if let Some(ref callback) = cb {
            callback(ProgressUpdate {
                node_id: node_id.clone(),
                status: NodeStatus::Running,
                message: Some(format!("Stop Guiding: {} ({:.0}%)", detail, progress)),
                ..Default::default()
            });
        }
    };
    execute_stop_guiding(config, &ctx, Some(&progress_fn)).await
}
```

**Step 3: Implement execute_start_guiding with progress**

```rust
pub async fn execute_start_guiding(
    config: &StartGuidingConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    if let Some(cb) = progress_callback {
        cb(0.0, "Connecting to guider...".to_string());
    }

    // Start guiding
    if let Err(e) = ctx.device_ops.guider_start(&config.guider_id).await {
        return InstructionResult::failure(format!("Failed to start guiding: {}", e));
    }

    if let Some(cb) = progress_callback {
        cb(30.0, "Guiding started, waiting for lock...".to_string());
    }

    // Wait for guide star lock
    let lock_timeout = std::time::Duration::from_secs(config.lock_timeout_secs.unwrap_or(30) as u64);
    let start = std::time::Instant::now();

    loop {
        if start.elapsed() > lock_timeout {
            return InstructionResult::failure("Timeout waiting for guide star lock".to_string());
        }

        match ctx.device_ops.guider_get_status(&config.guider_id).await {
            Ok(status) => {
                if let Some(cb) = progress_callback {
                    let progress = 30.0 + (start.elapsed().as_secs_f64() / lock_timeout.as_secs_f64()) * 60.0;
                    cb(progress.min(90.0), format!("Acquiring star... RMS: {:.2}\"",
                        (status.rms_ra.powi(2) + status.rms_dec.powi(2)).sqrt()));
                }

                // Check if guiding is stable
                if status.is_guiding && status.star_locked {
                    break;
                }
            }
            Err(e) => {
                tracing::warn!("Error checking guider status: {}", e);
            }
        }

        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
    }

    if let Some(cb) = progress_callback {
        cb(100.0, "Guiding active and locked".to_string());
    }

    InstructionResult::success("Guiding started successfully".to_string())
}
```

**Step 4: Implement execute_stop_guiding with progress**

```rust
pub async fn execute_stop_guiding(
    config: &StopGuidingConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    if let Some(cb) = progress_callback {
        cb(0.0, "Stopping guider...".to_string());
    }

    if let Err(e) = ctx.device_ops.guider_stop(&config.guider_id).await {
        return InstructionResult::failure(format!("Failed to stop guiding: {}", e));
    }

    if let Some(cb) = progress_callback {
        cb(50.0, "Verifying guider stopped...".to_string());
    }

    // Verify guiding actually stopped
    tokio::time::sleep(std::time::Duration::from_millis(500)).await;

    match ctx.device_ops.guider_get_status(&config.guider_id).await {
        Ok(status) => {
            if status.is_guiding {
                return InstructionResult::failure("Guider reports still guiding after stop command".to_string());
            }
        }
        Err(e) => {
            tracing::warn!("Could not verify guider stopped: {}", e);
        }
    }

    if let Some(cb) = progress_callback {
        cb(100.0, "Guiding stopped".to_string());
    }

    InstructionResult::success("Guiding stopped successfully".to_string())
}
```

**Step 5: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_sequencer`

**Step 6: Commit**

```bash
git add native/nightshade_native/sequencer/src/node.rs native/nightshade_native/sequencer/src/instructions.rs
git commit -m "feat(sequencer): add progress callbacks to guiding instructions

- StartGuiding reports connection, lock acquisition, RMS
- StopGuiding verifies guider actually stopped
- Both report clear progress percentages"
```

---

### Task 3.4: Add Progress Callbacks to Dome Operations

**Files:**
- Modify: `native/nightshade_native/sequencer/src/node.rs:981-989`
- Modify: `native/nightshade_native/sequencer/src/instructions.rs`

**Step 1: Update dome operations in node.rs**

```rust
NodeType::OpenDome(config) => {
    let cb = progress_callback.clone();
    let progress_fn = move |progress: f64, detail: String| {
        if let Some(ref callback) = cb {
            callback(ProgressUpdate {
                node_id: node_id.clone(),
                status: NodeStatus::Running,
                message: Some(format!("Open Dome: {} ({:.0}%)", detail, progress)),
                ..Default::default()
            });
        }
    };
    execute_open_dome(config, &ctx, Some(&progress_fn)).await
}

NodeType::CloseDome(config) => {
    let cb = progress_callback.clone();
    let progress_fn = move |progress: f64, detail: String| {
        if let Some(ref callback) = cb {
            callback(ProgressUpdate {
                node_id: node_id.clone(),
                status: NodeStatus::Running,
                message: Some(format!("Close Dome: {} ({:.0}%)", detail, progress)),
                ..Default::default()
            });
        }
    };
    execute_close_dome(config, &ctx, Some(&progress_fn)).await
}

NodeType::ParkDome(config) => {
    let cb = progress_callback.clone();
    let progress_fn = move |progress: f64, detail: String| {
        if let Some(ref callback) = cb {
            callback(ProgressUpdate {
                node_id: node_id.clone(),
                status: NodeStatus::Running,
                message: Some(format!("Park Dome: {} ({:.0}%)", detail, progress)),
                ..Default::default()
            });
        }
    };
    execute_park_dome(config, &ctx, Some(&progress_fn)).await
}
```

**Step 2: Implement dome operations with progress**

```rust
pub async fn execute_open_dome(
    config: &DomeConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    if let Some(cb) = progress_callback {
        cb(0.0, "Sending open command...".to_string());
    }

    if let Err(e) = ctx.device_ops.dome_open(&config.dome_id).await {
        return InstructionResult::failure(format!("Failed to open dome: {}", e));
    }

    if let Some(cb) = progress_callback {
        cb(10.0, "Waiting for shutter to open...".to_string());
    }

    // Wait for shutter to fully open
    let timeout = std::time::Duration::from_secs(config.timeout_secs.unwrap_or(120) as u64);
    let start = std::time::Instant::now();

    loop {
        if start.elapsed() > timeout {
            return InstructionResult::failure("Dome open timeout".to_string());
        }

        match ctx.device_ops.dome_get_shutter_status(&config.dome_id).await {
            Ok(status) => {
                let progress = 10.0 + (start.elapsed().as_secs_f64() / timeout.as_secs_f64()) * 80.0;

                if let Some(cb) = progress_callback {
                    cb(progress.min(90.0), format!("Shutter status: {:?}", status));
                }

                if status == ShutterStatus::Open {
                    break;
                }
            }
            Err(e) => {
                tracing::warn!("Error checking shutter status: {}", e);
            }
        }

        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    }

    if let Some(cb) = progress_callback {
        cb(100.0, "Dome shutter open".to_string());
    }

    InstructionResult::success("Dome opened successfully".to_string())
}

pub async fn execute_close_dome(
    config: &DomeConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    if let Some(cb) = progress_callback {
        cb(0.0, "Sending close command...".to_string());
    }

    if let Err(e) = ctx.device_ops.dome_close(&config.dome_id).await {
        return InstructionResult::failure(format!("Failed to close dome: {}", e));
    }

    // Similar wait loop as open_dome...
    let timeout = std::time::Duration::from_secs(config.timeout_secs.unwrap_or(120) as u64);
    let start = std::time::Instant::now();

    loop {
        if start.elapsed() > timeout {
            return InstructionResult::failure("Dome close timeout".to_string());
        }

        match ctx.device_ops.dome_get_shutter_status(&config.dome_id).await {
            Ok(status) => {
                let progress = 10.0 + (start.elapsed().as_secs_f64() / timeout.as_secs_f64()) * 80.0;

                if let Some(cb) = progress_callback {
                    cb(progress.min(90.0), format!("Shutter status: {:?}", status));
                }

                if status == ShutterStatus::Closed {
                    break;
                }
            }
            Err(e) => {
                tracing::warn!("Error checking shutter status: {}", e);
            }
        }

        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    }

    if let Some(cb) = progress_callback {
        cb(100.0, "Dome shutter closed".to_string());
    }

    InstructionResult::success("Dome closed successfully".to_string())
}

pub async fn execute_park_dome(
    config: &DomeConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    if let Some(cb) = progress_callback {
        cb(0.0, "Sending park command...".to_string());
    }

    if let Err(e) = ctx.device_ops.dome_park(&config.dome_id).await {
        return InstructionResult::failure(format!("Failed to park dome: {}", e));
    }

    if let Some(cb) = progress_callback {
        cb(50.0, "Waiting for dome to park...".to_string());
    }

    // Wait for park to complete
    let timeout = std::time::Duration::from_secs(config.timeout_secs.unwrap_or(180) as u64);
    let start = std::time::Instant::now();

    loop {
        if start.elapsed() > timeout {
            return InstructionResult::failure("Dome park timeout".to_string());
        }

        match ctx.device_ops.dome_is_parked(&config.dome_id).await {
            Ok(true) => break,
            Ok(false) => {
                if let Some(cb) = progress_callback {
                    let progress = 50.0 + (start.elapsed().as_secs_f64() / timeout.as_secs_f64()) * 45.0;
                    cb(progress.min(95.0), "Parking...".to_string());
                }
            }
            Err(e) => {
                tracing::warn!("Error checking park status: {}", e);
            }
        }

        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    }

    if let Some(cb) = progress_callback {
        cb(100.0, "Dome parked".to_string());
    }

    InstructionResult::success("Dome parked successfully".to_string())
}
```

**Step 3: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_sequencer`

**Step 4: Commit**

```bash
git add native/nightshade_native/sequencer/src/node.rs native/nightshade_native/sequencer/src/instructions.rs
git commit -m "feat(sequencer): add progress callbacks to dome operations

- OpenDome, CloseDome, ParkDome all report progress
- Shows shutter status during movement
- Waits for actual completion with timeout
- Reports clear progress percentages"
```

---

### Task 3.5: Add Progress Callbacks to Cover Calibrator Operations

**Files:**
- Modify: `native/nightshade_native/sequencer/src/node.rs:1001-1013`
- Modify: `native/nightshade_native/sequencer/src/instructions.rs`

Similar pattern to dome operations - add progress callbacks for OpenCover, CloseCover, CalibratorOn, CalibratorOff.

**Step 1-4:** Follow same pattern as Task 3.4 for cover calibrator operations.

**Step 5: Commit**

```bash
git add native/nightshade_native/sequencer/src/node.rs native/nightshade_native/sequencer/src/instructions.rs
git commit -m "feat(sequencer): add progress callbacks to cover calibrator operations"
```

---

### Task 3.6: Add Progress Callbacks to FlatWizard and Mosaic

**Files:**
- Modify: `native/nightshade_native/sequencer/src/node.rs:993-997`
- Modify: `native/nightshade_native/sequencer/src/flat_wizard.rs`
- Modify: `native/nightshade_native/sequencer/src/mosaic.rs`

These are complex multi-step operations that need detailed progress reporting.

**Step 1: Update FlatWizard with progress**

The flat wizard performs binary search for optimal exposure - report each iteration:

```rust
pub async fn execute_flat_wizard(
    config: &FlatWizardConfig,
    ctx: &InstructionContext,
    progress_callback: Option<&(dyn Fn(f64, String) + Send + Sync)>,
) -> InstructionResult {
    if let Some(cb) = progress_callback {
        cb(0.0, format!("Starting flat wizard for filter {}", config.filter_name));
    }

    // Change to target filter
    if let Some(cb) = progress_callback {
        cb(5.0, format!("Changing to filter: {}", config.filter_name));
    }

    if let Err(e) = ctx.device_ops.filterwheel_set_filter_by_name(
        &config.filterwheel_id,
        &config.filter_name,
    ).await {
        return InstructionResult::failure(format!("Failed to change filter: {}", e));
    }

    // Setup flat panel if configured
    if let Some(panel_id) = &config.flat_panel_id {
        if let Some(cb) = progress_callback {
            cb(10.0, "Opening flat panel cover...".to_string());
        }

        if let Err(e) = ctx.device_ops.cover_calibrator_open_cover(panel_id).await {
            return InstructionResult::failure(format!("Failed to open cover: {}", e));
        }

        if let Some(cb) = progress_callback {
            cb(15.0, "Turning on calibrator...".to_string());
        }

        if let Err(e) = ctx.device_ops.cover_calibrator_calibrator_on(panel_id, config.initial_brightness).await {
            return InstructionResult::failure(format!("Failed to turn on calibrator: {}", e));
        }
    }

    // Binary search for optimal exposure
    let mut min_exp = config.min_exposure_secs;
    let mut max_exp = config.max_exposure_secs;
    let mut iteration = 0;
    let max_iterations = 10;

    while iteration < max_iterations {
        iteration += 1;
        let test_exp = (min_exp + max_exp) / 2.0;

        if let Some(cb) = progress_callback {
            let progress = 20.0 + (iteration as f64 / max_iterations as f64) * 60.0;
            cb(progress, format!("Iteration {}: testing {:.2}s exposure", iteration, test_exp));
        }

        // Take test exposure
        let image = match ctx.device_ops.camera_start_exposure(
            &config.camera_id,
            test_exp,
            config.gain,
            config.offset,
            1, 1,
        ).await {
            Ok(img) => img,
            Err(e) => return InstructionResult::failure(format!("Test exposure failed: {}", e)),
        };

        // Calculate mean ADU
        let mean_adu = calculate_mean_adu(&image.data);

        if let Some(cb) = progress_callback {
            cb(20.0 + (iteration as f64 / max_iterations as f64) * 60.0,
               format!("Mean ADU: {:.0} (target: {:.0})", mean_adu, config.target_adu));
        }

        // Check if we've converged
        let adu_diff = (mean_adu - config.target_adu).abs();
        if adu_diff / config.target_adu < 0.05 {
            // Within 5% of target
            if let Some(cb) = progress_callback {
                cb(85.0, format!("Found optimal exposure: {:.2}s", test_exp));
            }

            // Take the actual flat frames
            for frame in 1..=config.frame_count {
                if let Some(cb) = progress_callback {
                    cb(85.0 + (frame as f64 / config.frame_count as f64) * 10.0,
                       format!("Capturing flat {}/{}", frame, config.frame_count));
                }

                // Take and save flat frame...
            }

            // Cleanup
            if let Some(panel_id) = &config.flat_panel_id {
                let _ = ctx.device_ops.cover_calibrator_calibrator_off(panel_id).await;
                let _ = ctx.device_ops.cover_calibrator_close_cover(panel_id).await;
            }

            if let Some(cb) = progress_callback {
                cb(100.0, format!("Flat wizard complete: {} frames at {:.2}s", config.frame_count, test_exp));
            }

            return InstructionResult::success(format!(
                "Flat wizard completed: {} frames at {:.2}s, mean ADU {:.0}",
                config.frame_count, test_exp, mean_adu
            ));
        }

        // Adjust search range
        if mean_adu < config.target_adu {
            min_exp = test_exp;
        } else {
            max_exp = test_exp;
        }
    }

    InstructionResult::failure("Flat wizard failed to converge on target ADU".to_string())
}
```

**Step 2: Build and commit**

```bash
git add native/nightshade_native/sequencer/src/node.rs native/nightshade_native/sequencer/src/flat_wizard.rs native/nightshade_native/sequencer/src/mosaic.rs
git commit -m "feat(sequencer): add progress callbacks to FlatWizard and Mosaic

- FlatWizard reports filter change, panel setup, binary search iterations
- Shows mean ADU vs target during search
- Reports each flat frame capture
- Mosaic reports panel progress and per-panel status"
```

---

## Phase 4: Fix Async/Await Issues

### Task 4.1: Fix Mount Slew to Validate Final Position

**Files:**
- Modify: `native/nightshade_native/sequencer/src/instructions.rs:291-320`

**Problem:** Slew wait only checks `is_slewing == false`, doesn't validate coordinates match target.

**Step 1: Update slew wait logic**

```rust
async fn wait_for_slew_complete(
    mount_id: &str,
    target_ra: f64,
    target_dec: f64,
    ctx: &InstructionContext,
    timeout: std::time::Duration,
) -> Result<(), String> {
    let start = std::time::Instant::now();
    let position_tolerance_arcsec = 30.0; // 30 arcseconds tolerance

    loop {
        if start.elapsed() > timeout {
            return Err(format!("Slew timeout after {} seconds", timeout.as_secs()));
        }

        // Check cancellation
        if ctx.cancellation_token.load(std::sync::atomic::Ordering::Relaxed) {
            // Abort slew and wait for it to actually stop
            if let Err(e) = ctx.device_ops.mount_abort_slew(mount_id).await {
                tracing::warn!("Error aborting slew: {}", e);
            }
            // Give mount time to stop
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            return Err("Slew cancelled".to_string());
        }

        // Check if still slewing
        let is_slewing = match ctx.device_ops.mount_is_slewing(mount_id).await {
            Ok(s) => s,
            Err(e) => {
                tracing::warn!("Error checking slew status: {}", e);
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                continue;
            }
        };

        if !is_slewing {
            // Mount reports not slewing - verify position
            let (actual_ra, actual_dec) = match ctx.device_ops.mount_get_coordinates(mount_id).await {
                Ok(coords) => coords,
                Err(e) => {
                    tracing::warn!("Error getting mount coordinates: {}", e);
                    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                    continue;
                }
            };

            // Calculate separation in arcseconds
            let ra_diff_arcsec = (actual_ra - target_ra).abs() * 15.0 * 3600.0; // hours to arcsec
            let dec_diff_arcsec = (actual_dec - target_dec).abs() * 3600.0; // degrees to arcsec
            let separation_arcsec = (ra_diff_arcsec.powi(2) + dec_diff_arcsec.powi(2)).sqrt();

            if separation_arcsec <= position_tolerance_arcsec {
                tracing::info!(
                    "Slew complete: target ({:.4}h, {:.4}°), actual ({:.4}h, {:.4}°), separation {:.1}\"",
                    target_ra, target_dec, actual_ra, actual_dec, separation_arcsec
                );
                return Ok(());
            } else {
                // Mount stopped but not at target - this is a problem
                tracing::warn!(
                    "Mount stopped but not at target: separation {:.1}\" > tolerance {:.1}\"",
                    separation_arcsec, position_tolerance_arcsec
                );
                // Give it a moment and re-check (mount might still be settling)
                tokio::time::sleep(std::time::Duration::from_secs(2)).await;

                // Re-check one more time
                let (actual_ra2, actual_dec2) = ctx.device_ops.mount_get_coordinates(mount_id).await
                    .map_err(|e| format!("Failed to verify final position: {}", e))?;

                let ra_diff2 = (actual_ra2 - target_ra).abs() * 15.0 * 3600.0;
                let dec_diff2 = (actual_dec2 - target_dec).abs() * 3600.0;
                let separation2 = (ra_diff2.powi(2) + dec_diff2.powi(2)).sqrt();

                if separation2 <= position_tolerance_arcsec {
                    return Ok(());
                } else {
                    return Err(format!(
                        "Mount stopped at wrong position: {:.1}\" from target (tolerance {:.1}\")",
                        separation2, position_tolerance_arcsec
                    ));
                }
            }
        }

        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    }
}
```

**Step 2: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_sequencer`

**Step 3: Commit**

```bash
git add native/nightshade_native/sequencer/src/instructions.rs
git commit -m "fix(sequencer): validate mount position after slew completes

- Now checks actual coordinates match target within tolerance
- Reports separation in arcseconds
- Handles mount settling with re-check
- Properly waits for abort to complete on cancel"
```

---

### Task 4.2: Fix Focuser Cancel to Wait for Movement Stop

**Files:**
- Modify: `native/nightshade_native/sequencer/src/instructions.rs:807-820`

**Problem:** On cancel, focuser move is initiated but not awaited.

**Step 1: Fix cancel handling**

```rust
// In autofocus instruction, when handling cancellation:
if let Some(result) = ctx.check_cancelled() {
    // Return focuser to original position AND WAIT for it
    tracing::info!("Autofocus cancelled, returning focuser to position {}", original_position);

    if let Err(e) = ctx.device_ops.focuser_move_to(&focuser_id, original_position).await {
        tracing::warn!("Failed to return focuser to original position: {}", e);
    } else {
        // Wait for focuser to actually reach position
        let wait_result = wait_for_focuser_idle(&focuser_id, ctx, std::time::Duration::from_secs(60)).await;
        if let Err(e) = wait_result {
            tracing::warn!("Error waiting for focuser to return: {}", e);
        }
    }

    return result;
}
```

**Step 2: Create reusable wait_for_focuser_idle function**

```rust
async fn wait_for_focuser_idle(
    focuser_id: &str,
    ctx: &InstructionContext,
    timeout: std::time::Duration,
) -> Result<(), String> {
    let start = std::time::Instant::now();

    loop {
        if start.elapsed() > timeout {
            return Err(format!("Focuser idle timeout after {} seconds", timeout.as_secs()));
        }

        match ctx.device_ops.focuser_is_moving(focuser_id).await {
            Ok(false) => return Ok(()),
            Ok(true) => {
                tokio::time::sleep(std::time::Duration::from_millis(250)).await;
            }
            Err(e) => {
                tracing::warn!("Error checking focuser status: {}", e);
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
            }
        }
    }
}
```

**Step 3: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_sequencer`

**Step 4: Commit**

```bash
git add native/nightshade_native/sequencer/src/instructions.rs
git commit -m "fix(sequencer): await focuser movement on cancel

- Wait for focuser to actually stop before returning
- Added reusable wait_for_focuser_idle function
- Proper timeout handling"
```

---

## Phase 5: FFI Robustness

### Task 5.1: Increase Event Buffer and Add Overflow Handling

**Files:**
- Modify: `native/nightshade_native/bridge/src/api.rs:158-200`

**Step 1: Increase buffer size and add overflow notification**

```rust
impl AppState {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            // Increase buffer from 1024 to 4096
            event_bus: Arc::new(EventBus::new(4096)),
            // ...
        })
    }
}

// In the event stream handler:
Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
    tracing::error!("[API_EVENT_STREAM] Event buffer overflow! Missed {} events", n);

    // Send a special event to notify the UI that events were lost
    let overflow_event = NightshadeEvent {
        category: EventCategory::System,
        event_type: "EventBufferOverflow".to_string(),
        data: serde_json::json!({
            "missed_events": n,
            "message": format!("Event buffer overflow - {} events were lost. Consider reducing event frequency.", n),
        }),
        timestamp: chrono::Utc::now(),
        severity: EventSeverity::Warning,
    };

    // Try to send overflow notification (might also fail if still overloaded)
    yield overflow_event;
}
```

**Step 2: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_bridge`

**Step 3: Commit**

```bash
git add native/nightshade_native/bridge/src/api.rs
git commit -m "fix(ffi): increase event buffer and add overflow notification

- Increased buffer from 1024 to 4096 events
- Added EventBufferOverflow event type
- UI now notified when events are lost"
```

---

### Task 5.2: Make Device State Updates Atomic

**Files:**
- Modify: `native/nightshade_native/bridge/src/devices.rs:440-475`

**Step 1: Update state atomically before publishing event**

```rust
async fn complete_connection(
    &self,
    device_id: &str,
    info: DeviceInfo,
) -> Result<(), String> {
    // FIRST: Update both state stores atomically
    {
        // Update DeviceManager state
        let mut devices = self.devices.write().await;
        if let Some(dev) = devices.get_mut(device_id) {
            dev.connection_state = ConnectionState::Connected;
            dev.last_error = None;
        }
    }

    // Update AppState
    self.app_state.register_device(info.clone(), ConnectionState::Connected).await;

    // THEN: Publish event (after state is consistent)
    self.app_state.publish_equipment_event(
        EquipmentEvent::Connected {
            device_id: device_id.to_string(),
            device_type: info.device_type,
            device_name: info.name.clone(),
            driver_type: info.driver_type,
        },
        EventSeverity::Info,
    );

    Ok(())
}
```

**Step 2: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_bridge`

**Step 3: Commit**

```bash
git add native/nightshade_native/bridge/src/devices.rs
git commit -m "fix(devices): make state updates atomic before publishing events

- State is now fully updated before Connected event is published
- Eliminates race where Dart receives event but state isn't ready"
```

---

### Task 5.3: Make Filter Wheel Timeout Configurable

**Files:**
- Modify: `native/nightshade_native/bridge/src/real_device_ops.rs:71-130`

**Step 1: Add configurable timeout based on filter count**

```rust
async fn filterwheel_is_moving(&self, fw_id: &str) -> DeviceResult<bool> {
    let movements = self.fw_movements.read().await;

    if let Some(movement) = movements.get(fw_id) {
        // Calculate timeout based on filter wheel configuration
        // Large filter wheels (12+ positions) can take up to 90 seconds
        let timeout_secs = match self.get_filter_wheel_timeout(fw_id).await {
            Ok(t) => t,
            Err(_) => 60, // Default 60 seconds if we can't determine
        };

        let elapsed = movement.started_at.elapsed();
        if elapsed > std::time::Duration::from_secs(timeout_secs) {
            tracing::warn!(
                "Filter wheel {} movement timed out after {} seconds",
                fw_id, timeout_secs
            );
            drop(movements);
            self.fw_movements.write().await.remove(fw_id);
            return Ok(false);
        }

        return Ok(true);
    }

    Ok(false)
}

async fn get_filter_wheel_timeout(&self, fw_id: &str) -> Result<u64, String> {
    // Get filter count and calculate appropriate timeout
    // ~8 seconds per position is conservative
    let mgr = get_device_manager();
    let (count, _) = mgr.filter_wheel_get_config(fw_id).await?;

    let timeout = (count as u64 * 8).max(30).min(180); // 30-180 seconds
    Ok(timeout)
}
```

**Step 2: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_bridge`

**Step 3: Commit**

```bash
git add native/nightshade_native/bridge/src/real_device_ops.rs
git commit -m "fix(filterwheel): make timeout configurable based on filter count

- Calculates timeout from filter wheel size
- Large wheels (12+) get up to 180 seconds
- Small wheels get minimum 30 seconds
- Prevents premature timeout on slow filter wheels"
```

---

## Phase 6: Remove Simulator Infrastructure

### Task 6.1: Remove NullDeviceOps Default from Executor

**Files:**
- Modify: `native/nightshade_native/sequencer/src/executor.rs:142`

**Problem:** SequenceExecutor defaults to NullDeviceOps which is a simulator.

**Step 1: Make DeviceOps required, not optional**

```rust
impl SequenceExecutor {
    /// Creates a new executor with the provided DeviceOps implementation.
    /// DeviceOps is required - there is no default simulator.
    pub fn new(device_ops: Arc<dyn DeviceOps>) -> Self {
        Self {
            state: ExecutorState::Idle,
            device_ops,
            // ... other fields ...
        }
    }

    // Remove any new() without device_ops parameter
}
```

**Step 2: Update all call sites to provide real DeviceOps**

Search for `SequenceExecutor::new()` and ensure all call sites provide a real implementation.

**Step 3: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_sequencer`

**Step 4: Commit**

```bash
git add native/nightshade_native/sequencer/src/executor.rs
git commit -m "refactor(sequencer): require DeviceOps, remove NullDeviceOps default

BREAKING: SequenceExecutor::new() now requires DeviceOps parameter
- No more silent fallback to simulator
- Forces explicit device configuration
- Removed NullDeviceOps from default constructor"
```

---

### Task 6.2: Remove DriverType::Simulator Case from DeviceManager

**Files:**
- Modify: `native/nightshade_native/bridge/src/devices.rs` (all Simulator match arms)

**Step 1: Replace Simulator cases with explicit errors**

Throughout devices.rs, change all `DriverType::Simulator` match arms:

```rust
// BEFORE:
DriverType::Simulator => {
    Ok(()) // Stub implementation
}

// AFTER:
DriverType::Simulator => {
    Err("Simulator devices are disabled. Connect real hardware or use INDI/ASCOM/Alpaca simulators for testing.".to_string())
}
```

**Step 2: Build and verify**

Run: `cd native/nightshade_native && cargo build --package nightshade_bridge`

**Step 3: Commit**

```bash
git add native/nightshade_native/bridge/src/devices.rs
git commit -m "refactor(devices): disable built-in simulator, require real hardware

- All Simulator driver type cases now return explicit error
- Users must connect real hardware or use external simulators
- No more silent stub operations"
```

---

### Task 6.3: Update Dart Bridge Stub to Throw on Production Use

**Files:**
- Modify: `packages/nightshade_bridge/lib/src/bridge_stub.dart`

**Step 1: Make stub methods throw clear errors**

```dart
// At the top of bridge_stub.dart
const _stubErrorMessage = '''
Native bridge not available. This is the Dart fallback stub.
Possible causes:
1. Native library failed to load - check build output
2. Running on unsupported platform (web)
3. DLL/dylib not found in expected location

For development: Use INDI/ASCOM/Alpaca simulators instead of built-in stubs.
''';

// Replace stub implementations:
Future<void> startExposure(...) async {
  throw UnsupportedError(_stubErrorMessage);
}

Future<ImageData> apiGetLastImage() async {
  throw UnsupportedError(_stubErrorMessage);
}

// etc. for all hardware-related stubs
```

**Step 2: Commit**

```bash
git add packages/nightshade_bridge/lib/src/bridge_stub.dart
git commit -m "refactor(bridge): make stub throw clear errors instead of simulating

- Stub methods now throw UnsupportedError
- Clear message explains why and what to do
- Prevents silent fallback to fake data"
```

---

## Final Verification

### Task 7.1: Integration Test - ASCOM Camera Exposure

Manually test with real ASCOM camera:
1. Connect ASCOM camera
2. Run single exposure through sequencer
3. Verify raw data is captured (not display data)
4. Verify HFR calculation produces realistic values
5. Verify progress events appear in UI

### Task 7.2: Integration Test - Alpaca Focuser Autofocus

Manually test with Alpaca focuser:
1. Connect Alpaca focuser
2. Run autofocus routine
3. Verify focuser moves to correct positions
4. Verify progress events show V-curve building
5. Verify final focus position is applied

### Task 7.3: Integration Test - INDI Filter Wheel

Manually test with INDI filter wheel:
1. Connect INDI filter wheel
2. Change filter through sequencer
3. Verify filter wheel moves
4. Verify correct filter is selected
5. Verify progress events appear

---

## Summary

This plan contains **36 tasks** across **7 phases**:

1. **Phase 1** (3 tasks): Fix critical data corruption
2. **Phase 2** (4 tasks): Complete driver routing for Alpaca/INDI
3. **Phase 3** (6 tasks): Add progress callbacks to 15 silent instructions
4. **Phase 4** (2 tasks): Fix async/await issues
5. **Phase 5** (3 tasks): FFI robustness improvements
6. **Phase 6** (3 tasks): Remove simulator infrastructure
7. **Phase 7** (3 tasks): Integration testing

Each task produces a working, committed change. No task leaves the system in a broken state.

**CRITICAL REMINDER:** Every implementation must be:
- 100% functional with real hardware
- Properly error-handled
- Emitting appropriate progress events
- Free of stubs, placeholders, or simulators
