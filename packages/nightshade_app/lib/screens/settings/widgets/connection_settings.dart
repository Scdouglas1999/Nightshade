import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/tutorial_keys/settings_keys.dart';
import '../../../widgets/work_locally.dart';
import '../../equipment/dialogs/indi_server_dialog.dart';
import 'connection_settings_alpaca_dialog.dart';
import 'settings_widgets.dart';

class ConnectionSettings extends ConsumerWidget {
  final bool isMobile;

  const ConnectionSettings({super.key, this.isMobile = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final backend = ref.watch(backendProvider);
    final isNetwork = backend is NetworkBackend;
    final isDisconnected = backend is DisconnectedBackend;
    // Live connection state — the authoritative signal for whether a network
    // backend is actually connected, mid-handshake, or errored. Relying on
    // `backend is NetworkBackend` alone would render a still-connecting (or a
    // rolled-back/errored) session as "Connected".
    final connState =
        ref.watch(networkBackendConnectionStateProvider).valueOrNull;
    final isConnected =
        isNetwork && connState == BackendConnectionState.connected;
    final isConnectError =
        isNetwork && connState == BackendConnectionState.error;
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final settingsNotifier = ref.read(appSettingsProvider.notifier);
    final platformCapabilities =
        PlatformCapabilityMatrix.forPlatform(Platform.operatingSystem);

    // Derive the status label/colour from the live connection state, not just
    // the backend's runtime type.
    String serverAddress = 'Not connected';
    String connectionStatus = 'Disconnected';
    Color statusColor = colors.textMuted;

    if (isNetwork) {
      serverAddress = '${backend.serverHost}:${backend.serverPort}';
      if (isConnected) {
        connectionStatus = 'Connected';
        statusColor = colors.success;
      } else if (isConnectError) {
        connectionStatus = 'Connection error';
        statusColor = colors.error;
      } else {
        connectionStatus = 'Connecting...';
        statusColor = colors.warning;
      }
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
      isMobile: isMobile,
      hideHeader: isMobile,
      children: [
        SettingsSection(
          title: 'Server Status',
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.server,
              title: 'Connection Status',
              subtitle: serverAddress,
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: NightshadeDecorations.emphasisSurface(
                  statusColor,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusMd),
                ),
                child: Text(
                  connectionStatus,
                  style: TextStyle(
                    fontSize: isMobile
                        ? NightshadeTypography.fontSize10
                        : NightshadeTypography.fontSize11,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              isMobile: isMobile,
            ),
            if (isNetwork)
              SettingRow(
                icon: LucideIcons.globe,
                title: 'Server Address',
                subtitle: 'Current host and port for this Nightshade server',
                trailing: SelectableText(
                  serverAddress,
                  style: TextStyle(
                    fontSize: isMobile
                        ? NightshadeTypography.fontSize11
                        : NightshadeTypography.fontSize12,
                    color: colors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
                isMobile: isMobile,
              ),
            SettingRow(
              icon: isNetwork ? LucideIcons.logOut : LucideIcons.logIn,
              title: isNetwork ? 'Disconnect' : 'Connect to Server',
              subtitle: isNetwork
                  ? 'Return to connection screen to connect to a different server'
                  : 'Open connection screen to connect to a server',
              trailing: NightshadeButton(
                label: isNetwork ? 'Disconnect' : 'Connect',
                variant: isNetwork
                    ? ButtonVariant.destructive
                    : ButtonVariant.primary,
                size: isMobile ? ButtonSize.small : ButtonSize.small,
                onPressed: () =>
                    _handleConnectionAction(context, ref, isNetwork),
              ),
              isLast: !(isDisconnected && canWorkLocally),
              isMobile: isMobile,
            ),
            // The only way out of a DisconnectedBackend was to relaunch:
            // `useLocalBackend()` had no UI caller anywhere in the app, so a
            // desktop that fell out of local mode stayed there, red banner and
            // all. Offer the way back on the platforms whose entry point runs
            // the rig locally — a phone has no local hardware to fall back to.
            if (isDisconnected && canWorkLocally)
              SettingRow(
                icon: LucideIcons.hardDrive,
                title: 'Work Locally',
                subtitle:
                    'Drive the equipment attached to this computer instead of '
                    'a remote server',
                trailing: const WorkLocallyButton(),
                isLast: true,
                isMobile: isMobile,
              ),
          ],
        ),
        if (settings != null)
          SettingsSection(
            title: 'Discovery',
            isMobile: isMobile,
            children: [
              // INDI is a Linux/macOS device-protocol server; on Windows the
              // host/port knob is not applicable, so only offer it off-Windows.
              if (!Platform.isWindows)
                SettingRow(
                  icon: LucideIcons.server,
                  title: 'INDI Server Address',
                  subtitle:
                      '${settings.indiServerHost}:${settings.indiServerPort}'
                      ' • host and port used for INDI discovery',
                  trailing: NightshadeButton(
                    label: 'Configure',
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed: () => showDialog<Map<String, dynamic>>(
                      context: context,
                      builder: (_) => const IndiServerDialog(),
                    ),
                  ),
                  isMobile: isMobile,
                ),
              SettingRow(
                icon: LucideIcons.radio,
                title: 'Query INDI on startup',
                subtitle:
                    'Include the configured INDI server in automatic startup discovery',
                trailing: SettingsSwitch(
                  value: settings.indiAutoConnect,
                  onChanged: settingsNotifier.setIndiAutoConnect,
                ),
                isMobile: isMobile,
              ),
              // The address row the "configured Alpaca server" below it always
              // referred to. Without it the address was permanently the stored
              // default (localhost:11111) even though the common Alpaca
              // deployment is an ASCOM Remote host elsewhere on the LAN.
              SettingRow(
                icon: LucideIcons.server,
                title: 'Alpaca Server Address',
                subtitle:
                    '${settings.alpacaServerHost}:${settings.alpacaServerPort}'
                    ' • host and port used for Alpaca discovery',
                trailing: NightshadeButton(
                  label: 'Configure',
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                  onPressed: () => showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => const AlpacaServerDialog(),
                  ),
                ),
                isMobile: isMobile,
              ),
              SettingRow(
                icon: LucideIcons.search,
                title: 'Query Alpaca on startup',
                subtitle:
                    'Include the configured Alpaca server in automatic startup discovery',
                trailing: SettingsSwitch(
                  value: settings.alpacaAutoDiscover,
                  onChanged: settingsNotifier.setAlpacaAutoDiscover,
                ),
                isLast: true,
                isMobile: isMobile,
              ),
            ],
          ),
        if (isConnected)
          SettingsSection(
            title: 'Remote Features',
            isMobile: isMobile,
            children: [
              SettingRow(
                icon: LucideIcons.refreshCw,
                title: 'Refresh Host Settings',
                subtitle:
                    'Reload this screen from the connected Nightshade host',
                trailing: _HostSettingsRefreshButton(
                  isMobile: isMobile,
                ),
                isLast: true,
                isMobile: isMobile,
              ),
            ],
          ),
        SettingsSection(
          // The capability matrix is computed from the LOCAL device's OS
          // (Platform.operatingSystem). In remote mode that is the tablet, not
          // the imaging host — so relabel to make clear whose driver support
          // this describes and avoid implying it is the rig's capabilities.
          title: isConnected
              ? 'This Device Capabilities'
              : 'Platform Capabilities',
          isMobile: isMobile,
          children: [
            _PlatformCapabilityMatrixView(
              report: platformCapabilities,
              isMobile: isMobile,
              isRemote: isConnected,
            ),
          ],
        ),
      ],
    );
  }

  void _handleConnectionAction(
      BuildContext context, WidgetRef ref, bool hasNetworkBackend) {
    if (hasNetworkBackend) {
      // Offer to tear down the installed network backend (whether it is live,
      // still connecting, or errored) before returning to the connect screen.
      var disconnecting = false;
      String? disconnectError;
      showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Disconnect from Server?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You will return to the connection screen where you can '
                  'connect to a different server.',
                ),
                if (disconnectError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    disconnectError!,
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              NightshadeButton(
                label: 'Cancel',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                onPressed: disconnecting ? null : () => Navigator.pop(ctx),
              ),
              NightshadeButton(
                label: disconnecting ? 'Disconnecting...' : 'Disconnect',
                variant: ButtonVariant.destructive,
                size: ButtonSize.small,
                onPressed: disconnecting
                    ? null
                    : () async {
                        setDialogState(() {
                          disconnecting = true;
                          disconnectError = null;
                        });
                        try {
                          await ref.read(backendProvider.notifier).disconnect();
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          if (!ctx.mounted) return;
                          setDialogState(() {
                            disconnecting = false;
                            disconnectError = 'Disconnect blocked: $e';
                          });
                        }
                      },
              ),
            ],
          ),
        ),
      );
    } else {
      // Show connection dialog
      _showConnectDialog(context);
    }
  }

  void _showConnectDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _ConnectToServerDialog(),
    );
  }
}

