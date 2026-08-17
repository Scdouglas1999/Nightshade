import 'package:flutter/material.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// States a Darkroom pass that finished BADLY.
///
/// The Darkroom pass is what turns a night's masters into drafts, a night
/// report and a delivery. When it runs at dawn nobody is standing at the
/// machine, so its ending lives only on its `darkroom_jobs` row — the toast
/// that reports a pass belongs to the button that started one. A pass that
/// failed at 05:40 therefore left this screen showing the night's verdict, the
/// masters and the score with nothing saying the drafting and the delivery had
/// not happened, and the operator's first sign of it was a destination that
/// never received the night.
///
/// Renders nothing for a pass that ran to the end or is still running: `done`
/// is already visible as the drafts and the report themselves, and a running
/// pass has the screen's own progress strip. Only an ending the operator has
/// to act on gets a banner.
class DarkroomPassBanner extends StatelessWidget {
  const DarkroomPassBanner({super.key, required this.job});

  /// The newest pass for the session under review, or null when none has been
  /// queued for it.
  final DarkroomJob? job;

  @override
  Widget build(BuildContext context) {
    final pass = job;
    if (pass == null) return const SizedBox.shrink();
    final String lead;
    final NightshadeAlertSeverity severity;
    switch (pass.state) {
      case DarkroomJobState.failed:
        lead = 'The Darkroom pass for this night failed.';
        severity = NightshadeAlertSeverity.error;
      case DarkroomJobState.cancelled:
        lead = 'The Darkroom pass for this night was stopped.';
        severity = NightshadeAlertSeverity.warning;
      case DarkroomJobState.queued:
      case DarkroomJobState.running:
      case DarkroomJobState.done:
        return const SizedBox.shrink();
    }

    // The row's own sentence, which names the stage that stopped. When the row
    // carries none the banner says so rather than inventing a cause: "the pass
    // failed" with a made-up reason is worse than "the pass failed and the row
    // does not say why".
    // Ended with a full stop unless it already carries punctuation: the row's
    // sentence is written by whatever stage stopped and often ends on a path
    // or a bracket, which would otherwise run straight into the next sentence
    // as one claim.
    final recorded = pass.errorText?.trim();
    final why = recorded == null || recorded.isEmpty
        ? 'The job row records no reason.'
        : ('.!?'.contains(recorded[recorded.length - 1])
            ? recorded
            : '$recorded.');
    final note = pass.note?.trim();
    final stage =
        note != null && note.isNotEmpty ? ' It was $note when it stopped.' : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceLg),
      child: NightshadeInlineBanner(
        key: const ValueKey('session_review_darkroom_pass_banner'),
        message: '$lead $why$stage '
            'The subs and any masters already integrated are untouched — '
            'press Process now to run the pass again.',
        severity: severity,
      ),
    );
  }
}
