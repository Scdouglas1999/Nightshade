import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../astronomy/sgp4.dart';
import '../catalogs/satellite_catalog.dart';
import 'planetarium_providers.dart';

// ============================================================================
// Satellite Toggle Provider
// ============================================================================

/// Whether satellite overlay is enabled
final showSatellitesProvider = StateProvider<bool>((ref) => false);

// ============================================================================
// Satellite Catalog Provider
// ============================================================================

/// Singleton satellite catalog instance for TLE management
final satelliteCatalogProvider = Provider<SatelliteCatalog>((ref) {
  return SatelliteCatalog();
});

// ============================================================================
// TLE Data Provider
// ============================================================================

/// Loads bright satellite TLE data. Auto-refreshes when toggled on.
final satelliteTleProvider = FutureProvider<List<OrbitalElements>>((ref) async {
  final showSatellites = ref.watch(showSatellitesProvider);
  if (!showSatellites) return [];

  final catalog = ref.read(satelliteCatalogProvider);
  try {
    return await catalog.loadBrightSatellites();
  } catch (e) {
    debugPrint('[Satellite] Failed to load TLE data: $e');
    rethrow;
  }
});

// ============================================================================
// Current Satellite Positions Provider
// ============================================================================

/// Satellite position state that updates every few seconds.
class SatellitePositionState {
  final List<SatelliteData> satellites;
  final DateTime lastUpdate;

  const SatellitePositionState({
    this.satellites = const [],
    required this.lastUpdate,
  });
}

/// Notifier that periodically recomputes satellite positions.
class SatellitePositionNotifier extends StateNotifier<SatellitePositionState> {
  final Ref _ref;
  Timer? _timer;

  SatellitePositionNotifier(this._ref)
      : super(SatellitePositionState(lastUpdate: DateTime.now())) {
    _startUpdates();

    // Listen for TLE data changes
    _ref.listen(satelliteTleProvider, (prev, next) {
      next.whenData((_) => _updatePositions());
    });

    // Listen for satellite toggle
    _ref.listen(showSatellitesProvider, (prev, next) {
      if (next) {
        _startUpdates();
      } else {
        _stopUpdates();
        state = SatellitePositionState(satellites: const [], lastUpdate: DateTime.now());
      }
    });
  }

  void _startUpdates() {
    _timer?.cancel();
    // Update every 2 seconds for smooth satellite motion
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      _updatePositions();
    });
    // Also do an initial update
    _updatePositions();
  }

  void _stopUpdates() {
    _timer?.cancel();
    _timer = null;
  }

  void _updatePositions() {
    if (!mounted) return;

    final showSatellites = _ref.read(showSatellitesProvider);
    if (!showSatellites) return;

    final tleData = _ref.read(satelliteTleProvider);
    final elements = tleData.valueOrNull;
    if (elements == null || elements.isEmpty) return;

    final location = _ref.read(observerLocationProvider);
    final timeState = _ref.read(observationTimeProvider);

    final satellites = SatelliteCatalog.computePositions(
      elements: elements,
      time: timeState.time,
      observerLatitude: location.latitude,
      observerLongitude: location.longitude,
    );

    if (!mounted) return;
    state = SatellitePositionState(
      satellites: satellites,
      lastUpdate: DateTime.now(),
    );
  }

  /// Force an immediate position update.
  void refresh() {
    _updatePositions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final satellitePositionProvider =
    StateNotifierProvider<SatellitePositionNotifier, SatellitePositionState>((ref) {
  return SatellitePositionNotifier(ref);
});

/// Convenience provider for just the satellite list.
final currentSatellitesProvider = Provider<List<SatelliteData>>((ref) {
  return ref.watch(satellitePositionProvider).satellites;
});

/// Provider for only visible (above horizon, illuminated) satellites.
final visibleSatellitesProvider = Provider<List<SatelliteData>>((ref) {
  final satellites = ref.watch(currentSatellitesProvider);
  return satellites.where((s) => s.isVisible).toList();
});

// ============================================================================
// Pass Prediction Provider
// ============================================================================

/// State for satellite pass predictions.
class PassPredictionState {
  final List<SatellitePass> passes;
  final bool isComputing;
  final String? error;

  const PassPredictionState({
    this.passes = const [],
    this.isComputing = false,
    this.error,
  });
}

/// Computes satellite pass predictions in the background.
class PassPredictionNotifier extends StateNotifier<PassPredictionState> {
  final Ref _ref;

  PassPredictionNotifier(this._ref) : super(const PassPredictionState());

  /// Compute pass predictions for all loaded satellites.
  /// This can take several seconds for many satellites, so runs in isolate.
  Future<void> computePasses({Duration predictionWindow = const Duration(hours: 48)}) async {
    if (!mounted) return;

    final tleData = _ref.read(satelliteTleProvider);
    final elements = tleData.valueOrNull;
    if (elements == null || elements.isEmpty) {
      state = const PassPredictionState(error: 'No satellite data loaded');
      return;
    }

    final location = _ref.read(observerLocationProvider);

    state = const PassPredictionState(isComputing: true);

    try {
      final passes = await compute(
        _computePassesIsolate,
        _ComputePassesArgs(
          elements: elements,
          latitude: location.latitude,
          longitude: location.longitude,
          startTime: DateTime.now().toUtc(),
          durationHours: predictionWindow.inHours,
        ),
      );

      if (!mounted) return;
      state = PassPredictionState(passes: passes);
    } catch (e) {
      if (!mounted) return;
      state = PassPredictionState(error: 'Pass prediction failed: $e');
    }
  }
}

/// Arguments for isolate computation.
class _ComputePassesArgs {
  final List<OrbitalElements> elements;
  final double latitude;
  final double longitude;
  final DateTime startTime;
  final int durationHours;

  _ComputePassesArgs({
    required this.elements,
    required this.latitude,
    required this.longitude,
    required this.startTime,
    required this.durationHours,
  });
}

/// Isolate function for pass prediction (CPU-intensive).
List<SatellitePass> _computePassesIsolate(_ComputePassesArgs args) {
  final allPasses = <SatellitePass>[];

  for (final elem in args.elements) {
    final passes = SatelliteCatalog.predictPasses(
      elements: elem,
      latitude: args.latitude,
      longitude: args.longitude,
      startTime: args.startTime,
      duration: Duration(hours: args.durationHours),
      minElevation: 10.0, // Only include passes with max elev > 10 degrees
    );
    allPasses.addAll(passes);
  }

  // Sort all passes by rise time
  allPasses.sort((a, b) => a.riseTime.compareTo(b.riseTime));
  return allPasses;
}

final passPredictionProvider =
    StateNotifierProvider<PassPredictionNotifier, PassPredictionState>((ref) {
  return PassPredictionNotifier(ref);
});

/// Provider for upcoming passes (future only).
final upcomingPassesProvider = Provider<List<SatellitePass>>((ref) {
  final state = ref.watch(passPredictionProvider);
  final now = DateTime.now();
  return state.passes.where((p) => p.setTime.isAfter(now)).toList();
});
