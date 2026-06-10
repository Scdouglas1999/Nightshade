import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  group('BackendProtocolColors', () {
    test('maps each backend to a distinct semantic hue', () {
      const colors = NightshadeColors.dark;

      expect(
        BackendProtocolColors.forBackend(DriverType.native, colors),
        colors.success,
      );
      expect(
        BackendProtocolColors.forBackend(DriverType.ascom, colors),
        colors.info,
      );
      expect(
        BackendProtocolColors.forBackend(DriverType.alpaca, colors),
        colors.warning,
      );
      expect(
        BackendProtocolColors.forBackend(DriverType.indi, colors),
        BackendProtocolColors.indi,
      );
      expect(
        BackendProtocolColors.forBackend(DriverType.simulator, colors),
        colors.textMuted,
      );
    });
  });

  group('AnnotationTypeColors', () {
    test('maps catalog types to theme-aligned colors', () {
      const colors = NightshadeColors.dark;

      expect(
        AnnotationTypeColors.forType(ObjectType.nebula, colors),
        AnnotationTypeColors.nebula,
      );
      expect(
        AnnotationTypeColors.forType(ObjectType.unknown, colors),
        colors.textMuted,
      );
    });
  });

  group('AnnotationStatusColors', () {
    test('derives status colors from theme semantics', () {
      const colors = NightshadeColors.dark;

      expect(
        AnnotationStatusColors.background(AnnotationStatus.complete, colors),
        isNot(Colors.transparent),
      );
      expect(
        AnnotationStatusColors.border(AnnotationStatus.error, colors),
        colors.error.withValues(alpha: 0.5),
      );
      expect(
        AnnotationStatusColors.background(AnnotationStatus.idle, colors),
        Colors.transparent,
      );
    });
  });

  group('NightshadeChartColors', () {
    test('provides six desaturated series colors', () {
      expect(NightshadeChartColors.series, hasLength(6));
    });

    test('gradient presets preserve stop count', () {
      expect(NightshadeChartColors.psfGradient, hasLength(3));
      expect(NightshadeChartColors.clipLowGradient, hasLength(3));
    });

    test('twilight astro applies alpha', () {
      expect(
        NightshadeChartColors.twilightAstro(alpha: 0.4).a,
        closeTo(0.4, 0.01),
      );
    });
  });
}
