import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Session-scoped set of readiness items the user has dismissed (✕) from an
/// inline checklist. Reset on app restart so a still-unresolved item reappears
/// next launch — matching the "dismiss for this session" contract. Only honored
/// when [ReadinessPanel.dismissible] is true (the equipment-screen inline
/// panel); the full "View all" dialog ignores it so nothing is ever truly
/// hidden from the authoritative list.
final dismissedReadinessItemsProvider =
    StateProvider<Set<ReadinessItemId>>((ref) => <ReadinessItemId>{});

/// Maps a [ReadinessLevel] onto the design system's semantic colors.
///
/// Resolved through [NightshadeColors] so the red-night palette (where
/// `success`/`warning` collapse to reds) is honored automatically — we never
/// hardcode green/amber here.
Color readinessLevelColor(ReadinessLevel level, NightshadeColors colors) {
  switch (level) {
    case ReadinessLevel.ready:
      return colors.success;
    case ReadinessLevel.caution:
      return colors.warning;
    case ReadinessLevel.blocked:
      return colors.error;
  }
}

/// Maps a [ReadinessLevel] onto a [NightshadeAlertSeverity] for the panel
/// header banner.
NightshadeAlertSeverity readinessLevelAlertSeverity(ReadinessLevel level) {
  switch (level) {
    case ReadinessLevel.ready:
      return NightshadeAlertSeverity.success;
    case ReadinessLevel.caution:
      return NightshadeAlertSeverity.warning;
    case ReadinessLevel.blocked:
      return NightshadeAlertSeverity.error;
  }
}

/// Maps a [ReadinessLevel] onto a [StatusPillStatus]. Used by the readiness
/// chip; exposed here so the chip and panel agree on the mapping.
StatusPillStatus readinessLevelPillStatus(ReadinessLevel level) {
  switch (level) {
    case ReadinessLevel.ready:
      return StatusPillStatus.success;
    case ReadinessLevel.caution:
      return StatusPillStatus.warning;
    case ReadinessLevel.blocked:
      return StatusPillStatus.error;
  }
}

/// Per-item leading icon, keyed off the stable [ReadinessItemId] so the icon is
/// independent of the (localizable) title text.
IconData readinessItemIcon(ReadinessItemId id) {
  switch (id) {
    case ReadinessItemId.criticalDevices:
      return LucideIcons.plug;
    case ReadinessItemId.location:
      return LucideIcons.mapPin;
    case ReadinessItemId.outputPath:
      return LucideIcons.folder;
    case ReadinessItemId.plateSolver:
      return LucideIcons.crosshair;
    case ReadinessItemId.darkLibrary:
      return LucideIcons.layers;
    case ReadinessItemId.focusState:
      return LucideIcons.focus;
  }
}

/// Opens the itemized [ReadinessPanel] in a standard [NightshadeDialog].
///
/// Shared by [ReadinessStatusChip], the dashboard card, and the equipment
/// panel's "View all" overflow button so every entry point presents an
/// identical full checklist. The panel's Fix buttons close this dialog (via
/// [ReadinessPanel.onFixTapped]) after navigating.
Future<void> showReadinessDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => NightshadeDialog(
      title: 'Ready to image',
      icon: LucideIcons.listChecks,
      width: 560,
      child: ReadinessPanel(
        onFixTapped: () => Navigator.of(dialogContext).pop(),
      ),
    ),
  );
}

/// Itemized "ready to image" checklist.
///
/// Renders a [ReadinessReport] as a header banner summarizing the overall
/// state ([NightshadeAlert] with severity per level) followed by one row per
/// [ReadinessItem]: a [StatusDot] colored by level, the item title + detail,
/// and — when the item is not [ReadinessLevel.ready] — a trailing **Fix**
/// button that navigates to [ReadinessItem.fixRoute].
///
/// When [onFixTapped] is supplied it is invoked *after* navigation, so the
/// hosting surface (e.g. a dialog) can close itself. The widget watches
/// [readinessReportProvider] directly so it stays live regardless of where it
/// is mounted.
class ReadinessPanel extends ConsumerWidget {
  /// Invoked after a Fix action navigates. Typically pops the host dialog.
  final VoidCallback? onFixTapped;

