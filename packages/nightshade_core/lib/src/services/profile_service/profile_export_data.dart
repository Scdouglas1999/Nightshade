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
  final String? cameraName;
  final String? mountName;
  final String? focuserName;
  final String? filterWheelName;
  final String? guiderName;
  final String? rotatorName;
  final String? safetyMonitorName;
  final String? switchName;
  final String? telescopeName;
  final double? telescopeFocalLength;
  final double? telescopeAperture;
  final double focalLength;
  final double aperture;
  final double? focalRatio;
  final int? defaultGain;
  final int? defaultOffset;
  final int defaultBinX;
  final int defaultBinY;
  final double? defaultCoolingTemp;
  final bool coolOnConnect;
  final double? defaultCenteringExposure;
  final List<String>? filterNames;
  final Map<String, int>? filterFocusOffsets;
  final String? meridianFlipOverrides;
  final String? profileIcon;
  final int? profileColor;

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
    this.cameraName,
    this.mountName,
    this.focuserName,
    this.filterWheelName,
    this.guiderName,
    this.rotatorName,
    this.safetyMonitorName,
    this.switchName,
    this.telescopeName,
    this.telescopeFocalLength,
    this.telescopeAperture,
    required this.focalLength,
    required this.aperture,
    this.focalRatio,
    this.defaultGain,
    this.defaultOffset,
    required this.defaultBinX,
    required this.defaultBinY,
    this.defaultCoolingTemp,
    this.coolOnConnect = false,
    this.defaultCenteringExposure,
    this.filterNames,
    this.filterFocusOffsets,
    this.meridianFlipOverrides,
    this.profileIcon,
    this.profileColor,
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
        developer.log(
          'ProfileService: Failed to parse filterNames: $e',
          name: 'ProfileService',
          level: 1000,
          error: e,
        );
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
        developer.log(
          'ProfileService: Failed to parse filterFocusOffsets: $e',
          name: 'ProfileService',
          level: 1000,
          error: e,
        );
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
      cameraName: profile.cameraName,
      mountName: profile.mountName,
      focuserName: profile.focuserName,
      filterWheelName: profile.filterWheelName,
      guiderName: profile.guiderName,
      rotatorName: profile.rotatorName,
      safetyMonitorName: profile.safetyMonitorName,
      switchName: profile.switchName,
      telescopeName: profile.telescopeName,
      telescopeFocalLength: profile.telescopeFocalLength,
      telescopeAperture: profile.telescopeAperture,
      focalLength: profile.focalLength,
      aperture: profile.aperture,
      focalRatio: profile.focalRatio,
      defaultGain: profile.defaultGain,
      defaultOffset: profile.defaultOffset,
      defaultBinX: profile.defaultBinX,
      defaultBinY: profile.defaultBinY,
      defaultCoolingTemp: profile.defaultCoolingTemp,
      coolOnConnect: profile.coolOnConnect,
      defaultCenteringExposure: profile.defaultCenteringExposure,
      filterNames: filterNames,
      filterFocusOffsets: filterOffsets,
      meridianFlipOverrides: profile.meridianFlipOverrides,
      profileIcon: profile.profileIcon,
      profileColor: profile.profileColor,
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
      cameraName: profile.cameraName,
      mountName: profile.mountName,
      focuserName: profile.focuserName,
      filterWheelName: profile.filterWheelName,
      guiderName: profile.guiderName,
      rotatorName: profile.rotatorName,
      safetyMonitorName: profile.safetyMonitorName,
      switchName: profile.switchName,
      telescopeName: profile.telescopeName,
      telescopeFocalLength: profile.telescopeFocalLength,
      telescopeAperture: profile.telescopeAperture,
      focalLength: profile.focalLength,
      aperture: profile.aperture,
      focalRatio: profile.focalRatio,
      defaultGain: profile.defaultGain,
      defaultOffset: profile.defaultOffset,
      defaultBinX: profile.defaultBinX,
      defaultBinY: profile.defaultBinY,
      defaultCoolingTemp: profile.defaultCoolingTemp,
      coolOnConnect: profile.coolOnConnect,
      defaultCenteringExposure: profile.defaultCenteringExposure,
      filterNames: profile.filterNames.isNotEmpty ? profile.filterNames : null,
      filterFocusOffsets: profile.filterFocusOffsets.isNotEmpty
          ? profile.filterFocusOffsets
          : null,
      meridianFlipOverrides: profile.meridianFlipOverrides,
      profileIcon: profile.profileIcon,
      profileColor: profile.profileColor,
    );
  }

  factory ProfileExportData.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Profile name must be a non-empty string');
    }
    final data = ProfileExportData(
      name: name.trim(),
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
      cameraName: json['cameraName'] as String?,
      mountName: json['mountName'] as String?,
      focuserName: json['focuserName'] as String?,
      filterWheelName: json['filterWheelName'] as String?,
      guiderName: json['guiderName'] as String?,
      rotatorName: json['rotatorName'] as String?,
      safetyMonitorName: json['safetyMonitorName'] as String?,
      switchName: json['switchName'] as String?,
      telescopeName: json['telescopeName'] as String?,
      telescopeFocalLength: (json['telescopeFocalLength'] as num?)?.toDouble(),
      telescopeAperture: (json['telescopeAperture'] as num?)?.toDouble(),
      focalLength: (json['focalLength'] as num?)?.toDouble() ?? 0.0,
      aperture: (json['aperture'] as num?)?.toDouble() ?? 0.0,
      focalRatio: (json['focalRatio'] as num?)?.toDouble(),
      defaultGain: (json['defaultGain'] as num?)?.toInt(),
      defaultOffset: (json['defaultOffset'] as num?)?.toInt(),
      defaultBinX: (json['defaultBinX'] as num?)?.toInt() ?? 1,
      defaultBinY: (json['defaultBinY'] as num?)?.toInt() ?? 1,
      defaultCoolingTemp: (json['defaultCoolingTemp'] as num?)?.toDouble(),
      coolOnConnect: json['coolOnConnect'] as bool? ?? false,
      defaultCenteringExposure: (json['defaultCenteringExposure'] as num?)
          ?.toDouble(),
      filterNames: _profileStringList(json['filterNames'], 'filterNames'),
      filterFocusOffsets: _profileIntMap(
        json['filterFocusOffsets'],
        'filterFocusOffsets',
      ),
      meridianFlipOverrides: json['meridianFlipOverrides'] as String?,
      profileIcon: json['profileIcon'] as String?,
      profileColor: (json['profileColor'] as num?)?.toInt(),
    );
    if (!data.focalLength.isFinite || data.focalLength < 0) {
      throw const FormatException('Profile focalLength must be non-negative');
    }
    if (!data.aperture.isFinite || data.aperture < 0) {
      throw const FormatException('Profile aperture must be non-negative');
    }
    // An export file is hand-editable and may have been produced by an older
    // build that had no plausibility bounds, so import is a real entry point
    // for an impossible optical train — not merely a round-trip of our own
    // data. Reject it with the same shared contract the editors and
    // `POST /api/profiles` use rather than letting it reach the FITS
    // `FOCALLEN` card and the plate-solve field-of-view estimate.
    final trainError = ProfileValidator.validateOpticalTrain(
      focalLengthMm: data.focalLength,
      apertureMm: data.aperture,
    );
    if (trainError != null) {
      throw FormatException('Profile optics rejected: $trainError');
    }
    final telescopeTrainError = ProfileValidator.validateOpticalTrain(
      focalLengthMm: data.telescopeFocalLength ?? 0,
      apertureMm: data.telescopeAperture ?? 0,
    );
    if (telescopeTrainError != null) {
      throw FormatException(
        'Profile telescope optics rejected: $telescopeTrainError',
      );
    }
    final importedFocalRatio = data.focalRatio;
    if (importedFocalRatio != null &&
        (!importedFocalRatio.isFinite ||
            importedFocalRatio < OpticalTrainLimits.minFRatio ||
            importedFocalRatio > OpticalTrainLimits.maxFRatio)) {
      throw const FormatException(
        'Profile focalRatio is outside the plausible range',
      );
    }
    if (data.defaultBinX < 1 || data.defaultBinY < 1) {
      throw const FormatException('Profile binning values must be at least 1');
    }
    final centeringExposure = data.defaultCenteringExposure;
    if (centeringExposure != null &&
        (!centeringExposure.isFinite || centeringExposure <= 0)) {
      throw const FormatException(
        'Profile centering exposure must be a positive finite value',
      );
    }
    final coolingTemp = data.defaultCoolingTemp;
    if (coolingTemp != null && !coolingTemp.isFinite) {
      throw const FormatException('Profile cooling temperature must be finite');
    }
    final overrides = data.meridianFlipOverrides;
    if (overrides != null && overrides.trim().isNotEmpty) {
      final decoded = jsonDecode(overrides);
      if (decoded is! Map) {
        throw const FormatException(
          'Profile meridian flip overrides must be a JSON object',
        );
      }
    }
    return data;
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
      'cameraName': cameraName,
      'mountName': mountName,
      'focuserName': focuserName,
      'filterWheelName': filterWheelName,
      'guiderName': guiderName,
      'rotatorName': rotatorName,
      'safetyMonitorName': safetyMonitorName,
      'switchName': switchName,
      'telescopeName': telescopeName,
      'telescopeFocalLength': telescopeFocalLength,
      'telescopeAperture': telescopeAperture,
      'focalLength': focalLength,
      'aperture': aperture,
      'focalRatio': focalRatio,
      'defaultGain': defaultGain,
      'defaultOffset': defaultOffset,
      'defaultBinX': defaultBinX,
      'defaultBinY': defaultBinY,
      'defaultCoolingTemp': defaultCoolingTemp,
      'coolOnConnect': coolOnConnect,
      'defaultCenteringExposure': defaultCenteringExposure,
      'filterNames': filterNames,
      'filterFocusOffsets': filterFocusOffsets,
      'meridianFlipOverrides': meridianFlipOverrides,
      'profileIcon': profileIcon,
      'profileColor': profileColor,
    };
  }
}

List<String>? _profileStringList(Object? raw, String field) {
  if (raw == null) return null;
  if (raw is! List) {
    throw FormatException('Profile $field must be an array');
  }
  final result = <String>[];
  for (var i = 0; i < raw.length; i++) {
    final value = raw[i];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Profile $field[$i] must be a non-empty string');
    }
    result.add(value.trim());
  }
  return result;
}

Map<String, int>? _profileIntMap(Object? raw, String field) {
  if (raw == null) return null;
  if (raw is! Map) {
    throw FormatException('Profile $field must be an object');
  }
  final result = <String, int>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String ||
        key.trim().isEmpty ||
        value is! num ||
        !value.isFinite) {
      throw FormatException(
        'Profile $field entries require non-empty string keys and finite numbers',
      );
    }
    result[key.trim()] = value.toInt();
  }
  return result;
}
