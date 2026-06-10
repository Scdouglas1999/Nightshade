part of '../equipment_profiles_screen.dart';

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
    final colors = NightshadeColors.of(context);
    final profilesAsync = ref.watch(equipmentProfilesProvider);

    return profilesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: EmptyState.compact(
          icon: LucideIcons.alertTriangle,
          title: 'Could not load profiles',
          body: 'Something went wrong reading your equipment profiles. '
              'Pull to refresh or try again.',
          action: NightshadeButton(
            label: 'Retry',
            icon: LucideIcons.refreshCw,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => ref.invalidate(equipmentProfilesProvider),
          ),
        ),
      ),
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
                )
              : EmptyState.compact(
                icon: LucideIcons.aperture,
                title: 'Select a profile',
                body:
                    'Choose a profile from the list or create a new one',
              ),
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
        content: SingleChildScrollView(
          child: Column(
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
