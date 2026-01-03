import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import 'database_provider.dart';
import '../services/profile_service.dart';

// ============================================================================
// Equipment Profile Model (UI-friendly)
// ============================================================================

/// A fully-typed model representing an equipment profile
class EquipmentProfileModel {
  final int? id;
  final String name;
  final String? description;
  final bool isActive;
  
  // Device identifiers
  final String? cameraId;
  final String? mountId;
  final String? focuserId;
  final String? filterWheelId;
  final String? guiderId;
  final String? rotatorId;
  final String? domeId;
  final String? weatherId;
  final String? coverCalibratorId;
  
  // Optical setup
  final double focalLength;
  final double aperture;
  final double? focalRatio;
  
  // Camera defaults
  final int? defaultGain;
  final int? defaultOffset;
  final int defaultBinX;
  final int defaultBinY;
  final double? defaultCoolingTemp;
  
  // Filter configuration
  final List<String> filterNames;
  final Map<String, int> filterFocusOffsets;
  
  // Timestamps
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const EquipmentProfileModel({
    this.id,
    required this.name,
    this.description,
    this.isActive = false,
    this.cameraId,
    this.mountId,
    this.focuserId,
    this.filterWheelId,
    this.guiderId,
    this.rotatorId,
    this.domeId,
    this.weatherId,
    this.coverCalibratorId,
    this.focalLength = 0.0,
    this.aperture = 0.0,
    this.focalRatio,
    this.defaultGain,
    this.defaultOffset,
    this.defaultBinX = 1,
    this.defaultBinY = 1,
    this.defaultCoolingTemp,
    this.filterNames = const [],
    this.filterFocusOffsets = const {},
    this.createdAt,
    this.updatedAt,
  });

  /// Create from database entity
  factory EquipmentProfileModel.fromDatabase(EquipmentProfile db) {
    List<String> filters = [];
    Map<String, int> offsets = {};
    
    if (db.filterNames != null) {
      try {
        filters = (jsonDecode(db.filterNames!) as List).cast<String>();
      } catch (_) {}
    }
    
    if (db.filterFocusOffsets != null) {
      try {
        final decoded = jsonDecode(db.filterFocusOffsets!) as Map<String, dynamic>;
        offsets = decoded.map((key, value) => MapEntry(key, value as int));
      } catch (_) {}
    }
    
    return EquipmentProfileModel(
      id: db.id,
      name: db.name,
      description: db.description,
      isActive: db.isActive,
      cameraId: db.cameraId,
      mountId: db.mountId,
      focuserId: db.focuserId,
      filterWheelId: db.filterWheelId,
      guiderId: db.guiderId,
      rotatorId: db.rotatorId,
      domeId: db.domeId,
      weatherId: db.weatherId,
      coverCalibratorId: db.coverCalibratorId,
      focalLength: db.focalLength,
      aperture: db.aperture,
      focalRatio: db.focalRatio,
      defaultGain: db.defaultGain,
      defaultOffset: db.defaultOffset,
      defaultBinX: db.defaultBinX,
      defaultBinY: db.defaultBinY,
      defaultCoolingTemp: db.defaultCoolingTemp,
      filterNames: filters,
      filterFocusOffsets: offsets,
      createdAt: db.createdAt,
      updatedAt: db.updatedAt,
    );
  }

  /// Convert to database companion for insert/update
  EquipmentProfilesCompanion toCompanion() {
    return EquipmentProfilesCompanion(
      id: id != null ? Value(id!) : const Value.absent(),
      name: Value(name),
      description: Value(description),
      isActive: Value(isActive),
      cameraId: Value(cameraId),
      mountId: Value(mountId),
      focuserId: Value(focuserId),
      filterWheelId: Value(filterWheelId),
      guiderId: Value(guiderId),
      rotatorId: Value(rotatorId),
      domeId: Value(domeId),
      weatherId: Value(weatherId),
      coverCalibratorId: Value(coverCalibratorId),
      focalLength: Value(focalLength),
      aperture: Value(aperture),
      focalRatio: Value(focalRatio),
      defaultGain: Value(defaultGain),
      defaultOffset: Value(defaultOffset),
      defaultBinX: Value(defaultBinX),
      defaultBinY: Value(defaultBinY),
      defaultCoolingTemp: Value(defaultCoolingTemp),
      filterNames: Value(filterNames.isNotEmpty ? jsonEncode(filterNames) : null),
      filterFocusOffsets: Value(filterFocusOffsets.isNotEmpty ? jsonEncode(filterFocusOffsets) : null),
      updatedAt: Value(DateTime.now()),
    );
  }

