// Part of ../targets_tab.dart -- extracted for maintainability.
//
// Active target campaign list and row widgets.
part of '../targets_tab.dart';

class _ActiveTargetList extends ConsumerWidget {
  final NightshadeColors colors;
  final Sequence sequence;

  const _ActiveTargetList({required this.colors, required this.sequence});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Trust-patch §B: removeNode + reorderTargets both throw
    // SequenceLockedException while running. Disable per-row delete and
    // skip drag-reorders proactively (Flutter's ReorderableListView has
    // no built-in "frozen" mode, so we no-op in onReorder).
    final canEdit = ref.watch(canEditSequenceProvider);
    return ReorderableListView.builder(
      itemCount: sequence.targetHeaders.length,
      buildDefaultDragHandles: canEdit,
      proxyDecorator: (child, index, animation) {
        return Material(
          color: Colors.transparent,
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final target = sequence.targetHeaders[index];
        // Use index-based color matching the chart
        final color = [
          colors.primary,
          colors.accent,
          colors.success,
          colors.warning,
          colors.info
        ][index % 5];

        // Wave 7 — Per-target campaign rollup column visibility is
        // gated by the [campaignRollupSurfaceTargetsTab] setting so
        // operators with clean targets tables can opt out of the
        // extra row.
        final settings = ref.watch(appSettingsProvider).valueOrNull;
        final showCampaign = settings?.campaignRollupSurfaceTargetsTab ?? true;
        return _TargetListItem(
          key: ValueKey(target.id),
          colors: colors,
          target: target,
          color: color,
          index: index,
          showCampaign: showCampaign,
          onDelete: canEdit
              ? () async {
                  // Why: a TargetHeaderNode usually owns a non-trivial
                  // subtree (exposures, autofocus, filter changes), so
                  // route the trash icon through the canonical confirm
                  // helper. Previously this was a silent removeNode call
                  // that could nuke a fully-authored target on a misclick.
                  await confirmAndDeleteSequenceNode(
                    context: context,
                    ref: ref,
                    nodeId: target.id,
                    colors: colors,
                  );
                }
              : null,
        );
      },
      onReorder: (oldIndex, newIndex) {
        if (!canEdit) {
          context.showErrorSnackBar('Cannot reorder while sequence is running');
          return;
        }
        try {
          ref
              .read(currentSequenceProvider.notifier)
              .reorderTargets(oldIndex, newIndex);
        } on CrossParentReorderException catch (e) {
          // Why: the targets list flattens targets across multiple
          // containers, but the editor only knows how to swap siblings.
          // Show the user the actual constraint instead of silently
          // ignoring their drag.
          context.showErrorSnackBar(e.message);
        } on SequenceLockedException catch (e) {
          context.showErrorSnackBar(e.message);
        }
      },
    );
  }
}

class _TargetListItem extends ConsumerWidget {
  final NightshadeColors colors;
  final TargetHeaderNode target;
  final Color color;
  final int index;
  // Null when canEditSequenceProvider == false. The delete control is
  // rendered grayed out in that case (rather than removed) so the user
  // sees what would be available once the sequence stops.
  final VoidCallback? onDelete;

  /// Wave 7 — show the campaign rollup column. Gated by the
  /// `campaignRollupSurfaceTargetsTab` setting.
  final bool showCampaign;

  const _TargetListItem({
    super.key,
    required this.colors,
    required this.target,
    required this.color,
    required this.index,
    required this.onDelete,
    this.showCampaign = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = Responsive.isMobile(context);
    final isVeryNarrow = MediaQuery.sizeOf(context).width < 360;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 16,
          vertical: isMobile ? 6 : 8,
        ),
        leading: Container(
          width: isMobile ? 36 : 40,
          height: isMobile ? 36 : 40,
          decoration: NightshadeDecorations.kpiBadge(color),
          child: Center(
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: isMobile ? 12 : 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        title: Text(
          target.targetName,
          style: TextStyle(
            fontSize: isMobile ? 14 : 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isVeryNarrow
                  ? '${target.raHours.toStringAsFixed(2)}h / ${target.decDegrees.toStringAsFixed(2)}°'
                  : 'RA: ${target.raHours.toStringAsFixed(4)}h  Dec: ${target.decDegrees.toStringAsFixed(4)}°',
              style: TextStyle(
                  color: colors.textSecondary, fontSize: isMobile ? 11 : 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (showCampaign)
              _TargetCampaignColumn(
                targetName: target.targetName,
                colors: colors,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(LucideIcons.trash2,
                  size: isMobile ? 16 : 18, color: colors.error),
              onPressed: onDelete,
              tooltip: 'Remove Target',
              visualDensity:
                  isMobile ? VisualDensity.compact : VisualDensity.standard,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            if (!isVeryNarrow) ...[
              const SizedBox(width: 4),
              Icon(LucideIcons.gripVertical,
                  color: colors.textMuted, size: isMobile ? 18 : 20),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wave 7 — Per-target campaign rollup row shown in the Scheduled
/// Targets list. Renders one line per filter ("L 24h, Ha 8h")
/// followed by the session count. Silently hides when the target is
/// unknown (target_name has no Drift row) or has no captured frames.
class _TargetCampaignColumn extends ConsumerWidget {
  final String targetName;
  final NightshadeColors colors;

  const _TargetCampaignColumn({
    required this.targetName,
    required this.colors,
  });

  String _formatHours(double seconds) {
    final hours = seconds / 3600.0;
    if (hours >= 10) return '${hours.toStringAsFixed(0)}h';
    return '${hours.toStringAsFixed(1)}h';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rollupAsync = ref.watch(campaignRollupByNameProvider(targetName));
    return rollupAsync.maybeWhen(
      data: (rollup) {
        if (rollup == null) return const SizedBox.shrink();
        if (rollup.totalCapturedIntegrationSecs <= 0) {
          return const SizedBox.shrink();
        }
        final filterBits = rollup.filters
            .where((f) => f.capturedIntegrationSecs > 0)
            .map(
                (f) => '${f.filter} ${_formatHours(f.capturedIntegrationSecs)}')
            .toList(growable: false);
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(LucideIcons.layers, size: 11, color: colors.primary),
              Text(
                'Total ${_formatHours(rollup.totalCapturedIntegrationSecs)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
              if (filterBits.isNotEmpty)
                Text(
                  '• ${filterBits.join(', ')}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
              Text(
                '• ${rollup.sessionCount} session'
                '${rollup.sessionCount == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
