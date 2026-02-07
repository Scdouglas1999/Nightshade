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
