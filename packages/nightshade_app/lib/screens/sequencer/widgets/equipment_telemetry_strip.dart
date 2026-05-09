import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Compact telemetry strip shown below the toolbar during sequence execution.
/// Displays live device state: camera temp, focuser position, guiding RMS,
/// current filter, and mount tracking status.
class EquipmentTelemetryStrip extends ConsumerWidget {
  final NightshadeColors colors;

  const EquipmentTelemetryStrip({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);

    // Only show if at least one device is connected
    final hasAnyDevice =
        cameraState.connectionState == DeviceConnectionState.connected ||
        mountState.connectionState == DeviceConnectionState.connected ||
        focuserState.connectionState == DeviceConnectionState.connected ||
        filterWheelState.connectionState == DeviceConnectionState.connected ||
        guiderState.connectionState == DeviceConnectionState.connected;

    if (!hasAnyDevice) return const SizedBox.shrink();

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.activity, size: 12, color: colors.textMuted),
          const SizedBox(width: 8),
          Text(
            'TELEMETRY',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: colors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 16),
          _TelemetrySeparator(colors: colors),
          const SizedBox(width: 12),

          // Camera temperature
          if (cameraState.connectionState == DeviceConnectionState.connected)
            _TelemetryItem(
              colors: colors,
              icon: LucideIcons.thermometer,
              label: 'Cam',
              value: cameraState.temperature != null
                  ? '${cameraState.temperature!.toStringAsFixed(1)}\u00B0C'
                  : '--',
              valueColor: _tempColor(cameraState.temperature),
            ),

          // Focuser position
          if (focuserState.connectionState == DeviceConnectionState.connected)
            _TelemetryItem(
              colors: colors,
              icon: LucideIcons.focus,
              label: 'Focus',
              value: focuserState.position?.toString() ?? '--',
              valueColor: focuserState.isMoving ? colors.warning : null,
            ),

          // Current filter
          if (filterWheelState.connectionState == DeviceConnectionState.connected)
            _TelemetryItem(
              colors: colors,
              icon: LucideIcons.filter,
              label: 'Filter',
              value: filterWheelState.currentFilterName ?? 'Pos ${filterWheelState.currentPosition ?? '?'}',
              valueColor: filterWheelState.isMoving ? colors.warning : null,
            ),

          // Guiding RMS
          if (guiderState.connectionState == DeviceConnectionState.connected)
            _TelemetryItem(
              colors: colors,
              icon: LucideIcons.crosshair,
              label: 'RMS',
              value: guiderState.isGuiding
                  ? (guiderState.rmsTotal != null
                      ? '${guiderState.rmsTotal!.toStringAsFixed(2)}"'
                      : 'Guiding')
                  : 'Idle',
              valueColor: _guidingRmsColor(guiderState),
            ),

          // Mount tracking
          if (mountState.connectionState == DeviceConnectionState.connected)
            _TelemetryItem(
              colors: colors,
              icon: LucideIcons.locateFixed,
              label: 'Mount',
              value: mountState.isSlewing
                  ? 'Slewing'
                  : mountState.isTracking
                      ? 'Tracking'
                      : mountState.isParked
                          ? 'Parked'
                          : 'Idle',
              valueColor: mountState.isSlewing
                  ? colors.warning
                  : mountState.isTracking
                      ? colors.success
                      : mountState.isParked
                          ? colors.textMuted
                          : colors.error,
            ),

          const Spacer(),
        ],
      ),
    );
  }

  Color? _tempColor(double? temp) {
    if (temp == null) return null;
    if (temp < -5) return colors.info;
    if (temp > 25) return colors.warning;
    return null;
  }

  Color? _guidingRmsColor(GuiderState state) {
    if (!state.isGuiding) return colors.textMuted;
    if (state.isCalibrating) return colors.warning;
    final rms = state.rmsTotal;
    if (rms == null) return null;
    if (rms < 1.0) return colors.success;
    if (rms < 2.0) return colors.warning;
    return colors.error;
  }
}

class _TelemetryItem extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _TelemetryItem({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 10,
              color: colors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              color: valueColor ?? colors.textSecondary,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _TelemetrySeparator extends StatelessWidget {
  final NightshadeColors colors;

  const _TelemetrySeparator({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 16,
      color: colors.border,
    );
  }
}