  /// When true, the header summary banner is omitted (the host already shows
  /// an equivalent summary — e.g. the equipment-screen panel header).
  final bool showHeader;

  /// When true, only the items that still need action (blocked + caution) are
  /// listed; ready items are hidden. The equipment-screen panel uses this so
  /// the inline checklist stays compact (and cannot overflow a column on a
  /// short phone screen) while still surfacing every actionable item. When the
  /// rig is fully ready, a single "all set" confirmation row is shown instead.
  /// The full-detail dialog (opened from the readiness chip) leaves this false
  /// so it lists every item.
  final bool outstandingOnly;

  /// Caps the number of inline rows. When the (filtered) item list exceeds
  /// this, only the first [maxItems] render and a "View all (N)" button opens
  /// the full [showReadinessDialog]. `null` (the default) renders every row —
  /// used by the full dialog itself, which must not recurse into another
  /// dialog. Bounding the row count keeps an inline host (e.g. the
  /// equipment-screen panel inside a non-scrolling column) from overflowing on
  /// short screens regardless of how many items are outstanding.
  final int? maxItems;

  /// When true, each not-ready row gains a ✕ that adds the item to
  /// [dismissedReadinessItemsProvider] (session-scoped). Dismissed items are
  /// filtered out, and a "Show N dismissed" footer lets the user restore them.
  /// Off by default so the shared dialog/chip usages stay non-dismissable —
  /// only the equipment-screen inline panel opts in.
  final bool dismissible;

  const ReadinessPanel({
    super.key,
    this.onFixTapped,
    this.showHeader = true,
    this.outstandingOnly = false,
    this.maxItems,
    this.dismissible = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final report = ref.watch(readinessReportProvider);

    // In outstanding-only mode, list blocked items first (they gate first
    // light), then caution items; drop the ready ones. Blocked + caution are
    // exactly the rows that carry a Fix action.
    final baseItems = outstandingOnly
        ? [...report.blockedItems, ...report.cautionItems]
        : report.items;

    // Session-dismissed items are filtered out only in dismissible mode. We
    // keep the count so the footer can offer to restore them.
    final dismissed =
        dismissible ? ref.watch(dismissedReadinessItemsProvider) : null;
    final allItems = dismissed == null
        ? baseItems
        : baseItems.where((i) => !dismissed.contains(i.id)).toList();
    final dismissedVisible = baseItems.length - allItems.length;

    final cap = maxItems;
    final overflowing = cap != null && allItems.length > cap;
    final items = overflowing ? allItems.sublist(0, cap) : allItems;
    final hiddenCount = overflowing ? allItems.length - cap : 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          NightshadeAlert(
            title: report.summaryLabel,
            message: _summaryDetail(report),
            severity: readinessLevelAlertSeverity(report.overall),
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
        ],
        // "Ready for first light" only when there is genuinely nothing
        // outstanding — not when the list is empty merely because every row
        // was dismissed (that would falsely claim all checks passed).
        if (outstandingOnly && items.isEmpty && dismissedVisible == 0)
          _AllSetRow(colors: colors)
        else
          for (var i = 0; i < items.length; i++) ...[
            _ReadinessRow(
              item: items[i],
              onFixTapped: onFixTapped,
              onDismiss: dismissible
                  ? () => ref
                      .read(dismissedReadinessItemsProvider.notifier)
                      .update((s) => {...s, items[i].id})
                  : null,
            ),
            if (i != items.length - 1)
              Divider(
                height: NightshadeTokens.spaceLg,
                thickness: 1,
                color: colors.border
                    .withValues(alpha: NightshadeTokens.opacityHalf),
              ),
          ],
        if (hiddenCount > 0) ...[
          const SizedBox(height: NightshadeTokens.spaceMd),
          Align(
            alignment: Alignment.centerLeft,
            child: NightshadeButton(
              label: 'View all ($hiddenCount more)',
              icon: LucideIcons.listChecks,
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
              onPressed: () => showReadinessDialog(context),
            ),
          ),
        ],
        if (dismissedVisible > 0) ...[
          const SizedBox(height: NightshadeTokens.spaceMd),
          Align(
            alignment: Alignment.centerLeft,
            child: NightshadeButton(
              label: 'Show $dismissedVisible dismissed',
              icon: LucideIcons.eye,
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
              onPressed: () => ref
                  .read(dismissedReadinessItemsProvider.notifier)
                  .update((s) {
                final restored = {...s};
                for (final item in baseItems) {
                  restored.remove(item.id);
                }
                return restored;
              }),
            ),
          ),
        ],
      ],
    );
  }

  String _summaryDetail(ReadinessReport report) {
    final blocked = report.blockedItems.length;
    final caution = report.cautionItems.length;
    switch (report.overall) {
      case ReadinessLevel.ready:
        return 'Everything required for first light is in place.';
      case ReadinessLevel.caution:
        return '$caution ${_plural(caution, 'item needs', 'items need')} '
            'attention, but you can still begin imaging.';
      case ReadinessLevel.blocked:
        final parts = <String>[
          if (blocked > 0)
            '$blocked ${_plural(blocked, 'item is', 'items are')} blocking '
                'first light',
          if (caution > 0)
            '$caution ${_plural(caution, 'item needs', 'items need')} '
                'attention',
        ];
        return '${parts.join(' and ')}. Resolve the blocking items below.';
    }
  }

  String _plural(int count, String singular, String plural) =>
      count == 1 ? singular : plural;
}

