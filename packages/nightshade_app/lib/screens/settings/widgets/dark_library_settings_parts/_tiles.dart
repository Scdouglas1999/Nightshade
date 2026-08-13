// Part of ../dark_library_settings.dart -- extracted for maintainability.
//
// Stat cards, action buttons and dark-library group/entry tiles.
part of '../dark_library_settings.dart';

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Expanded(
      child: NightshadeCard(
        variant: CardVariant.standard,
        borderRadius: NightshadeTokens.radiusInline8,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, size: 20, color: colors.primary),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isDanger;
  final bool isLoading;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.isDanger = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: NightshadeButton(
        onPressed: onPressed,
        icon: icon,
        label: label,
        variant: isDanger ? ButtonVariant.destructive : ButtonVariant.outline,
        isLoading: isLoading,
      ),
    );
  }
}

class _DarkGroupTile extends StatelessWidget {
  final DarkGroupKey group;
  final VoidCallback? onCreateMaster;
  final VoidCallback? onDeleteGroup;

  const _DarkGroupTile({
    required this.group,
    required this.onCreateMaster,
    required this.onDeleteGroup,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isD = group.frameType == 'dark';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: NightshadeCard(
        variant: CardVariant.standard,
        borderRadius: NightshadeTokens.radiusInline8,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isD ? LucideIcons.moon : LucideIcons.zap,
              size: 18,
              color: isD ? colors.primary : colors.warning,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${group.frameType.toUpperCase()} - ${group.exposureTime}s',
                    style: NightshadeTypography.labelStrong
                        .copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Gain ${group.gain} | Offset ${group.offset} | '
                    '${group.binX}x${group.binY}',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(LucideIcons.layers, size: 16, color: colors.primary),
              tooltip: 'Create master dark',
              onPressed: onCreateMaster,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(LucideIcons.trash2, size: 16, color: colors.error),
              tooltip: 'Delete group',
              onPressed: onDeleteGroup,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkEntryTile extends StatelessWidget {
  final DarkLibraryEntry entry;

  /// Whether the download affordance is rendered at all (remote host only).
  final bool downloadable;
  final bool isDownloading;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  const _DarkEntryTile({
    required this.entry,
    this.downloadable = false,
    this.isDownloading = false,
    this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isMaster = entry.masterDarkPath != null;
    final isDark = entry.frameType == 'dark';

    // Extract just the filename from the path
    final fileName = entry.filePath.split('/').last.split('\\').last;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMaster
            ? NightshadeDecorations.tintedBadge(
                colors.primary,
                borderRadius: BorderRadius.zero,
              ).color
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isMaster
                ? LucideIcons.layers
                : isDark
                    ? LucideIcons.moon
                    : LucideIcons.zap,
            size: 14,
            color: isMaster
                ? colors.primary
                : isDark
                    ? colors.textSecondary
                    : colors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMaster ? 'MASTER: $fileName' : fileName,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    fontWeight: isMaster ? FontWeight.w600 : FontWeight.w400,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${entry.exposureTime}s | '
                  'Gain ${entry.gain} | '
                  '${entry.binX}x${entry.binY}'
                  '${entry.temperature != null ? ' | ${entry.temperature!.toStringAsFixed(1)}\u00b0C' : ''}'
                  '${isMaster ? ' | ${entry.masterFrameCount} frames' : ''}',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textMuted),
                ),
              ],
            ),
          ),
          if (downloadable) ...[
            isDownloading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: Icon(
                      LucideIcons.download,
                      size: 14,
                      color: colors.textSecondary,
                    ),
                    onPressed: onDownload,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Download to this device',
                  ),
            const SizedBox(width: 10),
          ],
          IconButton(
            icon: Icon(LucideIcons.trash2, size: 14, color: colors.error),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Delete entry',
          ),
        ],
      ),
    );
  }
}
