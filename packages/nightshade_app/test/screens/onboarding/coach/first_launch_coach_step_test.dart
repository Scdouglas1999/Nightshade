import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/onboarding/coach/first_launch_coach_step.dart';
import 'package:nightshade_app/screens/settings/settings_screen.dart'
    show kSettingsSectionIndex;
import 'package:nightshade_core/nightshade_core.dart' show ReadinessItemId;

void main() {
  group('kFirstLaunchCoachSteps', () {
    test('covers every ReadinessItemId exactly once', () {
      final ids = kFirstLaunchCoachSteps.map((s) => s.id).toList();

      // Exactly one step per id (no duplicates, no extras).
      expect(ids.length, ReadinessItemId.values.length);
      expect(ids.toSet(), ReadinessItemId.values.toSet());

      for (final id in ReadinessItemId.values) {
        expect(
          ids.where((stepId) => stepId == id).length,
          1,
          reason: 'Expected exactly one coach step for $id',
        );
      }
    });

    test('is in the required order', () {
      expect(
        kFirstLaunchCoachSteps.map((s) => s.id).toList(),
        const <ReadinessItemId>[
          ReadinessItemId.criticalDevices,
          ReadinessItemId.location,
          ReadinessItemId.outputPath,
          ReadinessItemId.plateSolver,
          ReadinessItemId.darkLibrary,
          ReadinessItemId.focusState,
        ],
      );
    });

    test('maps each id to the exact deep-link route', () {
      expect(stepFor(ReadinessItemId.criticalDevices).deepLinkRoute, '/equipment');
      expect(stepFor(ReadinessItemId.location).deepLinkRoute,
          '/settings?section=location');
      expect(stepFor(ReadinessItemId.outputPath).deepLinkRoute,
          '/settings?section=file-paths');
      expect(stepFor(ReadinessItemId.plateSolver).deepLinkRoute,
          '/settings?section=plate-solving');
      expect(stepFor(ReadinessItemId.darkLibrary).deepLinkRoute,
          '/settings?section=dark-library');
      expect(stepFor(ReadinessItemId.focusState).deepLinkRoute, '/equipment');
    });

    test('has non-empty title, whyItMatters and actionLabel for every step', () {
      for (final step in kFirstLaunchCoachSteps) {
        expect(step.title.trim(), isNotEmpty, reason: '${step.id} title');
        expect(step.whyItMatters.trim(), isNotEmpty,
            reason: '${step.id} whyItMatters');
        expect(step.actionLabel.trim(), isNotEmpty,
            reason: '${step.id} actionLabel');
      }
    });

    test('every section= query key resolves to a real settings section', () {
      for (final step in kFirstLaunchCoachSteps) {
        final uri = Uri.parse(step.deepLinkRoute);
        final section = uri.queryParameters['section'];
        if (section == null) {
          // Routes without a section= (e.g. /equipment) are exempt.
          continue;
        }
        expect(
          kSettingsSectionIndex.containsKey(section),
          isTrue,
          reason:
              'Deep-link section "$section" for ${step.id} is not in kSettingsSectionIndex',
        );
      }
    });
  });

  group('stepFor', () {
    test('returns the matching step for every id', () {
      for (final id in ReadinessItemId.values) {
        expect(stepFor(id).id, id);
      }
    });

    test('never throws for any real ReadinessItemId (list is exhaustive)', () {
      // The StateError guard in stepFor only fires when kFirstLaunchCoachSteps
      // is missing an id. That must be unreachable via the public API: every
      // id in the enum resolves. If someone adds a new ReadinessItemId without
      // a coach step, this test fails with the surfaced StateError rather than
      // letting the gap ship silently.
      for (final id in ReadinessItemId.values) {
        expect(() => stepFor(id), returnsNormally, reason: '$id');
      }
    });
  });
}
