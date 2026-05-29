// Guided action rail for the survey-backed Framing Wizard (component C7).
//
// `FramingActionRail` is the in-place "wizard" UX: a vertical
// `NightshadeCard` of numbered, ordered steps that walks the user from a
// resolved target all the way to a one-click slew/center/rotate. It is a
// dedicated widget in its own file so the framing sidebar (owned elsewhere)
// can mount it without us reaching into shared sidebar code.
//
// Each step carries a `StatusPill` that reads `success` once that step's
// precondition is satisfied, so the rail doubles as a live readiness
// checklist:
//   1. Target  — resolved name / RA / Dec (read `framingProvider`), or an
//                 `EmptyState.compact` prompting the user to pick a target.
//   2. Frame   — survey-source `NightshadeDropdown` + the (reused, read-only)
//                 `FramingPreviewFovSlider` so the user can dial the cutout
//                 they're about to solve and slew to.
//   3. Solve   — runs `plateSolveServiceProvider.solveWithFallback` on the
//                 currently-displayed survey center. A `SolverNotAvailableError`
//                 surfaces the existing `PlateSolverRequiredBanner`; a
//                 successful solve reports the RA/Dec delta versus the target
//                 in a `NightshadeAlert`.
//   4. GoTo    — embeds the existing `SlewDropdownButton` (the complete
//                 slew + center + rotate flow), passing the framing rotation as
//                 the target angle so "Slew, Center & Rotate" lights up when a
//                 rotator is connected.
//
// Errors are surfaced, never swallowed (see CLAUDE.md) — a solve failure shows
// the solver's own error message; an IO failure writing the frame to disk shows
// the failure rather than silently degrading.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'package:nightshade_app/utils/snackbar_helper.dart';
import 'package:nightshade_app/widgets/plate_solver_required_banner.dart';
import 'package:nightshade_app/widgets/slew_dropdown_button.dart';
import '../../../widgets/tutorial_keys/framing_keys.dart';
import 'framing_controls.dart' show FramingPreviewFovSlider;

/// Outcome of a "Solve current frame" attempt, rendered inline beneath the
/// solve step. Exactly one of [result] / [error] / [solverMissing] is set.
@immutable
class _SolveOutcome {
  /// A solver-reported result (which may itself be `success == false`).
  final PlateSolveResult? result;

  /// The target the frame was solved against, used to compute the offset.
  final FramingTarget? against;

  /// A non-solver error string (IO failure, unexpected exception).
  final String? error;

  /// `true` when no plate solver is reachable; drives the inline banner.
  final bool solverMissing;

  const _SolveOutcome._({
    this.result,
    this.against,
    this.error,
    this.solverMissing = false,
  });

  factory _SolveOutcome.solved(PlateSolveResult result, FramingTarget against) =>
      _SolveOutcome._(result: result, against: against);

  factory _SolveOutcome.failed(String error) => _SolveOutcome._(error: error);

  const _SolveOutcome.noSolver() : this._(solverMissing: true);
}

/// The guided, numbered action rail for the framing wizard.
///
/// Stateful so it can own the transient solve state (in-flight flag + last
/// outcome) without pushing it into the shared framing provider — the outcome
/// is purely presentational and scoped to this rail's lifetime.
class FramingActionRail extends ConsumerStatefulWidget {
  const FramingActionRail({super.key});

  @override
  ConsumerState<FramingActionRail> createState() => _FramingActionRailState();
}

class _FramingActionRailState extends ConsumerState<FramingActionRail> {
  bool _isSolving = false;
  _SolveOutcome? _lastSolve;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final framingState = ref.watch(framingProvider);
    final equipmentAsync = ref.watch(framingFOVProvider);
    final solverDetection = ref.watch(plateSolverDetectionProvider);

    final target = framingState.target;
    final hasTarget = target != null;
    final hasSurveyImage = framingState.surveyImageBytes != null;
    final hasSolver = solverDetection.valueOrNull?.hasAnySolver ?? false;

