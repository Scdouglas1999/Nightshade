<p align="center">
  <!-- TODO: Add logo here -->
  <h1 align="center">Nightshade</h1>
  <p align="center">
    <strong>A modern, cross-platform astrophotography suite</strong>
  </p>
  <p align="center">
    <img src="https://img.shields.io/badge/status-early%20alpha-orange" alt="Status: Early Alpha">
    <img src="https://img.shields.io/badge/platforms-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20iOS%20%7C%20Android-blue" alt="Platforms">
    <img src="https://img.shields.io/badge/built%20with-Flutter%20%2B%20Rust-blue" alt="Built with Flutter + Rust">
  </p>
</p>

<!-- TODO: Add hero screenshot showing main imaging interface -->

Nightshade is a complete imaging platform for astrophotographers, combining camera control, mount automation, focusing, guiding, and sequence planning in a single unified application. Built with Flutter and Rust for performance and reliability across desktop and mobile.

> **Early Alpha**: Core features work but expect rough edges, breaking changes, and incomplete documentation. Not recommended for critical imaging sessions yet—but we'd love your help testing!

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
- FITS/TIFF with customizable naming
- Filter wheel integration
- Dithering via PHD2

</td>
<td width="50%" valign="top">

### Mount Control

<!-- TODO: Screenshot of mount control panel -->

- Directional slewing (guide → slew speeds)
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

</td>
<td width="50%" valign="top">

### Guiding

- PHD2 integration
- Real-time RA/Dec error graph
- Dithering with settle detection
- Guiding alerts and monitoring

</td>
</tr>
</table>

### Sequencer

<!-- TODO: Screenshot of sequence builder -->

The sequencer uses a **behavior tree architecture** for building complex automated workflows:

| Node Type | Examples |
|-----------|----------|
| **Instruction** | Expose, slew, autofocus, filter change, cool camera, park/unpark, wait |
| **Logic** | Loop, parallel execution, conditionals, sequence grouping |
| **Trigger** | HFR monitor, guiding monitor, weather safety, time triggers, meridian flip |

Build anything from simple single-target sequences to multi-target nights with automatic meridian flips, weather safety, and adaptive refocusing.

### Planetarium

<!-- TODO: Screenshot of planetarium view -->

- GPU-accelerated interactive sky map
- Messier, NGC, IC, Caldwell catalogs
- Altitude charts and visibility planning
- Framing preview with camera FOV
- Moon phase and separation warnings

### Remote Control

- Control your rig from phone or tablet
- Peer-to-peer WebRTC (no cloud required)
- Live preview and equipment status
- Full sequence control

---

## Supported Equipment

### Protocols

```
┌──────────────────────────────────────────────────────────────┐
│  ASCOM (Windows)  │  INDI (Linux/macOS)  │  Alpaca (All)    │
│  Native COM       │  Open-source         │  REST API        │
└──────────────────────────────────────────────────────────────┘
```

### Native Camera SDKs

<table>
<tr>
<td>ZWO ASI</td>
<td>QHY</td>
<td>PlayerOne</td>
<td>Atik</td>
<td>FLI</td>
</tr>
<tr>
<td>Moravian</td>
<td>SBIG</td>
<td>SVBony</td>
<td>Touptek</td>
<td><em>more coming</em></td>
</tr>
</table>

Mounts, focusers, filter wheels, rotators, and weather stations supported via ASCOM/INDI/Alpaca.

---

## Installation

### Requirements

| Platform | Requirements |
|----------|--------------|
| **Windows** | Windows 10/11 (64-bit), .NET 4.8+, [ASCOM Platform](https://ascom-standards.org/) (optional) |
| **macOS** | Ventura (13) or later, Intel or Apple Silicon |
| **Linux** | Ubuntu 22.04+, [INDI](https://indilib.org/) (optional) |

### Download

Pre-built releases will be available on the [Releases](https://github.com/Scdouglas1999/nightshade/releases) page once we hit beta.

---

## Development

### Prerequisites

| Tool | Notes |
|------|-------|
| [Flutter](https://flutter.dev/) | 3.0+ |
| [Rust](https://rustup.rs/) | Latest stable |
| [Melos](https://melos.invertase.dev/) | `dart pub global activate melos` |

**Windows**: Visual Studio 2022 (C++ workload), [LLVM/Clang](https://releases.llvm.org/)
**Linux**: `build-essential`, `libgtk-3-dev`, `liblzma-dev`, `libstdc++-12-dev`

### Quick Start

```bash
git clone https://github.com/Scdouglas1999/nightshade.git
cd nightshade

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
│  └─ mobile/                  # iOS/Android
│
├─ packages/
│  ├─ nightshade_core/         # Business logic, database, providers
│  ├─ nightshade_bridge/       # Dart ↔ Rust FFI bindings
│  ├─ nightshade_ui/           # Design system
│  ├─ nightshade_planetarium/  # GPU sky renderer
│  └─ ...                      # app, plugins, screens, updater, webrtc
│
├─ native/nightshade_native/
│  ├─ sequencer/               # Behavior tree engine
│  ├─ imaging/                 # LibRaw, FITS processing
│  ├─ ascom/                   # Windows ASCOM drivers
│  ├─ indi/                    # Linux/macOS INDI
│  ├─ alpaca/                  # Cross-platform Alpaca
│  └─ native/                  # Vendor SDK bindings
│
├─ lib/                        # Third-party libs (LibRaw)
├─ scripts/                    # Build scripts
└─ docs/                       # Documentation
```

### Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter UI                                │
│                    (Riverpod providers)                          │
├─────────────────────────────────────────────────────────────────┤
│                   flutter_rust_bridge                            │
├─────────────────────────────────────────────────────────────────┤
│     Sequencer    │    Imaging    │   ASCOM/INDI/Alpaca          │
│   (behavior tree)│   (LibRaw)    │   (equipment control)        │
└─────────────────────────────────────────────────────────────────┘
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

Nightshade is early alpha—there's plenty to do:

- **Bug reports** and **feature requests** via [Issues](https://github.com/Scdouglas1999/nightshade/issues)
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

**Alpha** (current)
- Core imaging workflow stability
- Equipment compatibility testing
- Sequencer reliability

**Beta** (upcoming)
- Plate solving integration
- Flat wizard
- Mosaic planning
- Plugin system
- Cloud sync

---

## License

<!-- TODO: Choose and add license -->

License TBD. See [LICENSE](LICENSE) for details.

---

## Acknowledgments

Standing on the shoulders of giants:

- [ASCOM](https://ascom-standards.org/) — Astronomy Common Object Model
- [INDI](https://indilib.org/) — Instrument Neutral Distributed Interface
- [PHD2](https://openphdguiding.org/) — Open-source autoguiding
- [Flutter](https://flutter.dev/) & [Rust](https://www.rust-lang.org/) — The foundation
- [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge) — Making FFI painless
- [LibRaw](https://www.libraw.org/) — RAW image processing

---

<p align="center">
  <sub>Clear skies! ✨</sub>
</p>
