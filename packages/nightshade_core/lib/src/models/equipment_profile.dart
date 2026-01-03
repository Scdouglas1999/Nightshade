import 'package:freezed_annotation/freezed_annotation.dart';

part 'equipment_profile.freezed.dart';
part 'equipment_profile.g.dart';

@freezed
class EquipmentProfile with _$EquipmentProfile {
  const factory EquipmentProfile({
    required String id,
    required String name,
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterWheelId,
    String? guiderId,
    String? rotatorId,
    String? domeId,
    String? weatherId,
    String? coverCalibratorId,
    @Default(0.0) double telescopeFocalLength,
    @Default(0.0) double telescopeAperture,
    // Additional fields for compatibility with database model
    @Default(0.0) double focalLength,
    @Default(0.0) double aperture,
    double? focalRatio,
    DateTime? updatedAt,
    @Default(false) bool isActive,
    // Equipment names for FITS headers
    String? telescopeName,
    String? cameraName,
    // Camera pixel size in microns
    double? pixelSize,
  }) = _EquipmentProfile;

  factory EquipmentProfile.fromJson(Map<String, dynamic> json) => _$EquipmentProfileFromJson(json);
}

// Extension to provide computed properties and compatibility
extension EquipmentProfileExtension on EquipmentProfile {
  /// Get effective focal length (uses focalLength if set, otherwise telescopeFocalLength)
  double get effectiveFocalLength {
    // Use focalLength field if it's set (> 0), otherwise fall back to telescopeFocalLength
    return this.focalLength > 0 ? this.focalLength : this.telescopeFocalLength;
  }
  
  /// Get effective aperture (uses aperture if set, otherwise telescopeAperture)
  double get effectiveAperture {
    // Use aperture field if it's set (> 0), otherwise fall back to telescopeAperture
    return this.aperture > 0 ? this.aperture : this.telescopeAperture;
  }
  
  /// Get computed focal ratio
  double? get computedFocalRatio {
    if (this.focalRatio != null) return this.focalRatio;
    final ap = effectiveAperture;
    final fl = effectiveFocalLength;
    if (ap > 0 && fl > 0) {
      return fl / ap;
    }
    return null;
  }
}
