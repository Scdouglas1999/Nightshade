import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Driver-selection step — the user picks which discovery backends to
/// scan. The set is persisted to the draft so the camera/mount/etc.
/// discovery steps later only spin up the chosen backends.
class OnboardingDriverStep extends ConsumerWidget {
  const OnboardingDriverStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);
    final draft = ref.watch(onboardingDraftProvider);
    final notifier = ref.read(onboardingDraftProvider.notifier);
    final available = ref.watch(availableOnboardingDriversProvider);

    // Preserve a stable rendering order so the chip layout is identical
    // between platforms and across launches.
    const displayOrder = [
      DriverType.native,
      DriverType.ascom,
      DriverType.alpaca,
      DriverType.indi,
      DriverType.simulator,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Which drivers should we scan?',
          style: theme.textTheme.titleLarge?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Pick everything that applies to your setup. You can change this later.",
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        ...displayOrder
            .where(available.contains)
            .map((driver) => _DriverTile(
                  driver: driver,
                  selected: draft.selectedDrivers.contains(driver),
                  onToggle: () => notifier.toggleDriver(driver),
                )),
        const SizedBox(height: 12),
        if (!available.contains(DriverType.ascom))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(LucideIcons.info,
                    size: 14, color: colors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ASCOM COM drivers are Windows-only. Use Alpaca to reach an ASCOM server from this platform.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DriverTile extends StatelessWidget {
  const _DriverTile({
    required this.driver,
    required this.selected,
    required this.onToggle,
  });

  final DriverType driver;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: 0.08)
                : colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? colors.primary.withValues(alpha: 0.4)
                  : colors.border,
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (_) => onToggle(),
                activeColor: colors.primary,
                side: BorderSide(color: colors.border),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver.shortLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      driver.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
