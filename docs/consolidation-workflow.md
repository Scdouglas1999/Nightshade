---
description: How to execute the codebase consolidation refactoring plan
---

# Codebase Consolidation Workflow

This workflow executes the consolidation plan in `/docs/consolidation-implementation-plan.md`.

## Prerequisites

- Flutter is at `/home/scdouglas/flutter/bin/flutter`
- Cargo is in standard PATH
- Project root is `/home/scdouglas/Documents/Nightshade`

## Verification Commands

Run these after EVERY change:

1. Build Dart:
```bash
cd /home/scdouglas/Documents/Nightshade
/home/scdouglas/flutter/bin/flutter build linux --debug
```

2. Run Dart tests:
```bash
/home/scdouglas/flutter/bin/flutter test packages/nightshade_core/test/
```

3. Build Rust (if Rust files changed):
```bash
cargo build --release --manifest-path native/nightshade_native/bridge/Cargo.toml
```

4. Run app manually:
```bash
cd apps/desktop && /home/scdouglas/flutter/bin/flutter run -d linux
```

## Workflow Steps

### Phase 1: Extract Dart Widgets

For each widget to extract from a large screen file:

1. Read the implementation plan: `docs/consolidation-implementation-plan.md`

2. Create target directory:
```bash
mkdir -p packages/nightshade_app/lib/screens/{screen_name}/widgets
```

3. For each widget class (e.g., `_HistogramWidget`):
   - Create new file with public name (remove underscore)
   - Copy class with all required imports
   - Add import to original file
   - Replace usage of `_PrivateName` with `PublicName`
   - Delete original class from source file

4. Build and test (use commands above)

5. Commit:
```bash
git add .
git commit -m "refactor({scope}): extract {WidgetName} to separate file"
```

### Phase 2: Split Providers with Re-exports

1. Create target directory:
```bash
mkdir -p packages/nightshade_core/lib/src/providers/{category}
```

2. Create barrel file `{category}_providers.dart` with exports

3. Move each provider to its own file

4. Update original file to re-export:
```dart
export '{category}/{category}_providers.dart';
```

5. Build and test

6. Commit

### Phase 3: Split Rust Modules

1. Create module directory:
```bash
mkdir -p native/nightshade_native/bridge/src/{module_name}
```

2. Create `mod.rs` with submodule declarations and re-exports

3. Move functions to submodules one category at a time

4. Keep `#[flutter_rust_bridge::frb]` attributes on all public functions

5. Build Rust

6. Delete original file after all moves complete

7. Commit

## Golden Rules

- **NEVER change any business logic** - Only move code
- **ALWAYS use re-exports** - Existing imports must work
- **ONE change at a time** - Verify before moving on
- **BUILD after every change** - Catch breakage early
- **COMMIT after verified change** - Enable rollback

## Rollback

If build fails:
```bash
git checkout .
```

If tests fail after commit:
```bash
git revert HEAD
```
