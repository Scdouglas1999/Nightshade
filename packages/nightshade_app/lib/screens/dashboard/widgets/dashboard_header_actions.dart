import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../../widgets/tutorial_keys/dashboard_keys.dart';

class DashboardHeaderActions extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final buttonSize = compact ? ButtonSize.small : ButtonSize.medium;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NightshadeButton(
          key: DashboardTutorialKeys.editButton,
          label: isEditing ? 'Done' : (compact ? 'Edit' : 'Edit Dashboard'),
          icon: isEditing ? LucideIcons.check : LucideIcons.layoutDashboard,
          variant: isEditing ? ButtonVariant.primary : ButtonVariant.outline,
          size: buttonSize,
          onPressed: onToggleEdit,
        ),
        if (isEditing) ...[
          SizedBox(width: compact ? 4 : 8),
          NightshadeButton(
            label: compact ? '' : 'Widgets',
            icon: LucideIcons.layoutGrid,
            variant: ButtonVariant.outline,
            size: buttonSize,
            onPressed: onManageWidgets,
          ),
          SizedBox(width: compact ? 4 : 8),
          NightshadeButton(
            label: compact ? '' : 'Reset',
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

class DashboardClockWidget extends ConsumerWidget {
  final NightshadeColors colors;

  const DashboardClockWidget({super.key, required this.colors});

  String _formatLST(double lstHours) {
    final h = lstHours.floor();
    final m = ((lstHours - h) * 60).floor();
    final s = (((lstHours - h) * 60 - m) * 60).floor();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the observationTimeProvider for both local time and LST
    // This provider already updates every second, no need for a separate timer
    final timeState = ref.watch(observationTimeProvider);
    final now = timeState.time;
    final lst = ref.watch(localSiderealTimeProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primary.withValues(alpha: 0.15),
            colors.accent.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.clock, size: 16, color: colors.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                'LST ${_formatLST(lst)}',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
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
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.grip, size: 16, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Edit mode: long-press the grip handle to drag and reorder tiles.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
