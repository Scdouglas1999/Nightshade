import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/onboarding/coach/first_launch_coach_progress.dart';
import 'package:nightshade_app/screens/onboarding/coach/first_launch_coach_step.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show
        ReadinessItem,
        ReadinessItemId,
        ReadinessLevel,
        ReadinessReport,
        readinessReportProvider;

/// Builds a [ReadinessItem] for [id] at [level] with throwaway copy. The coach
/// progress derivation only reads `id` and `level`, so the textual fields are
/// irrelevant to these tests.
ReadinessItem _item(ReadinessItemId id, ReadinessLevel level) {
  // `ready` items carry no fixRoute/fixLabel (matching the model invariant);
  // non-ready items carry both so the assert in ReadinessItem is satisfied.
  if (level == ReadinessLevel.ready) {
    return ReadinessItem(
      id: id,
      title: id.name,
      detail: 'ready',
      level: level,
    );
  }
  return ReadinessItem(
    id: id,
    title: id.name,
    detail: 'not ready',
    level: level,
    fixRoute: '/settings',
    fixLabel: 'Fix',
  );
}

/// A report where every readiness item is at [ReadinessLevel.ready].
ReadinessReport _allReadyReport() => ReadinessReport(
      items: [
        for (final id in ReadinessItemId.values)
          _item(id, ReadinessLevel.ready),
      ],
    );

