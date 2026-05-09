# PR 05: Mobile Remote Client

## Summary

Review Android/mobile remote-client code and mobile smoke tooling separately from desktop/headless server changes.

Recommended staging decision: Stage with Android build metadata and emulator smoke artifacts only after confirming the server API bucket it depends on is reviewed.

## Scope

- Bucket ID: `mobile-remote-client`
- Path count: `9`
- Tracked changes: `9`
- Untracked paths: `0`
- Deleted paths: `0`
- Must-ship/release-critical paths: `7`
- Generated-only paths: `0`
- Binary/evidence paths: `0`
- Defer/exclude review paths: `2`

Decision lists are generated in `docs/production-readiness/release-pr-lists` for must-ship, generated-only, binary/evidence, and defer/exclude paths.

## Stage Command

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt
```

## Review Notes

- Confirm every untracked path is intentional before staging.
- Confirm generated files were produced from reviewed source.
- Keep binary payloads and evidence artifacts only when they are required for this release PR.
- Move defer/exclude paths out of the staged set unless an owner explicitly accepts them.

## Category Mix

- `mobile`: `9`

## Representative Paths

- ` M` `apps/mobile/lib/main.dart` (mobile)
- ` M` `apps/mobile/lib/screens/qr_scanner_screen.dart` (mobile)
- ` M` `apps/mobile/lib/services/foreground_service.dart` (mobile)
- ` M` `apps/mobile/lib/services/mobile_sequence_hooks.dart` (mobile)
- ` M` `apps/mobile/lib/services/notification_service.dart` (mobile)
- ` M` `apps/mobile/lib/widgets/checkpoint_resume_dialog.dart` (mobile)
- ` M` `apps/mobile/lib/widgets/network_status_indicator.dart` (mobile)
- ` M` `apps/mobile/pubspec.yaml` (mobile)
- ` M` `apps/mobile/test/widget_test.dart` (mobile)

## Verification

- [ ] Run the focused tests or audits named by this bucket.
- [ ] Re-run `dart run tools/production/release_staging_audit.dart`.
- [ ] Re-run `dart run tools/production/release_pr_split_plan.dart`.
- [ ] Re-run `dart run tools/production/release_pr_staged_branch_validator.dart` on the staged branch.

## Release Gate Impact

This draft does not make the public release gate pass by itself. The staged branch still needs the external evidence and owner sign-off recorded by `docs/production-readiness/public-release-gate.md`.
