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

  /// Two fractional digits, zero-padded to a fixed `SS.ss` width.
  twoDecimal,
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
  /// precision. Inputs >24h are formatted as-is (callers that need wrapping
  /// must do it before calling); a negative input is rendered as a signed
  /// magnitude.
  static String ra(
    double raHours, {
    SexagesimalStyle style = SexagesimalStyle.paddedLetters,
    SecondsPrecision seconds = SecondsPrecision.oneDecimal,
  }) {
    final sign = raHours < 0 ? '-' : '';
    final (h, m, secStr) = _decompose(raHours.abs(), seconds);

    switch (style) {
      case SexagesimalStyle.paddedLetters:
        return '$sign${_pad2(h)}h ${_pad2(m)}m ${secStr}s';
      case SexagesimalStyle.paddedColons:
        return '$sign${_pad2(h)}:${_pad2(m)}:$secStr';
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
    final (d, m, secStr) = _decompose(decDegrees.abs(), seconds);

    switch (style) {
      case SexagesimalStyle.paddedLetters:
        return "$sign${_pad2(d)}° ${_pad2(m)}' $secStr\"";
      case SexagesimalStyle.paddedColons:
        return '$sign${_pad2(d)}:${_pad2(m)}:$secStr';
    }
  }

  /// Split a non-negative angle into its three components, quantizing the WHOLE
  /// angle at the rendered seconds precision first so the carry is structural.
  ///
  /// Rounding the seconds field on its own renders values that do not exist:
  /// 5.6h decomposes field-by-field to minutes=35, seconds=59.999…, which
  /// `toStringAsFixed(1)` shows as "05h 35m 60.0s" — a time this package's own
  /// [CoordinateParser] refuses to read back. Quantizing first means seconds
  /// can never reach 60 and minutes can never reach 60, for every precision.
  static (int whole, int minutes, String seconds) _decompose(
    double magnitude,
    SecondsPrecision precision,
  ) {
    final unitsPerSecond = _unitsPerSecond(precision);
    final exact = magnitude * 3600 * unitsPerSecond;
    // Only [SecondsPrecision.integerFloored] truncates; every other precision
    // rounds to its nearest representable value.
    final total = precision == SecondsPrecision.integerFloored
        ? exact.floor()
        : exact.round();

    final unitsPerMinute = 60 * unitsPerSecond;
    final secondsUnits = total % unitsPerMinute;
    final wholeMinutes = total ~/ unitsPerMinute;
    return (
      wholeMinutes ~/ 60,
      wholeMinutes % 60,
      _formatSeconds(secondsUnits, unitsPerSecond, precision),
    );
  }

  /// The quantum [precision] renders at, as sub-second units per second.
  static int _unitsPerSecond(SecondsPrecision precision) {
    switch (precision) {
      case SecondsPrecision.integerRounded:
      case SecondsPrecision.integerFloored:
        return 1;
      case SecondsPrecision.oneDecimal:
        return 10;
      case SecondsPrecision.twoDecimal:
        return 100;
    }
  }

  static String _formatSeconds(
    int units,
    int unitsPerSecond,
    SecondsPrecision precision,
  ) {
    switch (precision) {
      case SecondsPrecision.integerRounded:
      case SecondsPrecision.integerFloored:
        return _pad2(units);
      case SecondsPrecision.oneDecimal:
        return (units / unitsPerSecond).toStringAsFixed(1);
      case SecondsPrecision.twoDecimal:
        return (units / unitsPerSecond).toStringAsFixed(2).padLeft(5, '0');
    }
  }

  static String _pad2(int value) => value.toString().padLeft(2, '0');
}
