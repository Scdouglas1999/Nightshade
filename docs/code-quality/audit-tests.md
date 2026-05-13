# Nightshade 2.5.0 - Code Quality Audit: Tests, Dead Code, Generated Policy

**Auditor**: CQ-AUDIT-TESTS (read-only)
**Worktree base**: `bbdee9b` (downstream of `0c88691` / `release/v2.5.0-hardening`)
**Branch**: `worktree-agent-a2048b46daff2f586`
**Date**: 2026-05-12

> **NOTE**: `melos bootstrap` has NOT been run in this worktree, so `.dart_tool/package_config.json` is absent. Numbers derived from static `find/wc/grep` are reliable; `flutter analyze` numbers are dominated by missing-package-resolution noise and are flagged as such.

---

## 1. Test Coverage by Package

### Dart packages (handwritten LOC only; generated `.g.dart` / `.freezed.dart` / `frb_generated*` excluded)

| Package | Src LOC | Generated LOC | Test files | Test LOC | Inline tests | Src:Test |
|---|---:|---:|---:|---:|---:|---:|
| `packages/nightshade_core` | 66,618 | 48,587 | 21 | 8,060 | ~80 | 8.3 : 1 |
| `packages/nightshade_app` | 119,610 | 0 | 4 | 219 | ~10 | **546 : 1** |
| `packages/nightshade_ui` | 10,788 | 0 | 0 | 0 | 0 | INF |
| `packages/nightshade_planetarium` | 20,032 | 0 | 2 | 171 | ~6 | 117 : 1 |
| `packages/nightshade_bridge` | 12,301 | 76,882 | 1 | 293 | ~6 | 42 : 1 |
| `packages/nightshade_webrtc` | 5,340 | 1,199 | 0 | 0 | 0 | INF |
| `packages/nightshade_updater` | 1,982 | 1,901 | 1 | 346 | ~5 | 5.7 : 1 |
| `packages/nightshade_plugins` | 1,096 | 0 | 1 | 276 | ~10 | 4.0 : 1 |
| `apps/desktop` | 14,366 | 0 | 0 | 0 | 0 | INF |
| `apps/mobile` | 2,723 | 0 | 1 | 25 | 1 | 109 : 1 |

**Total Dart**: 254.9k handwritten src LOC vs. 9.4k test LOC = **27 : 1**. ~299 `test()` invocations across 31 test files.

### Rust crates

| Crate | Src LOC | `tests/` LOC | Inline test files | `#[test]` count |
|---|---:|---:|---:|---:|
| `sequencer` | 15,704 | 0 | 12 | ~54 |
| `imaging` | 10,365 | 261 | 6 | ~50 (incl. perf_tests) |
| `bridge` (handwritten ~38k, 25k generated) | 63,033 | 0 | 11 | ~50 |
| `ascom` | 3,894 | 0 | 0 | **0** |
| `indi` | 8,476 | 0 | 9 | ~72 |
| `alpaca` | 6,548 | 0 | 4 | ~19 |
| `native` (vendor SDKs) | 21,566 | 920 | 5 | ~61 |
| `updater` (binary) | 331 | 0 | 0 | 0 |

**Total Rust**: ~130k LOC, ~324 `#[test]` functions, weighted toward `indi/client.rs` (44) and `vendor/fujifilm.rs` (24). `ascom/windows_impl.rs` (3,756 LOC) has **zero** test coverage.

### Top 10 biggest files with **zero direct test coverage**