class _HostSettingsRefreshButton extends ConsumerStatefulWidget {
  const _HostSettingsRefreshButton({required this.isMobile});

  final bool isMobile;

  @override
  ConsumerState<_HostSettingsRefreshButton> createState() =>
      _HostSettingsRefreshButtonState();
}

class _HostSettingsRefreshButtonState
    extends ConsumerState<_HostSettingsRefreshButton> {
  bool _refreshing = false;
  int _generation = 0;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;

  @override
  void initState() {
    super.initState();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (identical(previous, next)) return;
        _generation++;
        if (mounted && _refreshing) {
          setState(() => _refreshing = false);
        }
      },
    );
  }

  @override
  void dispose() {
    _generation++;
    _backendSubscription?.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final authority = ref.read(backendProvider);
    final generation = ++_generation;
    setState(() => _refreshing = true);
    try {
      ref.invalidate(appSettingsProvider);
      await ref.read(appSettingsProvider.future);
      if (_isCurrent(generation, authority) && mounted) {
        context.showSuccessSnackBar('Host settings refreshed');
      }
    } catch (e) {
      if (_isCurrent(generation, authority) && mounted) {
        context.showErrorSnackBar('Refresh failed: $e');
      }
    } finally {
      if (_isCurrent(generation, authority)) {
        setState(() => _refreshing = false);
      }
    }
  }

  bool _isCurrent(int generation, NightshadeBackend authority) =>
      mounted &&
      _refreshing &&
      generation == _generation &&
      identical(ref.read(backendProvider), authority);

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return IconButton(
      tooltip: 'Refresh host settings',
      onPressed: _refreshing ? null : _refresh,
      icon: _refreshing
          ? SizedBox(
              width: widget.isMobile ? 20 : 18,
              height: widget.isMobile ? 20 : 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            )
          : Icon(
              LucideIcons.downloadCloud,
              color: colors.primary,
              size: widget.isMobile ? 20 : 18,
            ),
    );
  }
}

