// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'equipment_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$EquipmentProfileImpl _$$EquipmentProfileImplFromJson(
        Map<String, dynamic> json) =>
    _$EquipmentProfileImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      cameraId: json['cameraId'] as String?,
      mountId: json['mountId'] as String?,
      focuserId: json['focuserId'] as String?,
      filterWheelId: json['filterWheelId'] as String?,
      guiderId: json['guiderId'] as String?,
      rotatorId: json['rotatorId'] as String?,
      domeId: json['domeId'] as String?,
      weatherId: json['weatherId'] as String?,
      coverCalibratorId: json['coverCalibratorId'] as String?,
      telescopeFocalLength:
          (json['telescopeFocalLength'] as num?)?.toDouble() ?? 0.0,
      telescopeAperture: (json['telescopeAperture'] as num?)?.toDouble() ?? 0.0,
      focalLength: (json['focalLength'] as num?)?.toDouble() ?? 0.0,
      aperture: (json['aperture'] as num?)?.toDouble() ?? 0.0,
      focalRatio: (json['focalRatio'] as num?)?.toDouble(),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      isActive: json['isActive'] as bool? ?? false,
      telescopeName: json['telescopeName'] as String?,
      cameraName: json['cameraName'] as String?,
      pixelSize: (json['pixelSize'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$$EquipmentProfileImplToJson(
        _$EquipmentProfileImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'cameraId': instance.cameraId,
      'mountId': instance.mountId,
      'focuserId': instance.focuserId,
      'filterWheelId': instance.filterWheelId,
      'guiderId': instance.guiderId,
      'rotatorId': instance.rotatorId,
      'domeId': instance.domeId,
      'weatherId': instance.weatherId,
      'coverCalibratorId': instance.coverCalibratorId,
      'telescopeFocalLength': instance.telescopeFocalLength,
      'telescopeAperture': instance.telescopeAperture,
      'focalLength': instance.focalLength,
      'aperture': instance.aperture,
      'focalRatio': instance.focalRatio,
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'isActive': instance.isActive,
      'telescopeName': instance.telescopeName,
      'cameraName': instance.cameraName,
      'pixelSize': instance.pixelSize,
    };
