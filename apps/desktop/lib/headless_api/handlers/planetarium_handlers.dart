import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for planetarium endpoints supporting remote client rendering.
///
/// The planetarium renders locally on mobile/tablet clients but needs data from
/// the server for mount position, FOV configuration, catalog searches, and
/// target interactions (slew, sync, center).
class PlanetariumHandlers {
  final ProviderContainer container;

  PlanetariumHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'PlanetariumHandlers');

  // ===========================================================================
  // Mount Position (for FOV overlay on remote planetarium)
  // ===========================================================================

  /// GET /api/planetarium/mount-position
  /// Returns current mount RA/Dec/rotation for FOV display on client planetarium.
  Future<Response> handleGetMountPosition(Request request) async {
    _logInfo('[API] GET /api/planetarium/mount-position');
    final backend = container.read(deviceBackendProvider);

    // Get connected mount
    final connectedDevices = await backend.getConnectedDevices();
    final mount = connectedDevices
        .where((d) => d.deviceType == DeviceType.mount)
        .firstOrNull;

    if (mount == null) {
      return jsonOk({
        'connected': false,
        'ra': null,
        'dec': null,
        'altitude': null,
        'azimuth': null,
        'tracking': false,
        'slewing': false,
        'parked': false,
        'sideOfPier': null,
      });
    }

    final status = await backend.getMountStatus(mount.id);

    // Get rotator angle if connected. Why a localized try/catch: rotator
    // angle is optional metadata for the FOV overlay; the rest of the mount
    // status must still be returned even if the rotator driver fails.
    double? rotatorAngle;
    final rotator = connectedDevices
        .where((d) => d.deviceType == DeviceType.rotator)
        .firstOrNull;
    if (rotator != null) {
      try {
        rotatorAngle = await backend.rotatorGetAngle(rotator.id);
      } on Object catch (e, stackTrace) {
        // Why: rotator angle is optional metadata for the FOV overlay. A
        // rotator driver failure here must not blank out the mount status
        // the caller actually requested, so we surface `rotatorAngle: null`
        // and log the detail for operator triage.
        _logger.warning(
          'rotatorGetAngle failed for ${rotator.id}: $e',
          source: 'PlanetariumHandlers',
          fields: {'stack': stackTrace.toString()},
        );
      }
    }

    return jsonOk({
      'connected': true,
      'ra': status.rightAscension,
      'dec': status.declination,
      'altitude': status.altitude,
      'azimuth': status.azimuth,
      'tracking': status.tracking,
      'slewing': status.slewing,
      'parked': status.parked,
      'atHome': status.atHome,
      'sideOfPier': status.sideOfPier.name,
      'trackingRate': status.trackingRate.name,
      'rotatorAngle': rotatorAngle,
    });
  }

  // ===========================================================================
  // FOV Configuration (camera/optical setup for FOV calculation)
  // ===========================================================================

  /// GET /api/planetarium/fov-config
  /// Returns camera sensor size, pixel size, focal length, reducer for FOV calculation.
  Future<Response> handleGetFovConfig(Request request) async {
    _logInfo('[API] GET /api/planetarium/fov-config');
    // A-12: legitimately multi-role — needs ProfileSettings (getActiveProfile)
    // plus Device (getConnectedDevices, getCameraCapabilities). Stays on the
    // aggregate backend marker rather than carrying two role refs through one
    // 20-line handler.
    final backend = container.read(backendProvider);

    // Get active equipment profile
    final profile = await backend.getActiveProfile();

    // Get connected camera for sensor info
    final connectedDevices = await backend.getConnectedDevices();
    final camera = connectedDevices
        .where((d) => d.deviceType == DeviceType.camera)
        .firstOrNull;

    CameraCapabilities? cameraCapabilities;
    if (camera != null) {
      cameraCapabilities = await backend.getCameraCapabilities(camera.id);
    }

    // Calculate FOV if we have enough data
    double? fovWidthDegrees;
    double? fovHeightDegrees;
    double? imageScaleArcsecPerPixel;

    final focalLength = profile?.effectiveFocalLength ?? 0;
    final pixelSize = profile?.pixelSize ?? cameraCapabilities?.pixelSizeX;

    if (focalLength > 0 && cameraCapabilities != null) {
      final sensorWidthMm =
          (cameraCapabilities.maxWidth * (cameraCapabilities.pixelSizeX ?? 0)) /
          1000.0;
      final sensorHeightMm =
          (cameraCapabilities.maxHeight *
              (cameraCapabilities.pixelSizeY ??
                  cameraCapabilities.pixelSizeX ??
                  0)) /
          1000.0;

      if (sensorWidthMm > 0 && sensorHeightMm > 0) {
        // FOV = 2 * atan(sensor_size / (2 * focal_length)) * (180/pi)
        fovWidthDegrees =
            2 * (180 / math.pi) * math.atan(sensorWidthMm / (2 * focalLength));
        fovHeightDegrees =
            2 * (180 / math.pi) * math.atan(sensorHeightMm / (2 * focalLength));
      }

      if (pixelSize != null && pixelSize > 0) {
        // Image scale = (pixel_size_microns / focal_length_mm) * 206.265
        imageScaleArcsecPerPixel = (pixelSize / focalLength) * 206.265;
      }
    }

    return jsonOk({
      'profileId': profile?.id,
      'profileName': profile?.name,
      'focalLength': focalLength,
      'aperture': profile?.effectiveAperture ?? 0,
      'focalRatio': profile?.computedFocalRatio,
      'pixelSizeMicrons': pixelSize,
      'sensorWidthPixels': cameraCapabilities?.maxWidth,
      'sensorHeightPixels': cameraCapabilities?.maxHeight,
      'sensorWidthMm': cameraCapabilities != null && pixelSize != null
          ? (cameraCapabilities.maxWidth * pixelSize) / 1000.0
          : null,
      'sensorHeightMm': cameraCapabilities != null && pixelSize != null
          ? (cameraCapabilities.maxHeight *
                    (cameraCapabilities.pixelSizeY ?? pixelSize)) /
                1000.0
          : null,
      'fovWidthDegrees': fovWidthDegrees,
      'fovHeightDegrees': fovHeightDegrees,
      'imageScaleArcsecPerPixel': imageScaleArcsecPerPixel,
      'cameraConnected': camera != null,
      'cameraName': camera?.name,
    });
  }

  // ===========================================================================
  // Target Interactions
  // ===========================================================================

  /// POST /api/planetarium/slew-to
  /// Slew mount to RA/Dec coordinates.
  Future<Response> handleSlewTo(Request request) async {
    _logInfo('[API] POST /api/planetarium/slew-to');
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

    return jsonOk({'status': 'slewing', 'targetRa': ra, 'targetDec': dec});
  }

  /// POST /api/planetarium/center-on
  /// Center on RA/Dec with plate solving (iterative centering).
  Future<Response> handleCenterOn(Request request) async {
    _logInfo('[API] POST /api/planetarium/center-on');
    final payload = await readJsonObject(request);
    final ra = requireDouble(payload, 'ra');
    final dec = requireDouble(payload, 'dec');
    final maxIterations = optionalInt(payload, 'maxIterations') ?? 5;
    final toleranceArcsec = optionalDouble(payload, 'toleranceArcsec') ?? 30.0;
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
          .map(
            (i) => {
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
            },
          )
          .toList(),
    });
  }

  /// POST /api/planetarium/sync-to
  /// Sync mount to RA/Dec coordinates.
  Future<Response> handleSyncTo(Request request) async {
    _logInfo('[API] POST /api/planetarium/sync-to');
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

    return jsonOk({'status': 'synced', 'ra': ra, 'dec': dec});
  }

  // ===========================================================================
  // Catalog Data
  // ===========================================================================

  /// GET /api/planetarium/catalog/search?query=M31
  /// Search objects by name across star and DSO catalogs.
  Future<Response> handleCatalogSearch(Request request) async {
    _logInfo('[API] GET /api/planetarium/catalog/search');
    final query = request.url.queryParameters['query'] ?? '';
    final limitStr = request.url.queryParameters['limit'] ?? '50';
    final limit = int.tryParse(limitStr) ?? 50;

    if (query.isEmpty) {
      return jsonOk({'results': []});
    }

    // Use CatalogManager for searching
    final results = await CatalogManager.instance.search(query);

    // Convert to response format
    final responseResults = results
        .take(limit)
        .map(
          (r) => {
            'name': r.name,
            'catalogId': r.catalogId,
            // `ra` is degrees (catalog-native, kept for back-compat); `raHours`
            // is the canonical RA field used across the rest of the API —
            // mount/target/scheduler all speak hours. New clients should prefer
            // `raHours` so RA is consistently in hours on every surface. (B14)
            'ra': r.ra,
            'raHours': r.ra / 15.0,
            'dec': r.dec,
            'type': r.type,
            'magnitude': r.magnitude,
            'constellation': r.constellation,
            'size': r.size,
          },
        )
        .toList();

    return jsonOk({'results': responseResults});
  }

  /// GET /api/planetarium/catalog/region?ra=X&dec=Y&radius=Z
  /// Get objects in a region (cone search).
  Future<Response> handleCatalogRegion(Request request) async {
    _logInfo('[API] GET /api/planetarium/catalog/region');
    final raStr = request.url.queryParameters['ra'];
    final decStr = request.url.queryParameters['dec'];
    final radiusStr = request.url.queryParameters['radius'];
    final maxMagStr = request.url.queryParameters['maxMagnitude'];
    final typeFilter = request.url.queryParameters['type'];

    if (raStr == null || decStr == null || radiusStr == null) {
      return jsonBadRequest({
        'error': 'Missing required parameters: ra, dec, radius (in degrees)',
      });
    }

    final ra = double.tryParse(raStr);
    final dec = double.tryParse(decStr);
    final radius = double.tryParse(radiusStr);
    final maxMagnitude = maxMagStr != null ? double.tryParse(maxMagStr) : null;

    if (ra == null || dec == null || radius == null) {
      return jsonBadRequest({'error': 'Invalid numeric parameters'});
    }

    final results = <Map<String, dynamic>>[];

    // Search DSOs in region
    if (typeFilter == null || typeFilter == 'dso') {
      final dsos = await CatalogManager.instance.searchDsoNearby(
        ra: ra,
        dec: dec,
        radiusDegrees: radius,
        maxMagnitude: maxMagnitude,
      );

      for (final dso in dsos) {
        results.add({
          'name': dso.displayName,
          'catalogId': dso.name,
          'ra': dso.ra,
          'raHours': dso.ra / 15.0, // canonical hours field; see B14
          'dec': dso.dec,
          'type': dso.typeDescription,
          'magnitude': dso.magnitude,
          'constellation': dso.constellation,
          'size': dso.sizeString,
          'objectType': 'dso',
        });
      }
    }

    // Search stars in region
    if (typeFilter == null || typeFilter == 'star') {
      final stars = await CatalogManager.instance.searchStarsNearby(
        ra: ra,
        dec: dec,
        radiusDegrees: radius,
        maxMagnitude: maxMagnitude ?? 10.0, // Default to bright stars
      );

      for (final star in stars) {
        results.add({
          'name': star.name,
          'catalogId': star.catalogId,
          'ra': star.ra,
          'raHours': star.ra / 15.0, // canonical hours field; see B14
          'dec': star.dec,
          'type': 'Star',
          'magnitude': star.magnitude,
          'constellation': star.constellation,
          'spectralType': star.spectralType,
          'objectType': 'star',
        });
      }
    }

    // Sort by magnitude (brightest first). These casts are over typed data
    // we just constructed above, not over caller-supplied payload.
    results.sort(
      (a, b) => ((a['magnitude'] as num?) ?? 99).compareTo(
        (b['magnitude'] as num?) ?? 99,
      ),
    );

    return jsonOk({
      'centerRa': ra,
      'centerDec': dec,
      'radiusDegrees': radius,
      'count': results.length,
      'results': results,
    });
  }

  /// GET /api/planetarium/catalog/object/:id
  /// Get detailed object info by catalog ID.
  Future<Response> handleGetCatalogObject(
    Request request,
    String objectId,
  ) async {
    _logInfo('[API] GET /api/planetarium/catalog/object/$objectId');
    // Search for the object by ID
    final results = await CatalogManager.instance.search(objectId);

    // Find exact match
    final exactMatch = results
        .where(
          (r) =>
              r.catalogId.toLowerCase() == objectId.toLowerCase() ||
              r.name.toLowerCase() == objectId.toLowerCase(),
        )
        .firstOrNull;

    if (exactMatch == null) {
      return jsonNotFound({'error': 'Object not found: $objectId'});
    }

    // Get observer location for visibility calculation
    final backend = container.read(profileSettingsBackendProvider);
    final location = await backend.getLocation();

    // Calculate visibility if we have location
    Map<String, dynamic>? visibility;
    if (location != null) {
      final now = DateTime.now();
      // exactMatch.ra is in degrees (note the /15.0 used for hour formatting
      // below), so it maps directly to objectAltAz's raDeg parameter — the same
      // helper scheduler_handlers.dart uses, so remote answers stay consistent.
      final (alt, az) = AstronomyCalculations.objectAltAz(
        raDeg: exactMatch.ra,
        decDeg: exactMatch.dec,
        dt: now,
        latitudeDeg: location.latitude,
        longitudeDeg: location.longitude,
      );

      visibility = {
        'altitude': alt,
        'azimuth': az,
        'isAboveHorizon': alt > 0,
        'observerLatitude': location.latitude,
        'observerLongitude': location.longitude,
        'calculatedAt': now.toIso8601String(),
      };
    }

    return jsonOk({
      'name': exactMatch.name,
      'catalogId': exactMatch.catalogId,
      'ra': exactMatch.ra,
      'raHours': exactMatch.ra / 15.0, // canonical hours field; see B14
      'dec': exactMatch.dec,
      'raFormatted': CoordinateFormat.ra(exactMatch.ra / 15.0),
      'decFormatted': CoordinateFormat.dec(exactMatch.dec),
      'type': exactMatch.type,
      'magnitude': exactMatch.magnitude,
      'constellation': exactMatch.constellation,
      'size': exactMatch.size,
      'visibility': visibility,
    });
  }

  // ===========================================================================
  // WebSocket Subscription Info
  // ===========================================================================

  /// GET /api/planetarium/subscribe-info
  /// Returns WebSocket URL and event types for real-time mount updates.
  Future<Response> handleGetSubscribeInfo(Request request) async {
    _logInfo('[API] GET /api/planetarium/subscribe-info');
    // Get the host from the request
    final host = request.requestedUri.host;
    final port = request.requestedUri.port;
    final scheme = request.requestedUri.scheme == 'https' ? 'wss' : 'ws';

    return jsonOk({
      'websocketUrl': '$scheme://$host:$port/api/ws',
      'alternateUrl': '$scheme://$host:$port/events',
      'eventTypes': [
        'mount_position',
        'mount_status',
        'mount_slewing',
        'mount_tracking',
        'rotator_position',
        'camera_exposure_started',
        'camera_exposure_complete',
        'sequence_status',
      ],
      'subscriptionFormat': {
        'description':
            'Connect to WebSocket URL. Events are pushed automatically.',
        'example': {
          'type': 'event',
          'category': 'equipment',
          'event': 'mount_position',
          'data': {'ra': 12.5, 'dec': 45.0, 'tracking': true},
        },
      },
      'pingPongSupport': true,
      'pingFormat': {'type': 'ping'},
      'pongFormat': {'type': 'pong'},
    });
  }

  // ===========================================================================
  // Observer Location
  // ===========================================================================

  /// GET /api/planetarium/location
  /// Get current observer location for astronomical calculations.
  Future<Response> handleGetLocation(Request request) async {
    _logInfo('[API] GET /api/planetarium/location');
    final backend = container.read(profileSettingsBackendProvider);
    final location = await backend.getLocation();

    if (location == null) {
      return jsonOk({
        'configured': false,
        'latitude': null,
        'longitude': null,
        'elevation': null,
      });
    }

    return jsonOk({
      'configured': true,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'elevation': location.elevation,
    });
  }
}
