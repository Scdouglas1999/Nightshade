part of '../equipment_profiles_screen.dart';

typedef EquipmentProfileImportPicker = Future<XFile?> Function();
typedef EquipmentProfileImportReader = Future<String> Function(XFile file);
typedef EquipmentProfileImporter = Future<List<int>> Function(String json);
typedef EquipmentProfileExportPicker = Future<ExportTarget?> Function(
  String suggestedName,
);
typedef EquipmentProfileExporter = Future<String> Function(int profileId);
typedef EquipmentProfileExportWriter = Future<void> Function(
  String path,
  String fileName,
  String json,
);

Future<XFile?> _pickEquipmentProfileImport() {
  const jsonGroup = XTypeGroup(
    label: 'JSON files',
    extensions: ['json'],
  );
  return openFile(acceptedTypeGroups: [jsonGroup]);
}

final equipmentProfileImportPickerProvider =
    Provider<EquipmentProfileImportPicker>(
  (ref) => _pickEquipmentProfileImport,
);

final equipmentProfileImportReaderProvider =
    Provider<EquipmentProfileImportReader>(
  (ref) => (file) => file.readAsString(),
);

final equipmentProfileImporterProvider = Provider<EquipmentProfileImporter>(
  (ref) => (json) =>
      ref.read(equipmentProfilesProvider.notifier).importProfiles(json),
);

/// Resolves the export destination. Not `getSaveLocation`: Android/iOS have no
/// save dialog (`getSavePath` throws UnimplementedError), so exporting a
/// profile was dead on a phone. There the target is a sandbox path and
/// [_exportProfile] finishes with the share sheet.
final equipmentProfileExportPickerProvider =
    Provider<EquipmentProfileExportPicker>((ref) {
  return (suggestedName) => chooseExportTarget(
        suggestedName: suggestedName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON files', extensions: ['json']),
        ],
      );
});

final equipmentProfileExporterProvider = Provider<EquipmentProfileExporter>(
  (ref) => (profileId) =>
      ref.read(equipmentProfilesProvider.notifier).exportProfile(profileId),
);

