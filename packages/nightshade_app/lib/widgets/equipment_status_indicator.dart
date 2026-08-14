import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_app/screens/equipment/utils/equipment_disconnect.dart';
import 'package:nightshade_app/utils/cooled_camera_guard.dart';
import 'package:nightshade_app/utils/snackbar_helper.dart';

/// One device slot as the shell chip sees it: what it is called, whether it is
/// attached, and whether the active profile claims it.
typedef _DeviceSlot = ({
  IconData icon,
  String name,
  DeviceConnectionState connectionState,
  String? profileDeviceId,
  String status,
});

/// A compact equipment status indicator for the global status bar.
///
/// Shows the active profile name and a count of connected devices.
/// Click to expand a dropdown showing individual device status and actions.
class EquipmentStatusIndicator extends ConsumerWidget {
  const EquipmentStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);

    // Watch active profile
    final activeProfile = ref.watch(activeEquipmentProfileProvider);

    // Don't show if no profile
    if (activeProfile == null) {
      return const SizedBox.shrink();
    }

    final devices = _devices(ref, activeProfile);
    final counts = _countDevices(devices);

    // NEW-E4: `PopupMenuButton` wraps its child in a bare InkWell, which
    // publishes a tap action but NO button role and NO enabled state — and
    // AT-SPI reads a missing enabled flag as insensitive. Every screen's tree
    // dump therefore ended with `panel: 🔭 My Equipment / 2 connected
    // [DISABLED]` for a chip that opens a five-entry menu on click. This is the
    // shared-chrome instance of the same class as NEW-C2.
    return Semantics(
      button: true,
      enabled: true,
      label: '${activeProfile.name}, ${counts.label}',
      hint: 'Opens equipment status and actions',
      child: _menuButton(context, ref, activeProfile, devices, counts, colors),
    );
  }

  Widget _menuButton(
    BuildContext context,
    WidgetRef ref,
    EquipmentProfileModel activeProfile,
    List<_DeviceSlot> devices,
    _EquipmentCounts counts,
    NightshadeColors colors,
  ) {
    return PopupMenuButton<String>(
      tooltip: counts.tooltip,
      offset: const Offset(0, -200),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      color: colors.surface,
      child: _CompactStatus(
        profileIcon: activeProfile.profileIcon ?? '🔭',
        profileName: activeProfile.name,
        counts: counts,
        colors: colors,
      ),
      itemBuilder: (context) => _buildDropdownItems(
        context,
        ref,
        activeProfile,
        devices,
        counts,
        colors,
      ),
      onSelected: (value) => _handleMenuSelection(context, ref, value),
    );
  }

  /// Every device slot the app tracks a connection for, in dropdown order.
  ///
  /// One list feeds both the count and the rows, so the chip can never report a
  /// number the dropdown cannot account for. It covers all eleven slots, not
  /// the six the profile editor shows first: with a camera, mount, focuser,
  /// filter wheel, dome and weather station attached, a six-slot tally read
  /// "4 connected" in the status bar while the Equipment header read "6
  /// connected · 6 unsaved" — the bar a user glances at before starting a run
  /// was under-reporting live hardware by a third.
  List<_DeviceSlot> _devices(WidgetRef ref, EquipmentProfileModel profile) {
    final camera = ref.watch(cameraStateProvider);
    final mount = ref.watch(mountStateProvider);
    final focuser = ref.watch(focuserStateProvider);
    final filterWheel = ref.watch(filterWheelStateProvider);
    final guider = ref.watch(guiderStateProvider);
    final rotator = ref.watch(rotatorStateProvider);
    final dome = ref.watch(domeStateProvider);
    final weather = ref.watch(weatherStateProvider);
    final safetyMonitor = ref.watch(safetyMonitorStateProvider);
    final switchDevice = ref.watch(switchStateProvider);
    final coverCalibrator = ref.watch(coverCalibratorStateProvider);

    return [
      (
        icon: LucideIcons.camera,
        name: _getDeviceDisplayName(
            camera.deviceName, profile.cameraName, 'Camera'),
        connectionState: camera.connectionState,
        profileDeviceId: profile.cameraId,
        status: _getCameraStatus(camera),
      ),
      (
        icon: LucideIcons.compass,
        name:
            _getDeviceDisplayName(mount.deviceName, profile.mountName, 'Mount'),
        connectionState: mount.connectionState,
        profileDeviceId: profile.mountId,
        status: _getMountStatus(mount),
      ),
      (
        icon: LucideIcons.focus,
        name: _getDeviceDisplayName(
            focuser.deviceName, profile.focuserName, 'Focuser'),
        connectionState: focuser.connectionState,
        profileDeviceId: profile.focuserId,
        status: _getFocuserStatus(focuser),
      ),
      (
        icon: LucideIcons.circle,
        name: _getDeviceDisplayName(
            filterWheel.deviceName, profile.filterWheelName, 'Filter Wheel'),
        connectionState: filterWheel.connectionState,
        profileDeviceId: profile.filterWheelId,
        status: _getFilterWheelStatus(filterWheel),
      ),
      (
        icon: LucideIcons.crosshair,
        name: _getDeviceDisplayName(
            guider.deviceName, profile.guiderName, 'Guider'),
        connectionState: guider.connectionState,
        profileDeviceId: profile.guiderId,
        status: _getGuiderStatus(guider),
      ),
      (
        icon: LucideIcons.rotateCw,
        name: _getDeviceDisplayName(
            rotator.deviceName, profile.rotatorName, 'Rotator'),
        connectionState: rotator.connectionState,
        profileDeviceId: profile.rotatorId,
        status: _getRotatorStatus(rotator),
      ),
      (
        icon: LucideIcons.warehouse,
        name: _getDeviceDisplayName(dome.deviceName, null, 'Dome'),
        connectionState: dome.connectionState,
        profileDeviceId: profile.domeId,
        status: _readyStatus(dome.connectionState),
      ),
      (
        icon: LucideIcons.cloudSun,
        name:
            _getDeviceDisplayName(weather.deviceName, null, 'Weather Station'),
        connectionState: weather.connectionState,
        profileDeviceId: profile.weatherId,
        status: _readyStatus(weather.connectionState),
      ),
      (
        icon: LucideIcons.shieldCheck,
        name: _getDeviceDisplayName(safetyMonitor.deviceName,
            profile.safetyMonitorName, 'Safety Monitor'),
        connectionState: safetyMonitor.connectionState,
        profileDeviceId: profile.safetyMonitorId,
        status: _readyStatus(safetyMonitor.connectionState),
      ),
      (
        icon: LucideIcons.toggleLeft,
        name: _getDeviceDisplayName(
            switchDevice.deviceName, profile.switchName, 'Switch'),
        connectionState: switchDevice.connectionState,
        profileDeviceId: profile.switchId,
        status: _readyStatus(switchDevice.connectionState),
      ),
      (
        icon: LucideIcons.panelTop,
        name: _getDeviceDisplayName(
            coverCalibrator.deviceName, null, 'Cover Calibrator'),
        connectionState: coverCalibrator.connectionState,
        profileDeviceId: profile.coverCalibratorId,
        status: _readyStatus(coverCalibrator.connectionState),
      ),
    ];
  }

  /// Split the live device states into "what the profile expects" and "what is
  /// actually attached".
  ///
  /// Both numbers are needed because the chip has two jobs. The ratio answers
  /// "is my rig fully up?", so its numerator must stay scoped to the profile —
  /// counting every connection there once produced "4/2" on a two-device
  /// profile, which reads as a broken counter rather than as "two extra devices
  /// are attached". But scoping the ONLY count that way made a session-only
  /// connection invisible: the app's own discovery flow offers "This session
  /// only — not saved to your profile", and four devices connected that way
  /// left the shell reading "0/0 — No devices configured" while they streamed.
  /// So session-only connections are counted separately and reported, never
  /// folded into the ratio and never dropped.
  _EquipmentCounts _countDevices(List<_DeviceSlot> devices) {
    var assignedConnected = 0;
    var assignedTotal = 0;
    var sessionOnlyConnected = 0;

    for (final device in devices) {
      final isConnected =
          device.connectionState == DeviceConnectionState.connected;
      if (device.profileDeviceId != null) {
        assignedTotal++;
        if (isConnected) assignedConnected++;
      } else if (isConnected) {
        sessionOnlyConnected++;
      }
    }

    return _EquipmentCounts(
      assignedConnected: assignedConnected,
      assignedTotal: assignedTotal,
      sessionOnlyConnected: sessionOnlyConnected,
    );
  }

  static String _readyStatus(DeviceConnectionState state) =>
      state == DeviceConnectionState.connected ? 'Ready' : '---';

  List<PopupMenuEntry<String>> _buildDropdownItems(
    BuildContext context,
    WidgetRef ref,
    EquipmentProfileModel activeProfile,
    List<_DeviceSlot> devices,
    _EquipmentCounts counts,
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
          counts: counts,
          colors: colors,
        ),
      ),
    );

    items.add(PopupMenuDivider(color: colors.border));

    // "No devices configured" is only true when the profile assigns nothing AND
    // nothing is attached. With anything connected the per-device rows below
    // describe it, including devices the profile has never heard of.
    if (counts.assignedTotal == 0 && counts.totalConnected == 0) {
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
      for (final device in devices) {
        if (device.connectionState != DeviceConnectionState.connected &&
            device.profileDeviceId == null) {
          continue;
        }
        items.add(
          PopupMenuItem<String>(
            enabled: false,
            height: 36,
            child: _DeviceRow(
              icon: device.icon,
              name: device.name,
              isConnected:
                  device.connectionState == DeviceConnectionState.connected,
              status: device.status,
              colors: colors,
            ),
          ),
        );
      }
    }

    items.add(PopupMenuDivider(color: colors.border));

    // Action buttons
    //
    // Enablement is read off the SAME target list the sweep walks, not off
    // `counts`: a device mid-connect is not connected but still has a handle to
    // release, so gating on the chip counts would grey the item out while there
    // was work to do.
    final canDisconnect = equipmentDisconnectTargets(ref).any(
      (target) => !equipmentDisconnectShouldSkip(target.connectionState),
    );
    items.add(
      PopupMenuItem<String>(
        value: 'disconnect',
        enabled: canDisconnect,
        height: 40,
        child: Row(
          children: [
            Icon(
              LucideIcons.unplug,
              size: 16,
              color: canDisconnect ? colors.textSecondary : colors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              'Disconnect All',
              style: TextStyle(
                fontSize: 13,
                color: canDisconnect ? colors.textPrimary : colors.textMuted,
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

  String _getCameraStatus(CameraStateSnapshot state) {
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
        _disconnectAll(ref, context);
        break;
      case 'equipment':
        context.go('/equipment');
        break;
    }
  }

  Future<void> _disconnectAll(WidgetRef ref, BuildContext context) async {
    // Disconnect All includes the camera: gate on an active cooler so the TEC
    // is never cut abruptly without an explicit confirm (same guard as the
    // per-device card).
    final proceed = await confirmDisconnectCooledCamera(context, ref);
    if (!proceed || !context.mounted) return;

    // Skip by connection state via [runEquipmentDisconnectAll], not
    // error-message substring matching in notifier disconnect paths.
    final summary = await runEquipmentDisconnectAll(ref);
    if (!context.mounted) return;

    for (final failure in summary.failures) {
      context.showErrorSnackBar('Failed to disconnect $failure');
    }
  }
}

/// Live equipment counts behind the shell chip.
///
/// See [EquipmentStatusIndicator._countDevices] for why the profile ratio and
/// the session-only count are kept apart.
class _EquipmentCounts {
  /// Profile-assigned slots whose device is connected — the ratio numerator.
  final int assignedConnected;

  /// Slots the active profile assigns a device to — the ratio denominator.
  final int assignedTotal;

  /// Connected devices in slots the profile does NOT assign. The profile ratio
  /// has no room for these, so they are reported separately instead of being
  /// dropped.
  final int sessionOnlyConnected;

  const _EquipmentCounts({
    required this.assignedConnected,
    required this.assignedTotal,
    required this.sessionOnlyConnected,
  });

  /// Everything that is actually attached right now.
  int get totalConnected => assignedConnected + sessionOnlyConnected;

  /// What the chip reads.
  ///
  /// With nothing assigned the ratio is meaningless ("0/0" while four devices
  /// stream), so state the live count instead. With assignments the ratio is
  /// what the operator wants, plus an explicit "+n" for anything attached that
  /// the profile does not know about.
  String get label {
    if (assignedTotal == 0) return '$totalConnected connected';
    if (sessionOnlyConnected > 0) {
      return '$assignedConnected/$assignedTotal +$sessionOnlyConnected';
    }
    return '$assignedConnected/$assignedTotal';
  }

  /// Long-form of [label] for the hover tooltip, which has room to say what the
  /// "+n" means.
  String get tooltip {
    final parts = <String>['$totalConnected connected'];
    if (assignedTotal > 0) {
      parts.add('$assignedConnected of $assignedTotal in this profile');
    }
    if (sessionOnlyConnected > 0) {
      parts.add('$sessionOnlyConnected not saved to this profile');
    }
    return 'Equipment status — ${parts.join(' · ')}';
  }

  /// Muted when nothing is attached, success when the profile is fully up (a
  /// profile that assigns nothing is "fully up" as soon as anything connects),
  /// warning when some assigned device is still missing.
  Color statusColor(NightshadeColors colors) {
    if (totalConnected == 0) return colors.textMuted;
    if (assignedConnected == assignedTotal) return colors.success;
    return colors.warning;
  }
}

/// Compact status display for the status bar
class _CompactStatus extends StatelessWidget {
  final String profileIcon;
  final String profileName;
  final _EquipmentCounts counts;
  final NightshadeColors colors;

  const _CompactStatus({
    required this.profileIcon,
    required this.profileName,
    required this.counts,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = counts.statusColor(colors);

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
            counts.label,
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
  final _EquipmentCounts counts;
  final NightshadeColors colors;

  const _DropdownHeader({
    required this.profileName,
    required this.profileIcon,
    required this.counts,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = counts.statusColor(colors);

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
          counts.label,
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
