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

/// Provider that exposes whether the welcome flow should be shown.
/// Used by parent widgets to determine when to display WelcomeFlow.
final shouldShowWelcomeFlowProvider = Provider<bool>((ref) {
  final tutorialState = ref.watch(tutorialProvider);
  return !tutorialState.hasSeenInitialTour && tutorialState.tutorialsEnabled;
});

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
  static final navDiagnostics = GlobalKey(debugLabel: 'nav_diagnostics');
  static final navSettings = GlobalKey(debugLabel: 'nav_settings');
  static final navPolarAlignment = GlobalKey(debugLabel: 'nav_polar_alignment');

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
      case 'nav_polar_alignment':
        return navPolarAlignment;
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

    // Pulse controller for the expanding ring effect (2 second cycle)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

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

    // Note: Initial tour prompt is now handled by WelcomeFlow widget.
    // Parent widgets can use shouldShowWelcomeFlowProvider to determine
    // when to display the WelcomeFlow instead of this overlay.

    // Animate when tutorial state changes
    if (tutorialState.activeCategory != null) {
      _animController.forward();
    } else {
      _animController.reverse();
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
              onNext: notifier.nextStep,
              onPrevious: notifier.previousStep,
              onSkip: notifier.dismissTutorial,
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

class _TutorialOverlayContent extends StatefulWidget {
  final TutorialStep? step;
  final int currentIndex;
  final int totalSteps;
  final bool isFirst;
  final bool isLast;
  final Animation<double> ringAnimation;
  final Animation<double> ringOpacityAnimation;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onSkip;
  final VoidCallback? onSpotlightTapped;

  const _TutorialOverlayContent({
    required this.step,
    required this.currentIndex,
    required this.totalSteps,
    required this.isFirst,
    required this.isLast,
    required this.ringAnimation,
    required this.ringOpacityAnimation,
    required this.onNext,
    required this.onPrevious,
    required this.onSkip,
    this.onSpotlightTapped,
  });

  @override
  State<_TutorialOverlayContent> createState() =>
      _TutorialOverlayContentState();
}

class _TutorialOverlayContentState extends State<_TutorialOverlayContent> {
  final FocusNode _focusNode = FocusNode();
  int _lastAnnouncedIndex = -1;

  @override
  void initState() {
    super.initState();
    // Request focus when the overlay is shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _announceStep();
    });
  }

  @override
  void didUpdateWidget(_TutorialOverlayContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Announce step change to screen readers
    if (oldWidget.currentIndex != widget.currentIndex) {
      _announceStep();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _announceStep() {
    if (widget.step != null && widget.currentIndex != _lastAnnouncedIndex) {
      _lastAnnouncedIndex = widget.currentIndex;
      SemanticsService.announce(
        'Step ${widget.currentIndex + 1} of ${widget.totalSteps}: ${widget.step!.title}. ${widget.step!.description}',
        TextDirection.ltr,
      );
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onSkip();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      widget.onNext();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (!widget.isFirst) {
        widget.onPrevious();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onNext();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Determine spotlight shape based on target dimensions
  SpotlightShape _getSpotlightShape(Rect? targetRect) {
    if (targetRect == null) return SpotlightShape.roundedRect;

    // Use aspect ratio to guess appropriate shape
    final aspectRatio = targetRect.width / targetRect.height;

    // Square-ish elements (icons, circular buttons) -> circle
    if (aspectRatio > 0.8 && aspectRatio < 1.2) {
      return SpotlightShape.circle;
    }

    // Wide elements (text buttons, labels) -> pill
    if (aspectRatio > 2.0) {
      return SpotlightShape.pill;
    }

    // Default to rounded rect
    return SpotlightShape.roundedRect;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.step == null) return const SizedBox.shrink();

    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final targetKey = TutorialKeys.getKey(widget.step!.targetKey);
    Rect? targetRect;

    if (targetKey?.currentContext != null) {
      final renderBox =
          targetKey!.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final position = renderBox.localToGlobal(Offset.zero);
        targetRect = Rect.fromLTWH(
          position.dx,
          position.dy,
          renderBox.size.width,
          renderBox.size.height,
        );
      }
    }

    final spotlightShape = _getSpotlightShape(targetRect);
    final screenSize = MediaQuery.of(context).size;

    // Check if step is interactive (allows click-through)
    // Default to interactive when a target is available
    final isInteractive = targetRect != null;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Semantics(
        label:
            'Tutorial step ${widget.currentIndex + 1} of ${widget.totalSteps}: ${widget.step!.title}',
        hint:
            'Press Enter or Space for next step, Backspace for previous, Escape to skip',
        child: Stack(
          children: [
            // Dimmed background with spotlight - uses custom hit testing
            _SpotlightHitTestWidget(
              targetRect: targetRect,
              padding: 8,
              isInteractive: isInteractive,
              onSpotlightTapped: widget.onSpotlightTapped,
              child: CustomPaint(
                size: Size(screenSize.width, screenSize.height),
                painter: _SpotlightPainter(
                  targetRect: targetRect,
                  padding: 8,
                  dimColor: colors.background.withValues(alpha: 0.85),
                  shape: spotlightShape,
                ),
              ),
            ),

            // Expanding ring pulse effect around target
            if (targetRect != null)
              AnimatedBuilder(
                animation: widget.ringAnimation,
                builder: (context, child) {
                  return _ExpandingRingPainter.buildWidget(
                    targetRect: targetRect!,
                    padding: 8,
                    ringProgress: widget.ringAnimation.value,
                    ringOpacity: widget.ringOpacityAnimation.value,
                    ringColor: colors.primary,
                    shape: spotlightShape,
                  );
                },
              ),

            // Tooltip
            _TooltipWidget(
              step: widget.step!,
              targetRect: targetRect,
              currentIndex: widget.currentIndex,
              totalSteps: widget.totalSteps,
              isFirst: widget.isFirst,
              isLast: widget.isLast,
              onNext: widget.onNext,
              onPrevious: widget.onPrevious,
              onSkip: widget.onSkip,
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget that handles hit testing for the spotlight area
/// Clicks within the spotlight "hole" pass through to underlying widgets
/// Clicks outside the spotlight (on the dim area) are blocked
class _SpotlightHitTestWidget extends SingleChildRenderObjectWidget {
  final Rect? targetRect;
  final double padding;
  final bool isInteractive;
  final VoidCallback? onSpotlightTapped;

  const _SpotlightHitTestWidget({
    required super.child,
    required this.targetRect,
    required this.padding,
    required this.isInteractive,
    this.onSpotlightTapped,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _SpotlightHitTestRenderBox(
      targetRect: targetRect,
      padding: padding,
      isInteractive: isInteractive,
      onSpotlightTapped: onSpotlightTapped,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, _SpotlightHitTestRenderBox renderObject) {
    renderObject
      ..targetRect = targetRect
      ..padding = padding
      ..isInteractive = isInteractive
      ..onSpotlightTapped = onSpotlightTapped;
  }
}

class _SpotlightHitTestRenderBox extends RenderProxyBox {
  Rect? _targetRect;
  double _padding;
  bool _isInteractive;
  VoidCallback? _onSpotlightTapped;

  _SpotlightHitTestRenderBox({
    Rect? targetRect,
    required double padding,
    required bool isInteractive,
    VoidCallback? onSpotlightTapped,
  })  : _targetRect = targetRect,
        _padding = padding,
        _isInteractive = isInteractive,
        _onSpotlightTapped = onSpotlightTapped;

  Rect? get targetRect => _targetRect;
  set targetRect(Rect? value) {
    if (_targetRect != value) {
      _targetRect = value;
      markNeedsPaint();
    }
  }

  double get padding => _padding;
  set padding(double value) {
    if (_padding != value) {
      _padding = value;
      markNeedsPaint();
    }
  }

  bool get isInteractive => _isInteractive;
  set isInteractive(bool value) {
    if (_isInteractive != value) {
      _isInteractive = value;
      markNeedsPaint();
    }
  }

  VoidCallback? get onSpotlightTapped => _onSpotlightTapped;
  set onSpotlightTapped(VoidCallback? value) {
    _onSpotlightTapped = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // If no target or not interactive, block all hits (dim area behavior)
    if (_targetRect == null || !_isInteractive) {
      // Still need to add ourselves to absorb the hit
      result.add(BoxHitTestEntry(this, position));
      return true;
    }

    // Check if the hit is within the spotlight hole
    final spotlightRect = _targetRect!.inflate(_padding);
    if (spotlightRect.contains(position)) {
      // Hit is in the spotlight - let it pass through to underlying widget
      // Call the callback if provided
      _onSpotlightTapped?.call();
      return false;
    }

    // Hit is in the dim area - absorb it
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final double padding;
  final Color dimColor;
  final SpotlightShape shape;

  _SpotlightPainter({
    this.targetRect,
    this.padding = 8,
    required this.dimColor,
    this.shape = SpotlightShape.roundedRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dimColor;

    if (targetRect == null) {
      // No target - draw full dim
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    } else {
      // Draw dim with spotlight cutout based on shape
      final path = Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

      final inflatedRect = targetRect!.inflate(padding);

      switch (shape) {
        case SpotlightShape.circle:
          // Use the larger dimension for radius to ensure entire target is visible
          final radius = math.max(inflatedRect.width, inflatedRect.height) / 2;
          path.addOval(
            Rect.fromCenter(
              center: inflatedRect.center,
              width: radius * 2,
              height: radius * 2,
            ),
          );
          break;

        case SpotlightShape.pill:
          // Horizontal oval/capsule shape
          final verticalRadius = inflatedRect.height / 2;
          final horizontalRadius =
              inflatedRect.width / 2 + verticalRadius * 0.5;
          path.addRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: inflatedRect.center,
                width: horizontalRadius * 2,
                height: inflatedRect.height,
              ),
              Radius.circular(verticalRadius),
            ),
          );
          break;

        case SpotlightShape.roundedRect:
          path.addRRect(
            RRect.fromRectAndRadius(
              inflatedRect,
              const Radius.circular(8),
            ),
          );
          break;
      }

      path.fillType = PathFillType.evenOdd;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return targetRect != oldDelegate.targetRect ||
        dimColor != oldDelegate.dimColor ||
        padding != oldDelegate.padding ||
        shape != oldDelegate.shape;
  }
}

/// Painter for the expanding ring pulse effect
class _ExpandingRingPainter extends CustomPainter {
  final Rect targetRect;
  final double padding;
  final double ringProgress;
  final double ringOpacity;
  final Color ringColor;
  final SpotlightShape shape;

  _ExpandingRingPainter({
    required this.targetRect,
    required this.padding,
    required this.ringProgress,
    required this.ringOpacity,
    required this.ringColor,
    required this.shape,
  });

  /// Build a positioned widget containing the ring painter
  static Widget buildWidget({
    required Rect targetRect,
    required double padding,
    required double ringProgress,
    required double ringOpacity,
    required Color ringColor,
    required SpotlightShape shape,
  }) {
    // Calculate the maximum expansion distance
    const maxExpansion = 24.0;
    final currentExpansion = maxExpansion * ringProgress;
    final expandedPadding = padding + currentExpansion;

    // Calculate bounds for the ring
    final inflatedRect = targetRect.inflate(expandedPadding + 4);

    return Positioned(
      left: inflatedRect.left,
      top: inflatedRect.top,
      width: inflatedRect.width,
      height: inflatedRect.height,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _ExpandingRingPainter(
            targetRect: Rect.fromLTWH(
              targetRect.left - inflatedRect.left,
              targetRect.top - inflatedRect.top,
              targetRect.width,
              targetRect.height,
            ),
            padding: padding,
            ringProgress: ringProgress,
            ringOpacity: ringOpacity,
            ringColor: ringColor,
            shape: shape,
          ),
        ),
      ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (ringOpacity <= 0) return;

    const maxExpansion = 24.0;
    final currentExpansion = maxExpansion * ringProgress;

    final paint = Paint()
      ..color = ringColor.withValues(alpha: ringOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final inflatedRect = targetRect.inflate(padding + currentExpansion);

    switch (shape) {
      case SpotlightShape.circle:
        final radius = math.max(inflatedRect.width, inflatedRect.height) / 2;
        canvas.drawOval(
          Rect.fromCenter(
            center: inflatedRect.center,
            width: radius * 2,
            height: radius * 2,
          ),
          paint,
        );
        break;

      case SpotlightShape.pill:
        final verticalRadius = inflatedRect.height / 2;
        final horizontalRadius = inflatedRect.width / 2 + verticalRadius * 0.5;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: inflatedRect.center,
              width: horizontalRadius * 2,
              height: inflatedRect.height,
            ),
            Radius.circular(verticalRadius),
          ),
          paint,
        );
        break;

      case SpotlightShape.roundedRect:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            inflatedRect,
            const Radius.circular(8),
          ),
          paint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ExpandingRingPainter oldDelegate) {
    return targetRect != oldDelegate.targetRect ||
        padding != oldDelegate.padding ||
        ringProgress != oldDelegate.ringProgress ||
        ringOpacity != oldDelegate.ringOpacity ||
        ringColor != oldDelegate.ringColor ||
        shape != oldDelegate.shape;
  }
}

class _TooltipWidget extends StatelessWidget {
  final TutorialStep step;
  final Rect? targetRect;
  final int currentIndex;
  final int totalSteps;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onSkip;

  const _TooltipWidget({
    required this.step,
    this.targetRect,
    required this.currentIndex,
    required this.totalSteps,
    required this.isFirst,
    required this.isLast,
    required this.onNext,
    required this.onPrevious,
    required this.onSkip,
  });

  /// Get responsive tooltip width based on screen size
  double _getTooltipWidth(double screenWidth) {
    if (screenWidth < 600) return screenWidth * 0.85; // Mobile
    if (screenWidth < 1200) return 360; // Tablet
    return 400; // Desktop
  }

  /// Get responsive title font size
  double _getTitleSize(double screenWidth) {
    return screenWidth < 600 ? 14 : 16;
  }

  /// Get responsive description font size
  double _getDescriptionSize(double screenWidth) {
    return screenWidth < 600 ? 12 : 13;
  }

  /// Get responsive padding
  double _getPadding(double screenWidth) {
    return screenWidth < 600 ? 16 : 20;
  }

  /// Calculate the best position for the tooltip to avoid overflow
  ({double? left, double? top, double? right, double? bottom})
      _calculateBestPosition(
    Rect? targetRect,
    Size screenSize,
    double tooltipWidth,
  ) {
    const tooltipPadding = 16.0;
    const estimatedTooltipHeight = 200.0;
    final screenWidth = screenSize.width;

    // No target - use position hint or default placement
    if (targetRect == null) {
      if (step.position == TooltipPosition.center) {
        // Place in bottom-right corner so users can see main content
        // On mobile, center it instead
        if (screenWidth < 600) {
          return (
            left: (screenWidth - tooltipWidth) / 2,
            top: null,
            right: null,
            bottom: tooltipPadding + 24,
          );
        }
        return (
          left: null,
          top: null,
          right: tooltipPadding + 24,
          bottom: tooltipPadding + 24,
        );
      }
      // Center the tooltip
      return (
        left: (screenWidth - tooltipWidth) / 2,
        top: screenSize.height / 2 - 100,
        right: null,
        bottom: null,
      );
    }

    // Has target but wants center - center below target
    if (step.position == TooltipPosition.center) {
      return (
        left: (screenWidth - tooltipWidth) / 2,
        top: math.max(
            targetRect.bottom + tooltipPadding, screenSize.height / 2 - 100),
        right: null,
        bottom: null,
      );
    }

    // Try preferred position first
    var preferredPosition = step.position;
    var result = _tryPosition(
      preferredPosition,
      targetRect,
      screenSize,
      tooltipWidth,
      estimatedTooltipHeight,
      tooltipPadding,
    );

    if (_isValidPosition(result, screenSize, tooltipWidth,
        estimatedTooltipHeight, tooltipPadding)) {
      return result;
    }

    // Try opposite position
    final oppositePosition = _getOppositePosition(preferredPosition);
    result = _tryPosition(
      oppositePosition,
      targetRect,
      screenSize,
      tooltipWidth,
      estimatedTooltipHeight,
      tooltipPadding,
    );

    if (_isValidPosition(result, screenSize, tooltipWidth,
        estimatedTooltipHeight, tooltipPadding)) {
      return result;
    }

    // Try perpendicular positions
    final perpendicularPositions =
        _getPerpendicularPositions(preferredPosition);
    for (final position in perpendicularPositions) {
      result = _tryPosition(
        position,
        targetRect,
        screenSize,
        tooltipWidth,
        estimatedTooltipHeight,
        tooltipPadding,
      );

      if (_isValidPosition(result, screenSize, tooltipWidth,
          estimatedTooltipHeight, tooltipPadding)) {
        return result;
      }
    }

    // Last resort: center on screen
    return (
      left: (screenWidth - tooltipWidth) / 2,
      top: (screenSize.height - estimatedTooltipHeight) / 2,
      right: null,
      bottom: null,
    );
  }

  /// Try to position the tooltip at a specific position
  ({double? left, double? top, double? right, double? bottom}) _tryPosition(
    TooltipPosition position,
    Rect targetRect,
    Size screenSize,
    double tooltipWidth,
    double tooltipHeight,
    double padding,
  ) {
    switch (position) {
      case TooltipPosition.right:
        return (
          left: targetRect.right + padding,
          top: targetRect.top,
          right: null,
          bottom: null,
        );
      case TooltipPosition.left:
        return (
          left: null,
          top: targetRect.top,
          right: screenSize.width - targetRect.left + padding,
          bottom: null,
        );
      case TooltipPosition.bottom:
        return (
          left: targetRect.left,
          top: targetRect.bottom + padding,
          right: null,
          bottom: null,
        );
      case TooltipPosition.top:
        return (
          left: targetRect.left,
          top: null,
          right: null,
          bottom: screenSize.height - targetRect.top + padding,
        );
      case TooltipPosition.center:
        return (
          left: (screenSize.width - tooltipWidth) / 2,
          top: targetRect.bottom + padding,
          right: null,
          bottom: null,
        );
    }
  }

  /// Check if a position would result in the tooltip being visible on screen
  bool _isValidPosition(
    ({double? left, double? top, double? right, double? bottom}) position,
    Size screenSize,
    double tooltipWidth,
    double tooltipHeight,
    double padding,
  ) {
    double left = position.left ?? 0;
    double top = position.top ?? 0;

    // Calculate actual left if right is specified
    if (position.right != null) {
      left = screenSize.width - position.right! - tooltipWidth;
    }

    // Calculate actual top if bottom is specified
    if (position.bottom != null) {
      top = screenSize.height - position.bottom! - tooltipHeight;
    }

    // Check bounds
    return left >= padding &&
        left + tooltipWidth <= screenSize.width - padding &&
        top >= padding &&
        top + tooltipHeight <= screenSize.height - padding;
  }

  /// Get the opposite position
  TooltipPosition _getOppositePosition(TooltipPosition position) {
    switch (position) {
      case TooltipPosition.top:
        return TooltipPosition.bottom;
      case TooltipPosition.bottom:
        return TooltipPosition.top;
      case TooltipPosition.left:
        return TooltipPosition.right;
      case TooltipPosition.right:
        return TooltipPosition.left;
      case TooltipPosition.center:
        return TooltipPosition.center;
    }
  }

  /// Get perpendicular positions
  List<TooltipPosition> _getPerpendicularPositions(TooltipPosition position) {
    switch (position) {
      case TooltipPosition.top:
      case TooltipPosition.bottom:
        return [TooltipPosition.right, TooltipPosition.left];
      case TooltipPosition.left:
      case TooltipPosition.right:
        return [TooltipPosition.bottom, TooltipPosition.top];
      case TooltipPosition.center:
        return [
          TooltipPosition.bottom,
          TooltipPosition.right,
          TooltipPosition.top,
          TooltipPosition.left
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;

    // Responsive sizing
    final tooltipWidth = _getTooltipWidth(screenWidth);
    final titleSize = _getTitleSize(screenWidth);
    final descriptionSize = _getDescriptionSize(screenWidth);
    final padding = _getPadding(screenWidth);
    const tooltipPadding = 16.0;

    // Calculate smart tooltip position
    final position =
        _calculateBestPosition(targetRect, screenSize, tooltipWidth);

    // Apply clamping to ensure tooltip stays on screen
    double? finalLeft = position.left;
    double? finalTop = position.top;

    if (finalLeft != null) {
      finalLeft = math.max(
        tooltipPadding,
        math.min(finalLeft, screenWidth - tooltipWidth - tooltipPadding),
      );
    }
    if (finalTop != null) {
      finalTop = math.max(
        tooltipPadding,
        math.min(finalTop, screenSize.height - 200),
      );
    }

    return Positioned(
      left: finalLeft,
      top: finalTop,
      right: position.right,
      bottom: position.bottom,
      child: Semantics(
        container: true,
        label: 'Tutorial: ${step.title}',
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: tooltipWidth,
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: colors.background.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Semantics(
                  header: true,
                  child: Text(
                    step.title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Description
                Text(
                  step.description,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: descriptionSize,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 16),

                // Progress indicator - use a progress bar instead of dots for many steps
                Semantics(
                  label: 'Progress: step ${currentIndex + 1} of $totalSteps',
                  child: Row(
                    children: [
                      // Progress bar
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: totalSteps > 1
                                ? (currentIndex + 1) / totalSteps
                                : 1,
                            backgroundColor: colors.border,
                            valueColor: AlwaysStoppedAnimation(colors.primary),
                            minHeight: 4,
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      Text(
                        '${currentIndex + 1} / $totalSteps',
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Navigation buttons
                Row(
                  children: [
                    // Skip button
                    Semantics(
                      button: true,
                      label: 'Skip tour',
                      hint: 'Press Escape to skip',
                      child: NightshadeButton(
                        onPressed: onSkip,
                        label: 'Skip tour',
                        variant: ButtonVariant.ghost,
                        size: ButtonSize.small,
                      ),
                    ),

                    const Spacer(),

                    // Previous button
                    if (!isFirst)
                      Semantics(
                        button: true,
                        label: 'Previous step',
                        hint: 'Press Backspace or Left Arrow',
                        child: NightshadeButton(
                          onPressed: onPrevious,
                          label: 'Back',
                          icon: LucideIcons.chevronLeft,
                          variant: ButtonVariant.ghost,
                          size: ButtonSize.small,
                        ),
                      ),

                    const SizedBox(width: 8),

                    // Next/Done button
                    Semantics(
                      button: true,
                      label: isLast ? 'Finish tutorial' : 'Next step',
                      hint: 'Press Enter, Space, or Right Arrow',
                      child: NightshadeButton(
                        onPressed: onNext,
                        label: isLast ? 'Done' : 'Next',
                        icon: isLast ? null : LucideIcons.chevronRight,
                        size: ButtonSize.small,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
