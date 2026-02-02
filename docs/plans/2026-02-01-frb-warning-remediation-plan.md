# FRB Warning Remediation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate all `dev.ps1 -NoRun` warnings by fixing root causes (not suppressing), while preserving or improving device functionality and FFI behavior.

**Architecture:** Changes span Rust crates under `native/nightshade_native` (imaging, alpaca, ascom, bridge, vendor SDK shims, sequencer). The plan focuses on (1) removing truly dead code, (2) wiring missing functionality so unused items become used, and (3) correcting unsafe/ignored results and cfg usage at the FRB boundary.

**Tech Stack:** Rust 2021, flutter_rust_bridge, tokio, ASCOM/Alpaca SDKs, vendor FFI shims.

---

## Warning Inventory (from `docs/frb_warnings_2026-02-01.txt`)

Each entry includes a concrete fix strategy and the functional impact to review.

1. **Build script warning:** `imaging/build.rs` prints `cargo:warning=LibRaw found at...` even when healthy.  
   **Fix:** Only emit warnings on missing libs; emit info via `cargo:rustc-env` for success.  
   **Impact:** No runtime change; build output becomes meaningful (warnings only on failures).

2. **Unused imports:** `imaging/src/lib.rs` (`Luma`, `Rgb` in `write_tiff`; `GrayImage`, `ImageBuffer`, `RgbImage` in `write_jpeg`).  
   **Fix:** Remove unused imports.  
   **Impact:** No runtime change.

3. **Unused helper:** `imaging/src/xisf.rs` `build_xisf_xml`.  
   **Fix:** Remove the wrapper or use it in a call site; prefer removal unless external API expected.  
   **Impact:** No runtime change if removed; fewer redundant APIs.

4. **Unused client helper:** `alpaca/src/client.rs` `create_custom_timeout_client`.  
   **Fix:** Remove unused helper or wire into a per-call timeout path.  
   **Impact:** If removed, no behavior change (private helper). If wired, check timeout behavior.

5. **ASCOM SAFEARRAY string extractor unused:** `ascom/src/windows_impl.rs` `extract_safearray_string`.  
   **Fix:** Use it from `variant_to_string_array` to centralize SAFEARRAY parsing.  
   **Impact:** Improves error handling consistency for `SupportedActions` and other string arrays.

6. **Native vendor camera shims (unused enums/constants/fields):**  
   - `native/src/vendor/svbony.rs` (`SvbImgType`, `SvbBayerPattern`, `SvbControlType`, `Wb_R/Wb_G/Wb_B`, `get_serial_number`, `get_control_range`).  
   - `native/src/vendor/atik.rs` (`ArtemisColourType` variants, `ArtemisCameraState`, `ARTEMIS_CAMERA_HAS_FILTERWHEEL`, unused SDK fields).  
   - `native/src/vendor/fli.rs` (unused imports, constants, type aliases, SDK fields).  
   - `native/src/vendor/touptek.rs` (unused constants, SDK fields, `camera_id`, non-snake-case type parameters).  
   **Fix:** Prefer wiring unused enums/constants into capability/status mapping and SDK usage; if the capability is not supported, remove the dead items instead of suppressing.  
   **Impact:** If wired, device capability reporting and behavior improve; if removed, no runtime change but reduced future surface area.

7. **Native vendor mount shims (unused constants/fields/methods):**  
   - `native/src/vendor/moravian.rs` (`LongReal`, `GBP_*`, `GIP_*`, `GSP_*`, `GV_*`, `move_telescope`, `discovery_index`, `get_*_param`).  
   - `native/src/vendor/skywatcher.rs` (`SYNSCAN_BAUD_RATE_FAST`, `latitude`, `longitude`).  
   - `native/src/vendor/ioptron.rs` (`GET_FIRMWARE`, `firmware_version`).  
   - `native/src/vendor/lx200.rs` (`firmware_version`, `ONSTEP_*`).  
   **Fix:** Wire into connection/status/capability flow; remove if truly unused.  
   **Impact:** More accurate mount status; firmware strings and rate control may become available.

8. **Sequencer autofocus helpers unused:** `sequencer/src/instructions.rs` `HfrMeasurement` + `calculate_hfr_*` + `find_best_focus`.  
   **Fix:** Integrate into autofocus instruction or remove if not used.  
   **Impact:** If wired, autofocus quality improves; if removed, no change.

