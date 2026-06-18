/// Utility formatters shared across run-dashboard panels.
///
/// Kept in one file so all duration / RA / Dec strings on the dashboard
/// look the same (audit §UI consistency: design-system rule).
library;

String formatRA(double raHours) {
  // Decompose from a single rounded second count so the seconds carry into
  // minutes (and minutes into hours) instead of rendering a bogus "60s".
  var totalSeconds = (raHours * 3600).round();
  // RA wraps at 24h; keep it in [0, 24h) after the carry.
  totalSeconds %= 24 * 3600;
  if (totalSeconds < 0) totalSeconds += 24 * 3600;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  return '${h.toString().padLeft(2, '0')}h '
      '${m.toString().padLeft(2, '0')}m '
      '${s.toString().padLeft(2, '0')}s';
}

String formatDec(double decDegrees) {
  final sign = decDegrees >= 0 ? '+' : '-';
  // Decompose the absolute value from a single rounded second count so the
  // seconds carry into arcminutes (and arcminutes into degrees), then apply
  // the sign. Eliminates the 60-second carry artifact.
  final totalSeconds = (decDegrees.abs() * 3600).round();
  final d = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  return '$sign${d.toString().padLeft(2, '0')}° '
      '${m.toString().padLeft(2, '0')}\' '
      '${s.toString().padLeft(2, '0')}"';
}

/// Friendly duration: "2h 12m", "45m", "30s", "—" for nulls.
String formatDuration(Duration? d) {
  if (d == null) return '—';
  if (d.isNegative) return '—';
  final total = d.inSeconds;
  if (total == 0) return '0s';
  if (total >= 3600) {
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }
  if (total >= 60) {
    final m = total ~/ 60;
    final s = total % 60;
    return s > 0 && m < 5 ? '${m}m ${s}s' : '${m}m';
  }
  return '${total}s';
}

String formatSeconds(double seconds) {
  return formatDuration(Duration(seconds: seconds.round()));
}

String formatTimeOfDay(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  final s = t.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}
