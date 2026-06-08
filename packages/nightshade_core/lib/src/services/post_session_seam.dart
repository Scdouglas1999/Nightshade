import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;

/// Injectable seam over the four post-session batch-processing FFI functions
/// (`apiIntegrateSession`, `apiMasterAccumulate`, `apiBuildMasterFlat`,
/// `apiSaveFitsMaster`).
///
/// **Why this exists.** Those native entry points are free functions on the
/// generated bridge that take a single JSON string and return a JSON string.
/// Calling them directly from the orchestration services would make the
/// services' logic — calibration resolution, per-filter selection, record
/// persistence, multi-night dedup — only exercisable with the Rust dynamic
/// library loaded. This seam mirrors the sibling [StackingEngineSeam] /
/// `StackShareExportService` injection pattern: the production implementation
/// ([BridgePostSessionSeam]) forwards to the bridge, and tests substitute a
/// fake so the service bodies run end-to-end without native code.
///
/// The seam deliberately stays at the *JSON envelope* level (`Map` in,
/// decoded result out): the request shapes are documented on
/// [post_session.rs]'s arg structs, and the strongly-typed result classes below
/// model exactly what the native side returns. Keeping the boundary thin means
/// new native knobs ride inside the request map and never change this interface.
abstract class PostSessionSeam {
  /// One-shot batch integration of a sub list into a linear FITS master.
  ///
  /// [args] is the `IntegrateSessionArgs` JSON shape:
  /// `{ lightPaths, reference?, exposuresSec?, calibration, settings, output }`.
  Future<IntegrateSessionResult> integrateSession(Map<String, dynamic> args);

  /// Multi-night accumulating master. [args] must carry an `op` of
  /// `create` / `add` / `finalize` / `info` plus that op's fields.
  Future<MasterAccumulateResult> masterAccumulate(Map<String, dynamic> args);

  /// Build a unit-mean master flat from raw flats. [args] is the
  /// `BuildMasterFlatArgs` JSON shape.
  Future<BuildMasterFlatResult> buildMasterFlat(Map<String, dynamic> args);

  /// Re-export an in-memory pixel buffer as a FITS master. [args] is the
  /// `SaveFitsMasterArgs` JSON shape.
  Future<SaveFitsMasterResult> saveFitsMaster(Map<String, dynamic> args);
}

/// Production [PostSessionSeam] that encodes each request to JSON, forwards to
/// the native bridge, and decodes the JSON result.
class BridgePostSessionSeam implements PostSessionSeam {
  const BridgePostSessionSeam();

  @override
  Future<IntegrateSessionResult> integrateSession(
      Map<String, dynamic> args) async {
    final out =
        await bridge.apiIntegrateSession(argsJson: jsonEncode(args));
    return IntegrateSessionResult.fromJson(_decodeObject(out));
  }

  @override
  Future<MasterAccumulateResult> masterAccumulate(
      Map<String, dynamic> args) async {
    final out =
        await bridge.apiMasterAccumulate(argsJson: jsonEncode(args));
    return MasterAccumulateResult.fromJson(_decodeObject(out));
  }

  @override
  Future<BuildMasterFlatResult> buildMasterFlat(
      Map<String, dynamic> args) async {
    final out = await bridge.apiBuildMasterFlat(argsJson: jsonEncode(args));
    return BuildMasterFlatResult.fromJson(_decodeObject(out));
  }

  @override
  Future<SaveFitsMasterResult> saveFitsMaster(
      Map<String, dynamic> args) async {
    final out = await bridge.apiSaveFitsMaster(argsJson: jsonEncode(args));
    return SaveFitsMasterResult.fromJson(_decodeObject(out));
  }

  Map<String, dynamic> _decodeObject(String json) {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, dynamic>) return decoded;
    throw FormatException(
      'post-session native call returned a non-object JSON payload',
      json,
    );
  }
}

/// One per-frame record from [IntegrateSessionResult] — what the cull UI shows.
class PerFrameRecord {
  /// On-disk path of the sub this record describes.
  final String path;

  /// Normalized integration weight in (0, 1], or 0 when the frame was dropped.
  final double weight;

  /// RMS registration residual in reference pixels, or null if not registered.
  final double? rmsResidualPx;

  /// Whether the frame contributed to the master.
  final bool accepted;

  /// Human-readable reason when [accepted] is false.
  final String? reason;

  const PerFrameRecord({
    required this.path,
    required this.weight,
    required this.rmsResidualPx,
    required this.accepted,
    required this.reason,
  });

