import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../catalogs/catalog_manager.dart';
import '../catalogs/minor_planet_catalog.dart';
import '../catalogs/mpcorb.dart';

/// Refresh cadence for live orbital-element data.
enum ElementRefreshSchedule {
  manual,
  daily,
  weekly,
  monthly;

  Duration? get interval => switch (this) {
    ElementRefreshSchedule.manual => null,
    ElementRefreshSchedule.daily => const Duration(days: 1),
    ElementRefreshSchedule.weekly => const Duration(days: 7),
    ElementRefreshSchedule.monthly => const Duration(days: 30),
  };

  String get displayName => switch (this) {
    ElementRefreshSchedule.manual => 'Manual only',
    ElementRefreshSchedule.daily => 'Daily',
    ElementRefreshSchedule.weekly => 'Weekly',
    ElementRefreshSchedule.monthly => 'Monthly',
  };
}

/// Persisted configuration for the element refresh service.
class ElementRefreshConfig {
  /// MPCORB-format minor-planet source. Defaults to the MPC's yearly
  /// "bright minor planets at opposition" subset (a few hundred objects,
  /// ~60 KB) — the full MPCORB.DAT also parses if pointed at it, filtered
  /// by [maxAsteroidAbsoluteMag]. `{year}` is substituted at fetch time.
  final String asteroidUrl;

  /// MPC current cometary elements source.
  final String cometUrl;

  /// Refresh cadence (default weekly).
  final ElementRefreshSchedule schedule;

  /// Keep only asteroids with H <= this when parsing (bounds memory when
  /// the source is the full MPCORB.DAT; the bright subset is unaffected).
  final double maxAsteroidAbsoluteMag;

  static const String defaultAsteroidUrl =
      'https://www.minorplanetcenter.net/iau/Ephemerides/Bright/{year}/Soft00Bright.txt';
  static const String defaultCometUrl =
      'https://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt';

  const ElementRefreshConfig({
    this.asteroidUrl = defaultAsteroidUrl,
    this.cometUrl = defaultCometUrl,
    this.schedule = ElementRefreshSchedule.weekly,
    this.maxAsteroidAbsoluteMag = 14.0,
  });

  ElementRefreshConfig copyWith({
    String? asteroidUrl,
    String? cometUrl,
    ElementRefreshSchedule? schedule,
    double? maxAsteroidAbsoluteMag,
  }) => ElementRefreshConfig(
    asteroidUrl: asteroidUrl ?? this.asteroidUrl,
    cometUrl: cometUrl ?? this.cometUrl,
    schedule: schedule ?? this.schedule,
    maxAsteroidAbsoluteMag:
        maxAsteroidAbsoluteMag ?? this.maxAsteroidAbsoluteMag,
  );

  Map<String, Object?> toJson() => {
    'asteroidUrl': asteroidUrl,
    'cometUrl': cometUrl,
    'schedule': schedule.name,
    'maxAsteroidAbsoluteMag': maxAsteroidAbsoluteMag,
  };

  factory ElementRefreshConfig.fromJson(Map<String, Object?> json) =>
      ElementRefreshConfig(
        asteroidUrl: json['asteroidUrl'] as String? ?? defaultAsteroidUrl,
        cometUrl: json['cometUrl'] as String? ?? defaultCometUrl,
        schedule: ElementRefreshSchedule.values.firstWhere(
          (s) => s.name == json['schedule'],
          orElse: () => ElementRefreshSchedule.weekly,
        ),
        maxAsteroidAbsoluteMag:
            (json['maxAsteroidAbsoluteMag'] as num?)?.toDouble() ?? 14.0,
      );
}

/// The current refreshed element sets plus their provenance.
class RefreshedElements {
  final List<MinorBodyElements> asteroids;
  final List<MinorBodyElements> comets;
  final DateTime? asteroidsFetchedAt;
  final DateTime? cometsFetchedAt;

  const RefreshedElements({
    this.asteroids = const [],
    this.comets = const [],
    this.asteroidsFetchedAt,
    this.cometsFetchedAt,
  });

  bool get isEmpty => asteroids.isEmpty && comets.isEmpty;
  List<MinorBodyElements> get all => [...asteroids, ...comets];

