# Public Release Checklist Audit

- Source checklist: `docs/production-readiness/public-release-master-checklist.md`
- Checklist items: `284`
- Checked items: `0`
- Unchecked items: `284`
- Checked items without evidence notes: `0`
- Known limitations referenced: `true`
- Supported hardware by platform referenced: `true`

This audit is a repeatable status artifact for the release checklist. It does not provide final sign-off by itself, and unchecked items remain release blockers.

## Sections

| Section | Total | Checked | Unchecked | Checked without evidence |
| --- | ---: | ---: | ---: | ---: |
| Audit Method | 7 | 0 | 7 | 0 |
| Evidence Rules | 6 | 0 | 6 | 0 |
| Global Release Gates | 30 | 0 | 30 | 0 |
| App-Wide Audit Standards | 21 | 0 | 21 | 0 |
| First-Run and Core Journeys | 9 | 0 | 9 | 0 |
| Shell, Navigation, and Windowing | 7 | 0 | 7 | 0 |
| Dashboard | 7 | 0 | 7 | 0 |
| Equipment and Connection Management | 15 | 0 | 15 | 0 |
| Imaging | 11 | 0 | 11 | 0 |
| Focus and Autofocus | 6 | 0 | 6 | 0 |
| Guiding | 6 | 0 | 6 | 0 |
| Sequencer | 11 | 0 | 11 | 0 |
| Planetarium | 7 | 0 | 7 | 0 |
| Planner | 6 | 0 | 6 | 0 |
| Suggestions | 4 | 0 | 4 | 0 |
| Analytics | 7 | 0 | 7 | 0 |
| Diagnostics | 6 | 0 | 6 | 0 |
| Weather and Safety | 6 | 0 | 6 | 0 |
| Framing, Polar Alignment, Flat Wizard, and Other Capture Utilities | 5 | 0 | 5 | 0 |
| Observation Log and Observing Lists | 4 | 0 | 4 | 0 |
| Settings | 7 | 0 | 7 | 0 |
| Remote Access | 14 | 0 | 14 | 0 |
| Desktop Web Dashboard | 10 | 0 | 10 | 0 |
| Plugins | 4 | 0 | 4 | 0 |
| Mobile Experience | 8 | 0 | 8 | 0 |
| Accessibility, Copy, and Localization | 6 | 0 | 6 | 0 |
| Data Integrity, Persistence, and Recovery | 6 | 0 | 6 | 0 |
| Notifications, Alerts, and Feedback | 4 | 0 | 4 | 0 |
| Native Bridge and Backend Integrity | 5 | 0 | 5 | 0 |
| Performance and Stability | 5 | 0 | 5 | 0 |
| Security and Privacy | 8 | 0 | 8 | 0 |
| Updater and Release Delivery | 4 | 0 | 4 | 0 |
| Packaging and Public Release Operations | 10 | 0 | 10 | 0 |
| Audit Log | 3 | 0 | 3 | 0 |
| Final Sign-Off | 9 | 0 | 9 | 0 |

## First Unchecked Items

