import '../backend/nightshade_backend.dart';
import '../models/backend/phd2_status.dart';

/// Status returned when the host has no active PHD2 client.
const Phd2Status kPhd2DisconnectedStatus = Phd2Status(
  state: 'Disconnected',
  connected: false,
);

/// Default wait after launch/connect before giving up.
const Duration kPhd2PollTimeout = Duration(seconds: 30);

/// Poll interval while waiting for PHD2 socket + client registration.
const Duration kPhd2PollInterval = Duration(milliseconds: 500);

/// Legacy aliases for tests and callers that used the earlier constant names.
const Duration phd2StatusPollTimeout = kPhd2PollTimeout;
const Duration phd2StatusPollInterval = kPhd2PollInterval;

/// Whether a guiding event indicates PHD2 is still reachable (not link loss).
bool isPhd2GuidingHeartbeatEvent(String eventType) {
  switch (eventType) {
    case 'Disconnected':
    case 'LostStar':
    case 'UnknownGuidingEvent':
      return false;
    case 'GuideStep':
    case 'GuideStats':
    case 'Connected':
    case 'AppState':
    case 'GuidingStarted':
    case 'GuidingStopped':
    case 'Paused':
    case 'Resumed':
    case 'Settling':
    case 'SettleDone':
    case 'LoopingExposures':
    case 'Calibrating':
    case 'CalibrationComplete':
      return true;
    default:
      return false;
  }
}

bool isPhd2GuiderDeviceId(String? deviceId) {
  if (deviceId == null || deviceId.isEmpty) return false;
  return deviceId == 'phd2_guider' ||
      deviceId == 'phd2' ||
      deviceId.startsWith('phd2:') ||
      deviceId.startsWith('phd2://');
}

/// Resolve PHD2 TCP host for local connections (avoids Windows localhost/IPv6).
String resolvePhd2ConnectHost(String host) {
  final normalized = host.trim().toLowerCase();
  if (normalized.isEmpty || normalized == 'localhost' || normalized == '::1') {
    return '127.0.0.1';
  }
  return host.trim();
}

/// Poll [backend.phd2GetStatus] until PHD2 reports connected or [timeout].
///
/// Transient errors (host still launching PHD2, status endpoint not ready)
/// are retried instead of failing immediately.
Future<Phd2Status> pollPhd2Connected(
  NightshadeBackend backend, {
  Duration timeout = kPhd2PollTimeout,
  Duration interval = kPhd2PollInterval,
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;

  while (DateTime.now().isBefore(deadline)) {
    try {
      final status = await backend.phd2GetStatus();
      if (status.connected) {
        return status;
      }
      lastError = null;
    } catch (e) {
      lastError = e;
    }

    if (DateTime.now().add(interval).isAfter(deadline)) {
      break;
    }
    await Future<void>.delayed(interval);
  }

  try {
    final status = await backend.phd2GetStatus();
    if (status.connected) {
      return status;
    }
  } catch (e) {
    lastError = e;
  }

  if (lastError != null) {
    throw StateError(
      'PHD2 did not report a connection within ${timeout.inSeconds}s: $lastError',
    );
  }
  throw StateError(
    'PHD2 did not report a connection within ${timeout.inSeconds}s.',
  );
}

/// Best-effort status read; returns disconnected when the host has no client.
Future<Phd2Status> readPhd2StatusOrDisconnected(
  NightshadeBackend backend,
) async {
  try {
    return await backend.phd2GetStatus();
  } catch (_) {
    return kPhd2DisconnectedStatus;
  }
}
