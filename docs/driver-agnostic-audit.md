## Nightshade Driver-Agnostic Audit (ASCOM / Alpaca / INDI / Native)

### Scope & intent
- **Goal**: Verify that user-facing functionality across all UI screens works with **any supported driver type** (ASCOM, Alpaca, INDI, Native), and identify where the code assumes capabilities that some drivers/devices may not provide.
- **Constraint**: This report is updated incrementally “as we go” during the audit (per request). It will end with a consolidated summary and recommendations once all screens/services have been checked.

### Audit methodology
- Enumerate screens/tabs/routes from `nightshade_app`.
- For each screen:
  - List major user actions and the backend/service calls they trigger.
  - Trace those calls into `nightshade_core` (`providers/`, `services/`, `backend/`).
  - Identify **driver assumptions** (feature availability differences across ASCOM/Alpaca/INDI/Native, including per-device optional features).
  - Identify **edge cases** that can break in certain drivers or with multiple devices.
- Cross-cutting: compare `NightshadeBackend` contract to each backend implementation (`FfiBackend`, `NetworkBackend`, Rust bridge side) and note mismatches.

---

## Screen / tab inventory (confirmed)

### Primary nav tabs (side nav + bottom nav)
- Dashboard
- Equipment
- Imaging
- Guiding
- Sequencer
- Planetarium
- Framing
- Analytics
- Flat Wizard
- Weather

Sources:
- `packages/nightshade_app/lib/router/app_router.dart`
- `packages/nightshade_app/lib/screens/shell/app_shell.dart`
- `packages/nightshade_app/lib/screens/shell/widgets/side_navigation.dart`

### Additional routes (not in the left nav)
- **Settings**: reachable from title bar via `/settings` (route exists)
- **Polar Alignment**: `/polar-alignment` (route exists; not in main nav)
- **Potential routing bug**: title bar attempts `context.go('/profiles')`, but no `/profiles` `GoRoute` is defined in the router.

Sources:
- `packages/nightshade_app/lib/screens/shell/widgets/title_bar.dart`
- `packages/nightshade_app/lib/router/app_router.dart`

---

## Cross-cutting architecture findings (driver-agnostic risks)

### Backend abstraction is strong, but capability modeling is weak
- Core device/control abstraction is `NightshadeBackend` (`packages/nightshade_core/lib/src/backend/nightshade_backend.dart`).
- Implementations:
  - `FfiBackend` (desktop/headless, talks to Rust bridge)
  - `NetworkBackend` (mobile/thin client, talks to headless REST/WebSocket)
  - `DisconnectedBackend` (mobile default when not connected)
- **Key risk**: There is no first-class capability model (e.g., “camera has cooler”, “mount can set tracking rate”, “camera supports ROI/binning/offset”, etc.) that UI/services can use to gate or adapt behavior. Many operations assume the backend call exists and will succeed, and rely on exceptions when unsupported.

### “Recommended backend” is static and doesn’t consider capabilities
- `UnifiedDevice.recommendedBackend` is hard-coded priority:
  - Native > ASCOM > Alpaca > INDI > Simulator
- **Risk**: A “higher priority” backend may exist but lack a capability the user expects; there’s no evidence-based selection (“pick backend that supports required ops for this workflow”).

Source:
- `packages/nightshade_core/lib/src/models/equipment/unified_device.dart`

### Connection retry uses device name instead of device ID (likely breaks across all drivers)
- Several device state notifiers implement `retryConnection()` by calling `connect(state.deviceName!)` rather than `connect(state.deviceId!)`.
- If `connect()` expects a driver/device **ID**, retry will fail (and could be misdiagnosed as “driver incompatibility”).

Source:
- `packages/nightshade_core/lib/src/providers/equipment_provider.dart` (Mount/Focuser/FilterWheel/Guider `retryConnection()` patterns)

### Some device operations rely on the active profile instead of the connected device state
- Example: `DeviceService.setCameraCooling()` looks up `activeProfile.cameraId` rather than using the currently connected camera’s `deviceId`.
- Risk: user connects a device manually (or via unified selection) but doesn’t save it to the active profile; subsequent operations can fail or affect the wrong device.

Source:
- `packages/nightshade_core/lib/src/services/device_service.dart` (`setCameraCooling`)

### Event payload parsing is incomplete in `FfiBackend` (non-core categories become opaque strings)
- `FfiBackend.eventStream` extracts structured data only for: Equipment, Imaging, Guiding, Sequencer.
- Safety/System/PolarAlignment payloads fall back to `payload.toString()` parsing, resulting in:
  - Weak/unstable `eventType` derivation.
  - No structured `data` map (UI/services can’t reliably consume fields).
- This directly impacts features that depend on event-driven updates (e.g., Polar Alignment, Safety automation UIs, future weather device events).

Source:
- `packages/nightshade_core/lib/src/backend/ffi_backend.dart` (`_extractPayloadInfo`)

### The Rust bridge *does* know about driver-specific capabilities, but Dart UX rarely uses them
- Some device status models already carry capability flags (example: mount `can_set_tracking_rate`).
- The Rust DeviceManager enforces driver-type support at runtime (returning “not supported”) for operations that aren’t implemented for a given backend.
- In the UI, most buttons don’t gate on these flags, so unsupported operations become runtime errors that read like “driver incompatibility”.

Sources:
- `native/nightshade_native/bridge/src/devices.rs` (driver-type match arms like `mount_set_tracking_rate`, `cover_calibrator_*`)
- `packages/nightshade_core/lib/src/models/equipment/equipment_models.dart` (`MountState.canSetTrackingRate`)

### Some driver types are missing feature parity in the Rust DeviceManager (example: tracking rate for Alpaca/INDI)
- `mount_set_tracking_rate` / `mount_get_tracking_rate` are only implemented for **ASCOM** and **Native**; other driver types return “not supported”.
- The INDI mount status explicitly reports `can_set_tracking_rate: false`, reinforcing that this feature is not available in current INDI integration.
- If the UI exposes a tracking-rate selector globally, this will violate “driver agnostic” expectations unless it is gated per device.

Source:
- `native/nightshade_native/bridge/src/devices.rs` (`mount_set_tracking_rate`, `mount_get_tracking_rate`, INDI mount status)

### Some status/telemetry implementations are placeholders (can break downstream logic)
- Example: INDI dome status returns a basic “connected” status with placeholder telemetry (azimuth `0.0`, shutter `Unknown`), with a comment that full polling will be implemented later.
- Downstream features that rely on dome telemetry (slaving logic, safe close verification, UI status) will behave differently by driver type.

Source:
- `native/nightshade_native/bridge/src/devices.rs` (INDI dome status stub)

### Simulator devices are disabled in the native bridge (reduces cross-driver test coverage)
- Several code paths return: “Simulator devices are disabled…”.
- This increases the risk that workflows are only tested with the author’s real hardware, and capability gaps won’t be discovered until users try other drivers/devices.

Source:
- `native/nightshade_native/bridge/src/devices.rs` (driver type `Simulator` match arms)

---

## Equipment screen (Discovery / Connect) findings

### Unified discovery (cross-backend) — good, but has sharp edges
- **Good**: Equipment discovery intentionally searches across Native/ASCOM/Alpaca/INDI (+ Simulator) and groups devices into `UnifiedDevice`s so a user can pick a backend.
- **Grouping mechanism**: fuzzy name matching (Levenshtein + substring heuristics) with normalization that strips vendor prefixes and instance suffixes.

Sources:
- `packages/nightshade_core/lib/src/providers/unified_discovery_provider.dart`
- `packages/nightshade_core/lib/src/services/device_matching_service.dart`

#### High-risk edge case: multi-device rigs can be mis-grouped
- Because instance markers like “#1” / “(1)” / trailing digits are stripped during normalization, two identical devices (e.g., two “ASI290MM” cameras) may be **merged into a single `UnifiedDevice`**.
- Impact: user cannot reliably select/operate the second device; appears as “Nightshade doesn’t support my other camera” and can vary by driver naming conventions.

