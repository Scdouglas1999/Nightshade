/// Screen-space placement for a constellation art overlay.
///
/// Mirrors the future FFI [`ConstellationArtPlacementDto`] (Task 74). Until the
/// native snapshot publishes placements, overlays read an empty list from
/// [SceneSnapshotDto].
class ConstellationArtPlacementDto {
  const ConstellationArtPlacementDto({
    required this.abbreviation,
    required this.screenX,
    required this.screenY,
    this.scale = 1,
    this.opacity = 0.2,
  });

  /// IAU three-letter abbreviation (e.g. `Ori`).
  final String abbreviation;

  /// Projected centroid X in widget coordinates.
  final double screenX;

  /// Projected centroid Y in widget coordinates.
  final double screenY;

  /// Size multiplier relative to the catalog figure.
  final double scale;

  /// Fill/stroke alpha multiplier (0–1).
  final double opacity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationArtPlacementDto &&
          abbreviation == other.abbreviation &&
          screenX == other.screenX &&
          screenY == other.screenY &&
          scale == other.scale &&
          opacity == other.opacity;

  @override
  int get hashCode =>
      Object.hash(abbreviation, screenX, screenY, scale, opacity);
}
