# Hardware Compatibility & Production Readiness Audit

**Date:** 2026-02-05
**Scope:** All device categories, all driver layers (Native SDK, ASCOM, INDI, Alpaca), all target platforms
**Purpose:** Pre-commercial-distribution audit of device connectivity and communication

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Native Camera SDK Audit](#3-native-camera-sdk-audit)
4. [Native Mount Protocol Audit](#4-native-mount-protocol-audit)
5. [ASCOM COM Audit](#5-ascom-com-audit)
6. [INDI Protocol Audit](#6-indi-protocol-audit)
7. [ASCOM Alpaca Audit](#7-ascom-alpaca-audit)
8. [Dart Device Handling Audit](#8-dart-device-handling-audit)
9. [Gap Analysis](#9-gap-analysis)
10. [Licensing & Redistribution](#10-licensing--redistribution)
11. [Platform Support Matrix](#11-platform-support-matrix)
12. [Competitor Comparison](#12-competitor-comparison)
13. [Recommended Actions](#13-recommended-actions)

---

## 1. Executive Summary

Nightshade 2.0's device driver architecture is comprehensive and production-capable, supporting **9 camera vendors**, **3 native mount protocols**, and **4 driver layers** (Native SDK, ASCOM COM, INDI, Alpaca). The system covers all 11 device types: Camera, Mount, Focuser, FilterWheel, Guider, Dome, Rotator, Weather, SafetyMonitor, Switch, and CoverCalibrator.

### Key Strengths

- **8 native camera vendor SDKs** (more than NINA's 5 native drivers)
- **Comprehensive quirks database** -- more sophisticated than any competitor
- **Cross-platform architecture** -- Windows, macOS, Linux, iOS, Android
- **Unified trait-based device abstraction** -- all protocols expose the same interface
- **Production-quality error handling** -- structured errors with categories, recoverability flags, and reconnection hints
- **Thread-safe SDK access** -- per-vendor mutexes protect non-thread-safe SDKs
- **Timeout protection** on all operations with configurable presets (strict/lenient/for_exposure)

### Critical Gaps (P1)

| Gap | Impact |
|-----|--------|
| No Canon/Nikon DSLR native support | Excludes the largest DSLR astrophotography segment |
| No native focuser SDK implementations | ZWO EAF shares existing SDK infrastructure but isn't wired up |
| No native filter wheel SDK implementations | ZWO EFW and QHY CFW share existing SDK infrastructure |
| ZWO SDK lacks macOS ARM64 support | Blocker for native Apple Silicon builds |

### Important Gaps (P2)

| Gap | Impact |
|-----|--------|
| Missing Celestron native mount protocol | Second-most popular mount brand has no native driver |
| Incomplete ASCOM capability queries | `get_ascom_capabilities` only handles Camera/Mount/Focuser/FilterWheel |
| INDI missing Weather and Switch device types | Must fall back to Alpaca on Linux/macOS for these |
| QHY SDK stability concerns | Discovery crashes, image corruption, memory leaks |

---

## 2. Architecture Overview

### Rust Native Layer (`native/nightshade_native/`)

```
native/nightshade_native/
  bridge/      -- FFI entry point (cdylib + staticlib), event bus, device manager
  native/      -- Vendor SDK FFI bindings (9 camera vendors, 3 mount protocols)
  ascom/       -- Windows COM ASCOM drivers (10 device types)
  indi/        -- Linux/macOS INDI protocol (8 of 10 device types)
  alpaca/      -- Cross-platform ASCOM Alpaca HTTP (10 device types)
  sequencer/   -- Behavior tree automation engine
  imaging/     -- Image processing (LibRaw FFI, FITS, XISF)
```

### Device Abstraction

All vendor SDKs and protocols implement unified traits:

- `NativeDevice` -- base trait (id, name, vendor, is_connected)
- `NativeCamera` -- exposure, image download, temperature, cooler
- `NativeMount` -- slew, sync, tracking, park
- `NativeFocuser` -- position control, temperature
- `NativeFilterWheel` -- position control, slot naming
- `NativeRotator` -- angle control
- `NativeDome` -- slew, park, shutter
- `NativeWeather` -- weather monitoring
- `NativeSafetyMonitor` -- safety state

### Dart/Flutter Layer

- `NightshadeBackend` abstraction: `FfiBackend` (local), `NetworkBackend` (remote), `DisconnectedBackend`
- Riverpod `StateNotifier` per device type with retry logic and `mounted` guards
- `DeviceService` (2,292 lines): auto-reconnection, heartbeat monitoring, temperature polling, event processing
- Structured error handling: `NightshadeError` with 12 `BackendErrorCategory` values, `DeviceError` with 9 types

### Event Pipeline

```
Rust (tokio broadcast channel)
  -> FRB apiEventStream()
  -> DeviceService._handleEquipmentEvent()
  -> StateNotifier updates
  -> UI rebuild via Riverpod
```

---

## 3. Native Camera SDK Audit

### 3.1 ZWO ASI

| Attribute | Status |
|-----------|--------|
| **File** | `vendor/zwo.rs` (~27,738 lines) |
| **Devices** | Cameras (ASICamera2.dll), Focusers (EAF_focuser.dll), Filter Wheels (EFW_filter.dll) |
| **Implementation** | FULL -- complete with timeout handling, per-SDK mutexes |
| **Latest SDK** | V1.41 (Jan 2026) |
| **License** | MIT-like, free redistribution |
| **VC++ Runtime** | Not required |
| **macOS ARM64** | **NOT SUPPORTED** -- fat binary has i386+x86_64 only |
| **Linux ARM** | Supported (x86_64, RPi) |

**Known Issues:**
- `ASI_ERROR_TIMEOUT` on Raspberry Pi 4 with `ASIGetVideoData()` after initially successful captures
- Sporadic image distortion reported with ASI2600MC Pro in some software
- **macOS ARM64 is a blocker** -- must run under Rosetta 2 on M-series Macs

**Nightshade-Specific Notes:**
- ZWO module also implements EAF focuser and EFW filter wheel via the same SDK
- The focuser and filter wheel implementations exist in `zwo.rs` but are only exposed via native camera discovery, not as standalone native focuser/filter wheel devices (see Gap 5.2/5.3)

### 3.2 QHY

| Attribute | Status |
|-----------|--------|
| **File** | `vendor/qhy.rs` (~14,000+ lines) |
| **Devices** | Cameras, Filter Wheels (CFW via camera SDK) |
| **Implementation** | FULL with safety measures |
| **Latest SDK** | 20241227 (stable) |
| **License** | Commercial -- contact QHY for redistribution terms |
| **Stability** | **POOR-FAIR** -- most problematic SDK |

**Known Issues (CRITICAL for production):**
- `ScanQHYCCD()` can crash, especially with other USB devices. Nightshade wraps discovery in `catch_unwind`.
- ~1 in 10 images appear "scrambled like a mosaic" (reported in NINA 2025)
- Camera detection flicker: appears/disappears from detection list
- Linux `indi_qhy_ccd` crashes every few seconds
- USB driver version coupling: SDK 21.3.13.17+ requires USB driver >= 21.2.20
- 32-bit DLL prepends underscores to exported symbols

**Nightshade Mitigations Already Implemented:**
- `catch_unwind` crash protection for discovery
- Discovery can be globally disabled
- Configurable discovery timeout (default 10 seconds)
- Mutex serialization for all discovery calls

### 3.3 PlayerOne

| Attribute | Status |
|-----------|--------|
| **File** | `vendor/player_one.rs` (~14,000+ lines) |
| **Devices** | Cameras only (POA SDK) |
| **Implementation** | FULL |
| **License** | Unknown -- contact PlayerOne |
| **Stability** | Fair-Good |

**Known Issues:**
- Intermittent exposure start failures (NINA implements automatic retry)
- SDK is relatively young compared to ZWO/QHY

### 3.4 SVBony

| Attribute | Status |
|-----------|--------|
| **File** | `vendor/svbony.rs` (~10,000+ lines) |
| **Devices** | Cameras only |
| **Implementation** | FULL |
| **License** | Unknown -- contact SVBony |
| **Stability** | Fair |

**Known Issues:**
- SDK is **nearly identical to ZWO ASI SDK** (find-and-replace "ASI" with "SVB")
- SDK updates can break older camera support (SV305 broken in SharpCap 4.0)
- Camera keeps images in buffer causing errors with polar alignment tools
- Limited developer support channels

### 3.5 Atik (Artemis)

| Attribute | Status |
|-----------|--------|
| **File** | `vendor/atik.rs` (~5,000+ lines) |
| **Devices** | Cameras only (ArtemisSDK) |
| **Implementation** | FULL |
| **Latest SDK** | DLL v2024.11.26.2038 |
| **License** | Unknown -- free download, widely redistributed |
| **VC++ Runtime** | Yes (prerequisite installer included) |

**Known Issues:**
- Apx60 blank frames in Fast-Mode at max framerate on Linux/macOS (fixed in recent SDK)
- "Invalid Handle" errors in certain integration scenarios
- Now part of Moravian Instruments (acquired 2020)

### 3.6 FLI (Finger Lakes Instrumentation)

| Attribute | Status |
|-----------|--------|
| **File** | `vendor/fli.rs` (~5,000+ lines) |
| **Devices** | Cameras, Focusers, Filter Wheels (via libfli) |
| **Implementation** | FULL |
| **License** | **BSD -- freely redistributable** |
| **Stability** | Good (mature, stable, rarely updated) |

**Notes:**
- Truly open-source SDK -- easiest licensing for commercial redistribution
- Linux requires `fliusb` kernel module (may need manual compilation for newer kernels)
- Niche/professional brand with limited community support

### 3.7 Touptek/OGMA

| Attribute | Status |
|-----------|--------|
| **File** | `vendor/touptek.rs` (~8,000+ lines) |
| **Devices** | Cameras only (ogmacam.dll) |
| **Implementation** | FULL |
| **License** | Unknown -- contact ToupTek |
| **Stability** | Good |

**White-Label Brands (CRITICAL):**

Touptek is the OEM for numerous brands, each requiring a **separate branded DLL**:

| Brand | DLL Name |
|-------|----------|
| ToupTek | toupcam.dll |
| OGMA | ogmacam.dll |
| Altair Astro | altaircam.dll |
| Mallincam | mallincam.dll |
| RisingCam | toupcam or branded |
| Omegon | branded variant |
| Meade (DSI) | branded variant |
| Explore Scientific | branded variant |
| Lacerta | branded variant |

The APIs are **95% identical** across all brands -- same function signatures, different prefixes and DLL names. However, cameras identify to their brand-specific SDK, so **multiple DLLs must be shipped** to support all brands.

**Nightshade currently only ships ogmacam.dll** -- users with Altair, Mallincam, etc. cameras won't be detected.

### 3.8 Moravian Instruments

| Attribute | Status |
|-----------|--------|
| **File** | `vendor/moravian.rs` (~5,000+ lines) |
| **Devices** | Cameras only (gXusb SDK) |
| **Implementation** | FULL |
| **License** | BSD-like (copyright notice required, no endorsement) |
| **macOS ARM64** | **YES -- universal binary with Intel + Apple Silicon** |
| **Stability** | Excellent |

**Notes:**
- Best cross-platform support of all vendors, including Apple Silicon ARM64
- Two SDK families: gxusb.dll for G-series CCD, cxusb.dll for C-series CMOS

### 3.9 Fujifilm

| Attribute | Status |
|-----------|--------|
| **File** | `vendor/fujifilm.rs` (~6,000+ lines) |
| **Devices** | Cameras only (X Acquire SDK -- XAPI.dll) |
| **Implementation** | PARTIAL -- Windows-only |
| **License** | Proprietary EULA with redistribution in object code |
| **Latest SDK** | V1.34 (Nov 2025) |

**Critical Licensing Issue:**
- Using the SDK to control a Fujifilm camera **voids the camera's warranty**
- This MUST be disclosed to users in the application
- Fujifilm may terminate the license agreement without notice for breach

**Known Quirks (already handled in Nightshade):**
- Requires DR=100 before querying ISO
- Requires 100ms delays between operations
- Model-specific DLLs (FF0000API.dll through FF0020API.dll)

---

## 4. Native Mount Protocol Audit

### 4.1 Sky-Watcher (SynScan Protocol)

| Attribute | Status |
|-----------|--------|
| **File** | `vendor/skywatcher.rs` (~5,000+ lines) |
| **Protocol** | Motor Controller Command Set + SynScan HC Serial v3.3 |
| **Connection** | Serial (9600/115200 baud) + UDP WiFi (192.168.4.1:11880) |
| **Implementation** | FULL |

**Protocol Details:**
- 24-bit encoder positions (2^24 steps/revolution)
- Little-endian hex ASCII encoding with 0x800000 offset
- Two protocol levels: direct motor controller (low-level) and SynScan HC (high-level)
- WiFi is transparent UDP-to-serial bridge (same commands)

**Mount Identification Codes:**

| Code | Mount |
|------|-------|
| 0x00 | EQ6/Atlas/CG-5 |
| 0x01 | HEQ5/Sirius |
| 0x02 | EQ5 |
| 0x04 | EQ8 |
| 0x05 | AZ-EQ6/AZ-EQ5 |
| 0x23 | EQ6-R |
| 0x80 | 80GT |
| 0x90 | DOB |

**Known Firmware Issues:**
- AZ-GTi WiFi reliability on pre-Dec-2025 units
- Motor controller firmware v2.xx and v3.xx are not cross-compatible (wrong firmware bricks controller)
- Always query `GridPerRevolution` at connection (firmware updates can change resolution)

**Pulse Guide:**
- Guide rate: 0.1x-0.9x sidereal, configurable per axis
- Minimum pulse width limited by serial communication latency
- Backlash compensation in microsteps per axis

### 4.2 iOptron

| Attribute | Status |
|-----------|--------|
| **File** | `vendor/ioptron.rs` (~5,000+ lines) |
| **Protocol** | RS-232 Command Language v3.10 |
| **Connection** | Serial (115200 baud modern, 9600 legacy) |
| **Implementation** | FULL |

**Mount Identification (`:MountInfo#`):**

| Response | Mount |
|----------|-------|
| 0026 | CEM26 |
| 0028 | GEM28 |
| 0040 | CEM40(G) |
| 0043 | GEM45(G) |
| 0070 | CEM70(G) |
| 0120 | CEM120 |

**Known Firmware Issues:**
- CEM40 firmware crashes and bricking during upgrades
- CEM40EC/GEM45EC encoder calibration required after firmware upgrade
- CEM70 firmware update failures leaving mount unresponsive
- Firmware 210105+ required for modern ASCOM/INDI driver support
- PHD2 calibration showing no RA movement after certain firmware updates

**Superseded Commands:** Use `:GLS#` instead of `:GAS#` for GPS, `:GUT#` instead of `:GLT#` for time.

### 4.3 LX200 Protocol

| Attribute | Status |
|-----------|--------|
| **File** | `vendor/lx200.rs` (~5,000+ lines) |
| **Protocol** | Standard LX200 + OnStep + 10Micron + Losmandy extensions |
| **Connection** | Serial (9600-115200 baud) |
| **Implementation** | FULL (supports Meade and OnStep variants) |

**Compatible Mounts:**
- Meade LX200, LX600, LX850
- OnStep-based (Pegasus NYX-101, DIY builds)
- Losmandy Gemini (LX200 mode)
- 10Micron GM series
- Astro-Physics GTO series

**Known Incompatibilities Between Variants:**

| Feature | Issue |
|---------|-------|
| Slew rate | 10Micron uses `:RSn#` with parameter; standard uses `:RS#` alone |
| Precision modes | Different response formats: `HH:MM.T#` vs `HH:MM:SS#` vs `HH:MM:SS.SS#` |
| Sync semantics | `:CM#` means different things per vendor |
| Guide commands | No standard pulse guide in original LX200 |
| Park | Not in original spec; each vendor adds own commands |
| Tracking rates | Command letters differ between Meade, AP, OnStep, 10Micron |

---

## 5. ASCOM COM Audit

**File:** `ascom/src/windows_impl.rs`
**Platform:** Windows only
**Implementation:** FULL -- 10 of 10 device types

### Supported Device Types (All 10)

Camera, Telescope, Focuser, FilterWheel, Rotator, Dome, SafetyMonitor, ObservingConditions, Switch, CoverCalibrator

### Implementation Details

- Registry-based device discovery via ProgID
- Dynamic COM object instantiation via `CLSIDFromProgID` + `CoCreateInstance`
- `IDispatch` property/method access with comprehensive HRESULT handling
- `COINIT_APARTMENTTHREADED` (STA) threading model
- Operation timeouts to prevent hangs

### Error Handling

`AscomError` enum with 8 variants: `ComError`, `Timeout`, `NotConnected`, `PropertyNotAvailable`, `InvalidValue`, `AscomException` (with code/source/description), `CommunicationError`, `ResourceError`

### Timeout Configuration

```
TimeoutConfig {
  property_get_ms,
  property_set_ms,
  method_call_ms,
  long_operation_ms
}
```

### Known Issue: Incomplete Capability Queries

**`get_ascom_capabilities`** (in `device_capabilities.rs`) only handles 4 of 10 device types:
- Camera
- Mount (Telescope)
- Focuser
- FilterWheel

**Missing:** Rotator, Dome, SafetyMonitor, ObservingConditions, Switch, CoverCalibrator. These fall through to an error. The ASCOM lib already has the wrapper structs (`AscomRotator`, `AscomDome`, etc.) -- they just need capability mapping.

### Known Problematic ASCOM Drivers (from field reports)

| Driver | Issues |
|--------|--------|
| Celestron CPWI V6 | Crash on unpark, crash on time sync |
| Celestron NexStar+ HC | Can halt all external RS232 control |
| Meade LX200 Classic | Serial timeout, unreliable end-of-slew detection, runaway slewing |
| Meade Generic v1.3.9.482 | Intermittent connection failures |
| ZWO ASI ASCOM | Camera numbering instability in multi-camera setups |
| QHY ASCOM | Cooling control failure (works via native driver) |

### COM Threading Considerations

- Most ASCOM drivers use STA -- COM serializes all calls through a message pump
- MTA drivers must handle all thread synchronization internally
- Client applications calling from multiple threads must marshal to the STA thread
- Nightshade's current implementation uses `COINIT_APARTMENTTHREADED` which is correct

---

## 6. INDI Protocol Audit

**File:** `indi/src/lib.rs` and related modules
**Platform:** Linux/macOS (cross-platform TCP)
**Protocol Version:** 1.7
**Implementation:** PARTIAL -- 8 of 10 device types

### Supported Device Types

| Type | Status |
|------|--------|
| Camera | FULL |
| Mount | FULL |
| Focuser | FULL |
| FilterWheel | FULL |
| Rotator | FULL |
| Dome | FULL |
| SafetyMonitor | FULL |
| CoverCalibrator | PARTIAL (no halt support) |
| **Weather** | **NOT IMPLEMENTED** |
| **Switch** | **NOT IMPLEMENTED** |

### Key Implementation Features

- XML protocol parsing via quick-xml 0.31
- Reader task supervision with automatic reconnection
- BLOB stream format validation and detection
- Property min/max extraction for number elements
- Permission checking before property writes
- Protocol version negotiation (1.7, 1.8, 1.9)
- Exponential backoff with jitter for reconnection
- Device autodiscovery via mDNS, localhost, common hosts

### INDI Standard Properties Coverage

The INDI protocol defines standard properties per device type. Key coverage areas:

- **Camera:** CCD_EXPOSURE, CCD_FRAME, CCD_BINNING, CCD_TEMPERATURE, CCD_GAIN, CCD_OFFSET, CCD_COOLER, CCD1 (BLOB)
- **Mount:** EQUATORIAL_EOD_COORD, ON_COORD_SET, TELESCOPE_TRACK_MODE/STATE, TELESCOPE_PARK, TELESCOPE_PIER_SIDE
- **Focuser:** ABS_FOCUS_POSITION, REL_FOCUS_POSITION, FOCUS_MAX, FOCUS_TEMPERATURE, FOCUS_BACKLASH
- **FilterWheel:** FILTER_SLOT, FILTER_NAME
- **Rotator:** ABS_ROTATOR_ANGLE, ROTATOR_REVERSE, ROTATOR_BACKLASH
- **Dome:** ABS_DOME_POSITION, DOME_SHUTTER, DOME_PARK, DOME_AUTOSYNC

### INDI BLOB Transfer

Three modes for image data: `Never` (default), `Also` (properties + BLOBs), `Only` (BLOBs only). Best practice is to use a separate connection for BLOB transfers to prevent blocking property updates.

### Missing: Weather Properties

INDI defines comprehensive weather properties: WEATHER_STATUS, WEATHER_TEMPERATURE, WEATHER_WIND_SPEED, WEATHER_HUMIDITY, WEATHER_PRESSURE, WEATHER_DEWPOINT, WEATHER_FORECAST, configurable OK/Warning/Alert thresholds.

These are NOT implemented in Nightshade's INDI client.

### Missing: Switch/Auxiliary Properties

INDI does not have a fixed "Switch" device type like ASCOM. Auxiliary devices create custom switch and number properties per driver. The power interface provides standardized power control properties.

---

## 7. ASCOM Alpaca Audit

**Directory:** `alpaca/src/`
**Platform:** Cross-platform (HTTP REST)
**API Version:** v1
**Implementation:** FULL -- 10 of 10 device types

### Supported Device Types (All 10)

Camera, Telescope, Focuser, FilterWheel, Rotator, Dome, ObservingConditions, SafetyMonitor, Switch, CoverCalibrator

### Discovery Protocol

- UDP broadcast on port 32227 (IANA-registered)
- Device responds with `{"AlpacaPort": n}` via unicast
- Management API: `/management/apiversions`, `/management/v1/description`, `/management/v1/configureddevices`
- Default Alpaca port: 11111

### ImageArray Transfer

Alpaca supports three transfer methods:

1. **JSON Array** (original, slow) -- nested arrays in JSON
2. **Base64 Handoff** (intermediate) -- metadata first, then data
3. **ImageBytes** (recommended, ~8x faster) -- binary with structured header, `Accept: application/imagebytes`

**Recommendation:** Verify Nightshade uses ImageBytes for camera image transfer (if not already).

### Error Response Format

```json
{
  "Value": <return_value>,
  "ClientTransactionID": 321,
  "ServerTransactionID": 1,
  "ErrorNumber": 0,
  "ErrorMessage": ""
}
```

Standard error codes: 0x400 (InvalidValue), 0x401 (ValueNotSet), 0x402 (NotConnected), 0x407 (InvalidWhileParked), 0x408 (InvalidWhileSlaved), 0x40B (ActionNotImplemented), 0x40C (NotImplemented).

### Known Alpaca Server Quirks

| Server | Quirk |
|--------|-------|
| ASCOM Remote | NINA/SGP can't auto-create dynamic drivers without Chooser |
| INDIGO Alpaca Bridge | `MoveAxis` unavailable, `HaltCover` is dummy, some features unmappable |
| TinyAlpacaServer | Limited to switch/cover/weather types |

---

## 8. Dart Device Handling Audit

### 8.1 Auto-Reconnection

```
Strategy:
  Exponential Backoff Delays: [5s, 10s, 20s]
  Maximum Attempts: 3
  Per-device tracking via _reconnectionAttempts map
  Timer management via _reconnectionTimers map
  Cancellation on disposal
```

Trigger: `Disconnected` event from Rust backend. Auto-reconnect is enabled by default (configurable per device). Critical devices (camera/mount) trigger sequence resume on successful reconnection.

### 8.2 Heartbeat Monitoring

- Started on connection for cameras and mounts (critical devices)
- 10-second interval polling
- Graceful degradation: missing heartbeat doesn't prevent device use
- Properly cleaned up on disconnect

### 8.3 Temperature Polling (Camera)

- Every 5 seconds
- Multiple field name extraction for compatibility (`temperature`, `ccdTemperature`, `sensorTemp`)
- Separate extractors for cooler power and target temperature
- Continues on error (catches and logs warnings)

### 8.4 Filter Wheel Position Verification

- Poll every 250ms after command
- 60-second timeout
- Detects "moving" state (position < 0)
- Automatic focus offset application after successful filter change
- Non-fatal: filter change succeeds even if offset fails

### 8.5 State Notifier Retry Logic

All 11 device types follow the same pattern:

```dart
connect(deviceId, {maxRetries: 3})
  -> _connectWithRetry(deviceId, maxRetries)
    -> if error.recoverable && retryAttempts < maxRetries:
         delay(_defaultRetryDelay * retryAttempts)
         _connectWithRetry(deviceId, maxRetries)
```

All methods include `if (!mounted) return;` guards to prevent updates after disposal.

### 8.6 Identified Concerns

1. **No hard operation timeouts** for focuserMoveTo, filterWheelSetPosition -- relies on backend heartbeat (optional)
2. **Filter name sync priority:** Profile names override hardware names; stale profiles may mislead
3. **Auto-reconnect enabled by default** -- UI doesn't clearly expose this setting
4. **No device locking during batch operations** -- connectProfile() parallelizes all connects
5. **Event stream overflow:** EventsDropped notification documented but UI should refresh state on notification

---

## 9. Gap Analysis

### P1 -- Critical Gaps

#### 9.1 No Canon/Nikon DSLR Native Support

NINA, APT, and KStars/EKOS all support Canon and Nikon DSLRs natively. Canon EOS is the most popular DSLR brand in astrophotography. ASCOM DSLR support is poor ("ASCOM was designed around dedicated cameras"). Native SDK control provides RAW file access, bulb mode, live view, and camera settings that ASCOM cannot.

Nightshade's LibRaw integration already handles RAW processing for 600+ camera models -- the image pipeline is ready.

**SDKs required:** Canon EDSDK, Nikon SDK

#### 9.2 No Native Focuser SDK Implementations

Nightshade defines `NativeFocuser` traits and ZWO EAF code exists in `zwo.rs`, but no standalone native focuser discovery/connection path is exposed. All focuser support relies on ASCOM/Alpaca/INDI.

**Quick wins:**
- ZWO EAF: Already in the codebase via ZWO SDK (EAF_focuser.dll)
- FLI focusers: Already in the codebase via libfli

#### 9.3 No Native Filter Wheel SDK Implementations

Same situation as focusers. ZWO EFW code exists in `zwo.rs` and QHY CFW support in `qhy.rs`, but neither is exposed as standalone native filter wheel devices.

**Quick wins:**
- ZWO EFW: Already in the codebase (EFW_filter.dll)
- QHY CFW: Already in the codebase via QHY SDK
- FLI CFW: Already in the codebase via libfli

#### 9.4 ZWO SDK macOS ARM64 Blocker

ZWO's SDK binary only includes i386+x86_64 architectures. No ARM64 slice for Apple Silicon. Must run under Rosetta 2 on M-series Macs. No roadmap from ZWO for ARM64 support.

**Mitigation:** Rosetta 2 works but adds overhead. Monitor ZWO SDK releases. Moravian is the only vendor with native ARM64 macOS support.

### P2 -- Important Gaps

#### 9.5 Missing Celestron Native Mount Protocol

`NativeVendor::Celestron` is defined in the enum but has no vendor implementation. Celestron is the second-most popular mount brand. The NexStar+/CPWI AUX protocol is well-documented. The existing LX200 driver partially works with some older Celestron mounts.

#### 9.6 Incomplete ASCOM Capability Queries

`get_ascom_capabilities` only handles Camera, Mount, Focuser, FilterWheel. Missing: Rotator, Dome, SafetyMonitor, ObservingConditions, Switch, CoverCalibrator. The wrapper types exist -- they just need capability struct mapping.

#### 9.7 INDI Missing Weather and Switch

Weather and Switch device types are not implemented in the INDI client. Users on Linux/macOS must use Alpaca bridges for weather stations and power switches. Weather is important for unattended observatory safety.

#### 9.8 QHY SDK Stability

QHY is the most stability-problematic SDK across all vendors. While Nightshade already has strong mitigations (catch_unwind, disableable discovery, timeouts, mutex serialization), production distribution means exposing these issues to a wider user base. Consider:
- Prominent documentation of known QHY issues
- Easy toggle to disable QHY native and fall back to ASCOM
- Crash telemetry for QHY-specific failures

### P3 -- Nice-to-Have

#### 9.9 No Pegasus Powerbox Native Integration

`NativeVendor::Pegasus` is defined but unimplemented. Pegasus Ultimate Powerbox is extremely popular and has a documented serial protocol (power switching, dew heater PWM, USB control, voltage monitoring, focuser control).

#### 9.10 Missing Touptek White-Label DLLs

Currently only `ogmacam.dll` is shipped. Cameras from Altair, Mallincam, RisingCam, Omegon, etc. won't be detected. Must ship multiple branded DLLs with identical APIs.

#### 9.11 No GPS/Location Integration

No GPS device type or location service. GPS provides sub-second UTC accuracy and automatic site coordinates for unattended observatories.

#### 9.12 Expose Quirks Database in UI

Nightshade's quirks database is more sophisticated than any competitor's. Exposing it in the UI as a "Device Compatibility" panel showing known quirks for connected devices would be a genuine differentiator.

---

## 10. Licensing & Redistribution

| Vendor | License | Redistribution | Action Required |
|--------|---------|----------------|-----------------|
| ZWO ASI | MIT-like | Free | None |
| QHY | Commercial | Likely OK | **Contact QHY for formal agreement** |
| PlayerOne | Unknown | Likely OK | **Contact PlayerOne for formal agreement** |
| SVBony | Unknown | Likely OK | **Contact SVBony for formal agreement** |
| Atik | Unknown (free DL) | Likely OK | **Contact Atik/Moravian** |
| FLI | **BSD** | Free (preserve copyright) | Include BSD notice |
| Touptek | Unknown | Likely OK | **Contact ToupTek for formal agreement** |
| Moravian | BSD-like | Yes (preserve copyright, no endorsement) | Include notice |
| Fujifilm | Proprietary EULA | Object code only | **Must disclose warranty voiding to users** |
| Canon EDSDK | Requires license | Requires agreement | **Apply for Canon EDSDK license** |
| Nikon SDK | Requires license | Requires agreement | **Apply for Nikon SDK license** |

**Recommended action before commercial distribution:** Contact QHY, PlayerOne, SVBony, and ToupTek to secure formal redistribution agreements. Include FLI BSD and Moravian copyright notices. Add Fujifilm warranty disclaimer.

---

## 11. Platform Support Matrix

### Native Camera SDKs

| Vendor | Windows | macOS Intel | macOS ARM64 | Linux x64 | Linux ARM |
|--------|---------|-------------|-------------|-----------|-----------|
| ZWO | Yes | Yes | **No** (Rosetta) | Yes | Yes |
| QHY | Yes | Yes | Unknown | Yes | Yes (ARMv8) |
| PlayerOne | Yes | Yes | Unknown | Yes | Yes |
| SVBony | Yes | Unknown | Unknown | Yes | Unknown |
| Atik | Yes | Yes | Unknown | Yes | Yes |
| FLI | Yes | Yes (via source) | Unknown | Yes | Via source |
| Touptek | Yes | Yes | Unknown | Yes | Yes |
| Moravian | Yes | Yes | **Yes** | Yes | Yes (ARMv6/7/8) |
| Fujifilm | Yes | **No** | **No** | **No** | **No** |

### Protocol Support

| Protocol | Windows | macOS | Linux |
|----------|---------|-------|-------|
| ASCOM COM | Yes | No | No |
| ASCOM Alpaca | Yes | Yes | Yes |
| INDI | Via network | Yes | Yes |
| Native SDKs | Yes | Partial | Yes |

---

## 12. Competitor Comparison

| Feature | NINA | SGP | APT | EKOS | Voyager | TheSkyX | **Nightshade** |
|---------|------|-----|-----|------|---------|---------|---------------|
| Native camera SDKs | 5 | 0 | ~10 | Via INDI | 0 | Via X2 | **8 + Fuji** |
| Canon/Nikon DSLR native | Yes | No | Yes | Via gPhoto2 | No | No | **No (GAP)** |
| Native mount protocols | Via ASCOM | Via ASCOM | Via ASCOM | Via INDI | Via ASCOM | Native Bisque | **3 protocols** |
| Native focuser SDKs | 0 | 0 | 0 | Via INDI | 0 | Via X2 | **0 (GAP)** |
| Quirks database | Implicit | None | None | Per-driver | None | None | **Comprehensive** |
| Cross-platform | Windows | Windows | Windows | Linux/Mac | Windows | Win/Mac | **All 5** |
| Mobile companion | 3rd party | None | None | StellarMate | Web | None | **Native app** |
| Weather integration | ASCOM OC | ASCOM OC | ASCOM | INDI | ASCOM + AI | ASCOM | **ASCOM/Alpaca/INDI + radar** |
| Dome control | Full | Full | Limited | Full | Full | Full | **Full** |
| Plugin system | MEF (.NET) | None | None | INDI drivers | None | X2 | **Plugin host** |

**Nightshade strengths:** Cross-platform, native mobile, comprehensive quirks database, 8 camera vendors, weather radar, modern Rust/Flutter architecture.

**Nightshade gaps:** Canon/Nikon DSLR, native focuser/filter wheel exposure, Celestron mount.

---

## 13. Recommended Actions

### Before Commercial Launch (P1)

| # | Action | Effort | Impact |
|---|--------|--------|--------|
| 1 | Expose ZWO EAF/EFW and QHY CFW/FLI as native focuser/filter wheel devices | Medium | Completes device abstraction for already-written code |
| 2 | Complete ASCOM capability queries for remaining 6 device types | Low | Prevents errors when connecting ASCOM rotators, domes, etc. |
| 3 | Add Fujifilm warranty disclaimer to UI | Low | Legal compliance |
| 4 | Contact QHY, PlayerOne, SVBony, ToupTek for redistribution agreements | Low | Legal compliance |
| 5 | Ship multiple Touptek-branded DLLs | Low | Unlocks Altair, Mallincam, RisingCam, Omegon camera support |
| 6 | Add INDI Weather device type support | Medium | Enables weather safety on Linux/macOS |
| 7 | Document ZWO macOS ARM64 limitation | Low | Sets user expectations |

### Post-Launch (P2)

| # | Action | Effort | Impact |
|---|--------|--------|--------|
| 8 | Add Canon EDSDK native camera support | High | Largest DSLR astrophotography segment |
| 9 | Add Nikon SDK native camera support | High | Second-largest DSLR segment |
| 10 | Implement Celestron AUX mount protocol | Medium | Second-most popular mount brand |
| 11 | Add INDI Switch device type | Low | Completes INDI device coverage |
| 12 | Add hard operation timeouts for focuser/filter moves | Low | Prevents indefinite waits |
| 13 | Implement device locking during batch profile connects | Low | Prevents race conditions |

### Future Differentiators (P3)

| # | Action | Effort | Impact |
|---|--------|--------|--------|
| 14 | Native Pegasus Powerbox serial protocol | Medium | Integrated power/dew/focuser control |
| 15 | Expose quirks database in UI | Low | Unique differentiator |
| 16 | GPS/location service | Low | Automatic site coordinates and time sync |
| 17 | Sony MTP camera support | Medium | Growing mirrorless segment |

---

## Appendix A: Test Recommendations

### SDK Loading Tests (No Hardware Required)
- Verify each SDK DLL can be loaded on each platform
- Verify all function pointers resolve correctly
- Run existing non-ignored tests regularly (ZWO, SVBony SDK status + discovery tests)

### Hardware Integration Tests (Requires Hardware)
- Connect/disconnect cycling with exponential backoff verification
- Pull device power mid-exposure (should trigger reconnection, pause sequence)
- Rapid disconnect/reconnect cycles
- Profile switch while devices connecting
- Mixed device availability (partial online)
- Filter wheel stuck detection (position verification timeout)
- Network latency with Alpaca devices
- Event stream saturation (EventsDropped handling)

### USB Hub and Cable Tests
- Powered hub with insufficient amps (camera lockup detection)
- FTDI vs Prolific vs CH340 serial adapters
- USB 3.0 hub EMI interference with GPS
- USB selective suspend disabled verification

### Cross-Protocol Tests
- Same device type via ASCOM, Alpaca, and INDI (verify behavior parity)
- Alpaca ImageBytes transfer verification
- INDI BLOB transfer performance
- ASCOM COM apartment threading under multi-device load

---

## Appendix B: Reference Links

### SDK Downloads
- [ZWO SDK](https://www.zwoastro.com/layouts/download-others/)
- [QHY SDK](https://www.qhyccd.com/developer/)
- [PlayerOne SDK](https://player-one-astronomy.com/service/software/)
- [SVBony SDK](https://www.svbony.com/pages/support-software-driver/)
- [Atik SDK](https://www.atik-cameras.com/software-downloads/)
- [FLI libfli](https://github.com/SAIL-Labs/FLI-linux)
- [ToupTek SDK](https://www.touptekphotonics.com/download/?category=SDK)
- [Moravian SDK](https://www.gxccd.com/cat?id=148)
- [Fujifilm SDK](http://www.fujifilm-x.com/global/special/camera-control-sdk/)

### Protocol Specifications
- [ASCOM Standards](https://ascom-standards.org/)
- [ASCOM Master Interfaces](https://ascom-standards.org/newdocs/)
- [ASCOM Alpaca API](https://ascom-standards.org/api/)
- [INDI Protocol](http://docs.indilib.org/protocol/)
- [INDI Standard Properties](http://docs.indilib.org/drivers/standard-properties/)
- [SynScan Serial Protocol v3.3](https://inter-static.skywatcher.com/downloads/synscanserialcommunicationprotocol_version33.pdf)
- [SkyWatcher Motor Controller Command Set](https://inter-static.skywatcher.com/downloads/skywatcher_motor_controller_command_set.pdf)
- [iOptron RS-232 v3.10](https://www.ioptron.com/v/ASCOM/RS-232_Command_Language2014V310.pdf)
- [Meade LX200 Command Set](http://www.company7.com/library/meade/LX200CommandSet.pdf)
- [OnStep Commands](https://onstep.groups.io/g/main/wiki/23755)
- [10Micron Protocol v2.15.1](https://www.ap-i.net/mantis/file_download.php?file_id=1224&type=bug)

### Conformance Testing
- [ConformU](https://github.com/ASCOMInitiative/ConformU)
- [Alpaca Discovery Tests](https://github.com/DanielVanNoord/AlpacaDiscoveryTests)
- [ASCOM Alpaca Simulators](https://github.com/ASCOMInitiative/ASCOM.Alpaca.Simulators)

### Community References
- [NINA GitHub](https://github.com/daleghent/NINA)
- [INDI GitHub](https://github.com/indilib/indi)
- [INDI 3rd Party](https://github.com/indilib/indi-3rdparty)
- [EQMOD (SkyWatcher ASCOM)](https://github.com/rmorgan001/GSServer)
- [OnStep GitHub](https://github.com/hjd1964/OnStep)
