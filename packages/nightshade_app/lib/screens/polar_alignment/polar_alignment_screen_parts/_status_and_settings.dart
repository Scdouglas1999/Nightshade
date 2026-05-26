// Part of ../polar_alignment_screen.dart -- extracted for maintainability.
//
// Generic status chip, labelled-setting row, and tip-list item used across the polar alignment side panels.
part of '../polar_alignment_screen.dart';

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isConnected;
  final NightshadeColors colors;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.isConnected,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: NightshadeDecorations.statusChip(
        isConnected ? colors.success : colors.error,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isConnected ? colors.success : colors.error,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isConnected ? colors.success : colors.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final String tooltip;
  final NightshadeColors colors;
  final Widget child;

  const _SettingRow({
    required this.label,
    required this.tooltip,
    required this.colors,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: tooltip,
              waitDuration: const Duration(milliseconds: 500),
              child: Icon(
                LucideIcons.helpCircle,
                size: 12,
                color: colors.textMuted.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _TipItem extends StatelessWidget {
  final NightshadeColors colors;
  final String text;

  const _TipItem({required this.colors, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(LucideIcons.check, size: 12, color: colors.success),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
