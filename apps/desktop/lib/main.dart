import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_webrtc/nightshade_webrtc.dart';
import 'package:nightshade_updater/nightshade_updater.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as path;

import 'package:nightshade_app/nightshade_app.dart';

// Current app version - read from version.yaml during build
const String appVersion = '2.0.0';
const int appBuildNumber = 1;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check for headless mode flag
  final isHeadless = args.contains('--headless') ||
      Platform.environment['NIGHTSHADE_HEADLESS'] == '1';

  if (isHeadless) {
    // Redirect to headless entry point
    await _runHeadless();
    return;
  }

  // Initialize the native bridge
  final appSupportDir = await getApplicationSupportDirectory();
  final logDir = path.join(appSupportDir.path, 'logs');
  await bridge.NativeBridge.init(logDirectory: logDir);

  // Initialize profile storage
  final appDir = await getApplicationDocumentsDirectory();
  final profileDir = path.join(appDir.path, 'Nightshade', 'profiles');
  await Directory(profileDir).create(recursive: true);
  await bridge.NativeBridge.apiInitProfileStorage(storagePath: profileDir);

  // Initialize settings storage
  await bridge.NativeBridge.apiInitSettingsStorage(storagePath: profileDir);

  // Initialize window manager for desktop (only in GUI mode)
  await windowManager.ensureInitialized();

  // Initialize catalog manager with app data directory
  await _initializeCatalogManager();

  const windowOptions = WindowOptions(
    size: Size(1600, 900),
    minimumSize: Size(1200, 700),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'Nightshade 2.0',
  );

  final container = ProviderContainer(
    overrides: [
      // Initialize backendProvider with FfiBackend immediately for desktop GUI
      backendProvider.overrideWith((ref) {
        final notifier = BackendNotifier(ref);
        notifier.useLocalBackend();
        return notifier;
      }),
    ],
  );

  // Check if we should start minimized
  final shouldStartMinimized = await _shouldStartMinimized(container);

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();

    // Minimize after showing if setting is enabled
    if (shouldStartMinimized) {
      await windowManager.minimize();
    }
  });

  // Start background services for mobile access (non-blocking)
  _startBackgroundServices();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NightshadeApp(isDesktop: true),
    ),
  );
}

/// Start background services for mobile/remote access
void _startBackgroundServices() {
  // Start in background - don't block UI
  Future.microtask(() async {
    try {
      // Start web server with device handlers
      print('[MAIN] Creating web server with device handlers...');
      final webServer = NightshadeWebServer(
        port: 8080,
        devicesHandler: _getDevicesHandler,
        deviceConnectHandler: _connectDeviceHandler,
        deviceDisconnectHandler: _disconnectDeviceHandler,
        connectedDevicesHandler: _getConnectedDevicesHandler,
        phd2ConnectHandler: _phd2ConnectHandler,
        phd2DisconnectHandler: _phd2DisconnectHandler,
      );

      // Wire up additional handlers using setters
      webServer.cameraExposeHandler = _cameraExposeHandler;
      webServer.cameraAbortHandler = _cameraAbortHandler;
      webServer.cameraSetCoolingHandler = _cameraSetCoolingHandler;
      webServer.cameraSetGainHandler = _cameraSetGainHandler;
      webServer.cameraSetOffsetHandler = _cameraSetOffsetHandler;
      webServer.cameraStatusHandler = _cameraStatusHandler;

      webServer.mountSlewHandler = _mountSlewHandler;
      webServer.mountSyncHandler = _mountSyncHandler;
      webServer.mountParkHandler = _mountParkHandler;
      webServer.mountUnparkHandler = _mountUnparkHandler;
      webServer.mountSetTrackingHandler = _mountSetTrackingHandler;
      webServer.mountAbortHandler = _mountAbortHandler;
      webServer.mountGetStatusHandler = _mountGetStatusHandler;
      webServer.mountStatusHandler = _mountGetStatusHandler;

      webServer.focuserMoveToHandler = _focuserMoveToHandler;
      webServer.focuserMoveRelativeHandler = _focuserMoveRelativeHandler;
      webServer.focuserHaltHandler = _focuserHaltHandler;
      webServer.focuserStatusHandler = _focuserStatusHandler;

      webServer.filterWheelSetPositionHandler = _filterWheelSetPositionHandler;
      webServer.filterWheelGetNamesHandler = _filterWheelGetNamesHandler;
      webServer.filterWheelStatusHandler = _filterWheelStatusHandler;

      webServer.getLocationHandler = _getLocationHandler;
      webServer.setLocationHandler = _setLocationHandler;

      webServer.phd2GetStatusHandler = _phd2GetStatusHandler;
      webServer.phd2StartGuidingHandler = _phd2StartGuidingHandler;
      webServer.phd2StopGuidingHandler = _phd2StopGuidingHandler;
      webServer.phd2DitherHandler = _phd2DitherHandler;

      // Extended handlers
      webServer.cameraGetLastImageHandler = _cameraGetLastImageHandler;
      webServer.mountPulseGuideHandler = _mountPulseGuideHandler;
      webServer.autofocusStartHandler = _autofocusStartHandler;
      webServer.autofocusCancelHandler = _autofocusCancelHandler;
      webServer.filterWheelSetByNameHandler = _filterWheelSetByNameHandler;
      webServer.rotatorMoveToHandler = _rotatorMoveToHandler;
      webServer.rotatorMoveRelativeHandler = _rotatorMoveRelativeHandler;
      webServer.rotatorGetStatusHandler = _rotatorGetStatusHandler;
      webServer.rotatorHaltHandler = _rotatorHaltHandler;
      webServer.plateSolveHandler = _plateSolveHandler;
      webServer.sequencerStartHandler = _sequencerStartHandler;
      webServer.sequencerStopHandler = _sequencerStopHandler;
      webServer.sequencerPauseHandler = _sequencerPauseHandler;
      webServer.sequencerResumeHandler = _sequencerResumeHandler;
      webServer.sequencerLoadHandler = _sequencerLoadHandler;
      webServer.sequencerSetSimulationHandler = _sequencerSetSimulationHandler;
      webServer.sequencerStatusHandler = _sequencerGetStatusHandler;
      webServer.getProfilesHandler = _getProfilesHandler;
      webServer.saveProfileHandler = _saveProfileHandler;
      webServer.deleteProfileHandler = _deleteProfileHandler;
      webServer.loadProfileHandler = _loadProfileHandler;
      webServer.getActiveProfileHandler = _getActiveProfileHandler;
      webServer.getSettingsHandler = _getSettingsHandler;
      webServer.updateSettingsHandler = _updateSettingsHandler;
      webServer.polarAlignmentStartHandler = _polarAlignmentStartHandler;
      webServer.polarAlignmentStopHandler = _polarAlignmentStopHandler;

      print('[MAIN] Starting web server...');
      await webServer.start();
      print(
          '[MAIN] Web server started for mobile access on port ${webServer.actualPort}');

      // Start UDP broadcasting for auto-discovery
      print('[MAIN] Starting UDP broadcast for auto-discovery...');
      await NightshadeDiscovery.startBroadcasting(
        webPort: webServer.actualPort,
        signalingPort: 45678,
        name: 'Nightshade Server',
        version: '2.0.0',
      );
      print('[MAIN] Broadcasting on UDP port 45679');

      // Start mDNS/Bonjour advertising for iOS discovery
      try {
        await _startMdnsAdvertising(webServer.actualPort);
        print('[MAIN] mDNS service advertised as _nightshade._tcp');
      } catch (e) {
        debugPrint(
            '[MAIN] mDNS advertising failed (expected on some platforms): $e');
      }

      // Start LAN push update receiver
      try {
        var isReceivingLanPush = false;
        final lanPushReceiver = LanPushReceiver(
          currentVersion: appVersion,
          currentBuildNumber: appBuildNumber,
        );
        lanPushReceiver.onUpdateReceived = (manifest, stagingPath) {
          isReceivingLanPush = false;
          print('[MAIN] Update received via LAN push: ${manifest.version}');
          LanPushNotifier.notifyUpdateReceived(manifest, stagingPath);
        };
        lanPushReceiver.onProgress = (received, total, progress, message) {
          isReceivingLanPush = total > 0 && received < total;
          print(
              '[MAIN] LAN push progress: ${(progress * 100).toStringAsFixed(1)}% - $message');
          LanPushNotifier.notifyProgress(received, total, progress, message);
        };
        lanPushReceiver.onError = (error) {
          isReceivingLanPush = false;
          print('[MAIN] LAN push error: $error');
          LanPushNotifier.notifyError(error);
        };
        await lanPushReceiver.startServer();
        print('[MAIN] LAN push receiver started on port 45680');

        // Start responding to update push discovery
        await UpdatePushDiscovery.startResponding(
          name: 'Nightshade',
          version: appVersion,
          buildNumber: appBuildNumber,
          isReceivingCallback: () => isReceivingLanPush,
        );
        print('[MAIN] Update push discovery responder started');
      } catch (e) {
        debugPrint('[MAIN] LAN push receiver failed: $e');
      }
    } catch (e) {
      // Silently fail - web build might not be available
      debugPrint('[MAIN] Web server not available: $e');
    }

    try {
      // Start WebRTC signaling
      final signaling = NightshadeSignaling();
      await signaling.startServer();
      print('WebRTC signaling server started');
    } catch (e) {
      debugPrint('WebRTC signaling failed: $e');
    }
  });
}

