import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'run_dashboard/run_dashboard_format.dart';

/// Compact telemetry strip showing live device state: camera temperature,
/// focuser position, guiding RMS, current filter, and mount tracking
/// status.
///
/// Renders in two layouts driven by [direction]:
///
///   * [Axis.horizontal] (default): the 32 px-tall strip below the
///     sequencer toolbar that originally lived in this file. Each
///     telemetry item is rendered as an icon + label + value pair laid
///     out left to right with separators.
///   * [Axis.vertical]: a card with per-device blocks stacked top-down.
///     Used by the Run Dashboard's left column (and replaces the parallel
///     hand-formatted equipment panel that previously duplicated this
///     logic). Vertical layout renders more per-device detail (RA/Dec,
///     side-of-pier, cooler power, etc.) because the dashboard has
///     vertical real-estate the toolbar strip does not.
///
/// Both layouts read the same Riverpod providers, so they always agree.
class EquipmentTelemetryStrip extends ConsumerWidget {
  final NightshadeColors colors;
  final Axis direction;

  const EquipmentTelemetryStrip({
    super.key,
    required this.colors,
    this.direction = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final rotatorState = ref.watch(rotatorStateProvider);
    final afResult = ref.watch(autofocusResultProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);

    final hasAnyDevice =
        cameraState.connectionState == DeviceConnectionState.connected ||
            mountState.connectionState == DeviceConnectionState.connected ||
            focuserState.connectionState ==
                DeviceConnectionState.connected ||
            filterWheelState.connectionState ==
                DeviceConnectionState.connected ||
            rotatorState.connectionState == DeviceConnectionState.connected ||
            guiderState.connectionState == DeviceConnectionState.connected;

    if (direction == Axis.vertical) {
      return _VerticalLayout(
        colors: colors,
        camera: cameraState,
        mount: mountState,
        focuser: focuserState,
        filterWheel: filterWheelState,
        guider: guiderState,
        rotator: rotatorState,
        afResult: afResult,
        exposureProgress: exposureProgress,
        hasAnyDevice: hasAnyDevice,
      );
    }

    // Original horizontal strip — preserved verbatim so existing
    // callers continue to render identical pixels.
    if (!hasAnyDevice) return const SizedBox.shrink();
    return _HorizontalStrip(
      colors: colors,
      camera: cameraState,
      mount: mountState,
      focuser: focuserState,
      filterWheel: filterWheelState,
      guider: guiderState,
    );
  }
}

class _HorizontalStrip extends StatelessWidget {
  final NightshadeColors colors;
  final CameraStateSnapshot camera;
  final MountState mount;
  final FocuserState focuser;
  final FilterWheelState filterWheel;
  final GuiderState guider;

  const _HorizontalStrip({
    required this.colors,
    required this.camera,
    required this.mount,
    required this.focuser,
    required this.filterWheel,
    required this.guider,
  });

