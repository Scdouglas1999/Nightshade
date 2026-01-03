import 'package:freezed_annotation/freezed_annotation.dart';

part 'update_manifest.freezed.dart';
part 'update_manifest.g.dart';

/// Information about a single file in the update package
@freezed
class UpdateFileInfo with _$UpdateFileInfo {
  const factory UpdateFileInfo({
    required String path,
    required int size,
    required String sha256,
  }) = _UpdateFileInfo;

  factory UpdateFileInfo.fromJson(Map<String, dynamic> json) =>
      _$UpdateFileInfoFromJson(json);
}

/// Manifest for an update package
@freezed
class UpdateManifest with _$UpdateManifest {
  const UpdateManifest._();

  const factory UpdateManifest({
    /// Version string (e.g., "2.1.0")
    required String version,

    /// Build number for ordering
    required int buildNumber,

    /// Release date
    required DateTime releaseDate,

    /// Target platform (windows, macos, linux)
    required String platform,

    /// Architecture (x64, arm64)
    required String arch,

    /// Minimum version required to update from
    String? minVersion,

    /// Map of file path to file info
    required Map<String, UpdateFileInfo> files,

    /// Total uncompressed size in bytes
    required int totalSize,

    /// Compressed package size in bytes
    required int compressedSize,

    /// Download URL for the update package
    required String downloadUrl,

    /// Release notes (markdown)
    String? releaseNotes,

    /// Optional signature for verification
    String? signature,
  }) = _UpdateManifest;

  factory UpdateManifest.fromJson(Map<String, dynamic> json) =>
      _$UpdateManifestFromJson(json);

  /// Parse version string to comparable parts
  List<int> get versionParts =>
      version.split('.').map((p) => int.tryParse(p) ?? 0).toList();

  /// Check if this version is newer than another
  bool isNewerThan(String otherVersion) {
    final other =
        otherVersion.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final mine = versionParts;

    for (var i = 0; i < mine.length && i < other.length; i++) {
      if (mine[i] > other[i]) return true;
      if (mine[i] < other[i]) return false;
    }
    return mine.length > other.length;
  }

  /// Check if upgrade from a version is allowed
  bool canUpgradeFrom(String fromVersion) {
    if (minVersion == null) return true;
    final from =
        fromVersion.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final min = minVersion!.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    for (var i = 0; i < from.length && i < min.length; i++) {
      if (from[i] > min[i]) return true;
      if (from[i] < min[i]) return false;
    }
    return true;
  }
}

/// Version info returned from update server
@freezed
class VersionInfo with _$VersionInfo {
  const factory VersionInfo({
    /// Latest stable version
    required String latestVersion,

    /// Latest build number
    required int latestBuildNumber,

    /// Available channels
    required Map<String, ChannelInfo> channels,

    /// Minimum supported version (older versions must update)
    String? minSupportedVersion,

    /// Server version for compatibility checks
    String? serverVersion,
  }) = _VersionInfo;

  factory VersionInfo.fromJson(Map<String, dynamic> json) =>
      _$VersionInfoFromJson(json);
}

/// Channel information (stable, beta, etc.)
@freezed
class ChannelInfo with _$ChannelInfo {
  const factory ChannelInfo({
    required String version,
    required String manifestUrl,
  }) = _ChannelInfo;

  factory ChannelInfo.fromJson(Map<String, dynamic> json) =>
      _$ChannelInfoFromJson(json);
}
