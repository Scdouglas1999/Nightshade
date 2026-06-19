import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/analytics/widgets/science_onboarding/science_ladder_model.dart';

ScienceLadderProgress _eval({
  bool hasCalibration = false,
  bool hasTarget = false,
  bool photometryLive = false,
  int lightCurvePoints = 0,
  bool hasPeriodResult = false,
  bool hasExportableData = false,
}) {
  return evaluateLadder(
    hasCalibration: hasCalibration,
    hasTarget: hasTarget,
    photometryLive: photometryLive,
    lightCurvePoints: lightCurvePoints,
    hasPeriodResult: hasPeriodResult,
    hasExportableData: hasExportableData,
  );
}

void main() {
  test('kScienceLadder covers all five rungs in order', () {
    expect(
      kScienceLadder.map((s) => s.rung).toList(),
      ScienceRung.values,
    );
  });

  group('fresh start', () {
    final p = _eval();

    test('measure is the only actionable rung', () {
      expect(p.states[ScienceRung.measure], RungState.ready);
      expect(p.nextActionable, ScienceRung.measure);
    });

    test('every later rung is locked', () {
      expect(p.states[ScienceRung.track], RungState.locked);
      expect(p.states[ScienceRung.curve], RungState.locked);
      expect(p.states[ScienceRung.period], RungState.locked);
      expect(p.states[ScienceRung.contribute], RungState.locked);
    });

    test('nothing is done yet', () {
      expect(p.doneCount, 0);
    });
  });

  group('measure rung', () {
    test('ready without calibration, done with it', () {
      expect(_eval().states[ScienceRung.measure], RungState.ready);
      expect(
        _eval(hasCalibration: true).states[ScienceRung.measure],
        RungState.done,
      );
    });

    test('calibration unlocks track to ready', () {
      final p = _eval(hasCalibration: true);
      expect(p.states[ScienceRung.track], RungState.ready);
      expect(p.nextActionable, ScienceRung.track);
    });
  });

  group('track rung', () {
    test('locked until calibration', () {
      expect(_eval().states[ScienceRung.track], RungState.locked);
    });

    test('ready once calibrated', () {
      expect(
        _eval(hasCalibration: true).states[ScienceRung.track],
        RungState.ready,
      );
    });

    test('done only when photometry is live and a target is set', () {
      expect(
        _eval(hasCalibration: true, photometryLive: true)
            .states[ScienceRung.track],
        RungState.ready,
      );
      expect(
        _eval(hasCalibration: true, hasTarget: true).states[ScienceRung.track],
        RungState.ready,
      );
      expect(
        _eval(hasCalibration: true, photometryLive: true, hasTarget: true)
            .states[ScienceRung.track],
        RungState.done,
      );
    });
  });

  group('curve rung', () {
    test('locked until photometry is live', () {
      expect(
        _eval(hasCalibration: true, hasTarget: true).states[ScienceRung.curve],
        RungState.locked,
      );
    });

    test('ready once photometry is live', () {
      final p =
          _eval(hasCalibration: true, hasTarget: true, photometryLive: true);
      expect(p.states[ScienceRung.curve], RungState.ready);
      expect(p.nextActionable, ScienceRung.curve);
    });

    test('done at ten or more points', () {
      expect(
        _eval(
          hasCalibration: true,
          hasTarget: true,
          photometryLive: true,
          lightCurvePoints: 9,
        ).states[ScienceRung.curve],
        RungState.ready,
      );
      expect(
        _eval(
          hasCalibration: true,
          hasTarget: true,
          photometryLive: true,
          lightCurvePoints: 10,
        ).states[ScienceRung.curve],
        RungState.done,
      );
    });
  });

  group('period rung', () {
    test('locked under ten points', () {
      final p = _eval(
        hasCalibration: true,
        hasTarget: true,
        photometryLive: true,
        lightCurvePoints: 9,
      );
      expect(p.states[ScienceRung.period], RungState.locked);
    });

    test('ready at ten points', () {
      final p = _eval(
        hasCalibration: true,
        hasTarget: true,
        photometryLive: true,
        lightCurvePoints: 10,
      );
      expect(p.states[ScienceRung.period], RungState.ready);
      expect(p.nextActionable, ScienceRung.period);
    });

    test('done when a period result exists', () {
      final p = _eval(
        hasCalibration: true,
        hasTarget: true,
        photometryLive: true,
        lightCurvePoints: 12,
        hasPeriodResult: true,
      );
      expect(p.states[ScienceRung.period], RungState.done);
    });
  });

  group('contribute rung', () {
    test('locked while period is locked', () {
      expect(_eval().states[ScienceRung.contribute], RungState.locked);
    });

    test('ready when exportable data exists and the chain is open', () {
      final p = _eval(
        hasCalibration: true,
        hasTarget: true,
        photometryLive: true,
        lightCurvePoints: 12,
        hasExportableData: true,
      );
      expect(p.states[ScienceRung.contribute], RungState.ready);
    });

    test('never auto-set to done', () {
      final p = _eval(
        hasCalibration: true,
        hasTarget: true,
        photometryLive: true,
        lightCurvePoints: 20,
        hasPeriodResult: true,
        hasExportableData: true,
      );
      expect(p.states[ScienceRung.contribute], RungState.ready);
    });
  });

  group('full progression', () {
    test('climbs locked -> ready -> done as inputs accumulate', () {
      final p = _eval(
        hasCalibration: true,
        hasTarget: true,
        photometryLive: true,
        lightCurvePoints: 15,
        hasPeriodResult: true,
        hasExportableData: true,
      );
      expect(p.states[ScienceRung.measure], RungState.done);
      expect(p.states[ScienceRung.track], RungState.done);
      expect(p.states[ScienceRung.curve], RungState.done);
      expect(p.states[ScienceRung.period], RungState.done);
      expect(p.states[ScienceRung.contribute], RungState.ready);
      expect(p.doneCount, 4);
      expect(p.nextActionable, ScienceRung.contribute);
    });
  });
}
