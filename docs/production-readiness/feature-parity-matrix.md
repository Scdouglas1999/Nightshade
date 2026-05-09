# Feature Parity Matrix

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

## Driver Backend Platform Matrix

This matrix is mirrored in-app under Settings > Connection > Platform Capabilities and in the headless `/api/info` response under `platformCapabilities`.

| Driver backend | Windows | Linux | macOS | Contract |
| --- | --- | --- | --- | --- |
| ASCOM COM | Available | Unsupported | Unsupported | Windows-only because it requires COM and local ASCOM drivers. Linux/macOS clients must show this as unsupported, not hidden as a missing scan result. |
| ASCOM Alpaca | Available | Available | Available | Network API for ASCOM-compatible devices. Device-specific capability gaps must be returned by the connected driver. |
| INDI | Available | Available | Available | Requires a reachable INDI server. Missing or unreachable servers must report a deterministic connection error. |
| Native SDK | Capability-gated | Capability-gated | Capability-gated | Availability depends on packaged vendor SDK libraries and installed OS drivers. Unsupported SDKs must disable controls with an explicit reason. |
| Simulator | Capability-gated | Capability-gated | Capability-gated | Simulator support is workflow-specific; use ASCOM, Alpaca, or INDI simulator drivers for hardware-like smoke tests unless an in-app simulator path is explicitly enabled. |
