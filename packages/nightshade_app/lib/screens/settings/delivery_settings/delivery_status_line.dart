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
  ///
  /// The journal outranks the configuration: the newest recorded verdict —
  /// no `ssh` binary, a full disk, a conflicting file — leads the sentence,
  /// and any structural gap (a missing key, an empty selection, a folder that
  /// is not there) rides behind it. A configuration blocker stated first would
  /// hide the real mechanism and point the operator at a fix that cannot
  /// change the outcome.
  static DeliveryStatusLine of(DeliveryDestinationView view) {
    final destination = view.destination;
    if (!destination.enabled) return _offSentence(view);
    final note = _configurationNote(view);
    if (view.journal.isNotEmpty) {
      final verdict = _journalSentence(view);
      if (note == null) return verdict;
      return DeliveryStatusLine(
        verdict.kind,
        '${_ended(verdict.sentence)} $note',
      );
    }
    if (note != null) {
      return DeliveryStatusLine(DeliveryStatusKind.incomplete, note);
    }
    return const DeliveryStatusLine(
      DeliveryStatusKind.neverRun,
      'No delivery has run yet.',
    );
  }

  /// What a switched-off destination says, including the files standing at it.
  ///
  /// Off is not empty. The rows a destination holds when the operator turns it
  /// off stay `retrying` — the sweep names them suspended and skips them, and
  /// a peer's manifest endpoint answers that peer `unknown_delivery_peer`, so
  /// nothing on either side is going to move them. A row that said only "Off —
  /// nothing is sent here." left twelve published files invisible on the one
  /// page that owns the switch that would release them.
  static DeliveryStatusLine _offSentence(DeliveryDestinationView view) {
    final suspended = view.owed.length;
    final failed = view.unresolvedFailures.length;
    final sentences = <String>[
      if (suspended > 0)
        '${_files(suspended)} ${suspended == 1 ? 'is' : 'are'} suspended here '
            'until it is switched back on.',
      if (failed > 0) '${_files(failed)} never arrived.',
    ];
    return DeliveryStatusLine(
      DeliveryStatusKind.off,
      ['Off — nothing is sent here.', ...sentences].join(' '),
    );
  }

  /// [sentence] with a full stop, unless it already ends in punctuation. The
  /// journal verdict ends in raw `last_error` text, which may end with a
  /// bracket, a path or nothing at all, and running that straight into the
  /// configuration note would read as one run-on claim.
  static String _ended(String sentence) {
    final trimmed = sentence.trimRight();
    if (trimmed.isEmpty) return trimmed;
    return '.!?'.contains(trimmed[trimmed.length - 1]) ? trimmed : '$trimmed.';
  }

  /// What is structurally in this destination's way, or null when nothing is.
  ///
  /// An empty content selection is one of these rather than a state of its
  /// own: it stops delivery exactly the way a missing path does, and it is
  /// reported the same way wherever delivery is summarized.
  static String? _configurationNote(DeliveryDestinationView view) {
    if (view.destination.content.isEmpty) {
      return 'Nothing selected — this destination receives no files.';
    }
    return _configurationBlocker(view);
  }

  /// The reason this destination cannot deliver as configured, or null when
  /// nothing structural is in the way.
  static String? _configurationBlocker(DeliveryDestinationView view) {
    final destination = view.destination;
    final config = decodeDestinationConfig(destination.configJson);
    switch (destination.kind) {
      case ArtifactDestinationKind.watchedFolder:
        final path = configString(config, 'path').trim();
        if (path.isEmpty) {
          return 'No folder set — nothing can be written.';
        }
        switch (view.folder) {
          case WatchedFolderState.absent:
            // The same refusal the editor's write probe gives, kept alive on
            // the row after the dialog closed. An operator who saved past that
            // refusal used to get a row that said nothing at all about the
            // folder, and an unmounted share looks exactly like this.
            return 'There is no directory at $path — delivery never creates '
                'one, so nothing can be written there.';
          case WatchedFolderState.unreadable:
            final error = view.folderError;
            final detail = error != null && error.trim().isNotEmpty
                ? error.trim()
                : 'the filesystem did not answer';
            return 'The folder at $path could not be checked ($detail), so '
                'whether anything can be written there is unknown.';
          case WatchedFolderState.present:
          case WatchedFolderState.notProbed:
            return null;
        }
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

  /// The sentence this destination's journal states.
  ///
  /// **A red truth outranks a newer green.** What did not arrive is counted
  /// across EVERY job at this destination, and only what DID arrive is read
  /// from the newest run. A destination holding four of last night's drafts
  /// that failed terminally, and four of tonight's that landed, used to read
  /// "Delivered 17:55, 4 files" in green with no mention of the four the rig
  /// will never look at again — the exact sentence this page exists to get
  /// right, in the other direction.
  ///
  /// **The counts are the destination's whole backlog.** "4 files owed" beside
  /// a sweep logging "8 retrying" for the same destination is the page
  /// disagreeing with the process, and an operator whose share was full for
  /// two nights was told half of it.
  static DeliveryStatusLine _journalSentence(DeliveryDestinationView view) {
    final isPeer = view.destination.kind == ArtifactDestinationKind.peer;

    final failed = view.unresolvedFailures;
    final retrying = <DeliveryJournalEntry>[];
    final awaitingPull = <DeliveryJournalEntry>[];
    for (final entry in view.owed) {
      // A peer row is `retrying` from the moment it is published until the
      // desktop acknowledges the pull, because publication moves no bytes.
      // With no error recorded, that row is waiting on the desktop — not on a
      // retry — and saying "will retry" would blame the wrong side.
      if (isPeer && entry.lastError == null) {
        awaitingPull.add(entry);
      } else {
        retrying.add(entry);
      }
    }
    final lastRun = view.lastRun;
    final delivered = lastRun
        .where((entry) => entry.state == DeliveryAttemptState.delivered)
        .toList(growable: false);

    if (failed.isNotEmpty) {
      final reason = _newestError(failed);
      // `lastRun` is never empty here: this is only reached for a destination
      // whose journal holds rows, and every row belongs to some job.
      final newestJobId = lastRun.first.jobId;
      if (failed.every((entry) => entry.jobId == newestJobId)) {
        return DeliveryStatusLine(
          DeliveryStatusKind.failed,
          // The unit belongs to the pair, not to each half: counting both
          // sides separately printed "1 file of 3 files failed".
          '${failed.length} of ${_files(lastRun.length)} failed — $reason',
        );
      }
      // Failures the newest run does not account for. Naming them as a share
      // of that run's file count would understate them — they are files from
      // nights this destination has already been told were done with.
      return DeliveryStatusLine(
        DeliveryStatusKind.failed,
        '${_files(failed.length)} never arrived — $reason',
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
