# Nightshade

[![Latest release](https://img.shields.io/github/v/release/Scdouglas1999/Nightshade?include_prereleases&label=release)](https://github.com/Scdouglas1999/Nightshade/releases/latest)
[![Platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20Linux%20%7C%20macOS%20%7C%20iOS%20%7C%20Android-blue)](#platforms)
[![License](https://img.shields.io/badge/license-source--available-orange)](LICENSE)

Nightshade is astrophotography software for your imaging rig. One app handles camera control, mount slewing, autofocus, guiding, plate solving, sequencing, planetarium, and remote control from a phone or web browser. It runs on Windows, Linux, and macOS, with companion apps for iOS and Android.

> **This is a beta.** The current release (v2.6.0) lives on the `beta` update channel. It's been through a long internal audit and hardening pass, but it hasn't had the multi-week soak that usually comes before a stable cut. If you need bulletproof reliability for an unattended run tonight, stay on [v2.5.0](https://github.com/Scdouglas1999/Nightshade/releases/tag/v2.5.0) for now. Otherwise, please try it and tell me what breaks — that's the fastest way we get to a clean stable.

## What it does

**Capture and sequence.** Live preview with auto-stretch, full cooled-camera control (gain/offset/binning/ROI/readout mode), FITS/TIFF/XISF output with templated filenames, dithering through PHD2, and a behavior-tree sequencer that handles meridian flips, refocus on temperature or HFR drift, weather safety triggers, and checkpoint recovery when something dies mid-night.

**Pick targets automatically with Plan Tonight.** Give it your targets along with per-filter integration goals (`L: 4h, RGB: 2h each, Hα: 6h`) and constraints (moon illumination cap, minimum moon separation, altitude window, custom horizon profile for trees and rooflines). It picks what to image right now, weights by altitude/moon/weather/priority/scheduled window, and only swaps to a new target when the score difference is meaningful enough to be worth the slew. It re-evaluates on real events — weather changes, guiding excursions, mount-state shifts — instead of just on a wall-clock timer, and the decision panel shows you exactly why it picked what it picked.

**Plate solving that actually works on day one.** ASTAP and astrometry.net are auto-detected across all standard install paths on Windows, macOS, and Linux. Catalog presence is checked separately so "binary OK, no catalog" is a distinct state. There's a verify-solve button in settings that runs your configured binary right then so you find out at setup time, not mid-sequence, when something's off. The wizards for centering, framing, and polar alignment all surface a required-banner with a one-click jump to setup if no solver is reachable yet.

**Polar align two ways.** All-sky single-shot (Sharpcap-style) for users who don't want to do the 3-point dance, plus the classic 3-point TPPA flow when you want it.

**Image without darks.** A defect-map pipeline builds a hot/cold pixel + dust shadow map from a short stack of darks (minimum 5 by default, fewer is a hard error not a silent fallback) and substitutes neighborhood medians at capture time. Lights leave the camera already clean. Maps are keyed by camera + sensor size + temperature bucket, so a +5°C run and a -10°C run don't share the same map.

**Bring your existing sequences with you.** NINA and Sequence Generator Pro sequence files import with auto-format detection and a node-mapping preview that shows you exactly what's about to be created. Unsupported nodes don't silently disappear. You either get a structured error with the offending type, or you toggle "import anyway" and Nightshade preserves the raw scalar fields so you can reconstruct.

**Run it from a phone or a browser.** Hit Nightshade's host from any browser on your LAN and you get the full equipment surface: camera cooling, gain, offset, readout mode, binning, subframe, filter wheel, focuser, rotator, mount slew on a press-and-hold d-pad, sequence load + checkpoint resume + profile switch, plus the plate-solve, polar-align, flat, mosaic, and framing wizards. Below 600px the layout switches to phone-tailored bottom-tab navigation. The iOS and Android companion apps pair by QR code, push critical-event notifications, and keep a foreground service running with live capture-progress percent.

**End-of-session reports.** After a night ends you get a report — captured frames per target per filter, HFR trend, guiding RMS distribution, weather/safety events that interrupted things, time on each target vs. planned. Multi-night campaigns roll those reports up per target so you can see how close you are to your integration goals.

**First-night tutorial + equipment onboarding wizard.** New users get walked through the first sequence end-to-end. Connecting a new piece of equipment runs a 10-step onboarding that covers the common gotchas instead of throwing you into raw driver settings.

## Hardware support

Three driver backends, plus native vendor SDKs where they make sense:

| Backend | Windows | macOS | Linux | What it's for |
|---|---|---|---|---|
| ASCOM COM | yes | — | — | Locally installed ASCOM Platform drivers |
| ASCOM Alpaca | yes | yes | yes | Network REST API; any Alpaca server or bridge |
| INDI | yes | yes | yes | Any reachable INDI server |
| Native SDK | yes | partial | partial | Direct vendor library, bypasses ASCOM/INDI |

Native camera SDKs are bundled for ZWO ASI, QHY, Player One, SVBony, Atik, FLI, Moravian, and the Touptek family (Touptek, Altair, Mallincam, OGMA). Native mount support covers SkyWatcher/Synta, iOptron, and LX200 (serial).

Focusers, filter wheels, rotators, domes, and weather/safety devices go through ASCOM, Alpaca, or INDI. The protocol path is mature there and the native side isn't a public release guarantee yet for those categories.

A note on drivers, native or otherwise: I built this against the equipment I personally own. The protocol drivers were written to be as vendor-agnostic as the spec allows, so most things should work. But if your specific camera/mount/focuser combination misbehaves I want to hear about it — open an issue with the device, the backend (ASCOM/Alpaca/INDI/native), and the exact action that broke.

## Platforms

|  | Windows | Linux | macOS | iOS | Android |
|---|---|---|---|---|---|
| Desktop app | tested | early testing | untested | — | — |
| Headless server | tested | early testing | untested | — | — |
| Web dashboard | runs against any working server | | | | |
| Companion app | — | — | — | yes | yes |

Windows is the most-exercised path because that's what I image on. Linux testing is just starting and Mac is essentially untested at this point — they both build and should run, but there's been no rigorous device-test pass. If you're running on Linux or Mac and something breaks, that's exactly the feedback the beta period exists to collect.

## Install

Grab the right artifact from the [latest release](https://github.com/Scdouglas1999/Nightshade/releases/latest):

| Platform | File |
|---|---|
| Windows installer | `NightshadeSetup-2.6.0.exe` |
| Windows OTA bundle | `nightshade-2.6.0-windows-x64.zip` + `manifest.json` |
| Linux bundle | `nightshade-2.6.0-linux-x64.tar.gz` |
| Android APK | `nightshade-2.6.0-android.apk` |
| iOS | Build from source for now |

Windows needs Windows 10 or 11 (x64). On Windows the [ASCOM Platform](https://ascom-standards.org/) is optional but unlocks the local COM driver path.

Linux is built against Ubuntu 22.04+. Runtime needs `libgtk-3`, `libsecret-1`, and standard glibc; pull the tar.gz, extract, and run the binary. For native vendor SDK paths you'll need the vendor's own udev rules and matching group memberships (`dialout`, `plugdev`, etc.).

The Android APK is currently debug-signed for the beta, so you'll need to allow install from unknown sources. A Play Store / TestFlight build is on the list.

## Build from source

You need [Flutter](https://flutter.dev/) 3.35+, [Rust](https://rustup.rs/) stable (edition 2021), and [Melos](https://melos.invertase.dev/):

```bash
git clone https://github.com/Scdouglas1999/Nightshade.git
cd Nightshade
dart pub global activate melos
melos bootstrap
melos run dev
```

`melos run dev` builds the Rust bridge, regenerates the FFI bindings, builds the Flutter app, and runs it. After that, `melos run dev:quick` skips FFI codegen when you've only changed implementation, and `melos run dev:clean` is the hard-reset button when something gets stuck.

Build deps by platform:

- **Windows:** Visual Studio 2022 with the C++ workload, LLVM/Clang on `PATH`.
- **Linux:** `build-essential clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libjsoncpp-dev`.
- **macOS:** Xcode command-line tools.

If FFI codegen fails with `stdbool.h not found` (Windows) or missing-header errors (Linux), see [`docs/FRB_TROUBLESHOOTING.md`](docs/FRB_TROUBLESHOOTING.md). It's almost always a `CPATH` problem.

## How to help

The single most useful thing you can do right now is **try the beta and file what you hit**. Bug reports with the device, the backend, the OS, and the exact action that broke are worth more than anything else during the beta cycle. Use [GitHub Issues](https://github.com/Scdouglas1999/Nightshade/issues).

If you have a vendor camera or mount that isn't in my equipment list, a "yes this connected and captured a frame" or "no, here's the error" is a real data point. Same for Linux distros beyond Ubuntu and any flavor of Mac.

PRs are welcome for bugs you fix or small features you'd like. For anything substantial, open an issue first so we can talk through the design before you sink time into a branch. Development conventions live in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Source-available, not open source. You can view and study the code; you can't redistribute, modify, or build derivative works without explicit permission. Full terms in [LICENSE](LICENSE).

## Acknowledgments

This is built on a stack of community work that's older than I am at this hobby:

- [ASCOM](https://ascom-standards.org/) for the Windows COM standard the amateur astronomy industry settled on.
- [INDI](https://indilib.org/) for the open Linux/macOS equivalent.
- [PHD2](https://openphdguiding.org/) for guiding that everyone agrees on.
- [Flutter](https://flutter.dev/) and [Rust](https://www.rust-lang.org/) for the app itself, glued together by [flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/).
- [LibRaw](https://www.libraw.org/) for camera RAW decoding.

Clear skies.
