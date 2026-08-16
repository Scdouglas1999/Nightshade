// Behaviour tests for the v58 delivery DAOs — DeliveryTargetsDao (where the
// night's artifacts go) and DeliveryJournalDao (what happened to each file).
//
// Covers: the per-destination content selection and its canonical byte form,
// the no-secrets-in-config_json rule on every write, partial updates that leave
// unrelated fields alone, the journal's upsert-on-retry identity, the outcome
// writes, and the cascades that take a journal with its destination or its job.

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/daos/darkroom_jobs_dao.dart';
import 'package:nightshade_core/src/database/daos/delivery_journal_dao.dart';
import 'package:nightshade_core/src/database/daos/delivery_targets_dao.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/models/darkroom/delivery.dart';

void main() {
  late NightshadeDatabase db;
  late DeliveryTargetsDao targets;
  late DeliveryJournalDao journal;
  late DarkroomJobsDao jobs;

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    targets = DeliveryTargetsDao(db);
    journal = DeliveryJournalDao(db);
    jobs = DarkroomJobsDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> rawContentJson(int id) async {
    final rows = await db
        .customSelect(
          'SELECT content_json FROM delivery_targets WHERE id = ?',
          variables: [Variable<int>(id)],
        )
        .get();
    return rows.single.read<String>('content_json');
  }

  group('DeliveryTargetsDao', () {
    test('create stores the transport config and content selection', () async {
      final id = await targets.create(
        name: 'office-pc',
        kind: ArtifactDestinationKind.sftp,
        configJson: '{"host":"office.lan","port":22,"remoteDir":"/astro"}',
        content: const <ArtifactContent>{
          ArtifactContent.linearMasters,
          ArtifactContent.nightReport,
        },
        secretRef: 'delivery.office_pc_key',
        createdAt: DateTime.utc(2026, 8, 16, 5),
      );

      final destination = await targets.getById(id);
      expect(destination, isNotNull);
      expect(destination!.name, 'office-pc');
      expect(destination.kind, ArtifactDestinationKind.sftp);
      expect(destination.enabled, isTrue);
      expect(destination.secretRef, 'delivery.office_pc_key');
      expect(destination.content, <ArtifactContent>{
        ArtifactContent.linearMasters,
        ArtifactContent.nightReport,
      });
      expect(destination.deliversAnything, isTrue);
      expect(destination.createdAt, DateTime.utc(2026, 8, 16, 5));
    });

    test('the content selection serializes canonically', () async {
      // Two callers build the same selection in opposite orders.
      final forwards = await targets.create(
        name: 'a',
        kind: ArtifactDestinationKind.watchedFolder,
        content: const <ArtifactContent>{
          ArtifactContent.linearMasters,
          ArtifactContent.nightReport,
        },
      );
      final backwards = await targets.create(
        name: 'b',
        kind: ArtifactDestinationKind.watchedFolder,
        content: const <ArtifactContent>{
          ArtifactContent.nightReport,
          ArtifactContent.linearMasters,
        },
      );

      expect(
        await rawContentJson(forwards),
        '["linear_masters","night_report"]',
      );
      expect(
        await rawContentJson(backwards),
        await rawContentJson(forwards),
        reason: 'the same selection must produce the same bytes',
      );
    });

    test('an empty selection is a destination that receives nothing', () async {
      final id = await targets.create(
        name: 'idle',
        kind: ArtifactDestinationKind.peer,
      );
      final destination = await targets.getById(id);
      expect(destination!.content, isEmpty);
      expect(
        destination.deliversAnything,
        isFalse,
        reason: 'enabled with nothing selected still delivers nothing',
      );
    });

    test(
      'key material in config_json is refused on create and on update',
      () async {
        expect(
          () => targets.create(
            name: 'office-pc',
            kind: ArtifactDestinationKind.sftp,
            configJson: '{"host":"office.lan","password":"hunter2"}',
          ),
          throwsA(
            isA<DeliveryConfigSecretException>().having(
              (e) => e.keys,
              'keys',
              <String>['password'],
            ),
          ),
        );

        // Nested and inside a list, not only at the top level.
        expect(
          () => targets.create(
            name: 'nas',
            kind: ArtifactDestinationKind.watchedFolder,
            configJson: '{"auth":{"privateKey":"-----BEGIN"}}',
          ),
          throwsA(isA<DeliveryConfigSecretException>()),
        );
        expect(
          () => targets.create(
            name: 'nas',
            kind: ArtifactDestinationKind.watchedFolder,
            configJson: '{"hosts":[{"apiKey":"abc"}]}',
          ),
          throwsA(isA<DeliveryConfigSecretException>()),
        );
        expect(
          () => targets.create(
            name: 'nas',
            kind: ArtifactDestinationKind.watchedFolder,
            configJson: '["not","an","object"]',
          ),
          throwsA(isA<FormatException>()),
        );

        final id = await targets.create(
          name: 'nas',
          kind: ArtifactDestinationKind.watchedFolder,
          configJson: '{"path":"/mnt/nas/astro"}',
        );
        await expectLater(
          targets.update(id, configJson: '{"path":"/mnt","token":"t"}'),
          throwsA(isA<DeliveryConfigSecretException>()),
        );
        expect(
          (await targets.getById(id))!.configJson,
          '{"path":"/mnt/nas/astro"}',
          reason: 'the refused update must not have landed',
        );
      },
    );

    test(
      'update touches only what it is given, and clearing is explicit',
      () async {
        final id = await targets.create(
          name: 'office-pc',
          kind: ArtifactDestinationKind.sftp,
          configJson: '{"host":"office.lan"}',
          content: const <ArtifactContent>{ArtifactContent.draftRender},
          secretRef: 'delivery.office_pc_key',
          createdAt: DateTime.utc(2026, 8, 16, 5),
        );

        var destination = await targets.update(
          id,
          enabled: false,
          now: DateTime.utc(2026, 8, 16, 9),
        );
        expect(destination.enabled, isFalse);
        expect(destination.updatedAt, DateTime.utc(2026, 8, 16, 9));
        expect(
          destination.secretRef,
          'delivery.office_pc_key',
          reason: 'a partial update must not wipe the keyring reference',
        );
        expect(destination.configJson, '{"host":"office.lan"}');
        expect(destination.content, <ArtifactContent>{
          ArtifactContent.draftRender,
        });

        destination = await targets.update(
          id,
          content: const <ArtifactContent>{ArtifactContent.linearMasters},
        );
        expect(destination.content, <ArtifactContent>{
          ArtifactContent.linearMasters,
        });
        expect(destination.enabled, isFalse);

        destination = await targets.clearSecretRef(id);
        expect(destination.secretRef, isNull);
        expect(destination.configJson, '{"host":"office.lan"}');

        expect(
          () => targets.create(
            name: '',
            kind: ArtifactDestinationKind.watchedFolder,
          ),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          targets.update(id + 9999, enabled: true),
          throwsA(isA<ArtifactDestinationMissingException>()),
        );
      },
    );

    test('listEnabled is the set delivery should visit tonight', () async {
      final on = await targets.create(
        name: 'nas',
        kind: ArtifactDestinationKind.watchedFolder,
        createdAt: DateTime.utc(2026, 8, 16, 5),
      );
      final off = await targets.create(
        name: 'office-pc',
        kind: ArtifactDestinationKind.sftp,
        enabled: false,
        createdAt: DateTime.utc(2026, 8, 16, 6),
      );

      expect((await targets.listAll()).map((d) => d.id).toList(), <int>[
        on,
        off,
      ]);
      expect((await targets.listEnabled()).map((d) => d.id).toList(), <int>[
        on,
      ]);
    });
  });

  group('DeliveryJournalDao', () {
    late int targetId;
    late int jobId;
    const file = '/data/masters/M31_Ha_master.fits';

    setUp(() async {
      targetId = await targets.create(
        name: 'office-pc',
        kind: ArtifactDestinationKind.sftp,
        configJson: '{"host":"office.lan"}',
        content: const <ArtifactContent>{ArtifactContent.linearMasters},
      );
      jobId = await jobs.enqueue();
    });

    test('a retry upserts one row and counts the attempt', () async {
      final first = await journal.recordAttempt(
        targetId: targetId,
        jobId: jobId,
        filePath: file,
        bytes: 2048,
        now: DateTime.utc(2026, 8, 16, 5),
      );
      expect(first.attempts, 1);
      expect(first.state, DeliveryAttemptState.retrying);
      expect(first.bytes, 2048);
      expect(first.deliveredAt, isNull);

      await journal.markRetrying(
        targetId: targetId,
        jobId: jobId,
        filePath: file,
        error: 'Connection refused',
      );

      final second = await journal.recordAttempt(
        targetId: targetId,
        jobId: jobId,
        filePath: file,
        now: DateTime.utc(2026, 8, 16, 5, 30),
      );
      expect(
        second.id,
        first.id,
        reason: 'a retry is an upsert, not an append',
      );
      expect(second.attempts, 2);
      expect(
        second.bytes,
        2048,
        reason: 'a retry that did not restate the size keeps the known one',
      );
      expect(second.state, DeliveryAttemptState.retrying);
      expect(second.updatedAt, DateTime.utc(2026, 8, 16, 5, 30));
      expect(second.createdAt, DateTime.utc(2026, 8, 16, 5));

      expect(
        await journal.listForJob(jobId),
        hasLength(1),
        reason: 'one row per (destination, job, file)',
      );
    });

    test('a delivery that recovered still records what went wrong', () async {
      await journal.recordAttempt(
        targetId: targetId,
        jobId: jobId,
        filePath: file,
        bytes: 4096,
      );
      await journal.markRetrying(
        targetId: targetId,
        jobId: jobId,
        filePath: file,
        error: 'Host unreachable',
      );
      await journal.recordAttempt(
        targetId: targetId,
        jobId: jobId,
        filePath: file,
      );

      final delivered = await journal.markDelivered(
        targetId: targetId,
        jobId: jobId,
        filePath: file,
        checksum: 'sha256:abc123',
        now: DateTime.utc(2026, 8, 16, 6, 12),
      );
      expect(delivered.state, DeliveryAttemptState.delivered);
      expect(delivered.checksum, 'sha256:abc123');
      expect(delivered.deliveredAt, DateTime.utc(2026, 8, 16, 6, 12));
      expect(delivered.attempts, 2);
      expect(
        delivered.lastError,
        'Host unreachable',
        reason: 'the report should be able to say the delivery recovered',
      );
      expect(delivered.bytes, 4096);
      expect(delivered.state.isTerminal, isTrue);
    });

    test('a spent delivery fails with its last reason', () async {
      await journal.recordAttempt(
        targetId: targetId,
        jobId: jobId,
        filePath: file,
      );
      final failed = await journal.markFailed(
        targetId: targetId,
        jobId: jobId,
        filePath: file,
        error: 'nas unreachable after 6 attempts',
      );
      expect(failed.state, DeliveryAttemptState.failed);
      expect(failed.lastError, 'nas unreachable after 6 attempts');
      expect(failed.deliveredAt, isNull);
      expect(await journal.listPendingRetry(), isEmpty);
    });

    test('an outcome for a file nobody attempted is reported', () async {
      await expectLater(
        journal.markDelivered(
          targetId: targetId,
          jobId: jobId,
          filePath: '/data/never-sent.fits',
        ),
        throwsA(isA<DeliveryJournalMissingException>()),
      );
      expect(
        await journal.getEntry(
          targetId: targetId,
          jobId: jobId,
          filePath: '/data/never-sent.fits',
        ),
        isNull,
      );
      expect(
        () => journal.recordAttempt(
          targetId: targetId,
          jobId: jobId,
          filePath: file,
          bytes: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the same file to two destinations keeps two records', () async {
      final second = await targets.create(
        name: 'nas',
        kind: ArtifactDestinationKind.watchedFolder,
        configJson: '{"path":"/mnt/nas"}',
      );
      await journal.recordAttempt(
        targetId: targetId,
        jobId: jobId,
        filePath: file,
      );
      await journal.recordAttempt(
        targetId: second,
        jobId: jobId,
        filePath: file,
      );

      await journal.markDelivered(
        targetId: targetId,
        jobId: jobId,
        filePath: file,
      );
      await journal.markFailed(
        targetId: second,
        jobId: jobId,
        filePath: file,
        error: 'Mount not present',
      );

      final entries = await journal.listForJob(jobId);
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.state).toList(), <DeliveryAttemptState>[
        DeliveryAttemptState.delivered,
        DeliveryAttemptState.failed,
      ]);
      expect(
        (await journal.listForTarget(second)).single.lastError,
        'Mount not present',
      );
    });

    test('listPendingRetry is the overnight sweep work list', () async {
      final other = await targets.create(
        name: 'nas',
        kind: ArtifactDestinationKind.watchedFolder,
      );
      await journal.recordAttempt(
        targetId: targetId,
        jobId: jobId,
        filePath: file,
        now: DateTime.utc(2026, 8, 16, 5),
      );
      await journal.recordAttempt(
        targetId: other,
        jobId: jobId,
        filePath: file,
        now: DateTime.utc(2026, 8, 16, 6),
      );
      await journal.markDelivered(
        targetId: other,
        jobId: jobId,
        filePath: file,
      );

      final pending = await journal.listPendingRetry();
      expect(pending.map((e) => e.targetId).toList(), <int>[targetId]);
    });

    test(
      'the journal cascades with its destination and with its job',
      () async {
        final otherJob = await jobs.enqueue();
        await journal.recordAttempt(
          targetId: targetId,
          jobId: jobId,
          filePath: file,
        );
        await journal.recordAttempt(
          targetId: targetId,
          jobId: otherJob,
          filePath: file,
        );
        expect(await journal.listForTarget(targetId), hasLength(2));

        expect(await jobs.deleteJob(otherJob), 1);
        expect(await journal.listForJob(otherJob), isEmpty);
        expect(await journal.listForTarget(targetId), hasLength(1));

        expect(await targets.deleteTarget(targetId), 1);
        expect(await journal.listForTarget(targetId), isEmpty);
        expect(await journal.listForJob(jobId), isEmpty);
      },
    );
  });
}
