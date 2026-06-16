# Release Staging Audit

- Branch: `release/hardening-audit-2026-06-16`
- HEAD: `bd4b2544`
- Total changed/untracked entries: `189`
- Tracked modified/added/deleted entries: `188`
- Untracked entries: `1`
- Deleted entries: `1`
- Generated entries: `0`
- Binary/evidence/native artifact entries: `1`
- Untracked release-critical entries: `0`

This is a scoping report only. It does not make the worktree clean and does not prove a release branch or PR has been created.

## Category Summary

| Category | Count | Untracked |
| --- | ---: | ---: |
| app-ui | 22 | 0 |
| binary-native-artifact | 1 | 0 |
| bridge | 1 | 0 |
| core | 25 | 0 |
| docs | 3 | 0 |
| headless-remote | 33 | 0 |
| native-rust | 18 | 0 |
| other | 17 | 1 |
| release-evidence-docs | 47 | 0 |
| release-tooling | 2 | 0 |
| remote-protocol | 3 | 0 |
| tests | 14 | 0 |
| tooling | 2 | 0 |
| updater | 1 | 0 |

## Required Split Before PR

- Review generated files separately from human-authored source.
- Review binary/native artifacts separately from source diffs.
- Stage release evidence docs and production tools intentionally; many are untracked.
- Do not cut a public tag from this worktree until untracked release-critical entries are either staged or explicitly excluded.


## Untracked Release-Critical Entries

None.

## Binary / Evidence Artifact Entries

- `M ` `docs/design/goldens/surface-run-session-progress.png` (binary-native-artifact)

## Generated Entries

None.