  /// Oldest fetch time across the populated sets (for the staleness check
  /// and the "last updated" indicator).
  DateTime? get oldestFetch {
    final times = [
      if (asteroids.isNotEmpty && asteroidsFetchedAt != null)
        asteroidsFetchedAt!,
      if (comets.isNotEmpty && cometsFetchedAt != null) cometsFetchedAt!,
    ];
    if (times.isEmpty) return null;
    times.sort();
    return times.first;
  }
}

/// Fetches and caches live minor-planet (MPC) orbital elements on a
/// configurable schedule, offline-safe.
///
/// * Raw downloads are cached on disk (`mpc_asteroids.txt`,
///   `mpc_comets.txt`) next to the other catalogs, with fetch timestamps in
///   `element_refresh_metadata.json` — a failed refresh falls back to the
///   stale cache, and [loadCached] never touches the network.
/// * Satellite TLEs already have their own download/cache path
///   (`SatelliteCatalog`); this service only tracks/triggers it so one
///   "refresh" action covers all live element data.
class ElementRefreshService {
  final String _directory;
  final http.Client Function() _clientFactory;
  final DateTime Function() _now;

  ElementRefreshService({
    String? cacheDirectory,
    http.Client Function()? clientFactory,
    DateTime Function()? now,
  }) : _directory = cacheDirectory ?? CatalogManager.instance.catalogDirectory,
       _clientFactory = clientFactory ?? http.Client.new,
       _now = now ?? DateTime.now;

  String get _asteroidCachePath => path.join(_directory, 'mpc_asteroids.txt');
  String get _cometCachePath => path.join(_directory, 'mpc_comets.txt');
  String get _configPath =>
      path.join(_directory, 'element_refresh_config.json');
  String get _metaPath =>
      path.join(_directory, 'element_refresh_metadata.json');

  // -------------------------------------------------------------------
  // Config + metadata
  // -------------------------------------------------------------------

  Future<ElementRefreshConfig> loadConfig() async {
    try {
      final file = File(_configPath);
      if (await file.exists()) {
        return ElementRefreshConfig.fromJson(
          (jsonDecode(await file.readAsString()) as Map)
              .cast<String, Object?>(),
        );
      }
    } catch (e) {
      developer.log(
        '[ElementRefresh] config read error: $e',
        name: 'ElementRefreshService',
        level: 900,
      );
    }
    return const ElementRefreshConfig();
  }

  Future<void> saveConfig(ElementRefreshConfig config) async {
    await Directory(_directory).create(recursive: true);
    await File(_configPath).writeAsString(jsonEncode(config.toJson()));
  }

  Future<Map<String, Object?>> _loadMeta() async {
    try {
      final file = File(_metaPath);
      if (await file.exists()) {
        return (jsonDecode(await file.readAsString()) as Map)
            .cast<String, Object?>();
      }
    } catch (e) {
      // A corrupt meta file only loses the "last refreshed" bookkeeping; the
      // next save rewrites it. Log so repeated parse failures are visible.
      developer.log(
        'ElementRefreshService: failed to read refresh metadata: $e',
        name: 'nightshade.planetarium',
      );
    }
    return {};
  }

  Future<void> _saveMeta(Map<String, Object?> meta) async {
    await Directory(_directory).create(recursive: true);
    await File(_metaPath).writeAsString(jsonEncode(meta));
  }

  /// When a refresh was last *attempted* (success or failure). Used to avoid
  /// hammering the MPC after a failure when auto-refresh re-checks.
  Future<DateTime?> lastAttempt() async {
    final meta = await _loadMeta();
    return DateTime.tryParse(meta['lastAttempt'] as String? ?? '');
  }

  // -------------------------------------------------------------------
  // Load / refresh
  // -------------------------------------------------------------------

  /// Load the cached element sets from disk. Never touches the network;
  /// returns an empty set when nothing is cached.
  Future<RefreshedElements> loadCached() async {
    final meta = await _loadMeta();
    final config = await loadConfig();

    Future<(List<MinorBodyElements>, DateTime?)> read(
      String filePath,
      String metaKey,
      List<MinorBodyElements> Function(String) parse,
    ) async {
      final file = File(filePath);
      if (!await file.exists()) return (const <MinorBodyElements>[], null);
      try {
        final parsed = parse(await file.readAsString());
        final fetched =
            DateTime.tryParse(meta[metaKey] as String? ?? '') ??
            (await file.stat()).modified;
        return (parsed, fetched);
      } catch (e) {
        developer.log(
          '[ElementRefresh] cache read error ($filePath): $e',
          name: 'ElementRefreshService',
          level: 900,
          error: e,
        );
        return (const <MinorBodyElements>[], null);
      }
    }

    final (asteroids, asteroidsAt) = await read(
      _asteroidCachePath,
      'asteroidsFetchedAt',
      (text) => MpcOrbParser.parseAsteroids(
        text,
        maxAbsoluteMag: config.maxAsteroidAbsoluteMag,
      ),
    );
    final (comets, cometsAt) = await read(
      _cometCachePath,
      'cometsFetchedAt',
      MpcOrbParser.parseComets,
    );

    return RefreshedElements(
      asteroids: asteroids,
      comets: comets,
      asteroidsFetchedAt: asteroidsAt,
      cometsFetchedAt: cometsAt,
    );
  }

