import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/utils/plan_tonight_sequencer_helper.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  group('buildFramingMosaicConfig', () {
    const target = FramingTarget(
      name: 'M31',
      catalogId: 'M31',
      raHours: 0.7122222, // ~10.68 deg
      decDegrees: 41.2,
    );

    test('passes through framing UI knobs to the service-layer geometry', () {
      const framingState = FramingState(
        rotation: 12.0,
        mosaicEnabled: true,
        mosaicConfig: FramingMosaicConfig(
          columns: 3,
          rows: 2,
          overlapPercent: 18.0,
          serpentine: true,
        ),
      );

      final config = buildFramingMosaicConfig(
        target: target,
        framingState: framingState,
        panelWidthArcmin: 45.0,
        panelHeightArcmin: 30.0,
      );

      expect(config.centerRa, target.raHours);
      expect(config.centerDec, target.decDegrees);
      expect(config.panelsHorizontal, 3);
      expect(config.panelsVertical, 2);
      expect(config.totalPanels, 6);
      expect(config.overlapPercent, 18.0);
      expect(config.panelWidthArcmin, 45.0);
      expect(config.panelHeightArcmin, 30.0);
      // Rotation falls back to framing state when no override is given.
      expect(config.rotation, 12.0);
    });

    test('rotation override beats framing state rotation', () {
      const framingState = FramingState(
        rotation: 12.0,
        mosaicEnabled: true,
        mosaicConfig: FramingMosaicConfig(columns: 2, rows: 2),
      );
      final config = buildFramingMosaicConfig(
        target: target,
        framingState: framingState,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        rotationOverrideDegrees: -45.0,
      );
      expect(config.rotation, -45.0);
    });
  });

  group('MosaicService.createMosaicSequence (from framing config)', () {
    test('emits one TargetHeaderNode per panel + a single InstructionSetNode '
        'root, distinct from the single-target path', () {
      const target = FramingTarget(
        name: 'M51',
        raHours: 13.5,
        decDegrees: 47.2,
      );
      const framingState = FramingState(
        mosaicEnabled: true,
        mosaicConfig: FramingMosaicConfig(
          columns: 2,
          rows: 3, // 6 panels total
          overlapPercent: 10.0,
        ),
      );

      final config = buildFramingMosaicConfig(
        target: target,
        framingState: framingState,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
      );

      const exposure = MosaicExposureSettings(
        exposureSeconds: 60.0,
        exposuresPerPanel: 5,
        filterName: 'L',
        binning: 1,
      );

      const mosaicService = MosaicService();
      final nodes = mosaicService.createMosaicSequence(
        mosaicName: framingMosaicNameFor(target),
        config: config,
        exposure: exposure,
      );

      // Exactly one InstructionSetNode root.
      final roots =
          nodes.values.whereType<InstructionSetNode>().where((n) => n.parentId == null);
      expect(roots.length, 1);
      expect(roots.first.name, 'M51 Mosaic');

      // 6 panels => 6 TargetHeaderNodes (one per panel). Each panel has a
      // distinct (raHours, decDegrees) and a `targetName` derived from the
      // mosaic name so the per-frame FITS path can identify which mosaic
      // the panel belongs to.
      final targetHeaders =
          nodes.values.whereType<TargetHeaderNode>().toList();
      expect(targetHeaders.length, 6);

      // All panel target names reference the parent mosaic.
      for (final h in targetHeaders) {
        expect(h.targetName, startsWith('M51 Mosaic Panel '));
      }

      // Panel centers are unique — confirms the geometry actually produced
      // 6 distinct coordinates rather than 6 copies of the target center.
      final centers = targetHeaders
          .map((h) => '${h.raHours.toStringAsFixed(6)},'
              '${h.decDegrees.toStringAsFixed(6)}')
          .toSet();
      expect(centers.length, 6);
    });

    test('framingMosaicNameFor falls back to coords when target name is empty',
        () {
      const target = FramingTarget(
        name: '',
        raHours: 13.5,
        decDegrees: -22.0,
      );
      expect(framingMosaicNameFor(target), 'Mosaic 13.50h -22.0°');
    });
  });
}