| # | File | LOC | Acceptable? | Suggested mock-driver tests |
|---|---|---:|---|---|
| 1 | `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` | 7,079 | NO - widget testable | Golden/widget tests against `MockBackend` |
| 2 | `packages/nightshade_app/lib/screens/planetarium/planetarium_screen.dart` | 5,847 | partial - GPU-dependent | Pure-Dart util/state extracts unit-testable |
| 3 | `packages/nightshade_app/lib/screens/dashboard/dashboard_screen.dart` | 5,751 | NO | Widget tests with `ProviderScope.overrides` |
| 4 | `packages/nightshade_app/lib/screens/sequencer/widgets/node_properties_panel.dart` | 4,871 | NO | Widget tests per node type |
| 5 | `packages/nightshade_app/lib/screens/settings/settings_screen.dart` | 4,814 | NO | Form-validation widget tests |
| 6 | `packages/nightshade_app/lib/screens/framing/framing_screen.dart` | 4,688 | partial | Extract calc utils (one test exists) |
| 7 | `native/nightshade_native/ascom/src/windows_impl.rs` | 3,756 | partial - COM mocks hard | Integrate `mockall` for `IDispatch`; trait-test boundary |
| 8 | `packages/nightshade_planetarium/lib/src/rendering/sky_renderer.dart` | 3,491 | partial - GPU | Test catalog binning + viewport math separately |
| 9 | `packages/nightshade_core/lib/src/backend/network_backend.dart` | 3,010 | NO - pure HTTP wiring | `MockClient` from `package:http` |
| 10 | `packages/nightshade_core/lib/src/backend/ffi_backend.dart` | 2,577 | partial - FFI | Mock `NativeBridge` for transform/event logic |

`apps/desktop/lib/headless_api_server.dart` (1,352 LOC) and the 14 `headless_api/handlers/*.dart` files are also **completely untested** despite being the WebRTC dashboard's contract surface - high-impact gap.

---

## 2. Dead / Unreachable Code

### a) Unused public APIs exported from `nightshade_core.dart` barrel

Verified by `grep -rln <Symbol>` against `packages apps` outside the defining file.

| Symbol | File:Line | External refs | Verdict |
|---|---|---:|---|
| `NightshadeException`, `ConnectionException` (file: 472 LOC) | `packages/nightshade_core/lib/src/backend/nightshade_exception.dart:13` | 0 | **DEAD**. Not exported by barrel either; entire file unreferenced. |
| `Phd2Status` (nightshade_core copy) | `packages/nightshade_core/lib/src/models/backend/phd2_status.dart:1` | 0 (consumers use `nightshade_bridge.Phd2Status` instead) | **DUPLICATE** - delete core copy. |
| `PlateSolveResult` (core copy) | `packages/nightshade_core/lib/src/models/backend/plate_solve_result.dart:1` | 0 outside backend_types | **DUPLICATE** - bridge canonical version is used. |
| `SequencerStatus` (core copy) | `packages/nightshade_core/lib/src/models/backend/sequencer_status.dart:1` | 3 (all backend code) | Likely DEAD; bridge has its own. Verify before delete. |
| `PaginatedImageLoader` (246 LOC) | `packages/nightshade_core/lib/src/services/paginated_image_loader.dart:1` | 0 | **DEAD**. |
| `CatalogService`, `StarCatalogService`, `DsoCatalogService`, `AnnotationCatalogService` (449 LOC) | `packages/nightshade_core/lib/src/services/catalog_service.dart` | 0 | **DEAD**. Likely superseded by bridge-side catalog ops. |
| `GoesSatelliteProvider` (156 LOC) | `packages/nightshade_core/lib/src/services/weather/providers/goes_satellite_provider.dart` | 0 (only barrel) | **DEAD** - never instantiated. |
| `NoaaRadarProvider` (323 LOC) | `.../providers/noaa_radar_provider.dart` | 0 | **DEAD**. |
| `OpenmeteoCloudProvider` (222 LOC) | `.../providers/openmeteo_cloud_provider.dart` | 0 | **DEAD**. |
| `WeatherSafetyProvider` (382 LOC) | `packages/nightshade_core/lib/src/providers/weather_safety_provider.dart` | exported but no `ref.watch/read` of it | Likely DEAD - audit needed. |

Combined deletable surface: **~2,300 LOC** of pure dead Dart in `nightshade_core` alone.

### b) Unused widgets in `packages/nightshade_app/lib/widgets/`

