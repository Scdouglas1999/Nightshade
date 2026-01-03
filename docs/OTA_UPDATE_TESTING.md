# OTA Update System Testing Guide

This document describes how to test the Nightshade OTA (Over-The-Air) update system, specifically the LAN push functionality for pushing updates from your development machine to your imaging laptop.

## Quick Start

### Local Testing (Mock Receiver)

Test the complete push workflow without needing a real target machine:

```powershell
# From repo root
.\scripts\test_lan_push.ps1 -MockReceiver
```

This will:
1. Build an update package (or use existing)
2. Start a mock receiver on localhost
3. Discover the mock receiver
4. Push the update package
5. Verify the transfer completed

### Real Network Testing

With Nightshade running on your imaging laptop:

```powershell
# Discover Nightshade instances on the network
.\scripts\test_lan_push.ps1 -DiscoveryOnly

# Push to a specific machine
.\scripts\test_lan_push.ps1 -Target 192.168.1.50

# Push to all discovered machines
.\scripts\test_lan_push.ps1
```

## Test Scripts

### `test_lan_push.ps1`

End-to-end test script for LAN push functionality.

**Parameters:**
- `-MockReceiver` - Start a mock receiver for local testing
- `-Target <ip>` - Push to a specific IP address
- `-SkipBuild` - Skip building update package (use existing)
- `-DiscoveryOnly` - Only test discovery, don't push
- `-Verbose` - Show detailed output

**Examples:**

```powershell
# Full local test with mock
.\scripts\test_lan_push.ps1 -MockReceiver

# Test discovery only
.\scripts\test_lan_push.ps1 -DiscoveryOnly

# Push to imaging laptop
.\scripts\test_lan_push.ps1 -Target 192.168.1.50 -SkipBuild

# Verbose output
.\scripts\test_lan_push.ps1 -MockReceiver -Verbose
```

### `test_update_system.ps1`

Comprehensive test runner for the entire update system.

**Parameters:**
- `-UnitOnly` - Only run Dart unit tests
- `-E2EOnly` - Only run end-to-end tests
- `-RealNetwork` - Include real network discovery test
- `-Target <ip>` - Specific IP for network tests

**Examples:**

```powershell
# Run all tests
.\scripts\test_update_system.ps1

# Unit tests only
.\scripts\test_update_system.ps1 -UnitOnly

# Include real network test
.\scripts\test_update_system.ps1 -RealNetwork

# Test against specific machine
.\scripts\test_update_system.ps1 -Target 192.168.1.50
```

## Dart Unit Tests

The `packages/nightshade_updater` package includes unit tests for the LAN push protocol:

```powershell
cd packages/nightshade_updater
dart pub get
dart test test/lan_push_test.dart
```

Tests cover:
- Discovery protocol (UDP broadcast/response)
- Push protocol (TCP manifest + package transfer)
- Large file transfer handling
- Error conditions (connection refused, busy receiver)

## Manual Testing Workflow

### Step 1: Build Update Package

```powershell
# Build the app and create update package
.\scripts\build_update_package.ps1

# Or skip build if you have a recent build
.\scripts\build_update_package.ps1 -SkipBuild
```

This creates:
- `apps/desktop/build/update/nightshade-<version>-windows-x64.zip`
- `apps/desktop/build/update/manifest.json`
- `apps/desktop/build/update/nightshade-update.zip` (generic name for pusher)

### Step 2: Discover Targets

```powershell
.\tools\update_pusher\push_update.ps1 -Discover
```

Expected output:
```
Nightshade Update Pusher
========================

Discovering Nightshade instances...

  Found: Nightshade v2.0.0 (192.168.1.50:45680)

Found 1 instance(s).
```

### Step 3: Push Update

```powershell
# Push to specific target
.\tools\update_pusher\push_update.ps1 -Target 192.168.1.50

# Push to all discovered targets
.\tools\update_pusher\push_update.ps1 -All
```

Expected output:
```
Nightshade Update Pusher
========================

Pushing to 192.168.1.50:45680...
  Version: 2.0.0
  Package size: 37.2 MB
  Connected.
  Manifest sent.
  Uploading: 100%
  Success! Update staged on 192.168.1.50
```

### Step 4: Verify on Target

On the imaging laptop:
1. Nightshade should show an "Update Ready" banner
2. Check `%APPDATA%\Nightshade\updates\staging\ready.json` exists
3. The extracted files should be in `%APPDATA%\Nightshade\updates\staging\extracted\`

## Troubleshooting

### No targets discovered

1. **Firewall**: Ensure UDP port 45679 and TCP port 45680 are allowed
2. **Same network**: Both machines must be on the same local network
3. **Nightshade running**: The target must have Nightshade running with LAN push enabled

```powershell
# Check if ports are listening on target machine
netstat -an | Select-String "45679|45680"
```

### Push fails to connect

1. **Firewall on target**: Allow incoming TCP on port 45680
2. **Busy receiver**: Check if another push is in progress
3. **Wrong IP**: Verify the target IP is correct

### Package verification fails

1. **Incomplete transfer**: Check network stability
2. **Size mismatch**: Rebuild the update package
3. **Corrupt package**: Delete and rebuild: `.\scripts\build_update_package.ps1`

### Mock receiver doesn't start

1. **Port in use**: Check if port 45680 is already used
2. **Dart not found**: Ensure Dart SDK is in PATH
3. **Permissions**: Run PowerShell as Administrator

## Network Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 45679 | UDP | Discovery broadcast/response |
| 45680 | TCP | Update push file transfer |

## Protocol Details

### Discovery Protocol

1. Pusher broadcasts `NIGHTSHADE_UPDATE_PUSH` to UDP port 45679
2. Running Nightshade instances respond with JSON:
   ```json
   NIGHTSHADE_UPDATE_TARGET:{
     "name": "Nightshade",
     "version": "2.0.0",
     "buildNumber": 42,
     "pushPort": 45680,
     "isReceiving": false
   }
   ```

### Push Protocol

1. Pusher connects to TCP port 45680
2. Sends 4-byte manifest length (big-endian)
3. Sends manifest JSON
4. Streams ZIP package data
5. Receiver responds with status JSON:
   ```json
   {"status": "complete", "version": "2.0.0"}
   ```

## CI Integration

Add to your CI pipeline:

```yaml
- name: Test OTA Update System
  run: |
    .\scripts\test_update_system.ps1 -UnitOnly
```

For full E2E testing (requires mock receiver):

```yaml
- name: Test OTA Update System E2E
  run: |
    .\scripts\test_update_system.ps1
```
