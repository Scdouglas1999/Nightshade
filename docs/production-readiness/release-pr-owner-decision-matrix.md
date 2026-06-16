# Release PR Owner Decision Matrix

- Source split plan: `docs/production-readiness/release-pr-split-plan.json`
- Source generated at: `2026-06-16T19:35:32.397361Z`
- Branch at planning time: `release/hardening-audit-2026-06-16`
- HEAD at planning time: `bd4b2544`
- Buckets: `8`
- Paths: `189`

This file turns the generated pathspec buckets into owner-reviewable PR drafts and validation rules. It does not stage files or approve any bucket by itself.

## Decision Groups

| Group | Buckets | Paths | Validation rule | Related release list | Pathspecs |
| --- | ---: | ---: | --- | --- | --- |
| Must Ship | 6 | 187 | `required_all` | `docs/production-readiness/release-pr-lists/01-must-ship.txt` | `docs/production-readiness/release-pr-pathspecs/02-release-infra-evidence.txt`<br>`docs/production-readiness/release-pr-pathspecs/03-headless-remote-api.txt`<br>`docs/production-readiness/release-pr-pathspecs/04-native-driver-bridge.txt`<br>`docs/production-readiness/release-pr-pathspecs/05-core-data-model.txt`<br>`docs/production-readiness/release-pr-pathspecs/06-desktop-ui-workflows.txt`<br>`docs/production-readiness/release-pr-pathspecs/07-tests-and-support-tooling.txt` |
| Generated Only | 0 | 0 | `optional_all_or_none` | `docs/production-readiness/release-pr-lists/02-generated-only.txt` |  |
| Binary / Evidence | 1 | 1 | `optional_all_or_none` | `docs/production-readiness/release-pr-lists/03-binary-evidence.txt` | `docs/production-readiness/release-pr-pathspecs/01-binary-and-evidence-artifacts.txt` |
| Defer / Exclude | 1 | 1 | `forbidden` | `docs/production-readiness/release-pr-lists/04-defer-exclude.txt` | `docs/production-readiness/release-pr-pathspecs/08-out-of-release-scope-review.txt` |

## Release Triage Lists

These aggregate lists classify every dirty path by release triage. The decision groups above classify PR validation buckets, so counts can differ when a validation bucket contains both release-critical and support paths.

| List | Paths | Pathspec | Description |
| --- | ---: | --- | --- |
| Must Ship | 163 | `docs/production-readiness/release-pr-lists/01-must-ship.txt` | Release-critical source, docs, and tooling paths that are not generated outputs or binary/evidence artifacts. |
| Generated Only | 0 | `docs/production-readiness/release-pr-lists/02-generated-only.txt` | Generated files that should be reviewed against their source changes and generator commands. |
| Binary And Evidence | 1 | `docs/production-readiness/release-pr-lists/03-binary-evidence.txt` | Binary payloads, screenshots, APKs, DLLs, and other evidence artifacts that need explicit artifact review. |
| Defer Or Exclude | 25 | `docs/production-readiness/release-pr-lists/04-defer-exclude.txt` | Non-release-critical paths that need owner review before they are staged into a public release branch. |

## Validation Commands

- Validate currently staged index: `dart run tools/production/release_pr_staged_branch_validator.dart --mode=index`
- Validate a committed PR branch against main: `dart run tools/production/release_pr_staged_branch_validator.dart --mode=branch --base=main`

## Draft PR Descriptions

### Binary And Evidence Artifacts

- Decision group: `Binary / Evidence`
- Bucket ID: `binary-and-evidence-artifacts`
- Paths: `1`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/01-binary-and-evidence-artifacts.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/01-binary-and-evidence-artifacts.txt`

Suggested PR title:

```text
Release staging: Binary And Evidence Artifacts
```

Suggested PR body:

```markdown
## Scope
Review DLLs, APKs, screenshots, databases, and other binary artifacts outside normal source diffs.

## Owner Decision
- Decision group: `Binary / Evidence`
- Validation rule: `optional_all_or_none`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/01-binary-and-evidence-artifacts.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/01-binary-and-evidence-artifacts.txt`

## Counts
- Paths: `1`
- Tracked changes: `1`
- Untracked: `0`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `1`
- Release-critical: `0`

## Review Notes
Keep release payload binaries and smoke evidence in a deliberate artifact review; exclude scratch screenshots and research blobs from the release PR.

## Category Mix
- `binary-native-artifact`: `1`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Release Infrastructure And Evidence

- Decision group: `Must Ship`
- Bucket ID: `release-infra-evidence`
- Paths: `67`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/02-release-infra-evidence.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/02-release-infra-evidence.txt`

Suggested PR title:

```text
Release staging: Release Infrastructure And Evidence
```

Suggested PR body:

```markdown
## Scope
Keep release gates, production audit tools, public readiness docs, and operational docs together.

## Owner Decision
- Decision group: `Must Ship`
- Validation rule: `required_all`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/02-release-infra-evidence.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/02-release-infra-evidence.txt`

## Counts
- Paths: `67`
- Tracked changes: `67`
- Untracked: `0`
- Deleted: `1`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `67`

## Review Notes
Stage audit tooling and evidence docs as the release-readiness PR only after confirming each artifact is current and reproducible.

## Category Mix
- `docs`: `3`
- `other`: `15`
- `release-evidence-docs`: `47`
- `release-tooling`: `2`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Headless Remote API And Dashboard

