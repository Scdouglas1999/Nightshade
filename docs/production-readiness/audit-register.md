# Production Readiness Audit Register

This register tracks high-risk placeholder/stub/shortcut markers from `docs/production-readiness/highrisk-baseline.txt`.
Statuses: `open`, `in_progress`, `done`, `accepted_unsupported`, `accepted_baseline`.

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
- Original source snapshot date: 2026-02-07.
- All previously registered high-risk markers are now closed in code and no longer appear in the current scan.
- Current source snapshot date: 2026-05-16.
- `docs/production-readiness/highrisk-baseline.txt` is the exact line-level baseline for the 176 current high-risk markers. These are accepted as a release baseline, not as fixed code.
- The 2026-05-16 baseline is dominated by defensive optional metadata reads, best-effort disconnect/write cleanup, vendor capability probes, and known unsupported recovery/custom-driver paths. They remain visible so future changes cannot add more without an explicit register/baseline update.
- Update this register and the baseline whenever `tools/production/placeholder_audit.dart` reports new high-risk markers.

## Current Baseline Triage

| Area | Markers | Disposition | Status | Rationale |
| --- | ---: | --- | --- | --- |
| `native/nightshade_native/bridge/src/dispatch/alpaca.rs` | 40 | baseline metadata fallbacks | accepted_baseline | Alpaca discovery fills optional driver metadata and supported-actions fields; failures degrade capability descriptions, not command execution. |
| `native/nightshade_native/bridge/src/dispatch/ascom.rs` | 28 | baseline metadata fallbacks | accepted_baseline | ASCOM discovery mirrors Alpaca metadata handling for interface/version/info/action fields. |
| `native/nightshade_native/bridge/src/device_capabilities.rs` | 23 | baseline capability probing | accepted_baseline | Device capability scans tolerate missing optional fields and best-effort disconnect failures while building UI-visible capability summaries. |
| `native/nightshade_native/bridge/src/real_device_ops.rs` | 16 | baseline optional telemetry/cleanup | accepted_baseline | Runtime operations probe optional sensor/focuser/filter-wheel data and ignore cleanup disconnect failures after the primary operation path. |
| `packages/nightshade_core/lib/src/services/device_service.dart` | 10 | baseline cleanup catches | accepted_baseline | Device service cleanup paths swallow disconnect/dispose failures to avoid masking the primary user-visible operation result. |
| `native/nightshade_native/bridge/src/lib.rs` | 7 | baseline logging/export writes | accepted_baseline | Log initialization/export ignores one-time-set and formatting errors where there is no useful recovery path during diagnostics assembly. |
| `native/nightshade_native/bridge/src/ascom_wrapper.rs` | 5 | mixed baseline, unsupported driver hooks | accepted_baseline | Optional readout metadata is best-effort; two custom-action hooks still return explicit unsupported errors rather than silently succeeding. |
| `native/nightshade_native/bridge/src/device_manager/ops/camera.rs` | 5 | baseline optional camera metadata | accepted_baseline | Camera state refresh keeps optional temperature/gain/offset/capability metadata nullable when drivers do not expose it. |
| `native/nightshade_native/imaging/src/raw.rs` | 4 | baseline caller/default parameter fallbacks | accepted_baseline | Documented defaults are used for optional raw-processing inputs. |
| `native/nightshade_native/sequencer/src/executor.rs` | 4 | mixed baseline, unsupported custom branch | accepted_baseline | Optional result text defaults are cosmetic; `RecoveryAction::CustomBranch` remains explicitly unsupported and pauses instead of proceeding. |
| `native/nightshade_native/native/src/vendor/player_one.rs` | 3 | baseline vendor telemetry probes | accepted_baseline | Optional temperature/cooler/heater controls are nullable because the vendor SDK may not expose them on all models. |
| `native/nightshade_native/bridge/src/device_id.rs` | 3 | baseline parser optionality | accepted_baseline | Device-index parsing intentionally yields `None` for non-indexed identifiers. |
| `native/nightshade_native/bridge/src/event.rs` | 2 | baseline timestamp fallback | accepted_baseline | System-clock-before-epoch fallback is documented and non-recoverable in event serialization. |
| `native/nightshade_native/bridge/src/imaging_ops.rs` | 2 | baseline optional image metadata | accepted_baseline | Imaging metadata defaults preserve output when optional fields are unavailable. |
| `native/nightshade_native/indi/src/client.rs` | 2 | baseline XML/default parsing | accepted_baseline | INDI XML parsing tolerates absent optional attributes/text. |
| `native/nightshade_native/native/src/vendor/qhy.rs` | 2 | baseline vendor telemetry probes | accepted_baseline | Optional QHY controls are nullable because model support varies. |
| `native/nightshade_native/native/src/vendor/zwo.rs` | 2 | baseline vendor command tolerance | accepted_baseline | Optional ZWO SDK operations are tolerated where capability support varies. |
| Remaining single-marker files | 17 | baseline localized exception | accepted_baseline | Single entries are exact-line tracked in `highrisk-baseline.txt`; each is either optional metadata, best-effort cleanup, documented unsupported behavior, or a comment false-positive retained for audit continuity. |
