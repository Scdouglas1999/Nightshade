// P1-11: thin adapter between [UpdateService] and the headless API's
// `UpdateHandlers`.
//
// Why the indirection: `UpdateService` is bound to the host filesystem
// (the install directory, the staging directory, the on-disk `ready.json`
// marker) and to `Process.start(updater.exe)` for apply. Substituting a
// real instance in a unit test would require either filesystem doubles or
// process doubles — both invasive. By having `UpdateHandlers` depend on
// this abstract surface, the headless test suite can pass a fake
// controller that records calls + drives the `events` stream synthetically
// without touching disk.
//
// The default implementation wraps a real `UpdateService` and bridges its
// state-changing methods onto a broadcast stream of typed `UpdateEvent`s
// so the headless server can fan-out update lifecycle to paired phones
// over the existing WebSocket transport.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/update_manifest.dart';
import 'update_service.dart';

/// Lifecycle states the headless API exposes to clients. Mirrors
/// `UpdateStatus` but with names tuned for the REST surface — e.g. the
/// REST surface combines `available` + `upToDate` into a single `idle`
/// view, while keeping `staged` as a discrete state because the apply
/// gate hinges on it.
enum UpdateLifecycleState {
  /// No update activity in progress.
  idle,

  /// `checkForUpdate` is in flight against the configured server.
  checking,

  /// `downloadUpdate` has started; bytes are streaming to the staging dir.
  downloading,

  /// Bytes are on disk and the manifest signature + per-file hashes are
  /// being verified before we promote to `staged`.
  verifying,

  /// A verified update is staged and ready to apply.
  staged,

  /// Apply has been initiated; the host process is about to restart.
  installing,

  /// Last operation failed; check [UpdateControllerStatus.lastError].
  failed,
}

/// Wire-friendly name for [UpdateLifecycleState], used by both the JSON
/// response builder and the event payload.
extension UpdateLifecycleStateX on UpdateLifecycleState {
  String get wireName => name;
}

/// Snapshot exposed via `GET /api/system/update/status`. Immutable — the
/// controller rebuilds this on every state transition.
class UpdateControllerStatus {
  final UpdateLifecycleState state;
  final String? stagedVersion;
  final DateTime? stagedAt;
  final double? progressPct;
  final String? message;
  final String? lastError;

  const UpdateControllerStatus({
    required this.state,
    this.stagedVersion,
    this.stagedAt,
    this.progressPct,
    this.message,
    this.lastError,
  });

  Map<String, Object?> toJson() => {
        'state': state.wireName,
        if (stagedVersion != null) 'stagedVersion': stagedVersion,
        if (stagedAt != null) 'stagedAt': stagedAt!.toUtc().toIso8601String(),
        if (progressPct != null) 'progressPct': progressPct,
        if (message != null) 'message': message,
        if (lastError != null) 'lastError': lastError,
      };
}

/// Snapshot of a staged but-not-applied update exposed via
/// `GET /api/system/update/staged`. Built from the on-disk `ready.json`
/// marker + the persisted manifest.
class StagedUpdateInfo {
  final String stagedVersion;
  final int stagedBuildNumber;
  final DateTime stagedAt;
  final String? manifestHash;
  final int fileCount;
  final int totalBytes;
  final String? sourceUrl;
  final Map<String, String> expectedHashes;

  const StagedUpdateInfo({
    required this.stagedVersion,
    required this.stagedBuildNumber,
    required this.stagedAt,
    required this.fileCount,
    required this.totalBytes,
    required this.expectedHashes,
    this.manifestHash,
    this.sourceUrl,
  });

  Map<String, Object?> toJson() => {
        'stagedVersion': stagedVersion,
        'stagedBuildNumber': stagedBuildNumber,
        'stagedAt': stagedAt.toUtc().toIso8601String(),
        if (manifestHash != null) 'manifestHash': manifestHash,
        'fileCount': fileCount,
        'totalBytes': totalBytes,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        'expectedHashes': expectedHashes,
      };
}

/// Result of `POST /api/system/update/check`. The check job resolves to
/// this payload when complete.
class UpdateCheckOutcome {
  final bool available;
  final String? latestVersion;
  final int? latestBuildNumber;
  final String? releaseNotes;
  final String? downloadUrl;
  final int? downloadSize;
  final String? signature;
  final bool isPrerelease;
  final bool requiresManualUpgrade;

