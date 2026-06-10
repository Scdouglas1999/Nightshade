import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_layout.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_layout_provider.dart';
import 'package:nightshade_app/screens/dashboard/widgets/dashboard_widget_registry.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The settings key the dashboard layout persists under. Mirrors the private
/// `_dashboardLayoutKey` in dashboard_layout_provider.dart.
const _dashboardLayoutKey = 'dashboard_layout_v1';

/// The cockpit panel ids — the two merged density-pass tiles plus the 14
/// individual panels.
const _cockpitIds = <DashboardWidgetId>[
  DashboardWidgetId.cockpitNowImaging,
  DashboardWidgetId.cockpitFrames,
  DashboardWidgetId.cockpitTargetHeader,
  DashboardWidgetId.cockpitLiveFrame,
  DashboardWidgetId.cockpitExposureProgress,
  DashboardWidgetId.cockpitRecentFrames,
  DashboardWidgetId.cockpitFilterIntegration,
  DashboardWidgetId.cockpitEquipmentTelemetry,
  DashboardWidgetId.cockpitGuiding,
  DashboardWidgetId.cockpitWeatherSafety,
  DashboardWidgetId.cockpitSessionWarnings,
  DashboardWidgetId.cockpitTriggerFeed,
  DashboardWidgetId.cockpitScheduler,
  DashboardWidgetId.cockpitCloudMotion,
  DashboardWidgetId.cockpitAdaptiveConditions,
  DashboardWidgetId.cockpitLightCurve,
];

