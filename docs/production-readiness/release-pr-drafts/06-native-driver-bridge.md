# PR 06: Native Driver And Bridge Source

## Summary

Review Rust native code, driver integrations, Flutter Rust Bridge source, and bridge package API changes together.

Recommended staging decision: Keep source changes apart from compiled DLLs; require platform build evidence and driver capability notes before release staging.

## Scope

- Bucket ID: `native-driver-bridge`
- Path count: `100`
- Tracked changes: `87`
- Untracked paths: `13`
- Deleted paths: `1`
- Must-ship/release-critical paths: `100`
- Generated-only paths: `0`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `0`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `bridge`: `5`
- `native-rust`: `95`

## Representative Paths

- ` M` `native/nightshade_native/Cargo.toml` (native-rust)
- ` M` `native/nightshade_native/alpaca/src/camera.rs` (native-rust)
- ` M` `native/nightshade_native/alpaca/src/client.rs` (native-rust)
- ` M` `native/nightshade_native/alpaca/src/telescope.rs` (native-rust)
- ` M` `native/nightshade_native/ascom/src/windows_impl.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/adaptive_polling.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/api.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/ascom_wrapper.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/ascom_wrapper_covercalibrator.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/ascom_wrapper_filterwheel.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/ascom_wrapper_mount.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/ascom_wrapper_rotator.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/ascom_wrapper_safetymonitor.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/ascom_wrapper_weather.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/builtin_guider.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/device_id.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/devices.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/error.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/event.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/filter_matching.rs` (native-rust)
- ... 80 more paths in `docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt`.

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
