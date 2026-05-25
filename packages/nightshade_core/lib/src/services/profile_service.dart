import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../models/equipment/equipment_models.dart';
import '../providers/database_provider.dart';
import '../providers/equipment_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/unified_discovery_provider.dart';
import '../utils/json_validation.dart';
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
    checkDevice(profile.coverCalibratorId, 'Cover Calibrator');

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

  /// Set or clear the default startup profile.
  Future<void> setDefaultProfile(int? profileId,
      {bool makeActive = true}) async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    if (profileId == null) {
      await dao.clearDefaultProfile();
      return;
    }
    await dao.setDefaultProfile(profileId, makeActive: makeActive);
  }

  /// Connect devices from a profile
  Future<void> _connectProfileDevices(EquipmentProfile profile) async {
    final deviceService = _ref.read(deviceServiceProvider);
    final connections = <Future<void> Function()>[
      if (profile.cameraId != null)
        () => deviceService.connectCamera(profile.cameraId!),
      if (profile.mountId != null)
        () => deviceService.connectMount(profile.mountId!),
      if (profile.focuserId != null)
        () => deviceService.connectFocuser(profile.focuserId!),
      if (profile.filterWheelId != null)
        () => deviceService.connectFilterWheel(profile.filterWheelId!),
      if (profile.guiderId != null)
        () => deviceService.connectGuider(profile.guiderId!),
      if (profile.rotatorId != null)
        () => deviceService.connectRotator(profile.rotatorId!),
      if (profile.domeId != null)
        () => deviceService.connectDome(profile.domeId!),
      if (profile.weatherId != null)
        () => deviceService.connectWeather(profile.weatherId!),
      if (profile.safetyMonitorId != null)
        () => deviceService.connectSafetyMonitor(profile.safetyMonitorId!),
      if (profile.coverCalibratorId != null)
        () => deviceService.connectCoverCalibrator(profile.coverCalibratorId!),
    ];

    await Future.wait(
      connections.map((connect) => connect()),
      eagerError: false,
    );
  }

  /// Auto-connect to active profile's devices on startup
  Future<void> autoConnectOnStartup() async {
    final autoConnect = await _ref.read(autoConnectSettingsProvider.future);

    if (!autoConnect) return;

    final dao = _ref.read(equipmentProfilesDaoProvider);
    final activeProfile =
        await dao.getDefaultProfile() ?? await dao.getActiveProfile();

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

    final exportData = profiles
        .map((p) => ProfileExportData.fromDatabase(p).toJson())
        .toList();
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
        safetyMonitorId: Value(data.safetyMonitorId),
        coverCalibratorId: Value(data.coverCalibratorId),
        focalLength: Value(data.focalLength),
        aperture: Value(data.aperture),
        focalRatio: Value(data.focalRatio),
        defaultGain: Value(data.defaultGain),
        defaultOffset: Value(data.defaultOffset),
        defaultBinX: Value(data.defaultBinX),
        defaultBinY: Value(data.defaultBinY),
        defaultCoolingTemp: Value(data.defaultCoolingTemp),
        coolOnConnect: Value(data.coolOnConnect),
        defaultCenteringExposure: Value(data.defaultCenteringExposure),
        filterNames: Value(
            data.filterNames != null ? jsonEncode(data.filterNames) : null),
        filterFocusOffsets: Value(data.filterFocusOffsets != null
            ? jsonEncode(data.filterFocusOffsets)
            : null),
        meridianFlipOverrides: Value(data.meridianFlipOverrides),
        cameraName: Value(data.cameraName),
        mountName: Value(data.mountName),
        focuserName: Value(data.focuserName),
        filterWheelName: Value(data.filterWheelName),
        guiderName: Value(data.guiderName),
        rotatorName: Value(data.rotatorName),
        telescopeName: Value(data.telescopeName),
        telescopeFocalLength: Value(data.telescopeFocalLength),
        telescopeAperture: Value(data.telescopeAperture),
        profileIcon: Value(data.profileIcon),
        profileColor: Value(data.profileColor),
        sortOrder: Value(data.sortOrder),
        isDefault: Value(data.isDefault),
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
      cameraId: deviceTypes.contains('Camera')
          ? const Value(null)
          : Value(profile.cameraId),
      mountId: deviceTypes.contains('Mount')
          ? const Value(null)
          : Value(profile.mountId),
      focuserId: deviceTypes.contains('Focuser')
          ? const Value(null)
          : Value(profile.focuserId),
      filterWheelId: deviceTypes.contains('Filter Wheel')
          ? const Value(null)
          : Value(profile.filterWheelId),
      guiderId: deviceTypes.contains('Guider')
          ? const Value(null)
          : Value(profile.guiderId),
      rotatorId: deviceTypes.contains('Rotator')
          ? const Value(null)
          : Value(profile.rotatorId),
      domeId: deviceTypes.contains('Dome')
          ? const Value(null)
          : Value(profile.domeId),
      weatherId: deviceTypes.contains('Weather')
          ? const Value(null)
          : Value(profile.weatherId),
      safetyMonitorId: deviceTypes.contains('Safety Monitor')
          ? const Value(null)
          : Value(profile.safetyMonitorId),
      coverCalibratorId: deviceTypes.contains('Cover Calibrator')
          ? const Value(null)
          : Value(profile.coverCalibratorId),
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
    String? safetyMonitorId,
    String? coverCalibratorId,
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
      safetyMonitorId: Value(safetyMonitorId ?? profile.safetyMonitorId),
      coverCalibratorId: Value(coverCalibratorId ?? profile.coverCalibratorId),
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
      defaultCoolingTemp:
          Value(defaultCoolingTemp ?? profile.defaultCoolingTemp),
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
      developer.log('ProfileService: No active profile to save devices to',
          name: 'ProfileService', level: 900);
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
    final safetyMonitorState = _ref.read(safetyMonitorStateProvider);
    final coverCalibratorState = _ref.read(coverCalibratorStateProvider);

    // Collect connected device IDs
    String? cameraId;
    String? mountId;
    String? focuserId;
    String? filterWheelId;
    String? guiderId;
    String? rotatorId;
    String? domeId;
    String? weatherId;
    String? safetyMonitorId;
    String? coverCalibratorId;

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
    if (safetyMonitorState.connectionState == DeviceConnectionState.connected) {
      safetyMonitorId = safetyMonitorState.deviceId;
    }
    if (coverCalibratorState.connectionState ==
        DeviceConnectionState.connected) {
      coverCalibratorId = coverCalibratorState.deviceId;
    }

    // Check if any devices are connected
    final hasConnectedDevices = cameraId != null ||
        mountId != null ||
        focuserId != null ||
        filterWheelId != null ||
        guiderId != null ||
        rotatorId != null ||
        domeId != null ||
        weatherId != null ||
        safetyMonitorId != null ||
        coverCalibratorId != null;

    if (!hasConnectedDevices) {
      developer.log('ProfileService: No connected devices to save',
          name: 'ProfileService', level: 800);
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
      safetyMonitorId: Value(safetyMonitorId ?? activeProfile.safetyMonitorId),
      coverCalibratorId:
          Value(coverCalibratorId ?? activeProfile.coverCalibratorId),
      updatedAt: DateTime.now(),
    ));

    developer.log(
        'ProfileService: Saved connected devices to profile "${activeProfile.name}"',
        name: 'ProfileService',
        level: 800);
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
      filterNames: Value(
          filterNames != null ? jsonEncode(filterNames) : profile.filterNames),
      filterFocusOffsets: Value(filterFocusOffsets != null
          ? jsonEncode(filterFocusOffsets)
          : profile.filterFocusOffsets),
      updatedAt: DateTime.now(),
    ));
  }

  /// Sync filter names from connected filter wheel to the active profile
  /// Returns true if filters were synced, false otherwise
  Future<bool> syncFiltersFromHardware() async {
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final activeProfile = await dao.getActiveProfile();

    if (activeProfile == null) {
      developer.log('ProfileService: No active profile to sync filters to',
          name: 'ProfileService', level: 900);
      return false;
    }

    // Import the equipment provider to access filter wheel state
    final filterWheelState = _ref.read(filterWheelStateProvider);

    if (filterWheelState.connectionState != DeviceConnectionState.connected) {
      developer.log('ProfileService: Filter wheel not connected',
          name: 'ProfileService', level: 900);
      return false;
    }

    final hwFilterNames = filterWheelState.filterNames;
    if (hwFilterNames.isEmpty) {
      developer.log('ProfileService: No filter names from hardware',
          name: 'ProfileService', level: 900);
      return false;
    }

    // Parse existing filter offsets from profile
    Map<String, int> existingOffsets = {};
    if (activeProfile.filterFocusOffsets != null) {
      try {
        existingOffsets = decodeStringIntMapJson(
          activeProfile.filterFocusOffsets,
          context:
              'equipment_profiles.filter_focus_offsets for "${activeProfile.name}"',
        );
      } catch (error, stack) {
        developer.log(
          'ProfileService: Failed to parse filterFocusOffsets for profile '
          '"${activeProfile.name}" (id=${activeProfile.id}). '
          'Value=${activeProfile.filterFocusOffsets} Error=$error',
          name: 'ProfileService',
          level: 1000,
          error: error,
          stackTrace: stack,
        );
      }
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

    developer.log(
        'ProfileService: Synced ${hwFilterNames.length} filters to profile "${activeProfile.name}"',
        name: 'ProfileService',
        level: 800);
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
        existingOffsets = decodeStringIntMapJson(
          profile.filterFocusOffsets,
          context:
              'equipment_profiles.filter_focus_offsets for "${profile.name}"',
        );
      } catch (error, stack) {
        developer.log(
          'ProfileService: Failed to parse filterFocusOffsets for profile '
          '"${profile.name}" (id=${profile.id}). '
          'Value=${profile.filterFocusOffsets} Error=$error',
          name: 'ProfileService',
          level: 1000,
          error: error,
          stackTrace: stack,
        );
      }
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

const int _profileExportSchemaVersion = 1;

/// Data class for profile import/export
class ProfileExportData {
  final int schemaVersion;
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
  final String? coverCalibratorId;
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
  final String? cameraName;
  final String? mountName;
  final String? focuserName;
  final String? filterWheelName;
  final String? guiderName;
  final String? rotatorName;
  final String? telescopeName;
  final double? telescopeFocalLength;
  final double? telescopeAperture;
  final String? profileIcon;
  final int? profileColor;
  final int sortOrder;
  final bool isDefault;

  ProfileExportData({
    this.schemaVersion = _profileExportSchemaVersion,
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
    this.coverCalibratorId,
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
    this.cameraName,
    this.mountName,
    this.focuserName,
    this.filterWheelName,
    this.guiderName,
    this.rotatorName,
    this.telescopeName,
    this.telescopeFocalLength,
    this.telescopeAperture,
    this.profileIcon,
    this.profileColor,
    this.sortOrder = 0,
    this.isDefault = false,
  });

  factory ProfileExportData.fromDatabase(EquipmentProfile profile) {
    List<String>? filterNames;
    Map<String, int>? filterOffsets;

    if (profile.filterNames != null) {
      filterNames = decodeStringListJson(
        profile.filterNames,
        context: 'equipment_profiles.filter_names for "${profile.name}"',
      );
    }

    if (profile.filterFocusOffsets != null) {
      filterOffsets = decodeStringIntMapJson(
        profile.filterFocusOffsets,
        context:
            'equipment_profiles.filter_focus_offsets for "${profile.name}"',
      );
    }

    return ProfileExportData(
      schemaVersion: _profileExportSchemaVersion,
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
      coverCalibratorId: profile.coverCalibratorId,
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
      cameraName: profile.cameraName,
      mountName: profile.mountName,
      focuserName: profile.focuserName,
      filterWheelName: profile.filterWheelName,
      guiderName: profile.guiderName,
      rotatorName: profile.rotatorName,
      telescopeName: profile.telescopeName,
      telescopeFocalLength: profile.telescopeFocalLength,
      telescopeAperture: profile.telescopeAperture,
      profileIcon: profile.profileIcon,
      profileColor: profile.profileColor,
      sortOrder: profile.sortOrder,
      isDefault: profile.isDefault,
    );
  }

  factory ProfileExportData.fromJson(Map<String, dynamic> json) {
    final schemaVersion = jsonInt(
          json['schemaVersion'] ?? json['version'],
          context: 'profile.schemaVersion',
        ) ??
        _profileExportSchemaVersion;
    if (schemaVersion > _profileExportSchemaVersion) {
      throw FormatException(
        'Unsupported profile schemaVersion $schemaVersion '
        '(max $_profileExportSchemaVersion)',
      );
    }

    return ProfileExportData(
      schemaVersion: schemaVersion,
      name:
          jsonString(json['name'], context: 'profile.name', allowEmpty: false)!,
      description:
          jsonString(json['description'], context: 'profile.description'),
      cameraId: jsonString(json['cameraId'], context: 'profile.cameraId'),
      mountId: jsonString(json['mountId'], context: 'profile.mountId'),
      focuserId: jsonString(json['focuserId'], context: 'profile.focuserId'),
      filterWheelId:
          jsonString(json['filterWheelId'], context: 'profile.filterWheelId'),
      guiderId: jsonString(json['guiderId'], context: 'profile.guiderId'),
      rotatorId: jsonString(json['rotatorId'], context: 'profile.rotatorId'),
      domeId: jsonString(json['domeId'], context: 'profile.domeId'),
      weatherId: jsonString(json['weatherId'], context: 'profile.weatherId'),
      safetyMonitorId: jsonString(
        json['safetyMonitorId'],
        context: 'profile.safetyMonitorId',
      ),
      coverCalibratorId: jsonString(
        json['coverCalibratorId'],
        context: 'profile.coverCalibratorId',
      ),
      focalLength:
          jsonDouble(json['focalLength'], context: 'profile.focalLength') ??
              0.0,
      aperture:
          jsonDouble(json['aperture'], context: 'profile.aperture') ?? 0.0,
      focalRatio: jsonDouble(json['focalRatio'], context: 'profile.focalRatio'),
      defaultGain: jsonInt(json['defaultGain'], context: 'profile.defaultGain'),
      defaultOffset:
          jsonInt(json['defaultOffset'], context: 'profile.defaultOffset'),
      defaultBinX:
          jsonInt(json['defaultBinX'], context: 'profile.defaultBinX') ?? 1,
      defaultBinY:
          jsonInt(json['defaultBinY'], context: 'profile.defaultBinY') ?? 1,
      defaultCoolingTemp: jsonDouble(
        json['defaultCoolingTemp'],
        context: 'profile.defaultCoolingTemp',
      ),
      coolOnConnect: json['coolOnConnect'] as bool? ?? false,
      defaultCenteringExposure: jsonDouble(json['defaultCenteringExposure'],
          context: 'profile.defaultCenteringExposure'),
      filterNames: (json['filterNames'] as List?)?.cast<String>(),
      filterFocusOffsets: (json['filterFocusOffsets'] as Map?)?.map(
        (key, value) => MapEntry(
          key.toString(),
          (value as num).toInt(),
        ),
      ),
      meridianFlipOverrides: jsonString(
        json['meridianFlipOverrides'],
        context: 'profile.meridianFlipOverrides',
      ),
      cameraName: jsonString(json['cameraName'], context: 'profile.cameraName'),
      mountName: jsonString(json['mountName'], context: 'profile.mountName'),
      focuserName:
          jsonString(json['focuserName'], context: 'profile.focuserName'),
      filterWheelName: jsonString(
        json['filterWheelName'],
        context: 'profile.filterWheelName',
      ),
      guiderName: jsonString(json['guiderName'], context: 'profile.guiderName'),
      rotatorName:
          jsonString(json['rotatorName'], context: 'profile.rotatorName'),
      telescopeName:
          jsonString(json['telescopeName'], context: 'profile.telescopeName'),
      telescopeFocalLength: jsonDouble(
        json['telescopeFocalLength'],
        context: 'profile.telescopeFocalLength',
      ),
      telescopeAperture: jsonDouble(
        json['telescopeAperture'],
        context: 'profile.telescopeAperture',
      ),
      profileIcon:
          jsonString(json['profileIcon'], context: 'profile.profileIcon'),
      profileColor:
          jsonInt(json['profileColor'], context: 'profile.profileColor'),
      sortOrder: jsonInt(json['sortOrder'], context: 'profile.sortOrder') ?? 0,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
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
      'coverCalibratorId': coverCalibratorId,
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
      'cameraName': cameraName,
      'mountName': mountName,
      'focuserName': focuserName,
      'filterWheelName': filterWheelName,
      'guiderName': guiderName,
      'rotatorName': rotatorName,
      'telescopeName': telescopeName,
      'telescopeFocalLength': telescopeFocalLength,
      'telescopeAperture': telescopeAperture,
      'profileIcon': profileIcon,
      'profileColor': profileColor,
      'sortOrder': sortOrder,
      'isDefault': isDefault,
    };
  }
}

/// Provider for the profile service
final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService(ref);
});
