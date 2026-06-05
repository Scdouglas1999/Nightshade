import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/weather/radar_frame.dart';
import 'package:nightshade_core/src/services/weather/cloud_motion_analyzer.dart';

/// Tests for the *spatial* behaviour of [CloudMotionAnalyzer].
///
/// The analyzer used to estimate cloud density as a single scalar (the frame
/// opacity) for every grid cell, so the cloud centroid could never move and the
/// predictive ETA/direction were computed from a constant field. These tests
/// pin the real behaviour:
///
///  * a genuine moving cloud band (a high-density tile that shifts position
///    across two snapshots) produces a non-null ETA and a southward direction;
///  * a spatially-uniform field (a single whole-area box, the real-world
///    radar-tile / single-point-cloud-cover case) yields NO fabricated motion
///    and is reported loudly as "no spatial data".
void main() {
  group('CloudMotionAnalyzer spatial motion', () {
    late CloudMotionAnalyzer analyzer;

    // User sits at the origin of the analysis grid.
    const userLat = 40.0;
    const userLon = -90.0;

    setUp(() {
      analyzer = CloudMotionAnalyzer();
    });

    /// A clear "background" frame covering the whole 100 km analysis area at an
    /// opacity below the significance threshold (0.3). Because it is the largest
    /// box, the smaller cloud-band tile overrides it wherever they overlap.
    RadarFrame clearBackground(DateTime t) => RadarFrame(
          timestamp: t,
          tileUrlTemplate: 'clear',
          north: userLat + 3.0,
          south: userLat - 3.0,
          east: userLon + 3.0,
          west: userLon - 3.0,
          opacity: 0.05, // below significance threshold -> "clear sky"
        );

    /// A dense cloud band: a small high-opacity tile spanning the full
    /// east-west extent but a narrow north-south band centred on [bandLat].
    /// Being the smallest enclosing box, its opacity wins inside the band.
    RadarFrame cloudBand(DateTime t, double bandLat) => RadarFrame(
          timestamp: t,
          tileUrlTemplate: 'band',
          north: bandLat + 0.25,
          south: bandLat - 0.25,
          east: userLon + 3.0,
          west: userLon - 3.0,
          opacity: 0.9, // well above significance threshold
        );

    test('moving cloud band yields a non-null ETA and southward direction', () {
      final t0 = DateTime.utc(2024, 6, 15, 0, 0);
      final t1 = DateTime.utc(2024, 6, 15, 0, 30); // 30 min later

      // Band starts ~0.6 deg (~66 km) north of the user and moves to ~0.3 deg
      // (~33 km) north: it is genuinely approaching from the north.
      final frames = <RadarFrame>[
        clearBackground(t0),
        cloudBand(t0, userLat + 0.6),
        clearBackground(t1),
        cloudBand(t1, userLat + 0.3),
      ];

      final result = analyzer.analyzeMotionDetailed(
        frames: frames,
        userLatitude: userLat,
        userLongitude: userLon,
      );

      expect(result.isAvailable, isTrue,
          reason: 'a moving band must produce a real motion estimate');
      final motion = result.motion!;

      // Speed must be physically plausible and non-trivial.
      expect(motion.speedKmh, greaterThan(1.0));
      expect(motion.speedKmh, lessThan(200.0));

      // The band moved from north toward the user -> motion bearing ~ south.
      // calculateBearing of a due-south displacement is ~180 degrees.
      expect(motion.directionDegrees, closeTo(180.0, 20.0));

      // Clouds approaching from the north -> a finite ETA.
      expect(motion.etaToLocation, isNotNull);
      expect(motion.etaToLocation!.inMinutes, greaterThan(0));

      // The nearest significant cloud should be the (closer) t1 band ~33 km out.
      expect(motion.distanceKm, greaterThan(0.0));
      expect(motion.distanceKm, lessThan(100.0));
    });

    test('uniform field reports noSpatialData and no fabricated ETA', () {
      final t0 = DateTime.utc(2024, 6, 15, 0, 0);
      final t1 = DateTime.utc(2024, 6, 15, 0, 30);

      // Two snapshots, each a single whole-area box with constant opacity:
      // exactly what the real radar-tile / single-point cloud-cover providers
      // produce. There is no spatial gradient to track.
      final frames = <RadarFrame>[
        RadarFrame(
          timestamp: t0,
          tileUrlTemplate: 'uniform',
          north: userLat + 3.0,
          south: userLat - 3.0,
          east: userLon + 3.0,
          west: userLon - 3.0,
          opacity: 0.8,
        ),
        RadarFrame(
          timestamp: t1,
          tileUrlTemplate: 'uniform',
          north: userLat + 3.0,
          south: userLat - 3.0,
          east: userLon + 3.0,
          west: userLon - 3.0,
          opacity: 0.8,
        ),
      ];

      final result = analyzer.analyzeMotionDetailed(
        frames: frames,
        userLatitude: userLat,
        userLongitude: userLon,
      );

      // Fail loud: no spatial data -> no motion, with an explicit reason.
      expect(result.isAvailable, isFalse);
      expect(result.motion, isNull);
      expect(
        result.unavailableReason,
        CloudMotionUnavailableReason.noSpatialData,
      );

      // The convenience wrapper must collapse this to null (no fake ETA).
      final plain = analyzer.analyzeMotion(
        frames: frames,
        userLatitude: userLat,
        userLongitude: userLon,
      );
      expect(plain, isNull);
    });

    test('clear sky reports noCloudsDetected', () {
      final t0 = DateTime.utc(2024, 6, 15, 0, 0);
      final t1 = DateTime.utc(2024, 6, 15, 0, 30);

      final frames = <RadarFrame>[
        clearBackground(t0),
        clearBackground(t1),
      ];

      final result = analyzer.analyzeMotionDetailed(
        frames: frames,
        userLatitude: userLat,
        userLongitude: userLon,
      );

      expect(result.isAvailable, isFalse);
      expect(
        result.unavailableReason,
        CloudMotionUnavailableReason.noCloudsDetected,
      );
    });

    test('fewer than two frames reports insufficientFrames', () {
      final result = analyzer.analyzeMotionDetailed(
        frames: <RadarFrame>[
          RadarFrame(
            timestamp: DateTime.utc(2024, 6, 15, 0, 0),
            tileUrlTemplate: 'one',
            north: userLat + 3.0,
            south: userLat - 3.0,
            east: userLon + 3.0,
            west: userLon - 3.0,
            opacity: 0.8,
          ),
        ],
        userLatitude: userLat,
        userLongitude: userLon,
      );

      expect(result.isAvailable, isFalse);
      expect(
        result.unavailableReason,
        CloudMotionUnavailableReason.insufficientFrames,
      );
    });

    test('stationary band has spatial structure but no resolvable motion', () {
      final t0 = DateTime.utc(2024, 6, 15, 0, 0);
      final t1 = DateTime.utc(2024, 6, 15, 0, 30);

      // The band is in the SAME position in both snapshots: there is genuine
      // spatial structure (so it is NOT "no spatial data") but the centroid does
      // not move, so no motion vector can be resolved.
      final frames = <RadarFrame>[
        clearBackground(t0),
        cloudBand(t0, userLat + 0.5),
        clearBackground(t1),
        cloudBand(t1, userLat + 0.5),
      ];

      final result = analyzer.analyzeMotionDetailed(
        frames: frames,
        userLatitude: userLat,
        userLongitude: userLon,
      );

      expect(result.isAvailable, isFalse);
      expect(
        result.unavailableReason,
        CloudMotionUnavailableReason.noResolvableMotion,
      );
    });
  });
}
