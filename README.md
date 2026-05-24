<div align="center">

<img src="assets/branding/logo-512.png" alt="Nightshade" width="128">

# Nightshade

**One application for the full imaging night—from rig bind to unattended execution.**

Cross-platform astrophotography suite for serious imagers: multi-backend equipment profiles (ASCOM COM, Alpaca REST, INDI, gated native SDK), behavior-tree sequencing with checkpoint resume, hysteresis-aware Plan Tonight scheduling, and observatory-grade remote supervision—desktop, LAN web dashboard, or mobile companion—without maintaining a parallel toolchain.

[![Latest release](https://img.shields.io/github/v/release/Scdouglas1999/Nightshade?include_prereleases&label=release)](https://github.com/Scdouglas1999/Nightshade/releases/latest)
[![CI](https://github.com/Scdouglas1999/Nightshade/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Scdouglas1999/Nightshade/actions/workflows/ci.yml?query=branch%3Amain)
![Platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20Linux%20%7C%20macOS%20%7C%20iOS%20%7C%20Android-blue)
[![License](https://img.shields.io/badge/license-source--available-orange)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-user%20guide-informational)](docs/index.md)

[Download latest release](https://github.com/Scdouglas1999/Nightshade/releases/latest) · [Documentation](docs/index.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

<br>

<img src="assets/screenshots/desktop-dashboard.png" alt="Nightshade desktop dashboard with live preview, equipment status, session controls, and weather" width="920">

*Home dashboard: live preview and capture controls, equipment connection state, guiding and weather tiles, session progress, and night-ahead actions.*

</div>

> **Beta (v2.6.0)** — Delivered on the `beta` update channel after an extended hardening pass. Plan Tonight, working plate solving, defect-map calibration without darks, the web dashboard, mobile companion, and NINA/SGP import ship in this build; stable follows a longer soak. [Report issues](https://github.com/Scdouglas1999/Nightshade/issues) with device, backend, OS, and reproducible steps.

## Contents

- [Why Nightshade](#why-nightshade)
- [Walk through a night](#walk-through-a-night)
  - [Connect your rig](#connect-your-rig)
  - [Tune profiles and optics](#tune-profiles-and-optics)
  - [Choose what to shoot](#choose-what-to-shoot)
  - [Let Plan Tonight rank targets](#let-plan-tonight-rank-targets)
  - [Frame and solve the field](#frame-and-solve-the-field)
  - [Build the night in the sequencer](#build-the-night-in-the-sequencer)
  - [Capture lights and calibration](#capture-lights-and-calibration)
  - [Keep guiding on track](#keep-guiding-on-track)
  - [Watch the sky](#watch-the-sky)
  - [Review session quality](#review-session-quality)
  - [Run flats between targets](#run-flats-between-targets)
  - [Step away with remote access](#step-away-with-remote-access)
- [Hardware support](#hardware-support)
- [Platforms](#platforms)
- [Install](#install)
- [Documentation](#documentation)
- [Build from source](#build-from-source)
- [Contributing](#contributing)
- [License](#license)

---

## Why Nightshade

### At a glance

| Pillar | Capability |
|--------|------------|
| **Unified stack** | Equipment profile, planetarium, Plan Tonight, sequencer, imaging, guiding, weather, analytics, and remote surfaces share one session model—no hand-off between capture, planning, and monitoring apps. |
| **Capture & automation** | Behavior-tree sequencer: instruction nodes, parallel triggers (HFR, guiding, time), recovery branches, and checkpoint resume for meridian flips, autofocus, dithering, and filter changes. |
| **Planning & solving** | Plan Tonight scores altitude, moon separation, and horizon; scheduler re-evaluates with hysteresis when conditions shift. Plate solve via ASTAP or astrometry.net (verified at setup)—not placeholder coordinates. |
| **Safety & remote** | Radar, cloud-motion cues, and sequence-integrated alerts can pause or park before weather compromises the run. Browser dashboard and iOS/Android companion (QR pairing) supervise the same session on the observatory PC. |
| **Migration & calibration** | Defect-map buckets from a short dark stack repair hot pixels at capture time. NINA and SGP import with mapping preview; unsupported steps surface explicitly. Guided equipment wizard from driver choice through optical train and save path. |

Compared with a typical night built from separate capture, sequence, planetarium, and remote tools—each with its own profiles and failure semantics—Nightshade keeps connect, plan, execute, and supervise in one suite.

> **Technical foundation** — Flutter UI and Dart business logic in `packages/` and `apps/`; device control, sequencing, and imaging in Rust (`native/nightshade_native/`), exposed through ASCOM COM, Alpaca REST, INDI, and vendor SDK paths where gated for the platform.

---

## Walk through a night

End-to-end flow for a clear night on **Nightshade 2.6.0 (Windows)** ([latest release](https://github.com/Scdouglas1999/Nightshade/releases/latest)). Each subsection is one screen, one responsibility—prose describes preconditions, actions, and outcomes; captions label the figure.

### Connect your rig

**Precondition:** Drivers installed for your backends (ASCOM Platform on Windows for COM, Alpaca endpoint, INDI server, or gated native SDK).

**Action:** Discover cameras, mounts, focusers, and wheels; assign roles; confirm connection health; save the equipment profile.

**Outcome:** Every downstream screen—planetarium, sequencer, imaging—addresses the same rig. Connection loss is diagnosed here, not across multiple applications.

![Equipment discovery and profile management](assets/screenshots/equipment.png)

*Figure 1 — Equipment: discovery, driver selection, per-device connection state for the active profile.*

### Tune profiles and optics

Once the profile is saved, open **Equipment profiles** when focal length, plate scale, or device roles change—reducer swap, new camera, or solver parameter update.

**Outcome:** Framing, plate solving, and the sequencer inherit consistent optics defaults; offset and scale errors are caught before the first science exposure.

![Equipment profile and optical configuration](assets/screenshots/settings-equipment-profiles.png)

*Figure 2 — Equipment profiles: optics, device roles, and solver-related defaults.*

### Choose what to shoot

With optics locked, use the planetarium to pan the sky, search catalogs, and inspect tonight’s visibility before committing integration time.

**Outcome:** Selected fields feed Plan Tonight or drop directly into the sequencer—no re-entry of coordinates in a second tool.

![GPU-rendered interactive sky map with tonight panel](assets/screenshots/planetarium.png)

*Figure 3 — Planetarium: GPU sky map, object search, tonight visibility panel.*

### Let Plan Tonight rank targets

Hand candidates to **Plan Tonight**; the engine scores altitude, moon separation, and horizon limits and charts viable windows through the night.

**Outcome:** Target order follows observability data, not a static dusk list; the scheduler can re-rank when weather or guiding quality shifts.

![Plan Tonight target recommendations and altitude chart](assets/screenshots/plan-tonight.png)

*Figure 4 — Plan Tonight: scored target list and altitude chart for the remaining night.*

### Frame and solve the field

For each selected target, align composition with plate solving and a reference overlay (DSS or similar) so rotation and offset match the plan.

**Outcome:** Fewer iterative slews when centering faint objects or registering mosaic panes.

![Framing assistant with plate-solved overlay on M42](assets/screenshots/framing.png)

*Figure 5 — Framing: plate-solved overlay and reference image for rotation and offset.*

### Build the night in the sequencer

Translate the plan into an unattended run: expose, slew, filter changes, meridian flips, and parallel triggers on one behavior-tree canvas.

**Outcome:** Recovery branches and checkpoint resume isolate failures—a single bad step does not discard the remainder of the run.

![Behavior-tree sequence builder](assets/screenshots/sequencer.png)

*Figure 6 — Sequencer: instructions, triggers, and recovery branches on one canvas.*

### Capture lights and calibration

Execute the tree from the imaging workspace: exposure controls, live histogram, and frame metadata in one view.

**Outcome:** Defect-map calibration at capture time repairs hot pixels via bucket maps—without maintaining temperature-matched dark libraries for every session.

![Imaging screen with capture controls and histogram](assets/screenshots/imaging.png)

*Figure 7 — Imaging: capture controls, histogram, frame metadata.*

### Keep guiding on track

Operate **PHD2** inside Nightshade—star profile, guiding RMS, dither settings—while sequencer triggers watch tracking quality.

**Outcome:** Capture can pause on guiding degradation before trailed frames accumulate in the session stack.

![PHD2 guiding integration with RMS graphs](assets/screenshots/guiding.png)

*Figure 8 — Guiding: PHD2 star profile, RMS trends, dither controls.*

### Watch the sky

Alongside observatory conditions, monitor radar and cloud-motion signals when deciding to pause, park, or let automation continue.

**Outcome:** Plan Tonight and the sequencer can incorporate weather into decisions—the operator is not the sole watcher when a front approaches.

![Weather radar and cloud monitoring](assets/screenshots/weather.png)

*Figure 9 — Weather: radar, cloud cues, safety-oriented conditions.*

### Review session quality

During or after capture, inspect frame quality, HFR trends, and guiding performance in a single analytics view.

**Outcome:** Seeing softening or autofocus drift is visible without opening FITS headers file by file.

![Session analytics with HFR and guiding trends](assets/screenshots/analytics.png)

*Figure 10 — Analytics: frame quality, HFR, and guiding trends for the session.*

### Run flats between targets

When the sequencer requests calibration—or a manual flat series is needed before meridian—the flat wizard produces filter-aware panels with ADU targeting.

**Outcome:** Flats land in the intended brightness range per filter, ready for stacking pipelines.

![Flat frame wizard with ADU targeting](assets/screenshots/flat-wizard.png)

*Figure 11 — Flat wizard: filter-aware panels, ADU targeting.*

### Step away with remote access

Leave the observatory PC running headless or on the LAN; open the browser dashboard for session status, preview, and core actions from inside the house or on a tablet.

**Outcome:** Remote supervision without a second software stack on the pier; return to desktop equipment profiles when optics or device roles require editing at the keyboard.

![Browser remote dashboard for headless control](assets/screenshots/web-dashboard.png)

*Figure 12 — Web dashboard: session status and core actions via browser on the LAN.*

Screenshot refresh notes: [`assets/README.md`](assets/README.md).

---

## Hardware support

Nightshade connects to rigs through four driver backends. **Availability** means discovery and connection are implemented on that OS; individual devices may expose narrower capability sets after connect.

| Backend | Windows | Linux | macOS |
|---------|:-------:|:-----:|:-----:|
| ASCOM COM | ✓ | — | — |
| ASCOM Alpaca | ✓ | ✓ | ✓ |
| INDI | ✓ | ✓ | ✓ |
| Native SDK | Gated | Gated | Gated |

- **ASCOM COM** — Locally installed ASCOM Platform and device drivers (Windows only).
- **ASCOM Alpaca** — Network REST; any Alpaca server or ASCOM Alpaca bridge.
- **INDI** — Reachable INDI server; feature depth follows the INDI driver.
- **Native SDK** — Direct vendor libraries where bundled and verified for OS/CPU; otherwise use ASCOM, Alpaca, or INDI.

**Native cameras (SDK):** ZWO ASI, QHY, Player One, SVBony, Atik, FLI, Moravian, Touptek family (Touptek, Altair, Mallincam, OGMA).

**Native mounts (SDK):** SkyWatcher/Synta, iOptron, LX200 (serial).

Focusers, filter wheels, rotators, domes, weather, and safety devices use ASCOM, Alpaca, or INDI unless a native path is explicitly verified for your release. Full backend × category matrix: [Supported hardware by platform](docs/supported-hardware-by-platform.md).

---

## Platforms

| Surface | Windows | Linux | macOS | iOS / Android |
|---------|---------|-------|-------|---------------|
| Desktop app | Tested | Early testing | Untested | — |
| Headless server + API | Tested | Early testing | Untested | — |
| Web dashboard | ✓ | ✓ | ✓ | ✓ |
| Mobile companion | — | — | — | ✓ |

**Desktop and headless** — Windows is the primary beta path (installer, OTA, field use). Linux builds compile and run on CI; hardware and packaging feedback is welcome. macOS builds in CI; no signed beta artifact and no dedicated hardware soak for this release.

**Web dashboard** — Browser UI against a running desktop or headless host on your LAN (REST + WebSocket). Not a standalone cloud service.

**Mobile companion** — iOS and Android pair to the desktop host via QR; monitoring and light control, not a full capture replacement. Android ships as a debug-signed beta APK; iOS requires building from source (see Install).

---

## Install

Download from the **[latest release](https://github.com/Scdouglas1999/Nightshade/releases/latest)** (channel **beta**, version **2.6.0**). Confirm artifact names in the release notes before installing.

| Platform | Artifact |
|----------|----------|
| Windows installer | `NightshadeSetup-2.6.0.exe` |
| Windows OTA | `nightshade-2.6.0-windows-x64.zip` + `manifest.json` |
| Linux | `nightshade-2.6.0-linux-x64.tar.gz` |
| Android (companion) | `nightshade-2.6.0-android.apk` (debug-signed for beta) |
| iOS (companion) | Build from source |
| macOS desktop | Not shipped for v2.6.0 beta |

### Requirements

**Windows** — Windows 10 or 11 (64-bit); 8 GB RAM minimum (16 GB recommended); DirectX 11 GPU with 2 GB VRAM; ~500 MB for the app plus image storage. [.NET Framework 4.8+](https://dotnet.microsoft.com/download/dotnet-framework) and [ASCOM Platform](https://ascom-standards.org/) optional but required for local COM drivers.

**Linux** — Ubuntu 22.04 LTS or equivalent; same CPU/RAM guidance as Windows; OpenGL 3.3 GPU. Runtime needs `libgtk-3`, `libsecret-1`, and a current glibc. INDI equipment requires a reachable INDI server (`indi-full` or distro packages). Native USB/SDK paths may need vendor `udev` rules and group membership (`dialout`, `plugdev`, `video` as applicable).

**macOS / iOS** — See release notes for artifacts attached to the tag; do not assume a `.dmg` or TestFlight build from this table alone.

### Next steps

- [Installation guide](docs/getting-started/installation.md) — extract/install, ASCOM and INDI setup, verify launch, updates.
- [First connection](docs/getting-started/first-connection.md) — equipment profile, protocol choice, first camera/mount connect.

---

## Documentation

| Resource | What you'll find |
|----------|------------------|
| [**User documentation**](docs/index.md) | Installation, first connection, feature guides, troubleshooting, and API references |
| [**Supported hardware**](docs/supported-hardware-by-platform.md) | Driver backends (ASCOM, Alpaca, INDI, native SDK) and platform coverage |
| [**Known limitations**](docs/known-limitations.md) | Release-scope caveats, unsupported paths, and beta expectations |
| [**Headless / remote setup**](docs/headless-secure-setup.md) | Token auth, firewall ports, LAN web dashboard, and OpenAPI self-test |
| [**FFI troubleshooting**](docs/FRB_TROUBLESHOOTING.md) | `flutter_rust_bridge` codegen failures, `CPATH` / header paths, and hash mismatches |
| [**Changelog**](CHANGELOG.md) | Version history and release notes |

For a guided first run after install, see [Installation](docs/getting-started/installation.md) and [First connection](docs/getting-started/first-connection.md).

---

## Build from source

Nightshade is a **Melos** monorepo: Flutter/Dart UI and business logic in `packages/` and `apps/`, device control and sequencing in `native/nightshade_native/` (Rust), connected through **flutter_rust_bridge**.

### Requirements

| Tool | Version / notes |
|------|-----------------|
| [Flutter](https://flutter.dev/) | 3.35+ recommended (CI release builds use 3.35.5; analyzer CI uses 3.24+) |
| [Rust](https://rustup.rs/) | Stable toolchain, 2021 edition |
| [Melos](https://melos.invertase.dev/) | `dart pub global activate melos` |
| Git | Submodules not required for a standard clone |

### Quick start

From the repository root:

```bash
git clone https://github.com/Scdouglas1999/Nightshade.git
cd Nightshade
dart pub global activate melos
melos bootstrap
melos run dev
```

| Command | When to use it |
|---------|----------------|
| `melos run dev` | Full cycle: FRB codegen, Rust build, copy native libs, run desktop app (**Windows**; uses `scripts/dev.ps1`) |
| `melos run dev:quick` | Rust/Dart implementation changed, **FFI API unchanged** (skips FRB regen) |
| `melos run dev:norun` | Rebuild native bridge and bindings without launching Flutter |
| `melos run dev:clean` | Clean artifacts and rebuild from scratch |
| `melos run generate` | Regenerate freezed, drift, json_serializable, and FRB bindings after model/API edits |
| `melos run build:desktop:windows` | Release desktop build (also `build:desktop:linux`, `build:desktop:macos`) |
| `melos run test` | Flutter tests across packages |
| `melos run analyze` | `dart analyze` in all packages |

**Important:** After changing Rust FFI surfaces, do not rely on plain `flutter run` alone—Dart bindings and the native library must stay in sync. Use `melos run dev` on Windows, or run `flutter_rust_bridge_codegen generate`, `scripts/build_native.sh` (Linux/macOS), copy the built library into the app output, then `flutter run`. See [FFI troubleshooting](docs/FRB_TROUBLESHOOTING.md).

On **Linux/macOS**, install hooks once: `./scripts/install-hooks.sh`. On **Windows**: `.\scripts\install-hooks.ps1`.

### Build dependencies by OS

| OS | Install before `melos bootstrap` |
|----|----------------------------------|
| **Windows** | Visual Studio 2022 with **Desktop development with C++**; LLVM/Clang on `PATH` (for FRB/ffigen); optional [ASCOM Platform](https://ascom-standards.org/) for local COM drivers |
| **Linux** | `build-essential` `clang` `cmake` `ninja-build` `pkg-config` `libgtk-3-dev` `libsecret-1-dev` `libjsoncpp-dev`; vendor udev rules for native USB cameras where applicable |
| **macOS** | Xcode Command Line Tools; code signing for device builds |

Contributor layout, quality gates, and where to place changes: [CLAUDE.md](CLAUDE.md) (architecture) and [CONTRIBUTING.md](CONTRIBUTING.md) (workflow and CI).

```mermaid
flowchart TB
 subgraph clients["Clients"]
 Desktop["Desktop app"]
 Mobile["iOS / Android companion"]
 Web["Web dashboard"]
 end

 subgraph dart["Dart / Flutter monorepo"]
 App["nightshade_app / apps"]
 Core["nightshade_core"]
 Bridge["nightshade_bridge · FFI"]
 App --> Core
 Core --> Bridge
 end

 subgraph rust["Rust · native/nightshade_native"]
 API["bridge API · EventBus"]
 Seq["sequencer · behavior trees"]
 Img["imaging · FITS / raw"]
 Drv["ASCOM · INDI · Alpaca · vendor SDKs"]
 API --> Seq
 API --> Img
 API --> Drv
 end

 Desktop --> App
 Mobile --> App
 Web --> Core
 Bridge --> API
```

---

## Contributing

Nightshade is in active beta; reproducible reports and focused PRs accelerate hardening.

**Bug reports** — use the [bug report template](https://github.com/Scdouglas1999/Nightshade/issues/new?template=bug_report.yml). Include **device model**, **driver backend** (ASCOM COM, Alpaca, INDI, native SDK), **OS and version**, Nightshade **version/channel**, and **steps to reproduce** (logs or a short screen recording when possible).

**Code and docs** — read [CONTRIBUTING.md](CONTRIBUTING.md) for bootstrap, pre-commit hooks, CI gates (`melos run analyze`, `melos run audit:placeholders`, Rust `clippy` / tests), and house rules (no stubs, fail-closed errors, regenerate committed codegen in dedicated commits). Substantial features should start with a [feature request](https://github.com/Scdouglas1999/Nightshade/issues/new?template=feature_request.yml) or issue for design alignment.

**Security** — do **not** file public issues for vulnerabilities. Follow [SECURITY.md](SECURITY.md) for private reporting, supported release channels, and scope (trusted LAN vs internet-exposed headless API).

---

## License

Nightshade is **source-available**, not open source. You may use official releases for imaging work, view and study this repository, and build private modifications for equipment you own. Redistribution, sublicensing, and publishing derivative works require **explicit written permission** from the copyright holder. See [LICENSE](LICENSE) for the full terms (Version 1.2).

---

## Acknowledgments

Nightshade integrates with and depends on community standards and open libraries, including:

- **[ASCOM](https://ascom-standards.org/)** and **ASCOM Alpaca** — Windows COM and cross-platform REST device access
- **[INDI](https://indilib.org/)** — Linux/macOS/Windows INDI client protocol
- **[PHD2](https://openphdguiding.org/)** — autoguiding integration
- **[Flutter](https://flutter.dev/)** / **Dart** — cross-platform UI
- **[Rust](https://www.rust-lang.org/)** — native bridge, sequencer, drivers, and imaging
- **[flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/)** — Dart ↔ Rust FFI
- **[LibRaw](https://www.libraw.org/)** — camera RAW decoding

Clear skies.