/// Run in headless mode (no GUI window)
Future<void> _runHeadless() async {
  print('Nightshade 2.0 - Headless Mode');
  print('==============================');

  try {
    // Initialize the native bridge
    print('Initializing native bridge...');
    await bridge.NativeBridge.init();

    // Initialize profile storage
    final appDir = await getApplicationDocumentsDirectory();
    final profileDir = path.join(appDir.path, 'Nightshade', 'profiles');
    await Directory(profileDir).create(recursive: true);
    await bridge.NativeBridge.apiInitProfileStorage(storagePath: profileDir);

    // Initialize settings storage
    await bridge.NativeBridge.apiInitSettingsStorage(storagePath: profileDir);
    print('✓ Native bridge initialized');

    // Initialize catalog manager
    print('Initializing catalog manager...');
    await _initializeCatalogManager();
    print('✓ Catalog manager initialized');

    // Start headless services (web server, discovery, etc.)
    print('Starting headless services...');
    await _startHeadlessServices();
    print('✓ Headless services started');

    print('\nNightshade is running in headless mode.');
    print('Press Ctrl+C to stop.\n');

    // Keep the process alive
    ProcessSignal.sigint.watch().listen((signal) {
      print('\nShutting down...');
      exit(0);
    });

    // Keep alive loop
    while (true) {
      await Future.delayed(const Duration(seconds: 1));
    }
  } catch (e, stackTrace) {
    print('Error starting headless mode: $e');
    print('Stack trace: $stackTrace');
    exit(1);
  }
}