/// Manual "Connect to Nightshade Server" dialog.
///
/// A Nightshade server is a distinct authority from the Alpaca / INDI
/// device-protocol servers, so this dialog seeds neutral defaults rather than
/// borrowing an unrelated protocol's host/port (which conflated protocols and
/// pre-filled the wrong endpoint). It validates input, awaits the backend
/// connect behind a busy guard, and — because [BackendNotifier.connect] now
/// throws when the handshake does not reach a live connection — stays open and
/// shows the failure so a refused connection remains retryable.
class _ConnectToServerDialog extends ConsumerStatefulWidget {
  const _ConnectToServerDialog();

  @override
  ConsumerState<_ConnectToServerDialog> createState() =>
      _ConnectToServerDialogState();
}

class _ConnectToServerDialogState
    extends ConsumerState<_ConnectToServerDialog> {
  // Neutral defaults — deliberately NOT derived from Alpaca/INDI settings.
  // 8080 is the Nightshade headless server's default port.
  final _hostController = TextEditingController(text: 'localhost');
  final _portController = TextEditingController(text: '8080');
  final _tokenController = TextEditingController();

  bool _isConnecting = false;
  String? _hostError;
  String? _portError;
  String? _statusMessage;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  ({String host, int port, String? token})? _validatedInputs() {
    final host = _hostController.text.trim();
    final portRaw = _portController.text.trim();
    final token = _tokenController.text.trim();

    String? hostError;
    String? portError;
    if (host.isEmpty) {
      hostError = 'Enter a host name or IP address.';
    }
    final port = int.tryParse(portRaw);
    if (port == null) {
      portError = 'Port must be a whole number.';
    } else if (port < 1 || port > 65535) {
      portError = 'Port must be between 1 and 65535.';
    }

    setState(() {
      _hostError = hostError;
      _portError = portError;
    });

    if (hostError != null || portError != null || port == null) return null;
    return (host: host, port: port, token: token.isEmpty ? null : token);
  }

  Future<void> _connect() async {
    if (_isConnecting) return;
    final inputs = _validatedInputs();
    if (inputs == null) return;

    // A local FfiBackend is the only backend that is neither remote nor an
    // explicit "nothing installed" state. Remember whether we are about to
    // displace one, because the failure path has to put it back.
    final priorBackend = ref.read(backendProvider);
    final hadLocalBackend =
        priorBackend is! NetworkBackend && priorBackend is! DisconnectedBackend;

    setState(() {
      _isConnecting = true;
      _statusMessage = null;
    });

    try {
      await ref.read(backendProvider.notifier).connect(
            inputs.host,
            inputs.port,
            authToken: inputs.token,
          );
      if (!mounted) return;
      Navigator.pop(context);
    } on BackendTransitionSupersededException {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      // BackendNotifier.connect() rolls a failed handshake back to a
      // DisconnectedBackend. That is right for a client that never had a rig
      // of its own, but on the machine that OWNS the hardware it trades a
      // working local session for a dead one: every role provider follows
      // backendProvider, so the shell pins "Error: not connected to server"
      // over an app that was driving the mount a second earlier. Reaching an
      // OPTIONAL remote host must not cost the operator local mode.
      final restoreError =
          hadLocalBackend ? await _restoreLocalBackend() : null;
      if (!mounted) return;
      // Stay open so the operator can correct the address and retry.
      setState(() {
        _isConnecting = false;
        _statusMessage = switch ((hadLocalBackend, restoreError)) {
          (true, null) =>
            'Connection failed: $e\nStill working locally on this computer.',
          (true, final String problem) => 'Connection failed: $e\n'
              'Could not return to local mode either: $problem',
          _ => 'Connection failed: $e',
        };
      });
    }
  }

  /// Put the displaced local backend back. Returns null on success, or a
  /// description of why local mode could not be restored.
  Future<String?> _restoreLocalBackend() async {
    try {
      await ref.read(backendProvider.notifier).useLocalBackend();
      return null;
    } on BackendTransitionSupersededException {
      // A newer connect/disconnect owns the backend now; leave it alone.
      return null;
    } catch (error) {
      return '$error';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return AlertDialog(
      title: const Text('Connect to Server'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('connect-host-field'),
            controller: _hostController,
            enabled: !_isConnecting,
            onChanged: (_) {
              if (_hostError != null) setState(() => _hostError = null);
            },
            decoration: InputDecoration(
              labelText: 'Host',
              hintText: 'e.g., localhost or 192.168.1.100',
              errorText: _hostError,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('connect-port-field'),
            controller: _portController,
            enabled: !_isConnecting,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) {
              if (_portError != null) setState(() => _portError = null);
            },
            decoration: InputDecoration(
              labelText: 'Port',
              hintText: '8080',
              errorText: _portError,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tokenController,
            enabled: !_isConnecting,
            decoration: const InputDecoration(
              labelText: 'Access Token',
              hintText: 'Optional unless the server requires pairing/auth',
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(NightshadeIcons.error, size: 16, color: colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        NightshadeButton(
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
          onPressed: _isConnecting ? null : () => Navigator.pop(context),
        ),
        NightshadeButton(
          label: _isConnecting ? 'Connecting...' : 'Connect',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
          isLoading: _isConnecting,
          onPressed: _isConnecting ? null : _connect,
        ),
      ],
    );
  }
}

class _PlatformCapabilityMatrixView extends StatelessWidget {
  final PlatformCapabilityReport report;
  final bool isMobile;
  final bool isRemote;

  const _PlatformCapabilityMatrixView({
    required this.report,
    required this.isMobile,
    this.isRemote = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
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
                  isRemote
                      ? 'This device: $platformLabel (not the imaging host)'
                      : 'Current platform: $platformLabel',
                  style: TextStyle(
                    fontSize: isMobile
                        ? NightshadeTypography.fontSize12
                        : NightshadeTypography.fontSize13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (isRemote) ...[
            const SizedBox(height: 6),
            Text(
              'Driver support shown is for this device. The imaging host may '
              'support different drivers.',
              style: TextStyle(
                fontSize: isMobile
                    ? NightshadeTypography.fontSize11
                    : NightshadeTypography.fontSize12,
                color: colors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...report.drivers.map(
            (driver) => _PlatformCapabilityRow(
              driver: driver,
              platform: report.platform,
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
  final bool isMobile;

  const _PlatformCapabilityRow({
    required this.driver,
    required this.platform,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final status = driver.statusFor(platform);
    final statusColor = _statusColor(colors, status);
    final statusLabel = _statusLabel(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: isMobile
          ? _buildMobile(statusColor, statusLabel)
          : _buildDesktop(statusColor, statusLabel),
    );
  }

  Color _statusColor(NightshadeColors colors, String status) {
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
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _DriverDetails(
            driver: driver,
            platform: platform,
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
        ),
        const SizedBox(height: 8),
        _DriverDetails(
          driver: driver,
          platform: platform,
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

  const _DriverLabel({
    required this.driver,
    required this.statusColor,
    required this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          driver.label,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize12,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: NightshadeDecorations.statusChip(
            statusColor,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize10,
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
  final bool isMobile;

  const _DriverDetails({
    required this.driver,
    required this.platform,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final unsupportedReason =
        driver.isAvailableOn(platform) ? null : driver.unsupportedReason;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          driver.notes,
          style: TextStyle(
            fontSize: isMobile
                ? NightshadeTypography.fontSize11
                : NightshadeTypography.fontSize12,
            color: colors.textSecondary,
          ),
        ),
        if (unsupportedReason != null) ...[
          const SizedBox(height: 4),
          Text(
            unsupportedReason,
            style: TextStyle(
              fontSize: isMobile
                  ? NightshadeTypography.fontSize11
                  : NightshadeTypography.fontSize12,
              color: colors.warning,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          driver.deviceCoverage,
          style: TextStyle(
            fontSize: isMobile
                ? NightshadeTypography.fontSize10
                : NightshadeTypography.fontSize11,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}
