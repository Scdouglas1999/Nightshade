import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'region_detail_screen.dart';
import 'sky_atlas_format.dart';
import 'widgets/atlas_coverage_overlay.dart';
import 'widgets/atlas_region_card.dart';
import 'widgets/name_region_sheet.dart';

/// Pillar A ("Your Sky") — the personal growing all-sky atlas.
///
/// A top-level shell destination that shows the regions the observer has imaged
/// as deep, co-added previews, the atlas-wide growth ("4h deeper than
/// yesterday"), and a coverage heat summary. Tapping a region opens the
/// [RegionDetailScreen] with its co-added cutout and a time-scrub control.
///
/// Reads exclusively through [skyAtlasServiceProvider] and its read providers,
/// so the screen works unchanged on the desktop `FfiBackend` and the mobile
/// `NetworkBackend` (the latter resolving the same calls over the headless
/// `/api/atlas/*` routes).
class YourSkyScreen extends StatelessWidget {
  const YourSkyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: const SafeArea(
        bottom: false,
        child: YourSkyView(),
      ),
    );
  }
}

/// Scaffold-free body so the atlas can also be embedded (e.g. a dashboard tab).
class YourSkyView extends ConsumerWidget {
  const YourSkyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final regionsAsync = ref.watch(skyAtlasRegionsProvider);
    final coverageAsync = ref.watch(skyAtlasCoverageProvider);
    // HOST-ONLY: "Name a region" writes the local atlas DB. The atlas is owned
    // by the host; a NetworkBackend companion only mirrors it, so the manual
    // create control is hidden on a slave (auto-attach-on-fold also runs only
    // on the host).
    final canManageRegions = ref.watch(backendProvider) is! NetworkBackend;