/// The four individual cockpit panels superseded by the merged tiles. Present
/// in the layout but disabled by default in v5.
const _supersededIds = <DashboardWidgetId>[
  DashboardWidgetId.cockpitTargetHeader,
  DashboardWidgetId.cockpitLiveFrame,
  DashboardWidgetId.cockpitExposureProgress,
  DashboardWidgetId.cockpitRecentFrames,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DashboardWidgetId storage round-trip', () {
    test('storageKey/fromStorageKey round-trips for every id (incl. cockpit)',
        () {
      // If a new enum value is added without extending both switches, one of
      // these calls throws — this is the guard that keeps saved layouts safe.
      for (final id in DashboardWidgetId.values) {
        final key = id.storageKey;
        expect(DashboardWidgetIdX.fromStorageKey(key), id,
            reason: 'storageKey "$key" must round-trip back to $id.');
      }
    });

    test('each cockpit id has a unique, non-empty storage key', () {
      final keys = <String>{};
      for (final id in _cockpitIds) {
        final key = id.storageKey;
        expect(key, isNotEmpty);
        expect(keys.add(key), isTrue,
            reason: 'Cockpit storage key "$key" must be unique.');
      }
    });

    test('fromStorageKey throws on an unknown id', () {
      expect(
        () => DashboardWidgetIdX.fromStorageKey('definitelyNotAWidget'),
        throwsFormatException,
      );
    });
  });

  group('DashboardLayout.defaultLayout (v5 dense cockpit default)', () {
    test('is version 5', () {
      expect(DashboardLayout.currentVersion, 5);
      expect(DashboardLayout.defaultLayout().version, 5);
    });

    test('enables exactly the dense merged cockpit set', () {
      final layout = DashboardLayout.defaultLayout();
      final enabledIds =
          layout.tiles.where((t) => t.enabled).map((t) => t.widgetId).toSet();

      // The dense default: the merged now-imaging + frames tiles and guiding
      // up top, supporting telemetry on the right rail. The superseded panels,
      // the opt-in cockpit extras, and ALL legacy cards are off.
      expect(
        enabledIds,
        unorderedEquals(<DashboardWidgetId>{
          DashboardWidgetId.cockpitNowImaging,
          DashboardWidgetId.cockpitFrames,
          DashboardWidgetId.cockpitGuiding,
          DashboardWidgetId.cockpitEquipmentTelemetry,
          DashboardWidgetId.cockpitWeatherSafety,
          DashboardWidgetId.cockpitTriggerFeed,
        }),
      );
    });

    test('keeps the four superseded panels present but disabled', () {
      final layout = DashboardLayout.defaultLayout();
      for (final id in _supersededIds) {
        final tile = layout.tiles.firstWhere((t) => t.widgetId == id,
            orElse: () => fail('Superseded id $id must remain present.'));
        expect(tile.enabled, isFalse,
            reason: 'Superseded panel $id is disabled in the v5 default.');
      }
    });

    test('keeps every legacy card present but disabled by default', () {
      final layout = DashboardLayout.defaultLayout();
      const legacyIds = <DashboardWidgetId>[
        DashboardWidgetId.livePreview,
        DashboardWidgetId.captureSettings,
        DashboardWidgetId.sequenceStatus,
        DashboardWidgetId.guiding,
        DashboardWidgetId.mountControl,
        DashboardWidgetId.equipmentStatus,
        DashboardWidgetId.weather,
        DashboardWidgetId.focus,
        DashboardWidgetId.alerts,
        DashboardWidgetId.quickActions,
        DashboardWidgetId.quickStats,
        DashboardWidgetId.tonight,
        DashboardWidgetId.storage,
      ];
      for (final id in legacyIds) {
        final tile =
            layout.tiles.firstWhere((t) => t.widgetId == id, orElse: () {
          fail('Legacy id $id must remain present in the default layout.');
        });
        expect(tile.enabled, isFalse,
            reason: 'Legacy card $id must be disabled by default in v4.');
      }
    });

    test('every tile has a unique order', () {
      final layout = DashboardLayout.defaultLayout();
      final orders = layout.tiles.map((t) => t.order).toList();
      expect(orders.toSet().length, orders.length,
          reason: 'Tile orders must be unique.');
    });

    test('hero merged cockpit tiles use the large tile size', () {
      final layout = DashboardLayout.defaultLayout();
      DashboardTileConfig tileFor(DashboardWidgetId id) =>
          layout.tiles.firstWhere((t) => t.widgetId == id);
      expect(tileFor(DashboardWidgetId.cockpitNowImaging).size,
          DashboardTileSize.large);
      expect(tileFor(DashboardWidgetId.cockpitFrames).size,
          DashboardTileSize.large);
    });

    test(
        'merged now-imaging + frames lead the primary zone, frames after '
        'now-imaging', () {
      final layout = DashboardLayout.defaultLayout();
      DashboardTileConfig tileFor(DashboardWidgetId id) =>
          layout.tiles.firstWhere((t) => t.widgetId == id);

      final nowImaging = tileFor(DashboardWidgetId.cockpitNowImaging);
      final frames = tileFor(DashboardWidgetId.cockpitFrames);

      expect(nowImaging.enabled, isTrue);
      expect(frames.enabled, isTrue);
      expect(nowImaging.zone, DashboardZone.primary);
      expect(frames.zone, DashboardZone.primary);
      expect(nowImaging.order, 0,
          reason: 'Now-imaging is the lead tile in the dense default.');
      expect(frames.order, nowImaging.order + 1,
          reason: 'Frames is ordered directly after now-imaging.');
    });

    test('recent-frames is no longer enabled by default', () {
      final layout = DashboardLayout.defaultLayout();
      final recent = layout.tiles.firstWhere(
          (t) => t.widgetId == DashboardWidgetId.cockpitRecentFrames);
      expect(recent.enabled, isFalse,
          reason:
              'Recent-frames is folded into cockpitFrames and off by default.');
    });
  });

  group('DashboardWidgetDefinition.selfChromed', () {
    final registry = {for (final d in dashboardWidgetRegistry) d.id: d};

    test('every cockpit panel definition is self-chromed', () {
      for (final id in _cockpitIds) {
        final def = registry[id];
        expect(def, isNotNull,
            reason: 'Cockpit id $id must have a registry definition.');
        expect(def!.selfChromed, isTrue,
            reason: 'Cockpit panel $id provides its own chrome.');
      }
    });

    test('legacy card definitions default selfChromed to false', () {
      const legacyIds = <DashboardWidgetId>[
        DashboardWidgetId.livePreview,
        DashboardWidgetId.captureSettings,
        DashboardWidgetId.sequenceStatus,
        DashboardWidgetId.guiding,
        DashboardWidgetId.mountControl,
        DashboardWidgetId.equipmentStatus,
        DashboardWidgetId.weather,
        DashboardWidgetId.focus,
        DashboardWidgetId.alerts,
        DashboardWidgetId.quickActions,
        DashboardWidgetId.quickStats,
        DashboardWidgetId.tonight,
        DashboardWidgetId.storage,
      ];
      for (final id in legacyIds) {
        expect(registry[id]!.selfChromed, isFalse,
            reason: 'Legacy card $id must not claim its own chrome.');
      }
    });

    test('a definition without selfChromed defaults to false', () {
      const def = DashboardWidgetDefinition(
        id: DashboardWidgetId.livePreview,
        title: 't',
        subtitle: 's',
        icon: LucideIcons.image,
        defaultZone: DashboardZone.primary,
        builder: _noopBuilder,
      );
      expect(def.selfChromed, isFalse);
    });
  });

  group('v3/v4 -> v5 migration', () {
    late NightshadeDatabase database;

    setUp(() {
      database = NightshadeDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    /// Persist an older-version layout under the dashboard key, then read
    /// [dashboardLayoutProvider] which must migrate it to v5.
    Future<DashboardLayout> migrate(Map<String, dynamic> stored) async {
      await SettingsDao(database)
          .setSetting(_dashboardLayoutKey, jsonEncode(stored));

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      addTearDown(container.dispose);

      return container.read(dashboardLayoutProvider.future);
    }

    test('moves the user onto the dense default and bumps to v5', () async {
      // A representative v3 layout: the previous shipped default (live preview +
      // capture enabled, quick stats disabled).
      final storedV3 = {
        'version': 3,
        'secondaryZoneWidth': 0.4,
        'tiles': [
          {
            'id': 'livePreview',
            'size': 'large',
            'enabled': true,
            'order': 0,
            'zone': 'primary',
          },
          {
            'id': 'captureSettings',
            'size': 'medium',
            'enabled': true,
            'order': 1,
            'zone': 'primary',
          },
          {
            'id': 'guiding',
            'size': 'medium',
            'enabled': false,
            'order': 2,
            'zone': 'secondary',
          },
        ],
      };

      final migrated = await migrate(storedV3);

      expect(migrated.version, DashboardLayout.currentVersion);

      // The merged cockpit tiles were never in the v3 layout, so they take
      // their default enabled state — the dense hero tiles are now live.
      bool enabled(DashboardWidgetId id) =>
          migrated.tiles.any((t) => t.widgetId == id && t.enabled);
      expect(enabled(DashboardWidgetId.cockpitNowImaging), isTrue);
      expect(enabled(DashboardWidgetId.cockpitFrames), isTrue);
      expect(enabled(DashboardWidgetId.cockpitGuiding), isTrue);
    });

    test(
        'force-disables the four superseded panels even when a v4 user had '
        'them enabled', () async {
      // A v4 layout where all four superseded cockpit panels were enabled.
      // The migration must turn them OFF so the merged tiles don't double up.
      final storedV4 = {
        'version': 4,
        'secondaryZoneWidth': 0.4,
        'tiles': [
          {
            'id': 'cockpitTargetHeader',
            'size': 'large',
            'enabled': true,
            'order': 0,
            'zone': 'primary',
          },
          {
            'id': 'cockpitLiveFrame',
            'size': 'large',
            'enabled': true,
            'order': 1,
            'zone': 'primary',
          },
          {
            'id': 'cockpitExposureProgress',
            'size': 'medium',
            'enabled': true,
            'order': 2,
            'zone': 'primary',
          },
          {
            'id': 'cockpitRecentFrames',
            'size': 'large',
            'enabled': true,
            'order': 3,
            'zone': 'primary',
          },
        ],
      };

      final migrated = await migrate(storedV4);

      expect(migrated.version, DashboardLayout.currentVersion);

      DashboardTileConfig tileFor(DashboardWidgetId id) =>
          migrated.tiles.firstWhere((t) => t.widgetId == id);
      for (final id in _supersededIds) {
        expect(tileFor(id).enabled, isFalse,
            reason: 'Superseded panel $id must be force-disabled in v5.');
      }

      // And the merged tiles come in enabled from the defaults.
      expect(tileFor(DashboardWidgetId.cockpitNowImaging).enabled, isTrue);
      expect(tileFor(DashboardWidgetId.cockpitFrames).enabled, isTrue);
    });

    test('preserves the user enabled flag where ids overlap the default',
        () async {
      // User had storage explicitly OFF and tonight explicitly ON in v3. The
      // default has both OFF in v5; the migration must keep the user's choices.
      final storedV3 = {
        'version': 3,
        'secondaryZoneWidth': 0.4,
        'tiles': [
          {
            'id': 'storage',
            'size': 'small',
            'enabled': false,
            'order': 0,
            'zone': 'tertiary',
          },
          {
            'id': 'tonight',
            'size': 'small',
            'enabled': true,
            'order': 1,
            'zone': 'tertiary',
          },
        ],
      };

      final migrated = await migrate(storedV3);

      DashboardTileConfig tileFor(DashboardWidgetId id) =>
          migrated.tiles.firstWhere((t) => t.widgetId == id);

      expect(tileFor(DashboardWidgetId.storage).enabled, isFalse,
          reason: 'User had storage OFF; migration must keep it OFF.');
      expect(tileFor(DashboardWidgetId.tonight).enabled, isTrue,
          reason: 'User had tonight ON; migration must keep it ON.');
    });

    test('force-disables quick stats even if the user had it on', () async {
      final storedV3 = {
        'version': 3,
        'secondaryZoneWidth': 0.4,
        'tiles': [
          {
            'id': 'quickStats',
            'size': 'small',
            'enabled': true,
            'order': 0,
            'zone': 'tertiary',
          },
        ],
      };

      final migrated = await migrate(storedV3);

      final quickStats = migrated.tiles
          .firstWhere((t) => t.widgetId == DashboardWidgetId.quickStats);
      expect(quickStats.enabled, isFalse,
          reason: 'Quick Stats is force-disabled during migration.');
    });
  });
}

Widget _noopBuilder(
  BuildContext context,
  NightshadeColors colors,
  AnimationController pulseController,
) {
  return const SizedBox.shrink();
}
