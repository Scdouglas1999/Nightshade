// Cloud backup/sync — SyncService tests over a fake in-memory SyncTarget.
//
// Follows the backup_service_extended_test.dart pattern: real
// BackupService over an in-memory drift database, real SettingsDao,
// keyring faked with InMemorySecureKeyValueStore. The remote side is an
// in-memory SyncTarget so we can assert exactly which files were
// uploaded/pruned and corrupt them at will.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Test-only LoggingService that skips native init (same pattern as
/// backup_service_extended_test.dart).
LoggingService _testLogger(Directory tempDir) {
  return LoggingService(
    applicationSupportDirectoryProvider: () async => tempDir,
    nativeInitWithLogging: ({String? logDirectory}) {},
    nativeInit: () {},
    currentLogFileProvider: () => null,
  );
}

/// In-memory [SyncTarget]: a flat map of path -> bytes plus a directory
/// set. Records uploads so prune behaviour can be asserted.
class InMemorySyncTarget implements SyncTarget {
  final Map<String, List<int>> files = {};
  final Set<String> dirs = {};
  final List<String> uploadedPaths = [];
  final List<String> deletedPaths = [];

  @override
  Future<void> ensureDirectory(String path) async {
    var prefix = '';
    for (final segment in path.split('/').where((s) => s.isNotEmpty)) {
      prefix = prefix.isEmpty ? segment : '$prefix/$segment';
      dirs.add(prefix);
    }
  }

  @override
  Future<void> uploadFile(String path, List<int> bytes) async {
    files[path] = List.of(bytes);
    uploadedPaths.add(path);
  }

  @override
  Future<List<int>> downloadFile(String path) async {
    final bytes = files[path];
    if (bytes == null) {
      throw SyncTargetException('not found: $path',
          kind: SyncTargetErrorKind.notFound, statusCode: 404);
    }
    return bytes;
  }

  @override
  Future<void> deleteFile(String path) async {
    files.remove(path);
    deletedPaths.add(path);
  }

  @override
  Future<List<SyncRemoteEntry>> listDirectory(String path) async {
    if (!dirs.contains(path)) {
      throw SyncTargetException('not found: $path',
          kind: SyncTargetErrorKind.notFound, statusCode: 404);
    }
    final prefix = '$path/';
    final names = <String, bool>{}; // name -> isDirectory
    for (final dir in dirs) {
      if (dir.startsWith(prefix)) {
        names[dir.substring(prefix.length).split('/').first] = true;
      }
    }
    for (final file in files.keys) {
      if (file.startsWith(prefix) &&
          !file.substring(prefix.length).contains('/')) {
        names[file.substring(prefix.length)] = false;
      }
    }
    return [
      for (final entry in names.entries)
        SyncRemoteEntry(
          name: entry.key,
          isDirectory: entry.value,
          sizeBytes:
              entry.value ? null : files['$prefix${entry.key}']!.length,
        ),
    ];
  }

  @override
  Future<void> testConnection() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncManifest.withBundle', () {
    SyncBundleInfo bundle(String file, DateTime createdAt) => SyncBundleInfo(
        file: file, sha256: 'h-$file', sizeBytes: 1, createdAt: createdAt);

    test('prepends newest and trims to retainCount, returning pruned',
        () {
      final t0 = DateTime.utc(2026, 6, 1);
      final manifest = SyncManifest(
        machine: 'm',
        appVersion: 'v',
        updatedAt: t0,
        bundles: [
          bundle('b3', DateTime.utc(2026, 6, 3)),
          bundle('b2', DateTime.utc(2026, 6, 2)),
          bundle('b1', DateTime.utc(2026, 6, 1)),
        ],
      );

      final (updated, pruned) = manifest.withBundle(
        bundle('b4', DateTime.utc(2026, 6, 4)),
        retainCount: 2,
        now: DateTime.utc(2026, 6, 4),
      );

      expect(updated.bundles.map((b) => b.file), ['b4', 'b3']);
      expect(pruned.map((b) => b.file), ['b2', 'b1']);
    });