    return Column(
      children: [
        ScreenHeader(
          title: 'Your Sky',
          subtitle:
              'Every photon you capture becomes a brick in your growing all-sky atlas.',
          icon: LucideIcons.orbit,
          trailing: IconButton(
            icon: const Icon(NightshadeIcons.refresh,
                size: NightshadeTokens.iconMd),
            tooltip: 'Refresh atlas',
            color: colors.textSecondary,
            constraints: const BoxConstraints(
              minWidth: NightshadeTokens.minTouchTarget,
              minHeight: NightshadeTokens.minTouchTarget,
            ),
            onPressed: () {
              ref.invalidate(skyAtlasRegionsProvider);
              ref.invalidate(skyAtlasCoverageProvider);
            },
          ),
        ),
        Expanded(
          child: regionsAsync.when(
            data: (regions) => _buildBody(
              context,
              ref,
              regions,
              coverageAsync,
              canManageRegions,
            ),
            loading: _buildLoading,
            error: (error, _) => _buildError(ref, error),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<SkyAtlasRegionRow> regions,
    AsyncValue<List<AtlasTileCoverage>> coverageAsync,
    bool canManageRegions,
  ) {
    final coverage = coverageAsync.valueOrNull ?? const <AtlasTileCoverage>[];

    if (regions.isEmpty && coverage.isEmpty) {
      return _buildEmpty();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < NightshadeTokens.breakpointTablet;
        final padding = isMobile
            ? NightshadeTokens.screenPaddingCompact
            : NightshadeTokens.screenPadding;
        // Two-up region grid on wide layouts, single column on phones.
        final columns = constraints.maxWidth >= 1100
            ? 3
            : constraints.maxWidth >= NightshadeTokens.breakpointTablet
                ? 2
                : 1;

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(skyAtlasRegionsProvider);
            ref.invalidate(skyAtlasCoverageProvider);
            await ref.read(skyAtlasCoverageProvider.future);
          },
          child: ListView(
            padding: padding,
            children: [
              AtlasCoverageOverlay(coverage: coverage),
              const SizedBox(height: NightshadeTokens.spaceLg),
              SectionHeader(
                title: 'Regions',
                subtitle: regions.isEmpty
                    ? 'Tiles are accumulating — name a region to track its depth.'
                    : '${regions.length} region${regions.length == 1 ? '' : 's'} imaged',
                trailing: canManageRegions
                    ? NightshadeButton(
                        label: 'Name a region',
                        icon: LucideIcons.plus,
                        variant: ButtonVariant.ghost,
                        size: ButtonSize.small,
                        onPressed: () => NameRegionSheet.show(context),
                      )
                    : null,
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              if (regions.isEmpty)
                _buildNoRegionsHint(context, canManageRegions)
              else
                _RegionGrid(
                  regions: regions,
                  columns: columns,
                  onOpen: (region) => _openRegion(context, region),
                ),
              const SizedBox(height: NightshadeTokens.spaceLg),
            ],
          ),
        );
      },
    );
  }

  void _openRegion(BuildContext context, SkyAtlasRegionRow region) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RegionDetailScreen(regionId: region.id),
      ),
    );
  }

  Widget _buildNoRegionsHint(BuildContext context, bool canManageRegions) {
    final colors = NightshadeColors.of(context);
    return NightshadeCard(
      variant: CardVariant.subtle,
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
                decoration: NightshadeDecorations.tintedBadge(colors.info),
                child: Icon(LucideIcons.info,
                    size: NightshadeTokens.iconSm, color: colors.info),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Text(
                  canManageRegions
                      ? 'Your atlas is filling in tile by tile. Image a target '
                          'and it becomes a named region automatically — or '
                          'name one yourself (a target, mosaic, or polar field) '
                          'to track its depth and scrub it through time.'
                      : 'Your atlas is filling in tile by tile. Regions appear '
                          'here automatically as your host images targets.',
                  style: NightshadeTypography.caption.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (canManageRegions) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            Align(
              alignment: Alignment.centerLeft,
              child: NightshadeButton(
                label: 'Name a region',
                icon: LucideIcons.plus,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () => NameRegionSheet.show(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      // ListView so the empty state is still pull-to-refreshable in context.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: NightshadeTokens.screenPadding,
      children: const [
        SizedBox(height: NightshadeTokens.spaceXl),
        EmptyState(
          icon: LucideIcons.orbit,
          title: 'Your sky is dark — for now',
          body: 'Image and plate-solve a target and it folds into Your Sky '
              'automatically. Each frame deepens a permanent tile you can '
              'revisit and scrub through time.',
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return ShimmerLoading(
      child: ListView(
        padding: NightshadeTokens.screenPadding,
        children: const [
          SkeletonBox(
              width: double.infinity,
              height: 96,
              borderRadius: NightshadeTokens.radiusLg),
          SizedBox(height: NightshadeTokens.spaceLg),
          SkeletonBox(width: 140, height: 18),
          SizedBox(height: NightshadeTokens.spaceMd),
          SkeletonBox(
              width: double.infinity,
              height: 180,
              borderRadius: NightshadeTokens.radiusLg),
          SizedBox(height: NightshadeTokens.spaceMd),
          SkeletonBox(
              width: double.infinity,
              height: 180,
              borderRadius: NightshadeTokens.radiusLg),
        ],
      ),
    );
  }

  Widget _buildError(WidgetRef ref, Object error) {
    return EmptyState(
      icon: LucideIcons.alertCircle,
      title: 'Could not load your atlas',
      body: describeAtlasError(error),
      action: NightshadeButton(
        label: 'Retry',
        icon: NightshadeIcons.refresh,
        onPressed: () {
          ref.invalidate(skyAtlasRegionsProvider);
          ref.invalidate(skyAtlasCoverageProvider);
        },
      ),
    );
  }
}

/// Responsive region grid. Uses a [Wrap]-free column/row layout so the cards
/// keep an intrinsic height (cover preview + growth stats) without the fixed
/// aspect ratio a [GridView] would impose.
class _RegionGrid extends StatelessWidget {
  final List<SkyAtlasRegionRow> regions;
  final int columns;
  final ValueChanged<SkyAtlasRegionRow> onOpen;

  const _RegionGrid({
    required this.regions,
    required this.columns,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (columns <= 1) {
      return Column(
        children: [
          for (final region in regions)
            Padding(
              padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
              child: AtlasRegionCard(
                region: region,
                onTap: () => onOpen(region),
              ),
            ),
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < regions.length; i += columns) {
      final rowChildren = <Widget>[];
      for (var c = 0; c < columns; c++) {
        final index = i + c;
        if (c > 0) {
          rowChildren.add(const SizedBox(width: NightshadeTokens.spaceMd));
        }
        rowChildren.add(
          Expanded(
            child: index < regions.length
                ? AtlasRegionCard(
                    region: regions[index],
                    onTap: () => onOpen(regions[index]),
                  )
                : const SizedBox.shrink(),
          ),
        );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rowChildren,
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}
