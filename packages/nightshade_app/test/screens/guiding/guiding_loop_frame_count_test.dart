// IMG-9 — the `Frame Count` row in Star Statistics read `0` for the whole of a
// Loop Exposures run, directly beneath an SNR and a Star Mass that updated on
// every loop frame. All three rows read as describing the same frames, so one
// of them was lying: `frameCount` counts guide STEPS, and looping takes no
// corrections.
//
// Owner's call: while looping the row reports the loop's own frames, counting
// again from one for each new loop. The counting and per-loop reset are pinned
// at the provider in nightshade_core's guide_loop_frame_count_test.dart; this
// pins which number the screen puts on that row.
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

class _GuiderConnected extends GuiderStateNotifier {
  _GuiderConnected(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = const GuiderState(
      connectionState: DeviceConnectionState.connected,
      deviceId: builtinGuiderDeviceId,
      deviceName: 'Built-in Guider',
    );
  }
}

/// Twelve frames into a loop, and no guide step taken — the state the running
/// build showed as `Frame Count 0`.
class _LoopingStats extends GuideStatsNotifier {
  _LoopingStats(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = const Phd2GuideStats(
      snr: 445.4,
      starMass: 206760,
      frameCount: 0,
      loopFrameCount: 12,
    );
  }
}

/// Guiding after that loop: 37 guide steps, and the finished loop's 12 frames
/// still on the record.
class _GuidingStats extends GuideStatsNotifier {
  _GuidingStats(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = const Phd2GuideStats(
      rmsRa: 0.53,
      rmsDec: 0.57,
      rmsTotal: 0.78,
      snr: 445.4,
      starMass: 206760,
      frameCount: 37,
      loopFrameCount: 12,
    );
  }
}

Future<void> _drainAsyncFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

List<Override> _overrides(Phd2State phd2State, Override stats) => [
      tutorialProvider.overrideWith((ref) => _TutorialsDisabledNotifier()),
      guiderStateProvider.overrideWith(_GuiderConnected.new),
      phd2StateProvider.overrideWith((ref) => phd2State),
      stats,
    ];

/// The value rendered beside the `Frame Count` label in Star Statistics.
String _frameCountValue(WidgetTester tester) {
  final row = find.ancestor(
    of: find.text('Frame Count'),
    matching: find.byType(Row),
  );
  final texts = tester
      .widgetList<Text>(
          find.descendant(of: row.first, matching: find.byType(Text)))
      .map((t) => t.data)
      .toList();
  expect(texts.first, 'Frame Count');
  return texts.last!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a running loop reports the loop\'s own frames', (tester) async {
    await pumpAppScreen(
      tester,
      const GuidingScreen(),
      size: const Size(1400, 900),
      settle: false,
      extraOverrides: _overrides(Phd2State.looping,
          guideStatsProvider.overrideWith(_LoopingStats.new)),
    );
    await _drainAsyncFrames(tester);

    expect(
      _frameCountValue(tester),
      '12',
      reason: 'looping showed 0 while SNR and Star Mass updated per frame',
    );
  });

  testWidgets('guiding reports guide steps, not the last loop\'s frames',
      (tester) async {
    await pumpAppScreen(
      tester,
      const GuidingScreen(),
      size: const Size(1400, 900),
      settle: false,
      extraOverrides: _overrides(Phd2State.guiding,
          guideStatsProvider.overrideWith(_GuidingStats.new)),
    );
    await _drainAsyncFrames(tester);

    expect(_frameCountValue(tester), '37');
  });

  testWidgets('a stopped guider reports guide steps', (tester) async {
    await pumpAppScreen(
      tester,
      const GuidingScreen(),
      size: const Size(1400, 900),
      settle: false,
      extraOverrides: _overrides(Phd2State.stopped,
          guideStatsProvider.overrideWith(_GuidingStats.new)),
    );
    await _drainAsyncFrames(tester);

    expect(_frameCountValue(tester), '37');
  });
}
