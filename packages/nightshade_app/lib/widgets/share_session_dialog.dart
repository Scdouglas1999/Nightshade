import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Opens the Remote Access sheet: the local and LAN URLs, the pairing state
/// and the attached-viewer count.
///
/// It used to hang off a share glyph in the status bar. The status bar reports
/// state and nothing else now (04 §5), and sharing a session is an action on
/// the remote connection, so it lives on the top bar's remote indicator, which
/// is already the control for everything else about that connection.
Future<void> showShareSessionDialog(BuildContext context) {
  final colors = NightshadeColors.of(context);
  final webState = ProviderScope.containerOf(
    context,
  ).read(webServerStateProvider);
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _ShareSessionDialog(webState: webState, colors: colors),
  );
}

class _ShareSessionDialog extends ConsumerWidget {
  final WebServerState webState;
  final NightshadeColors colors;

  const _ShareSessionDialog({
    required this.webState,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentState = ref.watch(webServerStateProvider);
    final networkUrl = currentState.networkUrl;
    final hasLanAccess = networkUrl.isNotEmpty;
    final viewerLabel =
        currentState.requiresAuthentication ? 'authenticated viewer' : 'viewer';
    // Remote clients attached to this server. Reading the co-imaging viewer
    // list here made this panel say "No viewers connected" to an operator whose
    // phone was holding an authenticated event socket.
    final connected = currentState.connectedClients;

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: NightshadeTokens.borderRadiusInline8,
        side: BorderSide(color: colors.border),
      ),
      title: Row(
        children: [
          Icon(NightshadeIcons.share, size: 20, color: colors.primary),
          const SizedBox(width: 10),
          Text(
            'Remote Access',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: NightshadeTypography.fontSize18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: Responsive.dialogConstraints(
          context,
          preferredWidth: ShellChromeMetrics.shareDialogPreferredWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentState.bindLocalOnly
                  ? 'Remote access is currently limited to this machine.'
                  : currentState.requiresAuthentication
                      ? 'Local access works immediately on this machine. Remote browsers on your LAN must pair before they can control the app.'
                      : 'Remote access is available on your local network.',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _UrlCard(
              label: 'Local dashboard',
              url: currentState.localUrl,
              colors: colors,
            ),
            if (hasLanAccess) ...[
              const SizedBox(height: 12),
              _UrlCard(
                label: currentState.requiresAuthentication
                    ? 'LAN endpoint (paired devices only)'
                    : 'LAN endpoint',
                url: networkUrl,
                colors: colors,
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: connected > 0
                    ? colors.success.withValues(alpha: 0.08)
                    : colors.surfaceAlt,
                borderRadius: NightshadeTokens.borderRadiusInline8,
                border: Border.all(
                  color: connected > 0
                      ? colors.success.withValues(alpha: 0.3)
                      : colors.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.users,
                    size: 14,
                    color: connected > 0 ? colors.success : colors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    connected > 0
                        ? '$connected $viewerLabel${connected == 1 ? '' : 's'} connected'
                        : 'No viewers connected',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize13,
                      color: connected > 0 ? colors.success : colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (currentState.lastError.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.error.withValues(alpha: 0.08),
                  borderRadius: NightshadeTokens.borderRadiusInline8,
                  border: Border.all(
                    color: colors.error.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      NightshadeIcons.warning,
                      size: 14,
                      color: colors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        currentState.lastError,
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
                          color: colors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        NightshadeButton(
          label: 'Close',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _UrlCard extends StatelessWidget {
  final String label;
  final String url;
  final NightshadeColors colors;

  const _UrlCard({
    required this.label,
    required this.url,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      variant: CardVariant.standard,
      borderRadius: NightshadeTokens.radiusInline8,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: NightshadeTypography.labelStrongSm
                .copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(NightshadeIcons.link, size: 14, color: colors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  url,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize13,
                    fontWeight: FontWeight.w500,
                    color: colors.primary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Link copied to clipboard'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: colors.surfaceAlt,
                    ),
                  );
                },
                borderRadius: NightshadeTokens.borderRadiusMd,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: NightshadeDecorations.tintedBadge(
                    colors.primary,
                    borderRadius: NightshadeTokens.borderRadiusMd,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        NightshadeIcons.copy,
                        size: 12,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Copy',
                        style: NightshadeTypography.labelSm
                            .copyWith(color: colors.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
