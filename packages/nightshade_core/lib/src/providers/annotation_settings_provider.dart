import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/annotation_settings.dart';
import 'database_provider.dart';

/// Built-in annotation presets
const builtInAnnotationPresets = <AnnotationPreset>[
  AnnotationPreset(
    name: 'Deep Field',
    visibleTypes: {AnnotationObjectFilter.galaxies},
    minMagnitude: 10.0,
    magnitudeCutoff: 18.0,
    showLabels: true,
    showMagnitudes: true,
    isBuiltIn: true,
  ),
  AnnotationPreset(
    name: 'Wide Field',
    visibleTypes: {
      AnnotationObjectFilter.galaxies,
      AnnotationObjectFilter.nebulae,
      AnnotationObjectFilter.starClusters,
      AnnotationObjectFilter.planetaryNebulae,
    },
    minMagnitude: -5.0,
    magnitudeCutoff: 12.0,
    showLabels: true,
    showMagnitudes: false,
    isBuiltIn: true,
  ),
  AnnotationPreset(
    name: 'Star Field',
    visibleTypes: {AnnotationObjectFilter.stars},
    minMagnitude: -5.0,
    magnitudeCutoff: 15.0,
    showLabels: false,
    showMagnitudes: false,
    isBuiltIn: true,
  ),
];

/// Provider for annotation display settings (persisted to database)
final annotationSettingsProvider =
    AsyncNotifierProvider<AnnotationSettingsNotifier, AnnotationSettings>(() {
  return AnnotationSettingsNotifier();
});

/// Provider for annotation marker styles (persisted to database)
final annotationMarkerStyleProvider =
    AsyncNotifierProvider<AnnotationMarkerStyleNotifier, AnnotationMarkerStyle>(() {
  return AnnotationMarkerStyleNotifier();
});

/// Provider for tracking if mouse is hovering over image
final annotationHoverStateProvider = StateProvider<bool>((ref) => false);

/// Provider for current annotation opacity (animated)
final annotationOpacityProvider = Provider<double>((ref) {
  final settingsAsync = ref.watch(annotationSettingsProvider);
  final settings = settingsAsync.valueOrNull ?? const AnnotationSettings();
  final isHovering = ref.watch(annotationHoverStateProvider);

  if (!settings.fadeWhenNotHovering) {
    return settings.hoverOpacity;
  }

  return isHovering ? settings.hoverOpacity : settings.idleOpacity;
});

/// Notifier for annotation settings with database persistence
class AnnotationSettingsNotifier extends AsyncNotifier<AnnotationSettings> {
  static const _settingsKey = 'annotation_settings';

