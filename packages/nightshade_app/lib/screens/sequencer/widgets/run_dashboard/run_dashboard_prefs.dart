import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Identifies an individual panel on the Run dashboard so the visibility
/// preference can be persisted by stable key (not by display order).
///
/// New panels are added by extending this enum. Persisted JSON ignores
/// unknown keys, so removing a panel later won't break older databases.
enum RunDashboardPanelId {
  targetHeader,
  liveFrame,
  exposureProgress,
  filterIntegration,
  equipmentTelemetry,
  guidingGraph,
  weatherSafety,
  triggerFeed,
}

/// Immutable per-panel visibility state.
class RunDashboardPrefs {
  final Map<RunDashboardPanelId, bool> visibility;

  const RunDashboardPrefs(this.visibility);

  /// All panels visible by default. The dashboard would be nonsensical
  /// without the target header and live frame, so they remain user-toggleable
  /// (the user might prefer a "just guiding + telemetry" view).
  factory RunDashboardPrefs.defaults() {
    return RunDashboardPrefs({
      for (final id in RunDashboardPanelId.values) id: true,
    });
  }

  bool isVisible(RunDashboardPanelId id) => visibility[id] ?? true;

  RunDashboardPrefs withVisibility(RunDashboardPanelId id, bool visible) {
    final next = Map<RunDashboardPanelId, bool>.from(visibility);
    next[id] = visible;
    return RunDashboardPrefs(next);
  }

  Map<String, dynamic> toJson() => {
        'visibility': {
          for (final entry in visibility.entries) entry.key.name: entry.value,
        },
      };

  factory RunDashboardPrefs.fromJson(Map<String, dynamic> json) {
    final raw = json['visibility'];
    if (raw is! Map) {
      return RunDashboardPrefs.defaults();
    }
    final result = <RunDashboardPanelId, bool>{
      for (final id in RunDashboardPanelId.values) id: true,
    };
    for (final entry in raw.entries) {
      // Ignore unknown ids (forward-compat) — never silently default visible
      // to false, since that would hide a feature the user never opted out of.
      final id = RunDashboardPanelId.values.firstWhere(
        (p) => p.name == entry.key,
        orElse: () => RunDashboardPanelId.targetHeader,
      );
      if (id.name != entry.key) continue;
      final value = entry.value;
      if (value is! bool) continue;
      result[id] = value;
    }
    return RunDashboardPrefs(result);
  }
}

const _runDashboardPrefsKey = 'run_dashboard_prefs_v1';

/// Persisted Run-dashboard panel visibility preferences.
///
/// Backed by the same `settingsDaoProvider` pattern used by other settings
/// notifiers in the app. Errors during read/write surface as the Async error
/// state — silent fallbacks would mask schema issues per `CLAUDE.md` rules.
final runDashboardPrefsProvider =
    AsyncNotifierProvider<RunDashboardPrefsNotifier, RunDashboardPrefs>(() {
  return RunDashboardPrefsNotifier();
});

class RunDashboardPrefsNotifier extends AsyncNotifier<RunDashboardPrefs> {
  @override
  Future<RunDashboardPrefs> build() async {
    final dao = ref.read(settingsDaoProvider);
    final stored = await dao.getSetting(_runDashboardPrefsKey);
    if (stored == null || stored.trim().isEmpty) {
      return RunDashboardPrefs.defaults();
    }
    final decoded = jsonDecode(stored);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
          'Run-dashboard prefs JSON is not an object: $stored');
    }
    return RunDashboardPrefs.fromJson(decoded);
  }

  Future<void> setVisible(RunDashboardPanelId id, bool visible) async {
    final current = state.value ?? RunDashboardPrefs.defaults();
    final updated = current.withVisibility(id, visible);
    final dao = ref.read(settingsDaoProvider);
    await dao.setSetting(_runDashboardPrefsKey, jsonEncode(updated.toJson()));
    state = AsyncData(updated);
  }

  Future<void> resetToDefaults() async {
    final defaults = RunDashboardPrefs.defaults();
    final dao = ref.read(settingsDaoProvider);
    await dao.setSetting(_runDashboardPrefsKey, jsonEncode(defaults.toJson()));
    state = AsyncData(defaults);
  }
}

/// Lightweight UI metadata for the customize menu. Kept in the same file so
/// the enum, the persistence layer, and the display labels stay co-located.
class RunDashboardPanelDescriptor {
  final RunDashboardPanelId id;
  final String label;
  final String description;

  const RunDashboardPanelDescriptor({
    required this.id,
    required this.label,
    required this.description,
  });
}

const runDashboardPanelDescriptors = <RunDashboardPanelDescriptor>[
  RunDashboardPanelDescriptor(
    id: RunDashboardPanelId.targetHeader,
    label: 'Target header',
    description: 'Target name, RA/Dec, altitude, time-to-meridian',
  ),
  RunDashboardPanelDescriptor(
    id: RunDashboardPanelId.liveFrame,
    label: 'Live frame',
    description: 'Current image thumbnail',
  ),
  RunDashboardPanelDescriptor(
    id: RunDashboardPanelId.exposureProgress,
    label: 'Exposure progress',
    description: 'Current frame countdown and frame number',
  ),
  RunDashboardPanelDescriptor(
    id: RunDashboardPanelId.filterIntegration,
    label: 'Per-filter integration',
    description: 'Bar chart of accumulated time per filter',
  ),
  RunDashboardPanelDescriptor(
    id: RunDashboardPanelId.equipmentTelemetry,
    label: 'Equipment telemetry',
    description: 'Camera, mount, focuser, filter, rotator, guider state',
  ),
  RunDashboardPanelDescriptor(
    id: RunDashboardPanelId.guidingGraph,
    label: 'Guiding graph',
    description: 'RA/Dec drift trace',
  ),
  RunDashboardPanelDescriptor(
    id: RunDashboardPanelId.weatherSafety,
    label: 'Weather and safety',
    description: 'Active safety alerts and snooze status',
  ),
  RunDashboardPanelDescriptor(
    id: RunDashboardPanelId.triggerFeed,
    label: 'Trigger feed',
    description: 'Latest executor events with timestamps',
  ),
];
