// ignore_for_file: unused_field

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/update_manifest.dart';
import 'archive_extraction.dart';
import 'update_downloader.dart';
import 'update_verifier.dart';

/// Main service for managing OTA updates
class UpdateService {
  final String _currentVersion;
  final int _currentBuildNumber;
  final UpdateDownloader _downloader;
  final UpdateVerifier _verifier;
  final http.Client _httpClient;
  final Future<Directory> Function() _applicationSupportDirectoryProvider;

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

    // Write a marker file indicating staging is complete
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

  /// Check if there's a staged update ready to apply
  Future<StagedUpdate?> getStagedUpdate() async {
    final staging = await _getStagingDirectory();
    final markerFile = File(path.join(staging.path, 'ready.json'));

    if (!await markerFile.exists()) {
      return null;
    }

    try {
      final content = await markerFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      return StagedUpdate(
        version: data['version'] as String,
        buildNumber: data['buildNumber'] as int,
        stagedAt: DateTime.parse(data['stagedAt'] as String),
        extractPath: data['extractPath'] as String,
      );
    } catch (e) {
      // Corrupted marker, clean up
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

  /// Apply staged update by launching the external updater
  ///
  /// This will launch the updater executable and exit the current process.
  /// The updater will:
  /// 1. Wait for this process to exit
  /// 2. Backup current installation
  /// 3. Copy staged files to installation directory
  /// 4. Launch the new version
  Future<void> applyUpdate() async {
    final staged = await getStagedUpdate();
    if (staged == null) {
      throw UpdateException('No staged update available');
    }

    // Get paths
    final installDir = await _getInstallDirectory();
    final updaterPath = path.join(installDir.path, 'updater.exe');
    final backupDir = await _getBackupDirectory();
    final pendingFile = await _getPendingInstallFile();

    // Check if updater exists in install directory
    if (!await File(updaterPath).exists()) {
      // Try to bootstrap the updater from the staged update
      // This handles the case where the current install doesn't have updater.exe
      // but the staged update does
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

    // Launch updater with arguments
    final args = [
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
      '--launch-after',
    ];

    developer.log('Launching updater: $updaterPath with args: $args',
        name: 'UpdateService', level: 800);

    await Process.start(updaterPath, args, mode: ProcessStartMode.detached);

    // Exit this process so updater can proceed
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

  /// Dispose resources
  void dispose() {
    _downloader.dispose();
    _httpClient.close();
  }
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
