// Catalog overlay service (F5-CATALOG-OVERLAY) — turns a solved WCS into a
// list of catalog objects projected onto the captured frame so the imaging
// preview can label them in real time.
//
// Pipeline:
//   1. SolvedWcs → GnomonicProjection
//   2. Bounding box on the sky (RA / Dec)
//   3. Query the OpenNGC DSO catalog and the HYG star catalog
//   4. Project each survivor through the gnomonic projection
//   5. Sort by magnitude, downsample over `maxObjects` to keep paints cheap
//
// Why separate from the existing `AnnotationService`: that service runs
// the SIMBAD / Hyperleda / annotation-catalog pipeline against the solved
// image AFTER plate-solve and stores the result in the database as part
// of a snapshot. It's optional, slow, and online. This service is a
// purely-local visual overlay you can flip on/off from the preview
// toolbar — no network, no DB write, no annotation snapshot mutation.

import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import 'wcs/gnomonic_projection.dart';

/// Kind of marker to draw — used by the painter to pick the right symbol.
/// Stars get a crosshair, galaxies get an ellipse, clusters / nebulae get
/// type-appropriate symbols.
enum CatalogOverlayKind {
  star,
  galaxy,
  openCluster,
  globularCluster,
  nebula,
  planetaryNebula,
  supernovaRemnant,
  other,
}

/// Single catalog object projected onto an image.
class CatalogOverlayObject {
  /// Display id (e.g. "M31", "NGC 224", "α Lyr"). Always non-empty.
  final String id;

  /// Long human name when available (e.g. "Andromeda Galaxy", "Vega").
  /// Null if the catalog has nothing better than [id].
  final String? commonName;

  /// Comma-joined extra designations for the details panel.
  final String? alternateIds;

  /// Right ascension in hours (J2000).
  final double raHours;

  /// Declination in degrees (J2000).
  final double decDegrees;

  /// V (or B) magnitude when known, null when the catalog row is silent.
  final double? magnitude;

  /// Major-axis size in arcminutes when known (DSO-specific).
  final double? sizeArcMin;

  /// Object kind for marker selection.
  final CatalogOverlayKind kind;

  /// Pixel position on the original (un-zoomed) image. Never NaN.
  final double imageX;
  final double imageY;

  /// Hit-radius for click / hover, in image pixels at zoom 1x.
  final double hitRadius;

  /// Source catalog tag — "Messier" / "NGC" / "IC" / "HYG" / "OpenNGC".
  /// Surfaced in the tooltip so users can verify the data provenance.
  final String source;

  const CatalogOverlayObject({
    required this.id,
    required this.commonName,
    required this.alternateIds,
    required this.raHours,
    required this.decDegrees,
    required this.magnitude,
    required this.sizeArcMin,
    required this.kind,
    required this.imageX,
    required this.imageY,
    required this.hitRadius,
    required this.source,
  });

  /// Best display string for the marker label.
  String get displayName => commonName ?? id;
}

/// Aggregate query result. Carries the projected objects plus stats so the
/// HUD can show "12 of 487 catalog objects visible" without recomputing.
class CatalogOverlayResult {
  /// Objects intersecting the frame after magnitude / count limits.
  final List<CatalogOverlayObject> objects;

  /// Total objects matched in the FOV before [requestedMaxObjects] cap.
  /// `objects.length <= totalInFov` always holds.
  final int totalInFov;

  /// The mag limit actually used (mirrors the request unless clamped).
  final double appliedMagnitudeLimit;

  /// Mag limit at which objects were dropped to satisfy [requestedMaxObjects].
  /// Null when nothing was downsampled.
  final double? downsampleMagnitudeCutoff;

  /// True when the catalog files were available and the query ran.
  /// False indicates the user has not installed the planetarium catalog
  /// yet — the UI should explain that rather than just show nothing.
  final bool catalogAvailable;

  /// Wall-clock duration of the query, for UI HUD diagnostics.
  final Duration queryDuration;

  const CatalogOverlayResult({
    required this.objects,
    required this.totalInFov,
    required this.appliedMagnitudeLimit,
    required this.downsampleMagnitudeCutoff,
    required this.catalogAvailable,
    required this.queryDuration,
  });

  bool get isEmpty => objects.isEmpty;
  bool get wasDownsampled => downsampleMagnitudeCutoff != null;

  /// Constant empty result, useful when WCS is invalid.
  static const empty = CatalogOverlayResult(
    objects: <CatalogOverlayObject>[],
    totalInFov: 0,
    appliedMagnitudeLimit: 10.0,
    downsampleMagnitudeCutoff: null,
    catalogAvailable: false,
    queryDuration: Duration.zero,
  );
}

/// Source-injection seam used so tests can plug in a pre-baked list of
/// catalog objects without touching the on-disk planetarium catalog.
abstract class CatalogOverlaySource {
  /// Return every DSO (Messier / NGC / IC) currently known to the
  /// catalog. Must complete reasonably fast — the service slices by
  /// bounding box itself.
  Future<List<DeepSkyObject>> loadDsos();

  /// Return every star known to the catalog. May be empty if the user
  /// has only installed the DSO file.
  Future<List<Star>> loadStars();

