import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tutorial/tutorial_models.dart';

/// Provider for tutorial state
final tutorialProvider =
    StateNotifierProvider<TutorialNotifier, TutorialProgress>((ref) {
  return TutorialNotifier();
});

/// Registry for tutorial target keys
final tutorialKeyRegistry = Provider<TutorialKeyRegistry>((ref) {
  return TutorialKeyRegistry();
});

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

/// Manages tutorial progress and state
class TutorialNotifier extends StateNotifier<TutorialProgress> {
  TutorialNotifier() : super(const TutorialProgress());

  /// Start a tutorial category
  void startTutorial(TutorialCategory category) {
    state = state.copyWith(
      activeCategory: category,
      currentStepIndex: 0,
    );
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

      state = state.copyWith(
        completedSteps: newCompleted,
        currentStepIndex: state.currentStepIndex + 1,
      );
    } else {
      // Tutorial complete
      completeTutorial();
    }
  }

  /// Go to the previous step
  void previousStep() {
    if (state.currentStepIndex > 0) {
      state = state.copyWith(currentStepIndex: state.currentStepIndex - 1);
    }
  }

  /// Skip to a specific step
  void goToStep(int index) {
    if (state.activeCategory == null) return;

    final steps = TutorialDefinitions.getStepsForCategory(state.activeCategory!);
    if (index >= 0 && index < steps.length) {
      state = state.copyWith(currentStepIndex: index);
    }
  }

  /// Complete the current tutorial
  void completeTutorial() {
    if (state.activeCategory == null) return;

    // Mark all steps in this category as completed
    final steps = TutorialDefinitions.getStepsForCategory(state.activeCategory!);
    final newCompleted = Set<String>.from(state.completedSteps)
      ..addAll(steps.map((s) => s.id));

    final wasGettingStarted =
        state.activeCategory == TutorialCategory.gettingStarted;

    state = state.copyWith(
      completedSteps: newCompleted,
      hasSeenInitialTour:
          wasGettingStarted ? true : state.hasSeenInitialTour,
      clearActiveCategory: true,
      currentStepIndex: 0,
    );
  }

  /// Dismiss the current tutorial without completing
  void dismissTutorial() {
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
  void resetProgress() {
    state = const TutorialProgress();
  }

  /// Mark the initial tour as seen (without completing it)
  void markInitialTourSeen() {
    state = state.copyWith(hasSeenInitialTour: true);
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
