/// Human-readable integration / elapsed times, in the one shape the app uses.
///
/// WHY THIS EXISTS: the Continue Session dialog formatted integration as
/// whole minutes ("0 minutes" for a 12-second session, "2 minutes" for 90
/// seconds) while the dashboard's last-run card rendered the same run as
/// "12s". Reporting real captured photons as "0 minutes" reads as "the run
/// did nothing". One formatter, so the two surfaces cannot disagree.
library;

/// Format [seconds] as `1h 2m 3s` / `2m 3s` / `3s`.
///
/// Units are dropped from the left only: once hours are present, minutes and
/// seconds are always shown, so the string never silently loses precision.
/// Negative and non-finite inputs collapse to `0s` rather than rendering a
/// nonsense duration.
String formatIntegrationSeconds(double seconds) {
  if (!seconds.isFinite || seconds <= 0) return '0s';
  // Round to whole seconds FIRST so 59.6s reads "1m 0s" rather than "60s".
  final total = seconds.round();
  final hours = total ~/ 3600;
  final mins = (total % 3600) ~/ 60;
  final secs = total % 60;
  if (hours > 0) return '${hours}h ${mins}m ${secs}s';
  if (mins > 0) return '${mins}m ${secs}s';
  return '${secs}s';
}

/// [formatIntegrationSeconds] for a value already expressed in hours.
String formatIntegrationHours(double hours) =>
    formatIntegrationSeconds(hours * 3600);
