import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class DashboardGlassCard extends StatelessWidget {
  final NightshadeColors colors;
  final Widget child;
  final EdgeInsets padding;

  const DashboardGlassCard({
    super.key,
    required this.colors,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
