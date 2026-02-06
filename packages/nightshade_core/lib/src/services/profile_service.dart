import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../models/equipment/equipment_models.dart';
import '../providers/database_provider.dart';
import '../providers/equipment_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/unified_discovery_provider.dart';
import 'device_service.dart';

/// Result of validating a profile's devices against discovered devices
class ProfileValidationResult {
  /// Whether all devices in the profile are available
  final bool isValid;

  /// List of device types that are configured in profile but not found
  final List<String> missingDevices;

  /// List of device types that are configured and available
  final List<String> availableDevices;

  /// Map of device type to device ID for devices that are missing
  final Map<String, String> missingDeviceIds;

  const ProfileValidationResult({
    required this.isValid,
    required this.missingDevices,
    required this.availableDevices,
    this.missingDeviceIds = const {},
  });

  /// Create a result indicating all devices are valid
  const ProfileValidationResult.valid({
    required this.availableDevices,
  })  : isValid = true,
        missingDevices = const [],
        missingDeviceIds = const {};
}

/// Service for managing equipment profiles with auto-connect and import/export
class ProfileService {
  final Ref _ref;

  ProfileService(this._ref);

  // ===========================================================================
  // Profile Validation
  // ===========================================================================

  /// Validate that all devices in a profile are currently discoverable
  ///
  /// Checks each device ID configured in the profile against currently
  /// discovered devices. Returns a result indicating which devices are
  /// available and which are missing.
  Future<ProfileValidationResult> validateProfile(int profileId) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile = await dao.getProfileById(profileId);

    if (profile == null) {
      throw Exception('Profile not found');
    }

    // Get the current discovery state
    final discoveryState = _ref.read(unifiedDiscoveryProvider);
    final rawDevices = discoveryState.rawDevices;

    // Build set of discovered device IDs for fast lookup
    final discoveredIds = rawDevices.map((d) => d.id).toSet();

    final missingDevices = <String>[];
    final availableDevices = <String>[];
    final missingDeviceIds = <String, String>{};

    // Check each device type
    void checkDevice(String? deviceId, String deviceType) {
      if (deviceId != null && deviceId.isNotEmpty) {
        if (discoveredIds.contains(deviceId)) {
          availableDevices.add(deviceType);
        } else {
          missingDevices.add(deviceType);
          missingDeviceIds[deviceType] = deviceId;
        }
      }
    }

    checkDevice(profile.cameraId, 'Camera');
    checkDevice(profile.mountId, 'Mount');
    checkDevice(profile.focuserId, 'Focuser');
    checkDevice(profile.filterWheelId, 'Filter Wheel');
    checkDevice(profile.guiderId, 'Guider');
    checkDevice(profile.rotatorId, 'Rotator');
    checkDevice(profile.domeId, 'Dome');
    checkDevice(profile.weatherId, 'Weather');

