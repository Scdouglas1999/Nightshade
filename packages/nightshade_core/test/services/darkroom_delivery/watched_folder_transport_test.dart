// Watched-folder delivery against real temp directories, plus the fault
// injections a NAS actually produces: the mount disappears, the volume fills,
// the same name is already there with different bytes, and the process dies
// between the staged copy and the rename.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/darkroom/delivery.dart';
import 'package:nightshade_core/src/services/darkroom_delivery/artifact_transport.dart';
import 'package:nightshade_core/src/services/darkroom_delivery/atomic_file_write.dart';
import 'package:nightshade_core/src/services/darkroom_delivery/delivery_artifact.dart';
import 'package:nightshade_core/src/services/darkroom_delivery/delivery_failure.dart';
import 'package:nightshade_core/src/services/darkroom_delivery/watched_folder_transport.dart';
import 'package:path/path.dart' as p;

class _FixedFreeSpace implements FreeSpaceProbe {
  _FixedFreeSpace(this.bytes);

  final int bytes;

  @override
  Future<int> freeBytes(String path) async => bytes;
}

ArtifactDestination _destination({
  required String path,
  int? minFreeBytes,
  Set<ArtifactContent> content = const {ArtifactContent.linearMasters},
}) {
  final config = <String, Object?>{
    'path': path,
    if (minFreeBytes != null) 'minFreeBytes': minFreeBytes,
  };
  return ArtifactDestination(
    id: 3,
    name: 'nas',
    kind: ArtifactDestinationKind.watchedFolder,
    configJson: jsonEncode(config),
    enabled: true,
    content: content,
    createdAt: DateTime.utc(2026, 8, 16),
    updatedAt: DateTime.utc(2026, 8, 16),
  );
}

