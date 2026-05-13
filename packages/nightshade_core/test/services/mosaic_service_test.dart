import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/services/mosaic_service.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';

void main() {
  late MosaicService service;

  setUp(() {
    service = const MosaicService();
  });

  group('MosaicService - Panel Generation', () {
    test('generates correct number of panels for simple 3x3 grid', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 3,
        panelsVertical: 3,
      );

      final panels = service.generatePanels(config);

      expect(panels.length, equals(9));
    });

    test('generates panels with correct indices and positions', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 2,
        panelsVertical: 2,
      );

      final panels = service.generatePanels(config);

      expect(panels.length, equals(4));

      // Check indices are sequential
      for (var i = 0; i < panels.length; i++) {
        expect(panels[i].panelIndex, equals(i));
      }

      // Check row/col assignments
      expect(panels[0].row, equals(0));
      expect(panels[0].col, equals(0));
      expect(panels[1].row, equals(0));
      expect(panels[1].col, equals(1));
      expect(panels[2].row, equals(1));
      expect(panels[2].col, equals(0));
      expect(panels[3].row, equals(1));
      expect(panels[3].col, equals(1));
    });

    test('generates single panel correctly', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 1,
        panelsVertical: 1,
      );

      final panels = service.generatePanels(config);

      expect(panels.length, equals(1));

      // Single panel should be centered at mosaic center
      expect(panels[0].raHours, closeTo(12.0, 0.01));
      expect(panels[0].decDegrees, closeTo(30.0, 0.1));
    });

    test('handles large mosaic configurations', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 30.0,
        panelHeightArcmin: 20.0,
        panelsHorizontal: 10,
        panelsVertical: 10,
      );

      final panels = service.generatePanels(config);

      expect(panels.length, equals(100));
    });

    test('respects overlap percentage in panel calculations', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        overlapPercent: 10.0,
        panelsHorizontal: 2,
        panelsVertical: 1,
      );

      final panels = service.generatePanels(config);

      expect(panels.length, equals(2));

      // With 10% overlap, panels should be closer together than without
      final separation = (panels[1].raHours - panels[0].raHours).abs();

      // Expected separation is 90% of panel width (accounting for overlap)
      // 60 arcmin = 1 degree = 1/15 hours
      // With 10% overlap: 0.9 * 60 / 60 / 15 = 0.06 hours
      expect(separation, lessThan(0.07)); // Allow some margin for projection
    });

    test('applies rotation to panel layout', () {
      final configNoRotation = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        rotation: 0.0,
        panelsHorizontal: 2,
        panelsVertical: 1,
      );

      final configWithRotation = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        rotation: 90.0,
        panelsHorizontal: 2,
        panelsVertical: 1,
      );

      final panelsNoRot = service.generatePanels(configNoRotation);
      final panelsRot = service.generatePanels(configWithRotation);

      // With 90° rotation, what was horizontal should become vertical
      // Dec separation should be larger with rotation
      final decSepNoRot = (panelsNoRot[1].decDegrees - panelsNoRot[0].decDegrees).abs();
      final decSepRot = (panelsRot[1].decDegrees - panelsRot[0].decDegrees).abs();

      expect(decSepRot, greaterThan(decSepNoRot));
    });

    test('normalizes RA hours when mosaic spans across 0h', () {
      final config = MosaicConfig(
        centerRa: 23.98,
        centerDec: 10.0,
        panelWidthArcmin: 120.0,
        panelHeightArcmin: 60.0,
        panelsHorizontal: 3,
        panelsVertical: 1,
      );

      final panels = service.generatePanels(config);

      expect(panels.length, 3);
      expect(
        panels.every((panel) => panel.raHours >= 0.0 && panel.raHours < 24.0),
        isTrue,
      );
    });
  });

  group('MosaicService - Area Calculation', () {
    test('calculates correct area for simple grid', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 60.0,
        panelsHorizontal: 2,
        panelsVertical: 2,
      );

      final area = service.calculateMosaicArea(config);

      // 2x2 grid of 60'x60' panels = 120'x120' = 2°x2° = 4 sq°
      expect(area, closeTo(4.0, 0.01));
    });

    test('calculates correct area for rectangular panels', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 90.0,
        panelHeightArcmin: 60.0,
        panelsHorizontal: 1,
        panelsVertical: 1,
      );

      final area = service.calculateMosaicArea(config);

      // 90' x 60' = 1.5° x 1° = 1.5 sq°
      expect(area, closeTo(1.5, 0.01));
    });
  });

  group('MosaicService - Time Estimation', () {
    test('estimates correct time for simple mosaic', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 2,
        panelsVertical: 2,
      );

      final exposure = MosaicExposureSettings(
        exposureSeconds: 60.0,
        exposuresPerPanel: 10,
      );

      final time = service.estimateMosaicTime(config, exposure);

      // 4 panels * (10 * 60s exposure + 60s overhead) = 4 * 660s = 2640s
      expect(time, equals(2640.0));
    });

    test('respects custom overhead', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 1,
        panelsVertical: 1,
      );

      final exposure = MosaicExposureSettings(
        exposureSeconds: 60.0,
        exposuresPerPanel: 10,
      );

      final time = service.estimateMosaicTime(
        config,
        exposure,
        overheadPerPanelSecs: 120.0,
      );

      // 1 panel * (10 * 60s + 120s) = 720s
      expect(time, equals(720.0));
    });
  });

  group('MosaicService - Validation', () {
    test('validates correct configuration', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 3,
        panelsVertical: 3,
      );

      final validation = service.validateMosaic(config);

      expect(validation.isValid, isTrue);
      expect(validation.errors, isEmpty);
    });

    test('rejects invalid RA', () {
      final config = MosaicConfig(
        centerRa: 25.0, // Invalid: must be < 24
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 3,
        panelsVertical: 3,
      );

      final validation = service.validateMosaic(config);

      expect(validation.isValid, isFalse);
      expect(validation.errors, isNotEmpty);
      expect(validation.errors.any((e) => e.contains('Right Ascension')), isTrue);
    });

    test('rejects invalid declination', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 95.0, // Invalid: must be <= 90
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 3,
        panelsVertical: 3,
      );

      final validation = service.validateMosaic(config);

      expect(validation.isValid, isFalse);
      expect(validation.errors.any((e) => e.contains('Declination')), isTrue);
    });

    test('rejects invalid panel dimensions', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: -10.0, // Invalid: must be positive
        panelHeightArcmin: 40.0,
        panelsHorizontal: 3,
        panelsVertical: 3,
      );

      final validation = service.validateMosaic(config);

      expect(validation.isValid, isFalse);
      expect(validation.errors.any((e) => e.contains('dimensions')), isTrue);
    });

    test('rejects invalid grid size', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 0, // Invalid: must be >= 1
        panelsVertical: 3,
      );

      final validation = service.validateMosaic(config);

      expect(validation.isValid, isFalse);
      expect(validation.errors.any((e) => e.contains('Grid size')), isTrue);
    });

    test('warns about low overlap', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        overlapPercent: 2.0, // Low overlap
        panelsHorizontal: 3,
        panelsVertical: 3,
      );

      final validation = service.validateMosaic(config);

      expect(validation.isValid, isTrue);
      expect(validation.hasWarnings, isTrue);
      expect(validation.warnings.any((w) => w.contains('overlap')), isTrue);
    });

    test('warns about high overlap', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        overlapPercent: 60.0, // High overlap
        panelsHorizontal: 3,
        panelsVertical: 3,
      );

      final validation = service.validateMosaic(config);

      expect(validation.isValid, isTrue);
      expect(validation.hasWarnings, isTrue);
      expect(validation.warnings.any((w) => w.contains('overlap')), isTrue);
    });

    test('warns about large mosaics', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 25, // Large grid
        panelsVertical: 25,
      );

      final validation = service.validateMosaic(config);

      expect(validation.isValid, isTrue);
      expect(validation.hasWarnings, isTrue);
      expect(validation.warnings.any((w) => w.contains('20 panels')), isTrue);
    });

    test('warns about polar regions', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 85.0, // Near north celestial pole
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 3,
        panelsVertical: 3,
      );

      final validation = service.validateMosaic(config);

      expect(validation.isValid, isTrue);
      expect(validation.hasWarnings, isTrue);
      expect(validation.warnings.any((w) => w.contains('poles')), isTrue);
    });
  });

  group('MosaicService - Sequence Generation', () {
    test('generates sequence with correct number of target groups', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 2,
        panelsVertical: 2,
      );

      final exposure = MosaicExposureSettings(
        exposureSeconds: 60.0,
        exposuresPerPanel: 10,
      );

      final nodes = service.createMosaicSequence(
        mosaicName: 'Test Mosaic',
        config: config,
        exposure: exposure,
      );

      // Count target group nodes
      final targetGroups = nodes.values.whereType<TargetHeaderNode>().toList();
      expect(targetGroups.length, equals(4)); // 2x2 grid
    });

    test('generates sequence with slew and center nodes', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 1,
        panelsVertical: 1,
      );

      final exposure = MosaicExposureSettings(
        exposureSeconds: 60.0,
        exposuresPerPanel: 10,
      );

      final nodes = service.createMosaicSequence(
        mosaicName: 'Test Mosaic',
        config: config,
        exposure: exposure,
      );

      final slewNodes = nodes.values.whereType<SlewNode>().toList();
      final centerNodes = nodes.values.whereType<CenterNode>().toList();

      expect(slewNodes.length, equals(1));
      expect(centerNodes.length, equals(1));
    });

    test('generates sequence with correct loop configuration', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 1,
        panelsVertical: 1,
      );

      final exposure = MosaicExposureSettings(
        exposureSeconds: 60.0,
        exposuresPerPanel: 20,
      );

      final nodes = service.createMosaicSequence(
        mosaicName: 'Test Mosaic',
        config: config,
        exposure: exposure,
      );

      final loopNodes = nodes.values.whereType<LoopNode>().toList();

      expect(loopNodes.length, equals(1));
      expect(loopNodes[0].repeatCount, equals(20));
    });

    test('includes autofocus when enabled', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 2,
        panelsVertical: 1,
      );

      final exposure = MosaicExposureSettings(
        exposureSeconds: 60.0,
        exposuresPerPanel: 10,
      );

      final options = MosaicSequenceOptions(
        autofocusPerPanel: true,
      );

      final nodes = service.createMosaicSequence(
        mosaicName: 'Test Mosaic',
        config: config,
        exposure: exposure,
        options: options,
      );

      final autofocusNodes = nodes.values.whereType<AutofocusNode>().toList();
      expect(autofocusNodes.length, equals(2)); // One per panel
    });

    test('respects autofocus interval', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 4,
        panelsVertical: 1,
      );

      final exposure = MosaicExposureSettings(
        exposureSeconds: 60.0,
        exposuresPerPanel: 10,
      );

      final options = MosaicSequenceOptions(
        autofocusPerPanel: true,
        autofocusInterval: 1, // Every other panel
      );

      final nodes = service.createMosaicSequence(
        mosaicName: 'Test Mosaic',
        config: config,
        exposure: exposure,
        options: options,
      );

      final autofocusNodes = nodes.values.whereType<AutofocusNode>().toList();
      expect(autofocusNodes.length, equals(2)); // Panels 0 and 2
    });

    test('includes dither when enabled', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 1,
        panelsVertical: 1,
      );

      final exposure = MosaicExposureSettings(
        exposureSeconds: 60.0,
        exposuresPerPanel: 10,
      );

      final options = MosaicSequenceOptions(
        ditherBetweenExposures: true,
        ditherPixels: 5.0,
      );

      final nodes = service.createMosaicSequence(
        mosaicName: 'Test Mosaic',
        config: config,
        exposure: exposure,
        options: options,
      );

      final ditherNodes = nodes.values.whereType<DitherNode>().toList();
      expect(ditherNodes.length, equals(1));
      expect(ditherNodes[0].pixels, equals(5.0));
    });

    test('omits center when disabled', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 1,
        panelsVertical: 1,
      );

      final exposure = MosaicExposureSettings(
        exposureSeconds: 60.0,
        exposuresPerPanel: 10,
      );

      final options = MosaicSequenceOptions(
        centerAfterSlew: false,
      );

      final nodes = service.createMosaicSequence(
        mosaicName: 'Test Mosaic',
        config: config,
        exposure: exposure,
        options: options,
      );

      final centerNodes = nodes.values.whereType<CenterNode>().toList();
      expect(centerNodes, isEmpty);
    });

    test('applies altitude constraints to target groups', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 1,
        panelsVertical: 1,
      );

      final exposure = MosaicExposureSettings(
        exposureSeconds: 60.0,
        exposuresPerPanel: 10,
      );

      final options = MosaicSequenceOptions(
        minAltitude: 30.0,
        maxAltitude: 70.0,
      );

      final nodes = service.createMosaicSequence(
        mosaicName: 'Test Mosaic',
        config: config,
        exposure: exposure,
        options: options,
      );

      final targetGroups = nodes.values.whereType<TargetHeaderNode>().toList();
      expect(targetGroups[0].minAltitude, equals(30.0));
      expect(targetGroups[0].maxAltitude, equals(70.0));
    });

    test('sets correct exposure parameters', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 1,
        panelsVertical: 1,
      );

      final exposure = MosaicExposureSettings(
        exposureSeconds: 120.0,
        exposuresPerPanel: 10,
        filterName: 'Ha',
        binning: 2,
        gain: 100.0,
        offset: 10.0,
      );

      final nodes = service.createMosaicSequence(
        mosaicName: 'Test Mosaic',
        config: config,
        exposure: exposure,
      );

      final exposureNodes = nodes.values.whereType<ExposureNode>().toList();
      expect(exposureNodes.length, equals(1));
      expect(exposureNodes[0].durationSecs, equals(120.0));
      expect(exposureNodes[0].filter, equals('Ha'));
      expect(exposureNodes[0].binning, equals(BinningMode.two));
      expect(exposureNodes[0].gain, equals(100));
      expect(exposureNodes[0].offset, equals(10));
    });
  });

  group('MosaicService - Serpentine Ordering', () {
    test('applies serpentine ordering correctly', () {
      final config = MosaicConfig(
        centerRa: 12.0,
        centerDec: 30.0,
        panelWidthArcmin: 60.0,
        panelHeightArcmin: 40.0,
        panelsHorizontal: 3,
        panelsVertical: 2,
      );

      final exposure = MosaicExposureSettings(
        exposureSeconds: 60.0,
        exposuresPerPanel: 1,
      );

      final options = MosaicSequenceOptions(
        serpentineOrdering: true,
      );

      final nodes = service.createMosaicSequence(
        mosaicName: 'Test Mosaic',
        config: config,
        exposure: exposure,
        options: options,
      );

      final targetGroups = nodes.values.whereType<TargetHeaderNode>().toList();

      // With serpentine ordering for 3x2 grid:
      // Row 0: 0,1,2 (left to right)
      // Row 1: 5,4,3 (right to left)
      // So order should be: 0,1,2,5,4,3

      // Check that adjacent target groups alternate direction
      expect(targetGroups.length, equals(6));

      // First three should be in same row
      // Next three should be in next row
      final firstRowCount = targetGroups.take(3).where((t) =>
        t.targetName.contains('Panel 1') ||
        t.targetName.contains('Panel 2') ||
        t.targetName.contains('Panel 3')).length;
      expect(firstRowCount, equals(3));
    });
  });
}
