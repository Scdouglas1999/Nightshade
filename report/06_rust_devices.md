# 6. Rust Device Drivers Audit

**Rating: 8.5/10 -- Strong, production-quality driver layer with minor issues**

## Scope
- `native/nightshade_native/ascom/src/` - Windows COM ASCOM drivers (3,756 lines)
- `native/nightshade_native/indi/src/` - Linux/macOS INDI protocol (8,476 lines)
- `native/nightshade_native/alpaca/src/` - ASCOM Alpaca HTTP (6,548 lines)
- `native/nightshade_native/native/src/` - Vendor SDK FFI bindings (17,534+ lines)
- `native/nightshade_native/bridge/src/` - Bridge device dispatch & guards (12,124 lines)

Total: ~48,400+ lines of device driver code.

---

## Feature Inventory

### 1. ASCOM COM Drivers (`ascom/src/`, 3,756 lines)

**Supported Device Types (10/10 ASCOM types):**
| Device Type | Struct | Full API | Batch Status |
|---|---|---|---|
| Camera | `AscomCamera` | Yes | `CameraFullStatus`, `CameraThermalStatus`, `CameraSensorConfig`, `CameraExposureSettings` |
| Telescope/Mount | `AscomMount` | Yes | `MountFullStatus`, `MountPositionStatus`, `MountMotionStatus`, `MountGuideRates`, `MountCapabilities` |
| Focuser | `AscomFocuser` | Yes | `FocuserFullStatus`, `FocuserCapabilities` |
| Filter Wheel | `AscomFilterWheel` | Yes | `FilterWheelFullStatus` |
| Rotator | `AscomRotator` | Yes | `RotatorFullStatus` |
| Dome | `AscomDome` | Yes | `DomeFullStatus` |
| Safety Monitor | `AscomSafetyMonitor` | Yes | `SafetyMonitorFullStatus` |
| Observing Conditions | `AscomObservingConditions` | Yes | `ObservingConditionsFullStatus`, `WeatherStatus`, `WindStatus`, `SkyStatus` |
| Switch | `AscomSwitch` | Yes | `SwitchFullStatus` |
| Cover Calibrator | `AscomCoverCalibrator` | Yes | `CoverCalibratorFullStatus` |

**Infrastructure Features:**
- `AscomDeviceConnection`: Generic COM IDispatch wrapper with connect/disconnect, property get/set, method invocation
- `AscomError`: 8 error variants (ComError, Timeout, NotConnected, PropertyNotAvailable, InvalidValue, AscomException, CommunicationError, ResourceError)
- `TimeoutConfig`: Configurable timeouts for property get (5s), set (10s), methods (30s), long ops (5min), connect (1min)
- `HealthMonitor`: Atomic health tracking with configurable max failures (default 3) and check intervals (30s)
- `AscomOperationGuard`: RAII guard that disconnects device if operation fails (panic-safe)
- `AscomCleanupGuard`: Generic RAII cleanup guard for connect sequences
- `AscomDisconnectable` trait for uniform disconnect interface
- Registry discovery scanning both `HKEY_LOCAL_MACHINE\SOFTWARE\ASCOM` and `WOW6432Node` (32-bit on 64-bit)
- `probe_device_name()`: Non-invasive device name probing without connecting
- SAFEARRAY extraction for i32 and string arrays (handles 1D/2D, VT_I4/VT_I2/VT_UI2/VT_R8/VT_VARIANT/VT_BSTR)
- Size validation: max 150M elements (~600MB) for image arrays, max 15K pixels per dimension

### 2. INDI Protocol (`indi/src/`, 8,476 lines)

