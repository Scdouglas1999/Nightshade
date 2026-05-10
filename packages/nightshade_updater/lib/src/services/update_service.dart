import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/update_manifest.dart';
import 'archive_extraction.dart';
import 'update_downloader.dart';
import 'update_verifier.dart';

/// Filename of the staged manifest persisted alongside `ready.json`.
/// Both staging paths (HTTPS download + LAN push) write this so apply-time
/// can recover the exact verified manifest.
const String _stagedManifestFile = 'manifest.json';

/// Marker proving the staged tree was end-to-end verified (manifest
/// signature + package hash + per-file hashes). Apply-time refuses to
/// touch the install or copy `updater.exe` unless this marker exists
/// and its content matches the staged manifest. (§7A.9)
const String _stagedVerifiedMarker = 'staged_verified.marker';

/// Filename of the per-file expected-hashes JSON consumed by the Rust
/// updater (`--expected-hashes`). Built from the verified manifest at
/// apply-time so the on-disk copy is never read after the manifest has
/// been hash-verified.
const String _expectedHashesFile = 'expected_hashes.json';

/// One-shot UI banner queued after [getStagedUpdate] discards a
/// corrupted marker (§7A.12). The next consumer that reads + clears
/// this gets a single chance to surface the message; the banner is not
/// re-emitted on subsequent reads.
class UpdateNotice {
  final String message;
  final DateTime occurredAt;
  const UpdateNotice(this.message, this.occurredAt);
}

class _NoticeQueue {
  UpdateNotice? _pending;

  void enqueue(String message) {
    _pending = UpdateNotice(message, DateTime.now());
  }

  UpdateNotice? takePending() {
    final notice = _pending;
    _pending = null;
    return notice;
  }
}

/// Main service for managing OTA updates
class UpdateService {
  final String _currentVersion;
  final int _currentBuildNumber;
  final UpdateDownloader _downloader;
  final UpdateVerifier _verifier;
  final http.Client _httpClient;
  final Future<Directory> Function() _applicationSupportDirectoryProvider;
  final _NoticeQueue _noticeQueue = _NoticeQueue();

  String? _updateServerUrl;
  String _channel = 'stable';
  CancelToken? _currentDownloadToken;

  UpdateService({
    required String currentVersion,
    required int currentBuildNumber,
    UpdateDownloader? downloader,
    UpdateVerifier? verifier,
    http.Client? httpClient,
    Future<Directory> Function()? applicationSupportDirectoryProvider,
  })  : _currentVersion = currentVersion,
        _currentBuildNumber = currentBuildNumber,
        _downloader = downloader ?? UpdateDownloader(),
        _verifier = verifier ?? UpdateVerifier(),
        _httpClient = httpClient ?? http.Client(),
        _applicationSupportDirectoryProvider =
            applicationSupportDirectoryProvider ??
                getApplicationSupportDirectory;

  /// Cancel any in-progress download
  void cancelDownload() {
    _currentDownloadToken?.cancel();
    _currentDownloadToken = null;
  }

  /// Configure the update server URL and channel
  void configure({required String serverUrl, String channel = 'stable'}) {
    _updateServerUrl = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    _channel = channel;
  }

  /// Pop the most recent UI banner notice queued by background work, if any.
  /// Returns null if no notice is pending. Subsequent calls return null until
  /// a new notice is queued.
  UpdateNotice? takePendingNotice() => _noticeQueue.takePending();

