part of '../connected_device_card.dart';

extension _ConnectedDeviceActionsAndTelemetry on _ConnectedDeviceCardState {
  Widget _buildActionsRow(NightshadeColors colors) {
    final settingsAction = _resolveSettingsAction();

    final trailingButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Settings button — only shown for device types that have real
        // settings reachable from this card (or when an external onSettings
        // callback has been injected by the parent). Device types with nothing
        // to configure get no gear icon rather than an inert one.
        if (settingsAction != null)
          IconButton(
            onPressed: _anyCommandInFlight ? null : settingsAction,
            icon: const Icon(LucideIcons.settings2, size: 16),
            tooltip: 'Settings',
            style: IconButton.styleFrom(
              foregroundColor: colors.textMuted,
            ),
          ),

        // Disconnect button
        IconButton(
          onPressed: _anyCommandInFlight
              ? null
              : widget.onDisconnect ?? () => _handleDisconnect(),
          icon: const Icon(LucideIcons.unplug, size: 16),
          tooltip: 'Disconnect',
          style: IconButton.styleFrom(
            foregroundColor: colors.textMuted,
          ),
        ),
      ],
    );

    // Wrap so the quick-action chips and the trailing settings/disconnect
    // controls flow to a second line on a narrow phone card (or a narrow
    // landscape sheet panel) instead of overflowing the row. The trailing
    // buttons are pushed to the line's end via [Spacer] only when there is
    // room on the same line.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Device-specific quick actions, grouped so they wrap as a unit.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: _buildDeviceActions(colors)
              // Drop the inter-button SizedBox spacers; [Wrap] handles spacing.
              .where((w) => w is! SizedBox)
              .toList(),
        ),
        trailingButtons,
      ],
    );
  }

  /// Returns the settings action for the current device type, or `null` if
  /// this device type has no real settings to expose from the card.
  ///
  /// Wiring matrix:
  ///
  /// | Device          | Gear visible? | Action                                    |
  /// |-----------------|---------------|-------------------------------------------|
  /// | camera          | yes           | local cooling-target dialog               |
  /// | filterWheel     | yes (if      | injected `widget.onSettings`              |
  /// |                 | injected)     | (parent opens ProfileEditorDialog where   |
  /// |                 |               | per-filter offsets are edited)            |
  /// | mount           | no            | no slew-rate / park-position widget yet   |
  /// | focuser         | no            | no step-size / max-position widget yet    |
  /// | rotator         | no            | no sky-PA preset widget yet               |
  /// | dome            | no            | no park/home/follow-mount widget yet      |
  /// | coverCalibrator | yes, if light | local brightness dialog                    |
  /// | guider          | no            | no per-card settings (config in Imaging)  |
  /// | weather         | no            | read-only telemetry                       |
  /// | safetyMonitor   | no            | read-only                                 |
  ///
  /// No stubs or placeholders: unwired gears stay hidden
  /// — we never display a settings affordance that does nothing or that opens
  /// an empty dialog. When a real device-specific settings widget for one of
  /// the unwired entries is added under
  /// `packages/nightshade_app/lib/screens/equipment/widgets/`, route to it
  /// from this switch.
  ///
  /// An externally-injected `widget.onSettings` always wins, allowing the
  /// equipment screen (which knows the active profile) to wire filter-wheel
  /// offsets editing without making the card itself profile-aware.
  VoidCallback? _resolveSettingsAction() {
    final injected = widget.onSettings;
    if (injected != null) {
      return injected;
    }
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        return () {
          final targetTemp = ref.read(cameraStateProvider).targetTemp;
          _showCoolingTempDialog(targetTemp);
        };
      case ConnectedDeviceType.mount:
        return _showMountSettingsDialog;
      case ConnectedDeviceType.focuser:
        return _showFocuserSettingsDialog;
      case ConnectedDeviceType.rotator:
        return _showRotatorSettingsDialog;
      case ConnectedDeviceType.dome:
        return _showDomeSettingsDialog;
      case ConnectedDeviceType.coverCalibrator:
        final state = ref.watch(coverCalibratorStateProvider);
        final capabilities = ref.watch(
          equipmentCoverCalibratorCapabilitiesProvider(state.deviceId ?? ''),
        );
        return gateCapability(
          capabilities,
          (caps) => caps.calibratorPresent,
        )
            ? _showCoverCalibratorSettingsDialog
            : null;
      case ConnectedDeviceType.filterWheel:
      // Read-only / no per-card settings.
      case ConnectedDeviceType.guider:
      case ConnectedDeviceType.weather:
      case ConnectedDeviceType.safetyMonitor:
        return null;
    }
  }

  List<Widget> _buildDeviceActions(NightshadeColors colors) {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        final state = ref.watch(cameraStateProvider);
        return [
          _ActionButton(
            label: 'Cool to ${formatCelsius(state.targetTemp, decimals: 0)}',
            onTap: _deviceCommandInFlight
                ? null
                : () => _handleCoolCamera(state.targetTemp),
            onLongPress: _deviceCommandInFlight
                ? null
                : () => _showCoolingTempDialog(state.targetTemp),
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: state.isWarming ? 'Cancel Warm' : 'Warm Up',
            onTap: _deviceCommandInFlight
                ? null
                : state.isWarming
                    ? _handleCancelWarm
                    : _handleWarmCamera,
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.mount:
        final state = ref.watch(mountStateProvider);
        final capabilities = ref.watch(
          equipmentMountCapabilitiesProvider(state.deviceId ?? ''),
        );
        final connected =
            state.connectionState == DeviceConnectionState.connected &&
                state.deviceId != null &&
                state.deviceId!.isNotEmpty;
        final canPark = gateCapability<MountCapabilities>(
          capabilities,
          (caps) => state.isParked ? caps.canUnpark : caps.canPark,
        );
        final canSetTracking = gateCapability<MountCapabilities>(
          capabilities,
          (caps) => caps.canSetTracking,
        );
        final canFindHome = gateCapability<MountCapabilities>(
          capabilities,
          (caps) => caps.canFindHome,
        );
        final canFlip = gateCapability<MountCapabilities>(
          capabilities,
          (caps) =>
              caps.isEquatorial &&
              caps.canGetSideOfPier &&
              (caps.canSlew || caps.canSlewAsync),
        );
        final flipInProgress = ref.watch(isFlipInProgressProvider);
        final sequenceSettled =
            ref.watch(sequenceExecutionStateProvider).canStart;
        return [
          _ActionButton(
            label: state.isParked ? 'Unpark' : 'Park',
            onTap: connected &&
                    canPark &&
                    !state.isSlewing &&
                    !flipInProgress &&
                    !_mountCommandInFlight
                ? _handleTogglePark
                : null,
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: state.isTracking ? 'Stop Tracking' : 'Track',
            onTap: connected &&
                    canSetTracking &&
                    !state.isSlewing &&
                    !flipInProgress &&
                    !_mountCommandInFlight
                ? () => _handleToggleTracking(state.isTracking)
                : null,
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: 'Home',
            onTap: connected &&
                    canFindHome &&
                    !state.isSlewing &&
                    !flipInProgress &&
                    !_mountCommandInFlight
                ? _handleFindHome
                : null,
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: 'Flip',
            onTap: connected &&
                    canFlip &&
                    state.isTracking &&
                    !state.isParked &&
                    !state.isSlewing &&
                    state.ra != null &&
                    state.dec != null &&
                    sequenceSettled &&
                    !flipInProgress &&
                    !_mountCommandInFlight
                ? _handleManualMeridianFlip
                : null,
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.focuser:
        final state = ref.watch(focuserStateProvider);
        final autofocusRunning = ref.watch(
          sessionStateProvider.select((session) => session.isAutofocusing),
        );
        return [
          _ActionButton(
            label: 'Move to...',
            onTap: state.isAbsolute && !state.isMoving && !autofocusRunning
                ? () => _showMoveDialog(context)
                : null,
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.filterWheel:
        final state = ref.watch(filterWheelStateProvider);
        final autofocusRunning = ref.watch(
          sessionStateProvider.select((session) => session.isAutofocusing),
        );
        return [
          _FilterDropdown(
            filterNames: state.filterNames,
            currentPosition: state.currentPosition,
            onFilterSelected: _handleFilterChange,
            enabled: state.connectionState == DeviceConnectionState.connected &&
                !state.isMoving &&
                !autofocusRunning &&
                !_deviceCommandInFlight,
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.guider:
        final state = ref.watch(guiderStateProvider);
        return [
          _ActionButton(
            label: state.isGuiding ? 'Stop' : 'Start Guiding',
            onTap: state.connectionState == DeviceConnectionState.connected &&
                    state.deviceId != null &&
                    state.deviceId!.isNotEmpty &&
                    !state.isCalibrating &&
                    !_deviceCommandInFlight
                ? () => _handleToggleGuiding(state.isGuiding)
                : null,
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.rotator:
        // Keep the rotator's capability future warm so the "Rotate To Angle"
        // dialog observes the resolved min/maxAngleDeg window (it reads them
        // synchronously on open). capabilityRefreshOnConnectProvider only
        // invalidates on the connect edge; without an active watcher the
        // FutureProvider would be cold and the dialog would fall back to a
        // full 0..360 turn even on a bounded rotator.
        final state = ref.watch(rotatorStateProvider);
        final capabilities = ref.watch(
          equipmentRotatorCapabilitiesProvider(state.deviceId ?? ''),
        );
        final canMoveAbsolute = gateCapability<RotatorCapabilities>(
          capabilities,
          (caps) => caps.canMoveAbsolute,
        );
        return [
          _ActionButton(
            label: 'Rotate to...',
            onTap: state.connectionState == DeviceConnectionState.connected &&
                    !state.isMoving &&
                    canMoveAbsolute
                ? () => _showRotateDialog(context)
                : null,
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.dome:
        final state = ref.watch(domeStateProvider);
        final capabilities = ref.watch(
          equipmentDomeCapabilitiesProvider(state.deviceId ?? ''),
        );
        final connected =
            state.connectionState == DeviceConnectionState.connected &&
                state.deviceId != null &&
                state.deviceId!.isNotEmpty;
        final canSetShutter = gateCapability<DomeCapabilities>(
          capabilities,
          (caps) => caps.canSetShutter,
        );
        final canPark = gateCapability<DomeCapabilities>(
          capabilities,
          (caps) => caps.canPark,
        );
        final canSetAzimuth = gateCapability<DomeCapabilities>(
          capabilities,
          (caps) => caps.canSetAzimuth,
        );
        final canFindHome = gateCapability<DomeCapabilities>(
          capabilities,
          (caps) => caps.canFindHome,
        );
        final canAbort = gateCapability<DomeCapabilities>(
          capabilities,
          (caps) => caps.canAbort,
        );
        final shutterMoving = state.shutterStatus == ShutterStatus.opening ||
            state.shutterStatus == ShutterStatus.closing;
        return [
          _ActionButton(
            label: state.shutterStatus == ShutterStatus.open
                ? 'Close Shutter'
                : 'Open Shutter',
            onTap: connected &&
                    canSetShutter &&
                    !shutterMoving &&
                    !_domeCommandInFlight
                ? () => _handleDomeShutter(state.shutterStatus)
                : null,
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: state.isParked ? 'Parked' : 'Park',
            onTap: connected &&
                    canPark &&
                    !state.isParked &&
                    !state.isSlewing &&
                    !_domeCommandInFlight
                ? _handleDomePark
                : null,
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: 'Slew...',
            onTap: connected &&
                    canSetAzimuth &&
                    !state.isSlewing &&
                    !_domeCommandInFlight
                ? () => _showDomeSlewDialog(context)
                : null,
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: 'Home',
            onTap: connected &&
                    canFindHome &&
                    !state.isSlewing &&
                    !_domeCommandInFlight
                ? _handleDomeHome
                : null,
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: 'Halt',
            onTap: connected &&
                    canAbort &&
                    state.isSlewing &&
                    !_domeCommandInFlight
                ? _handleDomeHalt
                : null,
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.weather:
        return [];

      case ConnectedDeviceType.safetyMonitor:
        final state = ref.watch(safetyMonitorStateProvider);
        final safetyStatus = ref.watch(equipmentSafetySnoozeStatusProvider);
        return [
          if (!state.isSafe)
            _ActionButton(
              label: safetyStatus == WeatherSafetyStatus.snoozed
                  ? 'Cancel Snooze'
                  : 'Snooze 15m',
              onTap: state.connectionState != DeviceConnectionState.connected
                  ? null
                  : safetyStatus == WeatherSafetyStatus.snoozed
                      ? _handleSafetyCancelSnooze
                      : _handleSafetySnooze,
              colors: colors,
            ),
        ];

      case ConnectedDeviceType.coverCalibrator:
        final state = ref.watch(coverCalibratorStateProvider);
        final capabilities = ref.watch(
          equipmentCoverCalibratorCapabilitiesProvider(state.deviceId ?? ''),
        );
        final snapshot = capabilities.valueOrNull;
        if (snapshot == null) return [];
        final connected =
            state.connectionState == DeviceConnectionState.connected;
        final coverStatus = snapshot.coverStatus;
        final coverCanMove = coverStatus == CoverStatus.open ||
            coverStatus == CoverStatus.closed;
        final calibratorStatus = snapshot.calibratorStatus;
        final calibratorCanToggle = calibratorStatus == CalibratorStatus.off ||
            calibratorStatus == CalibratorStatus.ready ||
            calibratorStatus == CalibratorStatus.notReady;
        final calibratorOn = calibratorStatus == CalibratorStatus.ready ||
            calibratorStatus == CalibratorStatus.notReady;
        return [
          if (snapshot.coverPresent)
            _ActionButton(
              label: switch (coverStatus) {
                CoverStatus.open => 'Close Cover',
                CoverStatus.closed => 'Open Cover',
                CoverStatus.moving => 'Cover Moving',
                _ => 'Cover Unavailable',
              },
              onTap: connected &&
                      coverCanMove &&
                      !_coverCalibratorCommandInFlight
                  ? () => _handleCoverToggle(coverStatus == CoverStatus.open)
                  : null,
              colors: colors,
            ),
          if (snapshot.coverPresent && snapshot.calibratorPresent)
            const SizedBox(width: 8),
          if (snapshot.calibratorPresent)
            _ActionButton(
              label: calibratorOn ? 'Light Off' : 'Light On',
              onTap: connected &&
                      calibratorCanToggle &&
                      (calibratorOn || snapshot.maxBrightness > 0) &&
                      !_coverCalibratorCommandInFlight
                  ? () => _handleCalibratorToggle(
                        isOn: calibratorOn,
                        brightness: snapshot.brightness,
                        maxBrightness: snapshot.maxBrightness,
                      )
                  : null,
              colors: colors,
            ),
        ];
    }
  }

  Widget _buildExpandedContent(NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Additional Info',
              style: NightshadeTypography.labelStrongSm
                  .copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: 8),
            ..._buildExpandedTelemetry(colors),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildExpandedTelemetry(NightshadeColors colors) {
    switch (widget.type) {
      case ConnectedDeviceType.camera:
        final state = ref.watch(cameraStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
              label: 'Gain',
              value: state.gain?.toString() ?? '---',
              colors: colors),
          _TelemetryRow(
              label: 'Offset',
              value: state.offset?.toString() ?? '---',
              colors: colors),
          _TelemetryRow(
              label: 'Binning', value: state.binning ?? '---', colors: colors),
          _TelemetryRow(
              label: 'Cooling',
              value: state.isCooling ? 'Active' : 'Off',
              colors: colors),
          _TelemetryRow(
            label: 'Target Temp',
            value: formatCelsius(state.targetTemp),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.mount:
        final state = ref.watch(mountStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'RA',
            value: state.ra?.toStringAsFixed(4) ?? '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Dec',
            value: state.dec?.toStringAsFixed(4) ?? '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Altitude',
            value: state.altitude != null
                ? state.altitude!.toStringAsFixed(2)
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Azimuth',
            value: state.azimuth != null
                ? state.azimuth!.toStringAsFixed(2)
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Side of Pier',
            value: state.sideOfPier ?? 'Unknown',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Tracking Rate',
            value: state.trackingRate.name.toUpperCase(),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.focuser:
        final state = ref.watch(focuserStateProvider);
        final reportedMax = state.maxPosition;
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Max Position',
            value: reportedMax != null && reportedMax > 0
                ? reportedMax.toString()
                : '---',
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.filterWheel:
        final state = ref.watch(filterWheelStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Filters',
            value: state.filterNames.join(', '),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.guider:
        final state = ref.watch(guiderStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'RA RMS',
            value: state.rmsRa != null
                ? '${state.rmsRa!.toStringAsFixed(3)}"'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Dec RMS',
            value: state.rmsDec != null
                ? '${state.rmsDec!.toStringAsFixed(3)}"'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Calibrating',
            value: state.isCalibrating ? 'Yes' : 'No',
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.rotator:
        final state = ref.watch(rotatorStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Mechanical Position',
            value: state.mechanicalPosition != null
                ? state.mechanicalPosition!.toStringAsFixed(2)
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Reversed',
            value: state.isReversed ? 'Yes' : 'No',
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.dome:
        final state = ref.watch(domeStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Azimuth',
            value: state.azimuth != null
                ? '${state.azimuth!.toStringAsFixed(2)}\u00B0'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Shutter',
            value: _shutterStatusLabel(state.shutterStatus),
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Parked',
            value: state.isParked ? 'Yes' : 'No',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'At Home',
            value: state.isAtHome ? 'Yes' : 'No',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Slaved',
            value: state.isSlaved ? 'Yes' : 'No',
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.weather:
        final state = ref.watch(weatherStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Temperature',
            value: state.temperature != null
                ? '${state.temperature!.toStringAsFixed(1)}\u00B0C'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Humidity',
            value: state.humidity != null
                ? '${state.humidity!.toStringAsFixed(1)}%'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Dew Point',
            value: state.dewPoint != null
                ? '${state.dewPoint!.toStringAsFixed(1)}\u00B0C'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Pressure',
            value: state.pressure != null
                ? '${state.pressure!.toStringAsFixed(1)} hPa'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Wind Speed',
            value: state.windSpeed != null
                ? '${state.windSpeed!.toStringAsFixed(1)} km/h'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Wind Direction',
            value: state.windDirection != null
                ? '${state.windDirection!.toStringAsFixed(0)}\u00B0'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Cloud Cover',
            value: state.cloudCover != null
                ? '${state.cloudCover!.toStringAsFixed(0)}%'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Sky Quality',
            value: state.skyQuality != null
                ? '${state.skyQuality!.toStringAsFixed(2)} mag/arcsec\u00B2'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Sky Temp',
            value: state.skyTemperature != null
                ? '${state.skyTemperature!.toStringAsFixed(1)}\u00B0C'
                : '---',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Rain Rate',
            value: state.rainRate != null
                ? '${state.rainRate!.toStringAsFixed(1)} mm/h'
                : '---',
            colors: colors,
          ),
          if (state.lastUpdated != null)
            _TelemetryRow(
              label: 'Last Updated',
              value: '${_formatAge(_tickNow().difference(state.lastUpdated!))} '
                  'ago',
              colors: colors,
            ),
        ];

      case ConnectedDeviceType.safetyMonitor:
        final state = ref.watch(safetyMonitorStateProvider);
        final lastChecked = state.lastChecked;
        final age =
            lastChecked == null ? null : _tickNow().difference(lastChecked);
        final isStale = age != null && age > _safetyStatusStaleAfter;
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Is Safe',
            // Never answer Yes/No from a reading we can no longer vouch for.
            value: lastChecked == null
                ? 'Unknown — not read yet'
                : isStale
                    ? 'Unknown — reading is stale'
                    : state.isSafe
                        ? 'Yes'
                        : 'No',
            colors: colors,
          ),
          if (age != null)
            _TelemetryRow(
              label: 'Last Checked',
              value: '${_formatAge(age)} ago',
              colors: colors,
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
            _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors,
            ),
            _TelemetryRow(
              label: 'Capabilities',
              value: capabilities.hasError ? 'Unavailable' : 'Loading...',
              colors: colors,
            ),
          ];
        }
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          if (snapshot.coverPresent)
            _TelemetryRow(
              label: 'Cover Status',
              value: _coverStatusLabel(
                snapshot.coverStatus ?? CoverStatus.unknown,
              ),
              colors: colors,
            ),
          if (snapshot.calibratorPresent) ...[
            _TelemetryRow(
              label: 'Calibrator',
              value: _calibratorStatusLabel(snapshot.calibratorStatus),
              colors: colors,
            ),
            _TelemetryRow(
              label: 'Brightness',
              value: '${snapshot.brightness ?? 0} / '
                  '${snapshot.maxBrightness}',
              colors: colors,
            ),
          ],
          if (!snapshot.coverPresent && !snapshot.calibratorPresent)
            _TelemetryRow(
              label: 'Capabilities',
              value: 'No cover or calibrator reported',
              colors: colors,
            ),
        ];
    }
  }
}
