/// Why one file failed to reach one destination.
///
/// Delivery never throws into the dawn pipeline: the master row commits first
/// and a destination that is unreachable at 06:00 is a fact about the network,
/// not about the night's data. Every failure is therefore caught at the
/// [DeliveryService] boundary, turned into one of these, written to
/// `delivery_journal.last_error`, and surfaced in the morning report.
///
/// The kind is what callers match on. A message alone cannot answer "will
/// another attempt help?" — [DeliveryFailureKind.retryable] does, and it is
/// what decides between `retrying` and `failed` in the journal.
library;

/// The mechanism that stopped a delivery.
enum DeliveryFailureKind {
  /// The source artifact is gone from the rig — a deleted master, a renamed
  /// output directory. No later attempt finds it.
  sourceMissing,

  /// The destination root does not exist right now: an unmounted NAS, a
  /// removed drive, a remote directory that was deleted. A later attempt may
  /// find it mounted again.
  destinationUnreachable,

  /// The destination filesystem has less free space than the artifact needs.
  /// Retried, because space is freed by other things finishing.
  insufficientSpace,

  /// The bytes that landed do not hash to the source's checksum. The partial
  /// is removed and the file is retried, because a truncated transfer is the
  /// usual cause.
  checksumMismatch,

  /// A file already sits at the final name with DIFFERENT content. Delivery
  /// copies and never overwrites, so this is terminal until the operator
  /// resolves it — another attempt would make exactly the same refusal.
  destinationConflict,

  /// The OS refused the read or the write. Terminal: permissions do not
  /// change between two attempts a few minutes apart, and retrying hides the
  /// misconfiguration behind a retry counter.
  permissionDenied,

  /// The transport needs key material that `SecretsStore` does not hold, or
  /// the destination row names no `secret_ref` at all.
  credentialMissing,

  /// The host key the server presented differs from the one pinned on the
  /// destination row. Terminal, and loud: this is what a man-in-the-middle
  /// looks like.
  hostKeyMismatch,

  /// The external tool this transport drives is absent from the machine
  /// (no `sftp`/`ssh` binary), or the remote side offers no digest command to
  /// verify with. Terminal until the operator installs it.
  transportToolMissing,

  /// The transport can express the request but this build cannot perform it
  /// with the credentials given — SFTP password authentication, which
  /// OpenSSH refuses non-interactively. Terminal, and names the substitute.
  authMethodUnavailable,

  /// The destination's `config_json` does not describe a place to write:
  /// no path, no host, no peer id.
  configurationInvalid,

  /// The transport failed in a way that another attempt may survive — a
  /// dropped connection, a timeout, a non-zero exit with no clearer cause.
  transportFailure,

  /// The job was cancelled while this file was in flight.
  cancelled;

  /// Whether another attempt can plausibly succeed.
  ///
  /// A terminal kind is written to the journal as `failed` on its FIRST
  /// attempt: burning the retry budget on a refusal that is identical every
  /// time turns one honest error into an hour of noise.
  bool get retryable {
    switch (this) {
      case DeliveryFailureKind.destinationUnreachable:
      case DeliveryFailureKind.insufficientSpace:
      case DeliveryFailureKind.checksumMismatch:
      case DeliveryFailureKind.transportFailure:
        return true;
      case DeliveryFailureKind.sourceMissing:
      case DeliveryFailureKind.destinationConflict:
      case DeliveryFailureKind.permissionDenied:
      case DeliveryFailureKind.credentialMissing:
      case DeliveryFailureKind.hostKeyMismatch:
      case DeliveryFailureKind.transportToolMissing:
      case DeliveryFailureKind.authMethodUnavailable:
      case DeliveryFailureKind.configurationInvalid:
      case DeliveryFailureKind.cancelled:
        return false;
    }
  }
}

/// One file's delivery failure, carrying the mechanism and the sentence the
/// morning report prints.
class DeliveryFailure implements Exception {
  /// The mechanism that stopped the delivery.
  final DeliveryFailureKind kind;

  /// Operator-facing sentence naming what happened and where.
  final String message;

  /// The underlying error, when there was one to keep.
  final Object? cause;

  const DeliveryFailure(this.kind, this.message, {this.cause});

  /// Whether another attempt can plausibly succeed.
  bool get retryable => kind.retryable;

  /// The single line written to `delivery_journal.last_error`. The kind is
  /// part of it so a report reading only the journal can still say why.
  String get journalText => '${kind.name}: $message';

  @override
  String toString() => 'DeliveryFailure(${kind.name}): $message';
}
