# Nightshade P0 Remediation Tracker

Last updated: 2026-03-13
Source: `report/nightshade_audit_report.md` section 12.20

Purpose: persist the exact P0 remediation set, current status in the working tree, implementation targets, and verification notes so work can continue cleanly after context compaction.

Status legend:
- `fixed-in-tree`: confirmed fixed in the current worktree
- `in-progress`: actively being implemented in this pass
- `open`: confirmed still open
- `needs-verification`: not yet re-audited deeply enough to claim fixed

## P0 Task List

| Task ID | Area | Audit Item | Status | Primary files | Verification notes |
|---|---|---|---|---|---|
| P0-001 | Sequencer astro math | Fix HA conversion in 4 locations: `(ha * 15.0).to_radians()` | `fixed-in-tree` | `native/nightshade_native/sequencer/src/node.rs`, `native/nightshade_native/sequencer/src/meridian.rs` | Current tree already contains corrected hour-angle conversion. |
| P0-002 | Sequencer astro math | Fix GMST -> LST longitude correction for meridian flip | `fixed-in-tree` | `native/nightshade_native/sequencer/src/meridian_flip_executor.rs` | Current tree already applies longitude correction before HA calculation. |
| P0-003 | Database scheduling | Fix target scheduling degree normalization in `TargetsDao` | `fixed-in-tree` | `packages/nightshade_core/lib/src/database/daos/targets_dao.dart` | Current tree uses `_normalizeLst` and `_normalizeHa` with correct ranges. |
| P0-004 | Safety | Fail closed: `TriggerState.weather_safe` defaults false | `fixed-in-tree` | `native/nightshade_native/sequencer/src/triggers.rs` | `TriggerState::new()` now sets `weather_safe: false`. |
| P0-005 | Safety | INDI weather `Unknown` must be unsafe | `fixed-in-tree` | `native/nightshade_native/indi/src/weather.rs` | `IndiWeatherStatus::Unknown => false` confirmed. |
| P0-006 | Device persistence | Persist ASCOM rotator objects instead of connect/drop per call | `fixed-in-tree` | `native/nightshade_native/bridge/src/devices.rs`, `native/nightshade_native/bridge/src/ascom_wrapper_rotator.rs` | DeviceManager now stores persistent ASCOM rotator wrappers and reuses them for connect, disconnect, position, move, halt, and motion checks. `cargo test -p nightshade_bridge --lib` passed with bundled `libraw.dll` on `PATH`. |
| P0-007 | Device persistence | Persist ASCOM weather and safety monitor objects instead of connect/drop per call | `fixed-in-tree` | `native/nightshade_native/bridge/src/devices.rs`, `native/nightshade_native/bridge/src/ascom_wrapper_weather.rs`, `native/nightshade_native/bridge/src/ascom_wrapper_safetymonitor.rs` | DeviceManager now stores persistent ASCOM weather and safety wrappers and reuses them for connect, disconnect, condition reads, and safety checks. `cargo test -p nightshade_bridge --lib` passed with bundled `libraw.dll` on `PATH`. |
| P0-008 | FFI memory safety | Replace unsafe u8->u16 pointer cast in debayer path | `fixed-in-tree` | `native/nightshade_native/bridge/src/api.rs` | Current tree validates even byte count and converts via `chunks_exact(2)`. |
| P0-009 | FFI crash safety | Guard calibration file path usage individually in FITS calibration | `fixed-in-tree` | `native/nightshade_native/bridge/src/api.rs` | Original unconditional unwrap path no longer present in current tree. |
| P0-010 | Mobile runtime safety | Remove `block_in_place` from INDI camera/filter wheel timeout helpers | `fixed-in-tree` | `native/nightshade_native/indi/src/camera.rs`, `native/nightshade_native/indi/src/filterwheel.rs` | Replaced with normal async `RwLock` reads. `cargo test -p nightshade_indi --lib` passed. |
| P0-011 | HTTP client safety | Remove Alpaca HTTP client constructor panic on TLS/client build failure | `fixed-in-tree` | `native/nightshade_native/alpaca/src/client.rs` | Constructor now stores initialization failure and returns typed errors instead of panicking. `cargo test -p nightshade_alpaca --lib` passed. |
| P0-012 | Imaging memory safety | Remove LibRaw parameter memory scan UB | `fixed-in-tree` | `native/nightshade_native/imaging/src/raw.rs`, `native/nightshade_native/imaging/src/libraw_shim.c`, `native/nightshade_native/imaging/vendor/libraw/*` | Rust no longer scans `libraw_data_t` memory. A local C shim, compiled against vendored LibRaw 0.21.4 headers matching the bundled DLL, applies output parameters through the supported ABI. |
| P0-013 | Imaging memory safety | Copy LibRaw processed image using actual `data_size` semantics | `fixed-in-tree` | `native/nightshade_native/imaging/src/raw.rs` | The 16-bit and 8-bit paths now validate `img.data_size` against the expected sample count before copying. |
| P0-014 | Imaging correctness | Fix live stacking inverse affine translation math | `fixed-in-tree` | `native/nightshade_native/imaging/src/stacking.rs` | The current inverse uses `R^-1(ref - t)`, which is mathematically correct; a new rotation+translation regression test now locks that in. |
| P0-015 | Filter correctness | Fix filter-by-name 0-based vs 1-based position handling | `fixed-in-tree` | `native/nightshade_native/bridge/src/unified_device_ops.rs`, `native/nightshade_native/bridge/src/real_device_ops.rs` | Current tree branches on INDI 1-based vs others 0-based / 1-based mapping as appropriate. |
| P0-016 | Sequencer counters | Remove duplicate `progress_callback` exposure counting | `fixed-in-tree` | `native/nightshade_native/sequencer/src/instructions.rs` | Only one completed-exposure callback remains in current tree. |
| P0-017 | Driver safety | Prevent INDI mount from remaining in SLEW mode after partial failure | `fixed-in-tree` | `native/nightshade_native/indi/src/mount.rs` | Slew paths now snapshot the prior `ON_COORD_SET` mode and best-effort restore it if the coordinate write fails after switching to `SLEW`. `cargo test -p nightshade_indi --lib` passed. |
| P0-018 | Data loss | Make generated image save paths collision-safe | `fixed-in-tree` | `packages/nightshade_core/lib/src/services/imaging_service.dart`, `native/nightshade_native/sequencer/src/instructions.rs` | Dart imaging save path now de-dupes by suffix before save. Sequencer save path now does the same. Dart imaging/session tests passed; Rust package verification blocked by pre-existing imaging compile error. |
| P0-019 | Silent failure | Replace flat wizard filter-wheel placeholder delay with real completion handling | `fixed-in-tree` | `packages/nightshade_core/lib/src/services/flat_wizard_service.dart` | Current tree waits for actual exposure completion and performs real filter change calls. |
| P0-020 | Session recovery | Fix checkpoint timer interval update comparison | `fixed-in-tree` | `packages/nightshade_core/lib/src/services/session_service.dart` | Current tree compares against `previousInterval` captured before `_config = config`. |
| P0-021 | Focus settings persistence | Prevent `focusSettingsProvider` reset on unrelated settings saves | `fixed-in-tree` | `packages/nightshade_core/lib/src/providers/imaging_provider.dart` | Current tree uses `FocusSettingsNotifier` with one-time initialization. |
| P0-022 | Profile sync | Reload filter offsets when active profile changes | `fixed-in-tree` | `packages/nightshade_core/lib/src/providers/filter_offset_provider.dart` | Current tree listens to `activeEquipmentProfileProvider`. |
| P0-023 | Polar alignment latency | Remove extra post-exposure sleep in polar alignment workflow | `fixed-in-tree` | `native/nightshade_native/bridge/src/api.rs` | Removed redundant `sleep(exposure_time + 2.0)` after blocking exposure calls. Bridge verification currently blocked by pre-existing imaging compile error. |
| P0-024 | Plate solve races | Replace fixed temp FITS filenames with unique per-operation paths | `fixed-in-tree` | `native/nightshade_native/bridge/src/sequencer_ops.rs`, `native/nightshade_native/bridge/src/unified_device_ops.rs`, `native/nightshade_native/bridge/src/api.rs` | Added shared unique temp FITS path helper and switched plate-solve / polar-align temp files to use it. Bridge verification currently blocked by pre-existing imaging compile error. |