**Supported Device Types (10/10):**
| Device Type | Module | Support Level |
|---|---|---|
| Camera | `camera.rs` (539 lines) | Full -- exposure, binning, ROI, cooler, gain, offset, BLOB transfer, frame types |
| Mount | `mount.rs` (354 lines) | Full -- slew, sync, park/unpark, tracking, motion N/S/E/W, horizontal coords, slew rate |
| Focuser | `focuser.rs` (272 lines) | Full -- absolute/relative moves, halt, temperature, position |
| Filter Wheel | `filterwheel.rs` (188 lines) | Full -- position control, naming |
| Rotator | `rotator.rs` (175 lines) | Full -- angle control |
| Dome | `dome.rs` (467 lines) | Full -- slew, park, shutter control |
| Safety Monitor | `safetymonitor.rs` (281 lines) | Full |
| Cover Calibrator | `covercalibrator.rs` (510 lines) | Partial -- no halt support |
| Weather | `weather.rs` (381 lines) | Full |
| Switch | `switch_device.rs` (219 lines) | Full |

**Infrastructure Features:**
- `IndiClient` (2,756 lines): Full XML protocol client with async TCP, quick-xml parsing
- Protocol version negotiation (1.7, 1.8, 1.9)
- Reader task supervision with automatic reconnection using exponential backoff + jitter
- BLOB format validation and detection (CCD1/CCD2 elements)
- Property min/max extraction for number elements
- Permission checking before property writes
- Configurable timeouts: 14 different timeout parameters in `IndiTimeoutConfig`
- `IndiAutofocus` (1,190 lines): Full autofocus implementation
- `IndiError`: 14 error variants with detailed context (ConnectionFailed, ConnectionTimeout, OperationTimeout, MessageParseTimeout, BlobTimeout, PropertyTimeout, ParseError, PropertyNotFound, PermissionDenied, DeviceAlert, ProtocolError, ReaderDied, ChannelClosed, NotConnected, BlobFormatError, ValueOutOfRange, VersionMismatch, ReconnectionFailed)
- mDNS discovery, localhost discovery, common host scanning, server probing

### 3. Alpaca HTTP Protocol (`alpaca/src/`, 6,548 lines)

**Supported Device Types (10/10):**
| Device Type | Module | Lines |
|---|---|---|
| Camera | `camera.rs` | 937 |
| Telescope | `telescope.rs` | 972 |
| Focuser | `focuser.rs` | 323 |
| Filter Wheel | `filterwheel.rs` | 254 |
| Rotator | `rotator.rs` | 287 |
| Dome | `dome.rs` | 421 |
| Safety Monitor | `safetymonitor.rs` | 385 |
| Observing Conditions | `observingconditions.rs` | 150 |
| Switch | `switch.rs` | 136 |
| Cover Calibrator | `covercalibrator.rs` | 340 |

**Infrastructure Features:**
- `AlpacaClient` (1,341 lines): reqwest-based HTTP client with proper error handling
- `AlpacaError`: 9 error variants (Timeout, ConnectionRefused, HttpError, DeviceError, ParseError, NotConnected, OperationFailed, RequestFailed, UnsupportedApiVersion, ValidationFailed, RetryExhausted)
- `is_retryable()` on errors: retries on timeouts, connection refused, 5xx, 429
- `TimeoutConfig`: Per-operation-type timeouts with presets for camera, telescope, dome
- UDP broadcast discovery with configurable `DiscoveryConfig` (quick/default/thorough profiles)
- Server ping with latency measurement
- Management API: `get_configured_devices`, `get_server_description`, `get_api_versions`
- Atomic client/transaction ID tracking
- `AlpacaCameraGuard` / `AlpacaTelescopeGuard`: RAII guards for Alpaca device connections
- Parallel device fetch from multiple servers

### 4. Vendor SDKs (`native/src/`, 17,534+ lines)

**Camera Vendors (9 vendors):**
| Vendor | Module | Lines | Platform |
|---|---|---|---|
| ZWO ASI | `zwo.rs` | 2,572 | All |
| QHY | `qhy.rs` | 1,883 | All |
| Player One | `player_one.rs` | 1,218 | All |
| SVBony | `svbony.rs` | 1,279 | All |
| Atik | `atik.rs` | 1,252 | All |
| FLI | `fli.rs` | 1,611 | All |
| Touptek | `touptek.rs` | 1,316 | All |
| Moravian | `moravian.rs` | 1,198 | All |
| Fujifilm | `fujifilm.rs` | 2,556 | Windows only |

