// ignore_for_file: invalid_use_of_protected_member

part of '../profile_editor_dialog.dart';

extension _ProfileEditorOpticalAndDevices on _ProfileEditorDialogState {
  // Section 2: Optical Train
  // ============================================================================

  Widget _buildOpticalTrainSection(NightshadeColors colors, ThemeData theme) {
    return _SectionCard(
      title: 'Optical Train',
      icon: LucideIcons.target,
      isExpanded: _expandedSections['optical']!,
      onToggle: () => setState(
          () => _expandedSections['optical'] = !_expandedSections['optical']!),
      summary: _telescopeNameController.text.isEmpty
          ? 'Not configured'
          : _telescopeNameController.text,
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One-tap prefill from the built-in + user telescope library (C10).
          // Manual entry below remains fully available afterwards.
          Align(
            alignment: Alignment.centerLeft,
            child: NightshadeButton(
              // lucide_icons ships no `telescope` glyph; `aperture` is this
              // codebase's established optics/telescope icon (the onboarding
              // optical-train step uses the same).
              icon: LucideIcons.aperture,
              label: 'Telescope library',
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: _pickTelescopeFromLibrary,
            ),
          ),
          const SizedBox(height: 16),

          // Telescope name
          NightshadeTextField(
            label: 'Telescope / OTA',
            controller: _telescopeNameController,
            hint: 'e.g., Esprit 100ED, RC8',
          ),
          const SizedBox(height: 16),

          // Focal length and aperture row. Each carries an inline help
          // affordance (C10) beside its label; the labels are rendered
          // externally (matching the file's existing literal fontSize-12/w500
          // label style) so the help icon can sit next to them.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabelWithHelp(
                      colors,
                      label: 'Focal Length',
                      helpTitle: 'Focal length (mm)',
                      helpBody:
                          "The telescope's focal length in millimetres — on "
                          'the OTA label or its spec sheet. Sets your image '
                          'scale and field of view together with the camera '
                          'pixel size.',
                    ),
                    const SizedBox(height: 4),
                    NightshadeTextField(
                      controller: _focalLengthController,
                      hint: 'e.g., 550',
                      suffix: 'mm',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabelWithHelp(
                      colors,
                      label: 'Aperture',
                      helpTitle: 'Aperture (mm)',
                      helpBody: 'The diameter of the telescope in millimetres. '
                          'Focal length ÷ aperture gives your focal ratio and '
                          'sets how much light you gather.',
                    ),
                    const SizedBox(height: 4),
                    NightshadeTextField(
                      controller: _apertureController,
                      hint: 'e.g., 100',
                      suffix: 'mm',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Computed values
          NightshadeCard(
            variant: CardVariant.subtle,
            borderRadius: NightshadeTokens.radiusInline8,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _ComputedValue(
                  label: 'f/Ratio',
                  value: _computedFRatio != null
                      ? 'f/${_computedFRatio!.toStringAsFixed(1)}'
                      : '---',
                  colors: colors,
                ),
                const SizedBox(width: 32),
                _ComputedValue(
                  label: 'Scale',
                  value: _computedScale != null
                      ? '${_computedScale!.toStringAsFixed(2)}"/px'
                      : '---',
                  subtitle: _pixelSize != null
                      ? 'at ${_pixelSize!.toStringAsFixed(2)}\u00B5m'
                      : null,
                  colors: colors,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A field label rendered externally (matching this file's literal
  /// fontSize-12 / w500 / textSecondary label style) with an inline rich help
  /// affordance (C10) beside it.
  Widget _fieldLabelWithHelp(
    NightshadeColors colors, {
    required String label,
    required String helpTitle,
    required String helpBody,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: NightshadeTypography.labelSm
              .copyWith(color: colors.textSecondary),
        ),
        const SizedBox(width: NightshadeTokens.spaceXs),
        helpAffordance(context, title: helpTitle, body: helpBody),
      ],
    );
  }

  /// Open the telescope library (C10) and, on selection, prefill the OTA name,
  /// focal length, and aperture fields. Manual edits afterwards remain fully
  /// available — this is a one-tap convenience, not a lock-in.
  Future<void> _pickTelescopeFromLibrary() async {
    final preset = await HardwarePresetPickerDialog.showTelescope(context);
    if (preset == null || !mounted) return;
    setState(() {
      _telescopeNameController.text = preset.displayName;
      // The presets store whole-number optics as e.g. 550.0; render them as
      // plain integers when they have no fractional part to match how a user
      // would type the value.
      _focalLengthController.text = _formatOptic(preset.focalLengthMm);
      _apertureController.text = _formatOptic(preset.apertureMm);
    });
  }

  /// Format an optic dimension: integral values as a bare integer (e.g. `550`),
  /// otherwise with its decimal places (e.g. `714.5`).
  static String _formatOptic(double value) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
  }

  // ============================================================================
  // Section 3: Devices
  // ============================================================================

  Widget _buildDevicesSection(NightshadeColors colors, ThemeData theme) {
    final discovery = ref.watch(unifiedDiscoveryProvider);
    final cameras = discovery.getDevicesByType(DeviceType.camera);
    final mounts = discovery.getDevicesByType(DeviceType.mount);
    final focusers = discovery.getDevicesByType(DeviceType.focuser);
    final filterWheels = discovery.getDevicesByType(DeviceType.filterWheel);
    final guiders = discovery.getDevicesByType(DeviceType.guider);
    final rotators = discovery.getDevicesByType(DeviceType.rotator);
    final domes = discovery.getDevicesByType(DeviceType.dome);
    final weatherStations = discovery.getDevicesByType(DeviceType.weather);
    final safetyMonitors = discovery.getDevicesByType(DeviceType.safetyMonitor);
    final switches = discovery.getDevicesByType(DeviceType.switch_);
    final coverCalibrators =
        discovery.getDevicesByType(DeviceType.coverCalibrator);

    return _SectionCard(
      title: 'Devices',
      icon: LucideIcons.plugZap,
      isExpanded: _expandedSections['devices']!,
      onToggle: () => setState(
          () => _expandedSections['devices'] = !_expandedSections['devices']!),
      summary: _countAssignedDevices() > 0
          ? '${_countAssignedDevices()} assigned'
          : 'None assigned',
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Camera
          _DeviceRow(
            type: 'Camera',
            icon: LucideIcons.camera,
            nameController: _cameraNameController,
            deviceId: _cameraId,
            discoveredDevices: cameras,
            onDeviceSelected: (id, name) => setState(() {
              _cameraId = id;
              if (name != null && _cameraNameController.text.isEmpty) {
                _cameraNameController.text = name;
              }
            }),
            onClear: () => setState(() {
              _cameraId = null;
              _cameraNameController.clear();
            }),
            colors: colors,
          ),
          const SizedBox(height: 12),

          // Mount
          _DeviceRow(
            type: 'Mount',
            icon: LucideIcons.compass,
            nameController: _mountNameController,
            deviceId: _mountId,
            discoveredDevices: mounts,
            onDeviceSelected: (id, name) => setState(() {
              _mountId = id;
              if (name != null && _mountNameController.text.isEmpty) {
                _mountNameController.text = name;
              }
            }),
            onClear: () => setState(() {
              _mountId = null;
              _mountNameController.clear();
            }),
            colors: colors,
          ),
          const SizedBox(height: 12),

          // Focuser
          _DeviceRow(
            type: 'Focuser',
            icon: LucideIcons.focus,
            nameController: _focuserNameController,
            deviceId: _focuserId,
            discoveredDevices: focusers,
            onDeviceSelected: (id, name) => setState(() {
              _focuserId = id;
              if (name != null && _focuserNameController.text.isEmpty) {
                _focuserNameController.text = name;
              }
            }),
            onClear: () => setState(() {
              _focuserId = null;
              _focuserNameController.clear();
            }),
            colors: colors,
          ),
          const SizedBox(height: 12),

          // Filter Wheel
          _DeviceRow(
            type: 'Filter Wheel',
            icon: LucideIcons.disc,
            nameController: _filterWheelNameController,
            deviceId: _filterWheelId,
            discoveredDevices: filterWheels,
            onDeviceSelected: (id, name) => setState(() {
              _filterWheelId = id;
              if (name != null && _filterWheelNameController.text.isEmpty) {
                _filterWheelNameController.text = name;
              }
            }),
            onClear: () => setState(() {
              _filterWheelId = null;
              _filterWheelNameController.clear();
            }),
            colors: colors,
          ),
          const SizedBox(height: 12),

          // Guider
          _DeviceRow(
            type: 'Guider',
            icon: LucideIcons.crosshair,
            nameController: _guiderNameController,
            deviceId: _guiderId,
            discoveredDevices: guiders,
            onDeviceSelected: (id, name) => setState(() {
              _guiderId = id;
              if (name != null && _guiderNameController.text.isEmpty) {
                _guiderNameController.text = name;
              }
            }),
            onClear: () => setState(() {
              _guiderId = null;
              _guiderNameController.clear();
            }),
            colors: colors,
          ),
          const SizedBox(height: 12),

          // Rotator
          _DeviceRow(
            type: 'Rotator',
            icon: LucideIcons.rotateCcw,
            nameController: _rotatorNameController,
            deviceId: _rotatorId,
            discoveredDevices: rotators,
            onDeviceSelected: (id, name) => setState(() {
              _rotatorId = id;
              if (name != null && _rotatorNameController.text.isEmpty) {
                _rotatorNameController.text = name;
              }
            }),
            onClear: () => setState(() {
              _rotatorId = null;
              _rotatorNameController.clear();
            }),
            colors: colors,
          ),
          const SizedBox(height: 12),

          _DeviceRow(
            type: 'Dome',
            icon: LucideIcons.home,
            nameController: _domeNameController,
            deviceId: _domeId,
            discoveredDevices: domes,
            onDeviceSelected: (id, name) => setState(() {
              _domeId = id;
              if (name != null && _domeNameController.text.isEmpty) {
                _domeNameController.text = name;
              }
            }),
            onClear: () => setState(() {
              _domeId = null;
              _domeNameController.clear();
            }),
            colors: colors,
          ),
          const SizedBox(height: 12),

          _DeviceRow(
            type: 'Weather',
            icon: LucideIcons.cloud,
            nameController: _weatherNameController,
            deviceId: _weatherId,
            discoveredDevices: weatherStations,
            onDeviceSelected: (id, name) => setState(() {
              _weatherId = id;
              if (name != null && _weatherNameController.text.isEmpty) {
                _weatherNameController.text = name;
              }
            }),
            onClear: () => setState(() {
              _weatherId = null;
              _weatherNameController.clear();
            }),
            colors: colors,
          ),
          const SizedBox(height: 12),

          _DeviceRow(
            type: 'Safety Monitor',
            icon: LucideIcons.shieldCheck,
            nameController: _safetyMonitorNameController,
            deviceId: _safetyMonitorId,
            discoveredDevices: safetyMonitors,
            onDeviceSelected: (id, name) => setState(() {
              _safetyMonitorId = id;
              if (name != null && _safetyMonitorNameController.text.isEmpty) {
                _safetyMonitorNameController.text = name;
              }
            }),
            onClear: () => setState(() {
              _safetyMonitorId = null;
              _safetyMonitorNameController.clear();
            }),
            colors: colors,
          ),
          const SizedBox(height: 12),

          _DeviceRow(
            type: 'Switch',
            icon: LucideIcons.toggleLeft,
            nameController: _switchNameController,
            deviceId: _switchId,
            discoveredDevices: switches,
            onDeviceSelected: (id, name) => setState(() {
              _switchId = id;
              if (name != null && _switchNameController.text.isEmpty) {
                _switchNameController.text = name;
              }
            }),
            onClear: () => setState(() {
              _switchId = null;
              _switchNameController.clear();
            }),
            colors: colors,
          ),
          const SizedBox(height: 12),

          _DeviceRow(
            type: 'Cover / Calibrator',
            icon: LucideIcons.sunMedium,
            nameController: _coverCalibratorNameController,
            deviceId: _coverCalibratorId,
            discoveredDevices: coverCalibrators,
            onDeviceSelected: (id, name) => setState(() {
              _coverCalibratorId = id;
              if (name != null && _coverCalibratorNameController.text.isEmpty) {
                _coverCalibratorNameController.text = name;
              }
            }),
            onClear: () => setState(() {
              _coverCalibratorId = null;
              _coverCalibratorNameController.clear();
            }),
            colors: colors,
          ),
          const SizedBox(height: 16),

          // Add from connected button
          NightshadeButton(
            label: 'Add from connected',
            icon: LucideIcons.plus,
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: _populateFromConnected,
          ),
        ],
      ),
    );
  }

  int _countAssignedDevices() {
    int count = 0;
    if (_cameraId != null) count++;
    if (_mountId != null) count++;
    if (_focuserId != null) count++;
    if (_filterWheelId != null) count++;
    if (_guiderId != null) count++;
    if (_rotatorId != null) count++;
    if (_domeId != null) count++;
    if (_weatherId != null) count++;
    if (_safetyMonitorId != null) count++;
    if (_switchId != null) count++;
    if (_coverCalibratorId != null) count++;
    return count;
  }

  // ============================================================================
}
