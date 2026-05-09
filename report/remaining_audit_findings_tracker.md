# Nightshade Remaining Audit Findings Tracker

Last updated: 2026-03-14
Source: `report/nightshade_audit_report.md`, excluding items already tracked and closed in `p0_remediation_tracker.md`, `p1_remediation_tracker.md`, `p2_remediation_tracker.md`, and `p3_remediation_tracker.md`

Purpose: persist the complete post-priority residual audit inventory, current status in the working tree, and verification notes so this final remediation phase can continue cleanly after context compaction.

Operator note: do not report back to the user until every finding in this tracker is fully implemented and verified. Continue working end to end until the full list is driven to zero. Do not split the work into batches.

Status legend:
- `fixed-in-tree`: re-audited and confirmed fixed in the current worktree
- `open`: confirmed still open and requires implementation
- `needs-verification`: likely fixed incidentally or by overlapping work, but not yet re-audited deeply enough to close
- `duplicate`: duplicate of another finding in this tracker; close only when the primary issue is fixed and verified

## Scope

Excluded from this tracker:

- All P0 items already recorded in `report/p0_remediation_tracker.md`
- All P1 items already recorded in `report/p1_remediation_tracker.md`
- All P2 items already recorded in `report/p2_remediation_tracker.md`
- All P3 items already recorded in `report/p3_remediation_tracker.md`
- `report/p4_remediation_tracker.md` currently records a verified zero-item state because the audit defines no P4 work

Current residual finding count: 126 total / 0 open

## Wave 1 Residual Findings

### Bugs / High / Medium

| ID | Status | Finding |
|---|---|---|
| BUG-003 | `fixed-in-tree` | Array index out-of-bounds in median calculation |
| HIGH-004 | `fixed-in-tree` | Null dereference in guiding event handler |
| HIGH-005 | `fixed-in-tree` | Silent autofocus progress parsing failure |
| HIGH-006 | `fixed-in-tree` | Race condition in session stats (non-atomic RMS read) |
| HIGH-007 | `fixed-in-tree` | Camera switch race condition in temperature polling |
| HIGH-008 | `fixed-in-tree` | Nested time unwraps in twilight calculations |
| HIGH-009 | `fixed-in-tree` | Empty vector panic in autofocus fitting |
| HIGH-011 | `fixed-in-tree` | Plugin event bus not thread-safe |
| HIGH-014 | `fixed-in-tree` | Guiding RMS baseline never reset |
| HIGH-015 | `fixed-in-tree` | Cover calibrator not halted on cancellation |
| HIGH-016 | `fixed-in-tree` | Binning change does not invalidate autofocus |
| HIGH-018 | `fixed-in-tree` | Dangling recovery action references on node deletion |
| MED-002 | `fixed-in-tree` | Focus model accepts unrealistic slopes without warning |
| MED-003 | `fixed-in-tree` | Async init race in `FilterOffsetNotifier` |
| MED-004 | `fixed-in-tree` | Missing session ID validation |
| MED-005 | `fixed-in-tree` | `FocusModelService` reads before init completes |
| MED-006 | `fixed-in-tree` | Provider dependency chain too deep |
| MED-008 | `fixed-in-tree` | Missing empty states in multiple screens |
| MED-009 | `fixed-in-tree` | Missing loading states during async operations |
| MED-010 | `fixed-in-tree` | Missing error feedback to user |
| MED-011 | `fixed-in-tree` | Poor responsive design (no tablet breakpoint) |
| MED-012 | `fixed-in-tree` | Inconsistent styling across UI surfaces |
| MED-013 | `fixed-in-tree` | Missing provider invalidation after data changes |
| MED-014 | `fixed-in-tree` | Median calculation off-by-one for even lists |
| MED-018 | `fixed-in-tree` | Orphaned polar alignment history on profile delete |
| MED-019 | `fixed-in-tree` | Multiple active equipment profiles possible |
| MED-020 | `fixed-in-tree` | JSON blob schemas are unvalidated |
| MED-021 | `fixed-in-tree` | Settings init race (`INSERT OR IGNORE` vs `REPLACE`) |
| MED-022 | `fixed-in-tree` | Duplicate optical config fields in equipment profile |
| MED-023 | `fixed-in-tree` | Focus prediction data biased to recent sessions |
| MED-024 | `fixed-in-tree` | Autofocus V-curve assumes symmetric data |
| MED-025 | `fixed-in-tree` | Filter wheel name matching too fragile |
| MED-026 | `fixed-in-tree` | Sequence import does not validate equipment |
| MED-027 | `fixed-in-tree` | Mount tracking loss detection heuristic fragile |
| MED-028 | `fixed-in-tree` | Timer not disposed on error in mobile app |
| MED-029 | `fixed-in-tree` | LAN push receiver not atomic |
| MED-030 | `fixed-in-tree` | Planetarium label layout is O(n^2) |
| MED-031 | `fixed-in-tree` | Planetarium paint / blur cache grows unbounded |
| MED-032 | `fixed-in-tree` | Missing non-drag reorder path in sequence tree |
| MED-033 | `fixed-in-tree` | Missing accessibility metadata and focus flow |
| MED-034 | `fixed-in-tree` | Missing undo / redo for destructive operations |
| MED-035 | `fixed-in-tree` | Database v18 migration remains destructive |

