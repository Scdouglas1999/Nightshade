part of '../status_bar.dart';

class _WebDashboardButton extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const _WebDashboardButton({required this.colors});

  @override
  ConsumerState<_WebDashboardButton> createState() =>
      _WebDashboardButtonState();
}

class _WebDashboardButtonState extends ConsumerState<_WebDashboardButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final webState = ref.watch(webServerStateProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: webState.isRunning
            ? webState.dashboardAvailable
                ? 'Open local dashboard (${webState.localUrl})'
                : 'Remote access API is running, but the dashboard files are unavailable'
            : 'Remote access is not running',
        child: InkWell(
          onTap: webState.isRunning && webState.dashboardAvailable
              ? () {
                  launchUrl(
                    Uri.parse(webState.localUrl),
                    mode: LaunchMode.externalApplication,
                  );
                }
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
                  LucideIcons.globe,
                  size: 12,
                  color: webState.isRunning && webState.dashboardAvailable
                      ? widget.colors.primary
                      : widget.colors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Dashboard',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: webState.isRunning && webState.dashboardAvailable
                        ? widget.colors.textSecondary
                        : widget.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