9. **Bridge warnings (real functionality issues):**  
   - `bridge/src/api.rs` unused `Result` from `sink.add` (must handle errors).  
   - `bridge/src/device_guard.rs` unused `state_updater` (rollback never happens).  
   - `bridge/src/unified_device_ops.rs` `last_complete_status` unused assignment (poller not informed of latest status).  
   - `bridge/src/real_device_ops.rs` unused `focuser` variable.  
   - `bridge/src/lib.rs` unused `try_create_runtime`.  
   **Fix:** Handle `sink.add` errors; use `state_updater` in `Drop`; restructure polling; replace unused variable with `contains_key`; remove or use `try_create_runtime`.  
   **Impact:** Event stream becomes robust; connection rollback works; exposure polling logic is correct.

10. **ASCOM wrappers partially unused:**  
    - `ascom_wrapper_mount.rs` variants `CanPark`, `Stop` unused.  
    - `ascom_wrapper_focuser.rs` variants `GetMaxPosition`, `GetStepSize` unused.  
    - `ascom_wrapper_dome.rs` not wired in `connect_ascom`, so many commands unused.  
    - `ascom_wrapper_switch.rs` not wired; methods unused.  
    - `ascom_wrapper_covercalibrator.rs` some methods unused (`set_brightness`, `max_brightness`, `name`, `id`, `cached_name`).  
    **Fix:** Wire wrappers into device manager and call capability/metadata methods; add missing API functions for switches if supported.  
    **Impact:** ASCOM device coverage becomes consistent with Dart APIs.

11. **FRB macro cfg warnings:** `bridge/src/lib.rs` + `bridge/src/api.rs` `unexpected cfg frb_expand`.  
    **Fix:** Update `flutter_rust_bridge_macros` and/or add `check-cfg` allowlist in `Cargo.toml`.  
    **Impact:** Clean build with up-to-date macro behavior; no runtime change.

---

## Implementation Tasks

### Task 1: Reproduce warnings baseline

**Files:**  
- Reference: `docs/frb_warnings_2026-02-01.txt`

**Step 1: Capture baseline warnings**  
Run: `powershell -ExecutionPolicy Bypass -File scripts\dev.ps1 -NoRun *> "docs\frb_warnings_2026-02-01.txt"`  
Expected: Non-empty warning log matching inventory.

**Step 2: Confirm warnings to remove**  
Run: `rg "warning:" docs\frb_warnings_2026-02-01.txt`  
Expected: Matches list above.

---

### Task 2: Fix LibRaw build warning + imaging imports

**Files:**  
- Modify: `native/nightshade_native/imaging/build.rs`  
- Modify: `native/nightshade_native/imaging/src/lib.rs`  
- Test: `native/nightshade_native/imaging` (cargo check)

**Step 1: Update build script to warn only on missing libs**

```rust
// native/nightshade_native/imaging/build.rs
if !libraw_lib.exists() {
    println!("cargo:warning=libraw.lib not found at: {}", libraw_lib.display());
    println!("cargo:warning=Set LIBRAW_DIR environment variable or place libraw.lib in workspace root");
} else {
    // Use rustc-env for an informational breadcrumb instead of a warning
    println!("cargo:rustc-env=LIBRAW_PATH={}", search_dir.display());
}
```

**Step 2: Remove unused imports in image writers**

```rust
// native/nightshade_native/imaging/src/lib.rs
pub fn write_tiff(...) -> Result<(), String> {
    use image::{ImageBuffer, GrayImage, RgbImage};
    // Luma, Rgb removed
}

pub fn write_jpeg(...) -> Result<(), String> {
    use image::ImageEncoder;
    // ImageBuffer, GrayImage, RgbImage removed
}
```

**Step 3: Verify**
Run: `cd native/nightshade_native/imaging; cargo check`  
Expected: No warnings about unused imports or LibRaw found-at warning.

**Impact notes:** No runtime change; build output becomes actionable.

---

### Task 3: Remove unused XISF helper

**Files:**  
- Modify: `native/nightshade_native/imaging/src/xisf.rs`  
- Test: `native/nightshade_native/imaging` (cargo check)

**Step 1: Remove the unused wrapper**

```rust
// native/nightshade_native/imaging/src/xisf.rs
// Delete build_xisf_xml entirely; all call sites already use build_xisf_xml_with_location.
```

**Step 2: Verify**
Run: `cd native/nightshade_native/imaging; cargo check`  
Expected: No dead_code warning for `build_xisf_xml`.

**Impact notes:** No runtime change; reduces unused API surface.

---

### Task 4: Alpaca custom timeout helper (remove dead code)

