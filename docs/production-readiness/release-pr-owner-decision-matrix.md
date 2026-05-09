# Release PR Owner Decision Matrix

- Source split plan: `docs/production-readiness/release-pr-split-plan.json`
- Source generated at: `2026-05-06T09:42:36.905333Z`
- Branch at planning time: `main`
- HEAD at planning time: `bbdee9b`
- Buckets: `10`
- Paths: `913`

This file turns the generated pathspec buckets into owner-reviewable PR drafts and validation rules. It does not stage files or approve any bucket by itself.

## Decision Groups

| Group | Buckets | Paths | Validation rule | Related release list | Pathspecs |
| --- | ---: | ---: | --- | --- | --- |
| Must Ship | 7 | 790 | `required_all` | `docs/production-readiness/release-pr-lists/01-must-ship.txt` | `docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt`<br>`docs/production-readiness/release-pr-pathspecs/04-headless-remote-api.txt`<br>`docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt`<br>`docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt`<br>`docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt`<br>`docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt`<br>`docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt` |
| Generated Only | 1 | 35 | `optional_all_or_none` | `docs/production-readiness/release-pr-lists/02-generated-only.txt` | `docs/production-readiness/release-pr-pathspecs/01-generated-files.txt` |
| Binary / Evidence | 1 | 31 | `optional_all_or_none` | `docs/production-readiness/release-pr-lists/03-binary-evidence.txt` | `docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt` |
| Defer / Exclude | 1 | 57 | `forbidden` | `docs/production-readiness/release-pr-lists/04-defer-exclude.txt` | `docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt` |

## Release Triage Lists

These aggregate lists classify every dirty path by release triage. The decision groups above classify PR validation buckets, so counts can differ when a validation bucket contains both release-critical and support paths.

| List | Paths | Pathspec | Description |
| --- | ---: | --- | --- |
| Must Ship | 635 | `docs/production-readiness/release-pr-lists/01-must-ship.txt` | Release-critical source, docs, and tooling paths that are not generated outputs or binary/evidence artifacts. |
| Generated Only | 35 | `docs/production-readiness/release-pr-lists/02-generated-only.txt` | Generated files that should be reviewed against their source changes and generator commands. |
| Binary And Evidence | 31 | `docs/production-readiness/release-pr-lists/03-binary-evidence.txt` | Binary payloads, screenshots, APKs, DLLs, and other evidence artifacts that need explicit artifact review. |
| Defer Or Exclude | 212 | `docs/production-readiness/release-pr-lists/04-defer-exclude.txt` | Non-release-critical paths that need owner review before they are staged into a public release branch. |

## Validation Commands

- Validate currently staged index: `dart run tools/production/release_pr_staged_branch_validator.dart --mode=index`
- Validate a committed PR branch against main: `dart run tools/production/release_pr_staged_branch_validator.dart --mode=branch --base=main`

## Draft PR Descriptions

### Generated Files

- Decision group: `Generated Only`
- Bucket ID: `generated-files`
- Paths: `35`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/01-generated-files.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/01-generated-files.txt`

Suggested PR title:

```text
Release staging: Generated Files
```

Suggested PR body:

```markdown
## Scope
Review regenerated Dart, Drift, Freezed, bridge, and lock files apart from human-authored source.

## Owner Decision
- Decision group: `Generated Only`
- Validation rule: `optional_all_or_none`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/01-generated-files.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/01-generated-files.txt`

## Counts
- Paths: `35`
- Tracked changes: `31`
- Untracked: `4`
- Deleted: `0`
- Generated: `35`
- Binary/evidence: `0`
- Release-critical: `22`

## Review Notes
Regenerate from source, verify generator commands, then stage only outputs that correspond to reviewed model/API changes.

## Category Mix
- `generated`: `35`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Binary And Evidence Artifacts

- Decision group: `Binary / Evidence`
- Bucket ID: `binary-and-evidence-artifacts`
- Paths: `31`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt`

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
- Pathspec: `docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt`

## Counts
- Paths: `31`
- Tracked changes: `2`
- Untracked: `29`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `31`
- Release-critical: `4`

## Review Notes
Keep release payload binaries and smoke evidence in a deliberate artifact review; exclude scratch screenshots and research blobs from the release PR.

## Category Mix
- `binary-native-artifact`: `27`
- `release-evidence-binary`: `4`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Release Infrastructure And Evidence