Source:
- `packages/nightshade_core/lib/src/services/device_matching_service.dart` (instance stripping + similarity threshold)

### Mobile/remote cross-driver break: `native` driver type not handled in NetworkBackend
- `NetworkBackend._parseDriverType()` handles `ascom/alpaca/indi/simulator` but **not `native`**.
- If a headless server reports devices with driverType “native” (likely), mobile discovery can throw “Unknown driver type”.
- This breaks the “any driver type works” requirement for remote control scenarios.

Source:
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (`_parseDriverType`)

### Profile “Connect All” is not robust to empty IDs
- Equipment “Connect All” checks `!= null` but not `isNotEmpty` for device IDs.
- If a profile has an empty string device id (plausible via migrations/partial edits), it will attempt to connect `""` and fail in a way that looks like a driver/device incompatibility.

Source:
- `packages/nightshade_app/lib/screens/equipment/equipment_screen.dart`

### Initial device state after connect is sometimes placeholder instead of real status
- Mount connect sets a hard-coded position and parked state immediately after connecting.
- Filter wheel connect sets position 0 without reading actual wheel position.
- Risk: downstream screens (planetarium/framing/centering) may compute with incorrect mount state unless/ until real telemetry events arrive.

Source:
- `packages/nightshade_core/lib/src/services/device_service.dart` (connectMount/connectFilterWheel patterns)

### Profile-level connection UI is not actually profile-aware (device IDs are ignored)
- `QuickConnectBar` and `ConnectionStatusZone` compute “connected/connecting/error” counts by looking only at each device state’s `connectionState`.
- They **do not check** whether the currently connected device matches the profile’s assigned device id (e.g., `cameraState.deviceId == profile.cameraId`).
- Failure mode:
  - Connect “Profile A” (camera A), then switch to “Profile B” (camera B): UI can still show “Camera connected” even though camera B is not connected.
  - Subsequent actions (“Connect All”, “Disconnect”, status telemetry, etc.) become confusing and can look like “this driver doesn’t work” when it’s actually “wrong device is connected”.

Sources:
- `packages/nightshade_app/lib/screens/equipment/widgets/quick_connect_bar.dart` (`_getProfileConnectionState` ignores ids)
- `packages/nightshade_app/lib/screens/equipment/widgets/connection_status_zone.dart` (`_buildDeviceList` uses profile ids but reads global connection state)
- `packages/nightshade_core/lib/src/models/equipment/equipment_models.dart` (states include `deviceId`, so the check is possible)

### “Connect All” and status summaries only cover a subset of device types (rotator is omitted)
- Discovery supports selecting/connecting rotators (`ConnectionsTab` has a rotator card), and equipment profiles include `rotatorId`.
- However:
  - `EquipmentScreen._connectAllDevices()` and `_disconnectAllDevices()` do **not** include rotator (or dome/weather/safety/etc).
  - `QuickConnectBar` and `ConnectionStatusZone` totals do not include rotator.
- Failure mode: users assign a rotator in the profile, then “Connect All” leaves it disconnected; downstream workflows that assume rotator availability look “driver broken” even though it’s “not connected”.

Sources:
- `packages/nightshade_app/lib/screens/equipment/equipment_screen.dart` (`_connectAllDevices`, `_disconnectAllDevices`)
- `packages/nightshade_app/lib/screens/equipment/tabs/connections_tab.dart` (rotator support)
- `packages/nightshade_app/lib/screens/equipment/widgets/quick_connect_bar.dart` (totals omit rotator)
- `packages/nightshade_app/lib/screens/equipment/widgets/connection_status_zone.dart` (device list omits rotator)

### Error surfacing is stubbed in the “Connection Status Zone” (driver incompatibilities get hidden)
- `_DeviceStatus.error` is always `null` (“TODO: Get actual error”), and the “Skip” action is also TODO.
- This encourages generic “connection error” UX rather than actionable capability/driver feedback (timeouts vs unsupported methods vs permission issues).

Source:
- `packages/nightshade_app/lib/screens/equipment/widgets/connection_status_zone.dart`

### Connected tab contains driver-sensitive quick actions (Plate Solve & Sync is hard-coded + local-only)
- `MountControlPanel` includes “Plate Solve & Sync”, implemented as:
  1. Capture an image with **hard-coded** exposure settings: 2s, gain 100, offset 10, bin 2×2.
  2. Plate-solve via **ASTAP only**, locating the executable via `PlateSolverUtils.findAstapExecutable(appSettings.astapPath)`.
  3. Sync mount via `deviceService.syncMountToCoordinates(...)`.
- **Driver/backend-agnostic break**:
  - Assumes camera supports gain/offset/binning and those values are valid.
  - Assumes ASTAP is installed and discoverable on the same machine running the UI.
  - In remote mode, `image.filePath` is typically server-local; solving on the client will fail.
  - Ignores user solver choice (Settings can select Astrometry.net/PlateSolve2, but this action forces ASTAP).

Sources:
- `packages/nightshade_app/lib/screens/equipment/widgets/mount_control_panel.dart`
- `packages/nightshade_core/lib/src/services/plate_solve_service.dart` (`PlateSolverUtils`)
- `packages/nightshade_core/lib/src/providers/settings_provider.dart` (`astapPath` is client-local persisted setting)

### INDI server dialog does not persist configuration (likely to regress “INDI support” perceptions)
- `IndiServerDialog` loads `indiServerHost/indiServerPort` from settings but explicitly does not save updates (“Note: We need to implement updateIndiSettings… For now… return the values”).
- Result: users will repeatedly re-enter server addresses, and “INDI discovery doesn’t work” reports will be difficult to distinguish from stale config.

Source:
- `packages/nightshade_app/lib/screens/equipment/dialogs/indi_server_dialog.dart`

---

## Dashboard screen findings

### Quick Actions: Snapshot (camera capture)
- Dashboard “Snapshot” uses `ImagingService.captureImage()` with `ExposureSettings` from `exposureSettingsProvider`.
- **Driver/capability risk**: `ExposureSettings` always includes `gain`, `offset`, `binningX/Y`, and `ImagingService` always forwards those values into `backend.cameraStartExposure(...)`. Many cameras/drivers do not support one or more of these (or have different ranges/semantics).
- **Failure mode**: Snapshot fails with “driver error” on cameras lacking gain/offset/binning support unless the backend layer explicitly ignores unsupported fields.

Sources:
- `packages/nightshade_app/lib/screens/dashboard/dashboard_screen.dart` (Snapshot onTap)
- `packages/nightshade_core/lib/src/services/imaging_service.dart` (`cameraStartExposure` call)
- `packages/nightshade_core/lib/src/providers/imaging_provider.dart` (default gain/offset assumptions)

### Quick Actions: Center (plate solve + iterative correction)
- “Center” opens `_CenteringDialog` which:
  - Captures an image using **hard-coded** exposure settings:
    - exposure 5s, gain 100, offset 10, bin 2×2
  - Plate-solves via ASTAP (or other solver) using hints
  - Slews the mount using `deviceService.slewMountToCoordinates(newRa, newDec)` for up to 3 iterations
- **Driver/capability risks**:
  - Hard-coded `gain/offset/binning` can fail on many cameras (or be out of range).
  - Assumes mount supports equatorial slew-to-coordinates and that a fixed “wait 2s” is sufficient (no completion check).
  - **Unit mismatch bug**: `PlateSolveResult.ra` is documented as **hours**, but the centering code treats `(ra - targetRa) * 3600` as “arcseconds”. RA-to-arcsec conversion should include the 15× factor (and typically cos(dec) if expressing angular separation).
    - This makes the displayed “Error: … arcsec” incorrect and can distort the correction step / iteration logic.

