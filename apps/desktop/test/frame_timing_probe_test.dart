import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/frame_timing_probe.dart';

/// [FrameTiming] wants the full vsync phase vector; only the build and raster
/// spans are read back, so the rest are pinned at a fixed origin.
FrameTiming _frame({required int buildMicros, required int rasterMicros}) {
  const start = 1000000;
  final buildEnd = start + buildMicros;
  final rasterEnd = buildEnd + rasterMicros;
  return FrameTiming(
    vsyncStart: start,
    buildStart: start,
    buildFinish: buildEnd,
    rasterStart: buildEnd,
    rasterFinish: rasterEnd,
    rasterFinishWallTime: rasterEnd,
  );
}

void main() {
  group('frameTimingLine', () {
    // The zero case is the whole reason the probe exists: an idle app that
    // produces NO frames must say so out loud. A silent probe reads exactly
    // like a probe that failed to start, which is how the idle-CPU finding got
    // its severity wrong twice.
    test('an idle window reports zero frames rather than staying silent', () {
      expect(
        frameTimingLine(const [], const Duration(seconds: 5)),
        '[frame-timing] window=5.0s frames=0 fps=0.0',
      );
    });

    test('fps is frames divided by the window, not a frame count', () {
      final frames = List.generate(
        300,
        (_) => _frame(buildMicros: 1000, rasterMicros: 2000),
      );
      expect(
        frameTimingLine(frames, const Duration(seconds: 5)),
        contains('frames=300 fps=60.0'),
      );
      // Same frames, longer window -> lower rate. Pins that the divisor is the
      // window and not a hard-coded 60.
      expect(
        frameTimingLine(frames, const Duration(seconds: 10)),
        contains('frames=300 fps=30.0'),
      );
    });

    test('reports build and raster averages separately', () {
      // Averages 2.0 ms build / 8.0 ms raster. Keeping the two apart is what
      // distinguishes "the UI thread is rebuilding constantly" from "the
      // rasteriser is slow", which have different causes and different fixes.
      final frames = [
        _frame(buildMicros: 1000, rasterMicros: 6000),
        _frame(buildMicros: 3000, rasterMicros: 10000),
      ];
      final line = frameTimingLine(frames, const Duration(seconds: 1));
      expect(line, contains('buildAvgMs=2.0'));
      expect(line, contains('rasterAvgMs=8.0'));
    });

    test('p95 reports a tail frame, not the mean', () {
      // 94 frames at 1 ms and 6 at 100 ms: the mean lands at a comfortable
      // ~7 ms and hides the fact that six frames in a hundred blew a 16 ms
      // budget by 6x. The percentile is the number that makes that visible.
      final frames = [
        for (var i = 0; i < 94; i++)
          _frame(buildMicros: 1000, rasterMicros: 1000),
        for (var i = 0; i < 6; i++)
          _frame(buildMicros: 1000, rasterMicros: 100000),
      ];
      final line = frameTimingLine(frames, const Duration(seconds: 1));
      expect(line, contains('rasterAvgMs=6.9'));
      expect(line, contains('rasterP95Ms=100.0'));
    });

    test('a single-frame window does not run off the end of the samples', () {
      final line = frameTimingLine([
        _frame(buildMicros: 4000, rasterMicros: 7000),
      ], const Duration(seconds: 1));
      expect(line, contains('buildP95Ms=4.0'));
      expect(line, contains('rasterP95Ms=7.0'));
    });
  });

  group('startFrameTimingProbe', () {
    testWidgets('stays inert when it has not been armed', (tester) async {
      final lines = <String>[];

      final stop = startFrameTimingProbe(
        window: const Duration(seconds: 1),
        emit: lines.add,
        enabled: false,
      );

      // Long enough for thirty windows to have fired. An unarmed probe must
      // register no timer at all, so a shipping build pays nothing for it —
      // and the binding's own pending-timer invariant is what proves it, since
      // this test never cancels anything.
      await tester.pump(const Duration(seconds: 30));

      expect(lines, isEmpty);
      stop();
    });

    testWidgets('armed, it reports the window it observed', (tester) async {
      final lines = <String>[];
      final stop = startFrameTimingProbe(
        window: const Duration(seconds: 5),
        emit: lines.add,
        enabled: true,
      );

      // No frames are produced here, so this pins the idle path end to end:
      // timer fires, line is emitted, and it says zero.
      await tester.pump(const Duration(seconds: 5));

      expect(lines, ['[frame-timing] window=5.0s frames=0 fps=0.0']);
      // Inside the body, not addTearDown: the binding checks for pending
      // timers before tear-downs run.
      stop();
    });
  });
}
