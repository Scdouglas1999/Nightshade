import 'package:flutter/foundation.dart';

/// Zone-based layout architecture for NINA-style command center design.
///
/// Layout structure:
/// - Primary: Main content area (live preview, capture controls) - 60%
/// - Secondary: Supporting info (sequence, guiding, equipment) - 40% resizable
/// - Tertiary: Bottom row compact widgets (mount, focus, weather)
enum DashboardZone {
  primary,
  secondary,
  tertiary,
}

extension DashboardZoneX on DashboardZone {
  String get storageKey {
    return switch (this) {
      DashboardZone.primary => 'primary',
      DashboardZone.secondary => 'secondary',
      DashboardZone.tertiary => 'tertiary',
    };
  }

  static DashboardZone fromStorageKey(String value) {
    return switch (value) {
      'primary' => DashboardZone.primary,
      'secondary' => DashboardZone.secondary,
      'tertiary' => DashboardZone.tertiary,
      _ => throw FormatException('Unknown dashboard zone: $value'),
    };
  }

  /// Get the default zone for a widget ID (used for migration from v2 layouts)
  static DashboardZone defaultForWidget(DashboardWidgetId widgetId) {
    return switch (widgetId) {
      // Primary zone: main content area (hero widgets)
      DashboardWidgetId.livePreview => DashboardZone.primary,
      DashboardWidgetId.captureSettings => DashboardZone.primary,

      // Secondary zone: supporting information and controls
      DashboardWidgetId.sequenceStatus => DashboardZone.secondary,
      DashboardWidgetId.guiding => DashboardZone.secondary,
      DashboardWidgetId.equipmentStatus => DashboardZone.secondary,
      DashboardWidgetId.quickActions => DashboardZone.secondary,

      // Tertiary zone: compact status widgets
      DashboardWidgetId.mountControl => DashboardZone.tertiary,
      DashboardWidgetId.focus => DashboardZone.tertiary,
      DashboardWidgetId.weather => DashboardZone.tertiary,
      DashboardWidgetId.tonight => DashboardZone.tertiary,
      DashboardWidgetId.alerts => DashboardZone.tertiary,
      DashboardWidgetId.quickStats => DashboardZone.tertiary,
      DashboardWidgetId.storage => DashboardZone.tertiary,
    };
  }
}

enum DashboardWidgetId {
  livePreview,
  captureSettings,
  sequenceStatus,
  guiding,
  mountControl,
  equipmentStatus,
  weather,
  focus,
  alerts,
  quickActions,
  quickStats,
  tonight,
  storage,
}

extension DashboardWidgetIdX on DashboardWidgetId {
  String get storageKey {
    return switch (this) {
      DashboardWidgetId.livePreview => 'livePreview',
      DashboardWidgetId.captureSettings => 'captureSettings',
      DashboardWidgetId.sequenceStatus => 'sequenceStatus',
      DashboardWidgetId.guiding => 'guiding',
      DashboardWidgetId.mountControl => 'mountControl',
      DashboardWidgetId.equipmentStatus => 'equipmentStatus',
      DashboardWidgetId.weather => 'weather',
      DashboardWidgetId.focus => 'focus',
      DashboardWidgetId.alerts => 'alerts',
      DashboardWidgetId.quickActions => 'quickActions',
      DashboardWidgetId.quickStats => 'quickStats',
      DashboardWidgetId.tonight => 'tonight',
      DashboardWidgetId.storage => 'storage',
    };
  }

  static DashboardWidgetId fromStorageKey(String value) {
    return switch (value) {
      'livePreview' => DashboardWidgetId.livePreview,
      'captureSettings' => DashboardWidgetId.captureSettings,
      'sequenceStatus' => DashboardWidgetId.sequenceStatus,
      'guiding' => DashboardWidgetId.guiding,
      'mountControl' => DashboardWidgetId.mountControl,
      'equipmentStatus' => DashboardWidgetId.equipmentStatus,
      'weather' => DashboardWidgetId.weather,
      'focus' => DashboardWidgetId.focus,
      'alerts' => DashboardWidgetId.alerts,
      'quickActions' => DashboardWidgetId.quickActions,
      'quickStats' => DashboardWidgetId.quickStats,
      'tonight' => DashboardWidgetId.tonight,
      'storage' => DashboardWidgetId.storage,
      _ => throw FormatException('Unknown dashboard widget id: $value'),
    };
  }
}

enum DashboardTileSize {
  small,
  medium,
  large,
}

extension DashboardTileSizeX on DashboardTileSize {
  String get storageKey {
    return switch (this) {
      DashboardTileSize.small => 'small',
      DashboardTileSize.medium => 'medium',
      DashboardTileSize.large => 'large',
    };
  }