| Widget | LOC | Verdict |
|---|---:|---|
| `AnnotationCatalogDialog` (`annotation_catalog_dialog.dart`) | 484 | **DEAD** - only self-references (factory in same file). |
| `weather_widgets.dart` (barrel) | 13 | Re-exported but no consumer imports the barrel (individual widgets are imported directly). Safe to delete barrel. |

### c) Stale TutorialKeys / route constants

- `TutorialKeys.navSettings` and `TutorialKeys.navPolarAlignment` defined in `packages/nightshade_app/lib/widgets/tutorial_overlay.dart:50-52` are **never referenced** outside the file. (All other nav keys have exactly 1 external use.)
- Routes look clean - no `/diagnostics` or `/scheduler` route exists in `packages/nightshade_app/lib/router/app_router.dart`. The "scheduler" string appears only in `apps/desktop/lib/headless_api/handlers/scheduler_handlers.dart` (API namespace, not a UI route) - **OK**.
- Inside `tutorial_keys/*_keys.dart`, every defined key is dispatched in the local `getKey()` switch - no dead keys at file level.

### d) Unused DB columns / tables

All 23 Drift tables (`packages/nightshade_core/lib/src/database/tables/*.dart`) are referenced by at least one DAO method. Spot-checked the science suite (`LineRatioProducts`, `MovingObjectCandidates`, `AstrometryResidualVectors`, `PsfFieldTiles`) - all have `insert*`/`getAll*` methods in `science_dao.dart`. **No dead tables found**; would need column-level analysis to find dead fields.

### e) Orphan source files (verified, excluding `.g.dart`/`.freezed.dart`)

Truly orphan (no path reference anywhere outside themselves):
- `packages/nightshade_core/lib/src/backend/nightshade_exception.dart` (472 LOC) - **DEAD**
- `packages/nightshade_core/lib/src/services/paginated_image_loader.dart` (246 LOC) - **DEAD**
- `packages/nightshade_core/lib/src/services/catalog_service.dart` (449 LOC) - **DEAD**

The weather provider and backend model "orphans" are reachable via barrel re-exports (`weather_models.dart`, `backend_types.dart`) but their classes have **zero call sites**; treat as dead behaviour, not dead imports.

---

## 3. Deprecated-But-Still-Used Members

Found via `grep -rn "@Deprecated("`. 9 deprecated declarations total.

| Symbol | File:Line | Replacement | Call sites | Recommendation |
|---|---|---|---:|---|
| `DriverBackend` typedef | `packages/nightshade_core/lib/src/services/device_service.dart:82` | `DriverType` | **>27** (entire `unified_device.dart`, `discovery_state.dart`) | **MIGRATE then delete.** Massive ripple; do as one PR. |
| `NightshadeDeviceType` typedef | `device_service.dart:79` | `DeviceType` | 2 (`discovery_state.dart`, `unified_device.dart`) | MIGRATE then delete. |
| `AvailableDevice` typedef | `device_service.dart:85` | `DeviceInfo` | 5 (in `discovery_state.dart`, `unified_device.dart`) | MIGRATE then delete. |
| `DeviceInfo.backend` getter | `models/backend/device_info.dart:22` | `.driverType` | unverified (many `.backend` occurrences are unrelated) | Manual audit before deletion. |
| `DeviceInfo.type` getter | `models/backend/device_info.dart:26` | `.deviceType` | unverified | Same as above. |
| `TargetGroupNode` typedef | `models/sequence/sequence_models.dart:378` | `TargetHeaderNode` | 19 | MIGRATE then delete. |
| `SequenceData.targetGroups` getter | `models/sequence/sequence_models.dart:2284` | `targetHeaders` | 19 (same call-site set) | Delete with above. |
| `Plugin.initialize()` | `packages/nightshade_plugins/lib/src/plugin_api.dart:55` | `onLoad(PluginContext)` | 0 plugins implement it; only test/host call `dispose()` (unrelated) | **DELETE NOW** - no consumers. |
| `Plugin.dispose()` | `plugin_api.dart:59` | `onUnload()` | 0 plugin implementations | **DELETE NOW**. |