/// Builds a [ProviderContainer] with [readinessReportProvider] overridden to a
/// fixed, hand-built [report], so the coach progress is derived from a known
/// readiness state with no live device/settings dependencies.
ProviderContainer _containerWith(ReadinessReport report) {
  final container = ProviderContainer(
    overrides: [
      readinessReportProvider.overrideWithValue(report),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('CoachStepProgress', () {
    test('isComplete only at ready level', () {
      const step = FirstLaunchCoachStep(
        id: ReadinessItemId.location,
        title: 't',
        whyItMatters: 'w',
        actionLabel: 'a',
        deepLinkRoute: '/settings?section=location',
      );
      expect(
        const CoachStepProgress(step: step, level: ReadinessLevel.ready)
            .isComplete,
        isTrue,
      );
      expect(
        const CoachStepProgress(step: step, level: ReadinessLevel.caution)
            .isComplete,
        isFalse,
        reason: 'caution is degraded-but-usable, not complete',
      );
      expect(
        const CoachStepProgress(step: step, level: ReadinessLevel.blocked)
            .isComplete,
        isFalse,
      );
    });
  });

  group('firstLaunchCoachProgressProvider', () {
    test('all-ready report => all six steps complete, nothing outstanding', () {
      final container = _containerWith(_allReadyReport());

      final progress = container.read(firstLaunchCoachProgressProvider);

      expect(progress.totalCount, kFirstLaunchCoachSteps.length);
      expect(progress.totalCount, 6,
          reason: 'coach tracks all six readiness ids');
      expect(progress.completeCount, 6);
      expect(progress.allComplete, isTrue);
      expect(progress.nextOutstanding, isNull);
      // Every step is ready, so none is complete-by-accident in wrong order.
      for (final s in progress.steps) {
        expect(s.isComplete, isTrue);
      }
    });

    test('preserves kFirstLaunchCoachSteps display order', () {
      final container = _containerWith(_allReadyReport());

      final progress = container.read(firstLaunchCoachProgressProvider);

      expect(
        progress.steps.map((s) => s.step.id).toList(),
        kFirstLaunchCoachSteps.map((s) => s.id).toList(),
      );
    });

    test('location blocked => that step incomplete, nextOutstanding=location',
        () {
      final report = ReadinessReport(
        items: [
          for (final id in ReadinessItemId.values)
            _item(
              id,
              id == ReadinessItemId.location
                  ? ReadinessLevel.blocked
                  : ReadinessLevel.ready,
            ),
        ],
      );
      final container = _containerWith(report);

      final progress = container.read(firstLaunchCoachProgressProvider);

      final locationStep = progress.steps
          .firstWhere((s) => s.step.id == ReadinessItemId.location);
      expect(locationStep.isComplete, isFalse);
      expect(progress.completeCount, 5);
      expect(progress.allComplete, isFalse);
      expect(progress.nextOutstanding, isNotNull);
      expect(progress.nextOutstanding!.step.id, ReadinessItemId.location);
    });

    test('caution level does not complete the step (derives strictly)', () {
      final report = ReadinessReport(
        items: [
          for (final id in ReadinessItemId.values)
            _item(
              id,
              id == ReadinessItemId.plateSolver
                  ? ReadinessLevel.caution
                  : ReadinessLevel.ready,
            ),
        ],
      );
      final container = _containerWith(report);

      final progress = container.read(firstLaunchCoachProgressProvider);

      final solverStep = progress.steps
          .firstWhere((s) => s.step.id == ReadinessItemId.plateSolver);
      expect(solverStep.level, ReadinessLevel.caution);
      expect(solverStep.isComplete, isFalse);
      expect(progress.completeCount, 5);
      expect(progress.nextOutstanding!.step.id, ReadinessItemId.plateSolver);
    });

    test('empty report => every step fail-closes to blocked/incomplete', () {
      final container = _containerWith(const ReadinessReport(items: []));

      final progress = container.read(firstLaunchCoachProgressProvider);

      expect(progress.totalCount, kFirstLaunchCoachSteps.length);
      expect(progress.completeCount, 0);
      expect(progress.allComplete, isFalse);
      for (final s in progress.steps) {
        expect(s.level, ReadinessLevel.blocked,
            reason: 'missing readiness item must fail closed to blocked');
        expect(s.isComplete, isFalse);
      }
      // nextOutstanding is the first step in display order.
      expect(progress.nextOutstanding!.step.id, kFirstLaunchCoachSteps.first.id);
    });

    test(
        'partial report => present-but-missing ids fail closed, first missing '
        'in display order is nextOutstanding', () {
      // Only location and outputPath are present (both ready). Critical devices
      // (the FIRST step) is missing, so it must fail-closed to blocked and be
      // the nextOutstanding step despite later steps also being missing.
      final report = ReadinessReport(
        items: [
          _item(ReadinessItemId.location, ReadinessLevel.ready),
          _item(ReadinessItemId.outputPath, ReadinessLevel.ready),
        ],
      );
      final container = _containerWith(report);

      final progress = container.read(firstLaunchCoachProgressProvider);

      final criticalStep = progress.steps
          .firstWhere((s) => s.step.id == ReadinessItemId.criticalDevices);
      expect(criticalStep.level, ReadinessLevel.blocked);
      expect(criticalStep.isComplete, isFalse);

      // Two present-and-ready items => two complete steps.
      expect(progress.completeCount, 2);
      expect(progress.allComplete, isFalse);
      expect(
        progress.nextOutstanding!.step.id,
        ReadinessItemId.criticalDevices,
      );
    });

    test('recomputes when the overridden readiness report changes', () {
      // Verifies completion DERIVES from readiness: flipping the report from
      // a blocked-location state to all-ready flips the coach to allComplete.
      final blocked = ReadinessReport(
        items: [
          for (final id in ReadinessItemId.values)
            _item(
              id,
              id == ReadinessItemId.location
                  ? ReadinessLevel.blocked
                  : ReadinessLevel.ready,
            ),
        ],
      );

      final container = ProviderContainer(
        overrides: [readinessReportProvider.overrideWithValue(blocked)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(firstLaunchCoachProgressProvider).allComplete,
        isFalse,
      );

      container.updateOverrides([
        readinessReportProvider.overrideWithValue(_allReadyReport()),
      ]);

      expect(
        container.read(firstLaunchCoachProgressProvider).allComplete,
        isTrue,
      );
    });
  });

  group('CoachProgress equality', () {
    test('equal when steps are equal', () {
      final a = _containerWith(_allReadyReport())
          .read(firstLaunchCoachProgressProvider);
      final b = _containerWith(_allReadyReport())
          .read(firstLaunchCoachProgressProvider);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('allComplete is false for an empty step list', () {
      const empty = CoachProgress(steps: []);
      expect(empty.allComplete, isFalse);
      expect(empty.nextOutstanding, isNull);
      expect(empty.completeCount, 0);
      expect(empty.totalCount, 0);
    });
  });
}
