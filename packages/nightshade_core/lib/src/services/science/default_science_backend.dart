import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../backend/nightshade_backend.dart';
import '../../models/science/science_models.dart';
import '../../providers/backend_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/logging_service.dart';
import 'science_backend.dart';

class DefaultScienceBackend implements ScienceBackend {
  final Ref _ref;

  DefaultScienceBackend(this._ref);

  NightshadeBackend get _backend => _ref.read(backendProvider);
  LoggingService get _logger => _ref.read(loggingServiceProvider);

  @override
  Future<SolverCapabilities> getSolverCapabilities() async {
    final solver = _resolveSolverId().toLowerCase();
    if (solver == 'astap' || solver == 'astrometry.net') {
      return const SolverCapabilities(
        hasResidualVectors: true,
        hasDistortionTerms: true,
        supportsBatchSolve: true,
        supportsLocalIndexOnly: true,
      );
    }
    if (solver == 'platesolve2') {
      return const SolverCapabilities(
        hasResidualVectors: false,
        hasDistortionTerms: false,
        supportsBatchSolve: false,
        supportsLocalIndexOnly: true,
      );
    }
    return const SolverCapabilities();
  }

  @override
  Future<WcsSolution?> solveForScience(
      String imagePath, SolveOptions options) async {
    try {
      final result = await _backend.plateSolve(
        imagePath: imagePath,
        ra: options.raHintHours,
        dec: options.decHintDegrees,
        fovDegrees: options.searchRadiusDegrees,
      );
      if (!result.success) return null;
      return WcsSolution(
        raHours: result.ra,
        decDegrees: result.dec,
        pixelScaleArcsecPerPixel: result.pixelScale,
        rotationDegrees: result.rotation,
        fieldWidthDegrees: result.fieldWidth,
        fieldHeightDegrees: result.fieldHeight,
        solverId: _resolveSolverId(),
      );
    } catch (error, stack) {
      _logger.warning(
        'Science solve failed for $imagePath: $error\n$stack',
        source: 'ScienceBackend',
      );
      return null;
    }
  }

  @override
  Future<List<StarMeasurement>> measureStars(
    String imagePath,
    PhotometryOptions options,
  ) async {
    try {
      final config = StarDetectionConfigApi(
        detectionSigma: 4.0,
        minArea: 4,
        maxArea: 1024,
        maxEccentricity: 0.95,
        saturationLimit: 65535,
        hfrRadius: math.max(options.apertureRadiusPixels, 4),
        minHfr: 0.6,
        minSnr: options.minSnr,
        maxSharpness: 100.0,
      );
      final result =
          await apiDetectStarsInFile(filePath: imagePath, config: config);
      return result.stars
          .where((s) =>
              s.snr >= options.minSnr && s.flux > 0 && s.fwhm > 0 && s.hfr > 0)
          .map(
            (s) => StarMeasurement(
              x: s.x,
              y: s.y,
              flux: s.flux,
              hfr: s.hfr,
              fwhm: s.fwhm,
              snr: s.snr,
              eccentricity: s.eccentricity,
              sharpness: s.sharpness,
              background: s.background,
              peak: s.peak,
            ),
          )
          .toList(growable: false);
    } catch (error, stack) {
      _logger.warning(
        'Star measurement failed for $imagePath: $error\n$stack',
        source: 'ScienceBackend',
      );
      return const [];
    }
  }

  @override
  Future<FramePhotometricCalibration?> calibrateFramePhotometry(
    String imagePath,
    WcsSolution wcs,
    PhotometricCatalogSource catalog,
    ScienceFrameContext? frameContext,
  ) async {
    final context = frameContext;
    if (context == null) {
      _logger.warning(
        'Photometric calibration skipped for $imagePath: missing frame context (timestamp/exposure metadata unavailable).',
        source: 'ScienceBackend',
      );
      return null;
    }
    final timestamp = context.capturedAt;
    final rawExposureSeconds = context.exposureSeconds;
    if (!rawExposureSeconds.isFinite || rawExposureSeconds <= 0) {
      _logger.warning(
        'Photometric calibration skipped for $imagePath: invalid exposureSeconds=${context.exposureSeconds}.',
        source: 'ScienceBackend',
      );
      return null;
    }
    final exposureSeconds = rawExposureSeconds.clamp(0.001, double.infinity);

    final stars =
        await measureStars(imagePath, const PhotometryOptions(minSnr: 5.0));
    if (stars.length < 8) {
      return FramePhotometricCalibration(
        capturedImageId: context.capturedImageId,
        sessionId: context.sessionId,
        timestamp: timestamp,
        airmass: context.airmass,
        exposureSeconds: exposureSeconds,
        isCalibrated: false,
        matchedStarCount: stars.length,
        calibrationRms: 1.0,
        solverId: wcs.solverId,
        catalogSource: catalog,
      );
    }

    final matches = await _catalogMatches(
      imagePath: imagePath,
      wcs: wcs,
      detectedStars: stars,
      maxCatalogMag: 12.5,
      maxMatchPx: 9.0,
    );
    if (matches.length < 8) {
      return FramePhotometricCalibration(
        capturedImageId: context.capturedImageId,
        sessionId: context.sessionId,
        timestamp: timestamp,
        airmass: context.airmass,
        exposureSeconds: exposureSeconds,
        isCalibrated: false,
        matchedStarCount: matches.length,
        calibrationRms: 0.8,
        solverId: wcs.solverId,
        catalogSource: catalog,
      );
    }

    final zpSamples = matches
        .map((m) {
          final normalizedFlux =
              (m.detected.flux / exposureSeconds).clamp(1e-9, double.infinity);
          return m.catalogMag + 2.5 * math.log(normalizedFlux) / math.ln10;
        })
        .where((v) => v.isFinite)
        .toList(growable: false);
    final clipped = _sigmaClip(zpSamples, sigma: 2.8, iterations: 4);
    if (clipped.length < 6) {
      return FramePhotometricCalibration(
        capturedImageId: context.capturedImageId,
        sessionId: context.sessionId,
        timestamp: timestamp,
        airmass: context.airmass,
        exposureSeconds: exposureSeconds,
        isCalibrated: false,
        matchedStarCount: clipped.length,
        calibrationRms: 0.8,
        solverId: wcs.solverId,
        catalogSource: catalog,
      );
    }

    final zeroPoint = _median(clipped);
    final rms = math.sqrt(
      clipped.map((v) => v - zeroPoint).fold<double>(0, (s, d) => s + d * d) /
          clipped.length,
    );

    final bg = _median(
      stars
          .map((s) => s.background)
          .where((v) => v.isFinite && v >= 0)
          .toList(growable: false),
    );
    final fwhmEstimate = _median(
      stars
          .map((s) => s.fwhm)
          .where((v) => v.isFinite && v > 0.0)
          .toList(growable: false),
    );
    final apertureRadius = fwhmEstimate > 0
        ? (1.35 * fwhmEstimate).clamp(3.5, 10.0).toDouble()
        : 6.0;
    final aperturePixels = math.pi * apertureRadius * apertureRadius;
    final readNoise = await _readNoiseEstimate();
    double? lim5;
    double? lim3;
    if (readNoise != null) {
      final noise = math
          .sqrt(aperturePixels * (bg + readNoise * readNoise))
          .clamp(1e-6, double.infinity);
      lim5 =
          zeroPoint - 2.5 * math.log((5.0 * noise) / exposureSeconds) / math.ln10;
      lim3 =
          zeroPoint - 2.5 * math.log((3.0 * noise) / exposureSeconds) / math.ln10;
    } else {
      _logger.warning(
        'Limiting magnitude omitted for $imagePath: camera read noise is not configured.',
        source: 'ScienceBackend',
      );
    }

    return FramePhotometricCalibration(
      capturedImageId: context.capturedImageId,
      sessionId: context.sessionId,
      timestamp: timestamp,
      airmass: context.airmass,
      exposureSeconds: exposureSeconds,
      isCalibrated: true,
      zeroPoint: zeroPoint,
      limitingMag3Sigma: lim3,
      limitingMag5Sigma: lim5,
      matchedStarCount: clipped.length,
      calibrationRms: rms.clamp(0.0, 1.5),
      solverId: wcs.solverId,
      catalogSource: catalog,
    );
  }

