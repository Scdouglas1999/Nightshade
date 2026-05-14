# Nightshade 2.0 User Documentation

Welcome to the Nightshade 2.0 user documentation. Use these guides to install,
configure, and operate Nightshade within the platform and hardware scope listed
for the release candidate you are testing.

## What is Nightshade 2.0?

Nightshade 2.0 is an astrophotography application for controlling cameras,
mounts, focusers, and related observatory equipment where the release package
and connected driver backend support those capabilities. Built with Flutter and
Rust, it is designed for desktop imaging workflows, with platform support
limited by the artifacts and hardware evidence published for each release.

### Key Features

- **Platform-Scoped Support**: Windows, Linux, macOS, and mobile claims are
  release-specific and must match the release notes and support matrix
- **Multi-backend Device Support**: ASCOM COM, Alpaca, INDI, native SDK, and simulator paths with platform-specific capability gates
- **Intelligent Sequencer**: Behavior tree-based automation for complex imaging workflows
- **Integrated Planetarium**: GPU-rendered interactive sky visualization
- **Smart Focusing**: Automatic V-curve autofocus with temperature compensation
- **PHD2 Integration**: Seamless autoguiding integration
- **Plate Solving**: Precise target framing and alignment
- **Session Management**: Track and analyze your imaging sessions with checkpoint recovery
- **Weather Integration**: Radar display, cloud motion analysis, safety alerts
- **Remote Control**: Token-authenticated headless API, browser dashboard, and
  mobile client paths where verified for the release
- **Update Support**: Update checks and manifests where enabled by the release
  channel

## Getting Started

New to Nightshade? Start here:

### Installation and Setup

1. **[Installation Guide](getting-started/installation.md)**
   - System requirements
   - Download and install
   - First launch and setup

2. **[Connecting Your First Device](getting-started/first-connection.md)**
   - Understanding device protocols (ASCOM, INDI, Alpaca, Native)
   - Connecting camera and mount
   - Saving equipment profiles

3. **[Capturing Your First Image](getting-started/first-image.md)**
   - Single exposures
   - Camera settings
   - Focusing and plate solving
   - Reviewing your images

4. **[Headless Secure Setup](headless-secure-setup.md)**
   - Token-authenticated LAN mode
   - Firewall ports and discovery
   - Self-test and OpenAPI verification

5. **[Supported Hardware By Platform](supported-hardware-by-platform.md)**
   - Driver backend availability
   - Device category coverage
   - Known native SDK limitations

6. **[Known Limitations](known-limitations.md)**
   - Accepted limitations for release candidates
   - Unsupported-by-platform summary
   - Release notes checklist

7. **[Release Notes Template](release-notes-template.md)**
   - Required release evidence
   - Hardware and migration summaries
   - Rollback notes

8. **[Migration, Backup, and Restore Guide](migration-backup-restore.md)**
   - Backup contents and exclusions
   - Local and headless restore flows
   - Release-candidate migration evidence

## Feature Guides

Master Nightshade's powerful features:

### Core Imaging

**[Imaging Features](features/imaging.md)**
- Capture tab: Main imaging interface with live preview
- Camera tab: Settings, cooling, gain/offset presets, debayering
- Mount tab: Slewing, tracking, target centering, pulse guide
- Focus tab: V-curve autofocus, filter offsets, temperature compensation
- Guiding tab: PHD2 integration with real-time graphs

**[Sequencing and Automation](features/sequencing.md)**
- Building sequences with behavior trees
- 20+ instruction nodes (expose, slew, focus, etc.)
- Logic nodes (loops, conditionals, parallel, recovery)
- Trigger nodes (monitoring and safety)
- Pre-flight validation
- Multi-target imaging with session planner
- Sequence templates and checkpoint recovery

### Equipment & Configuration

**[Equipment Management](features/equipment.md)**
- Device discovery (ASCOM, INDI, Alpaca, Native)
- Connection protocols and troubleshooting
- Equipment profiles
- Per-device settings

**[Settings Reference](features/settings.md)**
- 15 configuration categories
- 100+ configurable options
- Location, appearance, notifications
- Plate solving configuration

### Sky Visualization & Planning

**[Planetarium](features/planetarium.md)**
- GPU-rendered interactive sky view
- Object selection and details
- Catalog support (Messier, NGC, IC, GLADE+)
- Time controls and mount integration

**[Framing Assistant](features/framing.md)**
- Target search and altitude planning
- Field of view preview
- Mosaic grid planning
- Equipment FOV overlay

### Monitoring & Safety

**[Weather Monitoring](features/weather.md)**
- Weather radar and satellite display
- Cloud motion analysis and ETA
- Safety alerts and auto-park
- Sequence integration

