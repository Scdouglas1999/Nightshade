/// Shared sexagesimal formatters for Right Ascension (hours) and Declination
/// (degrees).
///
/// Historically, ~20 screens each carried their own private `_formatRa` /
/// `_formatDec` helper. Most of those produced one of a small number of
/// distinct visual styles. This class consolidates them into a single,
/// parameterized implementation so the math lives in exactly one place.
///
/// IMPORTANT: the byte-for-byte output of a given [SexagesimalStyle] is part of
/// this class's contract — call sites were migrated only because the chosen
/// style reproduces their previous string exactly. Do not "tidy up" a style's
/// output without auditing every consumer, or you will silently change what
/// users see.
library;

/// How the seconds component of a sexagesimal value is rendered.
enum SecondsPrecision {
  /// Round to the nearest whole second (`.round()`), no decimals.
  integerRounded,

  /// Truncate toward zero to a whole second (`.floor()` of a non-negative
  /// value), no decimals.
  integerFloored,

  /// One fractional digit (`toStringAsFixed(1)`).
  oneDecimal,
}

/// The glyphs that separate the three components and the units shown.
enum SexagesimalStyle {
  /// `HHh MMm SSs` / `±DD° MM' SS"` — letter/symbol units, single spaces,
  /// two-digit zero padding on every component.
  paddedLetters,

  /// `HH:MM:SS` / `±DD:MM:SS` — colon separated, two-digit zero padding.
  paddedColons,
}

/// Astronomical coordinate formatting (presentation only — no parsing).
///
/// See [SexagesimalStyle] / [SecondsPrecision] for the exact output shapes.
class CoordinateFormat {
  const CoordinateFormat._();

  /// Format Right Ascension given in **decimal hours**.
  ///
  /// [style] selects the separators/padding; [seconds] selects the seconds
  /// precision. Negative or >24h inputs are formatted as-is (callers that need
  /// wrap/normalization must do it before calling).
  static String ra(
    double raHours, {
    SexagesimalStyle style = SexagesimalStyle.paddedLetters,
    SecondsPrecision seconds = SecondsPrecision.oneDecimal,
  }) {
    final h = raHours.floor();
    final remainder = (raHours - h) * 60;
    final m = remainder.floor();
    final rawSeconds = (remainder - m) * 60;
    final secStr = _formatSeconds(rawSeconds, seconds);

    switch (style) {
      case SexagesimalStyle.paddedLetters:
        return '${_pad2(h)}h ${_pad2(m)}m ${secStr}s';
      case SexagesimalStyle.paddedColons:
        return '${_pad2(h)}:${_pad2(m)}:$secStr';
    }
  }

  /// Format Declination given in **decimal degrees**.
  ///
  /// Always prefixes an explicit `+`/`-` sign.
  static String dec(
    double decDegrees, {
    SexagesimalStyle style = SexagesimalStyle.paddedLetters,
    SecondsPrecision seconds = SecondsPrecision.oneDecimal,
  }) {
    final sign = decDegrees >= 0 ? '+' : '-';
    final abs = decDegrees.abs();
    final d = abs.floor();
    final remainder = (abs - d) * 60;
    final m = remainder.floor();
    final rawSeconds = (remainder - m) * 60;
    final secStr = _formatSeconds(rawSeconds, seconds);

    switch (style) {
      case SexagesimalStyle.paddedLetters:
        return "$sign${_pad2(d)}° ${_pad2(m)}' $secStr\"";
      case SexagesimalStyle.paddedColons:
        return '$sign${_pad2(d)}:${_pad2(m)}:$secStr';
    }
  }

  static String _formatSeconds(double rawSeconds, SecondsPrecision precision) {
    switch (precision) {
      case SecondsPrecision.integerRounded:
        return _pad2(rawSeconds.round());
      case SecondsPrecision.integerFloored:
        return _pad2(rawSeconds.floor());
      case SecondsPrecision.oneDecimal:
        return rawSeconds.toStringAsFixed(1);
    }
  }

  static String _pad2(int value) => value.toString().padLeft(2, '0');
}
