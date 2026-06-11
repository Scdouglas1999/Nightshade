import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/network_backend.dart';
import '../../database/daos/settings_dao.dart';
import '../../models/equipment/equipment_models.dart';
import '../../providers/backend_provider.dart';
import '../../providers/capability_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/equipment/camera_state_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/session_optimizer_provider.dart';
import '../logging_service.dart';
import '../smart_night/hardware_specs_service.dart';

/// Keeps the `science.camera.*` settings (read noise, gain in e⁻/ADU,
/// saturation ADU) in sync with the hardware that is actually in use, so
/// photometric limiting magnitudes and saturation rejection work without
/// the user hand-typing sensor datasheets.
///
/// Sources, in priority order:
///   1. The connected camera (live device name + current driver gain).
///   2. The active equipment profile (camera name + default gain) when no
///      camera is connected.
///
/// Sensor values come from [HardwareSpecsService] — the same per-gain
/// read-noise / full-well catalog (plus user overrides) that Smart Night's
/// exposure model uses, so the two features can never disagree about the
/// camera. Saturation and the e⁻/ADU conversion are derived from the
/// driver-reported bit depth:
///   maxAdu       = 2^bitDepth − 1   (65535 when capabilities are absent)
///   gain e⁻/ADU  = fullWell_e / maxAdu
///
/// The sync is opt-out: `science.camera.auto_managed=false` (set when the
/// user manually edits any of the three fields) freezes the values, and
/// the Settings UI shows which camera/gain produced the current numbers
/// via `science.camera.auto_source`. In remote mode the appliance host
/// runs its own instance of this service against the real hardware, so the
/// client skips syncing entirely.
class ScienceCameraAutoConfig {
  static const autoManagedKey = 'science.camera.auto_managed';
  static const autoSourceKey = 'science.camera.auto_source';
  static const readNoiseKey = 'science.camera.read_noise_e';
  static const gainKey = 'science.camera.gain_e_per_adu';
  static const saturationKey = 'science.camera.saturation_adu';

  final Ref _ref;

  /// Last (name, gain, bitDepth) tuple applied, to skip redundant writes.
  (String, int?, int)? _lastApplied;

  ScienceCameraAutoConfig(this._ref);

  LoggingService get _logger => _ref.read(loggingServiceProvider);

  /// Recompute and persist the science camera settings if auto-management
  /// is enabled and a camera identity can be resolved. Safe to call often;
  /// no-ops when nothing relevant changed.
  Future<void> maybeSync({
    String reason = 'unspecified',
    bool force = false,
  }) async {
    try {
      if (_ref.read(backendProvider) is NetworkBackend) {
        return; // The appliance host owns the hardware and these settings.
      }
      final dao = _ref.read(settingsDaoProvider);
      final autoManaged = await dao.getSetting(autoManagedKey);
      if (autoManaged != null && autoManaged.toLowerCase() == 'false') {
        return;
      }

      final identity = _resolveCameraIdentity();
      if (identity == null) {
        return;
      }

      final bitDepth = await _resolveBitDepth(identity.deviceId);
      if (!force && _lastApplied == (identity.name, identity.gain, bitDepth)) {
        return;
      }

      final specs = await _specsWithOverrides(dao);
      final match = specs.matchCamera(
        cameraName: identity.name,
        cameraId: identity.deviceId,
        gain: identity.gain,
      );

      final maxAdu = ((1 << bitDepth) - 1).clamp(255, 65535);
      final updates = <String, String>{saturationKey: maxAdu.toString()};
      String source;
      if (match != null) {
        final readNoise = match.exposureSpec.readNoiseE;
        final gainEPerAdu = match.exposureSpec.fullWellE / maxAdu;
        updates[readNoiseKey] = readNoise.toStringAsFixed(2);
        updates[gainKey] = gainEPerAdu.toStringAsFixed(3);
        source =
            '${match.spec.model} @ gain ${identity.gain ?? match.spec.defaultGain} '
            '($bitDepth-bit)';
      } else {
        // Unknown sensor: bit depth still gives a correct saturation level,
        // but read noise / e-/ADU would be guesses — leave whatever the
        // user (or a previous match) configured rather than overwrite with
        // fabricated values.
        source =
            '${identity.name} ($bitDepth-bit) — sensor not in catalog, '
            'read noise/gain unchanged';
      }
      updates[autoSourceKey] = source;

      var changed = false;
      for (final entry in updates.entries) {
        final existing = await dao.getSetting(entry.key);
        if (existing != entry.value) {
          await dao.setSetting(entry.key, entry.value);
          changed = true;
        }
      }
      _lastApplied = (identity.name, identity.gain, bitDepth);
      if (changed) {
        _logger.info(
          'Science camera settings auto-updated ($reason): $source -> '
          '${updates.entries.where((e) => e.key != autoSourceKey).map((e) => '${e.key.split('.').last}=${e.value}').join(', ')}',
          source: 'ScienceCameraAutoConfig',
        );
      }
    } catch (error, stack) {
      _logger.warning(
        'Science camera auto-config sync failed ($reason): $error\n$stack',
        source: 'ScienceCameraAutoConfig',
      );
    }
  }