**Files:**  
- Modify: `native/nightshade_native/alpaca/src/client.rs`  
- Test: `native/nightshade_native/alpaca` (cargo check)

**Step 1: Remove unused helper**

```rust
// native/nightshade_native/alpaca/src/client.rs
// Delete create_custom_timeout_client if no call site is added.
```

**Step 2: Verify**
Run: `cd native/nightshade_native/alpaca; cargo check`  
Expected: No dead_code warning for `create_custom_timeout_client`.

**Impact notes:** No runtime change (private helper only).

---

### Task 5: Use ASCOM SAFEARRAY string extraction

**Files:**  
- Modify: `native/nightshade_native/ascom/src/windows_impl.rs`  
- Test: `native/nightshade_native/ascom` (cargo check)

**Step 1: Route string-array parsing through the robust SAFEARRAY helper**

```rust
// native/nightshade_native/ascom/src/windows_impl.rs
fn variant_to_string_array(var: &VARIANT) -> Option<Vec<String>> {
    unsafe { extract_safearray_string(var).ok() }
}
```

**Step 2: Verify**
Run: `cd native/nightshade_native/ascom; cargo check`  
Expected: No dead_code warning for `extract_safearray_string`.

**Impact notes:** Safer string-array handling for `SupportedActions`, `ReadoutModes`, etc.

---

### Task 6: Fix bridge polling + unused variable warnings

**Files:**  
- Modify: `native/nightshade_native/bridge/src/unified_device_ops.rs`  
- Modify: `native/nightshade_native/bridge/src/real_device_ops.rs`  
- Test: `native/nightshade_native/bridge` (cargo check)

**Step 1: Use `contains_key` instead of unused `focuser` binding**

```rust
// native/nightshade_native/bridge/src/real_device_ops.rs
if focuser_id.starts_with("native:") {
    let native_focusers = self.device_manager.native_focusers.read().await;
    if native_focusers.contains_key(focuser_id) {
        drop(native_focusers);
        let mut native_focusers = self.device_manager.native_focusers.write().await;
        if let Some(focuser) = native_focusers.get_mut(focuser_id) {
            // unchanged
        }
    }
}
```

**Step 2: Restructure exposure polling so `last_complete_status` is meaningful**

```rust
// native/nightshade_native/bridge/src/unified_device_ops.rs
loop {
    match mgr.camera_is_exposure_complete(camera_id).await {
        Ok(is_complete) => {
            last_complete_status = is_complete;
            if is_complete { break; }
        }
        Err(e) => { /* unchanged error handling */ }
    }

    let poll_interval = poller.tick(&last_complete_status);
    tokio::time::sleep(poll_interval).await;
    // progress event unchanged
}
```

**Step 3: Verify**
Run: `cd native/nightshade_native/bridge; cargo check`  
Expected: No unused variable/assignment warnings.

**Impact notes:** Adaptive poller now reflects actual exposure completion state; no behavior regressions expected.

---

### Task 7: ConnectionStateGuard rollback actually updates state

**Files:**  
- Modify: `native/nightshade_native/bridge/src/device_guard.rs`  
- Test: `native/nightshade_native/bridge` (unit test)

**Step 1: Store updater as `Option` and invoke on drop**

```rust
pub struct ConnectionStateGuard {
    device_id: String,
    rollback_state: crate::device::ConnectionState,
    committed: bool,
    state_updater: Option<Box<dyn FnOnce(String, crate::device::ConnectionState) + Send>>,
}

pub fn new<F>(...) -> Self
where F: FnOnce(String, crate::device::ConnectionState) + Send + 'static {
    Self { ..., state_updater: Some(Box::new(state_updater)) }
}

impl Drop for ConnectionStateGuard {
    fn drop(&mut self) {
        if !self.committed {
            if let Some(updater) = self.state_updater.take() {
                let device_id = std::mem::take(&mut self.device_id);
                let rollback_state = self.rollback_state;
                updater(device_id, rollback_state);
            }
        }
    }
}
```

**Step 2: Add a unit test for rollback behavior**

```rust
// native/nightshade_native/bridge/src/device_guard.rs (tests)
#[test]
fn connection_state_guard_rolls_back_on_drop() {
    use std::sync::{Arc, atomic::{AtomicBool, Ordering}};
    let called = Arc::new(AtomicBool::new(false));
    let called_clone = Arc::clone(&called);
    {
        let _guard = ConnectionStateGuard::new(
            "dev-1".to_string(),
            crate::device::ConnectionState::Disconnected,
            move |id, state| {
                assert_eq!(id, "dev-1");
                assert_eq!(state, crate::device::ConnectionState::Disconnected);
                called_clone.store(true, Ordering::SeqCst);
            },
        );
    }
    assert!(called.load(Ordering::SeqCst));
}
```

