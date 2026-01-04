# Codebase Consolidation Implementation Plan

**Created:** 2025-01-04  
**Status:** Approved for Implementation  
**Scope:** File structure consolidation and maintainability improvements

---

## ⚠️ CRITICAL: Read This First

> **This document describes STRUCTURAL refactoring only. The goal is to reorganize files for better maintainability while PRESERVING 100% OF EXISTING FUNCTIONALITY.**

### Prerequisites

**Flutter Location:**
```bash
/home/scdouglas/flutter/bin/flutter
```

**Rust/Cargo:** Standard PATH (`cargo`, `rustc`)

**Project Root:** `/home/scdouglas/Documents/Nightshade`

**Verification Commands (run after EVERY change):**
```bash
# Dart build
/home/scdouglas/flutter/bin/flutter build linux --debug

# Dart tests
cd /home/scdouglas/Documents/Nightshade
/home/scdouglas/flutter/bin/flutter test packages/nightshade_core/test/

# Rust build
cargo build --release --manifest-path native/nightshade_native/bridge/Cargo.toml

# Run app manually
cd apps/desktop
/home/scdouglas/flutter/bin/flutter run -d linux
```

### Golden Rules - MEMORIZE THESE

1. **NEVER change any business logic** - Only move code between files
2. **ALWAYS use re-exports** - Existing import paths must continue to work
3. **ONE change at a time** - Complete and verify each step before the next
4. **BUILD AND TEST after every change** - Catch breakage immediately
5. **COMMIT after each verified change** - Enable easy rollback
6. **If something breaks, STOP and revert immediately**

### If Something Breaks

```bash
# Immediately revert to last known good state
git checkout .

# Or if already committed
git revert HEAD
```

---

## Project Structure Overview

```
/home/scdouglas/Documents/Nightshade/
├── apps/
│   └── desktop/                    # Flutter desktop app entry point
├── packages/
│   ├── nightshade_app/             # UI screens and widgets
│   ├── nightshade_core/            # Business logic, providers, services
│   ├── nightshade_bridge/          # FFI bindings to Rust
│   ├── nightshade_ui/              # Design system
│   └── ... (other packages)
└── native/
    └── nightshade_native/
        └── bridge/src/             # Rust FFI code
```

---

## Phase 1: Dart Screen Decomposition

### 1.1 Split `imaging_screen.dart` (5093 lines)

**File:** `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart`

> ⚠️ **SAFETY WARNING:** This screen handles live camera control. Do not modify any camera interaction logic. Only extract widget classes into separate files.

**Current Structure (classes in this file):**
```
Line 25:   ImagingScreen (main widget)
Line 32:   _ImagingScreenState (main state - KEEP IN PLACE)
Line 616:  _LivePreviewArea → Extract to live_preview_area.dart
Line 912:  _StarFieldPainter → Extract to painters/star_field_painter.dart
Line 937:  _OverlayChip → Extract to widgets/overlay_chip.dart
Line 975:  _OverlayIconButton → Extract to widgets/overlay_icon_button.dart
Line 1038: _HistogramWidget → Extract to widgets/histogram_widget.dart
Line 1101: _HistogramPainter → Keep with histogram_widget.dart
Line 1140: _ImageStatsOverlay → Extract to widgets/image_stats_overlay.dart
Line 1187: _StatLine → Keep with image_stats_overlay.dart
... (more widgets follow)
```

**Target Structure:**
```
packages/nightshade_app/lib/screens/imaging/
├── imaging_screen.dart           # Keep ImagingScreen + _ImagingScreenState
├── widgets/
│   ├── live_preview_area.dart    # _LivePreviewArea → LivePreviewArea
│   ├── histogram_widget.dart     # _HistogramWidget + _HistogramPainter
│   ├── image_stats_overlay.dart  # _ImageStatsOverlay + _StatLine
│   ├── overlay_chip.dart         # _OverlayChip
│   └── overlay_icon_button.dart  # _OverlayIconButton
└── painters/
    └── star_field_painter.dart   # _StarFieldPainter
```

**Step-by-Step Example: Extract `_HistogramWidget`**

1. **Create new file:**
   ```bash
   mkdir -p packages/nightshade_app/lib/screens/imaging/widgets
   touch packages/nightshade_app/lib/screens/imaging/widgets/histogram_widget.dart
   ```

