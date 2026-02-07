// ignore_for_file: unused_local_variable

import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/nightshade_backend.dart' as backend_types;
import '../providers/backend_provider.dart';

/// Plate solve result
class PlateSolveResult {
  final bool success;
  final double? ra; // hours
  final double? dec; // degrees
  final double? rotation; // degrees
  final double? pixelScale; // arcsec/pixel
  final double? fieldWidth; // degrees
  final double? fieldHeight; // degrees
  final String? errorMessage;

  const PlateSolveResult({
    required this.success,
    this.ra,
    this.dec,
    this.rotation,
    this.pixelScale,
    this.fieldWidth,
    this.fieldHeight,
    this.errorMessage,
  });

  factory PlateSolveResult.failed(String message) {
    return PlateSolveResult(success: false, errorMessage: message);
  }

  /// Convert from backend PlateSolveResult
  factory PlateSolveResult.fromBackend(backend_types.PlateSolveResult result) {
    return PlateSolveResult(
      success: result.success,
      ra: result.ra,
      dec: result.dec,
      rotation: result.rotation,
      pixelScale: result.pixelScale,
      fieldWidth: result.fieldWidth,
      fieldHeight: result.fieldHeight,
      errorMessage: result.error,
    );
  }
}

/// Plate solver type
enum PlateSolverType {
  astap,
  astrometryNet,
  plateSolve2,
}

/// Plate solver configuration
class PlateSolverConfig {
  final PlateSolverType type;
  final String executablePath;
  final String? catalogPath;
  final int timeoutSeconds;
  final double? searchRadius; // degrees
  final double? hintRa; // hours
  final double? hintDec; // degrees

  const PlateSolverConfig({
    required this.type,
    required this.executablePath,
    this.catalogPath,
    this.timeoutSeconds = 60,
    this.searchRadius,
    this.hintRa,
    this.hintDec,
  });
}

/// Plate solve service
class PlateSolveService {
  final Ref _ref;

  PlateSolveService(this._ref);

  /// Solve an image using the backend (works for both local and remote)
  Future<PlateSolveResult> solve(
    String imagePath,
    PlateSolverConfig config,
  ) async {
    try {
      // Use backend's plateSolve - works for both local (FFI) and remote (Network)
      final backend = _ref.read(backendProvider);
      final result = await backend.plateSolve(
        imagePath: imagePath,
        ra: config.hintRa,
        dec: config.hintDec,
        fovDegrees: config.searchRadius,
      );
      return PlateSolveResult.fromBackend(result);
    } catch (e) {
      // Fall back to local solving if backend fails (e.g., DisconnectedBackend)
      return _solveLocally(imagePath, config);
    }
  }

  /// Local fallback solver
  Future<PlateSolveResult> _solveLocally(
    String imagePath,
    PlateSolverConfig config,
  ) async {
    switch (config.type) {
      case PlateSolverType.astap:
        return _solveWithAstap(imagePath, config);
      case PlateSolverType.astrometryNet:
        return _solveWithAstrometryNet(imagePath, config);
      case PlateSolverType.plateSolve2:
        return _solveWithPlateSolve2(imagePath, config);
    }
  }

  /// Solve with ASTAP
  Future<PlateSolveResult> _solveWithAstap(
    String imagePath,
    PlateSolverConfig config,
  ) async {
    try {
      final args = <String>[
        '-f',
        imagePath,
        '-r',
        (config.searchRadius ?? 30).toString(),
      ];

      if (config.hintRa != null && config.hintDec != null) {
        args.addAll([
          '-ra', (config.hintRa! * 15).toString(), // Convert hours to degrees
          '-spd', (config.hintDec! + 90).toString(), // South pole distance
        ]);
      }

      final result = await Process.run(
        config.executablePath,
        args,
        workingDirectory: File(imagePath).parent.path,
      ).timeout(Duration(seconds: config.timeoutSeconds));

      if (result.exitCode != 0) {
        return PlateSolveResult.failed(
          'ASTAP failed: ${result.stderr}',
        );
      }

      // Parse the .wcs file that ASTAP creates
      final wcsPath = imagePath.replaceAll(RegExp(r'\.[^.]+$'), '.wcs');
      if (await File(wcsPath).exists()) {
        return _parseWcsFile(wcsPath);
      }

      return PlateSolveResult.failed('No WCS file created');
    } on TimeoutException {
      return PlateSolveResult.failed('Plate solve timed out');
    } catch (e) {
      return PlateSolveResult.failed('Error: $e');
    }
  }

  /// Solve with Astrometry.net (local)
  Future<PlateSolveResult> _solveWithAstrometryNet(
    String imagePath,
    PlateSolverConfig config,
  ) async {
    try {
      final args = <String>[
        imagePath,
        '--no-plots',
        '--overwrite',
      ];

      if (config.searchRadius != null) {
        args.addAll(['--radius', config.searchRadius.toString()]);
      }

      if (config.hintRa != null && config.hintDec != null) {
        args.addAll([
          '--ra',
          (config.hintRa! * 15).toString(),
          '--dec',
          config.hintDec.toString(),
        ]);
      }

      final result = await Process.run(
        config.executablePath,
        args,
      ).timeout(Duration(seconds: config.timeoutSeconds));

      if (result.exitCode != 0) {
        return PlateSolveResult.failed(
          'Astrometry.net failed: ${result.stderr}',
        );
      }

      // Parse the output
      final output = result.stdout.toString();
      return _parseAstrometryOutput(output);
    } on TimeoutException {
      return PlateSolveResult.failed('Plate solve timed out');
    } catch (e) {
      return PlateSolveResult.failed('Error: $e');
    }
  }