Sources:
- `packages/nightshade_app/lib/screens/dashboard/dashboard_screen.dart` (`_CenteringDialog._runCentering`)
- `packages/nightshade_core/lib/src/services/plate_solve_service.dart` (`PlateSolveResult.ra // hours`)

### Quick Actions: Park
- Calls `deviceService.parkMount()`.
- **Driver/capability risk**: “Park” is not universally supported (or may require prior alignment/park position). Expect protocol-specific behavior differences unless the mount layer exposes/handles “canPark”.

Source:
- `packages/nightshade_app/lib/screens/dashboard/dashboard_screen.dart` (Park onTap)

---

## Imaging screen findings

### Capture pipeline: gain/offset/binning always passed to backend
- Imaging “Snapshot” and “Loop” call `ImagingService.captureImage()` / `startLoopCapture()` with `ExposureSettings`.
- **Driver/capability risk**: `ImagingService` always forwards `gain`, `offset`, `binX`, `binY` into `backend.cameraStartExposure(...)`.
  - Many cameras/drivers don’t support one or more of these fields, or require different ranges/semantics.
  - If the Rust/driver layer doesn’t explicitly treat these as optional, captures will fail on certain devices (presenting as “driver incompatibility”).

Sources:
- `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` (`_takeSnapshot`, `_toggleLoop`)
- `packages/nightshade_core/lib/src/services/imaging_service.dart` (`cameraStartExposure`)

### Camera cooling controls are not capability-gated
- The Imaging “Camera” panel always shows cooling UI (target temp slider, cool down / warm up).
- **Driver/capability risk**: Cameras without a cooler (or drivers that don’t expose cooler control) will throw errors on `setCameraCooling(...)`.
- **Cross-cutting risk**: `DeviceService.setCameraCooling()` uses the **active profile cameraId**, not the currently connected `cameraState.deviceId`. Manual connections can therefore appear “broken” here.

Sources:
- `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` (`_CameraPanel` cooling section)
- `packages/nightshade_core/lib/src/services/device_service.dart` (`setCameraCooling`)

### Camera “Sensor / Read Mode” settings may be a no-op
- Imaging “Camera” panel exposes “Read Mode: High Quality / Fast” via `ExposureSettings.fastReadout`.
- **Risk**: `ImagingService.cameraStartExposure(...)` does not forward `fastReadout` (and `NightshadeBackend.cameraStartExposure` signature doesn’t include it), so UI may imply a driver feature that isn’t actually applied.

Sources:
- `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` (`_CameraPanel` sensor section)
- `packages/nightshade_core/lib/src/backend/nightshade_backend.dart` (`cameraStartExposure` params)

### Filter selection uses the filter wheel state (good), but does not update exposure metadata
- The control-bar filter selector correctly reads `filterWheelState.filterNames` and calls `deviceService.setFilterWheelPosition(position)`.
- **Risk (cross-device)**: Selection does **not** update `exposureSettings.filter`, so file naming / FITS header metadata can drift from the real physical filter position unless something else updates it.
- **UI correctness risk**: `_FilterSelector` caches `_selectedFilter` locally and only initializes it once.
  - If the filter wheel position changes due to other actions (sequencer, profile connect, backend event), `_selectedFilter` is not recomputed and the UI can show the wrong active filter.
  - UI updates optimistically before the move; on failure it shows a snackbar but does not revert the selection.

Source:
- `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` (`_FilterSelector`)

### Capture panel “Save Path” uses a local filesystem picker (problematic for remote/mobile control)
- Imaging “Capture” panel uses `getDirectoryPath(...)` to set `AppSettings.imageOutputPath`.
- **Cross-backend risk**: In a mobile client controlling a remote/headless server, selecting a directory on the phone/tablet does not map to a valid server path. Unless `appSettingsProvider` is server-backed in network mode, this can silently misconfigure saving.

Source:
- `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` (`_CapturePanel` → `getDirectoryPath`, `setImageOutputPath`)

### Mount panel bypasses the backend abstraction (major driver-agnostic violation)
- The Imaging “Mount” tab is `MountTab` and it calls `nightshade_bridge/src/api.dart` (`bridge_api.*`) directly:
  - `apiGetMountStatus`, `apiMountSlewToCoordinates`, `apiMountSyncToCoordinates`, `apiMountSetTracking`, `apiMountPark/Unpark`, `apiMountPulseGuide`, `mountAbort`, etc.
- **Driver/back-end risk**:
  - Bypasses `NightshadeBackend` / `DeviceService`, so it’s tightly coupled to the desktop/headless bridge API surface.
  - Likely won’t work correctly for `NetworkBackend` (mobile remote control), and any future backend implementation.
  - Uses the **active profile’s** `mountId` rather than the currently connected mount state; manual connections can “mysteriously” fail.

Source:
- `packages/nightshade_app/lib/screens/imaging/tabs/mount_tab.dart`

### Focus panel: hardware moves are used, but autofocus is a stub
- Manual focus calls `deviceService.moveFocuserRelative(...)` and `moveFocuserTo(...)` with only “connected” gating.
  - **Risk**: no capability gating for focusers lacking absolute positioning or relative movement.
- Autofocus action in the imaging screen currently simulates a 5-second run rather than calling a backend autofocus routine.
  - Not a driver-specific issue, but it’s a **functional gap** that can be confused with “device/driver doesn’t support autofocus”.
- **Related (core)**: `filterOffsetProvider` contains a `_saveOffsetsToService()` method that currently does not persist manual offset edits (comment explicitly notes the missing persistence method).
  - Not driver-specific, but it affects “filter offsets” workflows across all filter wheel drivers.

Source:
- `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` (`_FocusPanelState`)
- `packages/nightshade_core/lib/src/providers/filter_offset_provider.dart` (`_saveOffsetsToService` comment / behavior)

### Guiding panel assumes “guider == PHD2”
- The imaging “Guiding” panel uses `DeviceService.startGuiding/stopGuiding/dither`, and the UI copy explicitly says “No guider connected (PHD2)”.
- **Driver/capability risk**: guiding support can vary widely:
  - Some users guide through PHD2, others via native driver pulse guiding / ST-4, etc.
  - If `DeviceService` is implemented strictly as “PHD2 only”, then guider functionality becomes driver-/workflow-specific.

Source:
- `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` (`_GuidingPanelState`)

### Annotation pipeline depends on backend plate solving + saved file paths
- Imaging screen initializes `AnnotationService`, which:
  - only processes images when `CapturedImageData.filePath != null`
  - uses `backend.plateSolve(imagePath: ...)` and optionally mount RA/Dec hints
- **Cross-backend risk**:
  - On remote/mobile workflows, `filePath` may not be present/meaningful locally, which effectively disables annotations.
  - Plate solving is backend-dependent; verify `NetworkBackend.plateSolve` parity with desktop.

Sources:
- `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` (annotation init)
- `packages/nightshade_core/lib/src/services/annotation_service.dart` (`backend.plateSolve`, filePath gating)

### Centering dialog (from Imaging → Mount tab): hard-coded ASTAP path + fixed camera parameters
- Imaging’s mount tools include a “Center Target” flow (`CenteringDialog`) backed by `CenteringService`.
- **Platform risk**: `CenteringDialog` currently hard-codes ASTAP executable path to Windows (`C:\Program Files\astap\astap.exe`).
- **Driver/capability risk**: `CenteringService` captures with fixed parameters (gain 100, offset 50, binning 2×2) and requires `CapturedImageData.filePath` to be present for plate solving.
  - Cameras/drivers without gain/offset/binning support (or with different ranges) can fail here.
  - Any backend that can’t save the image locally (no `filePath`) will fail centering at the plate-solve step.

Sources:
- `packages/nightshade_app/lib/screens/imaging/centering_dialog.dart`
- `packages/nightshade_core/lib/src/services/centering_service.dart`

