import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'run_dashboard_prefs.dart';

/// Top-right "Customize" affordance for the Run dashboard. Opens a popup
/// menu listing every panel with a checkbox-style toggle; persists via
/// `runDashboardPrefsProvider`.
class RunDashboardCustomizeMenu extends ConsumerWidget {
  const RunDashboardCustomizeMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final prefsAsync = ref.watch(runDashboardPrefsProvider);

    // While prefs are loading we still allow the menu to open (the
    // defaults will be returned by the notifier).
    final prefs = prefsAsync.valueOrNull ?? RunDashboardPrefs.defaults();

    return PopupMenuButton<_CustomizeAction>(
      tooltip: 'Customize dashboard',
      icon: Icon(
        LucideIcons.sliders,
        size: 18,
        color: colors.textSecondary,
      ),
      onSelected: (action) async {
        final notifier = ref.read(runDashboardPrefsProvider.notifier);
        if (action.isReset) {
          await notifier.resetToDefaults();
          return;
        }
        if (action.panelId == null) return;
        await notifier.setVisible(
          action.panelId!,
          !prefs.isVisible(action.panelId!),
        );
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<_CustomizeAction>>[
          PopupMenuItem<_CustomizeAction>(
            enabled: false,
            child: Row(
              children: [
                Icon(LucideIcons.sliders,
                    size: 14, color: colors.textMuted),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Text(
                  'Show / hide panels',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
        ];

        for (final desc in runDashboardPanelDescriptors) {
          final visible = prefs.isVisible(desc.id);
          items.add(
            PopupMenuItem<_CustomizeAction>(
              value: _CustomizeAction.toggle(desc.id),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: visible
                        ? Icon(LucideIcons.check,
                            size: 16, color: colors.primary)
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          desc.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          desc.description,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        items.add(const PopupMenuDivider());
        items.add(
          PopupMenuItem<_CustomizeAction>(
            value: const _CustomizeAction.reset(),
            child: Row(
              children: [
                Icon(LucideIcons.rotateCcw,
                    size: 14, color: colors.textSecondary),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Text(
                  'Reset to defaults',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
        return items;
      },
    );
  }
}

class _CustomizeAction {
  final RunDashboardPanelId? panelId;
  final bool isReset;

  const _CustomizeAction.toggle(this.panelId) : isReset = false;
  const _CustomizeAction.reset()
      : panelId = null,
        isReset = true;
}
