part of '../network_backend.dart';

/// Backend connection state.
///
/// P2-13: the chip in the mobile UI conflated OS-level connectivity with
/// WebSocket session liveness. Splitting `connecting` (very first attempt)
/// from `reconnecting` (subsequent attempts after a previously-successful
/// connection) and adding a terminal `error` (gave up / hard failure) lets
/// the indicator render "Server unreachable" distinctly from "Reconnecting".
///
/// Why five values rather than three: `connecting` and `reconnecting` both
/// look like "in flight" to the user, but the messaging differs — a fresh
/// connect should not promise "still reconnecting" when there's nothing to
/// reconnect to yet. `error` is reserved for the case where the backend has
/// stopped attempting (e.g. an unrecoverable version mismatch); the legacy
/// `disconnected` state is reused for the post-disconnect idle window while
/// the exponential backoff timer is armed.
enum BackendConnectionState {
  /// Idle — not currently attempting a connection and not connected.
  /// Either disposed, or a backoff timer is armed before the next attempt.
  disconnected,

  /// First-time connect in progress (no prior successful attachment).
  /// Distinct from [reconnecting] so the UI says "Connecting" rather than
  /// "Reconnecting" on the initial handshake.
  connecting,

  /// WebSocket is open and the upgrade handshake completed successfully.
  connected,

  /// A prior connection dropped and the backend is retrying.
  reconnecting,

  /// Terminal failure mode (e.g. API version incompatibility). The backend
  /// stopped attempting; the user must reconfigure or relaunch. Emitting
  /// `error` is rare — most transient failures stay in [reconnecting] until
  /// the backoff window times out.
  error,
}

class RemoteDirectoryEntry {
  final String name;
  final String path;

  const RemoteDirectoryEntry({
    required this.name,
    required this.path,
  });

  factory RemoteDirectoryEntry.fromJson(Map<String, dynamic> json) {
    return RemoteDirectoryEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
    );
  }
}

class RemoteDirectoryListing {
  final String? currentPath;
  final String? parentPath;
  final List<RemoteDirectoryEntry> directories;

  const RemoteDirectoryListing({
    required this.currentPath,
    required this.parentPath,
    required this.directories,
  });

