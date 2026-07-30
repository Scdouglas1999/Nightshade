import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalogs/catalog_manager.dart';
import '../catalogs/deep_star_store.dart';
import '../catalogs/deep_star_tile.dart';
import '../celestial_object.dart';
import 'planetarium_providers.dart';

// ============================================================================
// Deep-star tier — downloadable Tycho-2 / Gaia subset below the HYG floor
// ============================================================================

/// FOV (degrees) below which the deep-star tier is consulted.
///
/// The HYG path already saturates at wide fields (the renderer caps to
/// `maxStarsToRender`), so loading deep tiles only pays off once the user has
/// zoomed in enough that the bright stars no longer fill the view. This is also
/// the threshold below which [CelestialSpatialIndex] switches to the cheap
/// grid-cell query, so the deep tier comes online exactly when per-frame work
/// is cheapest.
const double kDeepStarFovThresholdDegrees = 8.0;

/// The bundled HYG catalog's faint floor. Deep-tier stars at or brighter than
/// this are already drawn by the HYG path, so the store is asked to exclude
/// them (it merges magnitude-sorted, so this is the hand-off seam).
const double kHygFaintFloorMag = 11.5;

/// Whether the deep-star tier is enabled for rendering. Off by default — it
/// only does anything once a tileset has been downloaded, and even then a user
/// may prefer the lighter HYG-only view.
final showDeepStarsProvider = StateProvider<bool>((ref) => false);

/// Process-wide store over the installed tileset directory. A [Provider] (not
/// recreated per query) so the decoded-tile LRU survives panning.
final deepStarStoreProvider = Provider<DeepStarTileStore>((ref) {
  final dir = CatalogManager.instance.isInitialized
      ? '${CatalogManager.instance.catalogDirectory}/deep_stars'
      : 'deep_stars';
  return DeepStarTileStore(directory: dir);
});

/// Loads (or reloads) the installed tileset manifest. Returns null when no
/// deep-star tileset is installed. Bumping [deepStarManifestRefreshProvider]
/// forces a reload after a download/delete.
final deepStarManifestProvider = FutureProvider<DeepStarManifest?>((ref) async {
  ref.watch(deepStarManifestRefreshProvider);
  final store = ref.watch(deepStarStoreProvider);
  final ok = await store.loadManifest();
  return ok ? store.manifest : null;
});

/// Increment to force [deepStarManifestProvider] to re-read from disk (after a
/// download completes or the tileset is deleted).
final deepStarManifestRefreshProvider = StateProvider<int>((ref) => 0);

/// Deep-tier stars intersecting the current viewport, fainter than the HYG
/// floor, brightest-first and capped to the same render budget as the HYG path.
///
/// Empty unless: (a) the tier is toggled on, (b) a tileset is installed, and
/// (c) the FOV is below [kDeepStarFovThresholdDegrees]. The result is merged
/// with [fovFilteredStarsProvider] by [combinedStarsProvider] so the renderer's
/// existing star path draws them with the identical style and respects the
/// active magnitude/label settings.
final deepStarsInViewProvider = FutureProvider<List<Star>>((ref) async {
  if (!ref.watch(showDeepStarsProvider)) return const [];

  final fov = ref.watch(skyViewStateProvider.select((s) => s.fieldOfView));
  if (fov >= kDeepStarFovThresholdDegrees) return const [];

  final manifest = await ref.watch(deepStarManifestProvider.future);
  if (manifest == null) return const [];

  final store = ref.watch(deepStarStoreProvider);
  final (starMagLimit, _) = ref.watch(dynamicMagnitudeLimitsProvider);
  // Don't out-draw the HYG budget: the deep tier shares the renderer's cap.
  final maxStars = ref.watch(fovAdaptiveQualityProvider).maxStarsToRender;
  // Tiles are indexed by RA/Dec, so the alt/az frame must be converted first
  // (see [viewCenterEquatorialProvider]).
  final (centerRa, centerDec) = ref.watch(viewCenterEquatorialProvider);
  final aspect = ref.watch(skyViewAspectRatioProvider);

  try {
    return await store.queryBrightest(
      centerRa,
      centerDec,
      fov,
      maxMagnitude: starMagLimit,
      // Hand off at the HYG floor so the two tiers never double-draw a star.
      minMagnitude: kHygFaintFloorMag,
      maxResults: maxStars,
      aspectRatio: aspect,
    );
  } catch (e) {
    developer.log(
      '[DeepStar] query failed: $e',
      name: 'DeepStarProviders',
      level: 900,
      error: e,
    );
    return const [];
  }
});

/// The HYG stars plus any in-view deep-tier stars — the single list the sky
/// view renders. When the deep tier is off / not installed / zoomed out, this
/// is exactly the HYG result, so the wide-field path is unchanged.
final combinedStarsProvider = Provider<AsyncValue<List<Star>>>((ref) {
  final hyg = ref.watch(fovFilteredStarsProvider);
  final deep = ref.watch(deepStarsInViewProvider);

  return hyg.whenData((hygStars) {
    final deepStars = deep.valueOrNull;
    if (deepStars == null || deepStars.isEmpty) return hygStars;
    return [...hygStars, ...deepStars];
  });
});
