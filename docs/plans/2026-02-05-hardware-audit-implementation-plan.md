# Hardware Audit: Implementation Plan

**Date:** 2026-02-05
**Prerequisite:** `docs/plans/2026-02-05-hardware-compatibility-audit.md`
**Execution:** Designed for sub-agent execution. Each task is self-contained with exact files, exact changes, and clear boundaries.

---

## Task Execution Rules

1. **No stubs or placeholders.** Every task must produce complete, working code.
2. **No scope creep.** Each agent does exactly what is specified -- nothing more, nothing less.
3. **Errors are features.** Never add silent fallbacks or swallow errors.
4. **Each task must compile.** Agent must verify `cargo check` passes for the relevant crate before declaring done.

---

## Phase 1: Pre-Launch Critical Fixes

These tasks can be executed in parallel where noted.

---

### Task 1.1: Complete ASCOM Capability Queries for Rotator

**Priority:** P1
**Parallel Group:** A (can run with 1.2-1.6)
**Crate:** `nightshade_native` (bridge)
**Files to modify:**
- `native/nightshade_native/bridge/src/device_capabilities.rs`

**What to do:**

In `get_ascom_capabilities()` (around line 867, just before the final `else` error block), add an `else if` branch for Rotator devices:

```
else if prog_id_lower.contains("rotator") {
```

Inside this branch:
1. Create an `AscomRotator` from `nightshade_ascom` (same pattern as Focuser at lines 820-843 which uses `nightshade_ascom::AscomFocuser` directly)
2. Connect to the device
3. Query these properties and build a `RotatorCapabilities` struct (already defined at lines 216-236):
   - `can_reverse` (bool)
   - `reverse` (bool)
   - `step_size` (f64)
   - `is_moving` (bool)
   - `mechanical_position` (f64)
   - `position` (f64)
   - `can_move_absolute` (bool, try `MoveAbsolute` existence)
   - `can_halt` (bool, try `Halt` existence)
   - `can_sync` (bool, try `Sync` existence)
4. Disconnect from the device
5. Return `Ok(DeviceCapabilities::Rotator(caps))`

**Reference pattern:** Copy the Focuser branch (lines 820-843) and adapt for Rotator properties.

**Verify:** `cargo check --package nightshade_bridge`

---

### Task 1.2: Complete ASCOM Capability Queries for Dome

**Priority:** P1
**Parallel Group:** A
**Crate:** `nightshade_native` (bridge)
**Files to modify:**
- `native/nightshade_native/bridge/src/device_capabilities.rs`

**What to do:**

Add an `else if` branch for Dome devices:

```
else if prog_id_lower.contains("dome") {
```

1. Use the existing `AscomDomeWrapper` from `ascom_wrapper_dome.rs` OR direct `nightshade_ascom::AscomDome`
2. Connect, query properties, build `DomeCapabilities` struct (already defined at lines 243-271):
   - `can_set_azimuth` (bool)
   - `can_park` (bool)
   - `can_find_home` (bool)
   - `can_set_shutter` (bool)
   - `can_slave` (bool)
   - `can_sync_azimuth` (bool)
   - `azimuth` (f64)
   - `slewing` (bool)
   - `at_home` (bool)
   - `at_park` (bool)
   - `shutter_status` (String)
   - `slaved` (bool)
   - `altitude` (f64, optional)
   - `can_set_altitude` (bool)
3. Disconnect
4. Return `Ok(DeviceCapabilities::Dome(caps))`

**Verify:** `cargo check --package nightshade_bridge`

---

### Task 1.3: Complete ASCOM Capability Queries for SafetyMonitor

**Priority:** P1
**Parallel Group:** A
**Crate:** `nightshade_native` (bridge)
**Files to modify:**
- `native/nightshade_native/bridge/src/device_capabilities.rs`

**What to do:**

Add an `else if` branch for SafetyMonitor:

```
else if prog_id_lower.contains("safetymonitor") {
```

1. Use `nightshade_ascom::AscomSafetyMonitor` (available in `ascom/src/windows_impl.rs` around line 2832)
2. Connect, query properties, build `SafetyMonitorCapabilities` struct (already defined at lines 360-367):
   - `is_safe` (bool)
   - `safety_description` (String, from device Description property)