  /// Solve with PlateSolve2
  Future<PlateSolveResult> _solveWithPlateSolve2(
    String imagePath,
    PlateSolverConfig config,
  ) async {
    try {
      // PlateSolve2 uses a different command line interface
      final args = <String>[
        imagePath,
        '0', // wait for result
      ];

      if (config.hintRa != null && config.hintDec != null) {
        args.addAll([
          (config.hintRa! * 15).toString(),
          config.hintDec.toString(),
          (config.searchRadius ?? 30).toString(),
        ]);
      }

      final result = await Process.run(
        config.executablePath,
        args,
      ).timeout(Duration(seconds: config.timeoutSeconds));

      // Parse PlateSolve2 output file
      final outputPath = '$imagePath.apm';
      if (await File(outputPath).exists()) {
        return _parsePlateSolve2Output(outputPath);
      }

      return PlateSolveResult.failed('No solution found');
    } on TimeoutException {
      return PlateSolveResult.failed('Plate solve timed out');
    } catch (e) {
      return PlateSolveResult.failed('Error: $e');
    }
  }

  Future<PlateSolveResult> _parseWcsFile(String wcsPath) async {
    try {
      final content = await File(wcsPath).readAsString();
      final lines = content.split('\n');

      double? crval1, crval2, cdelt1, cdelt2, crota2;

      for (final line in lines) {
        if (line.startsWith('CRVAL1')) {
          crval1 = _parseWcsValue(line);
        } else if (line.startsWith('CRVAL2')) {
          crval2 = _parseWcsValue(line);
        } else if (line.startsWith('CDELT1')) {
          cdelt1 = _parseWcsValue(line);
        } else if (line.startsWith('CDELT2')) {
          cdelt2 = _parseWcsValue(line);
        } else if (line.startsWith('CROTA2')) {
          crota2 = _parseWcsValue(line);
        }
      }

      if (crval1 != null && crval2 != null) {
        return PlateSolveResult(
          success: true,
          ra: crval1 / 15, // Convert degrees to hours
          dec: crval2,
          rotation: crota2,
          pixelScale: cdelt1 != null ? cdelt1.abs() * 3600 : null,
        );
      }

      return PlateSolveResult.failed('Could not parse WCS file');
    } catch (e) {
      return PlateSolveResult.failed('Error parsing WCS: $e');
    }
  }

  double? _parseWcsValue(String line) {
    final parts = line.split('=');
    if (parts.length >= 2) {
      final valueStr = parts[1].split('/')[0].trim();
      return double.tryParse(valueStr);
    }
    return null;
  }

  PlateSolveResult _parseAstrometryOutput(String output) {
    // Parse astrometry.net console output
    final raMatch = RegExp(r'RA,Dec = \(([^,]+),([^)]+)\)').firstMatch(output);
    if (raMatch != null) {
      final ra = double.tryParse(raMatch.group(1)!);
      final dec = double.tryParse(raMatch.group(2)!);

      if (ra != null && dec != null) {
        return PlateSolveResult(
          success: true,
          ra: ra / 15, // Convert degrees to hours
          dec: dec,
        );
      }
    }

    return PlateSolveResult.failed('Could not parse solution');
  }

  Future<PlateSolveResult> _parsePlateSolve2Output(String outputPath) async {
    try {
      final content = await File(outputPath).readAsString();
      final lines = content.split('\n');

      if (lines.isEmpty) {
        return PlateSolveResult.failed(
          'Plate solver output file is empty',
        );
      }

      final parts = lines[0].split(',');
      if (parts.length < 2) {
        return PlateSolveResult.failed(
          'Plate solver output has unexpected format: expected "RA,Dec" '
          'but got "${lines[0].length > 80 ? '${lines[0].substring(0, 80)}...' : lines[0]}"',
        );
      }

      final ra = double.tryParse(parts[0]);
      final dec = double.tryParse(parts[1]);

      if (ra == null || dec == null) {
        return PlateSolveResult.failed(
          'Plate solver output contains non-numeric coordinates: '
          'RA="${parts[0]}", Dec="${parts[1]}"',
        );
      }

      return PlateSolveResult(
        success: true,
        ra: ra / 15,
        dec: dec,
      );
    } catch (e) {
      return PlateSolveResult.failed('Error parsing output: $e');
    }
  }
}

/// Plate solve service provider
final plateSolveServiceProvider = Provider<PlateSolveService>((ref) {
  return PlateSolveService(ref);
});

/// Active plate solve state
class PlateSolveState {
  final bool isSolving;
  final PlateSolveResult? lastResult;
  final String? currentImage;

  const PlateSolveState({
    this.isSolving = false,
    this.lastResult,
    this.currentImage,
  });

  PlateSolveState copyWith({
    bool? isSolving,
    PlateSolveResult? lastResult,
    String? currentImage,
  }) {
    return PlateSolveState(
      isSolving: isSolving ?? this.isSolving,
      lastResult: lastResult ?? this.lastResult,
      currentImage: currentImage ?? this.currentImage,
    );
  }
}

/// Plate solve state provider
final plateSolveStateProvider = StateProvider<PlateSolveState>((ref) {
  return const PlateSolveState();
});
