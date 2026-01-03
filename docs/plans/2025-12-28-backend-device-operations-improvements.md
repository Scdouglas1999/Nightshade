# Backend Device Operations Improvement Plan

**Date**: 2025-12-28
**Scope**: All driver types (Alpaca, ASCOM, INDI, Native) and Bridge layer
**Priority**: Production hardening for reliability, performance, and compatibility

---

## Executive Summary

Comprehensive audit of Nightshade 2.0's backend device operations revealed **68 issues** across 5 driver layers. While the architecture is fundamentally sound with clean abstractions and good coverage, several critical issues require attention before production deployment in mission-critical astrophotography scenarios.

| Driver Layer | Critical | High | Medium | Low | Overall Score |
|--------------|----------|------|--------|-----|---------------|
| Alpaca | 2 | 4 | 6 | 4 | 6/10 |
| ASCOM | 2 | 3 | 4 | 3 | 6.5/10 |
| INDI | 2 | 4 | 5 | 3 | 6/10 |
| Native SDK | 3 | 2 | 3 | 2 | 7/10 |
| Bridge Layer | 4 | 8 | 12 | 6 | 5.5/10 |

---

## Critical Issues (Must Fix Before Production)

### 1. Timeout Handling (All Drivers)

**Problem**: No operation timeouts across any driver. Hung hardware or slow networks block indefinitely.

**Affected Files**:
- `alpaca/src/client.rs:52` - Fixed 30s timeout, no retry
- `ascom/src/windows_impl.rs:629-886` - No timeout on COM Invoke
- `indi/src/client.rs:172` - No timeout on partial XML
- `native/src/*/zwo.rs:688-761` - No timeout on exposure polling
- `bridge/src/real_device_ops.rs:163-220` - Slew loops forever

**Solution**:
```rust
// Add configurable timeout to all operations
pub struct OperationConfig {
    pub timeout_secs: f64,
    pub retry_count: u32,
    pub backoff_strategy: BackoffStrategy,
}

pub enum BackoffStrategy {
    Fixed(Duration),
    Exponential { base_ms: u64, max_ms: u64 },
    Adaptive,
}
```

**Effort**: High (touches all drivers)
**Impact**: Critical (prevents hung operations)

---

### 2. Panic Prevention Across FFI Boundary

**Problem**: Multiple `unwrap()` and `expect()` calls can crash the Flutter app.

**Affected Files**:
- `bridge/src/lib.rs:60` - `Runtime::new().expect()`
- `bridge/src/lib.rs:240` - `and_hms_opt().unwrap()`
- `bridge/src/api.rs:2488` - `partial_cmp().unwrap()` (NaN panic)
- `native/src/vendor/zwo.rs:781-783` - Integer overflow possible

**Solution**:
```rust
// Replace all panicking patterns with Result
fn safe_initialize() -> Result<Runtime, NightshadeError> {
    Runtime::new().map_err(|e|
        NightshadeError::Internal(format!("Runtime init failed: {}", e))
    )
}

// Add overflow-safe buffer allocation
let buffer_size = width.checked_mul(height)
    .and_then(|s| s.checked_mul(bytes_per_pixel as u32))
    .ok_or(NativeError::InvalidParameter("Image size overflow".to_string()))?
    as usize;
```

**Effort**: Medium
**Impact**: Critical (prevents app crashes)

---

### 3. Resource Leak Prevention

**Problem**: Device connections leak on error paths. Alpaca/ASCOM don't disconnect on failures.

**Affected Files**:
- `alpaca/src/camera.rs:328-413` - Image download creates new client, never closed
- `ascom/src/windows_impl.rs:601-603` - No cleanup on failed connect
- `bridge/src/real_device_ops.rs:163-220` - Mount disconnect never called on error
- `native/src/vendor/zwo.rs:1325-1352` - EAF handle leak on connect failure

**Solution**:
```rust
// RAII pattern for device connections
pub struct DeviceGuard<'a, T: Device> {
    device: &'a mut T,
    connected: bool,
}

impl<'a, T: Device> Drop for DeviceGuard<'a, T> {
    fn drop(&mut self) {
        if self.connected {
            let _ = self.device.disconnect();
        }
    }
}

async fn safe_mount_operation(mount: &mut AlpacaTelescope) -> Result<(), String> {
    let _guard = mount.connect().await?;  // Auto-disconnect on drop
    mount.slew_to_target().await?;
    Ok(())
}
```

