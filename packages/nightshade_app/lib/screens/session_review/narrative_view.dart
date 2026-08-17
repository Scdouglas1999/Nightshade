import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../sequencer/widgets/run_dashboard/frame_detail_dialog.dart';
import 'session_review_controller.dart';
import 'widgets/darkroom_pass_banner.dart';
import 'widgets/growth_curve_panel.dart';
import 'widgets/improvement_curve_panel.dart';
import 'widgets/master_overlay_view.dart';
import 'widgets/night_report_panel.dart';
import 'widgets/session_interruption_banner.dart';

/// The *narrative* rendering of the one [SessionReviewController] state: a
/// top-to-bottom story of the night, read like a morning report.
///
/// Order: hero master (with overlays) → Night-Doctor verdict
/// (headline + score) → "proof it's optimal" integration-improvement curve →
/// the ranked finding cards ("what I fixed/found") → multi-night growth curve →
/// a calibrated / annotated detail row. The verdict and findings are two slots
/// of `NightReportPanel` (`NightReportSection.verdict` then `.findings`) so the
/// findings sit *after* the curve, not bundled with the verdict before it.
///
/// This view computes nothing; it reads the same provider the workbench reads,
/// so the two are two renderings of one model. Panels are composed by their
/// contract constructor signatures and are design-system pure.
class NarrativeView extends ConsumerWidget {
  final SessionReviewScope scope;

  const NarrativeView({super.key, required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final state = ref.watch(sessionReviewControllerProvider(scope));
    final controller =
        ref.read(sessionReviewControllerProvider(scope).notifier);

    final report = state.nightReport;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── A pass a process exit cut off. ───────────────────────────────
          // First, because it outranks every ending below it: the row that
          // banner reads has been re-queued since, so it no longer says the
          // machine died mid-run.
          SessionInterruptionBanner(notice: state.interruptedPassNotice),

          // ── A Darkroom pass that failed or was stopped. ──────────────────
          // Above the hero: it is the reason the drafts and the delivery this
          // page would otherwise be read as reporting are not there.
          DarkroomPassBanner(job: state.darkroomJob),

          // ── Hero: the finished master with toggleable overlays. ──────────
          _HeroSection(state: state, controller: controller),
          const SizedBox(height: NightshadeTokens.spaceLg),

          // ── Verdict: big headline + 0..100 score ring. ───────────────────
          // Verdict header only here; the ranked finding cards render after the
          // improvement curve. A null report degrades to the
          // "analysis pending" placeholder in this slot.
          NightReportPanel(
            report: report,
            section: NightReportSection.verdict,
            onEvidenceTap: (id) =>
                FrameDetailDialog.showForFrame(context, imageId: id),
          ),
          _GradedSubsDisagreement(subs: state.lights, report: report),
          const SizedBox(height: NightshadeTokens.spaceLg),

          // ── Proof it's optimal: integration-improvement curve. ───────────
          const SectionHeader(title: 'How deep is deep enough?'),
          const SizedBox(height: NightshadeTokens.spaceSm),
          ImprovementCurvePanel(curve: state.improvementCurve),
          const SizedBox(height: NightshadeTokens.spaceLg),

          // ── What I fixed / found: the ranked finding cards. ──────────────
          if (report != null && report.findings.isNotEmpty) ...[
            const SectionHeader(title: 'What I fixed and found'),
            const SizedBox(height: NightshadeTokens.spaceSm),
            NightReportPanel(
              report: report,
              section: NightReportSection.findings,
              onEvidenceTap: (id) =>
                  FrameDetailDialog.showForFrame(context, imageId: id),
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
          ],

          // ── Multi-night growth curve. ────────────────────────────────────
          const SectionHeader(title: 'This project over time'),
          const SizedBox(height: NightshadeTokens.spaceSm),
          GrowthCurvePanel(
            points: state.growthPoints,
            best: state.bestNight,
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),

          // ── Calibrated / annotated detail row. ──────────────────────────
          const SectionHeader(title: 'Calibrated & annotated'),
          const SizedBox(height: NightshadeTokens.spaceSm),
          _CalibratedAnnotatedRow(
            state: state,
            onColorCalibration: () => _runFinishing(context,
                controller.runColorCalibration, 'Colour calibration applied'),
            onBackgroundExtraction: () => _runFinishing(context,
                controller.runBackgroundExtraction, 'Gradient extracted'),
          ),
          // Bottom breathing room so the last card clears the progress bar.
          SizedBox(
            height: NightshadeTokens.spaceXl,
            child: ColoredBox(color: colors.background),
          ),
        ],
      ),
    );
  }
}

