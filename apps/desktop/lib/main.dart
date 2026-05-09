import 'dart:async';
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
import 'main_headless.dart' as headless;

// Current app version - must match version.yaml
const String appVersion = '2.5.0';
const int appBuildNumber = 5;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check for headless mode flag
  final isHeadless = args.contains('--headless') ||
      Platform.environment['NIGHTSHADE_HEADLESS'] == '1';

  if (isHeadless) {
    // Delegate to the modern headless entry point (main_headless.dart)
    headless.main(args);
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
  _startBackgroundServices(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NightshadeApp(isDesktop: true),
    ),
  );
}

/// Start background services for mobile/remote access
void _startBackgroundServices(ProviderContainer container) {
  // Start in background - don't block UI
  Future.microtask(() async {
    NightshadeWebServer? webServer;
    StreamSubscription? collaborationSubscription;
    LiveCollaborationSessionManager? collaborationManager;
    AppSettings? queuedWebServerSettings;
    bool isApplyingWebServerSettings = false;
    final dashboardDir = _findDashboardDir();
    final pairingDatabase = PairingDatabase();
    final tokenManager = TokenManager(pairingDatabase);

    Future<void> stopWebServer(
      AppSettings settings, {
      String error = '',
    }) async {
      await collaborationSubscription?.cancel();
      collaborationSubscription = null;
      collaborationManager?.dispose();
      collaborationManager = null;

      final runningServer = webServer;
      webServer = null;

      if (runningServer != null) {
        await runningServer.stop();
      }

      container.read(webServerStateProvider.notifier).setStopped(
            configuredPort: settings.webServerPort,
            actualPort: settings.webServerPort,
            bindLocalOnly: false,
            requiresAuthentication: true,
            dashboardAvailable: dashboardDir != null,
            lastError: error,
          );
    }

    Future<void> applyWebServerSettings(AppSettings settings) async {
      await stopWebServer(settings);

      if (!settings.webServerEnabled) {
        debugPrint('[MAIN] Remote access is disabled in settings');
        return;
      }

      final nextCollaborationManager = LiveCollaborationSessionManager();
      final nextServer = NightshadeWebServer(
        port: settings.webServerPort,
        webRoot: dashboardDir?.path,
        bindLocalOnly: false,
        tokenManager: tokenManager,
        requireAuthentication: true,
        devicesHandler: _getDevicesHandler,
        deviceConnectHandler: _connectDeviceHandler,
        deviceDisconnectHandler: _disconnectDeviceHandler,
        connectedDevicesHandler: _getConnectedDevicesHandler,
        phd2ConnectHandler: _phd2ConnectHandler,
        phd2DisconnectHandler: _phd2DisconnectHandler,
      );
      nextServer.liveCollaborationSessionManager = nextCollaborationManager;
      nextServer.setEventStream(container.read(backendProvider).eventStream);

      // Wire up additional handlers using setters
      nextServer.cameraExposeHandler = _cameraExposeHandler;
      nextServer.cameraAbortHandler = _cameraAbortHandler;
      nextServer.cameraSetCoolingHandler = _cameraSetCoolingHandler;
      nextServer.cameraSetGainHandler = _cameraSetGainHandler;
      nextServer.cameraSetOffsetHandler = _cameraSetOffsetHandler;
      nextServer.cameraStatusHandler = _cameraStatusHandler;

      nextServer.mountSlewHandler = _mountSlewHandler;
      nextServer.mountSyncHandler = _mountSyncHandler;
      nextServer.mountParkHandler = _mountParkHandler;
      nextServer.mountUnparkHandler = _mountUnparkHandler;
      nextServer.mountSetTrackingHandler = _mountSetTrackingHandler;
      nextServer.mountAbortHandler = _mountAbortHandler;
      nextServer.mountGetStatusHandler = _mountGetStatusHandler;
      nextServer.mountStatusHandler = _mountGetStatusHandler;

      nextServer.focuserMoveToHandler = _focuserMoveToHandler;
      nextServer.focuserMoveRelativeHandler = _focuserMoveRelativeHandler;
      nextServer.focuserHaltHandler = _focuserHaltHandler;
      nextServer.focuserStatusHandler = _focuserStatusHandler;

      nextServer.filterWheelSetPositionHandler = _filterWheelSetPositionHandler;
      nextServer.filterWheelGetNamesHandler = _filterWheelGetNamesHandler;
      nextServer.filterWheelStatusHandler = _filterWheelStatusHandler;

      nextServer.getLocationHandler = _getLocationHandler;
      nextServer.setLocationHandler = _setLocationHandler;

      nextServer.phd2GetStatusHandler = _phd2GetStatusHandler;
      nextServer.phd2StartGuidingHandler = _phd2StartGuidingHandler;
      nextServer.phd2StopGuidingHandler = _phd2StopGuidingHandler;
      nextServer.phd2DitherHandler = _phd2DitherHandler;
      nextServer.guiderStartGuidingHandler = _guiderStartGuidingHandler;
      nextServer.guiderStopGuidingHandler = _guiderStopGuidingHandler;
      nextServer.guiderDitherHandler = _guiderDitherHandler;
      nextServer.guiderLoopHandler = _guiderLoopHandler;
      nextServer.guiderFindStarHandler = _guiderFindStarHandler;
      nextServer.guiderSetLockPositionHandler = _guiderSetLockPositionHandler;
      nextServer.guiderGetLockPositionHandler = _guiderGetLockPositionHandler;
      nextServer.guiderDeselectStarHandler = _guiderDeselectStarHandler;
      nextServer.guiderGetStarImageHandler = _guiderGetStarImageHandler;

      // Extended handlers
      nextServer.cameraGetLastImageHandler = _cameraGetLastImageHandler;
      nextServer.mountPulseGuideHandler = _mountPulseGuideHandler;
      nextServer.autofocusStartHandler = _autofocusStartHandler;
      nextServer.autofocusCancelHandler = _autofocusCancelHandler;
      nextServer.filterWheelSetByNameHandler = _filterWheelSetByNameHandler;
      nextServer.rotatorMoveToHandler = _rotatorMoveToHandler;
      nextServer.rotatorMoveRelativeHandler = _rotatorMoveRelativeHandler;
      nextServer.rotatorGetStatusHandler = _rotatorGetStatusHandler;
      nextServer.rotatorHaltHandler = _rotatorHaltHandler;
      nextServer.plateSolveHandler = _plateSolveHandler;
      nextServer.sequencerStartHandler = _sequencerStartHandler;
      nextServer.sequencerStopHandler = _sequencerStopHandler;
      nextServer.sequencerPauseHandler = _sequencerPauseHandler;
      nextServer.sequencerResumeHandler = _sequencerResumeHandler;
      nextServer.sequencerLoadHandler = _sequencerLoadHandler;
      nextServer.sequencerSetSimulationHandler = _sequencerSetSimulationHandler;
      nextServer.sequencerStatusHandler = _sequencerGetStatusHandler;
      nextServer.getProfilesHandler = _getProfilesHandler;
      nextServer.saveProfileHandler = _saveProfileHandler;
      nextServer.deleteProfileHandler = _deleteProfileHandler;
      nextServer.loadProfileHandler = _loadProfileHandler;
      nextServer.getActiveProfileHandler = _getActiveProfileHandler;
      nextServer.getSettingsHandler = _getSettingsHandler;
      nextServer.updateSettingsHandler = _updateSettingsHandler;
      nextServer.polarAlignmentStartHandler = _polarAlignmentStartHandler;
      nextServer.polarAlignmentStopHandler = _polarAlignmentStopHandler;

      try {
        debugPrint(
            '[MAIN] Starting authenticated desktop remote access server...');
        await nextServer.start();
        webServer = nextServer;
        collaborationManager = nextCollaborationManager;
        debugPrint(
          '[MAIN] Remote access started on port ${nextServer.actualPort}'
          ' (dashboard: ${dashboardDir?.path ?? 'unavailable'})',
        );

        container.read(webServerStateProvider.notifier).setRunning(
              isRunning: true,
              actualPort: nextServer.actualPort,
              configuredPort: settings.webServerPort,
              bindLocalOnly: false,
              requiresAuthentication: true,
              dashboardAvailable: dashboardDir != null,
            );

        await collaborationSubscription?.cancel();
        collaborationSubscription =
            nextCollaborationManager.stream.listen((collabState) {
          container
              .read(webServerStateProvider.notifier)
              .setActiveViewers(collabState.viewers.length);
        });

        try {
          final pushService = container.read(pushNotificationServiceProvider);
          nextServer.setPushNotificationStream(
            pushService.notifications
                .map((notification) => notification.toJson()),
          );
          debugPrint('[MAIN] Push notifications wired to web server');
        } catch (e) {
          debugPrint('[MAIN] Push notification setup failed: $e');
        }
      } catch (e) {
        debugPrint('[MAIN] Remote access failed to start: $e');
        await nextServer.stop();
        nextCollaborationManager.dispose();
        await stopWebServer(
          settings,
          error: 'Remote access failed to start: $e',
        );
      }
    }

    Future<void> scheduleWebServerUpdate(AppSettings settings) async {
      queuedWebServerSettings = settings;
      if (isApplyingWebServerSettings) {
        return;
      }

      isApplyingWebServerSettings = true;
      try {
        while (queuedWebServerSettings != null) {
          final nextSettings = queuedWebServerSettings!;
          queuedWebServerSettings = null;
          await applyWebServerSettings(nextSettings);
        }
      } finally {
        isApplyingWebServerSettings = false;
      }
    }

    try {
      AppSettings? lastAppliedSettings;
      container.listen<AsyncValue<AppSettings>>(
        appSettingsProvider,
        (_, next) {
          final settings = next.valueOrNull;
          if (settings == null) {
            return;
          }

          final shouldRestart = lastAppliedSettings == null ||
              lastAppliedSettings!.webServerEnabled !=
                  settings.webServerEnabled ||
              lastAppliedSettings!.webServerPort != settings.webServerPort;

          if (!shouldRestart) {
            return;
          }

          lastAppliedSettings = settings;
          unawaited(scheduleWebServerUpdate(settings));
        },
        fireImmediately: true,
      );

      // Start LAN push update receiver
      try {
        var isReceivingLanPush = false;
        final pushSecret = await _getOrCreatePushSecret();
        final lanPushReceiver = LanPushReceiver(
          currentVersion: appVersion,
          currentBuildNumber: appBuildNumber,
          pushSecret: pushSecret,
        );
        lanPushReceiver.onUpdateReceived = (manifest, stagingPath) {
          isReceivingLanPush = false;
          debugPrint(
              '[MAIN] Update received via LAN push: ${manifest.version}');
          LanPushNotifier.notifyUpdateReceived(manifest, stagingPath);
        };
        lanPushReceiver.onProgress = (received, total, progress, message) {
          isReceivingLanPush = total > 0 && received < total;
          debugPrint(
              '[MAIN] LAN push progress: ${(progress * 100).toStringAsFixed(1)}% - $message');
          LanPushNotifier.notifyProgress(received, total, progress, message);
        };
        lanPushReceiver.onError = (error) {
          isReceivingLanPush = false;
          debugPrint('[MAIN] LAN push error: $error');
          LanPushNotifier.notifyError(error);
        };
        await lanPushReceiver.startServer();
        debugPrint('[MAIN] LAN push receiver started on port 45680');

        // Start responding to update push discovery
        await UpdatePushDiscovery.startResponding(
          name: 'Nightshade',
          version: appVersion,
          buildNumber: appBuildNumber,
          isReceivingCallback: () => isReceivingLanPush,
        );
        debugPrint('[MAIN] Update push discovery responder started');
      } catch (e) {
        debugPrint('[MAIN] LAN push receiver failed: $e');
      }
    } catch (e) {
      debugPrint('[MAIN] Background services failed to initialize: $e');
    }

    debugPrint(
      '[MAIN] Desktop GUI remote access is authenticated for non-local clients.',
    );
  });
}

