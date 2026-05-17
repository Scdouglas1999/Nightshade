part of '../connections_tab.dart';

/// Equipment card for safety-monitor devices.
///
/// Wires the previously unconsumed `unifiedSafetyMonitorsProvider` +
/// `safetyMonitorStateProvider` so users can connect a safety monitor from
/// the Equipment screen. Safety monitors aren't stored on the equipment
/// profile today, so the save-to-profile dialog short-circuits — see
/// [DeviceCategory.safetyMonitor].
class _SafetyMonitorDeviceCard extends ConsumerStatefulWidget {
  final SafetyMonitorState safetyMonitorState;
  final NightshadeColors colors;

  const _SafetyMonitorDeviceCard({
    required this.safetyMonitorState,
    required this.colors,
  });

  @override
  ConsumerState<_SafetyMonitorDeviceCard> createState() =>
      _SafetyMonitorDeviceCardState();
}

class _SafetyMonitorDeviceCardState
    extends ConsumerState<_SafetyMonitorDeviceCard>
    with DeviceConnectionMixin {
  UnifiedDevice? _selectedDevice;
  bool _isHovered = false;

  bool get _isConnected =>
      widget.safetyMonitorState.connectionState ==
      DeviceConnectionState.connected;

  @override
  Widget build(BuildContext context) {
    final unifiedSafety = ref.watch(unifiedSafetyMonitorsProvider);

    final statusDetails = <String>[];
    if (_isConnected) {
      statusDetails.add(widget.safetyMonitorState.isSafe ? 'Safe' : 'UNSAFE');
      final lastChecked = widget.safetyMonitorState.lastChecked;
      if (lastChecked != null) {
        final delta = DateTime.now().difference(lastChecked);
        statusDetails.add('Updated ${_formatAgo(delta)}');
      }
    } else {
      statusDetails.add('Status: ---');
    }

    return _UnifiedBaseDeviceCard(
      icon: LucideIcons.shieldCheck,
      title: 'Safety Monitor',
      subtitle: _getDeviceDisplayName(widget.safetyMonitorState.deviceName,
          widget.safetyMonitorState.deviceId, 'Roof / safety sensor'),
      isConnected: _isConnected,
      isConnecting: isConnecting ||
          widget.safetyMonitorState.connectionState ==
              DeviceConnectionState.connecting,
      statusLabel: !_isConnected
          ? 'Idle'
          : (widget.safetyMonitorState.isSafe ? 'Safe' : 'UNSAFE'),
      statusDetails: statusDetails,
      accentColor: widget.safetyMonitorState.isSafe && _isConnected
          ? widget.colors.success
          : widget.colors.error,
      colors: widget.colors,
      isOptional: true,
      isHovered: _isHovered,
      onHoverChanged: (hovered) => setState(() => _isHovered = hovered),
      unifiedDevices: unifiedSafety,
      selectedDevice: _selectedDevice,
      onDeviceSelected: (device) => setState(() => _selectedDevice = device),
      onBackendSelected: _handleBackendSelected,
      onConnect: _handleConnect,
      onDisconnect: _handleDisconnect,
    );
  }

  static String _formatAgo(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }

  void _handleBackendSelected(DriverType backend) {
    if (_selectedDevice == null) return;
    setState(() {
      _selectedDevice = _selectedDevice!.withSelectedBackend(backend);
    });
  }

  Future<void> _handleConnect() async {
    if (_selectedDevice == null) return;
    final deviceId = _selectedDevice!.activeDeviceId;
    final deviceName = _selectedDevice!.displayName;

    await connectDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      connectFn: ref.read(safetyMonitorStateProvider.notifier).connect,
      onConnected: () async {
        // Why: safety monitor isn't part of the profile schema; this call
        // is short-circuited by DeviceCategory.safetyMonitor handling in
        // showSaveToProfileDialog. Kept invoked so a future schema migration
        // doesn't require touching every card.
        await showSaveToProfileDialog(
          context: context,
          ref: ref,
          deviceId: deviceId,
          deviceName: deviceName,
          deviceType: DeviceCategory.safetyMonitor,
        );
      },
    );
  }

  Future<void> _handleDisconnect() => disconnectDevice(
        disconnectFn: () async =>
            ref.read(safetyMonitorStateProvider.notifier).disconnect(),
        deviceType: 'safety monitor',
      );
}
