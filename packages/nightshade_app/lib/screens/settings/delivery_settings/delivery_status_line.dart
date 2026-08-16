part of '../delivery_settings.dart';

/// What a destination's status line is saying about it.
///
/// The kind drives the dot colour, so a state that is not a delivery cannot
/// borrow a delivered destination's green.
enum DeliveryStatusKind {
  /// Delivery to this destination is switched off.
  off,

  /// On, but the transport is not configured well enough to run.
  incomplete,

  /// Configured and on, and nothing has ever been attempted here.
  neverRun,

  /// The last run put every selected file on the destination.
  delivered,

  /// The files are published and the paired desktop has not pulled them yet.
  awaitingPull,

  /// The last run did not finish and another attempt is due.
  retrying,

  /// Every attempt is spent and files did not arrive.
  failed,
}

/// The one sentence a destination row states about its delivery.
///
/// Every branch is derived from a fact: a row of `delivery_journal`, an empty
/// journal, an empty content selection, an absent path, or an absent keyring
/// entry. There is deliberately no "ready" or "configured" state — a channel
/// that has never moved a byte must not read as one that has.
class DeliveryStatusLine {
  final DeliveryStatusKind kind;

  /// The sentence, already written for a person.
  final String sentence;

  const DeliveryStatusLine(this.kind, this.sentence);

  /// Read [view] and state what is true of it.
  static DeliveryStatusLine of(DeliveryDestinationView view) {
    final destination = view.destination;
    if (!destination.enabled) {
      return const DeliveryStatusLine(
        DeliveryStatusKind.off,
        'Off — nothing is sent here.',
      );
    }
    if (destination.content.isEmpty) {
      return const DeliveryStatusLine(
        DeliveryStatusKind.incomplete,
        'Nothing selected — this destination receives no files.',
      );
    }
    final blocker = _configurationBlocker(view);
    if (blocker != null) {
      return DeliveryStatusLine(DeliveryStatusKind.incomplete, blocker);
    }
    if (view.lastRun.isEmpty) {
      return const DeliveryStatusLine(
        DeliveryStatusKind.neverRun,
        'No delivery has run yet.',
      );
    }
    return _lastRunSentence(view);
  }

  /// The reason this destination cannot deliver as configured, or null when
  /// nothing structural is in the way.
  static String? _configurationBlocker(DeliveryDestinationView view) {
    final destination = view.destination;
    final config = decodeDestinationConfig(destination.configJson);
    switch (destination.kind) {
      case ArtifactDestinationKind.watchedFolder:
        if (configString(config, 'path').trim().isEmpty) {
          return 'No folder set — nothing can be written.';
        }
        return null;
      case ArtifactDestinationKind.sftp:
        if (configString(config, 'host').trim().isEmpty) {
          return 'No host set — nothing can be sent.';
        }
        if (configString(config, 'remoteDir').trim().isEmpty) {
          return 'No remote directory set — nothing can be sent.';
        }
        switch (view.secret) {
          case StoredSecretState.absent:
            return 'No key in the keyring — SSH cannot authenticate, so '
                'nothing is sent.';
          case StoredSecretState.unreadable:
            final error = view.secretError;
            final detail = error != null && error.trim().isNotEmpty
                ? error.trim()
                : 'the keyring did not answer';
            return 'The keyring could not be read ($detail), so whether this '
                'destination can authenticate is unknown.';
          case StoredSecretState.present:
            return null;
        }
      case ArtifactDestinationKind.peer:
        if (configString(config, 'peerId').trim().isEmpty) {
          return 'No peer id — no paired desktop can claim these files.';
        }
        return null;
    }
  }

