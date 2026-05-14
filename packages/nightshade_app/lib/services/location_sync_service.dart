import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

/// Provider that watches settings and syncs to planetarium provider and Rust backend
/// This ensures settings is the source of truth - changes in settings automatically update planetarium and Rust
/// Uses ref.listen to avoid modifying providers during build
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

        // Also sync to Rust backend for astronomical calculations
        await _syncLocationToBackend(ref, settings.latitude, settings.longitude, settings.elevation);
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
        await _syncLocationToBackend(ref, settings.latitude, settings.longitude, settings.elevation);
      });
    }
  });
});

/// Sync location to the Rust backend (for Provider ref)
Future<void> _syncLocationToBackend(Ref ref, double latitude, double longitude, double elevation) async {
  try {
    final backend = ref.read(backendProvider);
    developer.log('Syncing observer location to Rust backend: lat=$latitude, lon=$longitude, elev=$elevation',
        name: 'LocationSync');
    await backend.setLocation(ObserverLocation(
      latitude: latitude,
      longitude: longitude,
      elevation: elevation,
    ));
    developer.log('Observer location synced successfully to Rust backend', name: 'LocationSync');
  } catch (e, stackTrace) {
    developer.log('Failed to sync observer location to Rust backend: $e',
        name: 'LocationSync', error: e, stackTrace: stackTrace);
  }
}

/// Sync location to the Rust backend (for WidgetRef)
Future<void> _syncLocationToBackendWidget(WidgetRef ref, double latitude, double longitude, double elevation) async {
  try {
    final backend = ref.read(backendProvider);
    developer.log('Syncing observer location to Rust backend (widget): lat=$latitude, lon=$longitude, elev=$elevation',
        name: 'LocationSync');
    await backend.setLocation(ObserverLocation(
      latitude: latitude,
      longitude: longitude,
      elevation: elevation,
    ));
    developer.log('Observer location synced successfully to Rust backend (widget)', name: 'LocationSync');
  } catch (e, stackTrace) {
    developer.log('Failed to sync observer location to Rust backend (widget): $e',
        name: 'LocationSync', error: e, stackTrace: stackTrace);
  }
}

/// Service to sync location between settings and planetarium provider
class LocationSyncService {
  /// Initialize location on app startup
  /// 1. Check if location exists in settings
  /// 2. If not, fetch from IP geolocation and save to settings
  /// 3. The locationSyncProvider will automatically sync to planetarium
  static Future<void> initializeLocation(WidgetRef ref) async {
    try {
      // Wait a bit for providers to initialize
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Get settings
      final settingsAsync = ref.read(appSettingsProvider);
      await settingsAsync.when(
        data: (settings) async {
          // Check if we have a valid location in settings
          final hasLocation = settings.latitude != 0.0 || settings.longitude != 0.0;
          
          if (!hasLocation) {
            // Fetch location from IP and save to settings
            final location = await GeolocationService.fetchLocation();
            if (location != null) {
              final (lat, lon, locationName) = location;
              
              // Save to settings - locationSyncProvider will automatically sync to planetarium
              final notifier = ref.read(appSettingsProvider.notifier);
              await notifier.setLatitude(lat);
              await notifier.setLongitude(lon);
              
              // Also directly sync to planetarium provider immediately
              ref.read(observerLocationProvider.notifier).setLocation(
                latitude: lat,
                longitude: lon,
                locationName: locationName,
              );

              // Sync to Rust backend
              await _syncLocationToBackendWidget(ref, lat, lon, 0.0);
            }
          } else {
            // If location exists, sync it to planetarium provider immediately
            ref.read(observerLocationProvider.notifier).setLocation(
              latitude: settings.latitude,
              longitude: settings.longitude,
              elevation: settings.elevation,
            );

            // Sync to Rust backend
            await _syncLocationToBackendWidget(ref, settings.latitude, settings.longitude, settings.elevation);
          }
        },
        loading: () async {
          // Wait for settings to load
          await Future.delayed(const Duration(milliseconds: 500));
          // Retry once
          final settingsAsync2 = ref.read(appSettingsProvider);
          await settingsAsync2.when(
            data: (settings) async {
              final hasLocation = settings.latitude != 0.0 || settings.longitude != 0.0;
              if (!hasLocation) {
                final location = await GeolocationService.fetchLocation();
                if (location != null) {
                  final (lat, lon, locationName) = location;
                  final notifier = ref.read(appSettingsProvider.notifier);
                  await notifier.setLatitude(lat);
                  await notifier.setLongitude(lon);
                  ref.read(observerLocationProvider.notifier).setLocation(
                    latitude: lat,
                    longitude: lon,
                    locationName: locationName,
                  );
                  // Sync to Rust backend
                  await _syncLocationToBackendWidget(ref, lat, lon, 0.0);
                }
              } else {
                ref.read(observerLocationProvider.notifier).setLocation(
                  latitude: settings.latitude,
                  longitude: settings.longitude,
                  elevation: settings.elevation,
                );
                // Sync to Rust backend
                await _syncLocationToBackendWidget(ref, settings.latitude, settings.longitude, settings.elevation);
              }
            },
            loading: () {},
            error: (_, __) {},
          );
        },
        error: (_, __) {},
      );
    } catch (e) {
      // Silently fail - location will use defaults
      developer.log('Location initialization failed: $e', name: 'LocationSync');
    }
  }
}

