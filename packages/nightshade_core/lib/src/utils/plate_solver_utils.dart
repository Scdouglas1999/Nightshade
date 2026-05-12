import 'dart:io';

/// Description of an ASTAP star catalog discovered on disk. Mirrors the
/// Rust `nightshade_imaging::CatalogInfo` struct.
class AstapCatalogInfo {
  /// Short catalog identifier (e.g. `"V17"`, `"D80"`). Empty string when
  /// `.290`/`.1476` files were found but no known marker was detected.
  final String name;

  /// Approximate magnitude limit the catalog covers, or `null` when the
  /// flavour wasn't recognised.
  final double? magnitudeLimit;

  /// Directory containing the catalog files.
  final String path;

  const AstapCatalogInfo({
    required this.name,
    required this.magnitudeLimit,
    required this.path,
  });
}

/// Utility functions for plate solver path resolution
class PlateSolverUtils {
  /// Find ASTAP executable with fallback to common installation paths
  ///
  /// Returns the path to ASTAP executable if found, null otherwise.
  /// Searches in the following order:
  /// 1. User-configured path from settings
  /// 2. Common installation paths for the current platform
  static Future<String?> findAstapExecutable(String? configuredPath) async {
    // First, try the configured path if provided
    if (configuredPath != null && configuredPath.isNotEmpty) {
      final configured = await _validateAstapPath(configuredPath);
      if (configured != null) return configured;
    }

    // Fallback to common installation paths
    final fallbackPaths = _getCommonAstapPaths();
    for (final path in fallbackPaths) {
      final validated = await _validateAstapPath(path);
      if (validated != null) return validated;
    }

    return null;
  }

