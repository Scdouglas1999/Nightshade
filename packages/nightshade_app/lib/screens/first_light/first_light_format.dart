/// A user-facing message for a First Light load error, trimmed of the bridge's
/// envelope noise (`Exception:` / `DifferenceImageSeamException:`) so the
/// empty-state body stays readable.
String describeFirstLightError(Object error) {
  var raw = error.toString();
  const prefixes = <String>[
    'DifferenceImageSeamException: ',
    'Exception: ',
  ];
  for (final prefix in prefixes) {
    if (raw.startsWith(prefix)) {
      raw = raw.substring(prefix.length);
      break;
    }
  }
  return raw.isEmpty ? 'Unknown error.' : raw;
}
