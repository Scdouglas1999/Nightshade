import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/tutorial_dao.dart';
import '../database/daos/tutorial_progress_dao.dart';
import '../models/tutorial/tutorial_models.dart';
import 'database_provider.dart';

/// Provider for tutorial progress DAO
final tutorialProgressDaoProvider = Provider<TutorialProgressDao>((ref) {
  return TutorialProgressDao(ref.watch(databaseProvider));
});

/// Provider for the first-night wizard DAO wrapper.
///
/// Built on top of [tutorialProgressDaoProvider] so it shares the same
/// underlying Drift database connection — no risk of the wizard reading
/// stale state because it has its own DAO instance.
final tutorialDaoProvider = Provider<TutorialDao>((ref) {
  return TutorialDao(ref.watch(tutorialProgressDaoProvider));
});

/// State of the first-night wizard UI.
///
/// `currentStepIndex` is 0-based into [FirstNightWizard.steps]. `isLoaded`
/// flips to true once the saved progress has been read from the database;
/// the wizard widget waits on this so a freshly-launched app doesn't flash
/// step 0 before jumping to the resumed step.
class FirstNightWizardState {
  final int currentStepIndex;
  final bool isLoaded;

  const FirstNightWizardState({
    this.currentStepIndex = 0,
    this.isLoaded = false,
  });