## Current Implementation Batch

Completed in this pass:

- `P0-010` remove INDI `block_in_place` mobile panic path
- `P0-011` remove Alpaca client constructor panic path
- `P0-006` persist ASCOM rotator wrapper objects
- `P0-007` persist ASCOM weather and safety monitor wrapper objects
- `P0-012` replace LibRaw parameter scan with header-backed C shim
- `P0-013` validate LibRaw processed image copies against `data_size`
- `P0-014` verify and lock in correct live-stacking inverse transform math
- `P0-017` restore INDI `ON_COORD_SET` mode on partial slew failure
- `P0-018` make image save paths collision-safe
- `P0-023` remove polar alignment double-wait
- `P0-024` make temp FITS paths unique for concurrent plate solving

## Verification Log

- `cargo test -p nightshade_alpaca -p nightshade_indi --lib`: passed
- `cargo test -p nightshade_imaging stacking::tests::test_apply_transform_bilinear_rotation_and_translation --lib`: passed
- `cargo test -p nightshade_bridge --lib` with `libraw.dll` directory prepended to `PATH`: passed
- `flutter test test/services/imaging_service_test.dart test/services/session_service_test.dart`: passed
- `cargo test -p nightshade_imaging --lib`: compiles and runs, but still has two pre-existing FITS test failures in `imaging/src/fits.rs`
- `cargo test -p nightshade_sequencer --lib`: runs, but still has one pre-existing non-P0 failure in `sequencer/src/focus_prediction.rs::test_filter_offsets`

## Remaining Non-P0 Test Debt

The P0 set from audit section 12.20 is complete in the current tree. Residual failing tests are outside the P0 scope and should be handled as follow-up work:

- `native/nightshade_native/imaging/src/fits.rs` has two failing unit tests: `test_fits_complete_metadata` and `test_fits_round_trip`
- `native/nightshade_native/sequencer/src/focus_prediction.rs` has one failing unit test: `test_filter_offsets`
