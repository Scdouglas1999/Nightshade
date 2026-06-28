// Dart side of the Rust↔Dart scoring parity contract.
//
// The Rust port lives at `native/nightshade_native/sequencer/src/scheduling/
// scoring.rs::score_altitude`. This test is a REAL cross-language canary:
//   * it drives the production Dart scorer (`TargetScoringService`, via the
//     `debugScoreAltitude` seam) — NOT a re-implementation that can only ever
//     agree with itself, and
//   * it derives the EXPECTED values by parsing the breakpoints/slopes out of
//     the Rust `score_altitude` source, so editing either side without the
//     other trips the test.
//
// If the native tree is absent (some CI shards strip it), the Rust-derived
// arm is skipped, but the production-scorer pins below still run.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

class _Fixture implements CelestialObject {
  @override
  final String id;
  @override
  final String name;
  @override
  final CelestialCoordinate coordinates;

  const _Fixture({
    required this.id,
    required this.name,
    required this.coordinates,
  });

  @override
  double? get magnitude => null;
}

void main() {
  group('Rust↔Dart scoring parity', () {
    test('public scoreTarget routes altitude through the real piecewise', () {
      // Contract: TargetScore.altitudeScore from the PUBLIC scoreTarget path is
      // exactly what the production `_scoreAltitude` piecewise (exposed via the
      // `debugScoreAltitude` seam) yields for that frame's current altitude.
      // This ties the seam used by the parity assertions below to the same code
      // the real scorer runs — so neither can drift from the other unnoticed.
      final observer = DateTime.utc(2026, 1, 15, 6, 0, 0);
      const m42 = _Fixture(
        id: 'm42',
        name: 'M42',
        coordinates: CelestialCoordinate(ra: 5.5880, dec: -5.39),
      );
      const moon = (75.0, 18.0);

      final service = TargetScoringService(
        latitude: 40.0,
        longitude: -74.0,
        observationTime: observer,
        moonPosition: moon,
        moonIllumination: 50.0,
      );
      final score = service.scoreTarget(m42);

      final currentAlt = score.visibility.currentAltitude;
      // No re-implementation: assert the PUBLIC result equals the REAL private
      // scorer for the same altitude.
      expect(
        score.altitudeScore,
        service.debugScoreAltitude(currentAlt),
        reason:
            'scoreTarget.altitudeScore must come straight from _scoreAltitude',
      );
      expect(score.totalScore.isFinite, isTrue);
      expect(score.totalScore >= 0 && score.totalScore <= 100, isTrue);
    });

    test('real scorer reproduces the published altitude anchors', () {
      // Drive the PRODUCTION piecewise (via the seam) at hand-anchored
      // altitudes and assert exact outputs. These anchors are the published
      // contract {0->0, 7.5->15, 15->30, 30->60, >=60->100} plus two interior
      // points; if the production formula changes, this fails.
      final service = TargetScoringService(
        latitude: 40.0,
        longitude: -74.0,
        observationTime: DateTime.utc(2026, 1, 15, 6, 0, 0),
      );
      const anchors = <(double, double)>[
        (-10.0, 0.0),
        (0.0, 0.0),
        (7.5, 15.0),
        (15.0, 30.0),
        (22.5, 45.0), // 30 + 7.5*2
        (30.0, 60.0),
        (45.0, 79.95), // 60 + 15*1.33
        (60.0, 100.0),
        (89.0, 100.0),
      ];
      for (final (alt, expected) in anchors) {
        expect(
          service.debugScoreAltitude(alt),
          closeTo(expected, 1e-9),
          reason: 'real _scoreAltitude($alt) must equal $expected',
        );
      }
    });

    test(
      'moon-proximity warnings match between scoreTarget and scoreTargetForNight',
      () {
        // The two warning generators share one moon-proximity helper; this
        // pins that they emit the IDENTICAL (type/severity/message/suggestion)
        // moon warnings for a target sitting at a fixed separation from a fixed
        // Moon. We sweep the illumination/distance regimes that select each of
        // the three moon-proximity branches (critical/warning/caution) plus the
        // "no warning" regime.
        //
        // To make the two call sites see the SAME (moonDist, moonIllumination)
        // we place the target exactly AT the Moon's coordinates so the angular
        // separation is 0 (< 15°, the critical branch) for both, and vary the
        // illumination through the service.
        for (final illum in [10.0, 30.0, 60.0, 80.0]) {
          final observer = DateTime.utc(2026, 1, 15, 6, 0, 0);
          const moon = (75.0, 18.0);
          const atMoon = _Fixture(
            id: 'atmoon',
            name: 'AtMoon',
            // RA in hours: 75° / 15 = 5h.
            coordinates: CelestialCoordinate(ra: 5.0, dec: 18.0),
          );

          final service = TargetScoringService(
            latitude: 40.0,
            longitude: -74.0,
            observationTime: observer,
            moonPosition: moon,
            moonIllumination: illum,
          );

          final instant = service
              .scoreTarget(atMoon)
              .warnings
              .where((w) => w.type == WarningType.moonProximity)
              .toList();
          final night = service
              .scoreTargetForNight(
                target: atMoon,
                nightStart: observer.subtract(const Duration(hours: 4)),
                nightEnd: observer.add(const Duration(hours: 4)),
              )
              .warnings
              .where((w) => w.type == WarningType.moonProximity)
              .toList();

          expect(
            night.length,
            instant.length,
            reason: 'moon warning count must match at illum=$illum',
          );
          for (var i = 0; i < instant.length; i++) {
            expect(night[i].type, instant[i].type);
            expect(night[i].severity, instant[i].severity);
            expect(night[i].message, instant[i].message);
            expect(night[i].suggestion, instant[i].suggestion);
          }
        }
      },
    );

    test('default weights sum to 1.0', () {
      const weights = ScoringWeights();
      final sum =
          weights.altitudeWeight +
          weights.moonDistanceWeight +
          weights.transitProximityWeight +
          weights.darknessWeight +
          weights.airmassWeight;
      expect(
        (sum - 1.0).abs() < 1e-9,
        isTrue,
        reason: 'sum=$sum (must be 1.0)',
      );
    });

    test('real Dart scorer matches the Rust score_altitude source', () {
      // CROSS-LANGUAGE canary. Parse the Rust `score_altitude` piecewise and
      // build the EXPECTED closure from the parsed breakpoints/slopes, then run
      // the REAL Dart scorer over a sweep and assert agreement. Editing either
      // side's constants without the other trips this.
      final candidates = [
        File(
          '../../native/nightshade_native/sequencer/src/scheduling/scoring.rs',
        ),
        File(
          '${Directory.current.path}/../../native/nightshade_native/sequencer/'
          'src/scheduling/scoring.rs',
        ),
      ];
      final rustFile = candidates.firstWhere(
        (f) => f.existsSync(),
        orElse: () => candidates.first,
      );
      if (!rustFile.existsSync()) {
        // Native tree stripped on this shard; the production-scorer pins above
        // still guard the Dart side. Skip the cross-language arm.
        return;
      }
      final src = rustFile.readAsStringSync();

      // Isolate the `fn score_altitude(...) { ... }` body.
      final fnMatch = RegExp(
        r'fn score_altitude\(altitude: f64\) -> f64 \{(.*?)\n\}',
        dotAll: true,
      ).firstMatch(src);
      expect(
        fnMatch,
        isNotNull,
        reason: 'could not locate Rust fn score_altitude in scoring.rs',
      );
      final body = fnMatch!.group(1)!;

      // Breakpoints, in source order: `if altitude < <X>`.
      final breakpoints = RegExp(
        r'altitude < ([0-9.]+)',
      ).allMatches(body).map((m) => double.parse(m.group(1)!)).toList();
      // Slope of the first linear segment: `return altitude * <slope>`.
      final slope0 = double.parse(
        RegExp(r'return altitude \* ([0-9.]+)').firstMatch(body)!.group(1)!,
      );
      // Subsequent segments: `return <base> + (altitude - <pivot>) * <slope>`.
      final segments =
          RegExp(
            r'return ([0-9.]+) \+ \(altitude - ([0-9.]+)\) \* ([0-9.]+)',
          ).allMatches(body).map((m) {
            return (
              base: double.parse(m.group(1)!),
              pivot: double.parse(m.group(2)!),
              slope: double.parse(m.group(3)!),
            );
          }).toList();
      // Terminal constant: the bare `100.0` (or similar) returned at the top.
      final terminal = double.parse(
        RegExp(
          r'\n\s*([0-9.]+)\s*\n\}',
          dotAll: true,
        ).firstMatch('$body\n}')!.group(1)!,
      );

      // Pin the SHAPE so a reshaped piecewise (added/removed branch) trips the
      // structural expectation rather than silently passing.
      expect(breakpoints, [0.0, 15.0, 30.0, 60.0]);
      expect(segments, hasLength(2));

      // Reconstruct the oracle FROM the parsed Rust constants.
      double expectedFromRust(double alt) {
        if (alt < breakpoints[0]) return 0.0;
        if (alt < breakpoints[1]) return alt * slope0;
        if (alt < breakpoints[2]) {
          return segments[0].base +
              (alt - segments[0].pivot) * segments[0].slope;
        }
        if (alt < breakpoints[3]) {
          return segments[1].base +
              (alt - segments[1].pivot) * segments[1].slope;
        }
        return terminal;
      }

      final service = TargetScoringService(
        latitude: 40.0,
        longitude: -74.0,
        observationTime: DateTime.utc(2026, 1, 15, 6, 0, 0),
      );
      for (final alt in [
        -5.0,
        0.0,
        5.0,
        7.5,
        14.999,
        15.0,
        22.5,
        29.999,
        30.0,
        45.0,
        59.999,
        60.0,
        75.0,
        89.9,
      ]) {
        expect(
          service.debugScoreAltitude(alt),
          closeTo(expectedFromRust(alt), 1e-9),
          reason: 'Dart scorer must match Rust score_altitude at alt=$alt',
        );
      }
    });
  });
}
