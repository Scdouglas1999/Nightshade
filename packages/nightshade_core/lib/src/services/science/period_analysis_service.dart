import 'dart:math' as math;

import '../../models/science/science_models.dart';

/// Results from a Lomb-Scargle periodogram analysis.
class LombScargleResult {
  /// Trial frequencies at which the periodogram was evaluated.
  final List<double> frequencies;

  /// Normalized power at each trial frequency.
  final List<double> powers;

  /// The frequency with the highest power.
  final double bestFrequency;

  /// The best-fit period (1 / bestFrequency), in the same time units as input.
  final double bestPeriod;

  /// The peak power value.
  final double peakPower;

  /// Estimated false alarm probability for the peak.
  /// Lower FAP = more significant detection.
  final double falseAlarmProbability;

  const LombScargleResult({
    required this.frequencies,
    required this.powers,
    required this.bestFrequency,
    required this.bestPeriod,
    required this.peakPower,
    required this.falseAlarmProbability,
  });
}

/// Results from a Box Least Squares (BLS) transit search.
class BlsResult {
  /// The best-fit orbital period (same time units as input).
  final double bestPeriod;

  /// The transit duration as a fraction of the period.
  final double transitDurationFraction;

  /// The transit duration in the same time units as input.
  final double transitDuration;

  /// The transit depth in magnitude units.
  final double transitDepth;

  /// Signal Residue (SR) statistic — higher means more significant.
  final double signalResidueStatistic;

  /// Signal Detection Efficiency (SDE) — the significance measure.
  /// SDE > ~6 is typically considered a significant detection.
  final double signalDetectionEfficiency;

  /// The phase of mid-transit (0..1).
  final double transitMidPhase;

  /// Trial periods that were searched.
  final List<double> trialPeriods;

  /// SR statistic at each trial period (for plotting).
  final List<double> srSpectrum;

  const BlsResult({
    required this.bestPeriod,
    required this.transitDurationFraction,
    required this.transitDuration,
    required this.transitDepth,
    required this.signalResidueStatistic,
    required this.signalDetectionEfficiency,
    required this.transitMidPhase,
    required this.trialPeriods,
    required this.srSpectrum,
  });
}

/// A single point in a phase-folded light curve.
class PhaseFoldedPoint {
  /// Phase value (0..1), where 0 = epoch.
  final double phase;

  /// The differential magnitude at this phase.
  final double magnitude;

  /// The uncertainty on the magnitude.
  final double uncertainty;

  const PhaseFoldedPoint({
    required this.phase,
    required this.magnitude,
    required this.uncertainty,
  });
}

/// Combined results from all period analysis algorithms.
class PeriodAnalysisResult {
  final LombScargleResult lombScargle;
  final BlsResult bls;

  const PeriodAnalysisResult({
    required this.lombScargle,
    required this.bls,
  });
}

/// Service that implements period detection algorithms for variable star
/// and exoplanet transit analysis on unevenly sampled photometric time series.
class PeriodAnalysisService {
  const PeriodAnalysisService();

