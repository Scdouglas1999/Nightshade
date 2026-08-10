import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Driver-selection step — the user picks which discovery backends to
/// scan. The set is persisted to the draft so the camera/mount/etc.
/// discovery steps later only spin up the chosen backends.
class OnboardingDriverStep extends ConsumerWidget {
  const OnboardingDriverStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
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

    // Scrollable: four driver tiles plus the ASCOM footnote exceed the wizard
    // body in a small window (and on a phone), and as a bare Column the surplus
    // overflowed instead of scrolling.
    return SingleChildScrollView(
      child: Column(
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
          ...displayOrder.where(available.contains).map((driver) => _DriverTile(
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
                  Icon(NightshadeIcons.info,
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
      ),
    );
  }
}

class _DriverTile extends StatefulWidget {
  const _DriverTile({
    required this.driver,
    required this.selected,
    required this.onToggle,
  });

  final DriverType driver;
  final bool selected;
  final VoidCallback onToggle;

  @override
  State<_DriverTile> createState() => _DriverTileState();
}

class _DriverTileState extends State<_DriverTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);
    final driver = widget.driver;
    final selected = widget.selected;
    final onToggle = widget.onToggle;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // One accessible node for the whole row, describing what it actually is.
      //
      // Read off the live accessibility tree (GUI drive 2026-08-09), every
      // driver row came out as:
      //
      //   panel: Native
      //   Direct SDK connection ... [DISABLED]
      //
      // — focusable, no checked state, and announced as not enabled, while the
      // row was in fact live and checked (clicking it toggled the box). Two
      // untruths at once: a screen-reader user is told there is nothing to
      // operate here, and is never told whether the driver is selected.
      //
      // The cause is that a bare `InkWell` publishes a tappable, focusable node
      // that never sets `isEnabled`, and its node shadows the
      // `NightshadeCheckbox`'s own correct `checked`/`enabled` semantics. The
      // checkbox is not at fault — it is simply not the node assistive tech
      // reaches. Declaring the container here, and excluding the now-duplicate
      // inner node, makes the row announce as "Native, <description>, checkbox,
      // checked" and leaves the pointer/keyboard behaviour untouched.
      child: Semantics(
        container: true,
        checked: selected,
        enabled: true,
        label: '${driver.shortLabel}. ${driver.description}',
        onTap: onToggle,
        child: InkWell(
          onTap: onToggle,
          // InkWell is focusable and Space already toggled the row, but its focus
          // highlight paints BEHIND the child, and this row's own opaque surface
          // decoration covers it — so a keyboard user tabbing through the driver
          // list saw nothing move and could not tell which row Space would toggle.
          // The ring is drawn on the row's own decoration, in front of the fill.
          onFocusChange: (value) {
            if (_focused == value) return;
            setState(() => _focused = value);
          },
          borderRadius: NightshadeTokens.borderRadiusLg,
          child: Container(
            foregroundDecoration: _focused
                ? BoxDecoration(
                    borderRadius: NightshadeTokens.borderRadiusLg,
                    border: Border.all(color: colors.primary, width: 2),
                  )
                : null,
            padding: const EdgeInsets.all(12),
            decoration: selected
                ? NightshadeDecorations.selectedSurface(
                    colors.primary,
                    borderRadius: NightshadeTokens.borderRadiusLg,
                    fillAlpha: 0.08,
                  )
                : BoxDecoration(
                    color: colors.surface,
                    borderRadius: NightshadeTokens.borderRadiusLg,
                    border: Border.all(color: colors.border),
                  ),
            child: ExcludeSemantics(
              // The row above carries the label, the checked state and the tap.
              // Leaving these in would make a screen reader read the driver name
              // twice and offer a second, competing tap target for the same
              // action.
              child: Row(
                children: [
                  NightshadeCheckbox(
                    value: selected,
                    onChanged: (_) => onToggle(),
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
        ),
      ),
    );
  }
}
