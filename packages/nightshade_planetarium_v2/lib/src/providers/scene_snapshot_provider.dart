import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

import '../bridge/planetarium_driver.dart';
import '../models/scene_snapshot.dart';
import 'planetarium_handle_provider.dart';
import 'planetarium_quiesced_provider.dart';

/// Reads the native [`SceneSnapshotDto`] once per Flutter frame for overlays.
///
/// Polling is **frame-skipped on `frameId`** — Rust publishes a new snapshot
/// only when the render thread actually produced a frame, so most polls bail
/// out before allocating a new state object. The poller is a single chained
/// post-frame callback (not a vsync registration) so [WidgetTester.pumpAndSettle]
/// can drain it and tests never hit "Timer still pending".
class SceneSnapshotNotifier extends Notifier<SceneSnapshotDto> {
  bool _polling = false;
  bool _disposed = false;
  bool _frameScheduled = false;
  BigInt _lastSeenFrameId = BigInt.from(-1);

  @override
  SceneSnapshotDto build() {
    ref.onCancel(_stopPolling);
    ref.onResume(_startPolling);
    ref.onDispose(() {
      _disposed = true;
      _stopPolling();
    });

    ref.listen<AsyncValue<PlanetariumDriver>>(planetariumHandleProvider,
        (_, next) {
      next.whenData((_) {
        _readSnapshot(force: true);
        _startPolling();
      });
    });

    ref.listen<bool>(planetariumQuiescedProvider, (_, quiesced) {
      if (quiesced) {
        _stopPolling();
      } else {
        _startPolling();
      }
    });

    final handle = ref.read(planetariumHandleProvider);
    if (handle.hasValue && !ref.read(planetariumQuiescedProvider)) {
      final snapshot = handle.requireValue.snapshot();
      _lastSeenFrameId = snapshot.frameId;
      _startPolling();
      return snapshot;
    }

    return kEmptySceneSnapshot;
  }

  void _startPolling() {
    if (_disposed ||
        _polling ||
        ref.read(planetariumQuiescedProvider) ||
        !ref.read(planetariumHandleProvider).hasValue) {
      return;
    }
    _polling = true;
    _scheduleNextRead();
  }

  void _stopPolling() {
    _polling = false;
  }

  /// Schedules a single post-frame poll. We DO NOT call `scheduleFrame()`
  /// ourselves — that would peg the engine at vsync forever and make
  /// `pumpAndSettle` hang in widget tests. Frames produced by gestures,
  /// animations, or other providers (e.g. `tickerProvider`) drive polling
  /// in production; idle UIs correctly stop polling.
  void _scheduleNextRead() {
    if (!_polling || _disposed || _frameScheduled) {
      return;
    }
    _frameScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      if (!_polling || _disposed) {
        return;
      }
      _readSnapshot();
      _scheduleNextRead();
    });
  }

  void _readSnapshot({bool force = false}) {
    if (_disposed) {
      return;
    }
    final driver = ref.read(planetariumHandleProvider).valueOrNull;
    if (driver == null) {
      return;
    }
    final next = driver.snapshot();
    // Frame-skip: Rust only bumps frameId when something actually rendered.
    // Identical frame ids mean no overlay rebuild is needed. The handle-ready
    // path forces a read so the first snapshot replaces `kEmptySceneSnapshot`
    // even when Rust hasn't incremented the id yet.
    if (!force && next.frameId == _lastSeenFrameId) {
      return;
    }
    _lastSeenFrameId = next.frameId;
    state = next;
  }
}

/// Frame-synced scene snapshot for Dart overlay layers.
final sceneSnapshotProvider =
    NotifierProvider<SceneSnapshotNotifier, SceneSnapshotDto>(
  SceneSnapshotNotifier.new,
);
