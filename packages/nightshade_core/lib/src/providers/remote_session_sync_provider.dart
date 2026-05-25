import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../backend/nightshade_backend.dart';
import '../services/logging_service.dart';
import 'backend_provider.dart';
import 'remote_sync_handler.dart';

const _logSource = 'RemoteSessionSync';

/// Keeps companion UI state aligned with the imaging host when connected via
/// [NetworkBackend]. Without hydration, mobile shows local SQLite profiles and
/// disconnected device chips even though the desktop rig is live.
final remoteSessionSyncProvider = Provider<void>((ref) {
  StreamSubscription<NightshadeEvent>? eventSub;
  Timer? pollTimer;

  void teardown() {
    eventSub?.cancel();
    pollTimer?.cancel();
    eventSub = null;
    pollTimer = null;
  }

  ref.onDispose(teardown);

  ref.listen<NightshadeBackend>(backendProvider, (previous, next) {
    teardown();
    if (next is! NetworkBackend) {
      return;
    }

    unawaited(_hydrate(ref, next));

    eventSub = next.eventStream.listen((event) {
      unawaited(
        applyRemoteSyncEvent(
          ref,
          event,
          networkBackend: next,
        ),
      );
    });

    pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        unawaited(_hydrate(ref, backend));
      }
    });
  }, fireImmediately: true);
});

Future<void> _hydrate(Ref ref, NetworkBackend backend) async {
  final logger = ref.read(loggingServiceProvider);

  try {
    await hydrateRemoteSessionState(ref, backend);
    logger.info(
      'Hydrated remote session from host',
      source: _logSource,
    );
  } catch (e, stackTrace) {
    logger.error(
      'Remote session hydration failed: $e',
      source: _logSource,
      fields: {'stackTrace': '$stackTrace'},
    );
    developer.log(
      'Remote session hydration failed: $e',
      name: _logSource,
      level: 1000,
      error: e,
      stackTrace: stackTrace,
    );
  }
}
