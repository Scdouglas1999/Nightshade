import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:file_selector/file_selector.dart';

import '../../utils/confirm_dialog.dart';
import '../../utils/device_format_utils.dart';
import '../../utils/snackbar_helper.dart';

/// Screen for managing equipment profiles
class EquipmentProfilesScreen extends ConsumerStatefulWidget {
  final bool isMobile;

  const EquipmentProfilesScreen({super.key, this.isMobile = false});

  @override
  ConsumerState<EquipmentProfilesScreen> createState() =>
      _EquipmentProfilesScreenState();
}

class _EquipmentProfilesScreenState
    extends ConsumerState<EquipmentProfilesScreen> {
  EquipmentProfileModel? _selectedProfile;
  bool _isEditing = false;
  // For mobile: track whether we're viewing the detail
  bool _showingDetail = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final profilesAsync = ref.watch(equipmentProfilesProvider);

    return profilesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (state) {
        // Auto-select active profile if none selected (desktop only)
        if (!widget.isMobile &&
            _selectedProfile == null &&
            state.activeProfile != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() => _selectedProfile = state.activeProfile);
          });
        }

        if (widget.isMobile) {
          return _buildMobileLayout(state, colors);
        }

        return _buildDesktopLayout(state, colors);
      },
    );
  }

  Widget _buildMobileLayout(
      EquipmentProfilesState state, NightshadeColors colors) {
    // Show detail view if a profile is selected and we're viewing detail
    if (_showingDetail && _selectedProfile != null) {
      return _ProfileDetails(
        profile: _selectedProfile!,
        isActive: _selectedProfile?.id == state.activeProfile?.id,
        isEditing: _isEditing,
        isMobile: true,
        onBack: () => setState(() => _showingDetail = false),
        onEdit: () => setState(() => _isEditing = true),
        onSave: (updatedProfile) async {
          await ref
              .read(equipmentProfilesProvider.notifier)
              .updateProfile(updatedProfile);
          if (!mounted) return;
          setState(() {
            _selectedProfile = updatedProfile;
            _isEditing = false;
          });
        },
        onCancel: () => setState(() => _isEditing = false),
        onSetActive: () async {
          if (_selectedProfile?.id != null) {
            await ref
                .read(equipmentProfilesProvider.notifier)
                .setActiveProfile(_selectedProfile!.id!);
          }
        },
        onDuplicate: () =>
            _duplicateProfile(context, colors, _selectedProfile!),
        onDelete: () => _deleteProfile(context, colors, _selectedProfile!),
        onExport: () => _exportProfile(context, _selectedProfile!),
        onRefresh: () {
          ref.invalidate(equipmentProfilesProvider);
          final profiles = ref.read(equipmentProfileListProvider);
          final updated = profiles.firstWhere(
            (p) => p.id == _selectedProfile?.id,
            orElse: () => _selectedProfile!,
          );
          setState(() => _selectedProfile = updated);
        },
        colors: colors,
      );
    }

    // Show profile list
    return _ProfileList(
      profiles: state.profiles,
      selectedProfile: _selectedProfile,
      activeProfile: state.activeProfile,
      isMobile: true,
      onProfileSelected: (profile) {
        setState(() {
          _selectedProfile = profile;
          _isEditing = false;
          _showingDetail = true;
        });
      },
      onCreateProfile: () => _showCreateProfileDialog(context, colors),
      onImportProfiles: () => _importProfiles(context, colors),
      colors: colors,
    );
  }

  Widget _buildDesktopLayout(
      EquipmentProfilesState state, NightshadeColors colors) {
    return Row(
      children: [
        // Profile list sidebar
        _ProfileList(
          profiles: state.profiles,
          selectedProfile: _selectedProfile,
          activeProfile: state.activeProfile,
          onProfileSelected: (profile) {
            setState(() {
              _selectedProfile = profile;
              _isEditing = false;
            });
          },
          onCreateProfile: () => _showCreateProfileDialog(context, colors),
          onImportProfiles: () => _importProfiles(context, colors),
          colors: colors,
        ),

        // Profile details
        Expanded(
          child: _selectedProfile != null
              ? _ProfileDetails(
                  profile: _selectedProfile!,
                  isActive: _selectedProfile?.id == state.activeProfile?.id,
                  isEditing: _isEditing,
                  onEdit: () => setState(() => _isEditing = true),
                  onSave: (updatedProfile) async {
                    await ref
                        .read(equipmentProfilesProvider.notifier)
                        .updateProfile(updatedProfile);
                    if (!mounted) return;
                    setState(() {
                      _selectedProfile = updatedProfile;
                      _isEditing = false;
                    });
                  },
                  onCancel: () => setState(() => _isEditing = false),
                  onSetActive: () async {
                    if (_selectedProfile?.id != null) {
                      await ref
                          .read(equipmentProfilesProvider.notifier)
                          .setActiveProfile(_selectedProfile!.id!);
                    }
                  },
                  onDuplicate: () =>
                      _duplicateProfile(context, colors, _selectedProfile!),
                  onDelete: () =>
                      _deleteProfile(context, colors, _selectedProfile!),
                  onExport: () => _exportProfile(context, _selectedProfile!),
                  onRefresh: () {
                    ref.invalidate(equipmentProfilesProvider);
                    final profiles = ref.read(equipmentProfileListProvider);
                    final updated = profiles.firstWhere(
                      (p) => p.id == _selectedProfile?.id,
                      orElse: () => _selectedProfile!,
                    );
                    setState(() => _selectedProfile = updated);
                  },
                  colors: colors,
                )
              : _EmptyState(colors: colors),
        ),
      ],
    );
  }

  Future<void> _showCreateProfileDialog(
      BuildContext context, NightshadeColors colors) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Create New Profile',
            style: TextStyle(color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Profile Name',
                labelStyle: TextStyle(color: colors.textSecondary),
                hintText: 'e.g., Deep Sky Rig, Planetary Setup',
                hintStyle: TextStyle(color: colors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              style: TextStyle(color: colors.textPrimary),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: TextStyle(color: colors.textSecondary),
                hintText: 'Brief description of this setup',
                hintStyle: TextStyle(color: colors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          NightshadeButton(
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => Navigator.pop(context, false),
          ),
          NightshadeButton(
            label: 'Create',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      final id =
          await ref.read(equipmentProfilesProvider.notifier).createProfile(
                name: nameController.text,
                description:
                    descController.text.isEmpty ? null : descController.text,
              );

      // Wait for state to update and select the new profile
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      final profiles = ref.read(equipmentProfileListProvider);
      final newProfile = profiles.firstWhere((p) => p.id == id);
      setState(() {
        _selectedProfile = newProfile;
        _isEditing = true;
      });
    }
  }

  Future<void> _duplicateProfile(BuildContext context, NightshadeColors colors,
      EquipmentProfileModel profile) async {
    final nameController =
        TextEditingController(text: '${profile.name} (Copy)');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Duplicate Profile',
            style: TextStyle(color: colors.textPrimary)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            labelText: 'New Profile Name',
            labelStyle: TextStyle(color: colors.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colors.primary),
            ),
          ),
        ),
        actions: [
          NightshadeButton(
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => Navigator.pop(context, false),
          ),
          NightshadeButton(
            label: 'Duplicate',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (result == true &&
        nameController.text.isNotEmpty &&
        profile.id != null) {
      final id = await ref
          .read(equipmentProfilesProvider.notifier)
          .duplicateProfile(profile.id!, nameController.text);
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      final profiles = ref.read(equipmentProfileListProvider);
      final newProfile = profiles.firstWhere((p) => p.id == id);
      setState(() => _selectedProfile = newProfile);
    }
  }

  Future<void> _deleteProfile(BuildContext context, NightshadeColors colors,
      EquipmentProfileModel profile) async {
    final confirm = await ConfirmDialog.delete(
      context: context,
      itemName: 'profile "${profile.name}"',
    );

    if (confirm && profile.id != null) {
      await ref
          .read(equipmentProfilesProvider.notifier)
          .deleteProfile(profile.id!);
      if (!mounted) return;
      setState(() => _selectedProfile = null);
    }
  }

  Future<void> _exportProfile(
      BuildContext context, EquipmentProfileModel profile) async {
    try {
      final json = await ref
          .read(equipmentProfilesProvider.notifier)
          .exportProfile(profile.id!);

      final fileName =
          '${profile.name.replaceAll(RegExp(r'[^\w\s-]'), '_')}_profile.json';
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'JSON files', extensions: ['json']),
        ],
      );

      if (location != null) {
        final file = XFile.fromData(
          utf8.encode(json),
          mimeType: 'application/json',
          name: fileName,
        );
        await file.saveTo(location.path);

        if (!context.mounted) return;
        context.showSuccessSnackBar('Profile exported to ${location.path}');
      }
    } catch (e) {
      if (!context.mounted) return;
      context.showErrorSnackBar('Export failed: $e');
    }
  }

  Future<void> _importProfiles(
      BuildContext context, NightshadeColors colors) async {
    try {
      const jsonGroup = XTypeGroup(
        label: 'JSON files',
        extensions: ['json'],
      );

      final file = await openFile(acceptedTypeGroups: [jsonGroup]);
      if (file != null) {
        final json = await file.readAsString();
        final ids = await ref
            .read(equipmentProfilesProvider.notifier)
            .importProfiles(json);

        if (!context.mounted) return;
        context.showSuccessSnackBar('Imported ${ids.length} profile(s)');

        // Select the first imported profile
        if (ids.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (!mounted) return;
          final profiles = ref.read(equipmentProfileListProvider);
          final imported = profiles.firstWhere((p) => p.id == ids.first);
          setState(() => _selectedProfile = imported);
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      context.showErrorSnackBar('Import failed: $e');
    }
  }
}

// ============================================================================
// Profile List Sidebar
// ============================================================================

class _ProfileList extends StatelessWidget {
  final List<EquipmentProfileModel> profiles;
  final EquipmentProfileModel? selectedProfile;
  final EquipmentProfileModel? activeProfile;
  final ValueChanged<EquipmentProfileModel> onProfileSelected;
  final VoidCallback onCreateProfile;
  final VoidCallback onImportProfiles;
  final NightshadeColors colors;
  final bool isMobile;

  const _ProfileList({
    required this.profiles,
    required this.selectedProfile,
    required this.activeProfile,
    required this.onProfileSelected,
    required this.onCreateProfile,
    required this.onImportProfiles,
    required this.colors,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final padding = isMobile ? 16.0 : 20.0;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header - hide on mobile since parent shows it
        if (!isMobile)
          Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Equipment Profiles',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your imaging rigs and configurations',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

        // Actions
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 16),
          child: Row(
            children: [
              Expanded(
                child: NightshadeButton(
                  label: 'New Profile',
                  icon: LucideIcons.plus,
                  variant: ButtonVariant.primary,
                  onPressed: onCreateProfile,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onImportProfiles,
                icon: Icon(LucideIcons.download,
                    color: colors.textSecondary, size: 18),
                tooltip: 'Import profiles',
                style: IconButton.styleFrom(
                  backgroundColor: colors.surfaceAlt,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: colors.border),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Profile list
        Expanded(
          child: profiles.isEmpty
              ? Center(
                  child: Text(
                    'No profiles yet',
                    style: TextStyle(color: colors.textMuted),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 12),
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final isSelected =
                        !isMobile && profile.id == selectedProfile?.id;
                    final isActive = profile.id == activeProfile?.id;

                    return _ProfileListItem(
                      profile: profile,
                      isSelected: isSelected,
                      isActive: isActive,
                      isMobile: isMobile,
                      onTap: () => onProfileSelected(profile),
                      colors: colors,
                    );
                  },
                ),
        ),
      ],
    );

    // On mobile, just return the content without fixed width
    if (isMobile) {
      return content;
    }

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: content,
    );
  }
}

class _ProfileListItem extends StatefulWidget {
  final EquipmentProfileModel profile;
  final bool isSelected;
  final bool isActive;
  final VoidCallback onTap;
  final NightshadeColors colors;
  final bool isMobile;

  const _ProfileListItem({
    required this.profile,
    required this.isSelected,
    required this.isActive,
    required this.onTap,
    required this.colors,
    this.isMobile = false,
  });

  @override
  State<_ProfileListItem> createState() => _ProfileListItemState();
}

class _ProfileListItemState extends State<_ProfileListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.colors.primary.withValues(alpha: 0.1)
                : _isHovered
                    ? widget.colors.surfaceAlt
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: widget.isSelected
                ? Border.all(
                    color: widget.colors.primary.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.isActive
                      ? widget.colors.primary.withValues(alpha: 0.2)
                      : widget.colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.aperture,
                  size: 18,
                  color: widget.isActive
                      ? widget.colors.primary
                      : widget.colors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.profile.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: widget.colors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  widget.colors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: widget.colors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (widget.profile.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.profile.description!,
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.colors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Empty State
// ============================================================================

class _EmptyState extends StatelessWidget {
  final NightshadeColors colors;

  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.aperture,
            size: 64,
            color: colors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Select a profile',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose a profile from the list or create a new one',
            style: TextStyle(
              fontSize: 13,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Profile Details
// ============================================================================

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
  final NightshadeColors colors;
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
    required this.colors,
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

  @override
  Widget build(BuildContext context) {
    final padding = widget.isMobile ? 16.0 : 32.0;
    final titleFontSize = widget.isMobile ? 20.0 : 24.0;

    Widget content = SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isEditing)
                      _EditableField(
                        controller: _nameController,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w700,
                          color: widget.colors.textPrimary,
                        ),
                        colors: widget.colors,
                      )
                    else
                      Text(
                        widget.profile.name,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w700,
                          color: widget.colors.textPrimary,
                        ),
                      ),
                    const SizedBox(height: 4),
                    if (widget.isEditing)
                      _EditableField(
                        controller: _descController,
                        hint: 'Add a description...',
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.colors.textSecondary,
                        ),
                        colors: widget.colors,
                      )
                    else
                      Text(
                        widget.profile.description ?? 'No description',
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.colors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),

              // Action buttons
              if (widget.isEditing) ...[
                NightshadeButton(
                  label: 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                  onPressed: widget.onCancel,
                ),
                const SizedBox(width: 8),
                NightshadeButton(
                  label: 'Save',
                  icon: LucideIcons.check,
                  variant: ButtonVariant.primary,
                  size: ButtonSize.small,
                  onPressed: () async {
                    try {
                      await widget.onSave(_buildUpdatedProfile());
                      if (context.mounted) {
                        context
                            .showSuccessSnackBar('Profile saved successfully');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        context.showErrorSnackBar('Failed to save profile: $e');
                      }
                    }
                  },
                ),
              ] else ...[
                if (!widget.isActive)
                  NightshadeButton(
                    label: 'Set Active',
                    icon: LucideIcons.check,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed: widget.onSetActive,
                  ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: Icon(LucideIcons.moreVertical,
                      color: widget.colors.textSecondary),
                  color: widget.colors.surface,
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        widget.onEdit();
                        break;
                      case 'duplicate':
                        widget.onDuplicate();
                        break;
                      case 'export':
                        widget.onExport();
                        break;
                      case 'delete':
                        widget.onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(LucideIcons.pencil,
                              size: 16, color: widget.colors.textSecondary),
                          const SizedBox(width: 8),
                          Text('Edit',
                              style:
                                  TextStyle(color: widget.colors.textPrimary)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'duplicate',
                      child: Row(
                        children: [
                          Icon(LucideIcons.copy,
                              size: 16, color: widget.colors.textSecondary),
                          const SizedBox(width: 8),
                          Text('Duplicate',
                              style:
                                  TextStyle(color: widget.colors.textPrimary)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(LucideIcons.upload,
                              size: 16, color: widget.colors.textSecondary),
                          const SizedBox(width: 8),
                          Text('Export',
                              style:
                                  TextStyle(color: widget.colors.textPrimary)),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(LucideIcons.trash2,
                              size: 16, color: widget.colors.error),
                          const SizedBox(width: 8),
                          Text('Delete',
                              style: TextStyle(color: widget.colors.error)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 32),

          // Optical Configuration
          _Section(
            title: 'Optical Configuration',
            icon: LucideIcons.aperture,
            colors: widget.colors,
            isMobile: widget.isMobile,
            children: [
              widget.isMobile
                  ? Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _FieldCard(
                                label: 'Focal Length',
                                value: widget.isEditing
                                    ? null
                                    : '${widget.profile.focalLength.toStringAsFixed(0)} mm',
                                controller: widget.isEditing
                                    ? _focalLengthController
                                    : null,
                                suffix: 'mm',
                                colors: widget.colors,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _FieldCard(
                                label: 'Aperture',
                                value: widget.isEditing
                                    ? null
                                    : '${widget.profile.aperture.toStringAsFixed(0)} mm',
                                controller: widget.isEditing
                                    ? _apertureController
                                    : null,
                                suffix: 'mm',
                                colors: widget.colors,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _FieldCard(
                          label: 'Focal Ratio',
                          value: widget.profile.calculatedFocalRatio != null
                              ? 'f/${widget.profile.calculatedFocalRatio!.toStringAsFixed(1)}'
                              : 'N/A',
                          colors: widget.colors,
                          readOnly: true,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _FieldCard(
                            label: 'Focal Length',
                            value: widget.isEditing
                                ? null
                                : '${widget.profile.focalLength.toStringAsFixed(0)} mm',
                            controller: widget.isEditing
                                ? _focalLengthController
                                : null,
                            suffix: 'mm',
                            colors: widget.colors,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _FieldCard(
                            label: 'Aperture',
                            value: widget.isEditing
                                ? null
                                : '${widget.profile.aperture.toStringAsFixed(0)} mm',
                            controller:
                                widget.isEditing ? _apertureController : null,
                            suffix: 'mm',
                            colors: widget.colors,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _FieldCard(
                            label: 'Focal Ratio',
                            value: widget.profile.calculatedFocalRatio != null
                                ? 'f/${widget.profile.calculatedFocalRatio!.toStringAsFixed(1)}'
                                : 'N/A',
                            colors: widget.colors,
                            readOnly: true,
                          ),
                        ),
                      ],
                    ),
            ],
          ),
          const SizedBox(height: 24),

          // Camera Defaults
          _Section(
            title: 'Camera Defaults',
            icon: LucideIcons.camera,
            colors: widget.colors,
            isMobile: widget.isMobile,
            children: [
              widget.isMobile
                  ? Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _FieldCard(
                                label: 'Default Gain',
                                value: widget.isEditing
                                    ? null
                                    : (widget.profile.defaultGain?.toString() ??
                                        'Not set'),
                                controller:
                                    widget.isEditing ? _gainController : null,
                                hint: 'e.g., 100',
                                colors: widget.colors,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _FieldCard(
                                label: 'Default Offset',
                                value: widget.isEditing
                                    ? null
                                    : (widget.profile.defaultOffset
                                            ?.toString() ??
                                        'Not set'),
                                controller:
                                    widget.isEditing ? _offsetController : null,
                                hint: 'e.g., 10',
                                colors: widget.colors,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _FieldCard(
                          label: 'Cooling Temp',
                          value: widget.isEditing
                              ? null
                              : (widget.profile.defaultCoolingTemp != null
                                  ? '${widget.profile.defaultCoolingTemp!.toStringAsFixed(0)}°C'
                                  : 'Not set'),
                          controller:
                              widget.isEditing ? _coolingController : null,
                          suffix: '°C',
                          hint: 'e.g., -10',
                          colors: widget.colors,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _FieldCard(
                            label: 'Default Gain',
                            value: widget.isEditing
                                ? null
                                : (widget.profile.defaultGain?.toString() ??
                                    'Not set'),
                            controller:
                                widget.isEditing ? _gainController : null,
                            hint: 'e.g., 100',
                            colors: widget.colors,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _FieldCard(
                            label: 'Default Offset',
                            value: widget.isEditing
                                ? null
                                : (widget.profile.defaultOffset?.toString() ??
                                    'Not set'),
                            controller:
                                widget.isEditing ? _offsetController : null,
                            hint: 'e.g., 10',
                            colors: widget.colors,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _FieldCard(
                            label: 'Cooling Temp',
                            value: widget.isEditing
                                ? null
                                : (widget.profile.defaultCoolingTemp != null
                                    ? '${widget.profile.defaultCoolingTemp!.toStringAsFixed(0)}°C'
                                    : 'Not set'),
                            controller:
                                widget.isEditing ? _coolingController : null,
                            suffix: '°C',
                            hint: 'e.g., -10',
                            colors: widget.colors,
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 16),
              widget.isMobile
                  ? Row(
                      children: [
                        Expanded(
                          child: _BinningSelector(
                            label: 'Binning X',
                            value: _binX,
                            enabled: widget.isEditing,
                            onChanged: (v) => setState(() => _binX = v),
                            colors: widget.colors,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BinningSelector(
                            label: 'Binning Y',
                            value: _binY,
                            enabled: widget.isEditing,
                            onChanged: (v) => setState(() => _binY = v),
                            colors: widget.colors,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _BinningSelector(
                            label: 'Binning X',
                            value: _binX,
                            enabled: widget.isEditing,
                            onChanged: (v) => setState(() => _binX = v),
                            colors: widget.colors,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _BinningSelector(
                            label: 'Binning Y',
                            value: _binY,
                            enabled: widget.isEditing,
                            onChanged: (v) => setState(() => _binY = v),
                            colors: widget.colors,
                          ),
                        ),
                        const Expanded(flex: 2, child: SizedBox()),
                      ],
                    ),
            ],
          ),
          const SizedBox(height: 24),

          // Filter Configuration
          _Section(
            title: 'Filter Configuration',
            icon: LucideIcons.layers,
            colors: widget.colors,
            isMobile: widget.isMobile,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sync from hardware button (always visible when not editing)
                if (!widget.isEditing)
                  _isSyncingFilters
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                widget.colors.primary),
                          ),
                        )
                      : IconButton(
                          icon: Icon(LucideIcons.refreshCw,
                              size: 16, color: widget.colors.primary),
                          onPressed: _syncFiltersFromHardware,
                          tooltip: 'Sync from filter wheel',
                        ),
                if (widget.isEditing)
                  IconButton(
                    icon: Icon(LucideIcons.plus,
                        size: 16, color: widget.colors.primary),
                    onPressed: () {
                      setState(() {
                        _filterControllers.add(TextEditingController());
                      });
                    },
                    tooltip: 'Add filter',
                  ),
              ],
            ),
            children: [
              if (_filterControllers.isEmpty ||
                  (!widget.isEditing && widget.profile.filterNames.isEmpty))
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: widget.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      'No filters configured',
                      style: TextStyle(color: widget.colors.textMuted),
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (int i = 0;
                        i <
                            (widget.isEditing
                                ? _filterControllers.length
                                : widget.profile.filterNames.length);
                        i++)
                      widget.isEditing
                          ? _EditableFilterChip(
                              controller: _filterControllers[i],
                              onRemove: () {
                                setState(() {
                                  _filterControllers[i].dispose();
                                  _filterControllers.removeAt(i);
                                });
                              },
                              colors: widget.colors,
                            )
                          : _FilterChip(
                              name: widget.profile.filterNames[i],
                              colors: widget.colors,
                            ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Filter Focus Offsets section
          if (_hasFilters()) ...[
            _Section(
              title: 'Filter Focus Offsets',
              icon: LucideIcons.gitBranch,
              colors: widget.colors,
              isMobile: widget.isMobile,
              children: [
                Text(
                  'Focus position offset (in steps) when switching to each filter',
                  style:
                      TextStyle(color: widget.colors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                ..._buildFilterOffsetRows(),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Device Assignments
          _Section(
            title: 'Device Assignments',
            icon: LucideIcons.cpu,
            colors: widget.colors,
            isMobile: widget.isMobile,
            trailing: widget.isEditing
                ? NightshadeButton(
                    label: 'Copy from Connected',
                    icon: LucideIcons.copy,
                    variant: ButtonVariant.ghost,
                    size: ButtonSize.small,
                    onPressed: _copyFromConnectedDevices,
                  )
                : null,
            children: [
              if (!_hasDeviceAssignmentsForEdit() && !widget.isEditing)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: widget.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      'No devices assigned. Connect devices from the Equipment tab.',
                      style: TextStyle(color: widget.colors.textMuted),
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildDeviceAssignment(
                        'Camera',
                        widget.isEditing ? _cameraId : widget.profile.cameraId,
                        (val) => setState(() => _cameraId = val)),
                    _buildDeviceAssignment(
                        'Mount',
                        widget.isEditing ? _mountId : widget.profile.mountId,
                        (val) => setState(() => _mountId = val)),
                    _buildDeviceAssignment(
                        'Focuser',
                        widget.isEditing
                            ? _focuserId
                            : widget.profile.focuserId,
                        (val) => setState(() => _focuserId = val)),
                    _buildDeviceAssignment(
                        'Filter Wheel',
                        widget.isEditing
                            ? _filterWheelId
                            : widget.profile.filterWheelId,
                        (val) => setState(() => _filterWheelId = val)),
                    _buildDeviceAssignment(
                        'Guider',
                        widget.isEditing ? _guiderId : widget.profile.guiderId,
                        (val) => setState(() => _guiderId = val)),
                    _buildDeviceAssignment(
                        'Rotator',
                        widget.isEditing
                            ? _rotatorId
                            : widget.profile.rotatorId,
                        (val) => setState(() => _rotatorId = val)),
                    _buildDeviceAssignment(
                        'Dome',
                        widget.isEditing ? _domeId : widget.profile.domeId,
                        (val) => setState(() => _domeId = val)),
                    _buildDeviceAssignment(
                        'Weather',
                        widget.isEditing
                            ? _weatherId
                            : widget.profile.weatherId,
                        (val) => setState(() => _weatherId = val)),
                  ].whereType<Widget>().toList(),
                ),
              if (widget.isEditing)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Click "Copy from Connected" to assign currently connected devices, or use X to clear individual assignments.',
                    style:
                        TextStyle(color: widget.colors.textMuted, fontSize: 11),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    // Wrap with mobile back button header if needed
    if (widget.isMobile && widget.onBack != null) {
      return Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: widget.colors.surface,
              border: Border(bottom: BorderSide(color: widget.colors.border)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(LucideIcons.arrowLeft,
                          color: widget.colors.textPrimary),
                      onPressed: widget.onBack,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.profile.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: widget.colors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: content),
        ],
      );
    }

    return content;
  }

  bool _hasDeviceAssignments() {
    return widget.profile.cameraId != null ||
        widget.profile.mountId != null ||
        widget.profile.focuserId != null ||
        widget.profile.filterWheelId != null ||
        widget.profile.guiderId != null ||
        widget.profile.rotatorId != null ||
        widget.profile.domeId != null ||
        widget.profile.weatherId != null;
  }

  bool _hasDeviceAssignmentsForEdit() {
    if (widget.isEditing) {
      return _cameraId != null ||
          _mountId != null ||
          _focuserId != null ||
          _filterWheelId != null ||
          _guiderId != null ||
          _rotatorId != null ||
          _domeId != null ||
          _weatherId != null;
    }
    return _hasDeviceAssignments();
  }

  Widget? _buildDeviceAssignment(
      String type, String? deviceId, void Function(String?) onClear) {
    if (deviceId == null) return null;

    final displayId = formatDeviceId(deviceId);

    if (widget.isEditing) {
      return _EditableDeviceChip(
        type: type,
        id: displayId,
        fullId: deviceId,
        onClear: () => onClear(null),
        colors: widget.colors,
      );
    }

    return _DeviceChip(type: type, id: displayId, colors: widget.colors);
  }

  bool _hasFilters() {
    if (widget.isEditing) {
      return _filterControllers.any((c) => c.text.trim().isNotEmpty);
    }
    return widget.profile.filterNames.isNotEmpty;
  }

  List<Widget> _buildFilterOffsetRows() {
    // Get current filter names (from controllers if editing, otherwise from profile)
    final filterNames = widget.isEditing
        ? _filterControllers
            .map((c) => c.text.trim())
            .where((f) => f.isNotEmpty)
            .toList()
        : widget.profile.filterNames;

    final filterNameWidth = widget.isMobile ? 100.0 : 120.0;
    final inputWidth = widget.isMobile ? 90.0 : 100.0;

    return filterNames.map((filterName) {
      // Ensure we have a controller for this filter
      if (!_filterOffsetControllers.containsKey(filterName)) {
        _filterOffsetControllers[filterName] = TextEditingController(text: '0');
      }
      final controller = _filterOffsetControllers[filterName]!;
      final offset = widget.profile.filterFocusOffsets[filterName] ?? 0;

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              flex: widget.isMobile ? 2 : 1,
              child: Container(
                constraints: BoxConstraints(minWidth: filterNameWidth),
                padding: EdgeInsets.symmetric(
                  horizontal: widget.isMobile ? 10 : 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: widget.colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  filterName,
                  style: TextStyle(
                    color: widget.colors.textPrimary,
                    fontSize: widget.isMobile ? 13 : 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(width: widget.isMobile ? 10 : 12),
            if (widget.isEditing)
              SizedBox(
                width: inputWidth,
                child: TextFormField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                  ],
                  style: TextStyle(
                    color: widget.colors.textPrimary,
                    fontSize: widget.isMobile ? 13 : 14,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: widget.isMobile ? 6 : 8,
                      vertical: 8,
                    ),
                    suffixText: widget.isMobile ? 'st' : 'steps',
                    suffixStyle: TextStyle(
                      color: widget.colors.textMuted,
                      fontSize: widget.isMobile ? 11 : 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: widget.colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          BorderSide(color: widget.colors.primary, width: 2),
                    ),
                  ),
                ),
              )
            else
              Text(
                '$offset steps',
                style: TextStyle(
                  color: widget.colors.textSecondary,
                  fontSize: widget.isMobile ? 13 : 14,
                ),
              ),
          ],
        ),
      );
    }).toList();
  }
}

// ============================================================================
// Helper Widgets
// ============================================================================

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;
  final NightshadeColors colors;
  final bool isMobile;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
    required this.colors,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final sectionPadding = isMobile ? 16.0 : 20.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: isMobile ? 16 : 18, color: colors.primary),
            SizedBox(width: isMobile ? 6 : 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: isMobile ? 13 : 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        SizedBox(height: isMobile ? 12 : 16),
        Container(
          padding: EdgeInsets.all(sectionPadding),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _FieldCard extends StatelessWidget {
  final String label;
  final String? value;
  final TextEditingController? controller;
  final String? suffix;
  final String? hint;
  final bool readOnly;
  final NightshadeColors colors;

  const _FieldCard({
    required this.label,
    this.value,
    this.controller,
    this.suffix,
    this.hint,
    this.readOnly = false,
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
            fontSize: 11,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        if (controller != null && !readOnly)
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.border),
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                hintText: hint,
                hintStyle: TextStyle(color: colors.textMuted),
                suffixText: suffix,
                suffixStyle: TextStyle(
                  fontSize: 12,
                  color: colors.textMuted,
                ),
              ),
            ),
          )
        else
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value ?? 'Not set',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: value != null && value != 'Not set' && value != 'N/A'
                      ? colors.textPrimary
                      : colors.textMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BinningSelector extends StatelessWidget {
  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final NightshadeColors colors;

  const _BinningSelector({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
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
            fontSize: 11,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              for (int i = 1; i <= 4; i++)
                Expanded(
                  child: GestureDetector(
                    onTap: enabled ? () => onChanged(i) : null,
                    child: Container(
                      decoration: BoxDecoration(
                        color: value == i ? colors.primary : Colors.transparent,
                        borderRadius: BorderRadius.horizontal(
                          left: i == 1 ? const Radius.circular(5) : Radius.zero,
                          right:
                              i == 4 ? const Radius.circular(5) : Radius.zero,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$i',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: value == i
                                ? colors.background
                                : colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String name;
  final NightshadeColors colors;

  const _FilterChip({
    required this.name,
    required this.colors,
  });

  Color _getFilterColor(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('red') ||
        lowerName == 'r' ||
        lowerName == 'ha' ||
        lowerName.contains('h-alpha')) {
      return const Color(0xFFEF4444);
    } else if (lowerName.contains('green') || lowerName == 'g') {
      return const Color(0xFF22C55E);
    } else if (lowerName.contains('blue') || lowerName == 'b') {
      return const Color(0xFF3B82F6);
    } else if (lowerName.contains('lum') || lowerName == 'l') {
      return const Color(0xFFA1A1AA);
    } else if (lowerName.contains('oiii') || lowerName.contains('o3')) {
      return const Color(0xFF06B6D4);
    } else if (lowerName.contains('sii') || lowerName.contains('s2')) {
      return const Color(0xFFF97316);
    }
    return colors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final filterColor = _getFilterColor(name);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: filterColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: filterColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: filterColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: filterColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableFilterChip extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onRemove;
  final NightshadeColors colors;

  const _EditableFilterChip({
    required this.controller,
    required this.onRemove,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(
                fontSize: 12,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Filter name',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: colors.textMuted,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              LucideIcons.x,
              size: 14,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceChip extends StatelessWidget {
  final String type;
  final String id;
  final NightshadeColors colors;

  const _DeviceChip({
    required this.type,
    required this.id,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.link, size: 12, color: colors.textMuted),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type,
                style: TextStyle(
                  fontSize: 10,
                  color: colors.textMuted,
                ),
              ),
              Text(
                id,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditableDeviceChip extends StatelessWidget {
  final String type;
  final String id;
  final String fullId;
  final VoidCallback onClear;
  final NightshadeColors colors;

  const _EditableDeviceChip({
    required this.type,
    required this.id,
    required this.fullId,
    required this.onClear,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.link, size: 12, color: colors.textMuted),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type,
                style: TextStyle(
                  fontSize: 10,
                  color: colors.textMuted,
                ),
              ),
              Tooltip(
                message: fullId,
                child: Text(
                  id,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClear,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.x,
                size: 12,
                color: colors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final TextStyle style;
  final NightshadeColors colors;

  const _EditableField({
    required this.controller,
    this.hint,
    required this.style,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: style,
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: hint,
        hintStyle: style.copyWith(color: colors.textMuted),
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
