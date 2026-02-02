<p align="center">
  <!-- TODO: Add logo here -->
  <h1 align="center">Nightshade</h1>
  <p align="center">
    <strong>A modern, cross-platform astrophotography suite</strong>
  </p>
  <p align="center">
    <img src="https://img.shields.io/badge/version-2.0.0-blue" alt="Version: 2.0.0">
    <img src="https://img.shields.io/badge/platforms-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20iOS%20%7C%20Android-blue" alt="Platforms">
    <img src="https://img.shields.io/badge/built%20with-Flutter%20%2B%20Rust-blue" alt="Built with Flutter + Rust">
  </p>
</p>

<!-- TODO: Add hero screenshot showing main imaging interface -->

Nightshade is a complete imaging platform for astrophotographers, combining camera control, mount automation, focusing, guiding, and sequence planning in a single unified application. Built with Flutter and Rust for performance and reliability across desktop and mobile.

> **Early Alpha Status**: This software is currently in very early stages of functionality. Some things are polished and work quite well, others are pretty sketchy at the moment. Specifically, the Sequencer has been in a state of somewhat working for a while now, and while you may experience no problems, it would genuinely surprise me. Just keep in mind the early nature and rapidly changing state of the app. 

> **Note on ReadMe**: This project is progressing extremely quickly. There may be some areas of this readme that become outdated or inaccurate. I will do my best to keep things updated but you may find that some features in-app are different (hopefully improved) versus the readme.

---

## Features

<table>
<tr>
<td width="50%" valign="top">

### Imaging

<!-- TODO: Screenshot of imaging interface -->

- Live preview with auto-stretch
- Exposure sequencing with delays and looping
- Cooled camera temperature management
- Gain, offset, and binning presets
- ROI for faster downloads
- FITS/TIFF/XISF with customizable naming
- Filter wheel integration
- Dithering via PHD2

</td>
<td width="50%" valign="top">

### Mount Control

<!-- TODO: Screenshot of mount control panel -->

- Directional slewing (guide to slew speeds)
- Go-to with coordinates or target selection
- Sidereal, lunar, solar, and custom tracking
- Park/unpark with custom positions
- Automatic meridian flip
- Horizon and meridian safety limits

</td>
</tr>
<tr>
<td width="50%" valign="top">

### Focusing

- V-curve autofocus with HFR
- Manual focus with live star profile
- Temperature compensation
- Backlash compensation
- Per-filter focus offsets
- Focus prediction with ML-based modeling

</td>
<td width="50%" valign="top">

### Guiding

- PHD2 integration
- Real-time RA/Dec error graph
- Dithering with settle detection
- Guiding alerts and monitoring
- Star image display
- Calibration management

</td>
</tr>
</table>

### Sequencer

<!-- TODO: Screenshot of sequence builder -->

The sequencer uses a **behavior tree architecture** for building complex automated workflows:

| Node Type | Examples |
|-----------|----------|
| **Instruction** | Expose, slew, autofocus, filter change, cool camera, park/unpark, wait, dither, rotate, open/close dome |
| **Logic** | Loop, parallel execution, conditionals, sequence grouping, recovery |
| **Trigger** | HFR monitor, guiding monitor, weather safety, time triggers, meridian flip |

Build anything from simple single-target sequences to multi-target nights with automatic meridian flips, weather safety, checkpoint recovery, and adaptive refocusing.

### Planetarium

<!-- TODO: Screenshot of planetarium view -->

- GPU-accelerated interactive sky map
- Messier, NGC, IC, Caldwell, Hyperleda catalogs
- Altitude charts and visibility planning
- Framing preview with camera FOV
- Moon phase and separation warnings
- Mosaic planning
- Survey image overlays

### Remote Control

- Control your rig from phone or tablet
- Peer-to-peer WebRTC (no cloud required)
- Encrypted communications
- Live preview and equipment status
- Full sequence control
- QR code pairing

### Weather Integration

- Weather radar display
- Cloud motion analysis
- Safety alerts and monitoring
- Automatic sequence pausing for unsafe conditions

### OTA Updates

- Self-hosted update system
- LAN push for development
- SHA256-verified packages
- Automatic update detection

---

## Supported Equipment

### Protocols