  const UpdateCheckOutcome({
    required this.available,
    this.latestVersion,
    this.latestBuildNumber,
    this.releaseNotes,
    this.downloadUrl,
    this.downloadSize,
    this.signature,
    this.isPrerelease = false,
    this.requiresManualUpgrade = false,
  });

  Map<String, Object?> toJson() => {
        'available': available,
        if (latestVersion != null) 'latestVersion': latestVersion,
        if (latestBuildNumber != null) 'latestBuildNumber': latestBuildNumber,
        if (releaseNotes != null) 'releaseNotes': releaseNotes,
        if (downloadUrl != null) 'downloadUrl': downloadUrl,
        if (downloadSize != null) 'downloadSize': downloadSize,
        if (signature != null) 'signature': signature,
        'isPrerelease': isPrerelease,
        if (requiresManualUpgrade) 'requiresManualUpgrade': requiresManualUpgrade,
      };
}

/// Typed event broadcast by [UpdateController.events]. The headless API
/// server translates each variant into a `NightshadeEvent` with
/// `category: EventCategory.system`; the eventType is the variant name.
sealed class UpdateEvent {
  const UpdateEvent();

  /// Discriminator used as `NightshadeEvent.eventType`.
  String get type;

  /// Data payload merged into `NightshadeEvent.data`.
  Map<String, Object?> get data;
}

class UpdateAvailableEvent extends UpdateEvent {
  final String currentVersion;
  final String latestVersion;
  final String? downloadUrl;
  final String? releaseNotes;
  final int? downloadSize;

  const UpdateAvailableEvent({
    required this.currentVersion,
    required this.latestVersion,
    this.downloadUrl,
    this.releaseNotes,
    this.downloadSize,
  });

  @override
  String get type => 'UpdateAvailable';

  @override
  Map<String, Object?> get data => {
        'currentVersion': currentVersion,
        'latestVersion': latestVersion,
        if (downloadUrl != null) 'downloadUrl': downloadUrl,
        if (releaseNotes != null) 'releaseNotes': releaseNotes,
        if (downloadSize != null) 'downloadSize': downloadSize,
      };
}

class UpdateDownloadStartedEvent extends UpdateEvent {
  final String jobId;
  final String version;
  final int totalBytes;

  const UpdateDownloadStartedEvent({
    required this.jobId,
    required this.version,
    required this.totalBytes,
  });

  @override
  String get type => 'UpdateDownloadStarted';

  @override
  Map<String, Object?> get data => {
        'jobId': jobId,
        'version': version,
        'totalBytes': totalBytes,
      };
}

class UpdateDownloadProgressEvent extends UpdateEvent {
  final String jobId;
  final int downloadedBytes;
  final int totalBytes;
  final double pct;

  const UpdateDownloadProgressEvent({
    required this.jobId,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.pct,
  });

  @override
  String get type => 'UpdateDownloadProgress';

  @override
  Map<String, Object?> get data => {
        'jobId': jobId,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        'pct': pct,
      };
}

class UpdateDownloadCompleteEvent extends UpdateEvent {
  final String jobId;
  final String stagedPath;
  final String version;

  const UpdateDownloadCompleteEvent({
    required this.jobId,
    required this.stagedPath,
    required this.version,
  });

  @override
  String get type => 'UpdateDownloadComplete';

  @override
  Map<String, Object?> get data => {
        'jobId': jobId,
        'stagedPath': stagedPath,
        'version': version,
      };
}

class UpdateVerificationFailedEvent extends UpdateEvent {
  final String jobId;
  final String reason;
  final String? expectedHash;
  final String? actualHash;

  const UpdateVerificationFailedEvent({
    required this.jobId,
    required this.reason,
    this.expectedHash,
    this.actualHash,
  });

  @override
  String get type => 'UpdateVerificationFailed';

  @override
  Map<String, Object?> get data => {
        'jobId': jobId,
        'reason': reason,
        if (expectedHash != null) 'expectedHash': expectedHash,
        if (actualHash != null) 'actualHash': actualHash,
      };
}

class UpdateApplyStartedEvent extends UpdateEvent {
  final String jobId;
  final String version;

  const UpdateApplyStartedEvent({
    required this.jobId,
    required this.version,
  });

  @override
  String get type => 'UpdateApplyStarted';

  @override
  Map<String, Object?> get data => {
        'jobId': jobId,
        'version': version,
      };
}

