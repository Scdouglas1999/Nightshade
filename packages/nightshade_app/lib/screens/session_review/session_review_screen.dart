import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
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
  String? _lastShownShortfall;

  SessionReviewController get _controller =>
      ref.read(sessionReviewControllerProvider(widget.scope).notifier);

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final backend = ref.watch(backendProvider);
    if (backend is NetworkBackend) {
      // Session Review owns persisted masters, night reports, culling state,
      // and previews whose paths are local to the imaging host. Instantiating
      // its DAO-backed controller on a remote client would write a second,
      // client-local history after running compute on the host. Keep the
      // boundary explicit until the whole aggregate (including artifact
      // streaming) has a host-authoritative API.
      return Scaffold(
        backgroundColor: colors.background,
        body: const SafeArea(
          bottom: false,
          child: Column(
            children: [
              ScreenHeader(
                title: 'Session Review',
                subtitle: 'Host-only processing',
                icon: NightshadeIcons.image,
              ),
              Expanded(
                child: EmptyState(
                  icon: NightshadeIcons.device,
                  title: 'Open Session Review on the imaging host',
                  body: 'Full-resolution subs, integrated masters, and their '
                      'previews are stored on the imaging computer. Open '
                      'Nightshade there to review, cull, integrate, or finish '
                      'this session. Remote Session Review is unavailable in '
                      'this release.',
                ),
              ),
            ],
          ),
        ),
      );
    }
    final state = ref.watch(sessionReviewControllerProvider(widget.scope));

    // Surface controller errors as a toast, once each *occurrence*. Resetting
    // on the cleared state matters: actions clear the error before they run, so
    // retrying an action that keeps failing the same way toasts every time
    // instead of going quiet after the first attempt and leaving the control
    // looking dead.
    if (state.error == null) {
      _lastShownError = null;
    } else if (state.error != _lastShownError) {
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

    // An integration that dropped subs is not an error — it returns a master —
    // but it must never be silent. Same once-each dedupe as the error toast.
    final shortfall =
        SessionReviewController.integrationShortfall(state.lastOutcome);
    if (shortfall != null && shortfall != _lastShownShortfall) {
      _lastShownShortfall = shortfall;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        NightshadeToastHelper.show(
          context: context,
          message: shortfall,
          severity: NightshadeAlertSeverity.warning,
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
