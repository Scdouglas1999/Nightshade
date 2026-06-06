part of '../preflight_validation_dialog.dart';

class _PreflightSection extends StatefulWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String title;
  final List<ValidationIssue> issues;
  final Widget? trailing;

  const _PreflightSection({
    required this.colors,
    required this.icon,
    required this.title,
    required this.issues,
    this.trailing,
  });

  @override
  State<_PreflightSection> createState() => _PreflightSectionState();
}

class _PreflightSectionState extends State<_PreflightSection> {
  bool _expanded = true;

  Color _worstColor() {
    if (widget.issues.any((i) => i.severity == ValidationSeverity.error)) {
      return widget.colors.error;
    }
    if (widget.issues.any((i) => i.severity == ValidationSeverity.warning)) {
      return widget.colors.warning;
    }
    return widget.colors.info;
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final tone = _worstColor();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: NightshadeCard(
        borderRadius: NightshadeTokens.radiusLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: NightshadeDecorations.statusChip(
                        tone,
                        borderRadius:
                            BorderRadius.circular(NightshadeTokens.radiusMd),
                        bordered: false,
                      ),
                      child: Icon(widget.icon, size: 14, color: tone),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: NightshadeTypography.labelStrong
                            .copyWith(color: colors.textPrimary),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: NightshadeDecorations.statusChip(
                        tone,
                        borderRadius: BorderRadius.circular(
                            NightshadeTokens.radiusInline8),
                        bordered: false,
                      ),
                      child: Text(
                        '${widget.issues.length}',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize11,
                          fontWeight: FontWeight.w700,
                          color: tone,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 16,
                      color: colors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 1, thickness: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final issue in widget.issues)
                      _IssueRow(colors: colors, issue: issue),
                  ],
                ),
              ),
              if (widget.trailing != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    children: [
                      const Spacer(),
                      widget.trailing!,
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final NightshadeColors colors;
  final ValidationIssue issue;

  const _IssueRow({required this.colors, required this.issue});

  @override
  Widget build(BuildContext context) {
    final Color issueColor;
    final IconData issueIcon;
    switch (issue.severity) {
      case ValidationSeverity.error:
        issueColor = colors.error;
        issueIcon = LucideIcons.xCircle;
        break;
      case ValidationSeverity.warning:
        issueColor = colors.warning;
        issueIcon = LucideIcons.alertTriangle;
        break;
      case ValidationSeverity.info:
        issueColor = colors.info;
        issueIcon = LucideIcons.info;
        break;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(issueIcon, size: 12, color: issueColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.title,
                  style: NightshadeTypography.h6
                      .copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  issue.description,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.textSecondary,
                  ),
                ),
                if (issue.resolutionHint != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.lightbulb,
                          size: 10, color: colors.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          issue.resolutionHint!,
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize10,
                            color: colors.primary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
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
