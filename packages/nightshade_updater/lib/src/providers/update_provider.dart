import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show
        DeviceConnectionState,
        SequenceExecutionState,
        appVersionProvider,
        sequencerBackendProvider,
        cameraStateProvider,
        mountStateProvider,
        sequenceExecutionStateProvider;

import '../models/update_manifest.dart';
import '../models/update_state.dart';
import '../services/update_downloader.dart';
import '../services/update_service.dart';
import '../services/lan_push_receiver.dart';

typedef UpdateApplySafetyCheck = Future<void> Function();
typedef UpdateApplySafetyReader = T Function<T>(ProviderListenable<T> provider);

/// Provider for the update state.
///
/// Reads the running app's version from `nightshade_core`'s
/// [appVersionProvider], and lets that provider's error bubble when it has not
/// been overridden at startup: the update server decides whether to advertise a
/// newer build from this string, so a substituted default breaks update polling
/// with nothing on screen to say so.
final updateProvider = StateNotifierProvider<UpdateNotifier, UpdateState>((
  ref,
) {
  final versionInfo = ref.watch(appVersionProvider);
  return UpdateNotifier(
    currentVersion: versionInfo.version,
    currentBuildNumber: versionInfo.buildNumber,
    applySafetyCheck: () => defaultUpdateApplySafetyCheck(ref),
  );
});

bool _isActiveSequenceState(SequenceExecutionState state) {
  return state == SequenceExecutionState.running ||
      state == SequenceExecutionState.paused ||
      state == SequenceExecutionState.stopping ||
      state == SequenceExecutionState.recovering;
}

Future<void> _checkpointIfSessionLoaded(UpdateApplySafetyReader read) async {
  final sequenceState = read(sequenceExecutionStateProvider);
  if (sequenceState == SequenceExecutionState.idle) {
    return;
  }

  await read(sequencerBackendProvider).saveCheckpoint();
}

/// Run the update-apply safety gate against any Riverpod reader.
///
/// Accepting the reader rather than only a widget/provider [Ref] lets the
/// headless OTA controller use the exact same checks through its root
/// [ProviderContainer]. This keeps GUI and remotely-triggered updates from
/// drifting into different hardware-safety behavior.
Future<void> defaultUpdateApplySafetyCheckWithReader(
  UpdateApplySafetyReader read,
) async {
  final sequenceState = read(sequenceExecutionStateProvider);
  if (_isActiveSequenceState(sequenceState)) {
    try {
      await read(sequencerBackendProvider).saveCheckpoint();
    } catch (e, stackTrace) {
      developer.log(
        'Failed to save checkpoint before refusing update apply: $e',
        name: 'UpdateNotifier',
        level: 1000,
        error: e,
        stackTrace: stackTrace,
      );
    }
    throw UpdateException(
      'Cannot apply an update while a sequence is ${sequenceState.name}. '
      'Stop the sequence before applying the update.',
    );
  }

  final cameraState = read(cameraStateProvider);
  if (cameraState.connectionState == DeviceConnectionState.connected) {
    if (cameraState.isExposing) {
      throw UpdateException(
        'Cannot apply an update while the camera is exposing.',
      );
    }
    final coolerPower = cameraState.coolerPower ?? 0;
    if (cameraState.isCooling || cameraState.isWarming || coolerPower > 2) {
      throw UpdateException(
        'Cannot apply an update while the camera cooler is active. '
        'Warm the camera and wait for cooler power to reach 0% first.',
      );
    }
  }

  final mountState = read(mountStateProvider);
  if (mountState.connectionState == DeviceConnectionState.connected) {
    if (mountState.isSlewing) {
      throw UpdateException(
        'Cannot apply an update while the mount is slewing.',
      );
    }
    if (!mountState.isParked) {
      throw UpdateException(
        'Cannot apply an update until the mount is parked.',
      );
    }
  }

  try {
    await _checkpointIfSessionLoaded(read);
  } catch (e) {
    throw UpdateException(
      'Cannot apply update because the current session checkpoint '
      'could not be saved: $e',
    );
  }
}

Future<void> defaultUpdateApplySafetyCheck(Ref ref) {
  return defaultUpdateApplySafetyCheckWithReader(ref.read);
}

/// The apply gate used when a notifier is built without one.
///
/// Applying swaps the binary out from under a running session, so a notifier
/// with no gate cannot see the sequencer or camera state it would have to check.
/// It refuses rather than assume the rig is idle.
Future<void> _denyUnwiredUpdateApply() async {
  throw UpdateException(
    'Cannot apply an update: no safety check is wired into this update '
    'notifier, so imaging state cannot be verified.',
  );
}

/// Notifier for managing update state
class UpdateNotifier extends StateNotifier<UpdateState> {
  final UpdateService _updateService;
  final LanPushReceiver _lanPushReceiver;
  final UpdateApplySafetyCheck _applySafetyCheck;