  /// Run both Lomb-Scargle and BLS on the given light curve data.
  ///
  /// [points] must contain at least 10 data points to produce meaningful
  /// results. Throws [ArgumentError] if fewer than 10 points are provided.
  ///
  /// [minPeriodDays] and [maxPeriodDays] control the search range.
  /// [frequencyOversampling] controls the frequency grid density (higher = finer grid).
  PeriodAnalysisResult analyze({
    required List<LightCurvePoint> points,
    double minPeriodDays = 0.01,
    double maxPeriodDays = 100.0,
    int frequencyOversampling = 5,
    int blsNbins = 200,
  }) {
    if (points.length < 10) {
      throw ArgumentError(
        'Period analysis requires at least 10 light curve points, '
        'got ${points.length}.',
      );
    }

    // Convert timestamps to fractional days relative to the first observation.
    final sortedPoints = points.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final t0 = sortedPoints.first.timestamp;
    final times = <double>[];
    final mags = <double>[];
    final errs = <double>[];
    for (final point in sortedPoints) {
      final daysSinceT0 =
          point.timestamp.difference(t0).inMicroseconds / 8.64e10;
      times.add(daysSinceT0);
      mags.add(point.differentialMagnitude);
      errs.add(point.uncertainty > 0 ? point.uncertainty : 0.01);
    }

    final timeBaseline = times.last - times.first;
    if (timeBaseline <= 0) {
      throw ArgumentError(
        'Light curve has zero time baseline. All points have the same timestamp.',
      );
    }

    // Clamp period range to the data's Nyquist limits.
    final effectiveMaxPeriod = math.min(maxPeriodDays, timeBaseline);
    final minTimeDiff = _minimumPositiveTimeDifference(times);
    final effectiveMinPeriod = math.max(minPeriodDays, minTimeDiff * 2.0);
    if (effectiveMinPeriod >= effectiveMaxPeriod) {
      throw ArgumentError(
        'Period search range is empty: min=$effectiveMinPeriod, '
        'max=$effectiveMaxPeriod days (baseline=$timeBaseline days).',
      );
    }

    final ls = computeLombScargle(
      times: times,
      mags: mags,
      errs: errs,
      minPeriod: effectiveMinPeriod,
      maxPeriod: effectiveMaxPeriod,
      oversampling: frequencyOversampling,
      timeBaseline: timeBaseline,
    );

    final bls = computeBls(
      times: times,
      mags: mags,
      errs: errs,
      minPeriod: effectiveMinPeriod,
      maxPeriod: effectiveMaxPeriod,
      nbins: blsNbins,
    );

    return PeriodAnalysisResult(lombScargle: ls, bls: bls);
  }