  /// The sentence for the most recent run's journal rows.
  static DeliveryStatusLine _lastRunSentence(DeliveryDestinationView view) {
    final entries = view.lastRun;
    final isPeer = view.destination.kind == ArtifactDestinationKind.peer;

    final delivered = <DeliveryJournalEntry>[];
    final failed = <DeliveryJournalEntry>[];
    final retrying = <DeliveryJournalEntry>[];
    final awaitingPull = <DeliveryJournalEntry>[];
    for (final entry in entries) {
      switch (entry.state) {
        case DeliveryAttemptState.delivered:
          delivered.add(entry);
        case DeliveryAttemptState.failed:
          failed.add(entry);
        case DeliveryAttemptState.retrying:
          // A peer row is `retrying` from the moment it is published until the
          // desktop acknowledges the pull, because publication moves no bytes.
          // With no error recorded, that row is waiting on the desktop — not
          // on a retry — and saying "will retry" would blame the wrong side.
          if (isPeer && entry.lastError == null) {
            awaitingPull.add(entry);
          } else {
            retrying.add(entry);
          }
      }
    }

    if (failed.isNotEmpty) {
      final reason = _newestError(failed);
      return DeliveryStatusLine(
        DeliveryStatusKind.failed,
        '${_files(failed.length)} of ${_files(entries.length)} failed — '
        '$reason',
      );
    }
    if (retrying.isNotEmpty) {
      final reason = _newestError(retrying);
      return DeliveryStatusLine(
        DeliveryStatusKind.retrying,
        '$reason — will retry (${_files(retrying.length)} owed).',
      );
    }
    if (awaitingPull.isNotEmpty) {
      final config = decodeDestinationConfig(view.destination.configJson);
      final peer = configString(config, 'peerId').trim();
      final who = peer.isEmpty ? 'the paired desktop' : peer;
      return DeliveryStatusLine(
        DeliveryStatusKind.awaitingPull,
        'Published ${_files(awaitingPull.length)}, '
        '${_bytes(_totalBytes(awaitingPull))} — waiting for $who to pull.',
      );
    }
    if (delivered.isEmpty) {
      return const DeliveryStatusLine(
        DeliveryStatusKind.neverRun,
        'No delivery has run yet.',
      );
    }
    final at = _newestDeliveredAt(delivered);
    final when = at == null
        ? 'at an unrecorded time'
        : DateFormat('HH:mm').format(at.toLocal());
    final recovered = delivered.any((entry) => entry.lastError != null);
    return DeliveryStatusLine(
      DeliveryStatusKind.delivered,
      'Delivered $when, ${_files(delivered.length)}, '
      '${_bytes(_totalBytes(delivered))}'
      '${recovered ? ' (after a retry).' : '.'}',
    );
  }

  /// The most recently updated entry's failure text.
  static String _newestError(List<DeliveryJournalEntry> entries) {
    DeliveryJournalEntry? newest;
    for (final entry in entries) {
      if (entry.lastError == null) continue;
      if (newest == null || entry.updatedAt.isAfter(newest.updatedAt)) {
        newest = entry;
      }
    }
    final message = newest?.lastError;
    if (message == null || message.trim().isEmpty) {
      return 'The journal recorded no reason';
    }
    return message.trim();
  }

  static DateTime? _newestDeliveredAt(List<DeliveryJournalEntry> entries) {
    DateTime? newest;
    for (final entry in entries) {
      final at = entry.deliveredAt;
      if (at == null) continue;
      if (newest == null || at.isAfter(newest)) newest = at;
    }
    return newest;
  }

  static int _totalBytes(List<DeliveryJournalEntry> entries) {
    var total = 0;
    for (final entry in entries) {
      total += entry.bytes;
    }
    return total;
  }

  static String _files(int count) => count == 1 ? '1 file' : '$count files';

  /// Byte counts as the morning report writes them.
  static String _bytes(int bytes) {
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final rendered =
        unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '$rendered ${units[unit]}';
  }
}

/// The colour a status line is drawn in. Kept beside the kinds so a new kind
/// cannot silently inherit the delivered colour.
Color deliveryStatusColor(DeliveryStatusKind kind, NightshadeColors colors) {
  switch (kind) {
    case DeliveryStatusKind.delivered:
      return colors.success;
    case DeliveryStatusKind.awaitingPull:
      return colors.info;
    case DeliveryStatusKind.retrying:
      return colors.warning;
    case DeliveryStatusKind.failed:
      return colors.error;
    case DeliveryStatusKind.incomplete:
      return colors.warning;
    case DeliveryStatusKind.off:
    case DeliveryStatusKind.neverRun:
      return colors.textMuted;
  }
}