  EquipmentProfileModel copyWith({
    int? id,
    String? name,
    String? description,
    bool? isActive,
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterWheelId,
    String? guiderId,
    String? rotatorId,
    String? domeId,
    String? weatherId,
    String? coverCalibratorId,
    double? focalLength,
    double? aperture,
    double? focalRatio,
    int? defaultGain,
    int? defaultOffset,
    int? defaultBinX,
    int? defaultBinY,
    double? defaultCoolingTemp,
    List<String>? filterNames,
    Map<String, int>? filterFocusOffsets,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EquipmentProfileModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      cameraId: cameraId ?? this.cameraId,
      mountId: mountId ?? this.mountId,
      focuserId: focuserId ?? this.focuserId,
      filterWheelId: filterWheelId ?? this.filterWheelId,
      guiderId: guiderId ?? this.guiderId,
      rotatorId: rotatorId ?? this.rotatorId,
      domeId: domeId ?? this.domeId,
      weatherId: weatherId ?? this.weatherId,
      coverCalibratorId: coverCalibratorId ?? this.coverCalibratorId,
      focalLength: focalLength ?? this.focalLength,
      aperture: aperture ?? this.aperture,
      focalRatio: focalRatio ?? this.focalRatio,
      defaultGain: defaultGain ?? this.defaultGain,
      defaultOffset: defaultOffset ?? this.defaultOffset,
      defaultBinX: defaultBinX ?? this.defaultBinX,
      defaultBinY: defaultBinY ?? this.defaultBinY,
      defaultCoolingTemp: defaultCoolingTemp ?? this.defaultCoolingTemp,
      filterNames: filterNames ?? this.filterNames,
      filterFocusOffsets: filterFocusOffsets ?? this.filterFocusOffsets,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Calculate f/ratio from focal length and aperture
  double? get calculatedFocalRatio {
    if (focalRatio != null) return focalRatio;
    if (aperture > 0) return focalLength / aperture;
    return null;
  }

  /// Get image scale in arcsec/pixel for a given pixel size
  double getImageScale(double pixelSizeMicrons) {
    if (focalLength <= 0) return 0;
    return (pixelSizeMicrons / focalLength) * 206.265;
  }

  /// Get field of view for given sensor dimensions
  (double width, double height) getFieldOfView({
    required double sensorWidthMm,
    required double sensorHeightMm,
  }) {
    if (focalLength <= 0) return (0, 0);
    final widthDeg = 2 * (57.3 * (sensorWidthMm / (2 * focalLength)));
    final heightDeg = 2 * (57.3 * (sensorHeightMm / (2 * focalLength)));
    return (widthDeg, heightDeg);
  }
}

// ============================================================================
// Equipment Profiles Notifier
// ============================================================================

/// State class for equipment profiles
class EquipmentProfilesState {
  final List<EquipmentProfileModel> profiles;
  final EquipmentProfileModel? activeProfile;
  final bool isLoading;
  final String? error;

  const EquipmentProfilesState({
    this.profiles = const [],
    this.activeProfile,
    this.isLoading = false,
    this.error,
  });

  EquipmentProfilesState copyWith({
    List<EquipmentProfileModel>? profiles,
    EquipmentProfileModel? activeProfile,
    bool? isLoading,
    String? error,
  }) {
    return EquipmentProfilesState(
      profiles: profiles ?? this.profiles,
      activeProfile: activeProfile ?? this.activeProfile,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Notifier for managing equipment profiles
class EquipmentProfilesNotifier extends AsyncNotifier<EquipmentProfilesState> {
  @override
  Future<EquipmentProfilesState> build() async {
    // Set up a watch on the database profiles
    final profilesStream = ref.watch(allProfilesProvider);
    final activeStream = ref.watch(activeProfileProvider);
    
    List<EquipmentProfileModel> profiles = [];
    EquipmentProfileModel? active;
    
    if (profilesStream.hasValue) {
      profiles = profilesStream.value!.map((p) => EquipmentProfileModel.fromDatabase(p)).toList();
    }
    
    if (activeStream.hasValue && activeStream.value != null) {
      active = EquipmentProfileModel.fromDatabase(activeStream.value!);
    }
    
    return EquipmentProfilesState(
      profiles: profiles,
      activeProfile: active,
    );
  }

  /// Create a new profile
  Future<int> createProfile({
    required String name,
    String? description,
  }) async {
    final dao = ref.read(equipmentProfilesDaoProvider);
    
    final id = await dao.createProfile(
      EquipmentProfilesCompanion.insert(
        name: name,
        description: Value(description),
      ),
    );
    
    // Refresh state
    ref.invalidateSelf();
    
    return id;
  }

  /// Update an existing profile
  Future<void> updateProfile(EquipmentProfileModel profile) async {
    if (profile.id == null) {
      throw Exception('Cannot update profile without ID');
    }
    
    final dao = ref.read(equipmentProfilesDaoProvider);
    final dbProfile = await dao.getProfileById(profile.id!);
    
    if (dbProfile == null) {
      throw Exception('Profile not found');
    }
    
    // Create updated profile
    final updated = dbProfile.copyWith(
      name: profile.name,
      description: Value(profile.description),
      cameraId: Value(profile.cameraId),
      mountId: Value(profile.mountId),
      focuserId: Value(profile.focuserId),
      filterWheelId: Value(profile.filterWheelId),
      guiderId: Value(profile.guiderId),
      rotatorId: Value(profile.rotatorId),
      domeId: Value(profile.domeId),
      weatherId: Value(profile.weatherId),
      coverCalibratorId: Value(profile.coverCalibratorId),
      focalLength: profile.focalLength,
      aperture: profile.aperture,
      focalRatio: Value(profile.focalRatio),
      defaultGain: Value(profile.defaultGain),
      defaultOffset: Value(profile.defaultOffset),
      defaultBinX: profile.defaultBinX,
      defaultBinY: profile.defaultBinY,
      defaultCoolingTemp: Value(profile.defaultCoolingTemp),
      filterNames: Value(profile.filterNames.isNotEmpty ? jsonEncode(profile.filterNames) : null),
      filterFocusOffsets: Value(profile.filterFocusOffsets.isNotEmpty ? jsonEncode(profile.filterFocusOffsets) : null),
      updatedAt: DateTime.now(),
    );
    
    await dao.updateProfile(updated);
    ref.invalidateSelf();
  }

  /// Delete a profile
  Future<void> deleteProfile(int profileId) async {
    final dao = ref.read(equipmentProfilesDaoProvider);
    await dao.deleteProfile(profileId);
    ref.invalidateSelf();
  }

  /// Set a profile as active
  Future<void> setActiveProfile(int profileId) async {
    final dao = ref.read(equipmentProfilesDaoProvider);
    await dao.setActiveProfile(profileId);
    ref.invalidateSelf();
  }

  /// Duplicate a profile
  Future<int> duplicateProfile(int sourceId, String newName) async {
    final dao = ref.read(equipmentProfilesDaoProvider);
    final id = await dao.duplicateProfile(sourceId, newName);
    ref.invalidateSelf();
    return id;
  }

  /// Import profiles from JSON
  Future<List<int>> importProfiles(String json) async {
    final service = ref.read(profileServiceProvider);
    final ids = await service.importAllProfilesFromJson(json);
    ref.invalidateSelf();
    return ids;
  }

  /// Export all profiles to JSON
  Future<String> exportAllProfiles() async {
    final service = ref.read(profileServiceProvider);
    return await service.exportAllProfilesToJson();
  }

  /// Export a single profile to JSON
  Future<String> exportProfile(int profileId) async {
    final service = ref.read(profileServiceProvider);
    return await service.exportProfileToJson(profileId);
  }
}

/// Main provider for equipment profiles
final equipmentProfilesProvider = AsyncNotifierProvider<EquipmentProfilesNotifier, EquipmentProfilesState>(() {
  return EquipmentProfilesNotifier();
});

/// Provider for watching just the active profile (convenience)
final activeEquipmentProfileProvider = Provider<EquipmentProfileModel?>((ref) {
  final state = ref.watch(equipmentProfilesProvider);
  return state.valueOrNull?.activeProfile;
});

/// Provider for watching just the profile list (convenience)
final equipmentProfileListProvider = Provider<List<EquipmentProfileModel>>((ref) {
  final state = ref.watch(equipmentProfilesProvider);
  return state.valueOrNull?.profiles ?? [];
});