Directory? _findDashboardDir() {
  final exeDir = path.dirname(Platform.resolvedExecutable);
  final releasePath =
      path.join(exeDir, 'data', 'flutter_assets', 'web_dashboard');
  final releaseDir = Directory(releasePath);
  if (releaseDir.existsSync()) {
    return releaseDir;
  }

  final sameDirPath = path.join(exeDir, 'web_dashboard');
  final sameDir = Directory(sameDirPath);
  if (sameDir.existsSync()) {
    return sameDir;
  }

  var current = exeDir;
  for (var i = 0; i < 10; i++) {
    final candidate = Directory(path.join(current, 'web_dashboard'));
    if (candidate.existsSync()) {
      return candidate;
    }

    final parent = path.dirname(current);
    if (parent == current) {
      break;
    }
    current = parent;
  }

  final cwdDir = Directory(path.join(Directory.current.path, 'web_dashboard'));
  if (cwdDir.existsSync()) {
    return cwdDir;
  }

  final sourceTreeDir = Directory(
    path.join(Directory.current.path, 'apps', 'desktop', 'web_dashboard'),
  );
  if (sourceTreeDir.existsSync()) {
    return sourceTreeDir;
  }

  return null;
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
  try {
    // Discover ALL device types in parallel for faster discovery
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
  debugPrint('[API] Connecting device: $deviceType / $deviceId');
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
    debugPrint('[API] Device connected successfully');
  } catch (e, stackTrace) {
    debugPrint('[API] Error connecting device: $e');
    debugPrint('[API] Stack trace: $stackTrace');
    rethrow;
  }
}

