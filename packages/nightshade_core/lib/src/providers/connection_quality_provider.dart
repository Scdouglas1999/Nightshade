/// Connection-quality signal for the run dashboard / shell chip.
///
/// Collapses three facts the operator cares about — am I driving the rig
/// locally or over the network, is the remote session actually alive, and how
/// laggy is it — into one [ConnectionQuality] snapshot the UI can render as a
/// single chip. It taps the active [NetworkBackend]'s ping/pong
/// [NetworkBackend.latencyStream] (the WebSocket heartbeat round-trip) and its
/// [NetworkBackend.connectionStateStream]; in local FFI mode there is nothing
/// remote to measure, so it reports [ConnectionMode.local] with no latency.
///
/// This lives in core (not a widget's local state) so the run dashboard header,
/// the shell, and any future surface read the same graded signal instead of
/// each re-subscribing to the backend's raw streams and re-deriving the grade.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import 'backend_provider.dart';

/// Whether the app is driving hardware on this device (local FFI) or through a
/// network session to a remote headless/desktop host.
enum ConnectionMode {
  /// Local FFI backend — the rig is attached to this device. No network hop,
  /// so latency is not meaningful.
  local,

  /// Network backend — controlling a remote host over HTTP/WebSocket.
  remote,
}

/// Coarse latency grade for color-coding the chip. Thresholds mirror the
/// existing latency badge in the mobile shell so the two never disagree:
/// good < 50 ms, fair < 200 ms, poor otherwise.
enum ConnectionLatencyGrade { good, fair, poor }

/// Liveness of the remote session, projected from the backend's
/// [BackendConnectionState]. In [ConnectionMode.local] this is always
/// [ConnectionLiveness.local] — there is no remote socket to be live or not.
enum ConnectionLiveness {
  /// Local FFI mode — no remote session applies.
  local,

  /// Remote WebSocket is open and the handshake completed.
  connected,

  /// First-time connect in flight (no prior successful attachment).
  connecting,

  /// A prior connection dropped and the backend is retrying.
  reconnecting,

  /// Idle / server unreachable — backoff timer armed, nothing connected.
  offline,

  /// Terminal failure (e.g. version mismatch); backend stopped attempting.
  error,
}

/// Immutable snapshot of the current connection quality.
class ConnectionQuality {
  /// Local vs remote operation.
  final ConnectionMode mode;

  /// Remote-session liveness (always [ConnectionLiveness.local] when [mode] is
  /// local).
  final ConnectionLiveness liveness;

  /// Most recent WebSocket ping/pong round-trip. Null when local, or when no
  /// pong has been observed yet on a fresh remote session.
  final Duration? latency;

  /// Host of the remote server, for the chip's subtitle. Null when local.
  final String? remoteHost;

  /// `true` when the remote endpoint is a tailnet / Internet address (longer
  /// latency expected) rather than a LAN host. Always false when local.
  final bool isRemoteHost;

  const ConnectionQuality({
    required this.mode,
    required this.liveness,
    this.latency,
    this.remoteHost,
    this.isRemoteHost = false,
  });

  /// The local-mode snapshot — used as the seed and whenever the active backend
  /// is not a [NetworkBackend].
  static const ConnectionQuality local = ConnectionQuality(
    mode: ConnectionMode.local,
    liveness: ConnectionLiveness.local,
  );

  /// `true` when the remote session is up (or we're local, which is always
  /// "usable"). Drives the chip's healthy/unhealthy styling.
  bool get isHealthy =>
      mode == ConnectionMode.local || liveness == ConnectionLiveness.connected;

  /// Latency in whole milliseconds, or null when unavailable.
  int? get latencyMs =>
      latency == null ? null : (latency!.inMicroseconds / 1000.0).round();

  /// Graded latency for color coding. Null when there is no latency to grade
  /// (local mode, or no pong seen yet).
  ConnectionLatencyGrade? get latencyGrade {
    final ms = latencyMs;
    if (ms == null) return null;
    if (ms < 50) return ConnectionLatencyGrade.good;
    if (ms < 200) return ConnectionLatencyGrade.fair;
    return ConnectionLatencyGrade.poor;
  }

  ConnectionQuality copyWith({
    ConnectionMode? mode,
    ConnectionLiveness? liveness,
    Duration? latency,
    String? remoteHost,
    bool? isRemoteHost,
  }) {
    return ConnectionQuality(
      mode: mode ?? this.mode,
      liveness: liveness ?? this.liveness,
      latency: latency ?? this.latency,
      remoteHost: remoteHost ?? this.remoteHost,
      isRemoteHost: isRemoteHost ?? this.isRemoteHost,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionQuality &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          liveness == other.liveness &&
          latency == other.latency &&
          remoteHost == other.remoteHost &&
          isRemoteHost == other.isRemoteHost;

  @override
  int get hashCode =>
      Object.hash(mode, liveness, latency, remoteHost, isRemoteHost);
}

ConnectionLiveness _livenessForState(BackendConnectionState state) {
  switch (state) {
    case BackendConnectionState.connected:
      return ConnectionLiveness.connected;
    case BackendConnectionState.connecting:
      return ConnectionLiveness.connecting;
    case BackendConnectionState.reconnecting:
      return ConnectionLiveness.reconnecting;
    case BackendConnectionState.disconnected:
      return ConnectionLiveness.offline;
    case BackendConnectionState.error:
      return ConnectionLiveness.error;
  }
}

/// Live connection-quality snapshot for the active backend.
///
/// Emits [ConnectionQuality.local] when the backend is not a [NetworkBackend].
/// For a network session it seeds with the backend's current state + last
/// latency, then merges the connection-state and latency streams so the chip
/// updates on both a heartbeat round-trip and a reconnect transition. Always
/// seeded so the chip never flashes empty on first build.
final connectionQualityProvider = StreamProvider<ConnectionQuality>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is! NetworkBackend) {
    return Stream<ConnectionQuality>.value(ConnectionQuality.local);
  }

  ConnectionQuality current = ConnectionQuality(
    mode: ConnectionMode.remote,
    liveness: _livenessForState(backend.connectionState),
    latency: backend.lastLatency,
    remoteHost: backend.serverHost,
    isRemoteHost: backend.isRemoteHost,
  );

  final controller = StreamController<ConnectionQuality>();
  controller.add(current);

  final stateSub = backend.connectionStateStream.listen((state) {
    current = current.copyWith(liveness: _livenessForState(state));
    controller.add(current);
  }, onError: controller.addError);

  final latencySub = backend.latencyStream.listen((latency) {
    current = current.copyWith(latency: latency);
    controller.add(current);
  }, onError: controller.addError);

  ref.onDispose(() {
    stateSub.cancel();
    latencySub.cancel();
    controller.close();
  });

  return controller.stream;
});
