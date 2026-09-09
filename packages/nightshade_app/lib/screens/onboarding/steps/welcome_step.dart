import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Welcome step — the entry point of the wizard.
///
/// Detects whether the user already has equipment profiles. If they do
/// the step says so in one banner so a returning user knows why the wizard
/// appeared; the wizard's own "Skip onboarding" action is in the page header.
class OnboardingWelcomeStep extends ConsumerWidget {
  const OnboardingWelcomeStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final profilesAsync = ref.watch(allProfilesProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            icon: NightshadeIcons.sparkle,
            title: 'Welcome to Nightshade',
          ),
          Text(
            // No stopwatch promise: the run is gated on device discovery
            // finding your gear, and "about 2 minutes" was a specific number
            // nothing measured.
            "Let's get your rig set up. You can leave and pick this back up at "
            'any point.',
            style: NightshadeTypography.bodySm.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          Container(
            decoration: NightshadeDecorations.well(colors),
            padding: NightshadeTokens.paddingMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "What we'll cover".toUpperCase(),
                  style: NightshadeTypography.eyebrow.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: NightshadeTokens.spaceMd),
                _bullet(
                  colors,
                  NightshadeIcons.connected,
                  'Which device drivers to scan (ASCOM / INDI / Alpaca / '
                  'Native)',
                ),
                _bullet(
                  colors,
                  NightshadeIcons.camera,
                  'Picking your camera, mount, focuser, filter wheel, and '
                  'guider',
                ),
                _bullet(
                  colors,
                  LucideIcons.ruler,
                  'Optical train details: focal length, aperture, reducer',
                ),
                // The list has to name every step that follows, or the wizard
                // asks for things it said it would not — the observing site in
                // particular is written to global settings, not just the
                // profile.
                _bullet(
                  colors,
                  NightshadeIcons.sliders,
                  'Capture defaults: gain, offset, binning, cooling',
                ),
                _bullet(
                  colors,
                  NightshadeIcons.folder,
                  'Where Nightshade will save captured images',
                ),
                _bullet(
                  colors,
                  LucideIcons.mapPin,
                  'Where you observe from (optional, powers Tonight and the '
                  'planner)',
                ),
              ],
            ),
          ),
          profilesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (profiles) {
              if (profiles.isEmpty) return const SizedBox.shrink();
              // Returning user — explain why the wizard appeared at all.
              return Padding(
                padding: const EdgeInsets.only(top: NightshadeTokens.spaceLg),
                child: NightshadeBanner(
                  tone: BannerTone.warning,
                  title: 'You already have ${profiles.length} equipment '
                      'profile${profiles.length == 1 ? '' : 's'}.',
                  message: 'Running the wizard creates a new one; the '
                      'existing profiles are not modified.',
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _bullet(NightshadeColors colors, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.textMuted, size: NightshadeTokens.iconSm),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Text(
              text,
              style: NightshadeTypography.bodySm.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
