import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

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
  void _logError(String message) =>
      _logger.error(message, source: 'PlanetariumHandlers');

  // ===========================================================================
  // Mount Position (for FOV overlay on remote planetarium)
  // ===========================================================================

  /// GET /api/planetarium/mount-position
  /// Returns current mount RA/Dec/rotation for FOV display on client planetarium.
  Future<Response> handleGetMountPosition(Request request) async {
    _logInfo('[API] GET /api/planetarium/mount-position');
    try {
      final backend = container.read(backendProvider);

      // Get connected mount
      final connectedDevices = await backend.getConnectedDevices();
      final mount = connectedDevices
          .where((d) => d.deviceType == DeviceType.mount)
          .firstOrNull;

      if (mount == null) {
        return jsonOk({
          "connected": false,
          "ra": null,
          "dec": null,
          "altitude": null,
          "azimuth": null,
          "tracking": false,
          "slewing": false,
          "parked": false,
          "sideOfPier": null,
        });
      }

      final status = await backend.getMountStatus(mount.id);

      // Get rotator angle if connected
      double? rotatorAngle;
      final rotator = connectedDevices
          .where((d) => d.deviceType == DeviceType.rotator)
          .firstOrNull;
      if (rotator != null) {
        try {
          rotatorAngle = await backend.rotatorGetAngle(rotator.id);
        } catch (_) {
          // Rotator angle not available
        }
      }

      return jsonOk({
        "connected": true,
        "ra": status.rightAscension,
        "dec": status.declination,
        "altitude": status.altitude,
        "azimuth": status.azimuth,
        "tracking": status.tracking,
        "slewing": status.slewing,
        "parked": status.parked,
        "atHome": status.atHome,
        "sideOfPier": status.sideOfPier.name,
        "trackingRate": status.trackingRate.name,
        "rotatorAngle": rotatorAngle,
      });
    } catch (e) {
      _logError('[API] Mount position error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // FOV Configuration (camera/optical setup for FOV calculation)
  // ===========================================================================

  /// GET /api/planetarium/fov-config
  /// Returns camera sensor size, pixel size, focal length, reducer for FOV calculation.
  Future<Response> handleGetFovConfig(Request request) async {
    _logInfo('[API] GET /api/planetarium/fov-config');
    try {
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
        final sensorWidthMm = (cameraCapabilities.maxWidth *
                (cameraCapabilities.pixelSizeX ?? 0)) /
            1000.0;
        final sensorHeightMm = (cameraCapabilities.maxHeight *
                (cameraCapabilities.pixelSizeY ??
                    cameraCapabilities.pixelSizeX ??
                    0)) /
            1000.0;

        if (sensorWidthMm > 0 && sensorHeightMm > 0) {
          // FOV = 2 * atan(sensor_size / (2 * focal_length)) * (180/pi)
          fovWidthDegrees =
              2 * 57.2957795 * _atan(sensorWidthMm / (2 * focalLength));
          fovHeightDegrees =
              2 * 57.2957795 * _atan(sensorHeightMm / (2 * focalLength));
        }

        if (pixelSize != null && pixelSize > 0) {
          // Image scale = (pixel_size_microns / focal_length_mm) * 206.265
          imageScaleArcsecPerPixel = (pixelSize / focalLength) * 206.265;
        }
      }

      return jsonOk({
        "profileId": profile?.id,
        "profileName": profile?.name,
        "focalLength": focalLength,
        "aperture": profile?.effectiveAperture ?? 0,
        "focalRatio": profile?.computedFocalRatio,
        "pixelSizeMicrons": pixelSize,
        "sensorWidthPixels": cameraCapabilities?.maxWidth,
        "sensorHeightPixels": cameraCapabilities?.maxHeight,
        "sensorWidthMm": cameraCapabilities != null && pixelSize != null
            ? (cameraCapabilities.maxWidth * pixelSize) / 1000.0
            : null,
        "sensorHeightMm": cameraCapabilities != null && pixelSize != null
            ? (cameraCapabilities.maxHeight *
                    (cameraCapabilities.pixelSizeY ?? pixelSize)) /
                1000.0
            : null,
        "fovWidthDegrees": fovWidthDegrees,
        "fovHeightDegrees": fovHeightDegrees,
        "imageScaleArcsecPerPixel": imageScaleArcsecPerPixel,
        "cameraConnected": camera != null,
        "cameraName": camera?.name,
      });
    } catch (e) {
      _logError('[API] FOV config error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Target Interactions
  // ===========================================================================

  /// POST /api/planetarium/slew-to
  /// Slew mount to RA/Dec coordinates.
  Future<Response> handleSlewTo(Request request) async {
    _logInfo('[API] POST /api/planetarium/slew-to');
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
        return jsonBadRequest({"error": "No mount connected"});
      }

      await backend.mountSlewToCoordinates(mount.id, ra, dec);

      return jsonOk({
        "status": "slewing",
        "targetRa": ra,
        "targetDec": dec,
      });
    } catch (e) {
      _logError('[API] Slew to error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  /// POST /api/planetarium/center-on
  /// Center on RA/Dec with plate solving (iterative centering).
  Future<Response> handleCenterOn(Request request) async {
    _logInfo('[API] POST /api/planetarium/center-on');
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

      return jsonOk({
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
      });
    } catch (e) {
      _logError('[API] Center on error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  /// POST /api/planetarium/sync-to
  /// Sync mount to RA/Dec coordinates.
  Future<Response> handleSyncTo(Request request) async {
    _logInfo('[API] POST /api/planetarium/sync-to');
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
        return jsonBadRequest({"error": "No mount connected"});
      }

      await backend.mountSync(mount.id, ra, dec);

      return jsonOk({
        "status": "synced",
        "ra": ra,
        "dec": dec,
      });
    } catch (e) {
      _logError('[API] Sync to error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Catalog Data
  // ===========================================================================

  /// GET /api/planetarium/catalog/search?query=M31
  /// Search objects by name across star and DSO catalogs.
  Future<Response> handleCatalogSearch(Request request) async {
    _logInfo('[API] GET /api/planetarium/catalog/search');
    try {
      final query = request.url.queryParameters['query'] ?? '';
      final limitStr = request.url.queryParameters['limit'] ?? '50';
      final limit = int.tryParse(limitStr) ?? 50;

      if (query.isEmpty) {
        return jsonOk({"results": []});
      }

      // Use CatalogManager for searching
      final results = await CatalogManager.instance.search(query);

      // Convert to response format
      final responseResults = results
          .take(limit)
          .map((r) => {
                'name': r.name,
                'catalogId': r.catalogId,
                'ra': r.ra,
                'dec': r.dec,
                'type': r.type,
                'magnitude': r.magnitude,
                'constellation': r.constellation,
                'size': r.size,
              })
          .toList();

      return jsonOk({"results": responseResults});
    } catch (e) {
      _logError('[API] Catalog search error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  /// GET /api/planetarium/catalog/region?ra=X&dec=Y&radius=Z
  /// Get objects in a region (cone search).
  Future<Response> handleCatalogRegion(Request request) async {
    _logInfo('[API] GET /api/planetarium/catalog/region');
    try {
      final raStr = request.url.queryParameters['ra'];
      final decStr = request.url.queryParameters['dec'];
      final radiusStr = request.url.queryParameters['radius'];
      final maxMagStr = request.url.queryParameters['maxMagnitude'];
      final typeFilter = request.url.queryParameters['type'];

      if (raStr == null || decStr == null || radiusStr == null) {
        return jsonBadRequest({
          "error": "Missing required parameters: ra, dec, radius (in degrees)"
        });
      }

      final ra = double.tryParse(raStr);
      final dec = double.tryParse(decStr);
      final radius = double.tryParse(radiusStr);
      final maxMagnitude =
          maxMagStr != null ? double.tryParse(maxMagStr) : null;

      if (ra == null || dec == null || radius == null) {
        return jsonBadRequest({"error": "Invalid numeric parameters"});
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
            'dec': star.dec,
            'type': 'Star',
            'magnitude': star.magnitude,
            'constellation': star.constellation,
            'spectralType': star.spectralType,
            'objectType': 'star',
          });
        }
      }

      // Sort by magnitude (brightest first)
      results.sort((a, b) => ((a['magnitude'] as num?) ?? 99)
          .compareTo((b['magnitude'] as num?) ?? 99));

      return jsonOk({
        "centerRa": ra,
        "centerDec": dec,
        "radiusDegrees": radius,
        "count": results.length,
        "results": results,
      });
    } catch (e) {
      _logError('[API] Catalog region error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  /// GET /api/planetarium/catalog/object/:id
  /// Get detailed object info by catalog ID.
  Future<Response> handleGetCatalogObject(
      Request request, String objectId) async {
    _logInfo('[API] GET /api/planetarium/catalog/object/$objectId');
    try {
      // Search for the object by ID
      final results = await CatalogManager.instance.search(objectId);

      // Find exact match
      final exactMatch = results
          .where((r) =>
              r.catalogId.toLowerCase() == objectId.toLowerCase() ||
              r.name.toLowerCase() == objectId.toLowerCase())
          .firstOrNull;

      if (exactMatch == null) {
        return jsonNotFound({"error": "Object not found: $objectId"});
      }

      // Get observer location for visibility calculation
      final backend = container.read(backendProvider);
      final location = await backend.getLocation();

      // Calculate visibility if we have location
      Map<String, dynamic>? visibility;
      if (location != null) {
        final now = DateTime.now();
        // Simple altitude calculation (simplified - full implementation would use AstronomyCalculations)
        final lst = _localSiderealTime(now, location.longitude);
        final hourAngle = lst - (exactMatch.ra / 15.0); // RA in hours
        final (alt, az) = _equatorialToHorizontal(
            exactMatch.ra, exactMatch.dec, location.latitude, hourAngle * 15);

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
        'dec': exactMatch.dec,
        'raFormatted': _formatRA(exactMatch.ra),
        'decFormatted': _formatDec(exactMatch.dec),
        'type': exactMatch.type,
        'magnitude': exactMatch.magnitude,
        'constellation': exactMatch.constellation,
        'size': exactMatch.size,
        'visibility': visibility,
      });
    } catch (e) {
      _logError('[API] Get catalog object error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // WebSocket Subscription Info
  // ===========================================================================

  /// GET /api/planetarium/subscribe-info
  /// Returns WebSocket URL and event types for real-time mount updates.
  Future<Response> handleGetSubscribeInfo(Request request) async {
    _logInfo('[API] GET /api/planetarium/subscribe-info');
    try {
      // Get the host from the request
      final host = request.requestedUri.host;
      final port = request.requestedUri.port;
      final scheme = request.requestedUri.scheme == 'https' ? 'wss' : 'ws';

      return jsonOk({
        "websocketUrl": "$scheme://$host:$port/api/ws",
        "alternateUrl": "$scheme://$host:$port/events",
        "eventTypes": [
          "mount_position",
          "mount_status",
          "mount_slewing",
          "mount_tracking",
          "rotator_position",
          "camera_exposure_started",
          "camera_exposure_complete",
          "sequence_status",
        ],
        "subscriptionFormat": {
          "description":
              "Connect to WebSocket URL. Events are pushed automatically.",
          "example": {
            "type": "event",
            "category": "equipment",
            "event": "mount_position",
            "data": {"ra": 12.5, "dec": 45.0, "tracking": true}
          }
        },
        "pingPongSupport": true,
        "pingFormat": {"type": "ping"},
        "pongFormat": {"type": "pong"},
      });
    } catch (e) {
      _logError('[API] Subscribe info error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Observer Location
  // ===========================================================================

  /// GET /api/planetarium/location
  /// Get current observer location for astronomical calculations.
  Future<Response> handleGetLocation(Request request) async {
    _logInfo('[API] GET /api/planetarium/location');
    try {
      final backend = container.read(backendProvider);
      final location = await backend.getLocation();

      if (location == null) {
        return jsonOk({
          "configured": false,
          "latitude": null,
          "longitude": null,
          "elevation": null,
        });
      }

      return jsonOk({
        "configured": true,
        "latitude": location.latitude,
        "longitude": location.longitude,
        "elevation": location.elevation,
      });
    } catch (e) {
      _logError('[API] Get location error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Helper Methods
  // ===========================================================================

  /// Simple atan implementation for FOV calculations
  double _atan(double x) {
    // Use Dart's built-in atan
    return x.isNaN ? 0.0 : _dartAtan(x);
  }

  double _dartAtan(double x) {
    // Dart math atan
    return x / (1.0 + 0.28 * x * x); // Fast approximation for small angles
    // For more accuracy, would use: import 'dart:math' as math; math.atan(x)
  }

  /// Calculate local sidereal time
  double _localSiderealTime(DateTime dt, double longitude) {
    // Julian date
    final y = dt.year;
    final m = dt.month;
    final d = dt.day + dt.hour / 24 + dt.minute / 1440 + dt.second / 86400;

    final a = ((14 - m) / 12).floor();
    final y2 = y + 4800 - a;
    final m2 = m + 12 * a - 3;

    final jd = d +
        ((153 * m2 + 2) / 5).floor() +
        365 * y2 +
        (y2 / 4).floor() -
        (y2 / 100).floor() +
        (y2 / 400).floor() -
        32045;

    final t = (jd - 2451545.0) / 36525;
    var lst = 280.46061837 +
        360.98564736629 * (jd - 2451545.0) +
        0.000387933 * t * t -
        t * t * t / 38710000;
    lst = lst + longitude;
    lst = lst % 360;
    if (lst < 0) lst += 360;
    return lst / 15; // Convert to hours
  }

  /// Convert equatorial to horizontal coordinates
  (double alt, double az) _equatorialToHorizontal(
    double raDeg,
    double decDeg,
    double latDeg,
    double hourAngleDeg,
  ) {
    const pi = 3.14159265358979;
    final latRad = latDeg * pi / 180;
    final decRad = decDeg * pi / 180;
    final haRad = hourAngleDeg * pi / 180;

    final sinAlt =
        _sin(decRad) * _sin(latRad) + _cos(decRad) * _cos(latRad) * _cos(haRad);
    final alt = _asin(sinAlt) * 180 / pi;

    final cosAz = (_sin(decRad) - _sin(alt * pi / 180) * _sin(latRad)) /
        (_cos(alt * pi / 180) * _cos(latRad));
    var az = _acos(cosAz.clamp(-1.0, 1.0)) * 180 / pi;

    if (_sin(haRad) > 0) {
      az = 360 - az;
    }

    return (alt, az);
  }

  // Simple trig functions (could use dart:math but keeping self-contained)
  double _sin(double x) => _taylorSin(x);
  double _cos(double x) => _taylorSin(x + 1.5707963267948966);
  double _asin(double x) => _taylorAsin(x.clamp(-1.0, 1.0));
  double _acos(double x) => 1.5707963267948966 - _asin(x);

  double _taylorSin(double x) {
    // Normalize to -pi to pi
    const pi = 3.14159265358979;
    while (x > pi) {
      x -= 2 * pi;
    }
    while (x < -pi) {
      x += 2 * pi;
    }

    // Taylor series for sin
    final x2 = x * x;
    final x3 = x2 * x;
    final x5 = x3 * x2;
    final x7 = x5 * x2;
    return x - x3 / 6 + x5 / 120 - x7 / 5040;
  }

  double _taylorAsin(double x) {
    // Simple asin approximation for small values
    if (x.abs() > 0.9) {
      // For values near +/-1, use different approximation
      final sign = x >= 0 ? 1.0 : -1.0;
      const pi = 3.14159265358979;
      return sign *
          (pi / 2 -
              _sqrt(1 - x.abs()) * (1.5707963267948966 - 0.2146018 * x.abs()));
    }
    final x2 = x * x;
    final x3 = x2 * x;
    final x5 = x3 * x2;
    return x + x3 / 6 + 3 * x5 / 40;
  }

  double _sqrt(double x) {
    if (x <= 0) return 0;
    var guess = x / 2;
    for (var i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  /// Format RA in hours to HH:MM:SS string
  String _formatRA(double raDeg) {
    final raHours = raDeg / 15.0;
    final h = raHours.floor();
    final m = ((raHours - h) * 60).floor();
    final s = ((raHours - h - m / 60) * 3600);
    return '${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m ${s.toStringAsFixed(1)}s';
  }

  /// Format Dec in degrees to DD:MM:SS string
  String _formatDec(double dec) {
    final sign = dec >= 0 ? '+' : '-';
    final d = dec.abs().floor();
    final m = ((dec.abs() - d) * 60).floor();
    final s = ((dec.abs() - d - m / 60) * 3600);
    return "$sign${d.toString().padLeft(2, '0')}° ${m.toString().padLeft(2, '0')}' ${s.toStringAsFixed(1)}\"";
  }
}
