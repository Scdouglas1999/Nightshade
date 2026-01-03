# Nightshade App

The unified application UI shell for Nightshade 2.0, containing all screens, routing, and application-level widgets.

## Overview

This package provides the shared UI layer that works across both desktop and mobile platforms. It contains:

- **App Shell** - The main application widget with navigation and theming
- **Screens** - All major application screens (Dashboard, Equipment, Imaging, Sequencer, etc.)
- **Routing** - Navigation using go_router
- **Wizards** - Step-by-step workflows (Mosaic Wizard, Flat Wizard, etc.)

## Screens

### Dashboard
Overview of current session, equipment status, and quick actions.

### Equipment
Device connections, equipment profiles, protocol selection, and device settings.

### Imaging
Main imaging interface with tabs for:
- **Capture** - Exposure controls and live preview
- **Camera** - Camera settings, cooling, gain/offset
- **Mount** - Slewing and tracking control
- **Focus** - Autofocus and manual focusing
- **Guiding** - PHD2 integration

### Sequencer
Behavior tree-based automation builder with:
- Sequence builder/editor
- Target library
- Templates
- Execution monitoring
- Checkpoint recovery

### Planetarium
GPU-rendered interactive sky visualization for target planning and framing.

### Framing
Target framing assistant with FOV preview and mosaic planning.

### Analytics
Session statistics, image history, and performance analysis.

### Settings
Application configuration and preferences.

## Usage

This package is used internally by the desktop and mobile apps. It is not intended for standalone use.

```dart
import 'package:nightshade_app/nightshade_app.dart';

// The main app shell
NightshadeApp(
  // Configuration...
)
```

## Dependencies

- `nightshade_core` - Business logic, providers, and services
- `nightshade_bridge` - Rust FFI bindings
- `nightshade_ui` - Design system and shared widgets
- `nightshade_planetarium` - Sky visualization
- `nightshade_plugins` - Plugin system
- `nightshade_webrtc` - Remote control

## Architecture

Uses Riverpod for state management with go_router for navigation. Screens access backend services through providers defined in nightshade_core.

## License

Part of Nightshade 2.0 - see LICENSE file in repository root.
