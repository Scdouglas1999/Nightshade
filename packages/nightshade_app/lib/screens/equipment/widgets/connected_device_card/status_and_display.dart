part of '../connected_device_card.dart';

extension _ConnectedDeviceStatusAndDisplay on _ConnectedDeviceCardState {
  DeviceConnectionState _getConnectionState() {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        return ref.watch(cameraStateProvider).connectionState;
      case ConnectedDeviceType.mount:
        return ref.watch(mountStateProvider).connectionState;
      case ConnectedDeviceType.focuser:
        return ref.watch(focuserStateProvider).connectionState;
      case ConnectedDeviceType.filterWheel:
        return ref.watch(filterWheelStateProvider).connectionState;
      case ConnectedDeviceType.guider:
        return ref.watch(guiderStateProvider).connectionState;
      case ConnectedDeviceType.rotator:
        return ref.watch(rotatorStateProvider).connectionState;
      case ConnectedDeviceType.dome:
        return ref.watch(domeStateProvider).connectionState;
      case ConnectedDeviceType.weather:
        return ref.watch(weatherStateProvider).connectionState;
      case ConnectedDeviceType.safetyMonitor:
        return ref.watch(safetyMonitorStateProvider).connectionState;
      case ConnectedDeviceType.coverCalibrator:
        return ref.watch(coverCalibratorStateProvider).connectionState;
    }
  }

  Color _getBorderColor(DeviceConnectionState state, NightshadeColors colors) {
    switch (state) {
      case DeviceConnectionState.connected:
        return colors.success;
      case DeviceConnectionState.connecting:
        return colors.warning;
      case DeviceConnectionState.error:
        return colors.error;
      case DeviceConnectionState.disconnected:
        return colors.border;
    }
  }

  /// Header icon tint — never use category [accentColor] when disconnected.
  /// Safety-monitor accent is `colors.success`, which would read as "connected"
  /// if we fell back to accent (audit §4.22).
  Color _iconColorForState(
      DeviceConnectionState state, NightshadeColors colors) {
    return switch (state) {
      DeviceConnectionState.connected => colors.success,
      DeviceConnectionState.connecting => colors.warning,
      DeviceConnectionState.error => colors.error,
      DeviceConnectionState.disconnected => colors.textSecondary,
    };
  }

  Widget _buildHeader(
      NightshadeColors colors, Color accentColor, DeviceConnectionState state) {
    final deviceName = _getDeviceName();

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: NightshadeDecorations.iconChip(
            accentColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            widget.type.icon,
            size: 18,
            color: _iconColorForState(state, colors),
          ),
        ),

        const SizedBox(width: 12),

        // Device type and name
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.type.displayName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                deviceName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        // Connection badge
        _buildConnectionBadge(state, colors),
      ],
    );
  }

  /// Onboarding C4: when the device is in an error state, render a full-width
  /// row beneath the header that surfaces the same plain-language headline the
  /// troubleshooter dialog uses (via [DeviceErrorSubtitle]), with the raw driver
  /// message carried verbatim in the tooltip and a Diagnose button that opens
  /// the full [ConnectionTroubleshooterDialog]. Returns
  /// [SizedBox.shrink] when the device is healthy so the card keeps its compact
  /// layout. Placed as its own full-width row (not inside the header's narrow
  /// name column) so the headline and the Diagnose affordance have room to sit
  /// side by side without crowding the connection badge.
  Widget _buildErrorSubtitle(
      NightshadeColors colors, DeviceConnectionState state) {
    if (state != DeviceConnectionState.error) {
      return const SizedBox.shrink();
    }
    final errorMessage = _getDeviceError()?.message;
    if (errorMessage == null || errorMessage.isEmpty) {
      return const SizedBox.shrink();
    }
    final deviceId = _getDeviceId();
    return Padding(
      padding: const EdgeInsets.only(top: NightshadeTokens.spaceSm),
      child: DeviceErrorSubtitle(
        descriptiveSubtitle: '',
        isError: true,
        errorMessage: errorMessage,
        deviceType: widget.type.coreDeviceType,
        driverType: driverTypeFromDeviceId(deviceId) ?? DriverType.native,
        colors: colors,
        onDiagnose: () => _openTroubleshooter(
          deviceId: deviceId,
          rawError: errorMessage,
        ),
      ),
    );
  }

  /// Opens the guided [ConnectionTroubleshooterDialog] for this device,
  /// classifying the failure with the same knowledge base that powers the
  /// inline [DeviceErrorSubtitle] headline. The raw driver string is carried
  /// through verbatim (errors-are-a-feature). If the user chooses "Retry
  /// connection", the device's connect is re-attempted exactly once through the
  /// device service.
  Future<void> _openTroubleshooter({
    required String? deviceId,
    required String rawError,
  }) async {
    final retry = await ConnectionTroubleshooterDialog.show(
      context,
      deviceType: widget.type.coreDeviceType,
      driverType: driverTypeFromDeviceId(deviceId) ?? DriverType.native,
      rawError: rawError,
    );
    if (!retry || !mounted || deviceId == null) return;
    // Single, bounded retry — no loop. A second failure simply updates the
    // device state's lastError, which re-renders this subtitle and lets the
    // user open the troubleshooter again deliberately.
    final deviceService = ref.read(deviceServiceProvider);
    try {
      await _reconnect(deviceService, deviceId);
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to reconnect: $e');
      }
    }
  }

  /// Re-attempts the connection for this card's device type via the device
  /// service. Mirrors the connect dispatch used by the discovery panel.
  Future<void> _reconnect(DeviceService deviceService, String deviceId) {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        return deviceService.connectCamera(deviceId);
      case ConnectedDeviceType.mount:
        return deviceService.connectMount(deviceId);
      case ConnectedDeviceType.focuser:
        return deviceService.connectFocuser(deviceId);
      case ConnectedDeviceType.filterWheel:
        return deviceService.connectFilterWheel(deviceId);
      case ConnectedDeviceType.guider:
        return deviceService.connectGuider(deviceId);
      case ConnectedDeviceType.rotator:
        return deviceService.connectRotator(deviceId);
      case ConnectedDeviceType.dome:
        return deviceService.connectDome(deviceId);
      case ConnectedDeviceType.weather:
        return deviceService.connectWeather(deviceId);
      case ConnectedDeviceType.safetyMonitor:
        return deviceService.connectSafetyMonitor(deviceId);
      case ConnectedDeviceType.coverCalibrator:
        return deviceService.connectCoverCalibrator(deviceId);
    }
  }

  /// The device's last error (if any) for the current device type.
  DeviceError? _getDeviceError() {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        return ref.watch(cameraStateProvider).lastError;
      case ConnectedDeviceType.mount:
        return ref.watch(mountStateProvider).lastError;
      case ConnectedDeviceType.focuser:
        return ref.watch(focuserStateProvider).lastError;
      case ConnectedDeviceType.filterWheel:
        return ref.watch(filterWheelStateProvider).lastError;
      case ConnectedDeviceType.guider:
        return ref.watch(guiderStateProvider).lastError;
      case ConnectedDeviceType.rotator:
        return ref.watch(rotatorStateProvider).lastError;
      case ConnectedDeviceType.dome:
        return ref.watch(domeStateProvider).lastError;
      case ConnectedDeviceType.weather:
        return ref.watch(weatherStateProvider).lastError;
      case ConnectedDeviceType.safetyMonitor:
        return ref.watch(safetyMonitorStateProvider).lastError;
      case ConnectedDeviceType.coverCalibrator:
        return ref.watch(coverCalibratorStateProvider).lastError;
    }
  }

  /// The device's namespaced device id for the current device type. Used to
  /// resolve the [DriverType] for the troubleshooter and to drive the bounded
  /// reconnect retry.
  String? _getDeviceId() {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        return ref.watch(cameraStateProvider).deviceId;
      case ConnectedDeviceType.mount:
        return ref.watch(mountStateProvider).deviceId;
      case ConnectedDeviceType.focuser:
        return ref.watch(focuserStateProvider).deviceId;
      case ConnectedDeviceType.filterWheel:
        return ref.watch(filterWheelStateProvider).deviceId;
      case ConnectedDeviceType.guider:
        return ref.watch(guiderStateProvider).deviceId;
      case ConnectedDeviceType.rotator:
        return ref.watch(rotatorStateProvider).deviceId;
      case ConnectedDeviceType.dome:
        return ref.watch(domeStateProvider).deviceId;
      case ConnectedDeviceType.weather:
        return ref.watch(weatherStateProvider).deviceId;
      case ConnectedDeviceType.safetyMonitor:
        return ref.watch(safetyMonitorStateProvider).deviceId;
      case ConnectedDeviceType.coverCalibrator:
        return ref.watch(coverCalibratorStateProvider).deviceId;
    }
  }

  /// Resolve the device's display name, preferring the live discovery model
  /// name (e.g. "ZWO ASI1600MM-Cool"). Watching discovery here means the card
  /// updates reactively once a slow native SDK enumeration populates the
  /// discovery cache — even when the device connected (and its state name was
  /// set to the raw id) before that enumeration finished. Falls back to the
  /// connected state name, then the formatted id via [_getDeviceDisplayName].
  String _resolveDisplayName(
      String? stateName, String? deviceId, String fallback) {
    if (deviceId != null && deviceId.isNotEmpty) {
      final discovered = ref.watch(unifiedDiscoveryProvider).rawDevices;
      for (final device in discovered) {
        if (device.id == deviceId &&
            device.name.isNotEmpty &&
            device.name != deviceId) {
          return device.name;
        }
      }
    }
    return _getDeviceDisplayName(stateName, deviceId, fallback);
  }

  String _getDeviceName() {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        final state = ref.watch(cameraStateProvider);
        return _resolveDisplayName(state.deviceName, state.deviceId, 'Camera');
      case ConnectedDeviceType.mount:
        final state = ref.watch(mountStateProvider);
        return _resolveDisplayName(state.deviceName, state.deviceId, 'Mount');
      case ConnectedDeviceType.focuser:
        final state = ref.watch(focuserStateProvider);
        return _resolveDisplayName(state.deviceName, state.deviceId, 'Focuser');
      case ConnectedDeviceType.filterWheel:
        final state = ref.watch(filterWheelStateProvider);
        return _resolveDisplayName(
            state.deviceName, state.deviceId, 'Filter Wheel');
      case ConnectedDeviceType.guider:
        final state = ref.watch(guiderStateProvider);
        return _resolveDisplayName(state.deviceName, state.deviceId, 'Guider');
      case ConnectedDeviceType.rotator:
        final state = ref.watch(rotatorStateProvider);
        return _resolveDisplayName(state.deviceName, state.deviceId, 'Rotator');
      case ConnectedDeviceType.dome:
        final state = ref.watch(domeStateProvider);
        return _resolveDisplayName(state.deviceName, state.deviceId, 'Dome');
      case ConnectedDeviceType.weather:
        final state = ref.watch(weatherStateProvider);
        return _resolveDisplayName(
            state.deviceName, state.deviceId, 'Weather Station');
      case ConnectedDeviceType.safetyMonitor:
        final state = ref.watch(safetyMonitorStateProvider);
        return _resolveDisplayName(
            state.deviceName, state.deviceId, 'Safety Monitor');
      case ConnectedDeviceType.coverCalibrator:
        final state = ref.watch(coverCalibratorStateProvider);
        return _resolveDisplayName(
            state.deviceName, state.deviceId, 'Cover Calibrator');
    }
  }

  Widget _buildConnectionBadge(
      DeviceConnectionState state, NightshadeColors colors) {
    final (color, icon, text) = switch (state) {
      DeviceConnectionState.connected => (
          colors.success,
          LucideIcons.check,
          'Connected'
        ),
      DeviceConnectionState.connecting => (
          colors.warning,
          LucideIcons.loader,
          'Connecting'
        ),
      DeviceConnectionState.error => (colors.error, LucideIcons.x, 'Error'),
      DeviceConnectionState.disconnected => (
          colors.textMuted,
          LucideIcons.circle,
          'Disconnected'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: NightshadeDecorations.statusChip(
        color,
        borderRadius: BorderRadius.circular(8),
        bordered: false,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          if (state == DeviceConnectionState.connecting)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsRow(NightshadeColors colors) {
    final metrics = _getMetrics();

    return Row(
      children: metrics.map((metric) {
        return Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: metric.valueColor ?? colors.textPrimary,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                metric.label,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Format RA hours (0-24) as HH:MM:SS
  String _formatRA(double raHours) {
    final h = raHours.floor();
    final remainder = (raHours - h) * 60;
    final m = remainder.floor();
    final s = ((remainder - m) * 60).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Format Dec degrees (-90 to +90) as +/-DD:MM:SS
  String _formatDec(double decDegrees) {
    final sign = decDegrees >= 0 ? '+' : '-';
    final abs = decDegrees.abs();
    final d = abs.floor();
    final remainder = (abs - d) * 60;
    final m = remainder.floor();
    final s = ((remainder - m) * 60).round();
    return '$sign${d.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  List<_DeviceMetric> _getMetrics() {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        final state = ref.watch(cameraStateProvider);
        return [
          _DeviceMetric(
            value: state.temperature != null
                ? '${state.temperature!.toStringAsFixed(1)}C'
                : '---',
            label: 'Sensor Temp',
          ),
          _DeviceMetric(
            value: state.coolerPower != null
                ? '${state.coolerPower!.toStringAsFixed(0)}%'
                : '---',
            label: 'Cooler',
          ),
          _DeviceMetric(
            value: state.isExposing ? 'Exposing' : 'Idle',
            label: 'Status',
          ),
        ];

      case ConnectedDeviceType.mount:
        final state = ref.watch(mountStateProvider);
        return [
          _DeviceMetric(
            value: state.ra != null ? _formatRA(state.ra!) : '---',
            label: 'RA',
          ),
          _DeviceMetric(
            value: state.dec != null ? _formatDec(state.dec!) : '---',
            label: 'Dec',
          ),
          _DeviceMetric(
            value: state.isSlewing
                ? 'Slewing'
                : state.isParked
                    ? 'Parked'
                    : state.isTracking
                        ? 'Tracking'
                        : 'Idle',
            label: 'Status',
          ),
        ];

      case ConnectedDeviceType.focuser:
        final state = ref.watch(focuserStateProvider);
        return [
          _DeviceMetric(
            value: state.position?.toString() ?? '---',
            label: 'Position',
          ),
          _DeviceMetric(
            value: state.temperature != null
                ? '${state.temperature!.toStringAsFixed(1)}C'
                : '---',
            label: 'Temp',
          ),
          _DeviceMetric(
            value: state.isMoving ? 'Moving' : 'Ready',
            label: 'Status',
          ),
        ];

      case ConnectedDeviceType.filterWheel:
        final state = ref.watch(filterWheelStateProvider);
        return [
          _DeviceMetric(
            value: state.currentFilterName ?? 'Unknown',
            label: 'Filter',
          ),
          _DeviceMetric(
            value: state.currentPosition != null
                ? '#${state.currentPosition! + 1}'
                : '#?',
            label: 'Position',
          ),
        ];

      case ConnectedDeviceType.guider:
        final state = ref.watch(guiderStateProvider);
        return [
          _DeviceMetric(
            value: state.rmsTotal != null
                ? '${state.rmsTotal!.toStringAsFixed(2)}"'
                : '---',
            label: 'RMS Total',
          ),
          _DeviceMetric(
            value: state.rmsRa != null
                ? 'RA: ${state.rmsRa!.toStringAsFixed(2)}"'
                : '---',
            label: 'RA/Dec RMS',
          ),
          _DeviceMetric(
            value: state.isGuiding ? 'Guiding' : 'Idle',
            label: 'Status',
          ),
        ];

      case ConnectedDeviceType.rotator:
        final state = ref.watch(rotatorStateProvider);
        return [
          _DeviceMetric(
            value: state.position != null
                ? state.position!.toStringAsFixed(1)
                : '---',
            label: 'Angle',
          ),
          _DeviceMetric(
            value: state.isMoving ? 'Moving' : 'Ready',
            label: 'Status',
          ),
        ];

      case ConnectedDeviceType.dome:
        final state = ref.watch(domeStateProvider);
        return [
          _DeviceMetric(
            value: state.azimuth != null
                ? '${state.azimuth!.toStringAsFixed(1)}\u00B0'
                : '---',
            label: 'Azimuth',
          ),
          _DeviceMetric(
            value: _shutterStatusLabel(state.shutterStatus),
            label: 'Shutter',
          ),
          _DeviceMetric(
            value: state.isSlewing
                ? 'Slewing'
                : state.isParked
                    ? 'Parked'
                    : state.isSlaved
                        ? 'Slaved'
                        : 'Idle',
            label: 'Status',
          ),
        ];

      case ConnectedDeviceType.weather:
        final state = ref.watch(weatherStateProvider);
        final weatherColors = NightshadeColors.of(context);
        final hasRain = state.rainRate != null && state.rainRate! > 0;
        return [
          _DeviceMetric(
            value: state.temperature != null
                ? '${state.temperature!.toStringAsFixed(1)}\u00B0C'
                : '---',
            label: 'Temp',
          ),
          _DeviceMetric(
            value: state.humidity != null
                ? '${state.humidity!.toStringAsFixed(0)}%'
                : '---',
            label: 'Humidity',
          ),
          _DeviceMetric(
            value: hasRain
                ? 'Rain!'
                : state.dewPoint != null
                    ? '${state.dewPoint!.toStringAsFixed(1)}\u00B0C'
                    : '---',
            label: hasRain ? 'Alert' : 'Dew Point',
            valueColor: hasRain ? weatherColors.error : null,
          ),
        ];

      case ConnectedDeviceType.safetyMonitor:
        final state = ref.watch(safetyMonitorStateProvider);
        final colors = NightshadeColors.of(context);
        return [
          _DeviceMetric(
            value: state.isSafe ? 'SAFE' : 'UNSAFE',
            label: 'Status',
            valueColor: state.isSafe ? colors.success : colors.error,
          ),
          _DeviceMetric(
            value: state.lastChecked != null
                ? _formatTimeAgo(state.lastChecked!)
                : '---',
            label: 'Last Checked',
          ),
        ];

      case ConnectedDeviceType.coverCalibrator:
        final state = ref.watch(coverCalibratorStateProvider);
        return [
          if (state.hasCover)
            _DeviceMetric(
              value: _coverStatusLabel(state.coverStatus),
              label: 'Cover',
            ),
          if (state.hasCalibrator) ...[
            _DeviceMetric(
              value: state.isCalibratorOn ? 'ON' : 'OFF',
              label: 'Light',
            ),
            _DeviceMetric(
              value: state.isCalibratorOn
                  ? '${state.brightness}/${state.maxBrightness}'
                  : '---',
              label: 'Brightness',
            ),
          ],
          if (!state.hasCover && !state.hasCalibrator)
            _DeviceMetric(
              value: 'Connected',
              label: 'Status',
            ),
        ];
    }
  }

  String _shutterStatusLabel(ShutterStatus status) {
    switch (status) {
      case ShutterStatus.open:
        return 'Open';
      case ShutterStatus.closed:
        return 'Closed';
      case ShutterStatus.opening:
        return 'Opening';
      case ShutterStatus.closing:
        return 'Closing';
      case ShutterStatus.error:
        return 'Error';
      case ShutterStatus.unknown:
        return 'Unknown';
    }
  }

  String _coverStatusLabel(CoverStatus status) {
    switch (status) {
      case CoverStatus.open:
        return 'Open';
      case CoverStatus.closed:
        return 'Closed';
      case CoverStatus.moving:
        return 'Moving';
      case CoverStatus.notPresent:
        return 'N/A';
      case CoverStatus.unknown:
        return 'Unknown';
      case CoverStatus.error:
        return 'Error';
    }
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
