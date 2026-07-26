# Public Release External Evidence

- Passed checks: `3`
- Total checks: `5`
- Template directory: `docs/production-readiness/external-evidence-templates`

This verifier accepts future manual or external evidence only when it matches the required schema. Missing evidence remains blocked.

## Checks

| Status | Check | Evidence | Template |
| --- | --- | --- | --- |
| PASS | Linux release build/package evidence | `docs/production-readiness/linux-release-build-evidence.json` | `docs/production-readiness/external-evidence-templates/linux-release-build-evidence.template.json` |
| PASS | Full hardware/control smoke | `docs/production-readiness/full-hardware-control-smoke-evidence.json` | `docs/production-readiness/external-evidence-templates/full-hardware-control-smoke-evidence.template.json` |
| BLOCKED | Second-device LAN/firewall smoke | `docs/production-readiness/second-device-lan-firewall-smoke-evidence.json` | `docs/production-readiness/external-evidence-templates/second-device-lan-firewall-smoke-evidence.template.json` |
| PASS | Real remote-control actions | `docs/production-readiness/real-remote-control-actions-evidence.json` | `docs/production-readiness/external-evidence-templates/real-remote-control-actions-evidence.template.json` |
| BLOCKED | Final release checklist/sign-off | `docs/production-readiness/final-release-signoff-evidence.json` | `docs/production-readiness/external-evidence-templates/final-release-signoff-evidence.template.json` |

## Linux release build/package evidence

- ID: `linux_release_build`
- Status: `PASS`
- Evidence path: `docs/production-readiness/linux-release-build-evidence.json`
- Template path: `docs/production-readiness/external-evidence-templates/linux-release-build-evidence.template.json`

Requirements:
- Linux platform build command passed.
- Evidence uses metadata schema v2 or newer and records toolchain provenance.
- Package SHA256 sidecar exists and contains the package hash.
- Generated package metadata exists and matches the evidence hash/size.
- Package artifact path exists, size matches, and SHA256 matches.
- Runtime/headless smoke from the Linux artifact passed, covers required checks, and its log exists.
- Linux native shared library and permission notes are recorded.

Issues:
- None.

## Full hardware/control smoke

- ID: `hardware_control_smoke`
- Status: `PASS`
- Evidence path: `docs/production-readiness/full-hardware-control-smoke-evidence.json`
- Template path: `docs/production-readiness/external-evidence-templates/full-hardware-control-smoke-evidence.template.json`

Requirements:
- All required device classes are covered.
- Per-device connect/disconnect and status reads passed.
- Command results cover every required device type and the smoke log exists.

Issues:
- None.

## Second-device LAN/firewall smoke

- ID: `second_device_lan_firewall`
- Status: `BLOCKED`
- Evidence path: `docs/production-readiness/second-device-lan-firewall-smoke-evidence.json`
- Template path: `docs/production-readiness/external-evidence-templates/second-device-lan-firewall-smoke-evidence.template.json`

Requirements:
- A physical second device uses the real LAN URL.
- Evidence records client IP, Windows firewall rule/profile, and network path.
- Dashboard, auth success/failure, WebSocket connection, and reconnect are verified.
- Screenshot/log evidence artifact paths exist.

Issues:
- usedPhysicalSecondDevice must be true.
- clientDevice is required.
- clientIp is required.
- networkPath is required.
- dashboardLoaded must be true.
- authPositivePassed must be true.
- authNegativePassed must be true.
- websocketConnected must be true.
- websocketReconnectObserved must be true.
- evidenceArtifacts must be a non-empty list.

## Real remote-control actions

- ID: `real_remote_control_actions`
- Status: `PASS`
- Evidence path: `docs/production-readiness/real-remote-control-actions-evidence.json`
- Template path: `docs/production-readiness/external-evidence-templates/real-remote-control-actions-evidence.template.json`

Requirements:
- Remote client sends actual safe commands.
- Evidence declares the applicable remote-control device types in scope.
- Command results all pass and include device IDs.
- Post-command state readback and request IDs are recorded in the server audit log.

Issues:
- None.

## Final release checklist/sign-off

- ID: `final_release_signoff`
- Status: `BLOCKED`
- Evidence path: `docs/production-readiness/final-release-signoff-evidence.json`
- Template path: `docs/production-readiness/external-evidence-templates/final-release-signoff-evidence.template.json`

Requirements:
- Reviewer, date, and commit are recorded.
- Decision is ship.
- Commit is a full hash matching current git HEAD.
- Checklist audit has zero unchecked and zero checked-without-evidence items.
- Public release gate decision is READY with no blockers.
- Known limitations, supported hardware, and completed release notes artifacts exist.

Issues:
- reviewer is required.
- date is required.
- commit is required.
- date must be an ISO date in yyyy-mm-dd format.
- commit must be a full 40-character git commit hash.
- decision must be `ship`.
- checklistComplete must be true.
- noUnresolvedBlockers must be true.
- knownLimitationsReviewed must be true.
- releaseNotesReady must be true.
- releaseNotesPath file does not exist: docs/release-notes.md.
- Checklist audit has uncheckedItemCount=5.
- Public release gate must be READY with blockerCount=0; decision=NOT_READY ready=false blockerCount=4.
