import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/annotation_settings.dart';
import 'database_provider.dart';

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