/// Handler for /api/devices/disconnect endpoint
Future<void> _disconnectDeviceHandler(
    String deviceType, String deviceId) async {
  debugPrint('[API] Disconnecting device: $deviceType / $deviceId');
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
    debugPrint('[API] Device disconnected successfully');
  } catch (e, stackTrace) {
    debugPrint('[API] Error disconnecting device: $e');
    debugPrint('[API] Stack trace: $stackTrace');
    rethrow;
  }
}

/// Handler for /api/devices/connected endpoint
Future<List<Map<String, dynamic>>> _getConnectedDevicesHandler() async {
  debugPrint('[API] Getting connected devices...');
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
  debugPrint('[API] Connecting to PHD2: host=$host, port=$port');
  await bridge.NativeBridge.phd2Connect(host: host, port: port);
  debugPrint('[API] PHD2 connected successfully');
}

/// Handler for /api/phd2/disconnect endpoint
Future<void> _phd2DisconnectHandler() async {
  debugPrint('[API] Disconnecting from PHD2');
  await bridge.NativeBridge.phd2Disconnect();
  debugPrint('[API] PHD2 disconnected successfully');
}

// ============================================================================
// Camera Handlers
// ============================================================================

/// Handler for /api/camera/expose endpoint
Future<void> _cameraExposeHandler(Map<String, dynamic> params) async {
  debugPrint('[API] Starting camera exposure: $params');
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
  debugPrint('[API] Exposure started');
}

