import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/nightshade_backend.dart';
import '../backend/network_backend.dart';
import '../database/database.dart';
import '../models/equipment/equipment_models.dart';
import '../models/equipment_profile.dart' as remote_profile;
import '../models/equipment_profile_validation.dart';
import '../providers/backend_provider.dart';
import '../providers/database_provider.dart';
import '../providers/equipment_provider.dart';
import '../providers/profiles_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/unified_discovery_provider.dart';
import '../utils/json_validation.dart';
import 'device_exceptions.dart';
import 'device_service.dart';
import 'optical_train_limits.dart';

part 'profile_service/profile_export_data.dart';

typedef _BackendAuthority = ({
  BackendNotifier owner,
  NightshadeBackend backend,
});

/// Raised when startup auto-connect finishes activating a profile but one or
/// more of its devices failed to connect. Startup deliberately attempts EVERY
/// configured device (a single offline focuser must not strand the mount and
/// camera) and then aggregates the failures here so the wiring layer can log
/// loudly / surface a non-blocking notification. The profile is already active
/// by the time this throws.
class ProfileAutoConnectException implements Exception {
  final String profileName;
  final List<String> failures;

  const ProfileAutoConnectException({
    required this.profileName,
    required this.failures,
  });

  @override
  String toString() =>
      'ProfileAutoConnectException: ${failures.length} device(s) failed to '
      'connect for profile "$profileName": ${failures.join('; ')}';
}

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
  const ProfileValidationResult.valid({required this.availableDevices})
    : isValid = true,
      missingDevices = const [],
      missingDeviceIds = const {};
}

/// Service for managing equipment profiles with auto-connect and import/export
class ProfileService {
  final Ref _ref;

  ProfileService(this._ref);

  _BackendAuthority get _authority {
    final owner = _ref.read(backendProvider.notifier);
    return (owner: owner, backend: owner.currentBackend);
  }

  void _requireAuthority(_BackendAuthority authority) {
    if (!authority.owner.isCurrentBackend(authority.backend)) {
      throw StateError(
        'The imaging host changed while the profile operation was running.',
      );
    }
  }

  EquipmentProfilesNotifier get _profilesNotifier =>
      _ref.read(equipmentProfilesProvider.notifier);

