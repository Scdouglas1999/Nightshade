import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scene_snapshot.dart';
import 'planetarium_handle_provider.dart';

/// Reads the native [`SceneSnapshotDto`] once per Flutter frame for overlays.
///
/// Uses [SchedulerBinding.scheduleFrameCallback] plus a post-frame callback so
/// label layers rebuild after Rust publishes the latest snapshot.
class SceneSnapshotNotifier extends Notifier<SceneSnapshotDto> {
  bool _polling = false;

  @override
  SceneSnapshotDto build() {
    ref.onCancel(_stopPolling);
    ref.onResume(_startPolling);
    ref.onDispose(_stopPolling);

    ref.listen(planetariumHandleProvider, (_, next) {
      next.whenData((driver) {
        state = driver.snapshot();
        _startPolling();
      });
    });

    final handle = ref.read(planetariumHandleProvider);
    if (handle.hasValue) {
      final snapshot = handle.requireValue.snapshot();
      _startPolling();
      return snapshot;
    }

    return kEmptySceneSnapshot;
  }

  void _startPolling() {
    if (_polling || !ref.read(planetariumHandleProvider).hasValue) {
      return;
    }
    _polling = true;
    _scheduleFrame();
  }

  void _stopPolling() {
    _polling = false;
  }

  void _scheduleFrame() {
    if (!_polling) {
      return;
    }
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (!_polling) {
        return;
      }
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_polling) {
          return;
        }
        final driver = ref.read(planetariumHandleProvider).valueOrNull;
        if (driver != null) {
          final next = driver.snapshot();
          if (next != state) {
            state = next;
          }
        }
        _scheduleFrame();
      });
    });
  }
}

/// Frame-synced scene snapshot for Dart overlay layers.
final sceneSnapshotProvider =
    NotifierProvider<SceneSnapshotNotifier, SceneSnapshotDto>(
  SceneSnapshotNotifier.new,
);