2. **Copy the widget class (lines 1038-1138) to new file:**
   ```dart
   // histogram_widget.dart
   import 'dart:typed_data';
   import 'package:flutter/material.dart';
   import 'package:flutter_riverpod/flutter_riverpod.dart';
   import 'package:nightshade_core/nightshade_core.dart';

   /// Histogram display widget for imaging screen
   class HistogramWidget extends ConsumerWidget {
     final bool isLarge;
     final Uint8List? histogramR;
     final Uint8List? histogramG;
     final Uint8List? histogramB;
     final Uint8List? histogramL;

     const HistogramWidget({
       super.key,
       this.isLarge = false,
       this.histogramR,
       this.histogramG,
       this.histogramB,
       this.histogramL,
     });

     @override
     Widget build(BuildContext context) {
       // COPY THE EXACT BUILD METHOD BODY - DO NOT MODIFY
     }
   }

   class _HistogramPainter extends CustomPainter {
     // COPY EXACTLY AS-IS
   }
   ```

3. **Note:** Remove the underscore prefix (`_HistogramWidget` → `HistogramWidget`) to make it public.

4. **In `imaging_screen.dart`, add import and replace usage:**
   ```dart
   import 'widgets/histogram_widget.dart';
   
   // Replace all _HistogramWidget with HistogramWidget
   ```

5. **Delete the original `_HistogramWidget` and `_HistogramPainter` classes from `imaging_screen.dart`**

6. **Build and test:**
   ```bash
   /home/scdouglas/flutter/bin/flutter build linux --debug
   ```

7. **Commit:**
   ```bash
   git add .
   git commit -m "refactor(imaging): extract HistogramWidget to separate file"
   ```

8. **Repeat for each widget class**

**CRITICAL: DO NOT MODIFY:**
- Any method implementations
- State management logic (`ref.watch`, `ref.read`)
- Widget parameters
- Any business logic

---

### 1.2 Split `settings_screen.dart` (3217 lines)

**File:** `packages/nightshade_app/lib/screens/settings/settings_screen.dart`

> ⚠️ **SAFETY WARNING:** Settings affect app behavior. Do not modify how settings are read or saved. Only move tab widgets to separate files.

**Target Structure:**
```
screens/settings/
├── settings_screen.dart          # Keep as tab scaffold
├── tabs/
│   ├── general_settings_tab.dart
│   ├── location_settings_tab.dart
│   ├── equipment_settings_tab.dart
│   ├── imaging_settings_tab.dart
│   ├── weather_settings_tab.dart
│   └── advanced_settings_tab.dart
```

**Same extraction pattern as 1.1 - one tab at a time.**

---

## Phase 2: Provider Organization

### 2.1 Split `equipment_provider.dart` (1149 lines)

**File:** `packages/nightshade_core/lib/src/providers/equipment_provider.dart`

> ⚠️ **SAFETY WARNING:** Equipment providers manage device state. Changes here can break device connections. Use the RE-EXPORT pattern to ensure backward compatibility.

**Current Structure:**
```dart
// Line 12: cameraStateProvider + CameraStateNotifier (lines 12-150)
// Line 152: mountStateProvider + MountStateNotifier (lines 152-300)
// Line 302: focuserStateProvider + FocuserStateNotifier (lines 302-400)
// ... and so on for each device type
```

**Target Structure:**
```
providers/equipment/
├── equipment_providers.dart      # Barrel file - re-exports everything
├── camera_state_provider.dart
├── mount_state_provider.dart
├── focuser_state_provider.dart
├── filter_wheel_state_provider.dart
├── guider_state_provider.dart
├── rotator_state_provider.dart
├── dome_state_provider.dart
├── weather_state_provider.dart
├── safety_monitor_state_provider.dart
└── cover_calibrator_state_provider.dart
```

**Step-by-Step Implementation:**

1. **Create directory:**
   ```bash
   mkdir -p packages/nightshade_core/lib/src/providers/equipment
   ```

2. **Create `camera_state_provider.dart`:**
   ```dart
   // camera_state_provider.dart
   import 'dart:async';
   import 'package:flutter_riverpod/flutter_riverpod.dart';
   import 'package:nightshade_bridge/src/api.dart' as bridge_api;
   import '../../services/device_service.dart';
   import '../../models/equipment/equipment_models.dart';

   /// Default retry configuration for device operations
   const int _defaultMaxRetries = 3;
   const Duration _defaultRetryDelay = Duration(seconds: 1);

   /// Camera state provider
   final cameraStateProvider = StateNotifierProvider<CameraStateNotifier, CameraState>((ref) {
     return CameraStateNotifier(ref);
   });

   class CameraStateNotifier extends StateNotifier<CameraState> {
     // COPY ENTIRE CLASS EXACTLY AS-IS FROM ORIGINAL FILE
   }
   ```

