import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/imaging/integration_settings.dart';

void main() {
  group('IntegrationSettings defaults', () {
    test('balanced defaults match the documented PixInsight-spirit knobs', () {
      const s = IntegrationSettings.defaults;
      expect(s.model, TransformModel.affine);
      expect(s.resampler, Resampler.lanczos3);
      expect(s.ransacThresholdPx, 2.0);
      expect(s.maxRefStars, 60);
      expect(s.weightingEnabled, isTrue);
      expect(s.weighting, WeightFormula.snrSquared);
      expect(s.normalizationEnabled, isTrue);
      expect(s.normalization, NormalizationMode.global);
      expect(s.combine, CombineMode.mean);
      expect(s.reject, RejectAlgorithm.auto);
      expect(s.rejectLow, 3.0);
      expect(s.rejectHigh, 3.0);
      expect(s.generateRejectionMap, isTrue);
      expect(s.cosmeticCorrection, isTrue);
      expect(s.outputBitDepth, OutputBitDepth.f32);
      expect(s.autoCull, isTrue);
      expect(s.cullPercentile, closeTo(0.10, 1e-9));
      expect(s.sourcePreset, IntegrationPreset.balanced);
    });
  });

  group('presets', () {
    test('fast trades quality for speed', () {
      final s = IntegrationSettings.preset(IntegrationPreset.fast);
      expect(s.resampler, Resampler.bilinear);
      expect(s.weighting, WeightFormula.snr);
      expect(s.generateRejectionMap, isFalse);
      expect(s.cosmeticCorrection, isFalse);
      expect(s.sourcePreset, IntegrationPreset.fast);
    });

    test('maximumQuality keeps Lanczos + rejection map + f32', () {
      final s = IntegrationSettings.preset(IntegrationPreset.maximumQuality);
      expect(s.resampler, Resampler.lanczos3);
      expect(s.weighting, WeightFormula.snrSquared);
      expect(s.generateRejectionMap, isTrue);
      expect(s.outputBitDepth, OutputBitDepth.f32);
    });

    test('fewSubs uses percentile rejection with fractional thresholds', () {
      final s = IntegrationSettings.preset(IntegrationPreset.fewSubs);
      expect(s.reject, RejectAlgorithm.percentile);
      // Percentile thresholds are fractions in (0, 1), not sigma.
      expect(s.rejectLow, greaterThan(0.0));
      expect(s.rejectLow, lessThan(1.0));
      expect(s.rejectHigh, greaterThan(0.0));
      expect(s.rejectHigh, lessThan(1.0));
    });

    test('longNightGradient turns on local normalization', () {
      final s = IntegrationSettings.preset(IntegrationPreset.longNightGradient);
      expect(s.normalization, NormalizationMode.local);
    });
  });

  group('smartDefaults', () {
    test('keeps auto rejection and resolves to percentile for <8 subs', () {
      final s = IntegrationSettings.smartDefaults(subCount: 5);
      expect(s.reject, RejectAlgorithm.auto);
      expect(s.resolvedReject(5), RejectAlgorithm.percentile);
      // Percentile fractions substituted for the sigma defaults.
      expect(s.rejectLow, lessThan(1.0));
      expect(s.rejectHigh, lessThan(1.0));
      // A hand-tuned smart config is no longer tied to one preset.
      expect(s.sourcePreset, isNull);
    });

    test('resolves winsorizedSigma for the 8..24 band', () {
      final s = IntegrationSettings.smartDefaults(subCount: 15);
      expect(s.resolvedReject(15), RejectAlgorithm.winsorizedSigma);
      // Sigma thresholds retained (not substituted with fractions).
      expect(s.rejectLow, 3.0);
      expect(s.rejectHigh, 3.0);
    });

    test('resolves linearFit for >=25 subs', () {
      final s = IntegrationSettings.smartDefaults(subCount: 40);
      expect(s.resolvedReject(40), RejectAlgorithm.linearFit);
    });

    test('longNight enables local normalization', () {
      final s = IntegrationSettings.smartDefaults(subCount: 30, longNight: true);
      expect(s.normalization, NormalizationMode.local);
    });

    test('preferSpeed drops to the bilinear resampler', () {
      final s =
          IntegrationSettings.smartDefaults(subCount: 200, preferSpeed: true);
      expect(s.resampler, Resampler.bilinear);
    });

    test('resolvedReject is an identity for a non-auto algorithm', () {
      const s = IntegrationSettings(reject: RejectAlgorithm.sigmaClip);
      expect(s.resolvedReject(3), RejectAlgorithm.sigmaClip);
      expect(s.resolvedReject(100), RejectAlgorithm.sigmaClip);
    });
  });

  group('serialization', () {
    test('toJson / fromJson round-trips every knob', () {
      const s = IntegrationSettings(
        model: TransformModel.homography,
        resampler: Resampler.catmullRom,
        ransacThresholdPx: 1.5,
        maxRefStars: 120,
        weightingEnabled: false,
        weighting: WeightFormula.custom,
        snrPow: 2.5,
        fwhmPow: 0.5,
        eccPow: 1.5,
        normalizationEnabled: false,
        normalization: NormalizationMode.local,
        localRows: 12,
        localCols: 10,
        combine: CombineMode.median,
        reject: RejectAlgorithm.linearFit,
        rejectLow: 2.5,
        rejectHigh: 4.0,
        minMaxLow: 2,
        minMaxHigh: 3,
        generateRejectionMap: false,
        cosmeticCorrection: false,
        outputBitDepth: OutputBitDepth.u16,
        autoCull: false,
        cullPercentile: 0.25,
        sourcePreset: IntegrationPreset.maximumQuality,
      );
      final restored = IntegrationSettings.fromJson(s.toJson());
      expect(restored, s);
    });

    test('toJsonString / fromJsonStringOrDefault round-trips', () {
      final s = IntegrationSettings.preset(IntegrationPreset.longNightGradient);
      final restored =
          IntegrationSettings.fromJsonStringOrDefault(s.toJsonString());
      expect(restored, s);
    });

    test('fromJsonStringOrDefault returns defaults for null/blank/corrupt', () {
      expect(IntegrationSettings.fromJsonStringOrDefault(null),
          IntegrationSettings.defaults);
      expect(IntegrationSettings.fromJsonStringOrDefault('   '),
          IntegrationSettings.defaults);
      expect(IntegrationSettings.fromJsonStringOrDefault('{not json'),
          IntegrationSettings.defaults);
      // A JSON array (not an object) also falls back rather than throwing.
      expect(IntegrationSettings.fromJsonStringOrDefault('[1,2,3]'),
          IntegrationSettings.defaults);
    });

    test('fromJson forward-migrates missing keys to defaults', () {
      // An older blob that predates several knobs.
      final restored = IntegrationSettings.fromJson({
        'model': 'similarity',
        'rejectLow': 2.0,
      });
      expect(restored.model, TransformModel.similarity);
      expect(restored.rejectLow, 2.0);
      // Everything unspecified falls back to the default value.
      expect(restored.resampler, IntegrationSettings.defaults.resampler);
      expect(restored.weighting, IntegrationSettings.defaults.weighting);
      expect(restored.outputBitDepth,
          IntegrationSettings.defaults.outputBitDepth);
    });
  });

  group('toBridgeSettings', () {
    test('emits the native IntegrationSettingsArgs shape with camelCase keys',
        () {
      const s = IntegrationSettings.defaults;
      final bridge = s.toBridgeSettings();
      expect(bridge.keys,
          containsAll(['align', 'weighting', 'normalization', 'integration']));

      final align = bridge['align'] as Map<String, dynamic>;
      expect(align['model'], 'affine');
      expect(align['resampler'], 'lanczos3');
      expect(align['ransacThresholdPx'], 2.0);
      expect(align['maxRefStars'], 60);

      final weighting = bridge['weighting'] as Map<String, dynamic>;
      expect(weighting['enabled'], isTrue);
      expect(weighting['formula'], 'snrSquared');

      final norm = bridge['normalization'] as Map<String, dynamic>;
      expect(norm['enabled'], isTrue);
      expect(norm['mode'], 'global');

      final integ = bridge['integration'] as Map<String, dynamic>;
      expect(integ['combine'], 'mean');
      expect(integ['reject'], 'auto');
      expect(integ['rejectLow'], 3.0);
      expect(integ['generateRejectionMap'], isTrue);
      expect(integ['outputBitDepth'], 'f32');

      // cosmeticCorrection rides on the native calibration block, NOT here.
      expect(integ.containsKey('cosmeticCorrection'), isFalse);
      expect(weighting.containsKey('cosmeticCorrection'), isFalse);
    });
  });

  group('RejectAlgorithm.resolveAuto', () {
    test('matches the documented native sub-count rule boundaries', () {
      expect(RejectAlgorithm.resolveAuto(1), RejectAlgorithm.percentile);
      expect(RejectAlgorithm.resolveAuto(7), RejectAlgorithm.percentile);
      expect(RejectAlgorithm.resolveAuto(8), RejectAlgorithm.winsorizedSigma);
      expect(RejectAlgorithm.resolveAuto(24), RejectAlgorithm.winsorizedSigma);
      expect(RejectAlgorithm.resolveAuto(25), RejectAlgorithm.linearFit);
      expect(RejectAlgorithm.resolveAuto(1000), RejectAlgorithm.linearFit);
    });
  });
}