  @override
  Future<AnnotationSettings> build() async {
    final dao = ref.read(settingsDaoProvider);
    final jsonStr = await dao.getSetting(_settingsKey);

    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return AnnotationSettings.fromJson(json);
      } catch (e) {
        // If parsing fails, return defaults
        return const AnnotationSettings();
      }
    }
    return const AnnotationSettings();
  }

  Future<void> _save(AnnotationSettings settings) async {
    final dao = ref.read(settingsDaoProvider);
    final jsonStr = jsonEncode(settings.toJson());
    await dao.setSetting(_settingsKey, jsonStr);
  }

  Future<void> setEnabled(bool enabled) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(enabled: enabled);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setMagnitudeCutoff(double magnitude) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(magnitudeCutoff: magnitude.clamp(0.0, 25.0));
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setMinMagnitude(double magnitude) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(minMagnitude: magnitude.clamp(-10.0, 20.0));
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> toggleObjectType(AnnotationObjectFilter type) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final types = Set<AnnotationObjectFilter>.from(current.visibleTypes);
    if (types.contains(type)) {
      types.remove(type);
    } else {
      types.add(type);
    }
    final updated = current.copyWith(visibleTypes: types);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setObjectTypes(Set<AnnotationObjectFilter> types) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(visibleTypes: types);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setShowLabels(bool show) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(showLabels: show);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setShowMagnitudes(bool show) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(showMagnitudes: show);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setFadeWhenNotHovering(bool fade) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(fadeWhenNotHovering: fade);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setHoverOpacity(double opacity) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(hoverOpacity: opacity.clamp(0.0, 1.0));
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setIdleOpacity(double opacity) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(idleOpacity: opacity.clamp(0.0, 1.0));
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setFadeAnimationMs(int ms) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(fadeAnimationMs: ms.clamp(0, 2000));
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setClickToIdentify(bool enabled) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(clickToIdentify: enabled);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setClickSearchRadius(double arcsec) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(clickSearchRadiusArcsec: arcsec.clamp(1.0, 300.0));
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setAutoAnnotate(bool auto) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(autoAnnotate: auto);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setMaxObjectsToDisplay(int max) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(maxObjectsToDisplay: max.clamp(10, 5000));
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setCompassEnabled(bool enabled) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(compassEnabled: enabled);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setScaleBarEnabled(bool enabled) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(scaleBarEnabled: enabled);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setGridType(GridType gridType) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(gridType: gridType);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setShowSolveResiduals(bool show) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(showSolveResiduals: show);
    await _save(updated);
    state = AsyncData(updated);
  }

  /// Apply an annotation preset to current settings
  Future<void> applyPreset(AnnotationPreset preset) async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final updated = current.copyWith(
      visibleTypes: preset.visibleTypes,
      minMagnitude: preset.minMagnitude,
      magnitudeCutoff: preset.magnitudeCutoff,
      showLabels: preset.showLabels,
      showMagnitudes: preset.showMagnitudes,
    );
    await _save(updated);
    state = AsyncData(updated);
  }

  /// Cycle through grid types: none -> pixel -> celestial -> none
  Future<void> cycleGridType() async {
    final current = state.valueOrNull ?? const AnnotationSettings();
    final next = switch (current.gridType) {
      GridType.none => GridType.pixel,
      GridType.pixel => GridType.celestial,
      GridType.celestial => GridType.none,
    };
    final updated = current.copyWith(gridType: next);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> reset() async {
    const defaults = AnnotationSettings();
    await _save(defaults);
    state = const AsyncData(defaults);
  }
}

/// Notifier for annotation marker styles with database persistence
class AnnotationMarkerStyleNotifier extends AsyncNotifier<AnnotationMarkerStyle> {
  static const _settingsKey = 'annotation_marker_style';