    final equipment = equipmentAsync.valueOrNull;
    final hasEquipment = equipment?.isReady ?? false;

    return NightshadeCard(
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Guided Framing',
            subtitle: 'Resolve, frame, solve, and slew in order',
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),

          // ---- Step 1: Target -------------------------------------------
          _StepRow(
            number: 1,
            title: 'Target',
            status: hasTarget
                ? StatusPillStatus.success
                : StatusPillStatus.inactive,
            statusValue: hasTarget ? 'Resolved' : 'None',
            colors: colors,
            child: hasTarget
                ? _TargetSummary(colors: colors, target: target)
                : const EmptyState.compact(
                    icon: LucideIcons.target,
                    title: 'No target selected',
                    body: 'Search for an object or enter coordinates to begin '
                        'framing.',
                  ),
          ),

          _stepDivider(colors),

          // ---- Step 2: Frame --------------------------------------------
          _StepRow(
            number: 2,
            title: 'Frame',
            status: hasSurveyImage
                ? StatusPillStatus.success
                : StatusPillStatus.inactive,
            statusValue: hasSurveyImage ? 'Loaded' : 'Pending',
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Survey Source',
                  style: NightshadeTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: NightshadeTokens.spaceXs),
                NightshadeDropdown(
                  isExpanded: true,
                  value: framingState.surveySource.name,
                  items:
                      SurveySource.values.map((s) => s.name).toList(),
                  itemLabels: SurveySource.values
                      .map((s) => s.displayName)
                      .toList(),
                  onChanged: (name) {
                    if (name == null) return;
                    final source = SurveySource.values
                        .firstWhere((s) => s.name == name);
                    ref
                        .read(framingProvider.notifier)
                        .setSurveySource(source);
                  },
                ),
                const SizedBox(height: NightshadeTokens.spaceMd),
                Text(
                  'Preview Field of View',
                  style: NightshadeTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: NightshadeTokens.spaceXs),
                FramingPreviewFovSlider(
                  colors: colors,
                  value: framingState.previewFovDegrees,
                  hasEquipment: hasEquipment,
                  equipmentFov: equipment?.equipment?.fovWidthDeg,
                  onChanged: (value) {
                    ref.read(framingProvider.notifier).setPreviewFov(value);
                  },
                ),
              ],
            ),
          ),

          _stepDivider(colors),

          // ---- Step 3: Solve current frame ------------------------------
          _StepRow(
            number: 3,
            title: 'Solve current frame',
            status: (_lastSolve?.result?.success ?? false)
                ? StatusPillStatus.success
                : (_lastSolve?.error != null || _lastSolve?.solverMissing == true
                    ? StatusPillStatus.error
                    : StatusPillStatus.inactive),
            statusValue: (_lastSolve?.result?.success ?? false)
                ? 'Solved'
                : 'Ready',
            colors: colors,
            child: _SolveStep(
              colors: colors,
              isSolving: _isSolving,
              canSolve: hasTarget && hasSurveyImage && hasSolver && !_isSolving,
              hasTarget: hasTarget,
              hasSurveyImage: hasSurveyImage,
              hasSolver: hasSolver,
              outcome: _lastSolve,
              onSolve: _solveCurrentFrame,
            ),
          ),

          _stepDivider(colors),

          // ---- Step 4: GoTo & Frame -------------------------------------
          _StepRow(
            number: 4,
            title: 'GoTo & Frame',
            status: hasTarget
                ? StatusPillStatus.active
                : StatusPillStatus.inactive,
            statusValue: hasTarget ? 'Ready' : 'No target',
            colors: colors,
            child: hasTarget
                ? SizedBox(
                    width: double.infinity,
                    child: SlewDropdownButton(
                      key: FramingTutorialKeys.slewBtn,
                      ra: target.raHours,
                      dec: target.decDegrees,
                      targetName: target.name,
                      targetRotation: framingState.rotation != 0
                          ? framingState.rotation
                          : null,
                      icon: LucideIcons.compass,
                      label: 'Slew to Target',
                    ),
                  )
                : Text(
                    'Resolve a target above to enable slewing.',
                    style: NightshadeTypography.caption.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _stepDivider(NightshadeColors colors) => Padding(
        padding:
            const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceMd),
        child: Divider(height: 1, color: colors.border),
      );

  /// Solve the currently-displayed survey cutout against the resolved target.
  ///
  /// The displayed cutout is the bytes already in [FramingState.surveyImageBytes]
  /// for the current center. We persist those bytes through the framing image
  /// cache (the canonical on-disk home for survey snapshots) and hand the
  /// resulting path to `solveWithFallback`, hinting with the target coordinates
  /// so the solver converges quickly. The solved RA/Dec is then differenced
  /// against the target to report how far the survey center sits from where the
  /// user intends to point.
  Future<void> _solveCurrentFrame() async {
    final framingState = ref.read(framingProvider);
    final target = framingState.target;
    final bytes = framingState.surveyImageBytes;

    if (target == null || bytes == null || bytes.isEmpty) {
      // The button is disabled in this state; this guard exists so a stray
      // call can never silently no-op without explanation.
      if (mounted) {
        context.showWarningSnackBar(
          'Load a survey frame for a resolved target before solving.',
        );
      }
      return;
    }

    setState(() {
      _isSolving = true;
      _lastSolve = null;
    });

    try {
      final cache = ref.read(framingImageCacheServiceProvider);
      final entry = await cache.saveSurveyImage(
        bytes: Uint8List.fromList(bytes),
        raHours: target.raHours,
        decDegrees: target.decDegrees,
        source: framingState.surveySource,
        targetName: target.name,
        catalogId: target.catalogId,
      );

      final solver = ref.read(plateSolveServiceProvider);
      final result = await solver.solveWithFallback(
        imagePath: entry.filePath,
        hintRaHours: target.raHours,
        hintDecDegrees: target.decDegrees,
        searchRadiusDegrees: 5.0,
      );

      if (!mounted) return;
      setState(() {
        _isSolving = false;
        _lastSolve = _SolveOutcome.solved(result, target);
      });

      if (result.success) {
        context.showSuccessSnackBar(
          'Frame solved in ${result.solveTimeSecs.toStringAsFixed(1)}s',
        );
      } else {
        context.showErrorSnackBar(
          result.error ?? 'Plate solve failed',
        );
      }
    } on SolverNotAvailableError {
      if (!mounted) return;
      setState(() {
        _isSolving = false;
        _lastSolve = const _SolveOutcome.noSolver();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSolving = false;
        _lastSolve = _SolveOutcome.failed(e.toString());
      });
      context.showErrorSnackBar('Solve failed: $e');
    }
  }
}

