part of '../delivery_settings.dart';

/// Keyring field holding one SFTP destination's private key.
///
/// Keyed by the destination row id, so two SFTP destinations never share one
/// entry and deleting a row deletes exactly one keyring value. `SftpTransport`
/// reads `delivery_targets.secret_ref` verbatim, so this string is the whole
/// contract between this editor and the transport.
String deliverySecretRef(int destinationId) =>
    'delivery.target.$destinationId.private_key';

/// What the keyring says about one destination's stored key material.
enum StoredSecretState {
  /// The keyring holds no value for this destination.
  absent,

  /// The keyring holds a value. Its bytes are never read into the UI.
  present,

  /// The keyring refused the question — a locked or absent secret service.
  /// Distinct from [absent]: "we could not ask" is not "there is none".
  unreadable,
}

/// The v58 `content_json` classes in the order the UI offers them, with the
/// wording an operator reads.
const Map<ArtifactContent, String> kArtifactContentLabels =
    <ArtifactContent, String>{
  ArtifactContent.linearMasters: 'Linear masters',
  ArtifactContent.draftRender: 'Draft render',
  ArtifactContent.stageExports: 'Stage exports',
  ArtifactContent.nightReport: 'Night report',
};

/// One destination as this settings page needs it: the row, the journal's
/// verdict on its most recent run, and what the keyring says about its key.
class DeliveryDestinationView {
  /// The `delivery_targets` row.
  final ArtifactDestination destination;

  /// Journal rows for the NEWEST JOB that delivered to this destination,
  /// newest update first. Empty when nothing has ever been attempted here.
  final List<DeliveryJournalEntry> lastRun;

  /// What the keyring says about [ArtifactDestination.secretRef].
  final StoredSecretState secret;

  /// Why the keyring could not answer, when [secret] is
  /// [StoredSecretState.unreadable].
  final String? secretError;

  const DeliveryDestinationView({
    required this.destination,
    required this.lastRun,
    required this.secret,
    this.secretError,
  });

  /// The sentence this destination's status line states.
  DeliveryStatusLine get status => DeliveryStatusLine.of(this);
}

/// What the page reads: every destination it can render, and every row it
/// cannot.
///
/// Two lists rather than one throw. A single `delivery_targets` row this build
/// cannot decode used to abort the whole read, so the page rendered its error
/// state — no destination list, no Add buttons, no way to reach the row that
/// caused it — while the destinations either side of it were perfectly
/// readable. The unreadable row belongs on the page as itself.
class DeliveryDestinations {
  /// The destinations, in configuration order.
  final List<DeliveryDestinationView> views;

  /// The rows that would not decode, each naming itself and why.
  final List<UndecodableDeliveryTarget> unreadable;

  const DeliveryDestinations({required this.views, required this.unreadable});
}

/// The write probe's verdict on a watched folder.
class WatchedFolderProbe {
  /// True only when a file was actually created and removed under the path.
  final bool writable;

  /// One sentence naming what was tried and what answered.
  final String message;

  const WatchedFolderProbe({required this.writable, required this.message});
}

/// The reads and writes this settings page performs.
///
/// An interface rather than the DAOs directly so a widget test can drive the
/// page against an in-memory double, and so the keyring — which throws on a
/// host with no secret service — has exactly one place where its failure is
/// turned into a reportable state instead of an exception mid-build.
abstract class DeliverySettingsStore {
  /// Every configured destination in configuration order, each with its last
  /// run and keyring state resolved, alongside the rows that would not decode.
  Future<DeliveryDestinations> listDestinations();

  /// Insert a destination and return its new row id.
  Future<int> createDestination({
    required String name,
    required ArtifactDestinationKind kind,
    required String configJson,
    required Set<ArtifactContent> content,
    required bool enabled,
  });

  /// Update the named fields of one destination and leave the rest alone.
  Future<void> updateDestination(
    int id, {
    String? name,
    String? configJson,
    Set<ArtifactContent>? content,
    bool? enabled,
  });