3. Disconnect
4. Return `Ok(DeviceCapabilities::SafetyMonitor(caps))`

**Verify:** `cargo check --package nightshade_bridge`

---

### Task 1.4: Complete ASCOM Capability Queries for ObservingConditions (Weather)

**Priority:** P1
**Parallel Group:** A
**Crate:** `nightshade_native` (bridge)
**Files to modify:**
- `native/nightshade_native/bridge/src/device_capabilities.rs`

**What to do:**

Add an `else if` branch for ObservingConditions/Weather:

```
else if prog_id_lower.contains("observingconditions") || prog_id_lower.contains("weather") {
```

1. Use `nightshade_ascom::AscomObservingConditions` (available in `ascom/src/windows_impl.rs` around line 2908)
2. Connect, query each sensor availability (wrap each in try/catch -- sensors throw `PropertyNotImplementedException` when unavailable), build `WeatherCapabilities` struct (already defined at lines 324-354):
   - `has_cloud_cover`, `has_dew_point`, `has_humidity`, `has_pressure`, `has_rain_rate`, `has_sky_brightness`, `has_sky_quality`, `has_sky_temperature`, `has_star_fwhm`, `has_temperature`, `has_wind_direction`, `has_wind_gust`, `has_wind_speed` (all bool)
   - `time_since_last_update` (f64)
   - `average_period` (f64)
   - Read current values for sensors that are available
3. Disconnect
4. Return `Ok(DeviceCapabilities::Weather(caps))`

**Verify:** `cargo check --package nightshade_bridge`

---

### Task 1.5: Complete ASCOM Capability Queries for Switch

**Priority:** P1
**Parallel Group:** A
**Crate:** `nightshade_native` (bridge)
**Files to modify:**
- `native/nightshade_native/bridge/src/device_capabilities.rs`

**What to do:**

Add an `else if` branch for Switch:

```
else if prog_id_lower.contains("switch") {
```

1. Use `nightshade_ascom::AscomSwitch` or the existing `AscomSwitchWrapper` from `ascom_wrapper_switch.rs`
2. Connect, query properties, build `SwitchCapabilities` struct (already defined at lines 373-403):
   - `switch_count` (i32, from `MaxSwitch`)
   - `switches` (Vec of `SwitchInfo` with `id`, `name`, `description`, `value`, `min_value`, `max_value`, `step`, `can_write` for each switch 0..MaxSwitch)
3. Disconnect
4. Return `Ok(DeviceCapabilities::Switch(caps))`

**Verify:** `cargo check --package nightshade_bridge`

---

### Task 1.6: Complete ASCOM Capability Queries for CoverCalibrator

**Priority:** P1
**Parallel Group:** A
**Crate:** `nightshade_native` (bridge)
**Files to modify:**
- `native/nightshade_native/bridge/src/device_capabilities.rs`

**What to do:**

Add an `else if` branch for CoverCalibrator:

```
else if prog_id_lower.contains("covercalibrator") || prog_id_lower.contains("flatpanel") {
```

1. Use the existing `AscomCoverCalibratorWrapper` from `ascom_wrapper_covercalibrator.rs` OR direct `nightshade_ascom::AscomCoverCalibrator`
2. Connect, query properties, build `CoverCalibratorCapabilities` struct (already defined at lines 298-313):
   - `max_brightness` (i32)
   - `cover_present` (bool, derive from CoverState != NotPresent)
   - `calibrator_present` (bool, derive from CalibratorState != NotPresent)
   - `cover_state` (CoverState)
   - `calibrator_state` (CalibratorState)
   - `brightness` (i32)
3. Disconnect
4. Return `Ok(DeviceCapabilities::CoverCalibrator(caps))`

**Verify:** `cargo check --package nightshade_bridge`

---

### Task 1.7: Add INDI Weather Device Support

**Priority:** P1
**Parallel Group:** B (can run with 1.8)
**Crate:** `nightshade_indi`
**Files to modify:**
- `native/nightshade_native/indi/src/weather.rs` (NEW FILE)
- `native/nightshade_native/indi/src/lib.rs`
- `native/nightshade_native/indi/src/protocol.rs`

**What to do:**

**Step 1:** Create `native/nightshade_native/indi/src/weather.rs`

