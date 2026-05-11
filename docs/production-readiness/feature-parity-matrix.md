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
| Plate solving | External only [^solver] | External only (via remote desktop solver) | External only (via host solver) | Requires ASTAP or astrometry.net to be installed and configured. No internal solver ships in v2.5.0. |

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
