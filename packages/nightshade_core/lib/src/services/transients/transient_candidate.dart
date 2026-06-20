/// Shape/sign class of a difference-imaging residual. Wire tokens match the
/// native `TransientKind` enum and the `kind` column on `transient_detections`
/// (`docs/nightshade_5_0_contracts.md` §6 constants table).
enum TransientKind {
  /// A pre-existing source that got brighter (positive residual on a template
  /// that already had flux there).
  pointBrightening,

  /// An elongated residual — a moving body trailed across the exposure.
  movingStreak,

  /// A positive lobe next to a negative lobe — a registration/PSF mismatch
  /// signature, usually an artefact rather than a real transient.
  dipole,

  /// A clean point source with no flux in the template — a genuine newcomer.
  newSource;

  /// Wire token sent across the FFI / stored in the DB.
  String get wire => name;

  /// Parse a wire token; unknown values fall back to [dipole] (the
  /// least-exciting, artefact-leaning class) so a forward-compatible reader
  /// never crashes and never over-promotes an unrecognised residual.
  static TransientKind fromWire(String? token) {
    for (final value in TransientKind.values) {
      if (value.name == token) return value;
    }
    return TransientKind.dipole;
  }
}

/// One residual transient candidate decoded from the `api_difference_image`
/// result, after the Dart-side cross-match has filled [catalogMatch] /
/// [confidence].
///
/// This is the in-memory value the Narrator detectors read off
/// [NarratorContext] and the [FirstLightService] persists as a
/// `TransientDetectionRow`. [tileId] addresses the HEALPix tile the residual
/// fell on; [tileX]/[tileY] are pixel coordinates on that tile's grid.
class TransientCandidate {
  final double ra;
  final double dec;
  final int tileId;
  final double tileX;
  final double tileY;
  final double residualFlux;

  /// Estimated brightness change in magnitudes (negative = brighter). Null for
  /// a true new source with no template flux to compare against.
  final double? deltaMag;

  final double snr;
  final double fwhm;
  final double eccentricity;

  /// Major-axis position angle in degrees, `[0, 180)`, measured from the tile's
  /// +x axis toward +y — the real second-moment orientation of the residual
  /// (e.g. a moving streak's trail direction), not a fabricated constant.
  final double positionAngleDeg;

  final TransientKind kind;

  /// Resolved object name from the cross-match, or null when no match was found
  /// (the headline case of a possible unknown transient).
  final String? catalogMatch;

  /// Cross-match confidence in [0, 1] that the residual is a real astrophysical
  /// change rather than a subtraction artefact.
  final double confidence;

  const TransientCandidate({
    required this.ra,
    required this.dec,
    required this.tileId,
    required this.tileX,
    required this.tileY,
    required this.residualFlux,
    required this.deltaMag,
    required this.snr,
    required this.fwhm,
    required this.eccentricity,
    required this.positionAngleDeg,
    required this.kind,
    required this.confidence,
    this.catalogMatch,
  });

  /// Decode one entry of the bridge `candidates` array. The cross-match fields
  /// ([catalogMatch]/[confidence]) are not yet populated by the native side;
  /// [confidence] defaults to 0 and is overwritten by [withCrossMatch].
  factory TransientCandidate.fromBridgeJson(Map<String, dynamic> json) {
    return TransientCandidate(
      ra: (json['ra'] as num).toDouble(),
      dec: (json['dec'] as num).toDouble(),
      tileId: (json['tileId'] as num).toInt(),
      tileX: (json['tileX'] as num?)?.toDouble() ?? 0.0,
      tileY: (json['tileY'] as num?)?.toDouble() ?? 0.0,
      residualFlux: (json['residualFlux'] as num?)?.toDouble() ?? 0.0,
      deltaMag: (json['deltaMag'] as num?)?.toDouble(),
      snr: (json['snr'] as num?)?.toDouble() ?? 0.0,
      fwhm: (json['fwhm'] as num?)?.toDouble() ?? 0.0,
      eccentricity: (json['eccentricity'] as num?)?.toDouble() ?? 0.0,
      positionAngleDeg: (json['positionAngleDeg'] as num?)?.toDouble() ?? 0.0,
      kind: TransientKind.fromWire(json['kind'] as String?),
      catalogMatch: json['catalogMatch'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Return a copy with the cross-match outcome applied.
  TransientCandidate withCrossMatch({
    required String? catalogMatch,
    required double confidence,
  }) {
    return TransientCandidate(
      ra: ra,
      dec: dec,
      tileId: tileId,
      tileX: tileX,
      tileY: tileY,
      residualFlux: residualFlux,
      deltaMag: deltaMag,
      snr: snr,
      fwhm: fwhm,
      eccentricity: eccentricity,
      positionAngleDeg: positionAngleDeg,
      kind: kind,
      catalogMatch: catalogMatch,
      confidence: confidence,
    );
  }

  /// True for the genuinely exciting case: a clean, unmatched point source —
  /// `newSource` with no [catalogMatch] and a circular PSF.
  bool get isUnknownPointSource =>
      kind == TransientKind.newSource &&
      catalogMatch == null &&
      eccentricity < 0.5;
}
