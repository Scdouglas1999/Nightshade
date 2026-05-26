import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/network_backend.dart';
import '../database/database.dart';
import '../models/equipment/equipment_models.dart';
import '../models/equipment_profile.dart' as remote_profile;
import '../providers/backend_provider.dart';
import '../providers/database_provider.dart';
import '../providers/equipment_provider.dart';
import '../providers/profiles_provider.dart';
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

  NetworkBackend? get _remoteBackend {
    final backend = _ref.read(backendProvider);
    return backend is NetworkBackend ? backend : null;
  }

  EquipmentProfilesNotifier get _profilesNotifier =>
      _ref.read(equipmentProfilesProvider.notifier);

  Future<EquipmentProfileModel?> _getProfileModelById(int profileId) async {
    final remote = _remoteBackend;
    if (remote != null) {
      final profiles = await remote.getProfiles();
      for (final profile in profiles) {
        if (int.tryParse(profile.id) == profileId) {
          return EquipmentProfileModel.fromRemoteProfile(profile);
        }
      }
      return null;
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile = await dao.getProfileById(profileId);
    return profile != null
        ? EquipmentProfileModel.fromDatabase(profile)
        : null;
  }

  Future<EquipmentProfileModel?> _getActiveProfileModel() async {
    final cached = _ref.read(activeEquipmentProfileProvider);
    if (cached != null) {
      return cached;
    }

    final remote = _remoteBackend;
    if (remote != null) {
      final active = await remote.getActiveProfile();
      return active != null
          ? EquipmentProfileModel.fromRemoteProfile(active)
          : null;
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile = await dao.getActiveProfile();
    return profile != null
        ? EquipmentProfileModel.fromDatabase(profile)
        : null;
  }

  Future<EquipmentProfileModel?> _getStartupProfileModel() async {
    final remote = _remoteBackend;
    if (remote != null) {
      final profiles = await remote.getProfiles();
      remote_profile.EquipmentProfile? defaultProfile;
      remote_profile.EquipmentProfile? activeProfile;
      for (final profile in profiles) {
        if (profile.isDefault) {
          defaultProfile = profile;
        }
        if (profile.isActive) {
          activeProfile = profile;
        }
      }
      final chosen = defaultProfile ?? activeProfile;
      return chosen != null
          ? EquipmentProfileModel.fromRemoteProfile(chosen)
          : _ref.read(activeEquipmentProfileProvider);
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile =
        await dao.getDefaultProfile() ?? await dao.getActiveProfile();
    return profile != null
        ? EquipmentProfileModel.fromDatabase(profile)
        : null;
  }

  Future<void> _persistProfileModel(EquipmentProfileModel profile) async {
    final remote = _remoteBackend;
    if (remote != null) {
      await remote.saveProfile(profile.toRemoteProfile());
      _ref.invalidate(equipmentProfilesProvider);
      return;
    }

    if (profile.id == null) {
      throw StateError('Cannot persist profile without id on local backend');
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    final existing = await dao.getProfileById(profile.id!);
    if (existing == null) {
      throw Exception('Profile not found');
    }

    await dao.updateProfile(
      existing.copyWith(
        name: profile.name,
        description: Value(profile.description),
        isActive: profile.isActive,
        cameraId: Value(profile.cameraId),
        mountId: Value(profile.mountId),
        focuserId: Value(profile.focuserId),
        filterWheelId: Value(profile.filterWheelId),
        guiderId: Value(profile.guiderId),
        rotatorId: Value(profile.rotatorId),
        domeId: Value(profile.domeId),
        weatherId: Value(profile.weatherId),
        safetyMonitorId: Value(profile.safetyMonitorId),
        switchId: Value(profile.switchId),
        coverCalibratorId: Value(profile.coverCalibratorId),
        cameraName: Value(profile.cameraName),
        mountName: Value(profile.mountName),
        focuserName: Value(profile.focuserName),
        filterWheelName: Value(profile.filterWheelName),
        guiderName: Value(profile.guiderName),
        rotatorName: Value(profile.rotatorName),
        telescopeName: Value(profile.telescopeName),
        telescopeFocalLength: Value(profile.telescopeFocalLength),
        telescopeAperture: Value(profile.telescopeAperture),
        focalLength: profile.focalLength,
        aperture: profile.aperture,
        focalRatio: Value(profile.focalRatio),
        defaultGain: Value(profile.defaultGain),
        defaultOffset: Value(profile.defaultOffset),
        defaultBinX: profile.defaultBinX,
        defaultBinY: profile.defaultBinY,
        defaultCoolingTemp: Value(profile.defaultCoolingTemp),
        coolOnConnect: profile.coolOnConnect,
        defaultCenteringExposure: Value(profile.defaultCenteringExposure),
        filterNames: Value(
          profile.filterNames.isNotEmpty
              ? jsonEncode(profile.filterNames)
              : null,
        ),
        filterFocusOffsets: Value(
          profile.filterFocusOffsets.isNotEmpty
              ? jsonEncode(profile.filterFocusOffsets)
              : null,
        ),
        profileIcon: Value(profile.profileIcon),
        profileColor: Value(profile.profileColor),
        sortOrder: profile.sortOrder,
        isDefault: profile.isDefault,
        updatedAt: DateTime.now(),
      ),
    );
    _ref.invalidate(equipmentProfilesProvider);
  }

  // ===========================================================================
  // Profile Validation
  // ===========================================================================

  /// Validate that all devices in a profile are currently discoverable
  ///
  /// Checks each device ID configured in the profile against currently
  /// discovered devices. Returns a result indicating which devices are
  /// available and which are missing.
  Future<ProfileValidationResult> validateProfile(int profileId) async {
    final profile = await _getProfileModelById(profileId);

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
    checkDevice(profile.safetyMonitorId, 'Safety Monitor');
    checkDevice(profile.switchId, 'Switch');
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
    final remote = _remoteBackend;
    if (remote != null) {
      await remote.loadProfile(profileId.toString());
      _ref.invalidate(equipmentProfilesProvider);
      if (autoConnect) {
        final profile = await _getProfileModelById(profileId);
        if (profile != null) {
          await _connectProfileDevicesFromModel(profile);
        }
      }
      return;
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    await dao.setActiveProfile(profileId);
    _ref.invalidate(equipmentProfilesProvider);

    if (autoConnect) {
      final profile = await dao.getProfileById(profileId);
      if (profile != null) {
        await _connectProfileDevicesFromModel(
          EquipmentProfileModel.fromDatabase(profile),
        );
      }
    }
  }

  /// Set or clear the default startup profile.
  Future<void> setDefaultProfile(int? profileId, {bool makeActive = true}) async {
    if (_remoteBackend != null) {
      await _profilesNotifier.setDefaultProfile(profileId, makeActive: makeActive);
      return;
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    if (profileId == null) {
      await dao.clearDefaultProfile();
    } else {
      await dao.setDefaultProfile(profileId, makeActive: makeActive);
    }
    _ref.invalidate(equipmentProfilesProvider);
  }

  /// Connect devices from a profile model (local FFI or remote host).
  Future<void> _connectProfileDevicesFromModel(
    EquipmentProfileModel profile,
  ) async {
    final deviceService = _ref.read(deviceServiceProvider);
    final connections = <Future<void> Function()>[
      if (profile.cameraId != null && profile.cameraId!.isNotEmpty)
        () => deviceService.connectCamera(profile.cameraId!),
      if (profile.mountId != null && profile.mountId!.isNotEmpty)
        () => deviceService.connectMount(profile.mountId!),
      if (profile.focuserId != null && profile.focuserId!.isNotEmpty)
        () => deviceService.connectFocuser(profile.focuserId!),
      if (profile.filterWheelId != null && profile.filterWheelId!.isNotEmpty)
        () => deviceService.connectFilterWheel(profile.filterWheelId!),
      if (profile.guiderId != null && profile.guiderId!.isNotEmpty)
        () => deviceService.connectGuider(profile.guiderId!),
      if (profile.rotatorId != null && profile.rotatorId!.isNotEmpty)
        () => deviceService.connectRotator(profile.rotatorId!),
      if (profile.domeId != null && profile.domeId!.isNotEmpty)
        () => deviceService.connectDome(profile.domeId!),
      if (profile.weatherId != null && profile.weatherId!.isNotEmpty)
        () => deviceService.connectWeather(profile.weatherId!),
      if (profile.safetyMonitorId != null &&
          profile.safetyMonitorId!.isNotEmpty)
        () => deviceService.connectSafetyMonitor(profile.safetyMonitorId!),
      if (profile.switchId != null && profile.switchId!.isNotEmpty)
        () => deviceService.connectSwitch(profile.switchId!),
      if (profile.coverCalibratorId != null &&
          profile.coverCalibratorId!.isNotEmpty)
        () => deviceService.connectCoverCalibrator(profile.coverCalibratorId!),
    ];

    for (final connect in connections) {
      await connect();
    }
  }

  /// Auto-connect to active profile's devices on startup
  Future<void> autoConnectOnStartup() async {
    final autoConnect = await _ref.read(autoConnectSettingsProvider.future);

    if (!autoConnect) return;

    final activeProfile = await _getStartupProfileModel();
    if (activeProfile != null) {
      await _connectProfileDevicesFromModel(activeProfile);
    }
  }

  // ===========================================================================
  // Profile Import/Export
  // ===========================================================================

  /// Export a profile to JSON
  Future<String> exportProfileToJson(int profileId) async {
    final profile = await _getProfileModelById(profileId);

    if (profile == null) {
      throw Exception('Profile not found');
    }

    final exportData = ProfileExportData.fromModel(profile);
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
    final remote = _remoteBackend;
    final List<ProfileExportData> exportData;
    if (remote != null) {
      final profiles = await remote.getProfiles();
      exportData = profiles
          .map(
            (p) => ProfileExportData.fromModel(
              EquipmentProfileModel.fromRemoteProfile(p),
            ),
          )
          .toList();
    } else {
      final dao = _ref.read(equipmentProfilesDaoProvider);
      final profiles = await dao.getAllProfiles();
      exportData = profiles
          .map((p) => ProfileExportData.fromDatabase(p))
          .toList();
    }

    final exportJson = exportData.map((p) => p.toJson()).toList();
    return jsonEncode({
      'version': 1,
      'exportDate': DateTime.now().toIso8601String(),
      'profiles': exportJson,
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
    final remote = _remoteBackend;
    if (remote != null) {
      final existingProfiles = await remote.getProfiles();
      var name = data.name;
      var suffix = 1;
      while (existingProfiles.any((p) => p.name == name)) {
        name = '${data.name} ($suffix)';
        suffix++;
      }

      final model = EquipmentProfileModel(
        name: name,
        description: data.description,
        cameraId: data.cameraId,
        mountId: data.mountId,
        focuserId: data.focuserId,
        filterWheelId: data.filterWheelId,
        guiderId: data.guiderId,
        rotatorId: data.rotatorId,
        domeId: data.domeId,
        weatherId: data.weatherId,
        safetyMonitorId: data.safetyMonitorId,
        switchId: data.switchId,
        coverCalibratorId: data.coverCalibratorId,
        focalLength: data.focalLength,
        aperture: data.aperture,
        focalRatio: data.focalRatio,
        defaultGain: data.defaultGain,
        defaultOffset: data.defaultOffset,
        defaultBinX: data.defaultBinX,
        defaultBinY: data.defaultBinY,
        defaultCoolingTemp: data.defaultCoolingTemp,
        filterNames: data.filterNames ?? const [],
        filterFocusOffsets: data.filterFocusOffsets ?? const {},
      );
      await remote.saveProfile(model.toRemoteProfile());
      _ref.invalidate(equipmentProfilesProvider);
      final refreshed = await remote.getProfiles();
      for (final profile in refreshed) {
        if (profile.name == name) {
          final id = int.tryParse(profile.id);
          if (id != null) {
            return id;
          }
        }
      }
      throw StateError('Host saved imported profile "$name" but id was not resolved');
    }

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
        switchId: Value(data.switchId),
        coverCalibratorId: Value(data.coverCalibratorId),
        focalLength: Value(data.focalLength),
        aperture: Value(data.aperture),
        focalRatio: Value(data.focalRatio),
        defaultGain: Value(data.defaultGain),
        defaultOffset: Value(data.defaultOffset),
        defaultBinX: Value(data.defaultBinX),
        defaultBinY: Value(data.defaultBinY),
        defaultCoolingTemp: Value(data.defaultCoolingTemp),
        filterNames: Value(
            data.filterNames != null ? jsonEncode(data.filterNames) : null),
        filterFocusOffsets: Value(data.filterFocusOffsets != null
            ? jsonEncode(data.filterFocusOffsets)
            : null),
      ),
    );
  }

  // ===========================================================================
  // Profile Management
  // ===========================================================================

  /// Create a new empty profile
  Future<int> createProfile(String name, {String? description}) async {
    if (_remoteBackend != null) {
      return _profilesNotifier.createProfile(
        name: name,
        description: description,
      );
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    final id = await dao.createProfile(
      EquipmentProfilesCompanion.insert(
        name: name,
        description: Value(description),
      ),
    );
    _ref.invalidate(equipmentProfilesProvider);
    return id;
  }

  /// Duplicate an existing profile
  Future<int> duplicateProfile(int sourceId, String newName) async {
    if (_remoteBackend != null) {
      return _profilesNotifier.duplicateProfile(sourceId, newName);
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    final id = await dao.duplicateProfile(sourceId, newName);
    _ref.invalidate(equipmentProfilesProvider);
    return id;
  }

  /// Delete a profile
  Future<void> deleteProfile(int profileId) async {
    if (_remoteBackend != null) {
      await _profilesNotifier.deleteProfile(profileId);
      return;
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    await dao.deleteProfile(profileId);
    _ref.invalidate(equipmentProfilesProvider);
  }

  /// Clear specific device assignments from a profile
  ///
  /// [deviceTypes] is a set of device type names (e.g., 'Camera', 'Mount')
  /// that should be cleared (set to null) in the profile.
  Future<void> clearDevicesFromProfile(
    int profileId,
    Set<String> deviceTypes,
  ) async {
    final profile = await _getProfileModelById(profileId);
    if (profile == null) {
      throw Exception('Profile not found');
    }

    await _persistProfileModel(
      profile.copyWith(
        cameraId: deviceTypes.contains('Camera') ? null : profile.cameraId,
        mountId: deviceTypes.contains('Mount') ? null : profile.mountId,
        focuserId: deviceTypes.contains('Focuser') ? null : profile.focuserId,
        filterWheelId:
            deviceTypes.contains('Filter Wheel') ? null : profile.filterWheelId,
        guiderId: deviceTypes.contains('Guider') ? null : profile.guiderId,
        rotatorId: deviceTypes.contains('Rotator') ? null : profile.rotatorId,
        domeId: deviceTypes.contains('Dome') ? null : profile.domeId,
        weatherId: deviceTypes.contains('Weather') ? null : profile.weatherId,
        safetyMonitorId: deviceTypes.contains('Safety Monitor')
            ? null
            : profile.safetyMonitorId,
        switchId: deviceTypes.contains('Switch') ? null : profile.switchId,
        coverCalibratorId: deviceTypes.contains('Cover Calibrator')
            ? null
            : profile.coverCalibratorId,
      ),
    );
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
    String? switchId,
    String? coverCalibratorId,
  }) async {
    final profile = await _getProfileModelById(profileId);
    if (profile == null) {
      throw Exception('Profile not found');
    }

    await _persistProfileModel(
      profile.copyWith(
        cameraId: cameraId ?? profile.cameraId,
        mountId: mountId ?? profile.mountId,
        focuserId: focuserId ?? profile.focuserId,
        filterWheelId: filterWheelId ?? profile.filterWheelId,
        guiderId: guiderId ?? profile.guiderId,
        rotatorId: rotatorId ?? profile.rotatorId,
        domeId: domeId ?? profile.domeId,
        weatherId: weatherId ?? profile.weatherId,
        safetyMonitorId: safetyMonitorId ?? profile.safetyMonitorId,
        switchId: switchId ?? profile.switchId,
        coverCalibratorId: coverCalibratorId ?? profile.coverCalibratorId,
      ),
    );
  }

  /// Update profile optical configuration
  Future<void> updateProfileOptics(
    int profileId, {
    double? focalLength,
    double? aperture,
    double? focalRatio,
  }) async {
    final profile = await _getProfileModelById(profileId);
    if (profile == null) {
      throw Exception('Profile not found');
    }

    await _persistProfileModel(
      profile.copyWith(
        focalLength: focalLength ?? profile.focalLength,
        aperture: aperture ?? profile.aperture,
        focalRatio: focalRatio ?? profile.focalRatio,
      ),
    );
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
    final profile = await _getProfileModelById(profileId);
    if (profile == null) {
      throw Exception('Profile not found');
    }

    await _persistProfileModel(
      profile.copyWith(
        defaultGain: defaultGain ?? profile.defaultGain,
        defaultOffset: defaultOffset ?? profile.defaultOffset,
        defaultBinX: defaultBinX ?? profile.defaultBinX,
        defaultBinY: defaultBinY ?? profile.defaultBinY,
        defaultCoolingTemp: defaultCoolingTemp ?? profile.defaultCoolingTemp,
      ),
    );
  }

  /// Save all currently connected devices to the active profile
  ///
  /// Reads current device states and updates the active profile with
  /// all connected device IDs. Returns true if saved successfully.
  Future<bool> saveConnectedDevicesToProfile() async {
    final activeModel = await _getActiveProfileModel();

    if (activeModel == null) {
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
    final switchState = _ref.read(switchStateProvider);
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
    String? switchId;
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
    if (switchState.connectionState == DeviceConnectionState.connected) {
      switchId = switchState.deviceId;
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
        switchId != null ||
        coverCalibratorId != null;

    if (!hasConnectedDevices) {
      developer.log('ProfileService: No connected devices to save',
          name: 'ProfileService', level: 800);
      return false;
    }

    await _persistProfileModel(
      activeModel.copyWith(
        cameraId: cameraId ?? activeModel.cameraId,
        mountId: mountId ?? activeModel.mountId,
        focuserId: focuserId ?? activeModel.focuserId,
        filterWheelId: filterWheelId ?? activeModel.filterWheelId,
        guiderId: guiderId ?? activeModel.guiderId,
        rotatorId: rotatorId ?? activeModel.rotatorId,
        domeId: domeId ?? activeModel.domeId,
        weatherId: weatherId ?? activeModel.weatherId,
        safetyMonitorId: safetyMonitorId ?? activeModel.safetyMonitorId,
        switchId: switchId ?? activeModel.switchId,
        coverCalibratorId: coverCalibratorId ?? activeModel.coverCalibratorId,
      ),
    );

    developer.log(
        'ProfileService: Saved connected devices to profile "${activeModel.name}"',
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
    final profile = await _getProfileModelById(profileId);
    if (profile == null) {
      throw Exception('Profile not found');
    }

    await _persistProfileModel(
      profile.copyWith(
        filterNames: filterNames ?? profile.filterNames,
        filterFocusOffsets: filterFocusOffsets ?? profile.filterFocusOffsets,
      ),
    );
  }

  /// Sync filter names from connected filter wheel to the active profile
  /// Returns true if filters were synced, false otherwise
  Future<bool> syncFiltersFromHardware() async {
    final activeProfile = await _getActiveProfileModel();

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

    final existingOffsets = Map<String, int>.from(activeProfile.filterFocusOffsets);

    // Build new offsets map, preserving existing offsets for matching filter names
    final newOffsets = <String, int>{};
    for (final filterName in hwFilterNames) {
      newOffsets[filterName] = existingOffsets[filterName] ?? 0;
    }

    await _persistProfileModel(
      activeProfile.copyWith(
        filterNames: hwFilterNames,
        filterFocusOffsets: newOffsets,
      ),
    );

    developer.log(
        'ProfileService: Synced ${hwFilterNames.length} filters to profile "${activeProfile.name}"',
        name: 'ProfileService',
        level: 800);
    return true;
  }

  /// Sync filter names from connected filter wheel to a specific profile
  Future<bool> syncFiltersToProfile(int profileId) async {
    final profile = await _getProfileModelById(profileId);
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

    final existingOffsets = Map<String, int>.from(profile.filterFocusOffsets);
    final newOffsets = <String, int>{};
    for (final filterName in hwFilterNames) {
      newOffsets[filterName] = existingOffsets[filterName] ?? 0;
    }

    await _persistProfileModel(
      profile.copyWith(
        filterNames: hwFilterNames,
        filterFocusOffsets: newOffsets,
      ),
    );

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
        developer.log(
            'ProfileService: Failed to parse filterFocusOffsets: $e',
            name: 'ProfileService',
            level: 1000,
            error: e);
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
      filterNames:
          profile.filterNames.isNotEmpty ? profile.filterNames : null,
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

/// Provider for the profile service
final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService(ref);
});
