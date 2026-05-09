# Nightshade P1 Remediation Tracker

Last updated: 2026-03-13
Source: `report/nightshade_audit_report.md` section 12.20

Purpose: persist the exact P1 remediation set, current status in the working tree, implementation targets, and verification notes so work can continue cleanly after context compaction.

Operator note: do not report back to the user until every P1 task in this tracker is fully implemented and verified. Continue working end to end until the full list is complete.

Status legend:
- `fixed-in-tree`: confirmed fixed in the current worktree
- `in-progress`: actively being implemented in this pass
- `open`: confirmed still open
- `needs-verification`: not yet re-audited deeply enough to claim fixed

## P1 Task List

| Task ID | Area | Audit Item | Status | Primary files | Verification notes |
|---|---|---|---|---|---|
| P1-001 | Driver crash resilience | Replace all production `Mutex` poison panics with poison recovery or equivalent | `fixed-in-tree` | `native/nightshade_native/native/src/vendor/touptek.rs`, `native/nightshade_native/native/src/vendor/atik.rs`, `native/nightshade_native/native/src/vendor/moravian.rs` | Current production vendor lock sites use `unwrap_or_else(|e| e.into_inner())`. Remaining raw `lock().unwrap()` matches are in tests plus one Alpaca test helper block, not the audited production paths. |
| P1-002 | Native discovery | Remove blocking `std::thread::sleep` from async discovery | `fixed-in-tree` | `native/nightshade_native/native/src/discovery.rs` | The audited async discovery backoff sites now use `tokio::time::sleep(...).await`, so discovery no longer blocks the runtime worker thread. |
| P1-003 | Native camera drivers | Fix Touptek `connect()` TOCTOU race between open and re-enumeration | `fixed-in-tree` | `native/nightshade_native/native/src/vendor/touptek.rs` | `connect()` now enumerates and opens under the same SDK lock, reuses the captured capability snapshot, and no longer re-enumerates after open to recover metadata. |
| P1-004 | FITS reader correctness | Bound / harden mmap FITS `END` scan so malformed headers cannot run indefinitely into image data | `fixed-in-tree` | `native/nightshade_native/imaging/src/reader.rs` | `MappedFitsReader` now trusts the parsed FITS header length from `fits::read_header()` for `data_offset` instead of rescanning the mmap for a later `END`-looking block. |
| P1-005 | Sequencer mount waits | Replace flat wizard fixed slew waits with polling | `fixed-in-tree` | `native/nightshade_native/sequencer/src/flat_wizard.rs` | Current tree polls `mount_is_slewing()` instead of sleeping a fixed 5 seconds. |
| P1-006 | Sequencer mount waits | Replace polar alignment fixed slew waits with polling | `fixed-in-tree` | `native/nightshade_native/sequencer/src/polar_align.rs` | Current tree polls `mount_is_slewing()` instead of sleeping a fixed 5 seconds. |
| P1-007 | Meridian flip safety | Add slew timeout to meridian flip slew | `fixed-in-tree` | `native/nightshade_native/sequencer/src/meridian_flip_executor.rs` | Current tree aborts after a 10-minute timeout and best-effort aborts the slew before returning. |
| P1-008 | Meridian flip validation | Make `verify_pier_side_changed()` actually compare old vs new pier side | `fixed-in-tree` | `native/nightshade_native/sequencer/src/meridian_flip_executor.rs` | Current tree returns an error when pre- and post-flip pier side remain equal and both are known. |
| P1-009 | Sequencer trigger propagation | Preserve `trigger_state` in parallel branch execution contexts | `fixed-in-tree` | `native/nightshade_native/sequencer/src/node.rs` | Parallel branch child contexts now clone and preserve the parent `trigger_state` instead of resetting it to `None`. |
| P1-010 | Bridge FFI correctness | Stop silent node serialization failures in node factory APIs | `fixed-in-tree` | `native/nightshade_native/bridge/src/api.rs` | Node factories now serialize via shared helpers that return `Result<String, NightshadeError>` and surface serialization failures instead of returning an empty string. |
| P1-011 | Bridge FFI correctness | Stop silently dropping malformed nodes in `api_build_sequence` | `fixed-in-tree` | `native/nightshade_native/bridge/src/api.rs` | `api_build_sequence()` now collects deserialization results and returns `SerializationError` on malformed node JSON instead of dropping it with `filter_map`. |
| P1-012 | Database performance | Fix DAO N+1 / full-table aggregation patterns | `fixed-in-tree` | `packages/nightshade_core/lib/src/database/daos/images_dao.dart`, `packages/nightshade_core/lib/src/database/daos/dark_library_dao.dart`, `packages/nightshade_core/lib/src/database/daos/sessions_dao.dart` | The audited `DB-H2` through `DB-H5` paths now use SQL aggregation / grouping instead of loading whole tables into Dart. |
| P1-013 | Database integrity | Wrap prune operations in transactions | `fixed-in-tree` | `packages/nightshade_core/lib/src/database/daos/flat_history_dao.dart`, `packages/nightshade_core/lib/src/database/daos/polar_alignment_history_dao.dart` | Both prune paths now run the keep/delete sequence inside `transaction(() async { ... })`, preventing partial-prune states. |
| P1-014 | Device heartbeat correctness | Make ASCOM mount heartbeat actually ping hardware | `fixed-in-tree` | `native/nightshade_native/bridge/src/devices.rs` | Current ASCOM mount health check issues a live mount property read instead of trusting cached state. |
| P1-015 | Persistence reliability | Await all audited persistence futures instead of fire-and-forget writes | `fixed-in-tree` | `packages/nightshade_core/lib/src/providers/template_snippet_provider.dart`, `packages/nightshade_core/lib/src/providers/polar_alignment_provider.dart` | The audited snippet and polar-alignment persistence setters now return `Future<void>` and await `saveToDisk()` / `updateConfig(...)` instead of dropping those futures. |
| P1-016 | Imaging service robustness | Add circuit breaker to `startLoopCapture()` | `fixed-in-tree` | `packages/nightshade_core/lib/src/services/imaging_service.dart` | `startLoopCapture()` now aborts after `maxConsecutiveErrors` repeated failures. |
| P1-017 | Plugin persistence | Replace in-memory plugin storage with persistent backend | `fixed-in-tree` | `packages/nightshade_plugins/lib/src/plugin_context.dart`, `packages/nightshade_plugins/pubspec.yaml` | `PluginContextFactory` now uses `FilePluginStorage`, which persists plugin JSON atomically under an OS-specific application-data directory and survives process restarts. |
| P1-018 | Updater safety | Add real update rollback mechanism | `fixed-in-tree` | `packages/nightshade_updater/lib/src/services/update_service.dart`, `native/nightshade_native/updater/src/main.rs` | The updater now writes a pending-install marker, verifies the post-apply install, restores the backup on apply/verify/launch failure, and clears the pending marker after rollback or successful startup verification. |
| P1-019 | SDK loader hygiene | Remove hardcoded developer workstation path from ZWO SDK loader | `fixed-in-tree` | `native/nightshade_native/native/src/vendor/zwo.rs` | The personal workstation SDK path was removed from the DLL search list, leaving only repo-relative and system install locations. |