/// Run a narrative finishing action and, on success (a non-null output path),
/// surface a success toast — the `state.error` toast (fired by the screen) still
/// covers the failure path unchanged.
Future<void> _runFinishing(
  BuildContext context,
  Future<String?> Function() action,
  String successMessage,
) async {
  final path = await action();
  if (path != null && context.mounted) {
    NightshadeToastHelper.show(
      context: context,
      message: successMessage,
      severity: NightshadeAlertSeverity.success,
    );
  }
}

/// Wraps [child] in a [Tooltip] only when there is something to say — an empty
/// tooltip would pop a blank bubble on hover.
class _MaybeTooltip extends StatelessWidget {
  final String? message;
  final Widget child;

  const _MaybeTooltip({required this.message, required this.child});

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null || message.isEmpty) return child;
    return Tooltip(message: message, child: child);
  }
}

/// Why "Integrate now" / "Re-integrate" cannot run for [state], or null when it
/// can. Mirrors exactly the conditions that disable the button so the empty
/// state and its tooltip can never disagree with whether the action fires.
String? _integrateBlockedReason(SessionReviewState state) {
  if (state.integrating) return 'An integration is already running.';
  if (state.busy) {
    return 'Another processing step is running — it has to finish first.';
  }
  if (state.lights.isEmpty) {
    return 'This session captured no light frames, so there is nothing to '
        'integrate.';
  }
  if (state.acceptedCount == 0) {
    return 'Every one of this session’s ${state.lights.length} light frames is '
        'rejected. Accept at least one sub to integrate.';
  }
  return null;
}

/// The narrative hero: the finished master rendered through [MasterOverlayView]
/// (which extends the on-disk [MasterPreviewView] load/stretch path). The
/// narrative shows annotations on by default and leaves the dense rejection /
/// coverage toggles to the workbench. When no master exists yet it offers the
/// primary Integrate action so the read-first narrative is never a dead end.
class _HeroSection extends StatelessWidget {
  final SessionReviewState state;
  final SessionReviewController controller;

