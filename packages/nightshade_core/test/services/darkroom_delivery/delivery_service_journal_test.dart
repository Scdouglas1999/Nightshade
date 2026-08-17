// Delivery against a real v58 database and a fault-injected transport.
//
// The load-bearing claim is that retry state lives in `delivery_journal` and
// nowhere else: the restart tests close the database, reopen it, build a
// COMPLETELY NEW DeliveryService, and expect the sweep to pick up exactly
// where the dead process left off.

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/daos/darkroom_jobs_dao.dart';
import 'package:nightshade_core/src/database/daos/delivery_journal_dao.dart';
import 'package:nightshade_core/src/database/daos/delivery_targets_dao.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/models/darkroom/delivery.dart';
import 'package:nightshade_core/src/services/darkroom_delivery/artifact_transport.dart';
import 'package:nightshade_core/src/services/darkroom_delivery/atomic_file_write.dart';
import 'package:nightshade_core/src/services/darkroom_delivery/delivery_artifact.dart';
import 'package:nightshade_core/src/services/darkroom_delivery/delivery_failure.dart';
import 'package:nightshade_core/src/services/darkroom_delivery/delivery_naming.dart';
import 'package:nightshade_core/src/services/darkroom_delivery/delivery_retry_policy.dart';
import 'package:nightshade_core/src/services/darkroom_delivery/delivery_service.dart';
import 'package:nightshade_core/src/services/darkroom_delivery/watched_folder_transport.dart';
import 'package:path/path.dart' as p;

/// A transport whose behaviour the test dictates per file.
class _ScriptedTransport implements ArtifactTransport {
  _ScriptedTransport({
    required this.kind,
    this.openFailure,
    this.deliverFailure,
    this.disposition = DeliveryDisposition.delivered,
  });

  @override
  final ArtifactDestinationKind kind;

  DeliveryFailure? openFailure;
  DeliveryFailure? deliverFailure;
  DeliveryDisposition disposition;

  final List<String> delivered = [];
  int opens = 0;
  int closes = 0;

