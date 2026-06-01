// ignore_for_file: invalid_use_of_protected_member

part of '../profile_editor_dialog.dart';

extension _ProfileEditorDataOperations on _ProfileEditorDialogState {
  // Computed values for optical train
  double? get _computedFRatio {
    final focalLength = double.tryParse(_focalLengthController.text);
    final aperture = double.tryParse(_apertureController.text);
    if (focalLength != null && aperture != null && aperture > 0) {
      return focalLength / aperture;
    }
    return null;
  }

  double? get _computedScale {
    final focalLength = double.tryParse(_focalLengthController.text);
    if (focalLength == null || focalLength <= 0) return null;
    // Try to get pixel size from connected camera
    final cameraState = ref.read(cameraStateProvider);
    if (cameraState.connectionState == DeviceConnectionState.connected &&
        cameraState.deviceId != null) {
      final capabilitiesAsync =
          ref.read(cameraCapabilitiesProvider(cameraState.deviceId!));
      final capabilities = capabilitiesAsync.valueOrNull;
      final pixelSize = capabilities?.pixelSizeX;
      if (pixelSize != null && pixelSize > 0) {
        return (pixelSize / focalLength) * 206.265;
      }
    }
    return null;
  }

  double? get _pixelSize {
    final cameraState = ref.read(cameraStateProvider);
    if (cameraState.connectionState == DeviceConnectionState.connected &&
        cameraState.deviceId != null) {
      final capabilitiesAsync =
          ref.read(cameraCapabilitiesProvider(cameraState.deviceId!));
      final capabilities = capabilitiesAsync.valueOrNull;
      final pixelSize = capabilities?.pixelSizeX;
      if (pixelSize != null && pixelSize > 0) {
        return pixelSize;
      }
    }
    return null;
  }

  void _addFilter() {
    setState(() {
      _filterControllers.add(_FilterControllerPair(
        nameController: TextEditingController(
            text: 'Filter ${_filterControllers.length + 1}'),
        offsetController: TextEditingController(text: '0'),
      ));
    });
  }

  void _removeFilter(int index) {
    setState(() {
      _filterControllers[index].dispose();
      _filterControllers.removeAt(index);
    });
  }

  Future<void> _autoDetectFilters() async {
    final filterWheelState = ref.read(filterWheelStateProvider);
    if (filterWheelState.connectionState != DeviceConnectionState.connected) {
      return;
    }

    final deviceId = filterWheelState.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      return;
    }

    // Read filter names directly from hardware to avoid profile-overridden state
    // (which may have a different count than the actual wheel)
    List<String> filterNames;
    try {
      final backend = ref.read(deviceBackendProvider);
      final status = await backend.getFilterWheelStatus(deviceId);
      filterNames = status.filterNames;
    } catch (error, stack) {
      ref.read(loggingServiceProvider).warning(
        'ProfileEditorDialog: hardware filter-name query failed for '
        '$deviceId. Falling back to cached provider state. Error=$error',
        source: 'ProfileEditorDialog',
        fields: {'error': error.toString(), 'stack': stack.toString()},
      );
      // Fall back to state if hardware query fails
      filterNames = filterWheelState.filterNames;
    }

