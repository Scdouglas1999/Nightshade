import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show DbCapturedImage, ImagingSession, allDbImagesProvider;

/// Where a session's elapsed figure comes from.
///
/// The History cards and the Session tab both go through [sessionElapsed] and
/// carry the basis, so one session is never described two ways and a figure is
/// only shown when the app can stand behind it.
enum SessionElapsedBasis {
  /// `end_time` is set: the figure is the session's real span.
  closed,

  /// The session is the one running right now, so the wall clock is its span.
  running,

  /// `end_time` is missing and the session is not running. The app only knows
  /// it ran at least until its last frame.
  lastFrame,

  /// `end_time` is missing, the session is not running and it captured
  /// nothing. There is no honest duration to show.
  unknown,
}

/// A session's elapsed time together with what that number actually means.
class SessionElapsed {
  final Duration? duration;
  final SessionElapsedBasis basis;

  const SessionElapsed(this.duration, this.basis);

  /// True when `end_time` is missing, i.e. the row was never closed.
  bool get isUnfinished => basis != SessionElapsedBasis.closed;

  /// The number, or an em-dash when there is nothing truthful to print.
  String get valueLabel =>
      duration == null ? '—' : formatSessionDuration(duration!);

  /// Qualifier that says which of the four cases produced [valueLabel]. Shown
  /// beside the value so "20m" is never read as a closed session's total.
  String get captionLabel {
    switch (basis) {
      case SessionElapsedBasis.closed:
        return 'elapsed';
      case SessionElapsedBasis.running:
        return 'so far';
      case SessionElapsedBasis.lastFrame:
        return 'to last frame';
      case SessionElapsedBasis.unknown:
        return 'never closed';
    }
  }
}

/// Interpret [session]'s timing for display.
///
/// [isLive] must be true only for the session the app is running right now —
/// that is the one case where the wall clock is the session's real span.
/// [lastFrameAt] is the newest frame recorded against the session, from
/// [lastFrameBySessionProvider].
SessionElapsed sessionElapsed(
  ImagingSession session, {
  required bool isLive,
  DateTime? lastFrameAt,
  DateTime? now,
}) {
  final endTime = session.endTime;
  if (endTime != null) {
    return SessionElapsed(
      _nonNegative(endTime.difference(session.startTime)),
      SessionElapsedBasis.closed,
    );
  }
  if (isLive) {
    return SessionElapsed(
      _nonNegative((now ?? DateTime.now()).difference(session.startTime)),
      SessionElapsedBasis.running,
    );
  }
  if (lastFrameAt != null && lastFrameAt.isAfter(session.startTime)) {
    return SessionElapsed(
      lastFrameAt.difference(session.startTime),
      SessionElapsedBasis.lastFrame,
    );
  }
  return const SessionElapsed(null, SessionElapsedBasis.unknown);
}

Duration _nonNegative(Duration d) => d.isNegative ? Duration.zero : d;

/// `4h 12m` / `20m` / `45s`.
String formatSessionDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m';
  return '${d.inSeconds}s';
}

/// Newest frame timestamp per session id.
///
/// Derived from [allDbImagesProvider] rather than a dedicated aggregate so the
/// same map is available in remote mode (where the images are polled from the
/// host) and so the History list and the Session tab read one source — the
/// whole point of the helper above.
final lastFrameBySessionProvider = Provider<Map<int, DateTime>>((ref) {
  final images =
      ref.watch(allDbImagesProvider).valueOrNull ?? const <DbCapturedImage>[];
  final byId = <int, DateTime>{};
  for (final image in images) {
    final sessionId = image.sessionId;
    if (sessionId == null) continue;
    final current = byId[sessionId];
    if (current == null || image.capturedAt.isAfter(current)) {
      byId[sessionId] = image.capturedAt;
    }
  }
  return byId;
});
