<div align="center">

<img src="assets/branding/logo-512.png" width="128" alt="Nightshade logo">

# Nightshade

### One observatory. One control room. The whole night.

Plan targets, frame the sky, automate capture, guide, monitor weather, and review every session from one desktop application.

[![Latest release](https://img.shields.io/github/v/release/Scdouglas1999/Nightshade?label=latest&color=2ea44f)](https://github.com/Scdouglas1999/Nightshade/releases/latest)
[![Public beta](https://img.shields.io/badge/status-public_beta-f59e0b)](#beta-status)
[![Platforms](https://img.shields.io/badge/desktop-Windows_%7C_Linux_%7C_macOS-2563eb)](#platforms)
[![Companion](https://img.shields.io/badge/companion-Android_%7C_iOS-7c3aed)](#remote-observatory)
[![License](https://img.shields.io/badge/license-source_available-64748b)](LICENSE)

[**Download Nightshade**](https://github.com/Scdouglas1999/Nightshade/releases/latest) · [Documentation](docs/index.md) · [What's new in 5.0](docs/release/v5.0.0.md) · [Support development](https://www.patreon.com/cw/SeanDouglas)

<img src="assets/screenshots/desktop-dashboard.png?v=20260721" width="920" alt="Nightshade control room dashboard showing simulator camera frames and live PHD2 guiding telemetry">

</div>

---

Nightshade replaces the patchwork of apps that usually runs an astrophotography rig. Equipment, planetarium, framing, sequencing, imaging, guiding, weather, safety, and analytics all work from the same target, equipment profile, and live session.

Choose a target once. Nightshade carries its coordinates, framing, rotation, optics, constraints, and capture plan through the rest of the night. The Rust automation core continues operating when a control surface disconnects; the Flutter desktop app, LAN dashboard, and mobile companion reconnect to the same authoritative run.

> [!IMPORTANT]
> Nightshade is a **public beta**. Windows with ASCOM/Alpaca is the primary hardware-tested path. Supervise complete sessions on your exact rig—including slew, focus, guide, capture, meridian flip, safing, and park—before relying on unattended operation. See [beta status](#beta-status), [supported hardware](docs/supported-hardware-by-platform.md), and [known limitations](docs/known-limitations.md).

## Built for the entire imaging night

<table>
<tr>
<td width="50%">
<h3>Plan with the real sky</h3>
<p>Explore the planetarium, score targets against altitude, Moon, horizon, and darkness constraints, then compose exact framing and mosaics over survey imagery.</p>
</td>
<td width="50%">
<h3>Run with confidence</h3>
<p>Build visual sequences with capture, focus, guiding, calibration, meridian-flip, weather, and recovery logic. Checkpoints and structured decisions make the run observable and recoverable.</p>
</td>
</tr>
<tr>
<td>
<h3>Control the whole rig</h3>
<p>Manage cameras, mounts, focusers, filter wheels, rotators, domes, covers, switches, weather stations, and safety monitors through ASCOM, Alpaca, INDI, and capability-gated native drivers.</p>
</td>
<td>
<h3>Know what happened</h3>
<p>Follow frame quality, HFR, FWHM, eccentricity, guiding RMS, integration, rejection, and session history. Replay decisions instead of guessing why automation changed course.</p>
</td>
</tr>
</table>

<div align="center">
<img src="assets/screenshots/equipment.png?v=20260721" width="920" alt="Nightshade equipment workspace with a nine-device simulated observatory connected">
</div>

<div align="center">
<img src="assets/screenshots/sequencer.png?v=20260721" width="430" alt="Nightshade visual sequencer with an eleven-node NGC 7380 LRGB capture plan">
<img src="assets/screenshots/imaging.png?v=20260721" width="430" alt="Nightshade imaging workspace showing a captured simulator frame and live frame analysis">
</div>

## From target to finished session

<table>
<tr>
<td width="50%"><img src="assets/screenshots/planetarium.png?v=20260721" alt="Nightshade planetarium with the current sky and tonight's darkness window"></td>
<td width="50%"><img src="assets/screenshots/plan-tonight.png?v=20260721" alt="Plan Tonight recommendation for NGC 7380 with its altitude forecast"></td>
</tr>
<tr>
<td><strong>Explore.</strong> Navigate a GPU-rendered sky, inspect objects, overlay the active optical train, and switch to red night vision at the pier.</td>
<td><strong>Decide.</strong> Compare scheduler-ranked targets using the same constraints the automation engine will enforce.</td>
</tr>
<tr>
<td><img src="assets/screenshots/framing.png?v=20260721" alt="Nightshade framing assistant showing NGC 7380 in DSS2 survey imagery with a four-panel mosaic"></td>
<td><img src="assets/screenshots/guiding.png?v=20260721" alt="Nightshade guiding workspace with a live guide-star image and stochastic PHD2 telemetry"></td>
</tr>
<tr>
<td><strong>Compose.</strong> Plate-solve, center, rotate, and design mosaics against registered survey imagery before spending clear-sky time.</td>
<td><strong>Track.</strong> Operate PHD2 from the same workspace, watch RA/Dec error and RMS, and let capture wait for dither settling.</td>
</tr>
<tr>
<td><img src="assets/screenshots/weather.png?v=20260721" alt="Nightshade weather workspace displaying current GOES satellite cloud data"></td>
<td><img src="assets/screenshots/analytics.png?v=20260721" alt="Nightshade session analytics populated by three simulator exposures and live guiding"></td>
</tr>
<tr>
<td><strong>Protect.</strong> Combine weather, safety-monitor, twilight, Sun altitude, and disk conditions into one host-authoritative safety verdict.</td>
<td><strong>Learn.</strong> Review quality trends, integration, rejected subs, science workflows, and the sequence of decisions from the night.</td>
</tr>
</table>

## Automation that explains itself

- **One scheduler:** Plan Tonight and Unattended Autopilot use the same target scoring, horizon, darkness, safety, focus, and calibration contracts.
- **Resilient sequences:** retries, checkpoint recovery, guide-star reacquisition, meridian flips, dithering, autofocus, and calibration are part of the run—not separate scripts.
- **Fail-closed safety:** unknown or stale safety state is not treated as clear. Unsafe weather, critical disk space, or an emergency stop can pause capture and drive the rig toward park, dome, and cover safety.
- **Structured history:** automation decisions and recovery actions are emitted as events and persisted for session replay.
- **Honest ownership:** the native sequencer owns an active run; desktop, mobile, and browser surfaces observe and control that same session instead of creating competing copies.

<div align="center">
<img src="assets/screenshots/flat-wizard.png?v=20260721" width="700" alt="Nightshade flat wizard calibrating exposure from measured simulator ADU samples">
</div>

The Flat Wizard measures ADU, converges on the correct exposure, and tracks filter-by-filter calibration using the active camera gain, offset, binning, and optical train.

## Remote observatory

Nightshade can run as a desktop application or as a headless host at the telescope. Pair a companion over your LAN and keep the hardware authority where the equipment lives.

| Surface | Best for | Capability |
|---|---|---|
| **Desktop app** | Setup, planning, sequencing, imaging, and analysis | Full control surface |
| **Headless host** | A dedicated observatory computer or appliance | Native automation core plus authenticated API |
| **Web dashboard** | Fast access from any modern LAN browser | Live status and observatory control |
| **Mobile companion** | Checking or intervening away from the control desk | Pairing, monitoring, notifications, and light control |
| **Second desktop** | A full-size remote control room | Live master/slave session mirroring |

<div align="center">
<img src="assets/screenshots/web-dashboard.png?v=20260721" width="760" alt="Nightshade browser dashboard for remote observatory control">
</div>

The headless API defaults to fail-closed authentication on current development builds. Pairing and discovery remain available for onboarding; privileged actions require the appropriate view, control, or admin authority. Read the [secure headless setup guide](docs/headless-secure-setup.md) before exposing a host beyond loopback.

## Living Sky

Nightshade 5.0 extends a night's workflow beyond capture:

- **Your Sky** builds a personal atlas from completed sessions.
- **First Light** helps review transient candidates and prepare TNS, AAVSO, or MPC output.
- **Constellation** supports opt-in contribution through a self-hosted hub.
- **Science workflows** add photometric calibration, period analysis, transient reporting, and science-oriented exports.
- **S3-compatible backup** supports AWS S3, MinIO, and Backblaze B2 alongside WebDAV, with credentials stored in the operating-system keyring.

Read the complete [5.0 release notes](docs/release/v5.0.0.md) and [verification evidence](docs/release-evidence/5.0.0.md).

## Next: Nightshade 6

The current development branch is building **Make It Real / Collaborative Sky**, the next major release. It is visible in the source and current app development builds, but it is **not part of the latest 5.0 download**.

- Deeper unattended reliability: a dedicated Windows ASCOM STA worker, bounded headless shutdown, startup auto-connect, disk watchdog enforcement, and clearer sequencer teardown states.
- Signed update foundations: Ed25519 verification, anti-rollback, key rotation, and revocation support. Production signing and update infrastructure remain release-owner gated.
- Collaborative Sky for self-hosted clubs and multi-rig sites: shared calibration libraries, distributed mosaic panel claims, live co-imaging, consent, and provenance.
- Expanded remote control: fine-grained resource/action scopes, broader mobile host switching and reconnect behavior, and bearer-safe browser image delivery.

See the [Nightshade 6 development overview](docs/releases/v6.0.0-README.md) for the current implementation status and explicit limitations.

## Hardware support

Nightshade uses several device backends. A backend being present does not guarantee every vendor capability on every operating system.

| Backend | Windows | Linux | macOS | Notes |
|---|:---:|:---:|:---:|---|
| **ASCOM COM** | ✓ | — | — | Primary Windows path; requires ASCOM Platform and installed drivers |
| **ASCOM Alpaca** | ✓ | ✓ | ✓ | Network devices and bridges; capabilities depend on the server |
| **INDI** | ✓ | ✓ | ✓ | Requires a reachable INDI server; driver depth varies |
| **Native SDK** | Gated | Gated | Gated | Requires compatible user-installed vendor libraries and drivers |

Native camera paths exist for ZWO ASI, QHY, Player One, SVBony, Atik, FLI, Moravian, and the Touptek family. Native mount paths include SkyWatcher/Synta, iOptron, and LX200 serial. Official packages do not redistribute proprietary vendor SDK binaries.

Check the [platform and hardware matrix](docs/supported-hardware-by-platform.md) before building a profile.

## Platforms

| Product | Windows | Linux | macOS | Android | iOS |
|---|:---:|:---:|:---:|:---:|:---:|
| Desktop control room | Primary | Early testing | Builds from source | — | — |
| Headless host | Tested path | Early testing | Builds from source | — | — |
| Web dashboard | ✓ | ✓ | ✓ | Browser | Browser |
| Mobile companion | — | — | — | APK | Build from source |

## Install

Download the current release from **[GitHub Releases](https://github.com/Scdouglas1999/Nightshade/releases/latest)**.

| Platform | Current 5.0 artifact | Status |
|---|---|---|
| Windows x64 | `nightshade-5.0.0-windows-x64.zip` | Unsigned portable beta |
| Linux x64 | `nightshade-5.0.0-linux-x64.tar.gz` | Portable bundle; early testing |
| Android | `nightshade-5.0.0-android-universal.apk` | Debug-signed sideload companion beta |
| macOS / iOS | No published artifact | Build from source |

Each released archive has a matching SHA-256 file. Follow the [installation guide](docs/getting-started/installation.md), then [connect your first device](docs/getting-started/first-connection.md).

> [!NOTE]
> Nightshade 5.0 updates are manual. Back up your configuration and database, verify the new artifact, and retain the previous portable folder until migration and equipment profiles have been checked.

### System requirements

- **Windows:** Windows 10/11 x64, 8 GB RAM minimum (16 GB recommended), DirectX 11 GPU with 2 GB VRAM, and ASCOM Platform when using local ASCOM COM devices.
- **Linux:** x86-64 with glibc 2.35+, GTK 3, libsecret, libusb, libudev, OpenSSL, and an OpenGL 3.3-capable GPU.
- **Storage:** approximately 500 MB for Nightshade plus catalogs, previews, captured frames, and calibration data.

## Beta status

Nightshade is software for physical equipment, and support claims follow evidence rather than the presence of a code path.

**Recommended beta configuration:** Windows 10/11, ASCOM/Alpaca drivers, a supported camera, mount, focuser, filter wheel, and PHD2. Windows desktop control and supervised acquisition are the most exercised paths.

**Use extra supervision:** headless unattended acquisition, Linux, macOS, native SDK devices, new Living Sky automation, and development-only Nightshade 6 features. Linux remains early testing; macOS builds in CI but has no signed release artifact or hardware soak.

Before leaving a rig unattended, validate a complete night on your exact hardware and confirm that failure cases end safely. Useful reports include the operating system, backend, exact equipment, driver versions, sequence step, logs, and the behavior you observed.

## Build from source

Nightshade is a Melos-managed Flutter workspace over a Rust core, connected by `flutter_rust_bridge`. Use the project scripts so generated bindings and native libraries stay synchronized.

```bash
dart pub global activate melos
melos bootstrap
melos run dev
```

Common workflows:

| Command | Purpose |
|---|---|
| `melos run dev` | Generate the FFI bridge, build Rust, stage native libraries, and launch desktop |
| `melos run dev:quick` | Rebuild without regenerating an unchanged FFI surface |
| `melos run generate` | Regenerate Drift, Freezed, JSON, and bridge code |
| `melos run test` | Run workspace tests |
| `melos run analyze` | Run static analysis |
| `melos run build:desktop:windows` | Build the Windows desktop release |
| `melos run build:desktop:linux` | Build the Linux desktop release |

The CI toolchain is pinned to Flutter 3.44.1 / Dart 3.12 and Rust stable. Platform prerequisites and troubleshooting are in the [developer documentation](docs/index.md) and [FFI guide](docs/FRB_TROUBLESHOOTING.md).

## Documentation

| Start here | Operate Nightshade | Understand the project |
|---|---|---|
| [Installation](docs/getting-started/installation.md) | [Supported hardware](docs/supported-hardware-by-platform.md) | [Architecture](docs/architecture.md) |
| [First connection](docs/getting-started/first-connection.md) | [Known limitations](docs/known-limitations.md) | [Plugin SDK](docs/plugin_sdk/README.md) |
| [First image](docs/getting-started/first-image.md) | [Headless security](docs/headless-secure-setup.md) | [Contributing](.github/CONTRIBUTING.md) |
| [5.0 release notes](docs/release/v5.0.0.md) | [Release smoke test](docs/release-smoke-test.md) | [Changelog](docs/CHANGELOG.md) |

## Support the project

Nightshade is free to use. Patreon support helps fund hardware testing, packaging, documentation, driver compatibility, and the long tail of failures that only appear under a real sky. There are no paid-only builds or locked features.

<p align="center">
  <a href="https://www.patreon.com/cw/SeanDouglas"><img src="https://img.shields.io/badge/Support_Nightshade_on-Patreon-f96854?style=for-the-badge&logo=patreon&logoColor=white" alt="Support Nightshade on Patreon"></a>
</p>

Bug reports, hardware compatibility notes, and contributions are welcome. Read [CONTRIBUTING.md](.github/CONTRIBUTING.md); report vulnerabilities privately using [SECURITY.md](.github/SECURITY.md).

## License

Nightshade is **source-available**, not OSI open source. You may inspect, build, and audit the software under the terms in [LICENSE](LICENSE). Review those terms before redistributing Nightshade or building on its source.

---

<div align="center">

Built for clear skies, long nights, and observatories that should still be safe at sunrise.

[Download](https://github.com/Scdouglas1999/Nightshade/releases/latest) · [Docs](docs/index.md) · [Issues](https://github.com/Scdouglas1999/Nightshade/issues) · [Patreon](https://www.patreon.com/cw/SeanDouglas)

</div>