/// Handler for /api/camera/abort endpoint
Future<void> _cameraAbortHandler(String deviceId) async {
  debugPrint('[API] Aborting camera exposure: $deviceId');
  await bridge.NativeBridge.cancelExposure(deviceId);
  debugPrint('[API] Exposure aborted');
}

/// Handler for /api/camera/cooling endpoint
Future<void> _cameraSetCoolingHandler(
    String deviceId, bool enabled, double? targetTemp) async {
  debugPrint(
      '[API] Setting camera cooling: $deviceId, enabled=$enabled, target=$targetTemp');
  await bridge.NativeBridge.setCameraCooler(deviceId, enabled, targetTemp);
  debugPrint('[API] Cooling set');
}

/// Handler for /api/camera/gain endpoint
Future<void> _cameraSetGainHandler(String deviceId, int gain) async {
  debugPrint('[API] Setting camera gain: $deviceId, gain=$gain');
  await bridge.NativeBridge.setCameraGain(deviceId, gain);
  debugPrint('[API] Gain set');
}

/// Handler for /api/camera/offset endpoint
Future<void> _cameraSetOffsetHandler(String deviceId, int offset) async {
  debugPrint('[API] Setting camera offset: $deviceId, offset=$offset');
  await bridge.NativeBridge.setCameraOffset(deviceId, offset);
  debugPrint('[API] Offset set');
}

/// Handler for /api/equipment/camera/status endpoint
Future<Map<String, dynamic>> _cameraStatusHandler(String deviceId) async {
  debugPrint('[API] Getting camera status: $deviceId');
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
  debugPrint('[API] Slewing mount: $deviceId to RA=$ra, Dec=$dec');
  await bridge.NativeBridge.mountSlewToCoordinates(deviceId, ra, dec);
  debugPrint('[API] Slew started');
}

/// Handler for /api/mount/sync endpoint
Future<void> _mountSyncHandler(String deviceId, double ra, double dec) async {
  debugPrint('[API] Syncing mount: $deviceId to RA=$ra, Dec=$dec');
  await bridge.NativeBridge.mountSync(deviceId, ra, dec);
  debugPrint('[API] Mount synced');
}