### Dead/unused Imaging “tabs/*” implementations exist (potential confusion + latent assumptions)
- `CaptureTab`, `CameraTab`, `FocusTab`, `GuidingTab` in `packages/nightshade_app/lib/screens/imaging/tabs/` are **not referenced** by `ImagingScreen` or the router.
- Only `MountTab` is currently used (in `ImagingScreen`’s right panel).
- These unused widgets contain additional assumptions (e.g., fixed filter lists, halt-focuser workaround) that may become user-facing if re-wired later.

Source:
- `packages/nightshade_app/lib/screens/imaging/` + greps for `CaptureTab/CameraTab/FocusTab/GuidingTab`

---

## Guiding screen findings

### Guiding UI is effectively PHD2-only (and can mis-report when a non-PHD2 guider is connected)
- The Guiding screen UI is explicitly a “Full PHD2 guiding interface”:
  - Connect/disconnect uses `phd2ControllerProvider.connect(host, port)` / `.disconnect()`.
  - Guiding actions use `phd2ControllerProvider.startGuiding/stopGuiding/dither/loop`, and the graph + star view are fed by PHD2 event/poll providers.
- **Driver/workflow risk**:
  - `DeviceService.connectGuider()` supports both:
    - special `deviceId == 'phd2_guider'` path (PHD2)
    - “standard guider connection (ASCOM/Alpaca/INDI)” via `_backend.connectDevice(DeviceType.guider, deviceId)`
  - But `DeviceService.startGuiding/stopGuiding/dither` always call `_backend.phd2*` methods regardless of which guider device is connected.
    - This makes “non-PHD2 guider” connections misleading: guider state can be “connected” while PHD2 is not, and guiding operations will still attempt PHD2.
  - `phd2ConnectedProvider` is derived from `guiderStateProvider.connectionState`, not from a true “PHD2 connection established” flag, which amplifies the mis-reporting risk.

Sources:
- `packages/nightshade_app/lib/screens/guiding/guiding_screen.dart`
- `packages/nightshade_core/lib/src/services/device_service.dart` (`connectGuider`, `startGuiding/stopGuiding/dither`)
- `packages/nightshade_core/lib/src/providers/guiding_provider.dart` (`phd2ConnectedProvider`, `phd2ControllerProvider`)

---

## Sequencer screen findings (in progress)

### Sequencer uses two execution engines (native Rust vs Dart fallback)
- `SequenceExecutor` defaults to **native execution** (`useNativeExecution ?? true`) and will call:
  - `backend.sequencerSetSimulationMode(...)`
  - `backend.sequencerSetDevices(cameraId/mountId/focuserId/filterwheelId/rotatorId)`
  - `backend.sequencerLoadJson(...)`
  - `backend.sequencerStart()`
- **Risk**: The Sequencer UI can look “driver agnostic” while actual capability support depends heavily on which execution engine is active and how fully each backend implements sequencer methods.

Source:
- `packages/nightshade_core/lib/src/providers/sequence_provider.dart` (`_useNativeExecution`, `_startNativeExecution`)

### Dart fallback executor contains multiple non-agnostic / FFI-only calls
If `useNativeExecution` is disabled, `_executeSequence(...)` runs directly in Dart and includes direct bridge calls that bypass `NightshadeBackend` / `DeviceService`:
- **Center node** uses `bridge.NativeBridge.plateSolveNear(...)` and requires `CapturedImageData.filePath` (falls back to `''` if null, which will fail).
- **Cool/Warm camera nodes** use `bridge.NativeBridge.setCameraCooler(...)` / `getCameraStatus(...)` and identify the camera by **device name** (not device ID).
- **Impact**: This path is **not driver agnostic** (and likely not remote/mobile compatible) because it assumes the local FFI bridge is available and that driver mapping is name-based.

Source:
- `packages/nightshade_core/lib/src/providers/sequence_provider.dart` (`_executeSequence`: `CenterNode`, `CoolCameraNode`, `WarmCameraNode`)

### Dart fallback ignores core “logic” semantics (loops/conditionals/recovery become no-ops)
- The fallback executor builds a flat list of enabled nodes via depth-first traversal and then executes them once.
- Container/logic nodes (`LoopNode`, `ParallelNode`, `ConditionalNode`, `RecoveryNode`, etc.) are treated as “do nothing” with a status message.
- **Risk**: If a user disables native execution, the sequence may “run” but behave very differently from what the UI implies — easily misdiagnosed as driver/device problems.

Source:
- `packages/nightshade_core/lib/src/providers/sequence_provider.dart` (`collectNodes(...)` and logic node handling in `_executeSequence`)

### Filter change is name-matched against driver-provided filter names
- `FilterChangeNode` includes both `filterName` and optional `filterPosition`, but execution uses case-insensitive **name** lookup in `filterWheelState.filterNames`.
- **Driver risk**: filter naming varies widely across drivers (e.g., `Ha` vs `H-alpha`, spaces, case), and duplicates are possible; this can cause “Filter not found” failures even though the wheel supports the target position.

Source:
- `packages/nightshade_core/lib/src/providers/sequence_provider.dart` (`FilterChangeNode` execution)
- `packages/nightshade_core/lib/src/models/sequence/sequence_models.dart` (`FilterChangeNode` model)

### Required-device inference is incomplete for several “parameterized” nodes
- `ExposureNode.requiredDevices` is `{camera}` even though `ExposureNode.ditherEvery` implies guiding/dithering.
  - Result: preflight won’t warn about missing guider/PHD2 for “dither every N frames” exposures.
- `MeridianFlipNode.requiredDevices` is `{mount}` even though:
  - `pauseGuiding == true` implies guiding/PHD2
  - `autoCenter == true` implies camera + plate solving + mount slews
- `ConditionalNode` has no `requiredDevices` override even though certain condition types (e.g., `guidingRmsBelow`, `hfrBelow`, `weatherSafe`, `safetyMonitorSafe`) require telemetry sources/devices.

Sources:
- `packages/nightshade_core/lib/src/models/sequence/sequence_models.dart` (`requiredDevices` overrides / omissions)
- `packages/nightshade_app/lib/screens/sequencer/widgets/preflight_validation_dialog.dart` (preflight uses `node.requiredDevices`)

### Filter fields are free-text (flexible, but easy to mismatch)
- Builder UI uses free-text for both exposure `filter` and filter-change `filterName`.
- **Driver risk**: if the driver reports filter names differently than what the user types, filter-change and filter-matching logic can fail at runtime.

Sources:
- `packages/nightshade_app/lib/screens/sequencer/widgets/node_properties_panel.dart` (`_ExposureProperties`, `_FilterChangeProperties`)

### Sequence import/export is local-file based and only partially supports node types
- `SequenceFileService` uses `file_selector` + `dart:io` `File` APIs to read/write JSON.
  - **Remote/mobile risk**: in a remote-control setup, these dialogs operate on the client filesystem, not the server.
- `_jsonToNode` only implements a subset of node types; unknown nodes will be dropped on import.

Source:
- `packages/nightshade_core/lib/src/services/sequence_file_service.dart`

### Sequencer preflight equipment validation is biased toward PHD2
- The preflight validator reads `backend.getConnectedDevices()` and then special-cases guider detection because “PHD2 is not in getConnectedDevices”.
- Given earlier findings, guider “connected” can be true without an actual PHD2 connection, and non-PHD2 guider connections don’t map to working guiding operations.

Source:
- `packages/nightshade_app/lib/screens/sequencer/widgets/preflight_validation_dialog.dart` (`_checkEquipment`)

### “Slew to Target” action always uses the first target group
- Toolbar “Slew to Target” always slews to `sequence.targetGroups.first`.
- **Workflow risk**: multi-target sequences and mosaics can have multiple target groups/panels; this action can be misleading and appear “broken” depending on the active target the user expects.

Source:
- `packages/nightshade_app/lib/screens/sequencer/widgets/sequence_toolbar.dart` (Slew button)

