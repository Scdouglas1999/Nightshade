/// The ONE place that decides whether a sequencer `Error` event is really the
/// operator's Stop.
///
/// The native executor ends a cancelled run by emitting
/// `ExecutorEvent::Error { message: "Sequence cancelled" }`
/// (`native/nightshade_native/sequencer/src/executor/start.rs`, the
/// `NodeStatus::Cancelled` arm) *before* the `Stopped` state change. Every Dart
/// consumer that keys off the payload type therefore saw a run the operator had
/// deliberately ended as a fault, and each one said so in its own words:
///
///   * the notification classifier routed it to `sequenceFailed`
///     ("Sequence failed / Sequence aborted at …"),
///   * the run-dashboard bridge escalated it as a critical event
///     ("Critical · Sequencer", the red Dashboard banner, the RECENT EVENTS row),
///   * the executor's own event handler painted the target rollup
///     "Error: Sequence cancelled" and pushed the run into `recovering`.
///
/// Five surfaces, five producers, one wire event. They agree now because they
/// all ask this function.
///
/// ## Why the match is EXACT
///
/// The first attempt at this used a substring test on "cancelled". A Wave E
/// refuter showed what that costs: a run that had a REAL fault whose text
/// happens to contain the word — "Temperature compensation cancelled"
/// (`native/.../temperature_compensation.rs`), "Cancelled: Target"
/// (`executor/preflight.rs`), "focuser move was canceled by the driver",
/// "slew canceled by the mount (limit switch)" — had that fault silently
/// swallowed, so the operator got NO error report at all. Those messages are
/// the pinned counter-inputs of
/// `test/providers/sequence/run_stop_classification_test.dart`.
///
/// The notice is a fixed string the executor writes verbatim, so recognising it
/// exactly (trimmed, case-insensitive, both spellings) is both sufficient and
/// the only safe rule: anything else is a real fault and must survive.
library;

/// The verbatim notice the native executor emits for a cancelled run.
const String kSequenceCancelledNotice = 'Sequence cancelled';

/// The copy every surface uses instead of an error when [isSequenceCancelledNotice]
/// recognises the notice.
const String kSequenceStoppedByRequestMessage = 'Stopped by request';

/// Log tag stamped by every producer that reclassifies a stop, so a live log
/// says WHICH implementation acted.
///
/// The stop pipeline has been fixed twice before at a producer that was not the
/// one on screen. Each call site logs `[$kStopClassificationLogTag] <site>` when
/// it reclassifies, so "did my fix run?" is answerable from the run log instead
/// of from reading code.
const String kStopClassificationLogTag = 'stop-classification';

/// True when [message] is the run-cancelled NOTICE rather than a fault.
///
/// Exact match by design — see the library doc comment.
bool isSequenceCancelledNotice(String message) {
  final normalized = message.trim().toLowerCase();
  return normalized == 'sequence cancelled' ||
      normalized == 'sequence canceled';
}
