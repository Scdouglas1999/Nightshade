part of '../connections_tab.dart';

/// Dropdown for selecting unified devices (grouped by physical device)
/// Shows device name with backend count, not individual backend entries
class _UnifiedDeviceDropdown extends StatelessWidget {
  final List<UnifiedDevice> devices;
  final UnifiedDevice? selectedDevice;
  final ValueChanged<UnifiedDevice?> onSelected;
  final bool isEnabled;
  final NightshadeColors colors;

  const _UnifiedDeviceDropdown({
    required this.devices,
    required this.selectedDevice,
    required this.onSelected,
    required this.isEnabled,
    required this.colors,
  });

  Color _getBackendColor(DriverType backend) {
    switch (backend) {
      case DriverType.native:
        return colors.success;
      case DriverType.ascom:
        return colors.info;
      case DriverType.alpaca:
        return colors.warning;
      case DriverType.indi:
        return const Color(0xFF9333EA);
      case DriverType.simulator:
        return colors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<UnifiedDevice>(
      enabled: isEnabled,
      onSelected: onSelected,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: colors.surface,
      itemBuilder: (context) => devices.map((device) {
        final backendCount = device.availableBackends.length;
        final recommended = device.recommendedBackend;

        return PopupMenuItem<UnifiedDevice>(
          value: device,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Show available backends as small colored dots/badges
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        ...device.sortedBackends.map((backend) {
                          final isRecommended = backend == recommended;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: _getBackendColor(backend)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _getBackendColor(backend)
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isRecommended) ...[
                                  Icon(
                                    Icons.star,
                                    size: 8,
                                    color: colors.warning,
                                  ),
                                  const SizedBox(width: 2),
                                ],
                                Text(
                                  backend.shortLabel,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: isRecommended
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: _getBackendColor(backend),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
              if (backendCount > 1)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$backendCount drivers',
                    style: TextStyle(
                      fontSize: 9,
                      color: colors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isEnabled ? colors.surfaceAlt : colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedDevice?.displayName ?? 'Select device...',
                style: TextStyle(
                  fontSize: 12,
                  color: selectedDevice != null
                      ? colors.textPrimary
                      : colors.textMuted,
                ),
              ),
            ),
            if (selectedDevice != null &&
                selectedDevice!.availableBackends.length > 1) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: _getBackendColor(selectedDevice!.activeBackend)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  selectedDevice!.activeBackend.shortLabel,
                  style: TextStyle(
                    fontSize: 9,
                    color: _getBackendColor(selectedDevice!.activeBackend),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              LucideIcons.chevronDown,
              size: 14,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Base device card that uses UnifiedDevice (grouped by physical device)
/// Shows device dropdown, backend selector chips, and connect button
class _UnifiedBaseDeviceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isConnected;
  final bool isConnecting;
  final String statusLabel;
  final List<String> statusDetails;
  final bool isOptional;
  final Color accentColor;
  final NightshadeColors colors;
  final bool isHovered;
  final ValueChanged<bool> onHoverChanged;
  final List<UnifiedDevice> unifiedDevices;
  final UnifiedDevice? selectedDevice;
  final ValueChanged<UnifiedDevice?> onDeviceSelected;
  final ValueChanged<DriverType> onBackendSelected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _UnifiedBaseDeviceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isConnected,
    required this.isConnecting,
    required this.statusLabel,
    required this.statusDetails,
    this.isOptional = false,
    required this.accentColor,
    required this.colors,
    required this.isHovered,
    required this.onHoverChanged,
    required this.unifiedDevices,
    required this.selectedDevice,
    required this.onDeviceSelected,
    required this.onBackendSelected,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isHovered ? accentColor.withValues(alpha: 0.5) : colors.border,
            width: isHovered ? 1.5 : 1,
          ),
          boxShadow: isHovered
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                // Icon container
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accentColor.withValues(alpha: 0.2),
                        accentColor.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: isConnected ? colors.success : accentColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isOptional) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceAlt,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Optional',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Connection indicator
                _ConnectionIndicator(
                  isConnected: isConnected,
                  isConnecting: isConnecting,
                  colors: colors,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Device selector (unified - shows grouped devices)
            _UnifiedDeviceDropdown(
              devices: unifiedDevices,
              selectedDevice: selectedDevice,
              onSelected: onDeviceSelected,
              isEnabled: !isConnected && !isConnecting,
              colors: colors,
            ),

            // Backend selector (only show if selected device has multiple backends)
            if (selectedDevice != null &&
                selectedDevice!.availableBackends.length > 1) ...[
              const SizedBox(height: 10),
              BackendSelectorChips(
                availableBackends: selectedDevice!.sortedBackends,
                selectedBackend: selectedDevice!.activeBackend,
                recommendedBackend: selectedDevice!.recommendedBackend,
                onBackendSelected: onBackendSelected,
                isEnabled: !isConnected && !isConnecting,
                currentPlatform: Platform.operatingSystem,
              ),
            ],

            const SizedBox(height: 12),

            // Status details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text(
                    'Status:',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color:
                            isConnected ? colors.success : colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (statusDetails.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        statusDetails.join(' • '),
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Connect button
            SizedBox(
              width: double.infinity,
              child: _ConnectButton(
                isConnected: isConnected,
                isConnecting: isConnecting,
                isEnabled: selectedDevice != null || isConnected,
                accentColor: accentColor,
                colors: colors,
                onPressed: isConnected ? onDisconnect : onConnect,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionIndicator extends StatelessWidget {
  final bool isConnected;
  final bool isConnecting;
  final NightshadeColors colors;

  const _ConnectionIndicator({
    required this.isConnected,
    required this.isConnecting,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isConnected
            ? colors.success.withValues(alpha: 0.15)
            : isConnecting
                ? colors.warning.withValues(alpha: 0.15)
                : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isConnected
              ? colors.success.withValues(alpha: 0.3)
              : isConnecting
                  ? colors.warning.withValues(alpha: 0.3)
                  : colors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isConnecting)
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colors.warning,
              ),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? colors.success : colors.textMuted,
              ),
            ),
          const SizedBox(width: 6),
          Text(
            isConnecting
                ? 'Connecting...'
                : isConnected
                    ? 'Connected'
                    : 'Offline',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isConnected
                  ? colors.success
                  : isConnecting
                      ? colors.warning
                      : colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectButton extends StatefulWidget {
  final bool isConnected;
  final bool isConnecting;
  final bool isEnabled;
  final Color accentColor;
  final NightshadeColors colors;
  final VoidCallback onPressed;

  const _ConnectButton({
    required this.isConnected,
    required this.isConnecting,
    required this.isEnabled,
    required this.accentColor,
    required this.colors,
    required this.onPressed,
  });

  @override
  State<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<_ConnectButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final canPress = widget.isEnabled && !widget.isConnecting;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: canPress ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: widget.isConnected || !canPress
                ? null
                : LinearGradient(
                    colors: [
                      widget.accentColor,
                      widget.accentColor.withValues(alpha: 0.8),
                    ],
                  ),
            color: widget.isConnected
                ? widget.colors.surfaceAlt
                : !canPress
                    ? widget.colors.surfaceAlt.withValues(alpha: 0.5)
                    : null,
            borderRadius: BorderRadius.circular(10),
            border: widget.isConnected
                ? Border.all(color: widget.colors.border)
                : null,
            boxShadow: !widget.isConnected && canPress && _isHovered
                ? [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: widget.isConnecting
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: onPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Connecting...',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: onPrimary,
                        ),
                      ),
                    ],
                  )
                : Text(
                    widget.isConnected ? 'Disconnect' : 'Connect',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.isConnected
                          ? widget.colors.textSecondary
                          : canPress
                              ? onPrimary
                              : widget.colors.textMuted,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
