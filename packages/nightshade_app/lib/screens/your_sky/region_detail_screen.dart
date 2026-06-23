import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'sky_atlas_format.dart';
import 'widgets/atlas_region_cutout.dart';
import 'widgets/atlas_timescrub.dart';

/// The scrub anchor for the open region detail (null = latest / all folds).
final _scrubAnchorProvider =
    StateProvider.autoDispose<DateTime?>((ref) => null);

/// Region detail — the co-added cutout for a region with a time-scrub control
/// that replays how the region grew, the contributing folds, and provenance.
///
/// Backend-agnostic: every read flows through the backend-aware atlas families
/// ([atlasRegionProvider] / [atlasRegionTilesProvider] /
/// [atlasRegionTimelineProvider] / [atlasRegionCutoutProvider]), so the screen
/// renders identically on the desktop FFI backend AND a mobile network backend
/// companion — which reads the host's `/api/atlas/region/<id>[...]` routes
/// instead of its empty local atlas DB.
class RegionDetailScreen extends ConsumerWidget {
  final int regionId;

  const RegionDetailScreen({super.key, required this.regionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final regionAsync = ref.watch(atlasRegionProvider(regionId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon:
              const Icon(LucideIcons.arrowLeft, size: NightshadeTokens.iconMd),
          color: colors.textPrimary,
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          regionAsync.valueOrNull?.name ?? 'Region',
          style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
        ),
      ),
      body: SafeArea(
        top: false,
        child: regionAsync.when(
          data: (region) => region == null
              ? _missing(colors)
              : _RegionDetailBody(region: region),
          loading: () => const Center(
            child: NightshadeCircularProgress(
              value: 0,
              indeterminate: true,
              size: NightshadeTokens.iconXl,
            ),
          ),
          error: (error, _) => EmptyState(
            icon: LucideIcons.alertCircle,
            title: 'Could not load region',
            body: describeAtlasError(error),
          ),
        ),
      ),
    );
  }

  Widget _missing(NightshadeColors colors) => const EmptyState(
        icon: LucideIcons.searchX,
        title: 'Region not found',
        body: 'This region may have been removed since the gallery loaded.',
      );
}

class _RegionDetailBody extends ConsumerWidget {
  final SkyAtlasRegionRow region;

  const _RegionDetailBody({required this.region});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tilesAsync = ref.watch(atlasRegionTilesProvider(region.id));
    final timelineAsync = ref.watch(atlasRegionTimelineProvider(region.id));
    final anchor = ref.watch(_scrubAnchorProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < NightshadeTokens.breakpointTablet;
        final padding = isMobile
            ? NightshadeTokens.screenPaddingCompact
            : NightshadeTokens.screenPadding;

        final tiles = tilesAsync.valueOrNull ?? const <SkyTileRow>[];
        final folds = timelineAsync.valueOrNull ?? const <SkyAtlasFoldRow>[];

        return ListView(
          padding: padding,
          children: [
            _CutoutPanel(
              region: region,
              folds: folds,
              anchor: anchor,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            _ScrubPanel(
              regionId: region.id,
              folds: folds,
              anchor: anchor,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            _ChangedPanel(folds: folds, anchor: anchor),
            const SizedBox(height: NightshadeTokens.spaceLg),
            _ProvenancePanel(region: region, tiles: tiles, folds: folds),
            const SizedBox(height: NightshadeTokens.spaceLg),
          ],
        );
      },
    );
  }
}

/// The co-added region cutout — ALWAYS the latest depth (the portable cone
/// co-add the host renders), never a per-pixel time machine the engine refuses.
///
/// HONEST SCRUB: the scrub anchor does NOT drive the cutout image. The native
/// `tilePng(asOf:)` raises whenever any fold is after the anchor (an honest
/// refusal), which previously painted a broken-image icon over an "as of
/// `<date>`" badge on every past scrub stop. Here the cutout fetches latest
/// only, and an honest line under it states "Showing latest depth — N of M
/// sessions by `<date>`" so the slider clearly scrubs the FRAME LIST + growth
/// below, not the hero image.
class _CutoutPanel extends StatelessWidget {
  final SkyAtlasRegionRow region;
  final List<SkyAtlasFoldRow> folds;
  final DateTime? anchor;

