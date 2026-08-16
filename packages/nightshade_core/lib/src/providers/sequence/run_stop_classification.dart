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
/// A substring test on "cancelled" swallows real faults whose text happens to
/// contain the word — "Temperature compensation cancelled"
/// (`native/.../temperature_compensation.rs`), "Cancelled: Target"
/// (`executor/preflight.rs`), "focuser move was canceled by the driver",
/// "slew canceled by the mount (limit switch)" — leaving the operator with NO
/// error report at all. Those messages are the pinned counter-inputs of
/// `test/providers/sequence/run_stop_classification_test.dart`.
///
/// The notice is a fixed string the executor writes verbatim, so recognising it
/// exactly (trimmed, case-insensitive, both spellings) is both sufficient and
/// the only safe rule: anything else is a real fault and must survive.
library;

import 'dart:convert';

/// The verbatim notice the native executor emits for a cancelled run.
const String kSequenceCancelledNotice = 'Sequence cancelled';

/// The copy every surface uses instead of an error when [isSequenceCancelledNotice]
/// recognises the notice.
const String kSequenceStoppedByRequestMessage = 'Stopped by request';

/// Feed message for a stop the AUTOPILOT commanded (scheduler re-plan,
/// no-eligible-target tick). Distinct from the operator's message: an
/// unattended stop must never claim a human asked for it.
const String kSequenceStoppedByAutopilotMessage = 'Stopped by autopilot';

/// Log tag stamped by every producer that reclassifies a stop. Each call site
/// logs `[$kStopClassificationLogTag] <site>` when it reclassifies, so the run
/// log says WHICH producer acted.
const String kStopClassificationLogTag = 'stop-classification';

/// True when [message] is the run-cancelled NOTICE rather than a fault.
///
/// Exact match by design — see the library doc comment.
bool isSequenceCancelledNotice(String message) {
  final normalized = message.trim().toLowerCase();
  return normalized == 'sequence cancelled' ||
      normalized == 'sequence canceled';
}

// Who ended the run.
//
// Every cancellation path publishes the same cancel-notice pair, so the notice
// says only THAT a run ended. The one thing on the wire that says WHO is the
// decision row `SequencerExecutor::stop_with_origin` writes
// (`native/nightshade_native/sequencer/src/executor/lifecycle.rs`):
//
//   manual_intervention / "Operator: stop …"                    -> a human
//   system_event        / "Autopilot: stop"                     -> the scheduler
//   system_event        / "System: stop" + details.origin        -> a subsystem
//                          (`rollback`, `disk-watchdog`, …)
//
// The vocabulary is read HERE, once, so the surfaces that consume it (the Run
// Dashboard's stop row on bridge-typed events, the notification router on
// core-typed events) can never disagree about whose stop it was.

/// Decision-row category for the executor's manual-intervention rows.
const String kManualInterventionDecisionCategory = 'manual_intervention';

/// Decision-row category for the executor's system-event rows.
const String kSystemEventDecisionCategory = 'system_event';

/// Summary PREFIX of the operator's stop decision. A prefix, not an equality:
/// both `Operator: stop` and `Operator: stop requested` occur on the wire.
const String kOperatorStopSummaryPrefix = 'Operator: stop';

/// Summary of the autopilot's stop decision.
const String kAutopilotStopSummary = 'Autopilot: stop';

/// Summary of a stop no one commanded but the system itself; the caller is in
/// `details.origin`.
const String kSystemStopSummary = 'System: stop';

/// WHO ended the run, as the executor's decision rows name them.
enum SequenceStopAuthor {
  /// A human pressed Stop (locally or from a paired phone).
  operatorPress,

  /// The scheduler stopped the run on an unattended re-plan.
  autopilot,

  /// A subsystem stopped the run: see [SequenceStopDecision.origin].
  system,
}

/// One stop decision read off the wire.
class SequenceStopDecision {
  final SequenceStopAuthor author;

  /// For [SequenceStopAuthor.system]: the caller the stop API was given
  /// (`rollback`, `disk-watchdog`, …). Null for the other authors.
  final String? origin;

  const SequenceStopDecision(this.author, {this.origin});
}

/// Read a `DecisionLogged` row as stop authorship, or `null` when the row is
/// not one of the executor's stop decisions (the cancel-notice lifecycle
/// decision every cancellation path emits included — it names no author).
SequenceStopDecision? sequenceStopDecision({
  required String category,
  required String summary,
  String? detailsJson,
}) {
  if (category == kManualInterventionDecisionCategory &&
      summary.startsWith(kOperatorStopSummaryPrefix)) {
    return const SequenceStopDecision(SequenceStopAuthor.operatorPress);
  }
  if (category != kSystemEventDecisionCategory) return null;
  if (summary == kAutopilotStopSummary) {
    return const SequenceStopDecision(SequenceStopAuthor.autopilot);
  }
  if (summary == kSystemStopSummary) {
    return SequenceStopDecision(
      SequenceStopAuthor.system,
      origin: _stopOrigin(detailsJson),
    );
  }
  return null;
}

String? _stopOrigin(String? detailsJson) {
  if (detailsJson == null || detailsJson.isEmpty) return null;
  try {
    final decoded = jsonDecode(detailsJson);
    if (decoded is Map<String, dynamic>) {
      final origin = decoded['origin'];
      if (origin is String && origin.isNotEmpty) return origin;
    }
  } on FormatException {
    // A details payload we cannot read names no origin; the stop stays
    // cause-neutral, which is the honest direction.
  }
  return null;
}

/// The clause naming who ended the run — `by request`, `by autopilot`,
/// `by the disk-space watchdog` — or the empty string when nothing on the wire
/// names an author (a safety abort with nobody at the keyboard).
///
/// Every surface composes its own sentence around this one clause:
/// [kSequenceStoppedByRequestMessage] is `'Stopped ${clause}'` for the
/// operator, and the notification body is `'Sequence stopped ${clause} at …'`.
String sequenceStopCauseClause(SequenceStopDecision? decision) {
  switch (decision?.author) {
    case SequenceStopAuthor.operatorPress:
      return 'by request';
    case SequenceStopAuthor.autopilot:
      return 'by autopilot';
    case SequenceStopAuthor.system:
      final origin = decision?.origin;
      return origin == null ? '' : 'by ${sequenceStopOriginLabel(origin)}';
    case null:
      return '';
  }
}

/// The operator-facing name of a system stop's `origin`. Unknown origins are
/// printed verbatim: naming the real caller is more useful than a generic
/// "the system", and it is what the log says too.
String sequenceStopOriginLabel(String origin) {
  switch (origin) {
    case 'rollback':
      return 'the launch rollback';
    case 'disk-watchdog':
      return 'the disk-space watchdog';
    default:
      return origin;
  }
}
