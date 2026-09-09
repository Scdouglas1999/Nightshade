import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? NightshadeTheme.dark,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('Readout', () {
    testWidgets('a null value renders the em dash, muted', (tester) async {
      await tester.pumpWidget(
        _host(const Readout(value: null, label: 'HFR', unit: 'px')),
      );

      expect(find.text(kReadoutUnknown), findsOneWidget);
      // The unit is not drawn beside an unknown value: there is nothing for it
      // to be the unit OF.
      expect(find.text('px'), findsNothing);

      const colors = NightshadeColors.dark;
      final text = tester.widget<Text>(find.text(kReadoutUnknown));
      expect(text.style?.color, colors.textMuted);
    });

    testWidgets('a value renders loud, its unit muted at 60%', (tester) async {
      await tester.pumpWidget(
        _host(const Readout(value: '2.49', label: 'HFR', unit: 'px')),
      );

      final rich = tester.widget<Text>(
        find.byWidgetPredicate((w) => w is Text && w.textSpan != null),
      );
      final span = rich.textSpan! as TextSpan;
      expect(span.text, '2.49');
      final unit = span.children!.whereType<TextSpan>().single;
      expect(unit.text, 'px');
      expect(
        unit.style!.fontSize,
        closeTo(
          NightshadeTypography.readoutMd.fontSize! * Readout.unitScale,
          0.001,
        ),
      );
      expect(unit.style!.color, NightshadeColors.dark.textMuted);
    });

    testWidgets('the label is uppercased and the size selects the style', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const Readout(value: '43', label: 'Stars', size: ReadoutSize.lg)),
      );

      expect(find.text('STARS'), findsOneWidget);
      final value = tester.widget<Text>(
        find.byWidgetPredicate((w) => w is Text && w.textSpan != null),
      );
      expect(value.style!.fontSize, NightshadeTypography.readoutLg.fontSize);
    });

    testWidgets('KeyValueList lays out key and value per row', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 320,
            child: KeyValueList(
              rows: <(String, String)>[('Clouds', '4%'), ('Wind', '6 km/h')],
            ),
          ),
        ),
      );

      expect(find.text('Clouds'), findsOneWidget);
      expect(find.text('6 km/h'), findsOneWidget);
    });
  });

  group('NightshadePanel', () {
    testWidgets('takes the panel decoration and 16px padding', (tester) async {
      await tester.pumpWidget(
        _host(const NightshadePanel(child: Text('body'))),
      );

      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text('body'), matching: find.byType(Container))
            .first,
      );
      expect(container.padding, NightshadeTokens.paddingLg);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, NightshadeColors.dark.surface);
    });

    testWidgets('selected swaps in the primary ring', (tester) async {
      await tester.pumpWidget(
        _host(const NightshadePanel(selected: true, child: Text('body'))),
      );

      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text('body'), matching: find.byType(Container))
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(
        decoration.border!.top.color,
        NightshadeColors.dark.primary.withValues(
          alpha: NightshadeTokens.opacitySelectedRing,
        ),
      );
    });

    testWidgets('PanelHead uppercases its label and keeps 20px', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const NightshadePanel(
            head: PanelHead(label: 'Equipment', icon: LucideIcons.aperture),
            child: Text('body'),
          ),
        ),
      );

      expect(find.text('EQUIPMENT'), findsOneWidget);
      expect(tester.getSize(find.byType(PanelHead)).height, PanelHead.height);
    });
  });

  group('NightshadeChip', () {
    testWidgets('neutral takes the solid hover fill', (tester) async {
      await tester.pumpWidget(_host(const NightshadeChip(label: '27 nodes')));

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, NightshadeColors.dark.surfaceHover);
      expect(
        tester.getSize(find.byType(NightshadeChip)).height,
        NightshadeChip.height,
      );
    });

    testWidgets('a tone tints the fill and colours the dot', (tester) async {
      await tester.pumpWidget(
        _host(
          const NightshadeChip(
            label: 'Connected',
            tone: ChipTone.success,
            dot: true,
          ),
        ),
      );

      const colors = NightshadeColors.dark;
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration! as BoxDecoration;
      expect(
        decoration.color,
        colors.success.withValues(alpha: NightshadeTokens.opacityStatusFill),
      );
      expect(
        tester.widget<StatusDot>(find.byType(StatusDot)).color,
        colors.success,
      );
    });
  });

  group('StatusDot', () {
    testWidgets('is 7px and carries no halo at rest', (tester) async {
      await tester.pumpWidget(
        _host(StatusDot(color: NightshadeColors.dark.success)),
      );

      expect(
        tester.getSize(find.byType(StatusDot)).height,
        StatusDot.defaultSize,
      );
      final container = tester.widget<Container>(find.byType(Container).first);
      expect((container.decoration! as BoxDecoration).boxShadow, isNull);
    });

    testWidgets('live adds the static success halo', (tester) async {
      await tester.pumpWidget(
        _host(StatusDot(color: NightshadeColors.dark.success, live: true)),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final shadow = (container.decoration! as BoxDecoration).boxShadow!.single;
      expect(shadow.spreadRadius, StatusDot.liveHaloWidth);
      expect(shadow.blurRadius, 0);
      expect(
        shadow.color,
        NightshadeColors.dark.success.withValues(
          alpha: NightshadeTokens.opacityLiveHalo,
        ),
      );
    });
  });

  group('NightshadeIconButton', () {
    testWidgets('is square at each size and names itself from the tooltip', (
      tester,
    ) async {
      for (final (size, extent) in <(IconButtonSize, double)>[
        (IconButtonSize.md, NightshadeTokens.iconButtonSize),
        (IconButtonSize.sm, NightshadeTokens.iconButtonSizeSm),
        (IconButtonSize.strip, NightshadeTokens.iconButtonSizeStrip),
      ]) {
        await tester.pumpWidget(
          _host(
            NightshadeIconButton(
              icon: LucideIcons.settings,
              tooltip: 'Open settings',
              size: size,
              onPressed: () {},
            ),
          ),
        );
        final box = tester.getSize(
          find.descendant(
            of: find.byType(NightshadeIconButton),
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(box.width, extent);
        expect(box.height, extent);
      }

      final semantics = tester.getSemantics(
        find.byType(NightshadeIconButton).first,
      );
      expect(semantics.label, 'Open settings');
    });

    testWidgets('selected paints the accent tint and a primary glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          NightshadeIconButton(
            icon: LucideIcons.layers,
            tooltip: 'Layers',
            selected: true,
            onPressed: () {},
          ),
        ),
      );

      const colors = NightshadeColors.dark;
      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(
        decoration.color,
        colors.primary.withValues(alpha: NightshadeTokens.opacityAccentTint),
      );
      expect(tester.widget<Icon>(find.byType(Icon)).color, colors.primary);
    });

    testWidgets('a null onPressed disables it', (tester) async {
      await tester.pumpWidget(
        _host(
          const NightshadeIconButton(
            icon: LucideIcons.trash2,
            tooltip: 'Delete',
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(NightshadeIconButton));
      expect(semantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        NightshadeTokens.opacityDisabled,
      );
    });
  });
}