/// Start headless services (web server, discovery, WebRTC)
Future<void> _startHeadlessServices() async {
  // Start web server
  try {
    print('[HEADLESS] Initializing Nightshade headless mode...');
    final webServer = NightshadeWebServer(
      port: 8080,
      devicesHandler: _getDevicesHandler,
      deviceConnectHandler: _connectDeviceHandler,
      deviceDisconnectHandler: _disconnectDeviceHandler,
      connectedDevicesHandler: _getConnectedDevicesHandler,
      phd2ConnectHandler: _phd2ConnectHandler,
      phd2DisconnectHandler: _phd2DisconnectHandler,
    );

    // Wire up additional handlers using setters
    webServer.cameraExposeHandler = _cameraExposeHandler;
    webServer.cameraAbortHandler = _cameraAbortHandler;
    webServer.cameraSetCoolingHandler = _cameraSetCoolingHandler;
    webServer.cameraSetGainHandler = _cameraSetGainHandler;
    webServer.cameraSetOffsetHandler = _cameraSetOffsetHandler;
    webServer.cameraStatusHandler = _cameraStatusHandler;

    webServer.mountSlewHandler = _mountSlewHandler;
    webServer.mountSyncHandler = _mountSyncHandler;
    webServer.mountParkHandler = _mountParkHandler;
    webServer.mountUnparkHandler = _mountUnparkHandler;
    webServer.mountSetTrackingHandler = _mountSetTrackingHandler;
    webServer.mountAbortHandler = _mountAbortHandler;
    webServer.mountGetStatusHandler = _mountGetStatusHandler;
    webServer.mountStatusHandler = _mountGetStatusHandler;

    webServer.focuserMoveToHandler = _focuserMoveToHandler;
    webServer.focuserMoveRelativeHandler = _focuserMoveRelativeHandler;
    webServer.focuserHaltHandler = _focuserHaltHandler;
    webServer.focuserStatusHandler = _focuserStatusHandler;

    webServer.filterWheelSetPositionHandler = _filterWheelSetPositionHandler;
    webServer.filterWheelGetNamesHandler = _filterWheelGetNamesHandler;
    webServer.filterWheelStatusHandler = _filterWheelStatusHandler;

    webServer.getLocationHandler = _getLocationHandler;
    webServer.setLocationHandler = _setLocationHandler;

    webServer.phd2GetStatusHandler = _phd2GetStatusHandler;
    webServer.phd2StartGuidingHandler = _phd2StartGuidingHandler;
    webServer.phd2StopGuidingHandler = _phd2StopGuidingHandler;
    webServer.phd2DitherHandler = _phd2DitherHandler;

    // Extended handlers
    webServer.cameraGetLastImageHandler = _cameraGetLastImageHandler;
    webServer.mountPulseGuideHandler = _mountPulseGuideHandler;
    webServer.autofocusStartHandler = _autofocusStartHandler;
    webServer.autofocusCancelHandler = _autofocusCancelHandler;
    webServer.filterWheelSetByNameHandler = _filterWheelSetByNameHandler;
    webServer.rotatorMoveToHandler = _rotatorMoveToHandler;
    webServer.rotatorMoveRelativeHandler = _rotatorMoveRelativeHandler;
    webServer.rotatorGetStatusHandler = _rotatorGetStatusHandler;
    webServer.rotatorHaltHandler = _rotatorHaltHandler;
    webServer.plateSolveHandler = _plateSolveHandler;
    webServer.sequencerStartHandler = _sequencerStartHandler;
    webServer.sequencerStopHandler = _sequencerStopHandler;
    webServer.sequencerPauseHandler = _sequencerPauseHandler;
    webServer.sequencerResumeHandler = _sequencerResumeHandler;
    webServer.sequencerLoadHandler = _sequencerLoadHandler;
    webServer.sequencerSetSimulationHandler = _sequencerSetSimulationHandler;
    webServer.sequencerStatusHandler = _sequencerGetStatusHandler;
    webServer.getProfilesHandler = _getProfilesHandler;
    webServer.saveProfileHandler = _saveProfileHandler;
    webServer.deleteProfileHandler = _deleteProfileHandler;
    webServer.loadProfileHandler = _loadProfileHandler;
    webServer.getActiveProfileHandler = _getActiveProfileHandler;
    webServer.getSettingsHandler = _getSettingsHandler;
    webServer.updateSettingsHandler = _updateSettingsHandler;
    webServer.polarAlignmentStartHandler = _polarAlignmentStartHandler;
    webServer.polarAlignmentStopHandler = _polarAlignmentStopHandler;

    await webServer.start();
    print('  ✓ Web server started on port ${webServer.actualPort}');

    // Start discovery broadcasting
    try {
      await NightshadeDiscovery.startBroadcasting(
        webPort: webServer.actualPort,
        signalingPort: 45678,
        name: 'Nightshade',
        version: '2.0.0',
      );
      print('  ✓ Discovery broadcasting started');
    } catch (e) {
      print('  ⚠ Discovery broadcasting failed: $e');
    }

    // Start mDNS/Bonjour advertising for iOS discovery
    try {
      await _startMdnsAdvertising(webServer.actualPort);
      print('  ✓ mDNS service advertised as _nightshade._tcp');
    } catch (e) {
      print('  ⚠ mDNS advertising failed: $e');
    }

    // Print QR connection data for mobile scanning
    try {
      final localIp = await _getLocalIp();
      if (localIp != null) {
        final qrData = EnhancedNightshadeDiscovery.generateQrData(
          host: localIp,
          webPort: webServer.actualPort,
          signalingPort: 45678,
          serverName: 'Nightshade',
        );
        print('\n  Mobile connection info:');
        print('    Address: http://$localIp:${webServer.actualPort}');
        print('    QR Data: $qrData\n');
      }
    } catch (e) {
      // Ignore QR data errors
    }
  } catch (e) {
    print('  ⚠ Web server failed to start: $e');
  }

  // Start WebRTC signaling server for direct connections
  try {
    final signaling = NightshadeSignaling();
    await signaling.startServer();
    print('  ✓ WebRTC signaling server started on port 45678');
  } catch (e) {
    print('  ⚠ WebRTC signaling server failed: $e');
  }
}

Future<void> _initializeCatalogManager() async {
  try {
    final appDataDir = await getApplicationSupportDirectory();
    final catalogDir = path.join(appDataDir.path, 'catalogs');
    await CatalogManager.instance.initialize(catalogDir);
  } catch (e) {
    debugPrint('Failed to initialize catalog manager: $e');
  }
}

/// Handler for /api/devices endpoint
Future<Map<String, dynamic>> _getDevicesHandler() async {
  print('[API] Device discovery requested...');
  try {
    // Discover ALL device types in parallel for faster discovery
    print('[API] Discovering all devices in parallel...');
    final results = await Future.wait([
      bridge.NativeBridge.discoverDevices(bridge.DeviceType.camera),
      bridge.NativeBridge.discoverDevices(bridge.DeviceType.mount),
      bridge.NativeBridge.discoverDevices(bridge.DeviceType.focuser),
      bridge.NativeBridge.discoverDevices(bridge.DeviceType.filterWheel),
      bridge.NativeBridge.discoverDevices(bridge.DeviceType.guider),
    ]);

    final cameras = results[0];
    final mounts = results[1];
    final focusers = results[2];
    final filterWheels = results[3];
    final guiders = results[4];

    // Format devices for API response
    final allDevices = <Map<String, dynamic>>[];

    for (final camera in cameras) {
      allDevices.add({
        'id': camera.id,
        'name': camera.name,
        'type': 'camera',
        'driverType': camera.driverType.name,
        'description': camera.description,
      });
    }

    for (final mount in mounts) {
      allDevices.add({
        'id': mount.id,
        'name': mount.name,
        'type': 'mount',
        'driverType': mount.driverType.name,
        'description': mount.description,
      });
    }

    for (final focuser in focusers) {
      allDevices.add({
        'id': focuser.id,
        'name': focuser.name,
        'type': 'focuser',
        'driverType': focuser.driverType.name,
        'description': focuser.description,
      });
    }

    for (final filterWheel in filterWheels) {
      allDevices.add({
        'id': filterWheel.id,
        'name': filterWheel.name,
        'type': 'filterwheel',
        'driverType': filterWheel.driverType.name,
        'description': filterWheel.description,
      });
    }

    for (final guider in guiders) {
      allDevices.add({
        'id': guider.id,
        'name': guider.name,
        'type': 'guider',
        'driverType': guider.driverType.name,
        'description': guider.description,
      });
    }

    final response = {
      'devices': allDevices,
      'available': allDevices,
      'connected': {
        'camera': null,
        'mount': null,
        'focuser': null,
        'filterWheel': null,
        'rotator': null,
      },
    };

    return response;
  } catch (e, stackTrace) {
    debugPrint('[API] Error discovering devices: $e');
    debugPrint('[API] Stack trace: $stackTrace');
    return {
      'devices': <Map<String, dynamic>>[],
      'available': <Map<String, dynamic>>[],
      'connected': {
        'camera': null,
        'mount': null,
        'focuser': null,
        'filterWheel': null,
        'rotator': null,
      },
      'error': e.toString(),
    };
  }
}