/// Handler for /api/mount/park endpoint
Future<void> _mountParkHandler(String deviceId) async {
  debugPrint('[API] Parking mount: $deviceId');
  await bridge.NativeBridge.mountPark(deviceId);
  debugPrint('[API] Park started');
}

/// Handler for /api/mount/unpark endpoint
Future<void> _mountUnparkHandler(String deviceId) async {
  debugPrint('[API] Unparking mount: $deviceId');
  await bridge.NativeBridge.mountUnpark(deviceId);
  debugPrint('[API] Mount unparked');
}

/// Handler for /api/mount/tracking endpoint
Future<void> _mountSetTrackingHandler(String deviceId, bool enabled) async {
  debugPrint('[API] Setting mount tracking: $deviceId, enabled=$enabled');
  await bridge.NativeBridge.mountSetTracking(deviceId, enabled);
  debugPrint('[API] Tracking set');
}

/// Handler for /api/mount/abort endpoint
Future<void> _mountAbortHandler(String deviceId) async {
  debugPrint('[API] Aborting mount slew: $deviceId');
  await bridge.NativeBridge.mountAbort(deviceId);
  debugPrint('[API] Mount aborted');
}

/// Handler for /api/mount/status endpoint
Future<Map<String, dynamic>> _mountGetStatusHandler(String deviceId) async {
  debugPrint('[API] Getting mount status: $deviceId');
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
  debugPrint('[API] Moving focuser: $deviceId to position=$position');
  await bridge.NativeBridge.focuserMoveTo(deviceId, position);
  debugPrint('[API] Focuser moving');
}

/// Handler for /api/focuser/move-relative endpoint
Future<void> _focuserMoveRelativeHandler(String deviceId, int delta) async {
  debugPrint('[API] Moving focuser relative: $deviceId by delta=$delta');
  await bridge.NativeBridge.focuserMoveRelative(deviceId, delta);
  debugPrint('[API] Focuser moving');
}

/// Handler for /api/focuser/halt endpoint
Future<void> _focuserHaltHandler(String deviceId) async {
  debugPrint('[API] Halting focuser: $deviceId');
  await bridge.NativeBridge.apiFocuserHalt(deviceId: deviceId);
  debugPrint('[API] Focuser halted');
}

/// Handler for /api/equipment/focuser/status endpoint
Future<Map<String, dynamic>> _focuserStatusHandler(String deviceId) async {
  debugPrint('[API] Getting focuser status: $deviceId');
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
  debugPrint(
      '[API] Setting filter wheel position: $deviceId to position=$position');
  await bridge.NativeBridge.filterWheelSetPosition(deviceId, position);
  debugPrint('[API] Filter wheel moving');
}

/// Handler for /api/filter-wheel/names endpoint
Future<List<String>> _filterWheelGetNamesHandler(String deviceId) async {
  debugPrint('[API] Getting filter wheel names: $deviceId');
  final status = await bridge.NativeBridge.getFilterWheelStatus(deviceId);
  return status.filterNames;
}

/// Handler for /api/equipment/filter-wheel/status endpoint
Future<Map<String, dynamic>> _filterWheelStatusHandler(String deviceId) async {
  debugPrint('[API] Getting filter wheel status: $deviceId');
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
  debugPrint('[API] Getting location');
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
  debugPrint('[API] Setting location: $location');
  if (location != null) {
    final loc = bridge.ObserverLocation(
      latitude: (location['latitude'] as num).toDouble(),
      longitude: (location['longitude'] as num).toDouble(),
      elevation: (location['elevation'] as num?)?.toDouble() ?? 0.0,
    );
    await bridge.NativeBridge.apiSetLocation(location: loc);
  }
  debugPrint('[API] Location set');
}

// ============================================================================
// PHD2 Extended Handlers
// ============================================================================

