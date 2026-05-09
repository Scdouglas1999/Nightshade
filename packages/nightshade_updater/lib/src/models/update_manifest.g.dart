// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_manifest.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$UpdateFileInfoImpl _$$UpdateFileInfoImplFromJson(Map<String, dynamic> json) =>
    _$UpdateFileInfoImpl(
      path: json['path'] as String,
      size: (json['size'] as num).toInt(),
      sha256: json['sha256'] as String,
    );

Map<String, dynamic> _$$UpdateFileInfoImplToJson(
        _$UpdateFileInfoImpl instance) =>
    <String, dynamic>{
      'path': instance.path,
      'size': instance.size,
      'sha256': instance.sha256,
    };

_$UpdateManifestImpl _$$UpdateManifestImplFromJson(Map<String, dynamic> json) =>
    _$UpdateManifestImpl(
      version: json['version'] as String,
      buildNumber: (json['buildNumber'] as num).toInt(),
      releaseDate: DateTime.parse(json['releaseDate'] as String),
      platform: json['platform'] as String,
      arch: json['arch'] as String,
      minVersion: json['minVersion'] as String?,
      files: (json['files'] as Map<String, dynamic>).map(
        (k, e) =>
            MapEntry(k, UpdateFileInfo.fromJson(e as Map<String, dynamic>)),
      ),
      totalSize: (json['totalSize'] as num).toInt(),
      compressedSize: (json['compressedSize'] as num).toInt(),
      packageSha256: json['packageSha256'] as String?,
      downloadUrl: json['downloadUrl'] as String,
      releaseNotes: json['releaseNotes'] as String?,
      signature: json['signature'] as String?,
    );

Map<String, dynamic> _$$UpdateManifestImplToJson(
        _$UpdateManifestImpl instance) =>
    <String, dynamic>{
      'version': instance.version,
      'buildNumber': instance.buildNumber,
      'releaseDate': instance.releaseDate.toIso8601String(),
      'platform': instance.platform,
      'arch': instance.arch,
      'minVersion': instance.minVersion,
      'files': instance.files,
      'totalSize': instance.totalSize,
      'compressedSize': instance.compressedSize,
      'packageSha256': instance.packageSha256,
      'downloadUrl': instance.downloadUrl,
      'releaseNotes': instance.releaseNotes,
      'signature': instance.signature,
    };

_$VersionInfoImpl _$$VersionInfoImplFromJson(Map<String, dynamic> json) =>
    _$VersionInfoImpl(
      latestVersion: json['latestVersion'] as String,
      latestBuildNumber: (json['latestBuildNumber'] as num).toInt(),
      channels: (json['channels'] as Map<String, dynamic>).map(
        (k, e) => MapEntry(k, ChannelInfo.fromJson(e as Map<String, dynamic>)),
      ),
      minSupportedVersion: json['minSupportedVersion'] as String?,
      serverVersion: json['serverVersion'] as String?,
    );

Map<String, dynamic> _$$VersionInfoImplToJson(_$VersionInfoImpl instance) =>
    <String, dynamic>{
      'latestVersion': instance.latestVersion,
      'latestBuildNumber': instance.latestBuildNumber,
      'channels': instance.channels,
      'minSupportedVersion': instance.minSupportedVersion,
      'serverVersion': instance.serverVersion,
    };

_$ChannelInfoImpl _$$ChannelInfoImplFromJson(Map<String, dynamic> json) =>
    _$ChannelInfoImpl(
      version: json['version'] as String,
      manifestUrl: json['manifestUrl'] as String,
    );

Map<String, dynamic> _$$ChannelInfoImplToJson(_$ChannelInfoImpl instance) =>
    <String, dynamic>{
      'version': instance.version,
      'manifestUrl': instance.manifestUrl,
    };