Example call-site (line 23 of `discovery_state.dart`):
```dart
final DriverBackend backend;
...
final List<AvailableDevice> devices;
```
A single search-and-replace pass for `DriverBackend` -> `DriverType`, `AvailableDevice` -> `DeviceInfo`, `NightshadeDeviceType` -> `DeviceType` would fix ~30 sites and let the three typedefs (5 LOC) be deleted.

---

## 4. Generated Code Policy

```text
Total committed generated LOC: 162,865
```

### Top contributors

| File | LOC |
|---|---:|
| `packages/nightshade_core/lib/src/database/database.g.dart` | 28,879 |
| `packages/nightshade_bridge/lib/src/event.freezed.dart` | 26,894 |
| `native/nightshade_native/bridge/src/frb_generated.rs` | 25,137 |
| `packages/nightshade_bridge/lib/src/frb_generated.dart` | 16,665 |
| `packages/nightshade_bridge/lib/src/error.freezed.dart` | 14,965 |
| `packages/nightshade_bridge/lib/src/frb_generated.io.dart` | 14,601 |
| `bridge_generated.h` (macos/linux/ios) | 3,053 each = 9,159 |
| ~80 other `.freezed.dart` / `.g.dart` | ~26,500 |

### Regenerability

`melos run generate` calls the Dart `build_runner` + `flutter_rust_bridge_codegen`. The CLAUDE.md FRB troubleshooting section confirms regen is fragile on Windows (needs `CPATH` env var pointing at MSVC + clang headers). **Dry-run not attempted** here because (a) regen mutates source files which would violate read-only contract, (b) `melos bootstrap` not run in this worktree.

### Pros / Cons of committing

| Aspect | Commit (current) | `.gitignore` |
|---|---|---|
| Fresh-clone build speed | Fast (skip build_runner + FRB) | Adds ~3 min for Drift, ~5 min for FRB |
| PR diff noise | **HIGH** - 162k LOC in diffs after model edits | Clean |
| CI determinism | Deterministic | Requires regen step in every CI job |
| Onboarding | Works after `melos bootstrap` | Requires LLVM + MSVC headers on Windows |

### Recommendation

**Keep Drift `.g.dart`** (deterministic from schema files, fast to build, low churn) and **`.freezed.dart`** (deterministic from `@freezed` classes). **`.gitignore` `frb_generated*` and `bridge_generated.h`** - these regenerate from a single `lib.rs` and are the noisiest in PR diffs (~76k LOC). Add `tools/scripts/regen_frb.ps1` as part of `melos bootstrap` post-step so devs aren't surprised. Net: ~76k LOC removed from VCS, ~3-5 min added to fresh clone.

---

## 5. Static Analysis Debt

### `flutter analyze` - `packages/nightshade_core`

**WARNING**: result run without `melos bootstrap`, so output is dominated by missing-package-resolution errors. Reported counts here are inflated by `package:nightshade_bridge` not being on the path.

- **Total**: 22,565 issues (`5.8s`)
- Top "rule" buckets (mostly cascading from missing imports):

| Rule | Count |
|---|---:|
| `undefined_identifier` | 5,296 |
| `undefined_class` | 4,820 |
| `undefined_method` | 4,760 |
| `creation_with_non_type` | 2,209 |
| `undefined_function` | 1,863 |
| `undefined_annotation` | 889 |
| `override_on_non_overriding_member` | 617 |
| `const_initialized_with_non_constant_value` | 347 |
| `super_formal_parameter_without_associated_named` | 345 |
| `extends_non_class` | 289 |

The first 6 categories (~19.8k issues = 88%) are almost entirely **artefacts of the unrun `melos bootstrap`**. Files most affected are exactly the ones that `import 'package:nightshade_bridge/...'` (e.g. `ffi_backend.dart`, `network_backend.dart`, `equipment_provider.dart`).