  /// Get common ASTAP installation paths for the current platform.
  ///
  /// Mirrors `native/nightshade_native/imaging/src/platesolve/platesolve_paths.rs`.
  /// Order matters: more specific / more likely paths come first.
  static List<String> _getCommonAstapPaths() {
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      return [
        if (localAppData != null && localAppData.isNotEmpty) ...[
          '$localAppData\\Programs\\astap\\astap.exe',
          '$localAppData\\Programs\\astap\\astap_cli.exe',
          '$localAppData\\astap\\astap.exe',
          '$localAppData\\astap\\astap_cli.exe',
        ],
        r'C:\Program Files\astap\astap.exe',
        r'C:\Program Files\astap\astap_cli.exe',
        r'C:\Program Files (x86)\astap\astap.exe',
        r'C:\Program Files (x86)\astap\astap_cli.exe',
        r'C:\astap\astap.exe',
        r'C:\astap\astap_cli.exe',
      ];
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      return [
        '/Applications/ASTAP.app/Contents/MacOS/astap',
        '/Applications/astap.app/Contents/MacOS/astap',
        if (home != null && home.isNotEmpty)
          '$home/Applications/ASTAP.app/Contents/MacOS/astap',
        '/usr/local/bin/astap',
        '/opt/homebrew/bin/astap',
      ];
    } else if (Platform.isLinux) {
      return [
        '/opt/astap/astap',
        '/usr/local/bin/astap',
        '/usr/bin/astap',
      ];
    }
    return [];
  }

  /// Detect the ASTAP star catalog (`.290`/`.1476`/`.h17` files) that the
  /// solver needs in order to actually solve. ASTAP without a catalog will
  /// always fail, so the UX needs to surface this distinct from "ASTAP not
  /// installed".
  ///
  /// Search order (matches `nightshade_imaging::detect_astap_catalog`):
  ///   1. `configuredCatalogDir` if non-empty
  ///   2. the directory containing the ASTAP executable
  ///   3. `~/.astap/`
  ///   4. platform-specific locations (`%LOCALAPPDATA%\astap`, `/usr/share/astap`,
  ///      `/usr/local/share/astap`, …)
  static Future<AstapCatalogInfo?> detectAstapCatalog({
    String? astapExecutablePath,
    String? configuredCatalogDir,
  }) async {
    final candidates = _catalogDirCandidates(
      astapExecutablePath: astapExecutablePath,
      configuredCatalogDir: configuredCatalogDir,
    );

    for (final dir in candidates) {
      final directory = Directory(dir);
      if (!await directory.exists()) continue;

      try {
        final names = <String>[];
        await for (final entry in directory.list(followLinks: false)) {
          final base = entry.uri.pathSegments.isNotEmpty
              ? entry.uri.pathSegments.last
              : entry.path.split(Platform.pathSeparator).last;
          names.add(base);
        }
        final info = _identifyCatalog(dir, names);
        if (info != null) return info;
      } on FileSystemException {
        // Permission-denied or unreadable dir — skip, try the next one.
        continue;
      }
    }
    return null;
  }

  static List<String> _catalogDirCandidates({
    String? astapExecutablePath,
    String? configuredCatalogDir,
  }) {
    final dirs = <String>[];

    if (configuredCatalogDir != null && configuredCatalogDir.isNotEmpty) {
      dirs.add(configuredCatalogDir);
    }

    if (astapExecutablePath != null && astapExecutablePath.isNotEmpty) {
      final file = File(astapExecutablePath);
      dirs.add(file.parent.path);
    }

    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      dirs.add('$home${Platform.pathSeparator}.astap');
    }

    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        dirs.add('$localAppData\\astap');
        dirs.add('$localAppData\\Programs\\astap');
      }
      dirs.add(r'C:\astap');
    } else if (Platform.isMacOS) {
      dirs.add('/usr/local/share/astap');
      dirs.add('/opt/homebrew/share/astap');
    } else if (Platform.isLinux) {
      dirs.add('/usr/share/astap');
      dirs.add('/opt/astap');
    }
    return dirs;
  }

  /// Identify the catalog flavour from a list of filenames. Mirrors the
  /// Rust `identify_catalog` function — magnitude limits come from the
  /// published ASTAP catalog documentation
  /// (https://www.hnsky.org/star_databases.htm).
  static AstapCatalogInfo? _identifyCatalog(String dir, List<String> filenames) {
    var hasIndexFiles = false;
    String? detectedName;
    double? detectedMag;

    for (final raw in filenames) {
      final lower = raw.toLowerCase();
      if (lower.endsWith('.290') ||
          lower.endsWith('.1476') ||
          lower.endsWith('.h17')) {
        hasIndexFiles = true;
      }
      if (detectedName != null) continue;

      if (lower.startsWith('v17') || lower.contains('_v17')) {
        detectedName = 'V17';
        detectedMag = 17.0;
      } else if (lower.startsWith('v50') || lower.contains('_v50')) {
        detectedName = 'V50';
        detectedMag = 18.5;
      } else if (lower.startsWith('d80') || lower.contains('_d80')) {
        detectedName = 'D80';
        detectedMag = 12.0;
      } else if (lower.startsWith('g18') || lower.contains('_g18')) {
        detectedName = 'G18';
        detectedMag = 18.0;
      } else if (lower.startsWith('h18') || lower.contains('_h18')) {
        detectedName = 'H18';
        detectedMag = 18.0;
      } else if (lower.startsWith('h17') || lower.contains('_h17')) {
        detectedName = 'H17';
        detectedMag = 17.0;
      } else if (lower.startsWith('w08') || lower.contains('_w08')) {
        detectedName = 'W08';
        detectedMag = 8.0;
      }
    }

    if (!hasIndexFiles && detectedName == null) return null;
    return AstapCatalogInfo(
      name: detectedName ?? '',
      magnitudeLimit: detectedMag,
      path: dir,
    );
  }

  /// Validate that a path points to a valid ASTAP executable
  ///
  /// Returns the validated path if it exists and is executable, null otherwise.
  /// If the path is a directory, it will look for common ASTAP executable names.
  static Future<String?> _validateAstapPath(String path) async {
    try {
      final file = File(path);
      final dir = Directory(path);

      // Check if it's a file that exists
      if (await file.exists()) {
        return path;
      }

      // Check if it's a directory with ASTAP executable
      if (await dir.exists()) {
        final executableNames = Platform.isWindows
            ? ['astap.exe', 'astap_cli.exe']
            : ['astap', 'astap_cli'];

        for (final name in executableNames) {
          final execPath = '${path}${Platform.pathSeparator}$name';
          if (await File(execPath).exists()) {
            return execPath;
          }
        }
      }
    } catch (e) {
      // Path validation failed
      return null;
    }

    return null;
  }

  /// Generate a helpful error message when ASTAP is not found
  static String getAstapNotFoundMessage() {
    final downloadUrl = 'https://www.hnsky.org/astap.htm';

    if (Platform.isWindows) {
      return 'ASTAP executable not found.\n\n'
          'Please install ASTAP or configure the path in Settings > Plate Solving.\n\n'
          'Common installation paths:\n'
          '  • C:\\Program Files\\astap\\astap.exe\n'
          '  • C:\\Program Files (x86)\\astap\\astap.exe\n\n'
          'Download ASTAP: $downloadUrl';
    } else if (Platform.isMacOS) {
      return 'ASTAP executable not found.\n\n'
          'Please install ASTAP or configure the path in Settings > Plate Solving.\n\n'
          'Common installation paths:\n'
          '  • /Applications/astap.app/Contents/MacOS/astap\n'
          '  • /usr/local/bin/astap\n\n'
          'Download ASTAP: $downloadUrl';
    } else if (Platform.isLinux) {
      return 'ASTAP executable not found.\n\n'
          'Please install ASTAP or configure the path in Settings > Plate Solving.\n\n'
          'Common installation paths:\n'
          '  • /usr/bin/astap\n'
          '  • /usr/local/bin/astap\n\n'
          'Install via package manager or download: $downloadUrl';
    }

    return 'ASTAP executable not found.\n\n'
        'Please install ASTAP or configure the path in Settings > Plate Solving.\n\n'
        'Download ASTAP: $downloadUrl';
  }

  /// Get Astrometry.net executable with fallback to common installation paths
  static Future<String?> findAstrometryNetExecutable(String? configuredPath) async {
    // First, try the configured path if provided
    if (configuredPath != null && configuredPath.isNotEmpty) {
      final configured = await _validateExecutablePath(configuredPath, 'solve-field');
      if (configured != null) return configured;
    }

    // Fallback to common installation paths
    final fallbackPaths = _getCommonAstrometryNetPaths();
    for (final path in fallbackPaths) {
      final validated = await _validateExecutablePath(path, 'solve-field');
      if (validated != null) return validated;
    }

    return null;
  }

  /// Get common Astrometry.net installation paths for the current platform
  static List<String> _getCommonAstrometryNetPaths() {
    if (Platform.isWindows) {
      return [
        r'C:\Program Files\Astrometry\solve-field.exe',
        r'C:\Program Files (x86)\Astrometry\solve-field.exe',
      ];
    } else if (Platform.isMacOS) {
      return [
        '/usr/local/bin/solve-field',
        '/opt/homebrew/bin/solve-field',
        '/usr/local/astrometry/bin/solve-field',
      ];
    } else if (Platform.isLinux) {
      return [
        '/usr/bin/solve-field',
        '/usr/local/bin/solve-field',
        '/usr/local/astrometry/bin/solve-field',
      ];
    }
    return [];
  }

  /// Validate that a path points to a valid executable
  static Future<String?> _validateExecutablePath(String path, String executableName) async {
    try {
      final file = File(path);
      final dir = Directory(path);

      // Check if it's a file that exists
      if (await file.exists()) {
        return path;
      }

      // Check if it's a directory with the executable
      if (await dir.exists()) {
        final execNames = Platform.isWindows
            ? ['$executableName.exe']
            : [executableName];

        for (final name in execNames) {
          final execPath = '${path}${Platform.pathSeparator}$name';
          if (await File(execPath).exists()) {
            return execPath;
          }
        }
      }
    } catch (e) {
      // Path validation failed
      return null;
    }

    return null;
  }
}