## Imaging Residual Findings

| ID | Status | Finding |
|---|---|---|
| IMG-H1 | `fixed-in-tree` | Duplicate FITS keywords are recorded twice on write |
| IMG-H2 | `fixed-in-tree` | FITS boolean parsing matches any string starting with T/F |
| IMG-H3 | `fixed-in-tree` | Long float FITS keyword values can overflow 80-byte records |
| IMG-H4 | `fixed-in-tree` | `processing.rs` allocates one `Vec` per pixel in flattening path |
| IMG-H5 | `fixed-in-tree` | Histogram API divides by zero when `bins == 0` |
| IMG-H6 | `fixed-in-tree` | XISF offset convergence is not verified after the third pass |
| IMG-H7 | `fixed-in-tree` | `read_downsampled` silently emits wrong-length output on OOB samples |
| IMG-H8 | `fixed-in-tree` | `to_display_u8` returns gray for 3-channel `u16` color data |
| IMG-M3 | `fixed-in-tree` | Missing `NAXIS2` is treated as height `1` instead of error |
| IMG-M4 | `fixed-in-tree` | Sigma clipping uses population variance instead of sample variance |
| IMG-M5 | `fixed-in-tree` | `buffer_pool` panics after `into_vec()` with `expect()` calls |
| IMG-M6 | `fixed-in-tree` | Frame number scan can match camera model digits in filenames |

## Device Control Residual Findings

| ID | Status | Finding |
|---|---|---|
| DEV-CRIT-3 | `duplicate` | Empty debayer panic (duplicate of `BUG-003`) |
| DEV-H1 | `fixed-in-tree` | Reconnect delay is linear despite backoff configuration |
| DEV-H2 | `fixed-in-tree` | Tracking rate is hardcoded to sidereal for multiple mount types |
| DEV-H3 | `fixed-in-tree` | Native mount capability flags are hardcoded `true` |
| DEV-H4 | `fixed-in-tree` | Alpaca filter wheel config ignores existing connection |
| DEV-H5 | `fixed-in-tree` | INDI dome status is disabled on Windows via cfg gate |
| DEV-H6 | `fixed-in-tree` | INDI switch ops re-parse device ID without bounds checks |
| DEV-H8 | `fixed-in-tree` | Stale placeholder comments remain in `unified_device_ops.rs` |
| DEV-H9 | `fixed-in-tree` | Cover calibrator status queries hardware four times per poll |
| DEV-H10 | `fixed-in-tree` | ASCOM mount heartbeat may still rely on cached state outside the audited path |
| DEV-H11 | `fixed-in-tree` | `can_set_tracking` is inferred instead of using ASCOM capability property |
| DEV-H12 | `fixed-in-tree` | `disconnect()` can return stop error even if disconnect succeeded |

## Database Residual Findings

