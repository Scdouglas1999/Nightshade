import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../services/network_service.dart';

/// Network status indicator widget
/// Shows connection status with color-coded indicator and tap-to-details
class NetworkStatusIndicator extends StatelessWidget {
  final bool compact;

  const NetworkStatusIndicator({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<NetworkServiceState>(
      stream: NetworkService().stateStream,
      initialData: NetworkService().currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? NetworkService().currentState;

        return GestureDetector(
          onTap: () => _showConnectionDetails(context, state),
          child: compact
              ? _buildCompactIndicator(context, state)
              : _buildFullIndicator(context, state),
        );
      },
    );
  }

  /// Build compact indicator (just icon and color)
  Widget _buildCompactIndicator(
    BuildContext context,
    NetworkServiceState state,
  ) {
    final (color, icon) = _getStatusColorAndIcon(context, state);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        size: 20,
        color: color,
      ),
    );
  }

  /// Build full indicator (icon, text, server name)
  Widget _buildFullIndicator(BuildContext context, NetworkServiceState state) {
    final (color, icon) = _getStatusColorAndIcon(context, state);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _getStatusText(state),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (state.connectedServer != null)
                Text(
                  state.connectedServer!.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
          Icon(LucideIcons.chevronRight,
              size: 16, color: color.withValues(alpha: 0.5)),
        ],
      ),
    );
  }

  Color _getStatusColor(BuildContext context, NetworkStatus status) {
    final theme = Theme.of(context);
    final colors = theme.extension<NightshadeColors>();
    switch (status) {
      case NetworkStatus.connected:
        return colors?.success ?? theme.colorScheme.primary;
      case NetworkStatus.reconnecting:
        return colors?.warning ?? theme.colorScheme.secondary;
      case NetworkStatus.disconnected:
        return colors?.error ?? theme.colorScheme.error;
    }
  }

  /// Get status color and icon based on connection state
  (Color, IconData) _getStatusColorAndIcon(
    BuildContext context,
    NetworkServiceState state,
  ) {
    final color = _getStatusColor(context, state.status);
    final themeColors = Theme.of(context).extension<NightshadeColors>();
    switch (state.status) {
      case NetworkStatus.connected:
        return (color, LucideIcons.wifi);
      case NetworkStatus.reconnecting:
        return (color, LucideIcons.refreshCw);
      case NetworkStatus.disconnected:
        if (state.hasConnection) {
          return (color, LucideIcons.wifiOff);
        }
        return (
          themeColors?.textMuted ??
              Theme.of(context).colorScheme.onSurfaceVariant,
          LucideIcons.wifiOff,
        );
    }
  }

  /// Get status text
  String _getStatusText(NetworkServiceState state) {
    switch (state.status) {
      case NetworkStatus.connected:
        return 'Connected';
      case NetworkStatus.reconnecting:
        return 'Reconnecting...';
      case NetworkStatus.disconnected:
        if (state.hasConnection) {
          return 'Disconnected';
        }
        return 'No Network';
    }
  }

  /// Show connection details dialog
  void _showConnectionDetails(BuildContext context, NetworkServiceState state) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _ConnectionDetailsSheet(state: state),
    );
  }
}

/// Connection details bottom sheet
class _ConnectionDetailsSheet extends StatelessWidget {
  final NetworkServiceState state;

  const _ConnectionDetailsSheet({
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                _getStatusIcon(state.status),
                size: 32,
                color: _getStatusColor(context, state.status),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connection Status',
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(
                      _getStatusDescription(state),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Connection Details
          if (state.connectedServer != null) ...[
            _DetailRow(
              label: 'Server',
              value: state.connectedServer!.name,
            ),
            _DetailRow(
              label: 'Host',
              value: state.connectedServer!.host,
            ),
            _DetailRow(
              label: 'Port',
              value: state.connectedServer!.webPort.toString(),
            ),
            _DetailRow(
              label: 'Version',
              value: state.connectedServer!.version,
            ),
          ],

          // Network Details
          _DetailRow(
            label: 'Network Type',
            value: _getNetworkType(state.connectivityResults),
          ),

          if (state.statusMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.info,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.statusMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Actions
          if (state.status == NetworkStatus.disconnected && state.hasConnection)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  NetworkService().rediscoverServer();
                },
                icon: const Icon(LucideIcons.search),
                label: const Text('Search for Servers'),
              ),
            ),

          if (state.status == NetworkStatus.connected)
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                onPressed: () {
                  Navigator.pop(context);
                  NetworkService().disconnect();
                },
                icon: LucideIcons.logOut,
                label: 'Disconnect',
                variant: ButtonVariant.destructive,
              ),
            ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(NetworkStatus status) {
    switch (status) {
      case NetworkStatus.connected:
        return LucideIcons.checkCircle;
      case NetworkStatus.reconnecting:
        return LucideIcons.loader;
      case NetworkStatus.disconnected:
        return LucideIcons.xCircle;
    }
  }

  Color _getStatusColor(BuildContext context, NetworkStatus status) {
    final theme = Theme.of(context);
    final colors = theme.extension<NightshadeColors>();
    switch (status) {
      case NetworkStatus.connected:
        return colors?.success ?? theme.colorScheme.primary;
      case NetworkStatus.reconnecting:
        return colors?.warning ?? theme.colorScheme.secondary;
      case NetworkStatus.disconnected:
        return colors?.error ?? theme.colorScheme.error;
    }
  }

  String _getStatusDescription(NetworkServiceState state) {
    switch (state.status) {
      case NetworkStatus.connected:
        return 'Connected to ${state.connectedServer?.name ?? "server"}';
      case NetworkStatus.reconnecting:
        return 'Attempting to reconnect...';
      case NetworkStatus.disconnected:
        if (state.hasConnection) {
          return 'Not connected to any server';
        }
        return 'No network connection available';
    }
  }

  String _getNetworkType(List<dynamic> results) {
    if (results.isEmpty) return 'None';

    final types = <String>[];
    for (final result in results) {
      final name = result.toString().split('.').last;
      if (name != 'none') {
        types.add(name[0].toUpperCase() + name.substring(1));
      }
    }

    return types.isEmpty ? 'None' : types.join(', ');
  }
}

/// Detail row widget
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