  UpdateNotifier({
    required String currentVersion,
    required int currentBuildNumber,
    UpdateService? updateService,
    LanPushReceiver? lanPushReceiver,
    UpdateApplySafetyCheck? applySafetyCheck,
  }) : _updateService =
           updateService ??
           UpdateService(
             currentVersion: currentVersion,
             currentBuildNumber: currentBuildNumber,
           ),
       _lanPushReceiver =
           lanPushReceiver ??
           LanPushReceiver(
             currentVersion: currentVersion,
             currentBuildNumber: currentBuildNumber,
           ),
       _applySafetyCheck = applySafetyCheck ?? _denyUnwiredUpdateApply,
       super(
         UpdateState(
           currentVersion: currentVersion,
           currentBuildNumber: currentBuildNumber,
         ),
       ) {
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
    final skipped = await _updateService.readSkippedVersion();
    if (skipped != null) {
      state = state.copyWith(skippedVersion: skipped);
    }

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
  void configure({required String serverUrl, String channel = 'stable'}) {
    _updateService.configure(serverUrl: serverUrl, channel: channel);
    state = state.copyWith(updateServerUrl: serverUrl, channel: channel);
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
      developer.log(
        'Update server URL not configured, skipping update check',
        name: 'UpdateNotifier',
      );
      state = state.copyWith(
        status: UpdateStatus.upToDate,
        lastCheckTime: DateTime.now(),
        errorMessage: null,
      );
      return;
    }

    state = state.copyWith(status: UpdateStatus.checking, errorMessage: null);

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

        // A different version is being offered; forget any earlier skip so
        // it does not silently suppress this newer build on the next run.
        if (state.skippedVersion != null) {
          unawaited(_updateService.writeSkippedVersion(null));
        }

        if (result.requiresManualUpgrade) {
          // Build is below minVersion for OTA: surface the update but route
          // the user to a manual reinstall instead of the download/apply path.
          state = state.copyWith(
            status: UpdateStatus.available,
            availableUpdate: result.manifest,
            requiresManualUpgrade: true,
            skippedVersion: null,
            errorMessage:
                'This build is older than the minimum version supported by '
                'automatic updates. Download the latest full release and '
                'reinstall Nightshade manually.',
            lastCheckTime: DateTime.now(),
          );
          return;
        }

        state = state.copyWith(
          status: UpdateStatus.available,
          availableUpdate: result.manifest,
          requiresManualUpgrade: false,
          skippedVersion: null,
          lastCheckTime: DateTime.now(),
        );
      } else {
        state = state.copyWith(
          status: UpdateStatus.upToDate,
          requiresManualUpgrade: false,
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
    // Builds below minVersion for OTA must be reinstalled manually; the
    // download/apply path is intentionally unreachable for them.
    if (state.requiresManualUpgrade) return;
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
    developer.log(
      'applyUpdate() called, status: ${state.status}, staged: ${state.stagingPath}, version: ${state.availableUpdate?.version}',
      name: 'UpdateNotifier',
      level: 800,
    );

    if (state.status != UpdateStatus.staged) {
      developer.log(
        'Status is not staged, returning early',
        name: 'UpdateNotifier',
        level: 900,
      );
      return;
    }

    state = state.copyWith(status: UpdateStatus.applying);
    developer.log(
      'Status set to applying, calling service...',
      name: 'UpdateNotifier',
      level: 800,
    );

    try {
      await _applySafetyCheck();
      await _updateService.applyUpdate();
      // If we get here, something went wrong (we should have exited)
      developer.log(
        'applyUpdate returned without exiting!',
        name: 'UpdateNotifier',
        level: 1000,
      );
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage:
            'Update process did not launch correctly. The app should have restarted.',
      );
    } catch (e, stackTrace) {
      developer.log(
        'Error applying update: $e',
        name: 'UpdateNotifier',
        level: 1000,
        error: e,
        stackTrace: stackTrace,
      );
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Skip the current available update
  void skipUpdate() {
    if (state.availableUpdate == null) return;

    final version = state.availableUpdate!.version;
    state = state.copyWith(
      status: UpdateStatus.upToDate,
      skippedVersion: version,
      availableUpdate: null,
      requiresManualUpgrade: false,
    );
    unawaited(_updateService.writeSkippedVersion(version));
  }

  /// Clear any staged update
  Future<void> clearStagedUpdate() async {
    await _updateService.clearStagedUpdate();
    state = state.copyWith(status: UpdateStatus.upToDate, stagingPath: null);
  }

  /// Pop the most recent one-shot UI banner queued by the underlying
  /// [UpdateService] (e.g. corrupted-marker recovery). Returns
  /// null if no notice is pending. Subsequent calls return null until a
  /// new notice is queued.
  UpdateNotice? takePendingNotice() => _updateService.takePendingNotice();

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
    developer.log(
      'setStagedFromLanPush: ${manifest.version} at $stagingPath',
      name: 'UpdateNotifier',
      level: 800,
    );
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
    state = state.copyWith(status: UpdateStatus.error, errorMessage: error);
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