  String get label {
    return switch (this) {
      DashboardTileSize.small => 'Small',
      DashboardTileSize.medium => 'Medium',
      DashboardTileSize.large => 'Large',
    };
  }

  int get span {
    return switch (this) {
      DashboardTileSize.small => 1,
      DashboardTileSize.medium => 2,
      DashboardTileSize.large => 3,
    };
  }

  DashboardTileSize next() {
    return switch (this) {
      DashboardTileSize.small => DashboardTileSize.medium,
      DashboardTileSize.medium => DashboardTileSize.large,
      DashboardTileSize.large => DashboardTileSize.small,
    };
  }

  static DashboardTileSize fromStorageKey(String value) {
    return switch (value) {
      'small' => DashboardTileSize.small,
      'medium' => DashboardTileSize.medium,
      'large' => DashboardTileSize.large,
      _ => throw FormatException('Unknown dashboard tile size: $value'),
    };
  }
}

@immutable
class DashboardTileConfig {
  final DashboardWidgetId widgetId;
  final DashboardTileSize size;
  final bool enabled;
  final int order;
  final DashboardZone zone;

  const DashboardTileConfig({
    required this.widgetId,
    required this.size,
    required this.enabled,
    required this.order,
    required this.zone,
  });

  DashboardTileConfig copyWith({
    DashboardWidgetId? widgetId,
    DashboardTileSize? size,
    bool? enabled,
    int? order,
    DashboardZone? zone,
  }) {
    return DashboardTileConfig(
      widgetId: widgetId ?? this.widgetId,
      size: size ?? this.size,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      zone: zone ?? this.zone,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': widgetId.storageKey,
      'size': size.storageKey,
      'enabled': enabled,
      'order': order,
      'zone': zone.storageKey,
    };
  }

  factory DashboardTileConfig.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final size = json['size'];
    final enabled = json['enabled'];
    final order = json['order'];
    final zone = json['zone'];

    if (id is! String) {
      throw const FormatException('Dashboard tile id must be a string.');
    }
    if (size is! String) {
      throw const FormatException('Dashboard tile size must be a string.');
    }
    if (enabled is! bool) {
      throw const FormatException('Dashboard tile enabled must be a boolean.');
    }
    if (order is! int) {
      throw const FormatException('Dashboard tile order must be an integer.');
    }

    final widgetId = DashboardWidgetIdX.fromStorageKey(id);

    // Zone is optional for v2 migration - infer from widget ID if missing
    DashboardZone parsedZone;
    if (zone is String) {
      parsedZone = DashboardZoneX.fromStorageKey(zone);
    } else {
      parsedZone = DashboardZoneX.defaultForWidget(widgetId);
    }

    return DashboardTileConfig(
      widgetId: widgetId,
      size: DashboardTileSizeX.fromStorageKey(size),
      enabled: enabled,
      order: order,
      zone: parsedZone,
    );
  }
}

@immutable
class DashboardLayout {
  /// Layout version 3: Zone-based architecture
  /// - Version 1: Initial layout
  /// - Version 2: Added tile ordering
  /// - Version 3: Zone-based architecture (primary/secondary/tertiary)
  static const int currentVersion = 3;

  final int version;
  final List<DashboardTileConfig> tiles;
  /// Width of the secondary zone as a fraction of available space (0.25 to 0.5)
  final double secondaryZoneWidth;

  const DashboardLayout({
    required this.version,
    required this.tiles,
    this.secondaryZoneWidth = 0.4,
  });

  DashboardLayout copyWith({
    int? version,
    List<DashboardTileConfig>? tiles,
    double? secondaryZoneWidth,
  }) {
    return DashboardLayout(
      version: version ?? this.version,
      tiles: tiles ?? this.tiles,
      secondaryZoneWidth: secondaryZoneWidth ?? this.secondaryZoneWidth,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'tiles': tiles.map((tile) => tile.toJson()).toList(),
      'secondaryZoneWidth': secondaryZoneWidth,
    };
  }

  factory DashboardLayout.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final tiles = json['tiles'];
    final secondaryZoneWidth = json['secondaryZoneWidth'];

    if (version is! int) {
      throw const FormatException('Dashboard layout version must be an integer.');
    }
    if (tiles is! List) {
      throw const FormatException('Dashboard layout tiles must be a list.');
    }

    final parsedTiles = tiles
        .map((entry) {
          if (entry is! Map<String, dynamic>) {
            throw const FormatException('Dashboard tile entry must be an object.');
          }
          return DashboardTileConfig.fromJson(entry);
        })
        .toList();

