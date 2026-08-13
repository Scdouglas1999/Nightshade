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