Model it after `safetymonitor.rs` (224 lines). The safety monitor already reads weather properties -- the weather module provides a dedicated interface for weather devices.

Create `IndiWeather` struct with:
- Fields: `client: Arc<RwLock<IndiClient>>`, `device_name: String`
- `new(client, device_name)`, `device_name()`, `connect()`, `disconnect()`, `is_connected()` (copy pattern from safetymonitor.rs lines 24-58)
- Weather measurement methods (use INDI standard property names):
  - `get_temperature()` -> reads `WEATHER_PARAMETERS.WEATHER_TEMPERATURE`
  - `get_humidity()` -> reads `WEATHER_PARAMETERS.WEATHER_HUMIDITY`
  - `get_pressure()` -> reads `WEATHER_PARAMETERS.WEATHER_PRESSURE`
  - `get_wind_speed()` -> reads `WEATHER_PARAMETERS.WEATHER_WIND_SPEED`
  - `get_wind_gust()` -> reads `WEATHER_PARAMETERS.WEATHER_WIND_GUST`
  - `get_wind_direction()` -> reads `WEATHER_PARAMETERS.WEATHER_WIND_DIRECTION`
  - `get_cloud_cover()` -> reads `WEATHER_PARAMETERS.WEATHER_CLOUD_COVER`
  - `get_rain_rate()` -> reads `WEATHER_PARAMETERS.WEATHER_RAIN_RATE`
  - `get_dew_point()` -> reads `WEATHER_PARAMETERS.WEATHER_DEWPOINT`
  - `get_sky_quality()` -> reads `WEATHER_PARAMETERS.WEATHER_SKY_QUALITY`
  - `get_sky_temperature()` -> reads `WEATHER_PARAMETERS.WEATHER_SKY_TEMPERATURE`
  - `get_sky_brightness()` -> reads `WEATHER_PARAMETERS.WEATHER_SKY_BRIGHTNESS`
- Status methods:
  - `get_overall_status()` -> reads `WEATHER_STATUS` light property, returns enum (Ok/Warning/Alert)
  - `has_rain_alert()`, `has_wind_alert()`, `has_cloud_alert()`, `has_humidity_alert()` (same pattern as safetymonitor.rs lines 190-223)
  - `is_safe()` -> derives from WEATHER_STATUS overall state
- Availability methods:
  - `has_temperature()`, `has_humidity()`, etc. -> check if property elements exist

All methods return `Option<f64>` (None if property not available). Use `client.get_number()` exactly like safetymonitor.rs does.

**Step 2:** Modify `native/nightshade_native/indi/src/lib.rs`:
- Add `mod weather;` after `mod covercalibrator;` (around line 56)
- Add `pub use weather::IndiWeather;` after the covercalibrator pub use (around line 70)
- Remove the weather block from `check_feature_support()` (lines 117-121) -- delete those 5 lines so weather is no longer rejected

**Step 3:** Add weather property constants to `native/nightshade_native/indi/src/protocol.rs`:
- Add constants for `WEATHER_STATUS`, `WEATHER_PARAMETERS`, and element names

**Verify:** `cargo check --package nightshade_indi`

---

### Task 1.8: Add INDI Switch Device Support

**Priority:** P1
**Parallel Group:** B
**Crate:** `nightshade_indi`
**Files to modify:**
- `native/nightshade_native/indi/src/switch.rs` (NEW FILE)
- `native/nightshade_native/indi/src/lib.rs`

**What to do:**

**Step 1:** Create `native/nightshade_native/indi/src/switch.rs`

Model it after `rotator.rs` (154 lines) -- switches are simple devices.

Create `IndiSwitch` struct with:
- Fields: `client: Arc<RwLock<IndiClient>>`, `device_name: String`
- `new(client, device_name)`, `device_name()`, `connect()`, `disconnect()`, `is_connected()`
- Switch methods:
  - `get_switch_count()` -> enumerate switch properties on the device, count them
  - `get_switch_name(index)` -> get switch property name at index
  - `get_switch_state(name)` -> `client.get_switch(device, property_name, element)` returns bool
  - `set_switch_state(name, on: bool)` -> `client.set_switch()`
  - `get_switch_value(name)` -> `client.get_number()` for dimmer/PWM switches
  - `set_switch_value(name, value)` -> `client.set_number()` for dimmer/PWM switches
  - `get_all_switches()` -> returns vec of (name, state, description) tuples
  - `is_switch_read_only(name)` -> check property permission

