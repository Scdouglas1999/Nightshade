# Feature Parity Matrix

_Last updated: 2026-05-11 (v2.5.0)._

This matrix defines launch behavior by platform. Every row must be either:
- Implemented with equivalent behavior, or
- Explicitly capability-gated with a deterministic unsupported reason.

| Feature | Desktop | Mobile | Headless | Contract |
| --- | --- | --- | --- | --- |
| Device discovery/connect | Implemented | Implemented (remote) | Implemented (API) | No silent no-op; return explicit connection errors. |
| Capture start/stop | Implemented | Implemented (remote trigger) | Implemented (API trigger) | Capture path never blocks on science processing. |
| Sequencer run/pause/resume/stop | Implemented | Implemented (remote control) | Implemented (API) | Checkpoint + fail-closed policy consistent. |
| Science overlays and quality maps | Implemented | Implemented | N/A UI | Headless exposes same metrics via backend APIs. |
| Guiding (PHD2) | Implemented | Implemented (remote control) | Implemented (API) | Unsupported environments expose capability=false. |
| Mount tracking-rate changes | Capability-gated by driver | Capability-gated by driver | Capability-gated by driver | Unsupported rates return `NotSupported`; controls disabled. |
| Filter/focuser/rotator operations | Implemented | Implemented (remote) | Implemented (API) | No pseudo-success when unsupported. |
| FITS save/export | Implemented | Implemented | Implemented | Errors are explicit and surfaced to caller. |
| Logging/diagnostics | Implemented | Implemented | Implemented | Correlation IDs required for command flows. |
| Settings persistence | Implemented | Implemented | Implemented | Schema and defaults match across launch platforms. |
| Plate solving | External only [^solver], with auto-detect + verify-solve UX [^solver-ux] | External only (via remote desktop solver) | External only (via host solver) | Requires ASTAP or astrometry.net to be installed and configured. No internal solver ships in v2.5.0. Settings → Plate Solving auto-detects both solvers on all three OSes, verifies the binary, and surfaces a reusable required-banner from the centering / framing / polar-alignment flows. |
| Dynamic scheduling (RoboTarget-class) | Implemented (Scheduler screen) [^scheduler] | Implemented (Scheduler screen via shared shell) | Implemented (API + WebSocket decision stream) | Per-target integration goals, time-window / moon-illumination / custom-horizon constraints, hysteresis-stable selection, event-driven re-evaluation on weather / guiding / mount changes. |
| Cosmetic correction (defect map) | Implemented (Imaging → Image calibration) [^defect-map] | Implemented (remote trigger) | Implemented (API) | Multi-temperature buckets, neighborhood-median repair at capture time, persistent `.ndm` file per camera + sensor size + temperature bucket. Lets users image without darks while still hiding hot / cold pixels and dust shadows. |
| Sequence migration / import | Implemented (Sequencer → Import sequence) [^nina-import] | N/A (initiated from desktop / headless) | Implemented (API endpoint) | NINA Advanced Sequencer (`.json`) and SGP (`.sgf`) sequence files import with auto-format detection, node-mapping summary table, force-import override for unsupported nodes, and two persistence destinations (open-in-editor / save-to-library). Unmapped node types raise a structured `UnsupportedNodeError` rather than silently dropping. |

[^solver]: The v2.5.0 pre-release audit (§6.1) found that the previously
shipped "internal" plate solver returned the commanded RA/Dec or FITS-header
coordinates verbatim — no astrometric matching against any catalog was being
performed — while still reporting `success: true`. That code path has been
removed from the public solve surface in v2.5.0. A real geometric matcher
(quad hashing against a Gaia-DR3 / Tycho-2 subset) is queued for a future
release; until then, plate solving requires ASTAP or astrometry.net to be
installed on the host. The UI surfaces a guided install dialog when neither
solver is detected. See `docs/plans/2026-05-09-v250-audit-fixes.md` §6.1 and
§6.2 for the audit context.

[^solver-ux]: The Settings → Plate Solving screen (W6-SOLVER-UX) auto-detects
ASTAP and Astrometry.net across every standard install path on Windows,
macOS, and Linux (including ASTAP CLI / GUI builds, Homebrew
`astrometry.net`, and Cygwin-installed `solve-field`); detects catalog
presence separately so "binary OK, no catalog" is distinct from "not
installed"; runs a Verify-solve binary-health check on save (currently
`<solver> --help` — a full end-to-end synthetic-FITS verify is tracked for
v2.5.x); and offers an auto-fallback chain when both solvers are present.
The previous "ASTAP not found" snackbar in `CenteringDialog` has been
replaced with a reusable `PlateSolverRequiredBanner` + `go_router` CTA so
the user is never stranded mid-flow.