**Effort**: Medium
**Impact**: Critical (prevents resource exhaustion)

---

### 4. Thread Safety for Native SDKs

**Problem**: Vendor SDKs (ZWO, QHY, etc.) are NOT thread-safe. Concurrent access causes undefined behavior.

**Affected Files**:
- `native/src/discovery.rs:82-104` - Discovery mutex exists but not enforced elsewhere
- `native/src/vendor/*.rs` - No per-vendor mutex for device operations

**Solution**:
```rust
// Per-vendor mutex for all SDK operations
lazy_static! {
    static ref ZWO_MUTEX: Mutex<()> = Mutex::new(());
    static ref QHY_MUTEX: Mutex<()> = Mutex::new(());
    static ref PLAYER_ONE_MUTEX: Mutex<()> = Mutex::new(());
}

impl ZwoCamera {
    async fn start_exposure(&mut self, params: ExposureParams) -> Result<(), NativeError> {
        let _lock = ZWO_MUTEX.lock().await;
        // SDK operations here are now serialized
        unsafe { (sdk.start_exposure)(self.camera_id, ASI_FALSE) };
        Ok(())
    }
}
```

**Effort**: Medium
**Impact**: Critical (prevents crashes/UB)

---

## High Priority Issues

### 5. Connection State Validation

**Problem**: Operations proceed without verifying device is still connected.

**Affected Drivers**: All

**Solution**:
```rust
// Add connection check before operations
async fn validate_connection(&self, device_id: &str) -> Result<(), DeviceError> {
    let connected = self.is_connected(device_id).await?;
    if !connected {
        return Err(DeviceError::Disconnected(device_id.to_string()));
    }
    Ok(())
}

// Heartbeat monitoring with configurable interval
pub struct HeartbeatConfig {
    pub interval_secs: u64,
    pub failure_threshold: u32,
    pub auto_reconnect: bool,
}
```

---

### 6. Error Type Differentiation

**Problem**: All errors converted to `String`, losing recovery information.

**Solution**:
```rust
#[derive(Debug, thiserror::Error)]
pub enum DeviceError {
    #[error("Connection timeout: {0}")]
    Timeout(String),

    #[error("Device disconnected: {0}")]
    Disconnected(String),

    #[error("Hardware error: {0}")]
    Hardware(String),

    #[error("Invalid parameter: {0}")]
    InvalidParameter(String),

    #[error("Operation not supported: {0}")]
    NotSupported(String),

    #[error("SDK error: {vendor} code {code}: {message}")]
    SdkError { vendor: String, code: i32, message: String },
}
```

---

### 7. API Version Negotiation

**Problem**: Hard-coded API versions with no fallback.

**Affected**:
- Alpaca: Hard-coded to v1 (`lib.rs:34`)
- INDI: Hard-coded to 1.7 (`protocol.rs:4`)
- ASCOM: No version checking

**Solution**:
```rust
pub struct VersionedClient {
    preferred_version: ApiVersion,
    fallback_versions: Vec<ApiVersion>,
    negotiated_version: Option<ApiVersion>,
}

impl VersionedClient {
    async fn negotiate_version(&mut self, server: &str) -> Result<ApiVersion, Error> {
        for version in std::iter::once(&self.preferred_version)
            .chain(self.fallback_versions.iter())
        {
            if self.probe_version(server, version).await.is_ok() {
                self.negotiated_version = Some(version.clone());
                return Ok(version.clone());
            }
        }
        Err(Error::NoCompatibleVersion)
    }
}
```

---

### 8. Parallel Query Methods

**Problem**: Status checks make many sequential HTTP/COM calls. Dome is the only device with parallel aggregation.

**Affected**: `alpaca/src/camera.rs`, `alpaca/src/telescope.rs`, `ascom/src/windows_impl.rs`

