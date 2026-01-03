import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/imaging/camera_preset.dart';
import 'database_provider.dart';
import 'imaging_provider.dart';

/// Provider for managing camera gain/offset presets
final cameraPresetsProvider = StateNotifierProvider<CameraPresetsNotifier, AsyncValue<List<CameraPreset>>>((ref) {
  return CameraPresetsNotifier(ref);
});

/// Provider for the currently selected preset ID
final selectedPresetIdProvider = StateProvider<String?>((ref) => null);

class CameraPresetsNotifier extends StateNotifier<AsyncValue<List<CameraPreset>>> {
  final Ref _ref;
  static const String _storageKey = 'camera_presets';

  CameraPresetsNotifier(this._ref) : super(const AsyncValue.loading()) {
    _loadPresets();
  }

  /// Load presets from storage
  Future<void> _loadPresets() async {
    try {
      final dao = _ref.read(settingsDaoProvider);
      final jsonString = await dao.getSetting(_storageKey);

      if (jsonString == null || jsonString.isEmpty) {
        // Initialize with default presets
        final defaults = _createDefaultPresets();
        await _savePresets(defaults);
        state = AsyncValue.data(defaults);
      } else {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        final presets = jsonList.map((json) => CameraPreset.fromJson(json as Map<String, dynamic>)).toList();
        state = AsyncValue.data(presets);
      }
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Create default camera presets
  List<CameraPreset> _createDefaultPresets() {
    final now = DateTime.now();
    return [
      CameraPreset(
        id: 'high_dynamic_range',
        name: 'High Dynamic Range',
        gain: 0,
        offset: 10,
        createdAt: now,
      ),
      CameraPreset(
        id: 'low_read_noise',
        name: 'Low Read Noise',
        gain: 100,
        offset: 50,
        createdAt: now,
      ),
      CameraPreset(
        id: 'unity_gain',
        name: 'Unity Gain',
        gain: 139,
        offset: 30,
        createdAt: now,
      ),
    ];
  }

  /// Save presets to storage
  Future<void> _savePresets(List<CameraPreset> presets) async {
    try {
      final dao = _ref.read(settingsDaoProvider);
      final jsonList = presets.map((p) => p.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      await dao.setSetting(_storageKey, jsonString);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Add a new preset
  Future<void> addPreset(CameraPreset preset) async {
    final currentPresets = state.valueOrNull ?? [];

    // Check for duplicate names
    if (currentPresets.any((p) => p.name.toLowerCase() == preset.name.toLowerCase())) {
      throw Exception('A preset with this name already exists');
    }

    final updatedPresets = [...currentPresets, preset];
    await _savePresets(updatedPresets);
    state = AsyncValue.data(updatedPresets);
  }

  /// Update an existing preset
  Future<void> updatePreset(String id, CameraPreset updatedPreset) async {
    final currentPresets = state.valueOrNull ?? [];
    final index = currentPresets.indexWhere((p) => p.id == id);

    if (index == -1) {
      throw Exception('Preset not found');
    }

    final updatedPresets = [...currentPresets];
    updatedPresets[index] = updatedPreset.copyWith(
      updatedAt: DateTime.now(),
    );

    await _savePresets(updatedPresets);
    state = AsyncValue.data(updatedPresets);
  }

  /// Delete a preset
  Future<void> deletePreset(String id) async {
    final currentPresets = state.valueOrNull ?? [];
    final updatedPresets = currentPresets.where((p) => p.id != id).toList();

    await _savePresets(updatedPresets);
    state = AsyncValue.data(updatedPresets);

    // Clear selection if deleted preset was selected
    if (_ref.read(selectedPresetIdProvider) == id) {
      _ref.read(selectedPresetIdProvider.notifier).state = null;
    }
  }

  /// Apply a preset (updates exposure settings)
  void applyPreset(String id) {
    final preset = state.valueOrNull?.firstWhere(
      (p) => p.id == id,
      orElse: () => throw Exception('Preset not found'),
    );

    if (preset == null) return;

    // Update the selected preset
    _ref.read(selectedPresetIdProvider.notifier).state = id;

    // Update exposure settings
    final currentSettings = _ref.read(exposureSettingsProvider);
    _ref.read(exposureSettingsProvider.notifier).state = currentSettings.copyWith(
      gain: preset.gain,
      offset: preset.offset,
    );
  }

  /// Reset to default presets
  Future<void> resetToDefaults() async {
    final defaults = _createDefaultPresets();
    await _savePresets(defaults);
    state = AsyncValue.data(defaults);
    _ref.read(selectedPresetIdProvider.notifier).state = null;
  }
}