    test('retainCount below 1 still keeps the newest bundle', () {
      final manifest = SyncManifest(
        machine: 'm',
        appVersion: 'v',
        updatedAt: DateTime.utc(2026),
        bundles: const [],
      );
      final (updated, pruned) = manifest.withBundle(
        bundle('only', DateTime.utc(2026)),
        retainCount: 0,
        now: DateTime.utc(2026),
      );
      expect(updated.bundles, hasLength(1));
      expect(pruned, isEmpty);
    });

    test('round-trips through JSON', () {
      final manifest = SyncManifest(
        machine: 'laptop',
        appVersion: '2.6.0',
        updatedAt: DateTime.utc(2026, 6, 9, 1, 2, 3),
        bundles: [bundle('b1', DateTime.utc(2026, 6, 8))],
      );
      final decoded = SyncManifest.fromJson(
          jsonDecode(jsonEncode(manifest.toJson())) as Map<String, dynamic>);
      expect(decoded.machine, 'laptop');
      expect(decoded.appVersion, '2.6.0');
      expect(decoded.bundles.single.file, 'b1');
      expect(decoded.bundles.single.sha256, 'h-b1');
    });
  });

  group('SyncService', () {
    late NightshadeDatabase db;
    late Directory tempDir;
    late LoggingService logger;
    late InMemorySyncTarget remote;

    setUp(() async {
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      tempDir = await Directory.systemTemp.createTemp('ns_cloud_sync_test_');
      logger = _testLogger(tempDir);
      remote = InMemorySyncTarget();
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    SyncService serviceFor(
      NightshadeDatabase database, {
      int retainCount = kSyncDefaultRetainCount,
      bool autoPush = false,
    }) {
      final dao = SettingsDao(database);
      final service = SyncService(
        backupService: BackupService(
          database: database,
          sequenceRepository: SequenceRepository(database.sequencesDao),
          logger: logger,
        ),
        settingsDao: dao,
        secretsStore: SecretsStore(InMemorySecureKeyValueStore()),
        logger: logger,
        targetFactory: (config, password) => remote,
        downloadDirectoryProvider: () async => tempDir,
      );
      return service;
    }

    Future<void> configure(
      NightshadeDatabase database, {
      int retainCount = kSyncDefaultRetainCount,
      bool autoPush = false,
    }) async {
      await SettingsDao(database).setSettings({
        SyncSettingsKeys.serverUrl: 'https://cloud.example.com/dav/',
        SyncSettingsKeys.username: 'astro',
        SyncSettingsKeys.machineName: 'test-machine',
        SyncSettingsKeys.autoPush: autoPush.toString(),
        SyncSettingsKeys.retainCount: retainCount.toString(),
      });
    }

    test('pushNow uploads bundle + manifest with correct sha256', () async {
      await configure(db);
      final service = serviceFor(db);

      final result = await service.pushNow();

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.remotePath, startsWith('nightshade-sync/test-machine/'));
      expect(result.remotePath, endsWith('.nsbak'));

      final manifestBytes =
          remote.files['nightshade-sync/test-machine/manifest.json'];
      expect(manifestBytes, isNotNull);
      final manifest = SyncManifest.fromJson(
          jsonDecode(utf8.decode(manifestBytes!)) as Map<String, dynamic>);
      expect(manifest.machine, 'test-machine');
      expect(manifest.appVersion, BackupService.appVersion);
      expect(manifest.bundles, hasLength(1));

      final bundleBytes = remote.files[result.remotePath!];
      expect(bundleBytes, isNotNull);
      expect(manifest.bundles.single.sha256,
          sha256.convert(bundleBytes!).toString());
      expect(manifest.bundles.single.sizeBytes, bundleBytes.length);

      // State recorded for the settings UI / status endpoint.
      final status = await service.status();
      expect(status.lastPushAt, isNotNull);
      expect(status.lastError, isNull);
    });

    test('pushNow prunes bundles beyond retainCount', () async {
      await configure(db, retainCount: 2);
      final service = serviceFor(db);

      for (var i = 0; i < 3; i++) {
        final result = await service.pushNow();
        expect(result.success, isTrue, reason: result.errorMessage);
        // The bundle filename derives from the wall clock; make sure two
        // pushes can't land in the same microsecond.
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      final manifest = SyncManifest.fromJson(jsonDecode(utf8.decode(
              remote.files['nightshade-sync/test-machine/manifest.json']!))
          as Map<String, dynamic>);
      expect(manifest.bundles, hasLength(2));

      final remoteBundles = remote.files.keys
          .where((p) => p.endsWith('.nsbak'))
          .toList();
      expect(remoteBundles, hasLength(2));
      expect(remote.deletedPaths, hasLength(1));
      // The kept bundles are exactly the manifest's.
      for (final b in manifest.bundles) {
        expect(remote.files,
            contains('nightshade-sync/test-machine/${b.file}'));
      }
    });

    test('pushNow records the error and reports failure when unconfigured',
        () async {
      final service = serviceFor(db); // no serverUrl configured

      final result = await service.pushNow();

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('not configured'));
      final status = await service.status();
      expect(status.lastError, contains('not configured'));
    });

    test('pullAndRestore round-trips data into another database', () async {
      // Source machine: one target row, pushed to the fake remote.
      await configure(db);
      await TargetsDao(db).createTarget(
        TargetsCompanion.insert(name: 'M42', ra: 5.6, dec: -5.4),
      );
      final push = await serviceFor(db).pushNow();
      expect(push.success, isTrue, reason: push.errorMessage);
      final bundleFile = push.remotePath!.split('/').last;

      // Destination machine: fresh database, same remote.
      final dstDb = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(dstDb.close);
      await configure(dstDb);
      final restore = await serviceFor(dstDb).pullAndRestore(
        machine: 'test-machine',
        bundleFile: bundleFile,
      );

      expect(restore.success, isTrue, reason: restore.errorMessage);
      final targets = await TargetsDao(dstDb).getAllTargets();
      expect(targets.map((t) => t.name), contains('M42'));
    });

    test('pullAndRestore aborts on hash mismatch without touching data',
        () async {
      await configure(db);
      final push = await serviceFor(db).pushNow();
      expect(push.success, isTrue, reason: push.errorMessage);

      // Corrupt the remote bundle AFTER the manifest recorded its hash.
      remote.files[push.remotePath!] = utf8.encode('{"version":"evil"}');

      final dstDb = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(dstDb.close);
      await configure(dstDb);
      final restore = await serviceFor(dstDb).pullAndRestore(
        machine: 'test-machine',
        bundleFile: push.remotePath!.split('/').last,
      );

      expect(restore.success, isFalse);
      expect(restore.errorMessage, contains('Hash mismatch'));
      expect(restore.itemsRestored, 0);
    });

    test('listRemoteMachines and listRemoteBundles surface pushed state',
        () async {
      await configure(db);
      final service = serviceFor(db);
      final push = await service.pushNow();
      expect(push.success, isTrue, reason: push.errorMessage);

      final machines = await service.listRemoteMachines();
      expect(machines.map((m) => m.name), ['test-machine']);

      final bundles = await service.listRemoteBundles('test-machine');
      expect(bundles, hasLength(1));
      expect(bundles.single.file, push.remotePath!.split('/').last);
      expect(bundles.single.sha256, isNotEmpty);
    });

    test('maybeAutoPush is a no-op when auto-push is disabled', () async {
      await configure(db, autoPush: false);
      await serviceFor(db).maybeAutoPush(reason: 'test');
      expect(remote.uploadedPaths, isEmpty);
    });

    test('maybeAutoPush pushes when enabled', () async {
      await configure(db, autoPush: true);
      await serviceFor(db).maybeAutoPush(reason: 'test');
      expect(
        remote.uploadedPaths.where((p) => p.endsWith('.nsbak')),
        hasLength(1),
      );
    });
  });
}