/// One numbered step: a leading index badge, a title, a trailing [StatusPill],
/// and the step's body content.
class _StepRow extends StatelessWidget {
  final int number;
  final String title;
  final StatusPillStatus status;
  final String statusValue;
  final NightshadeColors colors;
  final Widget child;

  const _StepRow({
    required this.number,
    required this.title,
    required this.status,
    required this.statusValue,
    required this.colors,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = status == StatusPillStatus.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _StepBadge(number: number, isDone: isDone, colors: colors),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: Text(
                title,
                style: NightshadeTypography.h6.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            // Value-only pill: the step title to the left already names what
            // this readiness state refers to, so an empty label keeps the pill
            // reading 'Resolved' / 'Loaded' / 'Ready' rather than repeating the
            // step name. (StatusPill renders value-only when label is empty.)
            StatusPill(
              icon: isDone ? LucideIcons.check : LucideIcons.circle,
              label: '',
              value: statusValue,
              status: status,
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        // Small left inset to set the step body off from the rail edge. Kept
        // modest (spaceMd) rather than space2xl: a larger inset left the reused
        // FramingPreviewFovSlider too little room and overflowed the narrow
        // (250-500px) framing sidebar the rail is mounted in.
        Padding(
          padding: const EdgeInsets.only(
            left: NightshadeTokens.spaceMd,
          ),
          child: child,
        ),
      ],
    );
  }
}

/// The circular step index, which becomes a filled check once the step is done.
class _StepBadge extends StatelessWidget {
  final int number;
  final bool isDone;
  final NightshadeColors colors;

