// ignore_for_file: unused_local_variable

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../backend/ffi_backend.dart' show FfiBackend;
import '../backend/network_backend.dart' show NetworkBackend;
import '../backend/nightshade_backend.dart';
import '../models/plate_solver.dart' as ps_model;
import '../providers/backend_provider.dart';
import '../providers/settings_provider.dart';
import 'logging_service.dart';

final _kEmptyCoeffs = Float64List(0);

/// Thrown by `PlateSolveService.solveWithFallback()` when no plate solver
/// is reachable on disk. The settings UI catches this to render the
/// `PlateSolverRequiredBanner` rather than treating it as a generic error.
class SolverNotAvailableError implements Exception {
  final String message;
  const SolverNotAvailableError(this.message);

  @override
  String toString() => 'SolverNotAvailableError: $message';
}

/// Plate solver type
enum PlateSolverType { astap, astrometryNet, plateSolve2 }

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

class _SolverProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const _SolverProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// Plate solve service
class PlateSolveService {
  final Ref _ref;
  final NightshadeBackend _backend;
  final StateController<PlateSolveState> _stateController;
  bool _solveInFlight = false;
  bool _retired = false;

  PlateSolveService(this._ref, {NightshadeBackend? backend})
    : _backend = backend ?? _ref.read(backendProvider),
      _stateController = _ref.read(plateSolveStateProvider.notifier);

  /// Test seam: parse an ASTAP `.wcs` sidecar. Pins the unit contract
  /// (RA in degrees). Delegates to the private parser used by the local
  /// ASTAP fallback.
  @visibleForTesting
  Future<PlateSolveResult> parseWcsFileForTest(String wcsPath) =>
      _parseWcsFile(wcsPath);

  /// Test seam: parse astrometry.net console output. Pins the unit contract
  /// (RA in degrees).
  @visibleForTesting
  PlateSolveResult parseAstrometryOutputForTest(String output) =>
      _parseAstrometryOutput(output);

  /// Test seam: parse a PlateSolve2 `.apm` output file. Pins the unit
  /// contract (RA in degrees).
  @visibleForTesting
  Future<PlateSolveResult> parsePlateSolve2OutputForTest(String outputPath) =>
      _parsePlateSolve2Output(outputPath);

  /// Solve an image using the backend (works for both local and remote).
  ///
  /// Every solve — manual, framing, centering, or an unattended sequencer
  /// step — flows through here, so this is the single choke point where the
  /// outcome is recorded: [plateSolveStateProvider] is updated (so any UI can
  /// reflect "solving…" / last result) and the result is logged. The log line
  /// is the one place an unattended sequence's plate-solve outcome surfaces to
  /// the operator, who otherwise only saw a node flip green/red.
  Future<PlateSolveResult> solve(String imagePath, PlateSolverConfig config) {
    return _runExclusiveSolve(imagePath, () => _runSolve(imagePath, config));
  }

  Future<PlateSolveResult> _runExclusiveSolve(
    String imagePath,
    Future<PlateSolveResult> Function() operation,
  ) async {
    if (_solveInFlight) {
      return _failureResult(
        'Another plate solve is already running. Wait for it to finish before '
        'starting a new solve.',
      );
    }

    _solveInFlight = true;
    _ref.read(plateSolveStateProvider.notifier).state = _ref
        .read(plateSolveStateProvider)
        .copyWith(isSolving: true, currentImage: imagePath);

    try {
      final result = await operation();
      if (_hasAuthority) _announceSolveResult(imagePath, result);
      return result;
    } finally {
      // Detection/configuration/backend errors can throw before a result
      // exists. Always release both the UI state and the process-local gate.
      final state = _ref.read(plateSolveStateProvider);
      if (_hasAuthority && state.isSolving) {
        _ref.read(plateSolveStateProvider.notifier).state = state.copyWith(
          isSolving: false,
        );
      }
      _solveInFlight = false;
    }
  }

  bool get _hasAuthority =>
      !_retired && identical(_ref.read(backendProvider), _backend);

  void retire() {
    if (_retired) return;
    _retired = true;
    _solveInFlight = false;
    _stateController.state = const PlateSolveState();
  }

  Future<PlateSolveResult> _runSolve(
    String imagePath,
    PlateSolverConfig config,
  ) async {
    try {
      // Use backend's plateSolve - works for both local (FFI) and remote (Network)
      return await _backend.plateSolve(
        imagePath: imagePath,
        // PlateSolverConfig is app-canonical HOURS; the native bridge and
        // sequencer DeviceOps contract take solver hints in DEGREES.
        ra: config.hintRa == null ? null : config.hintRa! * 15.0,
        dec: config.hintDec,
        fovDegrees: config.searchRadius,
        timeoutSeconds: config.timeoutSeconds,
      );
    } catch (e) {
      // A NetworkBackend runs the solver on the desktop host. Its executable
      // path and image path are not meaningful on the remote client, so a
      // transport/backend failure must be surfaced instead of trying to spawn
      // that binary on the phone's local filesystem.
      if (_backend is NetworkBackend) {
        return _failureResult('Remote host plate solve failed: $e');
      }

      final fallbackResult = await _solveLocally(imagePath, config);
      if (fallbackResult.success) {
        return fallbackResult;
      }

      return PlateSolveResult(
        success: false,
        ra: 0,
        dec: 0,
        pixelScale: 0,
        rotation: 0,
        fieldWidth: 0,
        fieldHeight: 0,
        solveTimeSecs: 0,
        error:
            'Backend solve failed: $e. Local fallback failed: '
            '${fallbackResult.error ?? 'unknown error'}',
        cd11: 0,
        cd12: 0,
        cd21: 0,
        cd22: 0,
        sipAOrder: 0,
        sipBOrder: 0,
        sipACoeffs: _kEmptyCoeffs,
        sipBCoeffs: _kEmptyCoeffs,
        sipApOrder: 0,
        sipBpOrder: 0,
        sipApCoeffs: _kEmptyCoeffs,
        sipBpCoeffs: _kEmptyCoeffs,
      );
    }
  }

