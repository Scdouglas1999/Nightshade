import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/settings/widgets/replay_debug_settings.dart'
    as replay_ui;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

class _MockReplayController extends Mock
    implements ReplayDebugSettingsController {}

class _SwappableBackendNotifier extends BackendNotifier {
  _SwappableBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }

  void switchTo(NightshadeBackend backend) => state = backend;
}

Finder _clearButton() =>
    find.widgetWithText(NightshadeButton, 'Clear all replay history');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('host switch during confirmation cancels the clear',
      (tester) async {
    final controller = _MockReplayController();
    late _SwappableBackendNotifier backendNotifier;
    await pumpAppScreen(
      tester,
      const replay_ui.ReplayDebugSettings(),
      extraOverrides: [
        backendProvider.overrideWith((ref) {
          backendNotifier =
              _SwappableBackendNotifier(ref, DisconnectedBackend());
          return backendNotifier;
        }),
        replayDebugEnabledProvider.overrideWith((ref) async => true),
        replayDebugRetentionDaysProvider.overrideWith((ref) async => 90),
        replayDebugSettingsControllerProvider.overrideWithValue(controller),
      ],
    );

    await tester.tap(_clearButton());
    await tester.pump();
    expect(find.text('Clear all replay history?'), findsOneWidget);

    backendNotifier.switchTo(DisconnectedBackend());
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pump();

    verifyNever(() => controller.clearAllHistory());
    final button = tester.widget<NightshadeButton>(_clearButton());
    expect(button.onPressed, isNotNull);
    expect(button.isLoading, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late clear result from the old host is discarded',
      (tester) async {
    final controller = _MockReplayController();
    final clear = Completer<int>();
    when(() => controller.clearAllHistory()).thenAnswer((_) => clear.future);
    late _SwappableBackendNotifier backendNotifier;
    await pumpAppScreen(
      tester,
      const replay_ui.ReplayDebugSettings(),
      extraOverrides: [
        backendProvider.overrideWith((ref) {
          backendNotifier =
              _SwappableBackendNotifier(ref, DisconnectedBackend());
          return backendNotifier;
        }),
        replayDebugEnabledProvider.overrideWith((ref) async => true),
        replayDebugRetentionDaysProvider.overrideWith((ref) async => 90),
        replayDebugSettingsControllerProvider.overrideWithValue(controller),
      ],
    );

    await tester.tap(_clearButton());
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pump();
    verify(() => controller.clearAllHistory()).called(1);

    backendNotifier.switchTo(DisconnectedBackend());
    await tester.pump();
    clear.complete(4);
    await tester.pump();
    await tester.pump();

    expect(find.text('Cleared 4 replay decision row(s).'), findsNothing);
    final button = tester.widget<NightshadeButton>(_clearButton());
    expect(button.onPressed, isNotNull);
    expect(button.isLoading, isFalse);
    expect(tester.takeException(), isNull);
  });
}