  @override
  Future<TransparencySample?> estimateTransparency(
    List<FramePhotometricCalibration> recentCalibrations,
    TransparencyOptions options,
  ) async {
    final calibrations = recentCalibrations
        .where((c) =>
            c.isCalibrated && c.zeroPoint != null && c.zeroPoint!.isFinite)
        .toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (calibrations.length < options.minimumSampleCount) return null;

    final window = calibrations.length > options.rollingWindowSize
        ? calibrations.sublist(calibrations.length - options.rollingWindowSize)
        : calibrations;
    if (window.length < options.minimumSampleCount) return null;

    final withAirmass = window
        .where((c) => c.airmass != null && c.airmass!.isFinite)
        .toList(growable: false);
    // Leave-one-out needs one additional sample beyond the minimum,
    // because the latest sample is held out from the fit.
    final useAirmassFit = withAirmass.length >= options.minimumSampleCount + 1;

    double transparency = 100.0;
    double extinction = 0.0;
    double confidence = 0.0;

    if (useAirmassFit) {
      // Leave-one-out: fit the airmass model on all samples EXCEPT
      // the latest, then evaluate the residual of the held-out last
      // point.  This avoids the self-inclusion bias that would
      // suppress the residual and hide real transparency changes.
      final fitData = withAirmass.sublist(0, withAirmass.length - 1);
      final x = fitData.map((c) => c.airmass!).toList(growable: false);
      final y = fitData.map((c) => c.zeroPoint!).toList(growable: false);
      final allZps =
          withAirmass.map((c) => c.zeroPoint!).toList(growable: false);
      final yScatter = _robustStdDev(allZps);
      final span = (x.reduce(math.max) - x.reduce(math.min)).abs();
      if (span < options.minAirmassSpan) {
        return null;
      }

      final fit = _weightedLinearFit(
        x: x,
        y: y,
        weightBy: fitData
            .map((c) => 1.0 / math.max(0.03, c.calibrationRms))
            .toList(growable: false),
      );
      if (fit == null) {
        return null;
      }

      final slope = fit.slope;
      final intercept = fit.intercept;
      extinction = math.max(0.0, -slope);

      // Transparency = how much the ACTUAL latest ZP deviates from what
      // the airmass model PREDICTS.  A clear sky gives residual ≈ 0 →
      // transparency ≈ 100%, regardless of airmass.  Clouds / haze push
      // the actual ZP below the prediction → transparency < 100%.
      final currentAirmass = withAirmass.last.airmass!.clamp(1.0, 5.0);
      final predictedZp = intercept + slope * currentAirmass;
      final actualZp = withAirmass.last.zeroPoint!;
      final residualMag =
          predictedZp - actualZp; // positive ⇒ dimmer than expected
      transparency = (math.pow(10.0, -0.4 * residualMag) * 100.0)
          .clamp(0.0, 100.0)
          .toDouble();

      final sampleFactor =
          (withAirmass.length / options.rollingWindowSize).clamp(0.25, 1.0);
      final fitPenalty = math.exp(-(fit.rms / 0.12).clamp(0.0, 4.0));
      final scatterPenalty = math.exp(-(yScatter / 0.2).clamp(0.0, 4.0));
      confidence = (sampleFactor * fitPenalty * scatterPenalty)
          .clamp(0.1, 1.0)
          .toDouble();
    } else {
      final zps = window.map((c) => c.zeroPoint!).toList(growable: false);
      final baseline = _percentile(zps, 0.9);
      final current = window.last.zeroPoint!;
      final deltaMag = baseline - current;
      transparency = (math.pow(10.0, -0.4 * deltaMag) * 100.0)
          .clamp(0.0, 100.0)
          .toDouble();
      extinction = math.max(0.0, deltaMag);

      final scatter = _robustStdDev(zps);
      final sampleFactor = (window.length / options.rollingWindowSize)
          .clamp(0.2, 1.0)
          .toDouble();
      final stabilityPenalty = math.exp(-(scatter / 0.25).clamp(0.0, 4.0));
      confidence =
          (sampleFactor * stabilityPenalty).clamp(0.15, 1.0).toDouble();
    }

    final quality = transparency >= 95
        ? 'Excellent'
        : transparency >= 85
            ? 'Good'
            : transparency >= 70
                ? 'Fair'
                : 'Poor';

    return TransparencySample(
      capturedImageId: window.last.capturedImageId,
      sessionId: window.last.sessionId,
      timestamp: window.last.timestamp,
      transparencyPercent: transparency,
      extinctionCoefficient: extinction,
      qualityBucket: quality,
      confidence: confidence,
    );
  }

  @override
  Future<PsfFieldMap> buildPsfFieldMap(
    String imagePath,
    WcsSolution? wcs,
    PsfMapOptions options,
  ) async {
    final stars =
        await measureStars(imagePath, const PhotometryOptions(minSnr: 4.0));
    final usable = stars
        .where((s) =>
            s.snr >= 4 &&
            s.eccentricity <= 0.98 &&
            s.fwhm.isFinite &&
            s.hfr.isFinite &&
            s.peak < 65535)
        .toList(growable: false);
    if (usable.isEmpty) {
      return PsfFieldMap(
        gridRows: options.gridRows,
        gridCols: options.gridCols,
        tiles: const [],
      );
    }

    final fits = await apiReadFitsFile(filePath: imagePath);
    final tileW = fits.width / options.gridCols;
    final tileH = fits.height / options.gridRows;
    final buckets = <(int, int), List<StarMeasurement>>{};
    for (final star in usable) {
      final col = (star.x / tileW).floor().clamp(0, options.gridCols - 1);
      final row = (star.y / tileH).floor().clamp(0, options.gridRows - 1);
      buckets.putIfAbsent((row, col), () => <StarMeasurement>[]).add(star);
    }

    final tiles = <PsfTileMetric>[];
    for (var row = 0; row < options.gridRows; row++) {
      for (var col = 0; col < options.gridCols; col++) {
        final bucket = buckets[(row, col)] ?? const <StarMeasurement>[];
        if (bucket.isEmpty) {
          tiles.add(PsfTileMetric(
            row: row,
            col: col,
            starCount: 0,
            medianFwhm: 0,
            medianHfr: 0,
            medianEccentricity: 0,
            roundness: 0,
          ));
          continue;
        }
        final fwhm = _trimmedMedian(bucket.map((s) => s.fwhm).toList(), 0.15);
        final hfr = _trimmedMedian(bucket.map((s) => s.hfr).toList(), 0.15);
        final ecc =
            _trimmedMedian(bucket.map((s) => s.eccentricity).toList(), 0.15);
        tiles.add(PsfTileMetric(
          row: row,
          col: col,
          starCount: bucket.length,
          medianFwhm: fwhm,
          medianHfr: hfr,
          medianEccentricity: ecc,
          roundness: (1.0 - ecc).clamp(0.0, 1.0),
        ));
      }
    }
    return PsfFieldMap(
        gridRows: options.gridRows, gridCols: options.gridCols, tiles: tiles);
  }