  /// Compute the Lomb-Scargle periodogram.
  ///
  /// Implementation follows Lomb (1976) and Scargle (1982) with the
  /// generalization by Press & Rybicki (1989) for floating-mean normalization.
  /// The periodogram is evaluated at an oversampled frequency grid with
  /// step size df = 1 / (oversampling * timeBaseline).
  LombScargleResult computeLombScargle({
    required List<double> times,
    required List<double> mags,
    required List<double> errs,
    required double minPeriod,
    required double maxPeriod,
    required int oversampling,
    required double timeBaseline,
  }) {
    final n = times.length;

    // Compute weights from inverse variance.
    final weights = List<double>.filled(n, 0.0);
    var weightSum = 0.0;
    for (var i = 0; i < n; i++) {
      weights[i] = 1.0 / (errs[i] * errs[i]);
      weightSum += weights[i];
    }
    // Normalize weights.
    for (var i = 0; i < n; i++) {
      weights[i] /= weightSum;
    }

    // Weighted mean of magnitudes.
    var weightedMean = 0.0;
    for (var i = 0; i < n; i++) {
      weightedMean += weights[i] * mags[i];
    }

    // Residuals from the mean.
    final residuals = List<double>.filled(n, 0.0);
    for (var i = 0; i < n; i++) {
      residuals[i] = mags[i] - weightedMean;
    }

    // Build frequency grid.
    final minFreq = 1.0 / maxPeriod;
    final maxFreq = 1.0 / minPeriod;
    final df = 1.0 / (oversampling * timeBaseline);
    final nFreqs = ((maxFreq - minFreq) / df).ceil() + 1;

    // Cap at a reasonable maximum to avoid excessive computation.
    final effectiveNFreqs = math.min(nFreqs, 500000);
    final effectiveDf =
        effectiveNFreqs < nFreqs ? (maxFreq - minFreq) / effectiveNFreqs : df;

    final frequencies = List<double>.filled(effectiveNFreqs, 0.0);
    final powers = List<double>.filled(effectiveNFreqs, 0.0);

    // Weighted variance of the data (for normalization).
    var weightedVariance = 0.0;
    for (var i = 0; i < n; i++) {
      weightedVariance += weights[i] * residuals[i] * residuals[i];
    }
    if (weightedVariance <= 0.0) {
      // No variance in data — return flat periodogram.
      for (var k = 0; k < effectiveNFreqs; k++) {
        frequencies[k] = minFreq + k * effectiveDf;
      }
      return LombScargleResult(
        frequencies: frequencies,
        powers: powers,
        bestFrequency: minFreq,
        bestPeriod: maxPeriod,
        peakPower: 0.0,
        falseAlarmProbability: 1.0,
      );
    }

    var bestPower = -1.0;
    var bestIndex = 0;

    for (var k = 0; k < effectiveNFreqs; k++) {
      final freq = minFreq + k * effectiveDf;
      frequencies[k] = freq;
      final omega = 2.0 * math.pi * freq;

      // Compute tau (the time offset that makes the basis functions orthogonal).
      // tan(2*omega*tau) = sum(w_i * sin(2*omega*t_i)) / sum(w_i * cos(2*omega*t_i))
      var sin2Sum = 0.0;
      var cos2Sum = 0.0;
      for (var i = 0; i < n; i++) {
        final twoOmegaT = 2.0 * omega * times[i];
        sin2Sum += weights[i] * math.sin(twoOmegaT);
        cos2Sum += weights[i] * math.cos(twoOmegaT);
      }
      final tau = math.atan2(sin2Sum, cos2Sum) / (2.0 * omega);

      // Compute the four sums needed for the Lomb-Scargle statistic.
      var cosTermNum = 0.0;
      var cosTermDen = 0.0;
      var sinTermNum = 0.0;
      var sinTermDen = 0.0;

      for (var i = 0; i < n; i++) {
        final phase = omega * (times[i] - tau);
        final cosPhase = math.cos(phase);
        final sinPhase = math.sin(phase);
        final wResid = weights[i] * residuals[i];
        final wi = weights[i];

        cosTermNum += wResid * cosPhase;
        cosTermDen += wi * cosPhase * cosPhase;
        sinTermNum += wResid * sinPhase;
        sinTermDen += wi * sinPhase * sinPhase;
      }

      // Normalized Lomb-Scargle power.
      var power = 0.0;
      if (cosTermDen > 1e-30) {
        power += (cosTermNum * cosTermNum) / cosTermDen;
      }
      if (sinTermDen > 1e-30) {
        power += (sinTermNum * sinTermNum) / sinTermDen;
      }
      power /= (2.0 * weightedVariance);
      powers[k] = power;

      if (power > bestPower) {
        bestPower = power;
        bestIndex = k;
      }
    }

    final bestFreq = frequencies[bestIndex];
    final bestPeriod = 1.0 / bestFreq;

    // False alarm probability (Baluev 2008 approximation).
    // FAP = 1 - (1 - exp(-z))^M, where z = peak power, M = effective
    // number of independent frequencies.
    final m = effectiveNFreqs.toDouble();
    final expTerm = math.exp(-bestPower);
    final fap = 1.0 - math.pow(1.0 - expTerm, m).clamp(0.0, 1.0);

    return LombScargleResult(
      frequencies: frequencies,
      powers: powers,
      bestFrequency: bestFreq,
      bestPeriod: bestPeriod,
      peakPower: bestPower,
      falseAlarmProbability: fap.clamp(0.0, 1.0),
    );
  }

