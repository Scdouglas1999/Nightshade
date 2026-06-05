part of '../discovery_panel.dart';

/// Individual device row in the discovery panel with assign dropdown
class _DeviceRowItem extends ConsumerStatefulWidget {
  final UnifiedDevice device;
  final DeviceType deviceType;
  final Future<void> Function() onConnect;
  final Future<void> Function() onDisconnect;
  final ValueChanged<(DeviceInfo, int)>? onAssignDevice;

  const _DeviceRowItem({
    required this.device,
    required this.deviceType,
    required this.onConnect,
    required this.onDisconnect,
    this.onAssignDevice,
  });

  @override
  ConsumerState<_DeviceRowItem> createState() => _DeviceRowItemState();
}

class _DeviceRowItemState extends ConsumerState<_DeviceRowItem> {
  bool _isConnecting = false;

  bool _isDeviceConnected() {
    switch (widget.deviceType) {
      case DeviceType.camera:
        final state = ref.read(cameraStateProvider);
        return state.connectionState == DeviceConnectionState.connected &&
            _deviceIdsMatch(state.deviceId, widget.device.activeDeviceId);
      case DeviceType.mount:
        final state = ref.read(mountStateProvider);
        return state.connectionState == DeviceConnectionState.connected &&
            _deviceIdsMatch(state.deviceId, widget.device.activeDeviceId);
      case DeviceType.focuser:
        final state = ref.read(focuserStateProvider);
        return state.connectionState == DeviceConnectionState.connected &&
            _deviceIdsMatch(state.deviceId, widget.device.activeDeviceId);
      case DeviceType.filterWheel:
        final state = ref.read(filterWheelStateProvider);
        return state.connectionState == DeviceConnectionState.connected &&
            _deviceIdsMatch(state.deviceId, widget.device.activeDeviceId);
      case DeviceType.guider:
        final state = ref.read(guiderStateProvider);
        return state.connectionState == DeviceConnectionState.connected &&
            _deviceIdsMatch(state.deviceId, widget.device.activeDeviceId);
      case DeviceType.rotator:
        final state = ref.read(rotatorStateProvider);
        return state.connectionState == DeviceConnectionState.connected &&
            _deviceIdsMatch(state.deviceId, widget.device.activeDeviceId);
      default:
        return false;
    }
  }

