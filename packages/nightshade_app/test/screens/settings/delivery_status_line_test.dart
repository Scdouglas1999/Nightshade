// What one destination row is allowed to say about itself.
//
// The rule pinned here: the JOURNAL outranks the configuration. A destination
// whose last run failed for a reason the configuration cannot name — no `ssh`
// binary on the machine, a conflicting file, a full disk — used to have that
// verdict replaced by whichever structural gap was checked first. That both
// hid the mechanism and named a next step ("store a key") that could not
// change the outcome. The verdict now leads and the structural note rides
// behind it.
//
// The second rule pinned here: what did NOT arrive is counted across every job
// at the destination, and only what did arrive is read from the newest run. A
// destination holding a previous night's terminally-failed files under
// tonight's clean delivery read green, with no mention of them and no control
// to retry them; a destination owed eight files across two nights said four.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/delivery_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  final now = DateTime.utc(2026, 8, 16, 6, 30);

  ArtifactDestination sftp({
    required Set<ArtifactContent> content,
    String? secretRef = 'delivery.9.key',
  }) =>
      ArtifactDestination(
        id: 9,
        name: 'observatory-nas',
        kind: ArtifactDestinationKind.sftp,
        configJson: '{"host":"nas.example.invalid","port":22,"user":"astro",'
            '"remoteDir":"/srv/nightshade"}',
        enabled: true,
        content: content,
        secretRef: secretRef,
        createdAt: now,
        updatedAt: now,
      );

  DeliveryJournalEntry entry({
    required DeliveryAttemptState state,
    String? lastError,
    DateTime? updatedAt,
    int jobId = 1,
    DateTime? createdAt,
    String filePath = '/out/L.fits',
  }) =>
      DeliveryJournalEntry(
        id: 1,
        targetId: 9,
        jobId: jobId,
        filePath: filePath,
        bytes: 1024,
        checksum: null,
        state: state,
        attempts: 1,
        lastError: lastError,
        createdAt: createdAt ?? now,
        updatedAt: updatedAt ?? now,
        deliveredAt: null,
      );

  ArtifactDestination watchedFolder({String path = '/mnt/nas'}) =>
      ArtifactDestination(
        id: 9,
        name: 'observatory-nas',
        kind: ArtifactDestinationKind.watchedFolder,
        configJson: '{"path":"$path"}',
        enabled: true,
        content: const {ArtifactContent.linearMasters},
        secretRef: null,
        createdAt: now,
        updatedAt: now,
      );

  test('the journal verdict leads and the configuration note attaches', () {
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: sftp(content: const {ArtifactContent.linearMasters}),
        journal: [
          entry(
            state: DeliveryAttemptState.failed,
            lastError: 'transportToolMissing: SFTP delivery drives the OpenSSH '
                'client and `ssh` is not on this PATH',
          ),
        ],
        // No key stored: a real gap, but not why the last run failed.
        secret: StoredSecretState.absent,
      ),
    );

    expect(line.kind, DeliveryStatusKind.failed);
    expect(
      line.sentence,
      contains('transportToolMissing'),
      reason: 'the mechanism the journal recorded is what actually stopped it',
    );
    expect(
      line.sentence,
      contains('No key in the keyring'),
      reason: 'the configuration gap is still stated, just not instead',
    );
    expect(
      line.sentence.indexOf('transportToolMissing'),
      lessThan(line.sentence.indexOf('No key in the keyring')),
      reason: 'the verdict leads; the note follows it',
    );
  });

  test('an empty selection attaches to the verdict rather than replacing it',
      () {
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: sftp(content: const {}, secretRef: null),
        journal: [
          entry(
            state: DeliveryAttemptState.retrying,
            lastError: 'destinationUnreachable: the share is not mounted',
          ),
        ],
        secret: StoredSecretState.present,
      ),
    );

    expect(line.kind, DeliveryStatusKind.retrying);
    expect(line.sentence, contains('destinationUnreachable'));
    expect(line.sentence, contains('Nothing selected'));
  });

  test('an empty selection is its own state when nothing has ever run', () {
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: sftp(content: const {}, secretRef: null),
        journal: const [],
        secret: StoredSecretState.present,
      ),
    );

    expect(line.kind, DeliveryStatusKind.incomplete);
    expect(line.sentence, contains('Nothing selected'));
  });

  test('a configured destination with no journal rows still says never run',
      () {
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: sftp(content: const {ArtifactContent.linearMasters}),
        journal: const [],
        secret: StoredSecretState.present,
      ),
    );

    expect(line.kind, DeliveryStatusKind.neverRun);
    expect(line.sentence, 'No delivery has run yet.');
  });

  test('a clean run says only what the journal says', () {
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: sftp(content: const {ArtifactContent.linearMasters}),
        journal: [
          DeliveryJournalEntry(
            id: 1,
            targetId: 9,
            jobId: 1,
            filePath: '/out/L.fits',
            bytes: 2048,
            checksum: 'abc',
            state: DeliveryAttemptState.delivered,
            attempts: 1,
            lastError: null,
            createdAt: now,
            updatedAt: now,
            deliveredAt: now,
          ),
        ],
        secret: StoredSecretState.present,
      ),
    );

    expect(line.kind, DeliveryStatusKind.delivered);
    expect(line.sentence, startsWith('Delivered '));
    expect(line.sentence, isNot(contains('keyring')));
  });

  test('switched off outranks everything, because nothing is being sent', () {
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: ArtifactDestination(
          id: 9,
          name: 'observatory-nas',
          kind: ArtifactDestinationKind.watchedFolder,
          configJson: '{"path":"/mnt/nas"}',
          enabled: false,
          content: const {ArtifactContent.linearMasters},
          secretRef: null,
          createdAt: now,
          updatedAt: now,
        ),
        journal: [
          entry(
            state: DeliveryAttemptState.failed,
            lastError: 'destinationConflict: that name is taken',
          ),
        ],
        secret: StoredSecretState.present,
      ),
    );

    expect(line.kind, DeliveryStatusKind.off);
    expect(
      line.sentence,
      contains('1 file never arrived'),
      reason: 'off explains why nothing is moving, not what is standing there',
    );
  });

  test('an off destination states the files standing at it', () {
    // The sweep names these rows suspended and skips them, and a peer's
    // manifest endpoint answers that peer `unknown_delivery_peer` — so this
    // page holds the only switch that will ever release them. Saying only
    // "Off" left twelve published files with nothing anywhere naming them.
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: ArtifactDestination(
          id: 9,
          name: 'office-pc',
          kind: ArtifactDestinationKind.peer,
          configJson: '{"peerId":"office-pc"}',
          enabled: false,
          content: const {ArtifactContent.draftRender},
          secretRef: null,
          createdAt: now,
          updatedAt: now,
        ),
        journal: [
          for (var i = 0; i < 12; i++)
            entry(
              state: DeliveryAttemptState.retrying,
              filePath: '/out/draft_$i.jpg',
            ),
        ],
        secret: StoredSecretState.absent,
      ),
    );

    expect(line.kind, DeliveryStatusKind.off);
    expect(
      line.sentence,
      'Off — nothing is sent here. 12 files are suspended here until it is '
      'switched back on.',
    );
  });

  test('an off destination with an empty journal says only that', () {
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: ArtifactDestination(
          id: 9,
          name: 'observatory-nas',
          kind: ArtifactDestinationKind.watchedFolder,
          configJson: '{"path":"/mnt/nas"}',
          enabled: false,
          content: const {ArtifactContent.linearMasters},
          secretRef: null,
          createdAt: now,
          updatedAt: now,
        ),
        journal: const [],
        secret: StoredSecretState.absent,
      ),
    );

    expect(line.sentence, 'Off — nothing is sent here.');
  });

  test('a partial failure counts once and names the unit once', () {
    // "1 file of 3 files failed" — the count was rendered with its unit on
    // both sides of the "of", so the sentence said "file" twice for one pair.
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: sftp(content: const {ArtifactContent.linearMasters}),
        journal: [
          entry(
            state: DeliveryAttemptState.failed,
            lastError: 'destinationConflict: that name is taken',
          ),
          entry(state: DeliveryAttemptState.delivered),
          entry(state: DeliveryAttemptState.delivered),
        ],
        secret: StoredSecretState.present,
      ),
    );

    expect(line.kind, DeliveryStatusKind.failed);
    expect(line.sentence, startsWith('1 of 3 files failed'));
    expect(line.sentence, isNot(contains('1 file of')));
  });

  // The wave-7 shape, from the release bundle: `case8-strand` held four of
  // job 4's drafts `failed` with destinationConflict and four of job 5's
  // `delivered`, and the row read "Delivered 17:55, 4 files, 1.4 MB." in green
  // with no Retry control.
  test('an older job\'s terminal failures outrank the newest job\'s green', () {
    final earlier = DateTime.utc(2026, 8, 15, 6, 30);
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: sftp(content: const {ArtifactContent.draftRender}),
        journal: [
          for (var i = 0; i < 4; i++)
            entry(
              state: DeliveryAttemptState.delivered,
              jobId: 5,
              filePath: '/out/job5_$i.jpg',
            ),
          for (var i = 0; i < 4; i++)
            entry(
              state: DeliveryAttemptState.failed,
              jobId: 4,
              createdAt: earlier,
              updatedAt: earlier,
              filePath: '/out/job4_$i.jpg',
              lastError: 'destinationConflict: a different file already holds '
                  'that name',
            ),
        ],
        secret: StoredSecretState.present,
      ),
    );

    expect(
      line.kind,
      DeliveryStatusKind.failed,
      reason: 'four files never arrived; a newer green cannot outrank that',
    );
    expect(line.sentence, startsWith('4 files never arrived'));
    expect(line.sentence, contains('destinationConflict'));
    expect(
      line.sentence,
      isNot(contains('Delivered')),
      reason: 'the sentence slot states the outstanding truth, not the newest',
    );
  });

  test('owed counts the destination\'s whole backlog, not the newest job', () {
    final earlier = DateTime.utc(2026, 8, 15, 6, 30);
    const reason =
        'insufficientSpace: /mnt/nas has 8 MB free; this delivery needs 32 MB';
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: sftp(content: const {ArtifactContent.linearMasters}),
        journal: [
          for (var i = 0; i < 4; i++)
            entry(
              state: DeliveryAttemptState.retrying,
              jobId: 5,
              filePath: '/out/job5_$i.fits',
              lastError: reason,
            ),
          for (var i = 0; i < 4; i++)
            entry(
              state: DeliveryAttemptState.retrying,
              jobId: 3,
              createdAt: earlier,
              updatedAt: earlier,
              filePath: '/out/job3_$i.fits',
              lastError: reason,
            ),
        ],
        secret: StoredSecretState.present,
      ),
    );

    expect(line.kind, DeliveryStatusKind.retrying);
    expect(
      line.sentence,
      contains('8 files owed'),
      reason: 'the retry sweep reads all eight rows and logs "8 retrying"',
    );
  });

  test('a watched folder whose directory is absent never reads healthy', () {
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: watchedFolder(path: '/mnt/nowhere/nightshade'),
        journal: const [],
        secret: StoredSecretState.absent,
        folder: WatchedFolderState.absent,
      ),
    );

    expect(line.kind, DeliveryStatusKind.incomplete);
    expect(
      line.sentence,
      contains('There is no directory at /mnt/nowhere/nightshade'),
    );
    expect(line.sentence, isNot(contains('No delivery has run yet')));
  });

  test('an absent directory rides behind the journal\'s own verdict', () {
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: watchedFolder(path: '/mnt/nowhere/nightshade'),
        journal: [
          entry(
            state: DeliveryAttemptState.retrying,
            lastError: 'destinationUnreachable: the share is not mounted',
          ),
        ],
        secret: StoredSecretState.absent,
        folder: WatchedFolderState.absent,
      ),
    );

    expect(line.kind, DeliveryStatusKind.retrying);
    expect(
      line.sentence.indexOf('destinationUnreachable'),
      lessThan(line.sentence.indexOf('There is no directory')),
    );
  });

  test('a directory check that was refused says so rather than nothing', () {
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: watchedFolder(path: '/mnt/locked'),
        journal: const [],
        secret: StoredSecretState.absent,
        folder: WatchedFolderState.unreadable,
        folderError: 'Permission denied',
      ),
    );

    expect(line.kind, DeliveryStatusKind.incomplete);
    expect(line.sentence, contains('could not be checked (Permission denied)'));
  });

  test('a watched folder that is there states nothing about its folder', () {
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: watchedFolder(),
        journal: [entry(state: DeliveryAttemptState.delivered)],
        secret: StoredSecretState.absent,
        folder: WatchedFolderState.present,
      ),
    );

    expect(line.kind, DeliveryStatusKind.delivered);
    expect(line.sentence, isNot(contains('directory')));
  });
}
