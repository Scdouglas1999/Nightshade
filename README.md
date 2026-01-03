# Nightshade

**A modern, cross-platform astrophotography suite**

<!-- TODO: Add hero screenshot showing main imaging interface -->

Nightshade is a complete imaging platform for astrophotographers, combining camera control, mount automation, focusing, guiding, and sequence planning in a single unified application. Built with Flutter and Rust for performance and reliability across Windows, macOS, Linux, iOS, and Android.

> **Early Alpha**: Nightshade is under active development. Core features work but expect rough edges, breaking changes, and incomplete documentation. Not recommended for critical imaging sessions yet. We welcome testers and contributors!

---

## Features

### Imaging

<!-- TODO: Screenshot of imaging interface -->

- Full camera control with live preview and auto-stretch
- Exposure sequencing with configurable delays and looping
- Cooled camera temperature management with gradual ramp
- Gain, offset, and binning presets
- Region of interest (ROI) for faster downloads
- FITS and TIFF output with customizable file naming templates
- Filter wheel integration with focus offsets
- Dithering support via PHD2

### Mount Control

<!-- TODO: Screenshot of mount control panel -->

- Directional slewing with adjustable speed (guide/center/find/slew)
- Go-to with manual coordinates or target selection
- Tracking modes: sidereal, lunar, solar, and custom rates
- Park/unpark with configurable positions
- Automatic meridian flip with re-centering and refocus
- Horizon and meridian safety limits

### Focusing

- V-curve autofocus with HFR measurement
- Manual focus mode with real-time star profile
- Temperature compensation and drift tracking
- Backlash compensation
- Focus offsets per filter

### Guiding

- PHD2 integration for autoguiding
- Real-time guiding graph (RA/Dec error, RMS)
- Dithering control with settle detection
- Guiding alerts and monitoring

### Sequencer

<!-- TODO: Screenshot of sequence builder -->

The sequencer uses a behavior tree architecture for building complex automated workflows:

- **Instruction Nodes**: Camera exposure, slew, autofocus, filter change, cool camera, start/stop guiding, park/unpark, wait
- **Logic Nodes**: Loop, parallel execution, conditionals, sequence grouping
- **Trigger Nodes**: HFR monitor, guiding monitor, weather monitor, time triggers, meridian flip handler

Build anything from simple single-target sequences to multi-target nights with automatic meridian flips, weather safety, and adaptive refocusing.

### Planetarium

<!-- TODO: Screenshot of planetarium view -->

- GPU-accelerated interactive sky map
- Deep sky object catalogs (Messier, NGC, IC, Caldwell)
- Target altitude charts and visibility planning
- Framing preview with camera field of view
- Moon phase and separation warnings

### Remote Control

- Control your imaging rig from your phone or tablet
- Peer-to-peer WebRTC connection (no cloud required)
- Live image preview and equipment status
- Full sequence control

---

## Supported Equipment

### Protocols

| Protocol | Platforms | Description |
|----------|-----------|-------------|
| **ASCOM** | Windows | Native COM driver support via ASCOM Platform |
| **INDI** | Linux, macOS | Open-source instrument control protocol |
| **Alpaca** | All | ASCOM's cross-platform REST API |

### Camera SDKs

Direct SDK integration for enhanced performance with supported cameras:

- ZWO ASI
- QHY
- PlayerOne
- Atik
- FLI (Finger Lakes Instrumentation)
- Moravian Instruments
- SBIG
- SVBony
- Touptek

### Other Equipment

- Mounts (via ASCOM/INDI/Alpaca)
- Focusers (via ASCOM/INDI/Alpaca)
- Filter wheels (via ASCOM/INDI/Alpaca)
- Rotators (via ASCOM/INDI/Alpaca)
- Weather stations (via ASCOM/INDI/Alpaca)

---

## Installation

### Download