- `line 16` `Audit Method`: For each feature, document the intended user-facing behavior before judging the implementation.
- `line 17` `Audit Method`: For each feature, verify the implemented behavior in code and in the running UI.
- `line 18` `Audit Method`: For each feature, compare intended behavior vs actual behavior and record any mismatch.
- `line 19` `Audit Method`: For each feature, review the happy path, likely user mistakes, and failure/recovery paths.
- `line 20` `Audit Method`: For each feature, verify that the UX explains the system state clearly enough for a first-time user.
- `line 21` `Audit Method`: For each feature, verify persistence, restart behavior, and cross-screen state consistency where applicable.
- `line 22` `Audit Method`: For each feature, capture release notes: approved, blocked, or out of scope.
- `line 36` `Evidence Rules`: Every completed item has a short note with evidence.
- `line 37` `Evidence Rules`: Every release-blocking issue found during review is linked to a concrete file, flow, or repro.
- `line 38` `Evidence Rules`: Every unchecked item is treated as not yet release-approved.
- `line 39` `Evidence Rules`: Any feature that cannot pass this checklist is hidden or explicitly removed from the release scope.
- `line 40` `Evidence Rules`: Every item marked complete has been checked against both code structure and user experience, not just compilation.
- `line 41` `Evidence Rules`: Every blocker is categorized as functionality, UX, performance, security, packaging, or process.
- `line 45` `Global Release Gates`: `dart run melos run audit:public-release-gate` reports `Decision: READY`.
- `line 134` `Global Release Gates`: `dart run melos run analyze:production` passes with `Production: errors=0, warnings=0`.
- `line 139` `Global Release Gates`: `dart run melos run audit:fail-closed` passes.
- `line 145` `Global Release Gates`: `dart run melos run audit:placeholders` passes.
- `line 149` `Global Release Gates`: `dart run melos run audit:ui-consistency` runs and produces a reviewed UI consistency report.
- `line 159` `Global Release Gates`: `cargo check --manifest-path native/nightshade_native/bridge/Cargo.toml` passes.
- `line 169` `Global Release Gates`: Desktop app tests pass.
- `line 172` `Global Release Gates`: Android release APK builds successfully.
- `line 188` `Global Release Gates`: Core package tests pass.
- `line 191` `Global Release Gates`: App package tests pass.
- `line 194` `Global Release Gates`: Plugin package tests pass.
- `line 197` `Global Release Gates`: Any generated bindings or generated database files that are part of the release are up to date.
- `line 198` `Global Release Gates`: Database migration tests verify older schemas converge to the current table set and default settings.
- `line 202` `Global Release Gates`: Packaged assets required by shipped features are present in the release bundle.
- `line 210` `Global Release Gates`: Workspace packages declare direct dependencies for shipped `lib/` imports.
- `line 218` `Global Release Gates`: Platform unsupported items match `docs/production-readiness/feature-parity-matrix.md`, in-app Platform Capabilities, and `/api/info.platformCapabilities`.
- `line 245` `Global Release Gates`: Headless route registration, `/api/info`, generated OpenAPI, and `NetworkBackend` call sites stay aligned.
- `line 255` `Global Release Gates`: Public supported-hardware docs match `docs/supported-hardware-by-platform.md`, platform capabilities, and hardware smoke evidence.
- `line 270` `Global Release Gates`: Remote clients reject too-old, too-new, missing, or malformed server API versions before switching into network-control mode.
- `line 280` `Global Release Gates`: Headless runtime self-test reports backend, platform, device-driver availability, storage paths, auth mode, and route count via `/api/self-test`.
- `line 291` `Global Release Gates`: Headless API docs are generated from the route table and available at `/api/openapi.json`.
- `line 299` `Global Release Gates`: Headless contract tests compare registered server routes, advertised `/api/info` and OpenAPI routes, and `NetworkBackend` call sites.
- `line 303` `Global Release Gates`: Headless control endpoints reject oversized request bodies, with explicit larger limits only for image-processing JSON and backup upload.
- `line 312` `Global Release Gates`: Headless control endpoints apply per-client, per-endpoint rate limits with stricter limits for slew, park/unpark, device connect/disconnect, sequence start/stop, dome movement, and backup restore.
- `line 319` `Global Release Gates`: Headless high-risk remote commands produce audit log entries with request ID, client key, action, route, and completion status.
- `line 327` `Global Release Gates`: Headless scoped tokens enforce view, control, and admin access boundaries.
- `line 339` `Global Release Gates`: Mobile and remote clients send WebSocket heartbeats, consume `pong` replies from desktop and WebRTC servers, and reconnect after heartbeat timeout.
- `line 378` `Global Release Gates`: Release branch staging area is clean and intentionally scoped.
- `line 408` `Global Release Gates`: No critical feature depends on untracked or accidentally omitted files.
- `line 421` `Global Release Gates`: Migration, backup, and restore docs are published in `docs/migration-backup-restore.md` and match the BackupService, Settings UI, and headless backup routes.
- `line 431` `App-Wide Audit Standards`: Every major feature has a documented "supposed to work like this" summary before sign-off.
- `line 432` `App-Wide Audit Standards`: Every major feature has been checked for "implemented differently than implied by UI copy or docs".
- `line 433` `App-Wide Audit Standards`: Every major screen has a clear purpose on first open.
- `line 434` `App-Wide Audit Standards`: Every major screen has acceptable empty, loading, success, and error states.
- `line 435` `App-Wide Audit Standards`: No screen contains fake telemetry, placeholder values, misleading labels, or dead controls.
- `line 436` `App-Wide Audit Standards`: No screen contains visible encoding defects or broken formatting.
- `line 437` `App-Wide Audit Standards`: Copy is consistent across shell, settings, dialogs, toasts, and docs.
- `line 438` `App-Wide Audit Standards`: User actions produce timely, understandable feedback.
- `line 439` `App-Wide Audit Standards`: Long-running actions show progress or a clearly communicated busy state.
- `line 440` `App-Wide Audit Standards`: Errors are actionable and do not expose raw internal noise unless in diagnostics/dev flows.
- `line 441` `App-Wide Audit Standards`: State changes remain consistent across desktop shell, dialogs, overlays, and secondary views.
- `line 442` `App-Wide Audit Standards`: Layouts remain usable on supported desktop and mobile breakpoints.
- `line 443` `App-Wide Audit Standards`: Keyboard and pointer navigation are both workable for critical flows.
- `line 444` `App-Wide Audit Standards`: Focus order and modal dismissal behavior are sane.
- `line 445` `App-Wide Audit Standards`: Scroll behavior, overflow handling, and long-text truncation are acceptable on major screens.
- `line 446` `App-Wide Audit Standards`: Busy states, disabled states, and retry states are visually distinct and understandable.
- `line 447` `App-Wide Audit Standards`: Multi-step flows do not leave the user unsure what to do next.
- `line 448` `App-Wide Audit Standards`: Design-system gallery renders buttons, cards, inputs, tabs, chips, alerts, and status pills across dark, light, compact, and red-night themes.
- `line 455` `App-Wide Audit Standards`: UI consistency audit classifies remaining raw Material colors, raw button styles, large radii, fake callbacks, and unadvertised headless routes.
- `line 456` `App-Wide Audit Standards`: The structure of providers/services/screens remains understandable and maintainable.
- `line 457` `App-Wide Audit Standards`: No critical feature is implemented in a way that is obviously race-prone, misleading, or tightly coupled beyond reason.
- `line 461` `First-Run and Core Journeys`: First launch experience is coherent.
- `line 462` `First-Run and Core Journeys`: First launch does not expose broken or irrelevant settings.
- `line 463` `First-Run and Core Journeys`: App can launch without configured hardware and still feel intentional.
- `line 464` `First-Run and Core Journeys`: App can restart cleanly after settings changes.
- `line 465` `First-Run and Core Journeys`: App can recover after a crash or forced close.
- `line 466` `First-Run and Core Journeys`: Upgrade path from an existing install does not corrupt settings or state.
- `line 481` `First-Run and Core Journeys`: New user can discover the main workflows without dead ends.
- `line 482` `First-Run and Core Journeys`: Shutdown/quit while operations are active behaves safely and predictably.
- `line 483` `First-Run and Core Journeys`: Relaunch after incomplete work restores the right amount of context without misleading the user.
- `line 487` `Shell, Navigation, and Windowing`: Global shell layout is coherent on first launch.
- `line 488` `Shell, Navigation, and Windowing`: Primary navigation reflects the most important workflows.
- `line 489` `Shell, Navigation, and Windowing`: Route changes preserve or intentionally discard state.
- `line 490` `Shell, Navigation, and Windowing`: Back behavior is predictable on mobile and desktop.
- `line 491` `Shell, Navigation, and Windowing`: Dialogs, sheets, overlays, and popovers do not conflict with each other.
- `line 492` `Shell, Navigation, and Windowing`: Status bar reflects real state and remains readable during active operations.
- `line 493` `Shell, Navigation, and Windowing`: Multi-window, external-link, and browser-launch actions behave correctly if in release scope.
- ... 204 more.