**Solution**:
```rust
// Follow dome.rs pattern for all devices
impl AlpacaCamera {
    pub async fn get_full_status(&self) -> Result<CameraStatus, String> {
        let (state, temp, cooler_power, cooler_on, gain, offset, binning, subframe) =
            tokio::join!(
                self.camera_state(),
                self.ccd_temperature(),
                self.cooler_power(),
                self.cooler_on(),
                self.gain(),
                self.offset(),
                self.binning(),
                self.subframe(),
            );

        Ok(CameraStatus {
            state: state?,
            temperature: temp?,
            cooler_power: cooler_power?,
            // ...
        })
    }
}
```

---

### 9. Device Capability Reporting

**Problem**: Dart can't know what operations are available without trying and catching errors.

**Solution**:
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MountCapabilities {
    pub can_slew: bool,
    pub can_slew_async: bool,
    pub can_sync: bool,
    pub can_park: bool,
    pub can_unpark: bool,
    pub can_find_home: bool,
    pub can_pulse_guide: bool,
    pub can_set_tracking_rate: bool,
    pub supported_tracking_rates: Vec<TrackingRate>,
    pub can_move_axis: [bool; 3],  // Primary, Secondary, Tertiary
}

// Query at connect time, cache in DeviceInfo
pub async fn api_get_mount_capabilities(mount_id: String) -> Result<MountCapabilities, Error>;
```

---

### 10. Blocking Calls in Async Context

**Problem**: `spawn_blocking` used extensively but wastes thread pool.

**Affected**: `bridge/src/real_device_ops.rs` (20+ instances)

**Solution**:
```rust
// For ASCOM: Dedicated COM thread pool
pub struct AscomThreadPool {
    workers: Vec<JoinHandle<()>>,
    tx: mpsc::Sender<AscomTask>,
}

// For Alpaca: Already async, just needs better error handling

// For INDI: Already async

// For Native: Use spawn_blocking sparingly, cache SDK calls
```

---

## Medium Priority Issues

### 11. Discovery Improvements

| Driver | Issue | Solution |
|--------|-------|----------|
| Alpaca | Sync UDP blocking executor | Use `tokio::net::UdpSocket` |
| INDI | Network scan slow (50 hosts/sec) | Adaptive batching, progress callback |
| Native | QHY discovery commented out | Investigate and re-enable with safety |

### 12. Image Handling Optimization

- **Zero-copy buffer reuse**: Don't allocate new Vec for each exposure
- **Streaming for large images**: Add chunked download for 4K+ sensors
- **Format validation**: Parse BLOB format attribute, don't assume FITS

### 13. Vendor Quirks Database

```rust
pub struct VendorQuirks {
    pub name: &'static str,
    pub workarounds: Vec<Workaround>,
}

pub enum Workaround {
    SlowSlewResponse { wait_ms: u64 },
    NonStandardBoolReturn,
    RequiresDelayAfterConnect { ms: u64 },
    TemperatureReadingUnreliable,
}

