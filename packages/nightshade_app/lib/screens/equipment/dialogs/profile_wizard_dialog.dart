import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../utils/snackbar_helper.dart';

/// Multi-step wizard dialog for creating equipment profiles.
///
/// Steps:
/// 1. Basic Info - Profile name and description
/// 2. Select Devices - Choose connected devices for the profile
/// 3. Optical Configuration - Focal length, aperture, f-ratio
/// 4. Filter Configuration - Filter names and focus offsets (if filter wheel selected)
class ProfileWizardDialog extends ConsumerStatefulWidget {
  const ProfileWizardDialog({super.key});

  /// Show the wizard dialog and return the created profile ID if successful
  static Future<int?> show(BuildContext context) {
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ProfileWizardDialog(),
    );
  }

  @override
  ConsumerState<ProfileWizardDialog> createState() => _ProfileWizardDialogState();
}

class _ProfileWizardDialogState extends ConsumerState<ProfileWizardDialog> {
  int _currentStep = 0;
  bool _isCreating = false;

  // Step 1: Basic Info
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _nameError;

  // Step 2: Device Selection
  bool _includeCamera = false;
  bool _includeMount = false;
  bool _includeFocuser = false;
  bool _includeFilterWheel = false;
  bool _includeGuider = false;
  bool _includeRotator = false;

  // Step 3: Optical Configuration
  final _focalLengthController = TextEditingController();
  final _apertureController = TextEditingController();

  // Step 4: Filter Configuration
  List<TextEditingController> _filterNameControllers = [];
  List<TextEditingController> _filterOffsetControllers = [];
  int _filterSlotCount = 0;

