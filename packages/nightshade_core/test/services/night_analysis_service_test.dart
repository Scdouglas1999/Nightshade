import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/daos/night_reports_dao.dart';
import 'package:nightshade_core/src/database/daos/science_dao.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/models/imaging/night_report.dart';
import 'package:nightshade_core/src/services/night_analysis_service.dart';

/// Build a synthetic per-sub series. Each index `i` is one sub captured
/// [cadence] apart starting at [start]; the per-metric closures let a test dial
/// exactly one signal while leaving the rest null/flat.
List<NightSub> _series({
  required int count,
  DateTime? start,
  Duration cadence = const Duration(minutes: 2),
  double? Function(int i)? hfr,
  int? Function(int i)? starCount,
  double? Function(int i)? background,
  double? Function(int i)? guidingRmsTotal,
  double? Function(int i)? eccentricity,
  double? Function(int i)? snr,
  double? Function(int i)? focuserTemp,
}) {
  final t0 = start ?? DateTime.utc(2026, 6, 7, 22);
  return [
    for (var i = 0; i < count; i++)
      NightSub(
        id: i + 1,
        capturedAt: t0.add(cadence * i),
        hfr: hfr?.call(i),
        starCount: starCount?.call(i),
        background: background?.call(i),
        guidingRmsTotal: guidingRmsTotal?.call(i),
        eccentricity: eccentricity?.call(i),
        snr: snr?.call(i),
        focuserTemp: focuserTemp?.call(i),
      ),
  ];
}

NightAnalysisService _pureService() {
  // Detector tests drive analyze() directly; the DAOs are never touched, so a
  // single never-queried in-memory DB underneath them is sufficient. Sharing
  // one DB avoids drift's "multiple databases" warning.
  final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
  return NightAnalysisService(
    images: db.imagesDao,
    science: ScienceDao(db),
    reports: NightReportsDao(db),
    clock: () => DateTime.utc(2026, 6, 8, 6),
  );
}

NightFinding? _finding(NightReport r, String id) {
  for (final f in r.findings) {
    if (f.id == id) return f;
  }
  return null;
}

