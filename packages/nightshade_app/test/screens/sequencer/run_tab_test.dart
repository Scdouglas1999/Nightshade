// Widget tests for the Run dashboard tab.
//
// The tests override the providers that drive each panel so we don't
// need the real FFI backend or database. We exercise:
//
//   * Idle-state rendering (no sequence running) → empty state with a
//     "Go to Builder" button that flips the sequencerTabProvider back.
//   * Active-state rendering → panel titles appear for the expected
//     wide-layout columns.
//   * Customize menu → hiding a panel removes it from the layout.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/sequencer_screen.dart'
    show sequencerTabProvider;
import 'package:nightshade_app/screens/sequencer/tabs/run_tab.dart';
import 'package:nightshade_app/screens/sequencer/widgets/run_dashboard/run_dashboard_prefs.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Widget _wrap({
  required List<Override> overrides,
  double width = 1400,
  double height = 900,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: NightshadeTheme.dark,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: Size(width, height)),
          child: const RunTab(),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('idle state shows empty state and Go-to-Builder button',
      (tester) async {
    int? observedTab;
    await tester.pumpWidget(_wrap(overrides: [
      sequenceExecutionStateProvider
          .overrideWith((ref) => SequenceExecutionState.idle),
      runDashboardPrefsProvider.overrideWith(
        () => _FakeRunDashboardPrefsNotifier(RunDashboardPrefs.defaults()),
      ),
      sequencerTabProvider.overrideWith((ref) {
        ref.listenSelf((_, next) => observedTab = next);
        return 1;
      }),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('No sequence running'), findsOneWidget);
    expect(find.text('Go to Builder'), findsOneWidget);

    await tester.tap(find.text('Go to Builder'));
    await tester.pumpAndSettle();
    expect(observedTab, 0);
  });

  testWidgets('running state renders the dashboard scaffold and footer',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      sequenceExecutionStateProvider
          .overrideWith((ref) => SequenceExecutionState.running),
      runDashboardPrefsProvider.overrideWith(
        () => _FakeRunDashboardPrefsNotifier(RunDashboardPrefs.defaults()),
      ),
      sequenceProgressProvider.overrideWith(
        (ref) => _StubSequenceProgressNotifier(
          const SequenceProgress(
            state: SequenceExecutionState.running,
            totalExposures: 30,
            completedExposures: 12,
            elapsedSecs: 1800,
            estimatedRemainingSecs: 3600,
          ),
        ),
      ),
    ]));
    await tester.pumpAndSettle();

    // Section headers from the various panels — proves they all rendered.
    expect(find.text('EXPOSURE'), findsOneWidget);
    expect(find.text('PER-FILTER INTEGRATION'), findsOneWidget);
    expect(find.text('GUIDING'), findsOneWidget);
    expect(find.text('SAFETY'), findsOneWidget);
    expect(find.text('RECENT EVENTS'), findsOneWidget);
    expect(find.text('Equipment'), findsOneWidget);

    // Footer playback button — Pause when running.
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    // Sequence progress counts surface through the dashboard's exposure
    // panel ("12 / 30").
    expect(find.text('12 / 30'), findsOneWidget);
  });

  testWidgets('hiding the guiding panel via prefs removes it from the layout',
      (tester) async {
    final initialPrefs = RunDashboardPrefs.defaults()
        .withVisibility(RunDashboardPanelId.guidingGraph, false);

    await tester.pumpWidget(_wrap(overrides: [
      sequenceExecutionStateProvider
          .overrideWith((ref) => SequenceExecutionState.running),
      runDashboardPrefsProvider.overrideWith(
        () => _FakeRunDashboardPrefsNotifier(initialPrefs),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('GUIDING'), findsNothing);
    expect(find.text('SAFETY'), findsOneWidget);
  });

  test('RunDashboardPrefs JSON round-trips visibility flags', () {
    final p = RunDashboardPrefs.defaults()
        .withVisibility(RunDashboardPanelId.triggerFeed, false)
        .withVisibility(RunDashboardPanelId.guidingGraph, false);
    final decoded = RunDashboardPrefs.fromJson(p.toJson());
    expect(decoded.isVisible(RunDashboardPanelId.triggerFeed), false);
    expect(decoded.isVisible(RunDashboardPanelId.guidingGraph), false);
    expect(decoded.isVisible(RunDashboardPanelId.liveFrame), true);
  });
}

/// Test-only notifier that hands back a fixed [RunDashboardPrefs] without
/// touching the database. The production notifier reads from
/// [settingsDaoProvider], which would require spinning up the full
/// database stack — we don't need that surface here.
class _FakeRunDashboardPrefsNotifier extends RunDashboardPrefsNotifier {
  final RunDashboardPrefs initial;

  _FakeRunDashboardPrefsNotifier(this.initial);

  @override
  Future<RunDashboardPrefs> build() async => initial;

  @override
  Future<void> setVisible(RunDashboardPanelId id, bool visible) async {
    state = AsyncData(
      (state.value ?? initial).withVisibility(id, visible),
    );
  }

  @override
  Future<void> resetToDefaults() async {
    state = AsyncData(RunDashboardPrefs.defaults());
  }
}

class _StubSequenceProgressNotifier extends SequenceProgressNotifier {
  _StubSequenceProgressNotifier(SequenceProgress initial) {
    state = initial;
  }
}
