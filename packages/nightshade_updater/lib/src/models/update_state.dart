import 'package:freezed_annotation/freezed_annotation.dart';
import 'update_manifest.dart';

part 'update_state.freezed.dart';

/// Status of the update system
enum UpdateStatus {
  /// Initial state, not checked yet
  idle,

  /// Checking for updates
  checking,

  /// No update available
  upToDate,

  /// Update available, waiting for user action
  available,

  /// Currently downloading update
  downloading,

  /// Download complete, verifying
  verifying,

  /// Ready to install (staged)
  staged,

  /// Applying update (shouldn't see this in UI, app is restarting)
  applying,

  /// Error occurred
  error,
}

/// Current state of the update system
@freezed
class UpdateState with _$UpdateState {
  const UpdateState._();

  const factory UpdateState({
    /// Current status
    @Default(UpdateStatus.idle) UpdateStatus status,

    /// Current app version
    required String currentVersion,

    /// Current build number
    required int currentBuildNumber,

    /// Available update manifest (if any)
    UpdateManifest? availableUpdate,

    /// Download progress (0.0 to 1.0)
    @Default(0.0) double downloadProgress,

    /// Downloaded bytes
    @Default(0) int downloadedBytes,

    /// Total bytes to download
    @Default(0) int totalBytes,

    /// Error message if status is error
    String? errorMessage,

    /// Path to staged update (if staged)
    String? stagingPath,

    /// Last update check time
    DateTime? lastCheckTime,

    /// Version user chose to skip
    String? skippedVersion,

    /// Update server URL
    String? updateServerUrl,

    /// Current update channel
    @Default('stable') String channel,
  }) = _UpdateState;

  /// Whether an update is available and ready to download
  bool get hasUpdate =>
      status == UpdateStatus.available && availableUpdate != null;

  /// Whether an update is ready to apply
  bool get canApply => status == UpdateStatus.staged && stagingPath != null;

  /// Whether currently busy (checking, downloading, etc.)
  bool get isBusy =>
      status == UpdateStatus.checking ||
      status == UpdateStatus.downloading ||
      status == UpdateStatus.verifying ||
      status == UpdateStatus.applying;

  /// Human-readable status message
  String get statusMessage {
    switch (status) {
      case UpdateStatus.idle:
        return 'Ready';
      case UpdateStatus.checking:
        return 'Checking for updates...';
      case UpdateStatus.upToDate:
        return 'Up to date';
      case UpdateStatus.available:
        return 'Update available: ${availableUpdate?.version ?? ""}';
      case UpdateStatus.downloading:
        final percent = (downloadProgress * 100).toStringAsFixed(1);
        return 'Downloading... $percent%';
      case UpdateStatus.verifying:
        return 'Verifying download...';
      case UpdateStatus.staged:
        return 'Ready to install';
      case UpdateStatus.applying:
        return 'Installing update...';
      case UpdateStatus.error:
        return errorMessage ?? 'Unknown error';
    }
  }
}

/// Settings for the update system
@freezed
class UpdateSettings with _$UpdateSettings {
  const factory UpdateSettings({
    /// Whether automatic update checking is enabled
    @Default(true) bool autoCheckEnabled,

    /// Update server URL
    required String serverUrl,

    /// Update channel (stable, beta, alpha)
    @Default('stable') String channel,

    /// Hours between automatic checks
    @Default(24) int checkIntervalHours,

    /// Version user chose to skip (won't prompt for this version)
    String? skippedVersion,
  }) = _UpdateSettings;
}
