part of '../connections_tab.dart';

/// Device type enum for the save to profile dialog
enum DeviceCategory { camera, mount, focuser, filterWheel, guider, rotator }

/// Action to take when no profile exists
enum _NoProfileAction {
  createNew,
  selectExisting,
  cancel,
}

/// Get display name for a device, preferring deviceName, falling back to formatted deviceId
String _getDeviceDisplayName(
    String? deviceName, String? deviceId, String fallback) {
  if (deviceName != null && deviceName.isNotEmpty) {
    return deviceName;
  }
  if (deviceId != null && deviceId.isNotEmpty) {
    return formatDeviceId(deviceId);
  }
  return fallback;
}

/// Shows a dialog asking to save the connected device to the active profile.
/// Returns true if the device was saved, false otherwise.
Future<bool> showSaveToProfileDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String deviceId,
  required String deviceName,
  required DeviceCategory deviceType,
}) async {
  final colors = Theme.of(context).extension<NightshadeColors>()!;

  // Check if there's an active profile
  var activeProfile = await ref.read(activeProfileProvider.future);
  if (!context.mounted) return false;
  if (activeProfile == null) {
    // No active profile, show dialog with options
    final action = await showDialog<_NoProfileAction>(
      context: context,
      builder: (context) => _NoProfileDialog(
        deviceName: deviceName,
        colors: colors,
      ),
    );

    if (action == null || action == _NoProfileAction.cancel) {
      return false;
    }

    if (action == _NoProfileAction.createNew) {
      // Create a new profile and activate it
      try {
        final profileService = ref.read(profileServiceProvider);
        final newProfileId = await profileService.createProfile('New Profile');
        await profileService.loadProfile(newProfileId);
        ref.invalidate(activeProfileProvider);
        // Re-fetch the active profile
        activeProfile = await ref.read(activeProfileProvider.future);
        if (activeProfile == null) {
          if (context.mounted) {
            context.showErrorSnackBar(
              'Could not create an equipment profile. Try again.',
            );
          }
          return false;
        }
        if (context.mounted) {
          context.showSuccessSnackBar('Created new profile');
        }
      } catch (_) {
        if (context.mounted) {
          context.showErrorSnackBar(
            'Could not create an equipment profile. Try again.',
          );
        }
        return false;
      }
    } else if (action == _NoProfileAction.selectExisting) {
      if (!context.mounted) return false;
      // Show profile picker
      final selectedProfile = await showDialog<DbEquipmentProfile>(
        context: context,
        builder: (context) => _ProfilePickerDialog(colors: colors),
      );

      if (selectedProfile == null) {
        return false;
      }

      // Activate the selected profile
      try {
        final profileService = ref.read(profileServiceProvider);
        await profileService.loadProfile(selectedProfile.id);
        ref.invalidate(activeProfileProvider);
        activeProfile = selectedProfile;
        if (context.mounted) {
          context.showSuccessSnackBar('Activated "${selectedProfile.name}"');
        }
      } catch (_) {
        if (context.mounted) {
          context.showErrorSnackBar(
            'Could not activate that profile. Try again.',
          );
        }
        return false;
      }
    }
  }

  if (activeProfile == null) {
    return false;
  }

  final profile = activeProfile;

  // Check if device is already assigned to this profile
  bool alreadyAssigned = false;
  switch (deviceType) {
    case DeviceCategory.camera:
      alreadyAssigned = profile.cameraId == deviceId;
      break;
    case DeviceCategory.mount:
      alreadyAssigned = profile.mountId == deviceId;
      break;
    case DeviceCategory.focuser:
      alreadyAssigned = profile.focuserId == deviceId;
      break;
    case DeviceCategory.filterWheel:
      alreadyAssigned = profile.filterWheelId == deviceId;
      break;
    case DeviceCategory.guider:
      alreadyAssigned = profile.guiderId == deviceId;
      break;
    case DeviceCategory.rotator:
      alreadyAssigned = profile.rotatorId == deviceId;
      break;
  }

  // If already assigned, don't show dialog
  if (alreadyAssigned) {
    return false;
  }

  if (!context.mounted) return false;
  // Show the dialog
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Row(
        children: [
          Icon(LucideIcons.save, color: colors.primary, size: 20),
          const SizedBox(width: 12),
          Text(
            'Save to Profile',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Save "$deviceName" to the active profile "${profile.name}"?',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.info, color: colors.primary, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This device will be auto-connected when you activate this profile.',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.pop(context, false),
          label: 'Not Now',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: () => Navigator.pop(context, true),
          label: 'Save to Profile',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
        ),
      ],
    ),
  );

  if (result == true) {
    try {
      final profileService = ref.read(profileServiceProvider);

      switch (deviceType) {
        case DeviceCategory.camera:
          await profileService.updateProfileDevices(profile.id,
              cameraId: deviceId);
          break;
        case DeviceCategory.mount:
          await profileService.updateProfileDevices(profile.id,
              mountId: deviceId);
          break;
        case DeviceCategory.focuser:
          await profileService.updateProfileDevices(profile.id,
              focuserId: deviceId);
          break;
        case DeviceCategory.filterWheel:
          await profileService.updateProfileDevices(profile.id,
              filterWheelId: deviceId);
          break;
        case DeviceCategory.guider:
          await profileService.updateProfileDevices(profile.id,
              guiderId: deviceId);
          break;
        case DeviceCategory.rotator:
          await profileService.updateProfileDevices(profile.id,
              rotatorId: deviceId);
          break;
      }

      // Invalidate the profile provider to refresh the UI
      ref.invalidate(activeProfileProvider);

      return true;
    } catch (_) {
      if (context.mounted) {
        context.showErrorSnackBar(
          'Could not save this device to the active profile.',
        );
      }
      return false;
    }
  }

  return false;
}

