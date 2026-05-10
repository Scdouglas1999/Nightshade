import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart' show appVersionProvider;

import '../models/update_manifest.dart';
import '../models/update_state.dart';
import '../services/update_downloader.dart';
import '../services/update_service.dart';
import '../services/lan_push_receiver.dart';

/// Provider for the update state.
///
/// Reads the running app's version from `nightshade_core`'s
/// [appVersionProvider]. That provider throws if it has not been
/// overridden at app startup; we let the error bubble out instead of
/// substituting a hardcoded default. A wrong default here silently
/// breaks update polling (the server uses this string to decide whether
/// to advertise a newer build), so per CLAUDE.md "errors are a feature"
/// we refuse to start rather than ship a 2.0.0 fallback (§7A.10).
final updateProvider =
    StateNotifierProvider<UpdateNotifier, UpdateState>((ref) {
  final versionInfo = ref.watch(appVersionProvider);
  return UpdateNotifier(
    currentVersion: versionInfo.version,
    currentBuildNumber: versionInfo.buildNumber,
  );
});

/// Notifier for managing update state
class UpdateNotifier extends StateNotifier<UpdateState> {
  final UpdateService _updateService;
  final LanPushReceiver _lanPushReceiver;

  UpdateNotifier({
    required String currentVersion,
    required int currentBuildNumber,
    UpdateService? updateService,
    LanPushReceiver? lanPushReceiver,
  })  : _updateService = updateService ??
            UpdateService(
              currentVersion: currentVersion,
              currentBuildNumber: currentBuildNumber,
            ),
        _lanPushReceiver = lanPushReceiver ??
            LanPushReceiver(
              currentVersion: currentVersion,
              currentBuildNumber: currentBuildNumber,
            ),
        super(UpdateState(
          currentVersion: currentVersion,
          currentBuildNumber: currentBuildNumber,
        )) {
    // Set up LAN push callbacks
    _lanPushReceiver.onUpdateReceived = _onLanPushReceived;
    _lanPushReceiver.onProgress = _onLanPushProgress;
    _lanPushReceiver.onError = _onLanPushError;

    final envServerUrl = Platform.environment['NIGHTSHADE_UPDATE_SERVER'];
    if (envServerUrl != null && envServerUrl.trim().isNotEmpty) {
      final envChannel = Platform.environment['NIGHTSHADE_UPDATE_CHANNEL'];
      configure(
        serverUrl: envServerUrl.trim(),
        channel: (envChannel != null && envChannel.trim().isNotEmpty)
            ? envChannel.trim()
            : 'stable',
      );
    }

    unawaited(_initializeStartupState());
  }

