import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

import 'dashboard_layout.dart';

const _dashboardLayoutKey = 'dashboard_layout_v1';

class DashboardLayoutNotifier extends AsyncNotifier<DashboardLayout> {
  @override
  Future<DashboardLayout> build() async {
    final dao = ref.read(settingsDaoProvider);
    final stored = await dao.getSetting(_dashboardLayoutKey);

    if (stored == null || stored.trim().isEmpty) {
      return DashboardLayout.defaultLayout();
    }

    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Dashboard layout must be a JSON object.');
      }
      final layout = DashboardLayout.fromJson(decoded);

      // Migrate v2 layouts to v3 by assigning zones based on widget defaults
      if (layout.version < DashboardLayout.currentVersion) {
        final migrated = _migrateToV3(layout);
        await _persist(migrated);
        return migrated;
      }

      return layout.mergeWithDefaults(DashboardLayout.defaultLayout());
    } catch (error) {
      throw FormatException('Failed to parse dashboard layout: $error');
    }
  }

  /// Migrate a v2 layout to v3 by preserving enabled/disabled state
  /// and assigning tiles to zones based on widget defaults.
  DashboardLayout _migrateToV3(DashboardLayout oldLayout) {
    final defaults = DashboardLayout.defaultLayout();
    final enabledMap = {for (final t in oldLayout.tiles) t.widgetId: t.enabled};

    // Preserve user's enabled/disabled choices, use default zone assignments
    // Exception: Quick Stats is now redundant with Command Bar, so disable it
    final tiles = defaults.tiles.map((tile) {
      var wasEnabled = enabledMap[tile.widgetId];

      // Force disable Quick Stats during migration - Command Bar now shows this
      if (tile.widgetId == DashboardWidgetId.quickStats) {
        wasEnabled = false;
      }

      return tile.copyWith(enabled: wasEnabled ?? tile.enabled);
    }).toList();

    return DashboardLayout(
      version: DashboardLayout.currentVersion,
      tiles: tiles,
      secondaryZoneWidth: 0.4,
    );
  }

  Future<void> resetLayout() async {
    final defaults = DashboardLayout.defaultLayout();
    await _persist(defaults);
    state = AsyncData(defaults);
  }

  Future<void> reorder(DashboardWidgetId dragged, DashboardWidgetId target) async {
    final layout = state.value;
    if (layout == null) {
      throw StateError('Dashboard layout not loaded yet.');
    }

    final tiles = [...layout.tiles];
    final fromIndex = tiles.indexWhere((tile) => tile.widgetId == dragged);
    final toIndex = tiles.indexWhere((tile) => tile.widgetId == target);

    if (fromIndex == -1 || toIndex == -1) {
      throw StateError('Dashboard layout missing tile for reorder.');
    }
    if (fromIndex == toIndex) {
      return;
    }

    final moved = tiles.removeAt(fromIndex);
    tiles.insert(toIndex, moved);

    final updated = layout.copyWith(tiles: tiles).normalize();
    await _persist(updated);
    state = AsyncData(updated);
  }

  /// Move a tile to a different zone
  Future<void> setTileZone(DashboardWidgetId id, DashboardZone zone) async {
    final layout = state.value;
    if (layout == null) {
      throw StateError('Dashboard layout not loaded yet.');
    }

    final tiles = layout.tiles
        .map((tile) => tile.widgetId == id ? tile.copyWith(zone: zone) : tile)
        .toList();

    if (!tiles.any((tile) => tile.widgetId == id)) {
      throw StateError('Dashboard layout missing tile for zone change.');
    }

    final updated = layout.copyWith(tiles: tiles).normalize();
    await _persist(updated);
    state = AsyncData(updated);
  }

  /// Update the secondary zone width (0.25 to 0.5)
  Future<void> setSecondaryZoneWidth(double width) async {
    final layout = state.value;
    if (layout == null) {
      throw StateError('Dashboard layout not loaded yet.');
    }

    final clampedWidth = width.clamp(0.25, 0.5);
    final updated = layout.copyWith(secondaryZoneWidth: clampedWidth);
    await _persist(updated);
    state = AsyncData(updated);
  }

  Future<void> setTileSize(DashboardWidgetId id, DashboardTileSize size) async {
    final layout = state.value;
    if (layout == null) {
      throw StateError('Dashboard layout not loaded yet.');
    }

    final tiles = layout.tiles
        .map((tile) => tile.widgetId == id ? tile.copyWith(size: size) : tile)
        .toList();

    if (!tiles.any((tile) => tile.widgetId == id)) {
      throw StateError('Dashboard layout missing tile for resize.');
    }

    final updated = layout.copyWith(tiles: tiles).normalize();
    await _persist(updated);
    state = AsyncData(updated);
  }

  Future<void> setTileEnabled(DashboardWidgetId id, bool enabled) async {
    final layout = state.value;
    if (layout == null) {
      throw StateError('Dashboard layout not loaded yet.');
    }

    final tiles = layout.tiles
        .map((tile) => tile.widgetId == id ? tile.copyWith(enabled: enabled) : tile)
        .toList();

    if (!tiles.any((tile) => tile.widgetId == id)) {
      throw StateError('Dashboard layout missing tile for enable.');
    }

    final updated = layout.copyWith(tiles: tiles).normalize();
    await _persist(updated);
    state = AsyncData(updated);
  }

  Future<void> _persist(DashboardLayout layout) async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setSetting(_dashboardLayoutKey, jsonEncode(layout.toJson()));
  }
}

// Why keep-alive (not autoDispose): the dashboard layout is a user
// preference persisted to the settings DAO; the async build() reads from
// SQLite and migrates v2 -> v3 layouts. Disposing on navigation would force
// every revisit (which happens on every app launch and tab switch) to
// re-run that I/O + migration, causing a visible flash of the default
// layout while loading. Memory cost is trivial (a single DashboardLayout
// value object), and writes flow through this notifier so a single
// authoritative copy is correct (audit-dart §1b).
final dashboardLayoutProvider =
    AsyncNotifierProvider<DashboardLayoutNotifier, DashboardLayout>(() {
  return DashboardLayoutNotifier();
});
