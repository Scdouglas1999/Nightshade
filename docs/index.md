# Nightshade 2.0 User Documentation

Welcome to the Nightshade 2.0 user documentation! This guide will help you master the world's most advanced cross-platform astrophotography suite.

## What is Nightshade 2.0?

Nightshade 2.0 is a comprehensive astrophotography application that controls your telescope, camera, mount, focuser, and other equipment to capture stunning images of the night sky. Built with Flutter and Rust, it offers native performance on Windows, macOS, and Linux.

### Key Features

- **Multi-Platform Support**: Windows, macOS, Linux desktop + iOS/Android companion apps
- **Universal Device Compatibility**: ASCOM, INDI, Alpaca, and native SDK support
- **Intelligent Sequencer**: Behavior tree-based automation for complex imaging workflows
- **Integrated Planetarium**: GPU-rendered interactive sky visualization
- **Smart Focusing**: Automatic V-curve autofocus with temperature compensation
- **PHD2 Integration**: Seamless autoguiding integration
- **Plate Solving**: Precise target framing and alignment
- **Session Management**: Track and analyze your imaging sessions with checkpoint recovery
- **Weather Integration**: Radar display, cloud motion analysis, safety alerts
- **Remote Control**: WebRTC-based P2P control from mobile devices
- **OTA Updates**: Automatic updates with SHA256 verification

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
| **Native** | Direct USB connection, best performance | All platforms | Camera vendor SDK |
| **Alpaca** | Network devices, remote imaging | All platforms | Alpaca server on device |
| **INDI** | Linux/macOS standard | Linux/macOS | INDI server + drivers |

See [First Connection](getting-started/first-connection.md) for detailed setup instructions.

### Supported Equipment

**Cameras**
- ASCOM-compatible cameras (Windows)
- INDI-compatible cameras (Linux/macOS)
- Native SDK support: ZWO ASI, QHY, PlayerOne, SVBony, Atik, FLI, Moravian, Touptek
- Alpaca cameras (all platforms)

**Mounts**
- ASCOM-compatible mounts (Windows)
- INDI-compatible mounts (Linux/macOS)
- Alpaca mounts (all platforms)
- Direct serial: SkyWatcher/Synta, iOptron, LX200

**Focusers**
- ASCOM/INDI/Alpaca focusers
- Native support for popular models

**Filter Wheels**
- ASCOM/INDI/Alpaca filter wheels
- Integrated camera filter wheels

**Rotators**
- ASCOM/INDI/Alpaca rotators

**Domes**
- ASCOM/INDI/Alpaca domes
- Automatic slaving to mount

**Weather Stations**
- ASCOM/INDI/Alpaca observing conditions devices
- Safety monitors

**Guiders**
- PHD2 integration (all platforms)
- Direct guide camera support via ASCOM/INDI

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
2. Enable WebRTC in settings
3. Pair mobile app via QR code
4. Control remotely via phone/tablet

## Troubleshooting

Having issues? Check our comprehensive troubleshooting guide:

**[Common Issues and Solutions](troubleshooting/common-issues.md)**

### Quick Links to Common Problems

Equipment:
- [Camera Not Detected](troubleshooting/common-issues.md#camera-not-detected)
- [Mount Not Responding](troubleshooting/common-issues.md#mount-not-responding)
- [Connection Lost During Imaging](troubleshooting/common-issues.md#connection-lost-during-imaging)
- [PHD2 Not Connecting](troubleshooting/common-issues.md#phd2-not-connecting)

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
6. **Use Remote Control**: Monitor from mobile while equipment runs

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
- **Cross-Platform**: Windows, macOS, Linux, iOS, Android
- **Behavior Tree Sequencer**: More powerful than script-based v1
- **Native Performance**: Rust backend for speed
- **Integrated Planetarium**: GPU-rendered sky visualization with survey overlays
- **Advanced Focusing**: Temperature compensation, ML-based focus prediction
- **Better PHD2 Integration**: Real-time monitoring, star images, calibration
- **Weather Integration**: Radar, cloud motion analysis, safety alerts
- **Remote Control**: WebRTC P2P control from mobile devices
- **OTA Updates**: Automatic update system with LAN push for development
- **Checkpoint Recovery**: Resume interrupted sequences automatically
- **Modern UI**: Clean, responsive interface with dark theme
- **Plugin System**: Extensible architecture

## Feedback and Contributions

We value your feedback!

- **Bug Reports**: GitHub Issues
- **Feature Requests**: GitHub Issues
- **Code Contributions**: Pull requests welcome

## About

Nightshade 2.0 is developed by passionate astrophotographers for the astrophotography community. Our goal is to create the most powerful, user-friendly, and cross-platform imaging suite available.

---

**Ready to start capturing the cosmos?** Begin with the [Installation Guide](getting-started/installation.md)!

Clear skies!