- Decision group: `Must Ship`
- Bucket ID: `release-infra-evidence`
- Paths: `164`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt`

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
- Pathspec: `docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt`

## Counts
- Paths: `164`
- Tracked changes: `5`
- Untracked: `159`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `163`

## Review Notes
Stage audit tooling and evidence docs as the release-readiness PR only after confirming each artifact is current and reproducible.

## Category Mix
- `docs`: `5`
- `other`: `1`
- `package-config`: `1`
- `release-evidence-docs`: `98`
- `release-tooling`: `59`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Headless Remote API And Dashboard

- Decision group: `Must Ship`
- Bucket ID: `headless-remote-api`
- Paths: `34`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/04-headless-remote-api.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/04-headless-remote-api.txt`

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
- Pathspec: `docs/production-readiness/release-pr-pathspecs/04-headless-remote-api.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/04-headless-remote-api.txt`

## Counts
- Paths: `34`
- Tracked changes: `29`
- Untracked: `5`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `34`

## Review Notes
Pair this bucket with route contract tests, dashboard smoke logs, auth/LAN evidence, and reconnect evidence.

## Category Mix
- `headless-remote`: `34`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Mobile Remote Client

- Decision group: `Must Ship`
- Bucket ID: `mobile-remote-client`
- Paths: `9`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt`

Suggested PR title:

```text
Release staging: Mobile Remote Client
```

Suggested PR body:

```markdown
## Scope
Review Android/mobile remote-client code and mobile smoke tooling separately from desktop/headless server changes.

## Owner Decision
- Decision group: `Must Ship`
- Validation rule: `required_all`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt`

## Counts
- Paths: `9`
- Tracked changes: `9`
- Untracked: `0`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `7`

## Review Notes
Stage with Android build metadata and emulator smoke artifacts only after confirming the server API bucket it depends on is reviewed.

## Category Mix
- `mobile`: `9`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Native Driver And Bridge Source

- Decision group: `Must Ship`
- Bucket ID: `native-driver-bridge`
- Paths: `100`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt`

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
- Pathspec: `docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt`

## Counts
- Paths: `100`
- Tracked changes: `87`
- Untracked: `13`
- Deleted: `1`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `100`

## Review Notes
Keep source changes apart from compiled DLLs; require platform build evidence and driver capability notes before release staging.

## Category Mix
- `bridge`: `5`
- `native-rust`: `95`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Core Data Model And Services

- Decision group: `Must Ship`
- Bucket ID: `core-data-model`
- Paths: `127`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt`

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
- Pathspec: `docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt`

## Counts
- Paths: `127`
- Tracked changes: `82`
- Untracked: `45`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `127`

## Review Notes
Stage with focused tests and a real older-profile migration artifact; generated DB/model files stay in the generated-files bucket.

## Category Mix
- `core`: `127`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Desktop UI And Workflow Packages

- Decision group: `Must Ship`
- Bucket ID: `desktop-ui-workflows`
- Paths: `292`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt`

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
- Pathspec: `docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt`

## Counts
- Paths: `292`
- Tracked changes: `157`
- Untracked: `135`
- Deleted: `1`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `204`

## Review Notes
Use UI consistency audit results and focused screenshot/smoke evidence before moving these paths into a release PR.

## Category Mix
- `app-ui`: `204`
- `other`: `4`
- `planetarium`: `29`
- `plugins`: `11`
- `ui-system`: `18`
- `updater`: `10`
- `webrtc`: `16`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Tests And Support Tooling

- Decision group: `Must Ship`
- Bucket ID: `tests-and-support-tooling`
- Paths: `64`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt`

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
- Pathspec: `docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt`
- Owner command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt`

## Counts
- Paths: `64`
- Tracked changes: `14`
- Untracked: `50`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `0`

## Review Notes
Stage only support changes needed to verify the release; defer unrelated audit scratch or developer-only helpers.

## Category Mix
- `package-config`: `2`
- `tests`: `58`
- `tooling`: `4`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

### Out Of Release Scope Review

- Decision group: `Defer / Exclude`
- Bucket ID: `out-of-release-scope-review`
- Paths: `57`
- Pathspec: `docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt`
- Owner command: `git restore --staged --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt`

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
- Pathspec: `docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt`
- Owner command: `git restore --staged --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt`

## Counts
- Paths: `57`
- Tracked changes: `13`
- Untracked: `44`
- Deleted: `0`
- Generated: `0`
- Binary/evidence: `0`
- Release-critical: `0`

## Review Notes
Do not stage into the public release branch without owner review and an explicit reason.

## Category Mix
- `docs`: `25`
- `other`: `32`

## Verification
- Regenerate the owner matrix: `dart run melos run audit:release-pr-owner-matrix --no-select`
- Validate staged files before commit: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- Validate committed branch before PR: `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
```

## Defer / Exclude Policy

Any path in the `defer_exclude` group must remain unstaged unless the owner edits this matrix and reruns the validator. Any path outside this matrix is treated as an unplanned release change.
