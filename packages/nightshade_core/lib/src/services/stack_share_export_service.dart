import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:path/path.dart' as p;

import '../database/daos/stacked_results_dao.dart';
import '../models/imaging/stack_and_share_models.dart';
import '../providers/profiles_provider.dart';
import 'logging_service.dart';
import 'share_card_renderer.dart';

/// Signature of the function used to persist an 8-bit RGBA buffer as a PNG.
///
/// Defaults to the native bridge ([bridge.apiSaveRgbaPngFile]); injectable so
/// the export path is unit-testable without loading the Rust dynamic library
/// (tests substitute the pure-Dart [ShareCardRenderer]/`image` encoder).
typedef SaveRgbaPng = Future<void> Function({
  required String filePath,
  required int width,
  required int height,
  required List<int> rgba,
});

/// Signature of the function used to persist an 8-bit RGBA buffer as a JPEG.
///
/// Defaults to the native bridge ([bridge.apiSaveRgbaJpegFile]); injectable for
/// the same reason as [SaveRgbaPng].
typedef SaveRgbaJpeg = Future<void> Function({
  required String filePath,
  required int width,
  required int height,
  required List<int> rgba,
  required int quality,
});

/// Thrown when a Stack-and-Share export is requested with an RGBA buffer whose
/// length does not match `width * height * 4`.
///
/// A length mismatch is an upstream programming error (wrong stride, truncated
/// buffer). Per project policy we surface it loudly here — at the Dart boundary,
/// with the offending dimensions — rather than handing a corrupt buffer to the
/// encoder, which would write a plausible-looking but garbage image.
class ShareExportBufferException implements Exception {
  /// Human-readable explanation suitable for direct display.
  final String message;

  const ShareExportBufferException(this.message);

  @override
  String toString() => 'ShareExportBufferException: $message';
}

/// File generation for the **Stack-and-Share Loop** (component C8).
///
/// Owns turning a completed [StackAndShareResult] (plus its stretched RGBA
/// pixels) into share-ready artifacts on disk, and building the AstroBin-style
/// acquisition sidecar that accompanies them:
///
///  * [exportImage] writes the stacked master as PNG, JPEG, or an annotated
///    share card to an explicit path, then stamps that path back onto the
///    persisted result via [StackedResultsDao.updateExportedPath].
///  * [buildAstroBinMetadata] fills the equipment block from the active
///    equipment profile (telescope / camera / focal length / aperture) and the
///    run's frames / integration / filter.
///  * [exportAstroBinSidecar] writes a `.md` (copy-paste acquisition block) and
///    a `.json` (machine-readable payload) next to the image.
///
/// **Why no OS-share call here:** `share_plus` lives in the UI packages'
/// pubspecs, not `nightshade_core`. To respect the package boundary, this
/// service only *generates* the file and returns its path; the actual
/// `Share.shareXFiles(...)` invocation is performed by the screen layer (C9).
/// This keeps `nightshade_core` free of a Flutter-plugin dependency it would
/// otherwise have to take on solely for one call site.
///
/// **Why a copy-paste AstroBin sidecar rather than an upload:** AstroBin
/// exposes no open public API for unattended image upload. The honest,
/// non-stub deliverable is therefore the acquisition block (Markdown) plus a
/// JSON payload that the user pastes into AstroBin's upload form — a real,
/// complete export, not a placeholder for a non-existent API.
///
/// The PNG/JPEG save paths delegate to the native bridge by default (so the
/// pixel write matches every other image export in the app), but the save
/// functions are injectable so this service is unit-testable without the Rust
/// dynamic library loaded.
class StackShareExportService {
  StackShareExportService(
    this._ref, {
    SaveRgbaPng? savePng,
    SaveRgbaJpeg? saveJpeg,
    ShareCardRenderer cardRenderer = const ShareCardRenderer(),
  })  : _savePng = savePng ?? bridge.apiSaveRgbaPngFile,
        _saveJpeg = saveJpeg ?? bridge.apiSaveRgbaJpegFile,
        _cardRenderer = cardRenderer;

  final Ref _ref;
  final SaveRgbaPng _savePng;
  final SaveRgbaJpeg _saveJpeg;
  final ShareCardRenderer _cardRenderer;

  LoggingService get _logger => _ref.read(loggingServiceProvider);
  StackedResultsDao get _resultsDao => _ref.read(stackedResultsDaoProvider);