/// Dialog shown when trying to save a device but no profile is active
class _NoProfileDialog extends StatelessWidget {
  final String deviceName;
  final NightshadeColors colors;

  const _NoProfileDialog({
    required this.deviceName,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Row(
        children: [
          Icon(LucideIcons.info, color: colors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No Active Profile',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'To save "$deviceName" for future sessions, you need an equipment profile.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.lightbulb, color: colors.primary, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Profiles store your equipment setup so you can quickly reconnect devices in future sessions.',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.pop(context, _NoProfileAction.cancel),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: () =>
              Navigator.pop(context, _NoProfileAction.selectExisting),
          label: 'Select Existing',
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: () => Navigator.pop(context, _NoProfileAction.createNew),
          label: 'Create New Profile',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
        ),
      ],
    );
  }
}

/// Dialog for selecting an existing profile
class _ProfilePickerDialog extends ConsumerWidget {
  final NightshadeColors colors;

  const _ProfilePickerDialog({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(allProfilesProvider);

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Row(
        children: [
          Icon(LucideIcons.scan, color: colors.primary, size: 22),
          const SizedBox(width: 12),
          Text(
            'Select Profile',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 300,
        child: profilesAsync.when(
          data: (profiles) {
            if (profiles.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.info, size: 48, color: colors.textMuted),
                    const SizedBox(height: 12),
                    Text(
                      'No profiles found',
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a new profile to get started.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              itemCount: profiles.length,
              itemBuilder: (context, index) {
                final profile = profiles[index];
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      LucideIcons.scan,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                  ),
                  title: Text(
                    profile.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    profile.description ?? 'No description',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: colors.textMuted,
                  ),
                  onTap: () => Navigator.pop(context, profile),
                );
              },
            );
          },
          loading: () => Center(
            child: CircularProgressIndicator(color: colors.primary),
          ),
          error: (error, stack) => Center(
            child: Text(
              'Could not load your equipment profiles.',
              style: TextStyle(color: colors.error),
            ),
          ),
        ),
      ),
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.pop(context),
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
      ],
    );
  }
}
