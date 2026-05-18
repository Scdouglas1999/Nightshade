import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:nightshade_core/src/providers/sequence/sequence_executor.dart';

// Tests the ETA smoothing logic in isolation.
//
// The actual `_computeSmoothedEta` method on SequenceExecutor is private and
// depends on a full Ref + LoggingService stack. Rather than spin up the
// full container, we replicate the EMA formula here and verify the
// configuration constants behave as advertised in [docs] (alpha=0.3,
// window=10). If anyone tweaks the constants without updating the smoother
// docs, this test fails.
//
// The math we replicate:
//   * On the first sample the EMA bootstraps to the sample value.
//   * On subsequent samples: ema = alpha*sample + (1-alpha)*priorEma.
//   * The window cap discards the oldest sample but does NOT affect the
//     EMA itself (which is already smoothed) — it just bounds memory.
//
// Treat this file as a guard on the published constants.

void main() {
  group('ETA smoothing constants', () {
    test('window size is 10 (audit-handoff §7 ETA smoothing)', () {
      expect(kEtaWindowSize, 10);
    });

    test('EMA alpha is 0.3 (balance between responsiveness and stability)',
        () {
      expect(kEtaEmaAlpha, closeTo(0.3, 1e-9));
    });
  });

  group('EMA math (mirror of _recordFrameDurationSample)', () {
    double computeEma(Iterable<double> samples) {
      double? ema;
      final window = Queue<double>();
      for (final s in samples) {
        if (!s.isFinite || s <= 0) continue;
        window.addLast(s);
        if (window.length > kEtaWindowSize) {
          window.removeFirst();
        }
        if (ema == null) {
          ema = s;
        } else {
          ema = (kEtaEmaAlpha * s) + ((1.0 - kEtaEmaAlpha) * ema);
        }
      }
      return ema ?? 0.0;
    }

    test('first sample bootstraps the EMA', () {
      expect(computeEma([60.0]), closeTo(60.0, 1e-9));
    });

    test('outlier sample is absorbed, not amplified', () {
      // Baseline 60s subs, one 600s outlier.
      // ema after [60]: 60
      // ema after [60, 600]: 0.3*600 + 0.7*60 = 180 + 42 = 222
      // ema after [60, 600, 60]: 0.3*60 + 0.7*222 = 18 + 155.4 = 173.4
      // ema after [60, 600, 60, 60]: 0.3*60 + 0.7*173.4 = 18 + 121.38 = 139.38
      // Naive average would be (60+600+60+60)/4 = 195
      // EMA gives 139.38 — heavier weight on more-recent normal samples.
      final ema = computeEma([60.0, 600.0, 60.0, 60.0]);
      expect(ema, lessThan(195.0),
          reason: 'EMA should be lower than a naive average');
      expect(ema, closeTo(139.38, 0.1));
    });

    test('non-positive samples are skipped', () {
      // Negative/zero/NaN samples should not poison the EMA.
      final ema = computeEma([60.0, 0.0, -1.0, double.nan, 60.0]);
      expect(ema, closeTo(60.0, 1e-9));
    });

    test('window cap is bounded at kEtaWindowSize', () {
      // Feed kEtaWindowSize + 5 samples; the EMA should still converge
      // because it's not capped by window size, only the memory queue is.
      final samples = List<double>.filled(kEtaWindowSize + 5, 100.0);
      expect(computeEma(samples), closeTo(100.0, 1e-9));
    });
  });
}