  /// Export [result]'s stacked master to [outputPath] in the requested
  /// [format], returning the absolute path written.
  ///
  /// [rgba] is the already-stretched 8-bit RGBA display buffer for the
  /// integration (tightly packed `R,G,B,A`, `result.width * result.height * 4`
  /// bytes long); it is typically [StackAndShareService.lastRgbaResult]'s pixels.
  ///
  ///  * [ShareExportFormat.png] / [ShareExportFormat.jpeg] write the bare
  ///    stacked master (no overlay) via the native bridge save path.
  ///  * [ShareExportFormat.shareCard] composites the watermark + stat overlay
  ///    described by [cardSpec] onto the image with [ShareCardRenderer] and
  ///    writes the resulting bytes to disk. The card's file format follows the
  ///    [outputPath] extension: a `.jpg`/`.jpeg` path emits JPEG (honouring
  ///    [jpegQuality]); anything else emits PNG.
  ///
  /// When [result] has a persisted [StackAndShareResult.id], the written path is
  /// stamped onto its row via [StackedResultsDao.updateExportedPath] so the
  /// stacked master can be re-shared later.
  ///
  /// Throws [ShareExportBufferException] when [rgba] is shorter than
  /// `width * height * 4`, [ArgumentError] when [format] is
  /// [ShareExportFormat.shareCard] but no [cardSpec] is supplied, and
  /// [RangeError] when [jpegQuality] is outside `[1, 100]`. Errors are never
  /// swallowed.
  Future<String> exportImage({
    required StackAndShareResult result,
    required Uint8List rgba,
    required ShareExportFormat format,
    required String outputPath,
    ShareCardSpec? cardSpec,
    int jpegQuality = 92,
  }) async {
    final width = result.width;
    final height = result.height;
    _validateBuffer(rgba: rgba, width: width, height: height);

    final absolutePath = p.normalize(p.absolute(outputPath));
    await _ensureParentDirectory(absolutePath);

    switch (format) {
      case ShareExportFormat.png:
        await _savePng(
          filePath: absolutePath,
          width: width,
          height: height,
          rgba: rgba,
        );
      case ShareExportFormat.jpeg:
        _validateJpegQuality(jpegQuality);
        await _saveJpeg(
          filePath: absolutePath,
          width: width,
          height: height,
          rgba: rgba,
          quality: jpegQuality,
        );
      case ShareExportFormat.shareCard:
        if (cardSpec == null) {
          throw ArgumentError.notNull('cardSpec');
        }
        await _writeShareCard(
          width: width,
          height: height,
          rgba: rgba,
          spec: cardSpec,
          outputPath: absolutePath,
          jpegQuality: jpegQuality,
        );
    }

    await _verifyWritten(absolutePath, format);

    final id = result.id;
    if (id != null) {
      final updated = await _resultsDao.updateExportedPath(id, absolutePath);
      if (updated == 0) {
        // The result claims a persisted id but no row matched — a stale id is a
        // genuine inconsistency, not a benign miss, so log it rather than
        // silently dropping the provenance link.
        _logger.warning(
          'Stack-and-Share export stamped path on result id $id but no '
          'stacked_results row was updated (stale id).',
          source: 'StackShareExportService',
        );
      }
    }

    _logger.info(
      'Stack-and-Share exported ${format.name} to $absolutePath '
      '(${width}x$height)',
      source: 'StackShareExportService',
    );
    return absolutePath;
  }

  /// Composite [spec]'s overlay onto the RGBA buffer and write the share card.
  ///
  /// The output format follows the [outputPath] extension: `.jpg`/`.jpeg`
  /// emit JPEG (honouring [jpegQuality]); every other extension emits PNG so a
  /// `.png` path stays lossless.
  Future<void> _writeShareCard({
    required int width,
    required int height,
    required Uint8List rgba,
    required ShareCardSpec spec,
    required String outputPath,
    required int jpegQuality,
  }) async {
    final ext = p.extension(outputPath).toLowerCase();
    final isJpeg = ext == '.jpg' || ext == '.jpeg';
    final Uint8List bytes;
    if (isJpeg) {
      _validateJpegQuality(jpegQuality);
      bytes = _cardRenderer.renderJpegFromRgba(
        width: width,
        height: height,
        rgba: rgba,
        spec: spec,
        quality: jpegQuality,
      );
    } else {
      bytes = _cardRenderer.renderPngFromRgba(
        width: width,
        height: height,
        rgba: rgba,
        spec: spec,
      );
    }
    await File(outputPath).writeAsBytes(bytes, flush: true);
  }

