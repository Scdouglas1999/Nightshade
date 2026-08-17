// What one destination row is allowed to say about itself.
//
// The rule pinned here: the JOURNAL outranks the configuration. A destination
// whose last run failed for a reason the configuration cannot name — no `ssh`
// binary on the machine, a conflicting file, a full disk — used to have that
// verdict replaced by whichever structural gap was checked first. That both
// hid the mechanism and named a next step ("store a key") that could not
// change the outcome. The verdict now leads and the structural note rides
// behind it.

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
  }) =>
      DeliveryJournalEntry(
        id: 1,
        targetId: 9,
        jobId: 1,
        filePath: '/out/L.fits',
        bytes: 1024,
        checksum: null,
        state: state,
        attempts: 1,
        lastError: lastError,
        createdAt: now,
        updatedAt: updatedAt ?? now,
        deliveredAt: null,
      );

  test('the journal verdict leads and the configuration note attaches', () {
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: sftp(content: const {ArtifactContent.linearMasters}),
        lastRun: [
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
        lastRun: [
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
        lastRun: const [],
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
        lastRun: const [],
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
        lastRun: [
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
        lastRun: [
          entry(
            state: DeliveryAttemptState.failed,
            lastError: 'destinationConflict: that name is taken',
          ),
        ],
        secret: StoredSecretState.present,
      ),
    );

    expect(line.kind, DeliveryStatusKind.off);
  });

  test('a partial failure counts once and names the unit once', () {
    // "1 file of 3 files failed" — the count was rendered with its unit on
    // both sides of the "of", so the sentence said "file" twice for one pair.
    final line = DeliveryStatusLine.of(
      DeliveryDestinationView(
        destination: sftp(content: const {ArtifactContent.linearMasters}),
        lastRun: [
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
}
