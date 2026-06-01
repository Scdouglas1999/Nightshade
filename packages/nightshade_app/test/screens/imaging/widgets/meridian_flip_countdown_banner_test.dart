import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/screens/imaging/widgets/meridian_flip_countdown_banner.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Builds a [MeridianCountdownState] with sensible defaults so each test only
/// has to vary the field under examination.
MeridianCountdownState _state({
  required bool isArmed,
  Duration? timeToFlip,
  bool isSequencerOwned = false,
  String? disabledReason,
  MeridianTriggerMethod method = MeridianTriggerMethod.minutesPastMeridian,
  double hourAngleHours = 0.0,
  String? sideOfPier,
}) {
  return MeridianCountdownState(
    isArmed: isArmed,
    timeToFlip: timeToFlip,
    isAutomaticWatchdog: true,
    isSequencerOwned: isSequencerOwned,
    disabledReason: disabledReason,
    method: method,
    hourAngleHours: hourAngleHours,
    sideOfPier: sideOfPier,
  );
}

Future<void> _pump(
  WidgetTester tester,
  MeridianCountdownState state, {
  int? dismissedSeverityIndex,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 600);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The projection is now a pure synchronous Provider; override it with a
        // fixed state. (The banner owns its own 15s ticker, cancelled on dispose,
        // so no timer leaks past this test's teardown.)
        meridianCountdownProvider.overrideWith((ref) => state),
        if (dismissedSeverityIndex != null)
          meridianBannerDismissedSeverityProvider
              .overrideWith((ref) => dismissedSeverityIndex),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(
          body: Center(child: MeridianFlipCountdownBanner()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  group('formatTimeToFlip', () {
    test('rounds up to whole minutes so it never under-reports', () {
      // 2m05s of real time must read as 3m, not 2m.
      expect(formatTimeToFlip(const Duration(minutes: 2, seconds: 5)), '3m');
      expect(formatTimeToFlip(const Duration(minutes: 2)), '2m');
    });

    test('formats hours and minutes', () {
      expect(
        formatTimeToFlip(const Duration(hours: 1, minutes: 30)),
        '1h 30m',
      );
    });

    test('drops the minute component on a whole hour', () {
      expect(formatTimeToFlip(const Duration(hours: 2)), '2h');
    });

    test('round-up means any positive duration reads at least 1m, never 0m', () {
      expect(formatTimeToFlip(const Duration(seconds: 20)), '1m');
      expect(formatTimeToFlip(const Duration(seconds: 1)), '1m');
    });

    test('zero or negative reads as "now"', () {
      expect(formatTimeToFlip(Duration.zero), 'now');
      expect(formatTimeToFlip(const Duration(seconds: -30)), 'now');
    });
  });

  group('MeridianFlipCountdownBanner render rules', () {
    testWidgets('not armed renders nothing (non-intrusive)', (tester) async {
      await _pump(
        tester,
        _state(
          isArmed: false,
          disabledReason: 'Mount not connected',
        ),
      );

      expect(find.byType(MeridianFlipCountdownBanner), findsOneWidget);
      // Collapses to zero size; surfaces no disabled-reason chatter.
      expect(tester.getSize(find.byType(MeridianFlipCountdownBanner)), Size.zero);
      expect(find.textContaining('Meridian flip'), findsNothing);
    });

    testWidgets('armed numeric countdown shows tabular time + automatic copy',
        (tester) async {
      await _pump(
        tester,
        _state(
          isArmed: true,
          timeToFlip: const Duration(minutes: 42),
        ),
      );

      expect(find.textContaining('Meridian flip in'), findsOneWidget);
      expect(find.text('42m'), findsOneWidget);
      expect(
        find.text(
          'Automatic — the meridian-flip watchdog will run this for you. '
          'No action needed.',
        ),
        findsOneWidget,
      );
      // The flip icon is the design-reference flip glyph.
      expect(find.byIcon(LucideIcons.flipHorizontal2), findsOneWidget);
    });

    testWidgets('countdown under 10 minutes escalates to the warning tone',
        (tester) async {
      await _pump(
        tester,
        _state(
          isArmed: true,
          timeToFlip: const Duration(minutes: 6),
        ),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(MeridianFlipCountdownBanner),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;
      const colors = NightshadeColors.dark;
      // Border carries the warning accent (alpha 0.35), not info.
      expect(decoration.border!.top.color, colors.warning.withValues(alpha: 0.35));
    });

    testWidgets('calm tone above the warning threshold', (tester) async {
      await _pump(
        tester,
        _state(
          isArmed: true,
          timeToFlip: const Duration(minutes: 30),
        ),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(MeridianFlipCountdownBanner),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;
      const colors = NightshadeColors.dark;
      expect(decoration.border!.top.color, colors.info.withValues(alpha: 0.35));
    });

    testWidgets('sequencer-owned countdown uses the sequence copy',
        (tester) async {
      await _pump(
        tester,
        _state(
          isArmed: true,
          timeToFlip: const Duration(minutes: 20),
          isSequencerOwned: true,
        ),
      );

      expect(
        find.text('Handled automatically by the running sequence.'),
        findsOneWidget,
      );
      expect(find.textContaining('watchdog will run this'), findsNothing);
    });

    testWidgets('tracking-limit method (null countdown) shows monitored banner '
        'with no fake timer', (tester) async {
      await _pump(
        tester,
        _state(
          isArmed: true,
          timeToFlip: null,
          isSequencerOwned: true,
          method: MeridianTriggerMethod.minutesBeforeLimit,
          disabledReason: 'Monitored by sequencer (tracking-limit method)',
        ),
      );

      expect(find.text('Meridian flip armed'), findsOneWidget);
      expect(
        find.text('Monitored by the sequencer — no action needed.'),
        findsOneWidget,
      );
      // No fabricated countdown: the "Meridian flip in <time>" title must not
      // appear for a method that has no Dart-computable countdown.
      expect(find.textContaining('Meridian flip in'), findsNothing);
    });

    testWidgets('flip imminent (zero) shows warning imminent banner',
        (tester) async {
      await _pump(
        tester,
        _state(
          isArmed: true,
          timeToFlip: Duration.zero,
        ),
      );

      expect(find.text('Meridian flip imminent'), findsOneWidget);
      expect(find.textContaining('No action needed'), findsOneWidget);

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(MeridianFlipCountdownBanner),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;
      const colors = NightshadeColors.dark;
      expect(decoration.border!.top.color, colors.warning.withValues(alpha: 0.35));
    });

    testWidgets('pier-side renders as a trailing chip when present',
        (tester) async {
      await _pump(
        tester,
        _state(
          isArmed: true,
          timeToFlip: const Duration(minutes: 25),
          sideOfPier: 'west',
        ),
      );

      expect(find.text('Pier West'), findsOneWidget);
    });

    testWidgets('no pier chip when the mount does not report a side',
        (tester) async {
      await _pump(
        tester,
        _state(
          isArmed: true,
          timeToFlip: const Duration(minutes: 25),
        ),
      );

      expect(find.textContaining('Pier'), findsNothing);
    });

    testWidgets('is dismissable but offers no manual flip-action button',
        (tester) async {
      await _pump(
        tester,
        _state(
          isArmed: true,
          timeToFlip: const Duration(minutes: 25),
        ),
      );

      // It must never present an action that triggers/cancels the flip (that
      // would contradict the "automatic watchdog" promise)...
      expect(find.byType(NightshadeButton), findsNothing);
      // ...but it IS dismissable: a quiet close affordance silences the status.
      expect(find.byTooltip('Dismiss'), findsOneWidget);
      expect(find.byIcon(LucideIcons.x), findsOneWidget);
    });

    testWidgets('tapping dismiss hides the banner', (tester) async {
      await _pump(
        tester,
        _state(isArmed: true, timeToFlip: const Duration(minutes: 25)),
      );
      expect(find.textContaining('Meridian flip in'), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();

      expect(find.textContaining('Meridian flip in'), findsNothing);
      expect(
        tester.getSize(find.byType(MeridianFlipCountdownBanner)),
        Size.zero,
      );
    });

    testWidgets('stays hidden at or below the dismissed severity',
        (tester) async {
      // Dismissed at the calm info tone; a still-calm countdown stays silenced.
      await _pump(
        tester,
        _state(isArmed: true, timeToFlip: const Duration(minutes: 30)),
        dismissedSeverityIndex: NightshadeAlertSeverity.info.index,
      );

      expect(
        tester.getSize(find.byType(MeridianFlipCountdownBanner)),
        Size.zero,
      );
    });

    testWidgets('re-surfaces when the flip escalates past the dismissed tone',
        (tester) async {
      // Dismissed at info, but the flip is now within the warning threshold —
      // the more-urgent banner must come back despite the earlier dismissal.
      await _pump(
        tester,
        _state(isArmed: true, timeToFlip: const Duration(minutes: 6)),
        dismissedSeverityIndex: NightshadeAlertSeverity.info.index,
      );

      expect(find.textContaining('Meridian flip in'), findsOneWidget);
    });
  });
}