- Decision group: `Must Ship`
- Bucket ID: `headless-remote-api`
- Paths: `33`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/03-headless-remote-api.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/03-headless-remote-api.txt`

Suggested PR title:

```text
Release staging: Headless Remote API And Dashboard
```

Suggested PR body:

```markdown
## Scope
Review headless server routes, auth policy, dashboard assets, LAN behavior, and WebSocket changes as one API surface.

## Owner Decision
- Decision group: `Must Ship`
- Validation rule: `required_all`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/03-headless-remote-api.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/03-headless-remote-api.txt`

## Counts
- Paths: `33`
- Tracked changes: `33`
- Untracked: `0`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `30`

## Review Notes
Pair this bucket with route contract tests, dashboard smoke logs, auth/LAN evidence, and reconnect evidence.

## Category Mix
- `headless-remote`: `33`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Native Driver And Bridge Source

- Decision group: `Must Ship`
- Bucket ID: `native-driver-bridge`
- Paths: `19`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/04-native-driver-bridge.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/04-native-driver-bridge.txt`

Suggested PR title:

```text
Release staging: Native Driver And Bridge Source
```

Suggested PR body:

```markdown
## Scope
Review Rust native code, driver integrations, Flutter Rust Bridge source, and bridge package API changes together.

## Owner Decision
- Decision group: `Must Ship`
- Validation rule: `required_all`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/04-native-driver-bridge.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/04-native-driver-bridge.txt`

## Counts
- Paths: `19`
- Tracked changes: `19`
- Untracked: `0`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `19`

## Review Notes
Keep source changes apart from compiled DLLs; require platform build evidence and driver capability notes before release staging.

## Category Mix
- `bridge`: `1`
- `native-rust`: `18`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Core Data Model And Services

- Decision group: `Must Ship`
- Bucket ID: `core-data-model`
- Paths: `25`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/05-core-data-model.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/05-core-data-model.txt`

Suggested PR title:

```text
Release staging: Core Data Model And Services
```

Suggested PR body:

```markdown
## Scope
Review database, model, provider, backend, migration, and shared service changes as a data/API compatibility set.

## Owner Decision
- Decision group: `Must Ship`
- Validation rule: `required_all`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/05-core-data-model.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/05-core-data-model.txt`

## Counts
- Paths: `25`
- Tracked changes: `25`
- Untracked: `0`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `25`

## Review Notes
Stage with focused tests and a real older-profile migration artifact; generated DB/model files stay in the generated-files bucket.

## Category Mix
- `core`: `25`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Desktop UI And Workflow Packages

- Decision group: `Must Ship`
- Bucket ID: `desktop-ui-workflows`
- Paths: `27`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/06-desktop-ui-workflows.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/06-desktop-ui-workflows.txt`

Suggested PR title:

```text
Release staging: Desktop UI And Workflow Packages
```

Suggested PR body:

```markdown
## Scope
Review app UI, shared UI system, planetarium, plugin, updater, WebRTC, and desktop workflow changes together or split by screen if too large.

## Owner Decision
- Decision group: `Must Ship`
- Validation rule: `required_all`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/06-desktop-ui-workflows.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/06-desktop-ui-workflows.txt`

## Counts
- Paths: `27`
- Tracked changes: `27`
- Untracked: `0`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `22`

## Review Notes
Use UI consistency audit results and focused screenshot/smoke evidence before moving these paths into a release PR.

## Category Mix
- `app-ui`: `22`
- `other`: `1`
- `remote-protocol`: `3`
- `updater`: `1`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Tests And Support Tooling

- Decision group: `Must Ship`
- Bucket ID: `tests-and-support-tooling`
- Paths: `16`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/07-tests-and-support-tooling.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/07-tests-and-support-tooling.txt`

Suggested PR title:

```text
Release staging: Tests And Support Tooling
```

Suggested PR body:

```markdown
## Scope
Review non-release test files, scripts, package config, and developer tooling separately from product behavior.

## Owner Decision
- Decision group: `Must Ship`
- Validation rule: `required_all`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/07-tests-and-support-tooling.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/07-tests-and-support-tooling.txt`

## Counts
- Paths: `16`
- Tracked changes: `16`
- Untracked: `0`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `0`

## Review Notes
Stage only support changes needed to verify the release; defer unrelated audit scratch or developer-only helpers.

## Category Mix
- `tests`: `14`
- `tooling`: `2`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Out Of Release Scope Review

- Decision group: `Defer / Exclude`
- Bucket ID: `out-of-release-scope-review`
- Paths: `1`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/08-out-of-release-scope-review.txt`
- Owner command: `git restore --staged --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/08-out-of-release-scope-review.txt`

Suggested PR title:

```text
Release staging: Out Of Release Scope Review
```

Suggested PR body:

```markdown
## Scope
Quarantine scratch reports, research files, goal tracking, and broad miscellaneous edits until they are explicitly accepted or excluded.

## Owner Decision
- Decision group: `Defer / Exclude`
- Validation rule: `forbidden`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/08-out-of-release-scope-review.txt`
- Owner command: `git restore --staged --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/08-out-of-release-scope-review.txt`

## Counts
- Paths: `1`
- Tracked changes: `0`
- Untracked: `1`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `0`

## Review Notes
Do not stage into the public release branch without owner review and an explicit reason.

## Category Mix
- `other`: `1`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

## Defer / Exclude Policy

Any path in the `defer_exclude` group must remain unstaged unless the owner edits this matrix and reruns the validator. Any path outside this matrix is treated as an unplanned release change.