  factory PerFrameRecord.fromJson(Map<String, dynamic> json) {
    return PerFrameRecord(
      path: json['path'] as String,
      weight: (json['weight'] as num?)?.toDouble() ?? 0.0,
      rmsResidualPx: (json['rmsResidualPx'] as num?)?.toDouble(),
      accepted: json['accepted'] as bool? ?? false,
      reason: json['reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'weight': weight,
        'rmsResidualPx': rmsResidualPx,
        'accepted': accepted,
        'reason': reason,
      };
}

/// Decoded result of [PostSessionSeam.integrateSession].
class IntegrateSessionResult {
  final String masterFitsPath;
  final String? previewPath;
  final String? rejectionMapPath;
  final int framesIntegrated;
  final int framesRejected;
  final double totalIntegrationSec;

  /// Mean inlier RMS residual across registered subs (reference px).
  final double rmsResidual;
  final int width;
  final int height;
  final int channels;
  final List<PerFrameRecord> perFrameStats;

  const IntegrateSessionResult({
    required this.masterFitsPath,
    required this.previewPath,
    required this.rejectionMapPath,
    required this.framesIntegrated,
    required this.framesRejected,
    required this.totalIntegrationSec,
    required this.rmsResidual,
    required this.width,
    required this.height,
    required this.channels,
    required this.perFrameStats,
  });

  factory IntegrateSessionResult.fromJson(Map<String, dynamic> json) {
    final frames = (json['perFrameStats'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PerFrameRecord.fromJson)
        .toList(growable: false);
    return IntegrateSessionResult(
      masterFitsPath: json['masterFitsPath'] as String,
      previewPath: json['previewPath'] as String?,
      rejectionMapPath: json['rejectionMapPath'] as String?,
      framesIntegrated: (json['framesIntegrated'] as num?)?.toInt() ?? 0,
      framesRejected: (json['framesRejected'] as num?)?.toInt() ?? 0,
      totalIntegrationSec:
          (json['totalIntegrationSec'] as num?)?.toDouble() ?? 0.0,
      rmsResidual: (json['rmsResidual'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      channels: (json['channels'] as num?)?.toInt() ?? 1,
      perFrameStats: frames,
    );
  }
}

/// Decoded result of [PostSessionSeam.masterAccumulate] (all four ops share it).
class MasterAccumulateResult {
  final String sidecarPath;
  final String? masterPath;
  final String? previewPath;
  final int frameCount;
  final double totalIntegrationSec;
  final int width;
  final int height;
  final int channels;

  /// Frames added in this call (0 for create/finalize/info).
  final int framesAdded;

  /// Samples rejected by the online clip in this call.
  final int rejected;

  const MasterAccumulateResult({
    required this.sidecarPath,
    required this.masterPath,
    required this.previewPath,
    required this.frameCount,
    required this.totalIntegrationSec,
    required this.width,
    required this.height,
    required this.channels,
    required this.framesAdded,
    required this.rejected,
  });

  factory MasterAccumulateResult.fromJson(Map<String, dynamic> json) {
    return MasterAccumulateResult(
      sidecarPath: json['sidecarPath'] as String,
      masterPath: json['masterPath'] as String?,
      previewPath: json['previewPath'] as String?,
      frameCount: (json['frameCount'] as num?)?.toInt() ?? 0,
      totalIntegrationSec:
          (json['totalIntegrationSec'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      channels: (json['channels'] as num?)?.toInt() ?? 1,
      framesAdded: (json['framesAdded'] as num?)?.toInt() ?? 0,
      rejected: (json['rejected'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Decoded result of [PostSessionSeam.buildMasterFlat].
class BuildMasterFlatResult {
  final String outputPath;
  final int frameCount;

  /// Pre-normalization mean (illumination level).
  final double inputMean;

  /// Post-normalization mean (≈ unit-mean target).
  final double outputMean;
  final int width;
  final int height;
  final int channels;
  final String outputBitDepth;

  const BuildMasterFlatResult({
    required this.outputPath,
    required this.frameCount,
    required this.inputMean,
    required this.outputMean,
    required this.width,
    required this.height,
    required this.channels,
    required this.outputBitDepth,
  });

  factory BuildMasterFlatResult.fromJson(Map<String, dynamic> json) {
    return BuildMasterFlatResult(
      outputPath: json['outputPath'] as String,
      frameCount: (json['frameCount'] as num?)?.toInt() ?? 0,
      inputMean: (json['inputMean'] as num?)?.toDouble() ?? 0.0,
      outputMean: (json['outputMean'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      channels: (json['channels'] as num?)?.toInt() ?? 1,
      outputBitDepth: json['outputBitDepth'] as String? ?? 'f32',
    );
  }
}

/// Decoded result of [PostSessionSeam.saveFitsMaster].
class SaveFitsMasterResult {
  final String outputPath;
  final int width;
  final int height;
  final int channels;
  final String pixelType;

  const SaveFitsMasterResult({
    required this.outputPath,
    required this.width,
    required this.height,
    required this.channels,
    required this.pixelType,
  });

  factory SaveFitsMasterResult.fromJson(Map<String, dynamic> json) {
    return SaveFitsMasterResult(
      outputPath: json['outputPath'] as String,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      channels: (json['channels'] as num?)?.toInt() ?? 1,
      pixelType: json['pixelType'] as String? ?? 'f32',
    );
  }
}

/// Provider for the production [PostSessionSeam]. Tests override this with a
/// fake so the orchestration services run end-to-end without native code.
final postSessionSeamProvider = Provider<PostSessionSeam>((ref) {
  return const BridgePostSessionSeam();
});
