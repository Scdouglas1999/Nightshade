import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import 'glass_card.dart';

class EquipmentStatusCard extends ConsumerWidget {
  final NightshadeColors colors;

  const EquipmentStatusCard({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use select() to only rebuild when connection state changes
    final cameraConnected = ref.watch(cameraStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final mountConnected = ref.watch(mountStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final guiderConnected = ref.watch(guiderStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final focuserConnected = ref.watch(focuserStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final filterWheelConnected = ref.watch(filterWheelStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;

    final connectedCount = [cameraConnected, mountConnected, guiderConnected, focuserConnected, filterWheelConnected]
        .where((c) => c).length;

    return DashboardGlassCard(
      colors: colors,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          Row(
            children: [
              Icon(
                LucideIcons.plug,
                size: 14,
                color: connectedCount > 0 ? colors.success : colors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                'Equipment',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '$connectedCount/5',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: connectedCount == 5 ? colors.success : colors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.go('/equipment'),
                child: Text(
                  'Manage',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colors.accent,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Compact horizontal icon row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: colors.surfaceAlt.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CompactEquipmentIcon(
                  icon: LucideIcons.camera,
                  label: 'Cam',
                  isConnected: cameraConnected,
                  colors: colors,
                ),
                _CompactEquipmentIcon(
                  icon: LucideIcons.move3d,
                  label: 'Mnt',
                  isConnected: mountConnected,
                  colors: colors,
                ),
                _CompactEquipmentIcon(
                  icon: LucideIcons.crosshair,
                  label: 'Gdr',
                  isConnected: guiderConnected,
                  colors: colors,
                ),
                _CompactEquipmentIcon(
                  icon: LucideIcons.focus,
                  label: 'Foc',
                  isConnected: focuserConnected,
                  colors: colors,
                ),
                _CompactEquipmentIcon(
                  icon: LucideIcons.circle,
                  label: 'FW',
                  isConnected: filterWheelConnected,
                  colors: colors,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact equipment status icon for horizontal display
class _CompactEquipmentIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isConnected;
  final NightshadeColors colors;

  const _CompactEquipmentIcon({
    required this.icon,
    required this.label,
    required this.isConnected,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$label: ${isConnected ? "Connected" : "Disconnected"}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isConnected
                  ? colors.success.withValues(alpha: 0.15)
                  : colors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isConnected ? colors.success.withValues(alpha: 0.3) : colors.border,
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              size: 14,
              color: isConnected ? colors.success : colors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              color: isConnected ? colors.textSecondary : colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