/// Handler for /api/phd2/status endpoint
Future<Map<String, dynamic>> _phd2GetStatusHandler() async {
  debugPrint('[API] Getting PHD2 status');
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
  debugPrint('[API] Starting PHD2 guiding: $params');
  final settlePixels = (params['settlePixels'] as num?)?.toDouble() ?? 1.5;
  final settleTime = (params['settleTime'] as num?)?.toDouble() ?? 10.0;
  final settleTimeout = (params['settleTimeout'] as num?)?.toDouble() ?? 60.0;
  await bridge.NativeBridge.phd2StartGuiding(
    settlePixels: settlePixels,
    settleTime: settleTime,
    settleTimeout: settleTimeout,
  );
  debugPrint('[API] Guiding started');
}

/// Handler for /api/phd2/stop-guiding endpoint
Future<void> _phd2StopGuidingHandler() async {
  debugPrint('[API] Stopping PHD2 guiding');
  await bridge.NativeBridge.phd2StopGuiding();
  debugPrint('[API] Guiding stopped');
}

/// Handler for /api/phd2/dither endpoint
Future<void> _phd2DitherHandler(Map<String, dynamic> params) async {
  debugPrint('[API] Dithering PHD2: $params');
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
  debugPrint('[API] Dither requested');
}

Future<void> _guiderStartGuidingHandler(Map<String, dynamic> params) async {
  debugPrint('[API] Starting guider: $params');
  final deviceId = params['deviceId'] as String;
  final settlePixels = (params['settlePixels'] as num?)?.toDouble() ?? 1.0;
  final settleTime = (params['settleTime'] as num?)?.toDouble() ?? 10.0;
  final settleTimeout = (params['settleTimeout'] as num?)?.toDouble() ?? 60.0;
  await bridge.NativeBridge.guiderStartGuiding(
    deviceId: deviceId,
    settlePixels: settlePixels,
    settleTime: settleTime,
    settleTimeout: settleTimeout,
  );
  debugPrint('[API] Guider started: $deviceId');
}

Future<void> _guiderStopGuidingHandler(String deviceId) async {
  debugPrint('[API] Stopping guider: $deviceId');
  await bridge.NativeBridge.guiderStop(deviceId: deviceId);
  debugPrint('[API] Guider stopped: $deviceId');
}

Future<void> _guiderDitherHandler(Map<String, dynamic> params) async {
  debugPrint('[API] Dithering guider: $params');
  final deviceId = params['deviceId'] as String;
  final amount = (params['amount'] as num?)?.toDouble() ?? 5.0;
  final raOnly = params['raOnly'] as bool? ?? false;
  final settlePixels = (params['settlePixels'] as num?)?.toDouble() ?? 1.0;
  final settleTime = (params['settleTime'] as num?)?.toDouble() ?? 10.0;
  final settleTimeout = (params['settleTimeout'] as num?)?.toDouble() ?? 60.0;
  await bridge.NativeBridge.guiderDither(
    deviceId: deviceId,
    amount: amount,
    raOnly: raOnly,
    settlePixels: settlePixels,
    settleTime: settleTime,
    settleTimeout: settleTimeout,
  );
  debugPrint('[API] Guider dither requested: $deviceId');
}

Future<void> _guiderLoopHandler(String deviceId) async {
  debugPrint('[API] Starting guider loop: $deviceId');
  await bridge.NativeBridge.guiderLoop(deviceId: deviceId);
  debugPrint('[API] Guider loop started: $deviceId');
}

Future<Map<String, dynamic>> _guiderFindStarHandler(String deviceId) async {
  debugPrint('[API] Finding guide star: $deviceId');
  final (x, y) = await bridge.NativeBridge.guiderFindStar(deviceId: deviceId);
  return {
    'deviceId': deviceId,
    'x': x,
    'y': y,
  };
}

Future<void> _guiderSetLockPositionHandler(
  String deviceId,
  double x,
  double y,
  bool exact,
) async {
  debugPrint(
      '[API] Setting guider lock position: $deviceId @ ($x, $y), exact=$exact');
  await bridge.NativeBridge.guiderSetLockPosition(
    deviceId: deviceId,
    x: x,
    y: y,
    exact: exact,
  );
  debugPrint('[API] Guider lock position updated: $deviceId');
}

Future<Map<String, dynamic>> _guiderGetLockPositionHandler(
  String deviceId,
) async {
  debugPrint('[API] Getting guider lock position: $deviceId');
  final (x, y) =
      await bridge.NativeBridge.guiderGetLockPosition(deviceId: deviceId);
  return {
    'deviceId': deviceId,
    'x': x,
    'y': y,
  };
}

