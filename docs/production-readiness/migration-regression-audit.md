# Migration Regression Audit

- Passed: `true`
- Issues: `0`

This audit verifies synthetic old-schema/profile migration coverage and confirms the separate real older-profile migration gate remains documented. It does not replace the required real artifact probe.

## Required Files

| File | Exists | Missing required text |
| --- | --- | ---: |
| `packages/nightshade_core/test/fixtures/synthetic_old_profile_fixtures.dart` | `true` | `0` |
| `packages/nightshade_core/test/services/database_migration_test.dart` | `true` | `0` |
| `packages/nightshade_core/tool/production_migration_probe.dart` | `true` | `0` |

## Focused Verification

`cd packages/nightshade_core && flutter test test/services/database_migration_test.dart`