  /// Whether the catalog data files exist on disk. When false, the
  /// service returns `catalogAvailable: false` so the UI can prompt
  /// the user to install catalogs from Settings.
  Future<bool> get isAvailable;
}

/// Default catalog source backed by the planetarium package's OpenNGC
/// (DSOs) and HYG (stars) catalogs. The instance is reusable — both
/// catalogs cache their content after the first load.
class PlanetariumCatalogOverlaySource implements CatalogOverlaySource {
  final OpenNgcDsoCatalog _dso;
  final HygStarCatalog _star;

  PlanetariumCatalogOverlaySource({
    OpenNgcDsoCatalog? dso,
    HygStarCatalog? star,
  })  : _dso = dso ?? OpenNgcDsoCatalog(),
        _star = star ?? HygStarCatalog();

  @override
  Future<List<DeepSkyObject>> loadDsos() => _dso.loadObjects();

  @override
  Future<List<Star>> loadStars() => _star.loadObjects();

  @override
  Future<bool> get isAvailable async {
    final dsoOk = await _dso.isAvailable;
    final starOk = await _star.isAvailable;
    // Why "or": the overlay is still useful with just one of the two
    // catalogs installed (Messier-only users get the DSO file but skip
    // the multi-MB HYG star list).
    return dsoOk || starOk;
  }
}

/// Catalog overlay service.
class CatalogOverlayService {
  final CatalogOverlaySource source;

  /// Hard cap on rendered objects. The mission says "downsample if >500".
  final int maxObjects;

  CatalogOverlayService({
    required this.source,
    this.maxObjects = 500,
  });

  /// Project catalog objects through [wcs] and return everything visible
  /// in the FOV brighter than [magnitudeLimit].
  ///
  /// Throws nothing — invalid WCS yields [CatalogOverlayResult.empty]
  /// with `catalogAvailable=false` so the caller can choose to surface
  /// a banner. Errors from catalog file IO propagate so the user sees
  /// real failures (per the project's "errors are a feature" rule).
  Future<CatalogOverlayResult> queryFov({
    required SolvedWcs wcs,
    required double magnitudeLimit,
    bool includeStars = true,
    bool includeDsos = true,
  }) async {
    if (!wcs.isValid) {
      return CatalogOverlayResult.empty;
    }
    final stopwatch = Stopwatch()..start();

    final available = await source.isAvailable;
    if (!available) {
      stopwatch.stop();
      return CatalogOverlayResult(
        objects: const <CatalogOverlayObject>[],
        totalInFov: 0,
        appliedMagnitudeLimit: magnitudeLimit,
        downsampleMagnitudeCutoff: null,
        catalogAvailable: false,
        queryDuration: stopwatch.elapsed,
      );
    }

    final projection = GnomonicProjection(wcs);
    final bbox = projection.computeBoundingBox();

    final hits = <_RankedHit>[];
    var totalInFov = 0;

    if (includeDsos) {
      final dsos = await source.loadDsos();
      for (final dso in dsos) {
        if (!_dsoPassesMagnitudeFilter(dso, magnitudeLimit)) continue;
        final raDeg = _normaliseRaDeg(dso.coordinates.ra * 15.0);
        if (!bbox.contains(raDeg: raDeg, decDeg: dso.coordinates.dec)) {
          continue;
        }
        final p = projection.worldToPixel(
          raDegrees: raDeg,
          decDegrees: dso.coordinates.dec,
        );
        if (p == null || !p.onImage) continue;
        totalInFov++;
        hits.add(
          _RankedHit(
            object: _dsoToObject(dso, p.pixel.x, p.pixel.y),
            magForRank: dso.magnitude ?? magnitudeLimit + 1,
          ),
        );
      }
    }

    if (includeStars) {
      final stars = await source.loadStars();
      for (final star in stars) {
        // Stars without a magnitude are useless for an overlay — there's
        // no way to know whether to draw them.
        final mag = star.magnitude;
        if (mag == null || mag > magnitudeLimit) continue;
        final raDeg = _normaliseRaDeg(star.coordinates.ra * 15.0);
        if (!bbox.contains(raDeg: raDeg, decDeg: star.coordinates.dec)) {
          continue;
        }
        final p = projection.worldToPixel(
          raDegrees: raDeg,
          decDegrees: star.coordinates.dec,
        );
        if (p == null || !p.onImage) continue;
        totalInFov++;
        hits.add(
          _RankedHit(
            object: _starToObject(star, p.pixel.x, p.pixel.y),
            magForRank: mag,
          ),
        );
      }
    }

    // Sort brightest-first so the magnitude downsample below truncates
    // the faint tail. Stable sort isn't required — objects at the same
    // magnitude are visually interchangeable.
    hits.sort((a, b) => a.magForRank.compareTo(b.magForRank));

    double? cutoff;
    if (hits.length > maxObjects) {
      cutoff = hits[maxObjects - 1].magForRank;
      hits.removeRange(maxObjects, hits.length);
    }

    stopwatch.stop();

    return CatalogOverlayResult(
      objects: hits.map((h) => h.object).toList(growable: false),
      totalInFov: totalInFov,
      appliedMagnitudeLimit: magnitudeLimit,
      downsampleMagnitudeCutoff: cutoff,
      catalogAvailable: true,
      queryDuration: stopwatch.elapsed,
    );
  }