  /// Build the AstroBin-style acquisition metadata for [result].
  ///
  /// Equipment fields are taken from [profile] when supplied, otherwise from the
  /// active equipment profile ([activeEquipmentProfileProvider]). The telescope
  /// description prefers the explicit [EquipmentProfileModel.telescopeName],
  /// falling back to the camera-side optical-train fields; the camera comes from
  /// [EquipmentProfileModel.cameraName]. Focal length / aperture prefer the
  /// profile-level (effective, post-reducer/barlow) values, falling back to the
  /// bare telescope optics only when the profile value is unset.
  ///
  /// Frames, total integration, filter, and title come from the run [result]
  /// itself. Nothing is fabricated — a field with no source stays null so the
  /// acquisition block omits it rather than printing a guess.
  AstroBinExportMetadata buildAstroBinMetadata({
    required StackAndShareResult result,
    EquipmentProfileModel? profile,
  }) {
    final p0 = profile ?? _ref.read(activeEquipmentProfileProvider);

    final telescope = _firstNonEmpty([
      p0?.telescopeName,
    ]);
    final camera = _firstNonEmpty([
      p0?.cameraName,
    ]);

    // Prefer the profile-level optical values — these are the *effective*
    // focal length / aperture of the imaging train (post reducer / barlow),
    // which is the true acquisition value AstroBin wants. Fall back to the bare
    // telescope optics only when the profile-level value is unset. This matches
    // the `EquipmentProfileExtension.effectiveFocalLength` convention used
    // elsewhere (base field preferred over the telescope field); preferring the
    // telescope value first would report the wrong focal length / f-ratio for
    // anyone using a focal reducer or barlow. A non-positive value is treated
    // as "unknown" so f-ratio math never divides by zero.
    final focalLength = _firstPositive([
      p0?.focalLength,
      p0?.telescopeFocalLength,
    ]);
    final aperture = _firstPositive([
      p0?.aperture,
      p0?.telescopeAperture,
    ]);

    return AstroBinExportMetadata(
      title: result.targetName,
      integrationSecs: result.integrationSecs,
      frames: result.framesStacked,
      telescope: telescope,
      camera: camera,
      filter: result.filter,
      focalLength: focalLength,
      aperture: aperture,
    );
  }

  /// Write the AstroBin acquisition sidecar for [meta] next to the image.
  ///
  /// [outputPath] is the path of the exported image (e.g. `/exports/m51.png`);
  /// the sidecar files are written alongside it with the image's basename and a
  /// `.md` / `.json` extension (e.g. `/exports/m51.md`, `/exports/m51.json`).
  /// The `.md` file is the copy-paste acquisition block ([toMarkdown]); the
  /// `.json` file is the machine-readable payload ([toJson]).
  ///
  /// Returns the path of the Markdown sidecar (the primary, human-facing file).
  /// The JSON sidecar shares its basename and sits beside it.
  Future<String> exportAstroBinSidecar({
    required AstroBinExportMetadata meta,
    required String outputPath,
  }) async {
    final absolutePath = p.normalize(p.absolute(outputPath));
    await _ensureParentDirectory(absolutePath);

    final dir = p.dirname(absolutePath);
    final base = p.basenameWithoutExtension(absolutePath);
    final markdownPath = p.join(dir, '$base.md');
    final jsonPath = p.join(dir, '$base.json');

    await File(markdownPath).writeAsString(
      '${meta.toMarkdown()}\n',
      flush: true,
    );
    await File(jsonPath).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(meta.toJson())}\n',
      flush: true,
    );

    _logger.info(
      'Stack-and-Share wrote AstroBin sidecar: $markdownPath + $jsonPath',
      source: 'StackShareExportService',
    );
    return markdownPath;
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  void _validateBuffer({
    required Uint8List rgba,
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) {
      throw ShareExportBufferException(
        'Stack-and-Share export has non-positive dimensions '
        '(width=$width height=$height)',
      );
    }
    final expected = width * height * 4;
    if (rgba.length != expected) {
      throw ShareExportBufferException(
        'Stack-and-Share RGBA buffer length ${rgba.length} != expected '
        '$expected (width=$width height=$height x 4 channels)',
      );
    }
  }

  void _validateJpegQuality(int quality) {
    if (quality < 1 || quality > 100) {
      throw RangeError.range(quality, 1, 100, 'jpegQuality');
    }
  }

  Future<void> _ensureParentDirectory(String absolutePath) async {
    final parent = Directory(p.dirname(absolutePath));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
  }

  /// Assert the export actually produced a non-empty file. A zero-byte image is
  /// a silent corruption a user would only discover when the share fails, so we
  /// catch it here at the source.
  Future<void> _verifyWritten(String path, ShareExportFormat format) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError(
        'Stack-and-Share ${format.name} export reported success but no file '
        'exists at $path',
      );
    }
    final length = await file.length();
    if (length <= 0) {
      throw StateError(
        'Stack-and-Share ${format.name} export wrote an empty file at $path',
      );
    }
  }

  /// First trimmed, non-empty string in [candidates], or null when none qualify.
  String? _firstNonEmpty(List<String?> candidates) {
    for (final candidate in candidates) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  /// First strictly-positive value in [candidates], or null when none qualify.
  double? _firstPositive(List<double?> candidates) {
    for (final candidate in candidates) {
      if (candidate != null && candidate > 0) return candidate;
    }
    return null;
  }
}

/// Provider for the [StackShareExportService].
///
/// Reads the results DAO, active equipment profile, and logging providers
/// lazily inside the service so it follows the same Drift instance and backend
/// as the rest of the app, and so test overrides flow through. The save
/// functions default to the native bridge; tests construct the service directly
/// with pure-Dart substitutes.
final stackShareExportServiceProvider =
    Provider<StackShareExportService>((ref) {
  return StackShareExportService(ref);
});
