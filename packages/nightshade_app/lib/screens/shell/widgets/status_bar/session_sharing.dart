part of '../status_bar.dart';

class _ShareSessionButton extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _ShareSessionButton({required this.colors});

  @override
  ConsumerState<_ShareSessionButton> createState() =>
      _ShareSessionButtonState();
}

class _ShareSessionButtonState extends ConsumerState<_ShareSessionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final webState = ref.watch(webServerStateProvider);
    final hasViewers = webState.activeViewers > 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: webState.isRunning
            ? webState.bindLocalOnly
                ? 'Remote access is limited to this machine'
                : webState.requiresAuthentication
                    ? 'Remote access details and pairing'
                    : 'Remote access details'
            : 'Remote access is not running',
        child: InkWell(
          onTap: webState.isRunning
              ? () => _showShareDialog(context, webState)
              : null,
          borderRadius: NightshadeTokens.borderRadiusInline4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: _isHovered && webState.isRunning
                  ? widget.colors.surfaceAlt
                  : Colors.transparent,
              borderRadius: NightshadeTokens.borderRadiusInline4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  NightshadeIcons.share,
                  size: 12,
                  color: hasViewers
                      ? widget.colors.success
                      : webState.isRunning
                          ? widget.colors.textSecondary
                          : widget.colors.textMuted,
                ),
                if (hasViewers) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: widget.colors.success.withValues(alpha: 0.2),
                      borderRadius: NightshadeTokens.borderRadiusInline8,
                    ),
                    child: Text(
                      '${webState.activeViewers}',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize9,
                        fontWeight: FontWeight.w600,
                        color: widget.colors.success,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showShareDialog(BuildContext context, WebServerState webState) {
    final colors = NightshadeColors.of(context);

    showDialog(
      context: context,
      builder: (context) => _ShareSessionDialog(
        webState: webState,
        colors: colors,
      ),
    );
  }
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
                color: currentState.activeViewers > 0
                    ? colors.success.withValues(alpha: 0.08)
                    : colors.surfaceAlt,
                borderRadius: NightshadeTokens.borderRadiusInline8,
                border: Border.all(
                  color: currentState.activeViewers > 0
                      ? colors.success.withValues(alpha: 0.3)
                      : colors.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.users,
                    size: 14,
                    color: currentState.activeViewers > 0
                        ? colors.success
                        : colors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    currentState.activeViewers > 0
                        ? '${currentState.activeViewers} $viewerLabel${currentState.activeViewers == 1 ? '' : 's'} connected'
                        : 'No viewers connected',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize13,
                      color: currentState.activeViewers > 0
                          ? colors.success
                          : colors.textMuted,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusInline8,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: NightshadeTypography.labelStrongSm.copyWith(color: colors.textMuted),
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
                        style: NightshadeTypography.labelSm.copyWith(color: colors.primary),
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