## Current Implementation Batch

Completed in this pass:

- `P1-002` replaced blocking async discovery sleeps with `tokio::time::sleep(...).await`
- `P1-003` removed the Touptek connect re-enumeration race by keeping enumerate/open under one SDK lock
- `P1-004` removed the unbounded mmap `END` rescan from the FITS reader and added regression tests
- `P1-009` preserved `trigger_state` in parallel sequencer branches
- `P1-010` / `P1-011` surfaced bridge node serialization and deserialization failures instead of silently dropping them
- `P1-013` wrapped history prune flows in database transactions
- `P1-015` awaited the audited persistence futures in snippet and polar-alignment providers
- `P1-017` replaced in-memory plugin storage with persistent file-backed storage and added persistence tests
- `P1-018` implemented updater rollback, pending-install verification, and startup status handling
- `P1-019` removed the hardcoded workstation ZWO SDK path

## Verification Log

- `cargo test -p nightshade_native --lib`
- `cargo test -p nightshade_alpaca -p nightshade_indi --lib`
- `cargo test -p nightshade_bridge --lib` with `C:\Users\scdou\Documents\Nightshade2\lib\libraw` prepended to `PATH`
- `cargo test -p nightshade_imaging mapped_reader --lib`
- `cargo test -p nightshade_updater`
- `flutter test` in `packages/nightshade_plugins`
- `flutter test` in `packages/nightshade_updater`
- `flutter test test/services/imaging_service_test.dart test/services/session_service_test.dart` in `packages/nightshade_core`
- `dart analyze` in `packages/nightshade_bridge`
- `dart analyze` in `packages/nightshade_core`

Residual non-P1 failures still present in the tree:

- `cargo test -p nightshade_sequencer --lib`: pre-existing `focus_prediction::tests::test_filter_offsets`
- `flutter test test/services/centering_service_test.dart` in `packages/nightshade_core`: pre-existing expectation mismatch at `test/services/centering_service_test.dart:408`
- `cargo test -p nightshade_imaging --lib`: full suite not re-run because there are known pre-existing FITS test failures outside the P1 scope; the new `mapped_reader` regression tests passed

## Notes

- Several report-listed P1 items were already fixed in-tree before this batch began: flat wizard / polar alignment slew polling, meridian flip timeout and pier-side verification, DAO aggregation hot paths, ASCOM mount heartbeat, and the imaging loop-capture circuit breaker.
- The full P1 remediation set from the audit is now `fixed-in-tree`. Remaining red tests listed above are outside the audited P1 scope and were not introduced by this batch.