  @override
  Future<AstrometricResidualMap?> computeAstrometricResiduals(
    String imagePath,
    WcsSolution wcs,
    AstrometryOptions options,
  ) async {
    final stars =
        await measureStars(imagePath, const PhotometryOptions(minSnr: 4.0));
    if (stars.isEmpty) return null;
    final matches = await _catalogMatches(
      imagePath: imagePath,
      wcs: wcs,
      detectedStars: stars,
      maxCatalogMag: 12.5,
      maxMatchPx: 10.0,
    );
    if (matches.length < 6) return null;

    final scale = wcs.pixelScaleArcsecPerPixel;
    final vectors = matches.take(options.sampleCount).map((m) {
      final dx = (m.detected.x - m.catalogX) * scale;
      final dy = (m.detected.y - m.catalogY) * scale;
      return ResidualVectorSample(
        x: m.detected.x,
        y: m.detected.y,
        dxArcsec: dx,
        dyArcsec: dy,
        magnitudeArcsec: math.sqrt(dx * dx + dy * dy),
      );
    }).toList(growable: false);
    if (vectors.isEmpty) return null;

    final rms = math.sqrt(vectors.fold<double>(
            0.0, (s, v) => s + v.magnitudeArcsec * v.magnitudeArcsec) /
        vectors.length);
    final meanX =
        vectors.fold<double>(0.0, (s, v) => s + v.dxArcsec) / vectors.length;
    final meanY =
        vectors.fold<double>(0.0, (s, v) => s + v.dyArcsec) / vectors.length;
    final suggestion = rms > 2.0
        ? 'check_polar_alignment'
        : meanX.abs() > 0.5 && meanY.abs() > 0.5
            ? 'possible_field_rotation'
            : meanX.abs() > 0.5
                ? 'possible_cone_error'
                : meanY.abs() > 0.5
                    ? 'possible_flexure'
                    : null;
    return AstrometricResidualMap(
        vectors: vectors, rmsArcsec: rms, suggestionCode: suggestion);
  }

