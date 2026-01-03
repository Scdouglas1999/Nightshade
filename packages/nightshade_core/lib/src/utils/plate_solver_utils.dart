import 'dart:io';

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

  /// Get common ASTAP installation paths for the current platform
  static List<String> _getCommonAstapPaths() {
    if (Platform.isWindows) {
      return [
        r'C:\Program Files\astap\astap.exe',
        r'C:\Program Files\astap\astap_cli.exe',
        r'C:\Program Files (x86)\astap\astap.exe',
        r'C:\Program Files (x86)\astap\astap_cli.exe',
      ];
    } else if (Platform.isMacOS) {
      return [
        '/Applications/astap.app/Contents/MacOS/astap',
        '/Applications/ASTAP.app/Contents/MacOS/astap',
        '/usr/local/bin/astap',
        '/opt/homebrew/bin/astap',
      ];
    } else if (Platform.isLinux) {
      return [
        '/usr/bin/astap',
        '/usr/local/bin/astap',
        '/opt/astap/astap',
        '~/.local/bin/astap',
      ];
    }
    return [];
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