  /// Delete a destination, including its keyring entry.
  Future<void> deleteDestination(int id);

  /// Put the newest job's spent rows on [destinationId] back in the retry
  /// queue, and answer how many were re-queued.
  ///
  /// A `failed` row is the end of the line: the sweep reads only `retrying`
  /// rows, so nothing on the rig ever looks at that file again. The operator
  /// who mounts the share, frees the space or moves the conflicting file has
  /// no way to say so — which is what this is. Attempts are reset to zero, so
  /// the file gets the whole budget again rather than one attempt at the
  /// maximum backoff.
  ///
  /// Only the newest job's rows: older nights' failures were already reported
  /// and closed, and re-queueing a fortnight of them would spend the night's
  /// bandwidth on files the operator did not ask about.
  Future<int> requeueTerminalRows(int destinationId);

  /// Write [value] into the keyring and point the row's `secret_ref` at it.
  Future<void> storeSecret(int destinationId, String value);

  /// Remove the keyring entry and clear the row's `secret_ref`.
  Future<void> clearSecret(int destinationId);

  /// Prove — by writing and removing a file — that [path] can be delivered to.
  Future<WatchedFolderProbe> probeWatchedFolder(String path);
}

/// Production [DeliverySettingsStore]: the v58 DAOs plus the keyring.
class DaoDeliverySettingsStore implements DeliverySettingsStore {
  final DeliveryTargetsDao _targets;
  final DeliveryJournalDao _journal;
  final SecretsStore _secrets;

  DaoDeliverySettingsStore({
    required DeliveryTargetsDao targets,
    required DeliveryJournalDao journal,
    required SecretsStore secrets,
  })  : _targets = targets,
        _journal = journal,
        _secrets = secrets;

  @override
  Future<DeliveryDestinations> listDestinations() async {
    final read = await _targets.readAll();
    final views = <DeliveryDestinationView>[];
    for (final destination in read.destinations) {
      final id = destination.id;
      final entries = id == null
          ? const <DeliveryJournalEntry>[]
          : await _journal.listForTarget(id);
      final secret = await _secretStateOf(destination);
      views.add(
        DeliveryDestinationView(
          destination: destination,
          lastRun: _newestJobRows(entries),
          secret: secret.state,
          secretError: secret.error,
        ),
      );
    }
    return DeliveryDestinations(views: views, unreadable: read.undecodable);
  }

  /// What the keyring says about one destination's key, and — when it refused
  /// to answer — the keyring's own words for why.
  Future<({StoredSecretState state, String? error})> _secretStateOf(
    ArtifactDestination destination,
  ) async {
    final ref = destination.secretRef;
    if (ref == null || ref.trim().isEmpty) {
      return (state: StoredSecretState.absent, error: null);
    }
    try {
      final held = await _secrets.has(ref);
      return (
        state: held ? StoredSecretState.present : StoredSecretState.absent,
        error: null,
      );
    } catch (error) {
      return (
        state: StoredSecretState.unreadable,
        error: userFacingError(error),
      );
    }
  }

  /// The journal rows belonging to the NEWEST JOB that delivered to this
  /// destination, in `listForTarget`'s newest-updated-first order.
  ///
  /// The newest job, not the newest-touched row. Those are different rows the
  /// moment the overnight sweep re-attempts an older night: the sweep writes
  /// `updated_at` on a row from two nights ago, which lifts that row to the top
  /// of `listForTarget` and made this page report THAT job. An operator whose
  /// latest night failed and whose previous night was finally delivered at
  /// 06:20 therefore read a green "Delivered 06:20" and no sign of the failure
  /// — the one sentence the page exists to get right.
  ///
  /// A job is dated by the newest row it created, because that is when its
  /// delivery started; the higher `darkroom_jobs.id` breaks a tie, since the
  /// column is an autoincrement and the later job always holds the larger one.
  static List<DeliveryJournalEntry> _newestJobRows(
    List<DeliveryJournalEntry> entries,
  ) {
    if (entries.isEmpty) return const <DeliveryJournalEntry>[];
    var newestJobId = entries.first.jobId;
    var newestStartedAt = entries.first.createdAt;
    for (final entry in entries.skip(1)) {
      final startedAt = entry.createdAt;
      final isNewer = startedAt.isAfter(newestStartedAt) ||
          (!startedAt.isBefore(newestStartedAt) && entry.jobId > newestJobId);
      if (isNewer) {
        newestJobId = entry.jobId;
        newestStartedAt = entry.createdAt;
      }
    }
    return entries
        .where((entry) => entry.jobId == newestJobId)
        .toList(growable: false);
  }

