// SCI-28 (Stop destroys the stack) + SCI-47 (frame counts and pixel counts in
// one unitless list) for the live-stacking panel.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/imaging/widgets/stacking_panel.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../harness/mock_database.dart' show inMemoryDatabaseOverride;

/// Ordered log of the operations the panel performed, so "saved before the
/// stacker was released" is provable and not merely plausible.
final _log = <String>[];

class _RecordingLiveStackingNotifier extends LiveStackingNotifier {
  _RecordingLiveStackingNotifier(super.ref, LiveStackingState initial) {
    // ignore: invalid_use_of_protected_member
    state = initial;
  }

  int stopCalls = 0;

  @override
  Future<void> stop() async {
    stopCalls++;
    _log.add('stop');
    // ignore: invalid_use_of_protected_member
    state = LiveStackingState(config: state.config);
  }
}

class _FakeLiveStackingService extends LiveStackingService {
  _FakeLiveStackingService(super.ref);

  final saved = <String>[];
  bool failSave = false;

  @override
  Future<LiveStackingMasterSave> saveMaster({required String filePath}) async {
    // Mirrors the real service: the writer is PNG-only and refuses any other
    // extension rather than renaming the operator's file.
    final extension = filePath.contains('.')
        ? filePath.substring(filePath.lastIndexOf('.')).toLowerCase()
        : '';
    if (extension.isNotEmpty && extension != '.png') {
      _log.add('save-wrong-format');
      throw LiveStackingMasterFormatUnsupported(extension);
    }
    if (failSave) {
      _log.add('save-failed');
      throw StateError('destination is not writable');
    }
    saved.add(filePath);
    _log.add('save');
    return LiveStackingMasterSave(
      filePath: filePath,
      stackedFrameCount: 32,
      format: LiveStackingMasterFormat.linearMono16,
    );
  }
}

const _stats = LiveStackingStats(
  stackedFrameCount: 32,
  totalFramesAttempted: 32,
  rejectedAlignmentFailures: 0,
  avgMatchedPairs: 39.0,
  avgAlignmentResidual: 0.52,
  totalSigmaRejectedPixels: 7300000,
);

typedef _Harness = ({
  _RecordingLiveStackingNotifier stacker,
  _FakeLiveStackingService service,
});

Future<_Harness> _pumpPanel(
  WidgetTester tester, {
  String? destination,
  bool failSave = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 1600);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  _log.clear();

  late _RecordingLiveStackingNotifier stacker;
  final container = ProviderContainer(
    overrides: [
      inMemoryDatabaseOverride(),
      isRemoteModeProvider.overrideWithValue(false),
      connectedCameraIdProvider.overrideWithValue(null),
      stackingMasterDestinationPickerProvider.overrideWithValue(
        (suggestedName) async {
          _log.add('pick:$suggestedName');
          return destination;
        },
      ),
      liveStackingServiceProvider.overrideWith(
        (ref) => _FakeLiveStackingService(ref)..failSave = failSave,
      ),
      liveStackingProvider.overrideWith((ref) {
        stacker = _RecordingLiveStackingNotifier(
          ref,
          const LiveStackingState(
            status: LiveStackingStatus.running,
            stats: _stats,
            lastFrameSigmaRejectedPixels: 271800,
            lastFrameTotalPixels: 2073600,
          ),
        );
        return stacker;
      }),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(
          body: StackingPanel(colors: NightshadeColors.dark),
        ),
      ),
    ),
  );
  await tester.pump();
  return (
    stacker: stacker,
    service:
        container.read(liveStackingServiceProvider) as _FakeLiveStackingService,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Stop does not discard an accumulated stack unprompted',
      (tester) async {
    final harness = await _pumpPanel(tester);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      harness.stacker.stopCalls,
      0,
      reason: '32 stacked frames must not be released without a prompt',
    );
    expect(find.text('Keep this stack?'), findsOneWidget);
  });

  testWidgets('Discard is an explicit choice that then releases the stack',
      (tester) async {
    final harness = await _pumpPanel(tester);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(harness.stacker.stopCalls, 1);
    expect(harness.service.saved, isEmpty);
  });

  testWidgets('Save master writes the stack out before releasing it',
      (tester) async {
    final harness = await _pumpPanel(tester, destination: '/tmp/master.png');

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save master'));
    await tester.pumpAndSettle();

    expect(harness.service.saved, ['/tmp/master.png']);
    expect(harness.stacker.stopCalls, 1);
    final ops = _log.where((e) => !e.startsWith('pick:')).toList();
    expect(ops, ['save', 'stop'],
        reason: 'the master must be on disk before the stacker is released');
    expect(find.textContaining('/tmp/master.png'), findsOneWidget);
  });

  testWidgets('a cancelled destination leaves the stack running',
      (tester) async {
    final harness = await _pumpPanel(tester);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save master'));
    await tester.pumpAndSettle();

    expect(harness.service.saved, isEmpty);
    expect(harness.stacker.stopCalls, 0,
        reason: 'cancelling the save must not cost the operator the stack');
  });

  testWidgets('a failed save leaves the stack running', (tester) async {
    final harness = await _pumpPanel(
      tester,
      destination: '/nope/master.png',
      failSave: true,
    );

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save master'));
    await tester.pumpAndSettle();

    expect(harness.stacker.stopCalls, 0);
    expect(find.text('Could not save the stacked master'), findsOneWidget);
  });

  // ND-6: typing `stack_master.fits` into the save chooser produced
  // `stack_master.png` on disk — the extension was swapped silently, so the
  // operator believed they had a FITS master with a header, WCS and
  // integration metadata, and had a picture instead.
  testWidgets('asking for a FITS master is refused, not renamed',
      (tester) async {
    final harness = await _pumpPanel(
      tester,
      destination: '/tmp/ns-audit/stack_master.fits',
    );

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save master'));
    await tester.pumpAndSettle();

    expect(harness.service.saved, isEmpty);
    expect(
      harness.stacker.stopCalls,
      0,
      reason: 'nothing was written, so the stack must survive',
    );
    expect(find.text('Live-stack masters are saved as PNG'), findsOneWidget);
    expect(find.textContaining('.fits'), findsWidgets);
  });

  testWidgets('the Stop prompt names the format it is about to write',
      (tester) async {
    await _pumpPanel(tester);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    expect(find.textContaining('16-bit PNG'), findsOneWidget);
  });

  testWidgets('Statistics rows carry units for frames and for pixels',
      (tester) async {
    await _pumpPanel(tester);

    expect(find.text('32 frames'), findsWidgets);
    expect(find.text('7.3M px'), findsOneWidget);
    expect(find.text('271.8K px'), findsOneWidget);
    expect(find.text('PIXELS REJECTED BY SIGMA CLIPPING'), findsOneWidget);
  });
}