void main() {
  group('NightAnalysisService detectors (pure analyze)', () {
    late NightAnalysisService svc;
    setUp(() => svc = _pureService());

    test('focus-drift fires on a monotone HFR climb tracking temperature', () {
      // HFR ramps 2.0 → ~3.5 px over 16 subs; focuser temp falls 5 C.
      final data = NightData(
        _series(
          count: 16,
          hfr: (i) => 2.0 + i * 0.10,
          starCount: (i) => 1200,
          focuserTemp: (i) => 5.0 - i * 0.35,
        ),
      );
      final report = svc.analyze(data, sessionId: 1);
      final f = _finding(report, 'focus_drift');
      expect(f, isNotNull, reason: 'focus drift should fire');
      expect(f!.severity, NightFindingSeverity.critical); // >30% rel rise
      expect(f.evidenceSubIds, isNotEmpty);
      expect(f.metricSeries, isNotNull);
      expect(f.advice, contains('emperature')); // temp-comp advice
      expect(report.score, lessThan(100));
    });

    test('focus-drift stays silent on flat HFR (noise only)', () {
      final data = NightData(
        _series(count: 16, hfr: (i) => 2.0 + (i.isEven ? 0.02 : -0.02)),
      );
      final report = svc.analyze(data, sessionId: 1);
      expect(_finding(report, 'focus_drift'), isNull);
    });

    test(
      'guiding-correlation fires when RMS spikes coincide with elongation',
      () {
        // Flat ~0.5" guiding + round stars, except subs 7 and 8 spike to 2.0"
        // with eccentricity 0.7.
        final data = NightData(
          _series(
            count: 14,
            guidingRmsTotal: (i) => (i == 7 || i == 8) ? 2.0 : 0.5,
            eccentricity: (i) => (i == 7 || i == 8) ? 0.70 : 0.30,
          ),
        );
        final report = svc.analyze(data, sessionId: 1);
        final f = _finding(report, 'guiding_correlation');
        expect(f, isNotNull);
        expect(f!.evidenceSubIds, containsAll([8, 9])); // ids are index+1
        expect(f.severity, NightFindingSeverity.critical); // 2.0 > 2x baseline
      },
    );

    test(
      'guiding-correlation silent when RMS data present but no elongation',
      () {
        final data = NightData(
          _series(
            count: 14,
            guidingRmsTotal: (i) => (i == 7 || i == 8) ? 2.0 : 0.5,
            eccentricity: (i) => 0.30, // stars stay round despite the spike
          ),
        );
        final report = svc.analyze(data, sessionId: 1);
        expect(_finding(report, 'guiding_correlation'), isNull);
      },
    );

    test('guiding-correlation silent when eccentricity data is missing', () {
      final data = NightData(
        _series(
          count: 14,
          guidingRmsTotal: (i) => (i == 7 || i == 8) ? 2.0 : 0.5,
          // eccentricity all null
        ),
      );
      final report = svc.analyze(data, sessionId: 1);
      expect(_finding(report, 'guiding_correlation'), isNull);
    });

    test(
      'dew/HFR-collapse fires on a sharp irreversible HFR step + star loss',
      () {
        // HFR sits ~2.0 for 5 subs then jumps to ~4.5 and stays; stars halve.
        final data = NightData(
          _series(
            count: 12,
            hfr: (i) => i < 5 ? 2.0 : 4.5,
            starCount: (i) => i < 5 ? 1500 : 500,
          ),
        );
        final report = svc.analyze(data, sessionId: 1);
        final f = _finding(report, 'dew_hfr_collapse');
        expect(f, isNotNull);
        expect(f!.severity, NightFindingSeverity.critical);
        expect(
          f.evidenceSubIds,
          contains(6),
        ); // first post-collapse sub (index5)
        expect(f.title.toLowerCase(), contains('dew'));
      },
    );

    test('dew/HFR-collapse silent when HFR recovers (transient, not dew)', () {
      // One bad sub then back to baseline — must NOT read as an irreversible
      // collapse (and the slow-drift detector must not fire either).
      final data = NightData(
        _series(
          count: 12,
          hfr: (i) => i == 5 ? 4.5 : 2.0,
          starCount: (i) => 1500,
        ),
      );
      final report = svc.analyze(data, sessionId: 1);
      expect(_finding(report, 'dew_hfr_collapse'), isNull);
    });

    test('cloud/transparency-step clusters consecutive low-SNR subs into an '
        'event', () {
      // SNR ~40 baseline; subs 6,7,8 collapse to ~10 (clouds), then recover.
      final data = NightData(
        _series(
          count: 16,
          snr: (i) => (i >= 6 && i <= 8) ? 10.0 : 40.0,
          starCount: (i) => 1000,
        ),
      );
      final report = svc.analyze(data, sessionId: 1);
      final f = _finding(report, 'cloud_transparency');
      expect(f, isNotNull);
      // The 3-sub event → ids 7,8,9.
      expect(f!.evidenceSubIds, containsAll([7, 8, 9]));
      expect(f.severity, NightFindingSeverity.critical); // ~75% drop
      expect(f.explanation.toLowerCase(), contains('transparency'));
    });

    test('cloud-step falls back to star count when science SNR is absent', () {
      final data = NightData(
        _series(
          count: 16,
          // no snr → uses starCount; subs 9,10 drop to a fifth.
          starCount: (i) => (i == 9 || i == 10) ? 200 : 1000,
        ),
      );
      final report = svc.analyze(data, sessionId: 1);
      final f = _finding(report, 'cloud_transparency');
      expect(f, isNotNull);
      expect(f!.evidenceSubIds, containsAll([10, 11]));
    });

    test(
      'cloud-step ignores a single isolated dropout (needs >= 2 in a row)',
      () {
        final data = NightData(
          _series(
            count: 16,
            snr: (i) => i == 8 ? 8.0 : 40.0, // one bad sub only
            starCount: (i) => 1000,
          ),
        );
        final report = svc.analyze(data, sessionId: 1);
        expect(_finding(report, 'cloud_transparency'), isNull);
      },
    );

    test('cloud-step does NOT switch to SNR mode on partial coverage '
        '(no false storm when science ran for only a few subs)', () {
      // Science SNR exists for just 5 of 16 subs — the exact "pipeline stopped"
      // scenario. Those 5 are all healthy (40); star count is flat across the
      // whole night. Old behaviour: `useSnr` flipped true on ANY snr, dropped
      // the 11 snr-less subs, and built the baseline from a non-representative
      // subset. Correct behaviour: <80% coverage stays in star-count mode and,
      // because star count never dips, emits NOTHING.
      final data = NightData(
        _series(
          count: 16,
          snr: (i) => i < 5 ? 40.0 : null,
          starCount: (i) => 1000,
        ),
      );
      final report = svc.analyze(data, sessionId: 1);
      expect(_finding(report, 'cloud_transparency'), isNull);
    });

    test('cloud-step uses SNR mode only with near-complete coverage and fires '
        'on a real run', () {
      // 15/16 subs carry SNR (>=80%); subs 6,7,8 collapse — a genuine event.
      final data = NightData(
        _series(
          count: 16,
          snr: (i) => i == 0 ? null : ((i >= 6 && i <= 8) ? 10.0 : 40.0),
          starCount: (i) => 1000,
        ),
      );
      final report = svc.analyze(data, sessionId: 1);
      final f = _finding(report, 'cloud_transparency');
      expect(f, isNotNull);
      expect(f!.evidenceSubIds, containsAll([7, 8, 9]));
    });

    test('every detector is silent on an empty / signal-less night', () {
      // Subs exist but carry no usable per-sub metric → no findings, clean
      // score, neutral headline.
      final data = NightData(_series(count: 20));
      final report = svc.analyze(data, sessionId: 1);
      expect(report.findings, isEmpty);
      expect(report.score, 100);
      expect(report.headline.toLowerCase(), contains('clean'));
    });

    test('tilt/collimation detector is silent without per-sub field data', () {
      final data = NightData(_series(count: 20, hfr: (i) => 2.0));
      final report = svc.analyze(data, sessionId: 1);
      expect(_finding(report, 'tilt_collimation'), isNull);
    });
  });

  group('NightAnalysisService scoring', () {
    test('score is monotone non-increasing as severity worsens', () {
      final svc = _pureService();

      // Clean night.
      final clean = svc.analyze(NightData(_series(count: 20)));

      // A warn-level focus drift: rel rise lands between 12% and 30%.
      final warn = svc.analyze(
        NightData(
          _series(
            count: 16,
            hfr: (i) => 2.0 + i * 0.06, // early≈2.21 → late≈2.69, ~22% rise
          ),
        ),
      );

      // A critical dew collapse.
      final critical = svc.analyze(
        NightData(
          _series(
            count: 12,
            hfr: (i) => i < 5 ? 2.0 : 4.5,
            starCount: (i) => i < 5 ? 1500 : 500,
          ),
        ),
      );

      expect(clean.score, 100);
      expect(warn.score, lessThan(clean.score));
      expect(critical.score, lessThan(warn.score));

      // Sanity: the warn report's dominant finding is a warn, the critical's a
      // critical — confirms the monotonicity is severity-driven.
      expect(warn.findings.first.severity, NightFindingSeverity.warn);
      expect(critical.findings.first.severity, NightFindingSeverity.critical);
    });

    test(
      'findings are ranked most-severe first and headline reflects worst',
      () {
        final svc = _pureService();
        // Stack a critical dew collapse with a warn-ish background rise so >1
        // finding is present.
        final data = NightData(
          _series(
            count: 14,
            hfr: (i) => i < 6 ? 2.0 : 4.6,
            starCount: (i) => i < 6 ? 1500 : 500,
            background: (i) => 100.0 + i * 12.0, // steady rise
          ),
        );
        final report = svc.analyze(data);
        expect(report.findings.length, greaterThanOrEqualTo(2));
        expect(report.findings.first.severity, NightFindingSeverity.critical);
        expect(report.headline.toLowerCase(), contains('rough night'));
      },
    );
  });

  group('NightAnalysisService DB-bound computeReport', () {
    late NightshadeDatabase db;
    late NightAnalysisService svc;

    setUp(() {
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      svc = NightAnalysisService(
        images: db.imagesDao,
        science: ScienceDao(db),
        reports: NightReportsDao(db),
        clock: () => DateTime.utc(2026, 6, 8, 6),
      );
    });

    tearDown(() async => db.close());

    Future<int> insertSession() {
      return db
          .into(db.imagingSessions)
          .insert(
            ImagingSessionsCompanion.insert(
              startTime: DateTime.utc(2026, 6, 7, 22),
            ),
          );
    }

    Future<void> insertSub({
      required int sessionId,
      required int index,
      required double hfr,
      int starCount = 1500,
    }) async {
      await db
          .into(db.capturedImages)
          .insert(
            CapturedImagesCompanion.insert(
              filePath: '/lights/sub_$index.fits',
              fileName: 'sub_$index.fits',
              frameType: const Value('light'),
              exposureDuration: 120.0,
              capturedAt: DateTime.utc(
                2026,
                6,
                7,
                22,
              ).add(Duration(minutes: 2 * index)),
              sessionId: Value(sessionId),
              binX: const Value(1),
              binY: const Value(1),
              hfr: Value(hfr),
              starCount: Value(starCount),
              isAccepted: const Value(true),
            ),
          );
    }

    test(
      'computeReport reads subs, detects, and persists a night_reports row',
      () async {
        final sessionId = await insertSession();
        // A clean dew collapse: HFR jumps at sub 6 and stars halve.
        for (var i = 0; i < 12; i++) {
          await insertSub(
            sessionId: sessionId,
            index: i,
            hfr: i < 6 ? 2.0 : 4.6,
            starCount: i < 6 ? 1500 : 500,
          );
        }

        final report = await svc.computeReport(sessionId: sessionId);
        expect(report.sessionId, sessionId);
        expect(report.score, lessThan(100));
        final dew = _finding(report, 'dew_hfr_collapse');
        expect(dew, isNotNull);

        // Persisted and round-trips through the DAO.
        final stored = await NightReportsDao(db).latestForSession(sessionId);
        expect(stored, isNotNull);
        expect(stored!.score, report.score);
        expect(stored.headline, report.headline);
        expect(_finding(stored, 'dew_hfr_collapse'), isNotNull);
      },
    );

    test(
      'computeReport on a session with no lights yields a clean report',
      () async {
        final sessionId = await insertSession();
        final report = await svc.computeReport(sessionId: sessionId);
        expect(report.findings, isEmpty);
        expect(report.score, 100);
        // Still persisted (an empty report is a valid verdict).
        final stored = await NightReportsDao(db).latestForSession(sessionId);
        expect(stored, isNotNull);
      },
    );

    test('computeReport with persist:false does not write a row', () async {
      final sessionId = await insertSession();
      for (var i = 0; i < 10; i++) {
        await insertSub(sessionId: sessionId, index: i, hfr: 2.0);
      }
      await svc.computeReport(sessionId: sessionId, persist: false);
      final stored = await NightReportsDao(db).getForSession(sessionId);
      expect(stored, isEmpty);
    });

    test('defaulted-0.0 science snr rows do NOT fire a false cloud storm', () async {
      // A clean night: flat HFR, flat star count. Science wrote a frame-quality
      // row for every sub, but only filled snr on a handful — the rest carry the
      // non-nullable column's 0.0 DEFAULT (science.dart:171), i.e. missing
      // signal, not a real reading of zero. The cloud detector must NOT treat
      // those 0.0 rows as catastrophic transparency dropouts.
      final sessionId = await insertSession();
      final imageIds = <int>[];
      for (var i = 0; i < 12; i++) {
        await insertSub(
          sessionId: sessionId,
          index: i,
          hfr: 2.0,
          starCount: 1500,
        );
        final id =
            await (db.select(db.capturedImages)
                  ..where((t) => t.fileName.equals('sub_$i.fits')))
                .getSingle()
                .then((r) => r.id);
        imageIds.add(id);
      }
      // Science rows for all 12 subs; snr filled (real, positive) for the first
      // four, left at the 0.0 default for the remaining eight.
      for (var i = 0; i < imageIds.length; i++) {
        await db
            .into(db.scienceFrameQualityMetrics)
            .insert(
              ScienceFrameQualityMetricsCompanion.insert(
                capturedImageId: Value(imageIds[i]),
                sessionId: Value(sessionId),
                snr: i < 4 ? const Value(38.0) : const Value(0.0),
              ),
            );
      }

      final report = await svc.computeReport(sessionId: sessionId);
      // No transparency finding: the 0.0 rows are dropped as missing signal, the
      // detector falls back to the flat star count, and nothing dips.
      expect(_finding(report, 'cloud_transparency'), isNull);
    });
  });
}
