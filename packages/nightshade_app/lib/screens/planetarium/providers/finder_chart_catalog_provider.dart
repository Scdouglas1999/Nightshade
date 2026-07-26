import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

typedef FinderChartCatalogSnapshot = ({
  List<Star> stars,
  List<DeepSkyObject> dsos,
});

/// The exact viewport catalog snapshot used by finder-chart exports.
///
/// Rendering can legitimately show an empty frame while catalogs load, but an
/// exported PDF is a durable artifact: it must wait for both spatial indexes
/// and preserve load failures instead of treating them as empty catalogs.
final finderChartCatalogSnapshotProvider =
    FutureProvider.autoDispose<FinderChartCatalogSnapshot>((ref) async {
  var starsAsync = ref.watch(fovFilteredStarsProvider);
  var dsosAsync = ref.watch(fovFilteredDsosProvider);

  _throwCatalogError(starsAsync, 'star');
  _throwCatalogError(dsosAsync, 'deep-sky object');

  if (!starsAsync.hasValue || !dsosAsync.hasValue) {
    await Future.wait([
      ref.read(starSpatialIndexProvider.future),
      ref.read(dsoSpatialIndexProvider.future),
    ]);
    starsAsync = ref.read(fovFilteredStarsProvider);
    dsosAsync = ref.read(fovFilteredDsosProvider);
    _throwCatalogError(starsAsync, 'star');
    _throwCatalogError(dsosAsync, 'deep-sky object');
  }

  if (!starsAsync.hasValue || !dsosAsync.hasValue) {
    throw StateError('Finder-chart catalogs did not finish loading.');
  }

  return (
    stars: List<Star>.unmodifiable(starsAsync.requireValue),
    dsos: List<DeepSkyObject>.unmodifiable(dsosAsync.requireValue),
  );
});

void _throwCatalogError(AsyncValue<Object?> source, String label) {
  final error = source.error;
  if (!source.hasError || error == null) return;
  Error.throwWithStackTrace(
    StateError('Could not load the $label catalog: $error'),
    source.stackTrace ?? StackTrace.current,
  );
}