**[Guiding (PHD2)](features/guiding.md)**
- Full PHD2 control interface
- Real-time guiding graphs
- Calibration management
- PHD2 Brain settings

### Analysis & Automation

**[Analytics](features/analytics.md)**
- Session statistics and charts
- Historical data and trends
- Equipment performance metrics
- Image thumbnail review

## Equipment Setup

### Connection Protocols

Nightshade supports multiple ways to connect to your equipment:

| Protocol | Best For | Platform | Requirements |
|----------|----------|----------|--------------|
| **ASCOM** | Windows users with ASCOM drivers | Windows only | ASCOM Platform + drivers |
| **Native** | Direct USB connection when the release includes the needed SDK | Capability-gated | Packaged vendor SDK and OS driver support |
| **Alpaca** | Network devices, remote imaging | All platforms | Alpaca server on device |
| **INDI** | Linux/macOS standard | Linux/macOS | INDI server + drivers |

See [Supported Hardware By Platform](supported-hardware-by-platform.md) for
the public-release support matrix, then use
[First Connection](getting-started/first-connection.md) for detailed setup
instructions.

### Supported Equipment

**Cameras**
- ASCOM-compatible cameras (Windows)
- INDI-compatible cameras through a reachable INDI server
- Native SDK cameras only where the release package includes the required vendor library and the platform is verified
- Alpaca cameras (all platforms)

**Mounts**
- ASCOM-compatible mounts (Windows)
- INDI-compatible mounts through a reachable INDI server
- Alpaca mounts (all platforms)
- Limited native mount protocols where verified by the release candidate

**Focusers**
- ASCOM/INDI/Alpaca focusers
- Native standalone focuser support is not a public guarantee unless listed in the release notes

**Filter Wheels**
- ASCOM/INDI/Alpaca filter wheels
- Native standalone filter wheel support is not a public guarantee unless listed in the release notes

**Rotators**
- ASCOM/INDI/Alpaca rotators

**Domes**
- ASCOM/INDI/Alpaca domes
- Automatic slaving to mount

**Weather Stations**
- ASCOM/Alpaca observing conditions devices, plus INDI drivers where verified
- Safety monitors

**Guiders**
- PHD2 integration (all platforms)
- Direct guide camera support is driver-dependent and should be verified per release

## Application Overview

### Main Screen Layout

Nightshade's interface is organized into main screens accessible from the sidebar:

**Dashboard**
- Session overview
- Equipment status
- Live preview
- Quick actions
- Tonight's conditions

**Equipment**
- Device connections
- Equipment profiles
- Protocol selection
- Settings and configuration

**Imaging**
- Capture controls
- Camera settings
- Mount control
- Focus tools
- Guiding monitoring

**Sequencer**
- Sequence builder
- Target library
- Sequence templates
- Execution monitoring
- Checkpoint recovery

**Planetarium**
- Interactive sky map
- Target selection
- Framing preview
- Equipment overlay
- Mosaic planning
- Survey image overlays

**Framing**
- Target framing assistant
- Field of view planning
- Mosaic planning

**Analytics**
- Session statistics
- Image history
- Guiding performance
- Equipment logs

**Flat Wizard**
- Automated flat frame capture
- Multi-filter support
- Optimal exposure finding

## Common Workflows

### Simple Imaging Session

1. Connect equipment (camera, mount)
2. Slew to target
3. Focus
4. Start guiding (if needed)
5. Capture images
6. Review and save

### Automated Multi-Target Night

1. Create equipment profile
2. Build sequence in Sequencer:
   - Add targets from library
   - Configure exposures per target
   - Add autofocus between targets
   - Include safety triggers (weather, HFR monitor)
3. Run preflight validation
4. Start sequence
5. Monitor progress (or let checkpoint recovery handle interruptions)

### Multi-Filter Deep Sky Imaging

1. Connect filter wheel
2. Create LRGB or narrowband sequence
3. Configure filter changes with autofocus and filter offsets
4. Set dithering
5. Run automated sequence
6. Capture calibration frames with Flat Wizard

### Remote Imaging Session

1. Start desktop app on imaging computer
2. For the browser dashboard or mobile remote client, follow
   [Headless Secure Setup](headless-secure-setup.md)
3. Enable LAN exposure only with authentication unless you are on an isolated
   development network
4. Verify dashboard/mobile connection and WebSocket reconnect behavior before
   relying on remote monitoring
5. Treat localhost or emulator tests as development evidence; release validation
   still needs second-device LAN/firewall evidence

## Troubleshooting