  const _CutoutPanel({
    required this.region,
    required this.folds,
    required this.anchor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    // Session counts by the scrub point: distinct fold days at/before the anchor
    // out of all distinct fold days. Drives the honest depth line.
    String dayKey(DateTime d) {
      final u = d.toUtc();
      return '${u.year}-${u.month}-${u.day}';
    }

    final allDays = <String>{for (final f in folds) dayKey(f.foldedAt)};
    final shownDays = <String>{
      for (final f in folds)
        if (anchor == null || !f.foldedAt.toUtc().isAfter(anchor!.toUtc()))
          dayKey(f.foldedAt),
    };

    return NightshadeCard(
      padding: EdgeInsets.zero,
      borderRadius: NightshadeTokens.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(NightshadeTokens.radiusLg),
            ),
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: folds.isEmpty
                  ? Container(
                      color: colors.surfaceAlt,
                      alignment: Alignment.center,
                      child: Icon(LucideIcons.orbit,
                          size: NightshadeTokens.iconXl,
                          color: colors.textMuted),
                    )
                  : AtlasRegionCutout(regionId: region.id, fit: BoxFit.cover),
            ),
          ),
          Padding(
            padding: NightshadeTokens.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.mapPin,
                        size: NightshadeTokens.iconSm,
                        color: colors.textSecondary),
                    const SizedBox(width: NightshadeTokens.spaceSm),
                    Expanded(
                      child: Text(
                        '${formatCenter(region.centerRaDeg, region.centerDecDeg)}'
                        '  ·  r ${region.radiusDeg.toStringAsFixed(2)}°',
                        style: NightshadeTypography.monoSm
                            .copyWith(color: colors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (allDays.isNotEmpty) ...[
                  const SizedBox(height: NightshadeTokens.spaceXs),
                  Text(
                    anchor == null
                        ? 'Showing latest depth — all ${allDays.length} '
                            'session${allDays.length == 1 ? '' : 's'}.'
                        : 'Showing latest depth — ${shownDays.length} of '
                            '${allDays.length} sessions by ${_dateLabel(anchor!)}.',
                    style: NightshadeTypography.captionSm
                        .copyWith(color: colors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _dateLabel(DateTime instant) {
    final utc = instant.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }
}

class _ScrubPanel extends ConsumerWidget {
  final int regionId;
  final List<SkyAtlasFoldRow> folds;
  final DateTime? anchor;

  const _ScrubPanel({
    required this.regionId,
    required this.folds,
    required this.anchor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final stops = scrubStopsFromFolds(folds);

    return NightshadeCard(
      padding: NightshadeTokens.cardPadding,
      child: stops.length < 2
          ? Row(
              children: [
                Icon(LucideIcons.history,
                    size: NightshadeTokens.iconSm, color: colors.textMuted),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Expanded(
                  child: Text(
                    'Image this region across more nights to scrub it through '
                    'time.',
                    style: NightshadeTypography.caption
                        .copyWith(color: colors.textMuted, height: 1.4),
                  ),
                ),
              ],
            )
          : AtlasTimescrub(
              stops: stops,
              selected: anchor,
              onChanged: (instant) {
                ref.read(_scrubAnchorProvider.notifier).state = instant;
              },
            ),
    );
  }
}

/// "What changed" — the folds active at the current scrub anchor, newest first,
/// each summarising the frames + integration it added (seeds Pillar B's
/// discovery view).
class _ChangedPanel extends StatelessWidget {
  final List<SkyAtlasFoldRow> folds;
  final DateTime? anchor;

  const _ChangedPanel({required this.folds, required this.anchor});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final visible = [
      for (final fold in folds)
        if (anchor == null || !fold.foldedAt.toUtc().isAfter(anchor!.toUtc()))
          fold,
    ]..sort((a, b) => b.foldedAt.compareTo(a.foldedAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Contributing frames',
          subtitle: anchor == null
              ? 'Every session that has deepened this region.'
              : 'Sessions up to the scrub point.',
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        if (visible.isEmpty)
          NightshadeCard(
            variant: CardVariant.subtle,
            padding: NightshadeTokens.cardPadding,
            child: Text(
              'No folds at this point in time.',
              style: NightshadeTypography.caption
                  .copyWith(color: colors.textMuted),
            ),
          )
        else
          for (var i = 0; i < visible.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == visible.length - 1 ? 0 : NightshadeTokens.spaceSm,
              ),
              child: _FoldRow(fold: visible[i]),
            ),
      ],
    );
  }
}

class _FoldRow extends StatelessWidget {
  final SkyAtlasFoldRow fold;

  const _FoldRow({required this.fold});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isSwarm = fold.contributor.isNotEmpty;
    final tint = isSwarm ? colors.info : colors.primary;

    return NightshadeCard(
      variant: CardVariant.subtle,
      padding: NightshadeTokens.cardPadding,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
            decoration: NightshadeDecorations.tintedBadge(tint),
            child: Icon(
              isSwarm ? LucideIcons.users : LucideIcons.image,
              size: NightshadeTokens.iconSm,
              color: tint,
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label(fold),
                  style: NightshadeTypography.bodySm
                      .copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: NightshadeTokens.spaceXs),
                Text(
                  '${fold.framesAdded} frame${fold.framesAdded == 1 ? '' : 's'}'
                  '  ·  +${formatIntegration(fold.integrationSecondsAdded)}'
                  '  ·  tile ${fold.tileId}'
                  '${fold.rejected > 0 ? '  ·  ${fold.rejected} rejected' : ''}',
                  style: NightshadeTypography.captionSm
                      .copyWith(color: colors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _label(SkyAtlasFoldRow fold) {
    if (fold.label.trim().isNotEmpty) return fold.label.trim();
    final utc = fold.foldedAt.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')} fold';
  }
}

/// Provenance rollup — depth, contributors, and the running totals for the
/// region across its tiles.
class _ProvenancePanel extends StatelessWidget {
  final SkyAtlasRegionRow region;
  final List<SkyTileRow> tiles;
  final List<SkyAtlasFoldRow> folds;

  const _ProvenancePanel({
    required this.region,
    required this.tiles,
    required this.folds,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final totalFrames = folds.fold<int>(0, (s, f) => s + f.framesAdded);
    final contributors = <String>{
      for (final f in folds)
        if (f.contributor.trim().isNotEmpty) f.contributor.trim(),
    };
    final maxDepth = tiles.isEmpty
        ? 0.0
        : tiles
            .map((t) => t.integrationSeconds)
            .reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Depth & provenance'),
        const SizedBox(height: NightshadeTokens.spaceSm),
        NightshadeCard(
          padding: NightshadeTokens.cardPadding,
          child: Column(
            children: [
              _StatLine(
                icon: LucideIcons.clock,
                label: 'Total integration',
                value: formatIntegration(region.integrationSeconds),
                colors: colors,
              ),
              _StatLine(
                icon: LucideIcons.layers,
                label: 'Deepest tile',
                value: formatIntegration(maxDepth),
                colors: colors,
              ),
              _StatLine(
                icon: LucideIcons.layoutGrid,
                label: 'Tiles',
                value: '${region.tileCount}',
                colors: colors,
              ),
              _StatLine(
                icon: LucideIcons.image,
                label: 'Frames folded',
                value: '$totalFrames',
                colors: colors,
              ),
              _StatLine(
                icon: LucideIcons.users,
                label: 'Contributors',
                value: contributors.isEmpty ? 'You' : '${contributors.length}',
                colors: colors,
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;
  final bool isLast;

  const _StatLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: isLast ? 0 : NightshadeTokens.spaceMd,
      ),
      child: Row(
        children: [
          Icon(icon,
              size: NightshadeTokens.iconSm, color: colors.textSecondary),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Text(
              label,
              style: NightshadeTypography.bodySm
                  .copyWith(color: colors.textSecondary),
            ),
          ),
          Text(
            value,
            style:
                NightshadeTypography.monoSm.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}
