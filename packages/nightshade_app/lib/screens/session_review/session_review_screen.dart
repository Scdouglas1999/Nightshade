import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'narrative_view.dart';
import 'session_review_controller.dart';
import 'workbench_view.dart';

/// Session Review / Morning Report.
///
/// The cohesive "review the night" surface, rendered as two views of one
/// [SessionReviewController] model: a top-to-bottom *narrative* report (the
/// default) and a dense *workbench* console, switched by a single header
/// toggle. A live [NightshadeProgressBar] (phase + fraction) appears whenever a
/// long-running integration is in flight.
///
/// Reached from the run/session/analytics context via the `/session-review`
/// route with a `?session=<id>` or `?target=<id>` query.
class SessionReviewScreen extends ConsumerStatefulWidget {
  final SessionReviewScope scope;

  const SessionReviewScreen({super.key, required this.scope});

  @override
  ConsumerState<SessionReviewScreen> createState() =>
      _SessionReviewScreenState();
}

class _SessionReviewScreenState extends ConsumerState<SessionReviewScreen> {
  String? _lastShownError;

  SessionReviewController get _controller =>
      ref.read(sessionReviewControllerProvider(widget.scope).notifier);

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final state = ref.watch(sessionReviewControllerProvider(widget.scope));

    // Surface controller errors as a toast, once each.
    if (state.error != null && state.error != _lastShownError) {
      _lastShownError = state.error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        NightshadeToastHelper.show(
          context: context,
          message: state.error!,
          severity: NightshadeAlertSeverity.error,
        );
      });
    }

    final isNarrative = state.viewMode == SessionReviewViewMode.narrative;
    final progress = state.progress;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ScreenHeader(
              title: state.title,
              subtitle: state.loading
                  ? 'Loading…'
                  : '${state.acceptedCount} accepted · ${state.rejectedCount} rejected',
              icon: NightshadeIcons.image,
              trailing: NightshadeButton(
                label: 'Refresh',
                icon: NightshadeIcons.refresh,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () => _controller.refresh(),
              ),
            ),
            // Narrative ↔ workbench toggle: one tap, two renderings of one model.
            _ViewToggleBar(
              mode: state.viewMode,
              onChanged: (m) => _controller.setViewMode(m),
            ),
            // Live integration progress (phase + fraction). Only present while a
            // long-running run is reporting progress.
            if (progress != null)
              _ProgressStrip(
                  phase: progress.phase, fraction: progress.fraction),
            Expanded(
              child: state.loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : isNarrative
                      ? NarrativeView(scope: widget.scope)
                      : WorkbenchView(scope: widget.scope),
            ),
          ],
        ),
      ),
    );
  }
}

/// The narrative ↔ workbench segmented toggle that sits under the header. One
/// tap switches which rendering of the single controller state is shown.
class _ViewToggleBar extends StatelessWidget {
  final SessionReviewViewMode mode;
  final ValueChanged<SessionReviewViewMode> onChanged;

  const _ViewToggleBar({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg,
        vertical: NightshadeTokens.spaceSm,
      ),
      child: Row(
        children: [
          _ToggleChip(
            label: 'Narrative',
            icon: NightshadeIcons.image,
            selected: mode == SessionReviewViewMode.narrative,
            onTap: () => onChanged(SessionReviewViewMode.narrative),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          _ToggleChip(
            label: 'Workbench',
            icon: NightshadeIcons.sliders,
            selected: mode == SessionReviewViewMode.workbench,
            onTap: () => onChanged(SessionReviewViewMode.workbench),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final fg = selected ? colors.onPrimary : colors.textSecondary;
    return Material(
      color: selected ? colors.primary : colors.surfaceAlt,
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusButton),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusButton),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NightshadeTokens.spaceMd,
            vertical: NightshadeTokens.spaceSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: NightshadeTokens.iconSm, color: fg),
              const SizedBox(width: NightshadeTokens.spaceXs),
              Text(
                label,
                style: NightshadeTypography.button.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The live integration-progress strip: a phase label + a determinate
/// [NightshadeProgressBar], bound to `state.progress` (the
/// `seam.integrationProgress()` → controller binding). Shown only while a run
/// is reporting progress; absent otherwise.
class _ProgressStrip extends StatelessWidget {
  final String phase;
  final double fraction;

  const _ProgressStrip({required this.phase, required this.fraction});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg,
        vertical: NightshadeTokens.spaceMd,
      ),
      child: NightshadeProgressBar(
        value: fraction.clamp(0.0, 1.0),
        style: NightshadeProgressStyle.standard,
        state: NightshadeProgressState.normal,
        label: _phaseLabel(phase),
        showPercentage: true,
      ),
    );
  }

  /// Map a raw phase token (`registering`, `integrating`, …) to a friendly,
  /// capitalised label with an ellipsis.
  static String _phaseLabel(String phase) {
    if (phase.isEmpty) return 'Working…';
    final pretty = phase[0].toUpperCase() + phase.substring(1);
    return '$pretty…';
  }
}
