import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

/// Mirrors the persisted observer location into the planetarium provider and the
/// Rust backend. Settings is the single source of truth; this only fans changes
/// out. Uses `ref.listen` to avoid modifying providers during build.
///
/// This deliberately does **not** auto-detect a location on first launch. Free
/// IP services resolve to the ISP's egress point and disagree with each other
/// by a hundred kilometres or more, yet a persisted estimate is rendered
/// exactly like a site the user typed — twilight times, the astro-dark
/// countdown and the imaging window all quoted off it with no hint that
/// anything is approximate.
///
/// 0/0 is the designed "not set" sentinel and every location-driven surface has
/// an honest empty state for it. The estimate stays one click away: the
/// onboarding observing-site step offers it as a labelled suggestion, and
/// Settings → Location has the same affordance.
final locationSyncProvider = Provider<void>((ref) {
  // Use ref.listen to sync settings to planetarium provider and Rust backend whenever settings change
  // This defers the update until after the build phase, avoiding the Riverpod error
  ref.listen(appSettingsProvider, (previous, next) {
    next.whenData((settings) {
      // Schedule the update for after the current build phase
      Future.microtask(() async {
        // Update planetarium provider with settings location
        // This is a temporary update (doesn't persist) - only settings persists
        ref.read(observerLocationProvider.notifier).setLocation(
              latitude: settings.latitude,
              longitude: settings.longitude,
              elevation: settings.elevation,
            );

        // Bridge effectiveHorizonDeg into the planetarium
        // package. We can't make planetarium depend on nightshade_core
        // (core already depends on planetarium for catalog access), so the
        // app layer pumps the value across via this sync provider. The
        // altitude card and rise/set times in object_details_panel read
        // `effectiveHorizonDegProvider` from the planetarium package so
        // they automatically pick up the new value.
        ref.read(planetariumEffectiveHorizonDegProvider.notifier).state =
            settings.effectiveHorizonDeg;

        // Also sync to Rust backend for astronomical calculations
        await _syncLocationToBackend(
            ref, settings.latitude, settings.longitude, settings.elevation);
      });
    });
  });

  // Handle initial value if settings are already loaded.
  //
  // This pushes unconditionally, exactly as the listener above does. Gating it
  // on "not 0/0" made the planetarium observer depend on whether any settings
  // change had fired yet: before one, it held the package's Los Angeles
  // constructor default; after one, the 0/0 sentinel. Both are wrong for an
  // unconfigured site and neither is distinguishable from a real site, so the
  // two paths agree on one value instead.
  //
  // "Is there a site at all" is not this provider's question to answer —
  // `observerLocationProvider` is non-nullable geometry. Surfaces that must
  // not invent a night gate on `observingSiteProvider` /
  // `appObserverLocationProvider`, which return null at the 0/0 sentinel.
  final settingsAsync = ref.read(appSettingsProvider);
  settingsAsync.whenData((settings) {
    Future.microtask(() async {
      ref.read(observerLocationProvider.notifier).setLocation(
            latitude: settings.latitude,
            longitude: settings.longitude,
            elevation: settings.elevation,
          );
      ref.read(planetariumEffectiveHorizonDegProvider.notifier).state =
          settings.effectiveHorizonDeg;

      await _syncLocationToBackend(
          ref, settings.latitude, settings.longitude, settings.elevation);
    });
  });
});

/// Sync location to the Rust backend (for Provider ref)
Future<void> _syncLocationToBackend(
    Ref ref, double latitude, double longitude, double elevation) async {
  try {
    final backend = ref.read(profileSettingsBackendProvider);
    developer.log(
        'Syncing observer location to Rust backend: lat=$latitude, lon=$longitude, elev=$elevation',
        name: 'LocationSync');
    await backend.setLocation(ObserverLocation(
      latitude: latitude,
      longitude: longitude,
      elevation: elevation,
    ));
    developer.log('Observer location synced successfully to Rust backend',
        name: 'LocationSync');
  } catch (e, stackTrace) {
    developer.log('Failed to sync observer location to Rust backend: $e',
        name: 'LocationSync', error: e, stackTrace: stackTrace);
  }
}
