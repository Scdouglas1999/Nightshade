import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/render_config_state.dart';
import 'planetarium_sync.dart';

class RenderConfigNotifier extends StateNotifier<RenderConfigState> {
  RenderConfigNotifier() : super(const RenderConfigState());

  void toggleStars() {
    state = state.copyWith(showStars: !state.showStars);
  }

  void toggleConstellations() {
    state = state.copyWith(showConstellations: !state.showConstellations);
  }

  void toggleConstellationBoundaries() {
    state = state.copyWith(
      showConstellationBoundaries: !state.showConstellationBoundaries,
    );
  }

  void toggleConstellationArt() {
    state = state.copyWith(showConstellationArt: !state.showConstellationArt);
  }

  void toggleEquatorialGrid() {
    state = state.copyWith(showEquatorialGrid: !state.showEquatorialGrid);
  }

  void toggleAltAzGrid() {
    state = state.copyWith(showAltAzGrid: !state.showAltAzGrid);
  }

  void toggleGalacticGrid() {
    state = state.copyWith(showGalacticGrid: !state.showGalacticGrid);
  }

  void toggleEcliptic() {
    state = state.copyWith(showEcliptic: !state.showEcliptic);
  }

  void toggleGalacticPlane() {
    state = state.copyWith(showGalacticPlane: !state.showGalacticPlane);
  }

  void toggleMilkyWay() {
    state = state.copyWith(showMilkyWay: !state.showMilkyWay);
  }

  void toggleHorizon() {
    state = state.copyWith(showHorizon: !state.showHorizon);
  }

  void toggleAtmosphere() {
    state = state.copyWith(showAtmosphere: !state.showAtmosphere);
  }

  void toggleDsos() {
    state = state.copyWith(showDsos: !state.showDsos);
  }

  void toggleSolarSystem() {
    state = state.copyWith(showSolarSystem: !state.showSolarSystem);
  }

  void toggleSatellites() {
    state = state.copyWith(showSatellites: !state.showSatellites);
  }

  void toggleMinorPlanets() {
    state = state.copyWith(showMinorPlanets: !state.showMinorPlanets);
  }

  void toggleVariableStars() {
    state = state.copyWith(showVariableStars: !state.showVariableStars);
  }

  void toggleTwinkle() {
    state = state.copyWith(twinkle: !state.twinkle);
  }

  void setMagnitudeLimit(double limit) {
    state = state.copyWith(magnitudeLimit: limit);
  }

  void setQuality(int quality) {
    state = state.copyWith(quality: quality);
  }

  void setBortleClass(int bortleClass) {
    state = state.copyWith(bortleClass: bortleClass);
  }
}

/// Layer visibility and render quality for planetarium v2.
final renderConfigProvider =
    StateNotifierProvider<RenderConfigNotifier, RenderConfigState>((ref) {
  return RenderConfigNotifier();
});

/// Mirrors [renderConfigProvider] into Rust via [planetariumSetConfig].
final planetariumRenderConfigSyncProvider = Provider<void>((ref) {
  bindPlanetariumSync(
    ref,
    listenSource: renderConfigProvider,
    push: (driver, config) => driver.setConfig(config.toDto()),
  );
});
