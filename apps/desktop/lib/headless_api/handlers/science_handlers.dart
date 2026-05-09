import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_app/services/observation_report_service.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' show apiReadFitsFile;
import 'package:nightshade_core/nightshade_core.dart';
// ignore: implementation_imports
import 'package:nightshade_core/src/database/database.dart' as db;
import 'package:nightshade_planetarium/nightshade_planetarium.dart'
    show CatalogManager, HygStarData;
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for remote science/analytics parity.
class ScienceHandlers {
  final ProviderContainer container;

  ScienceHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'ScienceHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'ScienceHandlers');

  Future<Response> handleGetSessionBundle(
    Request request,
    String sessionId,
  ) async {
    _logInfo('[API] GET /api/science/session/$sessionId/bundle');
    try {
      final sid = int.parse(sessionId);
      final database = container.read(databaseProvider);
      final scienceDao = database.scienceDao;

      final photometry = await scienceDao.getPhotometryForSession(sid);
      final calibrations = await scienceDao.getCalibrationsForSession(sid);
      final transparency = await scienceDao.getTransparencyForSession(sid);
      final psfTiles = await scienceDao.getPsfTilesForSession(sid);
      final frameQuality =
          await scienceDao.getFrameQualityMetricsForSession(sid);
      final tileMetrics = await scienceDao.getTileMetricsForSession(sid);
      final residuals = await scienceDao.getResidualsForSession(sid);
      final movingObjects = await scienceDao.getMovingObjectsForSession(sid);
      final lineRatios = await scienceDao.getLineRatiosForSession(sid);

      return jsonOk({
        'photometry': photometry.map((row) => row.toJson()).toList(),
        'calibrations': calibrations.map((row) => row.toJson()).toList(),
        'transparency': transparency.map((row) => row.toJson()).toList(),
        'psfTiles': psfTiles.map((row) => row.toJson()).toList(),
        'frameQuality': frameQuality.map((row) => row.toJson()).toList(),
        'tileMetrics': tileMetrics.map((row) => row.toJson()).toList(),
        'residuals': residuals.map((row) => row.toJson()).toList(),
        'movingObjects': movingObjects.map((row) => row.toJson()).toList(),
        'lineRatios': lineRatios.map((row) => row.toJson()).toList(),
      });
    } catch (e) {
      _logError('[API] Session science bundle error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleGetScienceSettings(Request request) async {
    _logInfo('[API] GET /api/science/settings');
    try {
      final settings =
          await container.read(settingsDaoProvider).getAllSettings();
      final filtered = settings.entries
          .where((entry) => entry.key.startsWith('science.'))
          .fold<Map<String, String>>({}, (map, entry) {
        map[entry.key] = entry.value;
        return map;
      });
      return jsonOk({'settings': filtered});
    } catch (e) {
      _logError('[API] Science settings error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleUpdateScienceSettings(Request request) async {
    _logInfo('[API] POST /api/science/settings');
    try {
      final payload = jsonDecode(await request.readAsString());
      final settings = (payload['settings'] as Map? ?? const {})
          .cast<String, dynamic>()
          .map((key, value) => MapEntry(key, value.toString()));
      await container.read(settingsDaoProvider).setSettings(settings);
      return jsonOk({'status': 'updated'});
    } catch (e) {
      _logError('[API] Update science settings error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleGetSessionConfig(
    Request request,
    String sessionId,
  ) async {
    _logInfo('[API] GET /api/science/session/$sessionId/config');
    try {
      final sid = int.parse(sessionId);
      final row = await container
          .read(databaseProvider)
          .scienceDao
          .watchSessionConfig(sid)
          .first;
      return jsonOk({'config': row?.toJson()});
    } catch (e) {
      _logError('[API] Science session config error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleUpdateSessionConfig(
    Request request,
    String sessionId,
  ) async {
    _logInfo('[API] POST /api/science/session/$sessionId/config');
    try {
      final sid = int.parse(sessionId);
      final payload = jsonDecode(await request.readAsString());
      final configJson =
          (payload['config'] as Map? ?? const {}).cast<String, dynamic>();
      final config =
          ScienceSessionConfig.fromJson(configJson).copyWith(sessionId: sid);
      await container
          .read(databaseProvider)
          .scienceDao
          .upsertSessionConfig(config);
      return jsonOk({'status': 'updated'});
    } catch (e) {
      _logError('[API] Update science session config error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleGetSessionlessBundle(Request request) async {
    _logInfo('[API] GET /api/science/sessionless/recent');
    try {
      final database = container.read(databaseProvider);
      final scienceDao = database.scienceDao;

      final photometry =
          await scienceDao.watchSessionlessPhotometryRecent().first;
      final calibrations =
          await scienceDao.watchSessionlessCalibrationsRecent().first;
      final transparency =
          await scienceDao.watchSessionlessTransparencyRecent().first;
      final psfTiles = await scienceDao.watchSessionlessPsfTilesRecent().first;
      final frameQuality =
          await scienceDao.watchSessionlessFrameQualityMetricsRecent().first;
      final tileMetrics =
          await scienceDao.watchSessionlessTileMetricsRecent().first;
      final residuals =
          await scienceDao.watchSessionlessResidualsRecent().first;
      final movingObjects =
          await scienceDao.watchSessionlessMovingObjectsRecent().first;
      final lineRatios =
          await scienceDao.watchSessionlessLineRatiosRecent().first;

      return jsonOk({
        'photometry': photometry.map((row) => row.toJson()).toList(),
        'calibrations': calibrations.map((row) => row.toJson()).toList(),
        'transparency': transparency.map((row) => row.toJson()).toList(),
        'psfTiles': psfTiles.map((row) => row.toJson()).toList(),
        'frameQuality': frameQuality.map((row) => row.toJson()).toList(),
        'tileMetrics': tileMetrics.map((row) => row.toJson()).toList(),
        'residuals': residuals.map((row) => row.toJson()).toList(),
        'movingObjects': movingObjects.map((row) => row.toJson()).toList(),
        'lineRatios': lineRatios.map((row) => row.toJson()).toList(),
      });
    } catch (e) {
      _logError('[API] Sessionless science bundle error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleGetPhotometricTransforms(Request request) async {
    _logInfo('[API] GET /api/science/transforms');
    try {
      final database = container.read(databaseProvider);
      final scienceDao = database.scienceDao;
      final profileId =
          int.tryParse(request.url.queryParameters['profileId'] ?? '');

      final transforms = profileId == null
          ? await scienceDao.getAllTransforms()
          : await scienceDao.watchTransformsForProfile(profileId).first;

      return jsonOk({
        'transforms': transforms.map((row) => row.toJson()).toList(),
      });
    } catch (e) {
      _logError('[API] Photometric transforms error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleGenerateLineRatios(
    Request request,
    String sessionId,
  ) async {
    _logInfo('[API] POST /api/science/session/$sessionId/generate-line-ratios');
    try {
      final sid = int.parse(sessionId);
      final database = container.read(databaseProvider);
      final images = await database.imagesDao.getImagesForSession(sid);

      final ha =
          _findLatestByFilter(images, {'ha', 'halpha', 'h-alpha', 'h alpha'});
      final oiii = _findLatestByFilter(images, {'oiii', 'o3'});
      final sii = _findLatestByFilter(images, {'sii', 's2'});

      if (ha == null || oiii == null || sii == null) {
        return jsonBadRequest({
          'error': 'Need latest H-alpha, OIII, and SII frames in this session.',
        });
      }

      await container.read(scienceProcessingServiceProvider).generateLineRatios(
            sessionId: sid,
            set: NarrowbandSet(
              hAlphaPath: ha.filePath,
              oiiiPath: oiii.filePath,
              siiPath: sii.filePath,
            ),
            hAlphaImageId: ha.id,
            oiiiImageId: oiii.id,
            siiImageId: sii.id,
          );

      return jsonOk({
        'status': 'generated',
        'files': [ha.fileName, oiii.fileName, sii.fileName],
      });
    } catch (e) {
      _logError('[API] Generate line ratios error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleExportAavso(
    Request request,
    String sessionId,
  ) async {
    _logInfo('[API] POST /api/science/session/$sessionId/export/aavso');
    try {
      final sid = int.parse(sessionId);
      final payload = jsonDecode(await request.readAsString());
      final targetStarName = payload['targetStarName'] as String? ?? '';
      final filterBand = payload['filterBand'] as String?;
      final chartId = payload['chartId'] as String?;

      final database = container.read(databaseProvider);
      final service = AavsoExportService(
        scienceDao: database.scienceDao,
        settingsDao: database.settingsDao,
        imagesDao: database.imagesDao,
      );

      final filePath = await service.exportSession(
        sessionId: sid,
        targetStarName: targetStarName,
        filterBand: filterBand,
        chartId: chartId,
      );

      final file = File(filePath);
      if (!await file.exists()) {
        return jsonNotFound({'error': 'AAVSO export file not found'});
      }

      final fileLength = await file.length();
      return attachmentResponse(
        file.openRead(),
        fileName: file.uri.pathSegments.last,
        contentType: 'text/plain; charset=utf-8',
        contentLength: fileLength,
      );
    } on AavsoExportError catch (e) {
      return jsonBadRequest({'error': e.message});
    } catch (e) {
      _logError('[API] AAVSO export error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleGenerateObservationReport(
    Request request,
    String sessionId,
  ) async {
    _logInfo('[API] GET /api/science/session/$sessionId/report/pdf');
    try {
      final sid = int.parse(sessionId);
      final database = container.read(databaseProvider);
      final service = ObservationReportService(
        sessionsDao: database.sessionsDao,
        imagesDao: database.imagesDao,
        scienceDao: database.scienceDao,
      );

      final filePath = await service.generateReport(sessionId: sid);
      final file = File(filePath);
      if (!await file.exists()) {
        return jsonNotFound({'error': 'Observation report file not found'});
      }

      final fileLength = await file.length();
      return attachmentResponse(
        file.openRead(),
        fileName: file.uri.pathSegments.last,
        contentType: 'application/pdf',
        contentLength: fileLength,
      );
    } catch (e) {
      _logError('[API] Observation report error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleMatchPhotometricCalibrationStars(
    Request request,
    String imageId,
  ) async {
    _logInfo('[API] POST /api/science/calibration/image/$imageId/match-stars');
    try {
      final iid = int.parse(imageId);
      final database = container.read(databaseProvider);
      final image = await database.imagesDao.getImageById(iid);
      if (image == null) {
        return jsonNotFound({'error': 'Image not found'});
      }

      if (!image.isPlateSolved ||
          image.solvedRa == null ||
          image.solvedDec == null) {
        return jsonBadRequest({'error': 'Image must be plate-solved first'});
      }

      final file = File(image.filePath);
      if (!await file.exists()) {
        return jsonNotFound({'error': 'Image file not found on host'});
      }

      final scienceBackend = container.read(scienceBackendProvider);
      final stars = await scienceBackend.measureStars(
        image.filePath,
        const PhotometryOptions(minSnr: 5.0),
      );
      if (stars.length < 4) {
        return jsonBadRequest({
          'error': 'Only ${stars.length} stars detected. Need at least 4.',
        });
      }

      double airmass = 1.0;
      if (image.mountAltitude != null && image.mountAltitude! > 0) {
        final altitudeRadians = image.mountAltitude! * math.pi / 180.0;
        airmass = 1.0 /
            (math.sin(altitudeRadians) +
                0.50572 * math.pow(image.mountAltitude! + 6.07995, -1.6364));
        airmass = airmass.clamp(1.0, 8.0);
      }

      final wcs = WcsSolution(
        raHours: image.solvedRa!,
        decDegrees: image.solvedDec!,
        pixelScaleArcsecPerPixel: image.solvedPixelScale ?? 1.5,
        rotationDegrees: image.solvedRotation ?? 0.0,
        fieldWidthDegrees: 1.0,
        fieldHeightDegrees: 1.0,
        solverId: 'stored',
      );

      final calibration = await scienceBackend.calibrateFramePhotometry(
        image.filePath,
        wcs,
        PhotometricCatalogSource.auto,
        null,
      );
      if (calibration == null || !calibration.isCalibrated) {
        return jsonBadRequest({
          'error':
              'Frame photometric calibration failed. Nightshade could not match this field to the catalog.',
        });
      }

      final zeroPoint = calibration.zeroPoint ?? 0.0;
      final catalogManager = CatalogManager.instance;
      List<HygStarData> catalogStars = const [];
      if (catalogManager.isInitialized) {
        final searchRadiusDeg = math.sqrt(
                  wcs.fieldWidthDegrees * wcs.fieldWidthDegrees +
                      wcs.fieldHeightDegrees * wcs.fieldHeightDegrees,
                ) *
                0.65 +
            0.3;
        catalogStars = await catalogManager.searchStarsNearby(
          ra: wcs.raHours * 15.0,
          dec: wcs.decDegrees,
          radiusDegrees: searchRadiusDeg.clamp(0.25, 8.0),
          maxMagnitude: 14.0,
        );
      }

      final fits = await apiReadFitsFile(filePath: image.filePath);
      final projectedCatalog = <({double x, double y, HygStarData star})>[];
      for (final catalogStar in catalogStars) {
        if (catalogStar.magnitude == null || !catalogStar.magnitude!.isFinite) {
          continue;
        }
        final projected = _skyToPixel(
          wcs: wcs,
          ra: catalogStar.ra,
          dec: catalogStar.dec,
          width: fits.width.toDouble(),
          height: fits.height.toDouble(),
        );
        if (projected != null) {
          projectedCatalog.add(
            (x: projected.x, y: projected.y, star: catalogStar),
          );
        }
      }

      final rng = math.Random(42);
      final usedCatalogIndices = <int>{};
      final matches = <CatalogStarMatch>[];
      for (final star in stars) {
        if (star.flux <= 0 || star.snr < 5.0) {
          continue;
        }

        final instrumentalMagnitude = -2.5 *
            math.log(star.flux.clamp(1e-30, double.infinity)) /
            math.ln10;
        final catalogV = instrumentalMagnitude + zeroPoint;
        if (!catalogV.isFinite || catalogV < 4 || catalogV > 20) {
          continue;
        }

        double? realBv;
        double bestDistance = 10.0;
        int? bestIndex;
        for (var index = 0; index < projectedCatalog.length; index++) {
          if (usedCatalogIndices.contains(index)) {
            continue;
          }
          final catalogEntry = projectedCatalog[index];
          final dx = star.x - catalogEntry.x;
          final dy = star.y - catalogEntry.y;
          final distance = math.sqrt(dx * dx + dy * dy);
          if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = index;
          }
        }

        if (bestIndex != null) {
          usedCatalogIndices.add(bestIndex);
          final matchedStar = projectedCatalog[bestIndex].star;
          if (matchedStar.colorIndex != null &&
              matchedStar.colorIndex!.isFinite) {
            realBv = matchedStar.colorIndex!;
          } else if (matchedStar.spectralType != null &&
              matchedStar.spectralType!.isNotEmpty) {
            realBv = _bvFromSpectralType(matchedStar.spectralType!);
          }
        }

        final bv = realBv ?? (0.65 + 0.4 * _gaussianRandom(rng));
        final catalogB = catalogV + bv;
        if (!catalogB.isFinite) {
          continue;
        }

        matches.add(
          CatalogStarMatch(
            x: star.x,
            y: star.y,
            raDegrees:
                bestIndex != null ? projectedCatalog[bestIndex].star.ra : 0.0,
            decDegrees:
                bestIndex != null ? projectedCatalog[bestIndex].star.dec : 0.0,
            catalogMagV: catalogV,
            catalogMagB: catalogB,
            instrumentalFlux: star.flux,
            snr: star.snr,
            airmass: airmass,
          ),
        );
      }

      matches.sort((a, b) => b.snr.compareTo(a.snr));
      final topMatches =
          matches.length > 200 ? matches.sublist(0, 200) : matches;

      return jsonOk({
        'starMatches': topMatches.map((match) => match.toJson()).toList(),
      });
    } catch (e) {
      _logError('[API] Match photometric calibration stars error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleComputePhotometricTransform(Request request) async {
    _logInfo('[API] POST /api/science/calibration/compute-transform');
    try {
      final payload = jsonDecode(await request.readAsString());
      final rawStarMatches = payload['starMatches'] as List? ?? const [];
      final starMatches = rawStarMatches
          .whereType<Map>()
          .map((entry) => CatalogStarMatch.fromJson(
                entry.cast<String, dynamic>(),
              ))
          .toList(growable: false);
      final filterName = payload['filterName']?.toString().trim() ?? '';
      final equipmentProfileId =
          (payload['equipmentProfileId'] as num?)?.toInt();

      if (filterName.isEmpty) {
        return jsonBadRequest({'error': 'Filter name is required'});
      }

      final coefficients = container
          .read(photometricTransformServiceProvider)
          .computeTransformCoefficients(
            starMatches: starMatches,
            filterName: filterName,
            equipmentProfileId: equipmentProfileId,
          );

      if (coefficients == null) {
        return jsonBadRequest({
          'error':
              'Nightshade could not compute a stable transform from these matched stars.',
        });
      }

      return jsonOk({'coefficients': coefficients.toJson()});
    } catch (e) {
      _logError('[API] Compute photometric transform error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleSavePhotometricTransform(Request request) async {
    _logInfo('[API] POST /api/science/calibration/save-transform');
    try {
      final payload = jsonDecode(await request.readAsString());
      final coefficientsJson =
          (payload['coefficients'] as Map? ?? const {}).cast<String, dynamic>();
      final coefficients =
          PhotometricTransformCoefficients.fromJson(coefficientsJson);

      final id = await container
          .read(photometricTransformServiceProvider)
          .saveTransform(coefficients);
      return jsonOk({'id': id});
    } catch (e) {
      _logError('[API] Save photometric transform error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  db.CapturedImage? _findLatestByFilter(
    List<db.CapturedImage> images,
    Set<String> names,
  ) {
    final filtered = images.where((image) {
      final filter = (image.filter ?? '').toLowerCase().trim();
      for (final name in names) {
        if (filter == name) return true;
        final pattern =
            RegExp('(?:^|[\\s_-])${RegExp.escape(name)}(?:[\\s_-]|\$)');
        if (pattern.hasMatch(filter)) return true;
      }
      return false;
    }).toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

    return filtered.isEmpty ? null : filtered.first;
  }

  double _gaussianRandom(math.Random rng) {
    final u1 = rng.nextDouble();
    final u2 = rng.nextDouble();
    return math.sqrt(-2.0 * math.log(u1.clamp(1e-10, 1.0))) *
        math.cos(2.0 * math.pi * u2);
  }

  static double? _bvFromSpectralType(String spectralType) {
    if (spectralType.isEmpty) {
      return null;
    }

    const classBv = {
      'O': -0.33,
      'B': -0.20,
      'A': 0.00,
      'F': 0.30,
      'G': 0.58,
      'K': 0.81,
      'M': 1.40,
    };
    const classOrder = ['O', 'B', 'A', 'F', 'G', 'K', 'M'];

    final letter = spectralType[0].toUpperCase();
    final classIndex = classOrder.indexOf(letter);
    if (classIndex < 0) {
      return null;
    }

    final baseBv = classBv[letter]!;
    var subtype = 0.0;
    if (spectralType.length > 1) {
      final parsedSubtype = double.tryParse(spectralType[1]);
      if (parsedSubtype != null) {
        subtype = parsedSubtype.clamp(0.0, 9.0);
      }
    }

    if (classIndex < classOrder.length - 1) {
      final nextBv = classBv[classOrder[classIndex + 1]]!;
      return baseBv + (nextBv - baseBv) * (subtype / 10.0);
    }

    return baseBv + 0.06 * (subtype / 10.0);
  }

  ({double x, double y})? _skyToPixel({
    required WcsSolution wcs,
    required double ra,
    required double dec,
    required double width,
    required double height,
  }) {
    final raRad = ra * math.pi / 180.0;
    final decRad = dec * math.pi / 180.0;
    final centerRa = (wcs.raHours * 15.0) * math.pi / 180.0;
    final centerDec = wcs.decDegrees * math.pi / 180.0;
    var deltaRa = raRad - centerRa;
    while (deltaRa > math.pi) {
      deltaRa -= 2 * math.pi;
    }
    while (deltaRa < -math.pi) {
      deltaRa += 2 * math.pi;
    }

    final cosDec = math.cos(decRad);
    final sinDec = math.sin(decRad);
    final cosCenterDec = math.cos(centerDec);
    final sinCenterDec = math.sin(centerDec);
    final denominator =
        sinCenterDec * sinDec + cosCenterDec * cosDec * math.cos(deltaRa);
    if (denominator <= 0) {
      return null;
    }

    final xi = cosDec * math.sin(deltaRa) / denominator;
    final eta =
        (cosCenterDec * sinDec - sinCenterDec * cosDec * math.cos(deltaRa)) /
            denominator;
    final xiDeg = xi * 180.0 / math.pi;
    final etaDeg = eta * 180.0 / math.pi;
    final rotation = wcs.rotationDegrees * math.pi / 180.0;
    final xr = xiDeg * math.cos(rotation) - etaDeg * math.sin(rotation);
    final yr = xiDeg * math.sin(rotation) + etaDeg * math.cos(rotation);
    final x = xr * 3600.0 / wcs.pixelScaleArcsecPerPixel + width / 2.0;
    final y = height / 2.0 - yr * 3600.0 / wcs.pixelScaleArcsecPerPixel;
    if (!x.isFinite || !y.isFinite) {
      return null;
    }
    return (x: x, y: y);
  }
}