Future<void> _guiderDeselectStarHandler(String deviceId) async {
  debugPrint('[API] Deselecting guide star: $deviceId');
  await bridge.NativeBridge.guiderDeselectStar(deviceId: deviceId);
  debugPrint('[API] Guide star deselected: $deviceId');
}

Future<Map<String, dynamic>> _guiderGetStarImageHandler(
  String deviceId, {
  int size = 50,
}) async {
  debugPrint('[API] Getting guider star image: $deviceId size=$size');
  final image = await bridge.NativeBridge.guiderGetStarImage(
      deviceId: deviceId, size: size);
  return {
    'deviceId': deviceId,
    'frame': image.frame,
    'width': image.width,
    'height': image.height,
    'starX': image.starX,
    'starY': image.starY,
    'pixels': image.pixels,
  };
}

// ============================================================================
// Camera Extended Handlers
// ============================================================================

/// Handler for /api/camera/last-image endpoint
Future<Map<String, dynamic>?> _cameraGetLastImageHandler(
    String deviceId) async {
  debugPrint('[API] Getting last image for: $deviceId');
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
  debugPrint(
      '[API] Pulse guiding mount: $deviceId, direction=$direction, duration=$durationMs');
  await bridge.NativeBridge.mountPulseGuide(deviceId, direction, durationMs);
  debugPrint('[API] Pulse guide complete');
}

// ============================================================================
// Autofocus Handlers
// ============================================================================

/// Handler for /api/focuser/autofocus/start endpoint
Future<Map<String, dynamic>> _autofocusStartHandler(
    Map<String, dynamic> params) async {
  debugPrint('[API] Starting autofocus: $params');
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
  debugPrint('[API] Cancelling autofocus');
  await bridge.NativeBridge.apiCancelAutofocus();
  debugPrint('[API] Autofocus cancelled');
}

// ============================================================================
// Filter Wheel Extended Handlers
// ============================================================================

/// Handler for /api/filter-wheel/set-by-name endpoint
Future<void> _filterWheelSetByNameHandler(String deviceId, String name) async {
  debugPrint('[API] Setting filter by name: $deviceId to $name');
  await bridge.NativeBridge.apiFilterwheelSetByName(
      deviceId: deviceId, name: name);
  debugPrint('[API] Filter set');
}

// ============================================================================
// Rotator Handlers
// ============================================================================

/// Handler for /api/rotator/move-to endpoint
Future<void> _rotatorMoveToHandler(String deviceId, double angle) async {
  debugPrint('[API] Moving rotator: $deviceId to angle=$angle');
  await bridge.NativeBridge.apiRotatorMoveTo(deviceId: deviceId, angle: angle);
  debugPrint('[API] Rotator moving');
}

/// Handler for /api/rotator/move-relative endpoint
Future<void> _rotatorMoveRelativeHandler(String deviceId, double delta) async {
  debugPrint('[API] Moving rotator relative: $deviceId by delta=$delta');
  await bridge.NativeBridge.apiRotatorMoveRelative(
      deviceId: deviceId, delta: delta);
  debugPrint('[API] Rotator moving');
}

/// Handler for /api/rotator/status endpoint
Future<Map<String, dynamic>> _rotatorGetStatusHandler(String deviceId) async {
  debugPrint('[API] Getting rotator status: $deviceId');
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
  debugPrint('[API] Halting rotator: $deviceId');
  await bridge.NativeBridge.apiRotatorHalt(deviceId: deviceId);
  debugPrint('[API] Rotator halted');
}

// ============================================================================
// Plate Solve Handler
// ============================================================================

/// Handler for /api/plate-solve endpoint
Future<Map<String, dynamic>> _plateSolveHandler(
    Map<String, dynamic> params) async {
  debugPrint('[API] Plate solving: $params');
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
  debugPrint('[API] Pausing sequencer');
  await bridge.NativeBridge.sequencerPause();
  debugPrint('[API] Sequencer paused');
}

/// Handler for /api/sequencer/resume endpoint
Future<void> _sequencerResumeHandler() async {
  debugPrint('[API] Resuming sequencer');
  await bridge.NativeBridge.sequencerResume();
  debugPrint('[API] Sequencer resumed');
}

