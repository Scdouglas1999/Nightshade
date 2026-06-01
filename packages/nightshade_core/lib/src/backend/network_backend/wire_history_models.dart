part of '../network_backend.dart';

class RemotePage<T> {
  final List<T> items;
  final int total;

  const RemotePage({required this.items, required this.total});

  factory RemotePage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw StateError('Malformed paginated response: missing items list');
    }
    final items = rawItems
        .whereType<Map>()
        .map((m) => itemFromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
    return RemotePage(
      items: items,
      total: (json['total'] as num?)?.toInt() ?? items.length,
    );
  }
}

/// Wire row for `/api/sequence-runs`.
class RemoteSequenceRun {
  final int id;
  final int? sequenceId;
  final String? sequenceName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final String? statsJson;

  const RemoteSequenceRun({
    required this.id,
    required this.startedAt,
    required this.status,
    this.sequenceId,
    this.sequenceName,
    this.endedAt,
    this.statsJson,
  });

  factory RemoteSequenceRun.fromJson(Map<String, dynamic> json) {
    return RemoteSequenceRun(
      id: (json['id'] as num).toInt(),
      sequenceId: (json['sequenceId'] as num?)?.toInt(),
      sequenceName: json['sequenceName'] as String?,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: _parseDateField(json['endedAt']),
      status: json['status'] as String? ?? 'unknown',
      statsJson: json['statsJson'] as String?,
    );
  }
}

/// Wire row for `/api/notes-journal`.
class RemoteNotesJournalEntry {
  final int id;
  final DateTime timestamp;
  final String objectName;
  final String? objectType;
  final String? catalogId;
  final double ra;
  final double dec;
  final double? altitude;
  final double? azimuth;
  final String? notes;
  final int? rating;
  final int? equipmentProfileId;
  final String? seeingConditions;
  final String? transparency;
  final String? locationName;
  final double? latitude;
  final double? longitude;

  const RemoteNotesJournalEntry({
    required this.id,
    required this.timestamp,
    required this.objectName,
    required this.ra,
    required this.dec,
    this.objectType,
    this.catalogId,
    this.altitude,
    this.azimuth,
    this.notes,
    this.rating,
    this.equipmentProfileId,
    this.seeingConditions,
    this.transparency,
    this.locationName,
    this.latitude,
    this.longitude,
  });

