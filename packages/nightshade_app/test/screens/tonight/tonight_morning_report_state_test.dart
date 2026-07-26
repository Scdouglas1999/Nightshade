import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/tonight/one_tap_tonight_controller.dart';
import 'package:nightshade_app/screens/tonight/tonight_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Future<void> _pumpBody(
  WidgetTester tester,
  AsyncValue<int?> morningSessionAsync, {
  VoidCallback? onRetry,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: NightshadeTheme.dark,
      home: Scaffold(
        body: TonightBodyView(
          colors: NightshadeColors.dark,
          state: const OneTapTonightState(),
          activeRun: null,
          targetAsync: const AsyncData<TargetSuggestion?>(null),
          onGo: () async {},
          onReset: () {},
          onRefreshPick: () {},
          morningSessionAsync: morningSessionAsync,
          onRefreshMorningReport: onRetry ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('history loading is not mistaken for no morning report',
      (tester) async {
    await _pumpBody(tester, const AsyncLoading());

    expect(find.text('Loading morning report…'), findsOneWidget);
  });

  testWidgets('history failure is visible and retryable', (tester) async {
    var retries = 0;
    await _pumpBody(
      tester,
      AsyncError(StateError('session database unavailable'), StackTrace.empty),
      onRetry: () => retries++,
    );

    expect(find.text('Morning report unavailable'), findsOneWidget);
    expect(find.textContaining('session database unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry report'));
    expect(retries, 1);
  });
}