### Mosaic Wizard sequence generation bypasses `NightshadeBackend` for mosaic math + creates nodes with hidden capability requirements
- The Sequencer Mosaic Wizard uses `MosaicService`, which calls the generated `nightshade_bridge` API directly for mosaic panel math (`apiCalculateMosaicPanels`, `apiEstimateMosaicTime`, etc.), bypassing `NightshadeBackend`.
  - **Remote/client risk**: this couples mosaic generation to the presence/ABI of the native bridge on the UI side, even when the app is operating in “network backend” mode (client controlling a server).
- `createMosaicSequence()` generates a sequence containing `SlewNode` + optional `CenterNode` + optional `AutofocusNode` + optional `DitherNode` and a looped `ExposureNode` per panel.
  - **Driver/capability risk**: “center” implies plate-solve availability + mount supports slew/sync workflow; autofocus implies focuser + camera capabilities; dithering implies guiding provider (currently PHD2-only).
  - This also creates target group `rotation` metadata, which can be interpreted as a “needs rotator” expectation in UX even if you aren’t actually rotating.
- The wizard uses hard-coded default exposure parameters (60s × 10) and a fixed overhead-per-panel estimate, rather than reading current camera settings/capabilities.

Sources:
- `packages/nightshade_app/lib/screens/sequencer/widgets/mosaic_wizard_dialog.dart`
- `packages/nightshade_core/lib/src/services/mosaic_service.dart`

### Flat Wizard dialog is currently a UI stub; real calibration logic exists but has cross-driver assumptions
- The Sequencer `FlatWizardDialog` currently:
  - Uses a hard-coded filter list (`['L','R','G','B','Ha','OIII','SII']`)
  - Simulates calibration with a fixed “calculated exposure” placeholder
  - Does not generate or inject any real sequence nodes / does not interact with camera, filter wheel, flat panel, cover calibrator, etc.
- `FlatWizardService` (core) exists and *does* use `NightshadeBackend`, but has several assumptions that can break across drivers:
  - Uses fixed `gain: 0` / `offset: 0` when capturing test frames (`cameraStartExposure`) rather than the camera’s current gain/offset or nulls.
  - “Filter change” is not performed; the service just delays and expects the caller to have moved the filter wheel already.
  - Waits for exposure completion with `Future.delayed(exposure + 1s)` and then calls `cameraGetLastImage()`; drivers with longer download/readout times or async pipelines can race here.
  - Requires that `cameraGetLastImage()` returns image statistics (mean ADU) consistently across all backends/drivers.

Sources:
- `packages/nightshade_app/lib/screens/sequencer/widgets/flat_wizard_dialog.dart`
- `packages/nightshade_core/lib/src/services/flat_wizard_service.dart`

### Sequencer Equipment status widget hard-codes `DriverType.ascom` + uses inconsistent IDs
- `connectedDevicesProvider` builds a `List<DeviceInfo>` from individual device state providers but:
  - Hard-codes `driverType: DriverType.ascom` for every device, regardless of actual backend/driver.
  - Uses `deviceName` as the `DeviceInfo.id` for focuser/filter wheel/guider (camera/mount use `deviceId`), which can diverge from the real identifier used for backend operations.
- **Driver-agnostic risk**: status displays will be misleading for Alpaca/INDI/Native; any logic that relies on these `DeviceInfo` values will be incorrect for non-ASCOM and potentially incorrect even for ASCOM if name ≠ id.

Source:
- `packages/nightshade_app/lib/screens/sequencer/widgets/equipment_status_widget.dart` (`connectedDevicesProvider`)

### Sequencer progress panels depend on parsing human-readable status strings
- `node_progress_panels.dart` parses `progressDetail` strings with regex (e.g., extracting temperatures/power from text like `"Cooling: 15.2°C → -10.0°C (85% power)"`).
- **Backend parity risk**: if the native sequencer vs network sequencer emits different detail formats, or if units/wording change, these panels silently degrade or show incorrect values.
- **Recommendation direction**: prefer structured progress payloads (typed fields for temp/power/HFR/RMS/etc.) instead of regex over strings.

Source:
- `packages/nightshade_app/lib/screens/sequencer/widgets/node_progress_panels.dart`

---

## Planetarium + Framing screen findings

### Planetarium mount control is relatively clean (uses `DeviceService`), but assumes coordinate/epoch conventions
- Slew operations are routed through `deviceServiceProvider.slewMountToCoordinates(raHours, decDegrees)` and “Stop Slew” uses `deviceServiceProvider.abortMountSlew()`.
  - **Capability risk**: not all mount drivers implement “abort/stop slew” distinctly; this can throw at runtime without capability gating.
- `NightshadeBackend.mountSlewToCoordinates(deviceId, ra, dec)` has no explicit coordinate-system/epoch parameter.
  - **Driver/backend risk**: if a backend/driver expects apparent/JNow coordinates while the catalogs/planetarium use J2000, slews can be systematically off (especially at high declination / long sessions).
  - This risk is amplified because the Planetarium can slew from tapped sky positions (“slew mode”), which users expect to be exact.

Sources:
- `packages/nightshade_app/lib/screens/planetarium/planetarium_screen.dart` (`_handleSlewToTarget`, `_handleSlewToCoordinates`, `_handleStopSlew`)
- `packages/nightshade_core/lib/src/services/device_service.dart` (`slewMountToCoordinates`, `abortMountSlew`)
- `packages/nightshade_core/lib/src/backend/nightshade_backend.dart` (`mountSlewToCoordinates`)

### Planetarium FOV overlay is not wired to real equipment specs (only rotator angle is synced)
- Planetarium updates `equipmentFOVProvider.rotation` from `rotatorStateProvider.position`, but I did not find any app-side wiring that sets:
  - `equipmentFOVProvider.camera` (sensor size / pixel size)
  - `equipmentFOVProvider.telescope` (focal length)
- **Impact**: “Toggle FOV Overlay” can be enabled in UI but still render nothing (or render with null/placeholder specs), which can appear driver-dependent (“works on my setup”) if you happen to have other code paths setting it.

Sources:
- `packages/nightshade_app/lib/screens/planetarium/planetarium_screen.dart` (rotator sync)
- `packages/nightshade_planetarium/lib/src/providers/planetarium_providers.dart` (`EquipmentFOVState`)

### Framing FOV computation bypasses `NightshadeBackend` and is ASCOM-biased
- `framingFOVProvider` attempts to query real camera sensor specs when a camera is connected, but it does so via a direct FFI call:
  - `bridge.NativeBridge.getCameraStatus(profile.cameraId!)`
  - **Backend-agnostic break**: this bypasses `NightshadeBackend` (so it won’t work correctly in network-backend mode, and it ties the UI to local native libs even when controlling a remote server).
  - **Mismatch risk**: it checks `cameraState.connectionState == connected` but does not verify that the connected camera corresponds to `profile.cameraId`.
- Camera naming assumes ASCOM-like identifiers:
  - `_extractDeviceName()` splits on `.` and takes the last segment, and comments explicitly call out ASCOM IDs.
  - **Cross-driver risk**: Alpaca/INDI/Native IDs may not contain dots or may use different structured IDs; display names will be inconsistent and can leak ASCOM assumptions into UX.
- On failure it silently falls back to “APS‑C default” sensor specs.
  - **Agnosticism risk**: FOV/mosaic planning accuracy becomes dependent on whether the local bridge can successfully query the *specific* connected camera implementation; many cameras (or remote usage) will show incorrect framing.

Sources:
- `packages/nightshade_core/lib/src/providers/framing_provider.dart` (`framingFOVProvider`, `_extractDeviceName`)
- `packages/nightshade_app/lib/screens/framing/framing_screen.dart` (consumes `framingFOVProvider`)

### Framing depends on external astronomy web services with certificate-bypass logic
- `SimbadResolver` and survey image fetching use `dart:io` `HttpClient` with `badCertificateCallback` to bypass certificate verification for a hard-coded allowlist of “trusted astronomy domains”.
- **Operational risk**: this is a security trade-off and can behave differently across platforms/backends (mobile vs desktop), and it’s orthogonal to driver type.