**Step 3: Verify**
Run: `cd native/nightshade_native/bridge; cargo test -p nightshade_bridge device_guard`  
Expected: Test passes; no dead_code warning.

**Impact notes:** Rollback becomes real; verify no double-updates in connection flows.

---

### Task 8: Remove unused `try_create_runtime`

**Files:**  
- Modify: `native/nightshade_native/bridge/src/lib.rs`  
- Test: `native/nightshade_native/bridge` (cargo check)

**Step 1: Remove dead helper or use it in a call site**

```rust
// native/nightshade_native/bridge/src/lib.rs
// Remove try_create_runtime if no call site exists:
// pub(crate) fn try_create_runtime(...) { ... }
```

**Step 2: Verify**
Run: `cd native/nightshade_native/bridge; cargo check`  
Expected: No dead_code warning for `try_create_runtime`.

**Impact notes:** No runtime change (helper never used).

---

### Task 9: Resolve FRB `frb_expand` cfg warnings

**Files:**  
- Modify: `native/nightshade_native/bridge/Cargo.toml`  
- Modify: `native/nightshade_native/bridge/Cargo.lock` (if `cargo update` run)

**Step 1: Update FRB macros dependency**
Run: `cd native/nightshade_native/bridge; cargo update -p flutter_rust_bridge_macros`  
Expected: `Cargo.lock` updated.

**Step 2: Allow `frb_expand` in `unexpected_cfgs` lint (if warnings persist)**

```toml
# native/nightshade_native/bridge/Cargo.toml
[lints.rust]
unexpected_cfgs = { level = "warn", check-cfg = ["cfg(frb_expand)"] }
```

**Step 3: Verify**
Run: `cd native/nightshade_native/bridge; cargo check`  
Expected: No `unexpected cfg` warnings.

**Impact notes:** Macro expansion warnings disappear without suppressing real cfg issues.

---

### Task 10: Wire ASCOM Dome wrapper into device manager

**Files:**  
- Modify: `native/nightshade_native/bridge/src/devices.rs`  
- Modify: `native/nightshade_native/bridge/src/ascom_wrapper_dome.rs` (if needed)  
- Test: `native/nightshade_native/bridge` (cargo check)

**Step 1: Use `AscomDomeWrapper` in `connect_ascom`**

```rust
// native/nightshade_native/bridge/src/devices.rs
DeviceType::Dome => {
    use crate::ascom_wrapper_dome::AscomDomeWrapper;
    let mut dome = AscomDomeWrapper::new(prog_id.to_string())?;
    dome.connect().await.map_err(|e| e.to_string())?;
    let mut ascom_domes = self.ascom_domes.write().await;
    ascom_domes.insert(info.id.clone(), Arc::new(RwLock::new(dome)));
}
```

**Step 2: Remove unused getters if no call sites exist**

```rust
// native/nightshade_native/bridge/src/ascom_wrapper_dome.rs
// Remove id(), name(), cached_name() if not used anywhere.
```

**Step 3: Ensure disconnect path uses wrapper (already in place)**

**Step 4: Verify**
Run: `cd native/nightshade_native/bridge; cargo check`  
Expected: No dead_code warnings for `AscomDomeWrapper` or `AscomDomeCommand`.

**Impact notes:** ASCOM domes become fully managed (timeouts + worker thread).

---

### Task 11: Add ASCOM Switch support (wrapper + API path)

**Files:**  
- Modify: `native/nightshade_native/bridge/src/devices.rs`  
- Modify: `native/nightshade_native/bridge/src/api.rs`  
- Modify: `native/nightshade_native/bridge/src/ascom_wrapper_switch.rs` (if new methods needed)  
- Modify: `packages/nightshade_bridge/lib/src/api.dart` (FRB regen required)  
- Test: `native/nightshade_native/bridge` (cargo check)

**Step 1: Connect ASCOM switches and store in `ascom_switches`**

```rust
// native/nightshade_native/bridge/src/devices.rs
DeviceType::Switch => {
    use crate::ascom_wrapper_switch::AscomSwitchWrapper;
    let mut sw = AscomSwitchWrapper::new(prog_id.to_string())?;
    sw.connect().await.map_err(|e| e.to_string())?;
    let mut ascom_switches = self.ascom_switches.write().await;
    ascom_switches.insert(info.id.clone(), Arc::new(RwLock::new(sw)));
}
```