/// Handler for /api/sequencer/load endpoint
Future<void> _sequencerLoadHandler(String json) async {
  debugPrint('[API] Loading sequence');
  await bridge.NativeBridge.sequencerLoadJson(json);
  debugPrint('[API] Sequence loaded');
}

/// Handler for /api/sequencer/simulation endpoint
Future<void> _sequencerSetSimulationHandler(bool enabled) async {
  debugPrint('[API] Setting simulation mode: $enabled');
  await bridge.NativeBridge.sequencerSetSimulationMode(enabled);
  debugPrint('[API] Simulation mode set');
}

/// Handler for /api/sequencer/status endpoint
Future<Map<String, dynamic>> _sequencerGetStatusHandler() async {
  debugPrint('[API] Getting sequencer status');
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
  debugPrint('[API] Starting sequencer');
  await bridge.NativeBridge.sequencerStart();
  debugPrint('[API] Sequencer started');
  return {
    'status': 'started',
    'message': 'Sequence execution started successfully',
  };
}

/// Handler for /api/sequencer/stop and /api/sequences/stop endpoints
Future<Map<String, dynamic>> _sequencerStopHandler() async {
  debugPrint('[API] Stopping sequencer');
  await bridge.NativeBridge.sequencerStop();
  debugPrint('[API] Sequencer stopped');
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
  debugPrint('[API] Getting profiles');
  final profiles = await bridge.NativeBridge.apiGetProfiles();
  return profiles.map((p) => _profileToJson(p)).toList();
}

/// Handler for /api/profiles endpoint (POST)
Future<void> _saveProfileHandler(Map<String, dynamic> profileJson) async {
  debugPrint('[API] Saving profile: ${profileJson['id']}');
  final profile = _profileFromJson(profileJson);
  await bridge.NativeBridge.apiSaveProfile(profile: profile);
  debugPrint('[API] Profile saved');
}

/// Handler for /api/profiles/{id} endpoint (DELETE)
Future<void> _deleteProfileHandler(String profileId) async {
  debugPrint('[API] Deleting profile: $profileId');
  await bridge.NativeBridge.apiDeleteProfile(profileId: profileId);
  debugPrint('[API] Profile deleted');
}

/// Handler for /api/profiles/{id}/load endpoint
Future<void> _loadProfileHandler(String profileId) async {
  debugPrint('[API] Loading profile: $profileId');
  await bridge.NativeBridge.apiLoadProfile(profileId: profileId);
  debugPrint('[API] Profile loaded');
}

/// Handler for /api/profiles/active endpoint
Future<Map<String, dynamic>?> _getActiveProfileHandler() async {
  debugPrint('[API] Getting active profile');
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
  debugPrint('[API] Getting settings');
  final settings = await bridge.NativeBridge.apiGetSettings();
  return _settingsToJson(settings);
}

/// Handler for /api/settings endpoint (POST)
Future<void> _updateSettingsHandler(Map<String, dynamic> settingsJson) async {
  debugPrint('[API] Updating settings');
  final settings = _settingsFromJson(settingsJson);
  await bridge.NativeBridge.apiUpdateSettings(settings: settings);
  debugPrint('[API] Settings updated');
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
  debugPrint('[API] Starting polar alignment: $params');
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
  debugPrint('[API] Polar alignment started');
}

/// Handler for /api/polar-alignment/stop endpoint
Future<void> _polarAlignmentStopHandler() async {
  debugPrint('[API] Stopping polar alignment');
  await bridge.apiStopPolarAlignment();
  debugPrint('[API] Polar alignment stopped');
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

/// Load or generate the LAN push authentication secret.
/// The secret is persisted in the app data directory so it survives restarts.
/// The same secret must be configured on the push tool (dev machine) to authenticate.
Future<String> _getOrCreatePushSecret() async {
  final appData = await getApplicationSupportDirectory();
  final secretFile = File(path.join(appData.path, 'push_secret.txt'));

  if (await secretFile.exists()) {
    final secret = (await secretFile.readAsString()).trim();
    if (secret.isNotEmpty) {
      return secret;
    }
  }

  // Generate a new secret and persist it
  final secret = LanPushReceiver.generatePushSecret();
  await secretFile.parent.create(recursive: true);
  await secretFile.writeAsString(secret);
  debugPrint('[MAIN] Generated new LAN push secret. '
      'Configure this on the push tool: ${secretFile.path}');
  return secret;
}
