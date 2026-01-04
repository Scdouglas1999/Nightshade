import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart' as db;
import 'package:nightshade_ui/nightshade_ui.dart';
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
          ...profiles.map((profile) {
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
          AddProfileChip(onTap: onCreateProfile),
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
    bool isDeviceMatch(String? profileId, String? connectedId, DeviceConnectionState state) {
      if (state != DeviceConnectionState.connected) return true; // Not connected, no mismatch
      if (profileId == null || connectedId == null) return true; // No ID to compare
      return profileId == connectedId;
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

      final profileService = ref.read(profileServiceProvider);

      switch (value) {
        case 'edit':
          // Show rename dialog for the profile
          if (!context.mounted) return;
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
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Renamed to "$newName"'),
                    backgroundColor: colors.success,
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to rename: $e'),
                    backgroundColor: colors.error,
                  ),
                );
              }
            }
          }
          break;
        case 'duplicate':
          try {
            await profileService.duplicateProfile(profile.id, '${profile.name} Copy');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Duplicated "${profile.name}"'),
                  backgroundColor: colors.success,
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to duplicate: $e'),
                  backgroundColor: colors.error,
                ),
              );
            }
          }
          break;
        case 'default':
          try {
            final dao = ref.read(equipmentProfilesDaoProvider);
            await dao.setActiveProfile(profile.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('"${profile.name}" set as default'),
                  backgroundColor: colors.success,
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to set default: $e'),
                  backgroundColor: colors.error,
                ),
              );
            }
          }
          break;
        case 'delete':
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: colors.surface,
              title: Text('Delete Profile', style: TextStyle(color: colors.textPrimary)),
              content: Text(
                'Delete "${profile.name}"? This cannot be undone.',
                style: TextStyle(color: colors.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Delete', style: TextStyle(color: colors.error)),
                ),
              ],
            ),
          );

          if (confirmed == true) {
            try {
              await profileService.deleteProfile(profile.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted "${profile.name}"'),
                    backgroundColor: colors.success,
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete: $e'),
                    backgroundColor: colors.error,
                  ),
                );
              }
            }
          }
          break;
      }
    });
  }
}