  @override
  Future<void> open(List<DeliveryFile> artifacts) async {
    opens++;
    final failure = openFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<TransportDeliveryOutcome> deliver(DeliveryFile artifact) async {
    final failure = deliverFailure;
    if (failure != null) throw failure;
    delivered.add(artifact.sourcePath);
    return TransportDeliveryOutcome(
      disposition: disposition,
      checksum: artifact.checksum,
      destinationDescription: 'test://${artifact.fileName}',
    );
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  late Directory tempDir;
  late File dbFile;
  late Directory source;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ns_delivery_svc_');
    dbFile = File(p.join(tempDir.path, 'nightshade.db'));
    source = await Directory(p.join(tempDir.path, 'masters')).create();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  NightshadeDatabase open() =>
      NightshadeDatabase.forTesting(NativeDatabase(dbFile));

  /// Queue a real `darkroom_jobs` row. A journal row references one by
  /// foreign key, so delivery cannot be tested against an invented job id.
  Future<int> enqueueJob(NightshadeDatabase db) =>
      DarkroomJobsDao(db).enqueue();

  Future<DeliveryArtifactSet> artifactSet({
    int jobId = 1,
    List<String> names = const ['M31_Ha_master.fits'],
  }) async {
    final paths = <String>[];
    for (final name in names) {
      final file = File(p.join(source.path, name));
      await file.writeAsString('bytes-of-$name');
      paths.add(file.path);
    }
    return DeliveryArtifactSet.build(
      jobId: jobId,
      sources: {ArtifactContent.linearMasters: paths},
    );
  }

  Future<int> createWatchedFolder(
    NightshadeDatabase db, {
    String name = 'nas',
    bool enabled = true,
    ArtifactDestinationKind kind = ArtifactDestinationKind.watchedFolder,
  }) {
    return DeliveryTargetsDao(db).create(
      name: name,
      kind: kind,
      configJson: jsonEncode({'path': '/mnt/nas', 'peerId': 'office-pc'}),
      enabled: enabled,
      content: const {ArtifactContent.linearMasters},
    );
  }

  group('delivering a job', () {
    test(
      'journals a delivered row per file and reports where it went',
      () async {
        final db = open();
        addTearDown(db.close);
        await enqueueJob(db);
        final targetId = await createWatchedFolder(db);
        final transport = _ScriptedTransport(
          kind: ArtifactDestinationKind.watchedFolder,
        );
        final service = DeliveryService(
          targets: DeliveryTargetsDao(db),
          journal: DeliveryJournalDao(db),
          transportFactory: (_, __) => transport,
        );
        final set = await artifactSet(names: ['a.fits', 'b.fits']);

        final report = await service.deliverJobArtifacts(set);

        expect(report.delivered, 2);
        expect(report.failed, 0);
        expect(report.summary, contains('nas: 2 delivered'));
        expect(transport.opens, 1);
        expect(transport.closes, 1);

        final rows = await DeliveryJournalDao(db).listForJob(1);
        expect(rows.length, 2);
        for (final row in rows) {
          expect(row.state, DeliveryAttemptState.delivered);
          expect(row.targetId, targetId);
          expect(row.attempts, 1);
          expect(row.checksum, isNotNull);
          expect(row.bytes, greaterThan(0));
          expect(row.deliveredAt, isNotNull);
        }
      },
    );

    test('a destination that fails to open journals every file with the '
        'mechanism, and delivery still returns', () async {
      final db = open();
      addTearDown(db.close);
      await enqueueJob(db);
      await createWatchedFolder(db);
      final transport = _ScriptedTransport(
        kind: ArtifactDestinationKind.watchedFolder,
        openFailure: const DeliveryFailure(
          DeliveryFailureKind.destinationUnreachable,
          '/mnt/nas is not on the filesystem right now',
        ),
      );
      final service = DeliveryService(
        targets: DeliveryTargetsDao(db),
        journal: DeliveryJournalDao(db),
        transportFactory: (_, __) => transport,
      );

      final report = await service.deliverJobArtifacts(
        await artifactSet(names: ['a.fits', 'b.fits']),
      );

      expect(report.retrying, 2);
      expect(report.delivered, 0);
      expect(transport.closes, 1, reason: 'the transport is always released');

      final rows = await DeliveryJournalDao(db).listForJob(1);
      expect(rows.every((r) => r.state == DeliveryAttemptState.retrying), true);
      expect(
        rows.first.lastError,
        contains('destinationUnreachable'),
        reason: 'the journal names the mechanism, not just "failed"',
      );
    });

    test('a failure no retry can change is recorded as failed on the first '
        'attempt', () async {
      final db = open();
      addTearDown(db.close);
      await enqueueJob(db);
      await createWatchedFolder(db);
      final service = DeliveryService(
        targets: DeliveryTargetsDao(db),
        journal: DeliveryJournalDao(db),
        transportFactory: (_, __) => _ScriptedTransport(
          kind: ArtifactDestinationKind.watchedFolder,
          deliverFailure: const DeliveryFailure(
            DeliveryFailureKind.destinationConflict,
            'that name is taken by different bytes',
          ),
        ),
      );

      final report = await service.deliverJobArtifacts(await artifactSet());

      expect(report.failed, 1);
      expect(report.retrying, 0);
      final row = (await DeliveryJournalDao(db).listForJob(1)).single;
      expect(row.state, DeliveryAttemptState.failed);
      expect(row.attempts, 1);
      expect(row.lastError, contains('destinationConflict'));
    });

    test('a transport that throws something untyped never escapes into the '
        'pipeline', () async {
      final db = open();
      addTearDown(db.close);
      await enqueueJob(db);
      await createWatchedFolder(db);
      final service = DeliveryService(
        targets: DeliveryTargetsDao(db),
        journal: DeliveryJournalDao(db),
        transportFactory: (_, __) => _ThrowingTransport(),
      );

      final report = await service.deliverJobArtifacts(await artifactSet());

      expect(report.retrying, 1);
      final row = (await DeliveryJournalDao(db).listForJob(1)).single;
      expect(row.lastError, contains('transportFailure'));
    });

    test('a disabled destination is not visited at all', () async {
      final db = open();
      addTearDown(db.close);
      await enqueueJob(db);
      await createWatchedFolder(db, enabled: false);
      final transport = _ScriptedTransport(
        kind: ArtifactDestinationKind.watchedFolder,
      );
      final service = DeliveryService(
        targets: DeliveryTargetsDao(db),
        journal: DeliveryJournalDao(db),
        transportFactory: (_, __) => transport,
      );

      final report = await service.deliverJobArtifacts(await artifactSet());

      expect(report.destinations, isEmpty);
      expect(transport.opens, 0);
      expect(await DeliveryJournalDao(db).listForJob(1), isEmpty);
    });

    test('a peer destination is published, not claimed as delivered', () async {
      final db = open();
      addTearDown(db.close);
      await enqueueJob(db);
      await createWatchedFolder(
        db,
        name: 'office-pc',
        kind: ArtifactDestinationKind.peer,
      );
      final service = DeliveryService(
        targets: DeliveryTargetsDao(db),
        journal: DeliveryJournalDao(db),
        transportFactory: (_, __) => _ScriptedTransport(
          kind: ArtifactDestinationKind.peer,
          disposition: DeliveryDisposition.awaitingPull,
        ),
      );

      final report = await service.deliverJobArtifacts(await artifactSet());

      expect(report.awaitingPull, 1);
      expect(report.delivered, 0);
      final row = (await DeliveryJournalDao(db).listForJob(1)).single;
      expect(row.state, DeliveryAttemptState.retrying);
      expect(
        row.deliveredAt,
        isNull,
        reason: 'serving bytes is not the same as the bytes arriving',
      );
    });
  });

  group('the overnight retry sweep', () {
    test('waits out the backoff before spending another attempt', () async {
      final db = open();
      addTearDown(db.close);
      await enqueueJob(db);
      await createWatchedFolder(db);
      var now = DateTime.utc(2026, 8, 16, 5);
      final transport = _ScriptedTransport(
        kind: ArtifactDestinationKind.watchedFolder,
        openFailure: const DeliveryFailure(
          DeliveryFailureKind.destinationUnreachable,
          'the share is not mounted',
        ),
      );
      final service = DeliveryService(
        targets: DeliveryTargetsDao(db),
        journal: DeliveryJournalDao(db),
        transportFactory: (_, __) => transport,
        clock: () => now,
      );
      await service.deliverJobArtifacts(await artifactSet());

      now = now.add(const Duration(seconds: 30));
      final tooEarly = await service.sweepDueRetries();

      expect(tooEarly.retrying, 1);
      expect(transport.opens, 1, reason: 'the backoff has not elapsed');
      expect((await DeliveryJournalDao(db).listForJob(1)).single.attempts, 1);

      now = now.add(const Duration(minutes: 2));
      await service.sweepDueRetries();

      expect(transport.opens, 2);
      expect((await DeliveryJournalDao(db).listForJob(1)).single.attempts, 2);
    });

    test('resumes across a restart from the journal alone', () async {
      var now = DateTime.utc(2026, 8, 16, 5);
      final set = await artifactSet();

      // The process that ran the dawn job fails to reach the NAS, then dies.
      final first = open();
      await enqueueJob(first);
      await createWatchedFolder(first);
      final failing = DeliveryService(
        targets: DeliveryTargetsDao(first),
        journal: DeliveryJournalDao(first),
        transportFactory: (_, __) => _ScriptedTransport(
          kind: ArtifactDestinationKind.watchedFolder,
          openFailure: const DeliveryFailure(
            DeliveryFailureKind.destinationUnreachable,
            'the share is not mounted',
          ),
        ),
        clock: () => now,
      );
      await failing.deliverJobArtifacts(set);
      await first.close();

      // A completely new process, a completely new service. Nothing carries
      // over except the rows on disk.
      now = now.add(const Duration(minutes: 5));
      final second = open();
      addTearDown(second.close);
      final recovered = _ScriptedTransport(
        kind: ArtifactDestinationKind.watchedFolder,
      );
      final resumed = DeliveryService(
        targets: DeliveryTargetsDao(second),
        journal: DeliveryJournalDao(second),
        transportFactory: (_, __) => recovered,
        clock: () => now,
      );

      final report = await resumed.sweepDueRetries();

      expect(report.delivered, 1);
      expect(recovered.delivered, [set.artifacts.single.sourcePath]);
      final row = (await DeliveryJournalDao(second).listForJob(1)).single;
      expect(row.state, DeliveryAttemptState.delivered);
      expect(row.attempts, 2, reason: 'the first attempt is still counted');
      expect(
        row.lastError,
        contains('destinationUnreachable'),
        reason: 'a delivery that recovered says so rather than looking clean',
      );
    });

    test(
      'stops after the attempt budget and says how many attempts it took',
      () async {
        final db = open();
        addTearDown(db.close);
        await enqueueJob(db);
        await createWatchedFolder(db);
        var now = DateTime.utc(2026, 8, 16, 5);
        final service = DeliveryService(
          targets: DeliveryTargetsDao(db),
          journal: DeliveryJournalDao(db),
          policy: const DeliveryRetryPolicy(
            maxAttempts: 3,
            firstBackoff: Duration(minutes: 1),
          ),
          transportFactory: (_, __) => _ScriptedTransport(
            kind: ArtifactDestinationKind.watchedFolder,
            openFailure: const DeliveryFailure(
              DeliveryFailureKind.destinationUnreachable,
              'the share is not mounted',
            ),
          ),
          clock: () => now,
        );
        await service.deliverJobArtifacts(await artifactSet());

        for (var i = 0; i < 4; i++) {
          now = now.add(const Duration(hours: 1));
          await service.sweepDueRetries();
        }

        final row = (await DeliveryJournalDao(db).listForJob(1)).single;
        expect(row.state, DeliveryAttemptState.failed);
        expect(row.attempts, 3);
        expect(row.lastError, contains('after 3 attempts'));
      },
    );

    test('a peer row is left waiting for its pull, not retried', () async {
      final db = open();
      addTearDown(db.close);
      await enqueueJob(db);
      await createWatchedFolder(
        db,
        name: 'office-pc',
        kind: ArtifactDestinationKind.peer,
      );
      var now = DateTime.utc(2026, 8, 16, 5);
      final transport = _ScriptedTransport(
        kind: ArtifactDestinationKind.peer,
        disposition: DeliveryDisposition.awaitingPull,
      );
      final service = DeliveryService(
        targets: DeliveryTargetsDao(db),
        journal: DeliveryJournalDao(db),
        transportFactory: (_, __) => transport,
        clock: () => now,
      );
      await service.deliverJobArtifacts(await artifactSet());

      now = now.add(const Duration(hours: 3));
      final report = await service.sweepDueRetries();

      expect(report.awaitingPull, 1);
      expect(transport.opens, 1, reason: 'the sweep does not re-publish');
      expect((await DeliveryJournalDao(db).listForJob(1)).single.attempts, 1);
    });

    test('a destination switched off mid-night pauses without spending an '
        'attempt', () async {
      final db = open();
      addTearDown(db.close);
      await enqueueJob(db);
      final targetId = await createWatchedFolder(db);
      var now = DateTime.utc(2026, 8, 16, 5);
      final service = DeliveryService(
        targets: DeliveryTargetsDao(db),
        journal: DeliveryJournalDao(db),
        transportFactory: (_, __) => _ScriptedTransport(
          kind: ArtifactDestinationKind.watchedFolder,
          openFailure: const DeliveryFailure(
            DeliveryFailureKind.destinationUnreachable,
            'the share is not mounted',
          ),
        ),
        clock: () => now,
      );
      await service.deliverJobArtifacts(await artifactSet());
      await DeliveryTargetsDao(db).update(targetId, enabled: false);

      now = now.add(const Duration(hours: 1));
      final report = await service.sweepDueRetries();

      expect(report.retrying, 1);
      expect(
        report.destinations.single.problems.single,
        contains('switched off'),
      );
      expect((await DeliveryJournalDao(db).listForJob(1)).single.attempts, 1);
    });

    test('a source deleted between attempts stops being retried', () async {
      final db = open();
      addTearDown(db.close);
      await enqueueJob(db);
      await createWatchedFolder(db);
      var now = DateTime.utc(2026, 8, 16, 5);
      final service = DeliveryService(
        targets: DeliveryTargetsDao(db),
        journal: DeliveryJournalDao(db),
        transportFactory: (_, __) => _ScriptedTransport(
          kind: ArtifactDestinationKind.watchedFolder,
          openFailure: const DeliveryFailure(
            DeliveryFailureKind.destinationUnreachable,
            'the share is not mounted',
          ),
        ),
        clock: () => now,
      );
      final set = await artifactSet();
      await service.deliverJobArtifacts(set);
      await File(set.artifacts.single.sourcePath).delete();

      now = now.add(const Duration(hours: 1));
      final report = await service.sweepDueRetries();

      expect(report.failed, 1);
      final row = (await DeliveryJournalDao(db).listForJob(1)).single;
      expect(row.state, DeliveryAttemptState.failed);
      expect(row.lastError, contains('sourceMissing'));
    });

    // `delivery_journal.last_error` is the sentence the morning report and the
    // Settings > Delivery status line both print. It used to name the act and
    // not the cause — "failed: Cannot copy file to '<staged path>'" — for
    // every refusal the filesystem could make, so a full drive, a read-only
    // mount and a name the filesystem would not take all read identically.
    // The real transport, a real refused copy, and the row the operator reads.
    test('a copy the filesystem refuses journals the reason it gave, not just '
        'that it failed', () async {
      final db = open();
      addTearDown(db.close);
      await enqueueJob(db);
      final drop = await Directory(p.join(tempDir.path, 'drop')).create();
      await DeliveryTargetsDao(db).create(
        name: 'nas',
        kind: ArtifactDestinationKind.watchedFolder,
        configJson: jsonEncode({'path': drop.path, kDeliveryRigIdKey: ''}),
        content: const {ArtifactContent.linearMasters},
      );
      final set = await artifactSet();
      // A directory sitting on the staged name. `File.copy` onto a directory
      // is EISDIR on every platform Nightshade ships to, and unlike a
      // permission bit no user — root included — can copy over it, so this
      // reproduces a genuine OS refusal deterministically.
      await Directory(
        p.join(
          drop.path,
          '.${set.artifacts.single.fileName}.1$kStagedDeliverySuffix',
        ),
      ).create();

      final service = DeliveryService(
        targets: DeliveryTargetsDao(db),
        journal: DeliveryJournalDao(db),
        transportFactory: (destination, jobId) =>
            WatchedFolderTransport(destination: destination, jobId: jobId),
      );

      final report = await service.deliverJobArtifacts(set);
      expect(report.delivered, 0);

      final row = (await DeliveryJournalDao(db).listForJob(1)).single;
      expect(row.lastError, contains('M31_Ha_master.fits'));
      expect(
        row.lastError,
        contains('errno '),
        reason: 'the operator sentence must carry the reason the OS gave',
      );
      expect(
        row.lastError,
        isNot(endsWith("$kStagedDeliverySuffix'")),
        reason: 'the sentence used to end at the act it could not perform',
      );
    });
  });

  group('the retry schedule', () {
    test('backs off geometrically and then holds at the ceiling', () {
      const policy = DeliveryRetryPolicy.standard;

      expect(policy.backoffAfter(1), const Duration(minutes: 1));
      expect(policy.backoffAfter(2), const Duration(minutes: 3));
      expect(policy.backoffAfter(3), const Duration(minutes: 9));
      expect(policy.backoffAfter(4), const Duration(minutes: 27));
      expect(policy.backoffAfter(5), const Duration(minutes: 30));
      expect(policy.backoffAfter(50), const Duration(minutes: 30));
    });

    test('spends its budget and stops', () {
      const policy = DeliveryRetryPolicy.standard;

      expect(policy.isExhausted(7), isFalse);
      expect(policy.isExhausted(8), isTrue);
    });
  });
}

/// A transport that fails with something that is not a [DeliveryFailure], the
/// way a driver bug or a platform exception would.
class _ThrowingTransport implements ArtifactTransport {
  @override
  ArtifactDestinationKind get kind => ArtifactDestinationKind.watchedFolder;

  @override
  Future<void> open(List<DeliveryFile> artifacts) async {}

  @override
  Future<TransportDeliveryOutcome> deliver(DeliveryFile artifact) async {
    throw StateError('the driver fell over');
  }

  @override
  Future<void> close() async {}
}