| ID | Status | Finding |
|---|---|---|
| DB-H1 | `fixed-in-tree` | `duplicateSequence` reuses source node UUIDs |
| DB-H8 | `fixed-in-tree` | `sequence_id` foreign key has no `ON DELETE` action |
| DB-M1 | `fixed-in-tree` | Missing unique session row in science config |
| DB-M2 | `fixed-in-tree` | Dark library `filePath` is not unique |
| DB-M3 | `fixed-in-tree` | Dark matching uses float equality for exposure time |
| DB-M4 | `fixed-in-tree` | Dark matching ignores offset |
| DB-M5 | `fixed-in-tree` | `toggleFavorite` is read-then-write without transaction |
| DB-M6 | `fixed-in-tree` | `upsertSessionConfig` is read-then-write without transaction |
| DB-M7 | `fixed-in-tree` | Missing index on `sequence_id` |
| DB-M8 | `fixed-in-tree` | Weather settings allow multiple rows |

## Provider Residual Findings

| ID | Status | Finding |
|---|---|---|
| PROV-CRIT-1 | `fixed-in-tree` | Provider build function performs side-effect mutations |
| PROV-CRIT-4 | `fixed-in-tree` | `reorderNodes` null-bangs missing node IDs |
| PROV-H2 | `fixed-in-tree` | Session checkpoint persistence is unawaited |
| PROV-H4 | `fixed-in-tree` | Module-level HTTP client is never disposed |
| PROV-H5 | `fixed-in-tree` | Missing `mounted` check after await in framing provider |
| PROV-H6 | `fixed-in-tree` | Weather safety provider mutates during synchronous computation |
| PROV-H7 | `fixed-in-tree` | Auto-stretch provider does not track backend changes |

## Service Residual Findings

| ID | Status | Finding |
|---|---|---|
| SVC-CRIT-2 | `fixed-in-tree` | `ErrorService` has two incompatible singleton instances |
| SVC-H1 | `fixed-in-tree` | Unknown node types are silently dropped on sequence load |
| SVC-H2 | `fixed-in-tree` | Calibration settings save failures are swallowed |
| SVC-H3 | `fixed-in-tree` | Plate solve service hides backend exceptions before fallback |
| SVC-H4 | `fixed-in-tree` | Auto-save `stop()` does not await final save |
| SVC-H5 | `fixed-in-tree` | Device reconnection timers are not cancelled on dispose |
| SVC-H6 | `fixed-in-tree` | Logging service init ordering is not enforced |
| SVC-H7 | `fixed-in-tree` | Backup failure logs at `debug` instead of `error` |
| SVC-H8 | `fixed-in-tree` | Backup restore performs unsafe string casts on legacy JSON |
| SVC-H9 | `fixed-in-tree` | Profile restore casts JSON values to `int` too narrowly |
| SVC-H10 | `fixed-in-tree` | Annotation service constructor leak via unmanaged `ref.listen` |
| SVC-H11 | `fixed-in-tree` | `centerOnTarget` has no overall timeout |
| SVC-H13 | `fixed-in-tree` | Error service silently swallows provider read failures |
| SVC-M1 | `fixed-in-tree` | Session export divides by zero when `totalExposures == 0` |
| SVC-M2 | `fixed-in-tree` | Catalog pagination double-counts offset |
| SVC-M3 | `fixed-in-tree` | Focus model divides by zero when temperatures are identical |
| SVC-M4 | `fixed-in-tree` | Dark library FITS parsing skips the final pixel |
| SVC-M5 | `fixed-in-tree` | Notification HTTP requests have no timeout |
| SVC-M6 | `fixed-in-tree` | Flat wizard result iteration count is off by one |
| SVC-M7 | `fixed-in-tree` | Quick start swallows DB corruption and returns empty |
| SVC-M8 | `fixed-in-tree` | Paginated image loader does not update paging state |
| SVC-M9 | `fixed-in-tree` | Science processing logs top-level failures at warning instead of error |
| SVC-M10 | `fixed-in-tree` | Mosaic RA offsets are not normalized back to `[0, 24)` |

## Bridge / FFI Residual Findings