/// Handler for /api/devices/connect endpoint
Future<void> _connectDeviceHandler(String deviceType, String deviceId) async {
  print('[API] Connecting device: $deviceType / $deviceId');
  try {
    // Parse device type
    bridge.DeviceType bridgeType;
    switch (deviceType.toLowerCase()) {
      case 'camera':
        bridgeType = bridge.DeviceType.camera;
        break;
      case 'mount':
        bridgeType = bridge.DeviceType.mount;
        break;
      case 'focuser':
        bridgeType = bridge.DeviceType.focuser;
        break;
      case 'filterwheel':
        bridgeType = bridge.DeviceType.filterWheel;
        break;
      case 'guider':
        bridgeType = bridge.DeviceType.guider;
        break;
      default:
        throw Exception('Unknown device type: $deviceType');
    }

    // Handle PHD2 device IDs specially (extract host/port if present)
    if (deviceId.startsWith('phd2:')) {
      final parts = deviceId.split(':');
      String? host;
      int? port;
      if (parts.length >= 3) {
        host = parts[1];
        port = int.tryParse(parts[2]) ?? 4400;
      }
      await bridge.NativeBridge.phd2Connect(host: host, port: port);
    } else {
      // Regular device connection
      await bridge.NativeBridge.connectDevice(bridgeType, deviceId);
    }
    print('[API] Device connected successfully');
  } catch (e, stackTrace) {
    debugPrint('[API] Error connecting device: $e');
    debugPrint('[API] Stack trace: $stackTrace');
    rethrow;
  }
}

/// Handler for /api/devices/disconnect endpoint
Future<void> _disconnectDeviceHandler(
    String deviceType, String deviceId) async {
  print('[API] Disconnecting device: $deviceType / $deviceId');
  try {
    // Parse device type
    bridge.DeviceType bridgeType;
    switch (deviceType.toLowerCase()) {
      case 'camera':
        bridgeType = bridge.DeviceType.camera;
        break;
      case 'mount':
        bridgeType = bridge.DeviceType.mount;
        break;
      case 'focuser':
        bridgeType = bridge.DeviceType.focuser;
        break;
      case 'filterwheel':
        bridgeType = bridge.DeviceType.filterWheel;
        break;
      case 'guider':
        bridgeType = bridge.DeviceType.guider;
        break;
      default:
        throw Exception('Unknown device type: $deviceType');
    }

    // Handle PHD2 device IDs specially
    if (deviceId.startsWith('phd2:')) {
      await bridge.NativeBridge.phd2Disconnect();
    } else {
      // Regular device disconnection
      await bridge.NativeBridge.disconnectDevice(bridgeType, deviceId);
    }
    print('[API] Device disconnected successfully');
  } catch (e, stackTrace) {
    debugPrint('[API] Error disconnecting device: $e');
    debugPrint('[API] Stack trace: $stackTrace');
    rethrow;
  }
}

/// Handler for /api/devices/connected endpoint
Future<List<Map<String, dynamic>>> _getConnectedDevicesHandler() async {
  print('[API] Getting connected devices...');
  final connectedDevices = await bridge.NativeBridge.getConnectedDevices();
  return connectedDevices
      .map((device) => {
            'id': device.id,
            'name': device.name,
            'type': device.deviceType.name,
            'driverType': device.driverType.name,
            'description': device.description,
            'driverVersion': device.driverVersion,
          })
      .toList();
}

/// Handler for /api/phd2/connect endpoint
Future<void> _phd2ConnectHandler({String? host, int? port}) async {
  print('[API] Connecting to PHD2: host=$host, port=$port');
  await bridge.NativeBridge.phd2Connect(host: host, port: port);
  print('[API] PHD2 connected successfully');
}

/// Handler for /api/phd2/disconnect endpoint
Future<void> _phd2DisconnectHandler() async {
  print('[API] Disconnecting from PHD2');
  await bridge.NativeBridge.phd2Disconnect();
  print('[API] PHD2 disconnected successfully');
}

// ============================================================================
// Camera Handlers
// ============================================================================

/// Handler for /api/camera/expose endpoint
Future<void> _cameraExposeHandler(Map<String, dynamic> params) async {
  print('[API] Starting camera exposure: $params');
  final deviceId = params['deviceId'] as String;
  final duration = (params['duration'] as num).toDouble();
  final gain = params['gain'] as int? ?? 0;
  final offset = params['offset'] as int? ?? 0;
  final binX = params['binX'] as int? ?? 1;
  final binY = params['binY'] as int? ?? 1;

  await bridge.NativeBridge.startExposure(
    deviceId: deviceId,
    durationSecs: duration,
    gain: gain,
    offset: offset,
    binX: binX,
    binY: binY,
  );
  print('[API] Exposure started');
}

/// Handler for /api/camera/abort endpoint
Future<void> _cameraAbortHandler(String deviceId) async {
  print('[API] Aborting camera exposure: $deviceId');
  await bridge.NativeBridge.cancelExposure(deviceId);
  print('[API] Exposure aborted');
}

/// Handler for /api/camera/cooling endpoint
Future<void> _cameraSetCoolingHandler(
    String deviceId, bool enabled, double? targetTemp) async {
  print(
      '[API] Setting camera cooling: $deviceId, enabled=$enabled, target=$targetTemp');
  await bridge.NativeBridge.setCameraCooler(deviceId, enabled, targetTemp);
  print('[API] Cooling set');
}

/// Handler for /api/camera/gain endpoint
Future<void> _cameraSetGainHandler(String deviceId, int gain) async {
  print('[API] Setting camera gain: $deviceId, gain=$gain');
  await bridge.NativeBridge.setCameraGain(deviceId, gain);
  print('[API] Gain set');
}