/// Compact "everything is ready" confirmation row, shown in outstanding-only
/// mode when there is nothing left to fix. Mirrors a [_ReadinessRow] visually
/// (success dot + title + detail) so the panel reads consistently whether or
/// not work remains.
class _AllSetRow extends StatelessWidget {
  final NightshadeColors colors;

  const _AllSetRow({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: NightshadeTokens.spaceXs + 1),
          child: StatusDot(color: colors.success),
        ),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ready for first light',
                style: NightshadeTypography.bodyMedium
                    .copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: NightshadeTokens.spaceXs),
              Text(
                'Every readiness check has passed.',
                style: NightshadeTypography.caption
                    .copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  final ReadinessItem item;
  final VoidCallback? onFixTapped;

  /// When non-null, renders a trailing ✕ that hides this row for the session.
  final VoidCallback? onDismiss;

  const _ReadinessRow({
    required this.item,
    required this.onFixTapped,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final levelColor = readinessLevelColor(item.level, colors);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Optically align the dot with the first text line.
          padding: const EdgeInsets.only(top: NightshadeTokens.spaceXs + 1),
          child: StatusDot(
            color: levelColor,
            variant: item.level == ReadinessLevel.blocked
                ? StatusDotVariant.urgent
                : StatusDotVariant.static,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    readinessItemIcon(item.id),
                    size: NightshadeTokens.iconSm,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Expanded(
                    child: Text(
                      item.title,
                      style: NightshadeTypography.bodyMedium
                          .copyWith(color: colors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NightshadeTokens.spaceXs),
              Text(
                item.detail,
                style: NightshadeTypography.caption
                    .copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
        if (!item.isReady && item.hasFix) ...[
          const SizedBox(width: NightshadeTokens.spaceMd),
          NightshadeButton(
            label: item.fixLabel!,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () {
              context.go(item.fixRoute!);
              onFixTapped?.call();
            },
          ),
        ],
        if (onDismiss != null) ...[
          const SizedBox(width: NightshadeTokens.spaceXs),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(LucideIcons.x, size: NightshadeTokens.iconSm),
            color: colors.textMuted,
            tooltip: 'Dismiss for this session',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ],
    );
  }
}
