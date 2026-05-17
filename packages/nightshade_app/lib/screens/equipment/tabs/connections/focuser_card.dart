part of '../connections_tab.dart';

class _FocuserDeviceCard extends ConsumerStatefulWidget {
  final FocuserState focuserState;
  final NightshadeColors colors;

  const _FocuserDeviceCard({
    required this.focuserState,
    required this.colors,
  });

  @override
  ConsumerState<_FocuserDeviceCard> createState() => _FocuserDeviceCardState();
}

class _FocuserDeviceCardState extends ConsumerState<_FocuserDeviceCard>
    with DeviceConnectionMixin {
  UnifiedDevice? _selectedDevice;
  bool _isHovered = false;

  bool get _isConnected =>
      widget.focuserState.connectionState == DeviceConnectionState.connected;

  @override
  Widget build(BuildContext context) {
    // Use unified focusers (grouped by physical device)
    final unifiedFocusers = ref.watch(unifiedFocusersProvider);

    final statusDetails = <String>[];
    if (_isConnected && widget.focuserState.position != null) {
      statusDetails.add('Position: ${widget.focuserState.position}');
    } else {
      statusDetails.add('Position: ---');
    }

    // Why: surfaces focuserCapabilitiesProvider as a one-line summary on the
    // connected card so the user sees range / temp-comp / reversal support
    // without diving into a settings dialog. Silently skipped when not
    // connected, capabilities not yet loaded, or backend returns null.
    if (_isConnected && widget.focuserState.deviceId != null) {
      final capsAsync = ref
          .watch(focuserCapabilitiesProvider(widget.focuserState.deviceId!));
      final caps = capsAsync.valueOrNull;
      if (caps != null) {
        final badges = <String>[];
        if (caps.maxPosition > 0) {
          badges.add('0–${caps.maxPosition} steps');
        }
        if (caps.absolute) badges.add('absolute');
        if (caps.tempCompAvailable) badges.add('temp comp');
        if (caps.canReverse) badges.add('reversible');
        if (badges.isNotEmpty) {
          statusDetails.add(badges.join(' · '));
        }
      }
    }

    return _UnifiedBaseDeviceCard(
      icon: LucideIcons.focus,
      title: 'Focuser',
      subtitle: _getDeviceDisplayName(widget.focuserState.deviceName,
          widget.focuserState.deviceId, 'Motor focuser'),
      isConnected: _isConnected,
      isConnecting: isConnecting ||
          widget.focuserState.connectionState ==
              DeviceConnectionState.connecting,
      statusLabel: _isConnected ? 'Ready' : 'Idle',
      statusDetails: statusDetails,
      accentColor: widget.colors.success,
      colors: widget.colors,
      isOptional: true,
      isHovered: _isHovered,
      onHoverChanged: (hovered) => setState(() => _isHovered = hovered),
      unifiedDevices: unifiedFocusers,
      selectedDevice: _selectedDevice,
      onDeviceSelected: (device) => setState(() => _selectedDevice = device),
      onBackendSelected: _handleBackendSelected,
      onConnect: _handleConnect,
      onDisconnect: _handleDisconnect,
    );
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
      connectFn: ref.read(deviceServiceProvider).connectFocuser,
      onConnected: () async {
        await showSaveToProfileDialog(
          context: context,
          ref: ref,
          deviceId: deviceId,
          deviceName: deviceName,
          deviceType: DeviceCategory.focuser,
        );
      },
    );
  }

  Future<void> _handleDisconnect() => disconnectDevice(
        disconnectFn: ref.read(deviceServiceProvider).disconnectFocuser,
        deviceType: 'focuser',
      );
}
