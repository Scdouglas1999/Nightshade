// Auto Select has to report what it did.
//
// Live finding IMG-9 (residual): clicking **Auto Select** while the guider was
// looping "produces no visible change and no dedicated log line — clicking it
// while looping added only the loop's own [STAR_DETECT]/camera_start_exposure
// lines, and nothing on screen moved". The command ran; the operator had no
// way to know it had. The button handed the notifier's Future straight to the
// panel, which only surfaces THROWN failures, so a success was indistinguishable
// from a dead control.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/guiding/guiding_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

class _TutorialsDisabledNotifier extends TutorialNotifier {
  _TutorialsDisabledNotifier() : super(_NoopTutorialProgressDao()) {
    // ignore: invalid_use_of_protected_member
    state = const TutorialProgress(tutorialsEnabled: false);
  }
}

class _NoopTutorialProgressDao implements TutorialProgressDao {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'NoopTutorialProgressDao.${invocation.memberName} called in test',
      );
}

class _BuiltinGuiderConnected extends GuiderStateNotifier {
  _BuiltinGuiderConnected(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = const GuiderState(
      connectionState: DeviceConnectionState.connected,
      deviceId: builtinGuiderDeviceId,
      deviceName: 'Built-in Guider',
      isGuiding: true,
    );
  }
}

/// Accepts the command and reports the star it locked, like a guider that
/// found one.
class _FindsAStar extends LockPositionNotifier {
  _FindsAStar(super.ref);

  bool called = false;

  @override
  Future<void> findStar() async {
    called = true;
    state = (x: 512.4, y: 384.6);
  }
}

/// Accepts the command and reports no star, like a guider that found none.
class _FindsNothing extends LockPositionNotifier {
  _FindsNothing(super.ref);

  @override
  Future<void> findStar() async {
    state = null;
  }
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpGuiding(
  WidgetTester tester,
  List<Override> extra,
) async {
  await pumpAppScreen(
    tester,
    const GuidingScreen(),
    size: const Size(1280, 900),
    settle: false,
    extraOverrides: [
      tutorialProvider.overrideWith((ref) => _TutorialsDisabledNotifier()),
      guiderStateProvider.overrideWith(_BuiltinGuiderConnected.new),
      ...extra,
    ],
  );
  await _drain(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Auto Select reports the star it selected', (tester) async {
    late _FindsAStar lock;
    await _pumpGuiding(tester, [
      lockPositionProvider.overrideWith((ref) {
        lock = _FindsAStar(ref);
        return lock;
      }),
    ]);

    await tester.tap(find.text('Auto Select'));
    await _drain(tester);

    expect(lock.called, isTrue, reason: 'the command must still be issued');
    expect(
      find.textContaining('Guide star selected at (512.4, 384.6)'),
      findsOneWidget,
      reason: 'a successful Auto Select produced no visible response at all',
    );
  });

  testWidgets('Auto Select says so when it finds nothing', (tester) async {
    await _pumpGuiding(tester, [
      lockPositionProvider.overrideWith(_FindsNothing.new),
    ]);

    await tester.tap(find.text('Auto Select'));
    await _drain(tester);

    expect(
      find.textContaining('found no guide star'),
      findsOneWidget,
      reason: 'finding nothing is the outcome most worth reporting',
    );
  });
}