  @override
  void initState() {
    super.initState();
    // Pre-populate device selections based on connected devices
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeFromConnectedDevices();
    });
  }

  void _initializeFromConnectedDevices() {
    final cameraState = ref.read(cameraStateProvider);
    final mountState = ref.read(mountStateProvider);
    final focuserState = ref.read(focuserStateProvider);
    final filterWheelState = ref.read(filterWheelStateProvider);
    final guiderState = ref.read(guiderStateProvider);
    final rotatorState = ref.read(rotatorStateProvider);

    setState(() {
      _includeCamera = cameraState.connectionState == DeviceConnectionState.connected;
      _includeMount = mountState.connectionState == DeviceConnectionState.connected;
      _includeFocuser = focuserState.connectionState == DeviceConnectionState.connected;
      _includeFilterWheel = filterWheelState.connectionState == DeviceConnectionState.connected;
      _includeGuider = guiderState.connectionState == DeviceConnectionState.connected;
      _includeRotator = rotatorState.connectionState == DeviceConnectionState.connected;

      // Initialize filter slots from connected filter wheel
      if (filterWheelState.connectionState == DeviceConnectionState.connected) {
        final filterNames = filterWheelState.filterNames;
        _filterSlotCount = filterNames.isNotEmpty ? filterNames.length : 5;
        _initializeFilterControllers(filterNames);
      }
    });
  }

  void _initializeFilterControllers(List<String> existingNames) {
    // Dispose existing controllers
    for (final controller in _filterNameControllers) {
      controller.dispose();
    }
    for (final controller in _filterOffsetControllers) {
      controller.dispose();
    }

    // Create new controllers
    _filterNameControllers = List.generate(
      _filterSlotCount,
      (i) => TextEditingController(
        text: i < existingNames.length ? existingNames[i] : 'Filter ${i + 1}',
      ),
    );
    _filterOffsetControllers = List.generate(
      _filterSlotCount,
      (i) => TextEditingController(text: '0'),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _focalLengthController.dispose();
    _apertureController.dispose();
    for (final controller in _filterNameControllers) {
      controller.dispose();
    }
    for (final controller in _filterOffsetControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _hasFilterStep => _includeFilterWheel;

  int get _totalSteps => _hasFilterStep ? 4 : 3;

  bool get _canGoBack => _currentStep > 0;

  bool get _canGoNext => _currentStep < _totalSteps - 1;

  bool get _isLastStep => _currentStep == _totalSteps - 1;

  void _goBack() {
    if (_canGoBack) {
      setState(() => _currentStep--);
    }
  }

  void _goNext() {
    if (!_validateCurrentStep()) return;

    if (_canGoNext) {
      // Handle skipping filter step if filter wheel is deselected
      if (_currentStep == 1 && !_hasFilterStep) {
        // Skip to optical config (last step in 3-step wizard)
        setState(() => _currentStep = 2);
      } else {
        setState(() => _currentStep++);
      }
    }
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        // Validate basic info
        final name = _nameController.text.trim();
        if (name.isEmpty) {
          setState(() => _nameError = 'Profile name is required');
          return false;
        }
        setState(() => _nameError = null);
        return true;
      case 1:
        // Device selection - no validation needed
        return true;
      case 2:
        // Optical config - no required fields
        return true;
      case 3:
        // Filter config - no required validation
        return true;
      default:
        return true;
    }
  }

  void _createFromCurrentSetup() {
    final cameraState = ref.read(cameraStateProvider);
    final mountState = ref.read(mountStateProvider);
    final focuserState = ref.read(focuserStateProvider);
    final filterWheelState = ref.read(filterWheelStateProvider);
    final guiderState = ref.read(guiderStateProvider);
    final rotatorState = ref.read(rotatorStateProvider);
    final activeProfile = ref.read(activeEquipmentProfileProvider);

    setState(() {
      // Generate a default name
      if (_nameController.text.isEmpty) {
        _nameController.text = 'My Equipment Setup';
      }

      // Enable all connected devices
      _includeCamera = cameraState.connectionState == DeviceConnectionState.connected;
      _includeMount = mountState.connectionState == DeviceConnectionState.connected;
      _includeFocuser = focuserState.connectionState == DeviceConnectionState.connected;
      _includeFilterWheel = filterWheelState.connectionState == DeviceConnectionState.connected;
      _includeGuider = guiderState.connectionState == DeviceConnectionState.connected;
      _includeRotator = rotatorState.connectionState == DeviceConnectionState.connected;

      // Copy optical settings from active profile if available
      if (activeProfile != null) {
        if (activeProfile.focalLength > 0) {
          _focalLengthController.text = activeProfile.focalLength.toString();
        }
        if (activeProfile.aperture > 0) {
          _apertureController.text = activeProfile.aperture.toString();
        }
      }

      // Initialize filter configuration from connected filter wheel
      if (filterWheelState.connectionState == DeviceConnectionState.connected) {
        final filterNames = filterWheelState.filterNames;
        _filterSlotCount = filterNames.isNotEmpty ? filterNames.length : 5;
        _initializeFilterControllers(filterNames);
      }
    });
  }

  Future<void> _createProfile() async {
    if (!_validateCurrentStep()) return;

    setState(() => _isCreating = true);

    try {
      final cameraState = ref.read(cameraStateProvider);
      final mountState = ref.read(mountStateProvider);
      final focuserState = ref.read(focuserStateProvider);
      final filterWheelState = ref.read(filterWheelStateProvider);
      final guiderState = ref.read(guiderStateProvider);
      final rotatorState = ref.read(rotatorStateProvider);

      // Build filter configuration
      final filterNames = <String>[];
      final filterFocusOffsets = <String, int>{};

      if (_includeFilterWheel && _filterNameControllers.isNotEmpty) {
        for (int i = 0; i < _filterNameControllers.length; i++) {
          final name = _filterNameControllers[i].text.trim();
          filterNames.add(name.isNotEmpty ? name : 'Filter ${i + 1}');

          final offsetText = _filterOffsetControllers[i].text.trim();
          final offset = int.tryParse(offsetText) ?? 0;
          if (offset != 0) {
            filterFocusOffsets[filterNames[i]] = offset;
          }
        }
      }

      // Create the profile model
      final profile = EquipmentProfileModel(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        cameraId: _includeCamera && cameraState.connectionState == DeviceConnectionState.connected
            ? cameraState.deviceId
            : null,
        mountId: _includeMount && mountState.connectionState == DeviceConnectionState.connected
            ? mountState.deviceId
            : null,
        focuserId: _includeFocuser && focuserState.connectionState == DeviceConnectionState.connected
            ? focuserState.deviceId
            : null,
        filterWheelId: _includeFilterWheel && filterWheelState.connectionState == DeviceConnectionState.connected
            ? filterWheelState.deviceId
            : null,
        guiderId: _includeGuider && guiderState.connectionState == DeviceConnectionState.connected
            ? guiderState.deviceId
            : null,
        rotatorId: _includeRotator && rotatorState.connectionState == DeviceConnectionState.connected
            ? rotatorState.deviceId
            : null,
        focalLength: double.tryParse(_focalLengthController.text.trim()) ?? 0.0,
        aperture: double.tryParse(_apertureController.text.trim()) ?? 0.0,
        filterNames: filterNames,
        filterFocusOffsets: filterFocusOffsets,
      );

      // Save to database
      final dao = ref.read(equipmentProfilesDaoProvider);
      final id = await dao.createProfile(profile.toCompanion());

      if (mounted) {
        context.showSuccessSnackBar('Profile "${profile.name}" created');
        Navigator.of(context).pop(id);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to create profile: $e');
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
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
            _buildHeader(colors, theme),

            // Step indicator
            _buildStepIndicator(colors),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildCurrentStep(colors, theme),
              ),
            ),

            // Footer with navigation buttons
            _buildFooter(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NightshadeColors colors, ThemeData theme) {
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
              border: Border.all(
                color: colors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              LucideIcons.scan,
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
                  'Create Equipment Profile',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getStepTitle(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
            icon: Icon(
              LucideIcons.x,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0:
        return 'Step 1 of $_totalSteps: Basic Information';
      case 1:
        return 'Step 2 of $_totalSteps: Select Devices';
      case 2:
        if (_hasFilterStep) {
          return 'Step 3 of $_totalSteps: Optical Configuration';
        } else {
          return 'Step 3 of $_totalSteps: Optical Configuration';
        }
      case 3:
        return 'Step 4 of $_totalSteps: Filter Configuration';
      default:
        return '';
    }
  }

  Widget _buildStepIndicator(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_totalSteps, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;

          return Row(
            children: [
              if (index > 0)
                Container(
                  width: 40,
                  height: 2,
                  color: isCompleted || isActive
                      ? colors.primary
                      : colors.border,
                ),
              _StepDot(
                index: index + 1,
                isActive: isActive,
                isCompleted: isCompleted,
                colors: colors,
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep(NightshadeColors colors, ThemeData theme) {
    switch (_currentStep) {
      case 0:
        return _buildBasicInfoStep(colors, theme);
      case 1:
        return _buildDeviceSelectionStep(colors, theme);
      case 2:
        return _buildOpticalConfigStep(colors, theme);
      case 3:
        return _buildFilterConfigStep(colors, theme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBasicInfoStep(NightshadeColors colors, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick action button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.zap,
                color: colors.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Start',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Automatically fill in all fields from your currently connected equipment.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _createFromCurrentSetup,
                icon: const Icon(LucideIcons.arrowRight, size: 16),
                label: const Text('Use Current Setup'),
                style: TextButton.styleFrom(
                  foregroundColor: colors.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Profile name
        Text(
          'Profile Name *',
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g., Main Imaging Rig, Widefield Setup',
            hintStyle: TextStyle(color: colors.textMuted),
            errorText: _nameError,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.primary),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.error),
            ),
            filled: true,
            fillColor: colors.surface,
          ),
          onChanged: (_) {
            if (_nameError != null) {
              setState(() => _nameError = null);
            }
          },
        ),
        const SizedBox(height: 20),

        // Description
        Text(
          'Description (Optional)',
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionController,
          style: TextStyle(color: colors.textPrimary),
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Add notes about this equipment configuration...',
            hintStyle: TextStyle(color: colors.textMuted),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.primary),
            ),
            filled: true,
            fillColor: colors.surface,
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceSelectionStep(NightshadeColors colors, ThemeData theme) {
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final rotatorState = ref.watch(rotatorStateProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select the devices to include in this profile. Only connected devices can be added.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),

        _DeviceCheckbox(
          title: 'Camera',
          subtitle: cameraState.connectionState == DeviceConnectionState.connected
              ? cameraState.deviceName ?? cameraState.deviceId ?? 'Unknown'
              : 'Not connected',
          icon: LucideIcons.camera,
          isChecked: _includeCamera,
          isEnabled: cameraState.connectionState == DeviceConnectionState.connected,
          colors: colors,
          onChanged: (value) => setState(() => _includeCamera = value ?? false),
        ),

        _DeviceCheckbox(
          title: 'Mount',
          subtitle: mountState.connectionState == DeviceConnectionState.connected
              ? mountState.deviceName ?? mountState.deviceId ?? 'Unknown'
              : 'Not connected',
          icon: LucideIcons.compass,
          isChecked: _includeMount,
          isEnabled: mountState.connectionState == DeviceConnectionState.connected,
          colors: colors,
          onChanged: (value) => setState(() => _includeMount = value ?? false),
        ),

        _DeviceCheckbox(
          title: 'Focuser',
          subtitle: focuserState.connectionState == DeviceConnectionState.connected
              ? focuserState.deviceName ?? focuserState.deviceId ?? 'Unknown'
              : 'Not connected',
          icon: LucideIcons.focus,
          isChecked: _includeFocuser,
          isEnabled: focuserState.connectionState == DeviceConnectionState.connected,
          colors: colors,
          onChanged: (value) => setState(() => _includeFocuser = value ?? false),
        ),

        _DeviceCheckbox(
          title: 'Filter Wheel',
          subtitle: filterWheelState.connectionState == DeviceConnectionState.connected
              ? filterWheelState.deviceName ?? filterWheelState.deviceId ?? 'Unknown'
              : 'Not connected',
          icon: LucideIcons.disc,
          isChecked: _includeFilterWheel,
          isEnabled: filterWheelState.connectionState == DeviceConnectionState.connected,
          colors: colors,
          onChanged: (value) {
            setState(() {
              _includeFilterWheel = value ?? false;
              if (_includeFilterWheel && filterWheelState.connectionState == DeviceConnectionState.connected) {
                final filterNames = filterWheelState.filterNames;
                _filterSlotCount = filterNames.isNotEmpty ? filterNames.length : 5;
                _initializeFilterControllers(filterNames);
              }
            });
          },
        ),

        _DeviceCheckbox(
          title: 'Guider',
          subtitle: guiderState.connectionState == DeviceConnectionState.connected
              ? guiderState.deviceName ?? guiderState.deviceId ?? 'Unknown'
              : 'Not connected',
          icon: LucideIcons.crosshair,
          isChecked: _includeGuider,
          isEnabled: guiderState.connectionState == DeviceConnectionState.connected,
          colors: colors,
          onChanged: (value) => setState(() => _includeGuider = value ?? false),
        ),

        _DeviceCheckbox(
          title: 'Rotator',
          subtitle: rotatorState.connectionState == DeviceConnectionState.connected
              ? rotatorState.deviceName ?? rotatorState.deviceId ?? 'Unknown'
              : 'Not connected',
          icon: LucideIcons.rotateCcw,
          isChecked: _includeRotator,
          isEnabled: rotatorState.connectionState == DeviceConnectionState.connected,
          colors: colors,
          onChanged: (value) => setState(() => _includeRotator = value ?? false),
        ),
      ],
    );
  }

  Widget _buildOpticalConfigStep(NightshadeColors colors, ThemeData theme) {
    final focalLength = double.tryParse(_focalLengthController.text) ?? 0;
    final aperture = double.tryParse(_apertureController.text) ?? 0;
    final fRatio = aperture > 0 ? focalLength / aperture : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configure your optical system parameters. These are used for field of view calculations and image scale.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),

        // Focal length
        Text(
          'Focal Length (mm)',
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _focalLengthController,
          style: TextStyle(color: colors.textPrimary),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'e.g., 500, 1000, 2000',
            hintStyle: TextStyle(color: colors.textMuted),
            suffixText: 'mm',
            suffixStyle: TextStyle(color: colors.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.primary),
            ),
            filled: true,
            fillColor: colors.surface,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),

        // Aperture
        Text(
          'Aperture (mm)',
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _apertureController,
          style: TextStyle(color: colors.textPrimary),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'e.g., 80, 102, 200',
            hintStyle: TextStyle(color: colors.textMuted),
            suffixText: 'mm',
            suffixStyle: TextStyle(color: colors.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.primary),
            ),
            filled: true,
            fillColor: colors.surface,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 24),

        // Calculated f-ratio display
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.calculator,
                color: colors.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                'Calculated f-ratio:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                fRatio > 0 ? 'f/${fRatio.toStringAsFixed(1)}' : '--',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterConfigStep(NightshadeColors colors, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configure your filter wheel slots. Set filter names and focus offsets for each position.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),

        // Filter slot count selector
        Row(
          children: [
            Text(
              'Number of filter slots:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: 16),
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _filterSlotCount > 1
                        ? () {
                            setState(() {
                              _filterSlotCount--;
                              _initializeFilterControllers(
                                _filterNameControllers
                                    .take(_filterSlotCount)
                                    .map((c) => c.text)
                                    .toList(),
                              );
                            });
                          }
                        : null,
                    icon: Icon(
                      LucideIcons.minus,
                      size: 16,
                      color: _filterSlotCount > 1
                          ? colors.textSecondary
                          : colors.textMuted,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '$_filterSlotCount',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _filterSlotCount < 12
                        ? () {
                            setState(() {
                              _filterSlotCount++;
                              _initializeFilterControllers(
                                _filterNameControllers
                                    .map((c) => c.text)
                                    .toList(),
                              );
                            });
                          }
                        : null,
                    icon: Icon(
                      LucideIcons.plus,
                      size: 16,
                      color: _filterSlotCount < 12
                          ? colors.textSecondary
                          : colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Filter slots list
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(11),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        'Slot',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Filter Name',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Focus Offset',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Filter rows
              ...List.generate(_filterSlotCount, (index) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: index < _filterSlotCount - 1
                        ? Border(
                            bottom: BorderSide(color: colors.border),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${index + 1}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _filterNameControllers[index],
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            hintText: 'Filter ${index + 1}',
                            hintStyle: TextStyle(color: colors.textMuted),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: colors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: colors.primary),
                            ),
                            filled: true,
                            fillColor: colors.background,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _filterOffsetControllers[index],
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                          ),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            hintText: '0',
                            hintStyle: TextStyle(color: colors.textMuted),
                            suffixText: 'steps',
                            suffixStyle: TextStyle(
                              color: colors.textMuted,
                              fontSize: 11,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: colors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: colors.primary),
                            ),
                            filled: true,
                            fillColor: colors.background,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Cancel button
          TextButton(
            onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: colors.textMuted),
            ),
          ),
          const Spacer(),

          // Back button
          if (_canGoBack)
            OutlinedButton.icon(
              onPressed: _isCreating ? null : _goBack,
              icon: const Icon(LucideIcons.arrowLeft, size: 16),
              label: const Text('Back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textSecondary,
                side: BorderSide(color: colors.border),
              ),
            ),

          const SizedBox(width: 12),

          // Next/Create button
          FilledButton.icon(
            onPressed: _isCreating
                ? null
                : _isLastStep
                    ? _createProfile
                    : _goNext,
            icon: _isCreating
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  )
                : Icon(
                    _isLastStep ? LucideIcons.check : LucideIcons.arrowRight,
                    size: 16,
                  ),
            label: Text(_isLastStep ? 'Create Profile' : 'Next'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: colors.primary.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step indicator dot widget
class _StepDot extends StatelessWidget {
  final int index;
  final bool isActive;
  final bool isCompleted;
  final NightshadeColors colors;

  const _StepDot({
    required this.index,
    required this.isActive,
    required this.isCompleted,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive || isCompleted
            ? colors.primary
            : colors.surfaceAlt,
        border: Border.all(
          color: isActive
              ? colors.primary
              : isCompleted
                  ? colors.primary
                  : colors.border,
          width: 2,
        ),
      ),
      child: Center(
        child: isCompleted
            ? const Icon(
                LucideIcons.check,
                size: 14,
                color: Colors.white,
              )
            : Text(
                '$index',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : colors.textMuted,
                ),
              ),
      ),
    );
  }
}

/// Device checkbox widget for step 2
class _DeviceCheckbox extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isChecked;
  final bool isEnabled;
  final NightshadeColors colors;
  final ValueChanged<bool?>? onChanged;

  const _DeviceCheckbox({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isChecked,
    required this.isEnabled,
    required this.colors,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isChecked && isEnabled
              ? colors.primary.withValues(alpha: 0.08)
              : colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isChecked && isEnabled
                ? colors.primary.withValues(alpha: 0.3)
                : colors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isEnabled
                    ? colors.primary.withValues(alpha: 0.1)
                    : colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 18,
                color: isEnabled ? colors.primary : colors.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isEnabled
                          ? colors.textSecondary
                          : colors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Checkbox(
              value: isChecked && isEnabled,
              onChanged: isEnabled ? onChanged : null,
              activeColor: colors.primary,
              checkColor: Colors.white,
              side: BorderSide(color: colors.border),
            ),
          ],
        ),
      ),
    );
  }
}