  const _StepBadge({
    required this.number,
    required this.isDone,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final fill = isDone ? colors.success : colors.surfaceElevated;
    final fg = isDone ? colors.onPrimary : colors.textSecondary;
    final borderColor = isDone ? colors.success : colors.border;
    return Container(
      width: NightshadeTokens.iconLg,
      height: NightshadeTokens.iconLg,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor),
      ),
      child: isDone
          ? Icon(LucideIcons.check, size: NightshadeTokens.iconXs, color: fg)
          : Text(
              '$number',
              style: NightshadeTypography.labelSm.copyWith(color: fg),
            ),
    );
  }
}

/// Step 1 body: resolved target name + monospace RA/Dec readout.
class _TargetSummary extends StatelessWidget {
  final NightshadeColors colors;
  final FramingTarget target;

  const _TargetSummary({required this.colors, required this.target});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          target.name,
          style: NightshadeTypography.bodyMedium.copyWith(
            color: colors.textPrimary,
          ),
        ),
        if (target.catalogId != null && target.catalogId != target.name)
          Padding(
            padding: const EdgeInsets.only(top: NightshadeTokens.spaceXs),
            child: Text(
              target.catalogId!,
              style: NightshadeTypography.caption.copyWith(
                color: colors.textMuted,
              ),
            ),
          ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        _CoordLine(label: 'RA', value: target.raFormatted, colors: colors),
        const SizedBox(height: NightshadeTokens.spaceXs),
        _CoordLine(label: 'Dec', value: target.decFormatted, colors: colors),
      ],
    );
  }
}

