// ScienceReportExporter — markdown shape and content guard.
//
// We build an in-memory database, seed a session with light frames, a few
// calibration rows, and a transparency sample, then assert that the
// markdown output contains the section headers and the headline numbers.
// The intent is that *any future regression* — a typo in a section title,
// a unit swap, a missing field — fails the test.

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

NightshadeDatabase _openInMemory() {
  return NightshadeDatabase.forTesting(NativeDatabase.memory());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;
  late ScienceReportExporter exporter;

  setUp(() async {
    db = _openInMemory();
    exporter = ScienceReportExporter(
      imagesDao: ImagesDao(db),
      scienceDao: ScienceDao(db),
      sessionsDao: SessionsDao(db),
      targetsDao: TargetsDao(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedTargetAndSession() async {
    final targetId = await db.targetsDao.createTarget(
      TargetsCompanion.insert(
        name: 'NGC 7000',
        ra: 312.5,
        dec: 44.3,
        constellation: const drift.Value('Cygnus'),
      ),
    );
    final sessionId = await db.sessionsDao.startSession(
      targetId: targetId,
      name: 'Test session',
    );
    return sessionId;
  }

  test('markdown includes every expected section, even when empty', () async {
    final sessionId = await seedTargetAndSession();
    final md = await exporter.buildMarkdown(sessionId);
    for (final heading in [
      '# Nightshade Science Report',
      '## Session',
      '## Frames',
      '## Photometry',
      '## Transparency',
      '## Field quality',
      '## Filter breakdown',
      '## Moving objects',
    ]) {
      expect(md, contains(heading), reason: 'missing section "$heading"');
    }
    expect(md, contains('NGC 7000'));
    expect(md, contains('No photometric calibration produced this session.'));
    expect(md, contains('No transparency samples produced.'));
  });

  test('markdown reports photometric snapshot when data exists', () async {
    final sessionId = await seedTargetAndSession();
    final dao = db.scienceDao;
    final ts = DateTime.parse('2025-01-01T22:00:00.000Z');

    for (var i = 0; i < 6; i++) {
      await dao.insertFrameCalibration(
        FramePhotometricCalibrationCompanion.insert(
          sessionId: drift.Value(sessionId),
          isCalibrated: const drift.Value(true),
          zeroPoint: drift.Value(24.1 + i * 0.05),
          calibrationRms: const drift.Value(0.04),
          matchedStarCount: const drift.Value(28),
          limitingMag5Sigma: drift.Value(20.8 + i * 0.02),
          catalogSource: const drift.Value('localGaia'),
          timestamp: drift.Value(ts.add(Duration(minutes: i * 5))),
        ),
      );
    }

    await dao.insertTransparencySample(
      TransparencySamplesCompanion.insert(
        sessionId: drift.Value(sessionId),
        transparencyPercent: 87.0,
        extinctionCoefficient: const drift.Value(0.21),
        qualityBucket: const drift.Value('good'),
        confidence: const drift.Value(0.78),
        timestamp: drift.Value(ts),
      ),
    );

    final md = await exporter.buildMarkdown(sessionId);
    expect(md, contains('Latest zero point'));
    // The latest ZP is the 6th value (24.10 + 5*0.05 = 24.35) so we expect
    // exactly "24.35".
    expect(md, contains('24.35'));
    expect(md, contains('Median ZP across 6 frames'));
    expect(md, contains('Catalog source(s):**'));
    expect(md, contains('87% (good)'));
  });
}