```
+--------------------------+-------------------------+------------------+
|  ASCOM (Windows)         |  INDI (Linux/macOS)     |  Alpaca (All)    |
|  Native COM              |  Open-source            |  REST API        |
+--------------------------+-------------------------+------------------+
```

> **Note on drivers (native or otherwise)**: I have attempted to build both native drivers as well as full ASCOM/INDI/Alpaca support for as many manufacturers as I possibly could. Unfortunately, I only have one specific set of hardware to test on. While none of these drivers should be expected to be dangerous to run on other hardware, it is absolutely possible (and possibly even likely) that some native drivers may not work at all, while ASCOM/INDI/Alpaca may not work with some hardware for some reason. The attempt here was to make the code as driver agnostic as possible, but there could definitely be edge cases I simply can't test. 

### Native Camera SDKs

Direct SDK integration for maximum performance (bypasses ASCOM/INDI overhead):

| Vendor | Status |
|--------|--------|
| ZWO ASI | Supported |
| QHY | Supported |
| PlayerOne | Supported |
| SVBony | Supported |
| Atik | Supported |
| FLI | Supported |
| Moravian | Supported |
| Touptek | Supported |

### Native Mount Protocols

| Protocol | Status |
|----------|--------|
| SkyWatcher/Synta | Supported |
| iOptron | Supported |
| LX200 (Serial) | Supported |

Mounts, focusers, filter wheels, rotators, domes, and weather stations supported via ASCOM/INDI/Alpaca.

---

## Installation

### Requirements