/// A label + monospace value coordinate line (tabular figures so updating
/// numbers don't shift the layout).
class _CoordLine extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _CoordLine({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: NightshadeTypography.caption.copyWith(
              color: colors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: NightshadeTypography.monoSm.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Step 3 body: the solve button, its preconditions, and the inline outcome
/// (banner / alert).
class _SolveStep extends StatelessWidget {
  final NightshadeColors colors;
  final bool isSolving;
  final bool canSolve;
  final bool hasTarget;
  final bool hasSurveyImage;
  final bool hasSolver;
  final _SolveOutcome? outcome;
  final VoidCallback onSolve;

  const _SolveStep({
    required this.colors,
    required this.isSolving,
    required this.canSolve,
    required this.hasTarget,
    required this.hasSurveyImage,
    required this.hasSolver,
    required this.outcome,
    required this.onSolve,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: NightshadeButton(
            label: 'Solve current frame',
            icon: LucideIcons.crosshair,
            variant: ButtonVariant.outline,
            isLoading: isSolving,
            onPressed: canSolve ? onSolve : null,
          ),
        ),
        if (!hasTarget || !hasSurveyImage)
          Padding(
            padding: const EdgeInsets.only(top: NightshadeTokens.spaceXs),
            child: Text(
              !hasTarget
                  ? 'Resolve a target to solve.'
                  : 'Wait for the survey frame to finish loading.',
              style: NightshadeTypography.caption.copyWith(
                color: colors.textMuted,
              ),
            ),
          ),
        if (outcome != null) ...[
          const SizedBox(height: NightshadeTokens.spaceMd),
          _SolveOutcomeView(colors: colors, outcome: outcome!),
        ] else if (hasTarget && hasSurveyImage && !hasSolver) ...[
          const SizedBox(height: NightshadeTokens.spaceMd),
          const PlateSolverRequiredBanner(
            contextMessage:
                'The framing wizard solves the displayed survey cutout to '
                'measure how far its center is from your target. Set up '
                'ASTAP (or Astrometry.net) to enable this step.',
          ),
        ],
      ],
    );
  }
}

/// Renders the result of a solve attempt: the required-solver banner, a plain
/// error alert, or a success alert with the RA/Dec delta versus the target.
class _SolveOutcomeView extends StatelessWidget {
  final NightshadeColors colors;
  final _SolveOutcome outcome;

  const _SolveOutcomeView({required this.colors, required this.outcome});

  @override
  Widget build(BuildContext context) {
    if (outcome.solverMissing) {
      return const PlateSolverRequiredBanner(
        contextMessage:
            'No plate solver is reachable. Set up ASTAP (or Astrometry.net) '
            'to solve the displayed survey frame.',
      );
    }

    if (outcome.error != null) {
      return NightshadeAlert(
        severity: NightshadeAlertSeverity.error,
        title: 'Solve failed',
        message: outcome.error!,
      );
    }

    final result = outcome.result!;
    if (!result.success) {
      return NightshadeAlert(
        severity: NightshadeAlertSeverity.warning,
        title: 'Plate solve did not converge',
        message: result.error ??
            'The solver ran but could not find a solution for this frame.',
      );
    }

    final against = outcome.against;
    final deltaMessage = against != null
        ? _formatDelta(result: result, target: against)
        : 'Solved center: ${_formatRaHours(result.ra)} '
            '${_formatDecDegrees(result.dec)}';

    return NightshadeAlert(
      severity: NightshadeAlertSeverity.success,
      title: 'Frame solved',
      message: deltaMessage,
    );
  }

  /// Human-readable offset between the solved center and the target, plus the
  /// solved coordinates. RA delta is cos(dec)-scaled to a true angular offset.
  String _formatDelta({
    required PlateSolveResult result,
    required FramingTarget target,
  }) {
    final decRad = target.decDegrees * (math.pi / 180.0);
    final cosDec = math.cos(decRad).abs();

    // RA difference in hours, wrapped to the shortest arc, converted to degrees
    // then scaled by cos(dec) to an on-sky angle.
    var raDiffHours = result.ra - target.raHours;
    while (raDiffHours > 12.0) {
      raDiffHours -= 24.0;
    }
    while (raDiffHours < -12.0) {
      raDiffHours += 24.0;
    }
    final raDeltaDeg = (raDiffHours * 15.0) * cosDec;
    final decDeltaDeg = result.dec - target.decDegrees;

    final raDeltaArcmin = raDeltaDeg.abs() * 60.0;
    final decDeltaArcmin = decDeltaDeg.abs() * 60.0;

    final raDir = raDeltaDeg >= 0 ? 'E' : 'W';
    final decDir = decDeltaDeg >= 0 ? 'N' : 'S';

    return 'Solved center ${_formatRaHours(result.ra)} '
        '${_formatDecDegrees(result.dec)}\n'
        'Offset from target: '
        '${raDeltaArcmin.toStringAsFixed(1)}\' $raDir, '
        '${decDeltaArcmin.toStringAsFixed(1)}\' $decDir';
  }

  String _formatRaHours(double raHours) {
    final h = raHours.floor();
    final m = ((raHours - h) * 60).floor();
    final s = (((raHours - h) * 60 - m) * 60).round();
    return '${h.toString().padLeft(2, '0')}h '
        '${m.toString().padLeft(2, '0')}m '
        '${s.toString().padLeft(2, '0')}s';
  }

  String _formatDecDegrees(double decDeg) {
    final sign = decDeg >= 0 ? '+' : '-';
    final abs = decDeg.abs();
    final d = abs.floor();
    final m = ((abs - d) * 60).floor();
    final s = (((abs - d) * 60 - m) * 60).round();
    return '$sign${d.toString().padLeft(2, '0')}° '
        '${m.toString().padLeft(2, '0')}\' '
        '${s.toString().padLeft(2, '0')}"';
  }
}
