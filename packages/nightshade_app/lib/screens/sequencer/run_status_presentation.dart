/// The one place a durable `sequence_runs.status` becomes words a person reads.
///
/// The stored values are state-machine tokens, and the UI used to print them
/// verbatim: a run the operator stopped while it was *running* was titled
/// "New Sequence - paused-stopped" in the Session Report and offered under
/// that string as a History filter chip. It had not been paused — the token
/// means "stopped with the checkpoint preserved", which is a fact about
/// resumability, not about what the operator did.
///
/// Every surface that shows a run outcome goes through here, so the vocabulary
/// stays the product's rather than the schema's.
library;

import 'package:nightshade_core/nightshade_core.dart'
    show isSequenceCancelledNotice;

/// Human label for a durable run status.
///
/// Unknown tokens (a status added to the executor before this map) degrade to
/// a readable form rather than vanishing: hyphens become spaces and the first
/// letter is capitalised.
String runStatusLabel(String status) {
  switch (status) {
    case 'completed':
      return 'Completed';
    case 'failed':
      return 'Failed';
    case 'aborted':
      return 'Aborted';
    case 'stopped':
      return 'Stopped';
    case 'paused-stopped':
      // Stopped by the operator, checkpoint kept, so the run can be resumed.
      return 'Stopped (resumable)';
    case 'interrupted':
      return 'Interrupted';
    case 'running':
      return 'Running';
    case 'paused':
      return 'Paused';
    case 'finalizing':
      return 'Finishing up';
  }
  final words = status.replaceAll('-', ' ').replaceAll('_', ' ').trim();
  if (words.isEmpty) return 'Unknown';
  return words[0].toUpperCase() + words.substring(1);
}

/// One sentence explaining what a run status MEANS, in one shared vocabulary.
///
/// CON-51: History offered seven outcome chips, five of which mean "the run did
/// not finish" — Failed, Aborted, Stopped, Stopped (resumable), Interrupted —
/// in five unrelated words, with nothing on screen saying how they differ. The
/// distinctions are real (they call for different operator responses), so the
/// answer is to define them, once, in parallel phrasing: every not-finished
/// status opens with the same clause, and the difference follows the dash.
String runStatusMeaning(String status) {
  switch (status) {
    case 'completed':
      return 'Finished every planned frame.';
    case 'running':
      return 'Under way right now.';
    case 'paused':
      return 'Under way, held at the operator\'s request.';
    case 'finalizing':
      return 'Under way, writing its final results.';
    case 'failed':
      return 'Did not finish — the sequencer hit an error it could not '
          'recover from.';
    case 'aborted':
      return 'Did not finish — a safety rule or a trigger ended it.';
    case 'stopped':
      return 'Did not finish — you stopped it, and no checkpoint was kept.';
    case 'paused-stopped':
      return 'Did not finish — you stopped it, and the checkpoint was kept so '
          'it can be resumed.';
    case 'interrupted':
      return 'Did not finish — the app or the machine went down mid-run; this '
          'was reconciled at the next start.';
  }
  return 'Run status recorded as "$status".';
}

/// True when [status] means the operator ended the run themselves.
///
/// A deliberate Stop is the one terminal state that is not a fault, and the
/// surfaces that describe the run have to agree about that.
bool runWasStoppedByOperator(String status) =>
    status == 'stopped' || status == 'paused-stopped';

/// True when [message] is the run-cancelled notice rather than a fault.
///
/// The executor records "Sequence cancelled" in the run's error list because
/// that is how the native run ends on a Stop. Rendered verbatim under a red
/// "Errors" heading — in a report whose own title reads "Stopped (resumable)" —
/// it tells the operator their own button press was a critical failure
/// (Wave D, WD-SEQ-N1). Recognised here so the outcome-aware surfaces can drop
/// it; it is never dropped for a run that failed or aborted on its own.
///
/// The match is EXACT, and that is the whole point. Wave E refuted the first
/// version of this — a substring test on "cancelled" — with four messages the
/// stack really emits: "Temperature compensation cancelled",
/// "Cancelled: Target", "focuser move was canceled by the driver" and
/// "slew canceled by the mount (limit switch)". Press Stop after a night that
/// had any of those and the Session Report showed no Errors section at all: one
/// cry-wolf traded for a silent swallow. The notice itself is a fixed string,
/// so nothing is lost by recognising only the fixed strings.
///
/// [isSequenceCancelledNotice] (nightshade_core) is the shared spelling test;
/// this adds the operator-phrased variants the durable run rows can also carry.
bool isRunCancellationNotice(String message) {
  if (isSequenceCancelledNotice(message)) return true;
  final m = message.trim().toLowerCase();
  return m == 'stopped by user' ||
      m == 'stopped by the user' ||
      m == 'stopped by operator' ||
      m == 'stopped by the operator' ||
      m == 'stopped by request';
}

/// The messages worth showing as errors for a run that ended with [status].
///
/// Identity in, identity out for every non-stop outcome.
List<String> runErrorMessagesFor(String status, List<String> messages) {
  if (!runWasStoppedByOperator(status)) return messages;
  return messages.where((m) => !isRunCancellationNotice(m)).toList();
}