INDI switches use custom property names per driver (unlike ASCOM's indexed MaxSwitch). Discovery must enumerate properties that look like switch groups.

**Step 2:** Modify `native/nightshade_native/indi/src/lib.rs`:
- Add `mod switch;` after the weather module declaration
- Add `pub use switch::IndiSwitch;`
- Remove the switch block from `check_feature_support()` (lines 122-126) -- delete those 5 lines

**Verify:** `cargo check --package nightshade_indi`

---

### Task 1.9: Wire INDI Weather into Bridge Layer

**Priority:** P1
**Parallel Group:** C (depends on 1.7 completing)
**Crate:** `nightshade_native` (bridge)
**Files to modify:**
- `native/nightshade_native/bridge/src/indi_devices.rs` (or wherever INDI devices are dispatched to the bridge)

**What to do:**

Find where other INDI device types (camera, mount, focuser, etc.) are dispatched/created in the bridge layer and add Weather handling. The pattern will look like:

1. Find the match/dispatch on `DeviceType::Weather` for INDI connections
2. Add a branch that creates an `IndiWeather` and delegates calls to it
3. Map `IndiWeather` methods to the bridge's weather API methods (get_temperature, get_humidity, etc.)
4. Make sure `DeviceType::Weather` no longer returns "not supported" for INDI driver type

Search for where `IndiCamera`, `IndiMount`, `IndiFocuser` etc. are instantiated in the bridge -- the Weather entry should follow the same pattern.

**Verify:** `cargo check --package nightshade_bridge`

---

### Task 1.10: Wire INDI Switch into Bridge Layer

**Priority:** P1
**Parallel Group:** C (depends on 1.8 completing)
**Crate:** `nightshade_native` (bridge)
**Files to modify:**
- `native/nightshade_native/bridge/src/indi_devices.rs` (or wherever INDI devices are dispatched)

**What to do:**

Same as Task 1.9 but for Switch:

1. Find the dispatch on `DeviceType::Switch` for INDI connections
2. Add a branch that creates an `IndiSwitch` and delegates calls
3. Map `IndiSwitch` methods to bridge switch API methods

**Verify:** `cargo check --package nightshade_bridge`

---

### Task 1.11: Touptek Multi-Brand DLL Support -- SDK Loader Refactor

**Priority:** P1
**Parallel Group:** D (standalone)
**Crate:** `nightshade_native` (native)
**Files to modify:**
- `native/nightshade_native/native/src/vendor/touptek.rs`

**What to do:**

Refactor `TouptekSdk::load()` to accept a DLL name and function prefix as parameters instead of hardcoding `ogmacam.dll` and `Ogmacam_`.

**Step 1:** Change `TouptekSdk::load()` signature:
```rust
fn load(dll_name: &str, func_prefix: &str) -> Result<Self, NativeError>
```

Replace `Library::new("ogmacam.dll")` with `Library::new(dll_name)`.

Replace all hardcoded symbol names. For each function pointer load, change from:
```rust
library.get::<OgmacamEnumV2>(b"Ogmacam_EnumV2\0")
```
to building the symbol name dynamically:
```rust
let symbol = format!("{}_EnumV2\0", func_prefix);
library.get::<OgmacamEnumV2>(symbol.as_bytes())
```

Do this for ALL 15 function pointer loads (enum_v2, open_by_index, close, stop, pull_image_v3, put_expo_time, put_expo_again, get_expo_again_range, get_temperature, put_temperature, put_option, get_size, put_roi, get_serial_number, snap).

**Step 2:** Change the static SDK storage from a single `OnceLock` to a map of SDKs by brand:
```rust
use std::collections::HashMap;
use std::sync::Mutex;

static SDKS: OnceLock<Mutex<HashMap<String, Result<TouptekSdk, String>>>> = OnceLock::new();
```

**Step 3:** Define the supported brands:
```rust
const TOUPTEK_BRANDS: &[(&str, &str)] = &[
    ("ogmacam.dll", "Ogmacam"),
    ("toupcam.dll", "Toupcam"),
    ("altaircam.dll", "Altaircam"),
    ("mallincam.dll", "Mallincam"),
];
```

On Linux/macOS, use `.so`/`.dylib` extensions instead (conditional compilation).

**Step 4:** Update `get_sdk()` to take a brand parameter, and update `discover_devices()` to iterate over all brands, attempting to load each DLL. For each successfully loaded SDK, discover cameras from that brand. Tag discovered cameras with their brand name so the correct SDK is used at connection time.

**Step 5:** Update `TouptekCamera` and `TouptekDeviceInfo` to store which brand/SDK instance the camera belongs to. Update `connect()` and all camera operations to use the correct SDK instance.

**Step 6:** Update the discovery mapping in `native/src/discovery.rs` to include brand info in the device ID, e.g. `"native:touptek:ogma:0"` vs `"native:touptek:altair:0"`.

**Step 7:** Update the connection dispatch in `bridge/src/devices.rs` to parse the brand from the device ID and pass it through.

**Verify:** `cargo check --package nightshade_native` and `cargo check --package nightshade_bridge`

---

### Task 1.12: Add Fujifilm Warranty Disclaimer

**Priority:** P1
**Parallel Group:** E (standalone, Dart only)
**Crate:** `nightshade_app`
**Files to modify:**
- `packages/nightshade_app/lib/screens/equipment/` (find the device connection dialog or equipment screen)

**What to do:**

When a user selects a Fujifilm camera (device ID contains "fujifilm" or vendor is Fujifilm), show a one-time warning dialog before connection:

**Dialog text:**
> "Fujifilm Camera Control SDK Notice: According to Fujifilm's SDK license agreement, using third-party software to control your Fujifilm camera may void its limited product warranty. By proceeding, you acknowledge this risk. This notice will not be shown again."

Implementation:
1. Find where `connectDevice` is called for cameras in the equipment screen
2. Check if the device ID/name indicates Fujifilm
3. Check a shared preference key (e.g., `fujifilm_disclaimer_acknowledged`) -- if not set, show the dialog
4. On "I Understand" button: set the preference and proceed with connection
5. On "Cancel": do not connect

Use `SharedPreferences` or the app's existing settings provider to persist the acknowledgment.

**Verify:** `flutter analyze` passes for `nightshade_app`

---

### Task 1.13: Update INDI Support Matrix Documentation

**Priority:** P1
**Parallel Group:** F (depends on 1.7 and 1.8 completing)
**Crate:** `nightshade_indi`
**Files to modify:**
- `native/nightshade_native/indi/src/lib.rs` (doc comment at top of file)

**What to do:**

Update the support matrix table in the module doc comment (lines 8-19) to reflect that Weather and Switch are now supported:

Change:
```
//! | Weather          | NOT SUPPORTED | Use ASCOM Alpaca for weather devices     |
//! | Switch           | NOT SUPPORTED | Use ASCOM Alpaca for switch devices      |
```

To:
```
//! | Weather          | Full          | All standard INDI weather properties     |
//! | Switch           | Full          | Custom switch property enumeration       |
```

Also update the "Unsupported Features" section (lines 22-25) to remove Weather and Switch.

**Verify:** `cargo check --package nightshade_indi`

---

## Phase 2: Post-Launch Important Fixes

These tasks require more effort and can be scheduled after initial release.

---

### Task 2.1: Expose Native ZWO EAF Focuser via Bridge API

**Priority:** P2
**Parallel Group:** G (can run with 2.2, 2.3)
**Crate:** `nightshade_native` (bridge + native)
**Files to modify:**
- `native/nightshade_native/bridge/src/devices.rs` (connection dispatch)
- `native/nightshade_native/bridge/src/api.rs` (focuser API methods)

**What to do:**

The ZWO EAF focuser is already fully implemented in `zwo.rs` (lines 1503-1835) with discovery, connection, and all `NativeFocuser` trait methods. It's also already discovered in `discovery.rs` (lines 194-214) with device type `DeviceType::Focuser` and ID format `"native:zwo_eaf:{id}"`.

What's likely missing is the **bridge-layer dispatch** -- when `api_connect_device(DeviceType::Focuser, "native:zwo_eaf:0")` is called, it needs to create a `ZwoFocuser` and delegate operations.

1. In `bridge/src/devices.rs`, find the device creation match for focusers (or the native vendor dispatch)
2. Add a case for `"zwo_eaf"` vendor prefix that creates a `Box<dyn NativeFocuser>` from `ZwoFocuser::new(id)`
3. Verify the bridge API methods for focuser (move_to, get_position, halt, get_temperature) are wired through to the native focuser trait

Test by checking that `api_discover_devices(DeviceType::Focuser)` returns ZWO EAF devices and `api_connect_device` works.

**Verify:** `cargo check --package nightshade_bridge`

---

### Task 2.2: Expose Native ZWO EFW Filter Wheel via Bridge API

**Priority:** P2
**Parallel Group:** G
**Crate:** `nightshade_native` (bridge + native)
**Files to modify:**
- `native/nightshade_native/bridge/src/devices.rs`
- `native/nightshade_native/bridge/src/api.rs`

**What to do:**

Same pattern as Task 2.1 but for ZWO EFW filter wheels. The implementation exists in `zwo.rs` (lines 1958-2262) with full `NativeFilterWheel` trait support. Discovery maps to `"native:zwo_efw:{id}"`.

1. Add `"zwo_efw"` vendor prefix dispatch in device creation
2. Create `Box<dyn NativeFilterWheel>` from `ZwoFilterWheel::new(id)`
3. Verify bridge API methods for filter wheel (move_to_position, get_position, is_moving, get_filter_names) are wired through

**Verify:** `cargo check --package nightshade_bridge`

---

### Task 2.3: Expose Native FLI Focuser and Filter Wheel via Bridge API

**Priority:** P2
**Parallel Group:** G
**Crate:** `nightshade_native` (bridge + native)
**Files to modify:**
- `native/nightshade_native/bridge/src/devices.rs`
- `native/nightshade_native/bridge/src/api.rs`

**What to do:**

FLI focusers and filter wheels are already implemented in `fli.rs` with discovery mapped in `discovery.rs` to `"native:fli_focuser:{path}"` and `"native:fli_fw:{path}"`.

1. Add `"fli_focuser"` and `"fli_fw"` vendor prefix dispatch in device creation
2. Wire through to `FliFocuser` and `FliFilterWheel` trait implementations
3. Verify bridge API method delegation

**Verify:** `cargo check --package nightshade_bridge`

---

### Task 2.4: Expose Native QHY CFW Filter Wheel via Bridge API

**Priority:** P2
**Parallel Group:** G
**Crate:** `nightshade_native` (bridge + native)
**Files to modify:**
- `native/nightshade_native/bridge/src/devices.rs`

**What to do:**

QHY CFW is mapped to `"native:qhy_cfw:{camera_id}"` in discovery. The implementation in `qhy.rs` (lines 1401-1637) depends on the camera connection (filter wheel is controlled through the camera handle).

1. Add `"qhy_cfw"` vendor prefix dispatch
2. Wire through to `QhyFilterWheel` -- note this requires the associated camera to be connected first
3. Add error handling for the case where the camera is not connected when the filter wheel connect is attempted

**Verify:** `cargo check --package nightshade_bridge`

---

### Task 2.5: Add Hard Operation Timeouts for Focuser Moves

**Priority:** P2
**Parallel Group:** H (standalone Dart task)
**Crate:** `nightshade_core`
**Files to modify:**
- `packages/nightshade_core/lib/src/services/device_service.dart`

**What to do:**

The filter wheel already has position verification with a 60-second timeout (lines 1963-2047). Apply the same pattern to focuser moves:

1. Find the focuser move method in `device_service.dart`
2. After sending the move command to the backend, add a polling loop:
   - Poll `get_position()` every 500ms
   - Compare to target position
   - Timeout after 300 seconds (5 minutes -- focusers can be very slow)
   - If timeout: throw exception with current position and target position
   - If position matches target (within 1 step tolerance): return success
3. Check for `is_moving() == false` as an early exit if position hasn't reached target (indicates stall)

**Verify:** `flutter analyze` passes for `nightshade_core`

---

### Task 2.6: Expose Quirks Database in Equipment Screen UI

**Priority:** P3
**Parallel Group:** I (standalone Dart task)
**Crate:** `nightshade_app`
**Files to modify:**
- `packages/nightshade_app/lib/screens/equipment/` (device dashboard or device card widgets)

**What to do:**

When a device is connected, query the quirks database for that device and display any known quirks as an info banner on the device card.

1. Add a bridge API method `api_get_device_quirks(device_id: String) -> Vec<QuirkInfo>` that calls `get_quirks_for_device()` from `native/src/quirks/mod.rs` and returns a simplified list of quirk descriptions
2. In the device card widget (when connected), call this API and display quirks as an expandable info section:
   - Icon: info/warning icon
   - Text: "Known device characteristics: {quirk descriptions}"
   - Only shown when quirks exist (don't show empty section)
3. Quirk descriptions should be user-friendly (e.g., "Temperature readings from this camera are scaled by 10x and automatically corrected")

This requires changes on both Rust and Dart sides:
- Rust: Add `api_get_device_quirks` to `bridge/src/api.rs` that calls the quirks module
- Dart: Add UI to display quirk info on device cards

**Verify:** `cargo check --package nightshade_bridge` and `flutter analyze` for `nightshade_app`

---

## Phase 3: Future Differentiators

These are larger features that require design decisions and are not suitable for immediate sub-agent execution without further brainstorming.

---

### Task 3.1: Canon EDSDK Native Camera Support

**Status:** Requires Canon SDK license application first
**Effort:** High (~2000+ lines of Rust)
**Prerequisite:** Obtain Canon EDSDK from Canon's developer program

### Task 3.2: Nikon SDK Native Camera Support

**Status:** Requires Nikon SDK license application first
**Effort:** High (~1500+ lines of Rust)
**Prerequisite:** Obtain Nikon SDK from Nikon's developer program

### Task 3.3: Celestron AUX Mount Protocol

**Status:** Needs protocol spec research
**Effort:** Medium (~1500 lines of Rust)
**Reference:** INDI `indi-celestronaux` driver source code

### Task 3.4: Native Pegasus Powerbox Integration

**Status:** Needs serial protocol documentation
**Effort:** Medium (~800 lines of Rust)
**Reference:** Pegasus INDI driver, ASCOM driver protocol docs

---

## Execution Order & Dependencies

```
Phase 1 (Parallel Groups):

Group A (all parallel): Tasks 1.1, 1.2, 1.3, 1.4, 1.5, 1.6
  - All modify device_capabilities.rs but different sections
  - CAUTION: If agents run truly in parallel they'll conflict on the same file
  - RECOMMENDATION: Run as a SINGLE agent that does all 6 in sequence within one task

Group B (parallel): Tasks 1.7, 1.8
  - Different new files, same lib.rs modifications
  - RECOMMENDATION: Run as a SINGLE agent for both

Group C (depends on B): Tasks 1.9, 1.10
  - Wire the new INDI modules into bridge
  - Can run as a single agent

Group D (standalone): Task 1.11
  - Large refactor, run alone

Group E (standalone): Task 1.12
  - Dart-only, no Rust dependencies

Group F (depends on B): Task 1.13
  - Quick doc update

Phase 2 (after Phase 1):

Group G (parallel): Tasks 2.1, 2.2, 2.3, 2.4
  - All modify devices.rs -- run as SINGLE agent

Group H (standalone): Task 2.5
  - Dart-only

Group I (standalone): Task 2.6
  - Cross-layer (Rust + Dart)
```

---

## Recommended Agent Assignments

| Agent # | Tasks | Description | Est. Size |
|---------|-------|-------------|-----------|
| **Agent 1** | 1.1-1.6 | Complete all 6 ASCOM capability query branches | ~300 lines Rust |
| **Agent 2** | 1.7, 1.8, 1.13 | Add INDI Weather + Switch modules + update docs | ~400 lines Rust |
| **Agent 3** | 1.9, 1.10 | Wire INDI Weather + Switch into bridge layer | ~150 lines Rust |
| **Agent 4** | 1.11 | Touptek multi-brand DLL refactor | ~200 lines Rust refactor |
| **Agent 5** | 1.12 | Fujifilm warranty disclaimer dialog | ~80 lines Dart |
| **Agent 6** | 2.1-2.4 | Expose native focusers/filter wheels in bridge | ~200 lines Rust |
| **Agent 7** | 2.5 | Hard focuser move timeouts | ~60 lines Dart |
| **Agent 8** | 2.6 | Quirks database UI exposure | ~150 lines Rust + Dart |
