import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'tutorial_keys/tutorial_keys.dart';

part 'tutorial_overlay/content.dart';
part 'tutorial_overlay/spotlight.dart';
part 'tutorial_overlay/tooltip.dart';

/// Spotlight shape for tutorial highlighting
/// This is defined locally in case the model hasn't been updated yet.
/// Once tutorial_models.dart has SpotlightShape, this can be removed
/// and the import used instead.
enum SpotlightShape {
  /// Circular spotlight - ideal for icons and circular buttons
  circle,

  /// Rounded rectangle - default shape for most UI elements
  roundedRect,

  /// Pill/capsule shape - horizontal oval for text buttons and labels
  pill,
}

/// Global keys for tutorial targets
class TutorialKeys {
  // Navigation keys (used by multiple tutorials)
  static final sideNavigation = GlobalKey(debugLabel: 'side_navigation');
  static final navDashboard = GlobalKey(debugLabel: 'nav_dashboard');
  static final navEquipment = GlobalKey(debugLabel: 'nav_equipment');
  static final navImaging = GlobalKey(debugLabel: 'nav_imaging');
  static final navGuiding = GlobalKey(debugLabel: 'nav_guiding');
  static final navSequencer = GlobalKey(debugLabel: 'nav_sequencer');
  static final navPlanetarium = GlobalKey(debugLabel: 'nav_planetarium');
  static final navFraming = GlobalKey(debugLabel: 'nav_framing');
  static final navFlatWizard = GlobalKey(debugLabel: 'nav_flat_wizard');
  static final navAnalytics = GlobalKey(debugLabel: 'nav_analytics');
  static final navWeather = GlobalKey(debugLabel: 'nav_weather');
  static final navPlanner = GlobalKey(debugLabel: 'nav_planner');
  static final navScheduler = GlobalKey(debugLabel: 'nav_scheduler');
  static final navSettings = GlobalKey(debugLabel: 'nav_settings');

  /// Get a GlobalKey by its string ID.
  /// Delegates to screen-specific key classes based on the key prefix.
  static GlobalKey? getKey(String? keyId) {
    if (keyId == null) return null;

    // Navigation keys (shared across tutorials)
    switch (keyId) {
      case 'side_navigation':
        return sideNavigation;
      case 'nav_dashboard':
        return navDashboard;
      case 'nav_equipment':
        return navEquipment;
      case 'nav_imaging':
        return navImaging;
      case 'nav_guiding':
        return navGuiding;
      case 'nav_sequencer':
        return navSequencer;
      case 'nav_planetarium':
        return navPlanetarium;
      case 'nav_framing':
        return navFraming;
      case 'nav_flat_wizard':
        return navFlatWizard;
      case 'nav_analytics':
        return navAnalytics;
      case 'nav_weather':
        return navWeather;
      case 'nav_settings':
        return navSettings;
    }

    // Delegate to screen-specific key classes based on prefix
    if (keyId.startsWith('dashboard_')) {
      return DashboardTutorialKeys.getKey(keyId);
    }
    if (keyId.startsWith('equipment_')) {
      return EquipmentTutorialKeys.getKey(keyId);
    }
    if (keyId.startsWith('imaging_')) {
      return ImagingTutorialKeys.getKey(keyId);
    }
    if (keyId.startsWith('guiding_')) {
      return GuidingTutorialKeys.getKey(keyId);
    }
    if (keyId.startsWith('sequencer_')) {
      return SequencerTutorialKeys.getKey(keyId);
    }
    if (keyId.startsWith('planetarium_')) {
      return PlanetariumTutorialKeys.getKey(keyId);
    }
    if (keyId.startsWith('framing_')) {
      return FramingTutorialKeys.getKey(keyId);
    }
    if (keyId.startsWith('analytics_')) {
      return AnalyticsTutorialKeys.getKey(keyId);
    }
    if (keyId.startsWith('flat_')) {
      return FlatWizardTutorialKeys.getKey(keyId);
    }
    if (keyId.startsWith('weather_')) {
      return WeatherTutorialKeys.getKey(keyId);
    }
    if (keyId.startsWith('settings_')) {
      return SettingsTutorialKeys.getKey(keyId);
    }
    if (keyId.startsWith('polar_')) {
      return PolarAlignmentTutorialKeys.getKey(keyId);
    }

    return null;
  }
}