**Step 2: Add Rust API functions for switch operations**

```rust
// native/nightshade_native/bridge/src/api.rs
pub async fn api_switch_get_max(device_id: String) -> Result<i32, NightshadeError> {
    let mgr = get_device_manager();
    mgr.switch_get_max(&device_id).await.map_err(NightshadeError::OperationFailed)
}
```

**Step 3: Implement `switch_*` methods in device manager using wrapper**

```rust
// native/nightshade_native/bridge/src/devices.rs
pub async fn switch_get_max(&self, device_id: &str) -> Result<i32, String> {
    let switches = self.ascom_switches.read().await;
    if let Some(sw) = switches.get(device_id) {
        let sw = sw.read().await;
        return sw.get_max_switch().await;
    }
    Err(format!("ASCOM switch {} not found", device_id))
}
```

**Step 4: Add the remaining switch APIs (get/set switch, get name/description, etc.)**
Pattern after `api_switch_get_max`, mirroring ASCOM Switch capabilities.

**Step 5: Regenerate FRB bindings**
Run: `powershell -ExecutionPolicy Bypass -File scripts\dev.ps1 -NoRun`

**Impact notes:** New switch operations become accessible from Dart; no warnings for unused switch wrapper methods.

---

### Task 12: Use ASCOM mount/focuser command variants (and Stop command)

**Files:**  
- Modify: `native/nightshade_native/bridge/src/ascom_wrapper_mount.rs`  
- Modify: `native/nightshade_native/bridge/src/ascom_wrapper_focuser.rs`  
- Modify: `native/nightshade_native/bridge/src/devices.rs`  
- Test: `native/nightshade_native/bridge` (cargo check)

**Step 1: Expose `can_park` and `stop` in mount device manager**

```rust
// native/nightshade_native/bridge/src/devices.rs
pub async fn mount_can_park(&self, device_id: &str) -> Result<bool, String> {
    let mounts = self.ascom_mounts.read().await;
    if let Some(mount) = mounts.get(device_id) {
        let mount = mount.read().await;
        return mount.can_park().await;
    }
    Err(format!("ASCOM mount {} not found", device_id))
}
```

**Step 2: Use focuser `get_max_position` and `get_step_size` in capabilities**

```rust
// native/nightshade_native/bridge/src/devices.rs
let max_pos = focuser_guard.get_max_position().await.ok();
let step_size = focuser_guard.get_step_size().await.ok();
```

**Step 3: Use `AscomCommand::Stop` in `ascom_wrapper.rs`**
Add a `stop` method and call it from the camera/mount stop API so the variant is constructed.

```rust
// native/nightshade_native/bridge/src/ascom_wrapper.rs
pub async fn stop(&self) -> Result<(), String> {
    let (tx, rx) = oneshot::channel();
    self.sender.send(AscomCommand::Stop(tx)).await
        .map_err(|e| format!("Send error: {}", e))?;
    rx.await.map_err(|_| "Worker thread dead during stop".to_string())
}

// inside the worker loop
AscomCommand::Stop(reply) => {
    if let Some(cam) = &mut camera {
        let _ = reply.send(cam.stop_exposure().map_err(|e| e.to_string()));
    } else {
        let _ = reply.send(Err("Camera not created".to_string()));
    }
}
```

**Impact notes:** Capabilities report real limits; stop/park support becomes explicit.

---

### Task 13: Cover calibrator wrapper usage

**Files:**  
- Modify: `native/nightshade_native/bridge/src/devices.rs`  
- Modify: `native/nightshade_native/bridge/src/ascom_wrapper_covercalibrator.rs`

**Step 1: Use wrapper methods for brightness and name where available**

```rust
// native/nightshade_native/bridge/src/devices.rs
let max_brightness = locked.max_brightness().await.unwrap_or(255);
let name = locked.name().await.unwrap_or_else(|_| locked.cached_name().to_string());
```

**Impact notes:** Eliminates dead code and surfaces device metadata to UI.

---

### Task 14: Vendor camera shim cleanup (svbony/atik/fli/touptek)

**Files:**  
- Modify: `native/nightshade_native/native/src/vendor/svbony.rs`  
- Modify: `native/nightshade_native/native/src/vendor/atik.rs`  
- Modify: `native/nightshade_native/native/src/vendor/fli.rs`  
- Modify: `native/nightshade_native/native/src/vendor/touptek.rs`

**Step 1: Trim unused svbony enum variants and fields**