  @override
  Widget build(BuildContext context) {
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
          if (camera.connectionState == DeviceConnectionState.connected)
            _TelemetryItem(
              colors: colors,
              icon: LucideIcons.thermometer,
              label: 'Cam',
              value: camera.temperature != null
                  ? '${camera.temperature!.toStringAsFixed(1)}°C'
                  : '--',
              valueColor: _tempColor(camera.temperature, colors),
            ),
          if (focuser.connectionState == DeviceConnectionState.connected)
            _TelemetryItem(
              colors: colors,
              icon: LucideIcons.focus,
              label: 'Focus',
              value: focuser.position?.toString() ?? '--',
              valueColor: focuser.isMoving ? colors.warning : null,
            ),
          if (filterWheel.connectionState == DeviceConnectionState.connected)
            _TelemetryItem(
              colors: colors,
              icon: LucideIcons.filter,
              label: 'Filter',
              value: filterWheel.currentFilterName ??
                  'Pos ${filterWheel.currentPosition ?? '?'}',
              valueColor: filterWheel.isMoving ? colors.warning : null,
            ),
          if (guider.connectionState == DeviceConnectionState.connected)
            _TelemetryItem(
              colors: colors,
              icon: LucideIcons.crosshair,
              label: 'RMS',
              value: guider.isGuiding
                  ? (guider.rmsTotal != null
                      ? '${guider.rmsTotal!.toStringAsFixed(2)}"'
                      : 'Guiding')
                  : 'Idle',
              valueColor: _guidingRmsColor(guider, colors),
            ),
          if (mount.connectionState == DeviceConnectionState.connected)
            _TelemetryItem(
              colors: colors,
              icon: LucideIcons.locateFixed,
              label: 'Mount',
              value: mount.isSlewing
                  ? 'Slewing'
                  : mount.isTracking
                      ? 'Tracking'
                      : mount.isParked
                          ? 'Parked'
                          : 'Idle',
              valueColor: mount.isSlewing
                  ? colors.warning
                  : mount.isTracking
                      ? colors.success
                      : mount.isParked
                          ? colors.textMuted
                          : colors.error,
            ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _VerticalLayout extends StatelessWidget {
  final NightshadeColors colors;
  final CameraStateSnapshot camera;
  final MountState mount;
  final FocuserState focuser;
  final FilterWheelState filterWheel;
  final GuiderState guider;
  final RotatorState rotator;
  final AutofocusResult? afResult;
  final ExposureProgress exposureProgress;
  final bool hasAnyDevice;

  const _VerticalLayout({
    required this.colors,
    required this.camera,
    required this.mount,
    required this.focuser,
    required this.filterWheel,
    required this.guider,
    required this.rotator,
    required this.afResult,
    required this.exposureProgress,
    required this.hasAnyDevice,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[
      if (camera.connectionState == DeviceConnectionState.connected)
        _DeviceBlock(
          colors: colors,
          icon: LucideIcons.camera,
          name: 'Camera',
          deviceName: camera.deviceName,
          statusText: camera.isExposing ? 'Exposing' : 'Idle',
          statusColor:
              camera.isExposing ? colors.success : colors.textSecondary,
          rows: [
            if (camera.temperature != null)
              _TelemetryRow(
                colors: colors,
                label: 'Sensor',
                value: '${camera.temperature!.toStringAsFixed(1)}°C',
                valueColor: _tempColor(camera.temperature, colors),
              ),
            if (camera.coolerPower != null)
              _TelemetryRow(
                colors: colors,
                label: 'Cooler',
                value: '${camera.coolerPower!.toStringAsFixed(0)}%',
              ),
            if (camera.isExposing && exposureProgress.remaining > 0)
              _TelemetryRow(
                colors: colors,
                label: 'Remaining',
                value: formatSeconds(exposureProgress.remaining),
                valueColor: colors.primary,
              ),
          ],
        ),
      if (mount.connectionState == DeviceConnectionState.connected)
        _DeviceBlock(
          colors: colors,
          icon: LucideIcons.compass,
          name: 'Mount',
          deviceName: mount.deviceName,
          statusText: mount.isSlewing
              ? 'Slewing'
              : mount.isTracking
                  ? 'Tracking'
                  : mount.isParked
                      ? 'Parked'
                      : 'Idle',
          statusColor: mount.isSlewing
              ? colors.warning
              : mount.isTracking
                  ? colors.success
                  : mount.isParked
                      ? colors.textMuted
                      : colors.error,
          rows: [
            if (mount.ra != null && mount.dec != null) ...[
              _TelemetryRow(
                colors: colors,
                label: 'RA',
                value: formatRA(mount.ra!),
              ),
              _TelemetryRow(
                colors: colors,
                label: 'Dec',
                value: formatDec(mount.dec!),
              ),
            ],
            if (mount.altitude != null)
              _TelemetryRow(
                colors: colors,
                label: 'Alt',
                value: '${mount.altitude!.toStringAsFixed(1)}°',
              ),
            if (mount.sideOfPier != null && mount.sideOfPier!.isNotEmpty)
              _TelemetryRow(
                colors: colors,
                label: 'Pier',
                value: mount.sideOfPier!,
              ),
          ],
        ),
      if (focuser.connectionState == DeviceConnectionState.connected)
        _DeviceBlock(
          colors: colors,
          icon: LucideIcons.focus,
          name: 'Focuser',
          deviceName: focuser.deviceName,
          statusText: focuser.isMoving ? 'Moving' : 'Idle',
          statusColor:
              focuser.isMoving ? colors.warning : colors.textSecondary,
          rows: [
            if (focuser.position != null)
              _TelemetryRow(
                colors: colors,
                label: 'Position',
                value: focuser.position.toString(),
              ),
            if (focuser.temperature != null)
              _TelemetryRow(
                colors: colors,
                label: 'Temp',
                value: '${focuser.temperature!.toStringAsFixed(1)}°C',
              ),
            if (afResult != null)
              _TelemetryRow(
                colors: colors,
                label: 'Last AF HFR',
                value: afResult!.bestHfr.toStringAsFixed(2),
                valueColor: colors.primary,
              ),
          ],
        ),
      if (filterWheel.connectionState == DeviceConnectionState.connected)
        _DeviceBlock(
          colors: colors,
          icon: LucideIcons.filter,
          name: 'Filter wheel',
          deviceName: filterWheel.deviceName,
          statusText: filterWheel.isMoving ? 'Changing' : 'Ready',
          statusColor: filterWheel.isMoving
              ? colors.warning
              : colors.textSecondary,
          rows: [
            _TelemetryRow(
              colors: colors,
              label: 'Filter',
              value: filterWheel.currentFilterName ??
                  'Pos ${filterWheel.currentPosition ?? '?'}',
              valueColor: colors.primary,
            ),
          ],
        ),
      if (rotator.connectionState == DeviceConnectionState.connected)
        _DeviceBlock(
          colors: colors,
          icon: LucideIcons.rotateCw,
          name: 'Rotator',
          deviceName: rotator.deviceName,
          statusText: rotator.isMoving ? 'Rotating' : 'Idle',
          statusColor:
              rotator.isMoving ? colors.warning : colors.textSecondary,
          rows: [
            if (rotator.position != null)
              _TelemetryRow(
                colors: colors,
                label: 'Angle',
                value: '${rotator.position!.toStringAsFixed(2)}°',
              ),
          ],
        ),
      if (guider.connectionState == DeviceConnectionState.connected)
        _DeviceBlock(
          colors: colors,
          icon: LucideIcons.crosshair,
          name: 'Guider',
          deviceName: guider.deviceName,
          statusText: guider.isCalibrating
              ? 'Calibrating'
              : guider.isGuiding
                  ? 'Guiding'
                  : 'Idle',
          statusColor: guider.isCalibrating
              ? colors.warning
              : guider.isGuiding
                  ? colors.success
                  : colors.textMuted,
          rows: [
            if (guider.rmsTotal != null)
              _TelemetryRow(
                colors: colors,
                label: 'RMS Tot',
                value: '${guider.rmsTotal!.toStringAsFixed(2)}"',
                valueColor: _guidingRmsColor(guider, colors),
              ),
            if (guider.rmsRa != null)
              _TelemetryRow(
                colors: colors,
                label: 'RMS RA',
                value: '${guider.rmsRa!.toStringAsFixed(2)}"',
              ),
            if (guider.rmsDec != null)
              _TelemetryRow(
                colors: colors,
                label: 'RMS Dec',
                value: '${guider.rmsDec!.toStringAsFixed(2)}"',
              ),
          ],
        ),
    ];

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.activity, size: 14, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Equipment',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          if (blocks.isEmpty)
            Text(
              'No equipment connected',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            )
          else
            for (var i = 0; i < blocks.length; i++) ...[
              blocks[i],
              if (i < blocks.length - 1)
                const SizedBox(height: NightshadeTokens.spaceMd),
            ],
        ],
      ),
    );
  }
}

Color? _tempColor(double? temp, NightshadeColors colors) {
  if (temp == null) return null;
  if (temp < -5) return colors.info;
  if (temp > 25) return colors.warning;
  return null;
}

Color? _guidingRmsColor(GuiderState state, NightshadeColors colors) {
  if (!state.isGuiding) return colors.textMuted;
  if (state.isCalibrating) return colors.warning;
  final rms = state.rmsTotal;
  if (rms == null) return null;
  if (rms < 1.0) return colors.success;
  if (rms < 2.0) return colors.warning;
  return colors.error;
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

class _DeviceBlock extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String name;
  final String? deviceName;
  final String statusText;
  final Color statusColor;
  final List<_TelemetryRow> rows;

  const _DeviceBlock({
    required this.colors,
    required this.icon,
    required this.name,
    required this.deviceName,
    required this.statusText,
    required this.statusColor,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: colors.textSecondary),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusXs),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        if (deviceName != null && deviceName!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            deviceName!,
            style: TextStyle(
              fontSize: 10,
              color: colors.textMuted,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (rows.isNotEmpty) ...[
          const SizedBox(height: NightshadeTokens.spaceSm),
          ...rows,
        ],
      ],
    );
  }
}

class _TelemetryRow extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;
  final Color? valueColor;

  const _TelemetryRow({
    required this.colors,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colors.textMuted,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor ?? colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
