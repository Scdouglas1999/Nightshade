# Contributing to Nightshade 2.0

Welcome. This document covers the local setup steps every contributor should run once, plus the conventions CI enforces.

## One-time setup

After cloning the repo:

```bash
# 1. Bootstrap the workspace (installs deps, runs code generators).
melos bootstrap

# 2. Install the pre-commit hook so dart format / cargo fmt / dart analyze
#    run on staged files before each commit.
#
#    macOS / Linux / WSL:
./scripts/install-hooks.sh

#    Windows PowerShell:
.\scripts\install-hooks.ps1
```

The pre-commit hook checks only staged files, so it stays fast on partially-staged worktrees. If you ever need to bypass it (emergency hotfix), run `SKIP_PRECOMMIT=1 git commit ...` — CI will still gate the same checks on the PR.

## What CI enforces (and what the hook mirrors)

Every PR runs:

| Gate | Local equivalent |
|---|---|
| `dart format --set-exit-if-changed` | pre-commit hook (staged Dart files) |
| `cargo fmt --all --check` | pre-commit hook (when staging `.rs`) |
| `dart analyze` (analyzer-rollup with zero-error gate) | pre-commit hook (staged Dart files) + `melos run analyze` |
| `flutter test` across all packages | `melos run test` |
| `cargo test --all-features` + `cargo clippy -D warnings` (Linux + Windows) | `cd native/nightshade_native && cargo test --all-features && cargo clippy --all-features -- -D warnings` |
| `melos run audit:placeholders` (fails on **new** high-risk markers) | `melos run audit:placeholders` |
| `melos run audit:fail-closed` | `melos run audit:fail-closed` |
| `cargo tree --duplicates` (fails on multi-semver duplicates) | `cd native/nightshade_native && cargo tree --duplicates` |
| Codecov coverage threshold (max −1% regression) | `melos run test -- --coverage` |

## House rules

These are non-negotiable per `CLAUDE.md`:

1. **No stubs / placeholders.** If you find yourself writing `TODO: implement` or returning a hardcoded value, stop and do the full implementation. Stubs get forgotten.
2. **Errors are a feature.** Do not silently swallow failures with `try { ... } catch { /* ignore */ }`, `unwrap_or_default()`, or `if let Ok(_) = ...`. Either propagate the error, log it with the appropriate severity, or document why the fallback is correct.
3. **Use `melos run dev` after Rust changes.** Direct `flutter run` skips FRB regen and the DLL copy step, which causes hash mismatches at runtime.
4. **Run `melos run analyze` before pushing.** The analyzer-rollup gate is the most common CI failure for first-time contributors.

## Generated code

Generated files are committed but tagged `linguist-generated=true` in `.gitattributes`, so GitHub's diff UI collapses them by default. If you regenerate them (FRB, freezed, json_serializable, drift), commit the regenerated output in a dedicated commit named `chore: regenerate generated code` so reviewers can skip it cleanly.

## Where to put new code

See `CLAUDE.md` § "Where to Make Changes" for the canonical table. Quick reference:

- UI for desktop only: `apps/desktop/lib/`
- UI shared across platforms: `packages/nightshade_app/lib/`
- Business logic / providers: `packages/nightshade_core/lib/src/`
- Rust device drivers: `native/nightshade_native/{ascom,indi,alpaca,native}/`
- Rust automation / sequencer: `native/nightshade_native/sequencer/`

## Workflow waves

The active cleanup work is tracked in `docs/code-quality/v2.5.x-roadmap.md`. Agents pick scope from §4 (per-wave decomposition); humans pick from §3 (ship plan). Each task file in `docs/code-quality/` (`audit-arch.md`, `audit-dart.md`, `audit-rust.md`, `audit-tests.md`, `audit-observe.md`) is cross-referenced from the roadmap.