/// Handler for /api/camera/offset endpoint
Future<void> _cameraSetOffsetHandler(String deviceId, int offset) async {
  print('[API] Setting camera offset: $deviceId, offset=$offset');
  await bridge.NativeBridge.setCameraOffset(deviceId, offset);
  print('[API] Offset set');
}

/// Handler for /api/equipment/camera/status endpoint
Future<Map<String, dynamic>> _cameraStatusHandler(String deviceId) async {
  print('[API] Getting camera status: $deviceId');
  final status = await bridge.NativeBridge.getCameraStatus(deviceId);
  return {
    'connected': status.connected,
    'state': status.state.name,
    'coolerOn': status.coolerOn,
    'sensorTemp': status.sensorTemp,
    'targetTemp': status.targetTemp,
    'coolerPower': status.coolerPower,
    'gain': status.gain,
    'offset': status.offset,
  };
}

// ============================================================================
// Mount Handlers
// ============================================================================

/// Handler for /api/mount/slew endpoint
Future<void> _mountSlewHandler(String deviceId, double ra, double dec) async {
  print('[API] Slewing mount: $deviceId to RA=$ra, Dec=$dec');
  await bridge.NativeBridge.mountSlewToCoordinates(deviceId, ra, dec);
  print('[API] Slew started');
}

/// Handler for /api/mount/sync endpoint
Future<void> _mountSyncHandler(String deviceId, double ra, double dec) async {
  print('[API] Syncing mount: $deviceId to RA=$ra, Dec=$dec');
  await bridge.NativeBridge.mountSync(deviceId, ra, dec);
  print('[API] Mount synced');
}

/// Handler for /api/mount/park endpoint
Future<void> _mountParkHandler(String deviceId) async {
  print('[API] Parking mount: $deviceId');
  await bridge.NativeBridge.mountPark(deviceId);
  print('[API] Park started');
}

/// Handler for /api/mount/unpark endpoint
Future<void> _mountUnparkHandler(String deviceId) async {
  print('[API] Unparking mount: $deviceId');
  await bridge.NativeBridge.mountUnpark(deviceId);
  print('[API] Mount unparked');
}

/// Handler for /api/mount/tracking endpoint
Future<void> _mountSetTrackingHandler(String deviceId, bool enabled) async {
  print('[API] Setting mount tracking: $deviceId, enabled=$enabled');
  await bridge.NativeBridge.mountSetTracking(deviceId, enabled);
  print('[API] Tracking set');
}

/// Handler for /api/mount/abort endpoint
Future<void> _mountAbortHandler(String deviceId) async {
  print('[API] Aborting mount slew: $deviceId');
  await bridge.NativeBridge.mountAbort(deviceId);
  print('[API] Mount aborted');
}

/// Handler for /api/mount/status endpoint
Future<Map<String, dynamic>> _mountGetStatusHandler(String deviceId) async {
  print('[API] Getting mount status: $deviceId');
  final status = await bridge.NativeBridge.getMountStatus(deviceId);
  return {
    'connected': status.connected,
    'tracking': status.tracking,
    'slewing': status.slewing,
    'parked': status.parked,
    'rightAscension': status.rightAscension,
    'declination': status.declination,
    'altitude': status.altitude,
    'azimuth': status.azimuth,
    'sideOfPier': status.sideOfPier.name,
  };
}

// ============================================================================
// Focuser Handlers
// ============================================================================

/// Handler for /api/focuser/move-to endpoint
Future<void> _focuserMoveToHandler(String deviceId, int position) async {
  print('[API] Moving focuser: $deviceId to position=$position');
  await bridge.NativeBridge.focuserMoveTo(deviceId, position);
  print('[API] Focuser moving');
}

/// Handler for /api/focuser/move-relative endpoint
Future<void> _focuserMoveRelativeHandler(String deviceId, int delta) async {
  print('[API] Moving focuser relative: $deviceId by delta=$delta');
  await bridge.NativeBridge.focuserMoveRelative(deviceId, delta);
  print('[API] Focuser moving');
}

/// Handler for /api/focuser/halt endpoint
Future<void> _focuserHaltHandler(String deviceId) async {
  print('[API] Halting focuser: $deviceId');
  await bridge.NativeBridge.apiFocuserHalt(deviceId: deviceId);
  print('[API] Focuser halted');
}

/// Handler for /api/equipment/focuser/status endpoint
Future<Map<String, dynamic>> _focuserStatusHandler(String deviceId) async {
  print('[API] Getting focuser status: $deviceId');
  final status = await bridge.NativeBridge.getFocuserStatus(deviceId);
  return {
    'connected': status.connected,
    'position': status.position,
    'moving': status.moving,
    'isMoving': status.moving,
    'temperature': status.temperature,
    'maxPosition': status.maxPosition,
    'stepSize': status.stepSize,
    'isAbsolute': status.isAbsolute,
    'hasTemperature': status.hasTemperature,
  };
}

// ============================================================================
// Filter Wheel Handlers
// ============================================================================

/// Handler for /api/filter-wheel/position endpoint
Future<void> _filterWheelSetPositionHandler(
    String deviceId, int position) async {
  print('[API] Setting filter wheel position: $deviceId to position=$position');
  await bridge.NativeBridge.filterWheelSetPosition(deviceId, position);
  print('[API] Filter wheel moving');
}

/// Handler for /api/filter-wheel/names endpoint
Future<List<String>> _filterWheelGetNamesHandler(String deviceId) async {
  print('[API] Getting filter wheel names: $deviceId');
  final status = await bridge.NativeBridge.getFilterWheelStatus(deviceId);
  return status.filterNames;
}

/// Handler for /api/equipment/filter-wheel/status endpoint
Future<Map<String, dynamic>> _filterWheelStatusHandler(String deviceId) async {
  print('[API] Getting filter wheel status: $deviceId');
  final status = await bridge.NativeBridge.getFilterWheelStatus(deviceId);
  return {
    'connected': status.connected,
    'position': status.position,
    'isMoving': status.moving,
    'filterNames': status.filterNames,
  };
}

// ============================================================================
// Settings/Location Handlers
// ============================================================================

/// Handler for /api/settings/location endpoint (GET)
Future<Map<String, dynamic>?> _getLocationHandler() async {
  print('[API] Getting location');
  final loc = await bridge.NativeBridge.apiGetLocation();
  if (loc == null) return null;
  return {
    'latitude': loc.latitude,
    'longitude': loc.longitude,
    'elevation': loc.elevation,
  };
}