Source:
- `packages/nightshade_core/lib/src/providers/framing_provider.dart` (trusted domains + custom HTTP client)

---

## Flat Wizard screen findings

### Flat Wizard uses fixed gain/offset/binning and relies on `cameraGetLastImage()` stats for ADU
- Test exposures and auto-tuning call `backend.cameraStartExposure(..., frameType: flat, gain: 0, offset: 0, binX: 1, binY: 1)` and then read `backend.cameraGetLastImage()` to compute `image.stats.mean`.
  - **Driver/capability risk**:
    - Some cameras/drivers don’t support gain/offset (or reject `0`), and many require per-camera ranges.
    - Some backends may not compute/return image statistics consistently (mean ADU), especially if the camera produces raw frames without stats.
    - Fixed `Future.delayed(exposure + 500ms)` can race with download/readout times across drivers.

Sources:
- `packages/nightshade_app/lib/screens/flat_wizard/flat_wizard_screen.dart` (`captureTestFrame`, `autoTuneExposure`)

### Filter wheel control likely uses the wrong identifier (`deviceName` instead of `deviceId`)
- Filter changes call `backend.filterWheelSetPosition(filterState.deviceName!, filterIndex)` in multiple places.
  - `FilterWheelState` has both `deviceId` and `deviceName`; using `deviceName` as the backend identifier will fail whenever name ≠ id (and is especially risky for non-ASCOM backends and network mode).
- Connection checks are also name-based (`deviceName != null`) instead of using `connectionState == connected` + non-empty `deviceId`.

Sources:
- `packages/nightshade_app/lib/screens/flat_wizard/flat_wizard_screen.dart` (filter change logic)
- `packages/nightshade_core/lib/src/models/equipment/equipment_models.dart` (`FilterWheelState.deviceId/deviceName`)

### Flat panel / cover calibrator “panel control” is UI-only (no device integration)
- The UI exposes “Flat Panel Control” (enable + brightness slider) and stores `panelBrightness`/`usePanelControl` in state, but there are no backend calls to:
  - Turn on/off a flat panel (switch/cover calibrator)
  - Set brightness (cover calibrator brightness)
- **Driver-agnostic gap**: this feature surface implies support for flat panels/cover calibrators, but nothing is executed against ASCOM/Alpaca/INDI/Native device APIs.

Source:
- `packages/nightshade_app/lib/screens/flat_wizard/flat_wizard_screen.dart` (`FlatWizardState`, `_PanelControlSection`, `startCapture`)

### Capture loop does not persist frames or adapt exposure during batch runs
- `startCapture()` iterates plans and calls `cameraStartExposure()` repeatedly, but does not:
  - Save frames to disk (no explicit save/export step)
  - Re-check ADU per frame to adapt exposure/panel brightness (important for sky flats as brightness changes quickly)
- The “Live Preview” widget is currently a placeholder (no image rendering).

Source:
- `packages/nightshade_app/lib/screens/flat_wizard/flat_wizard_screen.dart` (`startCapture`, `_LivePreviewWidget`)

---

## Weather screen findings

### Weather UI is driven by external radar/cloud APIs, not by connected “weather device” drivers
- The Weather screen uses:
  - `WeatherRadarService` (GOES/NOAA/RainViewer/OpenMeteo overlays)
  - `cloudCoverPercentageProvider` (Open‑Meteo “current cloud_cover”)
  - `CloudMotionAnalyzer` + `WeatherAlertService` to produce alerts
- It does **not** consume `weatherStateProvider` (hardware weather/observing-conditions device telemetry) or `safetyMonitorStateProvider`.
- **Driver-agnostic gap**: users with ASCOM/Alpaca/INDI weather stations (ObservingConditions) won’t see their hardware values reflected in the Weather tab or alerts; conversely, Weather tab behavior depends on internet availability rather than driver capability.

Sources:
- `packages/nightshade_app/lib/screens/weather/weather_screen.dart` (uses `weatherStatusProvider`, `cloudCoverPercentageProvider`, `analyzeCloudMotionProvider`, `evaluateWeatherConditionsProvider`)
- `packages/nightshade_core/lib/src/providers/weather_providers.dart`
- `packages/nightshade_core/lib/src/providers/equipment_provider.dart` (`weatherStateProvider`, `safetyMonitorStateProvider`)

### Weather safety evaluation is UI-driven; global banner does not trigger periodic re-evaluation
- `WeatherScreen` refreshes radar/motion/alerts every 5 minutes by invalidating providers.
- The global `WeatherAlertBanner` is mounted in the app shell, but it only watches `weatherSafetyProvider` and does **not** trigger evaluation itself.
- `WeatherSafetyNotifier` listens to `weatherAlertService.alertStream`, but alerts are only emitted when `evaluateWeatherConditionsProvider` runs (currently only watched by the Weather screen).
- **Result**: unless something else in the app starts watching `evaluateWeatherConditionsProvider`, weather safety can remain in its initial “clear/safe” state even while conditions are unsafe.

Sources:
- `packages/nightshade_app/lib/screens/weather/weather_screen.dart` (`_refreshWeatherData`, periodic timer)
- `packages/nightshade_app/lib/widgets/weather/weather_alert_banner.dart`
- `packages/nightshade_app/lib/screens/shell/app_shell.dart` (banner placement)
- `packages/nightshade_core/lib/src/providers/weather_providers.dart`
- `packages/nightshade_core/lib/src/providers/weather_safety_provider.dart`

### Fail-open behavior can silently mark weather “safe” when APIs fail
- `cloudCoverPercentageProvider` returns `null` on any HTTP/parse error; `evaluateWeatherConditionsProvider` then treats density as `0.0` (“clear”).
- `weatherRadarFramesProvider` returns an empty frame list on fetch failure rather than throwing.
- **Safety implication**: loss of network connectivity or upstream API breakage can suppress alerts (appearing “safe”) rather than surfacing a degraded/unknown safety status.

Source:
- `packages/nightshade_core/lib/src/providers/weather_providers.dart` (`cloudCoverPercentageProvider`, `weatherRadarFramesProvider`, `evaluateWeatherConditionsProvider`)

### Sequencer “WeatherSafe” / “SafetyMonitorSafe” conditionals are stubbed in the native executor
- In the native sequencer, conditional checks are currently implemented as:
  - `ConditionalCheck::WeatherSafe` → `true` (always passes)
  - `ConditionalCheck::SafetyMonitorSafe` → `true` (always passes)
- **Driver-agnostic + safety risk**: sequences that include “Weather Safe” / “Safety Monitor Safe” conditionals will *not* actually gate execution on real sensors today.

Source:
- `native/nightshade_native/sequencer/src/node.rs` (`execute_conditional`)

### Native “WeatherUnsafe” trigger is wired to SafetyMonitor checks and is fail-open
- The native trigger loop updates `TriggerState.weather_safe` by calling `DeviceOps.safety_is_safe(None)`.
  - In `UnifiedDeviceOps`, `safety_is_safe(None)` attempts to resolve a device ID from the current profile’s `weather_id` and then calls the device manager’s safety check.
  - On errors, it logs and returns `Ok(true)` (“assume safe / fail-open”).
- **Driver-agnostic risk**:
  - There is no dedicated `safety_monitor_id` in the profile model; the code uses `weather_id`, which is ambiguous given Nightshade also supports *Weather* devices separately.
  - On any backend/driver error, the system defaults to “safe”, which can prevent `WeatherUnsafe` triggers from firing.

Sources:
- `native/nightshade_native/sequencer/src/executor.rs` (trigger loop calls `safety_is_safe(None)`)
- `native/nightshade_native/sequencer/src/triggers.rs` (`TriggerType::WeatherUnsafe`)
- `native/nightshade_native/bridge/src/unified_device_ops.rs` (`safety_is_safe`)
- `packages/nightshade_core/lib/src/models/equipment_profile.dart` (profile has `weatherId` but no safety monitor id)