**Action**: re-run after `melos bootstrap` for an accurate count. The genuine debt categories worth tracking are `override_on_non_overriding_member` (617 - possible API drift between bridge versions) and `super_formal_parameter_without_associated_named` (345 - Dart 3 super-parameter migration not yet done).

### `cargo clippy` (workspace)

Not run - no `target/` directory in worktree, would require ~5-10 min cold build. CLAUDE.md confirms `cargo clippy --all-features -- -D warnings` is the CI gate (no `clippy::pedantic`). The CI job in `.github/workflows/ci.yml:80` is green on `main`, so pedantic counts would need a separate measurement run.

---

## 6. Mock / Fake Infrastructure

### Existing

- `packages/nightshade_core/test/mocks/mock_backend.dart` (166 LOC) - `MockBackend extends Mock implements NightshadeBackend` (mocktail) + `TestFixtures` constants.
- `packages/nightshade_core/test/mocks/mock_database.dart` (179 LOC) - in-memory Drift database.
- `packages/nightshade_core/test/services/centering_service_test.mocks.dart` - generated `@GenerateMocks` for `CenteringService`.
- Rust: native crate's `tests/native_driver_tests.rs` (920 LOC) exercises vendor stubs.

### Missing

| Gap | Impact |
|---|---|
| No fake `NativeBridge` for FFI event stream | Blocks unit tests of `FfiBackend` event transformation (2,577 LOC untested). |
| No fake ASCOM `IDispatch` | `native/nightshade_native/ascom/src/windows_impl.rs` (3,756 LOC) is 0% covered; needs `mockall::automock` on the COM trait boundary. |
| No fake INDI server | `indi/client.rs` has 44 inline tests but they exercise XML parsing only, not full protocol round-trips. |
| No fake camera driver in `native` | Vendor SDKs are tested with real DLLs (hardware-gated). |
| No widget-test harness with `ProviderScope.overrides` for screens | `packages/nightshade_app/test/` has only 4 files, no shared widget fixtures. |
| No fake `NightshadeNetworkClient` for `NetworkBackend` | 3,010 LOC of HTTP wiring untested. |

### Recommendation: high-ROI mocks to add

1. **`FakeNativeBridge`** in `packages/nightshade_bridge/test/fakes/` - enables `FfiBackend` testing across the whole core.
2. **`FakeAscomDriver`** in `native/nightshade_native/ascom/tests/fakes/` - unlocks 3.7k LOC of Windows-COM code.
3. **Widget-test harness** in `packages/nightshade_app/test/harness/` exposing a `pumpAppScreen()` helper that wires mock backend + provider overrides. Unlocks regression coverage on the 100k+ LOC of screens.

---

## 7. CI / Pre-commit

### `.github/workflows/ci.yml` (8 jobs)

| Job | Runs |
|---|---|
| `analyze` | `placeholder_audit.dart`, `fail_closed_check.dart`, `behavioral_audit.dart`, `dependency_hygiene.dart`, `analyzer_rollup.dart` |
| `launch-gate` | duplicate of analyze (zero-warning enforcement) |
| `test-dart` | `melos run test` (Linux only) |
| `test-rust` | `cargo test --all-features` + `cargo clippy -D warnings` (Linux only) |
| `format-check` | `dart format --set-exit-if-changed` + `cargo fmt --check` |
| `build-test` | Matrix: Ubuntu/Windows/macOS Flutter debug build |
| `coverage` | LCOV -> Codecov, **does not fail PR on coverage drop** |

### Gaps