  /// Compute Box Least Squares (BLS) transit detection.
  ///
  /// Implementation follows Kovacs, Zucker & Mazeh (2002).
  /// The algorithm searches for periodic box-shaped dips in the light curve,
  /// which are characteristic of exoplanet transits.
  BlsResult computeBls({
    required List<double> times,
    required List<double> mags,
    required List<double> errs,
    required double minPeriod,
    required double maxPeriod,
    required int nbins,
    double minTransitDurationFraction = 0.01,
    double maxTransitDurationFraction = 0.15,
  }) {
    final n = times.length;

    // Compute weights from inverse variance.
    final weights = List<double>.filled(n, 0.0);
    var totalWeight = 0.0;
    for (var i = 0; i < n; i++) {
      weights[i] = 1.0 / (errs[i] * errs[i]);
      totalWeight += weights[i];
    }
    for (var i = 0; i < n; i++) {
      weights[i] /= totalWeight;
    }

    // Weighted mean magnitude.
    var meanMag = 0.0;
    for (var i = 0; i < n; i++) {
      meanMag += weights[i] * mags[i];
    }

    // Build trial period grid — logarithmically spaced.
    // The number of trial periods is set by the frequency resolution needed.
    final timeBaseline = times.last - times.first;
    final logMinP = math.log(minPeriod);
    final logMaxP = math.log(maxPeriod);
    // At minimum, use about 1000 trial periods; scale with baseline.
    final nTrialPeriods =
        math.max(1000, (timeBaseline / minPeriod * 2).ceil());
    final effectiveNTrials = math.min(nTrialPeriods, 100000);
    final dLogP = (logMaxP - logMinP) / effectiveNTrials;

    final trialPeriods = List<double>.filled(effectiveNTrials, 0.0);
    final srSpectrum = List<double>.filled(effectiveNTrials, 0.0);

    var globalBestSr = -1.0;
    var globalBestPeriod = minPeriod;
    var globalBestDurationFrac = 0.05;
    var globalBestPhase = 0.0;
    var globalBestDepth = 0.0;

    // Min/max bin-widths for transit duration.
    final minBinWidth = math.max(1, (minTransitDurationFraction * nbins).floor());
    final maxBinWidth = math.max(minBinWidth + 1, (maxTransitDurationFraction * nbins).ceil());

    for (var ip = 0; ip < effectiveNTrials; ip++) {
      final period = math.exp(logMinP + ip * dLogP);
      trialPeriods[ip] = period;

      // Phase-fold the data and bin it.
      final binWeight = List<double>.filled(nbins, 0.0);
      final binSignal = List<double>.filled(nbins, 0.0);

      for (var i = 0; i < n; i++) {
        var phase = (times[i] % period) / period;
        if (phase < 0) phase += 1.0;
        var bin = (phase * nbins).floor();
        if (bin >= nbins) bin = nbins - 1;
        binWeight[bin] += weights[i];
        binSignal[bin] += weights[i] * (mags[i] - meanMag);
      }

      // Search over all transit start phases and durations.
      // We use the running-sum approach from BLS for efficiency.
      var bestSrForPeriod = -1.0;
      var bestPhaseForPeriod = 0.0;
      var bestWidthForPeriod = minBinWidth;

      for (var width = minBinWidth; width <= maxBinWidth; width++) {
        // Initial sums for the first transit window.
        var s = 0.0;
        var r = 0.0;
        for (var j = 0; j < width; j++) {
          s += binSignal[j];
          r += binWeight[j];
        }

        for (var startBin = 0; startBin < nbins; startBin++) {
          // SR = s^2 / (r * (1 - r)) — the signal residue statistic.
          // Only evaluate when r is in a valid range (not 0 or 1).
          if (r > 1e-10 && r < 1.0 - 1e-10) {
            final sr = (s * s) / (r * (1.0 - r));
            if (sr > bestSrForPeriod) {
              bestSrForPeriod = sr;
              bestPhaseForPeriod = (startBin + width / 2.0) / nbins;
              bestWidthForPeriod = width;
            }
          }

          // Slide the window: remove the leading bin, add the next trailing bin.
          final removeBin = startBin % nbins;
          final addBin = (startBin + width) % nbins;
          s -= binSignal[removeBin];
          r -= binWeight[removeBin];
          s += binSignal[addBin];
          r += binWeight[addBin];
        }
      }

      srSpectrum[ip] = bestSrForPeriod > 0 ? math.sqrt(bestSrForPeriod) : 0.0;

      if (bestSrForPeriod > globalBestSr) {
        globalBestSr = bestSrForPeriod;
        globalBestPeriod = period;
        globalBestDurationFrac = bestWidthForPeriod / nbins;
        globalBestPhase = bestPhaseForPeriod;

        // Compute transit depth: the weighted mean in-transit magnitude
        // minus the weighted mean out-of-transit magnitude.
        // Re-fold at best period/phase to get depth.
        var inTransitWeightedSum = 0.0;
        var inTransitWeight = 0.0;
        var outTransitWeightedSum = 0.0;
        var outTransitWeight = 0.0;

        final transitStart =
            (globalBestPhase - globalBestDurationFrac / 2.0) % 1.0;
        final transitEnd =
            (globalBestPhase + globalBestDurationFrac / 2.0) % 1.0;

        for (var i = 0; i < n; i++) {
          var phase = (times[i] % period) / period;
          if (phase < 0) phase += 1.0;

          final inTransit = transitStart < transitEnd
              ? (phase >= transitStart && phase <= transitEnd)
              : (phase >= transitStart || phase <= transitEnd);

          if (inTransit) {
            inTransitWeightedSum += weights[i] * mags[i];
            inTransitWeight += weights[i];
          } else {
            outTransitWeightedSum += weights[i] * mags[i];
            outTransitWeight += weights[i];
          }
        }

        if (inTransitWeight > 0 && outTransitWeight > 0) {
          final inTransitMean = inTransitWeightedSum / inTransitWeight;
          final outTransitMean = outTransitWeightedSum / outTransitWeight;
          // Depth is positive when transit is fainter (higher mag).
          globalBestDepth = inTransitMean - outTransitMean;
        }
      }
    }

    // Compute Signal Detection Efficiency (SDE).
    // SDE = (peak_SR - mean_SR) / stddev_SR
    var srMean = 0.0;
    for (var i = 0; i < effectiveNTrials; i++) {
      srMean += srSpectrum[i];
    }
    srMean /= effectiveNTrials;

    var srVariance = 0.0;
    for (var i = 0; i < effectiveNTrials; i++) {
      final diff = srSpectrum[i] - srMean;
      srVariance += diff * diff;
    }
    srVariance /= effectiveNTrials;
    final srStd = math.sqrt(srVariance);

    final peakSr = globalBestSr > 0 ? math.sqrt(globalBestSr) : 0.0;
    final sde = srStd > 1e-10 ? (peakSr - srMean) / srStd : 0.0;

    return BlsResult(
      bestPeriod: globalBestPeriod,
      transitDurationFraction: globalBestDurationFrac,
      transitDuration: globalBestPeriod * globalBestDurationFrac,
      transitDepth: globalBestDepth,
      signalResidueStatistic: peakSr,
      signalDetectionEfficiency: sde,
      transitMidPhase: globalBestPhase,
      trialPeriods: trialPeriods,
      srSpectrum: srSpectrum,
    );
  }