---

## Analytics screen findings

### Analytics is tied to the local Drift database, not `NightshadeBackend` (remote mode will be incomplete by default)
- Analytics reads sessions/images from local Drift providers (`allSessionsProvider`, `imagesDaoProvider.watchImagesForSession`).
- Session export writes files to the local app documents directory.
- **Driver/backend-agnostic gap**: in a “mobile client controlling desktop server” topology, analytics will reflect whatever is stored locally on the client, not necessarily what happened on the server (unless you explicitly replicate session/image rows over the network).

Sources:
- `packages/nightshade_app/lib/screens/analytics/analytics_screen.dart` (`allSessionsProvider`, `sessionImagesProvider`, export actions)
- `packages/nightshade_core/lib/src/providers/database_provider.dart` (`allSessionsProvider`)
- `packages/nightshade_core/lib/src/services/session_export_service.dart`

### Metric availability depends on hardware capabilities and backend telemetry; missing fields silently become “No data”
- Charts derive points from optional image fields:
  - HFR: `CapturedImage.hfr` (accepted images only)
  - Temperature: `CapturedImage.sensorTemp`
  - Guiding RMS: `CapturedImage.guidingRmsTotal`
  - Focuser: `CapturedImage.focuserPosition`
- These are only populated if:
  - The backend provides image statistics (HFR/star count/etc)
  - The camera reports temperature (many do, some don’t)
  - Guiding telemetry is available (often PHD2-only in this codebase)
  - Focuser telemetry is available
- **Driver-agnostic note**: this is “soft-failing” (charts show “No data”), but it can hide capability gaps unless you explicitly surface “unsupported / not available for this driver/device”.

Sources:
- `packages/nightshade_app/lib/screens/analytics/widgets/session_chart.dart` (field selection)
- `packages/nightshade_core/lib/src/services/imaging_service.dart` (`_saveToDatabase` populates many of these fields from equipment state + image stats)

### Session charts may behave poorly with a single datapoint (zero ranges/intervals)
- `SessionChart` computes `yRange = dataMaxY - dataMinY`, then uses `yRange / 4` for grid/title intervals and pads by `yRange * 0.1`.
- With 1 point, `yRange == 0`, which yields:
  - `horizontalInterval: 0`
  - `leftTitles.interval: 0`
  - `bottomTitles.interval: spots.last.x / 4` where `spots.last.x == 0`
- Depending on `fl_chart` behavior, this can cause rendering glitches or runtime errors.

Source:
- `packages/nightshade_app/lib/screens/analytics/widgets/session_chart.dart` (`SessionChart.build`)

### Image thumbnails assume local file paths are valid on the current machine
- `ImageThumbnailStrip` checks `File(image.filePath).exists()` and shows a “broken image” icon otherwise.
- **Cross-platform / remote risk**:
  - Paths produced on a Windows host (e.g., `C:\...`) won’t exist on a Linux/macOS client.
  - In remote mode, paths likely refer to server-local storage, not accessible on the client.
- Result: Analytics thumbnails will often show “missing” even when the image exists on the capture host.

Source:
- `packages/nightshade_app/lib/screens/analytics/widgets/image_thumbnail_strip.dart`

### History tab UX is currently partially stubbed (hard-coded target filter values)
- The “Target” filter dropdown is hard-coded to `['All Targets', 'M31', 'M42', 'NGC 7000']` rather than being derived from actual session/target data.
- This isn’t a driver issue, but it’s a correctness gap that can hide real data partitioning problems (e.g., missing target IDs across backends).

Source:
- `packages/nightshade_app/lib/screens/analytics/analytics_screen.dart` (`_HistoryTabState`)

---

## Settings screen findings

### Settings are split between two unrelated `AppSettings` models (high risk for remote mode + capability config)
- The UI “Settings” screens use `appSettingsProvider` (`packages/nightshade_core/lib/src/providers/settings_provider.dart`), which persists to the local Drift settings table on **the device running the UI**.
- Separately, `NightshadeBackend` defines `getSettings()/updateSettings()` using a different model type (`packages/nightshade_core/lib/src/models/settings/app_settings.dart`) intended for the **capture host/server**.
- **Driver/backend-agnostic gap**: there is no general sync path from UI settings → backend settings (except observer location), so many settings that users expect to affect device operations will not apply when the UI is connected to a remote server.

Sources:
- `packages/nightshade_app/lib/screens/settings/settings_screen.dart` (`appSettingsProvider`)
- `packages/nightshade_core/lib/src/providers/settings_provider.dart` (local persisted `AppSettings`)
- `packages/nightshade_core/lib/src/models/settings/app_settings.dart` (backend `AppSettings`)
- `packages/nightshade_core/lib/src/backend/nightshade_backend.dart` (`getSettings`, `updateSettings`)
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (`getSettings`, `updateSettings`)

### Remote mode: Plate-solving, PHD2, and “file paths” are configured locally, but execution/storage are on the capture host
- **Plate solving**: Settings UI edits `plateSolver`, `astapPath`, `astrometryPath`, `plateSolveTimeout`, etc. These are stored locally, but:
  - Local mode (FFI) uses native code (`api_plate_solve*`) which likely needs paths/config on the same machine as the native runtime.
  - Remote mode (NetworkBackend) performs plate solving on the server (`POST /api/plate-solve`), so the server needs the solver + its configuration.
- **PHD2**: Settings UI edits `phd2Host/phd2Port/phd2Path` locally, but remote guiding operations are executed on the server (`POST /api/phd2/*`), so the host/port/path need to apply to the server environment.
- **File paths** (`imageOutputPath`, `sequencesPath`, `databasePath`, `logsPath`) are stored locally via `appSettingsProvider`, but in remote mode the “real” database/images/logs exist on the server. This creates the same symptom seen in Analytics: server-local paths won’t exist on the client.
- Net effect: a “mobile client controlling a desktop server” topology can be configured into a self-inconsistent state where Settings say “configured”, but the capture host is still using defaults/unconfigured paths.

Sources:
- `packages/nightshade_app/lib/screens/settings/settings_screen.dart` (Plate Solving, PHD2, File Paths pages)
- `packages/nightshade_core/lib/src/providers/settings_provider.dart` (where these values actually persist)
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (`plateSolve`, `phd2*` use server APIs)
- `native/nightshade_native/bridge/src/api.rs` (`api_plate_solve_*` is executed on the native runtime host)

### Connection settings “Connect” action is currently a no-op
- `_ConnectionSettings` renders a “Connect to Server” button when disconnected, but `_handleConnectionAction()` only implements the disconnect case.
- This is not directly a driver issue, but it impacts driver-agnostic adoption because it blocks the primary “remote control” topology from within Settings.

Source:
- `packages/nightshade_app/lib/screens/settings/settings_screen.dart` (`_handleConnectionAction`)

### Location is an exception: it *is* synced to the backend
- Changing latitude/longitude/elevation via Settings updates `appSettingsProvider`, and `locationSyncProvider` pushes the location into `NightshadeBackend.setLocation(...)`.
- In NetworkBackend mode, this becomes `POST /api/settings/location` (i.e., it updates the server).
- This is the correct pattern for other “host-executed” settings (plate solve, PHD2, file paths) but it currently exists only for observer location.

Sources:
- `packages/nightshade_app/lib/services/location_sync_service.dart` (`locationSyncProvider`, `backend.setLocation`)
- `packages/nightshade_app/lib/screens/settings/settings_screen.dart` (Location page)
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (`setLocation`)

