// A process killed mid-integration must not leave the night silent.
//
// The post-session pass integrates first and enqueues its Darkroom job second,
// so `_recoverInterruptedDarkroomJobs` has nothing to find when the kill lands
// during the integrate — the longest stretch of the night. The marker file
// this suite covers is the whole record that it happened.
//
// Tested the honest way, the same shape as darkroom_job_recovery_test.dart:
// write the marker, open the database, and read what the open did.

import 'dart:convert';
import 'dart:io';

// Only the two query primitives: drift also exports `isNull` / `isNotNull`
// column matchers that collide with the test matchers of the same name.
import 'package:drift/drift.dart' show UpdateKind, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/database/integration_stage_marker.dart';
import 'package:nightshade_core/src/database/sqlite_busy.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nightshade_integ_');
    dbFile = File('${tempDir.path}/nightshade.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  NightshadeDatabase open() => NightshadeDatabase.forTesting(
    NativeDatabase(dbFile, setup: applySqliteBusyTimeout),
  );

  Future<int> seedSession() async {
    final db = open();
    final id = await db.customInsert(
      'INSERT INTO imaging_sessions(start_time, status) VALUES (?, ?)',
      variables: [
        Variable<int>(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        const Variable<String>('completed'),
      ],
    );
    await db.close();
    return id;
  }

  Future<({String? notes, List<Map<String, Object?>> events})> reopenAndRead(
    int sessionId,
  ) async {
    final db = open();
    final notes = await db
        .customSelect(
          'SELECT notes FROM imaging_sessions WHERE id = ?',
          variables: [Variable<int>(sessionId)],
        )
        .getSingle();
    final events = await db
        .customSelect(
          'SELECT event_type, category, severity, headline, body, dedupe_key '
          'FROM narrator_events WHERE session_id = ?',
          variables: [Variable<int>(sessionId)],
        )
        .get();
    await db.close();
    return (
      notes: notes.data['notes'] as String?,
      events: events.map((e) => e.data).toList(),
    );
  }

  test(
    'an interrupted integration is reported and names its orphans',
    () async {
      final sessionId = await seedSession();

      // The masters the pass was going to write. One made it to disk before the
      // kill (truncated), one never got created.
      final orphan = File('${tempDir.path}/M31_L_master_123.fits');
      await orphan.writeAsString('half a FITS');
      final never = '${tempDir.path}/M31_Ha_master_123.fits';

      await markIntegrationStarted(
        tempDir,
        InterruptedIntegration(
          sessionId: sessionId,
          targetName: 'M31',
          startedAtUtc: DateTime.utc(2026, 8, 17, 3, 30),
          intendedMasterPaths: [orphan.path, never],
        ),
      );

      final read = await reopenAndRead(sessionId);

      expect(read.notes, isNotNull, reason: 'the night must not stay silent');
      expect(read.notes, contains('interrupted'));
      expect(
        read.notes,
        contains(orphan.path),
        reason: 'a truncated FITS is present and non-empty and looks finished',
      );
      expect(
        read.notes,
        isNot(contains(never)),
        reason: 'a file that was never written is not an orphan to delete',
      );

      expect(read.events, hasLength(1));
      final event = read.events.single;
      expect(event['event_type'], 'quality.integration_interrupted');
      expect(event['severity'], 'warning');
      expect(event['body'], contains(orphan.path));
      expect(event['dedupe_key'], contains('2026-08-17T03:30:00.000Z'));

      expect(
        await integrationMarkerFile(tempDir).exists(),
        isFalse,
        reason: 'reported once — the marker is consumed after the report lands',
      );
    },
  );

  test('a second open does not repeat the warning', () async {
    final sessionId = await seedSession();
    await markIntegrationStarted(
      tempDir,
      InterruptedIntegration(
        sessionId: sessionId,
        targetName: null,
        startedAtUtc: DateTime.utc(2026, 8, 17, 3, 30),
        intendedMasterPaths: const [],
      ),
    );

    final first = await reopenAndRead(sessionId);
    final second = await reopenAndRead(sessionId);

    expect(first.events, hasLength(1));
    expect(second.events, hasLength(1));
    expect(second.notes, first.notes);
  });

  test('a clean shutdown leaves nothing to report', () async {
    final sessionId = await seedSession();
    await markIntegrationStarted(
      tempDir,
      InterruptedIntegration(
        sessionId: sessionId,
        targetName: 'M42',
        startedAtUtc: DateTime.utc(2026, 8, 17, 3, 30),
        intendedMasterPaths: const [],
      ),
    );
    await clearIntegrationMarker(tempDir);

    final read = await reopenAndRead(sessionId);
    expect(read.notes, isNull);
    expect(read.events, isEmpty);
  });

  test('an existing note is appended to, never replaced', () async {
    final sessionId = await seedSession();
    final db = open();
    await db.customUpdate(
      'UPDATE imaging_sessions SET notes = ? WHERE id = ?',
      variables: [
        const Variable<String>('Guiding was rough after 2am.'),
        Variable<int>(sessionId),
      ],
      updateKind: UpdateKind.update,
    );
    await db.close();

    await markIntegrationStarted(
      tempDir,
      InterruptedIntegration(
        sessionId: sessionId,
        targetName: 'M42',
        startedAtUtc: DateTime.utc(2026, 8, 17, 3, 30),
        intendedMasterPaths: const [],
      ),
    );

    final read = await reopenAndRead(sessionId);
    expect(read.notes, contains('Guiding was rough after 2am.'));
    expect(read.notes, contains('interrupted'));
  });

  test(
    'an unreadable marker reports nothing and is kept for support',
    () async {
      final sessionId = await seedSession();
      await integrationMarkerFile(tempDir).writeAsString('{not json');

      final read = await reopenAndRead(sessionId);
      expect(read.notes, isNull, reason: 'no session id to attribute it to');
      expect(read.events, isEmpty);
      expect(
        await integrationMarkerFile(tempDir).exists(),
        isTrue,
        reason: 'evidence is left on disk rather than silently deleted',
      );
    },
  );

  group('InterruptedIntegration', () {
    test('round-trips through its payload', () {
      final original = InterruptedIntegration(
        sessionId: 12,
        targetName: 'NGC 7000',
        startedAtUtc: DateTime.utc(2026, 8, 17, 4),
        intendedMasterPaths: const ['/a/one.fits', '/a/two.fits'],
      );
      final parsed = InterruptedIntegration.fromJson(
        jsonEncode(original.toJson()),
      )!;

      expect(parsed.sessionId, 12);
      expect(parsed.targetName, 'NGC 7000');
      expect(parsed.startedAtUtc, original.startedAtUtc);
      expect(parsed.intendedMasterPaths, original.intendedMasterPaths);
    });

    test('refuses a payload with no session to attribute', () {
      expect(
        InterruptedIntegration.fromJson('{"startedAtUtc":"2026-08-17T04:00Z"}'),
        isNull,
      );
      expect(InterruptedIntegration.fromJson('{"sessionId":3}'), isNull);
      expect(InterruptedIntegration.fromJson('[]'), isNull);
    });
  });
}