3. **Create barrel file `equipment_providers.dart`:**
   ```dart
   // equipment_providers.dart
   export 'camera_state_provider.dart';
   export 'mount_state_provider.dart';
   export 'focuser_state_provider.dart';
   export 'filter_wheel_state_provider.dart';
   export 'guider_state_provider.dart';
   export 'rotator_state_provider.dart';
   export 'dome_state_provider.dart';
   export 'weather_state_provider.dart';
   export 'safety_monitor_state_provider.dart';
   export 'cover_calibrator_state_provider.dart';
   ```

4. **Update original `equipment_provider.dart` for BACKWARD COMPATIBILITY:**
   ```dart
   // equipment_provider.dart
   // BACKWARD COMPATIBILITY - re-exports from new location
   // All existing imports of this file will continue to work
   export 'equipment/equipment_providers.dart';
   ```

5. **Build and test:**
   ```bash
   /home/scdouglas/flutter/bin/flutter build linux --debug
   /home/scdouglas/flutter/bin/flutter test packages/nightshade_core/test/
   ```

6. **Commit:**
   ```bash
   git add .
   git commit -m "refactor(providers): split equipment_provider into per-device files"
   ```

**CRITICAL:** The re-export in step 4 ensures ALL existing code that imports `equipment_provider.dart` continues to work without changes.

---

## Phase 3: Service Organization

### 3.1 Split `device_service.dart` (2092 lines)

**File:** `packages/nightshade_core/lib/src/services/device_service.dart`

> ⚠️ **SAFETY WARNING:** DeviceService is the core interface to all equipment. This is HIGH RISK. Use the MIXIN approach to avoid breaking the class interface.

**Use Mixins to Split Without Breaking:**

```dart
// device_service.dart - AFTER refactoring
import 'devices/_camera_service_mixin.dart';
import 'devices/_mount_service_mixin.dart';
// ... etc

class DeviceService with 
    _CameraServiceMixin,
    _MountServiceMixin,
    _FocuserServiceMixin,
    _GuiderServiceMixin,
    _FilterWheelServiceMixin {
  
  // Core fields stay here
  final Ref _ref;
  final NightshadeBackend _backend;
  
  DeviceService(this._ref, this._backend) {
    // existing initialization stays here
  }
  
  // Core methods stay here
  // Device-specific methods are now in mixins
}
```

**Each mixin file:**
```dart
// services/devices/_camera_service_mixin.dart
part of '../device_service.dart';

mixin _CameraServiceMixin {
  Ref get _ref;  // Provided by DeviceService
  NightshadeBackend get _backend;  // Provided by DeviceService

  // All camera-related methods moved here - UNCHANGED
  Future<void> connectCamera(String deviceId) async { ... }
  Future<void> disconnectCamera() async { ... }
  Future<CameraStatus> getCameraStatus() async { ... }
}
```

**CRITICAL:** The `DeviceService` class interface must remain IDENTICAL. All existing code calling `deviceService.connectCamera()` must continue to work.

---

## Phase 4: Rust Module Reorganization

### 4.1 Split `api.rs` (7459 lines)

**File:** `native/nightshade_native/bridge/src/api.rs`

> ⚠️ **SAFETY WARNING:** This is the FFI boundary. Incorrect changes will crash the app. The Rust compiler will catch most errors, but test thoroughly.

**Current Structure (approximate line ranges):**
```rust
// Lines 1-100: Imports, static state, cache structures
// Lines 100-240: Initialization, event stream
// Lines 240-800: Device discovery (ASCOM, Alpaca, INDI, Native)
// Lines 800-1500: Device connection/disconnection
// Lines 1500-2500: Camera operations
// Lines 2500-3500: Mount operations
// Lines 3500-4500: Focuser, filter wheel operations
// Lines 4500-5500: Dome, rotator, weather operations
// Lines 5500-6500: Imaging operations
// Lines 6500-7459: Sequencer, misc operations
```

**Target Structure:**
```
bridge/src/
├── api/
│   ├── mod.rs                    # Re-exports + shared state
│   ├── init.rs                   # Initialization, event stream
│   ├── discovery.rs              # All device discovery
│   ├── camera_api.rs             # Camera operations
│   ├── mount_api.rs              # Mount operations
│   ├── focuser_api.rs            # Focuser operations
│   ├── filter_wheel_api.rs       # Filter wheel operations
│   ├── dome_api.rs               # Dome operations
│   ├── rotator_api.rs            # Rotator operations
│   ├── weather_api.rs            # Weather operations
│   ├── guider_api.rs             # Guider/PHD2 operations
│   ├── imaging_api.rs            # Image processing
│   └── sequencer_api.rs          # Sequencer operations
```

**Step-by-Step:**

1. **Create directory:**
   ```bash
   mkdir -p native/nightshade_native/bridge/src/api
   ```

