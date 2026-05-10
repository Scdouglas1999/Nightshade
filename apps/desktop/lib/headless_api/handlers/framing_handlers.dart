import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for framing assistant and centering operations
class FramingHandlers {
  final ProviderContainer container;

  FramingHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'FramingHandlers');

  // ===========================================================================
  // Slew To Target
  // ===========================================================================

  Future<Response> handleSlewToTarget(Request request) async {
    _logInfo('[API] POST /api/framing/slew-to-target');
    final payload = await readJsonObject(request);

    final ra = requireDouble(payload, 'ra');
    final dec = requireDouble(payload, 'dec');

    final backend = container.read(backendProvider);

    // Get connected mount
    final connectedDevices = await backend.getConnectedDevices();
    final mount = connectedDevices
        .where((d) => d.deviceType == DeviceType.mount)
        .firstOrNull;

    if (mount == null) {
      return jsonBadRequest({'error': 'No mount connected'});
    }

    await backend.mountSlewToCoordinates(mount.id, ra, dec);

    return jsonOk({
      'status': 'slewing',
      'targetRa': ra,
      'targetDec': dec,
    });
  }

  // ===========================================================================
  // Center On Target
  // ===========================================================================

  Future<Response> handleCenterOnTarget(Request request) async {
    _logInfo('[API] POST /api/framing/center-on-target');
    final payload = await readJsonObject(request);

    final ra = requireDouble(payload, 'ra');
    final dec = requireDouble(payload, 'dec');
    final maxIterations = optionalInt(payload, 'maxIterations') ?? 5;
    final toleranceArcsec =
        optionalDouble(payload, 'toleranceArcsec') ?? 30.0;
    final exposureTime = optionalDouble(payload, 'exposureTime') ?? 3.0;
    final binning = optionalInt(payload, 'binning') ?? 2;
    final gain = optionalInt(payload, 'gain') ?? 100;
    final syncMount = optionalBool(payload, 'syncMount') ?? false;

    final centeringService = container.read(centeringServiceProvider);

    // Create centering config
    final config = CenteringConfig(
      maxIterations: maxIterations,
      toleranceArcsec: toleranceArcsec,
      exposureTime: exposureTime,
      binning: binning,
      gain: gain,
      syncMount: syncMount,
    );

    // Get plate solver config from settings
    final database = container.read(databaseProvider);
    final solverName =
        await database.settingsDao.getSetting('plate_solve_solver') ?? 'ASTAP';
    final solverPath =
        await database.settingsDao.getSetting('plate_solve_path') ?? '';
    final timeoutStr =
        await database.settingsDao.getSetting('plate_solve_timeout') ?? '60';
    final solverType = PlateSolverType.values.firstWhere(
      (t) => t.name.toLowerCase() == solverName.toLowerCase(),
      orElse: () => PlateSolverType.astap,
    );
    final solverConfig = PlateSolverConfig(
      type: solverType,
      executablePath: solverPath,
      timeoutSeconds: int.tryParse(timeoutStr) ?? 60,
    );

    // Run centering
    final result = await centeringService.centerOnTarget(
      targetRa: ra,
      targetDec: dec,
      solverConfig: solverConfig,
      config: config,
    );

    return jsonOk({
      'success': result.success,
      'iterations': result.iterations,
      'finalOffsetArcsec': result.finalOffsetArcsec,
      'errorMessage': result.errorMessage,
      'iterationHistory': result.iterationHistory
          .map((i) => {
                'iterationNumber': i.iterationNumber,
                'solvedRa': i.solvedRa,
                'solvedDec': i.solvedDec,
                'targetRa': i.targetRa,
                'targetDec': i.targetDec,
                'offsetArcsec': i.offsetArcsec,
                'offsetArcmin': i.offsetArcmin,
                'plateSolveSuccess': i.plateSolveSuccess,
                'errorMessage': i.errorMessage,
                'timestamp': i.timestamp.millisecondsSinceEpoch,
              })
          .toList(),
    });
  }

  // ===========================================================================
  // Sync Mount
  // ===========================================================================

  Future<Response> handleSyncMount(Request request) async {
    _logInfo('[API] POST /api/framing/sync');
    final payload = await readJsonObject(request);

    final ra = requireDouble(payload, 'ra');
    final dec = requireDouble(payload, 'dec');

    final backend = container.read(backendProvider);

    // Get connected mount
    final connectedDevices = await backend.getConnectedDevices();
    final mount = connectedDevices
        .where((d) => d.deviceType == DeviceType.mount)
        .firstOrNull;

    if (mount == null) {
      return jsonBadRequest({'error': 'No mount connected'});
    }

    await backend.mountSync(mount.id, ra, dec);

    return jsonOk({
      'status': 'synced',
      'ra': ra,
      'dec': dec,
    });
  }

  // ===========================================================================
  // Get Current Position
  // ===========================================================================

  Future<Response> handleGetCurrentPosition(Request request) async {
    _logInfo('[API] GET /api/framing/current-position');
    final backend = container.read(backendProvider);

    // Get connected mount
    final connectedDevices = await backend.getConnectedDevices();
    final mount = connectedDevices
        .where((d) => d.deviceType == DeviceType.mount)
        .firstOrNull;

    if (mount == null) {
      return jsonBadRequest({'error': 'No mount connected'});
    }

    final status = await backend.getMountStatus(mount.id);

    return jsonOk({
      'ra': status.rightAscension,
      'dec': status.declination,
      'altitude': status.altitude,
      'azimuth': status.azimuth,
      'tracking': status.tracking,
      'sideOfPier': status.sideOfPier.name,
      'slewing': status.slewing,
      'atPark': status.parked,
      'atHome': status.atHome,
      'trackingRate': status.trackingRate.name,
    });
  }

  // ===========================================================================
  // Rotate To Angle
  // ===========================================================================

  Future<Response> handleRotateTo(Request request) async {
    _logInfo('[API] POST /api/framing/rotate-to');
    final payload = await readJsonObject(request);

    final angle = requireDouble(payload, 'angle');

    final backend = container.read(backendProvider);

    // Get connected rotator
    final connectedDevices = await backend.getConnectedDevices();
    final rotator = connectedDevices
        .where((d) => d.deviceType == DeviceType.rotator)
        .firstOrNull;

    if (rotator == null) {
      return jsonBadRequest({'error': 'No rotator connected'});
    }

    await backend.rotatorMoveTo(rotator.id, angle);

    return jsonOk({
      'status': 'rotating',
      'targetAngle': angle,
    });
  }

  // ===========================================================================
  // Abort Slew
  // ===========================================================================

  Future<Response> handleAbortSlew(Request request) async {
    _logInfo('[API] POST /api/framing/abort-slew');
    final backend = container.read(backendProvider);

    // Get connected mount
    final connectedDevices = await backend.getConnectedDevices();
    final mount = connectedDevices
        .where((d) => d.deviceType == DeviceType.mount)
        .firstOrNull;

    if (mount == null) {
      return jsonBadRequest({'error': 'No mount connected'});
    }

    await backend.mountAbort(mount.id);

    return jsonOk({'status': 'aborted'});
  }

  // ===========================================================================
  // Park Mount
  // ===========================================================================

  Future<Response> handleParkMount(Request request) async {
    _logInfo('[API] POST /api/framing/park');
    final backend = container.read(backendProvider);

    // Get connected mount
    final connectedDevices = await backend.getConnectedDevices();
    final mount = connectedDevices
        .where((d) => d.deviceType == DeviceType.mount)
        .firstOrNull;

    if (mount == null) {
      return jsonBadRequest({'error': 'No mount connected'});
    }

    await backend.mountPark(mount.id);

    return jsonOk({'status': 'parking'});
  }

  // ===========================================================================
  // Unpark Mount
  // ===========================================================================

  Future<Response> handleUnparkMount(Request request) async {
    _logInfo('[API] POST /api/framing/unpark');
    final backend = container.read(backendProvider);

    // Get connected mount
    final connectedDevices = await backend.getConnectedDevices();
    final mount = connectedDevices
        .where((d) => d.deviceType == DeviceType.mount)
        .firstOrNull;

    if (mount == null) {
      return jsonBadRequest({'error': 'No mount connected'});
    }

    await backend.mountUnpark(mount.id);

    return jsonOk({'status': 'unparking'});
  }
}
