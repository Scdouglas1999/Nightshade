import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_mobile/screens/dashboard/mobile_dashboard_screen.dart';
import 'package:nightshade_mobile/screens/setup/first_run_setup_screen.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  testWidgets('dashboard stays gated while setup detection is loading', (
    tester,
  ) async {
    final detection = Completer<FirstRunSetupNeeds>();
    await tester.pumpWidget(
      _app(
        shouldRunFirstRunSetupProvider.overrideWith((ref) => detection.future),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Devices'), findsNothing);
  });

  testWidgets('setup detection failure is visible and retryable', (
    tester,
  ) async {
    var attempts = 0;
    final retry = Completer<FirstRunSetupNeeds>();
    await tester.pumpWidget(
      _app(
        shouldRunFirstRunSetupProvider.overrideWith((ref) {
          attempts++;
          if (attempts == 1) return Future.error(StateError('offline'));
          return retry.future;
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not check server setup'), findsOneWidget);
    expect(find.text('Devices'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

Widget _app(Override override) => ProviderScope(
  overrides: [override],
  child: MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [NightshadeColors.dark]),
    home: const MobileDashboardScreen(),
  ),
);