### Pairing/Backup/Catalog tools are local-first and don’t obviously cover “server state”
- `PairingScreen` uses `nightshade_webrtc` token storage and pairing DB, but it does not interact with `backendProvider`/`NetworkBackend` at all. Meanwhile `NetworkBackend`’s WebSocket connection is unauthenticated (`ws://.../events`), and only HTTP requests optionally include an `Authorization` header.
- `BackupScreen` uses `backupServiceProvider` and local file pickers. In remote mode it will back up the **client’s** data, not the server’s database/images/config (unless you explicitly add server-side backup endpoints and plumb them here).
- `CatalogSettingsScreen` downloads/imports catalogs into the local filesystem (planetarium assets); in a remote topology, this may be expected to live on the capture host instead.

Sources:
- `packages/nightshade_app/lib/screens/settings/pairing_screen.dart`
- `packages/nightshade_app/lib/screens/settings/backup_screen.dart`
- `packages/nightshade_app/lib/screens/settings/catalog_settings_screen.dart`
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (WebSocket connect has no auth; HTTP has optional auth)

---

## Polar Alignment screen findings

### `polarAlignmentEvents` is never emitted by any backend (UI cannot receive updates)
- `PolarAlignmentScreen` listens to `backend.polarAlignmentEvents`.
- Both `FfiBackend` and `NetworkBackend` expose `polarAlignmentEvents` via a dedicated `StreamController`, but neither backend ever `add()`s to that controller.
- The Rust implementation publishes polar alignment updates on the *main* event bus with `EventCategory::PolarAlignment` (`EventPayload::PolarAlignment*`), which *does* arrive via `eventStream` (FFI) / WebSocket events (network).
- **Driver/backend-agnostic gap**: Polar Alignment works only if you happen to run a host/backend that emits the correct events *and* your UI listens to the correct stream; right now those don’t line up, so the feature can’t be relied upon across backends/drivers.

Sources:
- `packages/nightshade_app/lib/screens/polar_alignment/polar_alignment_screen.dart` (subscribes to `backend.polarAlignmentEvents`)
- `packages/nightshade_core/lib/src/backend/ffi_backend.dart` (`polarAlignmentEvents` is defined but never fed)
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (`polarAlignmentEvents` is defined but never fed)
- `native/nightshade_native/bridge/src/api.rs` (publishes `EventCategory::PolarAlignment` events)

### `PolarAlignmentScreen._handlePolarAlignEvent` has a Dart `switch` with no `break`s (compile-time error)
- The `switch (phase)` statement does not `break`/`return`/`continue`, which should fail Dart compilation.
- This is not a driver issue per se, but it prevents the feature from being shippable regardless of driver/backend.

Source:
- `packages/nightshade_app/lib/screens/polar_alignment/polar_alignment_screen.dart` (`_handlePolarAlignEvent`)

### The UI advertises controls that are not actually used by the backend implementation
- The UI exposes `solve timeout`, `start from current vs pole`, and optional `gain/offset`, but:
  - `gain/offset` are declared and never referenced.
  - `solve timeout` and `start from` are not passed into `startPolarAlignment(...)`.
  - Native code uses fixed 60s/30s timeouts and always blind-solves.
- Result: user expectations vary by driver/device (different cameras require different gain/binning/exposure), but the implementation is fixed and can’t be tuned from the UI.

Sources:
- `packages/nightshade_app/lib/screens/polar_alignment/polar_alignment_screen.dart` (UI options + `startPolarAlignment` call)
- `native/nightshade_native/bridge/src/api.rs` (`run_polar_alignment` hard-coded gain/offset + timeouts)

### Native polar alignment algorithm contains driver-sensitive assumptions (not capability-gated)
- Uses `api_camera_start_exposure(... gain=0, offset=0)` as “auto”; many camera drivers interpret 0 as a real value, not “auto”.
- Waits a fixed `exposure_time + 2s` instead of waiting on exposure-complete / download-complete events; slower cameras/drivers will intermittently fail.
- Uses `api_get_last_image()` (global last image) without selecting the camera instance; multi-camera rigs can race.
- Always calls `api_plate_solve_blind(...)` and uses fixed timeouts (60s initial, 30s adjustment) regardless of UI settings and regardless of whether a position hint is available.
- Mount rotation step uses `api_mount_slew_to_coordinates` by offsetting RA, which assumes:
  - The mount supports GoTo slews and is operating in equatorial RA/Dec mode.
  - Slewing by RA offset is a safe proxy for RA-axis rotation (meridian/pier limits are not checked here).
- Manual rotation mode is “sleep 15 seconds” (no explicit user confirmation / no verification that rotation happened).

Source:
- `native/nightshade_native/bridge/src/api.rs` (`run_polar_alignment`)

## Audit progress
- Inventory: **complete**
- Equipment screen: **complete**
- Imaging screen: **complete**
- Guiding screen: **complete**
- Sequencer screen: **complete**
- Planetarium + Framing: **complete**
- Flat Wizard: **complete**
- Weather: **complete**
- Analytics: **complete**
- Settings + Polar Alignment: **complete**
- Cross-cutting capabilities: **complete**

---

## Consolidated high-risk findings (what will most likely break for “other people’s rigs”)

### 1) Missing/implicit capability modeling causes hard failures (especially cameras)
- Across multiple screens, camera operations assume gain/offset/binning/ROI/cooling exist and accept specific numeric values.
- Some drivers/devices treat “0” as a real gain/offset, not “auto”.
- Downstream result: common user reports will look like “Nightshade doesn’t work with my camera/driver” when the actual issue is “workflow not capability-gated”.

### 2) Remote mode (mobile client → desktop server) is not consistently supported end-to-end
- Several UI features rely on local filesystem paths or local solver installs (ASTAP) and cannot work when images/solvers live on the server.
- Settings are split between a client-local provider and a smaller backend settings model; only observer location is reliably synced server-side.
- WebSocket events are unauthenticated in `NetworkBackend` and polar-alignment event plumbing is incomplete.

### 3) Profile/device identity confusion will mislead users in multi-device / multi-profile setups
- Many UI components treat “camera connected” as global state, not “profile’s camera connected”, because they don’t compare `state.deviceId` to `profile.*Id`.
- Some operations rely on `activeProfile.*Id` instead of the actually connected device id.
- This produces extremely confusing failure modes that users will interpret as driver instability.

### 4) Safety/weather automation is currently “fail-open” at critical points
- The native sequencer safety checks assume safe when no safety monitor is configured, and in some cases appear to query the wrong device type.
- Weather UI’s “safety actions” are not clearly enforced by the execution engine as written.

### 5) Polar Alignment is not shippable as-is
- UI subscribes to a backend stream that is never fed, and the event handler contains a Dart `switch` that should not compile.
- Native implementation uses fixed timeouts, blind-solve only, and fixed gain/offset assumptions.

---

## Recommendations (implementation direction, not code changes)

### Capability model + gating (top priority)
- Introduce explicit capability/range models per device type (camera: gain/offset/binning/roi/cooling ranges; mount: canSync/canPulseGuide/canSetTrackingRate; etc.).
- Populate these from each driver backend (ASCOM/Alpaca/INDI/native) and surface them through `NightshadeBackend` and/or device status.
- Update all workflows to:
  - Hide/disable unsupported controls.
  - Provide “Not supported by this device/driver” UX instead of generic exceptions.

### Enforce the backend abstraction boundary
- Treat `NightshadeBackend`/`DeviceService` as the only boundary from UI → device operations.
- Remove direct `nightshade_bridge` usage from UI code paths (it breaks remote mode immediately).

### Make profiles first-class in connection state
- Compare connected `state.deviceId` with profile-assigned ids when computing status.
- Consider per-profile “desired devices” vs “currently connected devices” state, and make mismatches explicit.

### Remote settings should be server-owned when they affect server execution
- Add clear separation between client preferences (UI theme, local notifications) and server runtime config (plate solver, PHD2, storage paths).
- Provide sync endpoints and a UI that clearly shows “this setting applies to server vs this device”.

### Safety should fail closed (or at least be user-configurable)
- Require explicit safety monitor configuration for safety-triggered behaviors, or provide a global “fail closed” option.
- Make trigger behavior explicit in UI (what will happen when weather/safety becomes unsafe).