  factory RemoteDirectoryListing.fromJson(Map<String, dynamic> json) {
    final directories = (json['directories'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(RemoteDirectoryEntry.fromJson)
        .toList();
    return RemoteDirectoryListing(
      currentPath: json['currentPath'] as String?,
      parentPath: json['parentPath'] as String?,
      directories: directories,
    );
  }
}

/// Wire shape for `GET /api/filter-wheel/position` (P2-7).
///
/// Mirrors the JSON envelope emitted by `DeviceHandlers
/// .handleFilterWheelGetPosition`. `position` is null when the filter
/// wheel is disconnected or the driver has not yet reported a slot,
/// `name` is null when the driver returned a short slot-name array.
class RemoteFilterWheelPosition {
  final int? position;
  final String? name;
  final bool isMoving;

  const RemoteFilterWheelPosition({
    required this.position,
    required this.name,
    required this.isMoving,
  });

  factory RemoteFilterWheelPosition.fromJson(Map<String, dynamic> json) {
    return RemoteFilterWheelPosition(
      position: (json['position'] as num?)?.toInt(),
      name: json['name'] as String?,
      isMoving: json['isMoving'] as bool? ?? false,
    );
  }
}

class RemoteScienceBundle {
  final List<PhotometryMeasurementRow> photometry;
  final List<FramePhotometricCalibrationRow> calibrations;
  final List<TransparencySampleRow> transparency;
  final List<PsfFieldTileRow> psfTiles;
  final List<ScienceFrameQualityMetricsRow> frameQuality;
  final List<ScienceTileMetricRow> tileMetrics;
  final List<AstrometryResidualVectorRow> residuals;
  final List<MovingObjectCandidateRow> movingObjects;
  final List<LineRatioProductRow> lineRatios;

  const RemoteScienceBundle({
    required this.photometry,
    required this.calibrations,
    required this.transparency,
    required this.psfTiles,
    required this.frameQuality,
    required this.tileMetrics,
    required this.residuals,
    required this.movingObjects,
    required this.lineRatios,
  });
}

class RemoteJob {
  final String jobId;
  final String operation;
  final String? deviceId;
  final String? commandId;
  final String state;
  final double? progress;
  final String? progressMessage;
  final Map<String, dynamic>? result;
  final Map<String, dynamic>? error;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RemoteJob({
    required this.jobId,
    required this.operation,
    required this.state,
    this.deviceId,
    this.commandId,
    this.progress,
    this.progressMessage,
    this.result,
    this.error,
    this.createdAt,
    this.updatedAt,
  });

  bool get isTerminal =>
      state == 'succeeded' || state == 'failed' || state == 'cancelled';

  factory RemoteJob.fromJson(Map<String, dynamic> json) {
    return RemoteJob(
      jobId: json['jobId'] as String? ?? '',
      operation: json['operation'] as String? ?? '',
      deviceId: json['deviceId'] as String?,
      commandId: json['commandId'] as String?,
      state: json['state'] as String? ?? 'unknown',
      progress: (json['progress'] as num?)?.toDouble(),
      progressMessage: json['progressMessage'] as String?,
      result: json['result'] is Map
          ? Map<String, dynamic>.from(json['result'] as Map)
          : null,
      error: json['error'] is Map
          ? Map<String, dynamic>.from(json['error'] as Map)
          : null,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  /// Construct from the `data` map of a job-category NightshadeEvent.
  /// The wire shape there is a subset of [fromJson] (no createdAt /
  /// updatedAt — the event itself carries the timestamp).
  factory RemoteJob.fromEventData(Map<String, dynamic> data) {
    return RemoteJob(
      jobId: data['jobId'] as String? ?? '',
      operation: data['operation'] as String? ?? '',
      deviceId: data['deviceId'] as String?,
      commandId: data['commandId'] as String?,
      state: data['state'] as String? ?? 'unknown',
      progress: (data['progress'] as num?)?.toDouble(),
      progressMessage: data['message'] as String?,
      result: data['result'] is Map
          ? Map<String, dynamic>.from(data['result'] as Map)
          : null,
      error: data['error'] is Map
          ? Map<String, dynamic>.from(data['error'] as Map)
          : null,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }
}

/// Client-side mirror of `GET /api/system/version`. Carries the
/// running build info plus the last-check / last-applied bookkeeping
/// timestamps. All optional fields tolerate missing keys so a future
/// server that drops one (e.g. when the controller cannot persist the
/// state markers) does not break older clients.
class RemoteVersionInfo {
  final String currentVersion;
  final int buildNumber;
  final String channel;
  final String platform;
  final String? dataDir;
  final String? updateServerUrl;
  final DateTime? lastUpdateCheck;
  final DateTime? lastUpdateApplied;

  const RemoteVersionInfo({
    required this.currentVersion,
    required this.buildNumber,
    required this.channel,
    required this.platform,
    this.dataDir,
    this.updateServerUrl,
    this.lastUpdateCheck,
    this.lastUpdateApplied,
  });

  factory RemoteVersionInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? raw) {
      if (raw is! String) return null;
      return DateTime.tryParse(raw);
    }

    return RemoteVersionInfo(
      currentVersion: json['currentVersion'] as String? ?? '',
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 0,
      channel: json['channel'] as String? ?? 'stable',
      platform: json['platform'] as String? ?? '',
      dataDir: json['dataDir'] as String?,
      updateServerUrl: json['updateServerUrl'] as String?,
      lastUpdateCheck: parse(json['lastUpdateCheck']),
      lastUpdateApplied: parse(json['lastUpdateApplied']),
    );
  }
}

/// Client-side mirror of `GET /api/system/update/status`. State is
/// kept loose (string, not enum) so a server that adds a new
/// lifecycle phase does not crash older clients — the caller
/// branches on the wire name.
class RemoteUpdateStatus {
  final String state;
  final String? stagedVersion;
  final DateTime? stagedAt;
  final double? progressPct;
  final String? message;
  final String? lastError;

  const RemoteUpdateStatus({
    required this.state,
    this.stagedVersion,
    this.stagedAt,
    this.progressPct,
    this.message,
    this.lastError,
  });

  bool get hasStagedUpdate => stagedVersion != null;
  bool get isInFlight =>
      state == 'checking' ||
      state == 'downloading' ||
      state == 'verifying' ||
      state == 'installing';

  factory RemoteUpdateStatus.fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? raw) {
      if (raw is! String) return null;
      return DateTime.tryParse(raw);
    }

    return RemoteUpdateStatus(
      state: json['state'] as String? ?? 'idle',
      stagedVersion: json['stagedVersion'] as String?,
      stagedAt: parse(json['stagedAt']),
      progressPct: (json['progressPct'] as num?)?.toDouble(),
      message: json['message'] as String?,
      lastError: json['lastError'] as String?,
    );
  }
}

/// Client-side mirror of `GET /api/system/update/staged`. Returned by
/// [NetworkBackend.getStagedUpdate] when a staged update exists.
class RemoteStagedUpdate {
  final String stagedVersion;
  final int stagedBuildNumber;
  final DateTime? stagedAt;
  final String? manifestHash;
  final int fileCount;
  final int totalBytes;
  final String? sourceUrl;
  final Map<String, String> expectedHashes;