[^scheduler]: The Scheduler screen (W6-SCHED) provides RoboTarget-class
multi-target selection over a single observing slot. Per-target integration
goals are filter-specific (e.g. L: 4h, R/G/B: 2h each, Ha: 6h). Constraints
cover time window (UTC or "after astronomical twilight"), moon illumination
cap, minimum moon separation, and a samples-based custom horizon profile
(separate from the legacy 8-point compass mask in settings). Target
selection is hysteresis-stable: a challenger displaces the running target
only when its weighted score exceeds the current target's by the configured
`hysteresisRatio` (default 1.20×). Re-evaluation happens on a fixed cadence
and on EventBus events for weather, guiding, and mount-state changes. The
decision panel exposes the full per-factor scoring breakdown and the
runner-up so the user can audit every switch. Known v2.5.x follow-up: the
hysteresis ratio compares the final `totalScore`, which folds in the
`userPriority` scoring weight; the default weights may need tuning so user
priority alone can flip the hysteresis without help from other factors
(`packages/nightshade_core/lib/src/services/scheduler/scheduler_engine.dart:348`).

[^defect-map]: Defect-map cosmetic correction (W6-DEFECT) eliminates hot
pixels, cold pixels, and small dust shadows from lights at capture time,
allowing imaging sessions to skip dark frames while still producing clean
stacks. A defect map is built from a small stack of dark frames (minimum 5
by default — fewer is a structured error, not a silent fallback) and
persisted as an `.ndm` file keyed by camera ID + sensor size + temperature
bucket (decicelsius). Repair uses the median of valid neighbours, applied
before the frame is written. The imaging-screen calibration section
surfaces explanatory tooltips for every disabled-control state (no camera,
unknown sensor size, no cooler telemetry yet). Known v2.5.x follow-up: the
`PlatformInt64 lastRebuiltUnixSeconds` field is currently assigned straight
into a Dart `int` in `DefectMapService._fromBridge`
(`packages/nightshade_core/lib/src/services/calibration/defect_map_service.dart:85`) —
safe on desktop / mobile, would not compile under web (web is not a
supported target in v2.5.0).

[^nina-import]: NINA / SGP sequence import (W6-NINA-IMPORT) auto-detects
file format from extension and content shape, maps source node types to
Nightshade types via `canonical_node_mapper`, and offers two persistence
destinations: "Open in editor" (load into the active sequencer) and "Save
to library" (persist via `SequenceRepository` without disturbing the
current edit). Both paths persist; only "Open in editor" also calls
`currentSequenceProvider`. Unsupported node types raise a structured
`UnsupportedNodeError` carrying the offending source type; the user can
explicitly retry with a force-import flag, which preserves the raw scalar
fields of the unsupported node rather than dropping them. The full type
table for both source formats lives in `docs/sequence-import-formats.md`.
Known v2.5.x follow-up: the test fixtures
(`packages/nightshade_core/test/services/import/fixtures/nina_basic.json`,
`nina_unsupported.json`) were authored from public NINA Advanced-Sequencer
documentation rather than from a verbatim recent NINA export; a
verification pass against a real current-NINA-release Advanced Sequencer
JSON is recommended before any "imports losslessly" marketing claim.

## Driver Backend Platform Matrix

This matrix is mirrored in-app under Settings > Connection > Platform Capabilities and in the headless `/api/info` response under `platformCapabilities`.

| Driver backend | Windows | Linux | macOS | Contract |
| --- | --- | --- | --- | --- |
| ASCOM COM | Available | Unsupported | Unsupported | Windows-only because it requires COM and local ASCOM drivers. Linux/macOS clients must show this as unsupported, not hidden as a missing scan result. |
| ASCOM Alpaca | Available | Available | Available | Network API for ASCOM-compatible devices. Device-specific capability gaps must be returned by the connected driver. |
| INDI | Available | Available | Available | Requires a reachable INDI server. Missing or unreachable servers must report a deterministic connection error. |
| Native SDK | Capability-gated | Capability-gated | Capability-gated | Availability depends on packaged vendor SDK libraries and installed OS drivers. Unsupported SDKs must disable controls with an explicit reason. |
| Simulator | Capability-gated | Capability-gated | Capability-gated | Simulator support is workflow-specific; use ASCOM, Alpaca, or INDI simulator drivers for hardware-like smoke tests unless an in-app simulator path is explicitly enabled. |

## Known limitations in v2.5.0

See `docs/production-readiness/v2.5.0-known-limitations.md` for items
deliberately deferred from the v2.5.0 release.
