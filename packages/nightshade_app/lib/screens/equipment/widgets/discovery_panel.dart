import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../../mixins/device_connection_mixin.dart';
import '../../../utils/snackbar_helper.dart';
import '../dialogs/fujifilm_disclaimer_dialog.dart';

/// Action for assigning a device to a profile
class AssignAction {
  final int profileId;
  final DeviceType deviceType;

  const AssignAction({
    required this.profileId,
    required this.deviceType,
  });
}

/// Provider to track when the last scan occurred
// autoDispose: the "last scan: N seconds ago" label is only meaningful while
// the Equipment screen is mounted. Resetting on screen teardown avoids
// stale "last scan: 6 hours ago" strings from a previous session
// (audit-dart §1b).
final lastScanTimeProvider =
    StateProvider.autoDispose<DateTime?>((ref) => null);

/// A collapsible panel at the bottom of the equipment screen for discovering devices.
/// Shows available backends, discovered devices grouped by type, and connection controls.
class DiscoveryPanel extends ConsumerStatefulWidget {
  /// Optional callback when a device is assigned to a profile
  final ValueChanged<(DeviceInfo, int)>? onAssignDevice;

  const DiscoveryPanel({super.key, this.onAssignDevice});

  @override
  ConsumerState<DiscoveryPanel> createState() => _DiscoveryPanelState();
}

