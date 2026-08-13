import 'package:drift/drift.dart';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import '../backend/network_backend.dart';
import '../database/database.dart';
import '../models/backend/device_capabilities.dart';
import '../models/equipment/equipment_models.dart' show DeviceConnectionState;
import '../models/equipment_profile.dart' as remote_profile;
import '../models/optical_config.dart';
import '../utils/json_validation.dart';
import 'backend_provider.dart';
import 'capability_provider.dart';
import 'database_provider.dart';
import 'equipment_provider.dart';
import 'profile_activation_writethrough.dart';
import '../services/logging_service.dart';
import '../services/profile_service.dart';
import '../services/optical_train_limits.dart';

final _log = Logger('ProfilesProvider');

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
  final String? safetyMonitorId;
  final String? switchId;
  final String? coverCalibratorId;

  // User-friendly device names (can be auto-generated or custom)
  final String? cameraName;
  final String? mountName;
  final String? focuserName;
  final String? filterWheelName;
  final String? guiderName;
  final String? rotatorName;
  final String? safetyMonitorName;
  final String? switchName;

  // Telescope/OTA information
  final String? telescopeName;
  final double? telescopeFocalLength;
  final double? telescopeAperture;

  // Optical setup (profile-level, may differ from telescope if using reducers/barlows)
  final double focalLength;
  final double aperture;
  final double? focalRatio;

  // Camera defaults
  final int? defaultGain;
  final int? defaultOffset;
  final int defaultBinX;
  final int defaultBinY;
  final double? defaultCoolingTemp;
  final bool coolOnConnect;

  // Centering/plate-solve default exposure (seconds)
  final double? defaultCenteringExposure;

  // Filter configuration
  final List<String> filterNames;
  final Map<String, int> filterFocusOffsets;

  // Meridian flip settings overrides (raw JSON; null = use global defaults)
  final String? meridianFlipOverrides;

  // Profile customization
  final String? profileIcon;
  final int? profileColor;
  final int sortOrder;
  final bool isDefault;

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
    this.focalLength = 0.0,
    this.aperture = 0.0,
    this.focalRatio,
    this.defaultGain,
    this.defaultOffset,
    this.defaultBinX = 1,
    this.defaultBinY = 1,
    this.defaultCoolingTemp,
    this.coolOnConnect = false,
    this.defaultCenteringExposure,
    this.filterNames = const [],
    this.filterFocusOffsets = const {},
    this.meridianFlipOverrides,
    this.profileIcon,
    this.profileColor,
    this.sortOrder = 0,
    this.isDefault = false,
    this.createdAt,
    this.updatedAt,
  });

  /// Returns telescope name + camera name as subtitle, or fallback
  String get subtitle {
    if (telescopeName != null && cameraName != null) {
      return '$telescopeName + $cameraName';
    }
    if (cameraName != null) return cameraName!;
    if (mountName != null) return mountName!;
    return '$deviceCount devices';
  }

  /// Count of assigned devices (non-null device IDs)
  int get deviceCount {
    int count = 0;
    if (cameraId != null) count++;
    if (mountId != null) count++;
    if (focuserId != null) count++;
    if (filterWheelId != null) count++;
    if (guiderId != null) count++;
    if (rotatorId != null) count++;
    if (domeId != null) count++;
    if (weatherId != null) count++;
    if (safetyMonitorId != null) count++;
    if (switchId != null) count++;
    if (coverCalibratorId != null) count++;
    return count;
  }

  /// Create from database entity
  factory EquipmentProfileModel.fromDatabase(EquipmentProfile db) {
    List<String> filters = [];
    Map<String, int> offsets = {};
    final rawTelescopeFocalLength = db.telescopeFocalLength;
    final rawTelescopeAperture = db.telescopeAperture;
    final telescopeFocalLength =
        rawTelescopeFocalLength != null && rawTelescopeFocalLength > 0
        ? rawTelescopeFocalLength
        : null;
    final telescopeAperture =
        rawTelescopeAperture != null && rawTelescopeAperture > 0
        ? rawTelescopeAperture
        : null;
    final effectiveFocalLength = db.focalLength > 0
        ? db.focalLength
        : (telescopeFocalLength ?? 0.0);
    final effectiveAperture = db.aperture > 0
        ? db.aperture
        : (telescopeAperture ?? 0.0);

    if (db.filterNames != null) {
      try {
        filters = decodeStringListJson(
          db.filterNames,
          context: 'equipment_profiles.filter_names for "${db.name}"',
        );
      } catch (e) {
        _log.warning(
          'Failed to parse filterNames JSON for profile "${db.name}": $e',
        );
      }
    }

    if (db.filterFocusOffsets != null) {
      try {
        offsets = decodeStringIntMapJson(
          db.filterFocusOffsets,
          context: 'equipment_profiles.filter_focus_offsets for "${db.name}"',
        );
      } catch (e) {
        _log.warning(
          'Failed to parse filterFocusOffsets JSON for profile "${db.name}": $e',
        );
      }
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
      safetyMonitorId: db.safetyMonitorId,
      switchId: db.switchId,
      coverCalibratorId: db.coverCalibratorId,
      cameraName: db.cameraName,
      mountName: db.mountName,
      focuserName: db.focuserName,
      filterWheelName: db.filterWheelName,
      guiderName: db.guiderName,
      rotatorName: db.rotatorName,
      safetyMonitorName: db.safetyMonitorName,
      switchName: db.switchName,
      telescopeName: db.telescopeName,
      telescopeFocalLength: telescopeFocalLength,
      telescopeAperture: telescopeAperture,
      focalLength: effectiveFocalLength,
      aperture: effectiveAperture,
      focalRatio: db.focalRatio,
      defaultGain: db.defaultGain,
      defaultOffset: db.defaultOffset,
      defaultBinX: db.defaultBinX,
      defaultBinY: db.defaultBinY,
      defaultCoolingTemp: db.defaultCoolingTemp,
      coolOnConnect: db.coolOnConnect,
      defaultCenteringExposure: db.defaultCenteringExposure,
      filterNames: filters,
      filterFocusOffsets: offsets,
      meridianFlipOverrides: db.meridianFlipOverrides,
      profileIcon: db.profileIcon,
      profileColor: db.profileColor,
      sortOrder: db.sortOrder,
      isDefault: db.isDefault,
      createdAt: db.createdAt,
      updatedAt: db.updatedAt,
    );
  }

  /// Create from the host's REST `/api/profiles` payload when running as a
  /// remote companion (NetworkBackend).
  factory EquipmentProfileModel.fromRemoteProfile(
    remote_profile.EquipmentProfile profile,
  ) {
    List<String> filters = [];
    Map<String, int> offsets = {};

    if (profile.filterNames != null && profile.filterNames!.isNotEmpty) {
      try {
        filters = decodeStringListJson(
          profile.filterNames,
          context: 'remote profile "${profile.name}" filterNames',
        );
      } catch (e) {
        _log.warning(
          'Failed to parse remote filterNames for "${profile.name}": $e',
        );
      }
    }

    if (profile.filterFocusOffsets != null &&
        profile.filterFocusOffsets!.isNotEmpty) {
      try {
        offsets = decodeStringIntMapJson(
          profile.filterFocusOffsets,
          context: 'remote profile "${profile.name}" filterFocusOffsets',
        );
      } catch (e) {
        _log.warning(
          'Failed to parse remote filterFocusOffsets for "${profile.name}": $e',
        );
      }
    }

    final remoteId = int.tryParse(profile.id);

    return EquipmentProfileModel(
      id: remoteId,
      name: profile.name,
      description: profile.description,
      isActive: profile.isActive,
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
      telescopeFocalLength: profile.telescopeFocalLength > 0
          ? profile.telescopeFocalLength
          : null,
      telescopeAperture: profile.telescopeAperture > 0
          ? profile.telescopeAperture
          : null,
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
      filterNames: filters,
      filterFocusOffsets: offsets,
      meridianFlipOverrides: profile.meridianFlipOverrides,
      profileIcon: profile.profileIcon,
      profileColor: profile.profileColor,
      sortOrder: profile.sortOrder,
      isDefault: profile.isDefault,
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt,
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
      safetyMonitorId: Value(safetyMonitorId),
      switchId: Value(switchId),
      coverCalibratorId: Value(coverCalibratorId),
      cameraName: Value(cameraName),
      mountName: Value(mountName),
      focuserName: Value(focuserName),
      filterWheelName: Value(filterWheelName),
      guiderName: Value(guiderName),
      rotatorName: Value(rotatorName),
      safetyMonitorName: Value(safetyMonitorName),
      switchName: Value(switchName),
      telescopeName: Value(telescopeName),
      telescopeFocalLength: Value(telescopeFocalLength),
      telescopeAperture: Value(telescopeAperture),
      focalLength: Value(focalLength),
      aperture: Value(aperture),
      focalRatio: Value(focalRatio),
      defaultGain: Value(defaultGain),
      defaultOffset: Value(defaultOffset),
      defaultBinX: Value(defaultBinX),
      defaultBinY: Value(defaultBinY),
      defaultCoolingTemp: Value(defaultCoolingTemp),
      coolOnConnect: Value(coolOnConnect),
      defaultCenteringExposure: Value(defaultCenteringExposure),
      filterNames: Value(
        filterNames.isNotEmpty ? jsonEncode(filterNames) : null,
      ),
      filterFocusOffsets: Value(
        filterFocusOffsets.isNotEmpty ? jsonEncode(filterFocusOffsets) : null,
      ),
      meridianFlipOverrides: Value(meridianFlipOverrides),
      profileIcon: Value(profileIcon),
      profileColor: Value(profileColor),
      sortOrder: Value(sortOrder),
      isDefault: Value(isDefault),
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
    String? safetyMonitorId,
    String? switchId,
    String? coverCalibratorId,
    String? cameraName,
    String? mountName,
    String? focuserName,
    String? filterWheelName,
    String? guiderName,
    String? rotatorName,
    String? safetyMonitorName,
    String? switchName,
    String? telescopeName,
    double? telescopeFocalLength,
    double? telescopeAperture,
    double? focalLength,
    double? aperture,
    double? focalRatio,
    int? defaultGain,
    int? defaultOffset,
    int? defaultBinX,
    int? defaultBinY,
    double? defaultCoolingTemp,
    bool? coolOnConnect,
    double? defaultCenteringExposure,
    List<String>? filterNames,
    Map<String, int>? filterFocusOffsets,
    String? meridianFlipOverrides,
    String? profileIcon,
    int? profileColor,
    int? sortOrder,
    bool? isDefault,
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
      safetyMonitorId: safetyMonitorId ?? this.safetyMonitorId,
      switchId: switchId ?? this.switchId,
      coverCalibratorId: coverCalibratorId ?? this.coverCalibratorId,
      cameraName: cameraName ?? this.cameraName,
      mountName: mountName ?? this.mountName,
      focuserName: focuserName ?? this.focuserName,
      filterWheelName: filterWheelName ?? this.filterWheelName,
      guiderName: guiderName ?? this.guiderName,
      rotatorName: rotatorName ?? this.rotatorName,
      safetyMonitorName: safetyMonitorName ?? this.safetyMonitorName,
      switchName: switchName ?? this.switchName,
      telescopeName: telescopeName ?? this.telescopeName,
      telescopeFocalLength: telescopeFocalLength ?? this.telescopeFocalLength,
      telescopeAperture: telescopeAperture ?? this.telescopeAperture,
      focalLength: focalLength ?? this.focalLength,
      aperture: aperture ?? this.aperture,
      focalRatio: focalRatio ?? this.focalRatio,
      defaultGain: defaultGain ?? this.defaultGain,
      defaultOffset: defaultOffset ?? this.defaultOffset,
      defaultBinX: defaultBinX ?? this.defaultBinX,
      defaultBinY: defaultBinY ?? this.defaultBinY,
      defaultCoolingTemp: defaultCoolingTemp ?? this.defaultCoolingTemp,
      coolOnConnect: coolOnConnect ?? this.coolOnConnect,
      defaultCenteringExposure:
          defaultCenteringExposure ?? this.defaultCenteringExposure,
      filterNames: filterNames ?? this.filterNames,
      filterFocusOffsets: filterFocusOffsets ?? this.filterFocusOffsets,
      meridianFlipOverrides:
          meridianFlipOverrides ?? this.meridianFlipOverrides,
      profileIcon: profileIcon ?? this.profileIcon,
      profileColor: profileColor ?? this.profileColor,
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Build a fresh INSERTION copy of this profile: no id, inert
  /// active/default flags, fresh timestamps, and the supplied [name]. Every
  /// other device id/name, optical, camera-default, filter, meridian-flip and
  /// customization field is preserved verbatim.
  ///
  /// Why not `copyWith`: `copyWith`'s nullable `id ?? this.id` semantics CANNOT
  /// clear the id — `copyWith(id: null)` silently keeps the source id, which on
  /// the remote path makes the host UPDATE (rename) the source instead of
  /// creating a copy, and it also retains `isDefault`. This constructs a genuine
  /// create with `id == null` (so `toRemoteProfile()` emits an empty id the host
  /// treats as a create) and `isActive == false` / `isDefault == false`.
  EquipmentProfileModel toInsertionCopy({required String name}) {
    return EquipmentProfileModel(
      // id intentionally omitted -> null -> host/DAO treats this as a CREATE.
      name: name,
      description: description,
      isActive: false,
      isDefault: false,
      cameraId: cameraId,
      mountId: mountId,
      focuserId: focuserId,
      filterWheelId: filterWheelId,
      guiderId: guiderId,
      rotatorId: rotatorId,
      domeId: domeId,
      weatherId: weatherId,
      safetyMonitorId: safetyMonitorId,
      switchId: switchId,
      coverCalibratorId: coverCalibratorId,
      cameraName: cameraName,
      mountName: mountName,
      focuserName: focuserName,
      filterWheelName: filterWheelName,
      guiderName: guiderName,
      rotatorName: rotatorName,
      safetyMonitorName: safetyMonitorName,
      switchName: switchName,
      telescopeName: telescopeName,
      telescopeFocalLength: telescopeFocalLength,
      telescopeAperture: telescopeAperture,
      focalLength: focalLength,
      aperture: aperture,
      focalRatio: focalRatio,
      defaultGain: defaultGain,
      defaultOffset: defaultOffset,
      defaultBinX: defaultBinX,
      defaultBinY: defaultBinY,
      defaultCoolingTemp: defaultCoolingTemp,
      coolOnConnect: coolOnConnect,
      defaultCenteringExposure: defaultCenteringExposure,
      filterNames: filterNames,
      filterFocusOffsets: filterFocusOffsets,
      meridianFlipOverrides: meridianFlipOverrides,
      profileIcon: profileIcon,
      profileColor: profileColor,
      sortOrder: sortOrder,
      // createdAt/updatedAt omitted -> null -> fresh timestamps on insert.
    );
  }

  /// Calculate f/ratio from focal length and aperture, or null when the numbers
  /// cannot describe a real optical system.
  ///
  /// Validation now bounds every path that can WRITE optics, but rows written
  /// before that — or restored from a backup, which deliberately reproduces
  /// prior state verbatim — can still hold an implausible pair. Reporting
  /// `f/9999999990000.00` as a derived fact is the same defect class as the
  /// original: the app stating something untrue. Every caller already handles
  /// null (Settings renders a dash), so refusing to compute is strictly better
  /// than computing nonsense.
  double? get calculatedFocalRatio {
    final ratio = focalRatio ?? (aperture > 0 ? focalLength / aperture : null);
    if (ratio == null || !ratio.isFinite) return null;
    if (ratio < OpticalTrainLimits.minFRatio ||
        ratio > OpticalTrainLimits.maxFRatio) {
      return null;
    }
    return ratio;
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

  /// REST `/api/profiles` payload for host-authoritative writes.
  remote_profile.EquipmentProfile toRemoteProfile() {
    return remote_profile.EquipmentProfile(
      id: id?.toString() ?? '',
      name: name,
      description: description,
      cameraId: cameraId,
      mountId: mountId,
      focuserId: focuserId,
      filterWheelId: filterWheelId,
      guiderId: guiderId,
      rotatorId: rotatorId,
      domeId: domeId,
      weatherId: weatherId,
      safetyMonitorId: safetyMonitorId,
      switchId: switchId,
      coverCalibratorId: coverCalibratorId,
      focalLength: focalLength,
      aperture: aperture,
      focalRatio: focalRatio,
      defaultGain: defaultGain,
      defaultOffset: defaultOffset,
      defaultBinX: defaultBinX,
      defaultBinY: defaultBinY,
      defaultCoolingTemp: defaultCoolingTemp,
      coolOnConnect: coolOnConnect,
      defaultCenteringExposure: defaultCenteringExposure,
      filterNames: filterNames.isNotEmpty ? jsonEncode(filterNames) : null,
      filterFocusOffsets: filterFocusOffsets.isNotEmpty
          ? jsonEncode(filterFocusOffsets)
          : null,
      meridianFlipOverrides: meridianFlipOverrides,
      cameraName: cameraName,
      mountName: mountName,
      focuserName: focuserName,
      filterWheelName: filterWheelName,
      guiderName: guiderName,
      rotatorName: rotatorName,
      safetyMonitorName: safetyMonitorName,
      switchName: switchName,
      telescopeName: telescopeName,
      telescopeFocalLength: telescopeFocalLength ?? 0.0,
      telescopeAperture: telescopeAperture ?? 0.0,
      profileIcon: profileIcon,
      profileColor: profileColor,
      sortOrder: sortOrder,
      isDefault: isDefault,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      isActive: isActive,
    );
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
  ({NetworkBackend backend, BackendNotifier owner})? get _remoteAuthority {
    final owner = ref.read(backendProvider.notifier);
    final backend = owner.currentBackend;
    return backend is NetworkBackend ? (backend: backend, owner: owner) : null;
  }

  void _requireRemoteAuthority(NetworkBackend backend, BackendNotifier owner) {
    if (!owner.isCurrentBackend(backend)) {
      throw StateError(
        'The imaging host changed while the profile operation was running.',
      );
    }
  }

  Future<int?> _resolveRemoteProfileIdByName(
    NetworkBackend backend,
    BackendNotifier owner,
    String name, {
    Set<int> excludingIds = const <int>{},
  }) async {
    final profiles = await backend.getProfiles();
    _requireRemoteAuthority(backend, owner);
    final candidates = <int>[];
    for (final profile in profiles) {
      if (profile.name == name) {
        final id = int.tryParse(profile.id);
        if (id != null && id > 0 && !excludingIds.contains(id)) {
          candidates.add(id);
        }
      }
    }
    // A name is not an identity. The compatibility fallback for older hosts
    // is only safe when exactly one previously unseen row matches; otherwise
    // fail loudly instead of selecting an arbitrary same-name profile.
    return candidates.length == 1 ? candidates.single : null;
  }

  @override
  Future<EquipmentProfilesState> build() async {
    final backend = ref.watch(backendProvider);
    if (backend is NetworkBackend) {
      try {
        final remoteProfiles = await backend.getProfiles();
        final activeRemote = await backend.getActiveProfile();
        final profiles =
            remoteProfiles.map(EquipmentProfileModel.fromRemoteProfile).toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

        EquipmentProfileModel? active;
        if (activeRemote != null) {
          active = EquipmentProfileModel.fromRemoteProfile(activeRemote);
        } else {
          for (final profile in profiles) {
            if (profile.isActive) {
              active = profile;
              break;
            }
          }
        }

        return EquipmentProfilesState(
          profiles: profiles,
          activeProfile: active,
        );
      } catch (e, stackTrace) {
        _log.warning('Remote equipment profile fetch failed: $e\n$stackTrace');
        Error.throwWithStackTrace(
          StateError('Could not load equipment profiles from host: $e'),
          stackTrace,
        );
      }
    }

    // Wait for both authoritative database streams. Returning an empty data
    // state while either stream was loading (or had failed) made an existing
    // installation look like it had no profiles and could launch first-run
    // onboarding over a transient database error.
    final profilesFuture = ref.watch(allProfilesProvider.future);
    final activeFuture = ref.watch(activeProfileProvider.future);
    final databaseProfiles = await profilesFuture;
    final databaseActive = await activeFuture;

    final profiles = databaseProfiles
        .map((profile) => EquipmentProfileModel.fromDatabase(profile))
        .toList();
    final active = databaseActive == null
        ? null
        : EquipmentProfileModel.fromDatabase(databaseActive);

    return EquipmentProfilesState(profiles: profiles, activeProfile: active);
  }

  /// Create a new profile
  Future<int> createProfile({required String name, String? description}) async {
    final authority = _remoteAuthority;
    if (authority != null) {
      final remote = authority.backend;
      final current = await future;
      _requireRemoteAuthority(remote, authority.owner);
      final existingIds = current.profiles
          .map((profile) => profile.id)
          .whereType<int>()
          .toSet();
      await remote.saveProfile(
        EquipmentProfileModel(
          name: name,
          description: description,
        ).toRemoteProfile(),
      );
      _requireRemoteAuthority(remote, authority.owner);
      final id =
          int.tryParse(remote.lastSavedProfileId ?? '') ??
          await _resolveRemoteProfileIdByName(
            remote,
            authority.owner,
            name,
            excludingIds: existingIds,
          );
      if (id == null || id <= 0) {
        throw StateError(
          'Host saved profile "$name" but id could not be resolved',
        );
      }
      ref.invalidateSelf();
      return id;
    }

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

  /// Update an existing profile.
  ///
  /// In remote (slave) mode this routes the FULL profile to the host's
  /// `POST /api/profiles` (SQLite-backed since the profiles layer); the host
  /// decides create-vs-update by the parsed id, so a null-id model is accepted
  /// as a remote CREATE. The local (host/desktop) DAO path still requires an id.
  Future<int> updateProfile(EquipmentProfileModel profile) async {
    final authority = _remoteAuthority;
    if (authority != null) {
      final remote = authority.backend;
      await remote.saveProfile(profile.toRemoteProfile());
      _requireRemoteAuthority(remote, authority.owner);
      final savedId =
          int.tryParse(remote.lastSavedProfileId ?? '') ??
          profile.id ??
          await _resolveRemoteProfileIdByName(
            remote,
            authority.owner,
            profile.name,
          );
      if (savedId == null || savedId <= 0) {
        throw StateError(
          'Host saved profile "${profile.name}" but returned no valid id',
        );
      }
      ref.invalidateSelf();
      return savedId;
    }

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
      safetyMonitorId: Value(profile.safetyMonitorId),
      switchId: Value(profile.switchId),
      coverCalibratorId: Value(profile.coverCalibratorId),
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
        profile.filterNames.isNotEmpty ? jsonEncode(profile.filterNames) : null,
      ),
      filterFocusOffsets: Value(
        profile.filterFocusOffsets.isNotEmpty
            ? jsonEncode(profile.filterFocusOffsets)
            : null,
      ),
      updatedAt: DateTime.now(),
    );

    await dao.updateProfile(updated);
    ref.invalidateSelf();
    return profile.id!;
  }

  /// Delete a profile
  Future<void> deleteProfile(int profileId) async {
    final authority = _remoteAuthority;
    if (authority != null) {
      final remote = authority.backend;
      await remote.deleteProfile(profileId.toString());
      _requireRemoteAuthority(remote, authority.owner);
      ref.invalidateSelf();
      return;
    }

    final dao = ref.read(equipmentProfilesDaoProvider);
    await dao.deleteProfile(profileId);
    ref.invalidateSelf();
  }

  /// Set a profile as active.
  ///
  /// This is the single, remote-aware activation authority. In remote (slave)
  /// mode it defers to the host's load endpoint exactly once (the host owns
  /// activation and its own native write-through). In local (desktop /
  /// Pi-headless) mode it updates SQLite, mirrors the now-active row into the
  /// native (Rust) executor store via [writeActiveProfileThrough], then
  /// refreshes provider state — so SQLite/UI and the native sequencer can never
  /// disagree about which profile is active.
  ///
  /// Activation is transactional for every caller: the native executor accepts
  /// the target before SQLite changes, so an interactive tap cannot leave the
  /// UI and running sequencer on different profiles.
  Future<void> setActiveProfile(int profileId) => _activateProfile(profileId);

  /// Startup-facing alias for the same strict transaction used by every
  /// activation. Kept as a named API because startup callers use the failure as
  /// a hard gate before connecting equipment.
  Future<void> setActiveProfileStrict(int profileId) =>
      _activateProfile(profileId);

  Future<void> _activateProfile(int profileId) async {
    final authority = _remoteAuthority;
    if (authority != null) {
      final remote = authority.backend;
      // Host owns activation and its own native write-through; a failed host
      // load already throws, which is exactly the strict behaviour startup
      // needs on a remote companion. No slave-local SQLite/native write.
      await remote.loadProfile(profileId.toString());
      _requireRemoteAuthority(remote, authority.owner);
      ref.invalidateSelf();
      return;
    }

    // Resolve every collaborator BEFORE mutating SQLite. build() watches the
    // profile streams, so a `ref.read` AFTER a SQLite mutation would trip
    // Riverpod's "dependency changed before rebuild" guard.
    final dao = ref.read(equipmentProfilesDaoProvider);
    final settingsBackend = ref.read(profileSettingsBackendProvider);
    final logger = ref.read(loggingServiceProvider);

    // Transactional truth: validate the target, push it into the native
    // executor store FIRST, and only THEN commit the SQLite active flag —
    // compensating the native store if the commit fails. This applies equally
    // to startup and operator-initiated activation.
    try {
      await activateProfileStrictTransactional(
        dao: dao,
        backend: settingsBackend,
        logger: logger,
        profileId: profileId,
      );
    } finally {
      ref.invalidateSelf();
    }
  }

  /// Set or clear the default startup profile.
  Future<void> setDefaultProfile(
    int? profileId, {
    bool makeActive = true,
  }) async {
    final authority = _remoteAuthority;
    if (authority != null) {
      final remote = authority.backend;
      if (profileId != null) {
        // Dedicated host endpoint: setDefaultProfile atomically unsets the
        // previous default and makes this row active (makeActive is owned
        // host-side). The generic saveProfile path could never flip the
        // host's isDefault because the converter preserves existing.isDefault.
        await remote.setDefaultProfileRemote(profileId.toString());
      } else {
        // Clear-default: dedicated host endpoint (the saveProfile path can't
        // clear isDefault because the converter preserves the existing row's
        // flag).
        await remote.clearDefaultProfileRemote();
      }
      _requireRemoteAuthority(remote, authority.owner);
      ref.invalidateSelf();
      return;
    }

    // Resolve collaborators up front (see [setActiveProfile] for why the reads
    // must precede the SQLite mutation).
    final dao = ref.read(equipmentProfilesDaoProvider);
    final settingsBackend = ref.read(profileSettingsBackendProvider);
    final logger = ref.read(loggingServiceProvider);
    if (profileId == null) {
      await dao.clearDefaultProfile();
    } else if (makeActive) {
      // The default+active DAO mutation is one transaction, but native must
      // accept the target first. Reuse the strict activation coordinator with
      // the default-setting transaction as its commit step.
      await activateProfileStrictTransactional(
        dao: dao,
        backend: settingsBackend,
        logger: logger,
        profileId: profileId,
        commit: () => dao.setDefaultProfile(profileId, makeActive: true),
      );
    } else {
      await dao.setDefaultProfile(profileId, makeActive: false);
    }
    ref.invalidateSelf();
  }

  /// Persist a new display order for the profiles.
  ///
  /// [orderedIds] is the full list of profile ids in their new order; each id
  /// is assigned `sortOrder == its index`. On a slave this routes to the
  /// dedicated host endpoint (the generic saveProfile path can't change
  /// sortOrder because the converter preserves the existing row's value);
  /// locally it writes the DAO directly.
  Future<void> reorderProfiles(List<int> orderedIds) async {
    final authority = _remoteAuthority;
    if (authority != null) {
      final remote = authority.backend;
      await remote.reorderProfilesRemote(
        orderedIds.map((id) => id.toString()).toList(),
      );
      _requireRemoteAuthority(remote, authority.owner);
      ref.invalidateSelf();
      return;
    }

    final dao = ref.read(equipmentProfilesDaoProvider);
    await dao.reorderProfiles(orderedIds);
    ref.invalidateSelf();
  }

  /// Duplicate a profile
  Future<int> duplicateProfile(int sourceId, String newName) async {
    final authority = _remoteAuthority;
    if (authority != null) {
      final remote = authority.backend;
      final current = await future;
      _requireRemoteAuthority(remote, authority.owner);
      EquipmentProfileModel? source;
      for (final profile in current.profiles) {
        if (profile.id == sourceId) {
          source = profile;
          break;
        }
      }
      if (source == null) {
        throw StateError('Profile $sourceId not found on host');
      }
      // Build a genuine insertion copy: id CLEARED (so the host creates a new
      // row rather than updating/renaming the source), active/default false, new
      // name, every other field preserved. `copyWith(id: null)` cannot clear the
      // id (id ?? this.id) and would send the source id — silently overwriting
      // the source instead of duplicating it.
      await remote.saveProfile(
        source.toInsertionCopy(name: newName).toRemoteProfile(),
      );
      _requireRemoteAuthority(remote, authority.owner);
      final existingIds = current.profiles
          .map((profile) => profile.id)
          .whereType<int>()
          .toSet();
      final id =
          int.tryParse(remote.lastSavedProfileId ?? '') ??
          await _resolveRemoteProfileIdByName(
            remote,
            authority.owner,
            newName,
            excludingIds: existingIds,
          );
      if (id == null) {
        throw StateError(
          'Host duplicated profile as "$newName" but id could not be resolved',
        );
      }
      ref.invalidateSelf();
      return id;
    }

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

  /// Export a single profile to JSON
  Future<String> exportProfile(int profileId) async {
    final service = ref.read(profileServiceProvider);
    return await service.exportProfileToJson(profileId);
  }
}

/// Main provider for equipment profiles
final equipmentProfilesProvider =
    AsyncNotifierProvider<EquipmentProfilesNotifier, EquipmentProfilesState>(
      () {
        return EquipmentProfilesNotifier();
      },
    );

/// Provider for watching just the active profile (convenience)
final activeEquipmentProfileProvider = Provider<EquipmentProfileModel?>((ref) {
  final state = ref.watch(equipmentProfilesProvider);
  return state.valueOrNull?.activeProfile;
});

/// Provider for watching just the profile list (convenience)
final equipmentProfileListProvider = Provider<List<EquipmentProfileModel>>((
  ref,
) {
  final state = ref.watch(equipmentProfilesProvider);
  return state.valueOrNull?.profiles ?? [];
});

// ============================================================================
// Optical Configuration Provider
// ============================================================================

/// Provider that computes optical configuration from the active profile and
/// connected camera capabilities.
///
/// This combines:
/// - Telescope focal length and aperture from the active profile
/// - Camera sensor dimensions and pixel size from camera capabilities
///
/// Returns null if no profile is active or required data is missing.
final opticalConfigProvider = Provider<OpticalConfig?>((ref) {
  final profile = ref.watch(activeEquipmentProfileProvider);
  if (profile == null) return null;

  // Get effective focal length - prefer profile focalLength, fall back to telescope
  final effectiveFocalLength = profile.focalLength > 0
      ? profile.focalLength
      : (profile.telescopeFocalLength ?? 0);
  final effectiveAperture = profile.aperture > 0
      ? profile.aperture
      : (profile.telescopeAperture ?? 0);

  // Try to get camera capabilities if camera is connected
  final cameraState = ref.watch(cameraStateProvider);
  int? sensorWidth;
  int? sensorHeight;
  double? pixelSize;

  if (cameraState.deviceId != null &&
      cameraState.connectionState == DeviceConnectionState.connected) {
    // Watch camera capabilities for the connected camera
    final capabilitiesAsync = ref.watch(
      cameraCapabilitiesProvider(cameraState.deviceId!),
    );
    final CameraCapabilities? capabilities = capabilitiesAsync.valueOrNull;

    if (capabilities != null) {
      sensorWidth = capabilities.maxWidth;
      sensorHeight = capabilities.maxHeight;
      final px = capabilities.pixelSizeX;
      final py = capabilities.pixelSizeY;
      if (px != null && px > 0 && py != null && py > 0) {
        // OpticalConfig currently stores a scalar pixel size; use the mean of
        // axis-specific values to avoid assuming perfectly square pixels.
        pixelSize = (px + py) / 2.0;
      } else if (px != null && px > 0) {
        pixelSize = px;
      } else if (py != null && py > 0) {
        pixelSize = py;
      }
    }
  }

  return OpticalConfig(
    telescopeName: profile.telescopeName,
    focalLength: effectiveFocalLength > 0 ? effectiveFocalLength : null,
    aperture: effectiveAperture > 0 ? effectiveAperture : null,
    focalRatio: profile.focalRatio,
    cameraName: profile.cameraName ?? cameraState.deviceName,
    sensorWidth: sensorWidth,
    sensorHeight: sensorHeight,
    pixelSize: pixelSize,
  );
});

// ============================================================================
// Profile Filters Provider
// ============================================================================

/// Provider that returns the filter names from the active profile.
///
/// Returns an empty list if no profile is active or no filters are configured.
final profileFiltersProvider = Provider<List<String>>((ref) {
  final profile = ref.watch(activeEquipmentProfileProvider);
  if (profile == null) return [];
  return profile.filterNames;
});

// ============================================================================
// Sorted Profiles Provider
// ============================================================================

/// Provider that returns all profiles sorted by sortOrder field.
///
/// Profiles with lower sortOrder values appear first.
/// Profiles with the same sortOrder are sorted by name alphabetically.
final sortedProfilesProvider = Provider<List<EquipmentProfileModel>>((ref) {
  final profiles = ref.watch(equipmentProfileListProvider);
  final sorted = List<EquipmentProfileModel>.from(profiles);
  sorted.sort((a, b) {
    final orderCompare = a.sortOrder.compareTo(b.sortOrder);
    if (orderCompare != 0) return orderCompare;
    return a.name.compareTo(b.name);
  });
  return sorted;
});
