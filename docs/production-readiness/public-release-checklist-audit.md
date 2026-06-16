# Public Release Checklist Audit

- Source checklist: `docs/production-readiness/public-release-master-checklist.md`
- Checklist items: `16`
- Checked items: `6`
- Unchecked items: `10`
- Checked items without evidence notes: `0`
- Known limitations referenced: `true`
- Supported hardware by platform referenced: `true`

This audit is a repeatable status artifact for the release checklist. It does not provide final sign-off by itself, and unchecked items remain release blockers.

## Sections

| Section | Total | Checked | Unchecked | Checked without evidence |
| --- | ---: | ---: | ---: | ---: |
| Code Quality Gates | 3 | 3 | 0 | 0 |
| Release Branch And Packaging | 4 | 2 | 2 | 0 |
| Hardware And Remote Control | 3 | 0 | 3 | 0 |
| Mobile And Migration | 4 | 1 | 3 | 0 |
| Final Sign-Off | 2 | 0 | 2 | 0 |

## First Unchecked Items

- `line 27` `Release Branch And Packaging`: Final release PR branch is clean, non-main, and validated against the
- `line 36` `Release Branch And Packaging`: Linux release package is built and smoke-tested from a real Linux
- `line 44` `Hardware And Remote Control`: Full hardware/control smoke covers required real or simulator-backed
- `line 48` `Hardware And Remote Control`: Second-device LAN/firewall remote access smoke passes from a physical
- `line 52` `Hardware And Remote Control`: Real remote-control actions are proven through dashboard, mobile, or
- `line 59` `Mobile And Migration`: Android emulator remote smoke artifacts exist and show a connected remote
- `line 64` `Mobile And Migration`: Android emulator reconnect smoke records reconnect behavior.
- `line 69` `Mobile And Migration`: Older real Nightshade profile/database migration is verified from a copied
- `line 75` `Final Sign-Off`: Public release external evidence validator passes for Linux build,
- `line 79` `Final Sign-Off`: Final ship/no-ship decision records reviewer, date, commit, version,
