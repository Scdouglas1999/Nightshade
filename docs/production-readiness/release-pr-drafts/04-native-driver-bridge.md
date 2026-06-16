# PR 04: Native Driver And Bridge Source

## Summary

Review Rust native code, driver integrations, Flutter Rust Bridge source, and bridge package API changes together.

Recommended staging decision: Keep source changes apart from compiled DLLs; require platform build evidence and driver capability notes before release staging.

## Scope

- Bucket ID: `native-driver-bridge`
- Path count: `19`
- Tracked changes: `19`
- Untracked paths: `0`
- Deleted paths: `0`
- Must-ship/release-critical paths: `19`
- Generated-only paths: `0`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `0`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/04-native-driver-bridge.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `bridge`: `1`
- `native-rust`: `18`

## Representative Paths

- `M ` `native/nightshade_native/alpaca/src/client.rs` (native-rust)
- `M ` `native/nightshade_native/alpaca/src/discovery.rs` (native-rust)
- `M ` `native/nightshade_native/bridge/src/api/discovery.rs` (native-rust)
- `M ` `native/nightshade_native/bridge/src/device_id.rs` (native-rust)
- `M ` `native/nightshade_native/bridge/src/device_manager/ops/camera.rs` (native-rust)
- `M ` `native/nightshade_native/bridge/src/dispatch/indi.rs` (native-rust)
- `M ` `native/nightshade_native/imaging/build.rs` (native-rust)
- `M ` `native/nightshade_native/indi/src/client.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/atik.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/fli.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/gphoto2.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/moravian.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/player_one.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/qhy.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/sdk_loader.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/svbony.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/touptek.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/zwo.rs` (native-rust)
- `M ` `packages/nightshade_bridge/lib/src/bridge_stub/connection_operations.dart` (bridge)

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