2. **Create `api/mod.rs`:**
   ```rust
   //! Public API exposed to Dart via flutter_rust_bridge

   mod init;
   mod discovery;
   mod camera_api;
   mod mount_api;
   // ... etc

   // Re-export everything
   pub use init::*;
   pub use discovery::*;
   pub use camera_api::*;
   pub use mount_api::*;
   // ... etc

   // Shared state stays here
   use std::sync::OnceLock;
   use crate::state::SharedAppState;
   use crate::devices::DeviceManager;

   static APP_STATE: OnceLock<SharedAppState> = OnceLock::new();
   // ... other static items
   ```

3. **Move functions group by group:**
   - Move `api_init*` functions to `init.rs`
   - Move `api_discover_*` functions to `discovery.rs`
   - Move `api_camera_*` (and `api_connect_camera`, etc.) to `camera_api.rs`

4. **CRITICAL: Keep `#[flutter_rust_bridge::frb]` attributes on all public functions**

5. **Update `lib.rs`:**
   ```rust
   // Change:
   mod api;
   // Rust automatically finds api/mod.rs when api.rs doesn't exist
   ```

6. **Build:**
   ```bash
   cargo build --release --manifest-path native/nightshade_native/bridge/Cargo.toml
   ```

7. **After confirming build succeeds, delete original `api.rs`**

8. **Commit:**
   ```bash
   git add .
   git commit -m "refactor(rust): split api.rs into per-category modules"
   ```

---

## Implementation Order

| Order | Phase | Item | Effort | Risk |
|-------|-------|------|--------|------|
| 1 | 1.1 | Split `imaging_screen.dart` | 3 hrs | Low |
| 2 | 1.2 | Split `settings_screen.dart` | 2 hrs | Low |
| 3 | 2.1 | Split `equipment_provider.dart` | 2 hrs | Low |
| 4 | 3.2 | Consolidate weather system | 3 hrs | Low |
| 5 | 4.1 | Split `api.rs` | 4 hrs | Medium |
| 6 | 4.2 | Split `devices.rs` | 4 hrs | Medium |
| 7 | 3.1 | Split `device_service.dart` | 3 hrs | Medium |
| 8 | 1.3 | Split `framing_screen.dart` | 2 hrs | Low |
| 9 | 1.4 | Split `planetarium_screen.dart` | 2 hrs | Low |
| 10 | 2.2 | Split `sequence_provider.dart` | 2 hrs | Low |

**Total Estimated Effort:** ~27 hours

---

## Verification Checklist

After **EVERY** change:

- [ ] `/home/scdouglas/flutter/bin/flutter build linux --debug` succeeds
- [ ] `/home/scdouglas/flutter/bin/flutter test packages/nightshade_core/test/` passes
- [ ] `cargo build --release --manifest-path native/nightshade_native/bridge/Cargo.toml` succeeds
- [ ] App launches: `cd apps/desktop && /home/scdouglas/flutter/bin/flutter run -d linux`
- [ ] No new warnings introduced (check output)

### Manual Testing (after each phase)

- [ ] App launches without errors
- [ ] Can connect to simulator camera
- [ ] Can take a test exposure
- [ ] Settings screen opens and saves work
- [ ] Weather screen loads data
- [ ] No console errors

---

## Git Workflow

```bash
# Before starting ANY refactor
git status  # Must be clean
git checkout -b refactor/split-{component-name}

# After each small change
/home/scdouglas/flutter/bin/flutter build linux --debug  # Must succeed
git add .
git commit -m "refactor({scope}): {description}"

# After completing a phase
git checkout main
git merge refactor/split-{component-name}
git branch -d refactor/split-{component-name}
git push
```

---

## Rollback Procedures

### Build fails after a change:
```bash
git diff                # See what changed
git checkout .          # Revert all uncommitted changes
```

### Tests fail after a commit:
```bash
git log --oneline -5    # Find the breaking commit
git revert HEAD         # Revert last commit
```

### App broken after merge:
```bash
git log --oneline -10   # Find last good state
git reset --hard HEAD~N # Go back N commits (CAREFUL!)
```

---

## Summary for AI Agents

1. **This is STRUCTURAL refactoring ONLY** - no behavior changes allowed
2. **Use re-exports everywhere** - `export 'new/location.dart';`
3. **One file at a time, one commit at a time**
4. **Build and test after EVERY change** - use exact commands above
5. **If anything breaks, REVERT immediately** - `git checkout .`
6. **When in doubt, DON'T MODIFY - just MOVE code**
7. **Flutter path is `/home/scdouglas/flutter/bin/flutter`** - not in PATH
8. **Preserve ALL existing imports** - use barrel files and re-exports