  const RemoteStagedUpdate({
    required this.stagedVersion,
    required this.stagedBuildNumber,
    required this.fileCount,
    required this.totalBytes,
    required this.expectedHashes,
    this.stagedAt,
    this.manifestHash,
    this.sourceUrl,
  });

  factory RemoteStagedUpdate.fromJson(Map<String, dynamic> json) {
    final hashesRaw = json['expectedHashes'];
    final hashes = <String, String>{};
    if (hashesRaw is Map) {
      hashesRaw.forEach((k, v) {
        if (k is String && v is String) {
          hashes[k] = v;
        }
      });
    }
    DateTime? parse(Object? raw) {
      if (raw is! String) return null;
      return DateTime.tryParse(raw);
    }

    return RemoteStagedUpdate(
      stagedVersion: json['stagedVersion'] as String? ?? '',
      stagedBuildNumber: (json['stagedBuildNumber'] as num?)?.toInt() ?? 0,
      stagedAt: parse(json['stagedAt']),
      manifestHash: json['manifestHash'] as String?,
      fileCount: (json['fileCount'] as num?)?.toInt() ?? hashes.length,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      sourceUrl: json['sourceUrl'] as String?,
      expectedHashes: hashes,
    );
  }
}

/// Client-side mirror of the headless server's session-status response.
class RemoteSessionStatus {
  final Map<String, dynamic>? owner;
  final bool isYouTheOwner;
  final String mode; // 'operator' | 'viewer' | 'unowned'
  final int heartbeatTimeoutSeconds;

  const RemoteSessionStatus({
    required this.owner,
    required this.isYouTheOwner,
    required this.mode,
    required this.heartbeatTimeoutSeconds,
  });

