import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../localization/nightshade_localizations.dart';
import '../../../services/mount_command_service.dart';
import 'glass_card.dart';

class MountControlCard extends ConsumerWidget {
  final NightshadeColors colors;

  const MountControlCard({super.key, required this.colors});

  static const double _expandedThreshold = 280.0;

  String _formatRa(double ra) {
    final hours = ra.floor();
    final minutes = ((ra - hours) * 60).floor();
    final seconds = (((ra - hours) * 60 - minutes) * 60).round();
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDec(double dec) {
    final sign = dec >= 0 ? '+' : '-';
    final absDec = dec.abs();
    final degrees = absDec.floor();
    final minutes = ((absDec - degrees) * 60).floor();
    final seconds = (((absDec - degrees) * 60 - minutes) * 60).round();
    return '$sign${degrees.toString().padLeft(2, '0')}°${minutes.toString().padLeft(2, '0')}\'${seconds.toString().padLeft(2, '0')}"';
  }

  String _trackingRateLabel(TrackingRate rate) {
    return switch (rate) {
      TrackingRate.sidereal => 'Sidereal',
      TrackingRate.lunar => 'Lunar',
      TrackingRate.solar => 'Solar',
      TrackingRate.king => 'King',
      TrackingRate.custom => 'Custom',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final mountState = ref.watch(mountStateProvider);
    final isConnected = mountState.connectionState == DeviceConnectionState.connected;

    final raText = mountState.ra != null ? _formatRa(mountState.ra!) : '---';
    final decText = mountState.dec != null ? _formatDec(mountState.dec!) : '---';
    final pierText = isConnected ? (mountState.sideOfPier?.toUpperCase() ?? '---') : '---';

    // Status with color
    final (statusText, statusColor) = mountState.isSlewing
        ? (l10n.text('slewing'), colors.warning)
        : mountState.isParked
            ? (l10n.text('parked'), colors.textMuted)
            : mountState.isTracking
                ? (l10n.text('tracking'), colors.success)
                : isConnected
                    ? (l10n.text('idle'), colors.textSecondary)
                    : (l10n.text('off'), colors.textMuted);

    return DashboardGlassCard(
      colors: colors,
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isExpanded = constraints.maxWidth >= _expandedThreshold;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: mountState.isTracking ? colors.success.withValues(alpha: 0.1) : colors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      LucideIcons.move3d,
                      size: 14,
                      color: mountState.isTracking ? colors.success : colors.info,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(l10n.text('mount'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Coordinates - NINA style
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.text('ra'), style: TextStyle(fontSize: 9, color: colors.textMuted)),
                          Text(raText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary, fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.text('dec'), style: TextStyle(fontSize: 9, color: colors.textMuted)),
                          Text(decText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary, fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(l10n.text('pier'), style: TextStyle(fontSize: 9, color: colors.textMuted)),
                        Text(pierText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                      ],
                    ),
                  ],
                ),
              ),

              // Expanded mode: Directional controls and tracking rate
              if (isExpanded && isConnected) ...[
                const SizedBox(height: 10),

                // Directional jog controls (N/S/E/W)
                _MountDirectionalPad(
                  colors: colors,
                  isEnabled: isConnected && !mountState.isParked,
                  onDirection: (direction) {
                    ref.read(mountCommandServiceProvider).pulseGuide(direction);
                  },
                ),

                const SizedBox(height: 10),

                // Tracking rate selector
                Row(
                  children: [
                    Text('${l10n.text('rate')}:', style: TextStyle(fontSize: 10, color: colors.textMuted)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.border.withValues(alpha: 0.5)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<TrackingRate>(
                            value: mountState.trackingRate,
                            isDense: true,
                            isExpanded: true,
                            style: TextStyle(fontSize: 11, color: colors.textPrimary),
                            dropdownColor: colors.surface,
                            icon: Icon(LucideIcons.chevronDown, size: 12, color: colors.textMuted),
                            items: TrackingRate.values.map((rate) => DropdownMenuItem(
                              value: rate,
                              child: Text(_trackingRateLabel(rate)),
                            )).toList(),
                            onChanged: mountState.canSetTrackingRate
                                ? (rate) {
                                    if (rate != null) {
                                      ref.read(deviceServiceProvider).setMountTrackingRate(rate.index);
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 8),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: NightshadeButton(
                      label: mountState.isParked ? l10n.text('unpark') : l10n.text('park'),
                      icon: LucideIcons.parkingCircle,
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: isConnected ? () => ref.read(mountCommandServiceProvider).togglePark() : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: NightshadeButton(
                      label: mountState.isTracking ? l10n.text('stop') : l10n.text('track'),
                      icon: LucideIcons.activity,
                      variant: mountState.isTracking ? ButtonVariant.primary : ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: isConnected ? () => ref.read(mountCommandServiceProvider).toggleTracking() : null,
                    ),
                  ),
                ],
              ),
              if (mountState.isSlewing) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: NightshadeButton(
                    label: l10n.text('abortSlew'),
                    icon: LucideIcons.xCircle,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed: isConnected ? () => ref.read(mountCommandServiceProvider).abortSlew() : null,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Directional pad for mount jog controls (N/S/E/W).
class _MountDirectionalPad extends StatelessWidget {
  final NightshadeColors colors;
  final bool isEnabled;
  final void Function(String direction) onDirection;

  const _MountDirectionalPad({
    required this.colors,
    required this.isEnabled,
    required this.onDirection,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // West button
          _DirectionalButton(
            icon: LucideIcons.chevronLeft,
            label: 'W',
            colors: colors,
            isEnabled: isEnabled,
            onPressed: () => onDirection('west'),
          ),
          const SizedBox(width: 2),
          // Column with North and South
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DirectionalButton(
                icon: LucideIcons.chevronUp,
                label: 'N',
                colors: colors,
                isEnabled: isEnabled,
                onPressed: () => onDirection('north'),
              ),
              const SizedBox(height: 2),
              _DirectionalButton(
                icon: LucideIcons.chevronDown,
                label: 'S',
                colors: colors,
                isEnabled: isEnabled,
                onPressed: () => onDirection('south'),
              ),
            ],
          ),
          const SizedBox(width: 2),
          // East button
          _DirectionalButton(
            icon: LucideIcons.chevronRight,
            label: 'E',
            colors: colors,
            isEnabled: isEnabled,
            onPressed: () => onDirection('east'),
          ),
        ],
      ),
    );
  }
}

/// Individual directional button for mount jog.
class _DirectionalButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;
  final bool isEnabled;
  final VoidCallback onPressed;

  const _DirectionalButton({
    required this.icon,
    required this.label,
    required this.colors,
    required this.isEnabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: isEnabled ? onPressed : null,
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              icon,
              size: 16,
              color: isEnabled ? colors.textPrimary : colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