  /// Verify whether a previously applied update booted successfully.
  Future<PendingInstallStatus> verifyPendingInstall() async {
    final pendingFile = await _getPendingInstallFile();
    if (!await pendingFile.exists()) {
      return const PendingInstallStatus.none();
    }

    try {
      final payload =
          jsonDecode(await pendingFile.readAsString()) as Map<String, dynamic>;
      final targetVersion = payload['targetVersion'] as String?;
      final targetBuild = payload['targetBuildNumber'] as int?;
      final previousVersion = payload['previousVersion'] as String?;
      final previousBuild = payload['previousBuildNumber'] as int?;
      final backupDirPath = payload['backupDir'] as String?;

      if (targetVersion == _currentVersion &&
          targetBuild == _currentBuildNumber) {
        await pendingFile.delete();
        if (backupDirPath != null) {
          final backupDir = Directory(backupDirPath);
          if (await backupDir.exists()) {
            await backupDir.delete(recursive: true);
          }
        }
        return PendingInstallStatus.verified(
          'Verified update $targetVersion+$targetBuild on startup.',
        );
      }

      if (previousVersion == _currentVersion &&
          previousBuild == _currentBuildNumber) {
        await pendingFile.delete();
        return PendingInstallStatus.rolledBack(
          'Rollback restored build $_currentVersion+$_currentBuildNumber '
          'after update to ${targetVersion ?? "unknown"}+${targetBuild ?? 0}.',
        );
      }

      return PendingInstallStatus.requiresAttention(
        'Pending update marker targets ${targetVersion ?? "unknown"}+'
        '${targetBuild ?? 0}, but the running build is '
        '$_currentVersion+$_currentBuildNumber.',
      );
    } catch (e) {
      await pendingFile.delete();
      return PendingInstallStatus.requiresAttention(
        'Discarded unreadable pending update marker: $e',
      );
    }
  }

