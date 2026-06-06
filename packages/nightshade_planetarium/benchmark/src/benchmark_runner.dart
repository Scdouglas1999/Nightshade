// Core measurement loop for the planetarium paint benchmark.
//
// Headless and deterministic: builds the real [SkyCanvasPainter] (+ FOV overlay)
// for each scripted camera frame, records paint() into a PictureRecorder canvas,
// and times each paint with a high-resolution Stopwatch. A few warm-up frames
// are discarded before timing so JIT/cache effects don't pollute the numbers.
//
// IMPORTANT: this measures CPU paint-pipeline time (the work CustomPainter does
// building the Skia display list), NOT GPU rasterization or on-display frame
// rate. That is the dominant, deterministic, reproducible lever for this
// pipeline. Real end-to-end FPS is captured separately by the integration_test
// using Flutter FrameTiming. See benchmark/README.md.

import 'dart:io';
import 'dart:ui' as ui;

import 'benchmark_scene.dart';
import 'camera_timeline.dart';
import 'stress_fixture.dart';

/// Aggregated result of one benchmark run. Mirrors the stable results JSON
/// schema documented in benchmark/README.md.
class BenchmarkResult {
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
  final double meanMs;
  final double avgFps;
  final double rssMb;
  final int objectsDrawn;
  final int frames;
  final String scene;
  final String note;

  const BenchmarkResult({
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.meanMs,
    required this.avgFps,
    required this.rssMb,
    required this.objectsDrawn,
    required this.frames,
    required this.scene,
    required this.note,
  });

  /// Stable on-disk schema. Field order/names are part of the contract — the
  /// optimization loop diffs successive runs by these keys.
  Map<String, dynamic> toJson() => {
        'p50Ms': _round(p50Ms),
        'p95Ms': _round(p95Ms),
        'p99Ms': _round(p99Ms),
        'avgFps': _round(avgFps),
        'rssMb': _round(rssMb),
        'objectsDrawn': objectsDrawn,
        'frames': frames,
        'scene': scene,
        'note': note,
      };

  static double _round(double v) => double.parse(v.toStringAsFixed(3));
}

/// Run the full paint benchmark over the scripted timeline.
///
/// [warmupFrames] paints are run and discarded before timing begins. The
/// remaining [CameraFrame]s are each timed once. Returns the aggregated result;
/// the caller decides whether to persist it.
BenchmarkResult runPaintBenchmark({
  required StressFixture fixture,
  required List<CameraFrame> timeline,
  int warmupFrames = 8,
  String note = '',
}) {
  const size = kBenchmarkCanvasSize;

  // Warm-up: paint the first few frames without timing so lazy atlas baking,
  // projection-cache priming and JIT warm-up don't land in the measured set.
  for (var i = 0; i < warmupFrames && i < timeline.length; i++) {
    _paintFrame(fixture, timeline[i], size);
  }

  final timingsMs = <double>[];
  var peakRssBytes = ProcessInfo.currentRss;
  var densestObjects = 0;

  for (final frame in timeline) {
    final sw = Stopwatch()..start();
    _paintFrame(fixture, frame, size);
    sw.stop();
    timingsMs.add(sw.elapsedMicroseconds / 1000.0);

    final rss = ProcessInfo.currentRss;
    if (rss > peakRssBytes) peakRssBytes = rss;

    // Cheap drawn-primitive proxy: count catalog objects whose centre projects
    // inside the canvas at this frame. The densest frame's count is reported.
    final n = _countOnScreen(fixture, frame, size);
    if (n > densestObjects) densestObjects = n;
  }

  final sorted = [...timingsMs]..sort();
  final mean = sorted.reduce((a, b) => a + b) / sorted.length;

  return BenchmarkResult(
    p50Ms: _percentile(sorted, 0.50),
    p95Ms: _percentile(sorted, 0.95),
    p99Ms: _percentile(sorted, 0.99),
    meanMs: mean,
    avgFps: mean > 0 ? 1000.0 / mean : 0,
    rssMb: peakRssBytes / (1024 * 1024),
    objectsDrawn: densestObjects,
    frames: timingsMs.length,
    scene: fixture.composition.split('\n').first,
    note: note,
  );
}

/// Paint one frame (sky + FOV overlay) into a throwaway recorder. Used by both
/// the warm-up and timed loops so they do identical work.
void _paintFrame(StressFixture fixture, CameraFrame frame, ui.Size size) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  buildSkyPainter(fixture: fixture, frame: frame).paint(canvas, size);
  buildFovPainter(frame).paint(canvas, size);
  // endRecording forces the display list to be finalised, so its cost is part
  // of the measured paint-pipeline time. Dispose to avoid leaking pictures
  // across the (potentially hundreds of) timed frames.
  recorder.endRecording().dispose();
}

/// Number of catalog objects (stars + DSOs) whose centre falls within the
/// canvas for [frame]. A cheap stand-in for "primitives drawn" — exact glyph
/// counts vary per layer, but on-screen object count tracks scene density.
int _countOnScreen(StressFixture fixture, CameraFrame frame, ui.Size size) {
  final scale =
      (size.width < size.height ? size.width : size.height) / 2 / (frame.fieldOfViewDeg / 2);
  final cx = size.width / 2;
  final cy = size.height / 2;
  var count = 0;

  bool onScreen(double raHours, double decDeg) {
    var dRaHours = raHours - frame.centerRaHours;
    if (dRaHours > 12) dRaHours -= 24;
    if (dRaHours < -12) dRaHours += 24;
    // Small-angle planar approximation — adequate for an on-screen tally.
    final dx = dRaHours * 15.0 * scale;
    final dy = -(decDeg - frame.centerDecDeg) * scale;
    final px = cx + dx;
    final py = cy + dy;
    return px >= 0 && px <= size.width && py >= 0 && py <= size.height;
  }

  for (final s in fixture.stars) {
    if (onScreen(s.coordinates.ra, s.coordinates.dec)) count++;
  }
  for (final d in fixture.dsos) {
    if (onScreen(d.coordinates.ra, d.coordinates.dec)) count++;
  }
  return count;
}

/// Nearest-rank percentile of an already-sorted ascending list of timings.
double _percentile(List<double> sortedMs, double q) {
  if (sortedMs.isEmpty) return 0;
  if (sortedMs.length == 1) return sortedMs.first;
  final rank = (q * (sortedMs.length - 1)).round();
  return sortedMs[rank.clamp(0, sortedMs.length - 1)];
}

/// Persist [result] to benchmark/results/latest.json (pretty-printed). The
/// results dir is gitignored; this file is a fresh artifact each run.
void writeResults(BenchmarkResult result, {String? path}) {
  final out = File(path ?? 'benchmark/results/latest.json');
  out.parent.createSync(recursive: true);
  // Hand-roll a stable, indented encoding (avoids importing dart:convert just
  // for one call site; keeps key order identical to toJson()).
  final json = result.toJson();
  final buf = StringBuffer('{\n');
  final entries = json.entries.toList();
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final v = e.value;
    final encoded = v is String ? _jsonString(v) : '$v';
    buf.write('  ${_jsonString(e.key)}: $encoded');
    buf.write(i == entries.length - 1 ? '\n' : ',\n');
  }
  buf.write('}\n');
  out.writeAsStringSync(buf.toString());
}

String _jsonString(String s) {
  final escaped = s
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return '"$escaped"';
}
