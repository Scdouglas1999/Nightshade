// Sidecar JPEG thumbnail caching for captured FITS frames.
//
// Without caching, every `GET /api/images/{id}/thumbnail` request triggers
// a cold FITS read + stretch + JPEG encode in Rust. Loading a 200-image
// gallery from a phone over a slow link took minutes on Pi-class hardware.
//
// This service generates a `{filePath}.thumb.jpg` next to every newly
// captured FITS (asynchronously via `unawaited(...)` so the capture path
// never blocks) and self-heals legacy rows on demand. The session
// handlers consult the sidecar first and only fall back to the FFI when
// the file is missing.
//
// Failed sidecar writes are logged at warning severity — not error,
// because the captured image is fully usable without a sidecar; the
// cold-read fallback handles missing sidecars. The warning IS real
// ("errors are a feature; silent fallbacks hide bugs for
// months"); we surface every failure rather than swallowing it.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge_api;

import '../database/daos/images_dao.dart';
import 'logging_service.dart';

/// Function signature for converting a FITS path to JPEG bytes. The
/// default production binding calls `bridge_api.apiGenerateFitsThumbnail`;
/// tests inject a deterministic stub so they don't need the Rust runtime.
typedef FitsThumbnailBytesGenerator =
    Future<Uint8List> Function({
      required String filePath,
      required int maxSize,
    });

/// Default sidecar max-edge in pixels. Mirrors the value baked into the
/// existing on-demand path (`ffi_backend.dart::getImageThumbnail` calls
/// `apiGenerateFitsThumbnail(maxSize: 512)`).
const int defaultSidecarMaxSize = 512;

/// Default production wrapper around the Rust FFI. Pulled out so test
/// suites can replace it without touching the bridge.
Future<Uint8List> defaultGenerateFitsThumbnail({
  required String filePath,
  required int maxSize,
}) async {
  final bytes = bridge_api.apiGenerateFitsThumbnail(
    filePath: filePath,
    maxSize: maxSize,
  );
  return Uint8List.fromList(bytes);
}

/// Computes the canonical sidecar path for a given FITS frame. The
/// `.thumb.jpg` suffix is appended to the full source path so two
/// frames with the same basename in different folders never collide.
String sidecarPathForFits(String fitsPath) => '$fitsPath.thumb.jpg';

/// Result of a sidecar write attempt. Returned synchronously from
/// [ThumbnailSidecarService.writeSidecar] when callers want to wait
/// (e.g. the regenerate endpoint and the backfill job); the
/// capture-time path uses `unawaited(...)` and ignores the result.
sealed class SidecarWriteResult {
  const SidecarWriteResult();
}

class SidecarWritten extends SidecarWriteResult {
  final File sidecarFile;
  final int byteCount;
  final DateTime mtime;
  const SidecarWritten({
    required this.sidecarFile,
    required this.byteCount,
    required this.mtime,
  });
}

class SidecarSkipped extends SidecarWriteResult {
  /// One of:
  ///   * `missing_source` — the FITS file no longer exists on disk.
  ///   * `empty_source_path` — the row has an empty `file_path`.
  final String reason;
  const SidecarSkipped(this.reason);
}

class SidecarFailed extends SidecarWriteResult {
  final Object error;
  final StackTrace stackTrace;
  const SidecarFailed(this.error, this.stackTrace);
}

/// Generates `.thumb.jpg` sidecars next to captured FITS frames.
class ThumbnailSidecarService {
  final FitsThumbnailBytesGenerator _generate;
  final LoggingService? _logger;
  final int _maxSize;

  ThumbnailSidecarService({
    FitsThumbnailBytesGenerator? generator,
    LoggingService? logger,
    int maxSize = defaultSidecarMaxSize,
  }) : _generate = generator ?? defaultGenerateFitsThumbnail,
       _logger = logger,
       _maxSize = maxSize;

  /// Generate JPEG bytes for [fitsPath] and write them to
  /// `{fitsPath}.thumb.jpg`. Idempotent — overwrites any existing
  /// sidecar. Returns:
  ///
  ///   * [SidecarWritten] on success (sidecar bytes flushed to disk).
  ///   * [SidecarSkipped] when the source FITS is missing.
  ///   * [SidecarFailed] when the FFI call or disk write throws.
  ///
  /// Never throws — callers (especially `unawaited(...)` capture paths)
  /// must not be derailed by sidecar failures, and the structured logger
  /// records every non-success outcome.
  Future<SidecarWriteResult> writeSidecar(String fitsPath) async {
    if (fitsPath.isEmpty) {
      _logger?.warning(
        'ThumbnailSidecarService: refusing to write sidecar for empty path',
        source: 'ThumbnailSidecarService',
      );
      return const SidecarSkipped('empty_source_path');
    }

    final source = File(fitsPath);
    if (!await source.exists()) {
      _logger?.warning(
        'ThumbnailSidecarService: source FITS not on disk: $fitsPath '
        '— skipping sidecar generation',
        source: 'ThumbnailSidecarService',
      );
      return const SidecarSkipped('missing_source');
    }

    try {
      final bytes = await _generate(filePath: fitsPath, maxSize: _maxSize);
      final sidecarPath = sidecarPathForFits(fitsPath);
      final sidecar = File(sidecarPath);
      // `flush: true` so we don't end up with a half-written sidecar if
      // the process is killed mid-write (an SD-card-pulled Pi mid-session
      // is the canonical failure mode).
      await sidecar.writeAsBytes(bytes, flush: true);
      final stat = await sidecar.lastModified();
      return SidecarWritten(
        sidecarFile: sidecar,
        byteCount: bytes.length,
        mtime: stat,
      );
    } catch (e, st) {
      _logger?.warning(
        'ThumbnailSidecarService: failed to write sidecar for $fitsPath: $e',
        source: 'ThumbnailSidecarService',
      );
      return SidecarFailed(e, st);
    }
  }

  /// Generate the sidecar AND stamp the DB row's `thumbnail_path` column
  /// on success. Used by the capture pipeline (fire-and-forget) and by
  /// the backfill job (awaited).
  Future<SidecarWriteResult> writeSidecarForRow({
    required int imageId,
    required String fitsPath,
    required ImagesDao imagesDao,
  }) async {
    final result = await writeSidecar(fitsPath);
    if (result is SidecarWritten) {
      try {
        await imagesDao.setThumbnailPath(imageId, result.sidecarFile.path);
      } catch (e) {
        // Stamping the DB row failed but the file IS on disk — log so
        // the operator knows the GET handler will need to self-heal
        // (it will, by reading the sidecar from the canonical path).
        _logger?.warning(
          'ThumbnailSidecarService: sidecar written but DB stamp failed '
          'for image $imageId: $e',
          source: 'ThumbnailSidecarService',
        );
      }
    } else if (result is SidecarSkipped && result.reason == 'missing_source') {
      // Clear any stale stamp so the GET handler doesn't keep probing
      // a path that will never resolve.
      try {
        await imagesDao.setThumbnailPath(imageId, null);
      } catch (_) {
        // Best-effort cleanup — never let a stamp clear failure
        // propagate.
      }
    }
    return result;
  }

  /// Best-effort fire-and-forget sidecar generation. Called from
  /// capture-pipeline insert paths via `unawaited(...)`. Errors are
  /// logged (inside [writeSidecarForRow]) but never propagate.
  void scheduleSidecarWrite({
    required int imageId,
    required String fitsPath,
    required ImagesDao imagesDao,
  }) {
    unawaited(
      writeSidecarForRow(
        imageId: imageId,
        fitsPath: fitsPath,
        imagesDao: imagesDao,
      ),
    );
  }
}
