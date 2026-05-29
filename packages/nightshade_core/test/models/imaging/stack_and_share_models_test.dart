// Tests for the Stack-and-Share value models in
// `src/models/imaging/stack_and_share_models.dart`.
//
// These pin: copyWith round-trips, fraction math (including the zero-total
// guard), integration-seconds summation, value equality, and the AstroBin
// acquisition-block Markdown / JSON output.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/imaging/stack_and_share_models.dart';
import 'package:nightshade_core/src/services/live_stacking_service.dart';

void main() {
  group('StackAndShareConfig', () {
    test('has the documented sensible defaults', () {
      const config = StackAndShareConfig();
      expect(config.applyCalibration, isTrue);
      expect(config.autoStretch, isTrue);
      expect(config.minQualityScore, 0);
      expect(config.rejectUnaccepted, isTrue);
      expect(config.stackingConfig, const LiveStackingConfig());
      expect(StackAndShareConfig.defaults, config);
    });

    test('copyWith round-trips every field', () {
      const original = StackAndShareConfig();
      final updated = original.copyWith(
        stackingConfig: const LiveStackingConfig(maxMatchStars: 250),
        applyCalibration: false,
        autoStretch: false,
        minQualityScore: 0.75,
        rejectUnaccepted: false,
      );

      expect(updated.stackingConfig.maxMatchStars, 250);
      expect(updated.applyCalibration, isFalse);
      expect(updated.autoStretch, isFalse);
      expect(updated.minQualityScore, 0.75);
      expect(updated.rejectUnaccepted, isFalse);

      // A no-op copyWith returns an equal value.
      expect(original.copyWith(), original);
      expect(updated.copyWith(), updated);
      expect(updated, isNot(original));
    });

    test('value equality and hashCode', () {
      const a = StackAndShareConfig(minQualityScore: 0.5);
      const b = StackAndShareConfig(minQualityScore: 0.5);
      const c = StackAndShareConfig(minQualityScore: 0.6);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('StackAndShareProgress.fraction', () {
    test('is 0 when total is 0 (no NaN)', () {
      const progress = StackAndShareProgress();
      expect(progress.framesTotal, 0);
      expect(progress.fraction, 0.0);
      expect(progress.fraction.isNaN, isFalse);
    });

    test('is 0 when total is negative', () {
      const progress = StackAndShareProgress(framesTotal: -5, framesProcessed: 2);
      expect(progress.fraction, 0.0);
    });

    test('computes the processed/total ratio', () {
      const progress =
          StackAndShareProgress(framesTotal: 8, framesProcessed: 2);
      expect(progress.fraction, 0.25);
    });

    test('clamps to 1.0 when processed exceeds total', () {
      const progress =
          StackAndShareProgress(framesTotal: 4, framesProcessed: 6);
      expect(progress.fraction, 1.0);
    });

    test('copyWith round-trips and clearCurrentFile nulls the file', () {
      const original = StackAndShareProgress(
        phase: StackAndSharePhase.stacking,
        framesTotal: 10,
        framesProcessed: 3,
        framesRejected: 1,
        currentFile: '/tmp/light_003.fits',
      );
      final updated = original.copyWith(
        phase: StackAndSharePhase.stretching,
        framesProcessed: 9,
      );
      expect(updated.phase, StackAndSharePhase.stretching);
      expect(updated.framesProcessed, 9);
      expect(updated.framesTotal, 10);
      expect(updated.currentFile, '/tmp/light_003.fits');
      expect(original.copyWith(), original);

      final cleared = original.clearCurrentFile();
      expect(cleared.currentFile, isNull);
      expect(cleared.phase, original.phase);
      expect(cleared.framesProcessed, original.framesProcessed);
    });

    test('value equality', () {
      const a = StackAndShareProgress(framesTotal: 5, framesProcessed: 2);
      const b = StackAndShareProgress(framesTotal: 5, framesProcessed: 2);
      const c = StackAndShareProgress(framesTotal: 5, framesProcessed: 3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('StackedFrameSelection', () {
    test('copyWith round-trips and equality', () {
      const frame = StackedFrameSelection(
        imageId: 7,
        filePath: '/data/m31_001.fits',
        filter: 'L',
        qualityScore: 0.9,
      );
      expect(frame.isReference, isFalse);
      final ref = frame.copyWith(isReference: true, qualityScore: 0.95);
      expect(ref.isReference, isTrue);
      expect(ref.qualityScore, 0.95);
      expect(ref.imageId, 7);
      expect(frame.copyWith(), frame);

      const same = StackedFrameSelection(
        imageId: 7,
        filePath: '/data/m31_001.fits',
        filter: 'L',
        qualityScore: 0.9,
      );
      expect(frame, same);
      expect(frame.hashCode, same.hashCode);
      expect(frame, isNot(ref));
    });
  });

  group('StackSelectionSummary', () {
    test('integration-secs summation and per-filter counts via copyWith', () {
      const frames = [
        StackedFrameSelection(imageId: 1, filePath: 'a.fits', filter: 'L'),
        StackedFrameSelection(imageId: 2, filePath: 'b.fits', filter: 'L'),
        StackedFrameSelection(imageId: 3, filePath: 'c.fits', filter: 'Ha'),
      ];
      // Three frames of 120s each = 360s total.
      const summary = StackSelectionSummary(
        selected: frames,
        referencePath: 'a.fits',
        perFilterCounts: {'L': 2, 'Ha': 1},
        totalIntegrationSecs: 360,
        targetName: 'M31',
      );

      expect(summary.selectedCount, 3);
      expect(summary.excludedCount, 0);
      expect(summary.totalIntegrationSecs, 360);
      expect(summary.perFilterCounts['L'], 2);
      expect(summary.perFilterCounts['Ha'], 1);

      final extended = summary.copyWith(
        selected: [
          ...frames,
          const StackedFrameSelection(
              imageId: 4, filePath: 'd.fits', filter: 'Ha'),
        ],
        perFilterCounts: {'L': 2, 'Ha': 2},
        totalIntegrationSecs: 480,
      );
      expect(extended.selectedCount, 4);
      expect(extended.totalIntegrationSecs, 480);
      expect(extended.perFilterCounts['Ha'], 2);
      expect(summary.copyWith(), summary);
    });

    test('value equality is order- and content-sensitive', () {
      const a = StackSelectionSummary(
        selected: [StackedFrameSelection(imageId: 1, filePath: 'a.fits')],
        perFilterCounts: {'L': 1},
        totalIntegrationSecs: 60,
      );
      const b = StackSelectionSummary(
        selected: [StackedFrameSelection(imageId: 1, filePath: 'a.fits')],
        perFilterCounts: {'L': 1},
        totalIntegrationSecs: 60,
      );
      const c = StackSelectionSummary(
        selected: [StackedFrameSelection(imageId: 2, filePath: 'b.fits')],
        perFilterCounts: {'L': 1},
        totalIntegrationSecs: 60,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('default empty summary', () {
      const summary = StackSelectionSummary();
      expect(summary.selected, isEmpty);
      expect(summary.excluded, isEmpty);
      expect(summary.totalIntegrationSecs, 0);
      expect(summary.referencePath, isNull);
    });
  });

  group('StackAndShareResult', () {
    final createdAt = DateTime.utc(2026, 5, 28, 3, 14, 15);

    StackAndShareResult build() => StackAndShareResult(
          id: 42,
          sessionId: 5,
          targetId: 9,
          targetName: 'NGC 7000',
          width: 6248,
          height: 4176,
          framesStacked: 58,
          framesAttempted: 60,
          integrationSecs: 6960,
          avgAlignmentResidual: 0.42,
          avgHfr: 2.1,
          filter: 'Ha',
          createdAt: createdAt,
          exportedImagePath: '/exports/ngc7000.png',
          stats: const LiveStackingStats(stackedFrameCount: 58),
        );

    test('framesRejected derives from attempted minus stacked', () {
      expect(build().framesRejected, 2);
    });

    test('copyWith round-trips every field', () {
      final original = build();
      final updated = original.copyWith(
        id: 43,
        framesStacked: 59,
        integrationSecs: 7080,
        exportedImagePath: '/exports/ngc7000.jpg',
      );
      expect(updated.id, 43);
      expect(updated.framesStacked, 59);
      expect(updated.integrationSecs, 7080);
      expect(updated.exportedImagePath, '/exports/ngc7000.jpg');
      // Untouched fields preserved.
      expect(updated.targetName, 'NGC 7000');
      expect(updated.createdAt, createdAt);
      expect(original.copyWith(), original);
      expect(updated, isNot(original));
    });

    test('value equality and hashCode', () {
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
      expect(build(), isNot(build().copyWith(width: 100)));
    });
  });

  group('ShareCardSpec / ShareStatLine', () {
    test('defaults and copyWith', () {
      const spec = ShareCardSpec(title: 'M42');
      expect(spec.targetWidth, 1080);
      expect(spec.targetHeight, 1080);
      expect(spec.layout, ShareCardLayout.bottomBar);
      expect(spec.stats, isEmpty);

      final updated = spec.copyWith(
        stats: const [ShareStatLine(label: 'Integration', value: '2h12m')],
        watermark: 'Nightshade',
        layout: ShareCardLayout.cornerCard,
      );
      expect(updated.stats.single.label, 'Integration');
      expect(updated.watermark, 'Nightshade');
      expect(updated.layout, ShareCardLayout.cornerCard);
      expect(spec.copyWith(), spec);
    });

    test('value equality is sensitive to stat lines', () {
      const a = ShareCardSpec(
        title: 'M42',
        stats: [ShareStatLine(label: 'Frames', value: '58')],
      );
      const b = ShareCardSpec(
        title: 'M42',
        stats: [ShareStatLine(label: 'Frames', value: '58')],
      );
      const c = ShareCardSpec(
        title: 'M42',
        stats: [ShareStatLine(label: 'Frames', value: '59')],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('ShareStatLine copyWith and equality', () {
      const line = ShareStatLine(label: 'HFR', value: '2.1');
      expect(line.copyWith(value: '2.2').value, '2.2');
      expect(line.copyWith(), line);
      expect(
        const ShareStatLine(label: 'HFR', value: '2.1'),
        line,
      );
    });
  });

  group('AstroBinExportMetadata', () {
    AstroBinExportMetadata build() => const AstroBinExportMetadata(
          title: 'NGC 7000 — North America Nebula',
          integrationSecs: 6960, // 1h 56m 00s
          frames: 58,
          telescope: 'Askar FRA400',
          camera: 'ZWO ASI2600MM Pro',
          filter: 'Ha',
          focalLength: 400,
          aperture: 72,
        );

    test('perFrameExposureSecs and zero-frame guard', () {
      expect(build().perFrameExposureSecs, closeTo(120, 1e-9));
      const noFrames = AstroBinExportMetadata(integrationSecs: 600, frames: 0);
      expect(noFrames.perFrameExposureSecs, 0);
    });

    test('integrationHms is zero-padded HH:MM:SS', () {
      expect(build().integrationHms, '01:56:00');
      const short = AstroBinExportMetadata(integrationSecs: 65, frames: 1);
      expect(short.integrationHms, '00:01:05');
    });

    test('focalRatio computes f-number, null when aperture unknown', () {
      expect(build().focalRatio, closeTo(400 / 72, 1e-9));
      const noAperture =
          AstroBinExportMetadata(integrationSecs: 60, frames: 1, focalLength: 400);
      expect(noAperture.focalRatio, isNull);
    });

    test('toMarkdown contains Integration label and the HMS string', () {
      final md = build().toMarkdown();
      expect(md, contains('Integration'));
      expect(md, contains('01:56:00'));
      // Frames x exposure breakdown present.
      expect(md, contains('58 x 120s'));
      // Equipment lines present when populated.
      expect(md, contains('Askar FRA400'));
      expect(md, contains('ZWO ASI2600MM Pro'));
      expect(md, contains('f/5.6'));
    });

    test('toMarkdown omits equipment lines that are null', () {
      const minimal = AstroBinExportMetadata(integrationSecs: 300, frames: 5);
      final md = minimal.toMarkdown();
      expect(md, contains('Integration'));
      expect(md, contains('00:05:00'));
      expect(md, isNot(contains('Telescope')));
      expect(md, isNot(contains('Camera')));
      expect(md, isNot(contains('Focal ratio')));
    });

    test('toJson omits null fields and includes derived values', () {
      final json = build().toJson();
      expect(json['subjectType'], 'Deep sky');
      expect(json['frames'], 58);
      expect(json['integrationSecs'], 6960);
      expect(json['integrationHms'], '01:56:00');
      expect(json['perFrameExposureSecs'], closeTo(120, 1e-9));
      expect(json['focalRatio'], closeTo(400 / 72, 1e-9));

      const minimal = AstroBinExportMetadata(integrationSecs: 300, frames: 5);
      final minJson = minimal.toJson();
      expect(minJson.containsKey('telescope'), isFalse);
      expect(minJson.containsKey('camera'), isFalse);
      expect(minJson.containsKey('focalRatio'), isFalse);
      expect(minJson.containsKey('title'), isFalse);
    });

    test('fromJson round-trips through toJson', () {
      final original = build();
      final restored = AstroBinExportMetadata.fromJson(
        original.toJson().cast<String, dynamic>(),
      );
      expect(restored, original);
    });

    test('copyWith round-trips and value equality', () {
      final original = build();
      final updated = original.copyWith(frames: 60, integrationSecs: 7200);
      expect(updated.frames, 60);
      expect(updated.integrationSecs, 7200);
      expect(updated.telescope, 'Askar FRA400');
      expect(original.copyWith(), original);
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
      expect(updated, isNot(original));
    });
  });

  group('formatHms', () {
    test('zero and negative clamp to 00:00:00', () {
      expect(formatHms(0), '00:00:00');
      expect(formatHms(-120), '00:00:00');
    });

    test('rounds fractional seconds and pads components', () {
      expect(formatHms(59.6), '00:01:00');
      expect(formatHms(3661), '01:01:01');
      expect(formatHms(36000), '10:00:00');
    });
  });
}
