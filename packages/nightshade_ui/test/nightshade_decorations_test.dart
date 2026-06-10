import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  group('NightshadeDecorations', () {
    test('iconChip applies subtle fill and border alpha', () {
      const color = Color(0xFF5B9EC4);
      final decoration = NightshadeDecorations.iconChip(color);

      expect(decoration.color, color.withValues(alpha: 0.1));
      expect(
        decoration.border,
        Border.all(color: color.withValues(alpha: 0.16)),
      );
    });

    test('emphasisSurface uses strong border alpha', () {
      const color = Color(0xFFD49A3A);
      final decoration = NightshadeDecorations.emphasisSurface(color);

      expect(decoration.color, color.withValues(alpha: 0.1));
      expect(
        decoration.border,
        Border.all(color: color.withValues(alpha: 0.3)),
      );
    });

    test('filledButtonColors lightens on hover', () {
      const base = Color(0xFF3DAA6D);
      final normal = NightshadeDecorations.filledButtonColors(
        base,
        isHovered: false,
        isDisabled: false,
      );
      final hovered = NightshadeDecorations.filledButtonColors(
        base,
        isHovered: true,
        isDisabled: false,
      );

      expect(normal.background, base);
      expect(hovered.background, Color.lerp(base, Colors.white, 0.04));
      expect(normal.border, Color.lerp(base, Colors.black, 0.12));
    });

    test('kpiBadge uses score badge fill and border', () {
      const color = Color(0xFF3DAA6D);
      final decoration = NightshadeDecorations.kpiBadge(color);

      expect(
        decoration.color,
        color.withValues(alpha: NightshadeTokens.opacityStatusFill),
      );
      expect(
        decoration.border,
        Border.all(color: color.withValues(alpha: 0.4)),
      );
    });

    test('cardSelected uses 4% tint without shadow', () {
      const accent = Color(0xFF5B9EC4);
      const background = Color(0xFF111418);
      final decoration = NightshadeDecorations.cardSelected(
        accent,
        background: background,
      );

      expect(
        decoration.color,
        Color.alphaBlend(accent.withValues(alpha: 0.04), background),
      );
      expect(decoration.boxShadow, isNull);
    });

    test('dragFeedback uses neutral elevation shadow', () {
      const colors = NightshadeColors.dark;
      final decoration = NightshadeDecorations.dragFeedback(colors);

      expect(decoration.boxShadow, NightshadeTokens.elevationLevel2);
    });

    test('statusChip uses status fill alpha', () {
      const color = Color(0xFF3DAA6D);
      final decoration = NightshadeDecorations.statusChip(color);

      expect(
        decoration.color,
        color.withValues(alpha: NightshadeTokens.opacityStatusFill),
      );
    });

    testWidgets('NightshadeColors.of resolves theme extension', (tester) async {
      const colors = NightshadeColors.dark;
      late BuildContext context;

      await tester.pumpWidget(
        MaterialApp(
          theme: NightshadeTheme.dark,
          home: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(NightshadeColors.of(context).primary, colors.primary);
    });
  });
}
