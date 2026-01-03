# Installation Guide

Welcome to Nightshade 2.0! This guide will help you install and set up the application on your computer.

## System Requirements

### Windows
- **Operating System**: Windows 10 or Windows 11 (64-bit)
- **Processor**: Intel Core i5 or AMD Ryzen 5 (or equivalent)
- **Memory**: 8 GB RAM minimum, 16 GB recommended
- **Graphics**: DirectX 11 compatible GPU with 2 GB VRAM
- **Storage**: 500 MB for application, plus space for images
- **Additional**: .NET Framework 4.8 or later (for ASCOM support)

### macOS
- **Operating System**: macOS 13 (Ventura) or later
- **Processor**: Intel or Apple Silicon (M1/M2/M3)
- **Memory**: 8 GB RAM minimum, 16 GB recommended
- **Graphics**: Metal-compatible GPU
- **Storage**: 500 MB for application, plus space for images

### Linux
- **Operating System**: Ubuntu 22.04 LTS or later (or equivalent distribution)
- **Processor**: Intel Core i5 or AMD Ryzen 5 (or equivalent)
- **Memory**: 8 GB RAM minimum, 16 GB recommended
- **Graphics**: OpenGL 3.3 compatible GPU
- **Storage**: 500 MB for application, plus space for images
- **Additional**: INDI server installed for equipment control

## Download

1. Visit the [Nightshade 2.0 releases page](https://github.com/Scodouglas1999/Nightshade/releases)
2. Download the installer for your operating system:
   - **Windows**: `Nightshade-2.0-Setup.exe`
   - **macOS**: `Nightshade-2.0.dmg`
   - **Linux**: `Nightshade-2.0-x64.AppImage` or `.deb` package

## Installation Steps

### Windows

1. **Run the Installer**
   - Double-click `Nightshade-2.0-Setup.exe`
   - If Windows SmartScreen appears, click "More info" then "Run anyway"

2. **Follow the Setup Wizard**
   - Accept the license agreement
   - Choose installation directory (default: `C:\Program Files\Nightshade`)
   - Select whether to create desktop shortcut
   - Click "Install"

3. **Complete Installation**
   - Wait for installation to complete
   - Click "Finish" to launch Nightshade

4. **ASCOM Setup (Optional but Recommended)**
   - If you plan to use ASCOM drivers, download and install the [ASCOM Platform](https://ascom-standards.org/)
   - Install ASCOM drivers for your equipment (camera, mount, focuser, etc.)

### macOS

1. **Open the Disk Image**
   - Double-click `Nightshade-2.0.dmg`
   - A new window will open

2. **Install the Application**
   - Drag the Nightshade icon to the Applications folder
   - Wait for the copy to complete

3. **First Launch**
   - Open Applications folder
   - Right-click Nightshade and select "Open" (first time only)
   - Click "Open" when prompted about an unidentified developer
   - Subsequent launches can use normal double-click

4. **Grant Permissions**
   - Allow camera access if prompted (for USB cameras)
   - Allow network access if prompted (for network-connected devices)

### Linux

#### Using AppImage (Universal)

1. **Make Executable**
   ```bash
   chmod +x Nightshade-2.0-x64.AppImage
   ```

2. **Run the Application**
   ```bash
   ./Nightshade-2.0-x64.AppImage
   ```

3. **Optional: Add to Menu**
   - Right-click the AppImage and select "Integrate with system"
   - Or move to `~/.local/bin/` for command-line access

#### Using .deb Package (Debian/Ubuntu)

1. **Install the Package**
   ```bash
   sudo dpkg -i nightshade_2.0_amd64.deb
   sudo apt-get install -f  # Install dependencies if needed
   ```

2. **Launch**
   - Find Nightshade in your application menu
   - Or run from terminal: `nightshade`

#### INDI Server Setup

For equipment control on Linux, you'll need INDI:

1. **Install INDI**
   ```bash
   sudo apt-add-repository ppa:mutlaqja/ppa
   sudo apt-get update
   sudo apt-get install indi-full
   ```

2. **Start INDI Server**
   - Nightshade can auto-start INDI drivers
   - Or manually start: `indiserver indi_simulator_telescope indi_simulator_ccd`

## First Launch

When you first launch Nightshade 2.0:

1. **Welcome Screen**
   - You'll see a brief welcome message
   - Click "Get Started" to continue

2. **Equipment Setup Wizard** (Optional)
   - Choose whether to set up equipment now or later
   - If you select "Set Up Now", you'll be guided through connecting your devices
   - You can always set up equipment later from the Equipment screen

3. **Main Interface**
   - The Dashboard will open, showing your equipment status
   - Use the sidebar to navigate between different features

## Verify Installation

To verify Nightshade is working correctly:

1. **Check the Dashboard**
   - All panels should load without errors
   - The clock should display current time and LST

2. **Open Equipment Screen**
   - Navigate to Equipment from the sidebar
   - You should see connection options for different protocols

3. **Open Planetarium**
   - Navigate to Planetarium from the sidebar
   - The sky view should render smoothly

## Data Storage

Nightshade stores configuration and data in the following locations:

- **Windows**: `%APPDATA%\Nightshade\`
- **macOS**: `~/Library/Application Support/Nightshade/`
- **Linux**: `~/.local/share/nightshade/`

This includes:
- Equipment profiles
- Imaging sequences
- Session data
- Application settings

## Updating

To update Nightshade:

1. Download the latest version from the releases page
2. Run the installer (it will replace the old version)
3. Your profiles and settings will be preserved

## Troubleshooting Installation

### Windows: "Windows protected your PC" message
- Click "More info"
- Click "Run anyway"
- This appears because the app is not signed with a Windows certificate

### macOS: "App is damaged and can't be opened"
- This is a Gatekeeper issue
- Open Terminal and run: `xattr -cr /Applications/Nightshade.app`
- Then try opening Nightshade again

### Linux: AppImage won't run
- Ensure you've made it executable: `chmod +x Nightshade-2.0-x64.AppImage`
- Install FUSE if needed: `sudo apt-get install fuse`

### Missing Dependencies
- Windows: Install Visual C++ Redistributable and .NET Framework 4.8
- Linux: Run `ldd Nightshade` to check for missing libraries

## Next Steps

Now that Nightshade is installed, proceed to:
- [Connecting Your First Device](first-connection.md) - Set up your camera and mount
- [Capturing Your First Image](first-image.md) - Take your first exposure

## Getting Help

If you encounter issues during installation:
- Check the [Troubleshooting Guide](../troubleshooting/common-issues.md)
- Visit our [GitHub Issues](https://github.com/Scodouglas1999/Nightshade/issues)