    return DashboardLayout(
      version: version,
      tiles: parsedTiles,
      secondaryZoneWidth: (secondaryZoneWidth is num)
          ? secondaryZoneWidth.toDouble().clamp(0.25, 0.5)
          : 0.4,
    ).normalize();
  }

  DashboardLayout normalize() {
    final sorted = [...tiles]..sort((a, b) => a.order.compareTo(b.order));
    final ids = <DashboardWidgetId>{};
    for (final tile in sorted) {
      if (!ids.add(tile.widgetId)) {
        throw FormatException('Duplicate dashboard tile: ${tile.widgetId.storageKey}');
      }
    }
    final normalized = <DashboardTileConfig>[];
    for (var i = 0; i < sorted.length; i++) {
      normalized.add(sorted[i].copyWith(order: i));
    }
    return DashboardLayout(
      version: version,
      tiles: normalized,
      secondaryZoneWidth: secondaryZoneWidth,
    );
  }

  DashboardLayout mergeWithDefaults(DashboardLayout defaults) {
    final existingIds = tiles.map((tile) => tile.widgetId).toSet();
    final merged = [...tiles];

    for (final tile in defaults.tiles) {
      if (!existingIds.contains(tile.widgetId)) {
        merged.add(tile.copyWith(order: merged.length));
      }
    }

    return DashboardLayout(
      version: defaults.version,
      tiles: merged,
      secondaryZoneWidth: secondaryZoneWidth,
    ).normalize();
  }

  /// Get tiles for a specific zone, sorted by order
  List<DashboardTileConfig> tilesForZone(DashboardZone zone) {
    return tiles.where((t) => t.zone == zone && t.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  static DashboardLayout defaultLayout() {
    final tiles = <DashboardTileConfig>[
      // Primary zone: hero content (live preview takes focus)
      const DashboardTileConfig(
        widgetId: DashboardWidgetId.livePreview,
        size: DashboardTileSize.large,
        enabled: true,
        order: 0,
        zone: DashboardZone.primary,
      ),
      const DashboardTileConfig(
        widgetId: DashboardWidgetId.captureSettings,
        size: DashboardTileSize.medium,
        enabled: true,
        order: 1,
        zone: DashboardZone.primary,
      ),

      // Secondary zone: supporting info and controls
      const DashboardTileConfig(
        widgetId: DashboardWidgetId.sequenceStatus,
        size: DashboardTileSize.medium,
        enabled: true,
        order: 2,
        zone: DashboardZone.secondary,
      ),
      const DashboardTileConfig(
        widgetId: DashboardWidgetId.guiding,
        size: DashboardTileSize.medium,
        enabled: true,
        order: 3,
        zone: DashboardZone.secondary,
      ),
      const DashboardTileConfig(
        widgetId: DashboardWidgetId.equipmentStatus,
        size: DashboardTileSize.small,
        enabled: true,
        order: 4,
        zone: DashboardZone.secondary,
      ),

      // Tertiary zone: compact status widgets (max 3-4 for clean row)
      const DashboardTileConfig(
        widgetId: DashboardWidgetId.mountControl,
        size: DashboardTileSize.small,
        enabled: true,
        order: 5,
        zone: DashboardZone.tertiary,
      ),
      const DashboardTileConfig(
        widgetId: DashboardWidgetId.focus,
        size: DashboardTileSize.small,
        enabled: true,
        order: 6,
        zone: DashboardZone.tertiary,
      ),
      const DashboardTileConfig(
        widgetId: DashboardWidgetId.weather,
        size: DashboardTileSize.small,
        enabled: true,
        order: 7,
        zone: DashboardZone.tertiary,
      ),
      const DashboardTileConfig(
        widgetId: DashboardWidgetId.tonight,
        size: DashboardTileSize.small,
        enabled: true,
        order: 8,
        zone: DashboardZone.tertiary,
      ),
      // Disabled by default - can be enabled via Edit Dashboard
      const DashboardTileConfig(
        widgetId: DashboardWidgetId.alerts,
        size: DashboardTileSize.small,
        enabled: false,
        order: 9,
        zone: DashboardZone.tertiary,
      ),
      const DashboardTileConfig(
        widgetId: DashboardWidgetId.quickActions,
        size: DashboardTileSize.medium,
        enabled: false,
        order: 10,
        zone: DashboardZone.secondary,
      ),
      // Quick Stats disabled - redundant with Command Bar stats
      const DashboardTileConfig(
        widgetId: DashboardWidgetId.quickStats,
        size: DashboardTileSize.small,
        enabled: false,
        order: 11,
        zone: DashboardZone.tertiary,
      ),
      // Storage tile: free space + projected run size. Enabled by default
      // so disk surprises don't blow up a multi-hour run at 3 AM (F3 polish).
      const DashboardTileConfig(
        widgetId: DashboardWidgetId.storage,
        size: DashboardTileSize.small,
        enabled: true,
        order: 12,
        zone: DashboardZone.tertiary,
      ),
    ];

    return DashboardLayout(
      version: DashboardLayout.currentVersion,
      tiles: tiles,
      secondaryZoneWidth: 0.4,
    );
  }
}
