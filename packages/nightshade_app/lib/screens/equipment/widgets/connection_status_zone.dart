import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart' as db;
import 'package:nightshade_ui/nightshade_ui.dart';

/// The adaptive connection status zone that changes based on connection state.
///
/// States:
/// - Disconnected (expanded): Shows profile preview with device list and "Connect All" button
/// - Connecting (animated): Shows live progress for each device
/// - Connected (compact): Shows minimal status bar
/// - Error (attention required): Shows error with retry options
class ConnectionStatusZone extends ConsumerStatefulWidget {
  final db.EquipmentProfile? selectedProfile;
  final VoidCallback onConnectAll;
  final VoidCallback onDisconnectAll;
  final VoidCallback onEditProfile;

  const ConnectionStatusZone({
    super.key,
    required this.selectedProfile,
    required this.onConnectAll,
    required this.onDisconnectAll,
    required this.onEditProfile,
  });

  @override
  ConsumerState<ConnectionStatusZone> createState() => _ConnectionStatusZoneState();
}

class _ConnectionStatusZoneState extends ConsumerState<ConnectionStatusZone>
    with SingleTickerProviderStateMixin {
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
    _expandController.value = 1.0;
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    if (widget.selectedProfile == null) {
      return _NoProfileSelected(colors: colors);
    }

    // Watch device states
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);

    // Build device list
    final devices = _buildDeviceList(
      widget.selectedProfile!,
      cameraState,
      mountState,
      focuserState,
      filterWheelState,
      guiderState,
    );

    // Calculate overall state
    final (overallState, connectedCount, totalCount, errorDevice) =
        _calculateOverallState(devices);

    // Auto-collapse/expand based on state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (overallState == _OverallState.connected && _isExpanded) {
        _collapse();
      } else if (overallState != _OverallState.connected && !_isExpanded) {
        _expand();
      }
    });

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Compact bar (always visible when collapsed, clickable to expand)
          if (!_isExpanded || overallState == _OverallState.connected)
            _CompactStatusBar(
              connectedCount: connectedCount,
              totalCount: totalCount,
              overallState: overallState,
              devices: devices,
              colors: colors,
              onTap: _toggle,
              onDisconnect: widget.onDisconnectAll,
            ),

          // Expandable content
          SizeTransition(
            sizeFactor: _expandAnimation,
            axisAlignment: -1.0,
            child: _buildExpandedContent(
              context,
              colors,
              devices,
              overallState,
              connectedCount,
              totalCount,
              errorDevice,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(
    BuildContext context,
    NightshadeColors colors,
    List<_DeviceStatus> devices,
    _OverallState overallState,
    int connectedCount,
    int totalCount,
    _DeviceStatus? errorDevice,
  ) {
    switch (overallState) {
      case _OverallState.disconnected:
        return _DisconnectedView(
          profile: widget.selectedProfile!,
          devices: devices,
          colors: colors,
          onConnect: widget.onConnectAll,
          onEdit: widget.onEditProfile,
        );
      case _OverallState.connecting:
        return _ConnectingView(
          profile: widget.selectedProfile!,
          devices: devices,
          colors: colors,
          onCancel: widget.onDisconnectAll,
        );
      case _OverallState.connected:
        // Compact bar handles this
        return const SizedBox.shrink();
      case _OverallState.mismatch:
        return _ErrorView(
          devices: devices,
          errorDevice: errorDevice,
          connectedCount: connectedCount,
          totalCount: totalCount,
          colors: colors,
          onRetry: widget.onConnectAll,
          onSkip: _collapse, // Dismiss mismatch warning and continue
          isMismatch: true,
        );
      case _OverallState.partiallyConnected:
      case _OverallState.error:
        return _ErrorView(
          devices: devices,
          errorDevice: errorDevice,
          connectedCount: connectedCount,
          totalCount: totalCount,
          colors: colors,
          onRetry: widget.onConnectAll,
          onSkip: _collapse, // Dismiss error and continue with partial connections
        );
    }
  }

  void _expand() {
    setState(() => _isExpanded = true);
    _expandController.forward();
  }

  void _collapse() {
    setState(() => _isExpanded = false);
    _expandController.reverse();
  }

  void _toggle() {
    if (_isExpanded) {
      _collapse();
    } else {
      _expand();
    }
  }

  List<_DeviceStatus> _buildDeviceList(
    db.EquipmentProfile profile,
    CameraState camera,
    MountState mount,
    FocuserState focuser,
    FilterWheelState filterWheel,
    GuiderState guider,
  ) {
    final devices = <_DeviceStatus>[];

    // Helper to check if connected device matches profile
    // Uses flexible matching that handles different ID formats while still
    // distinguishing between different models (e.g., ASI1600 vs ASI178)
    bool isDeviceMismatch(String? profileId, String? connectedId, DeviceConnectionState state) {
      if (state != DeviceConnectionState.connected) return false; // Not connected, no mismatch
      if (profileId == null || connectedId == null) return false; // No ID to compare

      // Debug logging
      debugPrint('[MISMATCH CHECK] Profile: "$profileId" vs Connected: "$connectedId"');

      final p = profileId.trim().toLowerCase();
      final c = connectedId.trim().toLowerCase();

      // Direct match
      if (p == c) {
        debugPrint('[MISMATCH CHECK] Direct match - no mismatch');
        return false;
      }

      // Normalize by removing all non-alphanumeric characters
      final normP = p.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final normC = c.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normP == normC) {
        debugPrint('[MISMATCH CHECK] Normalized match - no mismatch');
        return false;
      }

      // One contains the other (handles "ZWO EAF" containing "eaf")
      if (normP.contains(normC) || normC.contains(normP)) {
        debugPrint('[MISMATCH CHECK] Containment match - no mismatch');
        return false;
      }

      // Split into words first to preserve word boundaries
      // This ensures "phd2_guider" splits into ["phd2", "guider"] not ["phd2guider"]
      final profileWords = p.split(RegExp(r'[_\-\s:\.]+'))
          .map((w) => w.replaceAll(RegExp(r'[^a-z0-9]'), ''))
          .where((w) => w.isNotEmpty)
          .toList();
      final connectedWords = c.split(RegExp(r'[_\-\s:\.]+'))
          .map((w) => w.replaceAll(RegExp(r'[^a-z0-9]'), ''))
          .where((w) => w.isNotEmpty)
          .toList();

      debugPrint('[MISMATCH CHECK] Profile words: $profileWords, Connected words: $connectedWords');

      // Find words that contain numbers (most distinguishing identifiers)
      final profileNumbered = profileWords.where((w) => RegExp(r'\d').hasMatch(w)).toSet();
      final connectedNumbered = connectedWords.where((w) => RegExp(r'\d').hasMatch(w)).toSet();

      debugPrint('[MISMATCH CHECK] Profile numbered: $profileNumbered, Connected numbered: $connectedNumbered');

      // If both have numbered identifiers, they must share at least one
      // This ensures ASI1600 doesn't match ASI178, but phd2 matches phd2
      if (profileNumbered.isNotEmpty && connectedNumbered.isNotEmpty) {
        if (profileNumbered.intersection(connectedNumbered).isNotEmpty) {
          debugPrint('[MISMATCH CHECK] Numbered identifier match - no mismatch');
          return false; // Match - same model number
        }
        // Check if one model contains another (e.g., "asi1600mmcool" contains "asi1600")
        for (final pm in profileNumbered) {
          for (final cm in connectedNumbered) {
            if (pm.contains(cm) || cm.contains(pm)) {
              debugPrint('[MISMATCH CHECK] Numbered containment match: $pm / $cm - no mismatch');
              return false;
            }
          }
        }
        debugPrint('[MISMATCH CHECK] Different numbered identifiers - MISMATCH');
        return true; // Different model numbers = different devices
      }

      // Use the words we already split for token matching
      final pTokens = profileWords.where((t) => t.length >= 2).toSet();
      final cTokens = connectedWords.where((t) => t.length >= 2).toSet();

      if (pTokens.isEmpty || cTokens.isEmpty) {
        debugPrint('[MISMATCH CHECK] Empty token sets - assuming mismatch');
        return true;
      }

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
              debugPrint('[MISMATCH CHECK] Token stem match: "$pt" and "$ct" share ${commonLen}-char prefix');
              matches++;
              break;
            }
          }
        }
      }

      // Require significant overlap
      final minTokens = pTokens.length < cTokens.length ? pTokens.length : cTokens.length;
      final isMismatch = matches < (minTokens * 0.5).ceil(); // Mismatch if < 50% overlap
      debugPrint('[MISMATCH CHECK] Token match result: $matches/$minTokens tokens matched, isMismatch=$isMismatch');
      return isMismatch;
    }

    if (profile.cameraId != null) {
      devices.add(_DeviceStatus(
        type: 'Camera',
        name: camera.deviceName ?? _formatDeviceId(profile.cameraId!),
        icon: LucideIcons.camera,
        state: camera.connectionState,
        error: camera.lastError?.userMessage,
        isMismatch: isDeviceMismatch(profile.cameraId, camera.deviceId, camera.connectionState),
      ));
    }

    if (profile.mountId != null) {
      devices.add(_DeviceStatus(
        type: 'Mount',
        name: mount.deviceName ?? _formatDeviceId(profile.mountId!),
        icon: LucideIcons.compass,
        state: mount.connectionState,
        error: mount.lastError?.userMessage,
        isMismatch: isDeviceMismatch(profile.mountId, mount.deviceId, mount.connectionState),
      ));
    }

    if (profile.focuserId != null) {
      devices.add(_DeviceStatus(
        type: 'Focuser',
        name: focuser.deviceName ?? _formatDeviceId(profile.focuserId!),
        icon: LucideIcons.focus,
        state: focuser.connectionState,
        error: focuser.lastError?.userMessage,
        isMismatch: isDeviceMismatch(profile.focuserId, focuser.deviceId, focuser.connectionState),
      ));
    }

    if (profile.filterWheelId != null) {
      devices.add(_DeviceStatus(
        type: 'Filter Wheel',
        name: filterWheel.deviceName ?? _formatDeviceId(profile.filterWheelId!),
        icon: LucideIcons.circle,
        state: filterWheel.connectionState,
        error: filterWheel.lastError?.userMessage,
        isMismatch: isDeviceMismatch(profile.filterWheelId, filterWheel.deviceId, filterWheel.connectionState),
      ));
    }

    if (profile.guiderId != null) {
      devices.add(_DeviceStatus(
        type: 'Guider',
        name: guider.deviceName ?? _formatDeviceId(profile.guiderId!),
        icon: LucideIcons.crosshair,
        state: guider.connectionState,
        error: guider.lastError?.userMessage,
        isMismatch: isDeviceMismatch(profile.guiderId, guider.deviceId, guider.connectionState),
      ));
    }

    return devices;
  }

  /// Extracts a user-friendly name from a device ID
  /// Handles formats like:
  /// - native:zwo:1 → "ZWO #2"
  /// - native:zwo_eaf:0 → "ZWO EAF"
  /// - ascom:ASCOM.PegasusAstroNYX101.Telescope → "PegasusAstro NYX101"
  /// - phd2_guider → "PHD2 Guider"
  String _formatDeviceId(String id) {
    final lowerId = id.toLowerCase();

    // Handle native device IDs (native:vendor:index or native:vendor_type:index)
    if (lowerId.startsWith('native:')) {
      final parts = id.substring(7).split(':'); // Remove "native:" prefix
      if (parts.isNotEmpty) {
        final devicePart = parts[0]; // e.g., "zwo", "zwo_eaf", "zwo_efw"
        final index = parts.length > 1 ? int.tryParse(parts[1]) : null;

        // Parse vendor_type format
        if (devicePart.contains('_')) {
          final subParts = devicePart.split('_');
          final vendor = _capitalizeVendor(subParts[0]);
          final type = subParts.sublist(1).map((s) => s.toUpperCase()).join(' ');
          return '$vendor $type';
        }

        // Just vendor with index
        final vendor = _capitalizeVendor(devicePart);
        if (index != null) {
          return '$vendor #${index + 1}';
        }
        return vendor;
      }
    }

    // Handle ASCOM device IDs (ascom:ASCOM.Vendor.Type)
    if (lowerId.startsWith('ascom:')) {
      final ascomId = id.substring(6); // Remove "ascom:" prefix
      final parts = ascomId.split('.');
      if (parts.length >= 2) {
        // Try to extract vendor and model from ASCOM ID
        // e.g., "ASCOM.PegasusAstroNYX101.Telescope" → "PegasusAstro NYX101"
        // e.g., "ASCOM.ASICamera2.Camera" → "ASI Camera"
        final vendorPart = parts.length > 1 ? parts[1] : parts[0];
        return _formatAscomVendor(vendorPart);
      }
    }

    // Handle Alpaca device IDs
    if (lowerId.startsWith('alpaca:')) {
      final parts = id.substring(7).split(':');
      if (parts.isNotEmpty) {
        final type = _capitalizeWord(parts[0]);
        final index = parts.length > 1 ? int.tryParse(parts[1]) : null;
        if (index != null) {
          return 'Alpaca $type #${index + 1}';
        }
        return 'Alpaca $type';
      }
    }

    // Handle special IDs like phd2_guider
    if (lowerId.contains('phd2')) {
      return 'PHD2 Guiding';
    }

    // Handle dot-separated IDs (fallback for ASCOM-style)
    if (id.contains('.')) {
      final parts = id.split('.');
      return _formatAscomVendor(parts[parts.length > 1 ? 1 : 0]);
    }

    // Handle underscore-separated IDs
    if (id.contains('_')) {
      return id.split('_').map(_capitalizeWord).join(' ');
    }

    // Return as-is if no pattern matched
    return id;
  }

  String _capitalizeVendor(String vendor) {
    final lower = vendor.toLowerCase();
    // Known vendor name capitalizations
    const vendors = {
      'zwo': 'ZWO',
      'qhy': 'QHY',
      'asi': 'ASI',
      'svbony': 'SVBony',
      'atik': 'Atik',
      'fli': 'FLI',
      'moravian': 'Moravian',
      'touptek': 'Touptek',
      'playerone': 'Player One',
      'pegasus': 'Pegasus',
      'skywatcher': 'Sky-Watcher',
      'ioptron': 'iOptron',
    };
    return vendors[lower] ?? _capitalizeWord(vendor);
  }

  String _formatAscomVendor(String vendorPart) {
    // Insert spaces before capital letters and clean up
    // "PegasusAstroNYX101" → "Pegasus Astro NYX101"
    // "ASICamera2" → "ASI Camera 2"
    final spaced = vendorPart.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]}',
    );
    // Also handle number transitions
    final withNumbers = spaced.replaceAllMapped(
      RegExp(r'([A-Za-z])(\d)'),
      (m) => '${m[1]} ${m[2]}',
    );
    return withNumbers.replaceAll(RegExp(r'_+'), ' ').trim();
  }

  String _capitalizeWord(String word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }

  (_OverallState, int, int, _DeviceStatus?) _calculateOverallState(
    List<_DeviceStatus> devices,
  ) {
    if (devices.isEmpty) {
      return (_OverallState.disconnected, 0, 0, null);
    }

    int connected = 0;
    int connecting = 0;
    int error = 0;
    int mismatched = 0;
    _DeviceStatus? errorDevice;
    _DeviceStatus? mismatchDevice;

    for (final device in devices) {
      switch (device.state) {
        case DeviceConnectionState.connected:
          if (device.isMismatch) {
            mismatched++;
            mismatchDevice ??= device;
          } else {
            connected++;
          }
          break;
        case DeviceConnectionState.connecting:
          connecting++;
          break;
        case DeviceConnectionState.error:
          error++;
          errorDevice ??= device;
          break;
        case DeviceConnectionState.disconnected:
          break;
      }
    }

    final total = devices.length;

    if (connecting > 0) {
      return (_OverallState.connecting, connected, total, null);
    }

    // Check for mismatches - connected devices don't match profile
    if (mismatched > 0) {
      return (_OverallState.mismatch, connected, total, mismatchDevice);
    }

    if (error > 0 && connected == 0) {
      return (_OverallState.error, connected, total, errorDevice);
    }

    if (connected == total) {
      return (_OverallState.connected, connected, total, null);
    }

    if (connected > 0 || error > 0) {
      return (_OverallState.partiallyConnected, connected, total, errorDevice);
    }

    return (_OverallState.disconnected, 0, total, null);
  }
}