/// Handler for /api/settings/location endpoint (POST)
Future<void> _setLocationHandler(Map<String, dynamic>? location) async {
  print('[API] Setting location: $location');
  if (location != null) {
    final loc = bridge.ObserverLocation(
      latitude: (location['latitude'] as num).toDouble(),
      longitude: (location['longitude'] as num).toDouble(),
      elevation: (location['elevation'] as num?)?.toDouble() ?? 0.0,
    );
    await bridge.NativeBridge.apiSetLocation(location: loc);
  }
  print('[API] Location set');
}

// ============================================================================
// PHD2 Extended Handlers
// ============================================================================

/// Handler for /api/phd2/status endpoint
Future<Map<String, dynamic>> _phd2GetStatusHandler() async {
  print('[API] Getting PHD2 status');
  final status = await bridge.NativeBridge.phd2GetStatus();
  return {
    'connected': status.connected,
    'state': status.state,
    'rmsRa': status.rmsRa,
    'rmsDec': status.rmsDec,
    'rmsTotal': status.rmsTotal,
    'snr': status.snr,
    'starMass': status.starMass,
    'pixelScale': status.pixelScale,
  };
}

/// Handler for /api/phd2/start-guiding endpoint
Future<void> _phd2StartGuidingHandler(Map<String, dynamic> params) async {
  print('[API] Starting PHD2 guiding: $params');
  final settlePixels = (params['settlePixels'] as num?)?.toDouble() ?? 1.5;
  final settleTime = (params['settleTime'] as num?)?.toDouble() ?? 10.0;
  final settleTimeout = (params['settleTimeout'] as num?)?.toDouble() ?? 60.0;
  await bridge.NativeBridge.phd2StartGuiding(
    settlePixels: settlePixels,
    settleTime: settleTime,
    settleTimeout: settleTimeout,
  );
  print('[API] Guiding started');
}

/// Handler for /api/phd2/stop-guiding endpoint
Future<void> _phd2StopGuidingHandler() async {
  print('[API] Stopping PHD2 guiding');
  await bridge.NativeBridge.phd2StopGuiding();
  print('[API] Guiding stopped');
}

/// Handler for /api/phd2/dither endpoint
Future<void> _phd2DitherHandler(Map<String, dynamic> params) async {
  print('[API] Dithering PHD2: $params');
  final amount = (params['amount'] as num?)?.toDouble() ?? 5.0;
  final raOnly = params['raOnly'] as bool? ?? false;
  final settlePixels = (params['settlePixels'] as num?)?.toDouble() ?? 1.5;
  final settleTime = (params['settleTime'] as num?)?.toDouble() ?? 10.0;
  final settleTimeout = (params['settleTimeout'] as num?)?.toDouble() ?? 60.0;
  await bridge.NativeBridge.phd2Dither(
    amount: amount,
    raOnly: raOnly,
    settlePixels: settlePixels,
    settleTime: settleTime,
    settleTimeout: settleTimeout,
  );
  print('[API] Dither requested');
}

// ============================================================================
// Camera Extended Handlers
// ============================================================================

/// Handler for /api/camera/last-image endpoint
Future<Map<String, dynamic>?> _cameraGetLastImageHandler(
    String deviceId) async {
  print('[API] Getting last image for: $deviceId');
  final result = await bridge.NativeBridge.getLastImage(deviceId: deviceId);
  if (result == null) return null;
  return {
    'width': result.width,
    'height': result.height,
    'displayData': result.displayData,
    'histogram': result.histogram,
    'stats': {
      'min': result.stats.min,
      'max': result.stats.max,
      'mean': result.stats.mean,
      'median': result.stats.median,
      'stdDev': result.stats.stdDev,
      'hfr': result.stats.hfr,
      'starCount': result.stats.starCount,
    },
    'exposureTime': result.exposureTime,
    'timestamp': result.timestamp,
    'isColor': result.isColor,
  };
}

// ============================================================================
// Mount Extended Handlers
// ============================================================================

/// Handler for /api/mount/pulse-guide endpoint
Future<void> _mountPulseGuideHandler(
    String deviceId, String direction, int durationMs) async {
  print(
      '[API] Pulse guiding mount: $deviceId, direction=$direction, duration=$durationMs');
  await bridge.NativeBridge.mountPulseGuide(deviceId, direction, durationMs);
  print('[API] Pulse guide complete');
}

// ============================================================================
// Autofocus Handlers
// ============================================================================

/// Handler for /api/focuser/autofocus/start endpoint
Future<Map<String, dynamic>> _autofocusStartHandler(
    Map<String, dynamic> params) async {
  print('[API] Starting autofocus: $params');
  final deviceId = params['deviceId'] as String;
  final cameraId = params['cameraId'] as String;
  final exposureTime = (params['exposureTime'] as num).toDouble();
  final stepSize = params['stepSize'] as int;
  final stepsOut = params['stepsOut'] as int;
  final binning = params['binning'] as int? ?? 1;
  final method = params['method'] as String? ?? 'VCurve';

  final config = bridge.AutofocusConfigApi(
    exposureTime: exposureTime,
    stepSize: stepSize,
    stepsOut: stepsOut,
    method: method,
    binning: binning,
  );

  final result = await bridge.NativeBridge.apiRunAutofocus(
    deviceId: deviceId,
    cameraId: cameraId,
    config: config,
  );

  return {
    'bestPosition': result.bestPosition,
    'bestHfr': result.bestHfr,
    'focusData': result.focusData
        .map((dp) => {
              'position': dp.position,
              'hfr': dp.hfr,
              'fwhm': dp.fwhm,
              'starCount': dp.starCount,
            })
        .toList(),
    'method': result.method,
    'temperature': result.temperature,
    'timestamp': result.timestamp.toInt(),
    'curveFitQuality': result.curveFitQuality,
    'backlashApplied': result.backlashApplied,
  };
}

/// Handler for /api/focuser/autofocus/cancel endpoint
Future<void> _autofocusCancelHandler() async {
  print('[API] Cancelling autofocus');
  await bridge.NativeBridge.apiCancelAutofocus();
  print('[API] Autofocus cancelled');
}

// ============================================================================
// Filter Wheel Extended Handlers
// ============================================================================

/// Handler for /api/filter-wheel/set-by-name endpoint
Future<void> _filterWheelSetByNameHandler(String deviceId, String name) async {
  print('[API] Setting filter by name: $deviceId to $name');
  await bridge.NativeBridge.apiFilterwheelSetByName(
      deviceId: deviceId, name: name);
  print('[API] Filter set');
}

