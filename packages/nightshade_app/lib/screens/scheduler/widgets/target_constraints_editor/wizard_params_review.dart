part of '../target_constraints_editor.dart';

class _Step2Params extends StatelessWidget {
  final String targetName;
  final TargetConstraintKind kind;
  final TargetTimeWindow timeWindow;
  final double moonMax;
  final int? horizonId;
  final List<HorizonProfile> horizonProfiles;
  final ScheduledWindow scheduledWindow;
  final void Function(TargetTimeWindow) onTimeWindow;
  final void Function(double) onMoonMax;
  final void Function(int) onHorizon;
  final void Function(ScheduledWindow) onScheduledWindow;

  const _Step2Params({
    required this.targetName,
    required this.kind,
    required this.timeWindow,
    required this.moonMax,
    required this.horizonId,
    required this.horizonProfiles,
    required this.scheduledWindow,
    required this.onTimeWindow,
    required this.onMoonMax,
    required this.onHorizon,
    required this.onScheduledWindow,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    Widget body;
    switch (kind) {
      case TargetConstraintKind.timeWindow:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Default 22:00 – 02:00 local — a typical imaging session. '
              'Tap a time to adjust.',
              style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textSecondary),
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            _TimeWindowField(
              window: timeWindow,
              onChange: onTimeWindow,
            ),
          ],
        );
        break;
      case TargetConstraintKind.moonIlluminationMax:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Default 30% max illumination — typical for narrowband and '
              'most broadband DSO work. Increase the cap if your target '
              'tolerates more moon.',
              style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textSecondary),
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            _MoonField(value: moonMax, onChange: onMoonMax),
          ],
        );
        break;
      case TargetConstraintKind.customHorizon:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (horizonProfiles.isEmpty)
              Text(
                'No horizon profiles defined yet. Manage horizon '
                'profiles in Settings → Observing site, then return here '
                'to attach one.',
                style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.warning),
              )
            else ...[
              Text(
                'Pick an existing horizon profile to use for $targetName.',
                style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textSecondary),
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              _HorizonField(
                selectedId: horizonId,
                profiles: horizonProfiles,
                onChange: onHorizon,
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                'Manage horizon profiles in Settings → Observing site.',
                style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textMuted),
              ),
            ],
          ],
        );
        break;
      case TargetConstraintKind.scheduledWindow:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Forces the scheduler onto $targetName during the window, '
              'bypassing hysteresis. Defaults to tonight 20:00 → 06:00 '
              'local — adjust as needed.',
              style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textSecondary),
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            _ScheduledWindowField(
              window: scheduledWindow,
              onChange: onScheduledWindow,
            ),
          ],
        );
        break;
    }
    return body;
  }
}

class _Step3Review extends StatelessWidget {
  final String targetName;
  final TargetConstraintKind kind;
  final TargetTimeWindow timeWindow;
  final double moonMax;
  final int? horizonId;
  final List<HorizonProfile> horizonProfiles;
  final ScheduledWindow scheduledWindow;

  const _Step3Review({
    required this.targetName,
    required this.kind,
    required this.timeWindow,
    required this.moonMax,
    required this.horizonId,
    required this.horizonProfiles,
    required this.scheduledWindow,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    String typeLabel;
    String summary;
    switch (kind) {
      case TargetConstraintKind.timeWindow:
        typeLabel = 'Time window';
        summary =
            'Only image $targetName between ${_fmt(timeWindow.startMinutes)} and ${_fmt(timeWindow.endMinutes)} local time.';
        break;
      case TargetConstraintKind.moonIlluminationMax:
        typeLabel = 'Moon avoidance';
        summary =
            'Skip $targetName when the moon illumination is above ${(moonMax * 100).round()}%.';
        break;
      case TargetConstraintKind.customHorizon:
        final profile = horizonProfiles.firstWhere(
          (p) => p.id == horizonId,
          orElse: () => throw StateError(
              'No horizon profile selected on Step 3 (wizard internal bug)'),
        );
        typeLabel = 'Custom horizon';
        summary =
            'Reject $targetName when below the "${profile.name}" horizon profile at its current azimuth.';
        break;
      case TargetConstraintKind.scheduledWindow:
        final startLocal = scheduledWindow.startUtc.toLocal();
        final endLocal = scheduledWindow.endUtc.toLocal();
        typeLabel = 'Scheduled window';
        summary =
            'Force the scheduler onto $targetName from ${_fmtDt(startLocal)} '
            'to ${_fmtDt(endLocal)} local with priority boost '
            '+${scheduledWindow.priorityBoost.toStringAsFixed(1)}.';
        break;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review and save',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize14,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Container(
          width: double.infinity,
          padding: NightshadeTokens.paddingMd,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                typeLabel,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize13,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                summary,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize13,
                  color: colors.textPrimary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmt(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _fmtDt(DateTime t) {
    final mm = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mn = t.minute.toString().padLeft(2, '0');
    return '$mm/$dd $hh:$mn';
  }
}
