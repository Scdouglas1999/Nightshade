part of '../equipment_profiles_screen.dart';

class _ProfileDetails extends ConsumerStatefulWidget {
  final EquipmentProfileModel profile;
  final bool isActive;
  final bool isEditing;
  final VoidCallback onEdit;
  final Future<void> Function(EquipmentProfileModel) onSave;
  final VoidCallback onCancel;
  final VoidCallback onSetActive;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onExport;
  final VoidCallback onRefresh;
  final bool isMobile;
  final VoidCallback? onBack;

  const _ProfileDetails({
    required this.profile,
    required this.isActive,
    required this.isEditing,
    required this.onEdit,
    required this.onSave,
    required this.onCancel,
    required this.onSetActive,
    required this.onDuplicate,
    required this.onDelete,
    required this.onExport,
    required this.onRefresh,
    this.isMobile = false,
    this.onBack,
  });

  @override
  ConsumerState<_ProfileDetails> createState() => _ProfileDetailsState();
}

class _ProfileDetailsState extends ConsumerState<_ProfileDetails> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _focalLengthController;
  late TextEditingController _apertureController;
  late TextEditingController _gainController;
  late TextEditingController _offsetController;
  late TextEditingController _coolingController;
  late int _binX;
  late int _binY;
  late List<TextEditingController> _filterControllers;
  late Map<String, TextEditingController> _filterOffsetControllers;

  // Device IDs for editing
  late String? _cameraId;
  late String? _mountId;
  late String? _focuserId;
  late String? _filterWheelId;
  late String? _guiderId;
  late String? _rotatorId;
  late String? _domeId;
  late String? _weatherId;
  bool _isSyncingFilters = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(_ProfileDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _initControllers();
    }
  }

  void _initControllers() {
    _nameController = TextEditingController(text: widget.profile.name);
    _descController =
        TextEditingController(text: widget.profile.description ?? '');
    _focalLengthController = TextEditingController(
        text: widget.profile.focalLength.toStringAsFixed(0));
    _apertureController =
        TextEditingController(text: widget.profile.aperture.toStringAsFixed(0));
    _gainController = TextEditingController(
        text: widget.profile.defaultGain?.toString() ?? '');
    _offsetController = TextEditingController(
        text: widget.profile.defaultOffset?.toString() ?? '');
    _coolingController = TextEditingController(
        text: widget.profile.defaultCoolingTemp?.toString() ?? '');
    _binX = widget.profile.defaultBinX;
    _binY = widget.profile.defaultBinY;
    _filterControllers = widget.profile.filterNames.isEmpty
        ? [TextEditingController()]
        : widget.profile.filterNames
            .map((f) => TextEditingController(text: f))
            .toList();

    // Initialize filter focus offset controllers
    _filterOffsetControllers = {};
    for (final filterName in widget.profile.filterNames) {
      final offset = widget.profile.filterFocusOffsets[filterName] ?? 0;
      _filterOffsetControllers[filterName] =
          TextEditingController(text: offset.toString());
    }

    // Initialize device IDs
    _cameraId = widget.profile.cameraId;
    _mountId = widget.profile.mountId;
    _focuserId = widget.profile.focuserId;
    _filterWheelId = widget.profile.filterWheelId;
    _guiderId = widget.profile.guiderId;
    _rotatorId = widget.profile.rotatorId;
    _domeId = widget.profile.domeId;
    _weatherId = widget.profile.weatherId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _focalLengthController.dispose();
    _apertureController.dispose();
    _gainController.dispose();
    _offsetController.dispose();
    _coolingController.dispose();
    for (final c in _filterControllers) {
      c.dispose();
    }
    for (final c in _filterOffsetControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  EquipmentProfileModel _buildUpdatedProfile() {
    final filterNames = _filterControllers
        .map((c) => c.text.trim())
        .where((f) => f.isNotEmpty)
        .toList();

    // Build filter focus offsets map
    final filterFocusOffsets = <String, int>{};
    for (final entry in _filterOffsetControllers.entries) {
      final offset = int.tryParse(entry.value.text) ?? 0;
      // Only include if the filter name is still in the list
      if (filterNames.contains(entry.key)) {
        filterFocusOffsets[entry.key] = offset;
      }
    }

    return widget.profile.copyWith(
      name: _nameController.text,
      description: _descController.text.isEmpty ? null : _descController.text,
      focalLength: double.tryParse(_focalLengthController.text) ?? 0,
      aperture: double.tryParse(_apertureController.text) ?? 0,
      defaultGain: int.tryParse(_gainController.text),
      defaultOffset: int.tryParse(_offsetController.text),
      defaultCoolingTemp: double.tryParse(_coolingController.text),
      defaultBinX: _binX,
      defaultBinY: _binY,
      filterNames: filterNames,
      filterFocusOffsets: filterFocusOffsets,
      cameraId: _cameraId,
      mountId: _mountId,
      focuserId: _focuserId,
      filterWheelId: _filterWheelId,
      guiderId: _guiderId,
      rotatorId: _rotatorId,
      domeId: _domeId,
      weatherId: _weatherId,
    );
  }

  Future<void> _syncFiltersFromHardware() async {
    if (_isSyncingFilters) return;

    setState(() => _isSyncingFilters = true);

    try {
      final profileService = ref.read(profileServiceProvider);
      final synced =
          await profileService.syncFiltersToProfile(widget.profile.id!);

      if (synced) {
        // Refresh the profile to get the updated filter names
        widget.onRefresh();
        if (mounted) {
          context.showSuccessSnackBar('Filters synced from hardware');
        }
      } else {
        if (mounted) {
          context.showWarningSnackBar('No filter wheel connected');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to sync filters: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingFilters = false);
      }
    }
  }

  void _copyFromConnectedDevices() {
    // Read current device states
    final cameraState = ref.read(cameraStateProvider);
    final mountState = ref.read(mountStateProvider);
    final focuserState = ref.read(focuserStateProvider);
    final filterWheelState = ref.read(filterWheelStateProvider);
    final guiderState = ref.read(guiderStateProvider);
    final rotatorState = ref.read(rotatorStateProvider);
    final domeState = ref.read(domeStateProvider);
    final weatherState = ref.read(weatherStateProvider);

    int copiedCount = 0;

    setState(() {
      // Copy camera ID if connected
      if (cameraState.connectionState == DeviceConnectionState.connected &&
          cameraState.deviceId != null) {
        _cameraId = cameraState.deviceId;
        copiedCount++;
      }

      // Copy mount ID if connected
      if (mountState.connectionState == DeviceConnectionState.connected &&
          mountState.deviceId != null) {
        _mountId = mountState.deviceId;
        copiedCount++;
      }

      // Copy focuser ID if connected (uses deviceName as ID)
      if (focuserState.connectionState == DeviceConnectionState.connected &&
          focuserState.deviceName != null) {
        _focuserId = focuserState.deviceName;
        copiedCount++;
      }

      // Copy filter wheel ID if connected (uses deviceName as ID)
      if (filterWheelState.connectionState == DeviceConnectionState.connected &&
          filterWheelState.deviceName != null) {
        _filterWheelId = filterWheelState.deviceName;
        copiedCount++;
      }

      // Copy guider ID if connected (uses deviceName as ID)
      if (guiderState.connectionState == DeviceConnectionState.connected &&
          guiderState.deviceName != null) {
        _guiderId = guiderState.deviceName;
        copiedCount++;
      }

      // Copy rotator ID if connected
      if (rotatorState.connectionState == DeviceConnectionState.connected &&
          rotatorState.deviceId != null) {
        _rotatorId = rotatorState.deviceId;
        copiedCount++;
      }

      // Copy dome ID if connected
      if (domeState.connectionState == DeviceConnectionState.connected &&
          domeState.deviceId != null) {
        _domeId = domeState.deviceId;
        copiedCount++;
      }

      // Copy weather ID if connected
      if (weatherState.connectionState == DeviceConnectionState.connected &&
          weatherState.deviceId != null) {
        _weatherId = weatherState.deviceId;
        copiedCount++;
      }
    });

    if (copiedCount > 0) {
      context.showSuccessSnackBar(
          'Copied $copiedCount device(s) from connected equipment');
    } else {
      context.showWarningSnackBar('No devices currently connected');
    }
  }

  void _update(VoidCallback callback) => setState(callback);

  @override
  Widget build(BuildContext context) => _buildDetails(context);
}
