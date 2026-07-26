import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'science_ladder_model.dart';
import 'science_nav_row_card.dart';
import 'science_rung_sheet.dart';

class ScienceLadderCard extends ConsumerWidget {
  final bool hasCalibration;
  final bool hasTarget;
  final bool photometryLive;
  final int lightCurvePoints;
  final bool hasPeriodResult;
  final bool hasExportableData;
  final VoidCallback onJumpToPhotometry;
  final VoidCallback onJumpToFieldQuality;
  final VoidCallback onOpenExport;

  const ScienceLadderCard({
    super.key,
    required this.hasCalibration,
    required this.hasTarget,
    required this.photometryLive,
    required this.lightCurvePoints,
    required this.hasPeriodResult,
    required this.hasExportableData,
    required this.onJumpToPhotometry,
    required this.onJumpToFieldQuality,
    required this.onOpenExport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final collapsed = ref.watch(
      scienceSettingsProvider.select(
        (s) => s.valueOrNull?.scienceGuideCollapsed ?? false,
      ),
    );

    final progress = evaluateLadder(
      hasCalibration: hasCalibration,
      hasTarget: hasTarget,
      photometryLive: photometryLive,
      lightCurvePoints: lightCurvePoints,
      hasPeriodResult: hasPeriodResult,
      hasExportableData: hasExportableData,
    );

    if (collapsed) {
      return _CollapsedRow(
          progress: progress, onExpand: () => _setCollapsed(ref, false));
    }

    final next = progress.nextActionable;
    final nextSpec =
        next == null ? null : kScienceLadder.firstWhere((s) => s.rung == next);

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration:
                    NightshadeDecorations.emphasisSurface(colors.primary),
                child: Icon(
                  LucideIcons.flaskConical,
                  color: colors.primary,
                  size: NightshadeTokens.iconSm,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Text(
                  'Science guide',
                  style: NightshadeTypography.h6.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Collapse science guide',
                child: IconButton(
                  tooltip: 'Collapse',
                  onPressed: () => _setCollapsed(ref, true),
                  icon: Icon(LucideIcons.x, color: colors.textMuted),
                  splashRadius: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < kScienceLadder.length; i++) ...[
                  if (i != 0) ...[
                    Container(
                      width: 16,
                      height: 1,
                      color: colors.border,
                    ),
                  ],
                  _RungChip(
                    index: i + 1,
                    spec: kScienceLadder[i],
                    state: progress.states[kScienceLadder[i].rung]!,
                    onTap: () => _openRung(context, ref, kScienceLadder[i]),
                  ),
                ],
              ],
            ),
          ),
          if (nextSpec != null) ...[
            const SizedBox(height: NightshadeTokens.spaceLg),
            Align(
              alignment: Alignment.centerLeft,
              child: NightshadeButton(
                label: nextSpec.ctaLabel,
                icon: LucideIcons.arrowRight,
                onPressed: () => _runCta(context, ref, nextSpec.rung),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _setCollapsed(WidgetRef ref, bool collapsed) {
    ref
        .read(scienceSettingsProvider.notifier)
        .setScienceGuideCollapsed(collapsed);
  }

  void _openRung(BuildContext context, WidgetRef ref, ScienceRungSpec spec) {
    final state = evaluateLadder(
      hasCalibration: hasCalibration,
      hasTarget: hasTarget,
      photometryLive: photometryLive,
      lightCurvePoints: lightCurvePoints,
      hasPeriodResult: hasPeriodResult,
      hasExportableData: hasExportableData,
    ).states[spec.rung]!;
    showScienceRungSheet(
      context,
      spec,
      state,
      prerequisite: _prerequisiteFor(spec.rung),
      onCta: () => _runCta(context, ref, spec.rung),
    );
  }

  void _runCta(BuildContext context, WidgetRef ref, ScienceRung rung) {
    switch (rung) {
      case ScienceRung.measure:
        onJumpToFieldQuality();
      case ScienceRung.track:
      case ScienceRung.curve:
      case ScienceRung.period:
        onJumpToPhotometry();
      case ScienceRung.contribute:
        onOpenExport();
    }
  }

  String? _prerequisiteFor(ScienceRung rung) {
    return switch (rung) {
      ScienceRung.measure => null,
      ScienceRung.track => 'Calibrate your sky first so brightness reads true.',
      ScienceRung.curve =>
        'Turn on live photometry and track a star to start collecting points.',
      ScienceRung.period => 'Gather at least ten light-curve points first.',
      ScienceRung.contribute =>
        'Find a period — or build out the curve — before exporting.',
    };
  }
}

class _RungChip extends StatelessWidget {
  final int index;
  final ScienceRungSpec spec;
  final RungState state;
  final VoidCallback onTap;

  const _RungChip({
    required this.index,
    required this.spec,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final (accent, foreground, digit) = switch (state) {
      RungState.done => (colors.success, colors.success, colors.success),
      RungState.ready => (colors.primary, colors.textPrimary, colors.primary),
      RungState.locked => (
          colors.textMuted,
          colors.textMuted,
          colors.textSecondary
        ),
    };

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 132,
          constraints: const BoxConstraints(
            minHeight: NightshadeTokens.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: NightshadeTokens.spaceMd,
            vertical: NightshadeTokens.spaceSm + 2,
          ),
          decoration: state == RungState.ready
              ? NightshadeDecorations.selectedSurface(colors.primary)
              : BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: NightshadeTokens.borderRadiusMd,
                  border: Border.all(color: colors.border),
                ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: NightshadeDecorations.statusChip(accent),
                child: state == RungState.done
                    ? Icon(LucideIcons.check, size: 12, color: accent)
                    : Text(
                        '$index',
                        style: TextStyle(
                          color: digit,
                          fontSize: NightshadeTypography.fontSize12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Flexible(
                child: Text(
                  spec.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: NightshadeTypography.fontSize11_5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsedRow extends StatelessWidget {
  final ScienceLadderProgress progress;
  final VoidCallback onExpand;

  const _CollapsedRow({required this.progress, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final step = (progress.nextActionable == null ? 5 : progress.doneCount + 1)
        .clamp(1, 5);
    return ScienceNavRowCard(
      icon: LucideIcons.flaskConical,
      iconColor: colors.primary,
      label: 'Science guide — step $step of 5',
      labelColor: colors.textSecondary,
      onTap: onExpand,
    );
  }
}
