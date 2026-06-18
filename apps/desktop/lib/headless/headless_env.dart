import 'dart:io';

/// Shared environment-variable parsing helpers for the headless bootstrap.
///
/// These primitives are used by several bootstrap modules (auth config, TLS,
/// relay uplink) so they live in one place rather than being duplicated per
/// concern. Behaviour is identical to the original inline helpers in
/// `main_headless.dart`.

/// True when [name] is set to an affirmative value (`1`/`true`/`yes`,
/// case-insensitive, surrounding whitespace ignored).
bool envFlag(String name) {
  final value = Platform.environment[name]?.trim().toLowerCase();
  return value == '1' || value == 'true' || value == 'yes';
}

/// Trim [input] and collapse empty/blank values to null so callers can treat a
/// missing env var and a whitespace-only one identically.
String? trimToNull(String? input) {
  final t = input?.trim();
  if (t == null || t.isEmpty) return null;
  return t;
}
