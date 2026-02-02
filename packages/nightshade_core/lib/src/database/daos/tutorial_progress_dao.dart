import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/tutorial_progress.dart';

part 'tutorial_progress_dao.g.dart';

/// Data access object for tutorial progress persistence.
/// Allows saving and restoring tutorial progress across app sessions.
@DriftAccessor(tables: [TutorialProgress])
class TutorialProgressDao extends DatabaseAccessor<NightshadeDatabase>
    with _$TutorialProgressDaoMixin {
  TutorialProgressDao(super.db);

  /// Get progress for a specific tutorial category.
  /// Returns null if no progress has been saved for this category.
  Future<TutorialProgressEntry?> getProgress(String category) {
    return (select(tutorialProgress)
          ..where((t) => t.category.equals(category)))
        .getSingleOrNull();
  }

  /// Save progress for a tutorial category.
  /// Creates a new entry if none exists, or updates the existing one.
  Future<void> saveProgress(String category, int stepIndex) async {
    final existing = await getProgress(category);

    if (existing != null) {
      // Update existing entry
      await (update(tutorialProgress)
            ..where((t) => t.category.equals(category)))
          .write(TutorialProgressCompanion(
        lastStepIndex: Value(stepIndex),
      ));
    } else {
      // Create new entry
      await into(tutorialProgress).insert(TutorialProgressCompanion.insert(
        category: category,
        lastStepIndex: Value(stepIndex),
        startedAt: DateTime.now(),
      ));
    }
  }

  /// Mark a tutorial category as completed.
  /// Sets the completed flag and records the completion timestamp.
  Future<void> markCompleted(String category) async {
    final existing = await getProgress(category);

    if (existing != null) {
      await (update(tutorialProgress)
            ..where((t) => t.category.equals(category)))
          .write(TutorialProgressCompanion(
        completed: const Value(true),
        completedAt: Value(DateTime.now()),
        dismissed: const Value(false),
      ));
    } else {
      // Create entry if it doesn't exist (edge case: completing without starting)
      await into(tutorialProgress).insert(TutorialProgressCompanion.insert(
        category: category,
        completed: const Value(true),
        startedAt: DateTime.now(),
        completedAt: Value(DateTime.now()),
      ));
    }
  }

  /// Mark a tutorial category as dismissed.
  /// The user explicitly chose to skip without completing.
  Future<void> markDismissed(String category) async {
    final existing = await getProgress(category);

    if (existing != null) {
      await (update(tutorialProgress)
            ..where((t) => t.category.equals(category)))
          .write(const TutorialProgressCompanion(
        dismissed: Value(true),
      ));
    } else {
      // Create entry if it doesn't exist
      await into(tutorialProgress).insert(TutorialProgressCompanion.insert(
        category: category,
        startedAt: DateTime.now(),
        dismissed: const Value(true),
      ));
    }
  }

  /// Reset progress for a tutorial category.
  /// Deletes the progress entry so the tutorial can be restarted fresh.
  Future<void> resetProgress(String category) async {
    await (delete(tutorialProgress)
          ..where((t) => t.category.equals(category)))
        .go();
  }

  /// Get all tutorial progress entries.
  /// Useful for displaying an overview of tutorial completion status.
  Future<List<TutorialProgressEntry>> getAllProgress() {
    return select(tutorialProgress).get();
  }

  /// Watch all tutorial progress entries for reactive updates.
  Stream<List<TutorialProgressEntry>> watchAllProgress() {
    return select(tutorialProgress).watch();
  }

  /// Check if a tutorial category has been completed.
  Future<bool> isCategoryCompleted(String category) async {
    final progress = await getProgress(category);
    return progress?.completed ?? false;
  }

  /// Check if a tutorial category has been dismissed.
  Future<bool> isCategoryDismissed(String category) async {
    final progress = await getProgress(category);
    return progress?.dismissed ?? false;
  }

  /// Get all completed tutorial categories.
  Future<List<String>> getCompletedCategories() async {
    final entries = await (select(tutorialProgress)
          ..where((t) => t.completed.equals(true)))
        .get();
    return entries.map((e) => e.category).toList();
  }

  /// Reset all tutorial progress.
  /// Useful for a "reset all tutorials" settings option.
  Future<void> resetAllProgress() async {
    await delete(tutorialProgress).go();
  }
}
