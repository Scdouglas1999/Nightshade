# Manual Migration Probe

- Artifact provided: `false`
- Source exists: `false`
- Source path: `none`
- Source size bytes: `unknown`
- Source SHA256: `unknown`
- Copied source SHA256: `unknown`
- Copied source SHA256 matches: `false`
- Source user_version: `unknown`
- Final user_version: `unknown`
- Current schema version: `unknown`
- Expected table count: `unknown`
- Migrated table count: `unknown`
- Default setting count: `unknown`
- Older profile artifact: `false`
- Migration verified: `false`

Scope: this probe validates a supplied older real SQLite profile/database by migrating a temporary copy. It does not replace the synthetic database migration test suite.

## Blocker

No older real Nightshade database/profile was supplied. Set NIGHTSHADE_OLD_DATABASE or pass --dart-define=NIGHTSHADE_OLD_DATABASE=<path>.

## Missing Tables

None.

## Missing Default Settings

None.