Having issues? Check our comprehensive troubleshooting guide:

**[Common Issues and Solutions](troubleshooting/common-issues.md)**

Operations staff and on-call support: see the **[Operational Runbook](RUNBOOK.md)**
for first-responder checklists covering frozen startup, plate-solve failures,
OTA rollback, sequence resume issues, and headless server unreachability.

### Quick Links to Common Problems

Equipment:
- [Camera Not Detected](troubleshooting/common-issues.md#camera-not-detected)
- [Mount Not Responding](troubleshooting/common-issues.md#mount-not-responding)
- [Connection Lost During Imaging](troubleshooting/common-issues.md#connection-lost-during-imaging)
- [PHD2 Not Connecting](troubleshooting/common-issues.md#phd2-not-connecting)
- [PHD2 Troubleshooting](troubleshooting/phd2.md)
- [ASCOM Troubleshooting](troubleshooting/ascom.md)
- [INDI Troubleshooting](troubleshooting/indi.md)
- [Alpaca Troubleshooting](troubleshooting/alpaca.md)
- [Driver Troubleshooting](troubleshooting/drivers.md)
- [Permissions Troubleshooting](troubleshooting/permissions.md)
- [Firewall Troubleshooting](troubleshooting/firewall.md)

Imaging:
- [Autofocus Fails](troubleshooting/common-issues.md#autofocus-fails)
- [Images Not Saving](troubleshooting/common-issues.md#images-not-saving)
- [Poor Guiding Performance](troubleshooting/common-issues.md#poor-guiding-performance)
- [Plate Solving Fails](troubleshooting/common-issues.md#plate-solving-fails)

Application:
- [Nightshade Won't Start](troubleshooting/common-issues.md#nightshade-wont-start)
- [Application Crashes](troubleshooting/common-issues.md#application-crashes-during-use)
- [Slow Performance](troubleshooting/common-issues.md#slow-performance--ui-lag)

## Tips for Success

### For Beginners

1. **Start Simple**: Connect one device at a time
2. **Use Profiles**: Save working configurations
3. **Test First**: Take short exposures before long sequences
4. **Learn Focusing**: Master focus before automation
5. **Keep Notes**: Document what works for your setup

### For Advanced Users

1. **Build Templates**: Create reusable sequence templates
2. **Use Triggers**: Add safety monitoring to all sequences
3. **Plan Nights**: Use target library to plan entire sessions
4. **Automate Everything**: Meridian flips, refocusing, filter changes
5. **Analyze Sessions**: Review analytics to improve workflow
6. **Use Remote Control Carefully**: Monitor from mobile only after the secure
   setup and second-device LAN path are verified

## Additional Resources

### Community and Support

- **Documentation**: You're reading it!
- **GitHub**: https://github.com/Scodouglas1999/Nightshade
- **Issues**: https://github.com/Scodouglas1999/Nightshade/issues

### Developer Resources

Building plugins or contributing to Nightshade?

- [API Documentation](api/README.md)
- [Plugin Development Guide](api/plugin-api.md)
- [Architecture Overview](api/core-services.md)

## What's New in 2.0

Coming from Nightshade 1.x? Here's what's new:

- **Complete Rewrite**: Modern Flutter/Rust architecture
- **Platform-Scoped Builds**: Desktop and mobile artifacts are documented per
  release, with unsupported platforms listed in release notes
- **Behavior Tree Sequencer**: More powerful than script-based v1
- **Native Performance**: Rust backend for speed
- **Integrated Planetarium**: GPU-rendered sky visualization with survey overlays
- **Advanced Focusing**: Temperature compensation, ML-based focus prediction
- **Better PHD2 Integration**: Real-time monitoring, star images, calibration
- **Weather Integration**: Radar, cloud motion analysis, safety alerts
- **Remote Control**: Headless API, browser dashboard, and mobile client paths
  where verified for the release
- **Updates**: Manifest-based update checks where enabled by the release
  channel
- **Checkpoint Recovery**: Resume interrupted sequences automatically
- **Modern UI**: Clean, responsive interface with dark theme
- **Plugin System**: Extensible architecture

## Feedback and Contributions

We value your feedback!

- **Bug Reports**: GitHub Issues
- **Feature Requests**: GitHub Issues
- **Code Contributions**: Pull requests welcome

## About

Nightshade 2.0 is developed by astrophotographers for the astrophotography
community. Its public release scope is intentionally conservative: use the
release notes, support matrix, and known limitations to decide which workflows
are supported by the artifact you install.

---

**Ready to start capturing the cosmos?** Begin with the [Installation Guide](getting-started/installation.md)!

Clear skies!
