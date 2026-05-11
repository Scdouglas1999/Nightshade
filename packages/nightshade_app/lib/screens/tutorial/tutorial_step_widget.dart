import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Reusable body for a single first-night wizard step.
///
/// Renders inside the [NightshadeDialog] scaffold owned by the parent
/// wizard widget — this widget is just the body, not the chrome. Keeping
/// the step UI in its own widget means future tutorials (post v2.5.x) can
/// drop a `TutorialStepWidget(step: ...)` into any dialog and get the
/// same look: a circled lucide icon, a description block, an optional
/// "Show me" deep-link button, and a progress dot row.
///
/// Why factored out: the spec lists this as a reusable step UI so future
/// tutorials can be added without re-implementing the WHY-style layout.
class TutorialStepWidget extends StatelessWidget {
  /// The wizard step being rendered. Contains title, description, icon
  /// name, and deep-link route.
  final FirstNightWizardStep step;

  /// Current step index (0-based) — used by the progress dots.
  final int currentIndex;

  /// Total number of steps in the wizard. Drives the progress dot count.
  final int totalSteps;

  /// Invoked when the user clicks the "Show me" deep-link button. Caller
  /// is responsible for the actual navigation; this widget just decides
  /// whether to render the button based on `step.hasDeepLink`.
  final VoidCallback? onShowMe;

  const TutorialStepWidget({
    super.key,
    required this.step,
    required this.currentIndex,
    required this.totalSteps,
    this.onShowMe,
  });

  /// Map the model's icon name (a string, to keep nightshade_core free of
  /// Flutter imports) to the actual lucide IconData. Throws for unknown
  /// names — errors are a feature; a typo here should fail loud at
  /// runtime, not silently render a generic placeholder.
  IconData _resolveIcon(String iconName) {
    switch (iconName) {
      case 'sparkles':
        return LucideIcons.sparkles;
      case 'plug':
        return LucideIcons.plug;
      case 'compass':
        return LucideIcons.compass;
      case 'snowflake':
        return LucideIcons.snowflake;
      case 'crop':
        return LucideIcons.crop;
      case 'crosshair':
        return LucideIcons.crosshair;
      case 'play':
        return LucideIcons.play;
      default:
        throw ArgumentError(
          'TutorialStepWidget: unknown icon name "$iconName". '
          'Add a mapping in _resolveIcon when introducing a new wizard step.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final icon = _resolveIcon(step.iconName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon + step number row. The lucide icon goes in a tinted square
        // matching the rest of the design system; the "Step N of M" label
        // sits next to it to anchor the user in the wizard.
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: colors.primary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // TODO(v2.5.x i18n): localize wizard step labels in the
                    // nightshade_localizations sweep.
                    'Step ${currentIndex + 1} of $totalSteps',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // The WHY-style body text. Single fixed-width paragraph; the parent
        // NightshadeDialog provides the scroll view when content exceeds
        // dialog height, so we don't wrap this in another scroll widget.
        Text(
          step.description,
          style: TextStyle(
            fontSize: 13,
            height: 1.55,
            color: colors.textSecondary,
          ),
        ),

        const SizedBox(height: 20),

        // "Show me" deep-link. Only shown if the step has a route — the
        // welcome step has no screen to deep-link into, so the button is
        // hidden rather than rendered with a disabled-looking state.
        if (step.hasDeepLink)
          NightshadeButton(
            label: 'Show me on the ${_routeLabel(step.deepLinkRoute)} screen',
            icon: LucideIcons.externalLink,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: onShowMe,
          ),

        const SizedBox(height: 24),

        // Progress dots — a compact visual of where the user is in the
        // 7-step flow without taking vertical space from the description.
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(totalSteps, (i) {
            final isActive = i == currentIndex;
            final isComplete = i < currentIndex;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                width: isActive ? 16 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive
                      ? colors.primary
                      : isComplete
                          ? colors.primary.withValues(alpha: 0.5)
                          : colors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  /// Convert a go_router path to a human-readable screen name for the
  /// "Show me on the X screen" button label. Keeps the button copy concrete
  /// — "Show me on the Polar Alignment screen" is much clearer than
  /// "Show me".
  String _routeLabel(String route) {
    switch (route) {
      case '/equipment':
        return 'Equipment';
      case '/polar-alignment':
        return 'Polar Alignment';
      case '/imaging':
        return 'Imaging';
      case '/framing':
        return 'Framing';
      case '/guiding':
        return 'Guiding';
      case '/sequencer':
        return 'Sequencer';
      default:
        throw ArgumentError(
          'TutorialStepWidget._routeLabel: no human label for route '
          '"$route". Add one when introducing a new wizard deep-link.',
        );
    }
  }
}
