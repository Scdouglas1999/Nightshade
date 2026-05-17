import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_widgets.dart';

class ConnectionSettings extends ConsumerWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const ConnectionSettings(
      {super.key, required this.colors, this.isMobile = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendProvider);
    final isConnected = backend is NetworkBackend;
    final isDisconnected = backend is DisconnectedBackend;
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final settingsNotifier = ref.read(appSettingsProvider.notifier);
    final platformCapabilities =
        PlatformCapabilityMatrix.forPlatform(Platform.operatingSystem);

    // Extract server info from NetworkBackend if connected
    String serverAddress = 'Not connected';
    String connectionStatus = 'Disconnected';
    Color statusColor = colors.textMuted;

    if (isConnected) {
      serverAddress = '${backend.serverHost}:${backend.serverPort}';
      connectionStatus = 'Connected';
      statusColor = colors.success;
    } else if (!isDisconnected) {
      // FfiBackend (local mode)
      serverAddress = 'Local';
      connectionStatus = 'Local Mode';
      statusColor = colors.primary;
    }

    return SettingsPage(
      key: SettingsTutorialKeys.connection,
      title: 'Connection',
      description: 'Server connection settings',
      colors: colors,
      isMobile: isMobile,
      hideHeader: isMobile,
      children: [
        SettingsSection(
          title: 'Server Status',
          colors: colors,
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.server,
              title: 'Connection Status',
              subtitle: serverAddress,
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  connectionStatus,
                  style: TextStyle(
                    fontSize: isMobile ? 10 : 11,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              colors: colors,
              isMobile: isMobile,
            ),
            if (isConnected)
              SettingRow(
                icon: LucideIcons.globe,
                title: 'Server Address',
                subtitle: 'Current host and port for this Nightshade server',
                trailing: SelectableText(
                  serverAddress,
                  style: TextStyle(
                    fontSize: isMobile ? 11 : 12,
                    color: colors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
                colors: colors,
                isMobile: isMobile,
              ),
            SettingRow(
              icon: isConnected ? LucideIcons.logOut : LucideIcons.logIn,
              title: isConnected ? 'Disconnect' : 'Connect to Server',
              subtitle: isConnected
                  ? 'Return to connection screen to connect to a different server'
                  : 'Open connection screen to connect to a server',
              trailing: NightshadeButton(
                label: isConnected ? 'Disconnect' : 'Connect',
                variant: isConnected
                    ? ButtonVariant.destructive
                    : ButtonVariant.primary,
                size: isMobile ? ButtonSize.small : ButtonSize.small,
                onPressed: () =>
                    _handleConnectionAction(context, ref, isConnected),
              ),
              isLast: true,
              colors: colors,
              isMobile: isMobile,
            ),
          ],
        ),
        if (settings != null)
          SettingsSection(
            title: 'Discovery',
            colors: colors,
            isMobile: isMobile,
            children: [
              SettingRow(
                icon: LucideIcons.radio,
                title: 'INDI auto-connect',
                subtitle:
                    'Automatically connect to the configured INDI server when available',
                trailing: SettingsSwitch(
                  value: settings.indiAutoConnect,
                  onChanged: settingsNotifier.setIndiAutoConnect,
                  colors: colors,
                ),
                colors: colors,
                isMobile: isMobile,
              ),
              SettingRow(
                icon: LucideIcons.search,
                title: 'Alpaca auto-discovery',
                subtitle:
                    'Scan the local network for Alpaca devices and servers',
                trailing: SettingsSwitch(
                  value: settings.alpacaAutoDiscover,
                  onChanged: settingsNotifier.setAlpacaAutoDiscover,
                  colors: colors,
                ),
                isLast: true,
                colors: colors,
                isMobile: isMobile,
              ),
            ],
          ),
        if (isConnected)
          SettingsSection(
            title: 'Remote Features',
            colors: colors,
            isMobile: isMobile,
            children: [
              SettingRow(
                icon: LucideIcons.refreshCw,
                title: 'Refresh Host Settings',
                subtitle:
                    'Reload this screen from the connected Nightshade host',
                trailing: IconButton(
                  icon: Icon(LucideIcons.downloadCloud,
                      color: colors.primary, size: isMobile ? 20 : 18),
                  onPressed: () async {
                    try {
                      ref.invalidate(appSettingsProvider);
                      if (context.mounted) {
                        context.showSuccessSnackBar('Host settings refreshed');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        context.showErrorSnackBar('Refresh failed: $e');
                      }
                    }
                  },
                ),
                isLast: true,
                colors: colors,
                isMobile: isMobile,
              ),
            ],
          ),
        SettingsSection(
          title: 'Platform Capabilities',
          colors: colors,
          isMobile: isMobile,
          children: [
            _PlatformCapabilityMatrixView(
              report: platformCapabilities,
              colors: colors,
              isMobile: isMobile,
            ),
          ],
        ),
      ],
    );
  }

  void _handleConnectionAction(
      BuildContext context, WidgetRef ref, bool isConnected) {
    if (isConnected) {
      // Show confirmation dialog before disconnecting
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Disconnect from Server?'),
          content: const Text(
            'You will return to the connection screen where you can connect to a different server.',
          ),
          actions: [
            NightshadeButton(
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
              onPressed: () => Navigator.pop(ctx),
            ),
            NightshadeButton(
              label: 'Disconnect',
              variant: ButtonVariant.destructive,
              size: ButtonSize.small,
              onPressed: () {
                Navigator.pop(ctx);
                // Disconnect from server
                ref.read(backendProvider.notifier).disconnect();
              },
            ),
          ],
        ),
      );
    } else {
      // Show connection dialog
      _showConnectDialog(context, ref);
    }
  }

  void _showConnectDialog(BuildContext context, WidgetRef ref) {
    final settings = ref.read(appSettingsProvider).valueOrNull;
    final host = settings?.alpacaServerHost.isNotEmpty == true
        ? settings!.alpacaServerHost
        : settings?.indiServerHost ?? 'localhost';
    final port = settings?.alpacaServerPort ?? 8080;
    final hostController = TextEditingController(text: host);
    final portController = TextEditingController(text: port.toString());
    final tokenController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect to Server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: hostController,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText: 'e.g., localhost or 192.168.1.100',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '8080',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: tokenController,
              decoration: const InputDecoration(
                labelText: 'Access Token',
                hintText: 'Optional unless the server requires pairing/auth',
              ),
            ),
          ],
        ),
        actions: [
          NightshadeButton(
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => Navigator.pop(ctx),
          ),
          NightshadeButton(
            label: 'Connect',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: () {
              final host = hostController.text.trim();
              final port = int.tryParse(portController.text.trim()) ?? 8080;
              final token = tokenController.text.trim();
              if (host.isNotEmpty) {
                Navigator.pop(ctx);
                ref.read(backendProvider.notifier).connect(
                      host,
                      port,
                      authToken: token.isEmpty ? null : token,
                    );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _PlatformCapabilityMatrixView extends StatelessWidget {
  final PlatformCapabilityReport report;
  final NightshadeColors colors;
  final bool isMobile;

  const _PlatformCapabilityMatrixView({
    required this.report,
    required this.colors,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final platformLabel = _formatPlatform(report.platform);

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.monitor,
                  size: isMobile ? 16 : 18, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Current platform: $platformLabel',
                  style: TextStyle(
                    fontSize: isMobile ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...report.drivers.map(
            (driver) => _PlatformCapabilityRow(
              driver: driver,
              platform: report.platform,
              colors: colors,
              isMobile: isMobile,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPlatform(String platform) {
    switch (platform) {
      case PlatformCapabilityMatrix.windows:
        return 'Windows';
      case PlatformCapabilityMatrix.linux:
        return 'Linux';
      case PlatformCapabilityMatrix.macos:
        return 'macOS';
      default:
        return platform;
    }
  }
}

class _PlatformCapabilityRow extends StatelessWidget {
  final PlatformDriverCapability driver;
  final String platform;
  final NightshadeColors colors;
  final bool isMobile;

  const _PlatformCapabilityRow({
    required this.driver,
    required this.platform,
    required this.colors,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final status = driver.statusFor(platform);
    final statusColor = _statusColor(status);
    final statusLabel = _statusLabel(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: isMobile
          ? _buildMobile(statusColor, statusLabel)
          : _buildDesktop(statusColor, statusLabel),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'available':
        return colors.success;
      case 'capability-gated':
        return colors.warning;
      default:
        return colors.error;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'available':
        return 'Available';
      case 'capability-gated':
        return 'Capability-gated';
      default:
        return 'Unsupported';
    }
  }

  Widget _buildDesktop(Color statusColor, String statusLabel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: _DriverLabel(
            driver: driver,
            statusColor: statusColor,
            statusLabel: statusLabel,
            colors: colors,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _DriverDetails(
            driver: driver,
            platform: platform,
            colors: colors,
            isMobile: false,
          ),
        ),
      ],
    );
  }

  Widget _buildMobile(Color statusColor, String statusLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DriverLabel(
          driver: driver,
          statusColor: statusColor,
          statusLabel: statusLabel,
          colors: colors,
        ),
        const SizedBox(height: 8),
        _DriverDetails(
          driver: driver,
          platform: platform,
          colors: colors,
          isMobile: true,
        ),
      ],
    );
  }
}

class _DriverLabel extends StatelessWidget {
  final PlatformDriverCapability driver;
  final Color statusColor;
  final String statusLabel;
  final NightshadeColors colors;

  const _DriverLabel({
    required this.driver,
    required this.statusColor,
    required this.statusLabel,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          driver.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _DriverDetails extends StatelessWidget {
  final PlatformDriverCapability driver;
  final String platform;
  final NightshadeColors colors;
  final bool isMobile;

  const _DriverDetails({
    required this.driver,
    required this.platform,
    required this.colors,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final unsupportedReason =
        driver.isAvailableOn(platform) ? null : driver.reasonFor(platform);
    final detailText = unsupportedReason ?? driver.reasonFor(platform);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detailText,
          style: TextStyle(
            fontSize: isMobile ? 11 : 12,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          driver.deviceCoverage,
          style: TextStyle(
            fontSize: isMobile ? 10 : 11,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}
