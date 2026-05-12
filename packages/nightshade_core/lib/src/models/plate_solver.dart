/// Plate-solver UX model surface.
///
/// These types are consumed by the Plate Solving settings page and the
/// in-context "solver not configured" banners. They are deliberately
/// platform-agnostic; the detection/verification logic lives in
/// `PlateSolveService` (and, once FRB is regenerated, in the
/// `api_platesolve_*` bridge functions).
library;

/// Detection snapshot describing what plate solvers are reachable on disk.
/// Returned by `PlateSolveService.detect()`.
class PlateSolverDetection {
  /// Absolute path to the detected ASTAP executable, or `null` when ASTAP
  /// is not installed at any well-known location and is not on `PATH`.
  final String? astapPath;

  /// Absolute path to the detected `solve-field` executable, or `null` when
  /// astrometry.net is not installed.
  final String? astrometryPath;

  /// Short catalog identifier (e.g. `"V17"`, `"D80"`). Empty/`null` when
  /// the catalog flavour could not be identified from filename markers but
  /// `catalogPath` may still be set (generic `.290` files were found).
  final String? catalogName;

  /// Approximate magnitude limit the detected catalog covers — `17.0` for
  /// V17, `12.0` for D80, etc. `null` when the catalog flavour wasn't
  /// recognised.
  final double? catalogMagnitudeLimit;

  /// Directory containing the detected ASTAP catalog. `null` when ASTAP is
  /// detected but no catalog could be located — the user must point us at
  /// one through the settings UI.
  final String? catalogPath;

  const PlateSolverDetection({
    this.astapPath,
    this.astrometryPath,
    this.catalogName,
    this.catalogMagnitudeLimit,
    this.catalogPath,
  });

  /// `true` when at least one solver was detected. Used by the settings UI
  /// to decide between "ASTAP detected at..." and "Plate solver not
  /// installed" banners.
  bool get hasAnySolver => astapPath != null || astrometryPath != null;

  /// `true` when ASTAP is reachable AND a catalog is configured. ASTAP
  /// without a catalog cannot solve, so this guards the "Plate solver
  /// ready" UX.
  bool get astapReady => astapPath != null && catalogPath != null;
}

/// Result of running `--help` against a detected solver binary. Lets the
/// settings UI show "ASTAP version 2024.05.10" alongside the path.
class PlateSolverInfo {
  /// Absolute path the verifier ran against.
  final String path;

  /// `"ASTAP"`, `"Astrometry.net"`, or `"Unknown"`.
  final String flavour;

  /// First non-empty line of the solver's `--help` output. Surfaced
  /// verbatim in the settings UI so users can confirm the expected build.
  final String versionLine;

  const PlateSolverInfo({
    required this.path,
    required this.flavour,
    required this.versionLine,
  });
}

/// Which solver the user prefers. `auto` falls back to ASTAP first,
/// Astrometry.net second.
enum PlateSolverChoice {
  auto,
  astap,
  astrometry;

  /// Storage-stable string used by the bridge config payload.
  String get serialized {
    switch (this) {
      case PlateSolverChoice.auto:
        return 'auto';
      case PlateSolverChoice.astap:
        return 'astap';
      case PlateSolverChoice.astrometry:
        return 'astrometry';
    }
  }

  static PlateSolverChoice fromSerialized(String value) {
    switch (value) {
      case 'astap':
        return PlateSolverChoice.astap;
      case 'astrometry':
        return PlateSolverChoice.astrometry;
      case 'auto':
      default:
        // Unknown values collapse to `auto` — the most forgiving default.
        // We do *not* throw here because a config file from a newer build
        // shouldn't crash an older binary; the user can re-select.
        return PlateSolverChoice.auto;
    }
  }
}

/// Persisted plate-solver UX configuration. Lives next to `settings.json`
/// in the Nightshade application support directory.
class PlateSolverPreference {
  /// User-configured ASTAP executable path. Empty string means "auto-detect".
  final String astapPath;

  /// User-configured Astrometry.net `solve-field` path. Empty string means
  /// "auto-detect".
  final String astrometryPath;

  /// User-configured ASTAP star catalog directory. Empty string means
  /// "look next to the executable and in well-known catalog locations".
  final String catalogPath;

  /// Active solver choice.
  final PlateSolverChoice choice;

  const PlateSolverPreference({
    this.astapPath = '',
    this.astrometryPath = '',
    this.catalogPath = '',
    this.choice = PlateSolverChoice.auto,
  });

  PlateSolverPreference copyWith({
    String? astapPath,
    String? astrometryPath,
    String? catalogPath,
    PlateSolverChoice? choice,
  }) {
    return PlateSolverPreference(
      astapPath: astapPath ?? this.astapPath,
      astrometryPath: astrometryPath ?? this.astrometryPath,
      catalogPath: catalogPath ?? this.catalogPath,
      choice: choice ?? this.choice,
    );
  }

  Map<String, dynamic> toJson() => {
        'astapPath': astapPath,
        'astrometryPath': astrometryPath,
        'catalogPath': catalogPath,
        'solverChoice': choice.serialized,
      };

  factory PlateSolverPreference.fromJson(Map<String, dynamic> json) {
    return PlateSolverPreference(
      astapPath: (json['astapPath'] as String?) ?? '',
      astrometryPath: (json['astrometryPath'] as String?) ?? '',
      catalogPath: (json['catalogPath'] as String?) ?? '',
      choice: PlateSolverChoice.fromSerialized(
        (json['solverChoice'] as String?) ?? 'auto',
      ),
    );
  }
}
