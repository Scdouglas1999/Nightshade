/// Lifecycle status of an [IntegratedMaster] row.
enum IntegratedMasterStatus {
  /// A multi-night master still accepting new folds; `sidecarPath` holds the
  /// resumable accumulator state.
  accumulating,

  /// A finalized master with a shareable FITS on disk. (Accumulating masters
  /// stay re-finalizable, so this does not imply the sidecar was deleted.)
  finalized;

  String get wire =>
      this == IntegratedMasterStatus.accumulating ? 'accumulating' : 'finalized';

  static IntegratedMasterStatus fromWire(String value) {
    switch (value) {
      case 'accumulating':
        return IntegratedMasterStatus.accumulating;
      case 'finalized':
        return IntegratedMasterStatus.finalized;
      default:
        // Unknown persisted value forward-migrates to the safe terminal state
        // rather than throwing on read.
        return IntegratedMasterStatus.finalized;
    }
  }
}

/// How a master's pixels were combined — distinguishes a one-shot batch
/// integration from a multi-night running accumulator (the latter uses an
/// online clip and is honest that it is not a full batch re-clip).
enum AccumulationMode {
  /// One-shot batch integration over the full aligned population.
  batch,

  /// Persisted running weighted mean with an online clip (multi-night).
  runningWeightedMean;

  String get wire =>
      this == AccumulationMode.batch ? 'batch' : 'runningWeightedMean';

  static AccumulationMode fromWire(String value) {
    switch (value) {
      case 'runningWeightedMean':
        return AccumulationMode.runningWeightedMean;
      case 'batch':
      default:
        return AccumulationMode.batch;
    }
  }
}

/// A persisted record of one integrated master (the `integrated_masters` row).
///
/// This is the Dart mirror of the raw-DDL table documented in
/// `database/tables/post_session_tables.dart`. It is an immutable value type
/// with value equality and JSON-string accessors for the `settings_json` /
/// `stats_json` columns left to the service layer.
class IntegratedMaster {
  final int id;
  final int? targetId;
  final String name;

  /// Linear FITS master path. Null until the first finalize of an accumulating
  /// master.
  final String? masterFitsPath;
  final String? previewPngPath;

  /// Resumable accumulator sidecar (`.nsmaster`). Null for one-shot batch
  /// integrations.
  final String? sidecarPath;
  final String? rejectionMapPath;

  final IntegratedMasterStatus status;
  final AccumulationMode accumulationMode;

  final int channels;
  final int width;
  final int height;
  final int frameCount;
  final double totalIntegrationSeconds;
  final String? filter;

  /// Serialized [IntegrationSettings] JSON.
  final String settingsJson;

  /// Per-run aggregate stats JSON (rms residual, frames rejected, etc.).
  final String statsJson;

  final DateTime createdAt;
  final DateTime updatedAt;

  const IntegratedMaster({
    required this.id,
    required this.targetId,
    required this.name,
    required this.masterFitsPath,
    required this.previewPngPath,
    required this.sidecarPath,
    required this.rejectionMapPath,
    required this.status,
    required this.accumulationMode,
    required this.channels,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.totalIntegrationSeconds,
    required this.filter,
    required this.settingsJson,
    required this.statsJson,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isColor => channels >= 3;

  IntegratedMaster copyWith({
    String? name,
    String? masterFitsPath,
    String? previewPngPath,
    String? sidecarPath,
    String? rejectionMapPath,
    IntegratedMasterStatus? status,
    AccumulationMode? accumulationMode,
    int? channels,
    int? width,
    int? height,
    int? frameCount,
    double? totalIntegrationSeconds,
    String? filter,
    String? settingsJson,
    String? statsJson,
    DateTime? updatedAt,
  }) {
    return IntegratedMaster(
      id: id,
      targetId: targetId,
      name: name ?? this.name,
      masterFitsPath: masterFitsPath ?? this.masterFitsPath,
      previewPngPath: previewPngPath ?? this.previewPngPath,
      sidecarPath: sidecarPath ?? this.sidecarPath,
      rejectionMapPath: rejectionMapPath ?? this.rejectionMapPath,
      status: status ?? this.status,
      accumulationMode: accumulationMode ?? this.accumulationMode,
      channels: channels ?? this.channels,
      width: width ?? this.width,
      height: height ?? this.height,
      frameCount: frameCount ?? this.frameCount,
      totalIntegrationSeconds:
          totalIntegrationSeconds ?? this.totalIntegrationSeconds,
      filter: filter ?? this.filter,
      settingsJson: settingsJson ?? this.settingsJson,
      statsJson: statsJson ?? this.statsJson,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IntegratedMaster &&
          other.id == id &&
          other.targetId == targetId &&
          other.name == name &&
          other.masterFitsPath == masterFitsPath &&
          other.previewPngPath == previewPngPath &&
          other.sidecarPath == sidecarPath &&
          other.rejectionMapPath == rejectionMapPath &&
          other.status == status &&
          other.accumulationMode == accumulationMode &&
          other.channels == channels &&
          other.width == width &&
          other.height == height &&
          other.frameCount == frameCount &&
          other.totalIntegrationSeconds == totalIntegrationSeconds &&
          other.filter == filter &&
          other.settingsJson == settingsJson &&
          other.statsJson == statsJson &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
        id,
        targetId,
        name,
        masterFitsPath,
        previewPngPath,
        sidecarPath,
        rejectionMapPath,
        status,
        accumulationMode,
        channels,
        width,
        height,
        frameCount,
        totalIntegrationSeconds,
        filter,
        settingsJson,
        statsJson,
        createdAt,
        updatedAt,
      ]);
}

/// A row of the `integrated_master_frames` join table: one captured sub folded
/// into one master.
class IntegratedMasterFrame {
  final int id;
  final int masterId;
  final int imageId;

  /// Normalized integration weight in (0, 1], or null when the sub was dropped.
  final double? weight;

  /// RMS registration residual (reference px), or null if not registered.
  final double? alignmentResidualPx;

  /// Whether the sub contributed to the master.
  final bool accepted;

  /// Why the sub was dropped (when [accepted] is false).
  final String? rejectionReason;

  final DateTime foldedAt;

  const IntegratedMasterFrame({
    required this.id,
    required this.masterId,
    required this.imageId,
    required this.weight,
    required this.alignmentResidualPx,
    required this.accepted,
    required this.rejectionReason,
    required this.foldedAt,
  });
}

/// A row of the `flat_library` table: one master-flat artifact.
class FlatLibraryEntry {
  final int id;
  final String filePath;
  final String? filter;
  final int? equipmentProfileId;
  final String? opticalTrainId;
  final double? temperature;
  final int gain;
  final int offset;
  final int binX;
  final int binY;
  final int? width;
  final int? height;

  /// `'sky'` | `'panel'` | `'dome'`.
  final String flatKind;
  final int masterFrameCount;
  final DateTime createdAt;

  const FlatLibraryEntry({
    required this.id,
    required this.filePath,
    required this.filter,
    required this.equipmentProfileId,
    required this.opticalTrainId,
    required this.temperature,
    required this.gain,
    required this.offset,
    required this.binX,
    required this.binY,
    required this.width,
    required this.height,
    required this.flatKind,
    required this.masterFrameCount,
    required this.createdAt,
  });
}