// Apply quirks during device connection
```

### 14. Event Bus Improvements

- Per-category event buses (equipment, imaging, sequencer)
- Backpressure handling for slow subscribers
- Event ordering guarantees with sequence numbers

### 15. State Synchronization

- Single source of truth for device state
- Event-driven state propagation
- Optimistic locking for state transitions with rollback

---

## Driver-Specific Improvements

### Alpaca

| Issue | File:Line | Priority |
|-------|-----------|----------|
| Generic string errors | client.rs:99 | High |
| No retry logic | client.rs:52 | High |
| Hard-coded API v1 | lib.rs:34 | Medium |
| SafetyMonitor incomplete | safetymonitor.rs | Medium |
| No HTTP/2 support | client.rs:51 | Low |

### ASCOM

| Issue | File:Line | Priority |
|-------|-----------|----------|
| No operation timeouts | windows_impl.rs:629 | Critical |
| SAFEARRAY bounds too tight | windows_impl.rs:383 | High |
| can_move_axis stubbed | windows_impl.rs:1515 | Medium |
| No device version detection | windows_impl.rs:575 | Medium |
| Batch property queries | ascom_wrapper.rs:96 | Low |

### INDI

| Issue | File:Line | Priority |
|-------|-----------|----------|
| Race in keepalive | client.rs:671 | High |
| Reader task not supervised | client.rs:114 | High |
| XML parse timeout missing | client.rs:172 | High |
| BLOB format not validated | client.rs:293 | Medium |
| Property min/max not parsed | client.rs:273 | Medium |

### Native SDK

| Issue | File:Line | Priority |
|-------|-----------|----------|
| Buffer size overflow | zwo.rs:781 | Critical |
| No per-vendor mutex | discovery.rs:82 | Critical |
| QHY discovery disabled | discovery.rs:134 | High |
| Gain/offset range not exposed | camera.rs:89 | Medium |
| SDK version not detected | zwo.rs:200 | Low |

### Bridge Layer

| Issue | File:Line | Priority |
|-------|-----------|----------|
| Panics across FFI | lib.rs:60 | Critical |
| Device ID parsing unsafe | real_device_ops.rs:192 | Critical |
| block_in_place deadlock | real_device_ops.rs:52 | High |
| Resource leaks on error | real_device_ops.rs:163 | High |
| State not synchronized | devices.rs:76 | High |

---

## Implementation Phases

### Phase 1: Critical Fixes (1-2 weeks)
1. Add panic handlers across FFI boundary
2. Implement operation timeouts for all drivers
3. Add resource cleanup on error paths (RAII guards)
4. Add per-vendor mutex for native SDKs
5. Fix device ID parsing with proper validation

### Phase 2: Robustness (2-3 weeks)
1. Connection state validation before operations
2. Heartbeat monitoring improvements
3. Error type differentiation (remove String errors)
4. Reader task supervision for INDI
5. Keepalive race condition fix

### Phase 3: Performance (2-3 weeks)
1. Parallel query methods for all device types
2. Buffer pooling for image capture
3. Event bus optimization
4. FFI overhead reduction (cache parsed IDs)
5. Adaptive polling with exponential backoff

### Phase 4: Features & Compatibility (2-3 weeks)
1. Device capability reporting
2. API version negotiation
3. Vendor quirks database
4. Missing device operations (readout modes, subframe ROI)
5. Re-enable QHY discovery with safety

### Phase 5: Architecture (Ongoing)
1. State synchronization consolidation
2. Unified vs Real DeviceOps cleanup
3. Event ordering guarantees
4. Comprehensive test coverage

---

## Testing Requirements

### Unit Tests
- [ ] Device ID parsing edge cases
- [ ] Error type conversion
- [ ] Timeout behavior
- [ ] Buffer size calculations

### Integration Tests
- [ ] Concurrent device access
- [ ] Connection/disconnection cycles
- [ ] Heartbeat failure recovery
- [ ] Large image transfers

### Stress Tests
- [ ] 1000+ sequential exposures
- [ ] Multi-device concurrent operations
- [ ] Network interruption recovery
- [ ] Memory leak detection

### Hardware Tests
- [ ] ZWO cameras (ASI series)
- [ ] QHY cameras (if re-enabled)
- [ ] Various ASCOM drivers
- [ ] INDI on Linux/macOS
- [ ] Alpaca remote servers

---

## Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Panic rate | Unknown | 0 per 1000 sessions |
| Resource leaks | Present | 0 |
| Operation timeout coverage | 0% | 100% |
| Error recovery rate | Low | >95% |
| Concurrent device limit | ~5 | 20+ |
| Image capture reliability | Good | 99.9% |
| Connection recovery time | 30s+ | <5s |

---

## Appendix: File Reference

### Files Requiring Changes

**Critical Priority**:
- `native/nightshade_native/bridge/src/lib.rs`
- `native/nightshade_native/bridge/src/real_device_ops.rs`
- `native/nightshade_native/native/src/vendor/zwo.rs`
- `native/nightshade_native/alpaca/src/client.rs`
- `native/nightshade_native/ascom/src/windows_impl.rs`
- `native/nightshade_native/indi/src/client.rs`

**High Priority**:
- `native/nightshade_native/bridge/src/devices.rs`
- `native/nightshade_native/bridge/src/error.rs`
- `native/nightshade_native/bridge/src/unified_device_ops.rs`
- `native/nightshade_native/native/src/discovery.rs`
- `native/nightshade_native/alpaca/src/discovery.rs`

**Medium Priority**:
- All device-specific files in each driver
- `native/nightshade_native/bridge/src/event.rs`
- `native/nightshade_native/bridge/src/state.rs`