**Mount Vendors (3 vendors):**
| Vendor | Module | Lines | Protocol |
|---|---|---|---|
| Sky-Watcher | `skywatcher.rs` | 798 | SynScan serial/UDP |
| iOptron | `ioptron.rs` | 780 | iOptron serial |
| LX200 | `lx200.rs` | 1,051 | LX200 serial (Meade/Celestron) |

**Common Traits (well-defined interfaces):**
- `NativeDevice`: id, name, vendor, is_connected, connect, disconnect
- `NativeCamera`: capabilities, status, exposure control, cooling, gain/offset, binning, subframe, readout modes, vendor features, gain/offset ranges
- `NativeMount`: slew, sync, park/unpark, pulse guide, abort, tracking, tracking rate, side of pier, alt/az, sidereal time
- `NativeFocuser`: move_to, move_relative, position, is_moving, halt, temperature, max_position, step_size
- `NativeFilterWheel`: move_to_position, get_position, is_moving, filter_count, filter_names, set_filter_name
- `NativeRotator`: move_to, position, mechanical_position, is_moving, halt, reverse
- `NativeDome`: slew_to_azimuth, shutter control, slewing, abort, park, home, slave mode, altitude
- `NativeWeather`: temperature, humidity, pressure, dew point, wind, cloud cover, sky quality, sky brightness, rain rate, is_safe
- `NativeSafetyMonitor`: is_safe

**Thread Safety:**
- Per-vendor `tokio::sync::Mutex` for all SDK operations (9 vendor mutexes in `sync.rs`)
- `OnceLock` for lazy initialization of mutex instances
- SDK libraries loaded via `libloading::Library` (safe dynamic loading)

**Quirks Database (`quirks/`):**
- Centralized registry of known device bugs and workarounds
- Temperature quirks: ScaleFactor, Offset, Inverted, SkipFirstRead, RequiresDelayMs
- Timing quirks: DelayAfterOperation, DelayAfterConnect, DelayAfterDisconnect, DelayBetweenCommands
- Discovery quirks: SkipOperation, SkipOperations
- Runtime override support for testing
- Quirk disable/enable per-device

**Timeout Configuration:**
- `NativeTimeoutConfig`: 7 configurable timeouts (exposure poll, image download, connect, property, focuser move, filterwheel move, poll interval)
- Factory methods: `for_exposure()`, `strict()`, `lenient()`
- `calculate_exposure_timeout()` helper with 60s margin

### 5. Bridge Device Layer (`bridge/src/`, 12,124 lines)

- `devices.rs` (8,854 lines): Unified dispatch across all driver types (ASCOM, INDI, Alpaca, Native)
- `device_capabilities.rs` (1,729 lines): Device capability queries
- `device_id.rs` (968 lines): Structured device ID parsing with LRU cache (64 entries, hit/miss/eviction metrics)
- `device_guard.rs` (573 lines): RAII guards for Alpaca connections
- `AscomMountWrapper`: Dedicated STA thread with mpsc command channel for COM thread affinity

---

## Implementation Quality

### Strengths

1. **Complete ASCOM Coverage**: All 10 ASCOM device types are implemented with full property access, batch status queries, health monitoring, and RAII cleanup guards. This matches the coverage of commercial software like NINA.

2. **Robust Error Handling**: Each driver layer has its own detailed error types with rich context (device names, durations, operation names, last state). No silent fallbacks -- errors propagate with full diagnostic information.

3. **Timeout Architecture**: Every driver layer has configurable timeouts with sensible defaults. The `NativeTimeoutConfig` provides factory methods for different use cases (strict for fast hardware, lenient for slow USB 2.0). INDI has 14 separate timeout parameters. ASCOM has per-operation-type timeouts.

