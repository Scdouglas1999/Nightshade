import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart' as db;
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/tutorial_keys/equipment_keys.dart';
import 'profile_chip.dart';

/// A horizontal scrollable bar of profile chips for quick profile selection
class QuickConnectBar extends ConsumerWidget {
  final int? selectedProfileId;
  final ValueChanged<db.EquipmentProfile> onProfileSelected;
  final VoidCallback onCreateProfile;

  const QuickConnectBar({
    super.key,
    required this.selectedProfileId,
    required this.onProfileSelected,
    required this.onCreateProfile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final profilesAsync = ref.watch(allProfilesProvider);

    // Watch device connection states
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);

    return Container(
      key: EquipmentTutorialKeys.quickConnectBar,
      height: 56,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: profilesAsync.when(
        data: (profiles) => _buildProfileBar(
          context,
          ref,
          profiles,
          colors,
          cameraState,
          mountState,
          focuserState,
          filterWheelState,
          guiderState,
        ),
        loading: () => Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: colors.error),
              const SizedBox(width: 8),
              Text(
                'Failed to load profiles',
                style: TextStyle(color: colors.error, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileBar(
    BuildContext context,
    WidgetRef ref,
    List<db.EquipmentProfile> profiles,
    NightshadeColors colors,
    CameraState cameraState,
    MountState mountState,
    FocuserState focuserState,
    FilterWheelState filterWheelState,
    GuiderState guiderState,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ...profiles.asMap().entries.map((entry) {
            final index = entry.key;
            final profile = entry.value;
            final isSelected = profile.id == selectedProfileId;
            final (connectionState, connected, total) = _getProfileConnectionState(
              profile,
              cameraState,
              mountState,
              focuserState,
              filterWheelState,
              guiderState,
            );

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ProfileChip(
                // Add tutorial key to first profile chip for profile selector tutorial
                key: index == 0 ? EquipmentTutorialKeys.profileSelector : null,
                profile: profile,
                isSelected: isSelected,
                connectionState: connectionState,
                connectedDevices: connected,
                totalDevices: total,
                onTap: () => onProfileSelected(profile),
                onLongPress: () => _showProfileMenu(context, ref, profile, colors),
              ),
            );
          }),
          AddProfileChip(
            key: EquipmentTutorialKeys.createProfileBtn,
            onTap: onCreateProfile,
          ),
        ],
      ),
    );
  }

