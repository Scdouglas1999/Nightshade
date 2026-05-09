# Nightshade P2 Remediation Tracker

Last updated: 2026-03-13
Source: `report/nightshade_audit_report.md` section 12.20 plus the P2 "Medium-Term (Next Quarter)" table in section 11

Purpose: persist the exact P2 remediation and feature-delivery set, final status in the working tree, implementation targets, and verification notes so future context compaction retains the completed state.

Operator note: do not report back to the user until every P2 task in this tracker is fully implemented and verified. This condition is now satisfied for the full P2 set.

Status legend:
- `fixed-in-tree`: implemented in the current worktree and verified

## P2 Task List

| Task ID | Area | Audit Item | Status | Primary files | Verification notes |
|---|---|---|---|---|---|
| P2-001 | FITS correctness | Fix all FITS parsing issues (boolean, keywords, record overflow) | `fixed-in-tree` | `native/nightshade_native/imaging/src/fits.rs`, `native/nightshade_native/imaging/src/reader.rs` | Verified with `cargo test -p nightshade_imaging fits::tests --lib`; includes exact boolean token handling, keyword validation, overflow rejection, and complete-header validation coverage. |
| P2-002 | Imaging debayer | Fix BGGR debayer direction logic | `fixed-in-tree` | `native/nightshade_native/bridge/src/api.rs`, `native/nightshade_native/imaging/src/debayer.rs` | Verified with `cargo test -p nightshade_imaging debayer::tests --lib`; BGGR and RGGB interpolation tests both pass. |
| P2-003 | Imaging stats | Fix MAD calculation in stats | `fixed-in-tree` | `native/nightshade_native/imaging/src/stats.rs`, `native/nightshade_native/bridge/src/api.rs` | Verified with `cargo test -p nightshade_imaging stats::tests --lib`; MAD regression tests pass, including even-sample and trailing-byte handling. |
| P2-004 | Sequencer imaging parameters | Fix dither parameters hardcoding | `fixed-in-tree` | `native/nightshade_native/sequencer/src/instructions.rs`, `packages/nightshade_core/lib/src/models/sequence/sequence_models.dart` | Re-audited in-tree and verified with `cargo test -p nightshade_sequencer instructions::tests --lib`; sequencer instruction paths now consume configured parameters instead of hardcoded dither defaults. |
| P2-005 | Camera thermal control | Fix warm camera temperature hardcoding | `fixed-in-tree` | `native/nightshade_native/sequencer/src/instructions.rs`, `packages/nightshade_core/lib/src/models/sequence/sequence_models.dart` | Re-audited in-tree and verified with `cargo test -p nightshade_sequencer instructions::tests --lib`; warm-camera instructions now use configured target temperatures rather than fixed values. |
| P2-006 | WebRTC resilience | Fix WebRTC reconnection logic | `fixed-in-tree` | `packages/nightshade_webrtc/lib/src/peer_connection.dart`, `packages/nightshade_webrtc/lib/src/web_server.dart` | Verified with `flutter test` in `packages/nightshade_webrtc` and `dart analyze` in `packages/nightshade_webrtc`; reconnect/session transport hardening is in-tree and passing. |
| P2-007 | Plugin safety | Add plugin sandboxing and timeout protection | `fixed-in-tree` | `packages/nightshade_plugins/lib/src/plugin_host.dart`, `packages/nightshade_plugins/lib/src/plugin_context.dart` | Verified with `flutter test` in `packages/nightshade_plugins`; coverage includes plugin timeout enforcement, sandboxed event-bus behavior, and persistent plugin storage. |
| P2-008 | Updater security | Add update signature verification | `fixed-in-tree` | `packages/nightshade_updater/lib/src/update_verifier.dart`, `packages/nightshade_updater/lib/src/services/update_service.dart` | Verified with `flutter test test/update_service_test.dart` in `packages/nightshade_updater`; canonical manifest signature verification and rollback/pending-install checks pass. |
| P2-009 | Desktop/web surface | Ship web dashboard | `fixed-in-tree` | `apps/desktop/web_dashboard`, `apps/desktop/lib/headless_api_server.dart`, `scripts/package_windows.ps1` | Re-audited in-tree and verified with `dart analyze lib/headless_api_server.dart` in `apps/desktop`; static dashboard assets, serving path, and packaging hooks are present and consistent. |
| P2-010 | Mobile UX | Polish mobile companion experience | `fixed-in-tree` | `apps/mobile/lib/main.dart`, `apps/mobile/lib/services/foreground_service.dart`, `apps/mobile/lib/services/notification_service.dart` | Verified with `dart analyze lib/main.dart` and `flutter test` in `apps/mobile`; mobile startup, connection flow, overlays, and smoke coverage pass. |
| P2-011 | Scheduling | Build native target scheduler | `fixed-in-tree` | `packages/nightshade_core/lib/src/services/scheduler_service.dart`, `packages/nightshade_core/test/services/scheduler_service_test.dart`, `packages/nightshade_app/lib/screens/analytics/analytics_screen.dart` | Verified with `flutter test test/services/scheduler_service_test.dart` in `packages/nightshade_core`; moon exclusion, altitude, separation, and scheduler service behavior pass. |
| P2-012 | Weather safety UX | Add configurable weather thresholds | `fixed-in-tree` | `packages/nightshade_core/lib/src/providers/weather_safety_provider.dart`, `packages/nightshade_app/lib/screens/settings/widgets/weather_safety_settings.dart`, `packages/nightshade_app/lib/screens/settings/settings_screen.dart` | Verified in-tree via the new settings UI plus `dart analyze` in `packages/nightshade_app`; threshold values now persist and drive weather safety behavior instead of hardcoded limits. |
| P2-013 | Test coverage | Add integration tests for critical paths | `fixed-in-tree` | `native/nightshade_native/imaging/src/fits.rs`, `native/nightshade_native/imaging/src/debayer.rs`, `native/nightshade_native/imaging/src/stats.rs`, `native/nightshade_native/sequencer/src/instructions.rs`, `packages/nightshade_core/test`, `packages/nightshade_plugins/test`, `packages/nightshade_updater/test`, `apps/mobile/test` | Verified by the added/expanded native and Flutter test coverage: FITS, debayer, stats, sequencer instructions, session recovery, scheduler, project tracking, HTML export, plugin sandboxing, updater signature verification, app package UI tests, and mobile smoke coverage all pass. |
| P2-014 | Reporting | Add session report generation | `fixed-in-tree` | `packages/nightshade_core/lib/src/services/session_export_service.dart`, `packages/nightshade_app/lib/screens/analytics/analytics_screen.dart` | Verified with `flutter test test/services/session_export_service_test.dart` in `packages/nightshade_core` and `flutter test` in `packages/nightshade_app`; HTML report export is implemented and wired into session detail actions. |
| P2-015 | Project workflow | Add multi-night project tracking | `fixed-in-tree` | `packages/nightshade_core/lib/src/database/database.dart`, `packages/nightshade_core/lib/src/database/tables/targets.dart`, `packages/nightshade_core/lib/src/database/daos/targets_dao.dart`, `packages/nightshade_core/lib/src/services/project_tracking_service.dart`, `packages/nightshade_app/lib/screens/analytics/analytics_screen.dart` | Verified with `flutter test test/services/project_tracking_service_test.dart` in `packages/nightshade_core`; integration goals, aggregation, persistence, and analytics UI wiring are in-tree. |
| P2-016 | Localization | Implement i18n / localization | `fixed-in-tree` | `packages/nightshade_app/lib/localization/nightshade_localizations.dart`, `packages/nightshade_app/lib/app.dart`, `packages/nightshade_app/lib/screens`, `apps/mobile/lib/main.dart` | Verified with `dart analyze` in `packages/nightshade_app`, `flutter test` in `packages/nightshade_app`, `dart analyze lib/main.dart` in `apps/mobile`, and `flutter test` in `apps/mobile`; localized app chrome now covers navigation, settings, analytics, shell prompts, weather safety, and mobile connection UI with persisted language selection. |