| ID | Status | Finding |
|---|---|---|
| FFI-HIGH-4 | `fixed-in-tree` | Plate solve temp filename race may already be fixed incidentally; re-audit required |
| FFI-HIGH-5 | `fixed-in-tree` | `sequencer_clear_checkpoint` silently succeeds on lock contention |
| FFI-MED-1 | `fixed-in-tree` | Plate solve timeout message is hardcoded to `60 seconds` |
| FFI-MED-2 | `fixed-in-tree` | Filter wheel position failure silently becomes `0` |

## Sequencer Residual Findings

| ID | Status | Finding |
|---|---|---|
| SEQ-HIGH-2 | `fixed-in-tree` | Mount sync errors are silently discarded |
| SEQ-M1 | `fixed-in-tree` | `start_after` waits cannot be cancelled |
| SEQ-M2 | `fixed-in-tree` | Recovery autofocus uses default config instead of user config |
| SEQ-M3 | `fixed-in-tree` | Trigger-fired flip loses `focuser_id` |
| SEQ-M4 | `fixed-in-tree` | Trigger-fired autofocus loses lat/lon/save path |
| SEQ-M5 | `fixed-in-tree` | Temperature compensation holds write lock across device I/O |
| SEQ-M6 | `fixed-in-tree` | Filter offset poll stops on error without proving offset applied |
| SEQ-M7 | `fixed-in-tree` | Sun RA formula can produce `NaN` |
| SEQ-M8 | `fixed-in-tree` | `FlatWizardConfig` default `flat_count` is `0` |
| SEQ-M9 | `fixed-in-tree` | Polar azimuth error uses meaningless `pole_ra = 0.0` |
| SEQ-M10 | `fixed-in-tree` | Checkpoint resume can underflow `u32` counters |
| SEQ-M11 | `fixed-in-tree` | Start / SkipToNode commands are swallowed while running |
| SEQ-M12 | `fixed-in-tree` | Cancelled state is conflated with idle |
| SEQ-M13 | `fixed-in-tree` | Mosaic panel estimate hardcodes `60s` overhead |
| SEQ-M14 | `fixed-in-tree` | Mosaic RA correction uses center declination instead of panel declination |
| SEQ-M15 | `fixed-in-tree` | Checkpoint file is loaded twice per query |

## Driver Residual Findings

| ID | Status | Finding |
|---|---|---|
| DRV-CRIT-3 | `fixed-in-tree` | Vendor SDK poison-cascade finding was targeted in P1, but all 58 cited sites still need explicit residual re-audit |
| DRV-H1 | `fixed-in-tree` | INDI BLOB event channel can silently drop events |
| DRV-H3 | `fixed-in-tree` | `rand_simple()` jitter space is too small |
| DRV-H4 | `fixed-in-tree` | XML parse errors continue with parser in indeterminate state |
| DRV-H5 | `fixed-in-tree` | Touptek exposure remaining reports total duration, not actual remaining |
| DRV-H6 | `fixed-in-tree` | INDI discovery still performs blocking TCP connect from async |
| DRV-H7 | `fixed-in-tree` | ZWO SDK load code is duplicated verbatim |
| DRV-H8 | `fixed-in-tree` | Moravian enumeration callback races global state |
| DRV-H9 | `fixed-in-tree` | INDI autofocus FITS parser assumes a single header block |
| DRV-H10 | `fixed-in-tree` | ASCOM timeout config still falls back to defaults on poisoned lock |
| DRV-M1 | `fixed-in-tree` | INDI `is_available()` always returns `true` on Windows |
| DRV-M2 | `fixed-in-tree` | INDI exposure timeout buffer hardcodes `30s` |
| DRV-M3 | `fixed-in-tree` | Cover calibrator max brightness is hardcoded `255` |
| DRV-M4 | `fixed-in-tree` | INDI autofocus timeout buffer hardcodes `60s` |
| DRV-M5 | `fixed-in-tree` | Discovery subnet list is hardcoded |
| DRV-M6 | `fixed-in-tree` | LX200 serial driver busy-polls on `Ok(0)` |
| DRV-M7 | `fixed-in-tree` | Alpaca telescope query parameter is embedded in path string |
| DRV-M8 | `fixed-in-tree` | LX200 declination arcseconds parse failure silently defaults to `0.0` |

