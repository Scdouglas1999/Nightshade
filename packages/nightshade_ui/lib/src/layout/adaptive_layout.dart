import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/nightshade_tokens.dart';

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
/// [clampPanelWidth] and [dialogMaxWidth] answer “how wide in this layout?”.
///
/// Shell chrome heights and nav-vs-bottom thresholds live in
/// [ShellChromeMetrics], not here.
double clampPanelWidth(
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

/// Caps a dialog's design width to 92% of the viewport width.
///
/// Prefer this over a raw `designMax` when showing modals on narrow windows or
/// mobile web. Pair with [Responsive.dialogConstraints] when you also need
/// height limits and minimum sizes.
double dialogMaxWidth(BuildContext context, double designMax) {
  final viewportWidth = MediaQuery.sizeOf(context).width;
  return math.min(designMax, viewportWidth * 0.92);
}