// ============================================================================
// Rotator Handlers
// ============================================================================

/// Handler for /api/rotator/move-to endpoint
Future<void> _rotatorMoveToHandler(String deviceId, double angle) async {
  print('[API] Moving rotator: $deviceId to angle=$angle');
  await bridge.NativeBridge.apiRotatorMoveTo(deviceId: deviceId, angle: angle);
  print('[API] Rotator moving');
}

/// Handler for /api/rotator/move-relative endpoint
Future<void> _rotatorMoveRelativeHandler(String deviceId, double delta) async {
  print('[API] Moving rotator relative: $deviceId by delta=$delta');
  await bridge.NativeBridge.apiRotatorMoveRelative(
      deviceId: deviceId, delta: delta);
  print('[API] Rotator moving');
}

/// Handler for /api/rotator/status endpoint
Future<Map<String, dynamic>> _rotatorGetStatusHandler(String deviceId) async {
  print('[API] Getting rotator status: $deviceId');
  final status =
      await bridge.NativeBridge.apiGetRotatorStatus(deviceId: deviceId);
  return {
    'connected': status.connected,
    'position': status.position,
    'moving': status.moving,
    'mechanicalPosition': status.mechanicalPosition,
    'isMoving': status.isMoving,
    'canReverse': status.canReverse,
  };
}

/// Handler for /api/rotator/halt endpoint
Future<void> _rotatorHaltHandler(String deviceId) async {
  print('[API] Halting rotator: $deviceId');
  await bridge.NativeBridge.apiRotatorHalt(deviceId: deviceId);
  print('[API] Rotator halted');
}

// ============================================================================
// Plate Solve Handler
// ============================================================================

/// Handler for /api/plate-solve endpoint
Future<Map<String, dynamic>> _plateSolveHandler(
    Map<String, dynamic> params) async {
  print('[API] Plate solving: $params');
  final imagePath = params['imagePath'] as String;
  final ra = (params['ra'] as num?)?.toDouble();
  final dec = (params['dec'] as num?)?.toDouble();
  final fov = (params['fov'] as num?)?.toDouble();

  bridge.PlateSolveResult result;
  if (ra != null && dec != null) {
    result = await bridge.NativeBridge.plateSolveNear(
      imagePath,
      ra,
      dec,
      fov ?? 2.0,
    );
  } else {
    result = await bridge.NativeBridge.plateSolveBlind(imagePath);
  }

  return {
    'success': result.success,
    'ra': result.ra,
    'dec': result.dec,
    'pixelScale': result.pixelScale,
    'rotation': result.rotation,
    'fieldWidth': result.fieldWidth,
    'fieldHeight': result.fieldHeight,
    'solveTimeSecs': result.solveTimeSecs,
    'error': result.error,
  };
}

// ============================================================================
// Sequencer Extended Handlers
// ============================================================================

/// Handler for /api/sequencer/pause endpoint
Future<void> _sequencerPauseHandler() async {
  print('[API] Pausing sequencer');
  await bridge.NativeBridge.sequencerPause();
  print('[API] Sequencer paused');
}

/// Handler for /api/sequencer/resume endpoint
Future<void> _sequencerResumeHandler() async {
  print('[API] Resuming sequencer');
  await bridge.NativeBridge.sequencerResume();
  print('[API] Sequencer resumed');
}

/// Handler for /api/sequencer/load endpoint
Future<void> _sequencerLoadHandler(String json) async {
  print('[API] Loading sequence');
  await bridge.NativeBridge.sequencerLoadJson(json);
  print('[API] Sequence loaded');
}

/// Handler for /api/sequencer/simulation endpoint
Future<void> _sequencerSetSimulationHandler(bool enabled) async {
  print('[API] Setting simulation mode: $enabled');
  await bridge.NativeBridge.sequencerSetSimulationMode(enabled);
  print('[API] Simulation mode set');
}

/// Handler for /api/sequencer/status endpoint
Future<Map<String, dynamic>> _sequencerGetStatusHandler() async {
  print('[API] Getting sequencer status');
  final status = await bridge.NativeBridge.sequencerGetStatus();
  return {
    'state': status.state,
    'currentNodeId': status.currentNodeId,
    'currentNodeName': status.currentNodeName,
    'progress': status.progress,
    'message': status.message,
  };
}

/// Handler for /api/sequencer/start and /api/sequences/start endpoints
Future<Map<String, dynamic>> _sequencerStartHandler(String? body) async {
  print('[API] Starting sequencer');
  await bridge.NativeBridge.sequencerStart();
  print('[API] Sequencer started');
  return {
    'status': 'started',
    'message': 'Sequence execution started successfully',
  };
}

/// Handler for /api/sequencer/stop and /api/sequences/stop endpoints
Future<Map<String, dynamic>> _sequencerStopHandler() async {
  print('[API] Stopping sequencer');
  await bridge.NativeBridge.sequencerStop();
  print('[API] Sequencer stopped');
  return {
    'status': 'stopped',
    'message': 'Sequence execution stopped successfully',
  };
}

// ============================================================================
// Profile Handlers
// ============================================================================

/// Handler for /api/profiles endpoint (GET)
Future<List<Map<String, dynamic>>> _getProfilesHandler() async {
  print('[API] Getting profiles');
  final profiles = await bridge.NativeBridge.apiGetProfiles();
  return profiles.map((p) => _profileToJson(p)).toList();
}

/// Handler for /api/profiles endpoint (POST)
Future<void> _saveProfileHandler(Map<String, dynamic> profileJson) async {
  print('[API] Saving profile: ${profileJson['id']}');
  final profile = _profileFromJson(profileJson);
  await bridge.NativeBridge.apiSaveProfile(profile: profile);
  print('[API] Profile saved');
}

/// Handler for /api/profiles/{id} endpoint (DELETE)
Future<void> _deleteProfileHandler(String profileId) async {
  print('[API] Deleting profile: $profileId');
  await bridge.NativeBridge.apiDeleteProfile(profileId: profileId);
  print('[API] Profile deleted');
}

/// Handler for /api/profiles/{id}/load endpoint
Future<void> _loadProfileHandler(String profileId) async {
  print('[API] Loading profile: $profileId');
  await bridge.NativeBridge.apiLoadProfile(profileId: profileId);
  print('[API] Profile loaded');
}

/// Handler for /api/profiles/active endpoint
Future<Map<String, dynamic>?> _getActiveProfileHandler() async {
  print('[API] Getting active profile');
  final profile = await bridge.NativeBridge.apiGetActiveProfile();
  return profile != null ? _profileToJson(profile) : null;
}

