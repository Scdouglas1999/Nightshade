import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_toolbar.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

class _DeferredSequenceFileService extends SequenceFileService {
  final importResult = Completer<Sequence?>();
  int importCalls = 0;

  @override
  Future<Sequence?> importSequence() {
    importCalls++;
    return importResult.future;
  }
}

class _SwappableBackendNotifier extends BackendNotifier {
  _SwappableBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }

  void switchTo(NightshadeBackend backend) => state = backend;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'open sequence is single-flight and cannot mutate a different host',
    (tester) async {
      final hostA = mockBackend();
      final hostB = mockBackend();
      final fileService = _DeferredSequenceFileService();
      late _SwappableBackendNotifier backendNotifier;

      final handle = await pumpAppScreen(
        tester,
        Builder(
          builder: (context) => SequenceToolbar(
            colors: NightshadeColors.of(context),
          ),
        ),
        size: const Size(1600, 900),
        extraOverrides: [
          backendProvider.overrideWith((ref) {
            backendNotifier = _SwappableBackendNotifier(ref, hostA);
            return backendNotifier;
          }),
          sequenceFileServiceProvider.overrideWithValue(fileService),
        ],
      );

      await tester.tap(find.byTooltip('Open Sequence'));
      await tester.pump();
      expect(fileService.importCalls, 1);

      // The same action is visibly disabled while the native picker is open.
      await tester.tap(find.byTooltip('Open Sequence'), warnIfMissed: false);
      await tester.pump();
      expect(fileService.importCalls, 1);

      backendNotifier.switchTo(hostB);
      fileService.importResult.complete(Sequence.create(name: 'Host A file'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(handle.container.read(currentSequenceProvider), isNull);
      expect(
        find.textContaining('imaging host changed while the file dialog'),
        findsOneWidget,
      );
    },
  );
}