void main() {
  late Directory tempDir;
  late Directory source;
  late Directory destinationDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ns_watched_');
    source = await Directory(p.join(tempDir.path, 'source')).create();
    destinationDir = await Directory(p.join(tempDir.path, 'nas')).create();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<DeliveryArtifact> writeMaster(
    String name, {
    String contents = 'MASTER-LIGHT-BYTES',
  }) async {
    final file = File(p.join(source.path, name));
    await file.writeAsString(contents);
    return DeliveryArtifact.describeArtifact(
      content: ArtifactContent.linearMasters,
      path: file.path,
    );
  }

  WatchedFolderTransport transportFor({
    String? path,
    int freeBytes = 1 << 40,
    int? minFreeBytes,
  }) {
    return WatchedFolderTransport(
      destination: _destination(
        path: path ?? destinationDir.path,
        minFreeBytes: minFreeBytes,
      ),
      jobId: 42,
      freeSpace: _FixedFreeSpace(freeBytes),
    );
  }

  group('delivering into a watched folder', () {
    test(
      'copies the file, leaves the source, and reports where it went',
      () async {
        final artifact = await writeMaster('M31_Ha_master.fits');
        final transport = transportFor();
        await transport.open([artifact]);

        final outcome = await transport.deliver(artifact);
        await transport.close();

        final landed = File(p.join(destinationDir.path, 'M31_Ha_master.fits'));
        expect(outcome.disposition, DeliveryDisposition.delivered);
        expect(outcome.checksum, artifact.checksum);
        expect(outcome.destinationDescription, landed.path);
        expect(await landed.readAsString(), 'MASTER-LIGHT-BYTES');
        expect(
          await File(artifact.sourcePath).exists(),
          isTrue,
          reason: 'delivery copies and never moves',
        );
      },
    );

    test('leaves no staged file behind after a successful delivery', () async {
      final artifact = await writeMaster('M31_Ha_master.fits');
      final transport = transportFor();
      await transport.open([artifact]);
      await transport.deliver(artifact);
      await transport.close();

      final leftovers = destinationDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith(kStagedDeliverySuffix))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('re-delivering the same bytes is a delivery, not a rewrite', () async {
      final artifact = await writeMaster('M31_Ha_master.fits');
      final transport = transportFor();
      await transport.open([artifact]);
      await transport.deliver(artifact);
      final landed = File(p.join(destinationDir.path, 'M31_Ha_master.fits'));
      final firstModified = await landed.lastModified();

      final second = await transport.deliver(artifact);
      await transport.close();

      expect(second.disposition, DeliveryDisposition.delivered);
      expect(second.checksum, artifact.checksum);
      expect(await landed.lastModified(), firstModified);
    });

    test('refuses to overwrite a file that has different content and names '
        'the conflict', () async {
      final artifact = await writeMaster('M31_Ha_master.fits');
      final squatter = File(p.join(destinationDir.path, 'M31_Ha_master.fits'));
      await squatter.writeAsString('SOMEBODY-ELSES-MASTER');
      final transport = transportFor();
      await transport.open([artifact]);

      final failure = await transport
          .deliver(artifact)
          .then<DeliveryFailure?>((_) => null)
          .onError<DeliveryFailure>((error, _) => error);
      await transport.close();

      expect(failure, isNotNull);
      expect(failure!.kind, DeliveryFailureKind.destinationConflict);
      expect(failure.retryable, isFalse);
      expect(failure.message, contains('M31_Ha_master.fits'));
      expect(failure.message, contains(artifact.checksum));
      expect(await squatter.readAsString(), 'SOMEBODY-ELSES-MASTER');
    });
  });

  group('preflight', () {
    test('reports a destination that is not mounted as unreachable', () async {
      final artifact = await writeMaster('M31_Ha_master.fits');
      final transport = transportFor(
        path: p.join(tempDir.path, 'unmounted-nas'),
      );

      await expectLater(
        transport.open([artifact]),
        throwsA(
          isA<DeliveryFailure>()
              .having(
                (f) => f.kind,
                'kind',
                DeliveryFailureKind.destinationUnreachable,
              )
              .having((f) => f.retryable, 'retryable', isTrue),
        ),
      );
      expect(
        await Directory(p.join(tempDir.path, 'unmounted-nas')).exists(),
        isFalse,
        reason: 'an unmounted share is never created as a local directory',
      );
    });

    test(
      'refuses a delivery larger than the free space plus headroom',
      () async {
        final artifact = await writeMaster('M31_Ha_master.fits');
        final transport = transportFor(
          freeBytes: artifact.bytes + 10,
          minFreeBytes: 1024,
        );

        await expectLater(
          transport.open([artifact]),
          throwsA(
            isA<DeliveryFailure>()
                .having(
                  (f) => f.kind,
                  'kind',
                  DeliveryFailureKind.insufficientSpace,
                )
                .having((f) => f.retryable, 'retryable', isTrue),
          ),
        );
      },
    );

    test('accepts a delivery that fits inside the free space', () async {
      final artifact = await writeMaster('M31_Ha_master.fits');
      final transport = transportFor(
        freeBytes: artifact.bytes + 4096,
        minFreeBytes: 1024,
      );

      await transport.open([artifact]);
      await transport.close();
    });

    test('a destination with no path is a configuration failure, not a '
        'silent skip', () async {
      final artifact = await writeMaster('M31_Ha_master.fits');
      final transport = WatchedFolderTransport(
        destination: ArtifactDestination(
          id: 4,
          name: 'unconfigured',
          kind: ArtifactDestinationKind.watchedFolder,
          configJson: '{}',
          enabled: true,
          content: const {ArtifactContent.linearMasters},
          createdAt: DateTime.utc(2026, 8, 16),
          updatedAt: DateTime.utc(2026, 8, 16),
        ),
        jobId: 42,
        freeSpace: _FixedFreeSpace(1 << 40),
      );

      await expectLater(
        transport.open([artifact]),
        throwsA(
          isA<DeliveryFailure>().having(
            (f) => f.kind,
            'kind',
            DeliveryFailureKind.configurationInvalid,
          ),
        ),
      );
    });

    test('delivering before opening is refused rather than writing into a '
        'directory nobody checked', () async {
      final artifact = await writeMaster('M31_Ha_master.fits');
      final transport = transportFor();

      await expectLater(
        transport.deliver(artifact),
        throwsA(isA<DeliveryFailure>()),
      );
    });
  });

  group('atomicity', () {
    test('a process killed between the staged copy and the rename leaves no '
        'file under the final name', () async {
      final artifact = await writeMaster('M31_Ha_master.fits');

      // stage() is the whole of what a delivery does before commit(); dropping
      // the AtomicFileWrite here is exactly what a kill at that instant does.
      final staged = await AtomicFileWrite.stage(
        artifact: artifact,
        directory: destinationDir,
        jobId: 42,
      );

      expect(
        await File(p.join(destinationDir.path, 'M31_Ha_master.fits')).exists(),
        isFalse,
        reason: 'the final name is only ever created by the rename',
      );
      expect(await File(staged.stagedPath).exists(), isTrue);
      expect(staged.stagedPath, endsWith(kStagedDeliverySuffix));
      expect(staged.stagedChecksum, artifact.checksum);
    });

    test('the staged copy is verified before it is committed', () async {
      final artifact = await writeMaster('M31_Ha_master.fits');
      final lying = DeliveryArtifact(
        content: ArtifactContent.linearMasters,
        sourcePath: artifact.sourcePath,
        bytes: artifact.bytes,
        checksum: 'de' * 32,
      );

      await expectLater(
        AtomicFileWrite.stage(
          artifact: lying,
          directory: destinationDir,
          jobId: 42,
        ),
        throwsA(
          isA<DeliveryFailure>().having(
            (f) => f.kind,
            'kind',
            DeliveryFailureKind.checksumMismatch,
          ),
        ),
      );
      expect(
        destinationDir.listSync(),
        isEmpty,
        reason: 'a copy that did not verify is removed, not left as progress',
      );
    });

    test('a retry of the same job reuses one staged name instead of '
        'accumulating temporaries', () async {
      final artifact = await writeMaster('M31_Ha_master.fits');

      final first = await AtomicFileWrite.stage(
        artifact: artifact,
        directory: destinationDir,
        jobId: 42,
      );
      final second = await AtomicFileWrite.stage(
        artifact: artifact,
        directory: destinationDir,
        jobId: 42,
      );

      expect(second.stagedPath, first.stagedPath);
      expect(destinationDir.listSync().length, 1);

      await second.commit();
      expect(
        await File(p.join(destinationDir.path, 'M31_Ha_master.fits')).exists(),
        isTrue,
      );
    });

    test('a source that vanished before delivery is a typed failure', () async {
      final artifact = await writeMaster('M31_Ha_master.fits');
      await File(artifact.sourcePath).delete();
      final transport = transportFor();
      await transport.open([artifact]);

      await expectLater(
        transport.deliver(artifact),
        throwsA(isA<DeliveryFailure>()),
      );
      expect(
        await File(p.join(destinationDir.path, 'M31_Ha_master.fits')).exists(),
        isFalse,
      );
    });
  });

  group('describing artifacts', () {
    test('a missing source is reported, never skipped', () async {
      await expectLater(
        DeliveryArtifact.describeArtifact(
          content: ArtifactContent.draftRender,
          path: p.join(source.path, 'never-written.jpg'),
        ),
        throwsA(
          isA<DeliveryFailure>().having(
            (f) => f.kind,
            'kind',
            DeliveryFailureKind.sourceMissing,
          ),
        ),
      );
    });

    test('a set selects only what a destination asked for', () async {
      final master = await writeMaster('M31_Ha_master.fits');
      final draft = File(p.join(source.path, 'draft.jpg'));
      await draft.writeAsString('JPEG');

      final set = await DeliveryArtifactSet.build(
        jobId: 42,
        sources: {
          ArtifactContent.linearMasters: [master.sourcePath],
          ArtifactContent.draftRender: [draft.path],
        },
      );

      final mastersOnly = set.selectedFor(
        _destination(
          path: destinationDir.path,
          content: const {ArtifactContent.linearMasters},
        ),
      );
      expect(set.artifacts.length, 2);
      expect(mastersOnly.map((a) => a.fileName), ['M31_Ha_master.fits']);
    });
  });
}