4. **Thread Safety**: Per-vendor mutexes for native SDKs prevent concurrent access to non-thread-safe vendor libraries. The ASCOM wrapper uses a dedicated STA thread with async command channels to solve COM apartment threading requirements.

5. **RAII Guards**: `AscomOperationGuard`, `AscomCleanupGuard`, `AlpacaCameraGuard`, `CleanupGuard` -- all ensure resources are released even on panics or early returns.

6. **SAFEARRAY Handling**: Thorough bounds validation, integer overflow protection, support for multiple element types (VT_I4, VT_I2, VT_UI2, VT_R8, VT_VARIANT, VT_BSTR), and null pointer checks.

7. **Reconnection Logic**: INDI client has exponential backoff with jitter for reconnection, reader task supervision, and configurable max attempts.

8. **Device ID System**: Structured parsing with LRU cache and hit rate metrics. Supports all 4 driver types (ASCOM, Alpaca, INDI, Native) with varied ID formats.

9. **Quirks Database**: Centralized workaround registry with vendor-wide and device-specific quirks, runtime override support, and automatic temperature correction.

10. **Discovery**: All three protocol layers (ASCOM, INDI, Alpaca) have proper discovery. ASCOM scans registry (including WOW6432Node). INDI supports mDNS, localhost, common hosts. Alpaca uses UDP broadcast with configurable profiles.

### Weaknesses

1. **ASCOM Dome at_park/slewing Bug** (Minor): `AscomDome::at_park()` (line 2925) and `AscomDome::slewing()` (line 2932) use `get_int_property()` instead of `get_bool_property()`. The ASCOM standard defines these as Boolean properties. While the `!= 0` conversion works for most drivers, some drivers may return VT_BOOL which would fail `variant_to_i32()`. The `AscomMount` correctly uses `get_bool_property()` for the same properties (lines 2252, 2256).

2. **INDI Camera Default Max Binning Fallback** (Minor): `IndiCamera::get_max_bin_x/y()` at `camera.rs:281-293` uses `.or(Some(4.0))` as a fallback when the driver doesn't report max binning. This hardcoded default of 4 may be incorrect for some cameras.

3. **INDI Camera capture_image Block-in-Place** (Minor): `IndiCamera::capture_image_with_timeout()` at `camera.rs:447-451` uses `tokio::task::block_in_place` + `block_on` to read the timeout config. This blocks the current thread in a tokio context. While it works, it's not ideal.

---

## Bugs Found

### BUG-D01: AscomDome at_park() uses get_int_property instead of get_bool_property
- **File**: `native/nightshade_native/ascom/src/windows_impl.rs:2925-2929`
- **Severity**: Medium
- **Impact**: ASCOM standard defines `AtPark` as a Boolean property. Some drivers return `VT_BOOL` which `variant_to_i32()` does not handle (line 611-627 only handles VT_I4, VT_I2, VT_UI2, VT_R8). This would cause `get_int_property` to return an error like "Property AtPark is not an int (VARIANT type=11)".
- **Fix**: Change `self.device.get_int_property("AtPark")` to `self.device.get_bool_property("AtPark")`.
- **Same issue**: `slewing()` at line 2932-2934.

### BUG-D02: AscomDome slewing() uses get_int_property instead of get_bool_property
- **File**: `native/nightshade_native/ascom/src/windows_impl.rs:2932-2935`
- **Severity**: Medium
- **Impact**: Same as BUG-D01 -- `Slewing` is a Boolean property in the ASCOM Dome interface.
- **Fix**: Change `self.device.get_int_property("Slewing")` to `self.device.get_bool_property("Slewing")`.

### BUG-D03: INDI Camera hardcoded max binning fallback
- **File**: `native/nightshade_native/indi/src/camera.rs:281-293`
- **Severity**: Low
- **Impact**: When `CCD_MAX_BIN_X/Y` is not reported by the driver, falls back to 4. Some cameras only support 1x1 or 2x2 binning. Setting 4x4 on such cameras would fail at the hardware level.
- **Note**: The comment says "Default max if not available" but a safer approach would be to query `CCD_BINNING` number property limits (min/max) via `get_number_limits`.