final equipmentProfileExportWriterProvider =
    Provider<EquipmentProfileExportWriter>((ref) {
  return (path, fileName, json) => XFile.fromData(
        utf8.encode(json),
        mimeType: 'application/json',
        name: fileName,
      ).saveTo(path);
});

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
  bool _isImportingProfiles = false;
  int _importGeneration = 0;
  bool _isExportingProfile = false;
  int _exportGeneration = 0;
  int _profileMutationGeneration = 0;

  @override
  Widget build(BuildContext context) {
    ref.listen<NightshadeBackend>(backendProvider, (previous, next) {
      if (previous == null || identical(previous, next)) return;
      _importGeneration++;
      _exportGeneration++;
      _profileMutationGeneration++;
      setState(() {
        _selectedProfile = null;
        _isEditing = false;
        _showingDetail = false;
        _isImportingProfiles = false;
        _isExportingProfile = false;
      });
    });
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
          final authority = ref.read(backendProvider);
          final activeProfile = state.activeProfile!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                _selectedProfile != null ||
                !identical(ref.read(backendProvider), authority)) {
              return;
            }
            setState(() => _selectedProfile = activeProfile);
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
        onSave: _saveSelectedProfile,
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
        onRefresh: _refreshSelectedProfile,
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
      onImportProfiles:
          _isImportingProfiles ? null : () => _importProfiles(context),
      isImportingProfiles: _isImportingProfiles,
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
          onImportProfiles:
              _isImportingProfiles ? null : () => _importProfiles(context),
          isImportingProfiles: _isImportingProfiles,
        ),

        // Profile details
        Expanded(
          child: _selectedProfile != null
              ? _ProfileDetails(
                  profile: _selectedProfile!,
                  isActive: _selectedProfile?.id == state.activeProfile?.id,
                  isEditing: _isEditing,
                  onEdit: () => setState(() => _isEditing = true),
                  onSave: _saveSelectedProfile,
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
                  onRefresh: _refreshSelectedProfile,
                )
              : const EmptyState.compact(
                  icon: LucideIcons.aperture,
                  title: 'Select a profile',
                  body: 'Choose a profile from the list or create a new one',
                ),
        ),
      ],
    );
  }

  Future<void> _saveSelectedProfile(
      EquipmentProfileModel updatedProfile) async {
    final authority = ref.read(backendProvider);
    final profileId = updatedProfile.id;
    await ref
        .read(equipmentProfilesProvider.notifier)
        .updateProfile(updatedProfile);
    if (!mounted ||
        !identical(ref.read(backendProvider), authority) ||
        _selectedProfile?.id != profileId) {
      return;
    }
    setState(() {
      _selectedProfile = updatedProfile;
      _isEditing = false;
    });
  }

  Future<bool> _refreshSelectedProfile(
    int profileId,
    NightshadeBackend authority,
  ) async {
    // ProfileService invalidates the authoritative list after its write.
    // Await that refresh instead of immediately reading the previous cache or
    // invalidating a second time and restarting the in-flight reload.
    final refreshed = await ref.read(equipmentProfilesProvider.future);
    if (!mounted ||
        !identical(ref.read(backendProvider), authority) ||
        _selectedProfile?.id != profileId) {
      return false;
    }

    EquipmentProfileModel? updated;
    for (final profile in refreshed.profiles) {
      if (profile.id == profileId) {
        updated = profile;
        break;
      }
    }
    if (updated == null) {
      throw StateError(
        'Filters were saved, but profile $profileId could not be reloaded.',
      );
    }
    setState(() => _selectedProfile = updated);
    return true;
  }

  bool _isCurrentProfileMutation(
    int generation,
    NightshadeBackend authority,
  ) {
    return mounted &&
        generation == _profileMutationGeneration &&
        identical(ref.read(backendProvider), authority);
  }

  Future<EquipmentProfileModel?> _awaitMutatedProfile({
    required int profileId,
    required int generation,
    required NightshadeBackend authority,
    required String operation,
  }) async {
    final refreshed = await ref.read(equipmentProfilesProvider.future);
    if (!_isCurrentProfileMutation(generation, authority)) return null;
    for (final profile in refreshed.profiles) {
      if (profile.id == profileId) return profile;
    }
    throw StateError(
      '$operation completed, but profile $profileId was absent from the '
      'refreshed profile list.',
    );
  }

  Future<void> _showCreateProfileDialog(
      BuildContext context, NightshadeColors colors) async {
    final result = await showDialog<({String name, String? description})>(
      context: context,
      builder: (dialogContext) => _CreateProfileDialog(colors: colors),
    );

    if (result == null || !mounted) return;
    final authority = ref.read(backendProvider);
    final generation = ++_profileMutationGeneration;
    try {
      final id = await ref
          .read(equipmentProfilesProvider.notifier)
          .createProfile(name: result.name, description: result.description);
      if (!_isCurrentProfileMutation(generation, authority)) return;
      final newProfile = await _awaitMutatedProfile(
        profileId: id,
        generation: generation,
        authority: authority,
        operation: 'Profile creation',
      );
      if (newProfile == null) return;
      setState(() {
        _selectedProfile = newProfile;
        _isEditing = true;
        _showingDetail = widget.isMobile;
      });
    } catch (error) {
      if (_isCurrentProfileMutation(generation, authority) && context.mounted) {
        context.showErrorSnackBar('Create profile failed: $error');
      }
    }
  }

  Future<void> _duplicateProfile(BuildContext context, NightshadeColors colors,
      EquipmentProfileModel profile) async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _DuplicateProfileDialog(
        colors: colors,
        initialName: '${profile.name} (Copy)',
      ),
    );

    if (result == null || profile.id == null || !mounted) return;
    final authority = ref.read(backendProvider);
    final generation = ++_profileMutationGeneration;
    try {
      final id = await ref
          .read(equipmentProfilesProvider.notifier)
          .duplicateProfile(profile.id!, result);
      if (!_isCurrentProfileMutation(generation, authority)) return;
      final newProfile = await _awaitMutatedProfile(
        profileId: id,
        generation: generation,
        authority: authority,
        operation: 'Profile duplication',
      );
      if (newProfile == null) return;
      setState(() {
        _selectedProfile = newProfile;
        _isEditing = false;
        _showingDetail = widget.isMobile;
      });
    } catch (error) {
      if (_isCurrentProfileMutation(generation, authority) && context.mounted) {
        context.showErrorSnackBar('Duplicate profile failed: $error');
      }
    }
  }

  Future<void> _deleteProfile(BuildContext context, NightshadeColors colors,
      EquipmentProfileModel profile) async {
    final confirm = await ConfirmDialog.delete(
      context: context,
      itemName: 'profile "${profile.name}"',
    );

    if (!confirm || profile.id == null || !mounted) return;
    final authority = ref.read(backendProvider);
    final generation = ++_profileMutationGeneration;
    try {
      await ref
          .read(equipmentProfilesProvider.notifier)
          .deleteProfile(profile.id!);
      if (!_isCurrentProfileMutation(generation, authority)) return;
      setState(() {
        if (_selectedProfile?.id == profile.id) {
          _selectedProfile = null;
          _isEditing = false;
          _showingDetail = false;
        }
      });
    } catch (error) {
      if (_isCurrentProfileMutation(generation, authority) && context.mounted) {
        context.showErrorSnackBar('Delete profile failed: $error');
      }
    }
  }

  Future<void> _exportProfile(
      BuildContext context, EquipmentProfileModel profile) async {
    if (_isExportingProfile || profile.id == null) return;
    final generation = ++_exportGeneration;
    final authority = ref.read(backendProvider);
    setState(() => _isExportingProfile = true);

    bool isCurrent() =>
        mounted &&
        generation == _exportGeneration &&
        identical(ref.read(backendProvider), authority);

    try {
      final fileName =
          '${profile.name.replaceAll(RegExp(r'[^\w\s-]'), '_')}_profile.json';
      final target = await ref.read(equipmentProfileExportPickerProvider)(
        fileName,
      );
      if (target == null || !isCurrent()) return;

      final json =
          await ref.read(equipmentProfileExporterProvider)(profile.id!);
      if (!isCurrent()) return;

      await ref.read(equipmentProfileExportWriterProvider)(
        target.path,
        fileName,
        json,
      );

      if (isCurrent() && context.mounted) {
        await revealExportedFile(
          context,
          target.path,
          subject: 'Nightshade equipment profile',
          desktopMessage: 'Profile exported to ${target.path}',
        );
      }
    } catch (e) {
      if (!isCurrent() || !context.mounted) return;
      context.showErrorSnackBar('Export failed: $e');
    } finally {
      if (mounted && generation == _exportGeneration) {
        setState(() => _isExportingProfile = false);
      }
    }
  }

  Future<void> _importProfiles(BuildContext context) async {
    if (_isImportingProfiles) return;
    final generation = ++_importGeneration;
    final authority = ref.read(backendProvider);
    setState(() => _isImportingProfiles = true);

    try {
      final file = await ref.read(equipmentProfileImportPickerProvider)();
      if (file == null || !_isCurrentImport(generation, authority)) return;

      final json = await ref.read(equipmentProfileImportReaderProvider)(file);
      if (!_isCurrentImport(generation, authority)) return;

      final ids = await ref.read(equipmentProfileImporterProvider)(json);
      if (!_isCurrentImport(generation, authority)) return;

      // The notifier invalidates after import. Await the refreshed authority
      // instead of sleeping for an arbitrary 100 ms and assuming it is ready.
      final refreshed = await ref.read(equipmentProfilesProvider.future);
      if (!_isCurrentImport(generation, authority)) return;

      if (ids.isNotEmpty) {
        EquipmentProfileModel? imported;
        for (final profile in refreshed.profiles) {
          if (profile.id == ids.first) {
            imported = profile;
            break;
          }
        }
        if (imported != null) {
          setState(() {
            _selectedProfile = imported;
            _isEditing = false;
            _showingDetail = widget.isMobile;
          });
        }
      }

      if (context.mounted) {
        context.showSuccessSnackBar('Imported ${ids.length} profile(s)');
      }
    } catch (e) {
      if (!context.mounted || !_isCurrentImport(generation, authority)) return;
      context.showErrorSnackBar('Import failed: $e');
    } finally {
      if (_isCurrentImport(generation, authority)) {
        setState(() => _isImportingProfiles = false);
      }
    }
  }

  bool _isCurrentImport(int generation, NightshadeBackend authority) {
    return mounted &&
        generation == _importGeneration &&
        identical(ref.read(backendProvider), authority);
  }
}

