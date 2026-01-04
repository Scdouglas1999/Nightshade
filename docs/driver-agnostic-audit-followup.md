# Driver-Agnostic Audit — Follow-up (trimmed: remaining work only)

This document is intentionally **trimmed** to highlight only the **remaining driver-agnostic risks** that still need attention. Completed items are summarized briefly for historical context.

---

## Recently closed (since the previous follow-up)
- **FRB bindings/wrappers regenerated**: per-device image APIs now exist on the Dart side (`apiGetLastImage(deviceId)`, `apiGetLastRawImageData(deviceId)`, `apiClearDeviceImage(deviceId)`, `apiSaveFitsFromLastCapture(...)`).  
  Sources: `packages/nightshade_bridge/lib/src/api.dart`, `packages/nightshade_bridge/lib/src/frb_generated.dart`
- **Per-device last-image routing fixed on the server**: `/api/camera/last-image` handler now uses the passed `deviceId`.  
  Source: `apps/desktop/lib/main.dart`
- **Polar alignment is now end-to-end usable**:
  - FFI backend decodes polar payloads into the Map shape the UI expects.
  - UI passes tunables (`gain/offset/solveTimeout/startFromCurrent`) into `backend.startPolarAlignment(...)`.
  Sources: `packages/nightshade_core/lib/src/backend/ffi_backend.dart`, `packages/nightshade_app/lib/screens/polar_alignment/polar_alignment_screen.dart`
- **Profile/device mismatch is now explicitly surfaced** (no more “globally connected” lies):
  - Profile chips compute mismatch using `profile.*Id` vs `state.deviceId`.
  - Connection status zone also flags mismatches.
  Sources: `packages/nightshade_app/lib/screens/equipment/widgets/quick_connect_bar.dart`, `packages/nightshade_app/lib/screens/equipment/widgets/connection_status_zone.dart`
- **Camera cooling/disconnect now uses the connected `deviceId` (not profile)**.  
  Source: `packages/nightshade_core/lib/src/services/device_service.dart`
- **Title-bar “/profiles” broken route removed** (now routes to Settings).  
  Source: `packages/nightshade_app/lib/screens/shell/widgets/title_bar.dart`
- **Dart fallback sequencer no longer bypasses backend via direct bridge calls**.  
  Source: `packages/nightshade_core/lib/src/providers/sequence_provider.dart`

---

## Remaining action items (prioritized)

### P0 — Remote WebSocket events still won’t reach `NetworkBackend` (schema mismatch)
**Impact**: remote/mobile clients won’t get real-time equipment/imaging/sequencer/polar-alignment events, even though the server can now forward events.

What’s happening:
- Server (`NightshadeWebServer.setEventStream`) broadcasts WS messages containing **`payload`** (and wraps everything with `type: 'event'`).
- Client `NetworkBackend` connects to `ws://.../events` and tries to parse messages as `NightshadeEvent` **with `eventType` + `data`**.
- Result: JSON parse throws (missing `eventType`/`data`) and events are dropped.

Sources:
- Server: `apps/desktop/lib/main.dart` (event forwarding uses `'payload': _serializeEventPayload(event.payload)`), `packages/nightshade_webrtc/lib/src/web_server.dart` (`setEventStream` adds `type: 'event'`)
- Client: `packages/nightshade_core/lib/src/backend/network_backend.dart` (WS listener + `_eventFromJson`), `packages/nightshade_core/lib/src/models/backend/event_types.dart` (`NightshadeEvent.fromJson`)

What to do:
- Either **send `eventType` + `data`** over WS (server-side), or **teach `NetworkBackend` to decode the server payload schema** and convert into `(eventType, data)` locally.

---

### P1 — Guiding remains PHD2-only in practice
**Impact**: non-PHD2 guiders can appear “connected”, but guiding operations still route to PHD2 APIs.

Current behavior:
- `DeviceService.startGuiding/stopGuiding/dither` always call `_backend.phd2*` regardless of connected guider type.
- `phd2ConnectedProvider` still reports connected when *any* guider is connected (it does not check that the connected device is PHD2).

Sources:
- `packages/nightshade_core/lib/src/services/device_service.dart`
- `packages/nightshade_core/lib/src/providers/guiding_provider.dart`

What to do:
- Decide whether “Guider” is **PHD2-only** (then lock UI/profile selection to PHD2), or add a **driver-agnostic guiding API** (ASCOM/Alpaca/INDI guider operations) and route based on connected guider type.

---

### P1 — Mosaic generation still depends on local native bridge (remote mode risk)
**Impact**: mosaic math can fail on a pure-mobile client (or any client without the native library), and it’s not naturally backend-agnostic.

Sources:
- `packages/nightshade_core/lib/src/services/mosaic_service.dart` (`bridge.apiCalculateMosaicPanels(...)`)

What to do:
- Move mosaic math to pure Dart (recommended), or add a backend API and call it through `NightshadeBackend` in both FFI + Network modes.

---

### P1 — Safety fail mode is implemented in native sequencer, but errors may still be “fail-open” in practice
**Impact**: “FailClosed” can be bypassed if lower layers swallow errors.

Notes:
- Rust sequencer now supports `SafetyFailMode` and applies it when `safety_is_safe()` returns `Err`.
  - Source: `native/nightshade_native/sequencer/src/node.rs`, `native/nightshade_native/sequencer/src/executor.rs`
- However, `UnifiedDeviceOps::safety_is_safe` still returns `Ok(true)` on errors, which prevents the sequencer from applying fail-mode logic.
  - Source: `native/nightshade_native/bridge/src/unified_device_ops.rs`

What to do:
- Stop swallowing errors in `safety_is_safe` (return `Err` and let the sequencer apply fail mode), and confirm you’re querying the correct device ID (weather vs safety monitor).

---

### P2 — Capability gating is incomplete (binning + exposure params)
**Impact**: UI can still offer settings that certain drivers/devices don’t support, creating “works on my rig” risk.

Known gap:
- Binning dropdown is still hard-coded (`1x1..4x4`) and does not use `maxBinX/maxBinY` or `canBin`.

Sources:
- UI: `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart`
- Backend caps surface: `packages/nightshade_core/lib/src/providers/capability_provider.dart`

Also consider:
- `NightshadeBackend.cameraStartExposure(...)` still requires `gain` and `offset` even for cameras that can’t set them.
  - Source: `packages/nightshade_core/lib/src/backend/nightshade_backend.dart`

---

### P2 — Unified discovery matching risk (multi-device rigs)
**Impact**: two identical devices can still be merged into one `UnifiedDevice`.

Source:
- `packages/nightshade_core/lib/src/services/device_matching_service.dart`

---

### P3 — Recommended backend selection remains static, not capability-aware
**Impact**: user may end up on a backend that can’t support a chosen workflow even when an alternate backend for the same physical device could.

Source:
- `packages/nightshade_core/lib/src/models/equipment/unified_device.dart`

---

### P3 — Weather screen still appears “internet weather first”
**Impact**: users with hardware weather/safety devices may not see those values as first-class in the UI.

Source:
- `packages/nightshade_app/lib/screens/weather/weather_screen.dart`