## Verification Log

- Initial inventory derived from `report/nightshade_audit_report.md` after excluding IDs already covered by the P0-P3 trackers
- Residual count at tracker creation: 144 findings
- Imaging residual pass verified with `cargo test -p nightshade_imaging --lib`; this closed `IMG-H1`, `IMG-H2`, `IMG-H3`, `IMG-H4`, `IMG-H5`, `IMG-H7`, `IMG-H8`, `IMG-M3`, `IMG-M4`, and `IMG-M6`
- Bridge / FFI residual pass verified with `cargo check -p nightshade_bridge` and `cargo test -p nightshade_bridge --lib` (desktop DLL bundle on `PATH`); this closed `FFI-HIGH-4`, `FFI-HIGH-5`, `FFI-MED-1`, and `FFI-MED-2`
- Dart services residual pass verified with `flutter test test/services/mosaic_service_test.dart test/services/focus_model_service_test.dart test/services/session_export_service_test.dart` and targeted `dart analyze`; this closed `SVC-M1`, `SVC-M3`, `SVC-M9`, and `SVC-M10`
- Residual service regression pass verified with `flutter test test/services/residual_service_fixes_test.dart` and targeted `dart analyze`; this closed `SVC-M2`, `SVC-M4`, `SVC-M5`, `SVC-M6`, `SVC-M7`, and `SVC-M8`
- Service persistence / restore hardening verified with `flutter test test/services/residual_service_fixes_test.dart` and targeted `dart analyze`; this closed `SVC-CRIT-2`, `SVC-H2`, `SVC-H4`, `SVC-H5`, `SVC-H7`, `SVC-H8`, `SVC-H9`, and `SVC-H13`
- Service control-flow hardening verified with `flutter test test/services/residual_service_fixes_test.dart test/services/centering_service_test.dart test/services/annotation_service_test.dart` and targeted `dart analyze`; this closed `SVC-H1`, `SVC-H3`, `SVC-H10`, and `SVC-H11`
- Database DAO hardening verified with `flutter test test/services/residual_service_fixes_test.dart` and targeted `dart analyze`; this closed `DB-H1`, `DB-M2`, `DB-M3`, `DB-M4`, `DB-M5`, `DB-M6`, and `DB-M8`
- Provider residual re-audit verified with targeted `dart analyze` across the affected provider files and `flutter test test/providers`; this closed `PROV-CRIT-1`, `PROV-CRIT-4`, `PROV-H2`, `PROV-H4`, `PROV-H5`, `PROV-H6`, and `PROV-H7`
- Schema/runtime hardening verified with `dart run build_runner build --delete-conflicting-outputs`, targeted `dart analyze`, `flutter test test/services/logging_service_test.dart test/services/sequence_file_service_test.dart test/services/database_migration_test.dart`, and `flutter test test/lan_push_receiver_test.dart test/update_service_test.dart`; this closed `SVC-H6`, `DB-H8`, `DB-M1`, `DB-M7`, `MED-018`, `MED-019`, `MED-026`, and `MED-029`
- Imaging/sequencer runtime hardening verified with `cargo fmt`, `cargo test -p nightshade_imaging --lib`, `cargo test -p nightshade_imaging xisf::tests::resolves_offsets_until_fixed_point --lib`, `cargo test -p nightshade_sequencer node::tests --lib`, `cargo test -p nightshade_sequencer executor::tests --lib`, `cargo check -p nightshade_bridge`, and `cargo test -p nightshade_bridge --lib` with `C:\Users\scdou\Documents\Nightshade2\lib\libraw` prepended to `PATH`; this closed `IMG-H6`, `IMG-M5`, `SEQ-M1`, `SEQ-M2`, `SEQ-M3`, `SEQ-M4`, `SEQ-M5`, `SEQ-M8`, `SEQ-M11`, and `SEQ-M12`
- Sequencer control/math hardening verified with `cargo fmt`, `cargo test -p nightshade_sequencer triggers::tests --lib`, `cargo test -p nightshade_sequencer instructions::tests --lib`, `cargo test -p nightshade_sequencer mosaic::tests --lib`, and `cargo check -p nightshade_bridge`; this closed `SEQ-HIGH-2`, `SEQ-M6`, `SEQ-M10`, `SEQ-M13`, and `SEQ-M14`
- Polar/checkpoint hardening verified with `cargo fmt`, `cargo test -p nightshade_sequencer node::tests --lib`, `cargo test -p nightshade_sequencer polar_align::tests --lib`, `cargo test -p nightshade_sequencer checkpoint::tests --lib`, and `dart analyze lib/main.dart` in `apps/mobile`; this closed `SEQ-M7`, `SEQ-M9`, and `SEQ-M15`
- Native residual device/driver/sequencer hardening verified with `cargo fmt`, `cargo check -p nightshade_bridge -p nightshade_sequencer`, `cargo test -p nightshade_sequencer --lib`, and `cargo test -p nightshade_bridge filter_matching --lib` with `C:\Users\scdou\Documents\Nightshade2\lib\libraw` prepended to `PATH`; this closed `BUG-003`, `HIGH-008`, `HIGH-009`, `HIGH-014`, `HIGH-015`, `HIGH-016`, `MED-014`, `MED-023`, `MED-024`, `MED-025`, `MED-027`, `DEV-H1`, `DEV-H2`, `DEV-H3`, `DEV-H4`, `DEV-H5`, `DEV-H6`, `DEV-H8`, `DEV-H9`, `DEV-H10`, `DEV-H11`, `DEV-H12`, `DRV-CRIT-3`, `DRV-H1`, `DRV-H3`, `DRV-H4`, `DRV-H5`, `DRV-H6`, `DRV-H7`, `DRV-H8`, `DRV-H9`, `DRV-H10`, `DRV-M2`, `DRV-M3`, `DRV-M4`, `DRV-M5`, `DRV-M6`, `DRV-M7`, and `DRV-M8`
- Core/provider residual hardening verified with targeted `dart analyze` in `packages/nightshade_core`, `dart analyze lib/src/plugin_context.dart` in `packages/nightshade_plugins`, `flutter test test/services/focus_model_service_test.dart test/services/device_service_test.dart`, `flutter test test/providers/residual_provider_fixes_test.dart` in `packages/nightshade_core`, and `flutter test test/plugin_system_test.dart` in `packages/nightshade_plugins`; this closed `HIGH-004`, `HIGH-005`, `HIGH-006`, `HIGH-007`, `HIGH-011`, `MED-002`, `MED-004`, and `MED-005`
- Database/mobile/schema hardening verified with targeted `dart analyze` in `packages/nightshade_core`, `flutter test test/services/database_migration_test.dart test/services/residual_service_fixes_test.dart` in `packages/nightshade_core`, and `dart analyze lib/main.dart` in `apps/mobile`; this closed `MED-003`, `MED-020`, `MED-021`, `MED-022`, `MED-028`, and `MED-035`
- Planetarium residual verification passed with `dart analyze lib/src/rendering/sky_renderer.dart test/sky_renderer_layout_test.dart` and `flutter test test/sky_renderer_layout_test.dart test/star_psf_shader_cache_test.dart` in `packages/nightshade_planetarium`; this closed `MED-030` and `MED-031`
- Final residual UI/provider/device pass verified with targeted `dart analyze` in `packages/nightshade_core`, targeted `dart analyze` plus `flutter test` in `packages/nightshade_app`, and `cargo test -p nightshade_indi --lib` in `native/nightshade_native`; this closed `HIGH-018`, `MED-006`, `MED-008`, `MED-009`, `MED-010`, `MED-011`, `MED-012`, `MED-013`, `MED-032`, `MED-033`, `MED-034`, and `DRV-M1`
- Verification details for individual fixes will be appended here as the tracker is driven to zero

## Notes

- This tracker is the final cleanup phase, not a new priority band. It exists because the report’s full finding inventory is larger than the P0-P3 implementation program.
- Several rows are marked `needs-verification` instead of `open` where overlapping earlier work may already have addressed the defect. They still require explicit re-audit before closure.
