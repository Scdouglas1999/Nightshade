import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'session_review_controller.dart';
import 'widgets/growth_curve_panel.dart';
import 'widgets/improvement_curve_panel.dart';
import 'widgets/master_overlay_view.dart';
import 'widgets/night_report_panel.dart';

/// The *narrative* rendering of the one [SessionReviewController] state: a
/// top-to-bottom story of the night, read like a morning report.
///
/// Order (design §1): hero master (with overlays) → Night-Doctor verdict
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
          // ── Hero: the finished master with toggleable overlays. ──────────
          _HeroSection(state: state),
          const SizedBox(height: NightshadeTokens.spaceLg),

          // ── Verdict: big headline + 0..100 score ring. ───────────────────
          // Verdict header only here; the ranked finding cards render after the
          // improvement curve (design §1 order). A null report degrades to the
          // "analysis pending" placeholder in this slot.
          NightReportPanel(
            report: report,
            section: NightReportSection.verdict,
          ),
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
            onColorCalibration: controller.runColorCalibration,
            onBackgroundExtraction: controller.runBackgroundExtraction,
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

/// The narrative hero: the finished master rendered through [MasterOverlayView]
/// (which extends the on-disk [MasterPreviewView] load/stretch path). The
/// narrative shows annotations on by default and leaves the dense rejection /
/// coverage toggles to the workbench.
class _HeroSection extends StatelessWidget {
  final SessionReviewState state;

  const _HeroSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final outcome = state.lastOutcome;
    final previewPath = outcome?.result.previewPath;

    if (previewPath == null) {
      return const NightshadeCard(
        variant: CardVariant.subtle,
        padding: EdgeInsets.all(NightshadeTokens.spaceLg),
        child: EmptyState(
          icon: NightshadeIcons.image,
          title: 'No finished master yet',
          body: 'Run an integration to see tonight’s master here, '
              'annotated with the objects in frame.',
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
          rejectionMapPngPath: outcome?.result.rejectionMapPath,
          showAnnotations: true,
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
        final stacked = constraints.maxWidth < NightshadeTokens.breakpointTablet;
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
