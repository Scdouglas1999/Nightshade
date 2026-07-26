part of '../diagnostics_screen.dart';

class _DocsInfoChip extends StatelessWidget {
  final NightshadeColors colors;

  const _DocsInfoChip({required this.colors});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      onTap: () => _showGuide(context),
      child: Tooltip(
        message: 'Open optical diagnostics guide',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Learn more about optical diagnostics',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NightshadeTypography.labelSm
                      .copyWith(color: colors.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGuide(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.info, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text('Reading optical diagnostics')),
          ],
        ),
        content: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            dialogContext,
            designMaxWidth: 560,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _GuideParagraph(
                  'Nightshade compares solved light frames across the sensor. '
                  'Use several representative frames from one session; clouds, '
                  'guiding errors, and poor focus can distort a single-frame result.',
                ),
                const SizedBox(height: 16),
                const _GuideHeading('Scores and grade'),
                const _GuideParagraph(
                  'Tilt and collimation are penalty scores from 0 to 100, so '
                  'lower is better. The letter grade inverts and averages those '
                  'two penalties: A starts at 90, B at 75, C at 55, and D at 35.',
                ),
                const SizedBox(height: 12),
                _GuideThreshold(
                  label: 'Tilt',
                  good: '< ${OpticalHealthScore.tiltWarnThreshold.toInt()}',
                  warning:
                      '${OpticalHealthScore.tiltWarnThreshold.toInt()}–${OpticalHealthScore.tiltCriticalThreshold.toInt() - 1}',
                  critical:
                      '≥ ${OpticalHealthScore.tiltCriticalThreshold.toInt()}',
                  colors: colors,
                ),
                const SizedBox(height: 8),
                _GuideThreshold(
                  label: 'Collimation / spacing',
                  good:
                      '< ${OpticalHealthScore.collimationWarnThreshold.toInt()}',
                  warning:
                      '${OpticalHealthScore.collimationWarnThreshold.toInt()}–${OpticalHealthScore.collimationCriticalThreshold.toInt() - 1}',
                  critical:
                      '≥ ${OpticalHealthScore.collimationCriticalThreshold.toInt()}',
                  colors: colors,
                ),
                const SizedBox(height: 16),
                const _GuideHeading('What the patterns mean'),
                const _GuideBullet(
                  'Tilt: star size changes from one side or corner of the '
                  'sensor to the opposite side. Check the camera tilter, '
                  'focuser sag, adapters, and sensor seating.',
                ),
                const _GuideBullet(
                  'Collimation / spacing: astrometric residuals grow toward '
                  'the field edge. Check corrector backfocus and optical '
                  'alignment before changing tilt.',
                ),
                const _GuideBullet(
                  'Field map: compare opposite tiles and look for a repeatable '
                  'direction across multiple frames, not one isolated bad tile.',
                ),
                const SizedBox(height: 12),
                Text(
                  'Make one mechanical change at a time, capture another '
                  'representative set, then compare the scores and direction.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          NightshadeButton(
            label: 'Close',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }
}

class _GuideHeading extends StatelessWidget {
  final String text;

  const _GuideHeading(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: NightshadeTypography.labelStrong.copyWith(
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

class _GuideParagraph extends StatelessWidget {
  final String text;

  const _GuideParagraph(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Text(
      text,
      style: TextStyle(
        color: colors.textSecondary,
        fontSize: NightshadeTypography.fontSize12,
        height: 1.4,
      ),
    );
  }
}

class _GuideBullet extends StatelessWidget {
  final String text;

  const _GuideBullet(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _GuideParagraph(text)),
        ],
      ),
    );
  }
}

class _GuideThreshold extends StatelessWidget {
  final String label;
  final String good;
  final String warning;
  final String critical;
  final NightshadeColors colors;

  const _GuideThreshold({
    required this.label,
    required this.good,
    required this.warning,
    required this.critical,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: NightshadeTypography.labelStrongSm.copyWith(
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _ThresholdPill(label: 'Good $good', color: colors.success),
            _ThresholdPill(label: 'Watch $warning', color: colors.warning),
            _ThresholdPill(label: 'Strong $critical', color: colors.error),
          ],
        ),
      ],
    );
  }
}

class _ThresholdPill extends StatelessWidget {
  final String label;
  final Color color;

  const _ThresholdPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: NightshadeTypography.labelStrongSm.copyWith(color: color),
      ),
    );
  }
}

class _SessionSelector extends StatelessWidget {
  final List<ImagingSession> sessions;
  final int? selectedSessionId;
  final ValueChanged<int?> onChanged;
  final NightshadeColors colors;

  const _SessionSelector({
    required this.sessions,
    required this.selectedSessionId,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Text(
        context.l10n.text('diagnosticsNoSessions'),
        style: TextStyle(
            color: colors.textMuted, fontSize: NightshadeTypography.fontSize12),
      );
    }

    final dateFormat = DateFormat('MMM d, HH:mm');
    final sessionsByRecency = sessions.reversed.toList();
    final recentSessions = sessionsByRecency.take(50).toList();
    final selectedSession = selectedSessionId == null
        ? null
        : sessions.cast<ImagingSession?>().firstWhere(
              (session) => session?.id == selectedSessionId,
              orElse: () => null,
            );
    final visibleSessions = [...recentSessions];

    if (selectedSession != null &&
        !visibleSessions.any((session) => session.id == selectedSession.id)) {
      visibleSessions.insert(0, selectedSession);
    }

    final dropdownValue = selectedSessionId != null &&
            visibleSessions.any((session) => session.id == selectedSessionId)
        ? selectedSessionId
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: dropdownValue,
          // isExpanded lets the button shrink to its bounded parent and
          // ellipsize the selected label instead of sizing to the widest
          // item (which overflows a narrow phone header).
          isExpanded: true,
          hint: Text(
            context.l10n.text('diagnosticsSelectSession'),
            style: TextStyle(
                color: colors.textMuted,
                fontSize: NightshadeTypography.fontSize13),
          ),
          dropdownColor: colors.surfaceElevated,
          style: TextStyle(
              color: colors.textPrimary,
              fontSize: NightshadeTypography.fontSize13),
          icon:
              Icon(LucideIcons.chevronDown, size: 14, color: colors.textMuted),
          items: visibleSessions.map((session) {
            final label = session.name != null && session.name!.isNotEmpty
                ? '${session.name} (${dateFormat.format(session.startTime)})'
                : dateFormat.format(session.startTime);
            return DropdownMenuItem(
              value: session.id,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
