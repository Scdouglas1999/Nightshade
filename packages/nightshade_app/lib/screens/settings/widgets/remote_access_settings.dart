import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../localization/nightshade_localizations.dart';
import '../pairing_screen.dart';
import 'settings_widgets.dart';

class RemoteAccessSettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const RemoteAccessSettings({
    super.key,
    required this.colors,
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
    final l10n = context.l10n;

    return settingsAsync.when(
      loading: () => SettingsLoadingState(
          colors: widget.colors, isMobile: widget.isMobile),
      error: (error, stack) => SettingsErrorState(
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: widget.isMobile,
          hideHeader: widget.isMobile,
          children: [
            SettingsSection(
              title: l10n.text('remoteAccessWebServer'),
              colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                        color: widget.colors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: widget.colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: widget.colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: widget.colors.primary,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: widget.colors.surfaceAlt,
                      ),
                      onTapOutside: (_) =>
                          _commitPort(settings, showFeedback: true),
                      onSubmitted: (_) =>
                          _commitPort(settings, showFeedback: true),
                    ),
                  ),
                  isLast: true,
                  colors: widget.colors,
                  isMobile: widget.isMobile,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (webState.lastError.isNotEmpty)
              _RemoteAccessNoticeCard(
                colors: widget.colors,
                icon: LucideIcons.alertTriangle,
                iconColor: widget.colors.error,
                title: l10n.text('remoteAccessIssueTitle'),
                body: l10n.text('remoteAccessIssueBody'),
              )
            else if (webState.isRunning) ...[
              _AccessActionCard(
                colors: widget.colors,
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
                  colors: widget.colors,
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
                colors: widget.colors,
                icon: settings.webServerEnabled
                    ? LucideIcons.loader2
                    : LucideIcons.power,
                iconColor: settings.webServerEnabled
                    ? widget.colors.info
                    : widget.colors.textMuted,
                title: settings.webServerEnabled
                    ? l10n.text('remoteAccessStartingTitle')
                    : l10n.text('remoteAccessDisabledTitle'),
                body: settings.webServerEnabled
                    ? l10n.text('remoteAccessStartingBody')
                    : l10n.text('remoteAccessDisabledBody'),
              ),
            const SizedBox(height: 8),
            _PairingCallout(
              colors: widget.colors,
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
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.colors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.colors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.info,
                    size: 16,
                    color: widget.colors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.text('remoteAccessInfoBody'),
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.colors.textSecondary,
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
                    color: widget.colors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: widget.colors.border),
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
                      color: widget.colors.textMuted,
                    ),
                    title: Text(
                      l10n.text('remoteAccessDetailsTitle'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.colors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      l10n.text('remoteAccessDetailsBody'),
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.colors.textMuted,
                      ),
                    ),
                    children: [
                      _StatusRow(
                        icon: webState.isRunning
                            ? LucideIcons.checkCircle2
                            : LucideIcons.xCircle,
                        iconColor: webState.isRunning
                            ? widget.colors.success
                            : widget.colors.textMuted,
                        label: l10n.text('remoteAccessServerStatus'),
                        value: webState.isRunning
                            ? l10n.text('remoteAccessRunning')
                            : l10n.text('remoteAccessStopped'),
                        colors: widget.colors,
                      ),
                      _StatusRow(
                        icon: LucideIcons.shield,
                        iconColor: webState.requiresAuthentication
                            ? widget.colors.primary
                            : widget.colors.textMuted,
                        label: l10n.text('remoteAccessAuth'),
                        value: webState.requiresAuthentication
                            ? l10n.text('remoteAccessAuthRequired')
                            : l10n.text('remoteAccessAuthNotRequired'),
                        colors: widget.colors,
                      ),
                      _StatusRow(
                        icon: LucideIcons.wifi,
                        iconColor: webState.bindLocalOnly
                            ? widget.colors.textMuted
                            : widget.colors.primary,
                        label: l10n.text('remoteAccessScope'),
                        value: webState.bindLocalOnly
                            ? l10n.text('remoteAccessScopeLocal')
                            : l10n.text('remoteAccessScopeLan'),
                        colors: widget.colors,
                      ),
                      _StatusRow(
                        icon: LucideIcons.monitor,
                        iconColor: webState.dashboardAvailable
                            ? widget.colors.success
                            : widget.colors.warning,
                        label: l10n.text('remoteAccessDashboard'),
                        value: webState.dashboardAvailable
                            ? l10n.text('remoteAccessDashboardAvailable')
                            : l10n.text('remoteAccessDashboardMissing'),
                        colors: widget.colors,
                      ),
                      _StatusRow(
                        icon: LucideIcons.users,
                        iconColor: webState.activeViewers > 0
                            ? widget.colors.primary
                            : widget.colors.textMuted,
                        label: l10n.text('remoteAccessActiveViewers'),
                        value: webState.activeViewers.toString(),
                        colors: widget.colors,
                      ),
                      _StatusRow(
                        icon: webState.lastError.isEmpty
                            ? LucideIcons.info
                            : LucideIcons.alertTriangle,
                        iconColor: webState.lastError.isEmpty
                            ? widget.colors.textMuted
                            : widget.colors.error,
                        label: l10n.text('remoteAccessLastError'),
                        value: webState.lastError.isEmpty
                            ? l10n.text('remoteAccessNoErrors')
                            : webState.lastError,
                        isLast: true,
                        colors: widget.colors,
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
  final NightshadeColors colors;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  const _RemoteAccessNoticeCard({
    required this.colors,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
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
  final NightshadeColors colors;
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
    required this.colors,
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

class _PairingCallout extends StatelessWidget {
  final NightshadeColors colors;
  final String title;
  final String description;
  final VoidCallback onPressed;

  const _PairingCallout({
    required this.colors,
    required this.title,
    required this.description,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
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
  final NightshadeColors colors;

  const _StatusRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.isLast = false,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
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