- **No widget-test job split** - widget tests run inside `test-dart` but are not enforced separately; if anyone adds widget tests requiring `flutter_test` Goldens, they'd silently degrade on retina mismatch.
- **No `melos run audit:placeholders` gate** in `analyze` - the CI runs `placeholder_audit.dart` directly without the `--fail-on-new-highrisk` flag the melos script uses; new high-risk markers won't fail PRs.
- **No `cargo test --workspace`** distinct from `--all-features` (subtle: workspace-level vs crate-level).
- **No matrix Rust tests** - only Linux; ASCOM windows_impl.rs is `cfg(windows)` and runs **zero tests anywhere**.
- **No pre-commit hooks** (`.git/hooks/` empty of non-sample files). Devs can push unformatted code; CI is the only gate.
- **Coverage job uses `fail_ci_if_error: false`** - silently swallows codecov upload failures.

### Recommendations

1. Add `pre-commit` config (or husky) running `dart format --set-exit-if-changed` + `cargo fmt --check` locally.
2. Add Windows-host job to `test-rust` matrix so `ascom/` ever gets compile-checked in CI.
3. Wire `melos run audit:placeholders` (with `--fail-on-new-highrisk` + baseline) as a separate required check.
4. Add Codecov **threshold** (-1% per PR) to make coverage drops visible.

---

## 8. Quick-Win Punch List

Sorted by impact-per-effort.

| # | Item | Type | Effort | Impact | Reasoning |
|---|---|---|---|---|---|
| 1 | Delete `Plugin.initialize()` / `Plugin.dispose()` deprecated methods | delete | S | med | Zero consumers; removes 4 lines of misleading API surface. Pure win. |
| 2 | Delete `nightshade_exception.dart` (472 LOC) + `paginated_image_loader.dart` (246 LOC) + `catalog_service.dart` (449 LOC) | delete | S | high | 1,167 LOC of confirmed dead code. Reduces grep noise, simplifies onboarding. |
| 3 | Delete unused weather providers (`goes_satellite`, `noaa_radar`, `openmeteo_cloud`) + `weather_safety_provider` if confirmed dead | delete | S | high | ~1,083 LOC; barrel-exported but never instantiated. |
| 4 | Migrate `DriverBackend`/`NightshadeDeviceType`/`AvailableDevice` callers to canonical names, delete the 3 typedefs | migrate | M | high | ~30 call sites; ends the parallel-vocabulary problem the rest of the codebase navigates. |
| 5 | `.gitignore` FRB-generated files (`frb_generated*`, `bridge_generated.h`) + add post-bootstrap regen step | regen-policy | M | high | Removes ~76k LOC of churn from PR diffs; +3-5 min to fresh clone (acceptable). |
| 6 | Add `FakeNativeBridge` + widget-test harness for `nightshade_app` | cover | L | high | Unlocks testing of 100k+ LOC of UI; biggest coverage gap by far. |
| 7 | Delete `TutorialKeys.navSettings` + `navPolarAlignment` (unreferenced) | delete | S | low | 2 dead GlobalKeys; tiny but free. |
| 8 | Delete duplicate `Phd2Status`/`PlateSolveResult` core models (use bridge canonical) | delete | M | med | Removes confusion at import time; touches `backend_types.dart` barrel. |
| 9 | Migrate `TargetGroupNode` callers, delete typedef + `targetGroups` getter | migrate | M | med | 19 call sites; ends the "header vs group" terminology drift. |
| 10 | Add Windows-host job to `test-rust` CI matrix | ci-add | S | med | Currently zero CI exercise of `ascom/windows_impl.rs` (3,756 LOC). |
| 11 | Add `pre-commit` formatting hook | ci-add | S | med | Prevents trivial format-only churn in PRs. |
| 12 | Re-run `flutter analyze` after `melos bootstrap` and triage the (legitimate) `override_on_non_overriding_member` + `super_formal_parameter_without_associated_named` debt (962 issues) | cover | M | med | Real debt currently masked by missing-bootstrap noise. |

**Top 5 (best impact/effort ratio):** #1, #2, #3, #7, #10. Together: ~2,250 LOC deleted + Windows CI coverage + 4 lines of dead API removed, all in ~1 dev-day of work.

---

*End of report. Length: ~2,650 words.*
