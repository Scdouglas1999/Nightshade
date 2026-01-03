import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Global keys for tutorial targets
class TutorialKeys {
  static final sideNavigation = GlobalKey();
  static final navDashboard = GlobalKey();
  static final navEquipment = GlobalKey();
  static final navImaging = GlobalKey();
  static final navGuiding = GlobalKey();
  static final navSequencer = GlobalKey();
  static final navPlanetarium = GlobalKey();
  static final navFraming = GlobalKey();
  static final navFlatWizard = GlobalKey();
  static final navAnalytics = GlobalKey();
  static final navWeather = GlobalKey();

  static GlobalKey? getKey(String? keyId) {
    if (keyId == null) return null;
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
      default:
        return null;
    }
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
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;
  bool _hasShownInitialPrompt = false;

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
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
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
        final steps = TutorialDefinitions.getStepsForCategory(current.activeCategory!);
        if (current.currentStepIndex < steps.length) {
          final step = steps[current.currentStepIndex];
          _navigateForStep(context, step.targetKey);
        }
      }
    });

    // Check if we should show the initial tour
    if (!tutorialState.hasSeenInitialTour &&
        tutorialState.tutorialsEnabled &&
        tutorialState.activeCategory == null &&
        !_hasShownInitialPrompt) {
      // Show the initial tour prompt after ensuring the UI is ready
      _hasShownInitialPrompt = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Add a small delay to ensure the dialog is fully rendered and interactive
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && !tutorialState.hasSeenInitialTour) {
            _showInitialTourPrompt(context);
          }
        });
      });
    }

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
              pulseAnimation: _pulseAnimation,
              onNext: notifier.nextStep,
              onPrevious: notifier.previousStep,
              onSkip: notifier.dismissTutorial,
            ),
          ),
      ],
    );
  }

  void _showInitialTourPrompt(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    showDialog(
      context: context,
      barrierDismissible: false,
      useSafeArea: true,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(LucideIcons.sparkles, color: colors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              'Welcome to Nightshade',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Would you like a quick tour of the application?',
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'The tour will show you the main features and help you get started.',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(tutorialProvider.notifier).markInitialTourSeen();
            },
            child: Text(
              'Skip for now',
              style: TextStyle(color: colors.textMuted),
            ),
          ),
          ElevatedButton(
            autofocus: true,
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(tutorialProvider.notifier)
                  .startTutorial(TutorialCategory.gettingStarted);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Start Tour'),
          ),
        ],
      ),
    );
  }
}

class _TutorialOverlayContent extends StatelessWidget {
  final TutorialStep? step;
  final int currentIndex;
  final int totalSteps;
  final bool isFirst;
  final bool isLast;
  final Animation<double> pulseAnimation;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onSkip;

  const _TutorialOverlayContent({
    required this.step,
    required this.currentIndex,
    required this.totalSteps,
    required this.isFirst,
    required this.isLast,
    required this.pulseAnimation,
    required this.onNext,
    required this.onPrevious,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    if (step == null) return const SizedBox.shrink();

    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final targetKey = TutorialKeys.getKey(step!.targetKey);
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

    return Stack(
      children: [
        // Dimmed background with spotlight
        Positioned.fill(
          child: CustomPaint(
            painter: _SpotlightPainter(
              targetRect: targetRect,
              padding: 8,
              dimColor: Colors.black.withValues(alpha: 0.7),
            ),
          ),
        ),

        // Pulse effect around target
        if (targetRect != null)
          Positioned(
            left: targetRect.left - 4,
            top: targetRect.top - 4,
            child: ScaleTransition(
              scale: pulseAnimation,
              child: Container(
                width: targetRect.width + 8,
                height: targetRect.height + 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Tooltip
        _TooltipWidget(
          step: step!,
          targetRect: targetRect,
          currentIndex: currentIndex,
          totalSteps: totalSteps,
          isFirst: isFirst,
          isLast: isLast,
          onNext: onNext,
          onPrevious: onPrevious,
          onSkip: onSkip,
        ),
      ],
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final double padding;
  final Color dimColor;

  _SpotlightPainter({
    this.targetRect,
    this.padding = 8,
    required this.dimColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dimColor;

    if (targetRect == null) {
      // No target - draw full dim
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    } else {
      // Draw dim with spotlight cutout
      final path = Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRRect(
          RRect.fromRectAndRadius(
            targetRect!.inflate(padding),
            const Radius.circular(8),
          ),
        )
        ..fillType = PathFillType.evenOdd;

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return targetRect != oldDelegate.targetRect || dimColor != oldDelegate.dimColor;
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final screenSize = MediaQuery.of(context).size;

    // Calculate tooltip position
    double? left, top, right, bottom;
    const tooltipWidth = 320.0;
    const tooltipPadding = 16.0;

    if (targetRect == null && step.position == TooltipPosition.center) {
      // No target and center position - place in bottom-right corner
      // so users can see the main content being discussed
      right = tooltipPadding + 24;
      bottom = tooltipPadding + 24;
    } else if (targetRect == null) {
      // No target but specific position requested - center the tooltip
      left = (screenSize.width - tooltipWidth) / 2;
      top = screenSize.height / 2 - 100;
    } else if (step.position == TooltipPosition.center) {
      // Has target but wants center position - center below the target
      left = (screenSize.width - tooltipWidth) / 2;
      top = math.max(targetRect!.bottom + tooltipPadding, screenSize.height / 2 - 100);
    } else {
      switch (step.position) {
        case TooltipPosition.right:
          left = targetRect!.right + tooltipPadding;
          top = targetRect!.top;
          break;
        case TooltipPosition.left:
          right = screenSize.width - targetRect!.left + tooltipPadding;
          top = targetRect!.top;
          break;
        case TooltipPosition.bottom:
          left = targetRect!.left;
          top = targetRect!.bottom + tooltipPadding;
          break;
        case TooltipPosition.top:
          left = targetRect!.left;
          bottom = screenSize.height - targetRect!.top + tooltipPadding;
          break;
        case TooltipPosition.center:
          // Already handled above
          break;
      }

      // Clamp to screen bounds
      if (left != null) {
        left = math.max(tooltipPadding, math.min(left, screenSize.width - tooltipWidth - tooltipPadding));
      }
      if (top != null) {
        top = math.max(tooltipPadding, math.min(top, screenSize.height - 200));
      }
    }

    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: tooltipWidth,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
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
              Text(
                step.title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              // Description
              Text(
                step.description,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 16),

              // Progress indicator - use a progress bar instead of dots for many steps
              Row(
                children: [
                  // Progress bar
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: totalSteps > 1 ? (currentIndex + 1) / totalSteps : 1,
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

              const SizedBox(height: 16),

              // Navigation buttons
              Row(
                children: [
                  // Skip button
                  TextButton(
                    onPressed: onSkip,
                    child: Text(
                      'Skip tour',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ),

                  const Spacer(),

                  // Previous button
                  if (!isFirst)
                    TextButton(
                      onPressed: onPrevious,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.chevronLeft,
                            size: 14,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Back',
                            style: TextStyle(color: colors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(width: 8),

                  // Next/Done button
                  ElevatedButton(
                    onPressed: onNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isLast ? 'Done' : 'Next',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (!isLast) ...[
                          const SizedBox(width: 4),
                          const Icon(LucideIcons.chevronRight, size: 14),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