  Future<void> _initializeStartupState() async {
    final pendingStatus = await _updateService.verifyPendingInstall();
    if (pendingStatus.message != null) {
      developer.log(
        pendingStatus.message!,
        name: 'UpdateNotifier',
        level: pendingStatus.state == PendingInstallState.requiresAttention
            ? 1000
            : 800,
      );
    }

    if (pendingStatus.state == PendingInstallState.requiresAttention) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: pendingStatus.message,
      );
    }

    await checkStagedUpdate();
  }

  /// Configure the update server
  void configure({
    required String serverUrl,
    String channel = 'stable',
  }) {
    _updateService.configure(serverUrl: serverUrl, channel: channel);
    state = state.copyWith(
      updateServerUrl: serverUrl,
      channel: channel,
    );
  }

  /// Start listening for LAN push updates
  Future<void> startLanPushListener() async {
    await _lanPushReceiver.startServer();
  }

  /// Stop LAN push listener
  Future<void> stopLanPushListener() async {
    await _lanPushReceiver.stopServer();
  }

  /// Check for updates
  Future<void> checkForUpdates() async {
    if (state.isBusy) return;
    if (state.updateServerUrl == null || state.updateServerUrl!.isEmpty) {
      developer.log('Update server URL not configured, skipping update check', name: 'UpdateNotifier');
      state = state.copyWith(
        status: UpdateStatus.upToDate,
        lastCheckTime: DateTime.now(),
        errorMessage: null,
      );
      return;
    }

    state = state.copyWith(
      status: UpdateStatus.checking,
      errorMessage: null,
    );

    try {
      final result = await _updateService.checkForUpdates();

      if (result.hasUpdate && result.manifest != null) {
        // Check if this version was skipped
        if (state.skippedVersion == result.manifest!.version) {
          state = state.copyWith(
            status: UpdateStatus.upToDate,
            lastCheckTime: DateTime.now(),
          );
          return;
        }

        state = state.copyWith(
          status: UpdateStatus.available,
          availableUpdate: result.manifest,
          lastCheckTime: DateTime.now(),
        );
      } else {
        state = state.copyWith(
          status: UpdateStatus.upToDate,
          lastCheckTime: DateTime.now(),
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: e.toString(),
        lastCheckTime: DateTime.now(),
      );
    }
  }

  /// Download and stage the available update
  Future<void> downloadUpdate() async {
    if (state.availableUpdate == null) return;
    if (state.status == UpdateStatus.downloading) return;

    state = state.copyWith(
      status: UpdateStatus.downloading,
      downloadProgress: 0,
      downloadedBytes: 0,
      totalBytes: state.availableUpdate!.compressedSize,
      errorMessage: null,
    );

    try {
      await _updateService.downloadAndStage(
        state.availableUpdate!,
        onProgress: (downloaded, total, progress) {
          state = state.copyWith(
            downloadProgress: progress,
            downloadedBytes: downloaded,
            totalBytes: total,
          );
        },
      );

      state = state.copyWith(
        status: UpdateStatus.staged,
        downloadProgress: 1.0,
      );
    } on DownloadCancelledException {
      // Download was cancelled - reset to available state
      state = state.copyWith(
        status: UpdateStatus.available,
        downloadProgress: 0,
        downloadedBytes: 0,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Cancel an in-progress download
  void cancelDownload() {
    if (state.status != UpdateStatus.downloading) return;

    _updateService.cancelDownload();
    // State will be updated when DownloadCancelledException is caught
  }

  /// Apply the staged update (will restart the app)
  Future<void> applyUpdate() async {
    developer.log('applyUpdate() called, status: ${state.status}, staged: ${state.stagingPath}, version: ${state.availableUpdate?.version}', name: 'UpdateNotifier', level: 800);

    if (state.status != UpdateStatus.staged) {
      developer.log('Status is not staged, returning early', name: 'UpdateNotifier', level: 900);
      return;
    }

    state = state.copyWith(status: UpdateStatus.applying);
    developer.log('Status set to applying, calling service...', name: 'UpdateNotifier', level: 800);

    try {
      await _updateService.applyUpdate();
      // If we get here, something went wrong (we should have exited)
      developer.log('applyUpdate returned without exiting!', name: 'UpdateNotifier', level: 1000);
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Update process did not launch correctly. The app should have restarted.',
      );
    } catch (e, stackTrace) {
      developer.log('Error applying update: $e', name: 'UpdateNotifier', level: 1000, error: e, stackTrace: stackTrace);
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Skip the current available update
  void skipUpdate() {
    if (state.availableUpdate == null) return;

    state = state.copyWith(
      status: UpdateStatus.upToDate,
      skippedVersion: state.availableUpdate!.version,
      availableUpdate: null,
    );
  }

  /// Clear any staged update
  Future<void> clearStagedUpdate() async {
    await _updateService.clearStagedUpdate();
    state = state.copyWith(
      status: UpdateStatus.upToDate,
      stagingPath: null,
    );
  }

  /// Check for staged update on startup
  Future<void> checkStagedUpdate() async {
    final staged = await _updateService.getStagedUpdate();
    if (staged != null) {
      state = state.copyWith(
        status: UpdateStatus.staged,
        stagingPath: staged.extractPath,
        availableUpdate: UpdateManifest(
          version: staged.version,
          buildNumber: staged.buildNumber,
          releaseDate: staged.stagedAt,
          platform: 'windows',
          arch: 'x64',
          files: {},
          totalSize: 0,
          compressedSize: 0,
          downloadUrl: '',
        ),
      );
    }
  }

  // LAN Push callbacks

  void _onLanPushReceived(UpdateManifest manifest, String stagingPath) {
    setStagedFromLanPush(manifest, stagingPath);
  }

  /// Set the state to staged from an external LAN push notification
  /// Called when the LanPushNotifier stream receives an update
  void setStagedFromLanPush(UpdateManifest manifest, String stagingPath) {
    developer.log('setStagedFromLanPush: ${manifest.version} at $stagingPath', name: 'UpdateNotifier', level: 800);
    state = state.copyWith(
      status: UpdateStatus.staged,
      availableUpdate: manifest,
      stagingPath: stagingPath,
      downloadProgress: 1.0,
      errorMessage: null, // Clear any previous error
    );
  }

  void _onLanPushProgress(
    int receivedBytes,
    int totalBytes,
    double progress,
    String message,
  ) {
    state = state.copyWith(
      status: UpdateStatus.downloading,
      downloadedBytes: receivedBytes,
      totalBytes: totalBytes,
      downloadProgress: progress,
    );
  }

  void _onLanPushError(String error) {
    state = state.copyWith(
      status: UpdateStatus.error,
      errorMessage: error,
    );
  }

  /// Get version info for discovery response
  Map<String, dynamic> get versionInfo => _lanPushReceiver.versionInfo;

  @override
  void dispose() {
    _updateService.dispose();
    _lanPushReceiver.dispose();
    super.dispose();
  }
}