---

## Missing Pieces

### Minor Gaps (not blocking)

1. **INDI Cover Calibrator Halt**: Documented as unsupported in `lib.rs:17`. The `covercalibrator.rs` has no halt command. Low priority since cover calibrators are uncommon and halt is rarely needed.

2. **INDI BLOB Streaming**: Not implemented. Standard BLOB transfers work fine for single exposures. Streaming would only be needed for video mode which isn't a core use case for astrophotography.

3. **ASCOM Camera `ElectronsPerADU`/`FullWellCapacity`**: Not exposed through `AscomCamera`. These are optional but useful for noise analysis and flat calibration.

4. **ASCOM Camera `GainMin/GainMax`**: Not exposed. Currently the bridge queries gain range separately, but having it on the ASCOM camera struct would be cleaner.

5. **ASCOM `SetupDialog`**: Only implemented on `AscomCamera` (line 1825). Other device types (mount, focuser, etc.) could also benefit from setup dialog access.

6. **Alpaca Switch Coverage**: `switch.rs` is only 136 lines, suggesting minimal implementation compared to the full ASCOM Switch interface.

7. **No Automated Integration Tests**: The INDI module has good unit tests for error types, timeout configs, and device creation. But there are no integration tests against simulator devices (e.g., INDI CCD/Telescope Simulators).

---

## Recommendations

### Priority 1: Fix Dome Boolean Properties
Fix `AscomDome::at_park()` and `AscomDome::slewing()` to use `get_bool_property()` instead of `get_int_property()`. This is a real bug that will cause failures with some ASCOM dome drivers.

### Priority 2: Remove Hardcoded INDI Max Binning
Replace the `Some(4.0)` fallback in `get_max_bin_x/y()` with proper limit querying from the INDI number property's min/max attributes, or return `None` when the information is genuinely unavailable and let the caller handle it.

### Priority 3: Expand Alpaca Switch Coverage
The `switch.rs` module (136 lines) is thin compared to the ASCOM switch implementation (368 lines). Consider adding `GetSwitchName`, `GetSwitchDescription`, `CanWrite`, `MinSwitchValue`, `MaxSwitchValue`, `SetSwitchValue` if not already present.

### Priority 4: Add ASCOM Camera Extended Properties
Expose `ElectronsPerADU`, `FullWellCapacity`, `GainMin`, `GainMax`, `OffsetMin`, `OffsetMax` properties. These are valuable for the imaging pipeline's noise estimation and flat calibration.

### Priority 5: Integration Test Suite
Add integration tests using INDI/Alpaca simulator devices. The INDI simulator comes standard with any INDI server installation and would validate the full connect-expose-download pipeline.

---

## Architecture Assessment

The device driver layer is one of the strongest parts of the Nightshade codebase. Key architectural strengths:

- **Protocol Agnosticism**: All 4 driver types (ASCOM, INDI, Alpaca, Native) present the same interface through the bridge's `NativeDevice`/`NativeCamera`/`NativeMount` traits. The Dart side never needs to know which protocol is being used.

- **Layered Error Handling**: Each layer (ASCOM COM -> Bridge -> Dart) has its own error types with progressive enrichment. COM HRESULTs become `AscomError`s, which become `NightshadeError`s with device context.

- **Vendor Isolation**: Per-vendor mutexes prevent cross-contamination between SDK libraries. The `OnceLock<Mutex<()>>` pattern is clean and efficient.

- **12 Vendor SDK Integrations**: This is comparable to NINA's vendor support (NINA has ~14 camera vendors). The trait-based abstraction makes adding new vendors straightforward.

The 2 bugs found (BUG-D01, BUG-D02) are minor and unlikely to manifest in practice since most ASCOM dome drivers return compatible types. The overall code quality is high with consistent patterns, comprehensive error handling, and well-documented public APIs.
