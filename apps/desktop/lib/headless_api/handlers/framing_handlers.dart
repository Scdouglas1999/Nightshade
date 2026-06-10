import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../job_manager.dart';
import '../response_helpers.dart';
import '../validation.dart';
import 'device_handlers.dart' show requestPrefersLegacyBlocking;

/// Handlers for framing assistant and centering operations
class FramingHandlers {
  final ProviderContainer container;

  /// P1-2 / P1-3: optional job manager. When wired, center-on-target
  /// returns `{jobId, status: queued}` immediately and the multi-step
  /// slew/solve/adjust loop runs in the background, with each iteration
  /// reported as a progress update on the same job.
  final JobManager? jobManager;

  FramingHandlers(this.container, {this.jobManager});

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

    final backend = container.read(deviceBackendProvider);

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

    Map<String, Object?> resultToJson(CenteringResult result) => {
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
        };

    Future<CenteringResult> runCentering() async {
      final centeringService = container.read(centeringServiceProvider);
      final config = CenteringConfig(
        maxIterations: maxIterations,
        toleranceArcsec: toleranceArcsec,
        exposureTime: exposureTime,
        binning: binning,
        gain: gain,
        syncMount: syncMount,
      );

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
      return centeringService.centerOnTarget(
        targetRa: ra,
        targetDec: dec,
        solverConfig: solverConfig,
        config: config,
      );
    }

    final mgr = jobManager;
    final preferLegacy = requestPrefersLegacyBlocking(request);
    if (mgr != null && !preferLegacy) {
      final job = mgr.start(
        operation: 'framing.center-on-target',
        deviceId: null,
        work: (sink, cancellation) async {
          sink.update(0.0, 'Centering on RA=$ra DEC=$dec');
          final workFuture = runCentering();
          final raced = await Future.any<dynamic>([
            workFuture,
            cancellation.whenCancelled.then((_) => _CenteringCancelled.instance),
          ]);
          if (raced is _CenteringCancelled) {
            throw const JobCancelledException(
              'Center-on-target cancellation requested by client',
            );
          }
          final result = raced as CenteringResult;
          return resultToJson(result);
        },
      );
      return jsonOk({
        'jobId': job.jobId,
        'status': job.state.wireName,
        'operation': job.operation,
      });
    }

    final result = await runCentering();
    return jsonOk(resultToJson(result));
  }

  // ===========================================================================
  // Sync Mount
  // ===========================================================================

  Future<Response> handleSyncMount(Request request) async {
    _logInfo('[API] POST /api/framing/sync');
    final payload = await readJsonObject(request);

    final ra = requireDouble(payload, 'ra');
    final dec = requireDouble(payload, 'dec');

    final backend = container.read(deviceBackendProvider);

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
    final backend = container.read(deviceBackendProvider);

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

    final backend = container.read(deviceBackendProvider);

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
    final backend = container.read(deviceBackendProvider);

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
    final backend = container.read(deviceBackendProvider);

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
    final backend = container.read(deviceBackendProvider);

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

  // ===========================================================================
  // Set Framing Target (remote handoff)
  // ===========================================================================

  /// POST /api/framing/set-target
  ///
  /// Updates the host framing assistant when a remote companion sends a target
  /// from Plan Tonight / planetarium so the desktop framing screen matches.
  Future<Response> handleSetTarget(Request request) async {
    _logInfo('[API] POST /api/framing/set-target');
    final payload = await readJsonObject(request);
    final ra = requireDouble(payload, 'ra');
    final dec = requireDouble(payload, 'dec');
    final name = requireString(payload, 'name');

    container.read(framingProvider.notifier).setTargetCoordinates(
          ra,
          dec,
          name: name,
        );

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.framing,
      action: HostMutationAction.updated,
      extra: {'ra': ra, 'dec': dec, 'name': name},
    );
    return jsonOk({
      'status': 'ok',
      'ra': ra,
      'dec': dec,
      'name': name,
    });
  }

  // ===========================================================================
  // Save framing on a target row
  // ===========================================================================

  /// POST /api/framing/save
  ///
  /// Persists RA/Dec/position angle on an existing target or creates a new
  /// catalog row when [targetId] is omitted.
  Future<Response> handleSaveFraming(Request request) async {
    _logInfo('[API] POST /api/framing/save');
    final payload = await readJsonObject(request);
    final ra = requireDouble(payload, 'ra');
    final dec = requireDouble(payload, 'dec');
    final positionAngle = requireDouble(payload, 'positionAngle');
    final name = requireString(payload, 'name');
    final targetId = optionalInt(payload, 'targetId');

    final database = container.read(databaseProvider);

    if (targetId != null) {
      final existing = await database.targetsDao.getTargetById(targetId);
      if (existing == null) {
        return jsonNotFound({'error': 'Target not found: $targetId'});
      }
      final updated = existing.copyWith(
        name: name,
        ra: ra,
        dec: dec,
        positionAngle: Value(positionAngle),
      );
      await database.targetsDao.updateTarget(updated);
      publishHostMutationFromContainer(
        container,
        entityType: HostMutationEntity.target,
        action: HostMutationAction.updated,
        entityId: targetId.toString(),
        extra: {
          'name': name,
          'ra': ra,
          'dec': dec,
          'positionAngle': positionAngle,
        },
      );
      return jsonOk({
        'status': 'updated',
        'id': targetId,
        'name': name,
        'ra': ra,
        'dec': dec,
        'positionAngle': positionAngle,
      });
    }

    final companion = TargetsCompanion(
      name: Value(name),
      ra: Value(ra),
      dec: Value(dec),
      positionAngle: Value(positionAngle),
      minAltitude: const Value(30.0),
    );
    final id = await database.targetsDao.createTarget(companion);
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.target,
      action: HostMutationAction.created,
      entityId: id.toString(),
      extra: {
        'name': name,
        'ra': ra,
        'dec': dec,
        'positionAngle': positionAngle,
      },
    );
    return jsonOk({
      'status': 'created',
      'id': id,
      'name': name,
      'ra': ra,
      'dec': dec,
      'positionAngle': positionAngle,
    });
  }
}

/// Sentinel marking the cancellation branch of a Future.any race against
/// the multi-step centering loop. Library-private — see the analogous
/// sentinels in imaging_handlers / device_handlers.
class _CenteringCancelled {
  const _CenteringCancelled._();
  static const _CenteringCancelled instance = _CenteringCancelled._();
}
