import 'package:freezed_annotation/freezed_annotation.dart';

part 'update_manifest.freezed.dart';
part 'update_manifest.g.dart';

/// Information about a single file in the update package
@freezed
abstract class UpdateFileInfo with _$UpdateFileInfo {
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
abstract class UpdateManifest with _$UpdateManifest {
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

    /// SHA-256 hash of the downloaded package archive
    String? packageSha256,

    /// Download URL for the update package
    required String downloadUrl,

    /// Release notes (markdown)
    String? releaseNotes,

    /// Ed25519 signature for the canonical manifest payload
    String? signature,
  }) = _UpdateManifest;

  factory UpdateManifest.fromJson(Map<String, dynamic> json) =>
      _$UpdateManifestFromJson(json);

  /// Parse version string to comparable parts
  List<int> get versionParts =>
      version.split('.').map((p) => int.tryParse(p) ?? 0).toList();

  /// Check if this version is newer than another
  bool isNewerThan(String otherVersion) {
    final other = otherVersion
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final mine = versionParts;

    for (var i = 0; i < mine.length && i < other.length; i++) {
      if (mine[i] > other[i]) return true;
      if (mine[i] < other[i]) return false;
    }
    return mine.length > other.length;
  }

  /// Check if this build supersedes [currentVersion]+[currentBuild].
  ///
  /// Newer when the semver is strictly newer, OR the semver is identical
  /// and this manifest's [buildNumber] is greater. This lets same-semver
  /// hotfix builds be offered while never offering an identical
  /// version+build (which would loop a self-update). [isNewerThan]'s
  /// semver-only contract is intentionally left untouched for callers that
  /// want pure string ordering.
  bool isNewerBuildThan(String currentVersion, int currentBuild) {
    final cmp = _compareVersions(
      versionParts,
      currentVersion.split('.').map((p) => int.tryParse(p) ?? 0).toList(),
    );
    if (cmp != 0) return cmp > 0;
    return buildNumber > currentBuild;
  }

  /// Check if upgrade from a version is allowed
  bool canUpgradeFrom(String fromVersion) {
    if (minVersion == null) return true;
    final from = fromVersion
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final min = minVersion!
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    // At or above minVersion may upgrade; below it is gated out. Equal is
    // allowed (compare == 0). Shorter component lists are zero-padded so
    // '2.0' < '2.0.5'.
    return _compareVersions(from, min) >= 0;
  }

  /// Compare two zero-padded version-component lists. Returns >0 if [a] is
  /// newer, <0 if older, 0 if equal. The shorter list is treated as
  /// trailing zeros so '2.0' compares below '2.0.5'.
  static int _compareVersions(List<int> a, List<int> b) {
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final ai = i < a.length ? a[i] : 0;
      final bi = i < b.length ? b[i] : 0;
      if (ai != bi) return ai > bi ? 1 : -1;
    }
    return 0;
  }
}

/// Version info returned from update server
@freezed
abstract class VersionInfo with _$VersionInfo {
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
abstract class ChannelInfo with _$ChannelInfo {
  const factory ChannelInfo({
    required String version,
    required String manifestUrl,
  }) = _ChannelInfo;

  factory ChannelInfo.fromJson(Map<String, dynamic> json) =>
      _$ChannelInfoFromJson(json);
}
