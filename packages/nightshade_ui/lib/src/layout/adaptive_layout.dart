import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/nightshade_tokens.dart';
import '../utils/adaptive_dialog_constraints.dart';

/// Fractional panel sizing and viewport-capped dialog widths.
///
/// ## When to use this library vs [NightshadeTokens] breakpoints
///
/// Use the functions in this file when sizing should **track available space**
/// continuously (percent of parent, min/max clamps, dialog width caps).
///
/// Use [NightshadeTokens.breakpointMobile] … [breakpointUltraWide] with
/// [Responsive] (from `breakpoints.dart`) or [BreakpointTokens] when the UI
/// should **switch layout modes** at fixed widths (e.g. one column vs two,
/// bottom nav vs side rail, toolbar overflow). Breakpoints answer “which layout?”;
/// [panelWidthFromFraction] and [dialogMaxWidth] answer “how wide in this
/// layout?”.
///
/// Shell chrome heights and nav-vs-bottom thresholds live in
/// [ShellChromeMetrics], not here.
///
/// Not to be confused with [AdaptiveDialogConstraints.clampPanelWidth], which
/// answers a different question — it reads the viewport off a [BuildContext]
/// and caps a *design* width, where this takes the available width and a
/// fraction of it.
double panelWidthFromFraction(
  double available, {
  required double fraction,
  required double min,
  required double max,
}) {
  assert(available >= 0, 'available width must be non-negative');
  assert(fraction >= 0 && fraction <= 1, 'fraction must be between 0 and 1');
  assert(min <= max, 'min must be <= max');
  return (available * fraction).clamp(min, max);
}

@Deprecated(
  'Renamed to panelWidthFromFraction — it was indistinguishable at the call '
  'site from AdaptiveDialogConstraints.clampPanelWidth, which does something '
  'else. Will be removed one release after 6.1.0.',
)
double clampPanelWidth(
  double available, {
  required double fraction,
  required double min,
  required double max,
}) => panelWidthFromFraction(available, fraction: fraction, min: min, max: max);

/// Caps a dialog's design width to
/// [AdaptiveDialogConstraints.defaultWidthFraction] of the viewport width.
///
/// Prefer this over a raw `designMax` when showing modals on narrow windows or
/// mobile web. Pair with [Responsive.dialogConstraints] when you also need
/// height limits and minimum sizes.
double dialogMaxWidth(BuildContext context, double designMax) {
  final viewportWidth = MediaQuery.sizeOf(context).width;
  return math.min(
    designMax,
    viewportWidth * AdaptiveDialogConstraints.defaultWidthFraction,
  );
}
