// The Language row promises "app chrome". The persistent status bar IS app
// chrome — it is the one strip on every screen — and it was hard-coded English.
//
// Live (Settings > General > Language > Spanish, app_settings.language='es'):
// the nav rail translated (Panel / Equipo / Captura / Secuenciador) and the
// whole Settings tree translated, while the bar underneath still read
// "Camera Disconnected", "Mount Disconnected", "Guider Disconnected", "Focus",
// "Idle", "No save path", "Dashboard" on every one of those screens. The
// setting's own scoped claim was therefore still false.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/widgets/status_bar.dart';

import '../../harness/pump_app_screen.dart';

Future<void> _pumpBar(WidgetTester tester, {Locale? locale}) async {
  await pumpAppScreen(
    tester,
    const Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [StatusBar()],
    ),
    size: const Size(2600, 900),
    // The bar ticks a 1-second clock; pumpAndSettle would never return.
    settle: false,
    locale: locale,
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

/// Tears the tree down so the bar's periodic clock timer is cancelled before
/// the binding's pending-timer check runs.
Future<void> _disposeBar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Finder _inBar(String text) => find.descendant(
      of: find.byType(StatusBar),
      matching: find.text(text),
    );

void main() {
  testWidgets('the status bar follows the chosen language', (tester) async {
    await _pumpBar(tester, locale: const Locale('es'));

    // Device pills: label and state, the exact strings the audit read off the
    // Spanish build.
    expect(_inBar('Cámara'), findsOneWidget);
    expect(_inBar('Montura'), findsOneWidget);
    expect(_inBar('Guía'), findsOneWidget);
    expect(_inBar('Enfoque'), findsOneWidget);
    expect(_inBar('Desconectado'), findsWidgets);
    // Sequence-state pill and the save-path chip. The bar carries two
    // idle readouts (the progress pill and the LED), hence findsWidgets.
    expect(_inBar('Inactivo'), findsWidgets);
    expect(_inBar('Sin ruta de guardado'), findsOneWidget);
    // The web-dashboard button.
    expect(_inBar('Panel'), findsOneWidget);

    expect(_inBar('Camera'), findsNothing);
    expect(_inBar('Mount'), findsNothing);
    expect(_inBar('Disconnected'), findsNothing);
    expect(_inBar('No save path'), findsNothing);
    expect(_inBar('Idle'), findsNothing);
    expect(_inBar('Dashboard'), findsNothing);

    await _disposeBar(tester);
  });

  testWidgets('an English build is untouched', (tester) async {
    await _pumpBar(tester);

    expect(_inBar('Camera'), findsOneWidget);
    expect(_inBar('Mount'), findsOneWidget);
    expect(_inBar('Guider'), findsOneWidget);
    expect(_inBar('Focus'), findsOneWidget);
    expect(_inBar('Idle'), findsWidgets);
    expect(_inBar('No save path'), findsOneWidget);
    expect(_inBar('Dashboard'), findsOneWidget);

    await _disposeBar(tester);
  });
}