  factory RemoteSessionStatus.fromJson(Map<String, dynamic> json) {
    return RemoteSessionStatus(
      owner: json['owner'] is Map
          ? Map<String, dynamic>.from(json['owner'] as Map)
          : null,
      isYouTheOwner: json['isYouTheOwner'] as bool? ?? false,
      mode: json['mode'] as String? ?? 'unowned',
      heartbeatTimeoutSeconds:
          (json['heartbeatTimeoutSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}

// =============================================================================
// P1-12 — Client-side mirrors of the headless server's /api/catalog/... shapes.
// =============================================================================

/// Per-catalog install state surfaced by `GET /api/catalog/status`.
class RemoteCatalogStatus {
  final String name;
  final String? version;
  final int sizeBytes;
  final int fileCount;
  final DateTime? installedAt;
  final DateTime? lastVerified;
  final String? expectedHash;
  final String? actualHash;
  final int? objectCount;

  /// One of `installed`, `partial`, `corrupted`, `missing`.
  final String status;
  final List<String> errors;

  const RemoteCatalogStatus({
    required this.name,
    required this.status,
    this.version,
    this.sizeBytes = 0,
    this.fileCount = 0,
    this.installedAt,
    this.lastVerified,
    this.expectedHash,
    this.actualHash,
    this.objectCount,
    this.errors = const [],
  });

  bool get isInstalled => status == 'installed';

  factory RemoteCatalogStatus.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'];
    return RemoteCatalogStatus(
      name: json['name'] as String? ?? '',
      version: json['version'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      fileCount: (json['fileCount'] as num?)?.toInt() ?? 0,
      installedAt: _parseDateField(json['installedAt']),
      lastVerified: _parseDateField(json['lastVerified']),
      expectedHash: json['expectedHash'] as String?,
      actualHash: json['actualHash'] as String?,
      objectCount: (json['objectCount'] as num?)?.toInt(),
      status: json['status'] as String? ?? 'missing',
      errors: rawErrors is List
          ? rawErrors.map((e) => e.toString()).toList(growable: false)
          : const [],
    );
  }
}

/// Wire response for `GET /api/catalog/status`.
class RemoteCatalogStatusResponse {
  final List<RemoteCatalogStatus> catalogs;
  final int totalBytes;
  final String dataDir;
  final int? availableSpaceBytes;

  const RemoteCatalogStatusResponse({
    required this.catalogs,
    required this.totalBytes,
    required this.dataDir,
    this.availableSpaceBytes,
  });

  factory RemoteCatalogStatusResponse.fromJson(Map<String, dynamic> json) {
    final rawCatalogs = json['catalogs'];
    final catalogs = <RemoteCatalogStatus>[];
    if (rawCatalogs is List) {
      for (final entry in rawCatalogs) {
        if (entry is Map) {
          catalogs
              .add(RemoteCatalogStatus.fromJson(entry.cast<String, dynamic>()));
        }
      }
    }
    return RemoteCatalogStatusResponse(
      catalogs: catalogs,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      dataDir: json['dataDir'] as String? ?? '',
      availableSpaceBytes: (json['availableSpaceBytes'] as num?)?.toInt(),
    );
  }
}

/// One entry in the `GET /api/catalog/available` response.
class RemoteAvailableCatalog {
  final String name;
  final String displayName;
  final String version;
  final String description;
  final String? downloadUrl;
  final int sizeBytes;
  final String? sha256;
  final bool requiredForPlateSolve;

  const RemoteAvailableCatalog({
    required this.name,
    required this.displayName,
    required this.version,
    required this.description,
    this.downloadUrl,
    required this.sizeBytes,
    this.sha256,
    this.requiredForPlateSolve = false,
  });

  factory RemoteAvailableCatalog.fromJson(Map<String, dynamic> json) {
    return RemoteAvailableCatalog(
      name: json['name'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      version: json['version'] as String? ?? '',
      description: json['description'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String?,
      requiredForPlateSolve: json['requiredForPlateSolve'] as bool? ?? false,
    );
  }
}

/// Result of `POST /api/catalog/upload`.
class RemoteCatalogInstallResult {
  final String name;
  final String sha256;
  final int sizeBytes;
  final int objectCount;
  final String version;
  final DateTime? installedAt;

  const RemoteCatalogInstallResult({
    required this.name,
    required this.sha256,
    required this.sizeBytes,
    required this.objectCount,
    required this.version,
    this.installedAt,
  });

  factory RemoteCatalogInstallResult.fromJson(Map<String, dynamic> json) {
    return RemoteCatalogInstallResult(
      name: json['name'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      objectCount: (json['objectCount'] as num?)?.toInt() ?? 0,
      version: json['version'] as String? ?? '',
      installedAt: _parseDateField(json['installedAt']),
    );
  }
}

/// Per-catalog result of `POST /api/catalog/verify`.
class RemoteCatalogVerifyResult {
  final bool ok;
  final String? expectedHash;
  final String? actualHash;
  final List<String> errors;

  const RemoteCatalogVerifyResult({
    required this.ok,
    this.expectedHash,
    this.actualHash,
    this.errors = const [],
  });

  factory RemoteCatalogVerifyResult.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'];
    return RemoteCatalogVerifyResult(
      ok: json['ok'] as bool? ?? false,
      expectedHash: json['expectedHash'] as String?,
      actualHash: json['actualHash'] as String?,
      errors: rawErrors is List
          ? rawErrors.map((e) => e.toString()).toList(growable: false)
          : const [],
    );
  }
}

DateTime? _parseDateField(Object? raw) {
  if (raw is! String) return null;
  return DateTime.tryParse(raw);
}

// =========================================================================
// P2-8 — wire types for the read-only DB endpoints. All endpoints use the
// same `{items, total}` envelope, captured by [RemotePage<T>] so callers
// see one consistent paginated shape regardless of underlying table.
// =========================================================================

/// Generic envelope for paginated `GET` endpoints. `items` is the page
/// content; `total` is the unpaginated row count matching the filter.