  Future<EquipmentProfileModel?> _getProfileModelById(
    int profileId, {
    _BackendAuthority? authority,
  }) async {
    final operation = authority ?? _authority;
    final backend = operation.backend;
    if (backend is NetworkBackend) {
      final profiles = await backend.getProfiles();
      _requireAuthority(operation);
      for (final profile in profiles) {
        if (int.tryParse(profile.id) == profileId) {
          return EquipmentProfileModel.fromRemoteProfile(profile);
        }
      }
      return null;
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile = await dao.getProfileById(profileId);
    _requireAuthority(operation);
    return profile != null ? EquipmentProfileModel.fromDatabase(profile) : null;
  }

  Future<EquipmentProfileModel?> _getActiveProfileModel({
    _BackendAuthority? authority,
  }) async {
    final operation = authority ?? _authority;
    final backend = operation.backend;
    if (backend is NetworkBackend) {
      final active = await backend.getActiveProfile();
      _requireAuthority(operation);
      return active != null
          ? EquipmentProfileModel.fromRemoteProfile(active)
          : null;
    }

    final cached = _ref.read(activeEquipmentProfileProvider);
    if (cached != null) {
      _requireAuthority(operation);
      return cached;
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile = await dao.getActiveProfile();
    _requireAuthority(operation);
    return profile != null ? EquipmentProfileModel.fromDatabase(profile) : null;
  }

  Future<EquipmentProfileModel?> _getStartupProfileModel({
    _BackendAuthority? authority,
  }) async {
    final operation = authority ?? _authority;
    final backend = operation.backend;
    if (backend is NetworkBackend) {
      final profiles = await backend.getProfiles();
      _requireAuthority(operation);
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
      if (chosen != null) {
        return EquipmentProfileModel.fromRemoteProfile(chosen);
      }
      // Older hosts may omit isActive from list rows while still exposing the
      // authoritative active row on the dedicated endpoint. Never fall back
      // to a cached profile from the previous host.
      final active = await backend.getActiveProfile();
      _requireAuthority(operation);
      return active == null
          ? null
          : EquipmentProfileModel.fromRemoteProfile(active);
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    final profile =
        await dao.getDefaultProfile() ?? await dao.getActiveProfile();
    _requireAuthority(operation);
    return profile != null ? EquipmentProfileModel.fromDatabase(profile) : null;
  }

  Future<void> _persistProfileModel(
    EquipmentProfileModel profile, {
    _BackendAuthority? authority,
  }) async {
    final operation = authority ?? _authority;
    _requireAuthority(operation);
    final backend = operation.backend;
    if (backend is NetworkBackend) {
      await backend.saveProfile(profile.toRemoteProfile());
      _requireAuthority(operation);
      _ref.invalidate(equipmentProfilesProvider);
      return;
    }

    if (profile.id == null) {
      throw StateError('Cannot persist profile without id on local backend');
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    final existing = await dao.getProfileById(profile.id!);
    _requireAuthority(operation);
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
    _requireAuthority(operation);
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
    final authority = _authority;
    final profile = await _getProfileModelById(profileId, authority: authority);

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
    final authority = _authority;
    final backend = authority.backend;
    if (backend is NetworkBackend) {
      await backend.loadProfile(profileId.toString());
      _requireAuthority(authority);
      _ref.invalidate(equipmentProfilesProvider);
      if (autoConnect) {
        final profile = await _getProfileModelById(
          profileId,
          authority: authority,
        );
        if (profile != null) {
          await _connectProfileDevicesFromModel(profile);
          _requireAuthority(authority);
        }
      }
      return;
    }

    // Route activation through the single, remote-aware notifier authority so
    // the local path updates SQLite AND write-throughs the active row into the
    // native executor store (rather than a bare DAO write that the Rust
    // sequencer never sees). The notifier refreshes provider state itself.
    await _profilesNotifier.setActiveProfile(profileId);
    _requireAuthority(authority);

    if (autoConnect) {
      final dao = _ref.read(equipmentProfilesDaoProvider);
      final profile = await dao.getProfileById(profileId);
      _requireAuthority(authority);
      if (profile != null) {
        await _connectProfileDevicesFromModel(
          EquipmentProfileModel.fromDatabase(profile),
        );
        _requireAuthority(authority);
      }
    }
  }

  /// Set or clear the default startup profile.
  ///
  /// Delegates to the single [EquipmentProfilesNotifier] authority for both
  /// remote (host endpoint) and local (SQLite + native write-through when
  /// makeActive flips the active profile) so this service never becomes a
  /// second, unsynchronized activation writer.
  Future<void> setDefaultProfile(
    int? profileId, {
    bool makeActive = true,
  }) async {
    await _profilesNotifier.setDefaultProfile(
      profileId,
      makeActive: makeActive,
    );
  }

  /// Connect devices from a profile model (local FFI or remote host).
  ///
  /// Reuses the canonical [DeviceService.connectAllFromProfile] progress path:
  /// every configured device is dispatched (in parallel) and each device
  /// reports its own outcome, so one offline device can no longer abort the
  /// sweep and silently strand the rest — the historical bug where the loop
  /// stopped on the first device error. Per-device failures are aggregated and,
  /// if any occurred, surfaced as a [ProfileAutoConnectException] so the caller
  /// can log/notify rather than pretend everything connected.
  Future<void> _connectProfileDevicesFromModel(
    EquipmentProfileModel profile,
  ) async {
    final deviceService = _ref.read(deviceServiceProvider);
    final failures = <String>[];

    await for (final progress in deviceService.connectAllFromProfile(profile)) {
      if (progress.status == DeviceConnectProgressStatus.failed) {
        failures.add(
          '${progress.deviceType} (${progress.deviceId}): '
          '${progress.errorMessage ?? progress.error ?? 'unknown error'}',
        );
      }
    }

    if (failures.isNotEmpty) {
      throw ProfileAutoConnectException(
        profileName: profile.name,
        failures: failures,
      );
    }
  }

  /// Auto-connect to the startup profile's devices on startup.
  ///
  /// Contract:
  ///   1. No-op when the Auto-connect setting is off or there is no startup
  ///      profile (fresh install / no profiles) — never activates, never
  ///      connects.
  ///   2. Startup profile selection = default profile first, current active
  ///      profile as the fallback when no default is set.
  ///   3. The selected startup profile is ACTIVATED through the single
  ///      [EquipmentProfilesNotifier] authority BEFORE any device connect
  ///      (local: SQLite flip + strict native save/load once; remote: host load
  ///      endpoint once, no slave-local write). Startup intentionally makes the
  ///      selected startup profile active — so with profile A as default but B
  ///      currently active, A becomes active (B inactive) while A stays default.
  ///   4. If activation fails, NOTHING is connected and the error propagates.
  ///   5. Only then are that same profile's device ids connected, attempting
  ///      every device and aggregating failures (see
  ///      [_connectProfileDevicesFromModel]).
  ///
  /// This method connects hardware, so the production wiring only invokes it on
  /// the LOCAL hardware-owning master (desktop FfiBackend GUI / headless
  /// daemon). A passive remote/mobile slave launch must never call it; a remote
  /// client may still invoke it explicitly, in which case it drives the host via
  /// the host load endpoint + host-side device connects.
  Future<void> autoConnectOnStartup() async {
    final authority = _authority;
    final autoConnect = await _ref.read(autoConnectSettingsProvider.future);
    _requireAuthority(authority);
    if (!autoConnect) return;

    final startupProfile = await _getStartupProfileModel(authority: authority);
    final profileId = startupProfile?.id;
    if (startupProfile == null || profileId == null) return;

    // Activate/load the selected startup profile FIRST, through the single
    // notifier authority, with a strict native write-through. A failure here
    // (activation, or the native store never learning about the profile) throws
    // before any connect, satisfying "activation failure -> connect nothing".
    await _profilesNotifier.setActiveProfileStrict(profileId);
    _requireAuthority(authority);

    // The profile is now active; connect its devices (attempt-all + aggregate).
    await _connectProfileDevicesFromModel(startupProfile);
    _requireAuthority(authority);
  }

  // ===========================================================================
  // Profile Import/Export
  // ===========================================================================

  /// Export a profile to JSON
  Future<String> exportProfileToJson(int profileId) async {
    final authority = _authority;
    final profile = await _getProfileModelById(profileId, authority: authority);

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
    final authority = _authority;
    final backend = authority.backend;
    final List<ProfileExportData> exportData;
    if (backend is NetworkBackend) {
      final profiles = await backend.getProfiles();
      _requireAuthority(authority);
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
      _requireAuthority(authority);
      exportData = profiles
          .map((p) => ProfileExportData.fromDatabase(p))
          .toList();
    }

    final exportJson = exportData.map((p) => p.toJson()).toList();
    return jsonEncode({
      'version': 2,
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
    final authority = _authority;
    final data = jsonDecode(json);

    // Handle single profile export
    final Object? profileData;
    if (data is Map && data.containsKey('profiles')) {
      final profiles = data['profiles'];
      if (profiles is! List || profiles.isEmpty) {
        throw const FormatException(
          'Profile export must contain at least one profile',
        );
      }
      profileData = profiles.first;
    } else {
      profileData = data;
    }
    if (profileData is! Map<String, dynamic>) {
      throw const FormatException('Profile entry must be a JSON object');
    }

    final exportData = ProfileExportData.fromJson(profileData);
    return await _createProfileFromExport(exportData, authority: authority);
  }

  /// Import a profile from a file
  Future<int> importProfileFromFile(String filePath) async {
    final file = File(filePath);
    final json = await file.readAsString();
    return await importProfileFromJson(json);
  }

  /// Import all profiles from JSON (batch import)
  Future<List<int>> importAllProfilesFromJson(String json) async {
    final authority = _authority;
    final data = jsonDecode(json);

    List<dynamic> profilesData;
    if (data is Map && data.containsKey('profiles')) {
      final profiles = data['profiles'];
      if (profiles is! List) {
        throw const FormatException('"profiles" must be a JSON array');
      }
      profilesData = profiles;
    } else if (data is List) {
      profilesData = data;
    } else {
      // Single profile
      profilesData = [data];
    }

    if (profilesData.isEmpty) {
      throw const FormatException(
        'Profile export must contain at least one profile',
      );
    }

    // Parse and validate the entire document before persisting the first row.
    // A malformed later entry must not leave a misleading partial import.
    final parsedProfiles = profilesData
        .map((profileJson) {
          if (profileJson is! Map<String, dynamic>) {
            throw const FormatException('Each profile must be a JSON object');
          }
          return ProfileExportData.fromJson(profileJson);
        })
        .toList(growable: false);

    final ids = <int>[];
    for (final exportData in parsedProfiles) {
      final id = await _createProfileFromExport(
        exportData,
        authority: authority,
      );
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
  Future<int> _createProfileFromExport(
    ProfileExportData data, {
    required _BackendAuthority authority,
  }) async {
    _requireAuthority(authority);
    final backend = authority.backend;
    if (backend is NetworkBackend) {
      final existingProfiles = await backend.getProfiles();
      _requireAuthority(authority);
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
        cameraName: data.cameraName,
        mountName: data.mountName,
        focuserName: data.focuserName,
        filterWheelName: data.filterWheelName,
        guiderName: data.guiderName,
        rotatorName: data.rotatorName,
        safetyMonitorName: data.safetyMonitorName,
        switchName: data.switchName,
        telescopeName: data.telescopeName,
        telescopeFocalLength: data.telescopeFocalLength,
        telescopeAperture: data.telescopeAperture,
        focalLength: data.focalLength,
        aperture: data.aperture,
        focalRatio: data.focalRatio,
        defaultGain: data.defaultGain,
        defaultOffset: data.defaultOffset,
        defaultBinX: data.defaultBinX,
        defaultBinY: data.defaultBinY,
        defaultCoolingTemp: data.defaultCoolingTemp,
        coolOnConnect: data.coolOnConnect,
        defaultCenteringExposure: data.defaultCenteringExposure,
        filterNames: data.filterNames ?? const [],
        filterFocusOffsets: data.filterFocusOffsets ?? const {},
        meridianFlipOverrides: data.meridianFlipOverrides,
        profileIcon: data.profileIcon,
        profileColor: data.profileColor,
      );
      await backend.saveProfile(model.toRemoteProfile());
      _requireAuthority(authority);
      _ref.invalidate(equipmentProfilesProvider);
      final savedId = int.tryParse(backend.lastSavedProfileId ?? '');
      if (savedId != null && savedId > 0) {
        return savedId;
      }
      final refreshed = await backend.getProfiles();
      _requireAuthority(authority);
      for (final profile in refreshed) {
        if (profile.name == name) {
          final id = int.tryParse(profile.id);
          if (id != null) {
            return id;
          }
        }
      }
      throw StateError(
        'Host saved imported profile "$name" but id was not resolved',
      );
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);

    // Check for name conflicts and rename if needed
    final existingProfiles = await dao.getAllProfiles();
    _requireAuthority(authority);
    var name = data.name;
    var suffix = 1;
    while (existingProfiles.any((p) => p.name == name)) {
      name = '${data.name} ($suffix)';
      suffix++;
    }

    final id = await dao.createProfile(
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
        cameraName: Value(data.cameraName),
        mountName: Value(data.mountName),
        focuserName: Value(data.focuserName),
        filterWheelName: Value(data.filterWheelName),
        guiderName: Value(data.guiderName),
        rotatorName: Value(data.rotatorName),
        safetyMonitorName: Value(data.safetyMonitorName),
        switchName: Value(data.switchName),
        telescopeName: Value(data.telescopeName),
        telescopeFocalLength: Value(data.telescopeFocalLength),
        telescopeAperture: Value(data.telescopeAperture),
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
          data.filterNames != null ? jsonEncode(data.filterNames) : null,
        ),
        filterFocusOffsets: Value(
          data.filterFocusOffsets != null
              ? jsonEncode(data.filterFocusOffsets)
              : null,
        ),
        meridianFlipOverrides: Value(data.meridianFlipOverrides),
        profileIcon: Value(data.profileIcon),
        profileColor: Value(data.profileColor),
      ),
    );
    _requireAuthority(authority);
    return id;
  }

  // ===========================================================================
  // Profile Management
  // ===========================================================================

  /// Create a new empty profile
  Future<int> createProfile(String name, {String? description}) async {
    final authority = _authority;
    if (authority.backend is NetworkBackend) {
      final id = await _profilesNotifier.createProfile(
        name: name,
        description: description,
      );
      _requireAuthority(authority);
      return id;
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    final id = await dao.createProfile(
      EquipmentProfilesCompanion.insert(
        name: name,
        description: Value(description),
      ),
    );
    _requireAuthority(authority);
    _ref.invalidate(equipmentProfilesProvider);
    return id;
  }

  /// Duplicate an existing profile
  Future<int> duplicateProfile(int sourceId, String newName) async {
    final authority = _authority;
    if (authority.backend is NetworkBackend) {
      final id = await _profilesNotifier.duplicateProfile(sourceId, newName);
      _requireAuthority(authority);
      return id;
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    final id = await dao.duplicateProfile(sourceId, newName);
    _requireAuthority(authority);
    _ref.invalidate(equipmentProfilesProvider);
    return id;
  }

  /// Delete a profile
  Future<void> deleteProfile(int profileId) async {
    final authority = _authority;
    if (authority.backend is NetworkBackend) {
      await _profilesNotifier.deleteProfile(profileId);
      _requireAuthority(authority);
      return;
    }

    final dao = _ref.read(equipmentProfilesDaoProvider);
    await dao.deleteProfile(profileId);
    _requireAuthority(authority);
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
    final authority = _authority;
    final profile = await _getProfileModelById(profileId, authority: authority);
    if (profile == null) {
      throw Exception('Profile not found');
    }

    await _persistProfileModel(
      profile.copyWith(
        cameraId: deviceTypes.contains('Camera') ? null : profile.cameraId,
        mountId: deviceTypes.contains('Mount') ? null : profile.mountId,
        focuserId: deviceTypes.contains('Focuser') ? null : profile.focuserId,
        filterWheelId: deviceTypes.contains('Filter Wheel')
            ? null
            : profile.filterWheelId,
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
      authority: authority,
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
    final authority = _authority;
    final profile = await _getProfileModelById(profileId, authority: authority);
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
      authority: authority,
    );
  }

  /// Update profile optical configuration
  Future<void> updateProfileOptics(
    int profileId, {
    double? focalLength,
    double? aperture,
    double? focalRatio,
  }) async {
    final authority = _authority;
    final profile = await _getProfileModelById(profileId, authority: authority);
    if (profile == null) {
      throw Exception('Profile not found');
    }

    await _persistProfileModel(
      profile.copyWith(
        focalLength: focalLength ?? profile.focalLength,
        aperture: aperture ?? profile.aperture,
        focalRatio: focalRatio ?? profile.focalRatio,
      ),
      authority: authority,
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
    final authority = _authority;
    final profile = await _getProfileModelById(profileId, authority: authority);
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
      authority: authority,
    );
  }

  /// Save all currently connected devices to the active profile
  ///
  /// Reads current device states and updates the active profile with
  /// all connected device IDs. Returns true if saved successfully.
  Future<bool> saveConnectedDevicesToProfile() async {
    final authority = _authority;
    final activeModel = await _getActiveProfileModel(authority: authority);

    if (activeModel == null) {
      developer.log(
        'ProfileService: No active profile to save devices to',
        name: 'ProfileService',
        level: 900,
      );
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
    final hasConnectedDevices =
        cameraId != null ||
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
      developer.log(
        'ProfileService: No connected devices to save',
        name: 'ProfileService',
        level: 800,
      );
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
      authority: authority,
    );

    developer.log(
      'ProfileService: Saved connected devices to profile "${activeModel.name}"',
      name: 'ProfileService',
      level: 800,
    );
    return true;
  }

  /// Update profile filter configuration
  Future<void> updateProfileFilters(
    int profileId, {
    List<String>? filterNames,
    Map<String, int>? filterFocusOffsets,
  }) async {
    final authority = _authority;
    final profile = await _getProfileModelById(profileId, authority: authority);
    if (profile == null) {
      throw Exception('Profile not found');
    }

    await _persistProfileModel(
      profile.copyWith(
        filterNames: filterNames ?? profile.filterNames,
        filterFocusOffsets: filterFocusOffsets ?? profile.filterFocusOffsets,
      ),
      authority: authority,
    );
  }

  /// Sync filter names from connected filter wheel to the active profile
  /// Returns true if filters were synced, false otherwise
  Future<bool> syncFiltersFromHardware() async {
    final authority = _authority;
    final activeProfile = await _getActiveProfileModel(authority: authority);

    if (activeProfile == null) {
      developer.log(
        'ProfileService: No active profile to sync filters to',
        name: 'ProfileService',
        level: 900,
      );
      return false;
    }

    // Import the equipment provider to access filter wheel state
    final filterWheelState = _ref.read(filterWheelStateProvider);

    if (filterWheelState.connectionState != DeviceConnectionState.connected) {
      developer.log(
        'ProfileService: Filter wheel not connected',
        name: 'ProfileService',
        level: 900,
      );
      return false;
    }

    final hwFilterNames = filterWheelState.filterNames;
    if (hwFilterNames.isEmpty) {
      developer.log(
        'ProfileService: No filter names from hardware',
        name: 'ProfileService',
        level: 900,
      );
      return false;
    }

    final existingOffsets = Map<String, int>.from(
      activeProfile.filterFocusOffsets,
    );

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
      authority: authority,
    );

    developer.log(
      'ProfileService: Synced ${hwFilterNames.length} filters to profile "${activeProfile.name}"',
      name: 'ProfileService',
      level: 800,
    );
    return true;
  }

  /// Sync filter names from connected filter wheel to a specific profile
  Future<bool> syncFiltersToProfile(int profileId) async {
    final authority = _authority;
    final profile = await _getProfileModelById(profileId, authority: authority);
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
      authority: authority,
    );

    return true;
  }
}

/// Provider for the profile service
final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService(ref);
});