  ({String name, String? deviceId, int? gain})? _resolveCameraIdentity() {
    final camera = _ref.read(cameraStateProvider);
    if (camera.connectionState == DeviceConnectionState.connected) {
      final name = camera.deviceName ?? camera.deviceId;
      if (name != null && name.trim().isNotEmpty) {
        return (name: name, deviceId: camera.deviceId, gain: camera.gain);
      }
    }
    final profile = _ref.read(activeEquipmentProfileProvider);
    final profileCamera = profile?.cameraName ?? profile?.cameraId;
    if (profileCamera != null && profileCamera.trim().isNotEmpty) {
      return (
        name: profileCamera,
        deviceId: profile?.cameraId,
        gain: profile?.defaultGain,
      );
    }
    return null;
  }

  Future<int> _resolveBitDepth(String? deviceId) async {
    if (deviceId == null || deviceId.isEmpty) return 16;
    try {
      final caps = await _ref.read(cameraCapabilitiesProvider(deviceId).future);
      final bitDepth = caps?.bitDepth;
      if (bitDepth != null && bitDepth >= 8 && bitDepth <= 16) {
        return bitDepth;
      }
    } catch (_) {
      // Capabilities unavailable (camera offline): assume 16-bit output,
      // which matches how virtually all drivers scale sub-16-bit sensors.
    }
    return 16;
  }

  Future<HardwareSpecsService> _specsWithOverrides(SettingsDao dao) async {
    final base = _ref.read(hardwareSpecsServiceProvider);
    try {
      final raw = await dao.getSetting(
        HardwareSpecsService.cameraOverridesSettingKey,
      );
      if (raw == null || raw.trim().isEmpty) return base;
      final overrides = HardwareSpecsService.cameraOverridesFromJson(
        jsonDecode(raw),
      );
      return overrides.isEmpty ? base : base.withCameraOverrides(overrides);
    } catch (error) {
      _logger.warning(
        'Ignoring malformed camera hardware overrides: $error',
        source: 'ScienceCameraAutoConfig',
      );
      return base;
    }
  }
}

/// Watch this provider once at app startup (see `app.dart`) to activate the
/// sync. Listens only to the camera fields that matter — connection state,
/// identity, and gain — so per-exposure state churn does not re-trigger it.
final scienceCameraAutoConfigProvider = Provider<ScienceCameraAutoConfig>((
  ref,
) {
  final service = ScienceCameraAutoConfig(ref);
  ref.listen<(DeviceConnectionState, String?, String?, int?)>(
    cameraStateProvider.select(
      (s) => (s.connectionState, s.deviceName, s.deviceId, s.gain),
    ),
    (_, __) => service.maybeSync(reason: 'camera state changed'),
  );
  ref.listen(activeEquipmentProfileProvider, (_, __) {
    service.maybeSync(reason: 'active profile changed');
  });
  // Initial pass once the provider graph is up.
  Future.microtask(() => service.maybeSync(reason: 'startup'));
  return service;
});
