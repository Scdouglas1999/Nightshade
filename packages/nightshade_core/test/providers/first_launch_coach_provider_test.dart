import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/providers/database_provider.dart';
import 'package:nightshade_core/src/providers/first_launch_coach_provider.dart';

/// These tests exercise the first-launch coach persistence wrapper and its
/// gate provider against a REAL in-memory [NightshadeDatabase]. The point is
/// to prove the status round-trips through the `tutorial_progress` Drift
/// table — not an in-memory shortcut — so completion/dismissal genuinely
/// survives a re-read, and the auto-launch gate flips accordingly.
void main() {
  late NightshadeDatabase db;
  late ProviderContainer container;

  setUp(() {
    // forTesting + NativeDatabase.memory is the standard pattern in this
    // codebase (see services/database_migration_test.dart and
    // providers/onboarding_provider_test.dart).
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('FirstLaunchCoachDao.getStatus + gate', () {
    test('fresh database resolves to pending and the gate is true', () async {
      // First launch: no row has ever been written for the coach category.
      final status = await container.read(firstLaunchCoachDaoProvider).getStatus();
      expect(status, FirstLaunchCoachStatus.pending);

      final shouldShow =
          await container.read(shouldShowFirstLaunchCoachProvider.future);
      expect(shouldShow, isTrue);
    });

    test('after markDismissed the status is dismissed and the gate is false',
        () async {
      await container.read(firstLaunchCoachDaoProvider).markDismissed();

      final status = await container.read(firstLaunchCoachDaoProvider).getStatus();
      expect(status, FirstLaunchCoachStatus.dismissed);

      // Re-resolve the gate against the persisted state.
      container.invalidate(firstLaunchCoachStatusProvider);
      final shouldShow =
          await container.read(shouldShowFirstLaunchCoachProvider.future);
      expect(shouldShow, isFalse);
    });

    test('after markCompleted the status is completed and the gate is false',
        () async {
      await container.read(firstLaunchCoachDaoProvider).markCompleted();

      final status = await container.read(firstLaunchCoachDaoProvider).getStatus();
      expect(status, FirstLaunchCoachStatus.completed);

      container.invalidate(firstLaunchCoachStatusProvider);
      final shouldShow =
          await container.read(shouldShowFirstLaunchCoachProvider.future);
      expect(shouldShow, isFalse);
    });

    test('after reset the status is pending and the gate is true again',
        () async {
      // Drive it to a terminal state first, then reset back to pending.
      await container.read(firstLaunchCoachDaoProvider).markCompleted();
      await container.read(firstLaunchCoachDaoProvider).reset();

      final status = await container.read(firstLaunchCoachDaoProvider).getStatus();
      expect(status, FirstLaunchCoachStatus.pending);

      container.invalidate(firstLaunchCoachStatusProvider);
      final shouldShow =
          await container.read(shouldShowFirstLaunchCoachProvider.future);
      expect(shouldShow, isTrue);
    });

    test('persistence is real — status survives a fresh container/DAO over the '
        'same database', () async {
      // Mark dismissed through one container, then read it back through a
      // brand-new container/DAO sharing the SAME underlying database. If the
      // status were held in memory rather than persisted to the
      // tutorial_progress table, the second read would report pending.
      await container.read(firstLaunchCoachDaoProvider).markDismissed();

      final secondContainer = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      try {
        final status =
            await secondContainer.read(firstLaunchCoachDaoProvider).getStatus();
        expect(status, FirstLaunchCoachStatus.dismissed);

        final shouldShow = await secondContainer
            .read(shouldShowFirstLaunchCoachProvider.future);
        expect(shouldShow, isFalse);
      } finally {
        secondContainer.dispose();
      }
    });

    test('coach category is distinct from the other onboarding flows', () {
      expect(firstLaunchCoachCategory, 'firstLaunchCoach');
      expect(firstLaunchCoachCategory, isNot('firstLaunchTour'));
      expect(firstLaunchCoachCategory, isNot('equipmentOnboarding'));
      expect(firstLaunchCoachCategory, isNot('firstNight'));
    });
  });
}