  /// Check for available updates
  Future<UpdateCheckResult> checkForUpdates() async {
    if (_updateServerUrl == null) {
      throw UpdateException('Update server URL not configured');
    }

    try {
      // Fetch version info from server
      final versionUrl = '$_updateServerUrl/api/version';
      final response = await _httpClient.get(Uri.parse(versionUrl));

      if (response.statusCode != 200) {
        throw UpdateException('Server returned ${response.statusCode}');
      }

      final versionInfo = VersionInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );

      // Get the channel info
      final channelInfo = versionInfo.channels[_channel];
      if (channelInfo == null) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: _currentVersion,
        );
      }

      // Check if newer version available
      final latestVersion = channelInfo.version;
      final manifest = await _fetchManifest(channelInfo.manifestUrl);

      if (manifest.isNewerThan(_currentVersion)) {
        // Check if we can upgrade from current version
        if (!manifest.canUpgradeFrom(_currentVersion)) {
          return UpdateCheckResult(
            hasUpdate: true,
            currentVersion: _currentVersion,
            availableVersion: latestVersion,
            manifest: manifest,
            requiresManualUpgrade: true,
          );
        }

        return UpdateCheckResult(
          hasUpdate: true,
          currentVersion: _currentVersion,
          availableVersion: latestVersion,
          manifest: manifest,
        );
      }

      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: _currentVersion,
      );
    } on SocketException catch (e) {
      throw UpdateException('Network error: ${e.message}');
    } on FormatException catch (e) {
      throw UpdateException('Invalid response format: ${e.message}');
    }
  }

  /// Fetch manifest from URL (relative or absolute)
  Future<UpdateManifest> _fetchManifest(String manifestUrl) async {
    final url = manifestUrl.startsWith('http')
        ? manifestUrl
        : '$_updateServerUrl$manifestUrl';

    final response = await _httpClient.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw UpdateException('Failed to fetch manifest: ${response.statusCode}');
    }

    return UpdateManifest.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Download and stage an update
  Future<void> downloadAndStage(
    UpdateManifest manifest, {
    DownloadProgressCallback? onProgress,
  }) async {
    // Get staging directory
    final stagingDir = await _getStagingDirectory();
    final packagePath = path.join(stagingDir.path, 'update.zip');

    // Create cancel token for this download
    _currentDownloadToken = CancelToken();

    // Download the package
    await _downloader.download(
      manifest.downloadUrl,
      packagePath,
      onProgress: onProgress,
      expectedSize: manifest.compressedSize,
      cancelToken: _currentDownloadToken,
    );

    // Clear cancel token after successful download
    _currentDownloadToken = null;

    // Verify package integrity: size and SHA-256 hash
    final packageFile = File(packagePath);
    final verified = await _verifier.verifyPackage(
      packageFile,
      manifest,
    );
    if (!verified) {
      await packageFile.delete();
      throw UpdateException(
        'Package integrity verification failed: '
        'the package hash or manifest signature did not verify. '
        'The download may be corrupted or tampered with.',
      );
    }

    // Extract the package
    final extractDir = Directory(path.join(stagingDir.path, 'extracted'));
    if (await extractDir.exists()) {
      await extractDir.delete(recursive: true);
    }
    await extractDir.create(recursive: true);

    await extractZipSafely(packageFile, extractDir);

    // Verify extracted files
    final verification = await _verifier.verifyDirectory(extractDir, manifest);
    if (!verification.success) {
      await extractDir.delete(recursive: true);
      throw UpdateException('Verification failed: $verification');
    }

    await persistStagedManifest(stagingDir, manifest);

    // Marker file indicating staging is complete (separate from
    // staged_verified.marker which proves end-to-end verification).
    final markerFile = File(path.join(stagingDir.path, 'ready.json'));
    await markerFile.writeAsString(jsonEncode({
      'version': manifest.version,
      'buildNumber': manifest.buildNumber,
      'stagedAt': DateTime.now().toIso8601String(),
      'extractPath': extractDir.path,
    }));
  }

  /// Get the staging directory for updates
  Future<Directory> _getStagingDirectory() async {
    final updatesRoot = await _getUpdatesRootDirectory();
    final staging = Directory(path.join(updatesRoot.path, 'staging'));
    if (!await staging.exists()) {
      await staging.create(recursive: true);
    }
    return staging;
  }

  /// Check if there's a staged update ready to apply.
  ///
  /// Marker corruption is treated as a destructive event: the staged
  /// directory is wiped (the bytes on disk are not trustworthy because
  /// we have lost their provenance) and a one-shot UI banner is queued
  /// so the user knows their staged update was discarded (§7A.12).
  Future<StagedUpdate?> getStagedUpdate() async {
    final staging = await _getStagingDirectory();
    final markerFile = File(path.join(staging.path, 'ready.json'));

    if (!await markerFile.exists()) {
      return null;
    }

    try {
      final content = await markerFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final version = data['version'];
      final buildNumber = data['buildNumber'];
      final stagedAt = data['stagedAt'];
      final extractPath = data['extractPath'];

      if (version is! String ||
          buildNumber is! int ||
          stagedAt is! String ||
          extractPath is! String) {
        throw const FormatException('marker missing required fields');
      }

      return StagedUpdate(
        version: version,
        buildNumber: buildNumber,
        stagedAt: DateTime.parse(stagedAt),
        extractPath: extractPath,
      );
    } catch (e) {
      developer.log(
        'Discarding corrupted staged-update marker (${markerFile.path}): $e',
        name: 'UpdateService',
        level: 900,
      );
      _noticeQueue.enqueue(
        'A staged update was found in an inconsistent state and was '
        'discarded. Please redownload.',
      );
      await clearStagedUpdate();
      return null;
    }
  }

  /// Clear any staged update
  Future<void> clearStagedUpdate() async {
    final staging = await _getStagingDirectory();
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
  }

  /// Apply staged update by launching the external updater.
  ///
  /// The updater will:
  /// 1. Wait for this process to exit.
  /// 2. Move-then-copy each staged file (rolling back to .bak on failure).
  /// 3. Hash-verify every applied file against `expected_hashes.json`.
  /// 4. Launch the new version (if `--launch-after`).
  ///
  /// We refuse to spawn the updater unless [_stagedVerifiedMarker] is
  /// present and matches the staged manifest hash; otherwise the staging
  /// tree could have been swapped after verification (§7A.9). On
  /// `Process.start` failure we restore the in-memory status to staged
  /// instead of `exit(0)`-ing into a half-broken state (§7A.5).
  Future<void> applyUpdate() async {
    final staged = await getStagedUpdate();
    if (staged == null) {
      throw UpdateException('No staged update available');
    }

    final stagingRoot = await _getStagingDirectory();
    final manifest = await _readStagedManifest(stagingRoot);
    if (manifest == null) {
      throw UpdateException(
        'Staged manifest is missing or unreadable. '
        'The staged update is incomplete and must be rebuilt.',
      );
    }

    // §7A.9: prove the marker matches the staged manifest before we
    // touch any byte of the install. If the marker is missing or stale,
    // the staging tree is not trusted.
    await _assertVerifiedMarkerMatches(stagingRoot, manifest);

    // Build expected_hashes.json (POSIX-relative path -> sha256 hex)
    // straight from the verified manifest. The Rust updater will
    // re-verify this exact data after apply.
    final expectedHashesFile = await _writeExpectedHashes(stagingRoot, manifest);

    final installDir = await _getInstallDirectory();
    final updaterPath = path.join(installDir.path, 'updater.exe');
    final backupDir = await _getBackupDirectory();
    final pendingFile = await _getPendingInstallFile();

    // Bootstrap updater.exe out of the verified staging tree if it is
    // missing from the install dir (e.g. user installed before updater
    // was bundled). We only do this AFTER the verified marker check
    // above so we never copy an updater binary from an untrusted tree.
    if (!await File(updaterPath).exists()) {
      final stagedUpdaterPath = path.join(staged.extractPath, 'updater.exe');
      developer.log(
          'Updater not in install dir, checking staging: $stagedUpdaterPath',
          name: 'UpdateService',
          level: 900);

      if (await File(stagedUpdaterPath).exists()) {
        developer.log('Found updater in staging, copying to install directory',
            name: 'UpdateService', level: 800);
        try {
          await File(stagedUpdaterPath).copy(updaterPath);
          developer.log('Updater bootstrapped successfully',
              name: 'UpdateService', level: 800);
        } catch (e) {
          throw UpdateException(
            'Failed to bootstrap updater from staged update: $e\n'
            'Try running Nightshade as administrator, or install a full release build.',
          );
        }
      } else {
        throw UpdateException(
          'Updater executable not found.\n'
          'Not in install directory: $updaterPath\n'
          'Not in staged update: $stagedUpdaterPath\n\n'
          'Solutions:\n'
          '1. Create a new update package using build_update_package.ps1 (includes updater)\n'
          '2. Or install a full release build with package_windows.ps1',
        );
      }
    }

    await pendingFile.parent.create(recursive: true);
    await pendingFile.writeAsString(jsonEncode({
      'targetVersion': staged.version,
      'targetBuildNumber': staged.buildNumber,
      'previousVersion': _currentVersion,
      'previousBuildNumber': _currentBuildNumber,
      'installDir': installDir.path,
      'backupDir': backupDir.path,
      'stagingDir': staged.extractPath,
      'createdAt': DateTime.now().toIso8601String(),
    }));

    final args = <String>[
      '--parent-pid',
      pid.toString(),
      '--staging-dir',
      staged.extractPath,
      '--install-dir',
      installDir.path,
      '--backup-dir',
      backupDir.path,
      '--pending-file',
      pendingFile.path,
      '--expected-hashes',
      expectedHashesFile.path,
      '--launch-after',
    ];

    developer.log('Launching updater: $updaterPath with args: $args',
        name: 'UpdateService', level: 800);

    final Process updaterProcess;
    try {
      updaterProcess = await Process.start(
        updaterPath,
        args,
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      // §7A.5: spawn failed. Do NOT exit(0) — the user is still here and
      // the staged tree is still valid. Drop the pending marker so a
      // half-finished apply does not confuse next launch, then surface
      // the failure so the UI can re-arm the "Apply" button.
      try {
        if (await pendingFile.exists()) {
          await pendingFile.delete();
        }
      } catch (cleanupError) {
        developer.log(
          'Failed to remove pending marker after spawn failure: $cleanupError',
          name: 'UpdateService',
          level: 1000,
        );
      }
      throw UpdateException(
        'Failed to launch updater process at $updaterPath: $e',
      );
    }

    // §7A.5: a detached process with pid==0 means CreateProcess returned
    // but we have no handle to wait on; treat as failure rather than
    // letting exit(0) destroy the only diagnostic.
    if (updaterProcess.pid == 0) {
      try {
        if (await pendingFile.exists()) {
          await pendingFile.delete();
        }
      } catch (_) {
        // swallow: the more important error is the spawn failure below.
      }
      throw UpdateException(
        'Updater process reported pid=0; spawn was rejected by the OS. '
        'Check antivirus / file lock state on $updaterPath.',
      );
    }

    developer.log(
      'updater launched, pid=${updaterProcess.pid}',
      name: 'UpdateService',
      level: 800,
    );

    // §7A.5: hold the parent open for 500 ms so the OS commits the
    // child process and our log flush actually hits disk before exit(0)
    // tears down stdio. Without this the child can fail-to-start with
    // no trace in the user-visible log.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _flushDeveloperLog();

    exit(0);
  }

  /// Get the installation directory
  Future<Directory> _getInstallDirectory() async {
    // On Windows, this is the directory containing the executable
    final execPath = Platform.resolvedExecutable;
    return Directory(path.dirname(execPath));
  }

  /// Get the backup directory
  Future<Directory> _getBackupDirectory() async {
    final updatesRoot = await _getUpdatesRootDirectory();
    final backup = Directory(path.join(updatesRoot.path, 'backup'));
    if (!await backup.exists()) {
      await backup.create(recursive: true);
    }
    return backup;
  }

  Future<Directory> _getUpdatesRootDirectory() async {
    final appData = await _applicationSupportDirectoryProvider();
    final updatesRoot = Directory(path.join(appData.path, 'updates'));
    if (!await updatesRoot.exists()) {
      await updatesRoot.create(recursive: true);
    }
    return updatesRoot;
  }

  Future<File> _getPendingInstallFile() async {
    final updatesRoot = await _getUpdatesRootDirectory();
    return File(path.join(updatesRoot.path, 'pending_install.json'));
  }

  Future<UpdateManifest?> _readStagedManifest(Directory stagingDir) async {
    final manifestFile = File(path.join(stagingDir.path, _stagedManifestFile));
    if (!await manifestFile.exists()) {
      return null;
    }
    try {
      return UpdateManifest.fromJson(
        jsonDecode(await manifestFile.readAsString())
            as Map<String, dynamic>,
      );
    } on FormatException catch (e) {
      throw UpdateException(
        'Staged manifest at ${manifestFile.path} is malformed: ${e.message}',
      );
    }
  }

  Future<void> _assertVerifiedMarkerMatches(
    Directory stagingDir,
    UpdateManifest manifest,
  ) async {
    final markerFile =
        File(path.join(stagingDir.path, _stagedVerifiedMarker));
    if (!await markerFile.exists()) {
      throw UpdateException(
        'Staged update is missing the verified marker '
        '(${markerFile.path}). Refusing to apply: redownload the update.',
      );
    }

    final expectedHash = computeStagedManifestHash(manifest);
    final markerContent = (await markerFile.readAsString()).trim();
    if (markerContent != expectedHash) {
      throw UpdateException(
        'Verified marker at ${markerFile.path} does not match the staged '
        'manifest hash. Refusing to apply: the staging tree may have '
        'been tampered with after download.',
      );
    }
  }

  Future<File> _writeExpectedHashes(
    Directory stagingDir,
    UpdateManifest manifest,
  ) async {
    final expectedFile =
        File(path.join(stagingDir.path, _expectedHashesFile));
    final files = <String, String>{};
    for (final entry in manifest.files.entries) {
      // Why POSIX: the Rust updater normalises install-relative paths to
      // forward slashes; matching here keeps the hash lookup
      // platform-independent.
      final posixKey = entry.key.replaceAll('\\', '/');
      files[posixKey] = entry.value.sha256;
    }
    await expectedFile.writeAsString(jsonEncode({'files': files}));
    return expectedFile;
  }

  /// Force the developer.log buffer to drain before `exit(0)`. The log
  /// channel is fundamentally async; without an explicit flush the spawn
  /// pid is silently lost on early exit. Best we can do without dart:io
  /// `stdout.flush` because developer.log routes through the Dart VM
  /// service.
  Future<void> _flushDeveloperLog() async {
    try {
      await stdout.flush();
      await stderr.flush();
    } catch (e) {
      // Why: stdio may be detached in headless mode. Surface but do not
      // block exit on a non-essential flush.
      developer.log(
        'stdout/stderr flush failed: $e',
        name: 'UpdateService',
        level: 900,
      );
    }
  }

  /// Dispose resources
  void dispose() {
    _downloader.dispose();
    _httpClient.close();
  }
}