/// Helper to convert EquipmentProfile to JSON
Map<String, dynamic> _profileToJson(bridge.EquipmentProfile profile) {
  return {
    'id': profile.id,
    'name': profile.name,
    'cameraId': profile.cameraId,
    'mountId': profile.mountId,
    'focuserId': profile.focuserId,
    'filterWheelId': profile.filterWheelId,
    'guiderId': profile.guiderId,
    'rotatorId': profile.rotatorId,
    'domeId': profile.domeId,
    'weatherId': profile.weatherId,
    'telescopeFocalLength': profile.telescopeFocalLength,
    'telescopeAperture': profile.telescopeAperture,
  };
}

/// Helper to convert JSON to EquipmentProfile
bridge.EquipmentProfile _profileFromJson(Map<String, dynamic> json) {
  return bridge.EquipmentProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    cameraId: json['cameraId'] as String?,
    mountId: json['mountId'] as String?,
    focuserId: json['focuserId'] as String?,
    filterWheelId: json['filterWheelId'] as String?,
    guiderId: json['guiderId'] as String?,
    rotatorId: json['rotatorId'] as String?,
    domeId: json['domeId'] as String?,
    weatherId: json['weatherId'] as String?,
    telescopeFocalLength: (json['telescopeFocalLength'] as num).toDouble(),
    telescopeAperture: (json['telescopeAperture'] as num).toDouble(),
  );
}

// ============================================================================
// Settings Handlers
// ============================================================================

/// Handler for /api/settings endpoint (GET)
Future<Map<String, dynamic>> _getSettingsHandler() async {
  print('[API] Getting settings');
  final settings = await bridge.NativeBridge.apiGetSettings();
  return _settingsToJson(settings);
}

/// Handler for /api/settings endpoint (POST)
Future<void> _updateSettingsHandler(Map<String, dynamic> settingsJson) async {
  print('[API] Updating settings');
  final settings = _settingsFromJson(settingsJson);
  await bridge.NativeBridge.apiUpdateSettings(settings: settings);
  print('[API] Settings updated');
}

/// Helper to convert AppSettings to JSON
Map<String, dynamic> _settingsToJson(bridge.AppSettings settings) {
  return {
    'location': settings.location != null
        ? {
            'latitude': settings.location!.latitude,
            'longitude': settings.location!.longitude,
            'elevation': settings.location!.elevation,
          }
        : null,
    'theme': settings.theme,
    'language': settings.language,
    'autoConnect': settings.autoConnect,
  };
}

/// Helper to convert JSON to AppSettings
bridge.AppSettings _settingsFromJson(Map<String, dynamic> json) {
  final locationJson = json['location'] as Map<String, dynamic>?;
  return bridge.AppSettings(
    location: locationJson != null
        ? bridge.ObserverLocation(
            latitude: (locationJson['latitude'] as num).toDouble(),
            longitude: (locationJson['longitude'] as num).toDouble(),
            elevation: (locationJson['elevation'] as num).toDouble(),
          )
        : null,
    theme: json['theme'] as String,
    language: json['language'] as String,
    autoConnect: json['autoConnect'] as bool,
  );
}

// ============================================================================
// Polar Alignment Handlers
// ============================================================================

/// Handler for /api/polar-alignment/start endpoint
Future<void> _polarAlignmentStartHandler(Map<String, dynamic> params) async {
  print('[API] Starting polar alignment: $params');
  final exposureTime = (params['exposure_time'] as num).toDouble();
  final stepSize = (params['step_size'] as num).toDouble();
  final binning = params['binning'] as int;
  final isNorth = params['is_north'] as bool;
  final manualRotation = params['manual_rotation'] as bool;
  final rotateEast = params['rotate_east'] as bool;
  final gain = params['gain'] as int?;
  final offset = params['offset'] as int?;
  final solveTimeout = (params['solve_timeout'] as num?)?.toDouble();
  final startFromCurrent = params['start_from_current'] as bool?;

  await bridge.apiStartPolarAlignment(
    exposureTime: exposureTime,
    stepSize: stepSize,
    binning: binning,
    isNorth: isNorth,
    manualRotation: manualRotation,
    rotateEast: rotateEast,
    gain: gain,
    offset: offset,
    solveTimeout: solveTimeout,
    startFromCurrent: startFromCurrent,
  );
  print('[API] Polar alignment started');
}

/// Handler for /api/polar-alignment/stop endpoint
Future<void> _polarAlignmentStopHandler() async {
  print('[API] Stopping polar alignment');
  await bridge.apiStopPolarAlignment();
  print('[API] Polar alignment stopped');
}

// ============================================================================
// mDNS/Bonjour Advertising
// ============================================================================

/// Start mDNS/Bonjour service advertising for iOS discovery
/// Note: nsd package works best on mobile platforms (iOS/Android)
/// On desktop, this may fail gracefully - that's expected
Future<void> _startMdnsAdvertising(int port) async {
  // The nsd package is primarily designed for mobile platforms
  // On Windows/Linux/macOS desktop, mDNS advertising may not be fully supported
  // The UDP broadcast discovery is the primary method for desktop-to-mobile
  // This is a placeholder for future mobile-to-mobile discovery enhancement

  // For now, we rely on UDP broadcast which works cross-platform
  // Full mDNS implementation would require platform-specific setup:
  // - iOS: Requires NSBonjourServices in Info.plist
  // - Android: Requires NSD permissions
  // - Windows: Limited support via Bonjour for Windows

  debugPrint('[mDNS] mDNS advertising skipped - using UDP broadcast instead');
}

/// Get the local IP address for display
Future<String?> _getLocalIp() async {
  try {
    final interfaces = await NetworkInterface.list();
    for (final interface in interfaces) {
      // Skip loopback interfaces
      if (interface.name.contains('lo') ||
          interface.name.contains('Loopback')) {
        continue;
      }
      for (final addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
  } catch (e) {
    debugPrint('Error getting local IP: $e');
  }
  return null;
}

/// Check if the app should start minimized based on settings
/// This directly reads from the database before Riverpod is initialized
Future<bool> _shouldStartMinimized(ProviderContainer container) async {
  try {
    final dao = container.read(settingsDaoProvider);
    final value = await dao.getSetting('start_minimized');
    return value == 'true';
  } catch (e) {
    debugPrint('Error checking start minimized setting: $e');
    return false;
  }
}
