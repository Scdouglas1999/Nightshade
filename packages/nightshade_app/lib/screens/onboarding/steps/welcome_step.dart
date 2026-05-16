import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Welcome step — the entry point of the wizard.
///
/// Detects whether the user already has equipment profiles. If they do
/// the step offers both "Skip onboarding" (mark dismissed, return to
/// dashboard) and "Run anyway" so the wizard never traps a returning
/// user. For new users with zero profiles the call-to-action is just
/// "Get started".
class OnboardingWelcomeStep extends ConsumerWidget {
  const OnboardingWelcomeStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);
    final profilesAsync = ref.watch(allProfilesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Icon(LucideIcons.sparkles,
                  color: colors.primary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome to Nightshade',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Let's get your rig set up. This takes about 2 minutes.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "What we'll cover",
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _bullet(theme, colors, LucideIcons.plug,
                  'Which device drivers to scan (ASCOM / INDI / Alpaca / Native)'),
              _bullet(theme, colors, LucideIcons.camera,
                  'Picking your camera, mount, focuser, filter wheel, and guider'),
              _bullet(theme, colors, LucideIcons.ruler,
                  'Optical train details: focal length, aperture, reducer'),
              _bullet(theme, colors, LucideIcons.folder,
                  'Where Nightshade will save captured images'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        profilesAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (profiles) {
            if (profiles.isEmpty) return const SizedBox.shrink();
            // Returning user — explain why the wizard appeared at all.
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, color: colors.warning, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You already have ${profiles.length} equipment profile'
                      '${profiles.length == 1 ? '' : 's'}. '
                      'Running the wizard will create a new one — your existing profiles are not modified.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _bullet(
    ThemeData theme,
    NightshadeColors colors,
    IconData icon,
    String text,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