  FirstNightWizardState copyWith({int? currentStepIndex, bool? isLoaded}) {
    return FirstNightWizardState(
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

/// First-night wizard state notifier.
///
/// Lifecycle: created when the wizard opens, loads saved progress from the
/// DAO on construction, persists progress on every advance/back/dismiss.
/// The notifier intentionally does NOT auto-launch — the bootstrap flow
/// in `app.dart` decides when to open the wizard, this notifier just runs
/// it. Why: auto-launching from inside a provider creates surprise
/// rebuilds in tests and headless mode.
class FirstNightWizardNotifier extends StateNotifier<FirstNightWizardState> {
  final TutorialDao _dao;

  FirstNightWizardNotifier(this._dao) : super(const FirstNightWizardState()) {
    _loadResumeIndex();
  }

  Future<void> _loadResumeIndex() async {
    final stepIndex = await _dao.getLastStepIndex();
    // Clamp into the valid range — defends against a future where the
    // wizard is shortened and a user has a saved step beyond the new end.
    final clamped = stepIndex.clamp(0, _maxStepIndex);
    state = state.copyWith(currentStepIndex: clamped, isLoaded: true);
  }

  /// Total step count is owned by the model layer; we mirror it here as a
  /// constant so the clamp/advance math doesn't reach across packages
  /// every call.
  static const int _maxStepIndex = 6;

  /// True if the wizard is on the last (Launch sequence) step.
  bool get isLastStep => state.currentStepIndex >= _maxStepIndex;

  /// True if the wizard is on the first (Welcome) step. The Back button
  /// hides itself when this is true.
  bool get isFirstStep => state.currentStepIndex == 0;

  /// Advance one step. Persists progress. Calling next() on the last step
  /// completes the wizard; the caller uses [isLastStep] to swap the Next
  /// button to "Done".
  Future<void> next() async {
    if (state.currentStepIndex >= _maxStepIndex) {
      await complete();
      return;
    }
    final newIndex = state.currentStepIndex + 1;
    state = state.copyWith(currentStepIndex: newIndex);
    await _dao.saveFirstNightProgress(newIndex);
  }

  /// Go back one step. Persists. Does nothing on step 0.
  Future<void> back() async {
    if (state.currentStepIndex == 0) return;
    final newIndex = state.currentStepIndex - 1;
    state = state.copyWith(currentStepIndex: newIndex);
    await _dao.saveFirstNightProgress(newIndex);
  }

  /// Jump directly to a step (used by Settings → Help "Resume" deep-link).
  Future<void> goToStep(int index) async {
    if (index < 0 || index > _maxStepIndex) {
      // Errors are a feature: out-of-range index is a programmer bug, not
      // user input.
      throw ArgumentError(
        'FirstNightWizardNotifier.goToStep: index $index outside '
        '[0..$_maxStepIndex]',
      );
    }
    state = state.copyWith(currentStepIndex: index);
    await _dao.saveFirstNightProgress(index);
  }

  /// Mark the wizard finished. The user reached the final step and clicked
  /// Done. The wizard will not auto-open again on launch but can be
  /// replayed from Settings → Help.
  Future<void> complete() async {
    await _dao.markFirstNightCompleted();
  }

  /// "Skip forever" — the user explicitly opted out. Same launch-time
  /// effect as [complete] but distinguishes intent for analytics and the
  /// Settings → Help row label.
  Future<void> dismissForever() async {
    await _dao.dismissFirstNightForever();
  }

  /// "Show on next launch" — the wizard closes for this session but
  /// reopens next time. Implemented by deleting the saved progress row;
  /// [TutorialDao.shouldShowFirstNightOnLaunch] keys off row absence.
  Future<void> showOnNextLaunch() async {
    await _dao.resetFirstNight();
  }

  /// Restart from the welcome step. Used by Settings → Help "Restart".
  /// Doesn't dismiss or complete — just rewinds the saved index and the
  /// in-memory state.
  Future<void> restart() async {
    state = state.copyWith(currentStepIndex: 0);
    await _dao.saveFirstNightProgress(0);
  }
}

/// Provider for the first-night wizard state notifier. Standalone from
/// [tutorialProvider] (which is shared by all the screen tours) because the
/// wizard has different lifecycle semantics — it's modal, single-shot, and
/// auto-launched.
final firstNightWizardProvider = StateNotifierProvider<
    FirstNightWizardNotifier, FirstNightWizardState>((ref) {
  return FirstNightWizardNotifier(ref.watch(tutorialDaoProvider));
});

/// True if the first-night wizard should be auto-opened on this launch.
/// Resolves asynchronously because it has to read the `tutorial_progress`
/// table. Bootstrap code in `app.dart` watches this and triggers the
/// wizard once the result is `true`.
final shouldShowFirstNightProvider = FutureProvider<bool>((ref) {
  return ref.watch(tutorialDaoProvider).shouldShowFirstNightOnLaunch();
});

/// Provider for tutorial state with database persistence
final tutorialProvider =
    StateNotifierProvider<TutorialNotifier, TutorialProgress>((ref) {
  final dao = ref.watch(tutorialProgressDaoProvider);
  final notifier = TutorialNotifier(dao);
  // Load persisted progress on creation
  notifier._loadPersistedProgress();
  return notifier;
});

/// Registry for tutorial target keys
final tutorialKeyRegistry = Provider<TutorialKeyRegistry>((ref) {
  return TutorialKeyRegistry();
});

/// Provider for dismissed tour prompts with database persistence.
/// Tracks which screen IDs have had their contextual tour prompts dismissed.
final dismissedTourPromptsProvider =
    StateNotifierProvider<DismissedTourPromptsNotifier, Set<String>>((ref) {
  final dao = ref.watch(tutorialProgressDaoProvider);
  final notifier = DismissedTourPromptsNotifier(dao);
  notifier._loadDismissedPrompts();
  return notifier;
});

/// Manages dismissed tour prompts with database persistence
class DismissedTourPromptsNotifier extends StateNotifier<Set<String>> {
  final TutorialProgressDao _dao;

  DismissedTourPromptsNotifier(this._dao) : super({});

  /// Load dismissed prompts from database
  Future<void> _loadDismissedPrompts() async {
    final dismissed = await _dao.getDismissedPromptScreenIds();
    state = dismissed;
  }

  /// Dismiss a tour prompt for a screen (persists to database)
  Future<void> dismissPrompt(String screenId) async {
    await _dao.dismissPromptForScreen(screenId);
    state = {...state, screenId};
  }

  /// Check if a screen's prompt has been dismissed
  bool isPromptDismissed(String screenId) {
    return state.contains(screenId);
  }

  /// Reset all dismissed prompts (for "reset tutorials" feature)
  Future<void> resetAllDismissed() async {
    // This will be handled by resetAllProgress in TutorialProgressDao
    state = {};
  }
}

/// Manages global keys for tutorial targets
class TutorialKeyRegistry {
  final Map<String, GlobalKey> _keys = {};

  /// Register a key for a target
  GlobalKey registerKey(String id) {
    return _keys.putIfAbsent(id, () => GlobalKey());
  }

  /// Get a key by id
  GlobalKey? getKey(String id) => _keys[id];

  /// Get the render box for a target
  RenderBox? getRenderBox(String id) {
    final key = _keys[id];
    if (key?.currentContext == null) return null;
    return key!.currentContext!.findRenderObject() as RenderBox?;
  }

  /// Get the global position of a target
  Rect? getTargetRect(String id) {
    final renderBox = getRenderBox(id);
    if (renderBox == null) return null;
    final position = renderBox.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      position.dx,
      position.dy,
      renderBox.size.width,
      renderBox.size.height,
    );
  }
}

/// Manages tutorial progress and state with database persistence
class TutorialNotifier extends StateNotifier<TutorialProgress> {
  final TutorialProgressDao _dao;

  TutorialNotifier(this._dao) : super(const TutorialProgress());

  /// Load persisted progress from database
  Future<void> _loadPersistedProgress() async {
    final allProgress = await _dao.getAllProgress();

    // Build completed steps set from all completed categories
    final completedSteps = <String>{};
    bool hasSeenInitialTour = false;

    for (final entry in allProgress) {
      if (entry.completed) {
        // Add all steps from completed categories
        final category = _categoryFromName(entry.category);
        if (category != null) {
          final steps = TutorialDefinitions.getStepsForCategory(category);
          completedSteps.addAll(steps.map((s) => s.id));

          // Check if firstLight (initial tour) was completed
          if (category == TutorialCategory.firstLight) {
            hasSeenInitialTour = true;
          }
        }
      }
    }

    state = state.copyWith(
      completedSteps: completedSteps,
      hasSeenInitialTour: hasSeenInitialTour,
    );
  }

  /// Convert category name string to enum
  TutorialCategory? _categoryFromName(String name) {
    for (final cat in TutorialCategory.values) {
      if (cat.name == name) return cat;
    }
    return null;
  }

  /// Start a tutorial category
  void startTutorial(TutorialCategory category) {
    state = state.copyWith(
      activeCategory: category,
      currentStepIndex: 0,
    );
    // Save initial progress to DB
    _dao.saveProgress(category.name, 0);
  }

  /// Resume a tutorial from where the user left off
  Future<void> resumeTutorial(TutorialCategory category) async {
    final progress = await _dao.getProgress(category.name);
    final stepIndex = progress?.lastStepIndex ?? 0;

    // Make sure the step index is valid
    final steps = TutorialDefinitions.getStepsForCategory(category);
    final validIndex = stepIndex.clamp(0, steps.length - 1);

    state = state.copyWith(
      activeCategory: category,
      currentStepIndex: validIndex,
    );
  }

  /// Restart a tutorial from the beginning
  Future<void> restartTutorial(TutorialCategory category) async {
    await _dao.resetProgress(category.name);

    // Remove completed steps for this category from the set
    final steps = TutorialDefinitions.getStepsForCategory(category);
    final stepIds = steps.map((s) => s.id).toSet();
    final newCompleted = Set<String>.from(state.completedSteps)
      ..removeAll(stepIds);

    state = state.copyWith(
      completedSteps: newCompleted,
      activeCategory: category,
      currentStepIndex: 0,
    );

    // Save fresh progress
    await _dao.saveProgress(category.name, 0);
  }

  /// Go to the next step in the current tutorial
  void nextStep() {
    if (state.activeCategory == null) return;

    final steps = TutorialDefinitions.getStepsForCategory(state.activeCategory!);
    if (state.currentStepIndex < steps.length - 1) {
      // Mark current step as completed
      final currentStep = steps[state.currentStepIndex];
      final newCompleted = Set<String>.from(state.completedSteps)
        ..add(currentStep.id);

      final newIndex = state.currentStepIndex + 1;
      state = state.copyWith(
        completedSteps: newCompleted,
        currentStepIndex: newIndex,
      );

      // Save progress to DB
      _dao.saveProgress(state.activeCategory!.name, newIndex);
    } else {
      // Tutorial complete
      completeTutorial();
    }
  }

  /// Go to the previous step
  void previousStep() {
    if (state.currentStepIndex > 0) {
      final newIndex = state.currentStepIndex - 1;
      state = state.copyWith(currentStepIndex: newIndex);

      // Save progress to DB
      if (state.activeCategory != null) {
        _dao.saveProgress(state.activeCategory!.name, newIndex);
      }
    }
  }

  /// Skip to a specific step
  void goToStep(int index) {
    if (state.activeCategory == null) return;

    final steps = TutorialDefinitions.getStepsForCategory(state.activeCategory!);
    if (index >= 0 && index < steps.length) {
      state = state.copyWith(currentStepIndex: index);

      // Save progress to DB
      _dao.saveProgress(state.activeCategory!.name, index);
    }
  }

  /// Complete the current tutorial
  void completeTutorial() {
    if (state.activeCategory == null) return;

    // Mark all steps in this category as completed
    final steps = TutorialDefinitions.getStepsForCategory(state.activeCategory!);
    final newCompleted = Set<String>.from(state.completedSteps)
      ..addAll(steps.map((s) => s.id));

    final wasFirstLight =
        state.activeCategory == TutorialCategory.firstLight;

    // Mark completed in DB
    _dao.markCompleted(state.activeCategory!.name);

    state = state.copyWith(
      completedSteps: newCompleted,
      hasSeenInitialTour:
          wasFirstLight ? true : state.hasSeenInitialTour,
      clearActiveCategory: true,
      currentStepIndex: 0,
    );
  }

  /// Dismiss the current tutorial without completing
  void dismissTutorial() {
    if (state.activeCategory != null) {
      // Mark dismissed in DB
      _dao.markDismissed(state.activeCategory!.name);
    }

    state = state.copyWith(
      clearActiveCategory: true,
      currentStepIndex: 0,
    );
  }

  /// Toggle tutorials globally
  void setTutorialsEnabled(bool enabled) {
    state = state.copyWith(tutorialsEnabled: enabled);
  }

  /// Reset all tutorial progress
  Future<void> resetProgress() async {
    await _dao.resetAllProgress();
    state = const TutorialProgress();
  }

  /// Mark the initial tour as seen (without completing it)
  void markInitialTourSeen() {
    state = state.copyWith(hasSeenInitialTour: true);
  }

  /// Check if a category has been completed
  Future<bool> isCategoryCompleted(TutorialCategory category) async {
    return _dao.isCategoryCompleted(category.name);
  }

  /// Check if a category was dismissed
  Future<bool> isCategoryDismissed(TutorialCategory category) async {
    return _dao.isCategoryDismissed(category.name);
  }

  /// Get saved progress for a category (step index)
  Future<int?> getSavedStepIndex(TutorialCategory category) async {
    final progress = await _dao.getProgress(category.name);
    return progress?.lastStepIndex;
  }

  /// Get the number of completed steps for a category (synchronous from state)
  int getCompletedStepsCount(TutorialCategory category) {
    final steps = TutorialDefinitions.getStepsForCategory(category);
    return steps.where((s) => state.completedSteps.contains(s.id)).length;
  }

  /// Get the total number of steps for a category
  int getTotalStepsCount(TutorialCategory category) {
    return TutorialDefinitions.getStepsForCategory(category).length;
  }

  /// Check if a category is fully completed (synchronous from state)
  bool isCategoryCompletedSync(TutorialCategory category) {
    final steps = TutorialDefinitions.getStepsForCategory(category);
    return steps.every((s) => state.completedSteps.contains(s.id));
  }

  /// Check if a category has any progress (synchronous from state)
  bool hasCategoryProgress(TutorialCategory category) {
    final steps = TutorialDefinitions.getStepsForCategory(category);
    return steps.any((s) => state.completedSteps.contains(s.id));
  }

  /// Get the current step
  TutorialStep? get currentStep {
    if (state.activeCategory == null) return null;
    final steps = TutorialDefinitions.getStepsForCategory(state.activeCategory!);
    if (state.currentStepIndex >= steps.length) return null;
    return steps[state.currentStepIndex];
  }

  /// Get total steps in current tutorial
  int get totalSteps {
    if (state.activeCategory == null) return 0;
    return TutorialDefinitions.getStepsForCategory(state.activeCategory!).length;
  }

  /// Check if this is the last step
  bool get isLastStep {
    return state.currentStepIndex >= totalSteps - 1;
  }

  /// Check if this is the first step
  bool get isFirstStep {
    return state.currentStepIndex == 0;
  }
}
