part of '../connected_device_card.dart';

extension _ConnectedDeviceActionsAndTelemetry on _ConnectedDeviceCardState {
  Widget _buildActionsRow(NightshadeColors colors) {
    final settingsAction = _resolveSettingsAction();

    final trailingButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Settings button — only shown for device types that have real
        // settings reachable from this card (or when an external onSettings
        // callback has been injected by the parent). Device types without
        // settings have no gear icon at all so we never ship a non-functional
        // control. See docs/plans/2026-05-09-v250-audit-fixes.md §4.1.
        if (settingsAction != null)
          IconButton(
            onPressed: settingsAction,
            icon: const Icon(LucideIcons.settings2, size: 16),
            tooltip: 'Settings',
            style: IconButton.styleFrom(
              foregroundColor: colors.textMuted,
            ),
          ),

        // Disconnect button
        IconButton(
          onPressed: widget.onDisconnect ?? () => _handleDisconnect(),
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
  /// Wiring matrix (audit §4.6 follow-up; W0-EQ left TODOs that W1B-UI-EQ
  /// addressed here):
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
  /// | coverCalibrator | no            | no brightness / cover-state widget yet    |
  /// | guider          | no            | no per-card settings (config in Imaging)  |
  /// | weather         | no            | read-only telemetry                       |
  /// | safetyMonitor   | no            | read-only                                 |
  ///
  /// Per CLAUDE.md ("no stubs / no placeholders"), unwired gears stay hidden
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
        return _showCoverCalibratorSettingsDialog;
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
            label: 'Cool to ${state.targetTemp.toStringAsFixed(0)}C',
            onTap: () => _handleCoolCamera(state.targetTemp),
            onLongPress: () => _showCoolingTempDialog(state.targetTemp),
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: state.isWarming ? 'Cancel Warm' : 'Warm Up',
            onTap: state.isWarming ? _handleCancelWarm : _handleWarmCamera,
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.mount:
        final state = ref.watch(mountStateProvider);
        return [
          _ActionButton(
            label: state.isParked ? 'Unpark' : 'Park',
            onTap: () => _handleTogglePark(),
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: state.isTracking ? 'Stop Tracking' : 'Track',
            onTap: () => _handleToggleTracking(state.isTracking),
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: 'Home',
            onTap: () => _handleFindHome(),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.focuser:
        return [
          _ActionButton(
            label: 'Move to...',
            onTap: () => _showMoveDialog(context),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.filterWheel:
        final state = ref.watch(filterWheelStateProvider);
        return [
          _FilterDropdown(
            filterNames: state.filterNames,
            currentPosition: state.currentPosition,
            onFilterSelected: _handleFilterChange,
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.guider:
        final state = ref.watch(guiderStateProvider);
        return [
          _ActionButton(
            label: state.isGuiding ? 'Stop' : 'Start Guiding',
            onTap: () => _handleToggleGuiding(state.isGuiding),
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
        ref.watch(equipmentRotatorCapabilitiesProvider(
          ref.watch(rotatorStateProvider).deviceId ?? '',
        ));
        return [
          _ActionButton(
            label: 'Rotate to...',
            onTap: () => _showRotateDialog(context),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.dome:
        final state = ref.watch(domeStateProvider);
        return [
          _ActionButton(
            label: state.shutterStatus == ShutterStatus.open
                ? 'Close Shutter'
                : 'Open Shutter',
            onTap: () => _handleDomeShutter(state.shutterStatus),
            colors: colors,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            label: state.isParked ? 'Unpark' : 'Park',
            onTap: () => _handleDomePark(state.isParked),
            colors: colors,
          ),
        ];

      case ConnectedDeviceType.weather:
        return [];

      case ConnectedDeviceType.safetyMonitor:
        return [];

      case ConnectedDeviceType.coverCalibrator:
        final state = ref.watch(coverCalibratorStateProvider);
        return [
          if (state.hasCover)
            _ActionButton(
              label: state.isCoverOpen ? 'Close Cover' : 'Open Cover',
              onTap: () => _handleCoverToggle(state.isCoverOpen),
              colors: colors,
            ),
          if (state.hasCover && state.hasCalibrator) const SizedBox(width: 8),
          if (state.hasCalibrator)
            _ActionButton(
              label: state.isCalibratorOn ? 'Light Off' : 'Light On',
              onTap: () => _handleCalibratorToggle(state),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: NightshadeButton(
                    onPressed: () => _showEditNameDialog(context),
                    icon: LucideIcons.pencil,
                    label: 'Edit Name',
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                  ),
                ),
              ],
            ),
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
            value: '${state.targetTemp.toStringAsFixed(1)}C',
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
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Max Position',
            value: state.maxPosition?.toString() ?? '---',
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
              value: _formatTimeAgo(state.lastUpdated!),
              colors: colors,
            ),
        ];

      case ConnectedDeviceType.safetyMonitor:
        final state = ref.watch(safetyMonitorStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Is Safe',
            value: state.isSafe ? 'Yes' : 'No',
            colors: colors,
          ),
          if (state.lastChecked != null)
            _TelemetryRow(
              label: 'Last Checked',
              value: _formatTimeAgo(state.lastChecked!),
              colors: colors,
            ),
        ];

      case ConnectedDeviceType.coverCalibrator:
        final state = ref.watch(coverCalibratorStateProvider);
        return [
          _TelemetryRow(
              label: 'Device ID',
              value: state.deviceId ?? 'Unknown',
              colors: colors),
          _TelemetryRow(
            label: 'Cover Status',
            value: _coverStatusLabel(state.coverStatus),
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Calibrator',
            value: state.isCalibratorOn ? 'On' : 'Off',
            colors: colors,
          ),
          _TelemetryRow(
            label: 'Brightness',
            value: '${state.brightness} / ${state.maxBrightness}',
            colors: colors,
          ),
        ];
    }
  }
}
