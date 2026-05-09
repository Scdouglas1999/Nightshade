# Dependency Hygiene Audit

- Packages scanned: `10`
- Violations: `0`

This audit scans each workspace package `lib/` tree for `package:` imports and verifies each imported package is declared directly in that package pubspec. It does not audit transitive vulnerability status.

## Packages

| Package | Path | Imports | Declared dependencies | Missing |
| --- | --- | ---: | ---: | ---: |
| `nightshade_desktop` | `apps/desktop` | 19 | 41 | 0 |
| `nightshade_mobile` | `apps/mobile` | 16 | 35 | 0 |
| `nightshade_app` | `packages/nightshade_app` | 29 | 33 | 0 |
| `nightshade_bridge` | `packages/nightshade_bridge` | 7 | 14 | 0 |
| `nightshade_core` | `packages/nightshade_core` | 16 | 28 | 0 |
| `nightshade_planetarium` | `packages/nightshade_planetarium` | 7 | 11 | 0 |
| `nightshade_plugins` | `packages/nightshade_plugins` | 3 | 5 | 0 |
| `nightshade_ui` | `packages/nightshade_ui` | 6 | 8 | 0 |
| `nightshade_updater` | `packages/nightshade_updater` | 10 | 21 | 0 |
| `nightshade_webrtc` | `packages/nightshade_webrtc` | 9 | 16 | 0 |