Pre-built releases will be available on the [Releases](https://github.com/Scdouglas1999/nightshade/releases) page once the project reaches beta status.

| Platform | Format |
|----------|--------|
| Windows | `.exe` installer |
| macOS | `.dmg` disk image |
| Linux | `.AppImage`, `.deb` |
| iOS | TestFlight (coming soon) |
| Android | `.apk` / Play Store (coming soon) |

### Requirements

**Windows**
- Windows 10 or 11 (64-bit)
- .NET Framework 4.8+ (for ASCOM)
- [ASCOM Platform](https://ascom-standards.org/) (optional, for ASCOM drivers)

**macOS**
- macOS 13 (Ventura) or later
- Intel or Apple Silicon

**Linux**
- Ubuntu 22.04+ or equivalent
- [INDI](https://indilib.org/) (optional, for equipment control)

---

## Development

### Prerequisites

- [Flutter](https://flutter.dev/) 3.0+
- [Rust](https://rustup.rs/) (latest stable)
- [Melos](https://melos.invertase.dev/) (`dart pub global activate melos`)

**Windows additionally requires:**
- Visual Studio 2022 with C++ workload
- [LLVM/Clang](https://releases.llvm.org/) (for flutter_rust_bridge codegen)

**Linux additionally requires:**
- `build-essential`, `libgtk-3-dev`, `liblzma-dev`, `libstdc++-12-dev`

### Quick Start

```bash
# Clone the repository
git clone https://github.com/Scdouglas1999/nightshade.git
cd nightshade

# Install dependencies and generate code
melos bootstrap

# Build and run (handles Rust compilation, FFI codegen, and Flutter)
melos run dev
```

### Build Commands

```bash
# Development (full rebuild with FRB codegen)
melos run dev

# Quick rebuild (skip FRB if only Rust implementation changed)
melos run dev:quick

# Build without running
melos run dev:norun

# Clean everything
melos run dev:clean

# Run tests
melos run test

# Code analysis
melos run analyze

# Format code
melos run format

# Regenerate freezed/json_serializable/drift/FFI bindings
melos run generate
```

### Project Structure

```
nightshade/
├── apps/
│   ├── desktop/              # Windows/macOS/Linux Flutter app
│   └── mobile/               # iOS/Android Flutter app
│
├── packages/
│   ├── nightshade_app/       # Shared UI shell and navigation
│   ├── nightshade_core/      # Business logic, database, providers
│   ├── nightshade_bridge/    # Dart FFI bindings (flutter_rust_bridge)
│   ├── nightshade_ui/        # Design system and shared widgets
│   ├── nightshade_planetarium/  # GPU-rendered sky visualization
│   ├── nightshade_plugins/   # Plugin host and API
│   ├── nightshade_screens/   # Feature screens
│   ├── nightshade_updater/   # OTA update system
│   └── nightshade_webrtc/    # P2P remote control
│
├── native/nightshade_native/
│   ├── bridge/               # FFI entry point (cdylib)
│   ├── sequencer/            # Behavior tree automation engine
│   ├── ascom/                # Windows ASCOM COM drivers
│   ├── indi/                 # Linux/macOS INDI protocol
│   ├── alpaca/               # Cross-platform ASCOM Alpaca
│   ├── imaging/              # Image processing (LibRaw, FITS)
│   └── native/               # Vendor SDK FFI bindings
│
├── lib/                      # Third-party native libraries (LibRaw)
├── scripts/                  # Build and deployment scripts
├── docs/                     # Documentation
└── tools/                    # Development utilities
```

### Architecture

**State Management**: Riverpod providers throughout, with a backend abstraction layer supporting local (FFI), remote (network), and offline modes.

**FFI Bridge**: Dart communicates with Rust via [flutter_rust_bridge](https://github.com/aspect-build/flutter_rust_bridge) 2.0. Bindings are auto-generated from the Rust API.

**Database**: [Drift](https://drift.simonbinder.eu/) (SQLite) for equipment profiles, targets, sessions, sequences, and settings.

**Sequencer**: Rust-based behavior tree engine with three node categories:
- Instruction nodes (hardware actions)
- Trigger nodes (parallel monitors/watchdogs)
- Logic nodes (control flow)

### Rust Development

```bash
cd native/nightshade_native

# Check compilation
cargo check --all-features

# Run tests
cargo test --all-features

# Lint
cargo clippy --all-features -- -D warnings
```

### Troubleshooting

**FFI codegen fails with "stdbool.h not found" (Windows)**

Set the CPATH environment variable before running codegen:

```powershell
$env:CPATH = "C:\Program Files\LLVM\lib\clang\21\include;C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.43.34808\include;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\ucrt"
flutter_rust_bridge_codegen generate
```

**Hash mismatch errors at runtime**

The Dart bindings and compiled Rust library are out of sync. Always use `melos run dev` instead of `flutter run` directly after Rust changes.

**Clean rebuild**

```bash
melos run dev:clean
```

See [docs/FRB_TROUBLESHOOTING.md](docs/FRB_TROUBLESHOOTING.md) for more solutions.

---

## Contributing

Contributions are welcome! Nightshade is in early alpha and there's plenty to do:

- Bug reports and feature requests via [Issues](https://github.com/Scdouglas1999/nightshade/issues)
- Code contributions via pull requests
- Documentation improvements
- Testing on different equipment

Please read the contributing guidelines (coming soon) before submitting PRs.

### Development Philosophy

- **Keep it simple**: Avoid over-engineering. Solve today's problems, not hypothetical future ones.
- **Performance matters**: Astrophotography involves large images and real-time control. Optimize where it counts.
- **Cross-platform first**: Features should work on all platforms where possible, with graceful degradation where not.
- **Test your changes**: Run `melos run test` and `melos run analyze` before submitting.

---

## Roadmap

**Current focus (Alpha)**
- Core imaging workflow stability
- Equipment compatibility testing
- Sequencer reliability

**Upcoming**
- Plate solving integration
- Flat wizard
- Mosaic planning
- Plugin system
- Cloud sync for profiles and sequences

---

## License

<!-- TODO: Add license -->

License TBD. See [LICENSE](LICENSE) for details.

---

## Acknowledgments

Nightshade builds on the work of many open-source projects and standards:

- [ASCOM](https://ascom-standards.org/) — Astronomy Common Object Model
- [INDI](https://indilib.org/) — Instrument Neutral Distributed Interface
- [PHD2](https://openphdguiding.org/) — Open-source autoguiding
- [Flutter](https://flutter.dev/) — Cross-platform UI framework
- [Rust](https://www.rust-lang.org/) — Systems programming language
- [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge) — Dart/Rust FFI generator
- [LibRaw](https://www.libraw.org/) — RAW image processing

---

<p align="center">
  <i>Clear skies!</i>
</p>
