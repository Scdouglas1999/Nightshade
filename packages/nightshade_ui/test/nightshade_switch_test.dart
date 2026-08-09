import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: NightshadeTheme.dark,
  home: Scaffold(body: Center(child: child)),
);

AnimatedContainer _trackOf(WidgetTester tester) {
  return tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(NightshadeSwitch),
      matching: find.byType(AnimatedContainer),
    ),
  );
}

void main() {
  // These pin the behaviour that was missing entirely: measured on the running
  // app, the whole Settings screen exposed ZERO checkable accessibility nodes
  // and only five focusable ones, so no switch could be read by a screen reader
  // or reached by a keyboard. Asserting the rendered visuals is not enough --
  // the control looked perfect the whole time it was unusable.
  group('NightshadeSwitch accessibility', () {
    testWidgets('reports its on/off state to assistive technology', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(const NightshadeSwitch(value: true, onChanged: _noop)),
      );
      // Focusability lives on the detector's own semantics node rather than
      // this one; the keyboard-traversal test below is what pins that.
      expect(
        tester.getSemantics(find.byType(NightshadeSwitch)),
        matchesSemantics(
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      await tester.pumpWidget(
        _wrap(const NightshadeSwitch(value: false, onChanged: _noop)),
      );
      expect(
        tester.getSemantics(find.byType(NightshadeSwitch)),
        matchesSemantics(
          hasToggledState: true,
          isToggled: false,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      handle.dispose();
    });

    testWidgets('a disabled switch is announced as disabled', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(const NightshadeSwitch(value: false, onChanged: null)),
      );
      // Asserted with matchesSemantics rather than by poking a single flag:
      // it pins that the node still declares an enabled STATE (so assistive
      // tech knows the control exists and is currently unavailable) while that
      // state is false, and that no tap action is advertised.
      expect(
        tester.getSemantics(find.byType(NightshadeSwitch)),
        matchesSemantics(
          hasToggledState: true,
          isToggled: false,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('can be reached and operated by keyboard alone', (
      tester,
    ) async {
      var value = false;
      await tester.pumpWidget(
        _wrap(NightshadeSwitch(value: value, onChanged: (v) => value = v)),
      );

      // Tab must land on the switch: before the fix nothing in the subtree was
      // focusable, so traversal skipped straight past it.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        Focus.of(
          tester.element(find.byType(NightshadeSwitch)),
          scopeOk: true,
        ).hasFocus,
        isTrue,
        reason: 'Tab traversal never reached the switch',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        value,
        isTrue,
        reason: 'Space did not activate the focused switch',
      );
    });
  });

  group('NightshadeSwitch', () {
    testWidgets('toggles on tap', (tester) async {
      var value = false;
      await tester.pumpWidget(
        _wrap(NightshadeSwitch(value: value, onChanged: (v) => value = v)),
      );
      await tester.tap(find.byType(NightshadeSwitch));
      await tester.pumpAndSettle();
      expect(value, isTrue);
    });

    testWidgets('disabled switch ignores taps', (tester) async {
      var value = false;
      await tester.pumpWidget(
        _wrap(NightshadeSwitch(value: value, onChanged: null)),
      );
      await tester.tap(find.byType(NightshadeSwitch));
      await tester.pumpAndSettle();
      expect(value, isFalse);
    });

    testWidgets('enabled false applies disabled opacity', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NightshadeSwitch(value: false, enabled: false, onChanged: (_) {}),
        ),
      );
      await tester.pump();

      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byType(AnimatedContainer),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, NightshadeTokens.opacityDisabled);
    });

    testWidgets('on track uses primary fill', (tester) async {
      await tester.pumpWidget(
        _wrap(const NightshadeSwitch(value: true, onChanged: _noop)),
      );
      await tester.pump();

      final track = _trackOf(tester);
      final decoration = track.decoration! as BoxDecoration;
      const colors = NightshadeColors.dark;
      expect(
        decoration.color,
        NightshadeSwitchStyle.trackColor(colors, selected: true),
      );
    });

    testWidgets('compact variant uses smaller track', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const NightshadeSwitch(value: false, onChanged: _noop, compact: true),
        ),
      );
      await tester.pump();

      final size = tester.getSize(find.byType(NightshadeSwitch));
      expect(size.width, NightshadeSwitchStyle.compactTrackWidth);
    });

    testWidgets('hover darkens selected track', (tester) async {
      await tester.pumpWidget(
        _wrap(const NightshadeSwitch(value: true, onChanged: _noop)),
      );
      await tester.pump();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.byType(NightshadeSwitch)));
      await tester.pump();

      final track = _trackOf(tester);
      final decoration = track.decoration! as BoxDecoration;
      expect(decoration.color, NightshadeColors.dark.primary);
    });
  });

  group('NightshadeSwitchRow', () {
    testWidgets('renders label and switch', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const NightshadeSwitchRow(
            label: 'Cooling',
            value: true,
            onChanged: _noop,
          ),
        ),
      );
      expect(find.text('Cooling'), findsOneWidget);
      expect(find.byType(NightshadeSwitch), findsOneWidget);
    });

    testWidgets('renders subtitle when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const NightshadeSwitchRow(
            label: 'Cooling',
            subtitle: 'Enable camera cooling',
            value: false,
            onChanged: _noop,
          ),
        ),
      );
      expect(find.text('Enable camera cooling'), findsOneWidget);
    });

    testWidgets('forwards toggle to onChanged', (tester) async {
      var value = false;
      await tester.pumpWidget(
        _wrap(
          NightshadeSwitchRow(
            label: 'Cooling',
            value: value,
            onChanged: (v) => value = v,
          ),
        ),
      );
      await tester.tap(find.byType(NightshadeSwitch));
      await tester.pumpAndSettle();
      expect(value, isTrue);
    });
  });

  group('NightshadeSwitchStyle.switchThemeData', () {
    test('matches NightshadeSwitch color resolution', () {
      const colors = NightshadeColors.dark;
      final theme = NightshadeSwitchStyle.switchThemeData(
        colors,
        colors.onPrimary,
      );

      final selectedTrack = theme.trackColor!.resolve({WidgetState.selected});
      expect(selectedTrack, colors.primary);

      final unselectedTrack = theme.trackColor!.resolve({});
      expect(unselectedTrack, colors.surface);

      final selectedThumb = theme.thumbColor!.resolve({WidgetState.selected});
      expect(selectedThumb, colors.onPrimary);
    });
  });
}

void _noop(bool _) {}
