import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';

/// Single-page profile editor dialog replacing the multi-step wizard.
/// Allows creating new profiles or editing existing ones.
class ProfileEditorDialog extends ConsumerStatefulWidget {
  /// The profile to edit, or null to create a new profile.
  final EquipmentProfileModel? profile;

  const ProfileEditorDialog({super.key, this.profile});

  /// Show the profile editor dialog.
  /// Returns true if a profile was created/updated, false/null if cancelled.
  static Future<bool?> show(BuildContext context, {EquipmentProfileModel? profile}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProfileEditorDialog(profile: profile),
    );
  }

  @override
  ConsumerState<ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends ConsumerState<ProfileEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  // Track which sections are expanded
  final Map<String, bool> _expandedSections = {
    'identity': true,
    'optical': true,
    'devices': true,
    'filters': true,
    'camera': true,
  };

  // Section 1: Profile Identity
  final _nameController = TextEditingController();
  String _selectedIcon = '';
  Color? _selectedColor;
  bool _isDefault = false;

  // Section 2: Optical Train
  final _telescopeNameController = TextEditingController();
  final _focalLengthController = TextEditingController();
  final _apertureController = TextEditingController();

  // Section 3: Devices
  final _cameraNameController = TextEditingController();
  final _mountNameController = TextEditingController();
  final _focuserNameController = TextEditingController();
  final _filterWheelNameController = TextEditingController();
  final _guiderNameController = TextEditingController();
  final _rotatorNameController = TextEditingController();

  String? _cameraId;
  String? _mountId;
  String? _focuserId;
  String? _filterWheelId;
  String? _guiderId;
  String? _rotatorId;

  // Section 4: Filters (dynamic list)
  final List<_FilterControllerPair> _filterControllers = [];

  // Section 5: Camera Defaults
  final _gainController = TextEditingController();
  final _offsetController = TextEditingController();
  int _binning = 1;
  final _coolingTargetController = TextEditingController();
  bool _coolOnConnect = false;

  // Available icons for profile customization
  static const List<String> _availableIcons = [
    '',
    '\u{1F52D}', // Telescope emoji
    '\u{1F319}', // Moon emoji
    '\u{1FA90}', // Ringed planet emoji
    '\u{2B50}', // Star emoji
    '\u{1F4F7}', // Camera emoji
    '\u{1F534}', // Red circle
    '\u{1F535}', // Blue circle
    '\u{1F7E2}', // Green circle
    '\u{1F7E1}', // Yellow circle
  ];

  // Available accent colors
  static const List<Color> _accentColors = [
    Color(0xFF6366F1), // Indigo (default)
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFFEF4444), // Red
    Color(0xFFF97316), // Orange
    Color(0xFFEAB308), // Yellow
    Color(0xFF22C55E), // Green
    Color(0xFF06B6D4), // Cyan
    Color(0xFF3B82F6), // Blue
  ];

  @override
  void initState() {
    super.initState();
    _initializeFromProfile();
  }

  void _initializeFromProfile() {
    final profile = widget.profile;
    if (profile != null) {
      // Section 1: Identity
      _nameController.text = profile.name;
      _selectedIcon = profile.profileIcon ?? '';
      _selectedColor = profile.profileColor != null ? Color(profile.profileColor!) : null;
      _isDefault = profile.isDefault;

      // Section 2: Optical Train
      _telescopeNameController.text = profile.telescopeName ?? '';
      if (profile.telescopeFocalLength != null && profile.telescopeFocalLength! > 0) {
        _focalLengthController.text = profile.telescopeFocalLength!.toString();
      } else if (profile.focalLength > 0) {
        _focalLengthController.text = profile.focalLength.toString();
      }
      if (profile.telescopeAperture != null && profile.telescopeAperture! > 0) {
        _apertureController.text = profile.telescopeAperture!.toString();
      } else if (profile.aperture > 0) {
        _apertureController.text = profile.aperture.toString();
      }

      // Section 3: Devices
      _cameraId = profile.cameraId;
      _cameraNameController.text = profile.cameraName ?? '';
      _mountId = profile.mountId;
      _mountNameController.text = profile.mountName ?? '';
      _focuserId = profile.focuserId;
      _focuserNameController.text = profile.focuserName ?? '';
      _filterWheelId = profile.filterWheelId;
      _filterWheelNameController.text = profile.filterWheelName ?? '';
      _guiderId = profile.guiderId;
      _guiderNameController.text = profile.guiderName ?? '';
      _rotatorId = profile.rotatorId;
      _rotatorNameController.text = profile.rotatorName ?? '';

      // Section 4: Filters
      for (int i = 0; i < profile.filterNames.length; i++) {
        final offset = profile.filterFocusOffsets[profile.filterNames[i]] ?? 0;
        _filterControllers.add(_FilterControllerPair(
          nameController: TextEditingController(text: profile.filterNames[i]),
          offsetController: TextEditingController(text: offset.toString()),
        ));
      }

      // Section 5: Camera Defaults
      if (profile.defaultGain != null) {
        _gainController.text = profile.defaultGain!.toString();
      }
      if (profile.defaultOffset != null) {
        _offsetController.text = profile.defaultOffset!.toString();
      }
      _binning = profile.defaultBinX;
      if (profile.defaultCoolingTemp != null) {
        _coolingTargetController.text = profile.defaultCoolingTemp!.toString();
      }
      _coolOnConnect = profile.coolOnConnect;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _telescopeNameController.dispose();
    _focalLengthController.dispose();
    _apertureController.dispose();
    _cameraNameController.dispose();
    _mountNameController.dispose();
    _focuserNameController.dispose();
    _filterWheelNameController.dispose();
    _guiderNameController.dispose();
    _rotatorNameController.dispose();
    _gainController.dispose();
    _offsetController.dispose();
    _coolingTargetController.dispose();
    for (final pair in _filterControllers) {
      pair.dispose();
    }
    super.dispose();
  }

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
      final capabilitiesAsync = ref.read(cameraCapabilitiesProvider(cameraState.deviceId!));
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
      final capabilitiesAsync = ref.read(cameraCapabilitiesProvider(cameraState.deviceId!));
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
        nameController: TextEditingController(text: 'Filter ${_filterControllers.length + 1}'),
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
    if (filterWheelState.connectionState != DeviceConnectionState.connected) return;

    final deviceId = filterWheelState.deviceId;
    if (deviceId == null || deviceId.isEmpty) return;

    // Read filter names directly from hardware to avoid profile-overridden state
    // (which may have a different count than the actual wheel)
    List<String> filterNames;
    try {
      final backend = ref.read(backendProvider);
      final status = await backend.getFilterWheelStatus(deviceId);
      filterNames = status.filterNames;
    } catch (_) {
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

    setState(() {
      // Camera
      if (_cameraId == null && cameraState.connectionState == DeviceConnectionState.connected) {
        _cameraId = cameraState.deviceId;
        if (_cameraNameController.text.isEmpty) {
          _cameraNameController.text = cameraState.deviceName ?? cameraState.deviceId ?? '';
        }
      }

      // Mount
      if (_mountId == null && mountState.connectionState == DeviceConnectionState.connected) {
        _mountId = mountState.deviceId;
        if (_mountNameController.text.isEmpty) {
          _mountNameController.text = mountState.deviceName ?? mountState.deviceId ?? '';
        }
      }

      // Focuser
      if (_focuserId == null && focuserState.connectionState == DeviceConnectionState.connected) {
        _focuserId = focuserState.deviceId;
        if (_focuserNameController.text.isEmpty) {
          _focuserNameController.text = focuserState.deviceName ?? focuserState.deviceId ?? '';
        }
      }

      // Filter Wheel
      if (_filterWheelId == null && filterWheelState.connectionState == DeviceConnectionState.connected) {
        _filterWheelId = filterWheelState.deviceId;
        if (_filterWheelNameController.text.isEmpty) {
          _filterWheelNameController.text = filterWheelState.deviceName ?? filterWheelState.deviceId ?? '';
        }
        // Also populate filters
        if (_filterControllers.isEmpty && filterWheelState.filterNames.isNotEmpty) {
          _autoDetectFilters();
        }
      }

      // Guider
      if (_guiderId == null && guiderState.connectionState == DeviceConnectionState.connected) {
        _guiderId = guiderState.deviceId;
        if (_guiderNameController.text.isEmpty) {
          _guiderNameController.text = guiderState.deviceName ?? guiderState.deviceId ?? '';
        }
      }

      // Rotator
      if (_rotatorId == null && rotatorState.connectionState == DeviceConnectionState.connected) {
        _rotatorId = rotatorState.deviceId;
        if (_rotatorNameController.text.isEmpty) {
          _rotatorNameController.text = rotatorState.deviceName ?? rotatorState.deviceId ?? '';
        }
      }
    });
  }

  String _encodeFilterNames() {
    if (_filterControllers.isEmpty) return '';
    final names = _filterControllers.map((c) => c.nameController.text.trim()).toList();
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
          telescopeFocalLength: Value(double.tryParse(_focalLengthController.text)),
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
          filterNames: Value(filterNamesEncoded.isEmpty ? null : filterNamesEncoded),
          filterFocusOffsets: Value(filterOffsetsEncoded.isEmpty ? null : filterOffsetsEncoded),
          defaultGain: Value(int.tryParse(_gainController.text)),
          defaultOffset: Value(int.tryParse(_offsetController.text)),
          defaultBinX: _binning,
          defaultBinY: _binning,
          defaultCoolingTemp: Value(double.tryParse(_coolingTargetController.text)),
          coolOnConnect: _coolOnConnect,
          updatedAt: DateTime.now(),
        );

        await dao.updateProfile(updated);

        // Handle isDefault
        if (_isDefault && !existingProfile.isDefault) {
          await dao.setActiveProfile(existingProfile.id);
        }
      } else {
        // Create new profile
        final companion = EquipmentProfilesCompanion(
          name: Value(_nameController.text.trim()),
          profileIcon: Value(_selectedIcon.isEmpty ? null : _selectedIcon),
          profileColor: Value(_selectedColor?.toARGB32()),
          isDefault: Value(_isDefault),
          telescopeName: Value(_telescopeNameController.text.trimOrNull),
          telescopeFocalLength: Value(double.tryParse(_focalLengthController.text)),
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
          filterNames: Value(filterNamesEncoded.isEmpty ? null : filterNamesEncoded),
          filterFocusOffsets: Value(filterOffsetsEncoded.isEmpty ? null : filterOffsetsEncoded),
          defaultGain: Value(int.tryParse(_gainController.text)),
          defaultOffset: Value(int.tryParse(_offsetController.text)),
          defaultBinX: Value(_binning),
          defaultBinY: Value(_binning),
          defaultCoolingTemp: Value(double.tryParse(_coolingTargetController.text)),
          coolOnConnect: Value(_coolOnConnect),
        );

        final newId = await dao.createProfile(companion);

        // Set as default if requested
        if (_isDefault) {
          await dao.setActiveProfile(newId);
        }
      }

      if (mounted) {
        final action = widget.profile != null ? 'updated' : 'created';
        context.showSuccessSnackBar('Profile "${_nameController.text.trim()}" $action');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to save profile: $e');
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);
    final isEditing = widget.profile != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(colors, theme, isEditing),

            // Scrollable content
            Flexible(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildIdentitySection(colors, theme),
                      const SizedBox(height: 16),
                      _buildOpticalTrainSection(colors, theme),
                      const SizedBox(height: 16),
                      _buildDevicesSection(colors, theme),
                      if (_filterWheelId != null) ...[
                        const SizedBox(height: 16),
                        _buildFiltersSection(colors, theme),
                      ],
                      const SizedBox(height: 16),
                      _buildCameraDefaultsSection(colors, theme),
                    ],
                  ),
                ),
              ),
            ),

            // Footer
            _buildFooter(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NightshadeColors colors, ThemeData theme, bool isEditing) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
            ),
            child: Icon(
              isEditing ? LucideIcons.edit : LucideIcons.plus,
              color: colors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Edit Profile' : 'New Profile',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isEditing
                      ? 'Modify your equipment configuration'
                      : 'Create a new equipment configuration',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
            icon: Icon(LucideIcons.x, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          NightshadeButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
          ),
          const SizedBox(width: 12),
          NightshadeButton(
            onPressed: _isSaving ? null : _save,
            label: 'Save Changes',
            icon: LucideIcons.check,
            variant: ButtonVariant.primary,
            isLoading: _isSaving,
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // Section 1: Profile Identity
  // ============================================================================

  Widget _buildIdentitySection(NightshadeColors colors, ThemeData theme) {
    return _SectionCard(
      title: 'Profile Identity',
      icon: LucideIcons.user,
      isExpanded: _expandedSections['identity']!,
      onToggle: () => setState(() => _expandedSections['identity'] = !_expandedSections['identity']!),
      summary: _nameController.text.isEmpty ? 'Unnamed' : _nameController.text,
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name field
          NightshadeTextField(
            label: 'Profile Name *',
            controller: _nameController,
            hint: 'e.g., Main Imaging Rig, Widefield Setup',
            errorText: _nameController.text.isEmpty && _isSaving ? 'Name is required' : null,
          ),
          const SizedBox(height: 20),

          // Icon picker
          Text(
            'Icon',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableIcons.map((icon) {
              final isSelected = _selectedIcon == icon;
              return _IconOption(
                icon: icon,
                isSelected: isSelected,
                onTap: () => setState(() => _selectedIcon = icon),
                colors: colors,
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Color picker
          Text(
            'Accent Color',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // None option
              _ColorOption(
                color: null,
                isSelected: _selectedColor == null,
                onTap: () => setState(() => _selectedColor = null),
                colors: colors,
              ),
              ..._accentColors.map((color) {
                final isSelected = _selectedColor == color;
                return _ColorOption(
                  color: color,
                  isSelected: isSelected,
                  onTap: () => setState(() => _selectedColor = color),
                  colors: colors,
                );
              }),
            ],
          ),
          const SizedBox(height: 16),

          // Default checkbox
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: CheckboxListTile(
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v ?? false),
              title: Text(
                'Default profile',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                'Set as active profile on startup',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                ),
              ),
              activeColor: colors.primary,
              checkColor: Colors.white,
              controlAffinity: ListTileControlAffinity.trailing,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // Section 2: Optical Train
  // ============================================================================

  Widget _buildOpticalTrainSection(NightshadeColors colors, ThemeData theme) {
    return _SectionCard(
      title: 'Optical Train',
      icon: LucideIcons.target,
      isExpanded: _expandedSections['optical']!,
      onToggle: () => setState(() => _expandedSections['optical'] = !_expandedSections['optical']!),
      summary: _telescopeNameController.text.isEmpty
          ? 'Not configured'
          : _telescopeNameController.text,
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Telescope name
          NightshadeTextField(
            label: 'Telescope / OTA',
            controller: _telescopeNameController,
            hint: 'e.g., Esprit 100ED, RC8',
          ),
          const SizedBox(height: 16),

          // Focal length and aperture row
          Row(
            children: [
              Expanded(
                child: NightshadeTextField(
                  label: 'Focal Length',
                  controller: _focalLengthController,
                  hint: 'e.g., 550',
                  suffix: 'mm',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: NightshadeTextField(
                  label: 'Aperture',
                  controller: _apertureController,
                  hint: 'e.g., 100',
                  suffix: 'mm',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Computed values
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
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

    return _SectionCard(
      title: 'Devices',
      icon: LucideIcons.plugZap,
      isExpanded: _expandedSections['devices']!,
      onToggle: () => setState(() => _expandedSections['devices'] = !_expandedSections['devices']!),
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
    return count;
  }

  // ============================================================================
  // Section 4: Filters
  // ============================================================================

  Widget _buildFiltersSection(NightshadeColors colors, ThemeData theme) {
    return _SectionCard(
      title: 'Filters (${_filterControllers.length} slots)',
      icon: LucideIcons.filter,
      isExpanded: _expandedSections['filters']!,
      onToggle: () => setState(() => _expandedSections['filters'] = !_expandedSections['filters']!),
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '#',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Filter Name',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: Text(
                    'Focus Offset',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
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
      onToggle: () => setState(() => _expandedSections['camera'] = !_expandedSections['camera']!),
      summary: _gainController.text.isEmpty && _coolingTargetController.text.isEmpty
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
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _binning,
                          isExpanded: true,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          dropdownColor: colors.surfaceAlt,
                          style: TextStyle(color: colors.textPrimary, fontSize: 13),
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
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
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
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.border),
                      ),
                      child: CheckboxListTile(
                        value: _coolOnConnect,
                        onChanged: (v) => setState(() => _coolOnConnect = v ?? false),
                        title: Text(
                          'Cool on connect',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        activeColor: colors.primary,
                        checkColor: Colors.white,
                        controlAffinity: ListTileControlAffinity.trailing,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        dense: true,
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
}

// =============================================================================
// Helper Widgets
// =============================================================================

/// Collapsible section card
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isExpanded;
  final VoidCallback onToggle;
  final String summary;
  final Widget child;
  final NightshadeColors colors;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.isExpanded,
    required this.onToggle,
    required this.summary,
    required this.child,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          // Header (always visible, clickable to toggle)
          InkWell(
            onTap: onToggle,
            borderRadius: isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: colors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (!isExpanded) ...[
                          const SizedBox(height: 2),
                          Text(
                            summary,
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 18,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),

          // Content (only when expanded)
          if (isExpanded)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// Icon selection option
class _IconOption extends StatelessWidget {
  final String icon;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _IconOption({
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected ? colors.primary.withValues(alpha: 0.2) : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: icon.isEmpty
              ? Icon(
                  LucideIcons.ban,
                  size: 18,
                  color: colors.textMuted,
                )
              : Text(
                  icon,
                  style: const TextStyle(fontSize: 20),
                ),
        ),
      ),
    );
  }
}

/// Color selection option
class _ColorOption extends StatelessWidget {
  final Color? color;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _ColorOption({
    required this.color,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color ?? colors.surfaceAlt,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : (color ?? colors.border),
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (color ?? colors.primary).withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: color == null
            ? Icon(
                LucideIcons.ban,
                size: 14,
                color: colors.textMuted,
              )
            : null,
      ),
    );
  }
}

/// Computed value display
class _ComputedValue extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final NightshadeColors colors;

  const _ComputedValue({
    required this.label,
    required this.value,
    this.subtitle,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: colors.primary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 1),
          Text(
            subtitle!,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }
}

/// Device row with dropdown for selection
class _DeviceRow extends StatelessWidget {
  final String type;
  final IconData icon;
  final TextEditingController nameController;
  final String? deviceId;
  final List<UnifiedDevice> discoveredDevices;
  final void Function(String? id, String? name) onDeviceSelected;
  final VoidCallback onClear;
  final NightshadeColors colors;

  const _DeviceRow({
    required this.type,
    required this.icon,
    required this.nameController,
    required this.deviceId,
    required this.discoveredDevices,
    required this.onDeviceSelected,
    required this.onClear,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: deviceId != null ? colors.primary.withValues(alpha: 0.3) : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device type header with dropdown
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: colors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Friendly name text field
                    SizedBox(
                      height: 32,
                      child: TextField(
                        controller: nameController,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Friendly name...',
                          hintStyle: TextStyle(
                            color: colors.textMuted,
                            fontSize: 13,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: colors.primary),
                          ),
                          filled: true,
                          fillColor: colors.surface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Device selection dropdown
              _DeviceDropdown(
                deviceId: deviceId,
                discoveredDevices: discoveredDevices,
                onSelected: onDeviceSelected,
                colors: colors,
              ),
              // Clear button
              if (deviceId != null)
                IconButton(
                  onPressed: onClear,
                  icon: Icon(LucideIcons.x, size: 16, color: colors.textMuted),
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
            ],
          ),

          // Show device ID if assigned
          if (deviceId != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 38),
              child: Text(
                deviceId!,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dropdown for selecting a device
class _DeviceDropdown extends StatelessWidget {
  final String? deviceId;
  final List<UnifiedDevice> discoveredDevices;
  final void Function(String? id, String? name) onSelected;
  final NightshadeColors colors;

  const _DeviceDropdown({
    required this.deviceId,
    required this.discoveredDevices,
    required this.onSelected,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Select device',
      onSelected: (value) {
        if (value == '_manual_') {
          _showManualEntryDialog(context);
        } else if (value == '_scan_') {
          // Trigger discovery refresh
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scanning for devices...')),
          );
        } else {
          // Find the device name
          final device = discoveredDevices.where((d) => d.activeDeviceId == value).firstOrNull;
          onSelected(value, device?.displayName);
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];

        // Current selection
        if (deviceId != null) {
          items.add(PopupMenuItem(
            value: deviceId,
            child: Row(
              children: [
                Icon(LucideIcons.check, size: 14, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getDeviceDisplayName(deviceId!),
                    style: TextStyle(color: colors.textPrimary),
                  ),
                ),
              ],
            ),
          ));
          items.add(const PopupMenuDivider());
        }

        // Discovered devices
        if (discoveredDevices.isNotEmpty) {
          for (final device in discoveredDevices) {
            if (device.activeDeviceId == deviceId) continue;
            items.add(PopupMenuItem(
              value: device.activeDeviceId,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.displayName,
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  Text(
                    device.activeBackend.shortLabel,
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ));
          }
          items.add(const PopupMenuDivider());
        }

        // Actions
        items.add(PopupMenuItem(
          value: '_scan_',
          child: Row(
            children: [
              Icon(LucideIcons.refreshCw, size: 14, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Scan...', style: TextStyle(color: colors.textSecondary)),
            ],
          ),
        ));
        items.add(PopupMenuItem(
          value: '_manual_',
          child: Row(
            children: [
              Icon(LucideIcons.edit3, size: 14, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Enter manually...', style: TextStyle(color: colors.textSecondary)),
            ],
          ),
        ));

        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              deviceId != null ? 'Selected' : 'Select...',
              style: TextStyle(
                color: deviceId != null ? colors.textPrimary : colors.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 14, color: colors.textMuted),
          ],
        ),
      ),
    );
  }

  String _getDeviceDisplayName(String id) {
    final device = discoveredDevices.where((d) => d.activeDeviceId == id).firstOrNull;
    return device?.displayName ?? id;
  }

  Future<void> _showManualEntryDialog(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Device ID'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Device ID or path...',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    if (result != null && result.isNotEmpty) {
      onSelected(result, null);
    }
    controller.dispose();
  }
}

/// Filter row widget
class _FilterRow extends StatelessWidget {
  final int index;
  final TextEditingController nameController;
  final TextEditingController offsetController;
  final VoidCallback onRemove;
  final bool isLast;
  final NightshadeColors colors;

  const _FilterRow({
    required this.index,
    required this.nameController,
    required this.offsetController,
    required this.onRemove,
    required this.isLast,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '$index',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: nameController,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Filter name',
                  hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                  filled: true,
                  fillColor: colors.surface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            height: 32,
            child: TextField(
              controller: offsetController,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                suffixText: 'steps',
                suffixStyle: TextStyle(color: colors.textMuted, fontSize: 10),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.primary),
                ),
                filled: true,
                fillColor: colors.surface,
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(LucideIcons.trash2, size: 14, color: colors.error),
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// Helper class for filter name and offset controllers
class _FilterControllerPair {
  final TextEditingController nameController;
  final TextEditingController offsetController;

  _FilterControllerPair({
    required this.nameController,
    required this.offsetController,
  });

  void dispose() {
    nameController.dispose();
    offsetController.dispose();
  }
}

/// Extension to get trimmed string or null
extension _StringTrimOrNull on String {
  String? get trimOrNull {
    final trimmed = trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