  /// Whether the cached data is older than the configured schedule allows.
  /// Manual schedule never reports stale.
  bool isStale(RefreshedElements cached, ElementRefreshConfig config) {
    final interval = config.schedule.interval;
    if (interval == null) return false;
    final oldest = cached.oldestFetch;
    if (cached.isEmpty || oldest == null) return true;
    return _now().difference(oldest) > interval;
  }

  /// Download fresh element sets, update the disk cache, and return the
  /// merged result. On a download failure the stale cached set for that
  /// source is kept (offline-safe); throws only if BOTH sources fail AND
  /// nothing is cached.
  Future<RefreshedElements> refresh({ElementRefreshConfig? config}) async {
    final cfg = config ?? await loadConfig();
    final cached = await loadCached();
    final meta = await _loadMeta();
    meta['lastAttempt'] = _now().toIso8601String();

    var asteroids = cached.asteroids;
    var asteroidsAt = cached.asteroidsFetchedAt;
    var comets = cached.comets;
    var cometsAt = cached.cometsFetchedAt;
    Object? firstError;

    final client = _clientFactory();
    try {
      // Asteroids (MPCORB 1-line format).
      try {
        final url = cfg.asteroidUrl.replaceAll(
          '{year}',
          _now().toUtc().year.toString(),
        );
        final text = await _fetchText(client, url);
        final parsed = MpcOrbParser.parseAsteroids(
          text,
          maxAbsoluteMag: cfg.maxAsteroidAbsoluteMag,
        );
        if (parsed.isEmpty) {
          throw FormatException('No parsable MPCORB records from $url');
        }
        await File(_asteroidCachePath).writeAsString(text);
        asteroids = parsed;
        asteroidsAt = _now();
        meta['asteroidsFetchedAt'] = asteroidsAt.toIso8601String();
        meta['asteroidsUrl'] = url;
        meta['asteroidsCount'] = parsed.length;
      } catch (e) {
        firstError = e;
        developer.log(
          '[ElementRefresh] asteroid refresh failed: $e',
          name: 'ElementRefreshService',
          level: 900,
          error: e,
        );
      }

      // Comets (CometEls.txt format).
      try {
        final text = await _fetchText(client, cfg.cometUrl);
        final parsed = MpcOrbParser.parseComets(text);
        if (parsed.isEmpty) {
          throw FormatException(
            'No parsable comet records from ${cfg.cometUrl}',
          );
        }
        await File(_cometCachePath).writeAsString(text);
        comets = parsed;
        cometsAt = _now();
        meta['cometsFetchedAt'] = cometsAt.toIso8601String();
        meta['cometsUrl'] = cfg.cometUrl;
        meta['cometsCount'] = parsed.length;
      } catch (e) {
        firstError ??= e;
        developer.log(
          '[ElementRefresh] comet refresh failed: $e',
          name: 'ElementRefreshService',
          level: 900,
          error: e,
        );
      }
    } finally {
      client.close();
      await _saveMeta(meta);
    }

    final result = RefreshedElements(
      asteroids: asteroids,
      comets: comets,
      asteroidsFetchedAt: asteroidsAt,
      cometsFetchedAt: cometsAt,
    );
    if (result.isEmpty && firstError != null) {
      throw Exception('Element refresh failed: $firstError');
    }
    return result;
  }

  Future<String> _fetchText(http.Client client, String url) async {
    final response = await client.get(
      Uri.parse(url),
      headers: {'User-Agent': 'Nightshade/4.0'},
    );
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    List<int> bytes = response.bodyBytes;
    if (url.endsWith('.gz')) {
      bytes = gzip.decode(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