  /// Phase-fold the light curve at a given period.
  ///
  /// [epoch] is the reference time (JD or day offset) for phase = 0.
  /// Returns points sorted by phase.
  List<PhaseFoldedPoint> phaseFold({
    required List<LightCurvePoint> points,
    required double periodDays,
    DateTime? epoch,
  }) {
    if (points.isEmpty || periodDays <= 0) {
      return const [];
    }

    final sorted = points.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final t0 = epoch ?? sorted.first.timestamp;

    final folded = <PhaseFoldedPoint>[];
    for (final point in sorted) {
      final daysSinceEpoch =
          point.timestamp.difference(t0).inMicroseconds / 8.64e10;
      var phase = (daysSinceEpoch % periodDays) / periodDays;
      if (phase < 0) phase += 1.0;
      folded.add(PhaseFoldedPoint(
        phase: phase,
        magnitude: point.differentialMagnitude,
        uncertainty: point.uncertainty > 0 ? point.uncertainty : 0.01,
      ));
    }

    folded.sort((a, b) => a.phase.compareTo(b.phase));
    return folded;
  }

  /// Find the minimum positive time difference between consecutive sorted times.
  double _minimumPositiveTimeDifference(List<double> sortedTimes) {
    var minDiff = double.infinity;
    for (var i = 1; i < sortedTimes.length; i++) {
      final diff = sortedTimes[i] - sortedTimes[i - 1];
      if (diff > 0 && diff < minDiff) {
        minDiff = diff;
      }
    }
    return minDiff.isFinite ? minDiff : 0.001;
  }
}
