import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../localization/nightshade_localizations.dart';
import '../../../widgets/tutorial_keys/dashboard_keys.dart';
import '../dashboard_layout_provider.dart';

/// Why "Edit Dashboard" refuses in the standby briefing.
///
/// One string, used as the tooltip (pointer), the semantics hint (keyboard and
/// screen reader) and the toast (a click that lands on the disabled control's
/// row). A refusal the operator cannot read is indistinguishable from a broken
/// button.
const String standbyEditRefusalReason =
    'Nothing to arrange yet — the briefing has no tiles. Connect a device or '
    'load a sequence to arrange the session dashboard.';

/// The accessible NAME the refusing control publishes.
///
/// A `Semantics(hint:)` cannot carry the refusal. A widget test sees the hint
/// on the merged node, but the Linux accessibility bridge does not export it,
/// and a descendant re-publishes `isEnabled`, so the live AT-SPI node reads
/// `button: 'Edit Dashboard\nEdit Dashboard'  desc=''  states=['sensitive', …]`
/// — enabled, undescribed, byte-identical to the genuinely-enabled button.
///
/// So the refusal rides the one field the bridge demonstrably does export — the
/// name — and the button's own semantics are excluded so nothing underneath can
/// contradict the state. Anything that only *decorates* the node (hint,
/// tooltip, colour) is a bonus, never the disclosure.
String standbyEditSemanticLabel(String editLabel) =>
    '$editLabel, unavailable. $standbyEditRefusalReason';

class DashboardHeaderActions extends ConsumerWidget {
  final bool isEditing;
  final VoidCallback onToggleEdit;
  final VoidCallback onManageWidgets;
  final VoidCallback onResetLayout;
  final bool compact;

  const DashboardHeaderActions({
    super.key,
    required this.isEditing,
    required this.onToggleEdit,
    required this.onManageWidgets,
    required this.onResetLayout,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final buttonSize = compact ? ButtonSize.small : ButtonSize.medium;
    // The standby briefing is not made of arrangeable tiles, so offering to
    // edit it would swap the page for cockpit tiles that are not on it and
    // leave the visible dashboard unconfigurable.
    final canEdit = !ref.watch(dashboardStandbyProvider);
    final editLabel = l10n
        .text(isEditing ? 'dbDone' : (compact ? 'dbEdit' : 'dbEditDashboard'));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: canEdit ? '' : standbyEditRefusalReason,
          // `excludeSemantics` is the whole point of the second attempt: the
          // button publishes its own node (label + enabled), and a wrapper that
          // merely wraps it gets contradicted — the live probe read `sensitive`
          // on the refusing control and printed the label twice. Excluding the
          // subtree makes this the ONE node for the control, so its state and
          // its name are the only things exported.
          child: Semantics(
            button: true,
            enabled: canEdit,
            excludeSemantics: !canEdit,
            label: canEdit ? null : standbyEditSemanticLabel(editLabel),
            hint: canEdit ? null : standbyEditRefusalReason,
            // A pointer user gets the reason too, rather than a click that
            // lands on a dead control and produces nothing.
            //
            // `Listener`, not `GestureDetector`: NightshadeButton registers its
            // own tap recognizer even while disabled, so it wins the gesture
            // arena and a parent GestureDetector never fires. Pointer events
            // are delivered regardless of the arena.
            child: Listener(
              behavior: HitTestBehavior.deferToChild,
              onPointerDown: canEdit
                  ? null
                  : (_) => ref.read(uiNotificationProvider.notifier).showInfo(
                      standbyEditRefusalReason,
                      title: 'Nothing to arrange'),
              child: NightshadeButton(
                key: DashboardTutorialKeys.editButton,
                label: editLabel,
                icon:
                    isEditing ? LucideIcons.check : LucideIcons.layoutDashboard,
                variant:
                    isEditing ? ButtonVariant.primary : ButtonVariant.outline,
                size: buttonSize,
                onPressed: canEdit ? onToggleEdit : null,
              ),
            ),
          ),
        ),
        if (isEditing) ...[
          SizedBox(width: compact ? 4 : 8),
          NightshadeButton(
            label: compact ? '' : l10n.text('dbWidgets'),
            icon: LucideIcons.layoutGrid,
            variant: ButtonVariant.outline,
            size: buttonSize,
            onPressed: onManageWidgets,
          ),
          SizedBox(width: compact ? 4 : 8),
          NightshadeButton(
            label: compact ? '' : l10n.text('dbReset'),
            icon: LucideIcons.refreshCw,
            variant: ButtonVariant.outline,
            size: buttonSize,
            onPressed: onResetLayout,
          ),
        ],
      ],
    );
  }
}

class EditModeBanner extends StatelessWidget {
  final NightshadeColors colors;

  const EditModeBanner({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: NightshadeDecorations.emphasisSurface(
        colors.primary,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.grip, size: 16, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.text('dbEditModeHint'),
              style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