    if (filterNames.isNotEmpty && mounted) {
      setState(() {
        // Clear existing filters
        for (final pair in _filterControllers) {
          pair.dispose();
        }
        _filterControllers.clear();
        // Add filters from connected wheel
        for (final name in filterNames) {
          _filterControllers.add(_FilterControllerPair(
            nameController: TextEditingController(text: name),
            offsetController: TextEditingController(text: '0'),
          ));
        }
      });
    }
  }

  void _populateFromConnected() {
    final cameraState = ref.read(cameraStateProvider);
    final mountState = ref.read(mountStateProvider);
    final focuserState = ref.read(focuserStateProvider);
    final filterWheelState = ref.read(filterWheelStateProvider);
    final guiderState = ref.read(guiderStateProvider);
    final rotatorState = ref.read(rotatorStateProvider);
    final domeState = ref.read(domeStateProvider);
    final weatherState = ref.read(weatherStateProvider);
    final safetyMonitorState = ref.read(safetyMonitorStateProvider);
    final switchState = ref.read(switchStateProvider);
    final coverCalibratorState = ref.read(coverCalibratorStateProvider);

    setState(() {
      // Camera
      if (_cameraId == null &&
          cameraState.connectionState == DeviceConnectionState.connected) {
        _cameraId = cameraState.deviceId;
        if (_cameraNameController.text.isEmpty) {
          _cameraNameController.text =
              cameraState.deviceName ?? cameraState.deviceId ?? '';
        }
      }

      // Mount
      if (_mountId == null &&
          mountState.connectionState == DeviceConnectionState.connected) {
        _mountId = mountState.deviceId;
        if (_mountNameController.text.isEmpty) {
          _mountNameController.text =
              mountState.deviceName ?? mountState.deviceId ?? '';
        }
      }

      // Focuser
      if (_focuserId == null &&
          focuserState.connectionState == DeviceConnectionState.connected) {
        _focuserId = focuserState.deviceId;
        if (_focuserNameController.text.isEmpty) {
          _focuserNameController.text =
              focuserState.deviceName ?? focuserState.deviceId ?? '';
        }
      }

      // Filter Wheel
      if (_filterWheelId == null &&
          filterWheelState.connectionState == DeviceConnectionState.connected) {
        _filterWheelId = filterWheelState.deviceId;
        if (_filterWheelNameController.text.isEmpty) {
          _filterWheelNameController.text =
              filterWheelState.deviceName ?? filterWheelState.deviceId ?? '';
        }
        // Also populate filters
        if (_filterControllers.isEmpty &&
            filterWheelState.filterNames.isNotEmpty) {
          _autoDetectFilters();
        }
      }

      // Guider
      if (_guiderId == null &&
          guiderState.connectionState == DeviceConnectionState.connected) {
        _guiderId = guiderState.deviceId;
        if (_guiderNameController.text.isEmpty) {
          _guiderNameController.text =
              guiderState.deviceName ?? guiderState.deviceId ?? '';
        }
      }

      // Rotator
      if (_rotatorId == null &&
          rotatorState.connectionState == DeviceConnectionState.connected) {
        _rotatorId = rotatorState.deviceId;
        if (_rotatorNameController.text.isEmpty) {
          _rotatorNameController.text =
              rotatorState.deviceName ?? rotatorState.deviceId ?? '';
        }
      }

      if (_domeId == null &&
          domeState.connectionState == DeviceConnectionState.connected) {
        _domeId = domeState.deviceId;
        if (_domeNameController.text.isEmpty) {
          _domeNameController.text =
              domeState.deviceName ?? domeState.deviceId ?? '';
        }
      }

      if (_weatherId == null &&
          weatherState.connectionState == DeviceConnectionState.connected) {
        _weatherId = weatherState.deviceId;
        if (_weatherNameController.text.isEmpty) {
          _weatherNameController.text =
              weatherState.deviceName ?? weatherState.deviceId ?? '';
        }
      }

      if (_safetyMonitorId == null &&
          safetyMonitorState.connectionState ==
              DeviceConnectionState.connected) {
        _safetyMonitorId = safetyMonitorState.deviceId;
        if (_safetyMonitorNameController.text.isEmpty) {
          _safetyMonitorNameController.text = safetyMonitorState.deviceName ??
              safetyMonitorState.deviceId ??
              '';
        }
      }

      if (_switchId == null &&
          switchState.connectionState == DeviceConnectionState.connected) {
        _switchId = switchState.deviceId;
        if (_switchNameController.text.isEmpty) {
          _switchNameController.text =
              switchState.deviceName ?? switchState.deviceId ?? '';
        }
      }

      if (_coverCalibratorId == null &&
          coverCalibratorState.connectionState ==
              DeviceConnectionState.connected) {
        _coverCalibratorId = coverCalibratorState.deviceId;
        if (_coverCalibratorNameController.text.isEmpty) {
          _coverCalibratorNameController.text =
              coverCalibratorState.deviceName ??
                  coverCalibratorState.deviceId ??
                  '';
        }
      }
    });
  }

  String _encodeFilterNames() {
    if (_filterControllers.isEmpty) return '';
    final names =
        _filterControllers.map((c) => c.nameController.text.trim()).toList();
    return jsonEncode(names);
  }

  String _encodeFilterOffsets() {
    if (_filterControllers.isEmpty) return '';
    final offsets = <String, int>{};
    for (final pair in _filterControllers) {
      final name = pair.nameController.text.trim();
      final offset = int.tryParse(pair.offsetController.text) ?? 0;
      if (name.isNotEmpty && offset != 0) {
        offsets[name] = offset;
      }
    }
    return offsets.isNotEmpty ? jsonEncode(offsets) : '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final dao = ref.read(equipmentProfilesDaoProvider);

      // Parse numerical values
      final focalLength = double.tryParse(_focalLengthController.text) ?? 0.0;
      final aperture = double.tryParse(_apertureController.text) ?? 0.0;
      final fRatio = aperture > 0 ? focalLength / aperture : null;

      // Build filter data
      final filterNamesEncoded = _encodeFilterNames();
      final filterOffsetsEncoded = _encodeFilterOffsets();

      if (widget.profile != null) {
        // Update existing profile
        final existingProfile = await dao.getProfileById(widget.profile!.id!);
        if (existingProfile == null) {
          throw Exception('Profile not found');
        }

        final updated = existingProfile.copyWith(
          name: _nameController.text.trim(),
          profileIcon: Value(_selectedIcon.isEmpty ? null : _selectedIcon),
          profileColor: Value(_selectedColor?.toARGB32()),
          isDefault: _isDefault,
          telescopeName: Value(_telescopeNameController.text.trimOrNull),
          telescopeFocalLength:
              Value(double.tryParse(_focalLengthController.text)),
          telescopeAperture: Value(double.tryParse(_apertureController.text)),
          focalLength: focalLength,
          aperture: aperture,
          focalRatio: Value(fRatio),
          cameraId: Value(_cameraId),
          cameraName: Value(_cameraNameController.text.trimOrNull),
          mountId: Value(_mountId),
          mountName: Value(_mountNameController.text.trimOrNull),
          focuserId: Value(_focuserId),
          focuserName: Value(_focuserNameController.text.trimOrNull),
          filterWheelId: Value(_filterWheelId),
          filterWheelName: Value(_filterWheelNameController.text.trimOrNull),
          guiderId: Value(_guiderId),
          guiderName: Value(_guiderNameController.text.trimOrNull),
          rotatorId: Value(_rotatorId),
          rotatorName: Value(_rotatorNameController.text.trimOrNull),
          domeId: Value(_domeId),
          weatherId: Value(_weatherId),
          safetyMonitorId: Value(_safetyMonitorId),
          switchId: Value(_switchId),
          coverCalibratorId: Value(_coverCalibratorId),
          filterNames:
              Value(filterNamesEncoded.isEmpty ? null : filterNamesEncoded),
          filterFocusOffsets:
              Value(filterOffsetsEncoded.isEmpty ? null : filterOffsetsEncoded),
          defaultGain: Value(int.tryParse(_gainController.text)),
          defaultOffset: Value(int.tryParse(_offsetController.text)),
          defaultBinX: _binning,
          defaultBinY: _binning,
          defaultCoolingTemp:
              Value(double.tryParse(_coolingTargetController.text)),
          coolOnConnect: _coolOnConnect,
          defaultCenteringExposure:
              Value(double.tryParse(_centeringExposureController.text)),
          updatedAt: DateTime.now(),
        );

        await dao.updateProfile(updated);

        // Handle isDefault
        if (_isDefault && !existingProfile.isDefault) {
          await dao.setDefaultProfile(existingProfile.id, makeActive: true);
        } else if (!_isDefault && existingProfile.isDefault) {
          await dao.clearDefaultProfile();
        }
      } else {
        // Create new profile
        final companion = EquipmentProfilesCompanion(
          name: Value(_nameController.text.trim()),
          profileIcon: Value(_selectedIcon.isEmpty ? null : _selectedIcon),
          profileColor: Value(_selectedColor?.toARGB32()),
          isDefault: Value(_isDefault),
          telescopeName: Value(_telescopeNameController.text.trimOrNull),
          telescopeFocalLength:
              Value(double.tryParse(_focalLengthController.text)),
          telescopeAperture: Value(double.tryParse(_apertureController.text)),
          focalLength: Value(focalLength),
          aperture: Value(aperture),
          focalRatio: Value(fRatio),
          cameraId: Value(_cameraId),
          cameraName: Value(_cameraNameController.text.trimOrNull),
          mountId: Value(_mountId),
          mountName: Value(_mountNameController.text.trimOrNull),
          focuserId: Value(_focuserId),
          focuserName: Value(_focuserNameController.text.trimOrNull),
          filterWheelId: Value(_filterWheelId),
          filterWheelName: Value(_filterWheelNameController.text.trimOrNull),
          guiderId: Value(_guiderId),
          guiderName: Value(_guiderNameController.text.trimOrNull),
          rotatorId: Value(_rotatorId),
          rotatorName: Value(_rotatorNameController.text.trimOrNull),
          domeId: Value(_domeId),
          weatherId: Value(_weatherId),
          safetyMonitorId: Value(_safetyMonitorId),
          switchId: Value(_switchId),
          coverCalibratorId: Value(_coverCalibratorId),
          filterNames:
              Value(filterNamesEncoded.isEmpty ? null : filterNamesEncoded),
          filterFocusOffsets:
              Value(filterOffsetsEncoded.isEmpty ? null : filterOffsetsEncoded),
          defaultGain: Value(int.tryParse(_gainController.text)),
          defaultOffset: Value(int.tryParse(_offsetController.text)),
          defaultBinX: Value(_binning),
          defaultBinY: Value(_binning),
          defaultCoolingTemp:
              Value(double.tryParse(_coolingTargetController.text)),
          coolOnConnect: Value(_coolOnConnect),
          defaultCenteringExposure:
              Value(double.tryParse(_centeringExposureController.text)),
        );

        final newId = await dao.createProfile(companion);

        // Set as default if requested
        if (_isDefault) {
          await dao.setDefaultProfile(newId, makeActive: true);
        }
      }

      if (mounted) {
        final action = widget.profile != null ? 'updated' : 'created';
        context.showSuccessSnackBar(
            'Profile "${_nameController.text.trim()}" $action');
        Navigator.of(context).pop(true);
      }
    } catch (e, st) {
      ref.read(loggingServiceProvider).error(
        'ProfileEditorDialog save failed: $e',
        source: 'ProfileEditorDialog',
        fields: {'error': e.toString(), 'stack': st.toString()},
      );
      if (mounted) {
        context.showErrorSnackBar(profileSaveErrorMessage(e));
        setState(() => _isSaving = false);
      }
    }
  }
}