/// Persist the verified manifest plus the staged_verified marker into a
/// staging directory. Both download paths (HTTPS pull + LAN push) call
/// this once verification has succeeded so apply-time has a single
/// trusted handoff (§7A.9). Exposed at the library level so the
/// LAN push receiver can reuse it without duplicating filenames.
Future<void> persistStagedManifest(
  Directory stagingDir,
  UpdateManifest manifest,
) async {
  await stagingDir.create(recursive: true);

  final manifestJson = jsonEncode(manifest.toJson());
  final manifestFile = File(path.join(stagingDir.path, _stagedManifestFile));
  await manifestFile.writeAsString(manifestJson);

  final markerFile =
      File(path.join(stagingDir.path, _stagedVerifiedMarker));
  await markerFile.writeAsString(computeStagedManifestHash(manifest));
}

/// Hash of the canonical manifest JSON. Stable across runs because
/// `manifest.toJson` round-trips through freezed-generated keys in
/// declaration order.
String computeStagedManifestHash(UpdateManifest manifest) {
  return sha256.convert(utf8.encode(jsonEncode(manifest.toJson()))).toString();
}

/// Result of checking for updates
class UpdateCheckResult {
  final bool hasUpdate;
  final String currentVersion;
  final String? availableVersion;
  final UpdateManifest? manifest;
  final bool requiresManualUpgrade;

  UpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersion,
    this.availableVersion,
    this.manifest,
    this.requiresManualUpgrade = false,
  });
}

/// Information about a staged update
class StagedUpdate {
  final String version;
  final int buildNumber;
  final DateTime stagedAt;
  final String extractPath;

  StagedUpdate({
    required this.version,
    required this.buildNumber,
    required this.stagedAt,
    required this.extractPath,
  });
}

enum PendingInstallState {
  none,
  verified,
  rolledBack,
  requiresAttention,
}

class PendingInstallStatus {
  final PendingInstallState state;
  final String? message;

  const PendingInstallStatus._(this.state, this.message);

  const PendingInstallStatus.none() : this._(PendingInstallState.none, null);

  const PendingInstallStatus.verified(String message)
      : this._(PendingInstallState.verified, message);

  const PendingInstallStatus.rolledBack(String message)
      : this._(PendingInstallState.rolledBack, message);

  const PendingInstallStatus.requiresAttention(String message)
      : this._(PendingInstallState.requiresAttention, message);
}

/// Exception thrown by update operations
class UpdateException implements Exception {
  final String message;

  UpdateException(this.message);

  @override
  String toString() => 'UpdateException: $message';
}