  @override
  Future<List<MovingObjectMatch>> detectMovingObjects(
    List<String> imagePaths,
    WcsSolution wcs,
    MovingObjectOptions options,
  ) async {
    if (imagePaths.length < 2) return const [];
    final firstPath = imagePaths.first;
    final lastPath = imagePaths.last;
    final first =
        await measureStars(firstPath, const PhotometryOptions(minSnr: 5.0));
    final last =
        await measureStars(lastPath, const PhotometryOptions(minSnr: 5.0));
    if (first.isEmpty || last.isEmpty) return const [];

    final firstFits = await apiReadFitsFile(filePath: firstPath);
    final lastFits = await apiReadFitsFile(filePath: lastPath);
    final dtMin =
        _deltaMinutes(firstFits.dateObs, lastFits.dateObs, imagePaths.length);

    // When 3+ frames are available, measure the middle frame for linear
    // motion validation — a candidate must also appear near the
    // interpolated position in this frame.
    final midIndex = imagePaths.length ~/ 2;
    final bool hasMiddleFrame = imagePaths.length >= 3 &&
        midIndex > 0 &&
        midIndex < imagePaths.length - 1;
    List<StarMeasurement>? midStars;
    double midFraction = 0.5; // interpolation factor (0 = first, 1 = last)
    if (hasMiddleFrame) {
      midStars = await measureStars(
          imagePaths[midIndex], const PhotometryOptions(minSnr: 5.0));
      midFraction = midIndex / (imagePaths.length - 1);
    }

    // Maximum deviation from linear interpolation allowed in the middle
    // frame, in pixels.  Generous enough for slight dithering / guiding
    // drift but tight enough to reject random coincidences.
    const midMatchTolerance = 4.0;

    final usedLast = <int>{};
    final matches = <MovingObjectMatch>[];
    final firstSorted = first.toList(growable: false)
      ..sort((a, b) => b.snr.compareTo(a.snr));
    for (final star in firstSorted.take(280)) {
      var bestIndex = -1;
      var bestDist = double.infinity;
      for (var i = 0; i < last.length; i++) {
        if (usedLast.contains(i)) continue;
        final dx = last[i].x - star.x;
        final dy = last[i].y - star.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < bestDist) {
          bestDist = dist;
          bestIndex = i;
        }
      }
      if (bestIndex < 0 ||
          bestDist < options.minMotionPixels ||
          bestDist > options.maxMotionPixels) {
        continue;
      }
      final matched = last[bestIndex];
      if (!_mutualNearest(star, matched, firstSorted)) continue;

      // 3-frame linear motion validation: predict where the object
      // should be in the middle frame and check for a nearby detection.
      var passedMiddleValidation = false;
      if (midStars != null && midStars.isNotEmpty) {
        final expectedX = star.x + (matched.x - star.x) * midFraction;
        final expectedY = star.y + (matched.y - star.y) * midFraction;
        var foundMid = false;
        for (final midStar in midStars) {
          final mdx = midStar.x - expectedX;
          final mdy = midStar.y - expectedY;
          if (math.sqrt(mdx * mdx + mdy * mdy) <= midMatchTolerance) {
            foundMid = true;
            break;
          }
        }
        if (!foundMid) continue;
        passedMiddleValidation = true;
      }

      usedLast.add(bestIndex);

      final dxPx = matched.x - star.x;
      final dyPx = matched.y - star.y;
      // Convert to sky-up convention (Y increases toward North) then
      // apply the inverse WCS rotation (R^T) so the position angle is
      // measured in celestial coordinates (N through E).
      final dxUp = dxPx;
      final dyUp = -dyPx; // pixel Y-axis is flipped relative to sky
      final rotRad = wcs.rotationDegrees * math.pi / 180.0;
      final dxSky = dxUp * math.cos(rotRad) + dyUp * math.sin(rotRad);
      final dySky = -dxUp * math.sin(rotRad) + dyUp * math.cos(rotRad);
      final pa = (math.atan2(dxSky, dySky) * 180.0 / math.pi + 360.0) % 360.0;
      final motion = (bestDist * wcs.pixelScaleArcsecPerPixel) / dtMin;
      final mid = _pixelToSky(
        wcs: wcs,
        x: (star.x + matched.x) / 2.0,
        y: (star.y + matched.y) / 2.0,
        imageWidth: firstFits.width.toDouble(),
        imageHeight: firstFits.height.toDouble(),
      );
      if (mid == null) continue;

      final snrScore =
          (((star.snr + matched.snr) * 0.5) / 20.0).clamp(0.2, 1.0).toDouble();
      final motionScore = ((bestDist - options.minMotionPixels) /
              (options.maxMotionPixels - options.minMotionPixels))
          .clamp(0.0, 1.0)
          .toDouble();
      // Boost confidence only when 3-frame validation actually passed.
      final validationBonus = passedMiddleValidation ? 0.10 : 0.0;
      final confidence =
          (0.65 * snrScore + 0.35 * motionScore + validationBonus)
              .clamp(0.15, 0.98)
              .toDouble();
      matches.add(MovingObjectMatch(
        candidateId:
            'mo_${mid.ra.toStringAsFixed(5)}_${mid.dec.toStringAsFixed(5)}_${matches.length + 1}',
        raDegrees: mid.ra,
        decDegrees: mid.dec,
        motionArcsecPerMinute: motion,
        positionAngleDegrees: pa,
        confidence: confidence,
        isKnownObject: false,
      ));
    }
    matches.sort((a, b) => b.confidence.compareTo(a.confidence));
    return matches.take(40).toList(growable: false);
  }

  @override
  Future<(ScienceFrameQualityMetrics, List<ScienceTileMetric>)>
      computeLastCaptureQualityMaps({
    required String deviceId,
    required int gridRows,
    required int gridCols,
    required int lowClipAdu,
    required int highClipAdu,
    required DateTime timestamp,
    int? capturedImageId,
    int? sessionId,
  }) async {
    try {
      final result = await apiComputeLastCaptureQualityMaps(
        deviceId: deviceId,
        gridRows: gridRows,
        gridCols: gridCols,
        lowClipAdu: lowClipAdu,
        highClipAdu: highClipAdu,
      );
      return _mapBridgeQualityResult(
        result: result,
        timestamp: timestamp,
        capturedImageId: capturedImageId,
        sessionId: sessionId,
        fallbackProcessingTier: 'live',
      );
    } catch (error, stack) {
      _logger.warning(
        'Native last-capture quality map compute failed for $deviceId; '
        'falling back to Dart path: $error\n$stack',
        source: 'ScienceBackend',
      );
    }

    final stopwatch = Stopwatch()..start();
    final lastImage = await apiGetLastImage(deviceId: deviceId);
    final raw = await apiGetLastRawImageData(deviceId: deviceId);

    if (lastImage.width <= 0 || lastImage.height <= 0) {
      throw StateError('Last capture dimensions are unavailable');
    }
    final expected = lastImage.width * lastImage.height;
    if (raw.length < expected) {
      throw StateError(
        'Last raw buffer too small: ${raw.length} < $expected',
      );
    }

    final result = _computeQualityMetricsFromBuffer(
      width: lastImage.width,
      height: lastImage.height,
      gridRows: gridRows,
      gridCols: gridCols,
      lowClipAdu: lowClipAdu,
      highClipAdu: highClipAdu,
      timestamp: timestamp,
      capturedImageId: capturedImageId,
      sessionId: sessionId,
      processingTier: 'live',
      sampleAt: (index) => raw[index].toDouble(),
    );
    final processingMs = stopwatch.elapsedMilliseconds;

    return (
      result.frame.copyWith(processingMs: processingMs),
      result.tiles,
    );
  }

  @override
  Future<(ScienceFrameQualityMetrics, List<ScienceTileMetric>)>
      computeFitsQualityMaps({
    required String filePath,
    required int gridRows,
    required int gridCols,
    required int lowClipAdu,
    required int highClipAdu,
    required DateTime timestamp,
    int? capturedImageId,
    int? sessionId,
  }) async {
    try {
      final result = await apiComputeFitsQualityMaps(
        filePath: filePath,
        gridRows: gridRows,
        gridCols: gridCols,
        lowClipAdu: lowClipAdu,
        highClipAdu: highClipAdu,
      );
      return _mapBridgeQualityResult(
        result: result,
        timestamp: timestamp,
        capturedImageId: capturedImageId,
        sessionId: sessionId,
        fallbackProcessingTier: 'deferred',
      );
    } catch (error, stack) {
      _logger.warning(
        'Native FITS quality map compute failed for $filePath; '
        'falling back to Dart path: $error\n$stack',
        source: 'ScienceBackend',
      );
    }

    final stopwatch = Stopwatch()..start();
    final linear = await apiReadFitsLinearData(filePath: filePath);
    if (linear.width <= 0 || linear.height <= 0) {
      throw StateError('FITS dimensions are unavailable');
    }
    final expected = linear.width * linear.height;
    if (linear.linearData.length < expected) {
      throw StateError(
        'FITS linear buffer too small: ${linear.linearData.length} < $expected',
      );
    }

    final result = _computeQualityMetricsFromBuffer(
      width: linear.width,
      height: linear.height,
      gridRows: gridRows,
      gridCols: gridCols,
      lowClipAdu: lowClipAdu,
      highClipAdu: highClipAdu,
      timestamp: timestamp,
      capturedImageId: capturedImageId,
      sessionId: sessionId,
      processingTier: 'deferred',
      sampleAt: (index) => linear.linearData[index],
    );
    final processingMs = stopwatch.elapsedMilliseconds;

    return (
      result.frame.copyWith(processingMs: processingMs),
      result.tiles,
    );
  }

  @override
  Future<LineRatioProduct> computeLineRatios(
    NarrowbandSet set,
    LineRatioOptions options,
  ) async {
    final ha = await apiReadFitsLinearData(filePath: set.hAlphaPath);
    final oiii = await apiReadFitsLinearData(filePath: set.oiiiPath);
    final sii = await apiReadFitsLinearData(filePath: set.siiPath);
    if (options.requireMatchingDimensions &&
        (ha.width != oiii.width ||
            ha.width != sii.width ||
            ha.height != oiii.height ||
            ha.height != sii.height)) {
      return LineRatioProduct(createdAt: DateTime.now(), metrics: const [
        LineRatioMetric(label: 'SII/Ha', value: 0),
        LineRatioMetric(label: 'OIII/Ha', value: 0),
        LineRatioMetric(label: 'SII/OIII', value: 0),
      ]);
    }
    final len = math.min(
      ha.linearData.length,
      math.min(oiii.linearData.length, sii.linearData.length),
    );
    if (len <= 0) {
      return LineRatioProduct(createdAt: DateTime.now(), metrics: const [
        LineRatioMetric(label: 'SII/Ha', value: 0),
        LineRatioMetric(label: 'OIII/Ha', value: 0),
        LineRatioMetric(label: 'SII/OIII', value: 0),
      ]);
    }

    final stride = math.max(1, len ~/ 220000);
    final haRawSamples = <double>[];
    final oiiiRawSamples = <double>[];
    final siiRawSamples = <double>[];
    for (var i = 0; i < len; i += stride) {
      haRawSamples.add(ha.linearData[i]);
      oiiiRawSamples.add(oiii.linearData[i]);
      siiRawSamples.add(sii.linearData[i]);
    }

    final haBackground = _percentile(haRawSamples, 0.2);
    final oiiiBackground = _percentile(oiiiRawSamples, 0.2);
    final siiBackground = _percentile(siiRawSamples, 0.2);
    final haNoise = _robustStdDev(
      haRawSamples.map((value) => value - haBackground).toList(growable: false),
    ).clamp(1e-6, double.infinity);
    final oiiiNoise = _robustStdDev(
      oiiiRawSamples
          .map((value) => value - oiiiBackground)
          .toList(growable: false),
    ).clamp(1e-6, double.infinity);
    final siiNoise = _robustStdDev(
      siiRawSamples
          .map((value) => value - siiBackground)
          .toList(growable: false),
    ).clamp(1e-6, double.infinity);

    final haSamples = <double>[];
    final oiiiSamples = <double>[];
    final siiSamples = <double>[];
    final siiHa = <double>[];
    final oiiiHa = <double>[];
    final siiOiii = <double>[];
    final haExp = _requireExposureTime(
      label: 'H-alpha',
      exposureTime: ha.exposureTime,
      filePath: set.hAlphaPath,
    );
    final oiiiExp = _requireExposureTime(
      label: 'OIII',
      exposureTime: oiii.exposureTime,
      filePath: set.oiiiPath,
    );
    final siiExp = _requireExposureTime(
      label: 'SII',
      exposureTime: sii.exposureTime,
      filePath: set.siiPath,
    );
    final haThreshold = options.snrFloor * haNoise / haExp;
    final oiiiThreshold = options.snrFloor * oiiiNoise / oiiiExp;
    final siiThreshold = options.snrFloor * siiNoise / siiExp;

    for (var i = 0; i < len; i += stride) {
      var h = ((ha.linearData[i] - haBackground).clamp(0.0, double.infinity)) /
          haExp;
      var o =
          ((oiii.linearData[i] - oiiiBackground).clamp(0.0, double.infinity)) /
              oiiiExp;
      var s =
          ((sii.linearData[i] - siiBackground).clamp(0.0, double.infinity)) /
              siiExp;
      if (options.continuumCorrection) {
        final c = math.min(h, math.min(o, s)) * 0.2;
        h = (h - c).clamp(0.0, double.infinity);
        o = (o - c).clamp(0.0, double.infinity);
        s = (s - c).clamp(0.0, double.infinity);
      }
      haSamples.add(h);
      oiiiSamples.add(o);
      siiSamples.add(s);
      if (h > haThreshold && s > siiThreshold) {
        siiHa.add(s / h);
      }
      if (h > haThreshold && o > oiiiThreshold) {
        oiiiHa.add(o / h);
      }
      if (o > oiiiThreshold && s > siiThreshold) {
        siiOiii.add(s / o);
      }
    }

    final previewStrideX = math.max(1, ha.width ~/ 512);
    final previewStrideY = math.max(1, ha.height ~/ 512);
    final previewWidth = (ha.width / previewStrideX).floor();
    final previewHeight = (ha.height / previewStrideY).floor();
    final preview = Uint8List(previewWidth * previewHeight * 4);
    final hn = _percentile(haSamples, 0.99).clamp(1e-6, double.infinity);
    final on = _percentile(oiiiSamples, 0.99).clamp(1e-6, double.infinity);
    final sn = _percentile(siiSamples, 0.99).clamp(1e-6, double.infinity);

    var previewOffset = 0;
    for (var y = 0; y < previewHeight; y++) {
      final srcY = y * previewStrideY;
      for (var x = 0; x < previewWidth; x++) {
        final srcX = x * previewStrideX;
        final index = srcY * ha.width + srcX;
        if (index >= len) {
          preview[previewOffset] = 0;
          preview[previewOffset + 1] = 0;
          preview[previewOffset + 2] = 0;
          preview[previewOffset + 3] = 255;
          previewOffset += 4;
          continue;
        }
        final h = ((ha.linearData[index] - haBackground)
                .clamp(0.0, double.infinity)) /
            haExp;
        final o = ((oiii.linearData[index] - oiiiBackground)
                .clamp(0.0, double.infinity)) /
            oiiiExp;
        final s = ((sii.linearData[index] - siiBackground)
                .clamp(0.0, double.infinity)) /
            siiExp;
        preview[previewOffset] = ((h / hn).clamp(0.0, 1.0) * 255).round();
        preview[previewOffset + 1] = ((o / on).clamp(0.0, 1.0) * 255).round();
        preview[previewOffset + 2] = ((s / sn).clamp(0.0, 1.0) * 255).round();
        preview[previewOffset + 3] = 255;
        previewOffset += 4;
      }
    }

    return LineRatioProduct(
      createdAt: DateTime.now(),
      previewImage: preview,
      metrics: [
        LineRatioMetric(label: 'SII/Ha', value: _robustMedian(siiHa)),
        LineRatioMetric(label: 'OIII/Ha', value: _robustMedian(oiiiHa)),
        LineRatioMetric(label: 'SII/OIII', value: _robustMedian(siiOiii)),
      ],
    );
  }

  Future<List<_CatalogMatch>> _catalogMatches({
    required String imagePath,
    required WcsSolution wcs,
    required List<StarMeasurement> detectedStars,
    required double maxCatalogMag,
    required double maxMatchPx,
  }) async {
    final manager = CatalogManager.instance;
    if (!manager.isInitialized) return const [];
    try {
      final fits = await apiReadFitsFile(filePath: imagePath);
      final radius = (math.sqrt(wcs.fieldWidthDegrees * wcs.fieldWidthDegrees +
                      wcs.fieldHeightDegrees * wcs.fieldHeightDegrees) *
                  0.65 +
              0.3)
          .clamp(0.25, 8.0)
          .toDouble();
      final nearby = await manager.searchStarsNearby(
        ra: wcs.raHours * 15.0,
        dec: wcs.decDegrees,
        radiusDegrees: radius,
        maxMagnitude: maxCatalogMag,
      );
      if (nearby.isEmpty) return const [];

      final projected = <_ProjectedCatalogStar>[];
      for (final star in nearby) {
        if (star.magnitude == null || !star.magnitude!.isFinite) continue;
        final px = _skyToPixel(
          wcs: wcs,
          ra: star.ra,
          dec: star.dec,
          width: fits.width.toDouble(),
          height: fits.height.toDouble(),
        );
        if (px == null) continue;
        projected.add(_ProjectedCatalogStar(
          id: '${star.catalogId}_${star.ra.toStringAsFixed(6)}_${star.dec.toStringAsFixed(6)}',
          x: px.x,
          y: px.y,
          mag: star.magnitude!,
        ));
      }
      if (projected.isEmpty) return const [];

      final usedCatalog = <String>{};
      final sorted = detectedStars.toList(growable: false)
        ..sort((a, b) => b.snr.compareTo(a.snr));
      final matches = <_CatalogMatch>[];
      for (final detected in sorted) {
        _ProjectedCatalogStar? best;
        var bestDist = maxMatchPx;
        for (final catalogStar in projected) {
          if (usedCatalog.contains(catalogStar.id)) continue;
          final dx = detected.x - catalogStar.x;
          final dy = detected.y - catalogStar.y;
          final dist = math.sqrt(dx * dx + dy * dy);
          if (dist <= bestDist) {
            bestDist = dist;
            best = catalogStar;
          }
        }
        if (best != null) {
          usedCatalog.add(best.id);
          matches.add(_CatalogMatch(
            detected: detected,
            catalogX: best.x,
            catalogY: best.y,
            catalogMag: best.mag,
          ));
        }
      }
      return matches;
    } catch (error, stack) {
      _logger.warning(
        'Catalog matching failed for $imagePath: $error\n$stack',
        source: 'ScienceBackend',
      );
      return const [];
    }
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
    final cra = (wcs.raHours * 15.0) * math.pi / 180.0;
    final cdec = wcs.decDegrees * math.pi / 180.0;
    var dra = raRad - cra;
    while (dra > math.pi) dra -= 2 * math.pi;
    while (dra < -math.pi) dra += 2 * math.pi;

    final cosDec = math.cos(decRad);
    final sinDec = math.sin(decRad);
    final cosCDec = math.cos(cdec);
    final sinCDec = math.sin(cdec);
    final denom = sinCDec * sinDec + cosCDec * cosDec * math.cos(dra);
    if (denom <= 0) return null;

    final xi = cosDec * math.sin(dra) / denom;
    final eta = (cosCDec * sinDec - sinCDec * cosDec * math.cos(dra)) / denom;
    final xiDeg = xi * 180.0 / math.pi;
    final etaDeg = eta * 180.0 / math.pi;
    final rot = wcs.rotationDegrees * math.pi / 180.0;
    final xr = xiDeg * math.cos(rot) - etaDeg * math.sin(rot);
    final yr = xiDeg * math.sin(rot) + etaDeg * math.cos(rot);
    final x = xr * 3600.0 / wcs.pixelScaleArcsecPerPixel + width / 2.0;
    final y = height / 2.0 - yr * 3600.0 / wcs.pixelScaleArcsecPerPixel;
    if (!x.isFinite || !y.isFinite) return null;
    return (x: x, y: y);
  }

  ({double ra, double dec})? _pixelToSky({
    required WcsSolution wcs,
    required double x,
    required double y,
    required double imageWidth,
    required double imageHeight,
  }) {
    final xDeg = (x - imageWidth / 2.0) * wcs.pixelScaleArcsecPerPixel / 3600.0;
    final yDeg =
        (imageHeight / 2.0 - y) * wcs.pixelScaleArcsecPerPixel / 3600.0;
    final rot = wcs.rotationDegrees * math.pi / 180.0;
    final xi = (xDeg * math.cos(rot) + yDeg * math.sin(rot)) * math.pi / 180.0;
    final eta =
        (-xDeg * math.sin(rot) + yDeg * math.cos(rot)) * math.pi / 180.0;
    final rho = math.sqrt(xi * xi + eta * eta);
    final cra = (wcs.raHours * 15.0) * math.pi / 180.0;
    final cdec = wcs.decDegrees * math.pi / 180.0;
    if (rho < 1e-12) return (ra: wcs.raHours * 15.0, dec: wcs.decDegrees);

    final c = math.atan(rho);
    final sinC = math.sin(c);
    final cosC = math.cos(c);
    final sinCDec = math.sin(cdec);
    final cosCDec = math.cos(cdec);
    final dec = math.asin(cosC * sinCDec + eta * sinC * cosCDec / rho);
    final ra = cra +
        math.atan2(xi * sinC, rho * cosCDec * cosC - eta * sinCDec * sinC);
    var raDeg = ra * 180.0 / math.pi;
    while (raDeg < 0) raDeg += 360;
    while (raDeg >= 360) raDeg -= 360;
    return (ra: raDeg, dec: dec * 180.0 / math.pi);
  }

  double _deltaMinutes(String? firstObs, String? lastObs, int frameCount) {
    final t0 = firstObs == null ? null : DateTime.tryParse(firstObs);
    final t1 = lastObs == null ? null : DateTime.tryParse(lastObs);
    if (t0 != null && t1 != null) {
      return math.max(
          1.0 / 60.0, t1.difference(t0).inMilliseconds.abs() / 60000.0);
    }
    return math.max(1.0, (frameCount - 1).toDouble());
  }

  bool _mutualNearest(StarMeasurement first, StarMeasurement last,
      List<StarMeasurement> firstStars) {
    StarMeasurement? nearest;
    var best = double.infinity;
    for (final candidate in firstStars) {
      final dx = candidate.x - last.x;
      final dy = candidate.y - last.y;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < best) {
        best = d;
        nearest = candidate;
      }
    }
    return nearest == first;
  }

  List<double> _sigmaClip(List<double> values,
      {required double sigma, required int iterations}) {
    var working = values.where((v) => v.isFinite).toList(growable: true);
    if (working.length < 3) return working;
    for (var i = 0; i < iterations; i++) {
      final med = _median(working);
      final mad = _mad(working, med);
      if (mad <= 0) break;
      final limit = sigma * 1.4826 * mad;
      final filtered =
          working.where((v) => (v - med).abs() <= limit).toList(growable: true);
      if (filtered.length == working.length || filtered.length < 3) {
        working = filtered;
        break;
      }
      working = filtered;
    }
    return working;
  }

  double _robustMedian(List<double> values) {
    if (values.isEmpty) return 0.0;
    var working = values.where((v) => v.isFinite).toList(growable: true);
    if (working.isEmpty) return 0.0;
    for (var i = 0; i < 3; i++) {
      final med = _median(working);
      final mad = _mad(working, med);
      if (mad <= 0) return med;
      final limit = 3 * 1.4826 * mad;
      final filtered =
          working.where((v) => (v - med).abs() <= limit).toList(growable: true);
      if (filtered.length == working.length || filtered.length < 8)
        return _median(filtered);
      working = filtered;
    }
    return _median(working);
  }

  double _trimmedMedian(List<double> values, double trimFraction) {
    final sorted = values.where((v) => v.isFinite).toList(growable: false)
      ..sort();
    if (sorted.isEmpty) return 0.0;
    final trim =
        (sorted.length * trimFraction).floor().clamp(0, sorted.length ~/ 3);
    final start = trim;
    final end = sorted.length - trim;
    return _median(sorted.sublist(start, end <= start ? sorted.length : end));
  }

  double _median(List<double> values) {
    final sorted = values.where((v) => v.isFinite).toList(growable: false)
      ..sort();
    if (sorted.isEmpty) return 0.0;
    final m = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[m] : (sorted[m - 1] + sorted[m]) / 2.0;
  }

  double _mad(List<double> values, double median) {
    if (values.isEmpty) return 0.0;
    return _median(
        values.map((v) => (v - median).abs()).toList(growable: false));
  }

  double _robustStdDev(List<double> values) =>
      1.4826 * _mad(values, _median(values));

  _LinearFitResult? _weightedLinearFit({
    required List<double> x,
    required List<double> y,
    required List<double> weightBy,
  }) {
    if (x.length != y.length || x.length != weightBy.length || x.length < 2) {
      return null;
    }

    var sumW = 0.0;
    var sumX = 0.0;
    var sumY = 0.0;
    var sumXX = 0.0;
    var sumXY = 0.0;

    for (var i = 0; i < x.length; i++) {
      final xi = x[i];
      final yi = y[i];
      final wi = weightBy[i].clamp(1e-6, 1e6).toDouble();
      if (!xi.isFinite || !yi.isFinite || !wi.isFinite) {
        continue;
      }
      sumW += wi;
      sumX += wi * xi;
      sumY += wi * yi;
      sumXX += wi * xi * xi;
      sumXY += wi * xi * yi;
    }

    if (sumW <= 0.0) {
      return null;
    }

    final denominator = sumW * sumXX - sumX * sumX;
    if (denominator.abs() < 1e-12) {
      return null;
    }

    final slope = (sumW * sumXY - sumX * sumY) / denominator;
    final intercept = (sumY - slope * sumX) / sumW;

    var weightedResidual = 0.0;
    var residualWeight = 0.0;
    for (var i = 0; i < x.length; i++) {
      if (!x[i].isFinite || !y[i].isFinite) {
        continue;
      }
      final wi = weightBy[i].clamp(1e-6, 1e6).toDouble();
      final residual = y[i] - (intercept + slope * x[i]);
      weightedResidual += wi * residual * residual;
      residualWeight += wi;
    }
    final rms = residualWeight > 0
        ? math.sqrt(weightedResidual / residualWeight)
        : double.infinity;

    return _LinearFitResult(slope: slope, intercept: intercept, rms: rms);
  }

  double _percentile(List<double> values, double p) {
    final sorted = values.where((v) => v.isFinite).toList(growable: false)
      ..sort();
    if (sorted.isEmpty) return 0.0;
    final q = p.clamp(0.0, 1.0);
    final pos = (sorted.length - 1) * q;
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) return sorted[lo];
    final t = pos - lo;
    return sorted[lo] * (1 - t) + sorted[hi] * t;
  }

  (ScienceFrameQualityMetrics, List<ScienceTileMetric>) _mapBridgeQualityResult({
    required QualityMapsResultApi result,
    required DateTime timestamp,
    required int? capturedImageId,
    required int? sessionId,
    required String fallbackProcessingTier,
  }) {
    final frame = result.frame;
    final mappedFrame = ScienceFrameQualityMetrics(
      capturedImageId: capturedImageId,
      sessionId: sessionId,
      timestamp: timestamp,
      median: frame.median,
      mean: frame.mean,
      stdDev: frame.stdDev,
      mad: frame.mad,
      background: frame.background,
      noise: frame.noise,
      snr: frame.snr,
      dynamicRangeP1P99: frame.dynamicRangeP1P99,
      lowClipPercent: frame.lowClipPercent,
      highClipPercent: frame.highClipPercent,
      uniformityCv: frame.uniformityCv,
      gradientX: frame.gradientX,
      gradientY: frame.gradientY,
      processingTier: frame.processingTier.isEmpty
          ? fallbackProcessingTier
          : frame.processingTier,
      processingMs: frame.processingMs,
    );

    final mappedTiles = result.tiles
        .map(
          (tile) => ScienceTileMetric(
            capturedImageId: capturedImageId,
            sessionId: sessionId,
            timestamp: timestamp,
            layerType: ScienceLayerType.fromDbValue(tile.layerType),
            tileRow: tile.tileRow,
            tileCol: tile.tileCol,
            sampleCount: tile.sampleCount,
            value: tile.value,
            p05: tile.p05,
            p50: tile.p50,
            p95: tile.p95,
            auxValue: tile.auxValue,
          ),
        )
        .toList(growable: false);

    return (mappedFrame, mappedTiles);
  }

  _QualityResult _computeQualityMetricsFromBuffer({
    required int width,
    required int height,
    required int gridRows,
    required int gridCols,
    required int lowClipAdu,
    required int highClipAdu,
    required DateTime timestamp,
    required int? capturedImageId,
    required int? sessionId,
    required String processingTier,
    required double Function(int index) sampleAt,
  }) {
    final rows = gridRows.clamp(2, 128);
    final cols = gridCols.clamp(2, 128);
    final tileMetrics = <ScienceTileMetric>[];
    final tileMedians = <double>[];
    final tileNoises = <double>[];
    final tileP05 = <double>[];
    final tileP95 = <double>[];
    final tileGradX = <double>[];
    final tileGradY = <double>[];

    var globalCount = 0;
    var globalSum = 0.0;
    var globalSumSq = 0.0;
    var globalLowClip = 0;
    var globalHighClip = 0;

    final imageMidX = width ~/ 2;
    final imageMidY = height ~/ 2;

    for (var row = 0; row < rows; row++) {
      final yStart = (row * height / rows).floor();
      final yEnd =
          ((row + 1) * height / rows).floor().clamp(yStart + 1, height);
      for (var col = 0; col < cols; col++) {
        final xStart = (col * width / cols).floor();
        final xEnd =
            ((col + 1) * width / cols).floor().clamp(xStart + 1, width);

        final samples = <double>[];
        var sum = 0.0;
        var sumSq = 0.0;
        var lowClip = 0;
        var highClip = 0;
        var leftSum = 0.0;
        var rightSum = 0.0;
        var topSum = 0.0;
        var bottomSum = 0.0;
        var leftCount = 0;
        var rightCount = 0;
        var topCount = 0;
        var bottomCount = 0;

        for (var y = yStart; y < yEnd; y++) {
          final isTop = y < imageMidY;
          for (var x = xStart; x < xEnd; x++) {
            final value = sampleAt(y * width + x);
            if (!value.isFinite) {
              continue;
            }
            samples.add(value);
            sum += value;
            sumSq += value * value;
            globalSum += value;
            globalSumSq += value * value;
            globalCount++;

            if (value <= lowClipAdu) {
              lowClip++;
              globalLowClip++;
            }
            if (value >= highClipAdu) {
              highClip++;
              globalHighClip++;
            }

            final isLeft = x < imageMidX;
            if (isLeft) {
              leftSum += value;
              leftCount++;
            } else {
              rightSum += value;
              rightCount++;
            }
            if (isTop) {
              topSum += value;
              topCount++;
            } else {
              bottomSum += value;
              bottomCount++;
            }
          }
        }

        if (samples.isEmpty) {
          continue;
        }

        samples.sort();
        final count = samples.length;
        final mean = sum / count;
        final variance = math.max(0.0, (sumSq / count) - (mean * mean));
        final stdDev = math.sqrt(variance);
        final p05 = _percentileSorted(samples, 0.05);
        final p50 = _percentileSorted(samples, 0.50);
        final p95 = _percentileSorted(samples, 0.95);
        final cv = mean.abs() < 1e-6 ? 0.0 : stdDev / mean.abs();
        final lowClipPercent = 100.0 * lowClip / count;
        final highClipPercent = 100.0 * highClip / count;
        final snr = stdDev <= 0.0 ? 0.0 : mean / stdDev;
        final gradX = ((rightCount == 0 ? mean : rightSum / rightCount) -
                (leftCount == 0 ? mean : leftSum / leftCount))
            .toDouble();
        final gradY = ((bottomCount == 0 ? mean : bottomSum / bottomCount) -
                (topCount == 0 ? mean : topSum / topCount))
            .toDouble();
        final gradMag = math.sqrt(gradX * gradX + gradY * gradY);

        tileMedians.add(p50);
        tileNoises.add(stdDev);
        tileP05.add(p05);
        tileP95.add(p95);
        tileGradX.add(gradX);
        tileGradY.add(gradY);

        tileMetrics.add(
          ScienceTileMetric(
            capturedImageId: capturedImageId,
            sessionId: sessionId,
            timestamp: timestamp,
            layerType: ScienceLayerType.uniformity,
            tileRow: row,
            tileCol: col,
            sampleCount: count,
            value: cv,
            p05: p05,
            p50: p50,
            p95: p95,
            auxValue: gradMag,
          ),
        );
        tileMetrics.add(
          ScienceTileMetric(
            capturedImageId: capturedImageId,
            sessionId: sessionId,
            timestamp: timestamp,
            layerType: ScienceLayerType.clipLow,
            tileRow: row,
            tileCol: col,
            sampleCount: count,
            value: lowClipPercent,
            p05: lowClipPercent,
            p50: lowClipPercent,
            p95: lowClipPercent,
            auxValue: lowClip.toDouble(),
          ),
        );
        tileMetrics.add(
          ScienceTileMetric(
            capturedImageId: capturedImageId,
            sessionId: sessionId,
            timestamp: timestamp,
            layerType: ScienceLayerType.clipHigh,
            tileRow: row,
            tileCol: col,
            sampleCount: count,
            value: highClipPercent,
            p05: highClipPercent,
            p50: highClipPercent,
            p95: highClipPercent,
            auxValue: highClip.toDouble(),
          ),
        );
        tileMetrics.add(
          ScienceTileMetric(
            capturedImageId: capturedImageId,
            sessionId: sessionId,
            timestamp: timestamp,
            layerType: ScienceLayerType.background,
            tileRow: row,
            tileCol: col,
            sampleCount: count,
            value: p50,
            p05: p05,
            p50: p50,
            p95: p95,
            auxValue: stdDev,
          ),
        );
        tileMetrics.add(
          ScienceTileMetric(
            capturedImageId: capturedImageId,
            sessionId: sessionId,
            timestamp: timestamp,
            layerType: ScienceLayerType.snr,
            tileRow: row,
            tileCol: col,
            sampleCount: count,
            value: snr,
            p05: 0.0,
            p50: snr,
            p95: snr,
            auxValue: stdDev,
          ),
        );
      }
    }

    final safeCount = math.max(1, globalCount);
    final globalMean = globalSum / safeCount;
    final globalStdDev = math.sqrt(
        math.max(0.0, (globalSumSq / safeCount) - (globalMean * globalMean)));
    final median = tileMedians.isEmpty ? 0.0 : _median(tileMedians);
    final mad = tileMedians.isEmpty ? 0.0 : _mad(tileMedians, median);
    final background = tileMedians.isEmpty ? globalMean : _median(tileMedians);
    final noise = tileNoises.isEmpty ? globalStdDev : _median(tileNoises);
    final snr = noise <= 0.0 ? 0.0 : (globalMean / noise);
    final p1 = tileP05.isEmpty ? 0.0 : _percentile(tileP05, 0.2);
    final p99 = tileP95.isEmpty ? 0.0 : _percentile(tileP95, 0.8);
    final dynamicRange = math.max(0.0, p99 - p1);
    final gradientX = tileGradX.isEmpty
        ? 0.0
        : tileGradX.fold<double>(0.0, (sum, value) => sum + value) /
            tileGradX.length;
    final gradientY = tileGradY.isEmpty
        ? 0.0
        : tileGradY.fold<double>(0.0, (sum, value) => sum + value) /
            tileGradY.length;

    final frame = ScienceFrameQualityMetrics(
      capturedImageId: capturedImageId,
      sessionId: sessionId,
      timestamp: timestamp,
      median: median,
      mean: globalMean,
      stdDev: globalStdDev,
      mad: mad,
      background: background,
      noise: noise,
      snr: snr,
      dynamicRangeP1P99: dynamicRange,
      lowClipPercent: 100.0 * globalLowClip / safeCount,
      highClipPercent: 100.0 * globalHighClip / safeCount,
      uniformityCv:
          background.abs() < 1e-6 ? 0.0 : globalStdDev / background.abs(),
      gradientX: gradientX,
      gradientY: gradientY,
      processingTier: processingTier,
      processingMs: 0,
    );
    return _QualityResult(frame: frame, tiles: tileMetrics);
  }

  double _percentileSorted(List<double> sortedValues, double p) {
    if (sortedValues.isEmpty) {
      return 0.0;
    }
    final q = p.clamp(0.0, 1.0);
    final pos = (sortedValues.length - 1) * q;
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) {
      return sortedValues[lo];
    }
    final t = pos - lo;
    return sortedValues[lo] * (1 - t) + sortedValues[hi] * t;
  }

  String _resolveSolverId() {
    final settings = _ref.read(appSettingsProvider).valueOrNull;
    return settings?.plateSolver ?? 'ASTAP';
  }

  /// Require valid FITS exposure metadata for physically meaningful
  /// line-ratio normalization.
  double _requireExposureTime({
    required String label,
    required double? exposureTime,
    required String filePath,
  }) {
    if (exposureTime != null && exposureTime.isFinite && exposureTime > 0) {
      return exposureTime.clamp(0.001, double.infinity);
    }
    throw StateError(
      'Missing exposure metadata for $label frame: $filePath. '
      'Line-ratio normalization requires a valid FITS exposure time.',
    );
  }

  /// Returns the camera read-noise setting in electrons.
  /// Null means the value is unavailable/invalid and dependent metrics
  /// should be omitted instead of guessed.
  Future<double?> _readNoiseEstimate() async {
    try {
      final dao = _ref.read(settingsDaoProvider);
      final stored = await dao.getSetting('science.camera.read_noise_e');
      if (stored != null && stored.isNotEmpty) {
        final parsed = double.tryParse(stored);
        if (parsed != null && parsed.isFinite && parsed > 0) {
          return parsed.clamp(0.5, 30.0);
        }
        _logger.warning(
          'Invalid science.camera.read_noise_e setting "$stored"; limiting magnitude will be omitted.',
          source: 'ScienceBackend',
        );
      } else {
        _logger.warning(
          'science.camera.read_noise_e is not configured; limiting magnitude will be omitted.',
          source: 'ScienceBackend',
        );
      }
    } catch (error, stack) {
      _logger.warning(
        'Failed to read science.camera.read_noise_e; limiting magnitude will be omitted: $error\n$stack',
        source: 'ScienceBackend',
      );
    }
    return null;
  }
}

class _ProjectedCatalogStar {
  final String id;
  final double x;
  final double y;
  final double mag;

  const _ProjectedCatalogStar({
    required this.id,
    required this.x,
    required this.y,
    required this.mag,
  });
}

class _CatalogMatch {
  final StarMeasurement detected;
  final double catalogX;
  final double catalogY;
  final double catalogMag;

  const _CatalogMatch({
    required this.detected,
    required this.catalogX,
    required this.catalogY,
    required this.catalogMag,
  });
}

class _LinearFitResult {
  final double slope;
  final double intercept;
  final double rms;

  const _LinearFitResult({
    required this.slope,
    required this.intercept,
    required this.rms,
  });
}

class _QualityResult {
  final ScienceFrameQualityMetrics frame;
  final List<ScienceTileMetric> tiles;

  const _QualityResult({
    required this.frame,
    required this.tiles,
  });
}

final scienceBackendProvider = Provider<ScienceBackend>((ref) {
  return DefaultScienceBackend(ref);
});