```rust
// native/nightshade_native/native/src/vendor/svbony.rs
enum SvbControlType {
    Gain = 0,
    Exposure = 1,
    BlackLevel = 13,
    CoolerEnable = 14,
    TargetTemperature = 15,
    CurrentTemperature = 16,
    CoolerPower = 17,
}
```

**Step 2: Remove unused items that have no call sites**
- Remove `SvbBayerPattern` + `to_bayer_pattern` if not referenced anywhere.  
- Remove `SvbImgType` variants other than `Raw8` and `Raw16` (only used ones).  
- Remove `get_serial_number` field from `SvbonySdk` if unused.  
- Remove sync `get_control_range` if only async version is used.

**Step 3: Fix non-snake-case parameter names in touptek type aliases**

```rust
// native/nightshade_native/native/src/vendor/touptek.rs
type OgmacamPullImageV3 = unsafe extern "system" fn(
    h: HOgmacam,
    p_image_data: *mut c_void,
    b_still: c_int,
    row_pitch: c_int,
    p_info: *mut OgmacamFrameInfoV3,
) -> i32;
```

Apply the same snake_case rename pattern for `nMin/nMax/nDef`, `xOffset/yOffset/xWidth/yHeight`,
`nNumber`, and `nResolutionIndex` in other `type` aliases in this file.

**Step 4: Remove unused imports/constants in `fli.rs`**
Delete `BayerPattern` and `c_int` imports, and remove unused constants/type aliases listed in warnings.

**Impact notes:** No runtime change for removed unused items; fewer unused SDK surfaces.

---

### Task 15: Vendor mount shim cleanup (moravian/skywatcher/ioptron/lx200)

**Files:**  
- Modify: `native/nightshade_native/native/src/vendor/moravian.rs`  
- Modify: `native/nightshade_native/native/src/vendor/skywatcher.rs`  
- Modify: `native/nightshade_native/native/src/vendor/ioptron.rs`  
- Modify: `native/nightshade_native/native/src/vendor/lx200.rs`

**Step 1: Remove unused constants/fields without call sites**

Example removals (verify with `rg` first):
- `moravian.rs`: `LongReal`, `GBP_*`, `GIP_*`, `GSP_*`, `GV_*`, `move_telescope`, `discovery_index`, `get_*_param`  
- `skywatcher.rs`: `SYNSCAN_BAUD_RATE_FAST`, `latitude`, `longitude`  
- `ioptron.rs`: `GET_FIRMWARE`, `firmware_version`  
- `lx200.rs`: `ONSTEP_*`, `firmware_version`

```rust
// Remove unused fields/constants and adjust struct initializers accordingly.
```

Example (SkyWatcher mount struct cleanup):

```rust
// native/nightshade_native/native/src/vendor/skywatcher.rs
pub struct SkyWatcherMount {
    // remove latitude/longitude if never read
}
```

**Impact notes:** No runtime change if removals are truly unused; if features are required, reintroduce with full implementation.

---

### Task 16: Sequencer HFR helpers

**Files:**  
- Modify: `native/nightshade_native/sequencer/src/instructions.rs`

**Step 1: Remove unused HFR helpers if not wired into autofocus**  
Delete `HfrMeasurement` and the unused `calculate_hfr_*`/`find_best_focus` functions once verified as unused.

**Impact notes:** No runtime change (dead code removed).

---

### Task 17: Handle `StreamSink::add` results

**Files:**  
- Modify: `native/nightshade_native/bridge/src/api.rs`  
- Test: `native/nightshade_native/bridge` (cargo check)

**Step 1: Handle errors explicitly**

```rust
if let Err(err) = sink.add(event) {
    tracing::warn!("[API_EVENT_STREAM] Failed to send event: {}", err);
    break;
}
```

**Impact notes:** Prevents silent event stream failures; ensure Dart side reconnect logic still works.

---

## Final Verification

1. Run: `powershell -ExecutionPolicy Bypass -File scripts\dev.ps1 -NoRun *> "docs\frb_warnings_postfix.txt"`  
2. Run: `rg "warning:" docs\frb_warnings_postfix.txt`  
Expected: Zero warnings (or only hardware-not-present warnings, which should be addressed by code changes above).

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-02-01-frb-warning-remediation-plan.md`.

Two execution options:
1. Subagent-Driven (this session) - I dispatch fresh subagent per task, review between tasks, fast iteration  
2. Parallel Session (separate) - Open new session with executing-plans, batch execution with checkpoints

Which approach?