  @override
  Future<int> createDestination({
    required String name,
    required ArtifactDestinationKind kind,
    required String configJson,
    required Set<ArtifactContent> content,
    required bool enabled,
  }) {
    return _targets.create(
      name: name,
      kind: kind,
      configJson: configJson,
      content: content,
      enabled: enabled,
    );
  }

  @override
  Future<void> updateDestination(
    int id, {
    String? name,
    String? configJson,
    Set<ArtifactContent>? content,
    bool? enabled,
  }) async {
    await _targets.update(
      id,
      name: name,
      configJson: configJson,
      content: content,
      enabled: enabled,
    );
  }

  @override
  Future<void> deleteDestination(int id) async {
    // The keyring entry goes first. If it cannot be removed the row survives,
    // so the operator still has the destination the orphaned key belongs to
    // rather than a key in the keyring nothing names.
    //
    // The column is read on its own rather than through the decoded
    // destination, because deleting is the one action a row that will not
    // decode still needs — and reading it as a destination is exactly what
    // fails on such a row.
    final ref = await _targets.secretRefOf(id);
    if (ref != null && ref.trim().isNotEmpty) {
      await _secrets.delete(ref);
    }
    await _targets.deleteTarget(id);
  }

  @override
  Future<int> requeueTerminalRows(int destinationId) async {
    final rows = _newestJobRows(await _journal.listForTarget(destinationId));
    var requeued = 0;
    for (final row in rows) {
      if (row.state != DeliveryAttemptState.failed) continue;
      await _journal.requeueForRetry(
        targetId: row.targetId,
        jobId: row.jobId,
        filePath: row.filePath,
      );
      requeued++;
    }
    return requeued;
  }

  @override
  Future<void> storeSecret(int destinationId, String value) async {
    final ref = deliverySecretRef(destinationId);
    // Keyring first: a row whose `secret_ref` points at nothing fails the
    // delivery with `credentialMissing`, which is a worse lie than a row that
    // does not claim to hold a key yet.
    await _secrets.write(ref, value);
    await _targets.update(destinationId, secretRef: ref);
  }

  @override
  Future<void> clearSecret(int destinationId) async {
    // The row's own `secret_ref` is deleted, not the name this page would
    // have chosen: a row written by anything else names its keyring entry its
    // own way, and deleting a guessed key would leave that entry behind while
    // reporting the key removed.
    final destination = await _targets.getById(destinationId);
    final ref = destination?.secretRef;
    if (ref != null && ref.trim().isNotEmpty) {
      await _secrets.delete(ref);
    }
    await _targets.clearSecretRef(destinationId);
  }

  @override
  Future<WatchedFolderProbe> probeWatchedFolder(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return const WatchedFolderProbe(
        writable: false,
        message: 'This destination names no path, so there is nothing to probe',
      );
    }
    final directory = Directory(trimmed);
    if (!await directory.exists()) {
      return WatchedFolderProbe(
        writable: false,
        message:
            'There is no directory at $trimmed. Delivery never creates one: '
            'an unmounted network share looks exactly like this, and creating '
            'it would fill the local drive with masters instead.',
      );
    }
    final probeFile = File(
      p.join(
        trimmed,
        '.nightshade-write-probe-'
        '${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      await probeFile.writeAsString('nightshade delivery write probe\n');
      await probeFile.delete();
      return WatchedFolderProbe(
        writable: true,
        message: 'Wrote and removed a probe file in $trimmed',
      );
    } on FileSystemException catch (error) {
      final osMessage = error.osError;
      final detail = osMessage == null ? error.message : osMessage.message;
      return WatchedFolderProbe(
        writable: false,
        message: 'Could not write into $trimmed: $detail',
      );
    }
  }
}

