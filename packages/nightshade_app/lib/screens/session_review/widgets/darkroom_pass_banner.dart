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
    final stage = note == null || note.isEmpty ? '' : ' ${_noteSentence(note)}';

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

  /// The `darkroom_jobs.note` column as one grammatical sentence.
  ///
  /// Two writers share that column and they write two different shapes. A pass
  /// that is on its way through leaves the STAGE it is in — `Drafting Master ·
  /// B`, `Delivering the night` — a fragment that only reads as English inside
  /// a frame. The open-time recovery that ends a job at the retry limit leaves
  /// a finished sentence instead: `Stopped at the retry limit; this job is not
  /// re-queued.` Wrapping the second in the first's frame produced `It was
  /// Stopped at the retry limit; this job is not re-queued. when it stopped.`
  /// — a full stop mid-clause and a dangling tail, on the banner an operator
  /// reads when a night has gone wrong.
  ///
  /// Terminal punctuation is what separates them, and it separates them because
  /// of what each writer is doing: a stage name is a noun phrase and never ends
  /// a sentence, while a recovery writes a statement and ends it. So a note
  /// that closes itself is passed through as the statement it is, and one that
  /// does not is framed as the stage it names.
  static String _noteSentence(String note) =>
      '.!?'.contains(note[note.length - 1])
          ? note
          : 'It was $note when it stopped.';
}
