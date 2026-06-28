import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightshade_updater/src/models/update_manifest.dart';
import 'package:nightshade_updater/src/services/update_service.dart';

void main() {
  UpdateManifest manifest({
    String version = '2.1.0',
    int buildNumber = 42,
    String? minVersion,
  }) => UpdateManifest(
    version: version,
    buildNumber: buildNumber,
    releaseDate: DateTime.utc(2026, 5, 25),
    platform: 'windows',
    arch: 'x64',
    minVersion: minVersion,
    files: const {},
    totalSize: 0,
    compressedSize: 0,
    downloadUrl: 'https://example.invalid/nightshade.zip',
  );

  group('canUpgradeFrom version-component gating', () {
    test('from "2.0" with minVersion "2.0.5" is blocked (no fail-open)', () {
      expect(manifest(minVersion: '2.0.5').canUpgradeFrom('2.0'), isFalse);
    });

    test(
      'from "2.0.5" with minVersion "2.0.5" is allowed (equal -> allow)',
      () {
        expect(manifest(minVersion: '2.0.5').canUpgradeFrom('2.0.5'), isTrue);
      },
    );

    test('from "2.1" with minVersion "2.0.5" is allowed (strictly newer)', () {
      expect(manifest(minVersion: '2.0.5').canUpgradeFrom('2.1'), isTrue);
    });

    test(
      'from "2.0.5.1" with minVersion "2.0.5" is allowed (longer, prefix equal)',
      () {
        expect(manifest(minVersion: '2.0.5').canUpgradeFrom('2.0.5.1'), isTrue);
      },
    );

    test('minVersion == null means no gate', () {
      expect(manifest(minVersion: null).canUpgradeFrom('1.0.0'), isTrue);
      expect(manifest(minVersion: null).canUpgradeFrom('0.0'), isTrue);
    });
  });

  group('isNewerBuildThan same-semver build gating', () {
    test('newer build at equal version is newer', () {
      expect(
        manifest(version: '2.0.0', buildNumber: 5).isNewerBuildThan('2.0.0', 4),
        isTrue,
      );
    });

    test('identical version+build is not newer (no self-update loop)', () {
      expect(
        manifest(version: '2.0.0', buildNumber: 4).isNewerBuildThan('2.0.0', 4),
        isFalse,
      );
    });

    test('strictly newer semver is newer regardless of build', () {
      expect(
        manifest(
          version: '2.1.0',
          buildNumber: 1,
        ).isNewerBuildThan('2.0.0', 99),
        isTrue,
      );
    });

    test('older semver is not newer even with a higher build', () {
      expect(
        manifest(
          version: '1.9.0',
          buildNumber: 99,
        ).isNewerBuildThan('2.0.0', 1),
        isFalse,
      );
    });

    test('equal version with lower build is not newer', () {
      expect(
        manifest(version: '2.0.0', buildNumber: 3).isNewerBuildThan('2.0.0', 4),
        isFalse,
      );
    });

    test('isNewerThan keeps its semver-only contract (ignores build)', () {
      expect(manifest(version: '2.0.0').isNewerThan('2.0.0'), isFalse);
      expect(manifest(version: '2.0.1').isNewerThan('2.0.0'), isTrue);
    });
  });

  group('checkForUpdates build-aware availability', () {
    // Routes /api/version and the manifest URL through an in-memory mock so
    // the build-gating branch is exercised without network or disk.
    UpdateService serviceFor(
      UpdateManifest served, {
      required String currentVersion,
      required int currentBuildNumber,
    }) {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/api/version')) {
          return http.Response(
            jsonEncode({
              'latestVersion': served.version,
              'latestBuildNumber': served.buildNumber,
              'channels': {
                'stable': {
                  'version': served.version,
                  'manifestUrl': '/api/manifest',
                },
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/api/manifest')) {
          return http.Response(jsonEncode(served.toJson()), 200);
        }
        return http.Response('not found', 404);
      });

      final service = UpdateService(
        currentVersion: currentVersion,
        currentBuildNumber: currentBuildNumber,
        httpClient: client,
      );
      service.configure(serverUrl: 'https://example.invalid');
      return service;
    }

    test(
      'offers when version equals current but buildNumber is greater',
      () async {
        final service = serviceFor(
          manifest(version: '2.0.0', buildNumber: 5),
          currentVersion: '2.0.0',
          currentBuildNumber: 4,
        );
        final result = await service.checkForUpdates();
        expect(result.hasUpdate, isTrue);
        expect(result.availableVersion, '2.0.0');
      },
    );

    test(
      'does NOT offer when version and buildNumber both equal current',
      () async {
        final service = serviceFor(
          manifest(version: '2.0.0', buildNumber: 4),
          currentVersion: '2.0.0',
          currentBuildNumber: 4,
        );
        final result = await service.checkForUpdates();
        expect(result.hasUpdate, isFalse);
      },
    );

    test('still offers a strictly newer semver (unchanged behavior)', () async {
      final service = serviceFor(
        manifest(version: '2.1.0', buildNumber: 1),
        currentVersion: '2.0.0',
        currentBuildNumber: 99,
      );
      final result = await service.checkForUpdates();
      expect(result.hasUpdate, isTrue);
      expect(result.availableVersion, '2.1.0');
    });
  });
}
