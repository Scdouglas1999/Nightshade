part of '../connections_tab.dart';

class _DeviceDiscoveryCard extends ConsumerWidget {
  final bool isScanning;
  final VoidCallback onScan;
  final VoidCallback onAddAlpacaServer;
  final VoidCallback onAddIndiServer;
  final NightshadeColors colors;

  const _DeviceDiscoveryCard({
    required this.isScanning,
    required this.onScan,
    required this.onAddAlpacaServer,
    required this.onAddIndiServer,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch discovery state for progress info
    final discoveryState = ref.watch(unifiedDiscoveryProvider);
    final isDiscovering = discoveryState.isDiscovering || isScanning;
    final discoveredDevices = discoveryState.groupedDevices.length;
    final hasTriedDiscovery = discoveredDevices > 0 ||
        discoveryState.backendStates.values.any(
          (state) => state.status != DiscoveryStatus.idle,
        );
    final scanLabel = !hasTriedDiscovery
        ? 'Scan for devices'
        : isDiscovering
            ? 'Scanning...'
            : 'Scan again';
    final summary =
        switch ((isDiscovering, discoveredDevices, hasTriedDiscovery)) {
      (true, _, _) => (
          icon: LucideIcons.loader2,
          color: colors.info,
          title: 'Looking for connected gear',
          body:
              'Nightshade is checking this device and any configured remote sources for cameras, mounts, and accessories.',
        ),
      (false, > 0, _) => (
          icon: LucideIcons.checkCircle2,
          color: colors.success,
          title: discoveredDevices == 1
              ? '1 device is ready to connect'
              : '$discoveredDevices devices are ready to connect',
          body:
              'Pick a device card below to connect your camera, mount, or accessories.',
        ),
      (false, 0, true) => (
          icon: LucideIcons.alertCircle,
          color: colors.warning,
          title: 'No devices found yet',
          body:
              'Check power and cables, then scan again. Use Add Remote Server only if your gear is exposed from another computer.',
        ),
      _ => (
          icon: LucideIcons.info,
          color: colors.primary,
          title: 'Start here',
          body:
              'Turn on your gear, connect it to this computer, then scan for devices. Add a remote server only when your equipment lives on another machine.',
        ),
    };

    // Build backend status indicators
    final backendStatusWidgets = <Widget>[];
    for (final backend in [
      DriverType.native,
      DriverType.ascom,
      DriverType.alpaca,
      DriverType.indi
    ]) {
      if (backend == DriverType.ascom && !Platform.isWindows) {
        continue; // Skip ASCOM on non-Windows
      }
      final state = discoveryState.backendStates[backend];
      final status = state?.status ?? DiscoveryStatus.idle;
      final deviceCount = state?.devices.length ?? 0;

      Color statusColor;
      IconData statusIcon;
      switch (status) {
        case DiscoveryStatus.idle:
          statusColor = colors.textMuted;
          statusIcon = LucideIcons.circle;
          break;
        case DiscoveryStatus.discovering:
          statusColor = colors.info;
          statusIcon = LucideIcons.loader2;
          break;
        case DiscoveryStatus.completed:
          statusColor = deviceCount > 0 ? colors.success : colors.textMuted;
          statusIcon =
              deviceCount > 0 ? LucideIcons.checkCircle : LucideIcons.circle;
          break;
        case DiscoveryStatus.error:
          statusColor = colors.error;
          statusIcon = LucideIcons.alertCircle;
          break;
      }

      backendStatusWidgets.add(
        Tooltip(
          message:
              state?.error ?? '${backend.displayName}: $deviceCount device(s)',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 12, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  backend.shortLabel,
                  style: TextStyle(
                      fontSize: 10,
                      color: statusColor,
                      fontWeight: FontWeight.w500),
                ),
                if (status == DiscoveryStatus.completed && deviceCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '($deviceCount)',
                    style: TextStyle(fontSize: 10, color: statusColor),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.radar, color: colors.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect your gear',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scan this device first. Add a remote server only if your equipment is shared from another computer.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.info, color: colors.primary, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Recommended order: 1) power on the gear, 2) scan for devices on this computer, 3) connect the essentials first, 4) add a remote server only if the gear is hosted elsewhere.',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: summary.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: summary.color.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(summary.icon, size: 16, color: summary.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        summary.body,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Action buttons
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 220,
                child: NightshadeButton(
                  onPressed: isDiscovering ? null : onScan,
                  icon: LucideIcons.search,
                  label: scanLabel,
                  variant: ButtonVariant.primary,
                  isLoading: isDiscovering,
                ),
              ),
              // Add Server dropdown for INDI/Alpaca
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'indi') {
                    onAddIndiServer();
                  } else if (value == 'alpaca') {
                    onAddAlpacaServer();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'indi',
                    child: Row(
                      children: [
                        Icon(LucideIcons.server,
                            size: 16, color: colors.textSecondary),
                        const SizedBox(width: 8),
                        const Text('INDI server'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'alpaca',
                    child: Row(
                      children: [
                        Icon(LucideIcons.globe,
                            size: 16, color: colors.textSecondary),
                        const SizedBox(width: 8),
                        const Text('Alpaca server'),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.plus,
                        size: 16,
                        color: colors.textPrimary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Add Remote Server',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              leading: Icon(
                LucideIcons.chevronsUpDown,
                size: 16,
                color: colors.textMuted,
              ),
              title: Text(
                'Driver sources and remote servers',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                'Open this when you need to troubleshoot discovery or connect to gear exposed through INDI or Alpaca.',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textMuted,
                ),
              ),
              children: [
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: backendStatusWidgets,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    'Use a remote server only when the camera or mount is hosted on another computer. For local USB devices, scanning this computer is the fastest path.',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final NightshadeColors colors;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}