  const _HeroSection({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final outcome = state.lastOutcome;
    // Fall back to the persisted master's preview so a pre-existing master (DB
    // row, no in-session integrate) renders instead of an empty hero.
    final previewPath =
        outcome?.result.previewPath ?? state.reviewedMaster?.previewPngPath;

    if (previewPath == null) {
      // Why the action cannot run, or null when it can. A dimmed button with no
      // explanation is not an affordance at 2am — the workbench already knows
      // this reason, so the narrative states it too.
      final blockedReason = _integrateBlockedReason(state);
      return NightshadeCard(
        variant: CardVariant.subtle,
        padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EmptyState(
              icon: NightshadeIcons.image,
              title: 'No finished master yet',
              body: blockedReason ??
                  'Run an integration to see tonight’s master here, '
                      'annotated with the objects in frame.',
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            Align(
              alignment: Alignment.center,
              child: _MaybeTooltip(
                message: blockedReason,
                child: NightshadeButton(
                  label: state.lastOutcome == null
                      ? 'Integrate now'
                      : 'Re-integrate',
                  icon: NightshadeIcons.play,
                  isLoading: state.integrating,
                  onPressed: blockedReason != null
                      ? null
                      : () => controller.reIntegrate(state.settings),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return NightshadeCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 460,
        child: MasterOverlayView(
          previewPngPath: previewPath,
          annotations: state.annotationLayer,
          rejectionMapPngPath: outcome?.result.rejectionMapPreviewPath ??
              state.reviewedMaster?.rejectionMapPreviewPath,
          coverageMapPngPath:
              outcome?.result.coverageMapPreviewPath ?? state.coverageMapPath,
          showAnnotations: true,
          finishingLayers: finishingLayersForMaster(state.reviewedMaster),
        ),
      ),
    );
  }
}

/// A two-up row of one-tap finishing actions (color calibration, background
/// extraction) shown beneath the narrative. Each is a [NightshadeCard] with the
/// action's status, wired to the controller; the heavy lifting lives in the
/// service the controller calls.
class _CalibratedAnnotatedRow extends StatelessWidget {
  final SessionReviewState state;
  final Future<void> Function() onColorCalibration;
  final Future<void> Function() onBackgroundExtraction;

  const _CalibratedAnnotatedRow({
    required this.state,
    required this.onColorCalibration,
    required this.onBackgroundExtraction,
  });

  @override
  Widget build(BuildContext context) {
    final busy = state.busy;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < NightshadeTokens.breakpointTablet;
        final cards = [
          _ActionCard(
            icon: NightshadeIcons.star,
            title: 'Color calibration',
            body: 'Neutralise the background and balance the stars against a '
                'catalog white reference.',
            actionLabel: 'Calibrate color',
            busy: busy,
            onPressed: onColorCalibration,
          ),
          _ActionCard(
            icon: NightshadeIcons.layers,
            title: 'Background extraction',
            body: 'Model and subtract the light-pollution / moon gradient from '
                'the linear master.',
            actionLabel: 'Extract gradient',
            busy: busy,
            onPressed: onBackgroundExtraction,
          ),
        ];
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cards[0],
              const SizedBox(height: NightshadeTokens.spaceMd),
              cards[1],
            ],
          );
        }
        // IntrinsicHeight gives the Row a bounded cross-axis extent so the two
        // equal-width action cards can stretch to a shared height; without it,
        // CrossAxisAlignment.stretch inside the unbounded SingleChildScrollView
        // forces an infinite-height constraint on the cards.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(child: cards[1]),
            ],
          ),
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final bool busy;
  final Future<void> Function() onPressed;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: NightshadeTokens.iconSm, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Text(
                  title,
                  style: NightshadeTypography.h5
                      .copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            body,
            style: NightshadeTypography.bodySm
                .copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Align(
            alignment: Alignment.centerLeft,
            child: NightshadeButton(
              label: actionLabel,
              icon: NightshadeIcons.play,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              isLoading: busy,
              onPressed: busy ? null : () => onPressed(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reconciles the Night Doctor's verdict with the frame grader that the
/// Workbench tab of this same screen renders.
///
/// The two panels read different inputs: the night report is a session-level
/// degradation score built from session-level findings, the badges come from
/// [FrameQualityAssessmentService] per frame. So a four-frame run can score
/// **100 / 100 — "A clean night, no problems detected" — 0 findings** here
/// while the Workbench badges every one of its four subs red POOR at HFR 5.7
/// against a cull line of 3.5. Advisory badges never changing acceptance is
/// documented policy; a night on which *every* frame is graded POOR being
/// reported as having nothing wrong with it is not.
///
/// So the same grader the Workbench uses is read here, and when it disagrees
/// with a clean verdict the disagreement is stated instead of being left for the
/// operator to find on the other tab.
class _GradedSubsDisagreement extends StatelessWidget {
  final List<DbCapturedImage> subs;
  final NightReport? report;

  const _GradedSubsDisagreement({required this.subs, required this.report});

  @override
  Widget build(BuildContext context) {
    final message = gradedSubsDisagreementMessage(subs: subs, report: report);
    if (message == null) return const SizedBox.shrink();

    final colors = NightshadeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: NightshadeTokens.spaceMd),
      child: Container(
        padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.10),
          borderRadius: NightshadeTokens.borderRadiusLg,
          border: Border.all(color: colors.warning.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(NightshadeIcons.warning,
                size: NightshadeTokens.iconSm, color: colors.warning),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: Text(
                message,
                style: NightshadeTypography.bodySm
                    .copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sentence stating a clean Night-Doctor verdict's disagreement with the
/// per-frame grader, or null when the two do not disagree.
///
/// Pure, and public, so the reconciliation can be pinned without driving the
/// whole review screen: it states a claim, and a claim is exactly what a unit
/// test can hold.
String? gradedSubsDisagreementMessage({
  required List<DbCapturedImage> subs,
  required NightReport? report,
}) {
  // Only a *clean graded* verdict can be contradicted. An ungraded night
  // already says it could not judge, and a night that lists findings is not
  // claiming there is nothing wrong.
  if (report == null || !report.graded || report.findings.isNotEmpty)
    return null;
  if (subs.isEmpty) return null;

  const assessor = FrameQualityAssessmentService();
  final assessments = assessor.assessBatch(subs);
  final poor =
      assessments.values.where((a) => a.level == FrameQualityLevel.poor).length;
  if (poor == 0) return null;

  final hfrs = subs
      .map((s) => s.hfr)
      .whereType<double>()
      .where((v) => v.isFinite && v > 0)
      .toList()
    ..sort();
  final median = hfrs.isEmpty
      ? null
      : hfrs.length.isOdd
          ? hfrs[hfrs.length ~/ 2]
          : (hfrs[hfrs.length ~/ 2 - 1] + hfrs[hfrs.length ~/ 2]) / 2;
  final hfrClause =
      median == null ? '' : ' (median HFR ${median.toStringAsFixed(1)})';
  final total = subs.length;

  return poor == total
      ? 'The verdict above found no session-level problem, but the frame '
          'grader marks all $total subs POOR$hfrClause. Open Workbench before '
          'treating this night as clean.'
      : 'The verdict above found no session-level problem, but the frame '
          'grader marks $poor of $total subs POOR$hfrClause. Open Workbench '
          'to see which.';
}
