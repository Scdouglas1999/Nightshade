import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Sizes a chart plot area with a floor of [minHeight] and optional growth on
/// large viewports. Use [AdaptiveChartContainer.fixed] for empty and loading
/// placeholders so their height stays stable.
class AdaptiveChartContainer extends StatelessWidget {
  final Widget child;

  /// Minimum plot height in logical pixels.
  final double minHeight;

  /// Baseline height at standard desktop widths; defaults to [minHeight].
  final double? preferredHeight;

  /// Upper bound when [adaptToViewport] is true.
  final double? maxHeight;

  /// When false, height is exactly [preferredHeight] (or [minHeight]).
  final bool adaptToViewport;

  static const double defaultMinHeight = 150;

  const AdaptiveChartContainer({
    super.key,
    required this.child,
    this.minHeight = defaultMinHeight,
    this.preferredHeight,
    this.maxHeight,
    this.adaptToViewport = true,
  });

  const AdaptiveChartContainer.fixed({
    super.key,
    required this.child,
    required double height,
  })  : minHeight = height,
        preferredHeight = height,
        maxHeight = height,
        adaptToViewport = false;

  double _resolveHeight(BuildContext context, BoxConstraints constraints) {
    final base = preferredHeight ?? minHeight;
    if (!adaptToViewport) {
      return base;
    }

    final viewport = MediaQuery.sizeOf(context);
    final minDim = math.min(viewport.width, viewport.height);

    // Modest growth on large screens (up to ~25% above baseline).
    final growthFactor = Responsive.isDesktop(context)
        ? 1.0 + (minDim - 900).clamp(0.0, 500.0) / 500.0 * 0.25
        : 1.0;
    var height = base * growthFactor;

    if (constraints.hasBoundedHeight && constraints.maxHeight.isFinite) {
      final parentBudget = constraints.maxHeight * 0.4;
      if (parentBudget > base) {
        height = math.max(height, math.min(parentBudget, base * 1.35));
      }
    }

    final cap = maxHeight ?? base * 1.35;
    return height.clamp(minHeight, cap);
  }

  @override
  Widget build(BuildContext context) {
    if (!adaptToViewport) {
      final height = preferredHeight ?? minHeight;
      return SizedBox(
        height: height,
        width: double.infinity,
        child: child,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = _resolveHeight(context, constraints);
        return SizedBox(
          height: height,
          width: double.infinity,
          child: child,
        );
      },
    );
  }
}