  bool _deviceIdsMatch(String? connectedId, String discoveredId) {
    if (connectedId == null) return false;
    final c = connectedId.trim().toLowerCase();
    final d = discoveredId.trim().toLowerCase();
    if (c == d) return true;
    // Normalize and compare
    final normC = c.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normD = d.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normC == normD) return true;
    if (normC.contains(normD) || normD.contains(normC)) return true;
    return false;
  }

  Future<void> _handleConnect() async {
    if (_isConnecting) return;

    setState(() => _isConnecting = true);
    try {
      await widget.onConnect();
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _handleAssign(AssignAction action) async {
    try {
      final profileService = ref.read(profileServiceProvider);

      switch (action.deviceType) {
        case DeviceType.camera:
          await profileService.updateProfileDevices(
            action.profileId,
            cameraId: widget.device.activeDeviceId,
          );
          break;
        case DeviceType.mount:
          await profileService.updateProfileDevices(
            action.profileId,
            mountId: widget.device.activeDeviceId,
          );
          break;
        case DeviceType.focuser:
          await profileService.updateProfileDevices(
            action.profileId,
            focuserId: widget.device.activeDeviceId,
          );
          break;
        case DeviceType.filterWheel:
          await profileService.updateProfileDevices(
            action.profileId,
            filterWheelId: widget.device.activeDeviceId,
          );
          break;
        case DeviceType.guider:
          await profileService.updateProfileDevices(
            action.profileId,
            guiderId: widget.device.activeDeviceId,
          );
          break;
        case DeviceType.rotator:
          await profileService.updateProfileDevices(
            action.profileId,
            rotatorId: widget.device.activeDeviceId,
          );
          break;
        default:
          throw Exception('Unsupported device type: ${action.deviceType}');
      }

      // Notify callback if provided - need to convert from UnifiedDevice to DeviceInfo
      if (widget.onAssignDevice != null) {
        final deviceInfo = widget.device.activeDevice;
        widget.onAssignDevice!((deviceInfo, action.profileId));
      }

      // Get profile name for the success message
      final profiles = ref.read(sortedProfilesProvider);
      final profile = profiles.firstWhere(
        (p) => p.id == action.profileId,
        orElse: () => profiles.first,
      );

      if (mounted) {
        context.showSuccessSnackBar(
            'Assigned ${widget.device.displayName} to ${profile.name}');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to assign device: $e');
      }
    }
  }

  String _getSlotStatus(EquipmentProfileModel profile, DeviceType type) {
    final currentId = switch (type) {
      DeviceType.camera => profile.cameraId,
      DeviceType.mount => profile.mountId,
      DeviceType.focuser => profile.focuserId,
      DeviceType.filterWheel => profile.filterWheelId,
      DeviceType.guider => profile.guiderId,
      DeviceType.rotator => profile.rotatorId,
      _ => null,
    };
    return currentId == null || currentId.isEmpty ? '(empty)' : '(has device)';
  }

  List<PopupMenuEntry<AssignAction>> _buildAssignMenuItems(
      NightshadeColors colors) {
    final profiles = ref.read(sortedProfilesProvider);
    final items = <PopupMenuEntry<AssignAction>>[];

    for (final profile in profiles) {
      if (profile.id == null) continue;

      final slotStatus = _getSlotStatus(profile, widget.deviceType);
      items.add(PopupMenuItem<AssignAction>(
        value: AssignAction(
          profileId: profile.id!,
          deviceType: widget.deviceType,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                profile.name,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              slotStatus,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ));
    }

    if (items.isEmpty) {
      items.add(PopupMenuItem<AssignAction>(
        enabled: false,
        child: Text(
          'No profiles available',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize12,
            color: colors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ));
    }

    return items;
  }

  Color _getDriverTypeColor(DriverType driverType, NightshadeColors colors) {
    return BackendProtocolColors.forBackend(driverType, colors);
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    // Watch device states to react to connection changes
    ref.watch(cameraStateProvider);
    ref.watch(mountStateProvider);
    ref.watch(focuserStateProvider);
    ref.watch(filterWheelStateProvider);
    ref.watch(guiderStateProvider);
    ref.watch(rotatorStateProvider);

    final isConnected = _isDeviceConnected();
    final activeBackend = widget.device.activeBackend;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Connection indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected
                  ? colors.success
                  : colors.textMuted.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 12),

          // Device name
          Expanded(
            child: Text(
              widget.device.displayName,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 8),

          // Driver type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: NightshadeDecorations.statusChip(
              _getDriverTypeColor(activeBackend, colors),
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
            ),
            child: Text(
              activeBackend.shortLabel.toLowerCase(),
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize10,
                color: _getDriverTypeColor(activeBackend, colors),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Assign dropdown
          PopupMenuButton<AssignAction>(
            onSelected: _handleAssign,
            offset: const Offset(0, 30),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8)),
            color: colors.surface,
            itemBuilder: (context) => _buildAssignMenuItems(colors),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Assign',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    LucideIcons.chevronDown,
                    size: 12,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Connect/Disconnect button
          NightshadeButton(
            label: isConnected ? 'Disconnect' : 'Connect',
            variant: isConnected ? ButtonVariant.ghost : ButtonVariant.outline,
            size: ButtonSize.small,
            isLoading: _isConnecting,
            onPressed: _isConnecting
                ? null
                : (isConnected ? widget.onDisconnect : _handleConnect),
          ),
        ],
      ),
    );
  }
}
