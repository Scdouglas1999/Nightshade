part of '../profile_service.dart';

/// Data class for profile import/export
class ProfileExportData {
  final String name;
  final String? description;
  final String? cameraId;
  final String? mountId;
  final String? focuserId;
  final String? filterWheelId;
  final String? guiderId;
  final String? rotatorId;
  final String? domeId;
  final String? weatherId;
  final String? safetyMonitorId;
  final String? switchId;
  final String? coverCalibratorId;
  final double focalLength;
  final double aperture;
  final double? focalRatio;
  final int? defaultGain;
  final int? defaultOffset;
  final int defaultBinX;
  final int defaultBinY;
  final double? defaultCoolingTemp;
  final List<String>? filterNames;
  final Map<String, int>? filterFocusOffsets;

  ProfileExportData({
    required this.name,
    this.description,
    this.cameraId,
    this.mountId,
    this.focuserId,
    this.filterWheelId,
    this.guiderId,
    this.rotatorId,
    this.domeId,
    this.weatherId,
    this.safetyMonitorId,
    this.switchId,
    this.coverCalibratorId,
    required this.focalLength,
    required this.aperture,
    this.focalRatio,
    this.defaultGain,
    this.defaultOffset,
    required this.defaultBinX,
    required this.defaultBinY,
    this.defaultCoolingTemp,
    this.filterNames,
    this.filterFocusOffsets,
  });

  factory ProfileExportData.fromDatabase(EquipmentProfile profile) {
    List<String>? filterNames;
    Map<String, int>? filterOffsets;

    if (profile.filterNames != null) {
      try {
        filterNames = decodeStringListJson(
          profile.filterNames,
          context: 'equipment_profiles.filter_names for "${profile.name}"',
        );
      } catch (e) {
        // Malformed filter names JSON - skip
        developer.log('ProfileService: Failed to parse filterNames: $e',
            name: 'ProfileService', level: 1000, error: e);
      }
    }

    if (profile.filterFocusOffsets != null) {
      try {
        filterOffsets = decodeStringIntMapJson(
          profile.filterFocusOffsets,
          context:
              'equipment_profiles.filter_focus_offsets for "${profile.name}"',
        );
      } catch (e) {
        // Malformed filter offsets JSON - skip
        developer.log('ProfileService: Failed to parse filterFocusOffsets: $e',
            name: 'ProfileService', level: 1000, error: e);
      }
    }

    return ProfileExportData(
      name: profile.name,
      description: profile.description,
      cameraId: profile.cameraId,
      mountId: profile.mountId,
      focuserId: profile.focuserId,
      filterWheelId: profile.filterWheelId,
      guiderId: profile.guiderId,
      rotatorId: profile.rotatorId,
      domeId: profile.domeId,
      weatherId: profile.weatherId,
      safetyMonitorId: profile.safetyMonitorId,
      switchId: profile.switchId,
      coverCalibratorId: profile.coverCalibratorId,
      focalLength: profile.focalLength,
      aperture: profile.aperture,
      focalRatio: profile.focalRatio,
      defaultGain: profile.defaultGain,
      defaultOffset: profile.defaultOffset,
      defaultBinX: profile.defaultBinX,
      defaultBinY: profile.defaultBinY,
      defaultCoolingTemp: profile.defaultCoolingTemp,
      filterNames: filterNames,
      filterFocusOffsets: filterOffsets,
    );
  }

  factory ProfileExportData.fromModel(EquipmentProfileModel profile) {
    return ProfileExportData(
      name: profile.name,
      description: profile.description,
      cameraId: profile.cameraId,
      mountId: profile.mountId,
      focuserId: profile.focuserId,
      filterWheelId: profile.filterWheelId,
      guiderId: profile.guiderId,
      rotatorId: profile.rotatorId,
      domeId: profile.domeId,
      weatherId: profile.weatherId,
      safetyMonitorId: profile.safetyMonitorId,
      switchId: profile.switchId,
      coverCalibratorId: profile.coverCalibratorId,
      focalLength: profile.focalLength,
      aperture: profile.aperture,
      focalRatio: profile.focalRatio,
      defaultGain: profile.defaultGain,
      defaultOffset: profile.defaultOffset,
      defaultBinX: profile.defaultBinX,
      defaultBinY: profile.defaultBinY,
      defaultCoolingTemp: profile.defaultCoolingTemp,
      filterNames: profile.filterNames.isNotEmpty ? profile.filterNames : null,
      filterFocusOffsets: profile.filterFocusOffsets.isNotEmpty
          ? profile.filterFocusOffsets
          : null,
    );
  }

  factory ProfileExportData.fromJson(Map<String, dynamic> json) {
    return ProfileExportData(
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
      safetyMonitorId: json['safetyMonitorId'] as String?,
      switchId: json['switchId'] as String?,
      coverCalibratorId: json['coverCalibratorId'] as String?,
      focalLength: (json['focalLength'] as num?)?.toDouble() ?? 0.0,
      aperture: (json['aperture'] as num?)?.toDouble() ?? 0.0,
      focalRatio: (json['focalRatio'] as num?)?.toDouble(),
      defaultGain: (json['defaultGain'] as num?)?.toInt(),
      defaultOffset: (json['defaultOffset'] as num?)?.toInt(),
      defaultBinX: (json['defaultBinX'] as num?)?.toInt() ?? 1,
      defaultBinY: (json['defaultBinY'] as num?)?.toInt() ?? 1,
      defaultCoolingTemp: (json['defaultCoolingTemp'] as num?)?.toDouble(),
      filterNames: (json['filterNames'] as List?)?.cast<String>(),
      filterFocusOffsets: (json['filterFocusOffsets'] as Map?)?.map(
        (key, value) => MapEntry(
          key.toString(),
          (value as num).toInt(),
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'cameraId': cameraId,
      'mountId': mountId,
      'focuserId': focuserId,
      'filterWheelId': filterWheelId,
      'guiderId': guiderId,
      'rotatorId': rotatorId,
      'domeId': domeId,
      'weatherId': weatherId,
      'safetyMonitorId': safetyMonitorId,
      'switchId': switchId,
      'coverCalibratorId': coverCalibratorId,
      'focalLength': focalLength,
      'aperture': aperture,
      'focalRatio': focalRatio,
      'defaultGain': defaultGain,
      'defaultOffset': defaultOffset,
      'defaultBinX': defaultBinX,
      'defaultBinY': defaultBinY,
      'defaultCoolingTemp': defaultCoolingTemp,
      'filterNames': filterNames,
      'filterFocusOffsets': filterFocusOffsets,
    };
  }
}