  PlateSolveResult _failureResult(String error) {
    return PlateSolveResult(
      success: false,
      ra: 0,
      dec: 0,
      pixelScale: 0,
      rotation: 0,
      fieldWidth: 0,
      fieldHeight: 0,
      solveTimeSecs: 0,
      error: error,
      cd11: 0,
      cd12: 0,
      cd21: 0,
      cd22: 0,
      sipAOrder: 0,
      sipBOrder: 0,
      sipACoeffs: _kEmptyCoeffs,
      sipBCoeffs: _kEmptyCoeffs,
      sipApOrder: 0,
      sipBpOrder: 0,
      sipApCoeffs: _kEmptyCoeffs,
      sipBpCoeffs: _kEmptyCoeffs,
    );
  }

  /// Run a local solver while retaining a process handle so timeout can
  /// actually terminate it. `Process.run(...).timeout(...)` only abandons the
  /// Dart Future; the solver keeps running and can write a stale solution after
  /// the caller has already reported failure.
  Future<_SolverProcessResult> _runSolverProcess(
    String executable,
    List<String> args, {
    String? workingDirectory,
    required Duration timeout,
  }) async {
    final process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
    );
    final stdoutFuture = systemEncoding
        .decodeStream(process.stdout)
        .catchError((Object _) => '');
    final stderrFuture = systemEncoding
        .decodeStream(process.stderr)
        .catchError((Object _) => '');

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      await _terminateSolverProcess(process);
      throw TimeoutException('Plate solve timed out', timeout);
    }

    return _SolverProcessResult(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
    );
  }

  Future<void> _terminateSolverProcess(Process process) async {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
      return;
    } on TimeoutException {
      if (!Platform.isWindows) {
        process.kill(ProcessSignal.sigkill);
      }
      await process.exitCode.timeout(const Duration(seconds: 2));
    }
  }

  /// Record the outcome of a solve: update the shared state provider and emit
  /// a log line so the result is visible app-wide (activity log) even when the
  /// caller is an unattended sequence with no inline UI of its own.
  void _announceSolveResult(String imagePath, PlateSolveResult result) {
    _ref.read(plateSolveStateProvider.notifier).state = _ref
        .read(plateSolveStateProvider)
        .copyWith(isSolving: false, lastResult: result);

    final logging = _ref.read(loggingServiceProvider);
    if (result.success) {
      // `PlateSolveResult.ra` is in DEGREES across every solve path (FFI,
      // network host, and the local fallback parsers), so log it as degrees.
      // Earlier this claimed hours, which was wrong and made the log line
      // disagree with the actual value by 15x.
      logging.info(
        'Plate solve succeeded: RA ${result.ra.toStringAsFixed(4)}° '
        'Dec ${result.dec.toStringAsFixed(4)}° · '
        'scale ${result.pixelScale.toStringAsFixed(2)}"/px · '
        'rot ${result.rotation.toStringAsFixed(1)}° · '
        '${result.solveTimeSecs.toStringAsFixed(1)}s',
        source: 'PlateSolveService',
      );
    } else {
      logging.warning(
        'Plate solve failed: ${result.error ?? 'unknown error'}',
        source: 'PlateSolveService',
      );
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

  /// Solve with ASTAP.
  ///
  /// Argument list mirrors the native Rust solver in
  /// `imaging/src/platesolve.rs` so this Dart fallback is a *real* solve and
  /// not a no-op that silently masks a backend failure:
  ///   * `-f <image>`        — input frame.
  ///   * `-ra` / `-spd`      — hint position (RA in degrees, south-pole
  ///                           distance) when a hint is supplied.
  ///   * `-r <deg>`          — search radius.
  ///   * `-d <catalog dir>`  — REQUIRED when the user configured a catalog
  ///                           directory; without it ASTAP cannot match stars
  ///                           and never writes a `.wcs`.
  ///   * `-wcs`              — REQUIRED so ASTAP emits the `.wcs` sidecar this
  ///                           parser reads. Omitting it was the original bug:
  ///                           ASTAP would run, write nothing, and the missing
  ///                           `.wcs` looked like "No WCS file created" — a
  ///                           silent failure that masked the backend's real
  ///                           error.
  Future<PlateSolveResult> _solveWithAstap(
    String imagePath,
    PlateSolverConfig config,
  ) async {
    try {
      // Delete any stale `.wcs` from a previous solve before invoking ASTAP.
      // Otherwise a no-op run (e.g. ASTAP failing to match) would "succeed"
      // by parsing the previous frame's sidecar — a silent, wrong-answer
      // fallback, which we forbid. The presence of a freshly written
      // `.wcs` is our only proof the solve actually ran.
      final wcsPath = imagePath.replaceAll(RegExp(r'\.[^.]+$'), '.wcs');
      final wcsFile = File(wcsPath);
      if (await wcsFile.exists()) {
        await wcsFile.delete();
      }

      final args = <String>[
        '-f',
        imagePath,
        '-r',
        (config.searchRadius ?? 30).toString(),
      ];

      if (config.hintRa != null && config.hintDec != null) {
        args.addAll([
          // ASTAP's CLI takes -ra in hours (unlike astrometry.net and the
          // Nightshade native bridge, which take degree hints).
          '-ra', config.hintRa!.toString(),
          '-spd', (config.hintDec! + 90).toString(), // South pole distance
        ]);
      }

      // Point ASTAP at the configured star catalog. ASTAP cannot solve
      // without one; when the user configured a catalog directory we must
      // pass it explicitly via `-d`.
      if (config.catalogPath != null && config.catalogPath!.isNotEmpty) {
        args.addAll(['-d', config.catalogPath!]);
      }

      // Tell ASTAP to write the `.wcs` sidecar that `_parseWcsFile` reads.
      args.add('-wcs');

      final result = await _runSolverProcess(
        config.executablePath,
        args,
        workingDirectory: File(imagePath).parent.path,
        timeout: Duration(seconds: config.timeoutSeconds),
      );

      if (result.exitCode != 0) {
        return PlateSolveResult(
          success: false,
          ra: 0,
          dec: 0,
          pixelScale: 0,
          rotation: 0,
          fieldWidth: 0,
          fieldHeight: 0,
          solveTimeSecs: 0,
          error: 'ASTAP failed (exit ${result.exitCode}): ${result.stderr}',
          cd11: 0,
          cd12: 0,
          cd21: 0,
          cd22: 0,
          sipAOrder: 0,
          sipBOrder: 0,
          sipACoeffs: _kEmptyCoeffs,
          sipBCoeffs: _kEmptyCoeffs,
          sipApOrder: 0,
          sipBpOrder: 0,
          sipApCoeffs: _kEmptyCoeffs,
          sipBpCoeffs: _kEmptyCoeffs,
        );
      }

      // Parse the .wcs file that ASTAP creates
      if (await wcsFile.exists()) {
        return _parseWcsFile(wcsPath);
      }

      return PlateSolveResult(
        success: false,
        ra: 0,
        dec: 0,
        pixelScale: 0,
        rotation: 0,
        fieldWidth: 0,
        fieldHeight: 0,
        solveTimeSecs: 0,
        error:
            'ASTAP exited 0 but wrote no WCS file '
            '(no star match within search radius). stdout: '
            '${result.stdout.toString().trim()}',
        cd11: 0,
        cd12: 0,
        cd21: 0,
        cd22: 0,
        sipAOrder: 0,
        sipBOrder: 0,
        sipACoeffs: _kEmptyCoeffs,
        sipBCoeffs: _kEmptyCoeffs,
        sipApOrder: 0,
        sipBpOrder: 0,
        sipApCoeffs: _kEmptyCoeffs,
        sipBpCoeffs: _kEmptyCoeffs,
      );
    } on TimeoutException {
      return PlateSolveResult(
        success: false,
        ra: 0,
        dec: 0,
        pixelScale: 0,
        rotation: 0,
        fieldWidth: 0,
        fieldHeight: 0,
        solveTimeSecs: 0,
        error: 'Plate solve timed out',
        cd11: 0,
        cd12: 0,
        cd21: 0,
        cd22: 0,
        sipAOrder: 0,
        sipBOrder: 0,
        sipACoeffs: _kEmptyCoeffs,
        sipBCoeffs: _kEmptyCoeffs,
        sipApOrder: 0,
        sipBpOrder: 0,
        sipApCoeffs: _kEmptyCoeffs,
        sipBpCoeffs: _kEmptyCoeffs,
      );
    } catch (e) {
      return PlateSolveResult(
        success: false,
        ra: 0,
        dec: 0,
        pixelScale: 0,
        rotation: 0,
        fieldWidth: 0,
        fieldHeight: 0,
        solveTimeSecs: 0,
        error: 'Error: $e',
        cd11: 0,
        cd12: 0,
        cd21: 0,
        cd22: 0,
        sipAOrder: 0,
        sipBOrder: 0,
        sipACoeffs: _kEmptyCoeffs,
        sipBCoeffs: _kEmptyCoeffs,
        sipApOrder: 0,
        sipBpOrder: 0,
        sipApCoeffs: _kEmptyCoeffs,
        sipBpCoeffs: _kEmptyCoeffs,
      );
    }
  }

  /// Solve with Astrometry.net (local)
  Future<PlateSolveResult> _solveWithAstrometryNet(
    String imagePath,
    PlateSolverConfig config,
  ) async {
    try {
      final args = <String>[imagePath, '--no-plots', '--overwrite'];

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

      final result = await _runSolverProcess(
        config.executablePath,
        args,
        timeout: Duration(seconds: config.timeoutSeconds),
      );

      if (result.exitCode != 0) {
        return PlateSolveResult(
          success: false,
          ra: 0,
          dec: 0,
          pixelScale: 0,
          rotation: 0,
          fieldWidth: 0,
          fieldHeight: 0,
          solveTimeSecs: 0,
          error: 'Astrometry.net failed: ${result.stderr}',
          cd11: 0,
          cd12: 0,
          cd21: 0,
          cd22: 0,
          sipAOrder: 0,
          sipBOrder: 0,
          sipACoeffs: _kEmptyCoeffs,
          sipBCoeffs: _kEmptyCoeffs,
          sipApOrder: 0,
          sipBpOrder: 0,
          sipApCoeffs: _kEmptyCoeffs,
          sipBpCoeffs: _kEmptyCoeffs,
        );
      }

      // Parse the output
      final output = result.stdout.toString();
      return _parseAstrometryOutput(output);
    } on TimeoutException {
      return PlateSolveResult(
        success: false,
        ra: 0,
        dec: 0,
        pixelScale: 0,
        rotation: 0,
        fieldWidth: 0,
        fieldHeight: 0,
        solveTimeSecs: 0,
        error: 'Plate solve timed out',
        cd11: 0,
        cd12: 0,
        cd21: 0,
        cd22: 0,
        sipAOrder: 0,
        sipBOrder: 0,
        sipACoeffs: _kEmptyCoeffs,
        sipBCoeffs: _kEmptyCoeffs,
        sipApOrder: 0,
        sipBpOrder: 0,
        sipApCoeffs: _kEmptyCoeffs,
        sipBpCoeffs: _kEmptyCoeffs,
      );
    } catch (e) {
      return PlateSolveResult(
        success: false,
        ra: 0,
        dec: 0,
        pixelScale: 0,
        rotation: 0,
        fieldWidth: 0,
        fieldHeight: 0,
        solveTimeSecs: 0,
        error: 'Error: $e',
        cd11: 0,
        cd12: 0,
        cd21: 0,
        cd22: 0,
        sipAOrder: 0,
        sipBOrder: 0,
        sipACoeffs: _kEmptyCoeffs,
        sipBCoeffs: _kEmptyCoeffs,
        sipApOrder: 0,
        sipBpOrder: 0,
        sipApCoeffs: _kEmptyCoeffs,
        sipBpCoeffs: _kEmptyCoeffs,
      );
    }
  }

  /// Solve with PlateSolve2
  Future<PlateSolveResult> _solveWithPlateSolve2(
    String imagePath,
    PlateSolverConfig config,
  ) async {
    try {
      final outputPath = '$imagePath.apm';
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        await outputFile.delete();
      }

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

      final result = await _runSolverProcess(
        config.executablePath,
        args,
        timeout: Duration(seconds: config.timeoutSeconds),
      );

      if (result.exitCode != 0) {
        return _failureResult(
          'PlateSolve2 failed (exit ${result.exitCode}): ${result.stderr}',
        );
      }

      // Parse PlateSolve2 output file
      if (await outputFile.exists()) {
        return _parsePlateSolve2Output(outputPath);
      }

      return PlateSolveResult(
        success: false,
        ra: 0,
        dec: 0,
        pixelScale: 0,
        rotation: 0,
        fieldWidth: 0,
        fieldHeight: 0,
        solveTimeSecs: 0,
        error: 'No solution found',
        cd11: 0,
        cd12: 0,
        cd21: 0,
        cd22: 0,
        sipAOrder: 0,
        sipBOrder: 0,
        sipACoeffs: _kEmptyCoeffs,
        sipBCoeffs: _kEmptyCoeffs,
        sipApOrder: 0,
        sipBpOrder: 0,
        sipApCoeffs: _kEmptyCoeffs,
        sipBpCoeffs: _kEmptyCoeffs,
      );
    } on TimeoutException {
      return PlateSolveResult(
        success: false,
        ra: 0,
        dec: 0,
        pixelScale: 0,
        rotation: 0,
        fieldWidth: 0,
        fieldHeight: 0,
        solveTimeSecs: 0,
        error: 'Plate solve timed out',
        cd11: 0,
        cd12: 0,
        cd21: 0,
        cd22: 0,
        sipAOrder: 0,
        sipBOrder: 0,
        sipACoeffs: _kEmptyCoeffs,
        sipBCoeffs: _kEmptyCoeffs,
        sipApOrder: 0,
        sipBpOrder: 0,
        sipApCoeffs: _kEmptyCoeffs,
        sipBpCoeffs: _kEmptyCoeffs,
      );
    } catch (e) {
      return PlateSolveResult(
        success: false,
        ra: 0,
        dec: 0,
        pixelScale: 0,
        rotation: 0,
        fieldWidth: 0,
        fieldHeight: 0,
        solveTimeSecs: 0,
        error: 'Error: $e',
        cd11: 0,
        cd12: 0,
        cd21: 0,
        cd22: 0,
        sipAOrder: 0,
        sipBOrder: 0,
        sipACoeffs: _kEmptyCoeffs,
        sipBCoeffs: _kEmptyCoeffs,
        sipApOrder: 0,
        sipBpOrder: 0,
        sipApCoeffs: _kEmptyCoeffs,
        sipBpCoeffs: _kEmptyCoeffs,
      );
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
          // RA stays in DEGREES to match `PlateSolveResult.ra` from the
          // dominant FFI/network host path (Rust `PlateSolveResult.ra` reads
          // FITS `CRVAL1` verbatim — degrees). Downstream consumers
          // (CenteringService) normalise degrees→hours themselves; emitting
          // hours here would feed them a 15x-wrong RA.
          ra: crval1, // CRVAL1 is already in degrees
          dec: crval2,
          rotation: crota2 ?? 0,
          pixelScale: cdelt1 != null ? cdelt1.abs() * 3600 : 0,
          fieldWidth: 0,
          fieldHeight: 0,
          solveTimeSecs: 0,
          cd11: 0,
          cd12: 0,
          cd21: 0,
          cd22: 0,
          sipAOrder: 0,
          sipBOrder: 0,
          sipACoeffs: _kEmptyCoeffs,
          sipBCoeffs: _kEmptyCoeffs,
          sipApOrder: 0,
          sipBpOrder: 0,
          sipApCoeffs: _kEmptyCoeffs,
          sipBpCoeffs: _kEmptyCoeffs,
        );
      }

      return PlateSolveResult(
        success: false,
        ra: 0,
        dec: 0,
        pixelScale: 0,
        rotation: 0,
        fieldWidth: 0,
        fieldHeight: 0,
        solveTimeSecs: 0,
        error: 'Could not parse WCS file',
        cd11: 0,
        cd12: 0,
        cd21: 0,
        cd22: 0,
        sipAOrder: 0,
        sipBOrder: 0,
        sipACoeffs: _kEmptyCoeffs,
        sipBCoeffs: _kEmptyCoeffs,
        sipApOrder: 0,
        sipBpOrder: 0,
        sipApCoeffs: _kEmptyCoeffs,
        sipBpCoeffs: _kEmptyCoeffs,
      );
    } catch (e) {
      return PlateSolveResult(
        success: false,
        ra: 0,
        dec: 0,
        pixelScale: 0,
        rotation: 0,
        fieldWidth: 0,
        fieldHeight: 0,
        solveTimeSecs: 0,
        error: 'Error parsing WCS: $e',
        cd11: 0,
        cd12: 0,
        cd21: 0,
        cd22: 0,
        sipAOrder: 0,
        sipBOrder: 0,
        sipACoeffs: _kEmptyCoeffs,
        sipBCoeffs: _kEmptyCoeffs,
        sipApOrder: 0,
        sipBpOrder: 0,
        sipApCoeffs: _kEmptyCoeffs,
        sipBpCoeffs: _kEmptyCoeffs,
      );
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
          // astrometry.net's `RA,Dec = (...)` line is in DEGREES; keep it in
          // degrees to match the canonical `PlateSolveResult.ra` contract.
          ra: ra, // RA,Dec line is already in degrees
          dec: dec,
          pixelScale: 0,
          rotation: 0,
          fieldWidth: 0,
          fieldHeight: 0,
          solveTimeSecs: 0,
          cd11: 0,
          cd12: 0,
          cd21: 0,
          cd22: 0,
          sipAOrder: 0,
          sipBOrder: 0,
          sipACoeffs: _kEmptyCoeffs,
          sipBCoeffs: _kEmptyCoeffs,
          sipApOrder: 0,
          sipBpOrder: 0,
          sipApCoeffs: _kEmptyCoeffs,
          sipBpCoeffs: _kEmptyCoeffs,
        );
      }
    }

    return PlateSolveResult(
      success: false,
      ra: 0,
      dec: 0,
      pixelScale: 0,
      rotation: 0,
      fieldWidth: 0,
      fieldHeight: 0,
      solveTimeSecs: 0,
      error: 'Could not parse solution',
      cd11: 0,
      cd12: 0,
      cd21: 0,
      cd22: 0,
      sipAOrder: 0,
      sipBOrder: 0,
      sipACoeffs: _kEmptyCoeffs,
      sipBCoeffs: _kEmptyCoeffs,
      sipApOrder: 0,
      sipBpOrder: 0,
      sipApCoeffs: _kEmptyCoeffs,
      sipBpCoeffs: _kEmptyCoeffs,
    );
  }

  /// Probe disk for installed solvers + ASTAP catalog. Returns a snapshot
  /// the UI can render directly.
  ///
  /// Routed through the imaging backend so it runs against the machine that
  /// owns the solver binaries: locally on the host (FFI), and on the HOST
  /// (over HTTP) when this is a remote phone client. This is the fix for the
  /// phone probing its own (empty) filesystem and showing a false "Set up
  /// plate solver" banner. The host-side detection ultimately calls the Rust
  /// `api_platesolve_detect` so platform-specific path enumeration stays in
  /// one place (`platesolve_paths.rs`).
  Future<ps_model.PlateSolverDetection> detect() async {
    final logging = _ref.read(loggingServiceProvider);
    try {
      return await _backend.detectPlateSolvers();
    } catch (e) {
      logging.error(
        'plate-solver detection failed: $e',
        source: 'PlateSolveService',
      );
      rethrow;
    }
  }

  /// Run the given solver binary's `--help` to confirm the install is
  /// healthy. Surfaces the version banner so the settings UI can display
  /// "ASTAP 2024.05.10" alongside the path.
  ///
  /// Routed through the backend so a remote phone verifies the binary on the
  /// HOST (where the path is meaningful), not on the phone.
  Future<ps_model.PlateSolverInfo> verify(String executablePath) async {
    final logging = _ref.read(loggingServiceProvider);
    try {
      return await _backend.verifyPlateSolver(executablePath);
    } catch (e) {
      logging.warning(
        'plate-solver verify failed for $executablePath: $e',
        source: 'PlateSolveService',
      );
      rethrow;
    }
  }

  /// Load persisted plate-solver UX configuration. Falls back to defaults
  /// when no `platesolver.json` exists yet.
  ///
  /// Routed through the backend so the phone reads the HOST's persisted
  /// config rather than its own.
  Future<ps_model.PlateSolverPreference> getConfig() async {
    return _backend.getPlateSolverConfig();
  }

  /// Persist plate-solver UX configuration. Invalidates the solver-
  /// availability cache so the next `is_plate_solver_available` call
  /// re-probes the filesystem with the new paths.
  ///
  /// Routed through the backend so the phone writes config to the HOST (the
  /// machine that actually runs the solver), not to the phone.
  Future<void> setConfig(ps_model.PlateSolverPreference pref) async {
    await _backend.setPlateSolverConfig(pref);
  }

  /// Validate the selected solver before callers capture an image or move
  /// hardware. Centering uses this preflight so a missing executable/catalog
  /// fails immediately instead of wasting a camera exposure first.
  Future<void> ensureSolverAvailable() async {
    final detection = await detect();
    final pref = await getConfig();
    _validateSolverAvailability(detection, pref);
  }

  void _validateSolverAvailability(
    ps_model.PlateSolverDetection detection,
    ps_model.PlateSolverPreference pref,
  ) {
    switch (pref.choice) {
      case ps_model.PlateSolverChoice.astap:
        if (!detection.astapReady) {
          throw const SolverNotAvailableError(
            'ASTAP is selected but its executable or star catalog is not '
            'configured. Configure it in Settings → Plate Solving.',
          );
        }
        return;
      case ps_model.PlateSolverChoice.astrometry:
        if (detection.astrometryPath == null) {
          throw const SolverNotAvailableError(
            'Astrometry.net is selected but not installed. Configure it in '
            'Settings → Plate Solving.',
          );
        }
        return;
      case ps_model.PlateSolverChoice.auto:
        if (!detection.hasAnySolver) {
          throw const SolverNotAvailableError(
            'No usable plate solver configured. Set one up in Settings → Plate '
            'Solving.',
          );
        }
        return;
    }
  }

  /// Solve `imagePath` honouring the user's `PlateSolverChoice`.
  ///
  /// - `astap` runs ASTAP only. Failure surfaces verbatim.
  /// - `astrometry` runs astrometry.net only.
  /// - `auto` tries ASTAP first; on failure (and only if astrometry.net is
  ///   reachable) retries with astrometry.net so a missing/broken ASTAP
  ///   doesn't end the session.
  ///
  /// Throws `SolverNotAvailableError` when no solver matches the choice.
  /// Callers (centering dialog, framing wizard, polar alignment) catch
  /// this to render the "Set up plate solver" banner instead of treating
  /// it as a generic solver failure.
  Future<PlateSolveResult> solveWithFallback({
    required String imagePath,
    double? hintRaHours,
    double? hintDecDegrees,
    double? searchRadiusDegrees,
    int? timeoutSeconds,
  }) {
    return _runExclusiveSolve(
      imagePath,
      () => _solveWithFallbackInternal(
        imagePath: imagePath,
        hintRaHours: hintRaHours,
        hintDecDegrees: hintDecDegrees,
        searchRadiusDegrees: searchRadiusDegrees,
        timeoutSeconds: timeoutSeconds,
      ),
    );
  }

  Future<PlateSolveResult> _solveWithFallbackInternal({
    required String imagePath,
    double? hintRaHours,
    double? hintDecDegrees,
    double? searchRadiusDegrees,
    int? timeoutSeconds,
  }) async {
    final logging = _ref.read(loggingServiceProvider);
    final detection = await detect();
    final pref = await getConfig();
    _validateSolverAvailability(detection, pref);

    // Fall back to the user-configured defaults (Settings → Plate Solving →
    // Solve parameters) when the caller doesn't pin an explicit value. This is
    // what makes those knobs meaningful on the desktop solve path; previously
    // they only affected the headless handlers and this method hard-coded 60s.
    final appSettings = _ref.read(appSettingsProvider).valueOrNull;
    final effectiveTimeout =
        timeoutSeconds ?? appSettings?.plateSolveTimeout ?? 60;
    final effectiveRadius =
        searchRadiusDegrees ?? appSettings?.plateSolveSearchRadius;
    final forceBlind = appSettings?.blindSolve ?? false;
    final effectiveHintRa = forceBlind ? null : hintRaHours;
    final effectiveHintDec = forceBlind ? null : hintDecDegrees;

    // FFI and Network backends both execute against the host's persisted
    // solver choice. The native host performs Auto's ASTAP→astrometry fallback
    // under its process-wide gate, so issue exactly one backend solve rather
    // than accidentally running ASTAP twice when the first attempt fails.
    final activeBackend = _backend;
    if (activeBackend is FfiBackend || activeBackend is NetworkBackend) {
      final executable = switch (pref.choice) {
        ps_model.PlateSolverChoice.astrometry => detection.astrometryPath!,
        ps_model.PlateSolverChoice.astap => detection.astapPath!,
        ps_model.PlateSolverChoice.auto =>
          detection.astapReady
              ? detection.astapPath!
              : detection.astrometryPath!,
      };
      final type = pref.choice == ps_model.PlateSolverChoice.astrometry
          ? PlateSolverType.astrometryNet
          : PlateSolverType.astap;
      return _runSolve(
        imagePath,
        PlateSolverConfig(
          type: type,
          executablePath: executable,
          catalogPath: detection.catalogPath,
          timeoutSeconds: effectiveTimeout,
          searchRadius: effectiveRadius,
          hintRa: effectiveHintRa,
          hintDec: effectiveHintDec,
        ),
      );
    }

    Future<PlateSolveResult> runAstap() async {
      if (detection.astapPath == null) {
        return PlateSolveResult(
          success: false,
          ra: 0,
          dec: 0,
          pixelScale: 0,
          rotation: 0,
          fieldWidth: 0,
          fieldHeight: 0,
          solveTimeSecs: 0,
          error: 'ASTAP not installed at any known location.',
          cd11: 0,
          cd12: 0,
          cd21: 0,
          cd22: 0,
          sipAOrder: 0,
          sipBOrder: 0,
          sipACoeffs: _kEmptyCoeffs,
          sipBCoeffs: _kEmptyCoeffs,
          sipApOrder: 0,
          sipBpOrder: 0,
          sipApCoeffs: _kEmptyCoeffs,
          sipBpCoeffs: _kEmptyCoeffs,
        );
      }
      if (!detection.astapReady) {
        return PlateSolveResult(
          success: false,
          ra: 0,
          dec: 0,
          pixelScale: 0,
          rotation: 0,
          fieldWidth: 0,
          fieldHeight: 0,
          solveTimeSecs: 0,
          error: 'ASTAP star catalog not configured.',
          cd11: 0,
          cd12: 0,
          cd21: 0,
          cd22: 0,
          sipAOrder: 0,
          sipBOrder: 0,
          sipACoeffs: _kEmptyCoeffs,
          sipBCoeffs: _kEmptyCoeffs,
          sipApOrder: 0,
          sipBpOrder: 0,
          sipApCoeffs: _kEmptyCoeffs,
          sipBpCoeffs: _kEmptyCoeffs,
        );
      }
      final config = PlateSolverConfig(
        type: PlateSolverType.astap,
        executablePath: detection.astapPath!,
        catalogPath: detection.catalogPath,
        timeoutSeconds: effectiveTimeout,
        searchRadius: effectiveRadius,
        hintRa: effectiveHintRa,
        hintDec: effectiveHintDec,
      );
      return _runSolve(imagePath, config);
    }

    Future<PlateSolveResult> runAstrometry() async {
      if (detection.astrometryPath == null) {
        return PlateSolveResult(
          success: false,
          ra: 0,
          dec: 0,
          pixelScale: 0,
          rotation: 0,
          fieldWidth: 0,
          fieldHeight: 0,
          solveTimeSecs: 0,
          error: 'Astrometry.net (solve-field) not installed.',
          cd11: 0,
          cd12: 0,
          cd21: 0,
          cd22: 0,
          sipAOrder: 0,
          sipBOrder: 0,
          sipACoeffs: _kEmptyCoeffs,
          sipBCoeffs: _kEmptyCoeffs,
          sipApOrder: 0,
          sipBpOrder: 0,
          sipApCoeffs: _kEmptyCoeffs,
          sipBpCoeffs: _kEmptyCoeffs,
        );
      }
      final config = PlateSolverConfig(
        type: PlateSolverType.astrometryNet,
        executablePath: detection.astrometryPath!,
        timeoutSeconds: effectiveTimeout,
        searchRadius: effectiveRadius,
        hintRa: effectiveHintRa,
        hintDec: effectiveHintDec,
      );
      return _runSolve(imagePath, config);
    }

    switch (pref.choice) {
      case ps_model.PlateSolverChoice.astap:
        return runAstap();
      case ps_model.PlateSolverChoice.astrometry:
        return runAstrometry();
      case ps_model.PlateSolverChoice.auto:
        if (detection.astapReady) {
          final astapResult = await runAstap();
          if (astapResult.success) return astapResult;
          if (detection.astrometryPath != null) {
            logging.warning(
              'ASTAP failed (${astapResult.error}); falling back '
              'to astrometry.net',
              source: 'PlateSolveService',
            );
            return runAstrometry();
          }
          return astapResult;
        }
        return runAstrometry();
    }
  }

  Future<PlateSolveResult> _parsePlateSolve2Output(String outputPath) async {
    try {
      final content = await File(outputPath).readAsString();
      final lines = content.split('\n');

      if (lines.isEmpty) {
        return PlateSolveResult(
          success: false,
          ra: 0,
          dec: 0,
          pixelScale: 0,
          rotation: 0,
          fieldWidth: 0,
          fieldHeight: 0,
          solveTimeSecs: 0,
          error: 'Plate solver output file is empty',
          cd11: 0,
          cd12: 0,
          cd21: 0,
          cd22: 0,
          sipAOrder: 0,
          sipBOrder: 0,
          sipACoeffs: _kEmptyCoeffs,
          sipBCoeffs: _kEmptyCoeffs,
          sipApOrder: 0,
          sipBpOrder: 0,
          sipApCoeffs: _kEmptyCoeffs,
          sipBpCoeffs: _kEmptyCoeffs,
        );
      }

      final parts = lines[0].split(',');
      if (parts.length < 2) {
        return PlateSolveResult(
          success: false,
          ra: 0,
          dec: 0,
          pixelScale: 0,
          rotation: 0,
          fieldWidth: 0,
          fieldHeight: 0,
          solveTimeSecs: 0,
          error:
              'Plate solver output has unexpected format: expected "RA,Dec" '
              'but got "${lines[0].length > 80 ? '${lines[0].substring(0, 80)}...' : lines[0]}"',
          cd11: 0,
          cd12: 0,
          cd21: 0,
          cd22: 0,
          sipAOrder: 0,
          sipBOrder: 0,
          sipACoeffs: _kEmptyCoeffs,
          sipBCoeffs: _kEmptyCoeffs,
          sipApOrder: 0,
          sipBpOrder: 0,
          sipApCoeffs: _kEmptyCoeffs,
          sipBpCoeffs: _kEmptyCoeffs,
        );
      }

      final ra = double.tryParse(parts[0]);
      final dec = double.tryParse(parts[1]);

      if (ra == null || dec == null) {
        return PlateSolveResult(
          success: false,
          ra: 0,
          dec: 0,
          pixelScale: 0,
          rotation: 0,
          fieldWidth: 0,
          fieldHeight: 0,
          solveTimeSecs: 0,
          error:
              'Plate solver output contains non-numeric coordinates: '
              'RA="${parts[0]}", Dec="${parts[1]}"',
          cd11: 0,
          cd12: 0,
          cd21: 0,
          cd22: 0,
          sipAOrder: 0,
          sipBOrder: 0,
          sipACoeffs: _kEmptyCoeffs,
          sipBCoeffs: _kEmptyCoeffs,
          sipApOrder: 0,
          sipBpOrder: 0,
          sipApCoeffs: _kEmptyCoeffs,
          sipBpCoeffs: _kEmptyCoeffs,
        );
      }

      return PlateSolveResult(
        success: true,
        // Keep RA in DEGREES to match the canonical
        // `PlateSolveResult.ra` contract shared with the FFI/network path.
        ra: ra,
        dec: dec,
        pixelScale: 0,
        rotation: 0,
        fieldWidth: 0,
        fieldHeight: 0,
        solveTimeSecs: 0,
        cd11: 0,
        cd12: 0,
        cd21: 0,
        cd22: 0,
        sipAOrder: 0,
        sipBOrder: 0,
        sipACoeffs: _kEmptyCoeffs,
        sipBCoeffs: _kEmptyCoeffs,
        sipApOrder: 0,
        sipBpOrder: 0,
        sipApCoeffs: _kEmptyCoeffs,
        sipBpCoeffs: _kEmptyCoeffs,
      );
    } catch (e) {
      return PlateSolveResult(
        success: false,
        ra: 0,
        dec: 0,
        pixelScale: 0,
        rotation: 0,
        fieldWidth: 0,
        fieldHeight: 0,
        solveTimeSecs: 0,
        error: 'Error parsing output: $e',
        cd11: 0,
        cd12: 0,
        cd21: 0,
        cd22: 0,
        sipAOrder: 0,
        sipBOrder: 0,
        sipACoeffs: _kEmptyCoeffs,
        sipBCoeffs: _kEmptyCoeffs,
        sipApOrder: 0,
        sipBpOrder: 0,
        sipApCoeffs: _kEmptyCoeffs,
        sipBpCoeffs: _kEmptyCoeffs,
      );
    }
  }
}

/// Plate solve service provider
final plateSolveServiceProvider = Provider<PlateSolveService>((ref) {
  final backend = ref.watch(backendProvider);
  final service = PlateSolveService(ref, backend: backend);
  ref.onDispose(service.retire);
  return service;
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