  factory RemoteNotesJournalEntry.fromJson(Map<String, dynamic> json) {
    return RemoteNotesJournalEntry(
      id: (json['id'] as num).toInt(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      objectName: json['objectName'] as String? ?? '',
      objectType: json['objectType'] as String?,
      catalogId: json['catalogId'] as String?,
      ra: (json['ra'] as num?)?.toDouble() ?? 0.0,
      dec: (json['dec'] as num?)?.toDouble() ?? 0.0,
      altitude: (json['altitude'] as num?)?.toDouble(),
      azimuth: (json['azimuth'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      rating: (json['rating'] as num?)?.toInt(),
      equipmentProfileId: (json['equipmentProfileId'] as num?)?.toInt(),
      seeingConditions: json['seeingConditions'] as String?,
      transparency: json['transparency'] as String?,
      locationName: json['locationName'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}

/// Wire row for `/api/guide-rms-history`.
class RemoteGuideRmsHistoryEntry {
  final int id;
  final int? sessionId;
  final String? mountId;
  final int? targetId;
  final double totalRmsArcsec;
  final int sampleCount;
  final double? exposureSeconds;
  final DateTime recordedAt;

  const RemoteGuideRmsHistoryEntry({
    required this.id,
    required this.totalRmsArcsec,
    required this.sampleCount,
    required this.recordedAt,
    this.sessionId,
    this.mountId,
    this.targetId,
    this.exposureSeconds,
  });

  factory RemoteGuideRmsHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RemoteGuideRmsHistoryEntry(
      id: (json['id'] as num).toInt(),
      sessionId: (json['sessionId'] as num?)?.toInt(),
      mountId: json['mountId'] as String?,
      targetId: (json['targetId'] as num?)?.toInt(),
      totalRmsArcsec: (json['totalRmsArcsec'] as num?)?.toDouble() ?? 0.0,
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
      exposureSeconds: (json['exposureSeconds'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(json['recordedAt'] as String),
    );
  }
}

/// Wire row for `/api/polar-alignment-history`.
class RemotePolarAlignmentHistoryEntry {
  final int id;
  final int? equipmentProfileId;
  final double? initialAzimuthError;
  final double? initialAltitudeError;
  final double? initialTotalError;
  final double? finalAzimuthError;
  final double? finalAltitudeError;
  final double? finalTotalError;
  final DateTime startedAt;
  final DateTime completedAt;
  final bool autoCompleted;
  final bool isNorth;
  final String? configJson;

  const RemotePolarAlignmentHistoryEntry({
    required this.id,
    required this.startedAt,
    required this.completedAt,
    required this.autoCompleted,
    required this.isNorth,
    this.equipmentProfileId,
    this.initialAzimuthError,
    this.initialAltitudeError,
    this.initialTotalError,
    this.finalAzimuthError,
    this.finalAltitudeError,
    this.finalTotalError,
    this.configJson,
  });

  factory RemotePolarAlignmentHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RemotePolarAlignmentHistoryEntry(
      id: (json['id'] as num).toInt(),
      equipmentProfileId: (json['equipmentProfileId'] as num?)?.toInt(),
      initialAzimuthError: (json['initialAzimuthError'] as num?)?.toDouble(),
      initialAltitudeError: (json['initialAltitudeError'] as num?)?.toDouble(),
      initialTotalError: (json['initialTotalError'] as num?)?.toDouble(),
      finalAzimuthError: (json['finalAzimuthError'] as num?)?.toDouble(),
      finalAltitudeError: (json['finalAltitudeError'] as num?)?.toDouble(),
      finalTotalError: (json['finalTotalError'] as num?)?.toDouble(),
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: DateTime.parse(json['completedAt'] as String),
      autoCompleted: json['autoCompleted'] as bool? ?? false,
      isNorth: json['isNorth'] as bool? ?? true,
      configJson: json['configJson'] as String?,
    );
  }
}

/// Wire row for `/api/db/dark-library` (P2-8). Distinct from
/// [RemoteDarkLibraryEntry] in `models/calibration/`: that one is the
/// calibration UI's projection (P1-10) which elides several columns the
/// raw read surface keeps (master frame path, master count).
class RemoteDbDarkLibraryRow {
  final int id;
  final String filePath;
  final String frameType;
  final double exposureTime;
  final int gain;
  final int offset;
  final int binX;
  final int binY;
  final double? temperature;
  final int width;
  final int height;
  final String? masterDarkPath;
  final int masterFrameCount;
  final DateTime createdAt;

  const RemoteDbDarkLibraryRow({
    required this.id,
    required this.filePath,
    required this.frameType,
    required this.exposureTime,
    required this.gain,
    required this.offset,
    required this.binX,
    required this.binY,
    required this.width,
    required this.height,
    required this.masterFrameCount,
    required this.createdAt,
    this.temperature,
    this.masterDarkPath,
  });

  factory RemoteDbDarkLibraryRow.fromJson(Map<String, dynamic> json) {
    return RemoteDbDarkLibraryRow(
      id: (json['id'] as num).toInt(),
      filePath: json['filePath'] as String? ?? '',
      frameType: json['frameType'] as String? ?? 'dark',
      exposureTime: (json['exposureTime'] as num?)?.toDouble() ?? 0.0,
      gain: (json['gain'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      binX: (json['binX'] as num?)?.toInt() ?? 1,
      binY: (json['binY'] as num?)?.toInt() ?? 1,
      temperature: (json['temperature'] as num?)?.toDouble(),
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      masterDarkPath: json['masterDarkPath'] as String?,
      masterFrameCount: (json['masterFrameCount'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// Wire row for `/api/db/flat-history` (P2-8). See [RemoteDbDarkLibraryRow]
/// for the rationale for keeping this distinct from
/// [RemoteFlatHistoryEntry].
class RemoteDbFlatHistoryRow {
  final int id;
  final String filterName;
  final double exposureTime;
  final double histogramTarget;
  final double actualAdu;
  final int? equipmentProfileId;
  final int? panelBrightness;
  final double? skyAduRate;
  final String? twilightPhase;
  final int gain;
  final int binning;
  final DateTime timestamp;

  const RemoteDbFlatHistoryRow({
    required this.id,
    required this.filterName,
    required this.exposureTime,
    required this.histogramTarget,
    required this.actualAdu,
    required this.gain,
    required this.binning,
    required this.timestamp,
    this.equipmentProfileId,
    this.panelBrightness,
    this.skyAduRate,
    this.twilightPhase,
  });

  factory RemoteDbFlatHistoryRow.fromJson(Map<String, dynamic> json) {
    return RemoteDbFlatHistoryRow(
      id: (json['id'] as num).toInt(),
      filterName: json['filterName'] as String? ?? '',
      exposureTime: (json['exposureTime'] as num?)?.toDouble() ?? 0.0,
      histogramTarget: (json['histogramTarget'] as num?)?.toDouble() ?? 0.0,
      actualAdu: (json['actualAdu'] as num?)?.toDouble() ?? 0.0,
      equipmentProfileId: (json['equipmentProfileId'] as num?)?.toInt(),
      panelBrightness: (json['panelBrightness'] as num?)?.toInt(),
      skyAduRate: (json['skyAduRate'] as num?)?.toDouble(),
      twilightPhase: json['twilightPhase'] as String?,
      gain: (json['gain'] as num?)?.toInt() ?? 0,
      binning: (json['binning'] as num?)?.toInt() ?? 1,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

// Wave 7B — wire types for per-run replay endpoints.

class RemoteSequenceRunDetail {
  final int id;
  final int? sequenceId;
  final String? sequenceName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final String? statsJson;
  final int frameCount;
  final String? targetName;

  const RemoteSequenceRunDetail({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.frameCount,
    this.sequenceId,
    this.sequenceName,
    this.endedAt,
    this.statsJson,
    this.targetName,
  });

  factory RemoteSequenceRunDetail.fromJson(Map<String, dynamic> json) {
    return RemoteSequenceRunDetail(
      id: (json['id'] as num).toInt(),
      sequenceId: (json['sequenceId'] as num?)?.toInt(),
      sequenceName: json['sequenceName'] as String?,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: _parseDateField(json['endedAt']),
      status: json['status'] as String? ?? 'unknown',
      statsJson: json['statsJson'] as String?,
      frameCount: (json['frameCount'] as num?)?.toInt() ?? 0,
      targetName: json['targetName'] as String?,
    );
  }

  Duration? get duration {
    final end = endedAt;
    if (end == null) return null;
    return end.difference(startedAt);
  }
}

class RemoteReplayEvent {
  final DateTime timestamp;
  final int timestampMs;
  final String severity;
  final String? source;
  final String message;
  final Map<String, dynamic>? fields;

  const RemoteReplayEvent({
    required this.timestamp,
    required this.timestampMs,
    required this.severity,
    required this.message,
    this.source,
    this.fields,
  });

  factory RemoteReplayEvent.fromJson(Map<String, dynamic> json) {
    final ts = json['timestamp'];
    final tsMs = json['timestampMs'];
    final timestamp = ts is String ? DateTime.parse(ts) : DateTime.now();
    final timestampMs =
        (tsMs as num?)?.toInt() ?? timestamp.millisecondsSinceEpoch;
    final rawFields = json['fields'];
    return RemoteReplayEvent(
      timestamp: timestamp,
      timestampMs: timestampMs,
      severity: json['severity'] as String? ?? 'info',
      source: json['source'] as String?,
      message: json['message'] as String? ?? '',
      fields: rawFields is Map ? rawFields.cast<String, dynamic>() : null,
    );
  }
}

class RemoteReplayEventsPage {
  final List<RemoteReplayEvent> items;
  final int total;
  final bool isPartial;
  final String? partialReason;
  final String source;

  const RemoteReplayEventsPage({
    required this.items,
    required this.total,
    required this.isPartial,
    required this.source,
    this.partialReason,
  });

  factory RemoteReplayEventsPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw StateError('Malformed replay-events page: missing items list');
    }
    final items = rawItems
        .whereType<Map>()
        .map((m) => RemoteReplayEvent.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
    return RemoteReplayEventsPage(
      items: items,
      total: (json['total'] as num?)?.toInt() ?? items.length,
      isPartial: (json['is_partial'] as bool?) ??
          (json['isPartial'] as bool?) ??
          false,
      partialReason: json['partialReason'] as String?,
      source: json['source'] as String? ?? 'unknown',
    );
  }
}

class RemoteReplayFrame {
  final int id;
  final String fileName;
  final String filePath;
  final DateTime capturedAt;
  final int capturedAtMs;
  final String frameType;
  final double exposureDuration;
  final String? filter;
  final int? gain;
  final int? offset;
  final int binX;
  final int binY;
  final double? sensorTemp;
  final double? hfr;
  final int? starCount;
  final double? background;
  final double? noise;
  final double? qualityScore;
  final double? guidingRmsRa;
  final double? guidingRmsDec;
  final double? guidingRmsTotal;
  final double? mountRa;
  final double? mountDec;
  final double? mountAltitude;
  final double? mountAzimuth;
  final int? focuserPosition;
  final bool isAccepted;
  final String? rejectionReason;
  final int? sessionId;
  final int? targetId;

  const RemoteReplayFrame({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.capturedAt,
    required this.capturedAtMs,
    required this.frameType,
    required this.exposureDuration,
    required this.binX,
    required this.binY,
    required this.isAccepted,
    this.filter,
    this.gain,
    this.offset,
    this.sensorTemp,
    this.hfr,
    this.starCount,
    this.background,
    this.noise,
    this.qualityScore,
    this.guidingRmsRa,
    this.guidingRmsDec,
    this.guidingRmsTotal,
    this.mountRa,
    this.mountDec,
    this.mountAltitude,
    this.mountAzimuth,
    this.focuserPosition,
    this.rejectionReason,
    this.sessionId,
    this.targetId,
  });

  factory RemoteReplayFrame.fromJson(Map<String, dynamic> json) {
    final ts = json['capturedAt'];
    final tsMs = json['capturedAtMs'];
    final capturedAt = ts is String ? DateTime.parse(ts) : DateTime.now();
    final capturedAtMs =
        (tsMs as num?)?.toInt() ?? capturedAt.millisecondsSinceEpoch;
    return RemoteReplayFrame(
      id: (json['id'] as num).toInt(),
      fileName: json['fileName'] as String? ?? '',
      filePath: json['filePath'] as String? ?? '',
      capturedAt: capturedAt,
      capturedAtMs: capturedAtMs,
      frameType: json['frameType'] as String? ?? 'light',
      exposureDuration: (json['exposureDuration'] as num?)?.toDouble() ?? 0.0,
      filter: json['filter'] as String?,
      gain: (json['gain'] as num?)?.toInt(),
      offset: (json['offset'] as num?)?.toInt(),
      binX: (json['binX'] as num?)?.toInt() ?? 1,
      binY: (json['binY'] as num?)?.toInt() ?? 1,
      sensorTemp: (json['sensorTemp'] as num?)?.toDouble(),
      hfr: (json['hfr'] as num?)?.toDouble(),
      starCount: (json['starCount'] as num?)?.toInt(),
      background: (json['background'] as num?)?.toDouble(),
      noise: (json['noise'] as num?)?.toDouble(),
      qualityScore: (json['qualityScore'] as num?)?.toDouble(),
      guidingRmsRa: (json['guidingRmsRa'] as num?)?.toDouble(),
      guidingRmsDec: (json['guidingRmsDec'] as num?)?.toDouble(),
      guidingRmsTotal: (json['guidingRmsTotal'] as num?)?.toDouble(),
      mountRa: (json['mountRa'] as num?)?.toDouble(),
      mountDec: (json['mountDec'] as num?)?.toDouble(),
      mountAltitude: (json['mountAltitude'] as num?)?.toDouble(),
      mountAzimuth: (json['mountAzimuth'] as num?)?.toDouble(),
      focuserPosition: (json['focuserPosition'] as num?)?.toInt(),
      isAccepted: json['isAccepted'] as bool? ?? true,
      rejectionReason: json['rejectionReason'] as String?,
      sessionId: (json['sessionId'] as num?)?.toInt(),
      targetId: (json['targetId'] as num?)?.toInt(),
    );
  }
}

// =========================================================================
// P2-11 — wire types for the plugin management endpoints.
// =========================================================================

/// Wire row for `/api/plugins`, returned individually by upload/enable/
/// disable. Mirrors the on-disk plugin manifest that the
/// PluginManagementService maintains under app-data.
class RemotePluginManifest {
  final String id;
  final String name;
  final String version;
  final String? description;
  final String? author;
  final bool enabled;
  final bool signed;
  final bool signatureValid;
  final String? sha256;
  final int? sizeBytes;
  final DateTime? installedAt;
  final String? installedFilename;
  final String? loadError;

  const RemotePluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.enabled,
    required this.signed,
    required this.signatureValid,
    this.description,
    this.author,
    this.sha256,
    this.sizeBytes,
    this.installedAt,
    this.installedFilename,
    this.loadError,
  });

  factory RemotePluginManifest.fromJson(Map<String, dynamic> json) {
    return RemotePluginManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      description: json['description'] as String?,
      author: json['author'] as String?,
      enabled: json['enabled'] as bool? ?? false,
      signed: json['signed'] as bool? ?? false,
      signatureValid: json['signatureValid'] as bool? ?? false,
      sha256: json['sha256'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      installedAt: _parseDateField(json['installedAt']),
      installedFilename: json['installedFilename'] as String?,
      loadError: json['loadError'] as String?,
    );
  }
}

/// Helper function to consolidate HTTP response bytes
Future<List<int>> consolidateHttpClientResponseBytes(
    HttpClientResponse response) {
  final completer = Completer<List<int>>();
  final chunks = <List<int>>[];

  response.listen(
    (chunk) => chunks.add(chunk),
    onDone: () => completer.complete(chunks.expand((x) => x).toList()),
    onError: completer.completeError,
    cancelOnError: true,
  );

  return completer.future;
}
