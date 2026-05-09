# Known Limitations

This page is the public-release holding area for limitations that are accepted
for a release candidate. Do not use it to hide blockers. An accepted limitation
must be documented, understandable to users, paired with a workaround when one
exists, and reflected in release notes.

## Acceptance Rules

A limitation can be accepted only when all of these are true:

- the behavior is intentional for the release scope
- the user impact is documented plainly
- unsupported controls are disabled or fail with an explicit reason
- safety-critical workflows fail closed
- the limitation is included in release notes
- a future owner or tracking issue exists when follow-up is expected

If any item affects mount safety, unattended imaging safety, data loss,
credential exposure, or package install/upgrade integrity, treat it as a
release blocker unless the release explicitly removes that workflow from scope.

## Current Release Candidate Limitations

Fill this table during release-candidate review. Leave no row with placeholder
text in the published release.

| Area | Limitation | Impact | Workaround | Release blocker? | Owner/issue |
| --- | --- | --- | --- | --- | --- |
| Hardware/platform | Native SDK support is capability-gated by packaged vendor libraries and OS driver availability. | Some vendor devices may require ASCOM, Alpaca, or INDI instead of native mode. | Use a verified driver backend listed in `docs/supported-hardware-by-platform.md`. | No, if unsupported native paths are not advertised as shipped. | Track in `docs/production-readiness/public-release-master-checklist.md` under supported hardware and packaging gates. |
| Hardware/platform | ASCOM COM is Windows-only. | Linux and macOS users cannot use local ASCOM COM drivers directly. | Use ASCOM Alpaca/ASCOM Remote, INDI, or another supported backend. | No. | Track in `docs/production-readiness/feature-parity-matrix.md` and platform-capability verification. |
| Hardware/platform | Native DSLR control for Canon/Nikon is not a public-release guarantee. | DSLR users may need an external driver/backend. | Use supported ASCOM, INDI, or Alpaca workflows where available. | No, if docs and release notes do not advertise native DSLR support. | Track in `docs/supported-hardware-by-platform.md` and release notes scope review. |
| Hardware/platform | INDI weather and switch parity is not fully verified for release-critical safety. | Linux/macOS observatory safety may require another backend. | Use a verified Alpaca or ASCOM safety/weather path for unattended operation. | Yes for unattended safety claims unless verified. | Track in hardware smoke evidence and `docs/production-readiness/feature-parity-matrix.md`. |
| Remote/headless | Scoped tokens are coarse-grained (`view`, `control`, `admin`) rather than custom per-route roles. | Operators cannot yet define custom roles for a specific device or workflow. | Issue separate view/control/admin tokens and keep admin tokens limited to trusted operators. | No, if coarse scopes meet the release security model. | Track in Remote Access and Security sections of `docs/production-readiness/public-release-master-checklist.md`. |

## Unsupported By Platform

Platform-specific unsupported items must match the Platform Capabilities UI,
`/api/info.platformCapabilities`, and
`docs/production-readiness/feature-parity-matrix.md`.

| Feature/backend | Windows | Linux | macOS | User-facing reason |
| --- | --- | --- | --- | --- |
| ASCOM COM | Available | Unsupported | Unsupported | Requires Windows COM and locally installed ASCOM drivers. |
| ASCOM Alpaca | Available | Available | Available | Network backend; device-specific capability gaps are reported by the Alpaca server. |
| INDI | Available | Available | Available | Requires a reachable INDI server and driver support for the device capability. |
| Native SDK | Capability-gated | Capability-gated | Capability-gated | Requires packaged vendor SDK libraries and supported OS drivers. |
| Simulator | Capability-gated | Capability-gated | Capability-gated | Workflow-specific; use ASCOM, Alpaca, or INDI simulator drivers for hardware-like smoke tests unless an in-app simulator path is explicitly enabled. |

## Release Notes Checklist

Before publishing release notes, verify that each accepted limitation has:

- matching wording in release notes
- a support-matrix entry if hardware/platform related
- an in-app disabled state or explicit error path where applicable
- a troubleshooting or setup doc link when users can self-correct
- a tracking issue or owner for follow-up
