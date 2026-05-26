// Wave 5 Agent 2 — sky-brightness adaptive exposure validation tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/providers/sequence/rules/adaptive_exposure_rules.dart';

Sequence _sequenceWith(ExposureNode node) {
  // Minimal sequence shell wrapping one exposure node. The validators
  // we test here only read the nodes map, not the relationships, so the
  // shell can be empty otherwise.
  return Sequence.create(
    id: 'seq',
    name: 'test',
    nodes: {node.id: node},
    rootNodeId: node.id,
  );
}

ExposureNode _exp({
  String filter = 'L',
  double duration = 60.0,
  AdaptiveExposureConfig? adaptive,
}) {
  return ExposureNode(
    id: 'e1',
    name: 'Exposure',
    durationSecs: duration,
    count: 5,
    filter: filter,
    adaptiveExposure: adaptive,
  );
}

void main() {
  group('AdaptiveExposureBoundsRule', () {
    final rule = AdaptiveExposureBoundsRule();

    test('no override = clean', () {
      final issues = rule.validate(_sequenceWith(_exp()));
      expect(issues, isEmpty);
    });

    test('min > max fires error', () {
      final cfg = AdaptiveExposureConfig(
        minExposureSecs: 300,
        maxExposureSecs: 60,
      );
      final issues = rule.validate(_sequenceWith(_exp(adaptive: cfg)));
      expect(issues.length, 1);
      expect(issues.first.severity, ValidationSeverity.error);
      expect(issues.first.title, contains('inverted'));
    });

    test('min <= 0 fires error', () {
      final cfg = AdaptiveExposureConfig(minExposureSecs: 0);
      final issues = rule.validate(_sequenceWith(_exp(adaptive: cfg)));
      expect(issues.where((i) => i.title.contains('min must be > 0')),
          hasLength(1));
    });

    test('max <= 0 fires error', () {
      final cfg = AdaptiveExposureConfig(maxExposureSecs: 0);
      final issues = rule.validate(_sequenceWith(_exp(adaptive: cfg)));
      expect(issues.where((i) => i.title.contains('max must be > 0')),
          hasLength(1));
    });

    test('per-filter min > effective max fires error', () {
      final cfg = AdaptiveExposureConfig(
        minExposureSecs: 5,
        maxExposureSecs: 600,
        perFilterMinSecs: const {'L': 700},
      );
      final issues = rule.validate(_sequenceWith(_exp(adaptive: cfg)));
      expect(
        issues.where(
            (i) => i.title.contains('per-filter bounds inverted')),
        hasLength(1),
      );
    });
  });

  group('AdaptiveExposureNoFilterEnabledRule', () {
    final rule = AdaptiveExposureNoFilterEnabledRule();

    test('empty per-filter map = clean (implicit-global)', () {
      final cfg = AdaptiveExposureConfig();
      final issues = rule.validate(_sequenceWith(_exp(adaptive: cfg)));
      expect(issues, isEmpty);
    });

    test('disabled override = clean', () {
      final cfg = AdaptiveExposureConfig(
        enabled: false,
        perFilterEnabled: const {'L': false, 'R': false},
      );
      final issues = rule.validate(_sequenceWith(_exp(adaptive: cfg)));
      expect(issues, isEmpty);
    });

    test('all-disabled per-filter map fires warning', () {
      final cfg = AdaptiveExposureConfig(
        enabled: true,
        perFilterEnabled: const {'L': false, 'R': false, 'B': false},
      );
      final issues = rule.validate(_sequenceWith(_exp(adaptive: cfg)));
      expect(issues, hasLength(1));
      expect(issues.first.severity, ValidationSeverity.warning);
    });

    test('one filter enabled = clean', () {
      final cfg = AdaptiveExposureConfig(
        enabled: true,
        perFilterEnabled: const {'L': true, 'R': false},
      );
      final issues = rule.validate(_sequenceWith(_exp(adaptive: cfg)));
      expect(issues, isEmpty);
    });
  });

  group('AdaptiveExposureNominalOutOfBoundsRule', () {
    final rule = AdaptiveExposureNominalOutOfBoundsRule();

    test('nominal inside bounds = clean', () {
      final cfg = AdaptiveExposureConfig(
        minExposureSecs: 10,
        maxExposureSecs: 600,
      );
      final issues = rule.validate(_sequenceWith(_exp(adaptive: cfg, duration: 60)));
      expect(issues, isEmpty);
    });

    test('nominal below min fires warning', () {
      final cfg = AdaptiveExposureConfig(
        minExposureSecs: 100,
        maxExposureSecs: 600,
      );
      final issues = rule.validate(_sequenceWith(_exp(adaptive: cfg, duration: 60)));
      expect(issues, hasLength(1));
      expect(issues.first.severity, ValidationSeverity.warning);
      expect(issues.first.title, contains('below'));
    });

    test('nominal above max fires warning', () {
      final cfg = AdaptiveExposureConfig(
        minExposureSecs: 5,
        maxExposureSecs: 60,
      );
      final issues = rule.validate(_sequenceWith(_exp(adaptive: cfg, duration: 600)));
      expect(issues, hasLength(1));
      expect(issues.first.severity, ValidationSeverity.warning);
      expect(issues.first.title, contains('above'));
    });

    test('disabled config = clean', () {
      final cfg = AdaptiveExposureConfig(
        enabled: false,
        minExposureSecs: 100,
        maxExposureSecs: 600,
      );
      final issues = rule.validate(_sequenceWith(_exp(adaptive: cfg, duration: 60)));
      expect(issues, isEmpty);
    });
  });
}