  (ProfileConnectionState, int, int) _getProfileConnectionState(
    db.EquipmentProfile profile,
    CameraState cameraState,
    MountState mountState,
    FocuserState focuserState,
    FilterWheelState filterWheelState,
    GuiderState guiderState,
  ) {
    int totalDevices = 0;
    int connectedDevices = 0;
    int connectingDevices = 0;
    int errorDevices = 0;
    int mismatchDevices = 0;

    // Helper to check if connected device matches profile
    // Uses flexible matching that handles different ID formats while still
    // distinguishing between different models (e.g., ASI1600 vs ASI178)
    bool isDeviceMatch(String? profileId, String? connectedId, DeviceConnectionState state) {
      if (state != DeviceConnectionState.connected) return true; // Not connected, no mismatch
      if (profileId == null || connectedId == null) return true; // No ID to compare

      final p = profileId.trim().toLowerCase();
      final c = connectedId.trim().toLowerCase();

      // Direct match
      if (p == c) return true;

      // Normalize by removing all non-alphanumeric characters
      final normP = p.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final normC = c.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normP == normC) return true;

      // One contains the other (handles "ZWO EAF" containing "eaf")
      if (normP.contains(normC) || normC.contains(normP)) return true;

      // Extract model identifiers - alphanumeric sequences containing numbers
      // These uniquely identify devices: "asi1600", "phd2", "nyx101", "eaf", "efw"
      final modelPattern = RegExp(r'[a-z]*\d+[a-z0-9]*|[a-z]{2,}');

      final profileModels = modelPattern.allMatches(normP).map((m) => m.group(0)!).toSet();
      final connectedModels = modelPattern.allMatches(normC).map((m) => m.group(0)!).toSet();

      // Find models that contain numbers (most distinguishing)
      final profileNumberedModels = profileModels.where((m) => RegExp(r'\d').hasMatch(m)).toSet();
      final connectedNumberedModels = connectedModels.where((m) => RegExp(r'\d').hasMatch(m)).toSet();

      // If both have numbered model identifiers, they must share at least one
      // This ensures ASI1600 doesn't match ASI178
      if (profileNumberedModels.isNotEmpty && connectedNumberedModels.isNotEmpty) {
        if (profileNumberedModels.intersection(connectedNumberedModels).isNotEmpty) {
          return true; // Match - same model number
        }
        // Check if one model contains another (e.g., "asi1600mmcool" contains "asi1600")
        for (final pm in profileNumberedModels) {
          for (final cm in connectedNumberedModels) {
            if (pm.contains(cm) || cm.contains(pm)) return true;
          }
        }
        return false; // Different model numbers = different devices
      }

      // If only one has numbered models, check token overlap for the rest
      // Tokenize and check for significant overlap
      final pTokens = p.split(RegExp(r'[_\-\s:]+'))
          .where((t) => t.length >= 2)
          .map((t) => t.replaceAll(RegExp(r'[^a-z0-9]'), ''))
          .where((t) => t.isNotEmpty)
          .toSet();
      final cTokens = c.split(RegExp(r'[_\-\s:]+'))
          .where((t) => t.length >= 2)
          .map((t) => t.replaceAll(RegExp(r'[^a-z0-9]'), ''))
          .where((t) => t.isNotEmpty)
          .toSet();

      if (pTokens.isEmpty || cTokens.isEmpty) return false;

      // Check for matching tokens (handles "guider" vs "guiding" via common stem)
      int matches = 0;
      for (final pt in pTokens) {
        for (final ct in cTokens) {
          if (pt == ct || pt.contains(ct) || ct.contains(pt)) {
            matches++;
            break;
          }
          // Check for common stem (4+ chars) for word variations like "guider" vs "guiding"
          if (pt.length >= 4 && ct.length >= 4) {
            // Find longest common prefix
            int commonLen = 0;
            final minLen = pt.length < ct.length ? pt.length : ct.length;
            for (int i = 0; i < minLen; i++) {
              if (pt[i] == ct[i]) {
                commonLen++;
              } else {
                break;
              }
            }
            // If they share a stem of 4+ characters, consider it a match
            if (commonLen >= 4) {
              matches++;
              break;
            }
          }
        }
      }

      // Require significant overlap
      final minTokens = pTokens.length < cTokens.length ? pTokens.length : cTokens.length;
      return matches >= (minTokens * 0.5).ceil(); // Match if >= 50% overlap
    }

    // Check each device type
    if (profile.cameraId != null) {
      totalDevices++;
      if (cameraState.connectionState == DeviceConnectionState.connected) {
        if (isDeviceMatch(profile.cameraId, cameraState.deviceId, cameraState.connectionState)) {
          connectedDevices++;
        } else {
          mismatchDevices++;
        }
      } else if (cameraState.connectionState == DeviceConnectionState.connecting) {
        connectingDevices++;
      } else if (cameraState.connectionState == DeviceConnectionState.error) {
        errorDevices++;
      }
    }

    if (profile.mountId != null) {
      totalDevices++;
      if (mountState.connectionState == DeviceConnectionState.connected) {
        if (isDeviceMatch(profile.mountId, mountState.deviceId, mountState.connectionState)) {
          connectedDevices++;
        } else {
          mismatchDevices++;
        }
      } else if (mountState.connectionState == DeviceConnectionState.connecting) {
        connectingDevices++;
      } else if (mountState.connectionState == DeviceConnectionState.error) {
        errorDevices++;
      }
    }

    if (profile.focuserId != null) {
      totalDevices++;
      if (focuserState.connectionState == DeviceConnectionState.connected) {
        if (isDeviceMatch(profile.focuserId, focuserState.deviceId, focuserState.connectionState)) {
          connectedDevices++;
        } else {
          mismatchDevices++;
        }
      } else if (focuserState.connectionState == DeviceConnectionState.connecting) {
        connectingDevices++;
      } else if (focuserState.connectionState == DeviceConnectionState.error) {
        errorDevices++;
      }
    }

    if (profile.filterWheelId != null) {
      totalDevices++;
      if (filterWheelState.connectionState == DeviceConnectionState.connected) {
        if (isDeviceMatch(profile.filterWheelId, filterWheelState.deviceId, filterWheelState.connectionState)) {
          connectedDevices++;
        } else {
          mismatchDevices++;
        }
      } else if (filterWheelState.connectionState == DeviceConnectionState.connecting) {
        connectingDevices++;
      } else if (filterWheelState.connectionState == DeviceConnectionState.error) {
        errorDevices++;
      }
    }