  @override
  Future<AnnotationMarkerStyle> build() async {
    final dao = ref.read(settingsDaoProvider);
    final jsonStr = await dao.getSetting(_settingsKey);

    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return AnnotationMarkerStyle.fromJson(json);
      } catch (e) {
        // If parsing fails, return defaults
        return const AnnotationMarkerStyle();
      }
    }
    return const AnnotationMarkerStyle();
  }

  Future<void> _save(AnnotationMarkerStyle style) async {
    final dao = ref.read(settingsDaoProvider);
    final jsonStr = jsonEncode(style.toJson());
    await dao.setSetting(_settingsKey, jsonStr);
  }

  Future<void> setGalaxyColor(int color) async {
    final current = state.valueOrNull ?? const AnnotationMarkerStyle();
    final updated = current.copyWith(galaxyColor: color);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setNebulaColor(int color) async {
    final current = state.valueOrNull ?? const AnnotationMarkerStyle();
    final updated = current.copyWith(nebulaColor: color);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setClusterColor(int color) async {
    final current = state.valueOrNull ?? const AnnotationMarkerStyle();
    final updated = current.copyWith(clusterColor: color);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setPlanetaryNebulaColor(int color) async {
    final current = state.valueOrNull ?? const AnnotationMarkerStyle();
    final updated = current.copyWith(planetaryNebulaColor: color);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setStarColor(int color) async {
    final current = state.valueOrNull ?? const AnnotationMarkerStyle();
    final updated = current.copyWith(starColor: color);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setOtherColor(int color) async {
    final current = state.valueOrNull ?? const AnnotationMarkerStyle();
    final updated = current.copyWith(otherColor: color);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setStrokeWidth(double width) async {
    final current = state.valueOrNull ?? const AnnotationMarkerStyle();
    final updated = current.copyWith(strokeWidth: width.clamp(0.5, 5.0));
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setLabelFontSize(double size) async {
    final current = state.valueOrNull ?? const AnnotationMarkerStyle();
    final updated = current.copyWith(labelFontSize: size.clamp(8.0, 24.0));
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setScaleBySize(bool scale) async {
    final current = state.valueOrNull ?? const AnnotationMarkerStyle();
    final updated = current.copyWith(scaleBySize: scale);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setMinMarkerSize(double size) async {
    final current = state.valueOrNull ?? const AnnotationMarkerStyle();
    final updated = current.copyWith(minMarkerSize: size.clamp(5.0, 50.0));
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> setMaxMarkerSize(double size) async {
    final current = state.valueOrNull ?? const AnnotationMarkerStyle();
    final updated = current.copyWith(maxMarkerSize: size.clamp(20.0, 200.0));
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> reset() async {
    const defaults = AnnotationMarkerStyle();
    await _save(defaults);
    state = const AsyncData(defaults);
  }
}

/// Provider for user-created annotation presets (persisted to database)
final annotationPresetsProvider =
    AsyncNotifierProvider<AnnotationPresetsNotifier, List<AnnotationPreset>>(
        () {
  return AnnotationPresetsNotifier();
});

class AnnotationPresetsNotifier extends AsyncNotifier<List<AnnotationPreset>> {
  static const _settingsKey = 'annotation_presets';

  @override
  Future<List<AnnotationPreset>> build() async {
    final dao = ref.read(settingsDaoProvider);
    final jsonStr = await dao.getSetting(_settingsKey);

    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final jsonList = jsonDecode(jsonStr) as List<dynamic>;
        return jsonList
            .map((e) => AnnotationPreset.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        return const [];
      }
    }
    return const [];
  }

  Future<void> _save(List<AnnotationPreset> presets) async {
    final dao = ref.read(settingsDaoProvider);
    final jsonStr = jsonEncode(presets.map((p) => p.toJson()).toList());
    await dao.setSetting(_settingsKey, jsonStr);
  }

  /// Save the current annotation settings as a named preset
  Future<void> saveCurrentAsPreset(String name) async {
    final settingsNotifier = ref.read(annotationSettingsProvider.notifier);
    final settings =
        settingsNotifier.state.valueOrNull ?? const AnnotationSettings();

    final preset = AnnotationPreset(
      name: name,
      visibleTypes: settings.visibleTypes,
      minMagnitude: settings.minMagnitude,
      magnitudeCutoff: settings.magnitudeCutoff,
      showLabels: settings.showLabels,
      showMagnitudes: settings.showMagnitudes,
      isBuiltIn: false,
    );

    final current = state.valueOrNull ?? [];
    // Replace existing preset with same name, or append
    final updated = current
        .where((p) => p.name != name)
        .toList()
      ..add(preset);
    await _save(updated);
    state = AsyncData(updated);
  }

  Future<void> deletePreset(String name) async {
    final current = state.valueOrNull ?? [];
    final updated = current.where((p) => p.name != name).toList();
    await _save(updated);
    state = AsyncData(updated);
  }
}

/// Provider for custom user-drawn annotations on the current image.
/// These are in-memory and scoped to the current image.
final customAnnotationsProvider =
    StateNotifierProvider<CustomAnnotationsNotifier, List<CustomAnnotation>>(
        (ref) {
  return CustomAnnotationsNotifier();
});

/// Active drawing tool for custom annotations (null = no tool active)
final customAnnotationToolProvider =
    StateProvider<CustomAnnotationType?>((ref) => null);

class CustomAnnotationsNotifier extends StateNotifier<List<CustomAnnotation>> {
  CustomAnnotationsNotifier() : super(const []);

  void add(CustomAnnotation annotation) {
    state = [...state, annotation];
  }

  void remove(String id) {
    state = state.where((a) => a.id != id).toList();
  }

  void updateLabel(String id, String label) {
    state = state.map((a) {
      if (a.id == id) return a.copyWith(label: label);
      return a;
    }).toList();
  }

  void clear() {
    state = const [];
  }
}
