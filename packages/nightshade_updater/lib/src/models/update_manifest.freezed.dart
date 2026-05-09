// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'update_manifest.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

UpdateFileInfo _$UpdateFileInfoFromJson(Map<String, dynamic> json) {
  return _UpdateFileInfo.fromJson(json);
}

/// @nodoc
mixin _$UpdateFileInfo {
  String get path => throw _privateConstructorUsedError;
  int get size => throw _privateConstructorUsedError;
  String get sha256 => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $UpdateFileInfoCopyWith<UpdateFileInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UpdateFileInfoCopyWith<$Res> {
  factory $UpdateFileInfoCopyWith(
          UpdateFileInfo value, $Res Function(UpdateFileInfo) then) =
      _$UpdateFileInfoCopyWithImpl<$Res, UpdateFileInfo>;
  @useResult
  $Res call({String path, int size, String sha256});
}

/// @nodoc
class _$UpdateFileInfoCopyWithImpl<$Res, $Val extends UpdateFileInfo>
    implements $UpdateFileInfoCopyWith<$Res> {
  _$UpdateFileInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? path = null,
    Object? size = null,
    Object? sha256 = null,
  }) {
    return _then(_value.copyWith(
      path: null == path
          ? _value.path
          : path // ignore: cast_nullable_to_non_nullable
              as String,
      size: null == size
          ? _value.size
          : size // ignore: cast_nullable_to_non_nullable
              as int,
      sha256: null == sha256
          ? _value.sha256
          : sha256 // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$UpdateFileInfoImplCopyWith<$Res>
    implements $UpdateFileInfoCopyWith<$Res> {
  factory _$$UpdateFileInfoImplCopyWith(_$UpdateFileInfoImpl value,
          $Res Function(_$UpdateFileInfoImpl) then) =
      __$$UpdateFileInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String path, int size, String sha256});
}

/// @nodoc
class __$$UpdateFileInfoImplCopyWithImpl<$Res>
    extends _$UpdateFileInfoCopyWithImpl<$Res, _$UpdateFileInfoImpl>
    implements _$$UpdateFileInfoImplCopyWith<$Res> {
  __$$UpdateFileInfoImplCopyWithImpl(
      _$UpdateFileInfoImpl _value, $Res Function(_$UpdateFileInfoImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? path = null,
    Object? size = null,
    Object? sha256 = null,
  }) {
    return _then(_$UpdateFileInfoImpl(
      path: null == path
          ? _value.path
          : path // ignore: cast_nullable_to_non_nullable
              as String,
      size: null == size
          ? _value.size
          : size // ignore: cast_nullable_to_non_nullable
              as int,
      sha256: null == sha256
          ? _value.sha256
          : sha256 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$UpdateFileInfoImpl implements _UpdateFileInfo {
  const _$UpdateFileInfoImpl(
      {required this.path, required this.size, required this.sha256});

  factory _$UpdateFileInfoImpl.fromJson(Map<String, dynamic> json) =>
      _$$UpdateFileInfoImplFromJson(json);

  @override
  final String path;
  @override
  final int size;
  @override
  final String sha256;

  @override
  String toString() {
    return 'UpdateFileInfo(path: $path, size: $size, sha256: $sha256)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UpdateFileInfoImpl &&
            (identical(other.path, path) || other.path == path) &&
            (identical(other.size, size) || other.size == size) &&
            (identical(other.sha256, sha256) || other.sha256 == sha256));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, path, size, sha256);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$UpdateFileInfoImplCopyWith<_$UpdateFileInfoImpl> get copyWith =>
      __$$UpdateFileInfoImplCopyWithImpl<_$UpdateFileInfoImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$UpdateFileInfoImplToJson(
      this,
    );
  }
}

abstract class _UpdateFileInfo implements UpdateFileInfo {
  const factory _UpdateFileInfo(
      {required final String path,
      required final int size,
      required final String sha256}) = _$UpdateFileInfoImpl;

  factory _UpdateFileInfo.fromJson(Map<String, dynamic> json) =
      _$UpdateFileInfoImpl.fromJson;

  @override
  String get path;
  @override
  int get size;
  @override
  String get sha256;
  @override
  @JsonKey(ignore: true)
  _$$UpdateFileInfoImplCopyWith<_$UpdateFileInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

UpdateManifest _$UpdateManifestFromJson(Map<String, dynamic> json) {
  return _UpdateManifest.fromJson(json);
}

/// @nodoc
mixin _$UpdateManifest {
  /// Version string (e.g., "2.1.0")
  String get version => throw _privateConstructorUsedError;

  /// Build number for ordering
  int get buildNumber => throw _privateConstructorUsedError;

  /// Release date
  DateTime get releaseDate => throw _privateConstructorUsedError;

  /// Target platform (windows, macos, linux)
  String get platform => throw _privateConstructorUsedError;

  /// Architecture (x64, arm64)
  String get arch => throw _privateConstructorUsedError;

  /// Minimum version required to update from
  String? get minVersion => throw _privateConstructorUsedError;

  /// Map of file path to file info
  Map<String, UpdateFileInfo> get files => throw _privateConstructorUsedError;

  /// Total uncompressed size in bytes
  int get totalSize => throw _privateConstructorUsedError;

  /// Compressed package size in bytes
  int get compressedSize => throw _privateConstructorUsedError;

  /// SHA-256 hash of the downloaded package archive
  String? get packageSha256 => throw _privateConstructorUsedError;

  /// Download URL for the update package
  String get downloadUrl => throw _privateConstructorUsedError;

  /// Release notes (markdown)
  String? get releaseNotes => throw _privateConstructorUsedError;

  /// Ed25519 signature for the canonical manifest payload
  String? get signature => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $UpdateManifestCopyWith<UpdateManifest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UpdateManifestCopyWith<$Res> {
  factory $UpdateManifestCopyWith(
          UpdateManifest value, $Res Function(UpdateManifest) then) =
      _$UpdateManifestCopyWithImpl<$Res, UpdateManifest>;
  @useResult
  $Res call(
      {String version,
      int buildNumber,
      DateTime releaseDate,
      String platform,
      String arch,
      String? minVersion,
      Map<String, UpdateFileInfo> files,
      int totalSize,
      int compressedSize,
      String? packageSha256,
      String downloadUrl,
      String? releaseNotes,
      String? signature});
}

/// @nodoc
class _$UpdateManifestCopyWithImpl<$Res, $Val extends UpdateManifest>
    implements $UpdateManifestCopyWith<$Res> {
  _$UpdateManifestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? version = null,
    Object? buildNumber = null,
    Object? releaseDate = null,
    Object? platform = null,
    Object? arch = null,
    Object? minVersion = freezed,
    Object? files = null,
    Object? totalSize = null,
    Object? compressedSize = null,
    Object? packageSha256 = freezed,
    Object? downloadUrl = null,
    Object? releaseNotes = freezed,
    Object? signature = freezed,
  }) {
    return _then(_value.copyWith(
      version: null == version
          ? _value.version
          : version // ignore: cast_nullable_to_non_nullable
              as String,
      buildNumber: null == buildNumber
          ? _value.buildNumber
          : buildNumber // ignore: cast_nullable_to_non_nullable
              as int,
      releaseDate: null == releaseDate
          ? _value.releaseDate
          : releaseDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      platform: null == platform
          ? _value.platform
          : platform // ignore: cast_nullable_to_non_nullable
              as String,
      arch: null == arch
          ? _value.arch
          : arch // ignore: cast_nullable_to_non_nullable
              as String,
      minVersion: freezed == minVersion
          ? _value.minVersion
          : minVersion // ignore: cast_nullable_to_non_nullable
              as String?,
      files: null == files
          ? _value.files
          : files // ignore: cast_nullable_to_non_nullable
              as Map<String, UpdateFileInfo>,
      totalSize: null == totalSize
          ? _value.totalSize
          : totalSize // ignore: cast_nullable_to_non_nullable
              as int,
      compressedSize: null == compressedSize
          ? _value.compressedSize
          : compressedSize // ignore: cast_nullable_to_non_nullable
              as int,
      packageSha256: freezed == packageSha256
          ? _value.packageSha256
          : packageSha256 // ignore: cast_nullable_to_non_nullable
              as String?,
      downloadUrl: null == downloadUrl
          ? _value.downloadUrl
          : downloadUrl // ignore: cast_nullable_to_non_nullable
              as String,
      releaseNotes: freezed == releaseNotes
          ? _value.releaseNotes
          : releaseNotes // ignore: cast_nullable_to_non_nullable
              as String?,
      signature: freezed == signature
          ? _value.signature
          : signature // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$UpdateManifestImplCopyWith<$Res>
    implements $UpdateManifestCopyWith<$Res> {
  factory _$$UpdateManifestImplCopyWith(_$UpdateManifestImpl value,
          $Res Function(_$UpdateManifestImpl) then) =
      __$$UpdateManifestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String version,
      int buildNumber,
      DateTime releaseDate,
      String platform,
      String arch,
      String? minVersion,
      Map<String, UpdateFileInfo> files,
      int totalSize,
      int compressedSize,
      String? packageSha256,
      String downloadUrl,
      String? releaseNotes,
      String? signature});
}

/// @nodoc
class __$$UpdateManifestImplCopyWithImpl<$Res>
    extends _$UpdateManifestCopyWithImpl<$Res, _$UpdateManifestImpl>
    implements _$$UpdateManifestImplCopyWith<$Res> {
  __$$UpdateManifestImplCopyWithImpl(
      _$UpdateManifestImpl _value, $Res Function(_$UpdateManifestImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? version = null,
    Object? buildNumber = null,
    Object? releaseDate = null,
    Object? platform = null,
    Object? arch = null,
    Object? minVersion = freezed,
    Object? files = null,
    Object? totalSize = null,
    Object? compressedSize = null,
    Object? packageSha256 = freezed,
    Object? downloadUrl = null,
    Object? releaseNotes = freezed,
    Object? signature = freezed,
  }) {
    return _then(_$UpdateManifestImpl(
      version: null == version
          ? _value.version
          : version // ignore: cast_nullable_to_non_nullable
              as String,
      buildNumber: null == buildNumber
          ? _value.buildNumber
          : buildNumber // ignore: cast_nullable_to_non_nullable
              as int,
      releaseDate: null == releaseDate
          ? _value.releaseDate
          : releaseDate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      platform: null == platform
          ? _value.platform
          : platform // ignore: cast_nullable_to_non_nullable
              as String,
      arch: null == arch
          ? _value.arch
          : arch // ignore: cast_nullable_to_non_nullable
              as String,
      minVersion: freezed == minVersion
          ? _value.minVersion
          : minVersion // ignore: cast_nullable_to_non_nullable
              as String?,
      files: null == files
          ? _value._files
          : files // ignore: cast_nullable_to_non_nullable
              as Map<String, UpdateFileInfo>,
      totalSize: null == totalSize
          ? _value.totalSize
          : totalSize // ignore: cast_nullable_to_non_nullable
              as int,
      compressedSize: null == compressedSize
          ? _value.compressedSize
          : compressedSize // ignore: cast_nullable_to_non_nullable
              as int,
      packageSha256: freezed == packageSha256
          ? _value.packageSha256
          : packageSha256 // ignore: cast_nullable_to_non_nullable
              as String?,
      downloadUrl: null == downloadUrl
          ? _value.downloadUrl
          : downloadUrl // ignore: cast_nullable_to_non_nullable
              as String,
      releaseNotes: freezed == releaseNotes
          ? _value.releaseNotes
          : releaseNotes // ignore: cast_nullable_to_non_nullable
              as String?,
      signature: freezed == signature
          ? _value.signature
          : signature // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$UpdateManifestImpl extends _UpdateManifest {
  const _$UpdateManifestImpl(
      {required this.version,
      required this.buildNumber,
      required this.releaseDate,
      required this.platform,
      required this.arch,
      this.minVersion,
      required final Map<String, UpdateFileInfo> files,
      required this.totalSize,
      required this.compressedSize,
      this.packageSha256,
      required this.downloadUrl,
      this.releaseNotes,
      this.signature})
      : _files = files,
        super._();

  factory _$UpdateManifestImpl.fromJson(Map<String, dynamic> json) =>
      _$$UpdateManifestImplFromJson(json);

  /// Version string (e.g., "2.1.0")
  @override
  final String version;

  /// Build number for ordering
  @override
  final int buildNumber;

  /// Release date
  @override
  final DateTime releaseDate;

  /// Target platform (windows, macos, linux)
  @override
  final String platform;

  /// Architecture (x64, arm64)
  @override
  final String arch;

  /// Minimum version required to update from
  @override
  final String? minVersion;

  /// Map of file path to file info
  final Map<String, UpdateFileInfo> _files;

  /// Map of file path to file info
  @override
  Map<String, UpdateFileInfo> get files {
    if (_files is EqualUnmodifiableMapView) return _files;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_files);
  }

  /// Total uncompressed size in bytes
  @override
  final int totalSize;

  /// Compressed package size in bytes
  @override
  final int compressedSize;

  /// SHA-256 hash of the downloaded package archive
  @override
  final String? packageSha256;

  /// Download URL for the update package
  @override
  final String downloadUrl;

  /// Release notes (markdown)
  @override
  final String? releaseNotes;

  /// Ed25519 signature for the canonical manifest payload
  @override
  final String? signature;

  @override
  String toString() {
    return 'UpdateManifest(version: $version, buildNumber: $buildNumber, releaseDate: $releaseDate, platform: $platform, arch: $arch, minVersion: $minVersion, files: $files, totalSize: $totalSize, compressedSize: $compressedSize, packageSha256: $packageSha256, downloadUrl: $downloadUrl, releaseNotes: $releaseNotes, signature: $signature)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UpdateManifestImpl &&
            (identical(other.version, version) || other.version == version) &&
            (identical(other.buildNumber, buildNumber) ||
                other.buildNumber == buildNumber) &&
            (identical(other.releaseDate, releaseDate) ||
                other.releaseDate == releaseDate) &&
            (identical(other.platform, platform) ||
                other.platform == platform) &&
            (identical(other.arch, arch) || other.arch == arch) &&
            (identical(other.minVersion, minVersion) ||
                other.minVersion == minVersion) &&
            const DeepCollectionEquality().equals(other._files, _files) &&
            (identical(other.totalSize, totalSize) ||
                other.totalSize == totalSize) &&
            (identical(other.compressedSize, compressedSize) ||
                other.compressedSize == compressedSize) &&
            (identical(other.packageSha256, packageSha256) ||
                other.packageSha256 == packageSha256) &&
            (identical(other.downloadUrl, downloadUrl) ||
                other.downloadUrl == downloadUrl) &&
            (identical(other.releaseNotes, releaseNotes) ||
                other.releaseNotes == releaseNotes) &&
            (identical(other.signature, signature) ||
                other.signature == signature));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      version,
      buildNumber,
      releaseDate,
      platform,
      arch,
      minVersion,
      const DeepCollectionEquality().hash(_files),
      totalSize,
      compressedSize,
      packageSha256,
      downloadUrl,
      releaseNotes,
      signature);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$UpdateManifestImplCopyWith<_$UpdateManifestImpl> get copyWith =>
      __$$UpdateManifestImplCopyWithImpl<_$UpdateManifestImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$UpdateManifestImplToJson(
      this,
    );
  }
}

abstract class _UpdateManifest extends UpdateManifest {
  const factory _UpdateManifest(
      {required final String version,
      required final int buildNumber,
      required final DateTime releaseDate,
      required final String platform,
      required final String arch,
      final String? minVersion,
      required final Map<String, UpdateFileInfo> files,
      required final int totalSize,
      required final int compressedSize,
      final String? packageSha256,
      required final String downloadUrl,
      final String? releaseNotes,
      final String? signature}) = _$UpdateManifestImpl;
  const _UpdateManifest._() : super._();

  factory _UpdateManifest.fromJson(Map<String, dynamic> json) =
      _$UpdateManifestImpl.fromJson;

  @override

  /// Version string (e.g., "2.1.0")
  String get version;
  @override

  /// Build number for ordering
  int get buildNumber;
  @override

  /// Release date
  DateTime get releaseDate;
  @override

  /// Target platform (windows, macos, linux)
  String get platform;
  @override

  /// Architecture (x64, arm64)
  String get arch;
  @override

  /// Minimum version required to update from
  String? get minVersion;
  @override

  /// Map of file path to file info
  Map<String, UpdateFileInfo> get files;
  @override

  /// Total uncompressed size in bytes
  int get totalSize;
  @override

  /// Compressed package size in bytes
  int get compressedSize;
  @override

  /// SHA-256 hash of the downloaded package archive
  String? get packageSha256;
  @override

  /// Download URL for the update package
  String get downloadUrl;
  @override

  /// Release notes (markdown)
  String? get releaseNotes;
  @override

  /// Ed25519 signature for the canonical manifest payload
  String? get signature;
  @override
  @JsonKey(ignore: true)
  _$$UpdateManifestImplCopyWith<_$UpdateManifestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

VersionInfo _$VersionInfoFromJson(Map<String, dynamic> json) {
  return _VersionInfo.fromJson(json);
}

/// @nodoc
mixin _$VersionInfo {
  /// Latest stable version
  String get latestVersion => throw _privateConstructorUsedError;

  /// Latest build number
  int get latestBuildNumber => throw _privateConstructorUsedError;

  /// Available channels
  Map<String, ChannelInfo> get channels => throw _privateConstructorUsedError;

  /// Minimum supported version (older versions must update)
  String? get minSupportedVersion => throw _privateConstructorUsedError;

  /// Server version for compatibility checks
  String? get serverVersion => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $VersionInfoCopyWith<VersionInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $VersionInfoCopyWith<$Res> {
  factory $VersionInfoCopyWith(
          VersionInfo value, $Res Function(VersionInfo) then) =
      _$VersionInfoCopyWithImpl<$Res, VersionInfo>;
  @useResult
  $Res call(
      {String latestVersion,
      int latestBuildNumber,
      Map<String, ChannelInfo> channels,
      String? minSupportedVersion,
      String? serverVersion});
}

/// @nodoc
class _$VersionInfoCopyWithImpl<$Res, $Val extends VersionInfo>
    implements $VersionInfoCopyWith<$Res> {
  _$VersionInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? latestVersion = null,
    Object? latestBuildNumber = null,
    Object? channels = null,
    Object? minSupportedVersion = freezed,
    Object? serverVersion = freezed,
  }) {
    return _then(_value.copyWith(
      latestVersion: null == latestVersion
          ? _value.latestVersion
          : latestVersion // ignore: cast_nullable_to_non_nullable
              as String,
      latestBuildNumber: null == latestBuildNumber
          ? _value.latestBuildNumber
          : latestBuildNumber // ignore: cast_nullable_to_non_nullable
              as int,
      channels: null == channels
          ? _value.channels
          : channels // ignore: cast_nullable_to_non_nullable
              as Map<String, ChannelInfo>,
      minSupportedVersion: freezed == minSupportedVersion
          ? _value.minSupportedVersion
          : minSupportedVersion // ignore: cast_nullable_to_non_nullable
              as String?,
      serverVersion: freezed == serverVersion
          ? _value.serverVersion
          : serverVersion // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$VersionInfoImplCopyWith<$Res>
    implements $VersionInfoCopyWith<$Res> {
  factory _$$VersionInfoImplCopyWith(
          _$VersionInfoImpl value, $Res Function(_$VersionInfoImpl) then) =
      __$$VersionInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String latestVersion,
      int latestBuildNumber,
      Map<String, ChannelInfo> channels,
      String? minSupportedVersion,
      String? serverVersion});
}

/// @nodoc
class __$$VersionInfoImplCopyWithImpl<$Res>
    extends _$VersionInfoCopyWithImpl<$Res, _$VersionInfoImpl>
    implements _$$VersionInfoImplCopyWith<$Res> {
  __$$VersionInfoImplCopyWithImpl(
      _$VersionInfoImpl _value, $Res Function(_$VersionInfoImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? latestVersion = null,
    Object? latestBuildNumber = null,
    Object? channels = null,
    Object? minSupportedVersion = freezed,
    Object? serverVersion = freezed,
  }) {
    return _then(_$VersionInfoImpl(
      latestVersion: null == latestVersion
          ? _value.latestVersion
          : latestVersion // ignore: cast_nullable_to_non_nullable
              as String,
      latestBuildNumber: null == latestBuildNumber
          ? _value.latestBuildNumber
          : latestBuildNumber // ignore: cast_nullable_to_non_nullable
              as int,
      channels: null == channels
          ? _value._channels
          : channels // ignore: cast_nullable_to_non_nullable
              as Map<String, ChannelInfo>,
      minSupportedVersion: freezed == minSupportedVersion
          ? _value.minSupportedVersion
          : minSupportedVersion // ignore: cast_nullable_to_non_nullable
              as String?,
      serverVersion: freezed == serverVersion
          ? _value.serverVersion
          : serverVersion // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$VersionInfoImpl implements _VersionInfo {
  const _$VersionInfoImpl(
      {required this.latestVersion,
      required this.latestBuildNumber,
      required final Map<String, ChannelInfo> channels,
      this.minSupportedVersion,
      this.serverVersion})
      : _channels = channels;

  factory _$VersionInfoImpl.fromJson(Map<String, dynamic> json) =>
      _$$VersionInfoImplFromJson(json);

  /// Latest stable version
  @override
  final String latestVersion;

  /// Latest build number
  @override
  final int latestBuildNumber;

  /// Available channels
  final Map<String, ChannelInfo> _channels;

  /// Available channels
  @override
  Map<String, ChannelInfo> get channels {
    if (_channels is EqualUnmodifiableMapView) return _channels;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_channels);
  }

  /// Minimum supported version (older versions must update)
  @override
  final String? minSupportedVersion;

  /// Server version for compatibility checks
  @override
  final String? serverVersion;

  @override
  String toString() {
    return 'VersionInfo(latestVersion: $latestVersion, latestBuildNumber: $latestBuildNumber, channels: $channels, minSupportedVersion: $minSupportedVersion, serverVersion: $serverVersion)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VersionInfoImpl &&
            (identical(other.latestVersion, latestVersion) ||
                other.latestVersion == latestVersion) &&
            (identical(other.latestBuildNumber, latestBuildNumber) ||
                other.latestBuildNumber == latestBuildNumber) &&
            const DeepCollectionEquality().equals(other._channels, _channels) &&
            (identical(other.minSupportedVersion, minSupportedVersion) ||
                other.minSupportedVersion == minSupportedVersion) &&
            (identical(other.serverVersion, serverVersion) ||
                other.serverVersion == serverVersion));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      latestVersion,
      latestBuildNumber,
      const DeepCollectionEquality().hash(_channels),
      minSupportedVersion,
      serverVersion);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$VersionInfoImplCopyWith<_$VersionInfoImpl> get copyWith =>
      __$$VersionInfoImplCopyWithImpl<_$VersionInfoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$VersionInfoImplToJson(
      this,
    );
  }
}

abstract class _VersionInfo implements VersionInfo {
  const factory _VersionInfo(
      {required final String latestVersion,
      required final int latestBuildNumber,
      required final Map<String, ChannelInfo> channels,
      final String? minSupportedVersion,
      final String? serverVersion}) = _$VersionInfoImpl;

  factory _VersionInfo.fromJson(Map<String, dynamic> json) =
      _$VersionInfoImpl.fromJson;

  @override

  /// Latest stable version
  String get latestVersion;
  @override

  /// Latest build number
  int get latestBuildNumber;
  @override

  /// Available channels
  Map<String, ChannelInfo> get channels;
  @override

  /// Minimum supported version (older versions must update)
  String? get minSupportedVersion;
  @override

  /// Server version for compatibility checks
  String? get serverVersion;
  @override
  @JsonKey(ignore: true)
  _$$VersionInfoImplCopyWith<_$VersionInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ChannelInfo _$ChannelInfoFromJson(Map<String, dynamic> json) {
  return _ChannelInfo.fromJson(json);
}

/// @nodoc
mixin _$ChannelInfo {
  String get version => throw _privateConstructorUsedError;
  String get manifestUrl => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ChannelInfoCopyWith<ChannelInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ChannelInfoCopyWith<$Res> {
  factory $ChannelInfoCopyWith(
          ChannelInfo value, $Res Function(ChannelInfo) then) =
      _$ChannelInfoCopyWithImpl<$Res, ChannelInfo>;
  @useResult
  $Res call({String version, String manifestUrl});
}

/// @nodoc
class _$ChannelInfoCopyWithImpl<$Res, $Val extends ChannelInfo>
    implements $ChannelInfoCopyWith<$Res> {
  _$ChannelInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? version = null,
    Object? manifestUrl = null,
  }) {
    return _then(_value.copyWith(
      version: null == version
          ? _value.version
          : version // ignore: cast_nullable_to_non_nullable
              as String,
      manifestUrl: null == manifestUrl
          ? _value.manifestUrl
          : manifestUrl // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ChannelInfoImplCopyWith<$Res>
    implements $ChannelInfoCopyWith<$Res> {
  factory _$$ChannelInfoImplCopyWith(
          _$ChannelInfoImpl value, $Res Function(_$ChannelInfoImpl) then) =
      __$$ChannelInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String version, String manifestUrl});
}

/// @nodoc
class __$$ChannelInfoImplCopyWithImpl<$Res>
    extends _$ChannelInfoCopyWithImpl<$Res, _$ChannelInfoImpl>
    implements _$$ChannelInfoImplCopyWith<$Res> {
  __$$ChannelInfoImplCopyWithImpl(
      _$ChannelInfoImpl _value, $Res Function(_$ChannelInfoImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? version = null,
    Object? manifestUrl = null,
  }) {
    return _then(_$ChannelInfoImpl(
      version: null == version
          ? _value.version
          : version // ignore: cast_nullable_to_non_nullable
              as String,
      manifestUrl: null == manifestUrl
          ? _value.manifestUrl
          : manifestUrl // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ChannelInfoImpl implements _ChannelInfo {
  const _$ChannelInfoImpl({required this.version, required this.manifestUrl});

  factory _$ChannelInfoImpl.fromJson(Map<String, dynamic> json) =>
      _$$ChannelInfoImplFromJson(json);

  @override
  final String version;
  @override
  final String manifestUrl;

  @override
  String toString() {
    return 'ChannelInfo(version: $version, manifestUrl: $manifestUrl)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChannelInfoImpl &&
            (identical(other.version, version) || other.version == version) &&
            (identical(other.manifestUrl, manifestUrl) ||
                other.manifestUrl == manifestUrl));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, version, manifestUrl);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ChannelInfoImplCopyWith<_$ChannelInfoImpl> get copyWith =>
      __$$ChannelInfoImplCopyWithImpl<_$ChannelInfoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ChannelInfoImplToJson(
      this,
    );
  }
}

abstract class _ChannelInfo implements ChannelInfo {
  const factory _ChannelInfo(
      {required final String version,
      required final String manifestUrl}) = _$ChannelInfoImpl;

  factory _ChannelInfo.fromJson(Map<String, dynamic> json) =
      _$ChannelInfoImpl.fromJson;

  @override
  String get version;
  @override
  String get manifestUrl;
  @override
  @JsonKey(ignore: true)
  _$$ChannelInfoImplCopyWith<_$ChannelInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
