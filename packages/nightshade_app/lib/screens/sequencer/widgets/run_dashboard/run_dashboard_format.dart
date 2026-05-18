/// Utility formatters shared across run-dashboard panels.
///
/// Kept in one file so all duration / RA / Dec strings on the dashboard
/// look the same (audit §UI consistency: design-system rule).
library;

String formatRA(double raHours) {
  final h = raHours.floor();
  final m = ((raHours - h) * 60).floor();
  final s = (((raHours - h) * 60 - m) * 60).round();
  return '${h.toString().padLeft(2, '0')}h '
      '${m.toString().padLeft(2, '0')}m '
      '${s.toString().padLeft(2, '0')}s';
}

String formatDec(double decDegrees) {
  final sign = decDegrees >= 0 ? '+' : '-';
  final v = decDegrees.abs();
  final d = v.floor();
  final m = ((v - d) * 60).floor();
  final s = (((v - d) * 60 - m) * 60).round();
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
