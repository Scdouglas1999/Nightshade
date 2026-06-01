part of '../session_report_dialog.dart';

class _DiagnosticIssueTile extends StatelessWidget {
  final ValidationIssue issue;
  final NightshadeColors colors;

  const _DiagnosticIssueTile({
    required this.issue,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = issue.category == ValidationCategory.opticalTrain
        ? colors.primary
        : colors.info;
    final icon = issue.category == ValidationCategory.opticalTrain
        ? LucideIcons.crosshair
        : LucideIcons.activity;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 12, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  issue.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
                if (issue.resolutionHint != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    issue.resolutionHint!,
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