| Platform | Requirements |
|----------|--------------|
| **Windows** | Windows 10/11 (64-bit), .NET 4.8+, [ASCOM Platform](https://ascom-standards.org/) (optional) |
| **macOS** | Ventura (13) or later, Intel or Apple Silicon |
| **Linux** | Ubuntu 22.04+, [INDI](https://indilib.org/) (optional) |

### Download

Pre-built releases will be available on the [Releases](https://github.com/Scodouglas1999/Nightshade/releases) page.

---

## Development

### Prerequisites

| Tool | Notes |
|------|-------|
| [Flutter](https://flutter.dev/) | 3.24+ |
| [Rust](https://rustup.rs/) | Latest stable (Edition 2021) |
| [Melos](https://melos.invertase.dev/) | `dart pub global activate melos` |

**Windows**: Visual Studio 2022 (C++ workload), [LLVM/Clang](https://releases.llvm.org/)
**Linux**: `build-essential`, `clang`, `cmake`, `ninja-build`, `libgtk-3-dev`, `liblzma-dev`, `libstdc++-12-dev`

### Quick Start

```bash
git clone https://github.com/Scodouglas1999/Nightshade.git
cd Nightshade

melos bootstrap          # Install deps, generate code
melos run dev            # Build Rust + Flutter, run app
```

### Commands

| Command | Description |
|---------|-------------|
| `melos run dev` | Full rebuild with FRB codegen |
| `melos run dev:quick` | Skip FRB (implementation-only changes) |
| `melos run dev:norun` | Build without running |
| `melos run dev:clean` | Clean everything and rebuild |
| `melos run test` | Run all tests |
| `melos run analyze` | Static analysis |
| `melos run format` | Format code |
| `melos run generate` | Regenerate freezed/drift/FFI bindings |

### Project Structure

```
nightshade/
├─ apps/
│  ├─ desktop/                 # Windows/macOS/Linux
│  └─ mobile/                  # iOS/Android companion app
│
├─ packages/
│  ├─ nightshade_app/          # Shared UI shell, screens, routing
│  ├─ nightshade_core/         # Business logic, database, providers, services
│  ├─ nightshade_bridge/       # Dart <-> Rust FFI bindings
│  ├─ nightshade_ui/           # Design system & shared widgets
│  ├─ nightshade_planetarium/  # GPU sky renderer
│  ├─ nightshade_plugins/      # Plugin host & API
│  ├─ nightshade_screens/      # Shared screen stubs
│  ├─ nightshade_updater/      # OTA update system
│  └─ nightshade_webrtc/       # P2P remote control
│
├─ native/nightshade_native/
│  ├─ bridge/                  # FFI entry point (cdylib)
│  ├─ sequencer/               # Behavior tree engine
│  ├─ imaging/                 # LibRaw, FITS, XISF processing
│  ├─ ascom/                   # Windows ASCOM drivers
│  ├─ indi/                    # Linux/macOS INDI
│  ├─ alpaca/                  # Cross-platform Alpaca
│  ├─ native/                  # Vendor SDK bindings (12 vendors)
│  └─ updater/                 # Standalone update binary
│
├─ tools/
│  └─ update_server/           # Local update server
│
├─ lib/                        # Third-party libs (LibRaw)
├─ scripts/                    # Build scripts
└─ docs/                       # Documentation
```

### Architecture at a Glance

```
+-----------------------------------------------------------------+
|                        Flutter UI                                |
|                    (Riverpod providers)                          |
+-----------------------------------------------------------------+
|                   flutter_rust_bridge 2.11.1                     |
+-----------------------------------------------------------------+
|     Sequencer    |    Imaging    |   ASCOM/INDI/Alpaca/Native   |
|   (behavior tree)|   (LibRaw)    |   (equipment control)        |
+-----------------------------------------------------------------+
                              Rust
```

**Database**: [Drift](https://drift.simonbinder.eu/) (SQLite) for profiles, targets, sessions, sequences, settings.

### Rust Development

```bash
cd native/nightshade_native
cargo check --all-features
cargo test --all-features
cargo clippy --all-features -- -D warnings
```

### Troubleshooting

<details>
<summary><strong>FFI codegen fails with "stdbool.h not found" (Windows)</strong></summary>

Set CPATH before running codegen:

```powershell
$env:CPATH = "C:\Program Files\LLVM\lib\clang\21\include;C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.43.34808\include;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\ucrt"
flutter_rust_bridge_codegen generate
```
</details>

<details>
<summary><strong>FFI codegen fails (Linux)</strong></summary>

Set CPATH before running codegen:

```bash
export CPATH="/usr/lib/clang/21/include"
flutter_rust_bridge_codegen generate
```
</details>

<details>
<summary><strong>Hash mismatch errors at runtime</strong></summary>

Dart bindings and Rust library are out of sync. Use `melos run dev` instead of `flutter run` after Rust changes.
</details>

<details>
<summary><strong>Need a clean rebuild?</strong></summary>

```bash
melos run dev:clean
```

See [docs/FRB_TROUBLESHOOTING.md](docs/FRB_TROUBLESHOOTING.md) for more.
</details>

---

## Contributing

Contributions are welcome:

- **Bug reports** and **feature requests** via [Issues](https://github.com/Scodouglas1999/Nightshade/issues)
- **Code contributions** via pull requests
- **Documentation** improvements
- **Testing** on different equipment setups

### Philosophy

| Principle | Meaning |
|-----------|---------|
| **Keep it simple** | Solve today's problems, not hypothetical ones |
| **Performance matters** | Large images + real-time control = optimize where it counts |
| **Cross-platform first** | Features work everywhere, degrade gracefully |
| **Test your changes** | `melos run test && melos run analyze` before PRs |

---

## Roadmap

**Current Focus**
- Core imaging workflow stability
- Equipment compatibility testing
- Sequencer reliability
- Cross-platform consistency

**Upcoming**
- Plate solving integration
- Flat wizard improvements
- Advanced mosaic planning
- Plugin system expansion
- Cloud sync

---

## License

This software is proprietary and source-available. You may view and study the code, but you may not copy, modify, distribute, or create derivative works without explicit permission.

See [LICENSE](LICENSE) for full terms.

---

## Acknowledgments

Standing on the shoulders of giants:

- [ASCOM](https://ascom-standards.org/) - Astronomy Common Object Model
- [INDI](https://indilib.org/) - Instrument Neutral Distributed Interface
- [PHD2](https://openphdguiding.org/) - Open-source autoguiding
- [Flutter](https://flutter.dev/) & [Rust](https://www.rust-lang.org/) - The foundation
- [flutter_rust_bridge](https://github.com/aspect-build/flutter_rust_bridge) - Making FFI painless
- [LibRaw](https://www.libraw.org/) - RAW image processing

---

<p align="center">
  <sub>Clear skies!</sub>
</p>