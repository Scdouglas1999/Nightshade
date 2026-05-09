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
      description: json['description'] as String?,
      cameraId: json['cameraId'] as String?,
      mountId: json['mountId'] as String?,
      focuserId: json['focuserId'] as String?,
      filterWheelId: json['filterWheelId'] as String?,
      guiderId: json['guiderId'] as String?,
      rotatorId: json['rotatorId'] as String?,
      domeId: json['domeId'] as String?,
      weatherId: json['weatherId'] as String?,
      coverCalibratorId: json['coverCalibratorId'] as String?,
      focalLength: (json['focalLength'] as num?)?.toDouble() ?? 0.0,
      aperture: (json['aperture'] as num?)?.toDouble() ?? 0.0,
      focalRatio: (json['focalRatio'] as num?)?.toDouble(),
      defaultGain: (json['defaultGain'] as num?)?.toInt(),
      defaultOffset: (json['defaultOffset'] as num?)?.toInt(),
      defaultBinX: (json['defaultBinX'] as num?)?.toInt() ?? 1,
      defaultBinY: (json['defaultBinY'] as num?)?.toInt() ?? 1,
      defaultCoolingTemp: (json['defaultCoolingTemp'] as num?)?.toDouble(),
      coolOnConnect: json['coolOnConnect'] as bool? ?? false,
      defaultCenteringExposure:
          (json['defaultCenteringExposure'] as num?)?.toDouble(),
      filterNames: json['filterNames'] as String?,
      filterFocusOffsets: json['filterFocusOffsets'] as String?,
      meridianFlipOverrides: json['meridianFlipOverrides'] as String?,
      cameraName: json['cameraName'] as String?,
      mountName: json['mountName'] as String?,
      focuserName: json['focuserName'] as String?,
      filterWheelName: json['filterWheelName'] as String?,
      guiderName: json['guiderName'] as String?,
      rotatorName: json['rotatorName'] as String?,
      telescopeName: json['telescopeName'] as String?,
      telescopeFocalLength:
          (json['telescopeFocalLength'] as num?)?.toDouble() ?? 0.0,
      telescopeAperture: (json['telescopeAperture'] as num?)?.toDouble() ?? 0.0,
      profileIcon: json['profileIcon'] as String?,
      profileColor: (json['profileColor'] as num?)?.toInt(),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      isDefault: json['isDefault'] as bool? ?? false,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      isActive: json['isActive'] as bool? ?? false,
      pixelSize: (json['pixelSize'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$$EquipmentProfileImplToJson(
        _$EquipmentProfileImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'cameraId': instance.cameraId,
      'mountId': instance.mountId,
      'focuserId': instance.focuserId,
      'filterWheelId': instance.filterWheelId,
      'guiderId': instance.guiderId,
      'rotatorId': instance.rotatorId,
      'domeId': instance.domeId,
      'weatherId': instance.weatherId,
      'coverCalibratorId': instance.coverCalibratorId,
      'focalLength': instance.focalLength,
      'aperture': instance.aperture,
      'focalRatio': instance.focalRatio,
      'defaultGain': instance.defaultGain,
      'defaultOffset': instance.defaultOffset,
      'defaultBinX': instance.defaultBinX,
      'defaultBinY': instance.defaultBinY,
      'defaultCoolingTemp': instance.defaultCoolingTemp,
      'coolOnConnect': instance.coolOnConnect,
      'defaultCenteringExposure': instance.defaultCenteringExposure,
      'filterNames': instance.filterNames,
      'filterFocusOffsets': instance.filterFocusOffsets,
      'meridianFlipOverrides': instance.meridianFlipOverrides,
      'cameraName': instance.cameraName,
      'mountName': instance.mountName,
      'focuserName': instance.focuserName,
      'filterWheelName': instance.filterWheelName,
      'guiderName': instance.guiderName,
      'rotatorName': instance.rotatorName,
      'telescopeName': instance.telescopeName,
      'telescopeFocalLength': instance.telescopeFocalLength,
      'telescopeAperture': instance.telescopeAperture,
      'profileIcon': instance.profileIcon,
      'profileColor': instance.profileColor,
      'sortOrder': instance.sortOrder,
      'isDefault': instance.isDefault,
      'createdAt': instance.createdAt?.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'isActive': instance.isActive,
      'pixelSize': instance.pixelSize,
    };
