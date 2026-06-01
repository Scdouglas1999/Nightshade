part of '../stacking_panel.dart';

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

/// The Stack-and-Share launcher button (component C10).
///
/// A single primary [NightshadeButton] that opens [StackAndShareDialog] for the
/// current session. The button is disabled — with an explanatory
/// [NightshadeTooltip] — when there is no active/selected session, or when live
/// stacking is running (the stacking engine is a singleton, so we surface that
/// exclusivity here rather than letting the run fail at click). While the
/// selection preview is being computed the button shows its loading state.
class _StackAndShareEntry extends StatelessWidget {
  /// Current imaging session id, or null when none is active/selected.
  final int? sessionId;

  /// Whether live stacking is currently running (singleton-exclusivity gate).
  final bool liveStackingActive;

  /// Whether the selection preview is currently being computed.
  final bool isBusy;

  /// Invoked when the button is pressed; null when the action is unavailable.
  final VoidCallback? onPressed;

  const _StackAndShareEntry({
    required this.sessionId,
    required this.liveStackingActive,
    required this.isBusy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Live stacking takes precedence in the disabled reason: even with a valid
    // session, the singleton engine is busy.
    final disabledReason = liveStackingActive
        ? 'Stop live stacking to run Stack & Share'
        : sessionId == null
            ? 'Select a session to stack'
            : null;

    // Only enable when there is a session, live stacking is idle, and we are not
    // mid-preview. The reason text is mutually exclusive with an active handler.
    final enabled = disabledReason == null && !isBusy && onPressed != null;

    final button = SizedBox(
      width: double.infinity,
      child: NightshadeButton(
        label: 'Stack & Share',
        icon: LucideIcons.sparkles,
        isLoading: isBusy,
        onPressed: enabled ? onPressed : null,
      ),
    );

    if (disabledReason == null) {
      return button;
    }

    return NightshadeTooltip(
      message: disabledReason,
      child: button,
    );
  }
}