## Completion Summary

Completed in-tree for the full P2 set:

- Native imaging hardening: FITS parser correctness, BGGR debayer direction, MAD calculation, configurable dither/warm-camera instruction handling, and targeted native regression coverage.
- Platform/runtime hardening: WebRTC reconnection, plugin sandboxing/timeouts, updater signature verification, and shipped desktop web dashboard surface.
- Product delivery work: mobile polish, target scheduling, configurable weather thresholds, session HTML reporting, multi-night project tracking, and app/mobile localization.

## Verification Log

- `cargo test -p nightshade_imaging fits::tests --lib`
- `cargo test -p nightshade_imaging debayer::tests --lib`
- `cargo test -p nightshade_imaging stats::tests --lib`
- `cargo test -p nightshade_sequencer instructions::tests --lib`
- `flutter test test/services/project_tracking_service_test.dart test/services/session_export_service_test.dart test/services/session_service_test.dart test/services/scheduler_service_test.dart` in `packages/nightshade_core`
- `flutter test` in `packages/nightshade_plugins`
- `flutter test test/update_service_test.dart` in `packages/nightshade_updater`
- `flutter test` in `packages/nightshade_webrtc`
- `dart analyze lib/headless_api_server.dart` in `apps/desktop`
- `dart analyze lib/localization/nightshade_localizations.dart lib/screens/settings/settings_screen.dart lib/screens/dashboard/dashboard_screen.dart lib/screens/shell/app_shell.dart lib/screens/shell/widgets/side_navigation.dart lib/screens/shell/widgets/nightshade_bottom_navigation.dart lib/screens/settings/widgets/general_settings.dart lib/screens/settings/widgets/weather_safety_settings.dart lib/screens/analytics/analytics_screen.dart lib/app.dart` in `packages/nightshade_app`
- `flutter test` in `packages/nightshade_app`
- `dart analyze lib/main.dart` in `apps/mobile`
- `flutter test` in `apps/mobile`

Non-blocking notes from verification:

- `flutter test test/update_service_test.dart` in `packages/nightshade_updater` emits existing `uses-material-design` configuration warnings from dependent packages, but the updater test suite passes.
- Native test builds still emit an existing `dead_code` warning for `JsonRpcResponse.id` in `native/nightshade_native/imaging/src/phd2.rs`; it does not affect the P2 verification set.

## Notes

- The P2 source list intentionally used the union of section 12.20 and the section 11 medium-term table so no audit-listed P2 item was dropped during remediation.
- The tracker now reflects the final completed state: every P2 row is `fixed-in-tree` and backed by a verification entry above.
