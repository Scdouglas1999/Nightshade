import 'package:nightshade_bridge/nightshade_bridge.dart';

/// Dart-side render configuration (visibility toggles + quality).
///
/// Defaults match [`RenderConfig::default`](native/nightshade_native/planetarium/src/types.rs).
class RenderConfigState {
  const RenderConfigState({
    this.showStars = true,
    this.showConstellations = true,
    this.showConstellationBoundaries = false,
    this.showConstellationArt = false,
    this.showEquatorialGrid = false,
    this.showAltAzGrid = false,
    this.showGalacticGrid = false,
    this.showEcliptic = true,
    this.showGalacticPlane = false,
    this.showMilkyWay = true,
    this.showHorizon = true,
    this.showAtmosphere = true,
    this.showDsos = true,
    this.showSolarSystem = true,
    this.showSatellites = false,
    this.showMinorPlanets = false,
    this.showVariableStars = false,
    // Wide-field user baseline; v2 LOD pushes higher (toward the catalog
    // ceiling at narrow FOV). 6.0 was naked-eye-only and made the sky
    // look empty out of the box. Kept in sync with the Rust default at
    // `native/nightshade_native/planetarium/src/types.rs::RenderConfig::default`.
    this.magnitudeLimit = 11.0,
    this.quality = 1,
    this.bortleClass = 4,
    this.twinkle = true,
  });

  final bool showStars;
  final bool showConstellations;
  final bool showConstellationBoundaries;
  final bool showConstellationArt;
  final bool showEquatorialGrid;
  final bool showAltAzGrid;
  final bool showGalacticGrid;
  final bool showEcliptic;
  final bool showGalacticPlane;
  final bool showMilkyWay;
  final bool showHorizon;
  final bool showAtmosphere;
  final bool showDsos;
  final bool showSolarSystem;
  final bool showSatellites;
  final bool showMinorPlanets;
  final bool showVariableStars;
  final double magnitudeLimit;
  final int quality;
  final int bortleClass;
  final bool twinkle;

  RenderConfigState copyWith({
    bool? showStars,
    bool? showConstellations,
    bool? showConstellationBoundaries,
    bool? showConstellationArt,
    bool? showEquatorialGrid,
    bool? showAltAzGrid,
    bool? showGalacticGrid,
    bool? showEcliptic,
    bool? showGalacticPlane,
    bool? showMilkyWay,
    bool? showHorizon,
    bool? showAtmosphere,
    bool? showDsos,
    bool? showSolarSystem,
    bool? showSatellites,
    bool? showMinorPlanets,
    bool? showVariableStars,
    double? magnitudeLimit,
    int? quality,
    int? bortleClass,
    bool? twinkle,
  }) {
    return RenderConfigState(
      showStars: showStars ?? this.showStars,
      showConstellations: showConstellations ?? this.showConstellations,
      showConstellationBoundaries:
          showConstellationBoundaries ?? this.showConstellationBoundaries,
      showConstellationArt: showConstellationArt ?? this.showConstellationArt,
      showEquatorialGrid: showEquatorialGrid ?? this.showEquatorialGrid,
      showAltAzGrid: showAltAzGrid ?? this.showAltAzGrid,
      showGalacticGrid: showGalacticGrid ?? this.showGalacticGrid,
      showEcliptic: showEcliptic ?? this.showEcliptic,
      showGalacticPlane: showGalacticPlane ?? this.showGalacticPlane,
      showMilkyWay: showMilkyWay ?? this.showMilkyWay,
      showHorizon: showHorizon ?? this.showHorizon,
      showAtmosphere: showAtmosphere ?? this.showAtmosphere,
      showDsos: showDsos ?? this.showDsos,
      showSolarSystem: showSolarSystem ?? this.showSolarSystem,
      showSatellites: showSatellites ?? this.showSatellites,
      showMinorPlanets: showMinorPlanets ?? this.showMinorPlanets,
      showVariableStars: showVariableStars ?? this.showVariableStars,
      magnitudeLimit: magnitudeLimit ?? this.magnitudeLimit,
      quality: quality ?? this.quality,
      bortleClass: bortleClass ?? this.bortleClass,
      twinkle: twinkle ?? this.twinkle,
    );
  }

  RenderConfigDto toDto() {
    return RenderConfigDto(
      showStars: showStars,
      showConstellations: showConstellations,
      showConstellationBoundaries: showConstellationBoundaries,
      showConstellationArt: showConstellationArt,
      showEquatorialGrid: showEquatorialGrid,
      showAltAzGrid: showAltAzGrid,
      showGalacticGrid: showGalacticGrid,
      showEcliptic: showEcliptic,
      showGalacticPlane: showGalacticPlane,
      showMilkyWay: showMilkyWay,
      showHorizon: showHorizon,
      showAtmosphere: showAtmosphere,
      showDsos: showDsos,
      showSolarSystem: showSolarSystem,
      showSatellites: showSatellites,
      showMinorPlanets: showMinorPlanets,
      showVariableStars: showVariableStars,
      magnitudeLimit: magnitudeLimit,
      quality: quality,
      bortleClass: bortleClass,
      twinkle: twinkle,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RenderConfigState &&
          showStars == other.showStars &&
          showConstellations == other.showConstellations &&
          showConstellationBoundaries == other.showConstellationBoundaries &&
          showConstellationArt == other.showConstellationArt &&
          showEquatorialGrid == other.showEquatorialGrid &&
          showAltAzGrid == other.showAltAzGrid &&
          showGalacticGrid == other.showGalacticGrid &&
          showEcliptic == other.showEcliptic &&
          showGalacticPlane == other.showGalacticPlane &&
          showMilkyWay == other.showMilkyWay &&
          showHorizon == other.showHorizon &&
          showAtmosphere == other.showAtmosphere &&
          showDsos == other.showDsos &&
          showSolarSystem == other.showSolarSystem &&
          showSatellites == other.showSatellites &&
          showMinorPlanets == other.showMinorPlanets &&
          showVariableStars == other.showVariableStars &&
          magnitudeLimit == other.magnitudeLimit &&
          quality == other.quality &&
          bortleClass == other.bortleClass &&
          twinkle == other.twinkle;

  @override
  int get hashCode => Object.hashAll([
        showStars,
        showConstellations,
        showConstellationBoundaries,
        showConstellationArt,
        showEquatorialGrid,
        showAltAzGrid,
        showGalacticGrid,
        showEcliptic,
        showGalacticPlane,
        showMilkyWay,
        showHorizon,
        showAtmosphere,
        showDsos,
        showSolarSystem,
        showSatellites,
        showMinorPlanets,
        showVariableStars,
        magnitudeLimit,
        quality,
        bortleClass,
        twinkle,
      ]);
}
