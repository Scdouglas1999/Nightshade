// ignore_for_file: invalid_use_of_protected_member

part of '../profile_editor_dialog.dart';

extension _ProfileEditorFiltersAndCameraDefaults on _ProfileEditorDialogState {
  // Section 4: Filters
  // ============================================================================

  Widget _buildFiltersSection(NightshadeColors colors, ThemeData theme) {
    return _SectionCard(
      title: 'Filters (${_filterControllers.length} slots)',
      icon: LucideIcons.filter,
      isExpanded: _expandedSections['filters']!,
      onToggle: () => setState(
          () => _expandedSections['filters'] = !_expandedSections['filters']!),
      summary: _filterControllers.isEmpty
          ? 'No filters'
          : '${_filterControllers.length} filters',
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '#',
                    style: NightshadeTypography.h6.copyWith(color: colors.textMuted),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Filter Name',
                    style: NightshadeTypography.h6.copyWith(color: colors.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: dialogMaxWidth(context, 100),
                  child: Text(
                    'Focus Offset',
                    style: NightshadeTypography.h6.copyWith(color: colors.textMuted),
                  ),
                ),
                const SizedBox(width: 36), // Space for delete button
              ],
            ),
          ),

          // Filter rows
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(8)),
            ),
            child: Column(
              children: [
                if (_filterControllers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No filters configured',
                      style: TextStyle(color: colors.textMuted),
                    ),
                  )
                else
                  ..._filterControllers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final pair = entry.value;
                    return _FilterRow(
                      index: index + 1,
                      nameController: pair.nameController,
                      offsetController: pair.offsetController,
                      onRemove: () => _removeFilter(index),
                      isLast: index == _filterControllers.length - 1,
                      colors: colors,
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              NightshadeButton(
                label: 'Add Filter',
                icon: LucideIcons.plus,
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                onPressed: _addFilter,
              ),
              const Spacer(),
              NightshadeButton(
                label: 'Auto-detect from wheel',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                onPressed: _autoDetectFilters,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // Section 5: Camera Defaults
  // ============================================================================

  Widget _buildCameraDefaultsSection(NightshadeColors colors, ThemeData theme) {
    return _SectionCard(
      title: 'Camera Defaults',
      icon: LucideIcons.settings2,
      isExpanded: _expandedSections['camera']!,
      onToggle: () => setState(
          () => _expandedSections['camera'] = !_expandedSections['camera']!),
      summary:
          _gainController.text.isEmpty && _coolingTargetController.text.isEmpty
              ? 'Not configured'
              : 'Configured',
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gain, Offset, Binning row
          Row(
            children: [
              Expanded(
                child: NightshadeTextField(
                  label: 'Gain',
                  controller: _gainController,
                  hint: 'e.g., 100',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NightshadeTextField(
                  label: 'Offset',
                  controller: _offsetController,
                  hint: 'e.g., 10',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Binning',
                      style: NightshadeTypography.labelSm.copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                        border: Border.all(color: colors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _binning,
                          isExpanded: true,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          dropdownColor: colors.surfaceAlt,
                          style: TextStyle(
                              color: colors.textPrimary, fontSize: NightshadeTypography.fontSize13),
                          items: [1, 2, 3, 4].map((b) {
                            return DropdownMenuItem(
                              value: b,
                              child: Text('${b}x$b'),
                            );
                          }).toList(),
                          onChanged: (v) => setState(() => _binning = v ?? 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // IMG-P3-2: SDK auto-detect button + recommendation card.
          // The button is only useful when a camera is selected on this
          // profile (so we have a device_id to query).
          _buildAutoDetectRow(colors),
          if (_recommendedSettings != null)
            _buildRecommendationCard(colors, _recommendedSettings!),
          const SizedBox(height: 16),

          // Cooling row
          Row(
            children: [
              Expanded(
                child: NightshadeTextField(
                  label: 'Cooling Target',
                  controller: _coolingTargetController,
                  hint: 'e.g., -10',
                  suffix: '\u00B0C',
                  keyboardType: const TextInputType.numberWithOptions(
                      signed: true, decimal: true),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18), // Align with text field
                    Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                        border: Border.all(color: colors.border),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: CheckboxListTile(
                        value: _coolOnConnect,
                        onChanged: (v) =>
                            setState(() => _coolOnConnect = v ?? false),
                        title: Text(
                          'Cool on connect',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: NightshadeTypography.fontSize13,
                          ),
                        ),
                        activeColor: colors.primary,
                        checkColor: Theme.of(context).colorScheme.onPrimary,
                        controlAffinity: ListTileControlAffinity.trailing,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        dense: true,
                      ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Centering exposure
          Row(
            children: [
              Expanded(
                child: NightshadeTextField(
                  label: 'Centering Exposure',
                  controller: _centeringExposureController,
                  hint: 'e.g., 5',
                  suffix: 's',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18),
                    Text(
                      'Default exposure time used for plate-solve centering. '
                      'Can be adjusted per-session in the centering dialog.',
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: NightshadeTypography.fontSize11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // IMG-P3-2: Auto-detect recommended camera gain/offset
  // ===========================================================================

  /// Build the auto-detect button row.
  ///
  /// The button is enabled only when the user has selected (or auto-populated)
  /// a camera id for this profile AND that camera is currently connected.
  /// Without a live camera we have no SDK to query.
  Widget _buildAutoDetectRow(NightshadeColors colors) {
    final cameraState = ref.watch(cameraStateProvider);
    final liveDeviceId =
        cameraState.connectionState == DeviceConnectionState.connected
            ? cameraState.deviceId
            : null;
    // Prefer the connected camera's id when it matches what the profile has
    // selected; otherwise fall back to the live device.
    final queryDeviceId = (_cameraId != null && _cameraId == liveDeviceId)
        ? _cameraId
        : liveDeviceId;

    final enabled = queryDeviceId != null && !_isQueryingRecommendation;
    final disabledReason = queryDeviceId == null
        ? 'Connect a camera to query its SDK for recommended gain/offset.'
        : null;

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Tooltip(
          message: disabledReason ??
              'Query the connected camera SDK for the '
                  'manufacturer-recommended unity gain and offset.',
          child: NightshadeButton(
            onPressed: enabled ? () => _runAutoDetect(queryDeviceId) : null,
            icon: LucideIcons.zap,
            label: 'Auto-detect from camera',
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            isLoading: _isQueryingRecommendation,
          ),
        ),
        // Camera library (C10): a curated fallback that does NOT require a live
        // camera. It complements the SDK auto-detect above — the user can pull
        // sensible gain/offset (+ binning, cooling) from the built-in catalog
        // even when no camera is connected.
        NightshadeButton(
          label: 'Camera library',
          icon: LucideIcons.camera,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: _pickCameraFromLibrary,
        ),
        if (disabledReason != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              disabledReason,
              style: TextStyle(color: colors.textMuted, fontSize: NightshadeTypography.fontSize11),
            ),
          ),
      ],
    );
  }

  /// Open the camera library (C10) and, on selection, prefill the camera
  /// defaults: gain, offset, binning, and (when the preset has regulated
  /// cooling) the cooling set-point. Cameras without cooling leave the cooling
  /// field untouched rather than collapsing it to 0 °C.
  Future<void> _pickCameraFromLibrary() async {
    final preset = await HardwarePresetPickerDialog.showCamera(context);
    if (preset == null || !mounted) return;
    setState(() {
      _gainController.text = preset.recommendedGain.toString();
      _offsetController.text = preset.recommendedOffset.toString();
      // The binning dropdown is square (binX == binY) in this editor; presets
      // store the recommended X binning, which we apply directly when it is one
      // of the offered factors.
      if (preset.recommendedBinX >= 1 && preset.recommendedBinX <= 4) {
        _binning = preset.recommendedBinX;
      }
      final coolingTemp = preset.recommendedCoolingTempC;
      if (coolingTemp != null) {
        _coolingTargetController.text =
            _ProfileEditorOpticalAndDevices._formatOptic(coolingTemp);
      }
    });
  }

  /// Build the info card that surfaces the SDK-reported recommendation.
  ///
  /// All values are shown verbatim â€” the field is "Not reported" when the SDK
  /// returns null for it (we never invent a value to fill the gap).
  Widget _buildRecommendationCard(
      NightshadeColors colors, CameraRecommendedSettings rec) {
    final hasAny = rec.unityGain != null || rec.defaultOffset != null;
    final canApplyGain = rec.unityGain != null &&
        rec.unityGain.toString() != _gainController.text;
    final canApplyOffset = rec.defaultOffset != null &&
        rec.defaultOffset.toString() != _offsetController.text;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: NightshadeCard(
        variant: CardVariant.standard,
        borderRadius: NightshadeTokens.radiusInline8,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasAny ? LucideIcons.info : LucideIcons.alertCircle,
                size: 14,
                color: hasAny ? colors.primary : colors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                hasAny
                    ? 'Camera SDK reported:'
                    : 'Camera SDK did not report any recommendation',
                style: NightshadeTypography.h6.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
          if (hasAny) ...[
            const SizedBox(height: 6),
            _buildRecRow('Unity gain', rec.unityGain, colors),
            _buildRecRow('HCG gain', rec.hcgGain, colors),
            _buildRecRow('Default offset', rec.defaultOffset, colors),
          ],
          if (rec.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              rec.notes,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                fontStyle: FontStyle.italic,
                color: colors.textMuted,
              ),
            ),
          ],
          if (canApplyGain || canApplyOffset) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                NightshadeButton(
                  onPressed: () => _applyRecommendation(rec),
                  icon: LucideIcons.check,
                  label:
                      'Apply${(canApplyGain && canApplyOffset) ? ' both' : canApplyGain ? ' gain' : ' offset'}',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
              ],
            ),
          ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecRow(String label, int? value, NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textSecondary),
            ),
          ),
          Text(
            value == null ? 'Not reported' : value.toString(),
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: value == null ? colors.textMuted : colors.textPrimary,
              fontWeight: value == null ? FontWeight.normal : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runAutoDetect(String deviceId) async {
    setState(() {
      _isQueryingRecommendation = true;
    });
    try {
      final rec = await ref
          .read(deviceServiceProvider)
          .queryRecommendedCameraSettings(deviceId);
      if (!mounted) return;
      setState(() {
        _recommendedSettings = rec;
      });
    } catch (e) {
      if (!mounted) return;
      // Surface the failure to the user â€” never silently fall back.
      context.showErrorSnackBar('Auto-detect failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isQueryingRecommendation = false;
        });
      }
    }
  }

  void _applyRecommendation(CameraRecommendedSettings rec) {
    setState(() {
      if (rec.unityGain != null) {
        _gainController.text = rec.unityGain.toString();
      }
      if (rec.defaultOffset != null) {
        _offsetController.text = rec.defaultOffset.toString();
      }
    });
  }
}
