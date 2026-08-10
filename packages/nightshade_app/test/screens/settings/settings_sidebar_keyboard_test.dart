// The Settings section navigator must be usable without a mouse.
//
// Measured on the running app: clicking the Settings search box and pressing
// Tab 24 times left the sidebar pixel-identical every single time — focus
// never landed on any of the 7 group headers or 35 section entries, and the
// accessibility tree reported every entry as "panel: General" while real
// buttons on the same screen reported "button: Test Connection". Both
// _GroupHeader and _CategoryItem were a bare GestureDetector inside a
// MouseRegion: no Focus, no InkWell, no Semantics(button: true). A
// keyboard-only or screen-reader user could not change settings section at
// all.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/settings_screen.dart';
import 'package:nightshade_app/screens/settings/widgets/appearance_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

class _StubAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async => const AppSettingsState();
}

/// Text rendered inside whatever currently holds keyboard focus.
List<String> _focusedTexts() {
  final element = FocusManager.instance.primaryFocus?.context as Element?;
  if (element == null) return const [];
  final texts = <String>[];
  void visit(Element child) {
    final widget = child.widget;
    if (widget is Text && widget.data != null) texts.add(widget.data!);
    child.visitChildren(visit);
  }

  element.visitChildren(visit);
  return texts;
}

void _swallowKnownOverflows() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    defaultOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = defaultOnError);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Tab reaches a settings section and Enter opens it', (
    tester,
  ) async {
    _swallowKnownOverflows();
    await pumpAppScreen(
      tester,
      const SettingsScreen(),
      size: const Size(1280, 900),
      extraOverrides: [
        appSettingsProvider.overrideWith(_StubAppSettingsNotifier.new),
      ],
    );
    await tester.pumpAndSettle();

    // Start where the audit started: in the search box.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    var reached = false;
    for (var press = 0; press < 24 && !reached; press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      reached = _focusedTexts().contains('Appearance');
    }
    expect(
      reached,
      isTrue,
      reason: 'focus never landed on a settings section entry in 24 tab '
          'presses — the navigator is mouse-only',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.byType(AppearanceSettings),
      findsOneWidget,
      reason: 'Enter on a focused section entry must open it',
    );
  });

  testWidgets('sections and group headers announce themselves as buttons', (
    tester,
  ) async {
    _swallowKnownOverflows();
    final semantics = tester.ensureSemantics();
    await pumpAppScreen(
      tester,
      const SettingsScreen(),
      size: const Size(1280, 900),
      extraOverrides: [
        appSettingsProvider.overrideWith(_StubAppSettingsNotifier.new),
      ],
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.text('Appearance')),
      matchesSemantics(
        label: 'Appearance',
        isButton: true,
        isSelected: false,
        hasSelectedState: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        // A live section has to say it is live. `matchesSemantics` treats every
        // unlisted flag as an assertion that it is ABSENT, so omitting these
        // two pinned the pre-2026-08-10 behaviour: `Semantics(button: true)`
        // without `enabled:` publishes no isEnabled flag at all, and AT-SPI
        // reads that as insensitive. Measured on the running app, the whole
        // settings sidebar announced as disabled.
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    // The group header is a control too: it collapses/expands the group.
    expect(
      tester.getSemantics(find.text('GENERAL')),
      matchesSemantics(
        label: 'GENERAL',
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    semantics.dispose();
  });
}
