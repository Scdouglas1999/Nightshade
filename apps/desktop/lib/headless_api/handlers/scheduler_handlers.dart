import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:shelf/shelf.dart';

/// Handlers for intelligent scheduler endpoints
///
/// These endpoints provide astronomical calculations for target planning:
/// - Altitude calculation at specific times
/// - Transit time calculation
/// - Rise/set time calculation
/// - Hours above horizon calculation
/// - Target optimization for tonight
/// - Twilight times
/// - Moon information
class SchedulerHandlers {
  final ProviderContainer container;

  SchedulerHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'SchedulerHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'SchedulerHandlers');

  // ===========================================================================
  // Calculate Altitude
  // ===========================================================================

  /// GET /api/scheduler/altitude?ra=X&dec=Y&time=Z
  /// Calculate altitude of object at given time (or now if no time)
  Future<Response> handleCalculateAltitude(Request request) async {
    _logInfo('[API] GET /api/scheduler/altitude');
    try {
      final database = container.read(databaseProvider);

      // Parse query parameters
      final raParam = request.url.queryParameters['ra'];
      final decParam = request.url.queryParameters['dec'];
      final timeParam = request.url.queryParameters['time'];

      if (raParam == null || decParam == null) {
        return Response.badRequest(
          body:
              jsonEncode({"error": "Missing required parameters: ra and dec"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final raHours = double.tryParse(raParam);
      final decDegrees = double.tryParse(decParam);
      if (raHours == null || decDegrees == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "Invalid ra or dec values"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Parse time or use now
      DateTime time;
      if (timeParam != null) {
        final parsed = DateTime.tryParse(timeParam);
        if (parsed == null) {
          final epochMs = int.tryParse(timeParam);
          if (epochMs == null) {
            return Response.badRequest(
              body: jsonEncode({
                "error":
                    "Invalid time format. Use ISO8601 or epoch milliseconds."
              }),
              headers: {'content-type': 'application/json'},
            );
          }
          time = DateTime.fromMillisecondsSinceEpoch(epochMs);
        } else {
          time = parsed;
        }
      } else {
        time = DateTime.now();
      }

      // Get observer location
      final latitude = await database.settingsDao.getObserverLatitude();
      final longitude = await database.settingsDao.getObserverLongitude();
      if (latitude == 0.0 && longitude == 0.0) {
        return Response.badRequest(
          body: jsonEncode({
            "error":
                "No observer location configured. Set location in settings first."
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Calculate altitude and azimuth
      final raDeg = raHours * 15.0; // Convert RA hours to degrees
      final (altitude, azimuth) = AstronomyCalculations.objectAltAz(
        raDeg: raDeg,
        decDeg: decDegrees,
        dt: time,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
      );

      // Calculate airmass
      final airmass = altitude > 0
          ? AstronomyCalculations.airmass(altitude)
          : double.infinity;

      // Determine if rising or setting
      final futureTime = time.add(const Duration(minutes: 10));
      final (futureAlt, _) = AstronomyCalculations.objectAltAz(
        raDeg: raDeg,
        decDeg: decDegrees,
        dt: futureTime,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
      );
      final isRising = futureAlt > altitude;

      return Response.ok(
        jsonEncode({
          "ra": raHours,
          "dec": decDegrees,
          "time": time.toIso8601String(),
          "altitude": altitude,
          "azimuth": azimuth,
          "airmass": airmass.isFinite ? airmass : null,
          "isAboveHorizon": altitude > 0,
          "isRising": isRising,
          "location": {
            "latitude": latitude,
            "longitude": longitude,
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Calculate altitude error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Calculate Transit Time
  // ===========================================================================

  /// GET /api/scheduler/transit-time?ra=X&dec=Y
  /// Get transit time for object tonight
  Future<Response> handleCalculateTransitTime(Request request) async {
    _logInfo('[API] GET /api/scheduler/transit-time');
    try {
      final database = container.read(databaseProvider);

      // Parse query parameters
      final raParam = request.url.queryParameters['ra'];
      final decParam = request.url.queryParameters['dec'];

      if (raParam == null || decParam == null) {
        return Response.badRequest(
          body:
              jsonEncode({"error": "Missing required parameters: ra and dec"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final raHours = double.tryParse(raParam);
      final decDegrees = double.tryParse(decParam);
      if (raHours == null || decDegrees == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "Invalid ra or dec values"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Get observer location
      final latitude = await database.settingsDao.getObserverLatitude();
      final longitude = await database.settingsDao.getObserverLongitude();
      if (latitude == 0.0 && longitude == 0.0) {
        return Response.badRequest(
          body: jsonEncode({
            "error":
                "No observer location configured. Set location in settings first."
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Calculate visibility
      final raDeg = raHours * 15.0;
      final now = DateTime.now();
      final visibility = AstronomyCalculations.calculateObjectVisibility(
        raDeg: raDeg,
        decDeg: decDegrees,
        date: now,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
      );

      if (visibility.transitTime == null) {
        return Response.ok(
          jsonEncode({
            "ra": raHours,
            "dec": decDegrees,
            "transitTime": null,
            "transitAltitude": null,
            "isCircumpolar": visibility.isCircumpolar,
            "neverRises": visibility.neverRises,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({
          "ra": raHours,
          "dec": decDegrees,
          "transitTime": visibility.transitTime!.toIso8601String(),
          "transitTimeEpoch": visibility.transitTime!.millisecondsSinceEpoch,
          "transitAltitude": visibility.transitAltitude,
          "isCircumpolar": visibility.isCircumpolar,
          "neverRises": visibility.neverRises,
          "location": {
            "latitude": latitude,
            "longitude": longitude,
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Calculate transit time error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Calculate Rise/Set Times
  // ===========================================================================

  /// GET /api/scheduler/rise-set?ra=X&dec=Y
  /// Get rise and set times for object
  Future<Response> handleCalculateRiseSet(Request request) async {
    _logInfo('[API] GET /api/scheduler/rise-set');
    try {
      final database = container.read(databaseProvider);

      // Parse query parameters
      final raParam = request.url.queryParameters['ra'];
      final decParam = request.url.queryParameters['dec'];
      final minAltParam = request.url.queryParameters['minAltitude'];

      if (raParam == null || decParam == null) {
        return Response.badRequest(
          body:
              jsonEncode({"error": "Missing required parameters: ra and dec"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final raHours = double.tryParse(raParam);
      final decDegrees = double.tryParse(decParam);
      if (raHours == null || decDegrees == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "Invalid ra or dec values"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final minAltitude = double.tryParse(minAltParam ?? '0') ?? 0.0;

      // Get observer location
      final latitude = await database.settingsDao.getObserverLatitude();
      final longitude = await database.settingsDao.getObserverLongitude();
      if (latitude == 0.0 && longitude == 0.0) {
        return Response.badRequest(
          body: jsonEncode({
            "error":
                "No observer location configured. Set location in settings first."
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Calculate visibility
      final raDeg = raHours * 15.0;
      final now = DateTime.now();
      final visibility = AstronomyCalculations.calculateObjectVisibility(
        raDeg: raDeg,
        decDeg: decDegrees,
        date: now,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
        minAltitude: minAltitude,
      );

      return Response.ok(
        jsonEncode({
          "ra": raHours,
          "dec": decDegrees,
          "minAltitude": minAltitude,
          "riseTime": visibility.riseTime?.toIso8601String(),
          "riseTimeEpoch": visibility.riseTime?.millisecondsSinceEpoch,
          "transitTime": visibility.transitTime?.toIso8601String(),
          "transitTimeEpoch": visibility.transitTime?.millisecondsSinceEpoch,
          "setTime": visibility.setTime?.toIso8601String(),
          "setTimeEpoch": visibility.setTime?.millisecondsSinceEpoch,
          "transitAltitude": visibility.transitAltitude,
          "isCircumpolar": visibility.isCircumpolar,
          "neverRises": visibility.neverRises,
          "durationAboveHorizonMinutes":
              visibility.durationAboveHorizon?.inMinutes,
          "location": {
            "latitude": latitude,
            "longitude": longitude,
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Calculate rise/set error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Calculate Hours Above Horizon
  // ===========================================================================

  /// GET /api/scheduler/hours-above-horizon?ra=X&dec=Y&minAltitude=30
  /// Get hours object is above altitude
  Future<Response> handleCalculateHoursAbove(Request request) async {
    _logInfo('[API] GET /api/scheduler/hours-above-horizon');
    try {
      final database = container.read(databaseProvider);

      // Parse query parameters
      final raParam = request.url.queryParameters['ra'];
      final decParam = request.url.queryParameters['dec'];
      final minAltParam = request.url.queryParameters['minAltitude'];

      if (raParam == null || decParam == null) {
        return Response.badRequest(
          body:
              jsonEncode({"error": "Missing required parameters: ra and dec"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final raHours = double.tryParse(raParam);
      final decDegrees = double.tryParse(decParam);
      if (raHours == null || decDegrees == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "Invalid ra or dec values"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final minAltitude = double.tryParse(minAltParam ?? '30') ?? 30.0;

      // Get observer location
      final latitude = await database.settingsDao.getObserverLatitude();
      final longitude = await database.settingsDao.getObserverLongitude();
      if (latitude == 0.0 && longitude == 0.0) {
        return Response.badRequest(
          body: jsonEncode({
            "error":
                "No observer location configured. Set location in settings first."
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Calculate visibility
      final raDeg = raHours * 15.0;
      final now = DateTime.now();
      final visibility = AstronomyCalculations.calculateObjectVisibility(
        raDeg: raDeg,
        decDeg: decDegrees,
        date: now,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
        minAltitude: minAltitude,
      );

      double hoursAbove;
      if (visibility.isCircumpolar) {
        hoursAbove = 24.0;
      } else if (visibility.neverRises) {
        hoursAbove = 0.0;
      } else if (visibility.durationAboveHorizon != null) {
        hoursAbove = visibility.durationAboveHorizon!.inMinutes / 60.0;
      } else {
        hoursAbove = 0.0;
      }

      return Response.ok(
        jsonEncode({
          "ra": raHours,
          "dec": decDegrees,
          "minAltitude": minAltitude,
          "hoursAbove": hoursAbove,
          "isCircumpolar": visibility.isCircumpolar,
          "neverRises": visibility.neverRises,
          "transitAltitude": visibility.transitAltitude,
          "location": {
            "latitude": latitude,
            "longitude": longitude,
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Calculate hours above horizon error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Optimize Targets
  // ===========================================================================

  /// POST /api/scheduler/optimize-targets
  /// Reorder a list of target IDs for optimal imaging tonight
  Future<Response> handleOptimizeTargets(Request request) async {
    _logInfo('[API] POST /api/scheduler/optimize-targets');
    try {
      final database = container.read(databaseProvider);
      final payload = jsonDecode(await request.readAsString());

      // Parse target IDs from payload
      final targetIds = (payload['targetIds'] as List<dynamic>?)
          ?.map((id) => id is int ? id : int.parse(id.toString()))
          .toList();

      if (targetIds == null || targetIds.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "Missing or empty targetIds array"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Parse strategy
      final strategyStr = payload['strategy'] as String? ?? 'transitTime';
      final minAltitude = (payload['minAltitude'] as num?)?.toDouble() ?? 30.0;

      // Get observer location
      final latitude = await database.settingsDao.getObserverLatitude();
      final longitude = await database.settingsDao.getObserverLongitude();
      if (latitude == 0.0 && longitude == 0.0) {
        return Response.badRequest(
          body: jsonEncode({
            "error":
                "No observer location configured. Set location in settings first."
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Fetch targets from database
      final targets = <dynamic>[];
      for (final id in targetIds) {
        final target = await database.targetsDao.getTargetById(id);
        if (target != null) {
          targets.add(target);
        }
      }

      if (targets.isEmpty) {
        return Response.badRequest(
          body:
              jsonEncode({"error": "No valid targets found for provided IDs"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Calculate visibility data for each target
      final now = DateTime.now();
      final targetVisibility = <int, Map<String, dynamic>>{};

      for (final target in targets) {
        final raDeg = target.ra * 15.0;
        final visibility = AstronomyCalculations.calculateObjectVisibility(
          raDeg: raDeg,
          decDeg: target.dec,
          date: now,
          latitudeDeg: latitude,
          longitudeDeg: longitude,
          minAltitude: minAltitude,
        );

        final (currentAlt, currentAz) = AstronomyCalculations.objectAltAz(
          raDeg: raDeg,
          decDeg: target.dec,
          dt: now,
          latitudeDeg: latitude,
          longitudeDeg: longitude,
        );

        // Determine if rising
        final futureTime = now.add(const Duration(minutes: 10));
        final (futureAlt, _) = AstronomyCalculations.objectAltAz(
          raDeg: raDeg,
          decDeg: target.dec,
          dt: futureTime,
          latitudeDeg: latitude,
          longitudeDeg: longitude,
        );
        final isRising = futureAlt > currentAlt;

        targetVisibility[target.id] = {
          'target': target,
          'visibility': visibility,
          'currentAltitude': currentAlt,
          'currentAzimuth': currentAz,
          'isRising': isRising,
          'transitTime': visibility.transitTime,
        };
      }

      // Sort based on strategy
      final sortedTargets = List<dynamic>.from(targets);

      switch (strategyStr.toLowerCase()) {
        case 'transittime':
          // Sort by transit time (earliest first)
          sortedTargets.sort((a, b) {
            final aTransit =
                targetVisibility[a.id]!['transitTime'] as DateTime?;
            final bTransit =
                targetVisibility[b.id]!['transitTime'] as DateTime?;
            if (aTransit == null && bTransit == null) return 0;
            if (aTransit == null) return 1;
            if (bTransit == null) return -1;
            return aTransit.compareTo(bTransit);
          });
          break;

        case 'currentaltitude':
          // Sort by current altitude, setting targets first (higher alt first for setting)
          sortedTargets.sort((a, b) {
            final aData = targetVisibility[a.id]!;
            final bData = targetVisibility[b.id]!;
            final aRising = aData['isRising'] as bool;
            final bRising = bData['isRising'] as bool;
            final aAlt = aData['currentAltitude'] as double;
            final bAlt = bData['currentAltitude'] as double;

            // Setting targets first
            if (!aRising && bRising) return -1;
            if (aRising && !bRising) return 1;

            // Within same category, higher altitude first for setting, lower for rising
            if (!aRising) {
              return bAlt.compareTo(aAlt);
            } else {
              return aAlt.compareTo(bAlt);
            }
          });
          break;

        case 'risingfirst':
          // Image rising targets first
          sortedTargets.sort((a, b) {
            final aData = targetVisibility[a.id]!;
            final bData = targetVisibility[b.id]!;
            final aRising = aData['isRising'] as bool;
            final bRising = bData['isRising'] as bool;
            final aAlt = aData['currentAltitude'] as double;
            final bAlt = bData['currentAltitude'] as double;

            if (aRising != bRising) {
              return aRising ? -1 : 1;
            }
            return aAlt.compareTo(bAlt);
          });
          break;

        case 'settingfirst':
          // Image setting targets first
          sortedTargets.sort((a, b) {
            final aData = targetVisibility[a.id]!;
            final bData = targetVisibility[b.id]!;
            final aRising = aData['isRising'] as bool;
            final bRising = bData['isRising'] as bool;
            final aAlt = aData['currentAltitude'] as double;
            final bAlt = bData['currentAltitude'] as double;

            if (aRising != bRising) {
              return aRising ? 1 : -1;
            }
            if (!aRising) {
              return bAlt.compareTo(aAlt);
            }
            return aAlt.compareTo(bAlt);
          });
          break;

        case 'priority':
          // Use target priority
          sortedTargets.sort((a, b) => a.priority.compareTo(b.priority));
          break;

        default:
          return Response.badRequest(
            body: jsonEncode({
              "error":
                  "Unknown strategy: $strategyStr. Valid options: transitTime, currentAltitude, risingFirst, settingFirst, priority"
            }),
            headers: {'content-type': 'application/json'},
          );
      }

      // Build response
      final orderedResults = sortedTargets.map((target) {
        final data = targetVisibility[target.id]!;
        final visibility = data['visibility'] as ObjectVisibility;
        return {
          'targetId': target.id,
          'targetName': target.name,
          'raHours': target.ra,
          'decDegrees': target.dec,
          'currentAltitude': data['currentAltitude'],
          'currentAzimuth': data['currentAzimuth'],
          'isRising': data['isRising'],
          'transitTime': visibility.transitTime?.toIso8601String(),
          'transitAltitude': visibility.transitAltitude,
          'isCircumpolar': visibility.isCircumpolar,
          'neverRises': visibility.neverRises,
        };
      }).toList();

      return Response.ok(
        jsonEncode({
          "strategy": strategyStr,
          "minAltitude": minAltitude,
          "optimizedTargets": orderedResults,
          "location": {
            "latitude": latitude,
            "longitude": longitude,
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Optimize targets error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Get Twilight Times
  // ===========================================================================

  /// GET /api/scheduler/twilight-times
  /// Get astronomical, nautical, civil twilight times for tonight
  Future<Response> handleGetTwilightTimes(Request request) async {
    _logInfo('[API] GET /api/scheduler/twilight-times');
    try {
      final database = container.read(databaseProvider);

      // Get observer location
      final latitude = await database.settingsDao.getObserverLatitude();
      final longitude = await database.settingsDao.getObserverLongitude();
      if (latitude == 0.0 && longitude == 0.0) {
        return Response.badRequest(
          body: jsonEncode({
            "error":
                "No observer location configured. Set location in settings first."
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Optional date parameter
      final dateParam = request.url.queryParameters['date'];
      DateTime date;
      if (dateParam != null) {
        final parsed = DateTime.tryParse(dateParam);
        if (parsed == null) {
          return Response.badRequest(
            body: jsonEncode({"error": "Invalid date format. Use ISO8601."}),
            headers: {'content-type': 'application/json'},
          );
        }
        date = parsed;
      } else {
        date = DateTime.now();
      }

      // Calculate twilight times
      final twilight = AstronomyCalculations.calculateTwilightTimes(
        date: date,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
      );

      return Response.ok(
        jsonEncode({
          "date": date.toIso8601String().split('T')[0],
          "sunset": twilight.sunset?.toIso8601String(),
          "sunsetEpoch": twilight.sunset?.millisecondsSinceEpoch,
          "civilDusk": twilight.civilDusk?.toIso8601String(),
          "civilDuskEpoch": twilight.civilDusk?.millisecondsSinceEpoch,
          "nauticalDusk": twilight.nauticalDusk?.toIso8601String(),
          "nauticalDuskEpoch": twilight.nauticalDusk?.millisecondsSinceEpoch,
          "astronomicalDusk": twilight.astronomicalDusk?.toIso8601String(),
          "astronomicalDuskEpoch":
              twilight.astronomicalDusk?.millisecondsSinceEpoch,
          "astronomicalDawn": twilight.astronomicalDawn?.toIso8601String(),
          "astronomicalDawnEpoch":
              twilight.astronomicalDawn?.millisecondsSinceEpoch,
          "nauticalDawn": twilight.nauticalDawn?.toIso8601String(),
          "nauticalDawnEpoch": twilight.nauticalDawn?.millisecondsSinceEpoch,
          "civilDawn": twilight.civilDawn?.toIso8601String(),
          "civilDawnEpoch": twilight.civilDawn?.millisecondsSinceEpoch,
          "sunrise": twilight.sunrise?.toIso8601String(),
          "sunriseEpoch": twilight.sunrise?.millisecondsSinceEpoch,
          "darknessDurationMinutes": twilight.darknessDuration?.inMinutes,
          "location": {
            "latitude": latitude,
            "longitude": longitude,
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Get twilight times error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Get Moon Info
  // ===========================================================================

  /// GET /api/scheduler/moon-info
  /// Get moon phase, rise/set, illumination
  Future<Response> handleGetMoonInfo(Request request) async {
    _logInfo('[API] GET /api/scheduler/moon-info');
    try {
      final database = container.read(databaseProvider);

      // Get observer location
      final latitude = await database.settingsDao.getObserverLatitude();
      final longitude = await database.settingsDao.getObserverLongitude();
      if (latitude == 0.0 && longitude == 0.0) {
        return Response.badRequest(
          body: jsonEncode({
            "error":
                "No observer location configured. Set location in settings first."
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Optional date parameter
      final dateParam = request.url.queryParameters['date'];
      DateTime date;
      if (dateParam != null) {
        final parsed = DateTime.tryParse(dateParam);
        if (parsed == null) {
          return Response.badRequest(
            body: jsonEncode({"error": "Invalid date format. Use ISO8601."}),
            headers: {'content-type': 'application/json'},
          );
        }
        date = parsed;
      } else {
        date = DateTime.now();
      }

      // Calculate moon position and illumination
      final (moonRaDeg, moonDecDeg, moonDistance) =
          AstronomyCalculations.moonPosition(date);
      final moonRaHours = moonRaDeg / 15.0;
      final illumination = AstronomyCalculations.moonIllumination(date);
      final phaseName = AstronomyCalculations.moonPhaseName(date);

      // Calculate current altitude
      final (moonAlt, moonAz) = AstronomyCalculations.objectAltAz(
        raDeg: moonRaDeg,
        decDeg: moonDecDeg,
        dt: date,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
      );

      // Calculate moon rise/set times
      final moonTimes = AstronomyCalculations.calculateMoonTimes(
        date: date,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
      );

      return Response.ok(
        jsonEncode({
          "date": date.toIso8601String(),
          "position": {
            "raHours": moonRaHours,
            "raDegrees": moonRaDeg,
            "decDegrees": moonDecDeg,
            "distanceKm": moonDistance,
          },
          "illumination": illumination,
          "phaseName": phaseName,
          "currentAltitude": moonAlt,
          "currentAzimuth": moonAz,
          "isAboveHorizon": moonAlt > 0,
          "moonrise": moonTimes.moonrise?.toIso8601String(),
          "moonriseEpoch": moonTimes.moonrise?.millisecondsSinceEpoch,
          "moonset": moonTimes.moonset?.toIso8601String(),
          "moonsetEpoch": moonTimes.moonset?.millisecondsSinceEpoch,
          "location": {
            "latitude": latitude,
            "longitude": longitude,
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Get moon info error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
