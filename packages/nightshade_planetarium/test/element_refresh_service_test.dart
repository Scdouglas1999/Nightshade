import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightshade_planetarium/src/catalogs/mpcorb.dart';
import 'package:nightshade_planetarium/src/services/element_refresh_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ns_element_refresh_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  // One real-format MPCORB record (Ceres) the parser accepts.
  const ceresMpcorb =
      '00001    3.34  0.12 K239D  60.07881   73.42179   80.25496   10.58688  '
      '0.0788175  0.21424651   2.7656460  0 MPO719049  7283 122 1801-2023 0.65 '
      'M-v 30h MPCLINUX   0000      (1) Ceres              20230906';

  // One CometEls.txt record (Halley).
  const halleyComet =
      '0001P         1986 02  9.6671  0.587104  0.967658  111.3324   58.4204'
      '  162.2627  20240101  4.0  6.0  1P/Halley';

  group('ElementRefreshService', () {
    test('refresh downloads, caches to disk, and parses', () async {
      final service = ElementRefreshService(
        cacheDirectory: tempDir.path,
        clientFactory: () => MockClient((req) async {
          if (req.url.path.contains('CometEls') ||
              req.url.toString().contains('Comet')) {
            return http.Response(halleyComet, 200);
          }
          return http.Response(ceresMpcorb, 200);
        }),
        now: () => DateTime.utc(2026, 6, 1),
      );

      final result = await service.refresh();
      expect(result.asteroids, isNotEmpty);
      expect(result.asteroids.first.commonName, 'Ceres');
      expect(result.comets, isNotEmpty);

      // Disk cache was written.
      expect(File('${tempDir.path}/mpc_asteroids.txt').existsSync(), isTrue);
      expect(File('${tempDir.path}/mpc_comets.txt').existsSync(), isTrue);
    });

    test('loadCached reads disk without hitting the network', () async {
      // Seed the cache via a refresh.
      await ElementRefreshService(
        cacheDirectory: tempDir.path,
        clientFactory: () => MockClient((req) async {
          if (req.url.toString().contains('Comet')) {
            return http.Response(halleyComet, 200);
          }
          return http.Response(ceresMpcorb, 200);
        }),
        now: () => DateTime.utc(2026, 6, 1),
      ).refresh();

      // A fresh service with a client that would THROW if called.
      final offline = ElementRefreshService(
        cacheDirectory: tempDir.path,
        clientFactory: () =>
            MockClient((_) async => throw StateError('network used')),
      );
      final cached = await offline.loadCached();
      expect(cached.asteroids, isNotEmpty);
      expect(cached.asteroids.first.commonName, 'Ceres');
    });

    test('refresh falls back to stale cache when the network fails', () async {
      // Seed cache.
      await ElementRefreshService(
        cacheDirectory: tempDir.path,
        clientFactory: () => MockClient((req) async {
          if (req.url.toString().contains('Comet')) {
            return http.Response(halleyComet, 200);
          }
          return http.Response(ceresMpcorb, 200);
        }),
        now: () => DateTime.utc(2026, 6, 1),
      ).refresh();

      // Now both endpoints 500 — should keep the cached asteroids.
      final failing = ElementRefreshService(
        cacheDirectory: tempDir.path,
        clientFactory: () => MockClient((_) async => http.Response('', 500)),
        now: () => DateTime.utc(2026, 6, 8),
      );
      final result = await failing.refresh();
      expect(
        result.asteroids,
        isNotEmpty,
        reason: 'stale cache should survive a failed refresh',
      );
    });

    test(
      'refresh throws only when network fails AND nothing is cached',
      () async {
        final service = ElementRefreshService(
          cacheDirectory: tempDir.path,
          clientFactory: () => MockClient((_) async => http.Response('', 503)),
        );
        expect(service.refresh(), throwsA(isA<Exception>()));
      },
    );

    test('isStale respects the schedule', () {
      final service = ElementRefreshService(
        cacheDirectory: tempDir.path,
        now: () => DateTime.utc(2026, 6, 10),
      );
      const weekly = ElementRefreshConfig();
      final one = [MpcOrbParser.parseAsteroidLine(ceresMpcorb)!];
      final fresh = RefreshedElements(
        asteroids: one,
        asteroidsFetchedAt: DateTime.utc(2026, 6, 9),
      );
      final old = RefreshedElements(
        asteroids: one,
        asteroidsFetchedAt: DateTime.utc(2026, 5, 1),
      );
      expect(service.isStale(fresh, weekly), isFalse);
      expect(service.isStale(old, weekly), isTrue);

      const manual = ElementRefreshConfig(
        schedule: ElementRefreshSchedule.manual,
      );
      expect(service.isStale(old, manual), isFalse);
    });

    test('config persists and reloads', () async {
      final service = ElementRefreshService(cacheDirectory: tempDir.path);
      const cfg = ElementRefreshConfig(
        schedule: ElementRefreshSchedule.daily,
        maxAsteroidAbsoluteMag: 9.0,
      );
      await service.saveConfig(cfg);
      final loaded = await service.loadConfig();
      expect(loaded.schedule, ElementRefreshSchedule.daily);
      expect(loaded.maxAsteroidAbsoluteMag, 9.0);
    });
  });
}
