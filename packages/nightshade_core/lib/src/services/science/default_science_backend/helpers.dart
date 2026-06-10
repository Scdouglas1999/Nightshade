part of '../default_science_backend.dart';

extension _DefaultScienceBackendHelpers on DefaultScienceBackend {
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
      final radius =
          (math.sqrt(
                        wcs.fieldWidthDegrees * wcs.fieldWidthDegrees +
                            wcs.fieldHeightDegrees * wcs.fieldHeightDegrees,
                      ) *
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
        projected.add(
          _ProjectedCatalogStar(
            id: '${star.catalogId}_${star.ra.toStringAsFixed(6)}_${star.dec.toStringAsFixed(6)}',
            x: px.x,
            y: px.y,
            mag: star.magnitude!,
          ),
        );
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
          matches.add(
            _CatalogMatch(
              detected: detected,
              catalogX: best.x,
              catalogY: best.y,
              catalogMag: best.mag,
            ),
          );
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
    final ra =
        cra +
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
        1.0 / 60.0,
        t1.difference(t0).inMilliseconds.abs() / 60000.0,
      );
    }
    return math.max(1.0, (frameCount - 1).toDouble());
  }

  bool _mutualNearest(
    StarMeasurement first,
    StarMeasurement last,
    List<StarMeasurement> firstStars,
  ) {
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

  List<double> _sigmaClip(
    List<double> values, {
    required double sigma,
    required int iterations,
  }) {
    var working = values.where((v) => v.isFinite).toList(growable: true);
    if (working.length < 3) return working;
    for (var i = 0; i < iterations; i++) {
      final med = _median(working);
      final mad = _mad(working, med);
      if (mad <= 0) break;
      final limit = sigma * 1.4826 * mad;
      final filtered = working
          .where((v) => (v - med).abs() <= limit)
          .toList(growable: true);
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
      final filtered = working
          .where((v) => (v - med).abs() <= limit)
          .toList(growable: true);
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
    final trim = (sorted.length * trimFraction).floor().clamp(
      0,
      sorted.length ~/ 3,
    );
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
      values.map((v) => (v - median).abs()).toList(growable: false),
    );
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

  (ScienceFrameQualityMetrics, List<ScienceTileMetric>)
  _mapBridgeQualityResult({
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
      final yEnd = ((row + 1) * height / rows).floor().clamp(
        yStart + 1,
        height,
      );
      for (var col = 0; col < cols; col++) {
        final xStart = (col * width / cols).floor();
        final xEnd = ((col + 1) * width / cols).floor().clamp(
          xStart + 1,
          width,
        );

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
        final gradX =
            ((rightCount == 0 ? mean : rightSum / rightCount) -
                    (leftCount == 0 ? mean : leftSum / leftCount))
                .toDouble();
        final gradY =
            ((bottomCount == 0 ? mean : bottomSum / bottomCount) -
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
      math.max(0.0, (globalSumSq / safeCount) - (globalMean * globalMean)),
    );
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
      uniformityCv: background.abs() < 1e-6
          ? 0.0
          : globalStdDev / background.abs(),
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