    if (profile.guiderId != null) {
      totalDevices++;
      if (guiderState.connectionState == DeviceConnectionState.connected) {
        if (isDeviceMatch(profile.guiderId, guiderState.deviceId, guiderState.connectionState)) {
          connectedDevices++;
        } else {
          mismatchDevices++;
        }
      } else if (guiderState.connectionState == DeviceConnectionState.connecting) {
        connectingDevices++;
      } else if (guiderState.connectionState == DeviceConnectionState.error) {
        errorDevices++;
      }
    }

    if (totalDevices == 0) {
      return (ProfileConnectionState.disconnected, 0, 0);
    }

    if (connectingDevices > 0) {
      return (ProfileConnectionState.connecting, connectedDevices, totalDevices);
    }

    // Check for mismatches - connected devices don't match profile
    if (mismatchDevices > 0) {
      return (ProfileConnectionState.mismatch, connectedDevices, totalDevices);
    }

    if (errorDevices > 0 && connectedDevices == 0) {
      return (ProfileConnectionState.error, connectedDevices, totalDevices);
    }

    if (connectedDevices == totalDevices) {
      return (ProfileConnectionState.connected, connectedDevices, totalDevices);
    }

    if (connectedDevices > 0) {
      return (ProfileConnectionState.partiallyConnected, connectedDevices, totalDevices);
    }

    return (ProfileConnectionState.disconnected, 0, totalDevices);
  }

  void _showProfileMenu(
    BuildContext context,
    WidgetRef ref,
    db.EquipmentProfile profile,
    NightshadeColors colors,
  ) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Edit Profile', style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.copy_outlined, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Duplicate', style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'default',
          child: Row(
            children: [
              Icon(Icons.star_outline, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text('Set as Default', style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: colors.error),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: colors.error)),
            ],
          ),
        ),
      ],
    ).then((value) async {
      if (value == null) return;
      if (!context.mounted) return;

      final profileService = ref.read(profileServiceProvider);

      switch (value) {
        case 'edit':
          // Show rename dialog for the profile
          final nameController = TextEditingController(text: profile.name);
          final newName = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: colors.surface,
              title: Text('Rename Profile', style: TextStyle(color: colors.textPrimary)),
              content: TextField(
                controller: nameController,
                autofocus: true,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Profile Name',
                  labelStyle: TextStyle(color: colors.textMuted),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colors.primary),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
                  style: FilledButton.styleFrom(backgroundColor: colors.primary),
                  child: const Text('Save'),
                ),
              ],
            ),
          );
          if (newName != null && newName.isNotEmpty && newName != profile.name) {
            try {
              final dao = ref.read(equipmentProfilesDaoProvider);
              await dao.updateProfile(profile.copyWith(
                name: newName,
                updatedAt: DateTime.now(),
              ));
              if (!context.mounted) return;
              context.showSuccessSnackBar('Renamed to "$newName"');
            } catch (e) {
              if (!context.mounted) return;
              context.showErrorSnackBar('Failed to rename: $e');
            }
          }
          break;
        case 'duplicate':
          try {
            await profileService.duplicateProfile(profile.id, '${profile.name} Copy');
            if (!context.mounted) return;
            context.showSuccessSnackBar('Duplicated "${profile.name}"');
          } catch (e) {
            if (!context.mounted) return;
            context.showErrorSnackBar('Failed to duplicate: $e');
          }
          break;
        case 'default':
          try {
            final dao = ref.read(equipmentProfilesDaoProvider);
            await dao.setActiveProfile(profile.id);
            if (!context.mounted) return;
            context.showSuccessSnackBar('"${profile.name}" set as default');
          } catch (e) {
            if (!context.mounted) return;
            context.showErrorSnackBar('Failed to set default: $e');
          }
          break;
        case 'delete':
          if (!context.mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: colors.surface,
              title: Text('Delete Profile', style: TextStyle(color: colors.textPrimary)),
              content: Text(
                'Delete "${profile.name}"? This cannot be undone.',
                style: TextStyle(color: colors.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text('Delete', style: TextStyle(color: colors.error)),
                ),
              ],
            ),
          );

          if (confirmed == true) {
            try {
              await profileService.deleteProfile(profile.id);
              if (!context.mounted) return;
              context.showSuccessSnackBar('Deleted "${profile.name}"');
            } catch (e) {
              if (!context.mounted) return;
              context.showErrorSnackBar('Failed to delete: $e');
            }
          }
          break;
      }
    });
  }
}
