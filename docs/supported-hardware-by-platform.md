# Supported Hardware By Platform

This page describes public-release hardware support by driver backend and
platform. It is intentionally conservative: a backend being available means
Nightshade can attempt discovery and connection on that platform. Individual
devices can still expose narrower capabilities after connection.

The same backend availability is surfaced in-app under
Settings > Connection > Platform Capabilities and through
`/api/info.platformCapabilities` in headless mode.

## Driver Backend Availability

| Driver backend | Windows | Linux | macOS | Notes |
| --- | --- | --- | --- | --- |
| ASCOM COM | Available | Unsupported | Unsupported | Requires Windows COM and locally installed ASCOM Platform/device drivers. |
| ASCOM Alpaca | Available | Available | Available | Network API for ASCOM-compatible devices and bridges. Device capability gaps are reported by the Alpaca server. |
| INDI | Available | Available | Available | Requires a reachable INDI server. Feature depth depends on the INDI driver and device property support. |
| Native SDK | Capability-gated | Capability-gated | Capability-gated | Depends on packaged vendor libraries, OS driver support, and redistribution approval. |
| Simulator | Capability-gated | Capability-gated | Capability-gated | Workflow-specific; use ASCOM, Alpaca, or INDI simulator drivers for hardware-like smoke tests unless an in-app simulator path is explicitly enabled. |

## Device Category Coverage

| Device category | ASCOM COM | Alpaca | INDI | Native SDK | Release expectation |
| --- | --- | --- | --- | --- | --- |
| Camera | Windows | All desktop platforms | INDI server platforms | Vendor/OS gated | Discovery and capture must report explicit errors when a device or SDK is unavailable. |
| Mount | Windows | All desktop platforms | INDI server platforms | Limited native protocols | Slew, sync, park, unpark, and tracking controls must be capability-gated per connected driver. |
| Focuser | Windows | All desktop platforms | INDI server platforms | Not a standalone public guarantee | Native focuser SDK work may exist internally, but release support should rely on ASCOM, Alpaca, or INDI unless verified. |
| Filter wheel | Windows | All desktop platforms | INDI server platforms | Not a standalone public guarantee | Native filter wheel SDK work may exist internally, but release support should rely on ASCOM, Alpaca, or INDI unless verified. |
| Rotator | Windows | All desktop platforms | INDI server platforms | Not currently a native guarantee | Controls must be disabled or fail explicitly if the driver lacks rotation support. |
| Guider | PHD2 integration and driver-dependent devices | PHD2 integration and driver-dependent devices | PHD2 integration and driver-dependent devices | Not currently a native guarantee | PHD2 is the primary release path for guiding workflows. |
| Dome | Windows | All desktop platforms | INDI server platforms | Not currently a native guarantee | Dome movement and slaving must be tested per driver before release sign-off. |
| Weather/safety | Windows ObservingConditions and safety drivers | All desktop platforms when provided by Alpaca | Driver-dependent and not fully parity-verified | Not currently a native guarantee | Weather safety must fail closed when unavailable or stale. |
| Switch/cover/calibrator | Windows where driver exposes device | All desktop platforms when provided by Alpaca | Driver-dependent and not fully parity-verified | Not currently a native guarantee | Power and cover controls are high-risk and must be explicitly audited per device. |

## Native SDK Notes

Native camera SDK support is gated by the libraries bundled for each release and
by the vendor's operating-system support. Do not treat a vendor name in the code
base as a public support guarantee until the release candidate has verified:

- the SDK library is present in the package for that OS and CPU architecture
- discovery succeeds with the intended hardware or vendor simulator
- connect, capture, download, abort, cooling, gain, offset, and cleanup paths
  behave correctly
- redistribution notices or agreements are in place where required

Known release-planning gaps from the hardware audit:

- Canon/Nikon DSLR native control is not a public-release guarantee.
- Native focuser and filter-wheel devices should not be advertised unless their
  standalone discovery and connection paths have been verified.
- ZWO native support on Apple Silicon depends on vendor SDK architecture
  availability and may require Rosetta or a non-native fallback.
- QHY native support should remain easy to disable or bypass because SDK
  discovery and stability can vary by installation.
- INDI weather and switch parity is not fully verified and may require Alpaca
  bridges for release-critical observatory safety.

## Linux Packaging And Permissions

Linux support must be treated as package- and host-specific until the external
Linux release build evidence is attached. A Linux artifact can only claim
hardware support when the release evidence records:

- required native shared libraries bundled with the package or listed as
  runtime dependencies
- USB/serial permission setup for the target host, including `udev rules`,
  `dialout`, `plugdev`, and `video` group membership where applicable
- INDI server package/source, driver names, and whether the server was local or
  remote during the smoke pass
- any vendor SDK packages, redistribution notes, and architecture constraints
  for ZWO, QHY, Player One, ToupTek, Moravian, Atik, and DSLR/gphoto2 paths
- the exact device, simulator, or loopback path used for discovery, connect,
  capture/control, and cleanup validation

Do not promote a Linux-native SDK or USB device path from capability-gated to
supported based only on code presence. The package must prove the relevant
library loads, permissions allow device access, and the runtime smoke exercised
the supported workflow from the shipped artifact.

## Release Verification Gate

Before a public release, run a hardware or simulator-backed smoke pass for every
backend and device category claimed in scope. Record unsupported items in the
release notes and make sure they match:

- this page
- `docs/production-readiness/feature-parity-matrix.md`
- in-app Platform Capabilities
- `/api/info.platformCapabilities`

If those four artifacts disagree, treat the release candidate as not ready.