class _CreateProfileDialog extends StatefulWidget {
  final NightshadeColors colors;

  const _CreateProfileDialog({required this.colors});

  @override
  State<_CreateProfileDialog> createState() => _CreateProfileDialogState();
}

class _CreateProfileDialogState extends State<_CreateProfileDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _nameError;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Create New Profile',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Profile Name',
                errorText: _nameError,
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
              controller: _descriptionController,
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
          onPressed: () => Navigator.pop(context),
        ),
        NightshadeButton(
          label: 'Create',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
          onPressed: _submit,
        ),
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a profile name.');
      return;
    }
    final description = _descriptionController.text.trim();
    Navigator.pop(
      context,
      (
        name: name,
        description: description.isEmpty ? null : description,
      ),
    );
  }
}

class _DuplicateProfileDialog extends StatefulWidget {
  final NightshadeColors colors;
  final String initialName;

  const _DuplicateProfileDialog({
    required this.colors,
    required this.initialName,
  });

  @override
  State<_DuplicateProfileDialog> createState() =>
      _DuplicateProfileDialogState();
}

class _DuplicateProfileDialogState extends State<_DuplicateProfileDialog> {
  late final TextEditingController _nameController;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Duplicate Profile',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        onChanged: (_) {
          if (_nameError != null) {
            setState(() => _nameError = null);
          }
        },
        style: TextStyle(color: colors.textPrimary),
        decoration: InputDecoration(
          labelText: 'New Profile Name',
          errorText: _nameError,
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
          onPressed: () => Navigator.pop(context),
        ),
        NightshadeButton(
          label: 'Duplicate',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
          onPressed: _submit,
        ),
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a profile name.');
      return;
    }
    Navigator.pop(context, name);
  }
}

// ============================================================================
// Profile List Sidebar
// ============================================================================