class _DiscoveryPanelState extends ConsumerState<DiscoveryPanel>
    with
        SingleTickerProviderStateMixin,
        DeviceConnectionMixin,
        WidgetsBindingObserver {
  bool _isExpanded = false;
  bool _isScanning = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  // 30s tick refreshes the "Last scan: N seconds ago" label. Suspended when
  // the app is backgrounded so a hidden equipment tab doesn't tick (§4.33).
  Timer? _lastScanTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOut,
    );
    _startLastScanTimer();
  }

  void _startLastScanTimer() {
    _lastScanTimer?.cancel();
    _lastScanTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_lastScanTimer == null || !_lastScanTimer!.isActive) {
        if (mounted) setState(() {});
        _startLastScanTimer();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lastScanTimer?.cancel();
      _lastScanTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expandController.dispose();
    _lastScanTimer?.cancel();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  Future<void> _scanForDevices() async {
    setState(() => _isScanning = true);
    try {
      await ref.read(unifiedDiscoveryProvider.notifier).discoverAll();
      ref.read(lastScanTimeProvider.notifier).state = DateTime.now();
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  String _formatLastScanTime(DateTime? lastScan) {
    if (lastScan == null) return 'Never scanned';

    final now = DateTime.now();
    final difference = now.difference(lastScan);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return '$mins min${mins == 1 ? '' : 's'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours hour${hours == 1 ? '' : 's'} ago';
    } else {
      return 'Over a day ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final discoveryState = ref.watch(unifiedDiscoveryProvider);
    final lastScanTime = ref.watch(lastScanTimeProvider);
    final groupedDevices = discoveryState.groupedDevices;
    final isDiscovering = discoveryState.isDiscovering || _isScanning;

    // Count discovered devices by type
    final cameras =
        groupedDevices.where((d) => d.type == DeviceType.camera).toList();
    final mounts =
        groupedDevices.where((d) => d.type == DeviceType.mount).toList();
    final focusers =
        groupedDevices.where((d) => d.type == DeviceType.focuser).toList();
    final filterWheels =
        groupedDevices.where((d) => d.type == DeviceType.filterWheel).toList();
    final guiders =
        groupedDevices.where((d) => d.type == DeviceType.guider).toList();
    final rotators =
        groupedDevices.where((d) => d.type == DeviceType.rotator).toList();
    final domes =
        groupedDevices.where((d) => d.type == DeviceType.dome).toList();
    final weatherStations =
        groupedDevices.where((d) => d.type == DeviceType.weather).toList();
    final safetyMonitors = groupedDevices
        .where((d) => d.type == DeviceType.safetyMonitor)
        .toList();
    final coverCalibrators = groupedDevices
        .where((d) => d.type == DeviceType.coverCalibrator)
        .toList();

    final totalDevices = groupedDevices.length;
    final lastScanText = _formatLastScanTime(lastScanTime);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header bar - always visible
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Discovery icon
                  Icon(
                    LucideIcons.radar,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 10),

                  // Title
                  Text(
                    'DISCOVERY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Summary text
                  Expanded(
                    child: Text(
                      '$totalDevices device${totalDevices == 1 ? '' : 's'} found  \u2022  Last scan: $lastScanText',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Scan All button
                  NightshadeButton(
                    label: isDiscovering ? 'Scanning...' : 'Scan All',
                    icon: LucideIcons.search,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    isLoading: isDiscovering,
                    onPressed: isDiscovering ? null : _scanForDevices,
                  ),

                  const SizedBox(width: 8),

                  // Expand/collapse button
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isExpanded ? 'Collapse' : 'Expand',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _isExpanded ? 0 : 0.5,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            LucideIcons.chevronDown,
                            size: 14,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              constraints: const BoxConstraints(maxHeight: 500),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Server configuration hint
                    if (!Platform.isWindows) _buildINDIServerHint(colors),

                    // Device lists by type (always show, even if empty for that type)
                    _buildDeviceGroupSection(
                      context,
                      colors,
                      'CAMERAS',
                      DeviceType.camera,
                      LucideIcons.camera,
                      cameras,
                    ),
                    const SizedBox(height: 12),
                    _buildDeviceGroupSection(
                      context,
                      colors,
                      'MOUNTS',
                      DeviceType.mount,
                      LucideIcons.compass,
                      mounts,
                    ),
                    const SizedBox(height: 12),
                    _buildDeviceGroupSection(
                      context,
                      colors,
                      'FOCUSERS',
                      DeviceType.focuser,
                      LucideIcons.focus,
                      focusers,
                    ),
                    const SizedBox(height: 12),
                    _buildDeviceGroupSection(
                      context,
                      colors,
                      'FILTER WHEELS',
                      DeviceType.filterWheel,
                      LucideIcons.disc,
                      filterWheels,
                    ),
                    const SizedBox(height: 12),
                    _buildDeviceGroupSection(
                      context,
                      colors,
                      'GUIDERS',
                      DeviceType.guider,
                      LucideIcons.crosshair,
                      guiders,
                    ),
                    const SizedBox(height: 12),
                    _buildDeviceGroupSection(
                      context,
                      colors,
                      'ROTATORS',
                      DeviceType.rotator,
                      LucideIcons.rotateCw,
                      rotators,
                    ),
                    const SizedBox(height: 12),
                    _buildDeviceGroupSection(
                      context,
                      colors,
                      'DOMES',
                      DeviceType.dome,
                      LucideIcons.home,
                      domes,
                    ),
                    const SizedBox(height: 12),
                    _buildDeviceGroupSection(
                      context,
                      colors,
                      'WEATHER',
                      DeviceType.weather,
                      LucideIcons.cloud,
                      weatherStations,
                    ),
                    const SizedBox(height: 12),
                    _buildDeviceGroupSection(
                      context,
                      colors,
                      'SAFETY MONITORS',
                      DeviceType.safetyMonitor,
                      LucideIcons.shieldAlert,
                      safetyMonitors,
                    ),
                    const SizedBox(height: 12),
                    _buildDeviceGroupSection(
                      context,
                      colors,
                      'COVER / CALIBRATORS',
                      DeviceType.coverCalibrator,
                      LucideIcons.sunMedium,
                      coverCalibrators,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceGroupSection(
    BuildContext context,
    NightshadeColors colors,
    String title,
    DeviceType deviceType,
    IconData icon,
    List<UnifiedDevice> devices,
  ) {
    if (devices.isEmpty) {
      // Show empty state with per-type scan button
      return Row(
        children: [
          Icon(icon, size: 14, color: colors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No ${title.toLowerCase()} found',
              style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          IconButton(
            onPressed: _scanForDevices,
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            tooltip: 'Scan for ${title.toLowerCase()}',
            style: IconButton.styleFrom(
              foregroundColor: colors.textMuted,
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 14, color: colors.textMuted),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${devices.length} found',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // Divider
          Divider(height: 1, color: colors.border.withValues(alpha: 0.5)),
          // Device list
          ...devices.map((device) => _DeviceRowItem(
                device: device,
                deviceType: deviceType,
                onConnect: () => _connectDevice(device),
                onDisconnect: () => _disconnectDevice(device.type),
                onAssignDevice: widget.onAssignDevice,
              )),
        ],
      ),
    );
  }

  Widget _buildINDIServerHint(NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.info.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.info.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.info, size: 16, color: colors.info),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Configure INDI servers in Settings to discover remote devices.',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectDevice(UnifiedDevice device) async {
    final deviceService = ref.read(deviceServiceProvider);
    final deviceId = device.activeDeviceId;

    // Fujifilm warranty disclaimer check
    if (device.type == DeviceType.camera &&
        isFujifilmDevice(deviceId, device.displayName)) {
      final accepted = await showFujifilmDisclaimerIfNeeded(context);
      if (!accepted) return;
    }

    try {
      switch (device.type) {
        case DeviceType.camera:
          await deviceService.connectCamera(deviceId);
          break;
        case DeviceType.mount:
          await deviceService.connectMount(deviceId);
          break;
        case DeviceType.focuser:
          await deviceService.connectFocuser(deviceId);
          break;
        case DeviceType.filterWheel:
          await deviceService.connectFilterWheel(deviceId);
          break;
        case DeviceType.guider:
          await deviceService.connectGuider(deviceId);
          break;
        case DeviceType.rotator:
          await deviceService.connectRotator(deviceId);
          break;
        default:
          throw Exception('Unsupported device type: ${device.type}');
      }
      if (mounted) {
        context.showSuccessSnackBar('Connected to ${device.displayName}');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to connect: $e');
      }
    }
  }

  Future<void> _disconnectDevice(DeviceType deviceType) async {
    final deviceService = ref.read(deviceServiceProvider);

    try {
      switch (deviceType) {
        case DeviceType.camera:
          await deviceService.disconnectCamera();
          break;
        case DeviceType.mount:
          await deviceService.disconnectMount();
          break;
        case DeviceType.focuser:
          await deviceService.disconnectFocuser();
          break;
        case DeviceType.filterWheel:
          await deviceService.disconnectFilterWheel();
          break;
        case DeviceType.guider:
          await deviceService.disconnectGuider();
          break;
        case DeviceType.rotator:
          await deviceService.disconnectRotator();
          break;
        default:
          throw Exception('Unsupported device type: $deviceType');
      }
      if (mounted) {
        context.showSuccessSnackBar(
            'Disconnected ${deviceType.displayName.toLowerCase()}');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to disconnect: $e');
      }
    }
  }
}

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
                  fontSize: 12,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              slotStatus,
              style: TextStyle(
                fontSize: 11,
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
            fontSize: 12,
            color: colors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ));
    }

    return items;
  }

  Color _getDriverTypeColor(DriverType driverType, NightshadeColors colors) {
    switch (driverType) {
      case DriverType.native:
        return colors.success;
      case DriverType.ascom:
        return colors.info;
      case DriverType.alpaca:
        return colors.warning;
      case DriverType.indi:
        return const Color(0xFF9333EA); // Purple
      case DriverType.simulator:
        return colors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

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
                fontSize: 12,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 8),

          // Driver type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _getDriverTypeColor(activeBackend, colors)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _getDriverTypeColor(activeBackend, colors)
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              activeBackend.shortLabel.toLowerCase(),
              style: TextStyle(
                fontSize: 10,
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
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            color: colors.surface,
            itemBuilder: (context) => _buildAssignMenuItems(colors),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Assign',
                    style: TextStyle(
                      fontSize: 11,
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
