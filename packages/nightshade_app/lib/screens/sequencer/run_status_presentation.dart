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
bool isRunCancellationNotice(String message) {
  final m = message.toLowerCase();
  return m.contains('cancelled') ||
      m.contains('canceled') ||
      m.contains('stopped by user') ||
      m.contains('stopped by the user') ||
      m.contains('stopped by operator');
}

/// The messages worth showing as errors for a run that ended with [status].
///
/// Identity in, identity out for every non-stop outcome.
List<String> runErrorMessagesFor(String status, List<String> messages) {
  if (!runWasStoppedByOperator(status)) return messages;
  return messages.where((m) => !isRunCancellationNotice(m)).toList();
}
