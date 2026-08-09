import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';

/// Opt-in frame-rate probe, armed by `NIGHTSHADE_FRAME_TIMING=1`.
///
/// Reports engine [FrameTiming] counts per window to stdout. It is inert unless
/// enabled and returns a cleanup callback for tests.
void Function() startFrameTimingProbe({
  Duration window = const Duration(seconds: 5),
  void Function(String line) emit = _stdout,
  bool? enabled,
}) {
  final armed =
      enabled ?? Platform.environment['NIGHTSHADE_FRAME_TIMING'] == '1';
  if (!armed) {
    return () {};
  }

  final frames = <FrameTiming>[];
  void collect(List<FrameTiming> timings) => frames.addAll(timings);
  SchedulerBinding.instance.addTimingsCallback(collect);

  // A periodic timer, not a frame callback: the whole point is to report the
  // windows in which NO frame was produced, and a frame-driven report cannot
  // observe its own absence.
  final timer = Timer.periodic(window, (_) {
    emit(frameTimingLine(frames, window));
    frames.clear();
  });

  return () {
    timer.cancel();
    SchedulerBinding.instance.removeTimingsCallback(collect);
  };
}

/// Render one window's worth of [frames] as a single log line.
///
/// ```text
/// [frame-timing] window=5.0s frames=0 fps=0.0
/// [frame-timing] window=5.0s frames=312 fps=62.4 buildAvgMs=0.8 rasterAvgMs=6.1 buildP95Ms=1.9 rasterP95Ms=11.4
/// ```
///
/// The zero case prints deliberately rather than staying silent: "the app
/// produced no frames for five seconds" is the finding, and a silent probe is
/// indistinguishable from a probe that failed to start.
String frameTimingLine(List<FrameTiming> frames, Duration window) {
  final seconds = window.inMicroseconds / Duration.microsecondsPerSecond;
  final fps = (frames.length / seconds).toStringAsFixed(1);
  final head = '[frame-timing] window=${seconds}s frames=${frames.length}';

  if (frames.isEmpty) {
    return '$head fps=0.0';
  }

  final build = _Summary.of([
    for (final frame in frames) frame.buildDuration.inMicroseconds,
  ]);
  final raster = _Summary.of([
    for (final frame in frames) frame.rasterDuration.inMicroseconds,
  ]);
  return '$head fps=$fps '
      'buildAvgMs=${build.averageMs} rasterAvgMs=${raster.averageMs} '
      'buildP95Ms=${build.p95Ms} rasterP95Ms=${raster.p95Ms}';
}

void _stdout(String line) => stdout.writeln(line);

class _Summary {
  final String averageMs;
  final String p95Ms;

  const _Summary(this.averageMs, this.p95Ms);

  factory _Summary.of(List<int> micros) {
    final sorted = List<int>.from(micros)..sort();
    final total = sorted.fold<int>(0, (sum, value) => sum + value);
    // Nearest-rank p95, clamped so a single-sample window reports that sample
    // rather than running off the end of the list.
    final rank = ((sorted.length * 95) / 100).ceil().clamp(1, sorted.length);
    return _Summary(
      _ms(total / sorted.length),
      _ms(sorted[rank - 1].toDouble()),
    );
  }

  static String _ms(double micros) =>
      (micros / Duration.microsecondsPerMillisecond).toStringAsFixed(1);
}
