// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'optical_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OpticalConfigImpl _$$OpticalConfigImplFromJson(Map<String, dynamic> json) =>
    _$OpticalConfigImpl(
      telescopeName: json['telescopeName'] as String?,
      focalLength: (json['focalLength'] as num?)?.toDouble(),
      aperture: (json['aperture'] as num?)?.toDouble(),
      focalRatio: (json['focalRatio'] as num?)?.toDouble(),
      cameraName: json['cameraName'] as String?,
      sensorWidth: (json['sensorWidth'] as num?)?.toInt(),
      sensorHeight: (json['sensorHeight'] as num?)?.toInt(),
      pixelSize: (json['pixelSize'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$$OpticalConfigImplToJson(_$OpticalConfigImpl instance) =>
    <String, dynamic>{
      'telescopeName': instance.telescopeName,
      'focalLength': instance.focalLength,
      'aperture': instance.aperture,
      'focalRatio': instance.focalRatio,
      'cameraName': instance.cameraName,
      'sensorWidth': instance.sensorWidth,
      'sensorHeight': instance.sensorHeight,
      'pixelSize': instance.pixelSize,
    };