/// Tutorial overlay that displays coach marks with spotlight effect
class TutorialOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const TutorialOverlay({super.key, required this.child});

  @override
  ConsumerState<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends ConsumerState<TutorialOverlay>
    with TickerProviderStateMixin {
  late AnimationController _animController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _ringAnimation;
  late Animation<double> _ringOpacityAnimation;
  _TutorialOverlayAction? _pendingAction;

  void _runAction(
    _TutorialOverlayAction action,
    Future<void> Function() operation,
  ) {
    if (_pendingAction != null) return;
    unawaited(() async {
      setState(() => _pendingAction = action);
      try {
        await operation();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text(
                'Could not save tutorial progress. Please try again.',
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _pendingAction = null);
      }
    }());
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    // Pulse controller for the expanding ring effect (2 second cycle).
    //
    // NOT started here. This overlay wraps the whole app and stays mounted on
    // every screen, but it only draws its spotlight ring while a tutorial is
    // actually running. Repeating unconditionally kept a Ticker alive forever,
    // which keeps Flutter's vsync loop alive: the app produced ~30 frames per
    // second, running the full build/layout/paint/semantics pipeline, on every
    // screen, permanently — for a ring that is not on screen. It is started and
    // stopped in build, alongside the fade controller.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Ring expands from 0 to 1 (spotlight edge to outer ring)
    _ringAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeOut,
      ),
    );

    // Ring fades out as it expands
    _ringOpacityAnimation = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeIn,
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Navigate to the appropriate route based on the tutorial step's target key
  void _navigateForStep(BuildContext context, String? targetKey) {
    if (targetKey == null || !context.mounted) return;

    final routes = <String, String>{
      'nav_dashboard': '/dashboard',
      'nav_equipment': '/equipment',
      'nav_imaging': '/imaging',
      'nav_sequencer': '/sequencer',
      'nav_planetarium': '/planetarium',
      'nav_framing': '/framing',
      'nav_analytics': '/analytics',
      'nav_flat_wizard': '/flat-wizard',
    };

    final route = routes[targetKey];
    if (route != null) {
      // Use a short delay to allow the UI to settle
      Future.microtask(() {
        if (context.mounted) {
          context.go(route);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tutorialState = ref.watch(tutorialProvider);
    final notifier = ref.read(tutorialProvider.notifier);

    // Listen for tutorial state changes to navigate to appropriate tabs
    ref.listen<TutorialProgress>(tutorialProvider, (previous, current) {
      if (current.activeCategory != null && current.currentStepIndex >= 0) {
        final steps =
            TutorialDefinitions.getStepsForCategory(current.activeCategory!);
        if (current.currentStepIndex < steps.length) {
          final step = steps[current.currentStepIndex];
          _navigateForStep(context, step.targetKey);
        }
      }
    });

    // Note: this overlay only renders spotlight coach marks for an actively
    // running tutorial; it does not gate a separate welcome takeover.

    // Animate when tutorial state changes. The pulse ring only exists while a
    // tutorial is running, so its ticker is stopped the rest of the time (see
    // initState) — otherwise it holds the whole app at ~30fps forever.
    if (tutorialState.activeCategory != null) {
      _animController.forward();
      if (!_pulseController.isAnimating) _pulseController.repeat();
    } else {
      _animController.reverse();
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.value = 0;
      }
    }

    return Stack(
      children: [
        widget.child,

        // Tutorial overlay
        if (tutorialState.activeCategory != null)
          FadeTransition(
            opacity: _fadeAnimation,
            child: _TutorialOverlayContent(
              step: notifier.currentStep,
              currentIndex: tutorialState.currentStepIndex,
              totalSteps: notifier.totalSteps,
              isFirst: notifier.isFirstStep,
              isLast: notifier.isLastStep,
              ringAnimation: _ringAnimation,
              ringOpacityAnimation: _ringOpacityAnimation,
              isBusy: _pendingAction != null,
              isAdvancing: _pendingAction == _TutorialOverlayAction.next,
              isGoingBack: _pendingAction == _TutorialOverlayAction.previous,
              isSkipping: _pendingAction == _TutorialOverlayAction.skip,
              onNext: () => _runAction(
                _TutorialOverlayAction.next,
                notifier.nextStep,
              ),
              onPrevious: () => _runAction(
                _TutorialOverlayAction.previous,
                notifier.previousStep,
              ),
              onSkip: () => _runAction(
                _TutorialOverlayAction.skip,
                notifier.dismissTutorial,
              ),
              onSpotlightTapped: () {
                // Action completion callback - fires when user interacts with spotlight
                // This can be used to auto-advance steps in the future
              },
            ),
          ),
      ],
    );
  }
}

enum _TutorialOverlayAction { next, previous, skip }
