import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

/// Provider that watches settings and syncs to planetarium provider and Rust backend
/// This ensures settings is the source of truth - changes in settings automatically update planetarium and Rust
/// Uses ref.listen to avoid modifying providers during build
final locationSyncProvider = Provider<void>((ref) {
  // First-launch auto-detect: if the user has never set a location (lat/lon
  // are both 0), fetch an approximate position from IP geolocation once and
  // persist it. Guarded so it runs at most once per app session and never
  // overwrites a real location. Both desktop (app.dart) and mobile
  // (main.dart) watch this provider, so wiring it here covers both.
  var autoDetectAttempted = false;
  Future<void> maybeAutoDetectLocation(AppSettingsState settings) async {
    if (autoDetectAttempted) return;
    if (settings.latitude != 0.0 || settings.longitude != 0.0) return;
    autoDetectAttempted = true;
    final location = await GeolocationService.fetchLocation();
    if (location == null) return;
    final (lat, lon, _) = location;
    // Re-check: the user may have entered a location while the network call
    // was in flight.
    final current = ref.read(appSettingsProvider).valueOrNull;
    if (current != null &&
        (current.latitude != 0.0 || current.longitude != 0.0)) {
      return;
    }
    final notifier = ref.read(appSettingsProvider.notifier);
    await notifier.setLatitude(lat);
    await notifier.setLongitude(lon);
    // The persisted change flows back through the listener below, which syncs
    // the planetarium provider and the Rust backend.
  }

  // Use ref.listen to sync settings to planetarium provider and Rust backend whenever settings change
  // This defers the update until after the build phase, avoiding the Riverpod error
  ref.listen(appSettingsProvider, (previous, next) {
    next.whenData((settings) {
      unawaited(maybeAutoDetectLocation(settings));
      // Schedule the update for after the current build phase
      Future.microtask(() async {
        // Update planetarium provider with settings location
        // This is a temporary update (doesn't persist) - only settings persists
        ref.read(observerLocationProvider.notifier).setLocation(
              latitude: settings.latitude,
              longitude: settings.longitude,
              elevation: settings.elevation,
            );

        // Wave 1.5 Pack D: bridge effectiveHorizonDeg into the planetarium
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

  // Handle initial value if settings are already loaded
  final settingsAsync = ref.read(appSettingsProvider);
  settingsAsync.whenData((settings) {
    // Only sync if we have a valid location
    if (settings.latitude != 0.0 || settings.longitude != 0.0) {
      Future.microtask(() async {
        ref.read(observerLocationProvider.notifier).setLocation(
              latitude: settings.latitude,
              longitude: settings.longitude,
              elevation: settings.elevation,
            );

        // Also sync to Rust backend
        await _syncLocationToBackend(
            ref, settings.latitude, settings.longitude, settings.elevation);
      });
    } else {
      // No location set yet — auto-detect from IP on this first launch.
      unawaited(maybeAutoDetectLocation(settings));
    }
    // Effective horizon must sync even when location is 0/0 (e.g. user
    // hasn't set location yet but did set the horizon).
    Future.microtask(() {
      ref.read(planetariumEffectiveHorizonDegProvider.notifier).state =
          settings.effectiveHorizonDeg;
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