/// Decode a destination's `config_json` into a map the editor can mutate.
///
/// Unknown keys are preserved by every edit path, which is what keeps
/// `hostKeyFingerprint` and `hostKey` (the two halves of the SSH
/// trust-on-first-use pin) and `minFreeBytes` alive through a name change made
/// in this page.
///
/// Returns an empty map when the column does not hold a JSON object: such a
/// row cannot describe a transport, and the status line reports it as
/// incomplete rather than inventing the missing fields.
Map<String, Object?> decodeDestinationConfig(String configJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(configJson);
  } on FormatException {
    return <String, Object?>{};
  }
  if (decoded is Map) return Map<String, Object?>.from(decoded);
  return <String, Object?>{};
}

/// The string at [key], or an empty string when the config does not carry one.
String configString(Map<String, Object?> config, String key) {
  final value = config[key];
  return value is String ? value : '';
}

/// The integer at [key], or null when the config does not carry one. JSON
/// numbers arrive as `int` from the SQLite text column; a decimal port is not
/// a port, so a `double` is rejected rather than truncated.
int? configInt(Map<String, Object?> config, String key) {
  final value = config[key];
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

/// The store this page reads and writes through.
final deliverySettingsStoreProvider = Provider<DeliverySettingsStore>((ref) {
  return DaoDeliverySettingsStore(
    targets: ref.watch(deliveryTargetsDaoProvider),
    journal: ref.watch(deliveryJournalDaoProvider),
    secrets: ref.watch(secretsStoreProvider),
  );
});

/// Every configured destination with its last run and keyring state, plus the
/// rows that would not decode.
///
/// Invalidated by every mutation on this page, which is what re-reads the
/// journal — the status line is a report, never a prediction.
final deliveryDestinationsProvider =
    FutureProvider.autoDispose<DeliveryDestinations>((ref) {
  return ref.watch(deliverySettingsStoreProvider).listDestinations();
});

/// Runs one delivery retry pass and answers what it did, or null when a pass
/// was already in flight and this one was folded into it.
typedef DeliverySweepRequest = Future<DeliveryRunReport?> Function();

/// Runs the retry sweep the operator's "Retry now" asks for.
///
/// A seam over [deliveryRetrySweeperProvider] so a widget test can drive the
/// action without the real transports reaching for a filesystem or an SSH
/// host. Production reads the same sweeper the overnight timer arms, which is
/// what keeps one pass at a time over one journal.
final deliverySweepRequestProvider = Provider<DeliverySweepRequest>(
  (ref) => ref.watch(deliveryRetrySweeperProvider).sweepOnce,
);

/// Reads the devices currently paired with this install.
typedef PairedDesktopReader = Future<List<PairedDevice>> Function();

Future<List<PairedDevice>> _readPairedDevices() async {
  final database = PairingDatabase();
  try {
    return await database.getActivePairedDevices();
  } finally {
    await database.close();
  }
}

/// Seam over the pairing database so a peer row's pairing state can be driven
/// in a test without opening the on-disk pairing store.
final pairedDesktopReaderProvider = Provider<PairedDesktopReader>(
  (ref) => _readPairedDevices,
);

/// The paired devices a peer destination could be answered by.
///
/// Watched only by the peer rows, so an install with no peer destination never
/// opens the pairing database from this page.
final deliveryPairedDesktopsProvider =
    FutureProvider.autoDispose<List<PairedDevice>>((ref) {
  return ref.watch(pairedDesktopReaderProvider)();
});
