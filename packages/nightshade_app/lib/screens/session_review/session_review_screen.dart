import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'auto_integration_service.dart';
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

  /// True while an operator-requested Darkroom pass is running. The pass spans
  /// minutes of native rendering, so the control latches rather than letting a
  /// second press queue a second job over the same masters.
  bool _darkroomRunning = false;

  /// True once the operator has asked the running pass to stop. The stop is
  /// cooperative — the engine's flag is polled between tiles and the pipeline
  /// checks it between masters — so the control says "Stopping…" and stays
  /// disabled rather than pretending the pass is already over.
  bool _stopRequested = false;

  SessionReviewController get _controller =>
      ref.read(sessionReviewControllerProvider(widget.scope).notifier);

  /// Run the Darkroom pass for this session on request.
  ///
  /// Only offered for a session scope: the pass reads a session's frames to
  /// find the masters they were folded into, and a target scope spans nights
  /// that were each processed on their own.
  Future<void> _processTonightNow(int sessionId) async {
    if (_darkroomRunning) return;
    setState(() {
      _darkroomRunning = true;
      _stopRequested = false;
    });
    final ManualDarkroomRun run;
    try {
      run = await ref
          .read(autoIntegrationServiceProvider)
          .runDarkroomNow(sessionId);
    } finally {
      if (mounted) {
        setState(() {
          _darkroomRunning = false;
          _stopRequested = false;
        });
      }
    }
    if (!mounted) return;
    // The masters are re-read because a finished pass has written recipes the
    // library panel's Darkroom buttons now open.
    await _controller.refresh();
    if (!mounted) return;
    NightshadeToastHelper.show(
      context: context,
      message: run.autoDraftEnabled
          ? run.message
          : '${run.message} Automatic drafts are switched off, so this one was '
              'made because you asked.',
      severity: run.succeeded
          ? NightshadeAlertSeverity.success
          : NightshadeAlertSeverity.warning,
    );
  }

  /// Ask the running Darkroom pass to stop.
  ///
  /// The pass is minutes of native rendering per master, and without this the
  /// only way out of one started by mistake — over the wrong night, with the
  /// wrong masters, or while the operator wants the machine for something else
  /// — is to wait it out or kill the app. The stop is cooperative: the engine's
  /// cancellation flag is raised for this job's render id and the autopilot's
  /// own flag stops the pipeline before the next master, so a render already
  /// inside Rust ends at its next poll rather than instantly. The toast says
  /// exactly that; the pass's own outcome toast reports how it actually ended.
  Future<void> _stopTonightsPass(int sessionId) async {
    if (_stopRequested) return;
    setState(() => _stopRequested = true);
    final int? jobId;
    try {
      jobId = await ref
          .read(autoIntegrationServiceProvider)
          .cancelDarkroomPassForSession(
            sessionId,
            reason: 'Stopped from Session Review',
          );
    } catch (error) {
      if (!mounted) return;
      setState(() => _stopRequested = false);
      NightshadeToastHelper.show(
        context: context,
        message: 'The Darkroom pass could not be stopped: $error',
        severity: NightshadeAlertSeverity.error,
      );
      return;
    }
    if (!mounted) return;
    if (jobId == null) {
      // Nothing was asked to stop, so the control goes back to offering it.
      setState(() => _stopRequested = false);
      NightshadeToastHelper.show(
        context: context,
        message: 'There is no Darkroom pass to stop for this session — it has '
            'either finished already or has not reached its job yet.',
        severity: NightshadeAlertSeverity.info,
      );
      return;
    }
    NightshadeToastHelper.show(
      context: context,
      message: 'Stopping the Darkroom pass. A master already being rendered '
          'finishes that render first; nothing after it is started.',
      severity: NightshadeAlertSeverity.warning,
    );
  }

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
    final sessionId = widget.scope.sessionId;

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
              trailing: Wrap(
                spacing: NightshadeTokens.spaceSm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // The manual half of the dawn autopilot. Reaching it here is
                  // deliberate: this is the screen an operator is already on
                  // when they decide tonight is worth drafting now rather than
                  // at dawn. The whole screen is host-only (the remote arm
                  // above returns before this), so no further backend gate is
                  // needed.
                  Tooltip(
                    message: sessionId != null
                        ? 'Draft tonight\'s masters in the Darkroom now, '
                            'without waiting for dawn'
                        : 'This review spans a target rather than one night. '
                            'Open a single session to process it.',
                    child: NightshadeButton(
                      key: const ValueKey('session_review_process_now'),
                      label: 'Process now',
                      icon: NightshadeIcons.sliders,
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      isLoading: _darkroomRunning,
                      onPressed: (sessionId == null || _darkroomRunning)
                          ? null
                          : () => _processTonightNow(sessionId),
                    ),
                  ),
                  // The way out of a pass that is already under way. Present
                  // only while one is: a Stop that is always on the header
                  // would be a control with nothing to stop.
                  if (_darkroomRunning && sessionId != null)
                    Tooltip(
                      message: 'Stop the Darkroom pass. The master being '
                          'rendered finishes; nothing after it starts.',
                      child: NightshadeButton(
                        key: const ValueKey('session_review_stop_pass'),
                        label: _stopRequested ? 'Stopping…' : 'Stop',
                        icon: NightshadeIcons.stop,
                        variant: ButtonVariant.destructive,
                        size: ButtonSize.small,
                        onPressed: _stopRequested
                            ? null
                            : () => _stopTonightsPass(sessionId),
                      ),
                    ),
                  NightshadeButton(
                    label: 'Refresh',
                    icon: NightshadeIcons.refresh,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed: () => _controller.refresh(),
                  ),
                ],
              ),
            ),
            // Narrative ↔ workbench toggle: one tap, two renderings of one model.
            SessionReviewViewToggleBar(
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
class SessionReviewViewToggleBar extends StatelessWidget {
  final SessionReviewViewMode mode;
  final ValueChanged<SessionReviewViewMode> onChanged;

  const SessionReviewViewToggleBar({
    super.key,
    required this.mode,
    required this.onChanged,
  });

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
    return Semantics(
      button: true,
      enabled: true,
      selected: selected,
      child: Material(
        color: selected ? colors.primary : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusButton),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusButton),
          // The app theme's hoverColor is an OPAQUE surface tone, so the
          // pointer left resting on a chip after the click that selected it
          // repainted the primary fill grey — the selected tab looked disabled
          // and the unselected one looked live. A tint of the chip's own
          // foreground sits on the fill instead of replacing it.
          hoverColor: fg.withValues(alpha: 0.08),
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
