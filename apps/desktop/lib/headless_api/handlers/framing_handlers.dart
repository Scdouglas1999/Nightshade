import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

/// Handlers for framing assistant and centering operations
class FramingHandlers {
  final ProviderContainer container;

  FramingHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'FramingHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'FramingHandlers');

  // ===========================================================================
  // Slew To Target
  // ===========================================================================

  Future<Response> handleSlewToTarget(Request request) async {
    _logInfo('[API] POST /api/framing/slew-to-target');
    try {
      final payload = jsonDecode(await request.readAsString());

      final ra = (payload['ra'] as num).toDouble();
      final dec = (payload['dec'] as num).toDouble();

      final backend = container.read(backendProvider);

      // Get connected mount
      final connectedDevices = await backend.getConnectedDevices();
      final mount = connectedDevices
          .where((d) => d.deviceType == DeviceType.mount)
          .firstOrNull;

      if (mount == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No mount connected"}),
          headers: {'content-type': 'application/json'},
        );
      }

      await backend.mountSlewToCoordinates(mount.id, ra, dec);

      return Response.ok(
        jsonEncode({
          "status": "slewing",
          "targetRa": ra,
          "targetDec": dec,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Slew to target error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Center On Target
  // ===========================================================================

  Future<Response> handleCenterOnTarget(Request request) async {
    _logInfo('[API] POST /api/framing/center-on-target');
    try {
      final payload = jsonDecode(await request.readAsString());

      final ra = (payload['ra'] as num).toDouble();
      final dec = (payload['dec'] as num).toDouble();
      final maxIterations = payload['maxIterations'] as int? ?? 5;
      final toleranceArcsec =
          (payload['toleranceArcsec'] as num?)?.toDouble() ?? 30.0;
      final exposureTime = (payload['exposureTime'] as num?)?.toDouble() ?? 3.0;
      final binning = payload['binning'] as int? ?? 2;
      final gain = payload['gain'] as int? ?? 100;
      final syncMount = payload['syncMount'] as bool? ?? false;

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
          await database.settingsDao.getSetting('plate_solve_solver') ??
              'ASTAP';
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

      return Response.ok(
        jsonEncode({
          "success": result.success,
          "iterations": result.iterations,
          "finalOffsetArcsec": result.finalOffsetArcsec,
          "errorMessage": result.errorMessage,
          "iterationHistory": result.iterationHistory
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
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Center on target error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Sync Mount
  // ===========================================================================

  Future<Response> handleSyncMount(Request request) async {
    _logInfo('[API] POST /api/framing/sync');
    try {
      final payload = jsonDecode(await request.readAsString());

      final ra = (payload['ra'] as num).toDouble();
      final dec = (payload['dec'] as num).toDouble();

      final backend = container.read(backendProvider);

      // Get connected mount
      final connectedDevices = await backend.getConnectedDevices();
      final mount = connectedDevices
          .where((d) => d.deviceType == DeviceType.mount)
          .firstOrNull;

      if (mount == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No mount connected"}),
          headers: {'content-type': 'application/json'},
        );
      }

      await backend.mountSync(mount.id, ra, dec);

      return Response.ok(
        jsonEncode({
          "status": "synced",
          "ra": ra,
          "dec": dec,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Sync mount error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Get Current Position
  // ===========================================================================

  Future<Response> handleGetCurrentPosition(Request request) async {
    _logInfo('[API] GET /api/framing/current-position');
    try {
      final backend = container.read(backendProvider);

      // Get connected mount
      final connectedDevices = await backend.getConnectedDevices();
      final mount = connectedDevices
          .where((d) => d.deviceType == DeviceType.mount)
          .firstOrNull;

      if (mount == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No mount connected"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final status = await backend.getMountStatus(mount.id);

      return Response.ok(
        jsonEncode({
          "ra": status.rightAscension,
          "dec": status.declination,
          "altitude": status.altitude,
          "azimuth": status.azimuth,
          "tracking": status.tracking,
          "sideOfPier": status.sideOfPier.name,
          "slewing": status.slewing,
          "atPark": status.parked,
          "atHome": status.atHome,
          "trackingRate": status.trackingRate.name,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Get current position error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Rotate To Angle
  // ===========================================================================

  Future<Response> handleRotateTo(Request request) async {
    _logInfo('[API] POST /api/framing/rotate-to');
    try {
      final payload = jsonDecode(await request.readAsString());

      final angle = (payload['angle'] as num).toDouble();

      final backend = container.read(backendProvider);

      // Get connected rotator
      final connectedDevices = await backend.getConnectedDevices();
      final rotator = connectedDevices
          .where((d) => d.deviceType == DeviceType.rotator)
          .firstOrNull;

      if (rotator == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No rotator connected"}),
          headers: {'content-type': 'application/json'},
        );
      }

      await backend.rotatorMoveTo(rotator.id, angle);

      return Response.ok(
        jsonEncode({
          "status": "rotating",
          "targetAngle": angle,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Rotate to error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Abort Slew
  // ===========================================================================

  Future<Response> handleAbortSlew(Request request) async {
    _logInfo('[API] POST /api/framing/abort-slew');
    try {
      final backend = container.read(backendProvider);

      // Get connected mount
      final connectedDevices = await backend.getConnectedDevices();
      final mount = connectedDevices
          .where((d) => d.deviceType == DeviceType.mount)
          .firstOrNull;

      if (mount == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No mount connected"}),
          headers: {'content-type': 'application/json'},
        );
      }

      await backend.mountAbort(mount.id);

      return Response.ok(
        jsonEncode({"status": "aborted"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Abort slew error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Park Mount
  // ===========================================================================

  Future<Response> handleParkMount(Request request) async {
    _logInfo('[API] POST /api/framing/park');
    try {
      final backend = container.read(backendProvider);

      // Get connected mount
      final connectedDevices = await backend.getConnectedDevices();
      final mount = connectedDevices
          .where((d) => d.deviceType == DeviceType.mount)
          .firstOrNull;

      if (mount == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No mount connected"}),
          headers: {'content-type': 'application/json'},
        );
      }

      await backend.mountPark(mount.id);

      return Response.ok(
        jsonEncode({"status": "parking"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Park mount error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Unpark Mount
  // ===========================================================================

  Future<Response> handleUnparkMount(Request request) async {
    _logInfo('[API] POST /api/framing/unpark');
    try {
      final backend = container.read(backendProvider);

      // Get connected mount
      final connectedDevices = await backend.getConnectedDevices();
      final mount = connectedDevices
          .where((d) => d.deviceType == DeviceType.mount)
          .firstOrNull;

      if (mount == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "No mount connected"}),
          headers: {'content-type': 'application/json'},
        );
      }

      await backend.mountUnpark(mount.id);

      return Response.ok(
        jsonEncode({"status": "unparking"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Unpark mount error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
