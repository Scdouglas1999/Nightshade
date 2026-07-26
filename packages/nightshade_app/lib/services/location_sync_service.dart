import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

/// Mirrors the persisted observer location into the planetarium provider and the
/// Rust backend. Settings is the single source of truth; this only fans changes
/// out. Uses `ref.listen` to avoid modifying providers during build.
///
/// This deliberately does **not** auto-detect a location on first launch. It used
/// to: with lat/lon at 0/0 it fetched an IP-geolocation estimate and persisted it
/// as the observing site before the user had seen, let alone approved, it. That
/// is unsafe in a way the user cannot see. Free IP services resolve to the ISP's
/// egress point and disagree with each other — two virgin launches minutes apart
/// on one machine recorded sites ~180 km apart — yet the dashboard then reports
/// twilight times, the astro-dark countdown, and the imaging window off that
/// guess with no hint that anything is approximate, and the summary screen shows
/// it exactly as it shows a site the user typed.
///
/// 0/0 is the designed "not set" sentinel and every location-driven surface
/// already has an honest empty state for it, so leaving it alone until the user
/// acts is both safer and less code. The estimate is still one click away: the
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
