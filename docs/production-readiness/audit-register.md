# Production Readiness Audit Register

This register tracks all high-risk placeholder/stub/shortcut markers from `docs/production-readiness/highrisk-baseline.txt`.
Statuses: `open`, `in_progress`, `done`, `accepted_unsupported`.

| ID | Location | Disposition | Owner | Target Gate | Status |
| --- | --- | --- | --- | --- | --- |
| HR-001 | `native/nightshade_native/alpaca/src/client.rs:1254` | implement | Native | Gate 5 | done |
| HR-002 | `native/nightshade_native/alpaca/src/client.rs:1258` | implement | Native | Gate 5 | done |
| HR-003 | `native/nightshade_native/bridge/src/device_capabilities.rs:1411` | implement | Native | Gate 1 | done |
| HR-004 | `native/nightshade_native/bridge/src/devices.rs:1353` | implement | Native | Gate 5 | done |
| HR-005 | `native/nightshade_native/bridge/src/devices.rs:1409` | implement | Native | Gate 5 | done |
| HR-006 | `native/nightshade_native/bridge/src/devices.rs:3532` | implement | Native | Gate 5 | done |
| HR-007 | `native/nightshade_native/bridge/src/devices.rs:3567` | implement | Native | Gate 5 | done |
| HR-008 | `native/nightshade_native/bridge/src/devices.rs:3609` | implement | Native | Gate 5 | done |
| HR-009 | `native/nightshade_native/bridge/src/devices.rs:3644` | implement | Native | Gate 5 | done |
| HR-010 | `native/nightshade_native/bridge/src/devices.rs:3692` | implement | Native | Gate 5 | done |
| HR-011 | `native/nightshade_native/bridge/src/devices.rs:3728` | implement | Native | Gate 5 | done |
| HR-012 | `native/nightshade_native/bridge/src/devices.rs:3777` | implement | Native | Gate 5 | done |
| HR-013 | `native/nightshade_native/bridge/src/devices.rs:5140` | implement | Native | Gate 5 | done |
| HR-014 | `native/nightshade_native/bridge/src/devices.rs:5193` | implement | Native | Gate 5 | done |
| HR-015 | `native/nightshade_native/bridge/src/devices.rs:5240` | implement | Native | Gate 5 | done |
| HR-016 | `native/nightshade_native/bridge/src/devices.rs:5287` | implement | Native | Gate 5 | done |
| HR-017 | `native/nightshade_native/bridge/src/devices.rs:5696` | implement | Native | Gate 5 | done |
| HR-018 | `native/nightshade_native/bridge/src/devices.rs:6007` | implement | Native | Gate 5 | done |
| HR-019 | `native/nightshade_native/bridge/src/devices.rs:6059` | implement | Native | Gate 5 | done |
| HR-020 | `native/nightshade_native/bridge/src/devices.rs:7048` | implement | Native | Gate 5 | done |
| HR-021 | `native/nightshade_native/bridge/src/devices.rs:7084` | implement | Native | Gate 5 | done |
| HR-022 | `native/nightshade_native/bridge/src/devices.rs:7137` | implement | Native | Gate 5 | done |
| HR-023 | `native/nightshade_native/bridge/src/devices.rs:7173` | implement | Native | Gate 5 | done |
| HR-024 | `native/nightshade_native/bridge/src/devices.rs:7214` | implement | Native | Gate 5 | done |
| HR-025 | `native/nightshade_native/bridge/src/devices.rs:7263` | implement | Native | Gate 5 | done |
| HR-026 | `native/nightshade_native/bridge/src/devices.rs:7316` | implement | Native | Gate 5 | done |
| HR-027 | `native/nightshade_native/bridge/src/devices.rs:7356` | implement | Native | Gate 5 | done |
| HR-028 | `native/nightshade_native/bridge/src/devices.rs:7396` | implement | Native | Gate 5 | done |
| HR-029 | `native/nightshade_native/bridge/src/devices.rs:7432` | implement | Native | Gate 5 | done |
| HR-030 | `native/nightshade_native/imaging/src/lib.rs:815` | implement | Native | Gate 3 | done |
| HR-031 | `native/nightshade_native/imaging/src/processing.rs:163` | implement | Native | Gate 3 | done |
| HR-032 | `native/nightshade_native/sequencer/src/instructions.rs:608` | implement | Native | Gate 2 | done |

## Notes
- Source snapshot date: 2026-02-07.
- All previously registered high-risk markers are now closed in code and no longer appear in the current scan.
- `docs/production-readiness/highrisk-baseline.txt` is now an empty baseline (0 high-risk markers).
- Update this register whenever `tools/production/placeholder_audit.dart` reports new high-risk markers.
