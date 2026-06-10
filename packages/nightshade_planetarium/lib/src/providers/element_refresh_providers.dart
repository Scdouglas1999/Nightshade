import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalogs/minor_planet_catalog.dart';
import '../services/element_refresh_service.dart';

// ============================================================================
// Live MPC orbital-element refresh
// ============================================================================

/// The element-refresh service over the shared catalog directory.
final elementRefreshServiceProvider = Provider<ElementRefreshService>((ref) {
  return ElementRefreshService();
});

/// Persisted refresh configuration (URLs, schedule). Bumping
/// [elementRefreshReloadProvider] re-reads it after a settings change.
final elementRefreshConfigProvider =
    FutureProvider<ElementRefreshConfig>((ref) async {
  ref.watch(elementRefreshReloadProvider);
  return ref.watch(elementRefreshServiceProvider).loadConfig();
});

/// Increment to force the cached-element + config providers to re-read.
final elementRefreshReloadProvider = StateProvider<int>((ref) => 0);

/// The cached refreshed element sets (offline-safe, never touches the network).
/// Empty until a refresh has been run at least once.
final cachedRefreshedElementsProvider =
    FutureProvider<RefreshedElements>((ref) async {
  ref.watch(elementRefreshReloadProvider);
  return ref.watch(elementRefreshServiceProvider).loadCached();
});

/// The minor-body element set the rest of the app should propagate: the live
/// refreshed sets when present, otherwise the bundled [MinorPlanetCatalog].
///
/// Refreshed asteroids/comets are unioned with the bundled bright bodies and
/// de-duplicated by name, so a successful refresh strictly *adds* objects (and
/// supersedes a bundled body's stale elements with the fresh ones) — it never
/// drops the bundled set, which keeps the planetarium populated offline before
/// any refresh has run.
final effectiveMinorBodyElementsProvider =
    Provider<List<MinorBodyElements>>((ref) {
  final cached = ref.watch(cachedRefreshedElementsProvider).valueOrNull;
  if (cached == null || cached.isEmpty) {
    return MinorPlanetCatalog.all;
  }

  // Fresh elements win on name collision; bundled bodies fill the rest.
  final byName = <String, MinorBodyElements>{};
  for (final b in MinorPlanetCatalog.all) {
    byName[_normName(b.commonName ?? b.name)] = b;
  }
  for (final b in cached.all) {
    byName[_normName(b.commonName ?? b.name)] = b;
  }
  return byName.values.toList(growable: false);
});

String _normName(String s) => s.toLowerCase().trim();

/// "Last updated" indicator state for the refresh UI.
class ElementRefreshStatus {
  final DateTime? asteroidsFetchedAt;
  final DateTime? cometsFetchedAt;
  final int asteroidCount;
  final int cometCount;
  final bool isRefreshing;
  final String? error;

  const ElementRefreshStatus({
    this.asteroidsFetchedAt,
    this.cometsFetchedAt,
    this.asteroidCount = 0,
    this.cometCount = 0,
    this.isRefreshing = false,
    this.error,
  });

  DateTime? get lastUpdated {
    final t = [
      if (asteroidsFetchedAt != null) asteroidsFetchedAt!,
      if (cometsFetchedAt != null) cometsFetchedAt!,
    ]..sort();
    return t.isEmpty ? null : t.last;
  }

  bool get hasData => asteroidCount > 0 || cometCount > 0;

  ElementRefreshStatus copyWith({
    DateTime? asteroidsFetchedAt,
    DateTime? cometsFetchedAt,
    int? asteroidCount,
    int? cometCount,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
  }) =>
      ElementRefreshStatus(
        asteroidsFetchedAt: asteroidsFetchedAt ?? this.asteroidsFetchedAt,
        cometsFetchedAt: cometsFetchedAt ?? this.cometsFetchedAt,
        asteroidCount: asteroidCount ?? this.asteroidCount,
        cometCount: cometCount ?? this.cometCount,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Drives manual + scheduled refreshes and exposes the "last updated" status.
///
/// On construction it loads the cache (no network) and, if the cached data is
/// stale per the configured schedule, kicks off a single background refresh.
/// Manual [refresh] is always available.
class ElementRefreshController extends StateNotifier<ElementRefreshStatus> {
  final Ref _ref;

  ElementRefreshController(this._ref) : super(const ElementRefreshStatus()) {
    _init();
  }

  Future<void> _init() async {
    final service = _ref.read(elementRefreshServiceProvider);
    final cached = await service.loadCached();
    if (!mounted) return;
    _applyResult(cached);

    final config = await service.loadConfig();
    if (!mounted) return;
    if (service.isStale(cached, config)) {
      // Auto-refresh on the schedule, but only one attempt — failures fall
      // back to the (possibly empty) cache and surface in [state.error].
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (state.isRefreshing) return;
    state = state.copyWith(isRefreshing: true, clearError: true);
    final service = _ref.read(elementRefreshServiceProvider);
    try {
      final result = await service.refresh();
      if (!mounted) return;
      _applyResult(result);
      // Let consumers (propagation, search) pick up the new disk cache.
      _ref.read(elementRefreshReloadProvider.notifier).state++;
    } catch (e) {
      developer.log('[ElementRefresh] refresh failed: $e',
          name: 'ElementRefreshProviders', level: 900, error: e);
      if (!mounted) return;
      state = state.copyWith(isRefreshing: false, error: '$e');
    }
  }

  void _applyResult(RefreshedElements r) {
    state = ElementRefreshStatus(
      asteroidsFetchedAt: r.asteroidsFetchedAt,
      cometsFetchedAt: r.cometsFetchedAt,
      asteroidCount: r.asteroids.length,
      cometCount: r.comets.length,
      isRefreshing: false,
    );
  }
}

final elementRefreshControllerProvider =
    StateNotifierProvider<ElementRefreshController, ElementRefreshStatus>((ref) {
  return ElementRefreshController(ref);
});