  // -------------------------------------------------------------------------
  // Conversion helpers — kept small so the per-object loop stays cheap.
  // -------------------------------------------------------------------------

  static bool _dsoPassesMagnitudeFilter(
      DeepSkyObject dso, double magnitudeLimit) {
    final mag = dso.magnitude;
    // Mission requirement: include Messier objects even when magnitude
    // is unknown — they're the centerpiece of any overlay. NGC / IC
    // entries without a magnitude are dropped because they explode the
    // count (most OpenNGC rows lack a V-mag).
    if (mag == null) return dso.isMessier;
    return mag <= magnitudeLimit;
  }

  static CatalogOverlayObject _dsoToObject(
    DeepSkyObject dso,
    double imageX,
    double imageY,
  ) {
    final messier = dso.messierNumber;
    final ngcIc = dso.ngcIcDesignation;
    final preferredId = messier ?? ngcIc ?? dso.id;
    final commonName = (dso.commonNames != null && dso.commonNames!.isNotEmpty)
        ? dso.commonNames!.split(',').first.trim()
        : (dso.name != preferredId ? dso.name : null);

    final altIds = dso.catalogIds.where((c) => c != preferredId).join(', ');

    // Larger objects get a bigger hit radius — the Andromeda Galaxy is
    // hundreds of arcminutes across, a planetary nebula is well under
    // one. We translate arcminutes to a reasonable pixel hit-radius
    // assuming a typical 1.5"/px scale; the painter applies its own
    // size scaling.
    final hitRadius = _hitRadiusForArcmin(dso.sizeArcMin);

    return CatalogOverlayObject(
      id: preferredId,
      commonName: commonName,
      alternateIds: altIds.isEmpty ? null : altIds,
      raHours: dso.coordinates.ra,
      decDegrees: dso.coordinates.dec,
      magnitude: dso.magnitude,
      sizeArcMin: dso.sizeArcMin,
      kind: _kindForDsoType(dso.type),
      imageX: imageX,
      imageY: imageY,
      hitRadius: hitRadius,
      source: messier != null ? 'Messier' : (ngcIc ?? 'OpenNGC'),
    );
  }

  static CatalogOverlayObject _starToObject(
    Star star,
    double imageX,
    double imageY,
  ) {
    final hasFancyName = star.name.isNotEmpty && star.name != star.id;
    return CatalogOverlayObject(
      id: star.id,
      commonName: hasFancyName ? star.name : null,
      alternateIds:
          star.catalogIds.isEmpty ? null : star.catalogIds.join(', '),
      raHours: star.coordinates.ra,
      decDegrees: star.coordinates.dec,
      magnitude: star.magnitude,
      sizeArcMin: null,
      kind: CatalogOverlayKind.star,
      imageX: imageX,
      imageY: imageY,
      hitRadius: 18,
      source: 'HYG',
    );
  }

  static CatalogOverlayKind _kindForDsoType(DsoType type) {
    switch (type) {
      case DsoType.galaxy:
      case DsoType.galaxyPair:
      case DsoType.galaxyTriplet:
      case DsoType.galaxyGroup:
        return CatalogOverlayKind.galaxy;
      case DsoType.openCluster:
        return CatalogOverlayKind.openCluster;
      case DsoType.globularCluster:
        return CatalogOverlayKind.globularCluster;
      case DsoType.clusterWithNebulosity:
      case DsoType.nebula:
      case DsoType.emissionNebula:
      case DsoType.reflectionNebula:
      case DsoType.hiiRegion:
      case DsoType.darkNebula:
        return CatalogOverlayKind.nebula;
      case DsoType.planetaryNebula:
        return CatalogOverlayKind.planetaryNebula;
      case DsoType.supernova:
        return CatalogOverlayKind.supernovaRemnant;
      case DsoType.star:
      case DsoType.doubleStar:
        return CatalogOverlayKind.star;
      case DsoType.association:
      case DsoType.starCloud:
      case DsoType.asterism:
      case DsoType.nova:
      case DsoType.other:
        return CatalogOverlayKind.other;
    }
  }

  static double _hitRadiusForArcmin(double? arcmin) {
    if (arcmin == null || arcmin <= 0) return 24;
    // Why this curve: a 1 arcmin planetary nebula needs only a 16-pixel
    // click target; a 180 arcmin Andromeda needs hundreds. Square-root
    // softens the growth so we don't end up with thousand-pixel hit
    // boxes for the wide Milky Way HII regions.
    const base = 18.0;
    final scaled = base + 6.0 * (arcmin.clamp(0.0, 600.0));
    return scaled.clamp(18.0, 320.0);
  }

  static double _normaliseRaDeg(double raDeg) {
    var v = raDeg % 360.0;
    if (v < 0) v += 360.0;
    return v;
  }
}

class _RankedHit {
  final CatalogOverlayObject object;
  final double magForRank;
  const _RankedHit({required this.object, required this.magForRank});
}
