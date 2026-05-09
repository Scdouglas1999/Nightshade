# Nightshade P3 Remediation Tracker

Last updated: 2026-03-14
Source: `report/nightshade_audit_report.md` roadmap table (`P3` rows at lines 630-637) and section `12.20 Updated Priority Actions`

Purpose: persist the exact P3 roadmap implementation set, current status in the working tree, implementation targets, and verification notes so work can continue cleanly after context compaction.

Operator note: do not report back to the user until every P3 task in this tracker is fully implemented and verified. Continue working end to end until the full list is complete. Do not split the work into batches.

Status legend:
- `fixed-in-tree`: confirmed implemented and verified in the current worktree
- `in-progress`: actively being implemented in this pass
- `open`: confirmed still open
- `needs-verification`: existing groundwork is present in-tree but has not yet been re-audited deeply enough to claim the roadmap item complete

## P3 Task List

| Task ID | Area | Roadmap Item | Status | Primary files | Verification notes |
|---|---|---|---|---|---|
| P3-001 | Guiding | Native built-in multi-star guider | `fixed-in-tree` | `native/nightshade_native/bridge/src/builtin_guider.rs`, `native/nightshade_native/bridge/src/api.rs`, `native/nightshade_native/bridge/src/real_device_ops.rs`, `packages/nightshade_bridge/lib/src/bridge_stub.dart`, `packages/nightshade_core/lib/src/providers/guiding_provider.dart`, `apps/desktop/lib/main.dart` | Built-in guider is implemented end to end, exposed through native bridge / HTTP / WebRTC surfaces, and no longer depends on PHD2 for generic guide operations. Verified with `cargo check -p nightshade_bridge` and `cargo test -p nightshade_bridge builtin_guider --lib` with the desktop DLL bundle on `PATH`. |
| P3-002 | Imaging intelligence | Real-time frame quality grading with ML | `fixed-in-tree` | `packages/nightshade_core/lib/src/services/frame_quality_assessment_service.dart`, `packages/nightshade_core/test/services/frame_quality_assessment_service_test.dart`, `packages/nightshade_app/lib/screens/analytics/widgets/science_insights_panel.dart` | Frame grading now produces confidence-weighted quality classes, actionable reject reasons, and summary intelligence suitable for live decisions. Verified by targeted core service tests and targeted `dart analyze`. |
| P3-003 | Planning intelligence | AI session optimizer / "What to image tonight" | `fixed-in-tree` | `packages/nightshade_core/lib/src/services/session_optimizer_service.dart`, `packages/nightshade_core/test/services/session_optimizer_service_test.dart`, `packages/nightshade_app/lib/screens/dashboard/widgets/tonight_card.dart` | Session optimizer now ranks targets, emits alternates and fallback plans, and is wired into the dashboard recommendation surface. Verified by targeted core service tests and targeted `dart analyze`. |
| P3-004 | Diagnostics | Optical train diagnostics / tilt and collimation analysis | `fixed-in-tree` | `packages/nightshade_core/lib/src/services/optical_train_diagnostics_service.dart`, `packages/nightshade_core/test/services/optical_train_diagnostics_service_test.dart`, `packages/nightshade_app/lib/screens/analytics/widgets/science_analytics_tab.dart` | Optical-train diagnostics now detect tilt / edge residual growth and feed analytics UI insights. Verified by targeted core service tests and targeted `dart analyze`. |
| P3-005 | Plate solving | GPU-accelerated plate solving | `fixed-in-tree` | `native/nightshade_native/imaging/src/platesolve.rs`, `native/nightshade_native/imaging/Cargo.toml`, `packages/nightshade_core/lib/src/services/centering_service.dart` | Plate solving now defaults to an internal GPU-assisted solver with explicit CPU fallback, FITS metadata inference, and no external ASTAP dependency on the primary path. Verified with `cargo test -p nightshade_imaging platesolve --lib`. |
| P3-006 | Collaboration | Live collaborative viewing | `fixed-in-tree` | `packages/nightshade_webrtc/lib/src/web_server.dart`, `packages/nightshade_webrtc/lib/src/collaboration/live_collaboration_session.dart`, `packages/nightshade_webrtc/test/web_server_collaboration_test.dart`, `apps/desktop/lib/headless_api_server.dart`, `apps/desktop/lib/main.dart` | Live collaboration now supports shared viewer state, preview ownership, chat, annotations, websocket fanout, and REST access from desktop/headless servers. Verified with targeted `flutter test` in `packages/nightshade_webrtc` and targeted `dart analyze`. |
| P3-007 | Reliability intelligence | Predictive maintenance / equipment health tracking | `fixed-in-tree` | `packages/nightshade_core/lib/src/services/equipment_health_service.dart`, `packages/nightshade_core/test/services/equipment_health_service_test.dart`, `packages/nightshade_app/lib/screens/analytics/widgets/science_insights_panel.dart` | Equipment-health scoring now tracks degrading guiding / device health trends and emits predictive maintenance findings. Verified by targeted core service tests and targeted `dart analyze`. |
| P3-008 | Workflow continuity | Seamless session handoff between devices | `fixed-in-tree` | `packages/nightshade_core/lib/src/services/session_handoff_service.dart`, `packages/nightshade_core/test/services/session_handoff_service_test.dart`, `packages/nightshade_webrtc/lib/src/web_server.dart`, `apps/desktop/lib/headless_api_server.dart` | Session handoff now round-trips portable context bundles and is exposed over collaboration transport and server APIs for cross-device continuation. Verified by targeted core service tests, WebRTC tests, and targeted `dart analyze`. |

## Current Implementation Batch

Completed in this pass:

- Established the full persistent P3 tracker and preserved the standing operator note not to stop before full completion
- Re-audited every roadmap P3 item against the current tree and implemented the remaining gaps end to end
- Verified the completed P3 work across native, Dart, desktop, and WebRTC surfaces

## Verification Log

- `cargo check -p nightshade_bridge` in `native/nightshade_native`
- `cargo test -p nightshade_bridge builtin_guider --lib` in `native/nightshade_native` with `apps/desktop`, `apps/desktop/windows`, `apps/desktop/build/windows/x64/runner/Debug`, and `native/nightshade_native/target/debug` prepended to `PATH`
- `cargo test -p nightshade_imaging platesolve --lib` in `native/nightshade_native`
- `flutter test test/live_collaboration_session_test.dart test/web_server_collaboration_test.dart` in `packages/nightshade_webrtc`
- `flutter test test/services/frame_quality_assessment_service_test.dart test/services/session_optimizer_service_test.dart test/services/optical_train_diagnostics_service_test.dart test/services/equipment_health_service_test.dart test/services/session_handoff_service_test.dart` in `packages/nightshade_core`
- `dart analyze lib/src/web_server.dart lib/src/collaboration/live_collaboration_session.dart` in `packages/nightshade_webrtc`
- `dart analyze lib/src/services/frame_quality_assessment_service.dart lib/src/services/session_optimizer_service.dart lib/src/services/optical_train_diagnostics_service.dart lib/src/services/equipment_health_service.dart lib/src/services/session_handoff_service.dart` in `packages/nightshade_core`
- `dart analyze lib/main.dart lib/headless_api_server.dart` in `apps/desktop` reported only pre-existing `avoid_print` infos and one existing unused helper warning; no blocking P3 errors were introduced

## Notes

- The P3 source list comes from the roadmap table rather than the earlier remediation tables; this tracker intentionally preserves every roadmap-listed P3 item.
- Final status for this pass: every row above is `fixed-in-tree` and verified in the current worktree.
