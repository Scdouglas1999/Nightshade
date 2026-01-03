import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';

enum StatusPillStatus { active, warning, error, inactive }

class StatusPill extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final StatusPillStatus status;
  final VoidCallback? onTap;

  const StatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.status = StatusPillStatus.inactive,
    this.onTap,
  });

  @override
  State<StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<StatusPill> {
  bool _isHovered = false;

  Color _getStatusColor(NightshadeColors colors) {
    switch (widget.status) {
      case StatusPillStatus.active:
        return colors.success;
      case StatusPillStatus.warning:
        return colors.warning;
      case StatusPillStatus.error:
        return colors.error;
      case StatusPillStatus.inactive:
        return colors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final statusColor = _getStatusColor(colors);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovered ? colors.surfaceHover : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.status != StatusPillStatus.inactive
                  ? statusColor.withValues(alpha: 0.3)
                  : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                widget.icon,
                size: 12,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                '${widget.label}: ${widget.value}',
                style: TextStyle(
                  fontSize: 10,
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}





