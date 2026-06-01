part of '../planetarium_providers.dart';

// ============================================================================
// Density Hotspots Provider
// ============================================================================

/// Calculates density hotspots for crowded regions when zoomed out.
/// Returns list of (ra, dec, visibleCount, hiddenCount) for areas with many hidden objects.
/// This helps users know when to zoom in to reveal more objects.
final densityHotspotsDataProvider =
    Provider<List<(double, double, int, int)>>((ref) {
  final (starMagLimit, _) = ref.watch(dynamicMagnitudeLimitsProvider);

  // Get all loaded stars (not the filtered ones - we need the full set to count hidden)
  final starsAsync = ref.watch(loadedStarsProvider);
  final stars = starsAsync.valueOrNull ?? [];

  if (stars.isEmpty) return [];

  // Grid the sky into cells and count objects
  const cellSize = 15.0; // degrees
  final Map<String, (int, int)> cells = {}; // visible, hidden counts

  for (final star in stars) {
    // Calculate cell key from RA (hours to degrees) and Dec
    final raDegs = star.coordinates.ra * 15; // Convert hours to degrees
    final decDegs = star.coordinates.dec;

    // Normalize RA to 0-360 range before gridding
    final normalizedRA =
        raDegs < 0 ? raDegs + 360 : (raDegs >= 360 ? raDegs - 360 : raDegs);
    final cellKey =
        '${(normalizedRA ~/ cellSize)}_${((decDegs + 90) ~/ cellSize)}';

    final current = cells[cellKey] ?? (0, 0);
    final starMag = star.magnitude ?? 99;

    if (starMag <= starMagLimit) {
      cells[cellKey] = (current.$1 + 1, current.$2);
    } else {
      cells[cellKey] = (current.$1, current.$2 + 1);
    }
  }

  // Return cells with significant hidden objects (> 30)
  return cells.entries.where((e) => e.value.$2 > 30).map((e) {
    final parts = e.key.split('_');
    final raCellIndex = double.parse(parts[0]);
    final decCellIndex = double.parse(parts[1]);
    // Convert back to center of cell in RA (hours) and Dec (degrees)
    final ra = (raCellIndex * cellSize + cellSize / 2) / 15; // Convert to hours
    final dec = decCellIndex * cellSize -
        90 +
        cellSize / 2; // Convert from shifted index
    return (ra, dec, e.value.$1, e.value.$2);
  }).toList();
});

final densityHotspotsProvider =
    Provider<List<(double, double, int, int)>>((ref) {
  final fieldOfView =
      ref.watch(skyViewStateProvider.select((state) => state.fieldOfView));

  // Only show density indicators when zoomed out (FOV > 30 degrees)
  if (fieldOfView < 30) return [];

  return ref.watch(densityHotspotsDataProvider);
});
