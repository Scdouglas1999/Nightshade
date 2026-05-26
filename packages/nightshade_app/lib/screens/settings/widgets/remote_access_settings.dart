import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../localization/nightshade_localizations.dart';
import '../pairing_screen.dart';
import 'settings_widgets.dart';

class RemoteAccessSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const RemoteAccessSettings({
    super.key,
    this.isMobile = false,
  });

  @override
  ConsumerState<RemoteAccessSettings> createState() =>
      _RemoteAccessSettingsState();
}

class _RemoteAccessSettingsState extends ConsumerState<RemoteAccessSettings> {
  late TextEditingController _portController;
  late FocusNode _portFocusNode;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController();
    _portFocusNode = FocusNode();
    _portFocusNode.addListener(() {
      if (!_portFocusNode.hasFocus) {
        final settings = ref.read(appSettingsProvider).valueOrNull;
        if (settings != null) {
          _commitPort(settings, showFeedback: false);
        }
      }
    });
  }

  @override
  void dispose() {
    _portController.dispose();
    _portFocusNode.dispose();
    super.dispose();
  }

  void _commitPort(
    AppSettingsState settings, {
    required bool showFeedback,
  }) {
    final port = int.tryParse(_portController.text);
    if (port != null && port >= 1024 && port <= 65535) {
      if (port != settings.webServerPort) {
        ref.read(appSettingsProvider.notifier).setWebServerPort(port);
      }
      return;
    }

    _portController.text = settings.webServerPort.toString();
    if (showFeedback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text('remoteAccessInvalidPort')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.text(
            'remoteAccessCopiedUrl',
            params: {'url': url},
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text('remoteAccessOpenFailed')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final webState = ref.watch(webServerStateProvider);
    final pairingState = ref.watch(pairingProvider);
    final appVersion = ref.watch(appVersionProvider);
    final l10n = context.l10n;

    return settingsAsync.when(
      loading: () => SettingsLoadingState(isMobile: widget.isMobile),
      error: (error, stack) => SettingsErrorState(
        isMobile: widget.isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) {
        if (!_portFocusNode.hasFocus &&
            _portController.text != settings.webServerPort.toString()) {
          _portController.text = settings.webServerPort.toString();
        }

        final showDetails =
            settings.webServerEnabled || webState.lastError.isNotEmpty;

        return SettingsPage(
          title: l10n.text('remoteAccessTitle'),
          description: l10n.text('remoteAccessDescription'),
          isMobile: widget.isMobile,
          hideHeader: widget.isMobile,
          children: [
            SettingsSection(
              title: l10n.text('remoteAccessWebServer'),
              isMobile: widget.isMobile,
              children: [
                SettingRow(
                  icon: LucideIcons.globe,
                  title: l10n.text('remoteAccessEnableTitle'),
                  subtitle: l10n.text('remoteAccessEnableDesc'),
                  trailing: SettingsSwitch(
                    value: settings.webServerEnabled,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setWebServerEnabled(value);
                    },
                  ),
                  isMobile: widget.isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.hash,
                  title: l10n.text('remoteAccessPortTitle'),
                  subtitle: l10n.text('remoteAccessPortDesc'),
                  trailing: SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _portController,
                      focusNode: _portFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        _PortRangeFormatter(),
                      ],
                      style: TextStyle(
                        fontSize: 13,
                        color: NightshadeColors.of(context).textPrimary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                              color: NightshadeColors.of(context).border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                              color: NightshadeColors.of(context).border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: NightshadeColors.of(context).primary,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: NightshadeColors.of(context).surfaceAlt,
                      ),
                      onTapOutside: (_) =>
                          _commitPort(settings, showFeedback: true),
                      onSubmitted: (_) =>
                          _commitPort(settings, showFeedback: true),
                    ),
                  ),
                  isLast: true,
                  isMobile: widget.isMobile,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (webState.lastError.isNotEmpty)
              _RemoteAccessNoticeCard(
                icon: LucideIcons.alertTriangle,
                iconColor: NightshadeColors.of(context).error,
                title: l10n.text('remoteAccessIssueTitle'),
                body: l10n.text('remoteAccessIssueBody'),
              )
            else if (webState.isRunning) ...[
              _AccessActionCard(
                icon: LucideIcons.monitor,
                title: l10n.text('remoteAccessLocalActionTitle'),
                description: l10n.text('remoteAccessLocalActionBody'),
                url: webState.localUrl,
                primaryLabel: l10n.text('remoteAccessOpenLocal'),
                primaryIcon: LucideIcons.externalLink,
                onPrimary: () => _openUrl(webState.localUrl),
                secondaryLabel: l10n.text('remoteAccessCopyLink'),
                secondaryIcon: LucideIcons.copy,
                onSecondary: () => _copyUrl(webState.localUrl),
              ),
              if (webState.networkUrl.isNotEmpty)
                _AccessActionCard(
                  icon: LucideIcons.wifi,
                  title: l10n.text('remoteAccessLanActionTitle'),
                  description: l10n.text(
                    webState.requiresAuthentication
                        ? 'remoteAccessLanActionBodyPaired'
                        : 'remoteAccessLanActionBodyOpen',
                  ),
                  url: webState.networkUrl,
                  primaryLabel: l10n.text('remoteAccessCopyLan'),
                  primaryIcon: LucideIcons.copy,
                  onPrimary: () => _copyUrl(webState.networkUrl),
                  secondaryLabel: l10n.text('remoteAccessOpenLink'),
                  secondaryIcon: LucideIcons.externalLink,
                  onSecondary: () => _openUrl(webState.networkUrl),
                ),
            ] else
              _RemoteAccessNoticeCard(
                icon: settings.webServerEnabled
                    ? LucideIcons.loader2
                    : LucideIcons.power,
                iconColor: settings.webServerEnabled
                    ? NightshadeColors.of(context).info
                    : NightshadeColors.of(context).textMuted,
                title: settings.webServerEnabled
                    ? l10n.text('remoteAccessStartingTitle')
                    : l10n.text('remoteAccessDisabledTitle'),
                body: settings.webServerEnabled
                    ? l10n.text('remoteAccessStartingBody')
                    : l10n.text('remoteAccessDisabledBody'),
              ),
            const SizedBox(height: 8),
            _PairingCallout(
              title: l10n.text('remoteAccessPairTitle'),
              description: l10n.text('remoteAccessPairDesc'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PairingScreen(),
                  ),
                );
              },
            ),
            if (webState.isRunning &&
                webState.serverFingerprint.isNotEmpty) ...[
              const SizedBox(height: 8),
              _RemotePairingQrPanel(
                webState: webState,
                pairingCode: pairingState.pairingCode,
                appVersion: appVersion.version,
                onStartPairing: pairingState.pairingCode == null
                    ? () => ref.read(pairingProvider.notifier).startPairing()
                    : null,
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: NightshadeDecorations.iconChip(
                NightshadeColors.of(context).primary,
                borderRadius: BorderRadius.circular(10),
                borderAlpha: 0.2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.info,
                    size: 16,
                    color: NightshadeColors.of(context).primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.text('remoteAccessInfoBody'),
                      style: TextStyle(
                        fontSize: 12,
                        color: NightshadeColors.of(context).textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showDetails) ...[
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: NightshadeColors.of(context).surface,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: NightshadeColors.of(context).border),
                  ),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    childrenPadding: EdgeInsets.zero,
                    leading: Icon(
                      LucideIcons.slidersHorizontal,
                      size: 16,
                      color: NightshadeColors.of(context).textMuted,
                    ),
                    title: Text(
                      l10n.text('remoteAccessDetailsTitle'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: NightshadeColors.of(context).textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      l10n.text('remoteAccessDetailsBody'),
                      style: TextStyle(
                        fontSize: 12,
                        color: NightshadeColors.of(context).textMuted,
                      ),
                    ),
                    children: [
                      _StatusRow(
                        icon: webState.isRunning
                            ? LucideIcons.checkCircle2
                            : LucideIcons.xCircle,
                        iconColor: webState.isRunning
                            ? NightshadeColors.of(context).success
                            : NightshadeColors.of(context).textMuted,
                        label: l10n.text('remoteAccessServerStatus'),
                        value: webState.isRunning
                            ? l10n.text('remoteAccessRunning')
                            : l10n.text('remoteAccessStopped'),
                      ),
                      _StatusRow(
                        icon: LucideIcons.shield,
                        iconColor: webState.requiresAuthentication
                            ? NightshadeColors.of(context).primary
                            : NightshadeColors.of(context).textMuted,
                        label: l10n.text('remoteAccessAuth'),
                        value: webState.requiresAuthentication
                            ? l10n.text('remoteAccessAuthRequired')
                            : l10n.text('remoteAccessAuthNotRequired'),
                      ),
                      _StatusRow(
                        icon: LucideIcons.wifi,
                        iconColor: webState.bindLocalOnly
                            ? NightshadeColors.of(context).textMuted
                            : NightshadeColors.of(context).primary,
                        label: l10n.text('remoteAccessScope'),
                        value: webState.bindLocalOnly
                            ? l10n.text('remoteAccessScopeLocal')
                            : l10n.text('remoteAccessScopeLan'),
                      ),
                      _StatusRow(
                        icon: LucideIcons.monitor,
                        iconColor: webState.dashboardAvailable
                            ? NightshadeColors.of(context).success
                            : NightshadeColors.of(context).warning,
                        label: l10n.text('remoteAccessDashboard'),
                        value: webState.dashboardAvailable
                            ? l10n.text('remoteAccessDashboardAvailable')
                            : l10n.text('remoteAccessDashboardMissing'),
                      ),
                      _StatusRow(
                        icon: LucideIcons.users,
                        iconColor: webState.activeViewers > 0
                            ? NightshadeColors.of(context).primary
                            : NightshadeColors.of(context).textMuted,
                        label: l10n.text('remoteAccessActiveViewers'),
                        value: webState.activeViewers.toString(),
                      ),
                      _StatusRow(
                        icon: webState.lastError.isEmpty
                            ? LucideIcons.info
                            : LucideIcons.alertTriangle,
                        iconColor: webState.lastError.isEmpty
                            ? NightshadeColors.of(context).textMuted
                            : NightshadeColors.of(context).error,
                        label: l10n.text('remoteAccessLastError'),
                        value: webState.lastError.isEmpty
                            ? l10n.text('remoteAccessNoErrors')
                            : webState.lastError,
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PortRangeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final port = int.tryParse(newValue.text);
    if (port == null) return oldValue;
    if (port > 65535) return oldValue;
    return newValue;
  }
}

class _RemoteAccessNoticeCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  const _RemoteAccessNoticeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
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
    );
  }
}

class _AccessActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String url;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final IconData secondaryIcon;
  final VoidCallback onSecondary;

  const _AccessActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.url,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.secondaryIcon,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              url,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colors.primary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              NightshadeButton(
                label: primaryLabel,
                icon: primaryIcon,
                variant: ButtonVariant.primary,
                size: ButtonSize.small,
                onPressed: onPrimary,
              ),
              NightshadeButton(
                label: secondaryLabel,
                icon: secondaryIcon,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: onSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RemotePairingQrPanel extends StatelessWidget {
  final WebServerState webState;
  final String? pairingCode;
  final String appVersion;
  final VoidCallback? onStartPairing;

  const _RemotePairingQrPanel({
    required this.webState,
    required this.pairingCode,
    required this.appVersion,
    this.onStartPairing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final l10n = context.l10n;
    // Never embed localhost in QR — tablets cannot reach the PC loopback.
    final host = webState.localIp.isNotEmpty &&
            webState.localIp != 'localhost' &&
            webState.localIp != '127.0.0.1'
        ? webState.localIp
        : '';
    final qrPayload = host.isEmpty
        ? null
        : EnhancedNightshadeDiscovery.generateQrData(
            host: host,
            webPort: webState.actualPort,
            version: appVersion,
            fingerprint: webState.serverFingerprint,
            serverName: 'Nightshade',
            mode: 'desktop',
            authRequired: webState.requiresAuthentication,
            authenticationMode:
                webState.requiresAuthentication ? 'token' : 'none',
            pairingSupported: true,
            pairingCode: pairingCode,
          );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.text('remoteAccessQrTitle'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.text('remoteAccessQrBody'),
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            '${l10n.text('remoteAccessFingerprint')}: '
            '${shortServerFingerprint(webState.serverFingerprint)}',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          if (pairingCode == null && onStartPairing != null) ...[
            NightshadeButton(
              label: l10n.text('pairingStartButton'),
              icon: LucideIcons.link,
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: onStartPairing,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.text('remoteAccessQrStartHint'),
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ] else if (pairingCode != null && qrPayload != null) ...[
            Center(
              child: QrImageView(
                data: qrPayload,
                size: 200,
                backgroundColor: const Color(0xFFFFFFFF),
                semanticsLabel:
                    'Nightshade pairing QR for $host:${webState.actualPort}',
              ),
            ),
          ] else if (pairingCode != null && qrPayload == null) ...[
            Text(
              l10n.text('remoteAccessQrNoLanIp'),
              style: TextStyle(fontSize: 12, color: colors.warning),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                pairingCode!,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PairingCallout extends StatelessWidget {
  final String title;
  final String description;
  final VoidCallback onPressed;

  const _PairingCallout({
    required this.title,
    required this.description,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          NightshadeButton(
            label: context.l10n.text('remoteAccessManagePairing'),
            icon: LucideIcons.link,
            variant: ButtonVariant.primary,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool isLast;

  const _StatusRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: colors.border.withValues(alpha: 0.5),
                ),
              ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