class UpdateAppliedEvent extends UpdateEvent {
  final String fromVersion;
  final String toVersion;
  final bool restartRequired;

  const UpdateAppliedEvent({
    required this.fromVersion,
    required this.toVersion,
    this.restartRequired = true,
  });

  @override
  String get type => 'UpdateApplied';

  @override
  Map<String, Object?> get data => {
        'fromVersion': fromVersion,
        'toVersion': toVersion,
        'restartRequired': restartRequired,
      };
}

class UpdateFailedEvent extends UpdateEvent {
  final String? jobId;
  final String phase;
  final String error;

  const UpdateFailedEvent({
    required this.phase,
    required this.error,
    this.jobId,
  });

  @override
  String get type => 'UpdateFailed';

  @override
  Map<String, Object?> get data => {
        if (jobId != null) 'jobId': jobId,
        'phase': phase,
        'error': error,
      };
}

/// Adapter the headless API depends on. Wraps a real [UpdateService] and
/// bridges its state-changing methods onto a broadcast stream of typed
/// [UpdateEvent]s. Tests substitute a fake controller that records calls
/// and drives the [events] stream directly.
///
/// The controller owns the service lifecycle so the bootstrap does not
/// need to track disposal of two objects.
class UpdateController {
  final UpdateService _service;
  final String _currentVersion;
  final int _currentBuildNumber;
  final String _channel;
  final String? _serverUrl;
  final DateTime Function() _now;

  /// Where the controller persists `last_update_check.txt` /
  /// `last_update_applied.txt`. Supplied by the bootstrap (the same
  /// `applicationSupport` directory the service uses for staging).
  final Directory _stateDir;

  final StreamController<UpdateEvent> _eventsController =
      StreamController<UpdateEvent>.broadcast();

  UpdateControllerStatus _status =
      const UpdateControllerStatus(state: UpdateLifecycleState.idle);
  DateTime? _lastUpdateCheck;
  DateTime? _lastUpdateApplied;

  /// Cached manifest from the most recent [checkForUpdates] call.
  /// Reused by [downloadAndStage] so we don't have to re-fetch the
  /// manifest between check and download (and so a manifest signature
  /// is only verified once).
  UpdateManifest? _lastManifest;

  UpdateController({
    required UpdateService service,
    required String currentVersion,
    required int currentBuildNumber,
    required Directory stateDirectory,
    String channel = 'stable',
    String? serverUrl,
    DateTime Function()? now,
  })  : _service = service,
        _currentVersion = currentVersion,
        _currentBuildNumber = currentBuildNumber,
        _channel = channel,
        _serverUrl = serverUrl,
        _stateDir = stateDirectory,
        _now = now ?? DateTime.now;

  /// Hydrate persisted state markers from disk. Must be awaited before
  /// the controller is exposed via the API.
  Future<void> bootstrap() async {
    _lastUpdateCheck = await _readTimestamp('last_update_check.txt');
    _lastUpdateApplied = await _readTimestamp('last_update_applied.txt');

    // Surface any existing staged update so `GET /api/system/update/status`
    // shows `staged` immediately on startup (not just after the first
    // check).
    final staged = await _service.getStagedUpdate();
    if (staged != null) {
      _status = UpdateControllerStatus(
        state: UpdateLifecycleState.staged,
        stagedVersion: staged.version,
        stagedAt: staged.stagedAt,
      );
    }
  }

  /// Lifecycle event stream. Replays nothing on subscribe; clients should
  /// pair this with [status] to discover the current snapshot.
  Stream<UpdateEvent> get events => _eventsController.stream;

  /// Current snapshot. Cheap synchronous read; the controller maintains
  /// this in memory and rebuilds on every state transition.
  UpdateControllerStatus get status => _status;

  /// The running app's version string (e.g. `2.5.0`).
  String get currentVersion => _currentVersion;

  /// The running app's build number.
  int get currentBuildNumber => _currentBuildNumber;

  /// Configured channel (`stable`, `beta`, ...).
  String get channel => _channel;

  /// Configured update-server URL, or null when the server is not set.
  String? get updateServerUrl => _serverUrl;

  /// Persisted moment of the last successful check, or null when no
  /// check has run during this process lifetime.
  DateTime? get lastUpdateCheck => _lastUpdateCheck;

