import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// A compact equipment status indicator for the global status bar.
///
/// Shows the active profile name and a count of connected devices.
/// Click to expand a dropdown showing individual device status and actions.
class EquipmentStatusIndicator extends ConsumerWidget {
  const EquipmentStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Watch active profile
    final activeProfile = ref.watch(activeEquipmentProfileProvider);

    // Watch device states
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final rotatorState = ref.watch(rotatorStateProvider);

    // Count connected devices
    final connectedCount = _countConnectedDevices(
      cameraState,
      mountState,
      focuserState,
      filterWheelState,
      guiderState,
      rotatorState,
    );
    final totalInProfile = _countDevicesInProfile(activeProfile);

    // Don't show if no profile
    if (activeProfile == null) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      tooltip: 'Equipment status',
      offset: const Offset(0, -200),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      color: colors.surface,
      child: _CompactStatus(
        profileIcon: activeProfile.profileIcon ?? '🔭',
        profileName: activeProfile.name,
        connectedCount: connectedCount,
        totalCount: totalInProfile,
        colors: colors,
      ),
      itemBuilder: (context) => _buildDropdownItems(
        context,
        ref,
        activeProfile,
        cameraState,
        mountState,
        focuserState,
        filterWheelState,
        guiderState,
        rotatorState,
        connectedCount,
        totalInProfile,
        colors,
      ),
      onSelected: (value) => _handleMenuSelection(context, ref, value),
    );
  }

  int _countConnectedDevices(
    CameraState camera,
    MountState mount,
    FocuserState focuser,
    FilterWheelState filterWheel,
    GuiderState guider,
    RotatorState rotator,
  ) {
    int count = 0;
    if (camera.connectionState == DeviceConnectionState.connected) count++;
    if (mount.connectionState == DeviceConnectionState.connected) count++;
    if (focuser.connectionState == DeviceConnectionState.connected) count++;
    if (filterWheel.connectionState == DeviceConnectionState.connected) count++;
    if (guider.connectionState == DeviceConnectionState.connected) count++;
    if (rotator.connectionState == DeviceConnectionState.connected) count++;
    return count;
  }

  int _countDevicesInProfile(EquipmentProfileModel? profile) {
    if (profile == null) return 0;
    int count = 0;
    if (profile.cameraId != null) count++;
    if (profile.mountId != null) count++;
    if (profile.focuserId != null) count++;
    if (profile.filterWheelId != null) count++;
    if (profile.guiderId != null) count++;
    if (profile.rotatorId != null) count++;
    return count;
  }

  List<PopupMenuEntry<String>> _buildDropdownItems(
    BuildContext context,
    WidgetRef ref,
    EquipmentProfileModel activeProfile,
    CameraState cameraState,
    MountState mountState,
    FocuserState focuserState,
    FilterWheelState filterWheelState,
    GuiderState guiderState,
    RotatorState rotatorState,
    int connectedCount,
    int totalCount,
    NightshadeColors colors,
  ) {
    final items = <PopupMenuEntry<String>>[];

    // Header with profile info
    items.add(
      PopupMenuItem<String>(
        enabled: false,
        height: 44,
        child: _DropdownHeader(
          profileName: activeProfile.name,
          profileIcon: activeProfile.profileIcon ?? '🔭',
          connectedCount: connectedCount,
          totalCount: totalCount,
          colors: colors,
        ),
      ),
    );

    items.add(PopupMenuDivider(color: colors.border));

    // Device rows for connected devices (only show if connected or configured in profile)
    final hasAnyDevice = activeProfile.cameraId != null ||
        activeProfile.mountId != null ||
        activeProfile.focuserId != null ||
        activeProfile.filterWheelId != null ||
        activeProfile.guiderId != null ||
        activeProfile.rotatorId != null;

    if (!hasAnyDevice && connectedCount == 0) {
      items.add(
        PopupMenuItem<String>(
          enabled: false,
          height: 36,
          child: Text(
            'No devices configured',
            style: TextStyle(
              fontSize: 12,
              color: colors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    } else {
      // Camera
      if (cameraState.connectionState == DeviceConnectionState.connected ||
          activeProfile.cameraId != null) {
        items.add(
          PopupMenuItem<String>(
            enabled: false,
            height: 36,
            child: _DeviceRow(
              icon: LucideIcons.camera,
              name: _getDeviceDisplayName(
                cameraState.deviceName,
                activeProfile.cameraName,
                'Camera',
              ),
              isConnected:
                  cameraState.connectionState == DeviceConnectionState.connected,
              status: _getCameraStatus(cameraState),
              colors: colors,
            ),
          ),
        );
      }

      // Mount
      if (mountState.connectionState == DeviceConnectionState.connected ||
          activeProfile.mountId != null) {
        items.add(
          PopupMenuItem<String>(
            enabled: false,
            height: 36,
            child: _DeviceRow(
              icon: LucideIcons.compass,
              name: _getDeviceDisplayName(
                mountState.deviceName,
                activeProfile.mountName,
                'Mount',
              ),
              isConnected:
                  mountState.connectionState == DeviceConnectionState.connected,
              status: _getMountStatus(mountState),
              colors: colors,
            ),
          ),
        );
      }

      // Focuser
      if (focuserState.connectionState == DeviceConnectionState.connected ||
          activeProfile.focuserId != null) {
        items.add(
          PopupMenuItem<String>(
            enabled: false,
            height: 36,
            child: _DeviceRow(
              icon: LucideIcons.focus,
              name: _getDeviceDisplayName(
                focuserState.deviceName,
                activeProfile.focuserName,
                'Focuser',
              ),
              isConnected:
                  focuserState.connectionState == DeviceConnectionState.connected,
              status: _getFocuserStatus(focuserState),
              colors: colors,
            ),
          ),
        );
      }

      // Filter Wheel
      if (filterWheelState.connectionState == DeviceConnectionState.connected ||
          activeProfile.filterWheelId != null) {
        items.add(
          PopupMenuItem<String>(
            enabled: false,
            height: 36,
            child: _DeviceRow(
              icon: LucideIcons.circle,
              name: _getDeviceDisplayName(
                filterWheelState.deviceName,
                activeProfile.filterWheelName,
                'Filter Wheel',
              ),
              isConnected: filterWheelState.connectionState ==
                  DeviceConnectionState.connected,
              status: _getFilterWheelStatus(filterWheelState),
              colors: colors,
            ),
          ),
        );
      }

      // Guider
      if (guiderState.connectionState == DeviceConnectionState.connected ||
          activeProfile.guiderId != null) {
        items.add(
          PopupMenuItem<String>(
            enabled: false,
            height: 36,
            child: _DeviceRow(
              icon: LucideIcons.crosshair,
              name: _getDeviceDisplayName(
                guiderState.deviceName,
                activeProfile.guiderName,
                'Guider',
              ),
              isConnected:
                  guiderState.connectionState == DeviceConnectionState.connected,
              status: _getGuiderStatus(guiderState),
              colors: colors,
            ),
          ),
        );
      }

      // Rotator
      if (rotatorState.connectionState == DeviceConnectionState.connected ||
          activeProfile.rotatorId != null) {
        items.add(
          PopupMenuItem<String>(
            enabled: false,
            height: 36,
            child: _DeviceRow(
              icon: LucideIcons.rotateCw,
              name: _getDeviceDisplayName(
                rotatorState.deviceName,
                activeProfile.rotatorName,
                'Rotator',
              ),
              isConnected:
                  rotatorState.connectionState == DeviceConnectionState.connected,
              status: _getRotatorStatus(rotatorState),
              colors: colors,
            ),
          ),
        );
      }
    }

    items.add(PopupMenuDivider(color: colors.border));

    // Action buttons
    items.add(
      PopupMenuItem<String>(
        value: 'disconnect',
        height: 40,
        child: Row(
          children: [
            Icon(LucideIcons.unplug, size: 16, color: colors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Disconnect All',
              style: TextStyle(
                fontSize: 13,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );

    items.add(
      PopupMenuItem<String>(
        value: 'equipment',
        height: 40,
        child: Row(
          children: [
            Icon(LucideIcons.settings2, size: 16, color: colors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Equipment',
              style: TextStyle(
                fontSize: 13,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );

    return items;
  }

  String _getDeviceDisplayName(
    String? connectedName,
    String? profileName,
    String fallback,
  ) {
    if (connectedName != null && connectedName.isNotEmpty) {
      return connectedName;
    }
    if (profileName != null && profileName.isNotEmpty) {
      return profileName;
    }
    return fallback;
  }

  String _getCameraStatus(CameraState state) {
    if (state.connectionState != DeviceConnectionState.connected) {
      return '---';
    }
    if (state.temperature != null) {
      return '${state.temperature!.toStringAsFixed(1)}°C';
    }
    return 'Ready';
  }

  String _getMountStatus(MountState state) {
    if (state.connectionState != DeviceConnectionState.connected) {
      return '---';
    }
    if (state.isSlewing) return 'Slewing';
    if (state.isParked) return 'Parked';
    if (state.isTracking) return 'Tracking';
    return 'Idle';
  }

  String _getFocuserStatus(FocuserState state) {
    if (state.connectionState != DeviceConnectionState.connected) {
      return '---';
    }
    if (state.isMoving) return 'Moving';
    if (state.position != null) return state.position.toString();
    return 'Ready';
  }

  String _getFilterWheelStatus(FilterWheelState state) {
    if (state.connectionState != DeviceConnectionState.connected) {
      return '---';
    }
    if (state.isMoving) return 'Moving';
    if (state.currentFilterName != null) return state.currentFilterName!;
    if (state.currentPosition != null) return 'Pos ${state.currentPosition}';
    return 'Ready';
  }

  String _getGuiderStatus(GuiderState state) {
    if (state.connectionState != DeviceConnectionState.connected) {
      return '---';
    }
    if (state.isCalibrating) return 'Calibrating';
    if (state.isGuiding && state.rmsTotal != null) {
      return '${state.rmsTotal!.toStringAsFixed(2)}"';
    }
    if (state.isGuiding) return 'Guiding';
    return 'Ready';
  }

  String _getRotatorStatus(RotatorState state) {
    if (state.connectionState != DeviceConnectionState.connected) {
      return '---';
    }
    if (state.isMoving) return 'Moving';
    if (state.position != null) return '${state.position!.toStringAsFixed(1)}°';
    return 'Ready';
  }

  void _handleMenuSelection(BuildContext context, WidgetRef ref, String value) {
    switch (value) {
      case 'disconnect':
        _disconnectAll(ref);
        break;
      case 'equipment':
        context.go('/equipment');
        break;
    }
  }

  Future<void> _disconnectAll(WidgetRef ref) async {
    // Disconnect each device via its state notifier
    // This properly cleans up state and notifies listeners
    await ref.read(cameraStateProvider.notifier).disconnect();
    await ref.read(mountStateProvider.notifier).disconnect();
    await ref.read(focuserStateProvider.notifier).disconnect();
    await ref.read(filterWheelStateProvider.notifier).disconnect();
    await ref.read(guiderStateProvider.notifier).disconnect();
    await ref.read(rotatorStateProvider.notifier).disconnect();
  }
}

/// Compact status display for the status bar
class _CompactStatus extends StatelessWidget {
  final String profileIcon;
  final String profileName;
  final int connectedCount;
  final int totalCount;
  final NightshadeColors colors;

  const _CompactStatus({
    required this.profileIcon,
    required this.profileName,
    required this.connectedCount,
    required this.totalCount,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Determine status color based on connection state
    final Color statusColor;
    if (totalCount == 0) {
      // No devices configured
      statusColor = colors.textMuted;
    } else if (connectedCount == totalCount) {
      // All devices connected
      statusColor = colors.success;
    } else if (connectedCount > 0) {
      // Some devices connected
      statusColor = colors.warning;
    } else {
      // No devices connected
      statusColor = colors.textMuted;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            profileIcon,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Text(
              profileName,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$connectedCount/$totalCount',
            style: TextStyle(
              fontSize: 11,
              color: statusColor,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Header row in the dropdown showing profile name and status
class _DropdownHeader extends StatelessWidget {
  final String profileName;
  final String profileIcon;
  final int connectedCount;
  final int totalCount;
  final NightshadeColors colors;

  const _DropdownHeader({
    required this.profileName,
    required this.profileIcon,
    required this.connectedCount,
    required this.totalCount,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    if (totalCount == 0) {
      statusColor = colors.textMuted;
    } else if (connectedCount == totalCount) {
      statusColor = colors.success;
    } else if (connectedCount > 0) {
      statusColor = colors.warning;
    } else {
      statusColor = colors.textMuted;
    }

    return Row(
      children: [
        Text(
          profileIcon,
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            profileName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: statusColor,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$connectedCount/$totalCount',
          style: TextStyle(
            fontSize: 13,
            color: statusColor,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Individual device row in the dropdown
class _DeviceRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final bool isConnected;
  final String status;
  final NightshadeColors colors;

  const _DeviceRow({
    required this.icon,
    required this.name,
    required this.isConnected,
    required this.status,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = isConnected ? colors.success : colors.textMuted;
    final textColor = isConnected ? colors.textPrimary : colors.textMuted;

    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: iconColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected ? colors.success : colors.textMuted,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 70,
          child: Text(
            status,
            style: TextStyle(
              fontSize: 11,
              color: isConnected ? colors.textSecondary : colors.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
