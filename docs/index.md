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
- **Session Management**: Track and analyze your imaging sessions

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
- Capture tab: Main imaging interface
- Camera tab: Settings, cooling, gain/offset
- Mount tab: Slewing and tracking control
- Focus tab: Automatic and manual focusing
- Guiding tab: PHD2 integration

**[Sequencing and Automation](features/sequencing.md)**
- Building sequences with behavior trees
- Instruction nodes (expose, slew, focus, etc.)
- Logic nodes (loops, conditionals, parallel)
- Trigger nodes (monitoring and safety)
- Multi-target imaging
- Sequence templates

### Advanced Features

**Focusing** (covered in [Imaging Guide](features/imaging.md#focus-tab))
- V-curve autofocus
- Temperature compensation
- Focus vs. time graphing
- Manual focus aids

**Plate Solving** (covered in [Imaging Guide](features/imaging.md#plate-solving))
- Solving images for precise coordinates
- Target centering
- Mosaic alignment

**Framing Assistant** (Planetarium integration)
- Planning target composition
- Field of view preview
- Equipment framing overlay

**Flat Wizard**
- Automated flat frame capture
- Optimal exposure calculation
- Multi-filter flats

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
- Native support: QHY, ZWO ASI, Atik, FLI, SBIG
- Alpaca cameras (all platforms)

**Mounts**
- ASCOM-compatible mounts (Windows)
- INDI-compatible mounts (Linux/macOS)
- Alpaca mounts (all platforms)
- Direct serial/USB connection for popular mounts

**Focusers**
- ASCOM/INDI/Alpaca focusers
- Native support for popular models

**Filter Wheels**
- ASCOM/INDI/Alpaca filter wheels
- Integrated camera filter wheels

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

**Planetarium**
- Interactive sky map
- Target selection
- Framing preview
- Equipment overlay

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
   - Include safety triggers
3. Run preflight validation
4. Start sequence
5. Monitor progress

### Multi-Filter Deep Sky Imaging

1. Connect filter wheel
2. Create LRGB or narrowband sequence
3. Configure filter changes with autofocus
4. Set dithering
5. Run automated sequence
6. Capture calibration frames with Flat Wizard

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

## Additional Resources

### Community and Support

- **Documentation**: You're reading it!
- **GitHub**: https://github.com/your-org/nightshade
- **Discord**: https://discord.gg/nightshade (real-time help)
- **Forum**: https://forum.nightshade.app
- **Email Support**: support@nightshade.app

### Learning Resources

- Video tutorials (coming soon)
- Community sequence templates
- Equipment setup guides
- Processing workflow guides

### Developer Resources

Building plugins or contributing to Nightshade?

- [API Documentation](api/README.md)
- [Plugin Development Guide](api/plugin-api.md)
- [Architecture Overview](api/core-services.md)
- [Contributing Guidelines](../CONTRIBUTING.md)

## What's New in 2.0

Coming from Nightshade 1.x? Here's what's new:

- **Complete Rewrite**: Modern Flutter/Rust architecture
- **Cross-Platform**: Windows, macOS, Linux, iOS, Android
- **Behavior Tree Sequencer**: More powerful than script-based v1
- **Native Performance**: Rust backend for speed
- **Integrated Planetarium**: No external planetarium needed
- **Advanced Focusing**: Temperature compensation, graphs
- **Better PHD2 Integration**: Real-time monitoring
- **Modern UI**: Clean, responsive interface
- **Plugin System**: Extensible architecture

## Feedback and Contributions

We value your feedback!

- **Bug Reports**: GitHub Issues
- **Feature Requests**: GitHub Discussions
- **Documentation Improvements**: Submit pull requests
- **Community Help**: Answer questions on Discord/Forum

## License

Nightshade 2.0 is open-source software licensed under the MIT License.

## About

Nightshade 2.0 is developed by passionate astrophotographers for the astrophotography community. Our goal is to create the most powerful, user-friendly, and cross-platform imaging suite available.

---

**Ready to start capturing the cosmos?** Begin with the [Installation Guide](getting-started/installation.md)!

Clear skies!