  /// Persisted moment of the last successfully applied update on this
  /// host, or null. Surfaced by `GET /api/system/version`.
  DateTime? get lastUpdateApplied => _lastUpdateApplied;

  /// Check for updates against the configured server. Emits a
  /// `UpdateAvailable` event if a newer version exists. Honours
  /// [channelOverride] for one-off `?channel=` query params.
  Future<UpdateCheckOutcome> checkForUpdates({String? channelOverride}) async {
    if (channelOverride != null && channelOverride.isNotEmpty) {
      _service.configure(
        serverUrl: _serverUrl ?? '',
        channel: channelOverride,
      );
    }
    _updateStatus(_status = UpdateControllerStatus(
      state: UpdateLifecycleState.checking,
      stagedVersion: _status.stagedVersion,
      stagedAt: _status.stagedAt,
    ));

    try {
      final result = await _service.checkForUpdates();
      _lastManifest = result.manifest;
      _lastUpdateCheck = _now();
      await _writeTimestamp('last_update_check.txt', _lastUpdateCheck!);

      if (result.hasUpdate && result.manifest != null) {
        final manifest = result.manifest!;
        _updateStatus(UpdateControllerStatus(
          state: _status.stagedVersion != null
              ? UpdateLifecycleState.staged
              : UpdateLifecycleState.idle,
          stagedVersion: _status.stagedVersion,
          stagedAt: _status.stagedAt,
          message:
              'Update ${manifest.version}+${manifest.buildNumber} available',
        ));
        _eventsController.add(UpdateAvailableEvent(
          currentVersion: _currentVersion,
          latestVersion: manifest.version,
          downloadUrl: manifest.downloadUrl,
          releaseNotes: manifest.releaseNotes,
          downloadSize: manifest.compressedSize,
        ));
        return UpdateCheckOutcome(
          available: true,
          latestVersion: manifest.version,
          latestBuildNumber: manifest.buildNumber,
          releaseNotes: manifest.releaseNotes,
          downloadUrl: manifest.downloadUrl,
          downloadSize: manifest.compressedSize,
          signature: manifest.signature,
          requiresManualUpgrade: result.requiresManualUpgrade,
        );
      }

      // No update — reset to idle (or staged if a previously-staged
      // update still exists).
      _updateStatus(UpdateControllerStatus(
        state: _status.stagedVersion != null
            ? UpdateLifecycleState.staged
            : UpdateLifecycleState.idle,
        stagedVersion: _status.stagedVersion,
        stagedAt: _status.stagedAt,
      ));
      return const UpdateCheckOutcome(available: false);
    } catch (e) {
      _updateStatus(UpdateControllerStatus(
        state: UpdateLifecycleState.failed,
        stagedVersion: _status.stagedVersion,
        stagedAt: _status.stagedAt,
        lastError: e.toString(),
      ));
      _eventsController.add(UpdateFailedEvent(
        phase: 'check',
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Download + stage the most recently checked available update.
  /// [jobId] is the JobManager id so the controller can stamp progress
  /// events with the same handle the client polls.
  Future<void> downloadAndStage({required String jobId}) async {
    final manifest = _lastManifest;
    if (manifest == null) {
      throw StateError(
        'No manifest available; call checkForUpdates first.',
      );
    }

    _eventsController.add(UpdateDownloadStartedEvent(
      jobId: jobId,
      version: manifest.version,
      totalBytes: manifest.compressedSize,
    ));
    _updateStatus(UpdateControllerStatus(
      state: UpdateLifecycleState.downloading,
      progressPct: 0,
      message: 'Downloading ${manifest.version}',
    ));

    try {
      await _service.downloadAndStage(
        manifest,
        onProgress: (downloaded, total, progress) {
          _updateStatus(UpdateControllerStatus(
            state: UpdateLifecycleState.downloading,
            progressPct: progress,
            message:
                'Downloading ${manifest.version} (${(progress * 100).toStringAsFixed(1)}%)',
          ));
          _eventsController.add(UpdateDownloadProgressEvent(
            jobId: jobId,
            downloadedBytes: downloaded,
            totalBytes: total == 0 ? manifest.compressedSize : total,
            pct: progress,
          ));
        },
      );

      // §7A.9: by the time downloadAndStage returns, the staged tree has
      // a `staged_verified.marker`. We can confidently move to staged.
      final staged = await _service.getStagedUpdate();
      if (staged == null) {
        // Defensive: downloadAndStage succeeded but the marker isn't on
        // disk. Surface loudly rather than silently flipping back to
        // idle.
        throw StateError(
          'Download completed but no staged marker was written. The '
          'staging directory may have been wiped concurrently.',
        );
      }

      _updateStatus(UpdateControllerStatus(
        state: UpdateLifecycleState.staged,
        stagedVersion: staged.version,
        stagedAt: staged.stagedAt,
        progressPct: 1.0,
      ));
      _eventsController.add(UpdateDownloadCompleteEvent(
        jobId: jobId,
        stagedPath: staged.extractPath,
        version: staged.version,
      ));
    } catch (e) {
      _updateStatus(UpdateControllerStatus(
        state: UpdateLifecycleState.failed,
        lastError: e.toString(),
      ));
      // Verification failures surface as `UpdateVerificationFailed` so
      // the client can distinguish "the bytes were bad" from "the network
      // dropped".
      if (e is UpdateException && e.message.toLowerCase().contains('verif')) {
        _eventsController.add(UpdateVerificationFailedEvent(
          jobId: jobId,
          reason: e.message,
        ));
      } else {
        _eventsController.add(UpdateFailedEvent(
          jobId: jobId,
          phase: 'download',
          error: e.toString(),
        ));
      }
      rethrow;
    }
  }

  /// Apply the staged update. On success the host process restarts (the
  /// returned future MAY never complete because `exit(0)` is called
  /// before the future resolves). Always emits `UpdateApplyStarted`
  /// before invoking the underlying applier.
  Future<void> applyStagedUpdate({required String jobId}) async {
    final staged = await _service.getStagedUpdate();
    if (staged == null) {
      throw StateError('No staged update available to apply');
    }

    _eventsController.add(UpdateApplyStartedEvent(
      jobId: jobId,
      version: staged.version,
    ));
    _updateStatus(UpdateControllerStatus(
      state: UpdateLifecycleState.installing,
      stagedVersion: staged.version,
      stagedAt: staged.stagedAt,
      message: 'Applying ${staged.version}',
    ));

    try {
      // applyUpdate may exit(0) before this returns. We still emit the
      // applied-event optimistically here so phones receive the alert
      // before the WebSocket teardown. On real failure (Process.start
      // throws) we transition back to staged so the client can retry.
      _eventsController.add(UpdateAppliedEvent(
        fromVersion: _currentVersion,
        toVersion: staged.version,
        restartRequired: true,
      ));
      _lastUpdateApplied = _now();
      await _writeTimestamp(
          'last_update_applied.txt', _lastUpdateApplied!);
      await _service.applyUpdate();
    } catch (e) {
      _updateStatus(UpdateControllerStatus(
        state: UpdateLifecycleState.failed,
        stagedVersion: staged.version,
        stagedAt: staged.stagedAt,
        lastError: e.toString(),
      ));
      _eventsController.add(UpdateFailedEvent(
        jobId: jobId,
        phase: 'apply',
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Abort an in-flight check / download. Throws [StateError] when there
  /// is nothing to abort.
  void abortInFlight() {
    final inFlight = _status.state == UpdateLifecycleState.checking ||
        _status.state == UpdateLifecycleState.downloading;
    if (!inFlight) {
      throw StateError(
        'No update operation is currently in flight '
        '(state=${_status.state.wireName}).',
      );
    }
    _service.cancelDownload();
    _updateStatus(UpdateControllerStatus(
      state: _status.stagedVersion != null
          ? UpdateLifecycleState.staged
          : UpdateLifecycleState.idle,
      stagedVersion: _status.stagedVersion,
      stagedAt: _status.stagedAt,
      message: 'Aborted by operator',
    ));
  }

  /// Return the current staged update, or null when no staged update is
  /// present (or the marker was corrupted and discarded).
  Future<StagedUpdateInfo?> stagedUpdate() async {
    final staged = await _service.getStagedUpdate();
    if (staged == null) return null;

    // Try to read the persisted manifest so we can include accurate file
    // counts + expected hashes. The marker file alone doesn't carry
    // that detail, but the manifest does (it's persisted next to
    // ready.json by [persistStagedManifest]).
    final stagingRoot = Directory(p.dirname(staged.extractPath));
    final manifestFile =
        File(p.join(stagingRoot.path, 'manifest.json'));
    Map<String, String> expectedHashes = {};
    int totalBytes = 0;
    int fileCount = 0;
    String? manifestHash;
    String? sourceUrl;
    if (await manifestFile.exists()) {
      try {
        final raw = await manifestFile.readAsString();
        if (raw.isNotEmpty) {
          final manifestJson = jsonDecode(raw);
          if (manifestJson is Map) {
            final manifest = UpdateManifest.fromJson(
              manifestJson.cast<String, dynamic>(),
            );
            manifest.files.forEach((path, info) {
              expectedHashes[path.replaceAll('\\', '/')] = info.sha256;
              totalBytes += info.size;
            });
            fileCount = manifest.files.length;
            manifestHash = computeStagedManifestHash(manifest);
            sourceUrl = manifest.downloadUrl;
          }
        }
      } catch (_) {
        // Defensive: corrupted manifest. Leave hashes empty — the caller
        // still learns about the staged version + time from the marker
        // fields populated below.
      }
    }

    return StagedUpdateInfo(
      stagedVersion: staged.version,
      stagedBuildNumber: staged.buildNumber,
      stagedAt: staged.stagedAt,
      fileCount: fileCount,
      totalBytes: totalBytes,
      expectedHashes: expectedHashes,
      manifestHash: manifestHash,
      sourceUrl: sourceUrl,
    );
  }

  /// Discard any staged update on disk. No-op when nothing is staged.
  Future<void> discardStaged() async {
    await _service.clearStagedUpdate();
    _updateStatus(const UpdateControllerStatus(
      state: UpdateLifecycleState.idle,
      message: 'Staged update discarded',
    ));
  }

  /// Whether a manual rollback is currently possible. True only while a
  /// retained restore point exists on disk — i.e. an update was applied on
  /// this host and the next launch has not yet confirmed it healthy (the
  /// boot verifier reclaims the backup once it does). When false, the
  /// handler returns 501. Async because it probes the filesystem; the
  /// previous implementation hard-coded `false` because `UpdateService`
  /// exposed no rollback path.
  Future<bool> rollbackSupported() => _service.hasRestorePoint();

  /// Roll back the last applied update by relaunching the external updater
  /// in `--rollback` mode (the same binary + backup machinery the
  /// auto-rollback path uses on failure). On success the host process
  /// restarts, so the returned future MAY never complete. Emits
  /// `UpdateApplyStarted` before and `UpdateApplied` optimistically so
  /// paired phones learn the host is about to restart; on a real spawn
  /// failure it transitions to `failed` and rethrows.
  Future<void> rollback({required String jobId}) async {
    if (!await _service.hasRestorePoint()) {
      throw UnsupportedError(
        'No restore point is available to roll back to. A rollback is only '
        'possible after an update is applied and before the next launch '
        'confirms it healthy.',
      );
    }

    _eventsController.add(UpdateApplyStartedEvent(
      jobId: jobId,
      version: 'rollback',
    ));
    _updateStatus(const UpdateControllerStatus(
      state: UpdateLifecycleState.installing,
      message: 'Rolling back to the previous version',
    ));

    try {
      // Optimistic applied-event so phones receive the restart alert before
      // the WebSocket teardown (rollbackToPrevious exits the process on
      // success). On a real failure (spawn throws) we fall through to the
      // catch and re-arm.
      _eventsController.add(UpdateAppliedEvent(
        fromVersion: _currentVersion,
        toVersion: 'previous',
        restartRequired: true,
      ));
      await _service.rollbackToPrevious();
    } catch (e) {
      _updateStatus(UpdateControllerStatus(
        state: UpdateLifecycleState.failed,
        lastError: e.toString(),
      ));
      _eventsController.add(UpdateFailedEvent(
        jobId: jobId,
        phase: 'rollback',
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Release any resources held by the controller (HTTP client, sockets).
  Future<void> dispose() async {
    await _eventsController.close();
    _service.dispose();
  }

  void _updateStatus(UpdateControllerStatus next) {
    _status = next;
  }

  Future<DateTime?> _readTimestamp(String fileName) async {
    final file = File(p.join(_stateDir.path, fileName));
    if (!await file.exists()) return null;
    try {
      final raw = (await file.readAsString()).trim();
      if (raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeTimestamp(String fileName, DateTime ts) async {
    final file = File(p.join(_stateDir.path, fileName));
    await file.parent.create(recursive: true);
    await file.writeAsString(ts.toUtc().toIso8601String());
  }

}
