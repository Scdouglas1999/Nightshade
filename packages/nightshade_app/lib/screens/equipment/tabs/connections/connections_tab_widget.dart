part of '../connections_tab.dart';

class ConnectionsTab extends ConsumerStatefulWidget {
  const ConnectionsTab({super.key});

  @override
  ConsumerState<ConnectionsTab> createState() => _ConnectionsTabState();
}

class _ConnectionsTabState extends ConsumerState<ConnectionsTab> {
  bool _isScanning = false;

  Future<void> _scanForDevices() async {
    setState(() => _isScanning = true);

    try {
      // Use unified discovery - discovers from ALL backends in parallel
      // The unifiedDiscoveryProvider already caches results in rawDevices/groupedDevices
      await ref.read(unifiedDiscoveryProvider.notifier).discoverAll();
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  // ignore: unused_element
  void _showDebugInfo() {
    // Use unified discovery state (doesn't trigger new discovery)
    final discoveryState = ref.read(unifiedDiscoveryProvider);
    final rawDevices = discoveryState.rawDevices;
    final groupedDevices = discoveryState.groupedDevices;

    // Count by type from raw devices
    final cameras =
        rawDevices.where((d) => d.deviceType == DeviceType.camera).toList();
    final mounts =
        rawDevices.where((d) => d.deviceType == DeviceType.mount).toList();
    final focusers =
        rawDevices.where((d) => d.deviceType == DeviceType.focuser).toList();
    final wheels = rawDevices
        .where((d) => d.deviceType == DeviceType.filterWheel)
        .toList();
    final guiders =
        rawDevices.where((d) => d.deviceType == DeviceType.guider).toList();
    final rotators =
        rawDevices.where((d) => d.deviceType == DeviceType.rotator).toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Debug: Discovered Devices'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('=== Raw Devices (${rawDevices.length} total) ===',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Cameras: ${cameras.length}'),
              ...cameras.map((d) => Text('• ${d.name} (${d.driverType.name})')),
              const SizedBox(height: 8),
              Text('Mounts: ${mounts.length}'),
              ...mounts.map((d) => Text('• ${d.name} (${d.driverType.name})')),
              const SizedBox(height: 8),
              Text('Focusers: ${focusers.length}'),
              ...focusers
                  .map((d) => Text('• ${d.name} (${d.driverType.name})')),
              const SizedBox(height: 8),
              Text('Filter Wheels: ${wheels.length}'),
              ...wheels.map((d) => Text('• ${d.name} (${d.driverType.name})')),
              const SizedBox(height: 8),
              Text('Guiders: ${guiders.length}'),
              ...guiders.map((d) => Text('• ${d.name} (${d.driverType.name})')),
              const SizedBox(height: 8),
              Text('Rotators: ${rotators.length}'),
              ...rotators
                  .map((d) => Text('• ${d.name} (${d.driverType.name})')),
              const SizedBox(height: 16),
              Text(
                  '=== Unified Devices (${groupedDevices.length} physical) ===',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...groupedDevices.map((u) {
                final backends = u.availableBackends.keys
                    .map((b) => b.shortLabel)
                    .join(', ');
                return Text('• ${u.displayName} [$backends]');
              }),
            ],
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Close',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }

  void _showAddAlpacaServerDialog() {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final hostController = TextEditingController(text: 'localhost');
    final portController = TextEditingController(text: '11111');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Add Alpaca Server',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter the address of your Alpaca server.\n'
                    'If you have ASCOM drivers, install "ASCOM Remote" to expose them via Alpaca.',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: hostController,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Host',
                      labelStyle: TextStyle(color: colors.textMuted),
                      hintText: 'localhost or IP address',
                      hintStyle: TextStyle(
                          color: colors.textMuted.withValues(alpha: 0.5)),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: portController,
                    style: TextStyle(color: colors.textPrimary),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Port',
                      labelStyle: TextStyle(color: colors.textMuted),
                      hintText: '11111',
                      hintStyle: TextStyle(
                          color: colors.textMuted.withValues(alpha: 0.5)),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () async {
              Navigator.pop(context);
              final host = hostController.text.trim();
              final port = int.tryParse(portController.text) ?? 11111;
              await _connectToAlpacaServer(host, port);
            },
            label: 'Connect',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }

  Future<void> _connectToAlpacaServer(String host, int port) async {
    // Show loading indicator
    context.showInfoSnackBar('Connecting to Alpaca server at $host:$port...');

    try {
      // Import and use the Alpaca client directly
      final devices = await _discoverAlpacaAtAddress(host, port);

      if (devices.isEmpty) {
        if (mounted) {
          context.showErrorSnackBar(
              'No devices found at $host:$port. Make sure ASCOM Remote is running.');
        }
      } else {
        // Re-discover all devices to include the new Alpaca devices
        // This uses the unified discovery which discovers from ALL backends
        await ref.read(unifiedDiscoveryProvider.notifier).discoverAll();

        if (mounted) {
          context.showSuccessSnackBar(
              'Found ${devices.length} device(s) at $host:$port');
        }
      }
    } catch (_) {
      if (mounted) {
        context.showErrorSnackBar(
          'Could not connect to that Alpaca server.',
        );
      }
    }
  }

  Future<List<DeviceInfo>> _discoverAlpacaAtAddress(
      String host, int port) async {
    final deviceService = ref.read(deviceServiceProvider);
    return deviceService.discoverAlpacaAtAddress(host, port);
  }

  Future<void> _connectToIndiServer(String host, int port) async {
    final deviceService = ref.read(deviceServiceProvider);

    // Show loading indicator
    context.showInfoSnackBar('Connecting to INDI server at $host:$port...');

    try {
      // Use the device service to discover INDI devices
      final devices = await deviceService.discoverIndiAtAddress(host, port);

      if (devices.isEmpty) {
        if (mounted) {
          context.showWarningSnackBar('No devices found at $host:$port.');
        }
      } else {
        // Re-discover all devices to include the new INDI devices
        // This uses the unified discovery which discovers from ALL backends
        await ref.read(unifiedDiscoveryProvider.notifier).discoverAll();

        if (mounted) {
          context.showSuccessSnackBar(
              'Found ${devices.length} device(s) at $host:$port');
        }
      }
    } catch (_) {
      if (mounted) {
        context.showErrorSnackBar(
          'Could not connect to that INDI server.',
        );
      }
    }
  }

  void _showIndiServerDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const IndiServerDialog(),
    );

    if (result != null) {
      final host = result['host'] as String;
      final port = result['port'] as int;

      // Connect to the INDI server
      await _connectToIndiServer(host, port);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Watch device states
    final cameraState = ref.watch(cameraStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final focuserState = ref.watch(focuserStateProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final rotatorState = ref.watch(rotatorStateProvider);

    // Device cards now use unified providers internally (unifiedCamerasProvider, etc.)
    // Each card fetches its own grouped devices and shows inline backend selector chips

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Discovery Section
          _DeviceDiscoveryCard(
            isScanning: _isScanning,
            onScan: _scanForDevices,
            onAddAlpacaServer: _showAddAlpacaServerDialog,
            onAddIndiServer: _showIndiServerDialog,
            colors: colors,
          ),
          const SizedBox(height: 24),

          // Essential Equipment Section
          _SectionHeader(
            title: 'Start with the essentials',
            subtitle: 'Connect a camera and mount to begin imaging.',
            colors: colors,
          ),
          const SizedBox(height: 16),

          // Camera and Mount - responsive grid
          ResponsiveCardGrid(
            minCardWidth: 350,
            children: [
              _CameraDeviceCard(
                cameraState: cameraState,
                colors: colors,
              ),
              _MountDeviceCard(
                mountState: mountState,
                colors: colors,
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Optional Equipment Section
          _SectionHeader(
            title: 'Optional gear',
            subtitle:
                'Add guiding, focus, filters, or rotation when available.',
            colors: colors,
          ),
          const SizedBox(height: 16),

          // Optional equipment - responsive grid
          ResponsiveCardGrid(
            minCardWidth: 300,
            children: [
              _GuiderDeviceCard(
                guiderState: guiderState,
                colors: colors,
              ),
              _FocuserDeviceCard(
                focuserState: focuserState,
                colors: colors,
              ),
              _FilterWheelDeviceCard(
                filterWheelState: filterWheelState,
                colors: colors,
              ),
              _RotatorDeviceCard(
                rotatorState: rotatorState,
                colors: colors,
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Telescope Configuration Section
          _SectionHeader(
            title: 'Telescope profile',
            subtitle: 'Review focal length, aperture, and optical setup.',
            colors: colors,
          ),
          const SizedBox(height: 16),

          _TelescopeCard(colors: colors),
        ],
      ),
    );
  }
}