    return ProfileValidationResult(
      isValid: missingDevices.isEmpty,
      missingDevices: missingDevices,
      availableDevices: availableDevices,
      missingDeviceIds: missingDeviceIds,
    );
  }

  // ===========================================================================
  // Profile Loading with Auto-Connect
  // ===========================================================================

  /// Load and activate a profile, optionally connecting devices
  Future<void> loadProfile(int profileId, {bool autoConnect = false}) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    
    // Set this profile as active
    await dao.setActiveProfile(profileId);
    
    // Auto-connect if requested
    if (autoConnect) {
      final profile = await dao.getProfileById(profileId);
      if (profile != null) {
        await _connectProfileDevices(profile);
      }
    }
  }
  
  /// Connect devices from a profile
  Future<void> _connectProfileDevices(EquipmentProfile profile) async {
    final deviceService = _ref.read(deviceServiceProvider);
    
    await deviceService.connectProfile(
      cameraId: profile.cameraId,
      mountId: profile.mountId,
      focuserId: profile.focuserId,
      filterWheelId: profile.filterWheelId,
      guiderId: profile.guiderId,
    );
  }
  
  /// Auto-connect to active profile's devices on startup
  Future<void> autoConnectOnStartup() async {
    final autoConnect = await _ref.read(autoConnectSettingsProvider.future);
    
    if (!autoConnect) return;
    
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final activeProfile = await dao.getActiveProfile();
    
    if (activeProfile != null) {
      await _connectProfileDevices(activeProfile);
    }
  }
  
  // ===========================================================================
  // Profile Import/Export
  // ===========================================================================
  
  /// Export a profile to JSON
  Future<String> exportProfileToJson(int profileId) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile = await dao.getProfileById(profileId);
    
    if (profile == null) {
      throw Exception('Profile not found');
    }
    
    final exportData = ProfileExportData.fromDatabase(profile);
    return jsonEncode(exportData.toJson());
  }
  
  /// Export a profile to a file
  Future<void> exportProfileToFile(int profileId, String filePath) async {
    final json = await exportProfileToJson(profileId);
    final file = File(filePath);
    await file.writeAsString(json);
  }
  
  /// Export all profiles to JSON
  Future<String> exportAllProfilesToJson() async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profiles = await dao.getAllProfiles();
    
    final exportData = profiles.map((p) => ProfileExportData.fromDatabase(p).toJson()).toList();
    return jsonEncode({
      'version': 1,
      'exportDate': DateTime.now().toIso8601String(),
      'profiles': exportData,
    });
  }
  
  /// Export all profiles to a file
  Future<void> exportAllProfilesToFile(String filePath) async {
    final json = await exportAllProfilesToJson();
    final file = File(filePath);
    await file.writeAsString(json);
  }
  
  /// Import a profile from JSON
  Future<int> importProfileFromJson(String json) async {
    final data = jsonDecode(json);
    
    // Handle single profile export
    final profileData = data is Map && data.containsKey('profiles')
        ? data['profiles'][0]
        : data;
    
    final exportData = ProfileExportData.fromJson(profileData);
    return await _createProfileFromExport(exportData);
  }
  
  /// Import a profile from a file
  Future<int> importProfileFromFile(String filePath) async {
    final file = File(filePath);
    final json = await file.readAsString();
    return await importProfileFromJson(json);
  }
  
  /// Import all profiles from JSON (batch import)
  Future<List<int>> importAllProfilesFromJson(String json) async {
    final data = jsonDecode(json);
    
    List<dynamic> profilesData;
    if (data is Map && data.containsKey('profiles')) {
      profilesData = data['profiles'];
    } else if (data is List) {
      profilesData = data;
    } else {
      // Single profile
      profilesData = [data];
    }
    
    final ids = <int>[];
    for (final profileJson in profilesData) {
      final exportData = ProfileExportData.fromJson(profileJson);
      final id = await _createProfileFromExport(exportData);
      ids.add(id);
    }
    
    return ids;
  }
  
  /// Import all profiles from a file
  Future<List<int>> importAllProfilesFromFile(String filePath) async {
    final file = File(filePath);
    final json = await file.readAsString();
    return await importAllProfilesFromJson(json);
  }
  
  /// Create a profile from export data
  Future<int> _createProfileFromExport(ProfileExportData data) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    
    // Check for name conflicts and rename if needed
    final existingProfiles = await dao.getAllProfiles();
    var name = data.name;
    var suffix = 1;
    while (existingProfiles.any((p) => p.name == name)) {
      name = '${data.name} ($suffix)';
      suffix++;
    }
    
    return await dao.createProfile(
      EquipmentProfilesCompanion.insert(
        name: name,
        description: Value(data.description),
        cameraId: Value(data.cameraId),
        mountId: Value(data.mountId),
        focuserId: Value(data.focuserId),
        filterWheelId: Value(data.filterWheelId),
        guiderId: Value(data.guiderId),
        rotatorId: Value(data.rotatorId),
        domeId: Value(data.domeId),
        weatherId: Value(data.weatherId),
        focalLength: Value(data.focalLength),
        aperture: Value(data.aperture),
        focalRatio: Value(data.focalRatio),
        defaultGain: Value(data.defaultGain),
        defaultOffset: Value(data.defaultOffset),
        defaultBinX: Value(data.defaultBinX),
        defaultBinY: Value(data.defaultBinY),
        defaultCoolingTemp: Value(data.defaultCoolingTemp),
        filterNames: Value(data.filterNames != null ? jsonEncode(data.filterNames) : null),
        filterFocusOffsets: Value(data.filterFocusOffsets != null ? jsonEncode(data.filterFocusOffsets) : null),
      ),
    );
  }
  
  // ===========================================================================
  // Profile Management
  // ===========================================================================
  
  /// Create a new empty profile
  Future<int> createProfile(String name, {String? description}) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    
    return await dao.createProfile(
      EquipmentProfilesCompanion.insert(
        name: name,
        description: Value(description),
      ),
    );
  }
  
  /// Duplicate an existing profile
  Future<int> duplicateProfile(int sourceId, String newName) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    return await dao.duplicateProfile(sourceId, newName);
  }
  
  /// Delete a profile
  Future<void> deleteProfile(int profileId) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    await dao.deleteProfile(profileId);
  }
  
  /// Clear specific device assignments from a profile
  ///
  /// [deviceTypes] is a set of device type names (e.g., 'Camera', 'Mount')
  /// that should be cleared (set to null) in the profile.
  Future<void> clearDevicesFromProfile(
    int profileId,
    Set<String> deviceTypes,
  ) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile = await dao.getProfileById(profileId);

    if (profile == null) {
      throw Exception('Profile not found');
    }

    await dao.updateProfile(profile.copyWith(
      cameraId: deviceTypes.contains('Camera') ? const Value(null) : Value(profile.cameraId),
      mountId: deviceTypes.contains('Mount') ? const Value(null) : Value(profile.mountId),
      focuserId: deviceTypes.contains('Focuser') ? const Value(null) : Value(profile.focuserId),
      filterWheelId: deviceTypes.contains('Filter Wheel') ? const Value(null) : Value(profile.filterWheelId),
      guiderId: deviceTypes.contains('Guider') ? const Value(null) : Value(profile.guiderId),
      rotatorId: deviceTypes.contains('Rotator') ? const Value(null) : Value(profile.rotatorId),
      domeId: deviceTypes.contains('Dome') ? const Value(null) : Value(profile.domeId),
      weatherId: deviceTypes.contains('Weather') ? const Value(null) : Value(profile.weatherId),
      updatedAt: DateTime.now(),
    ));
  }

  /// Update profile device assignments
  Future<void> updateProfileDevices(
    int profileId, {
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterWheelId,
    String? guiderId,
    String? rotatorId,
    String? domeId,
    String? weatherId,
  }) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile = await dao.getProfileById(profileId);
    
    if (profile == null) {
      throw Exception('Profile not found');
    }
    
    await dao.updateProfile(profile.copyWith(
      cameraId: Value(cameraId ?? profile.cameraId),
      mountId: Value(mountId ?? profile.mountId),
      focuserId: Value(focuserId ?? profile.focuserId),
      filterWheelId: Value(filterWheelId ?? profile.filterWheelId),
      guiderId: Value(guiderId ?? profile.guiderId),
      rotatorId: Value(rotatorId ?? profile.rotatorId),
      domeId: Value(domeId ?? profile.domeId),
      weatherId: Value(weatherId ?? profile.weatherId),
      updatedAt: DateTime.now(),
    ));
  }
  
  /// Update profile optical configuration
  Future<void> updateProfileOptics(
    int profileId, {
    double? focalLength,
    double? aperture,
    double? focalRatio,
  }) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile = await dao.getProfileById(profileId);
    
    if (profile == null) {
      throw Exception('Profile not found');
    }
    
    await dao.updateProfile(profile.copyWith(
      focalLength: focalLength ?? profile.focalLength,
      aperture: aperture ?? profile.aperture,
      focalRatio: Value(focalRatio ?? profile.focalRatio),
      updatedAt: DateTime.now(),
    ));
  }
  
  /// Update profile default camera settings
  Future<void> updateProfileCameraDefaults(
    int profileId, {
    int? defaultGain,
    int? defaultOffset,
    int? defaultBinX,
    int? defaultBinY,
    double? defaultCoolingTemp,
  }) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile = await dao.getProfileById(profileId);
    
    if (profile == null) {
      throw Exception('Profile not found');
    }
    
    await dao.updateProfile(profile.copyWith(
      defaultGain: Value(defaultGain ?? profile.defaultGain),
      defaultOffset: Value(defaultOffset ?? profile.defaultOffset),
      defaultBinX: defaultBinX ?? profile.defaultBinX,
      defaultBinY: defaultBinY ?? profile.defaultBinY,
      defaultCoolingTemp: Value(defaultCoolingTemp ?? profile.defaultCoolingTemp),
      updatedAt: DateTime.now(),
    ));
  }
  
  /// Save all currently connected devices to the active profile
  ///
  /// Reads current device states and updates the active profile with
  /// all connected device IDs. Returns true if saved successfully.
  Future<bool> saveConnectedDevicesToProfile() async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final activeProfile = await dao.getActiveProfile();

    if (activeProfile == null) {
      debugPrint('ProfileService: No active profile to save devices to');
      return false;
    }

    // Read all device states
    final cameraState = _ref.read(cameraStateProvider);
    final mountState = _ref.read(mountStateProvider);
    final focuserState = _ref.read(focuserStateProvider);
    final filterWheelState = _ref.read(filterWheelStateProvider);
    final guiderState = _ref.read(guiderStateProvider);
    final rotatorState = _ref.read(rotatorStateProvider);
    final domeState = _ref.read(domeStateProvider);
    final weatherState = _ref.read(weatherStateProvider);

    // Collect connected device IDs
    String? cameraId;
    String? mountId;
    String? focuserId;
    String? filterWheelId;
    String? guiderId;
    String? rotatorId;
    String? domeId;
    String? weatherId;

    if (cameraState.connectionState == DeviceConnectionState.connected) {
      cameraId = cameraState.deviceId;
    }
    if (mountState.connectionState == DeviceConnectionState.connected) {
      mountId = mountState.deviceId;
    }
    if (focuserState.connectionState == DeviceConnectionState.connected) {
      focuserId = focuserState.deviceId;
    }
    if (filterWheelState.connectionState == DeviceConnectionState.connected) {
      filterWheelId = filterWheelState.deviceId;
    }
    if (guiderState.connectionState == DeviceConnectionState.connected) {
      guiderId = guiderState.deviceId;
    }
    if (rotatorState.connectionState == DeviceConnectionState.connected) {
      rotatorId = rotatorState.deviceId;
    }
    if (domeState.connectionState == DeviceConnectionState.connected) {
      domeId = domeState.deviceId;
    }
    if (weatherState.connectionState == DeviceConnectionState.connected) {
      weatherId = weatherState.deviceId;
    }

    // Check if any devices are connected
    final hasConnectedDevices = cameraId != null ||
        mountId != null ||
        focuserId != null ||
        filterWheelId != null ||
        guiderId != null ||
        rotatorId != null ||
        domeId != null ||
        weatherId != null;

    if (!hasConnectedDevices) {
      debugPrint('ProfileService: No connected devices to save');
      return false;
    }

    // Update the profile with connected device IDs
    await dao.updateProfile(activeProfile.copyWith(
      cameraId: Value(cameraId ?? activeProfile.cameraId),
      mountId: Value(mountId ?? activeProfile.mountId),
      focuserId: Value(focuserId ?? activeProfile.focuserId),
      filterWheelId: Value(filterWheelId ?? activeProfile.filterWheelId),
      guiderId: Value(guiderId ?? activeProfile.guiderId),
      rotatorId: Value(rotatorId ?? activeProfile.rotatorId),
      domeId: Value(domeId ?? activeProfile.domeId),
      weatherId: Value(weatherId ?? activeProfile.weatherId),
      updatedAt: DateTime.now(),
    ));

    debugPrint('ProfileService: Saved connected devices to profile "${activeProfile.name}"');
    return true;
  }

  /// Update profile filter configuration
  Future<void> updateProfileFilters(
    int profileId, {
    List<String>? filterNames,
    Map<String, int>? filterFocusOffsets,
  }) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile = await dao.getProfileById(profileId);

    if (profile == null) {
      throw Exception('Profile not found');
    }

    await dao.updateProfile(profile.copyWith(
      filterNames: Value(filterNames != null ? jsonEncode(filterNames) : profile.filterNames),
      filterFocusOffsets: Value(filterFocusOffsets != null ? jsonEncode(filterFocusOffsets) : profile.filterFocusOffsets),
      updatedAt: DateTime.now(),
    ));
  }

  /// Sync filter names from connected filter wheel to the active profile
  /// Returns true if filters were synced, false otherwise
  Future<bool> syncFiltersFromHardware() async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final activeProfile = await dao.getActiveProfile();

    if (activeProfile == null) {
      debugPrint('ProfileService: No active profile to sync filters to');
      return false;
    }

    // Import the equipment provider to access filter wheel state
    final filterWheelState = _ref.read(filterWheelStateProvider);

    if (filterWheelState.connectionState != DeviceConnectionState.connected) {
      debugPrint('ProfileService: Filter wheel not connected');
      return false;
    }

    final hwFilterNames = filterWheelState.filterNames;
    if (hwFilterNames.isEmpty) {
      debugPrint('ProfileService: No filter names from hardware');
      return false;
    }

    // Parse existing filter offsets from profile
    Map<String, int> existingOffsets = {};
    if (activeProfile.filterFocusOffsets != null) {
      try {
        existingOffsets = (jsonDecode(activeProfile.filterFocusOffsets!) as Map)
            .cast<String, int>();
      } catch (_) {}
    }

    // Build new offsets map, preserving existing offsets for matching filter names
    final newOffsets = <String, int>{};
    for (final filterName in hwFilterNames) {
      newOffsets[filterName] = existingOffsets[filterName] ?? 0;
    }

    await dao.updateProfile(activeProfile.copyWith(
      filterNames: Value(jsonEncode(hwFilterNames)),
      filterFocusOffsets: Value(jsonEncode(newOffsets)),
      updatedAt: DateTime.now(),
    ));

    debugPrint('ProfileService: Synced ${hwFilterNames.length} filters to profile "${activeProfile.name}"');
    return true;
  }

  /// Sync filter names from connected filter wheel to a specific profile
  Future<bool> syncFiltersToProfile(int profileId) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile = await dao.getProfileById(profileId);

    if (profile == null) {
      throw Exception('Profile not found');
    }

    final filterWheelState = _ref.read(filterWheelStateProvider);

    if (filterWheelState.connectionState != DeviceConnectionState.connected) {
      return false;
    }

    final hwFilterNames = filterWheelState.filterNames;
    if (hwFilterNames.isEmpty) {
      return false;
    }

    // Parse existing filter offsets
    Map<String, int> existingOffsets = {};
    if (profile.filterFocusOffsets != null) {
      try {
        existingOffsets = (jsonDecode(profile.filterFocusOffsets!) as Map)
            .cast<String, int>();
      } catch (_) {}
    }

    // Build new offsets map
    final newOffsets = <String, int>{};
    for (final filterName in hwFilterNames) {
      newOffsets[filterName] = existingOffsets[filterName] ?? 0;
    }

    await dao.updateProfile(profile.copyWith(
      filterNames: Value(jsonEncode(hwFilterNames)),
      filterFocusOffsets: Value(jsonEncode(newOffsets)),
      updatedAt: DateTime.now(),
    ));

    return true;
  }
}

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
        filterNames = (jsonDecode(profile.filterNames!) as List).cast<String>();
      } catch (e) {
        // Malformed filter names JSON - skip
        debugPrint('ProfileService: Failed to parse filterNames: $e');
      }
    }

    if (profile.filterFocusOffsets != null) {
      try {
        filterOffsets = (jsonDecode(profile.filterFocusOffsets!) as Map).cast<String, int>();
      } catch (e) {
        // Malformed filter offsets JSON - skip
        debugPrint('ProfileService: Failed to parse filterFocusOffsets: $e');
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
      focalLength: (json['focalLength'] as num?)?.toDouble() ?? 0.0,
      aperture: (json['aperture'] as num?)?.toDouble() ?? 0.0,
      focalRatio: (json['focalRatio'] as num?)?.toDouble(),
      defaultGain: json['defaultGain'] as int?,
      defaultOffset: json['defaultOffset'] as int?,
      defaultBinX: json['defaultBinX'] as int? ?? 1,
      defaultBinY: json['defaultBinY'] as int? ?? 1,
      defaultCoolingTemp: (json['defaultCoolingTemp'] as num?)?.toDouble(),
      filterNames: (json['filterNames'] as List?)?.cast<String>(),
      filterFocusOffsets: (json['filterFocusOffsets'] as Map?)?.cast<String, int>(),
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

/// Provider for the profile service
final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService(ref);
});

