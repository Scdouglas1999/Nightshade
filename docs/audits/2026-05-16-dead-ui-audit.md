# Dead-UI / TODO / hardcoded audit — 2026-05-16

Branch: `release/v2.5.0-hardening`  HEAD: `74abe34`  Agent: A5-DEAD-UI-AUDIT

## Summary
- **5 TODOs** found in non-generated source: **0 real, 0 stale, 3 intentional (i18n/observability roadmap with tagged version), 2 in tests/wizard step labels**, **0 placeholders (CLAUDE.md violations)**.
- **0 Rust TODO/FIXME/HACK markers** in `native/nightshade_native/` (excluding `frb_generated.rs`).
- **0 user-visible "coming soon" / "TBD" / "lorem ipsum" / "future update" strings.**
- **0 empty `onPressed: () {}` or `onTap: () {}` handlers in non-test production code** (the single match in `scheduler_tab_content.dart:1418` is an intentional event-swallow on a modal backdrop's inner `GestureDetector` to prevent tap-through; not a button).
- **0 hardcoded magic numbers in UI that should be settings.** All polling/timeout constants live in services and have correct context-driven defaults; user-tunable durations are exposed via `app_settings`/profile providers.
- **5 endpoints that return HTTP 501 ("not yet implemented")** are fail-loud, not silent placeholders.
- **Behavioral-marker spot-check: 10/10 match registered disposition** (line numbers occasionally shifted due to subsequent edits, but the cited safe behavior is present in the surrounding context).

## CLAUDE.md placeholder violations (CRITICAL — should not exist)

**None found.** This branch contains no `// TODO: implement X` placeholders nor `unimplemented!()` / `todo!()` macros in hand-written Rust. All `unimplemented!("")` occurrences are inside `bridge/src/frb_generated.rs` (auto-generated, excluded per audit constraints).

## TODO inventory (all intentional / tracked)

| File:line | Marker | Classification | Notes |
|---|---|---|---|
| `packages/nightshade_app/lib/screens/tutorial/tutorial_step_widget.dart:98` | `TODO(v2.5.x i18n)` | REAL-tracked | Pending i18n sweep; tagged with version milestone. |
| `packages/nightshade_app/lib/screens/tutorial/first_night_wizard.dart:85` | `TODO(v2.5.x i18n)` | REAL-tracked | Same i18n sweep; explicit string list documented. |
| `packages/nightshade_core/lib/src/backend/nightshade_exception.dart:92` | `TODO(v2.7)` | REAL-tracked | Heuristic fallback to be removed once Rust emits structured JSON for all error paths; tracked under audit-observe §10 / roadmap R9. |
| `packages/nightshade_app/test/screens/sequencer/import_summary_dialog_test.dart:18,97` | `'TODO: review filters'` | TEST-FIXTURE | String is a test fixture for an *import-summary* dialog rendering review-needed entries; excluded per audit constraint "don't flag tests' use of placeholders/TODOs". |

No stale TODOs and no placeholders that the audit cycle missed.

## Empty handlers

`packages/nightshade_app/lib/screens/planner/widgets/scheduler_tab_content.dart:1418` — `onTap: () {}` on the inner `GestureDetector` wrapping a modal dialog. **Intentional**: an outer `GestureDetector` at line 1412 calls `onClose` for backdrop taps; the inner empty handler prevents the close-on-tap from firing when the user interacts inside the modal panel. Standard Flutter pattern, not a UX bug. No fix needed.

All other matches were in `packages/nightshade_ui/test/**` (button/dialog widget tests), excluded by constraint.

## Hardcoded values that should be settings

**None that meet the bar.** Verified the most-touched constants:

- `device_service.dart:91-96` — filter-wheel verify (60s timeout, 250ms poll) and focuser-move (300s timeout, 500ms poll). Internal correctness budgets matching ASCOM/Alpaca driver semantics; exposing these to users would invite footguns.
- `device_service.dart:117` — 5-second camera temperature polling. Aligned with cooler-loop time constants; not user-facing.
- `auto_save_service.dart:18` — `backupInterval: const Duration(hours: 24)` is the **constructor default** and is overridable via `copyWith` from user config. The `Duration(minutes: 5)` at line 143 is the initial post-startup backup-check delay (one-shot), not a recurring interval.
- `disk_space_guard.dart:239` — 30s poll interval is the `start()` parameter default, callers can override.
- `scheduler_engine.dart:142` — 500ms re-evaluation debounce (private internal). Documented inline as a coalescing window for burst-emit, not user-tunable.
- `notification_service.dart:34` — 15s default request timeout for Pushover, well-justified.
- `transient_alert_service.dart:35` — 15-minute cache TTL for VSX/TNS responses, well-justified.

Hardcoded URLs are all public-API endpoints (Pushover, OpenMeteo, AAVSO/VSX, TNS, HNSky/ASTAP) — appropriate to ship hardcoded; user credentials/keys are config-supplied separately.

## Placeholder copy

**None user-visible.** All `placeholder` string occurrences are:
- Dart-source comments describing skeleton/shimmer/empty-state widgets (not user-visible).
- `EmptyState(title: 'No science data yet', ...)` and similar explicit empty-state copy — these are documented UX, not placeholders.
- `_EmptyZonePlaceholder` in `zone_layout.dart` — the placeholder *is* the documented edit-mode UX (registered in behavioral register at entry `zone_layout.dart`).
- `framing_sidebar.dart:754` doc-comment describing the "no target selected" card.

## Incorrectly-implemented features

None identified after the following heuristic sweeps:
- Charts with empty/static data sources: science_analytics_tab returns `const []` only when input is empty (correct identity-on-empty), and renders a top-level `EmptyState` when *all* nine data streams are empty (lines 192-209) instead of stacking nine "no data" cards. Confirmed by registered comment.
- Stuck "loading…" indicators: 9 screens render shimmer skeletons but each is gated behind an `AsyncValue` provider that resolves to data or `error`, with `EmptyState` for empty-result.
- Stale-switch / non-updating-counter heuristics: spot-checked `project_tracking_panel`, `session_progress_card`, `equipment_status_widget` — all are `ConsumerWidget` watching live providers.

### Fail-loud HTTP 501 endpoints (NOT bugs — surface errors loudly)

The following 5 headless-API endpoints respond `501 Not Implemented` with explanatory JSON instead of pretending success. They are correctly fail-loud per CLAUDE.md, but the caller should be aware the feature surface exists in the route table:

- `apps/desktop/lib/headless_api/handlers/safety_monitor_handlers.dart:210` — `POST /api/safety/settings`
- `apps/desktop/lib/headless_api/handlers/safety_monitor_handlers.dart:236` — `POST /api/safety/acknowledge`
- `apps/desktop/lib/headless_api/handlers/dome_handlers.dart:114` — `POST /api/dome/sync`
- `apps/desktop/lib/headless_api/handlers/dome_handlers.dart:133` — `POST /api/dome/home`
- `apps/desktop/lib/headless_api/handlers/dome_handlers.dart:138` — `POST /api/dome/halt`

Recommend tracking these in the audit register if not already (they were not found in `behavioral-audit-register.md` under the safety/dome handler keys).

## Behavioral marker spot-check

Sampled 10 representative entries from `docs/production-readiness/behavioral-audit-register.md` (465 entries total).

| # | Entry | Code location verified | Match |
|---|---|---|---|
| 1 | `ascom_wrapper_filterwheel.rs:227:is_moving_error_fallback` (done) | Line 293-297: propagates `get_position()` error via `?`, no error→false coercion. | ✓ |
| 2 | `temperature_compensation.rs:174:absolute_mode_fallback` (done) | Lines 178-188: uses trigger-state `baseline_focuser_position`, establishes on first call rather than fabricating. | ✓ |
| 3 | `instructions.rs:2248:hardcoded_location` / `:2328:polar_twilight_fallback` (done) | Lines 2603 & 2611 — explicit fail-loud on missing observer location and unreachable twilight. | ✓ (line numbers shifted; behavior intact) |
| 4 | `flat_wizard.rs:649:best_guess_success` (done) | Line ~712: returns `Err(...)` with actionable message on non-convergence. | ✓ |
| 5 | `device_ops.rs:347:simulated_runtime_path` (explicit_unsupported) | `NullDeviceOps` impl at line 347, only constructed when release-mode simulation is off. | ✓ |
| 6 | `update_manifest.dart:70:literal_null_coalesce` (accepted_modeled_approximation) | Line 70: `int.tryParse(p) ?? 0` in `versionParts`. Read-only comparator path. | ✓ |
| 7 | `discovery.dart:84:empty_catch` (explicit_unsupported) | Lines 82-89: documented idempotent socket-close swallow with full inline rationale. | ✓ |
| 8 | `catalog.dart:47:literal_null_coalesce` (accepted_modeled_approximation) | Line 47: `_cachedObjects?.length ?? 0`, pre-load count display. | ✓ |
| 9 | `sky_view.dart:94:guessed_now_timestamp` (accepted_modeled_approximation) | Line 97: `widget.observationTime ?? DateTime.now()` — live-mode default. | ✓ |
| 10 | `catalog_manager.dart:1141:literal_null_coalesce` (accepted_modeled_approximation) | Line 1141: HYG `id` field tolerant parse. | ✓ |

**Result: 10/10 matched. 0 mismatches.** Some line numbers in the register have drifted due to subsequent edits, but the documented behavior is present in the corresponding code regions in every sampled case.

## Conclusion

The branch is exceptionally clean. There are no CLAUDE.md placeholder/stub violations, no empty UI handlers that look like buttons but do nothing, no user-visible "coming soon" copy, no hardcoded URLs/paths that should be settings, and no chart-with-static-data or stale-state UI anti-patterns. The remaining TODO markers (3) all target specific future-version milestones (`v2.5.x` i18n, `v2.7` exception-decode cleanup) and are not placeholders. The five HTTP-501 headless endpoints fail loudly with explicit error bodies and are CLAUDE.md-compliant, though they would benefit from explicit register entries documenting their unsupported-by-design status.
