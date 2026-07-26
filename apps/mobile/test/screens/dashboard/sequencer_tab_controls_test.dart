import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_mobile/screens/dashboard/tabs/sequencer_tab.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  testWidgets(
    'host switch retires an old start without blocking the new host',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final executor = _MockSequenceExecutor();
      final firstStart = Completer<void>();
      final secondStart = Completer<void>();
      var starts = 0;
      when(
        executor.start,
      ).thenAnswer((_) => (starts++ == 0 ? firstStart : secondStart).future);
      late _SwappableBackendNotifier backendNotifier;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWith((ref) {
              backendNotifier = _SwappableBackendNotifier(
                ref,
                DisconnectedBackend(),
              );
              return backendNotifier;
            }),
            sequenceExecutorProvider.overrideWithValue(executor),
          ],
          child: MaterialApp(
            theme: NightshadeTheme.dark,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: buildSequencerControlButtonsForTesting(
                    sequence: Sequence.create(name: 'Test sequence'),
                    execState: SequenceExecutionState.idle,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final startFinder = find.widgetWithText(NightshadeButton, 'Start');
      await tester.ensureVisible(startFinder);
      await tester.tap(startFinder);
      await tester.pump();
      expect(starts, 1);
      expect(tester.widget<NightshadeButton>(startFinder).isLoading, isTrue);

      backendNotifier.switchTo(DisconnectedBackend());
      await tester.pump();
      expect(tester.widget<NightshadeButton>(startFinder).isLoading, isFalse);

      await tester.tap(startFinder);
      await tester.pump();
      expect(starts, 2);
      expect(tester.widget<NightshadeButton>(startFinder).isLoading, isTrue);

      firstStart.completeError(StateError('old host failed'));
      await tester.pump();
      expect(find.textContaining('old host failed'), findsNothing);
      expect(tester.widget<NightshadeButton>(startFinder).isLoading, isTrue);

      secondStart.complete();
      await tester.pump();
      await tester.pump();
      expect(tester.widget<NightshadeButton>(startFinder).isLoading, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

class _MockSequenceExecutor extends Mock implements SequenceExecutor {}

class _SwappableBackendNotifier extends BackendNotifier {
  _SwappableBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }

  void switchTo(NightshadeBackend backend) => state = backend;
}
