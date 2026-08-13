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
  bool _isAssigning = false;
  int _assignGeneration = 0;

  bool _isDeviceConnected() {
    final slot = readDeviceSlot(ref, widget.deviceType);
    return slot.connectionState == DeviceConnectionState.connected &&
        _deviceIdsMatch(slot.deviceId, widget.device.activeDeviceId);
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
    // A click that lands after the connect completes but before the row
    // repaints as "Disconnect" issued a SECOND connect to a device that was
    // already connected — two `Connecting to Camera device: sim_camera_1`
    // 190 ms apart with no disconnect between them, each starting its own
    // heartbeat monitor.
    if (_isDeviceConnected()) return;

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
    if (_isAssigning) return;
    final backendOwner = ref.read(backendProvider.notifier);
    final authority = backendOwner.currentBackend;
    final profiles = ref.read(sortedProfilesProvider);
    final profile =
        profiles.where((profile) => profile.id == action.profileId).firstOrNull;
    if (profile == null) {
      if (mounted) {
        context.showErrorSnackBar(
          'Cannot assign ${widget.device.displayName}: the selected profile '
          'no longer exists.',
        );
      }
      return;
    }
    final device = widget.device;
    final generation = ++_assignGeneration;
    setState(() => _isAssigning = true);
    try {
      final profileService = ref.read(profileServiceProvider);

      switch (action.deviceType) {
        case DeviceType.camera:
          await profileService.updateProfileDevices(
            action.profileId,
            cameraId: device.activeDeviceId,
          );
          break;
        case DeviceType.mount:
          await profileService.updateProfileDevices(
            action.profileId,
            mountId: device.activeDeviceId,
          );
          break;
        case DeviceType.focuser:
          await profileService.updateProfileDevices(
            action.profileId,
            focuserId: device.activeDeviceId,
          );
          break;
        case DeviceType.filterWheel:
          await profileService.updateProfileDevices(
            action.profileId,
            filterWheelId: device.activeDeviceId,
          );
          break;
        case DeviceType.guider:
          await profileService.updateProfileDevices(
            action.profileId,
            guiderId: device.activeDeviceId,
          );
          break;
        case DeviceType.rotator:
          await profileService.updateProfileDevices(
            action.profileId,
            rotatorId: device.activeDeviceId,
          );
          break;
        case DeviceType.dome:
          await profileService.updateProfileDevices(
            action.profileId,
            domeId: device.activeDeviceId,
          );
          break;
        case DeviceType.weather:
          await profileService.updateProfileDevices(
            action.profileId,
            weatherId: device.activeDeviceId,
          );
          break;
        case DeviceType.safetyMonitor:
          await profileService.updateProfileDevices(
            action.profileId,
            safetyMonitorId: device.activeDeviceId,
          );
          break;
        case DeviceType.switch_:
          await profileService.updateProfileDevices(
            action.profileId,
            switchId: device.activeDeviceId,
          );
          break;
        case DeviceType.coverCalibrator:
          await profileService.updateProfileDevices(
            action.profileId,
            coverCalibratorId: device.activeDeviceId,
          );
          break;
      }

      if (!mounted ||
          generation != _assignGeneration ||
          !backendOwner.isCurrentBackend(authority)) {
        return;
      }

      // Notify callback if provided - need to convert from UnifiedDevice to DeviceInfo
      if (widget.onAssignDevice != null) {
        final deviceInfo = device.activeDevice;
        widget.onAssignDevice!((deviceInfo, action.profileId));
      }

      context.showSuccessSnackBar(
          'Assigned ${device.displayName} to ${profile.name}');
    } catch (e) {
      if (mounted &&
          generation == _assignGeneration &&
          backendOwner.isCurrentBackend(authority)) {
        context.showErrorSnackBar('Failed to assign device: $e');
      }
    } finally {
      if (mounted && generation == _assignGeneration) {
        setState(() => _isAssigning = false);
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
      DeviceType.dome => profile.domeId,
      DeviceType.weather => profile.weatherId,
      DeviceType.safetyMonitor => profile.safetyMonitorId,
      DeviceType.switch_ => profile.switchId,
      DeviceType.coverCalibrator => profile.coverCalibratorId,
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
    ref.listen<NightshadeBackend>(backendProvider, (previous, next) {
      if (previous == null || identical(previous, next)) return;
      _assignGeneration++;
      if (_isAssigning) setState(() => _isAssigning = false);
    });
    final colors = NightshadeColors.of(context);

    // Watch device states to react to connection changes
    ref.watch(cameraStateProvider);
    ref.watch(mountStateProvider);
    ref.watch(focuserStateProvider);
    ref.watch(filterWheelStateProvider);
    ref.watch(guiderStateProvider);
    ref.watch(rotatorStateProvider);
    ref.watch(domeStateProvider);
    ref.watch(weatherStateProvider);
    ref.watch(safetyMonitorStateProvider);
    ref.watch(switchStateProvider);
    ref.watch(coverCalibratorStateProvider);

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
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline4),
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
            enabled: !_isAssigning,
            onSelected: _handleAssign,
            offset: const Offset(0, 30),
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8)),
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
                    _isAssigning ? 'Assigning' : 'Assign',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (_isAssigning)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: colors.primary,
                      ),
                    )
                  else
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

          // Connect/Disconnect button.
          //
          // "Assign" persists the device to a profile; "Connect" does not — it
          // is a session-only connection that is silently gone after a restart.
          // The two sat side by side with nothing saying so, so the difference is
          // spelled out in the tooltip here and marked on the resulting card.
          Tooltip(
            message: isConnected
                ? 'Disconnect this device now.'
                : 'Connect for this session only. It is NOT saved to a '
                    'profile and will not reconnect on the next launch — use '
                    'Assign for that.',
            child: NightshadeButton(
              label: isConnected ? 'Disconnect' : 'Connect',
              variant:
                  isConnected ? ButtonVariant.ghost : ButtonVariant.outline,
              size: ButtonSize.small,
              isLoading: _isConnecting,
              onPressed: _isConnecting
                  ? null
                  : (isConnected ? widget.onDisconnect : _handleConnect),
            ),
          ),
        ],
      ),
    );
  }
}