enum _OverallState {
  disconnected,
  connecting,
  connected,
  partiallyConnected,
  error,
  /// Devices are connected but don't match the profile's device IDs
  mismatch,
}

class _DeviceStatus {
  final String type;
  final String name;
  final IconData icon;
  final DeviceConnectionState state;
  final String? error;
  /// Whether the connected device doesn't match the profile's expected device ID
  final bool isMismatch;

  _DeviceStatus({
    required this.type,
    required this.name,
    required this.icon,
    required this.state,
    this.error,
    this.isMismatch = false,
  });
}

class _NoProfileSelected extends StatelessWidget {
  final NightshadeColors colors;

  const _NoProfileSelected({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              LucideIcons.info,
              color: colors.textMuted,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No Profile Selected',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select a profile above to view and connect your equipment',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactStatusBar extends StatelessWidget {
  final int connectedCount;
  final int totalCount;
  final _OverallState overallState;
  final List<_DeviceStatus> devices;
  final NightshadeColors colors;
  final VoidCallback onTap;
  final VoidCallback onDisconnect;

  const _CompactStatusBar({
    required this.connectedCount,
    required this.totalCount,
    required this.overallState,
    required this.devices,
    required this.colors,
    required this.onTap,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = overallState == _OverallState.connected
        ? colors.success
        : overallState == _OverallState.error
            ? colors.error
            : colors.warning;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),

              // Status text
              Text(
                overallState == _OverallState.connected
                    ? 'All Connected'
                    : '$connectedCount/$totalCount Connected',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),

              const SizedBox(width: 16),

              // Device dots
              ...devices.map((device) {
                final dotColor = device.state == DeviceConnectionState.connected
                    ? colors.success
                    : device.state == DeviceConnectionState.error
                        ? colors.error
                        : colors.textMuted.withValues(alpha: 0.5);

                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Tooltip(
                    message: '${device.type}: ${device.name}',
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                      ),
                    ),
                  ),
                );
              }),

              const Spacer(),

              // Disconnect button (only when connected)
              if (overallState == _OverallState.connected)
                TextButton(
                  onPressed: onDisconnect,
                  child: Text(
                    'Disconnect',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ),

              Icon(
                LucideIcons.chevronDown,
                size: 16,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisconnectedView extends StatelessWidget {
  final db.EquipmentProfile profile;
  final List<_DeviceStatus> devices;
  final NightshadeColors colors;
  final VoidCallback onConnect;
  final VoidCallback onEdit;

  const _DisconnectedView({
    required this.profile,
    required this.devices,
    required this.colors,
    required this.onConnect,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profile.name,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          // Device list
          ...devices.map((device) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(device.icon, size: 14, color: colors.textMuted),
                    const SizedBox(width: 12),
                    Text(
                      '${device.type}:',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        device.name,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),

          if (devices.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertTriangle,
                      size: 16, color: colors.warning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No devices assigned to this profile. Edit the profile to add devices.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: devices.isNotEmpty ? onConnect : null,
                  icon: const Icon(LucideIcons.plug, size: 16),
                  label: const Text('Connect All'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: onEdit,
                child: const Text('Edit Profile'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  side: BorderSide(color: colors.border),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectingView extends StatelessWidget {
  final db.EquipmentProfile profile;
  final List<_DeviceStatus> devices;
  final NightshadeColors colors;
  final VoidCallback onCancel;

  const _ConnectingView({
    required this.profile,
    required this.devices,
    required this.colors,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Connecting ${profile.name}...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Device progress list
          ...devices.map((device) {
            final (icon, color) = _getStateIcon(device.state, colors);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: device.state == DeviceConnectionState.connecting
                        ? CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          )
                        : Icon(icon, size: 16, color: color),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    device.type,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      device.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getStateLabel(device.state),
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          // Cancel button
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onCancel,
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _getStateIcon(DeviceConnectionState state, NightshadeColors colors) {
    switch (state) {
      case DeviceConnectionState.connected:
        return (LucideIcons.checkCircle, colors.success);
      case DeviceConnectionState.connecting:
        return (LucideIcons.loader, colors.warning);
      case DeviceConnectionState.error:
        return (LucideIcons.xCircle, colors.error);
      case DeviceConnectionState.disconnected:
        return (LucideIcons.circle, colors.textMuted);
    }
  }

  String _getStateLabel(DeviceConnectionState state) {
    switch (state) {
      case DeviceConnectionState.connected:
        return 'Connected';
      case DeviceConnectionState.connecting:
        return 'Connecting';
      case DeviceConnectionState.error:
        return 'Failed';
      case DeviceConnectionState.disconnected:
        return 'Waiting';
    }
  }
}

class _ErrorView extends StatelessWidget {
  final List<_DeviceStatus> devices;
  final _DeviceStatus? errorDevice;
  final int connectedCount;
  final int totalCount;
  final NightshadeColors colors;
  final VoidCallback onRetry;
  final VoidCallback onSkip;
  final bool isMismatch;

  const _ErrorView({
    required this.devices,
    required this.errorDevice,
    required this.connectedCount,
    required this.totalCount,
    required this.colors,
    required this.onRetry,
    required this.onSkip,
    this.isMismatch = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Error or mismatch header
          Row(
            children: [
              Icon(LucideIcons.alertTriangle, size: 18, color: colors.warning),
              const SizedBox(width: 12),
              Text(
                isMismatch
                    ? 'Profile Mismatch'
                    : '$connectedCount/$totalCount Connected',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.warning,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Text(isMismatch ? 'Reconnect' : 'Retry'),
              ),
            ],
          ),

          // Show mismatch warning
          if (isMismatch) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertTriangle, size: 16, color: colors.warning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Connected devices don\'t match the profile. Reconnect to use profile devices.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (errorDevice != null && !isMismatch) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.xCircle, size: 16, color: colors.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${errorDevice!.type} failed',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          errorDevice!.error ?? 'Device not responding',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: onRetry,
                        child: Text(
                          'Retry',
                          style: TextStyle(color: colors.primary, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: onSkip,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                              color: colors.textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
