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
  /// if we fell back to accent.
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
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
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
                  fontSize: NightshadeTypography.fontSize11,
                  fontWeight: FontWeight.w500,
                  color: colors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              // A name a couple of characters over the column width must
              // shrink to fit before any of it is dropped: at 1600x900 the
              // FILTER WHEEL card ellipsises to "Simulated Filter ..." beside
              // camera, mount and focuser cards of the same width showing
              // their full names, so one card looks like it holds a different,
              // mangled device. The ellipsis (and a tooltip) stays for a name
              // that is genuinely too long.
              Tooltip(
                message: deviceName,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    deviceName,
                    maxLines: 1,
                    style: NightshadeTypography.h5
                        .copyWith(color: colors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Connection badge
        _buildConnectionBadge(state, colors),
      ],
    );
  }

  /// Full-width notice for a device that is connected but is NOT the device the
  /// active profile assigns to this slot.
  ///
  /// Returns [SizedBox.shrink] otherwise, so a profile device keeps its compact
  /// card.
  Widget _buildSessionOnlyNotice(
    NightshadeColors colors,
    DeviceConnectionState state,
  ) {
    if (state != DeviceConnectionState.connected || !widget.sessionOnly) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: NightshadeTokens.spaceSm),
      child: _SessionOnlyNotice(colors: colors),
    );
  }

  /// When the device is in an error state, render a full-width
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
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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
              fontSize: NightshadeTypography.fontSize10,
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
          child: Padding(
            // Gutter between columns: at full width a sexagesimal Dec fills its
            // share exactly, so without this the value ran straight into the
            // next column's ("+00:00:00Parked").
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Scale down rather than wrap. These columns are equal-width
                // `Expanded`s, and a sexagesimal Dec is one character wider than
                // an RA because of its sign — so `+00:00:00` wrapped after
                // `+00:00:0` and left a stray `0` on the line below, which reads
                // as a completely different declination. Shrinking keeps the whole
                // value on one line and legible; ellipsis would be worse here,
                // since a truncated coordinate is indistinguishable from a real
                // one.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    metric.value,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize18,
                      fontWeight: FontWeight.w600,
                      color: metric.valueColor ?? colors.textPrimary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metric.label,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  List<_DeviceMetric> _getMetrics() {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        final state = ref.watch(cameraStateProvider);
        return [
          _DeviceMetric(
            value: formatCelsius(state.temperature),
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
            value: state.ra != null
                ? CoordinateFormat.ra(state.ra!,
                    style: SexagesimalStyle.paddedColons,
                    seconds: SecondsPrecision.integerRounded)
                : '---',
            label: 'RA',
          ),
          _DeviceMetric(
            value: state.dec != null
                ? CoordinateFormat.dec(state.dec!,
                    style: SexagesimalStyle.paddedColons,
                    seconds: SecondsPrecision.integerRounded)
                : '---',
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
            value: formatCelsius(state.temperature),
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
        // The age must be driven by a CLOCK, not by the provider that sets
        // `lastChecked`. Computing it at build time only worked out to "0s ago"
        // forever: the widget rebuilt exactly when lastChecked was set to
        // DateTime.now(), so sampling the label every 3 s over 42 s produced
        // fourteen consecutive "0s ago" against a 5 s poll.
        final now = _tickNow();
        final lastChecked = state.lastChecked;
        final age = lastChecked == null ? null : now.difference(lastChecked);
        final isStale = age != null && age > _safetyStatusStaleAfter;
        return [
          // A stale reading is NOT a safe reading: once the read is older
          // than the staleness budget the card reports STALE, never SAFE.
          _DeviceMetric(
            value: lastChecked == null
                ? 'UNKNOWN'
                : isStale
                    ? 'STALE'
                    : state.isSafe
                        ? 'SAFE'
                        : 'UNSAFE',
            label: 'Status',
            valueColor: lastChecked == null || isStale
                ? colors.warning
                : state.isSafe
                    ? colors.success
                    : colors.error,
          ),
          _DeviceMetric(
            value: age != null ? '${_formatAge(age)} ago' : '---',
            label: 'Last Checked',
            valueColor: isStale ? colors.warning : null,
          ),
        ];

      case ConnectedDeviceType.coverCalibrator:
        final state = ref.watch(coverCalibratorStateProvider);
        final capabilities = ref.watch(
          equipmentCoverCalibratorCapabilitiesProvider(state.deviceId ?? ''),
        );
        final snapshot = capabilities.valueOrNull;
        if (snapshot == null) {
          return [
            _DeviceMetric(
              value: capabilities.hasError ? 'Unavailable' : 'Loading...',
              label: 'Capabilities',
            ),
          ];
        }
        return [
          if (snapshot.coverPresent)
            _DeviceMetric(
              value: _coverStatusLabel(
                snapshot.coverStatus ?? CoverStatus.unknown,
              ),
              label: 'Cover',
            ),
          if (snapshot.calibratorPresent) ...[
            _DeviceMetric(
              value: _calibratorStatusLabel(snapshot.calibratorStatus),
              label: 'Light',
            ),
            _DeviceMetric(
              // Brightness is a driver reading. A calibrator that reports no
              // brightness, or no brightness scale, must read '---' — showing
              // "0/0" or "0/100" claims the panel is measurably dark when the
              // truth is that nothing was measured.
              value: _calibratorBrightnessLabel(snapshot),
              label: 'Brightness',
            ),
          ],
          if (!snapshot.coverPresent && !snapshot.calibratorPresent)
            _DeviceMetric(
              value: 'None reported',
              label: 'Capabilities',
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

  String _calibratorStatusLabel(CalibratorStatus? status) {
    return switch (status) {
      CalibratorStatus.ready => 'ON',
      CalibratorStatus.notReady => 'WARMING',
      CalibratorStatus.off => 'OFF',
      CalibratorStatus.notPresent => 'N/A',
      CalibratorStatus.error => 'ERROR',
      CalibratorStatus.unknown || null => 'UNKNOWN',
    };
  }

  /// `<level>/<max>` only when the driver actually reported both halves.
  ///
  /// `maxBrightness` arrives as 0 when neither the host payload nor the native
  /// capability probe carries a brightness scale, and `brightness` is null when
  /// the level itself is unreported. Either way there is no reading to show.
  String _calibratorBrightnessLabel(
      CoverCalibratorCapabilitySnapshot snapshot) {
    final isPowered = snapshot.calibratorStatus == CalibratorStatus.ready ||
        snapshot.calibratorStatus == CalibratorStatus.notReady;
    if (!isPowered) return '---';
    final level = snapshot.brightness;
    final max = snapshot.maxBrightness;
    if (level == null || max <= 0) return '---';
    return '$level/$max';
  }

  /// "Now" as seen by the card's own 5 s freshness clock
  /// (see `_startFreshnessTicker`).
  ///
  /// Freshness labels MUST derive from a clock, not from `DateTime.now()` read
  /// during a build that only happens when the value being aged is refreshed —
  /// that combination pinned "Last Checked" at "0s ago" permanently, including
  /// while polling was wedged.
  DateTime _tickNow() => _freshnessNow;
}

/// Marks a card whose device is connected but is NOT the device the active
/// profile assigns to that slot.
///
/// Discovery's "Assign" (persistent) and "Connect" (ephemeral) sat side by side
/// with no wording, icon or hint that Connect alone would not survive a restart,
/// and the resulting cards were pixel-identical to the profile devices. A user
/// who set up nine devices at dusk saw "9 connected" and reasonably concluded the
/// rig was configured; the next night four came up.
class _SessionOnlyNotice extends StatelessWidget {
  final NightshadeColors colors;

  const _SessionOnlyNotice({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: NightshadeDecorations.tintedBadge(
        colors.warning,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.bookmarkMinus, size: 12, color: colors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'This session only — not saved to your profile, so it will not '
              'reconnect next launch. Use Assign in Discovery to keep it.',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize10,
                fontWeight: FontWeight.w500,
                color: colors.warning,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a duration as `12s` / `4m` / `2h`. Takes the age rather than a
/// timestamp so the caller supplies the clock — see the safety-monitor branch of
/// `_getMetrics` for why reading `DateTime.now()` in here made the label
/// structurally incapable of ageing.
String _formatAge(Duration age) {
  if (age.isNegative) return '0s';
  if (age.inSeconds < 60) return '${age.inSeconds}s';
  if (age.inMinutes < 60) return '${age.inMinutes}m';
  return '${age.inHours}h';
}

/// How old a safety reading may be before the card stops presenting it as the
/// current safety verdict.
///
/// The environmental poll runs every 5 s with a 4 s read cap, so a healthy cycle
/// completes well inside 10 s. 30 s therefore cannot fire on ordinary jitter but
/// still catches a wedged or unresponsive monitor within half a minute.
const Duration _safetyStatusStaleAfter = Duration(seconds: 30);
