import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Tooltip card for a single onboarding step.
///
/// The card hosts the step title + body, optional progress dots, and the
/// footer button row (Back / Next / Skip / Done depending on position).
/// It is positioned by the overlay above or below the spotlighted target
/// using the [targetRect] passed in; for steps with no target it centers
/// itself on the screen.
class OnboardingTooltipCard extends StatelessWidget {
  final String title;
  final String body;
  final int currentIndex;
  final int totalSteps;

  /// Spotlight rect in screen coordinates. Drives placement: cards
  /// position themselves below the target if the target is in the top
  /// half of the screen, above otherwise. Null means center the card.
  final Rect? targetRect;
  final Size screenSize;

  /// Button row config. Caller decides which buttons to show — the card
  /// just renders whatever it's given. Null buttons are omitted.
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;
  final VoidCallback? onDone;

  /// Label for the primary button. Defaults to "Next" but the welcome
  /// card uses "Show me around" and the completion card uses "Done".
  final String primaryLabel;

  /// Optional secondary button (used by the welcome card's "Skip — I know
  /// what I'm doing" and the completion card's "Show me about defect
  /// maps").
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const OnboardingTooltipCard({
    super.key,
    required this.title,
    required this.body,
    required this.currentIndex,
    required this.totalSteps,
    required this.targetRect,
    required this.screenSize,
    this.onBack,
    this.onNext,
    this.onSkip,
    this.onDone,
    this.primaryLabel = 'Next',
    this.secondaryLabel,
    this.onSecondary,
  });

  /// Pick a fixed tooltip width by breakpoint so the card never tries to
  /// stretch full-screen on a 4K monitor or compress unreadably on a
  /// phone-width window.
  double _cardWidth() {
    if (screenSize.width < 600) return screenSize.width - 32;
    if (screenSize.width < 1200) return 380;
    return 420;
  }

  /// Compute the (left, top) of the card.
  ///
  /// Layout policy:
  ///   - No target → centered.
  ///   - Target in top half of screen → card sits below the cutout.
  ///   - Target in bottom half → card sits above the cutout.
  /// Always clamped to a 16-pixel margin from screen edges.
  Offset _cardOffset(double cardWidth, double estimatedCardHeight) {
    const margin = 16.0;

    if (targetRect == null) {
      return Offset(
        (screenSize.width - cardWidth) / 2,
        (screenSize.height - estimatedCardHeight) / 2,
      );
    }

    final rect = targetRect!;
    final placeBelow = rect.center.dy < screenSize.height / 2;

    double left = rect.center.dx - cardWidth / 2;
    left = left.clamp(margin, screenSize.width - cardWidth - margin);

    double top;
    if (placeBelow) {
      top = rect.bottom + margin;
      // If the card would overflow off the bottom, pin it to the top of
      // the cutout so it's at least visible.
      if (top + estimatedCardHeight > screenSize.height - margin) {
        top = (screenSize.height - estimatedCardHeight) / 2;
      }
    } else {
      top = rect.top - estimatedCardHeight - margin;
      if (top < margin) {
        top = (screenSize.height - estimatedCardHeight) / 2;
      }
    }

    return Offset(left, top);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final cardWidth = _cardWidth();
    // Conservative estimate that fits any of our copy without
    // measure-then-place ping-pong. The card paints with mainAxisSize.min
    // so this is only used for the placement math, not for the rendered
    // height.
    const estimatedCardHeight = 240.0;
    final offset = _cardOffset(cardWidth, estimatedCardHeight);

    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: Semantics(
        container: true,
        label: 'Onboarding tour: $title',
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: cardWidth,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colors.primary.withValues(alpha: 0.35),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        LucideIcons.sparkles,
                        color: colors.primary,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Step ${currentIndex + 1} of $totalSteps',
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.textMuted,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                _ProgressDots(
                  current: currentIndex,
                  total: totalSteps,
                  primaryColor: colors.primary,
                  inactiveColor: colors.border,
                ),
                const SizedBox(height: 18),
                _buildActions(colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions(NightshadeColors colors) {
    // Wrap so long secondary labels ("Show me about defect maps",
    // "Skip — I know what I'm doing") flow onto a second row on narrow
    // tooltip widths instead of overflowing horizontally. Spacing
    // separates rows when wrap engages; alignment.end keeps the primary
    // action button right-aligned within whatever row it lands on, which
    // matches the user's read order.
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (onSkip != null)
          NightshadeButton(
            label: 'Skip',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: onSkip,
          ),
        if (secondaryLabel != null && onSecondary != null)
          NightshadeButton(
            label: secondaryLabel!,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: onSecondary,
          ),
        if (onBack != null)
          NightshadeButton(
            label: 'Back',
            icon: LucideIcons.chevronLeft,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: onBack,
          ),
        if (onDone != null)
          NightshadeButton(
            label: 'Done',
            icon: LucideIcons.check,
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: onDone,
          )
        else if (onNext != null)
          NightshadeButton(
            label: primaryLabel,
            icon: LucideIcons.chevronRight,
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: onNext,
          ),
      ],
    );
  }
}

class _ProgressDots extends StatelessWidget {
  final int current;
  final int total;
  final Color primaryColor;
  final Color inactiveColor;

  const _ProgressDots({
    required this.current,
    required this.total,
    required this.primaryColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final isActive = i == current;
        final isComplete = i < current;
        return Padding(
          padding: const EdgeInsets.only(right: 5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: isActive ? 14 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive
                  ? primaryColor
                  : isComplete
                      ? primaryColor.withValues(alpha: 0.5)
                      : inactiveColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }
}
