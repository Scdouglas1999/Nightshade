/// Plate solve result from astrometric solving.

/// Result of plate solving an image
class PlateSolveResult {
  /// Whether the solve was successful
  final bool success;

  /// Right ascension in hours (0-24)
  final double ra;

  /// Declination in degrees (-90 to +90)
  final double dec;

  /// Image scale in arcseconds per pixel
  final double pixelScale;

  /// Field rotation in degrees (0-360)
  final double rotation;

  /// Field width in degrees
  final double fieldWidth;

  /// Field height in degrees
  final double fieldHeight;

  /// Time taken to solve in seconds
  final double solveTimeSecs;

  /// Error message if solve failed
  final String? error;

  const PlateSolveResult({
    required this.success,
    required this.ra,
    required this.dec,
    required this.pixelScale,
    required this.rotation,
    required this.fieldWidth,
    required this.fieldHeight,
    required this.solveTimeSecs,
    this.error,
  });

  /// Create from JSON (for network transport)
  factory PlateSolveResult.fromJson(Map<String, dynamic> json) {
    return PlateSolveResult(
      success: json['success'] as bool,
      ra: (json['ra'] as num).toDouble(),
      dec: (json['dec'] as num).toDouble(),
      pixelScale: (json['pixelScale'] as num).toDouble(),
      rotation: (json['rotation'] as num).toDouble(),
      fieldWidth: (json['fieldWidth'] as num).toDouble(),
      fieldHeight: (json['fieldHeight'] as num).toDouble(),
      solveTimeSecs: (json['solveTimeSecs'] as num).toDouble(),
      error: json['error'] as String?,
    );
  }

  /// Convert to JSON (for network transport)
  Map<String, dynamic> toJson() => {
        'success': success,
        'ra': ra,
        'dec': dec,
        'pixelScale': pixelScale,
        'rotation': rotation,
        'fieldWidth': fieldWidth,
        'fieldHeight': fieldHeight,
        'solveTimeSecs': solveTimeSecs,
        'error': error,
      };

  @override
  String toString() => success
      ? 'PlateSolveResult(RA=${ra.toStringAsFixed(4)}h, Dec=${dec.toStringAsFixed(4)}°, scale=${pixelScale.toStringAsFixed(2)}"/px)'
      : 'PlateSolveResult(failed: $error)';
}
