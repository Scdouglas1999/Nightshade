import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Terminal "what's next" step shown after the equipment profile is created.
///
/// By the time this renders the rig already exists and is the active profile —
/// [OnboardingNotifier.complete] ran on the summary step. This step celebrates
/// that, summarizes the rig the user just built, and offers the three natural
/// next actions: capture first light, take the first-night walkthrough, or
/// review the readiness checklist.
///
/// Every action routes through [onNavigate], which retires the wizard
/// (marks the tutorial complete, wipes the draft, flips the bootstrap gate) and
/// then navigates. That keeps the "finish exactly once" logic in the wizard
/// shell rather than duplicating it per card.
class OnboardingNextStepsStep extends ConsumerWidget {
  const OnboardingNextStepsStep({super.key, required this.onNavigate});

  /// Finalizes onboarding and navigates to the given route. Supplied by
  /// [OnboardingScreen]; see [OnboardingNotifier.finishNextSteps].
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingDraftProvider);
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);

    final profileName = (draft.profileName ?? '').trim().isNotEmpty
        ? draft.profileName!.trim()
        : 'My First Rig';
    final imageScale = draft.imageScaleArcsecPerPixel;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Celebration / summary panel.
          NightshadeCard(
            variant: CardVariant.elevated,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: NightshadeTokens.iconXl + NightshadeTokens.spaceMd,
                      height:
                          NightshadeTokens.iconXl + NightshadeTokens.spaceMd,
                      alignment: Alignment.center,
                      decoration:
                          NightshadeDecorations.iconChip(colors.success),
                      child: Icon(
                        LucideIcons.rocket,
                        color: colors.success,
                        size: NightshadeTokens.iconLg,
                      ),
                    ),
                    const SizedBox(width: NightshadeTokens.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "You're all set",
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$profileName is active and ready to image.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NightshadeTokens.spaceLg),
                _SummaryLine(
                  // `aperture` is this codebase's telescope/optics icon;
                  // lucide_icons 0.257.0 has no `telescope` glyph.
                  icon: LucideIcons.aperture,
                  label: 'Telescope',
                  value: draft.telescopeName ??
                      (draft.focalLengthMm != null
                          ? '${draft.focalLengthMm!.toStringAsFixed(0)} mm'
                          : null),
                ),
                _SummaryLine(
                  icon: LucideIcons.camera,
                  label: 'Camera',
                  value: draft.cameraName,
                ),
                _SummaryLine(
                  icon: LucideIcons.move,
                  label: 'Image scale',
                  value: imageScale != null
                      ? '${imageScale.toStringAsFixed(2)} arcsec/px'
                      : null,
                  mono: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: NightshadeTokens.space2xl),
          Text(
            'Where to next?',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _NextStepCard(
            icon: LucideIcons.sparkles,
            tint: colors.primary,
            title: 'Capture your first light',
            subtitle:
                'Connect your camera and take your very first exposure, guided step by step.',
            onTap: () => onNavigate('/imaging?firstLight=1'),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _NextStepCard(
            icon: LucideIcons.bookOpen,
            tint: colors.info,
            title: 'Take the first-night walkthrough',
            subtitle:
                'A short tour of the imaging, sequencing, and guiding workflow.',
            onTap: () => onNavigate('/tutorial/first-night'),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _NextStepCard(
            icon: LucideIcons.listChecks,
            tint: colors.success,
            title: 'Review readiness checklist',
            subtitle:
                'Confirm your gear connects and everything is configured before you head out.',
            onTap: () => onNavigate('/equipment'),
          ),
        ],
      ),
    );
  }
}

/// One labelled fact in the rig-summary panel. Renders "— not set —" in muted
/// type when the value is absent rather than hiding the row, so the user sees
/// the complete shape of their profile.
class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);
    final hasValue = value != null && value!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceXs),
      child: Row(
        children: [
          Icon(icon,
              size: NightshadeTokens.iconXs, color: colors.textSecondary),
          const SizedBox(width: NightshadeTokens.spaceSm),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              hasValue ? value! : '— not set —',
              style: hasValue && mono
                  ? NightshadeTypography.monoSm.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    )
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: hasValue ? colors.textPrimary : colors.textMuted,
                      fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable next-step card: tinted icon chip + title + subtitle + chevron.
class _NextStepCard extends StatelessWidget {
  const _NextStepCard({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);

    return NightshadeCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: NightshadeTokens.iconXl,
            height: NightshadeTokens.iconXl,
            alignment: Alignment.center,
            decoration: NightshadeDecorations.iconChip(tint),
            child: Icon(icon, color: tint, size: NightshadeTokens.iconMd),
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Icon(
            LucideIcons.chevronRight,
            size: NightshadeTokens.iconMd,
            color: colors.textMuted,
          ),
        ],
      ),
    );
  }
}
