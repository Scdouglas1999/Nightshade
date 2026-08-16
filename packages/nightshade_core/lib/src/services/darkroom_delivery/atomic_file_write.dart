/// Two-step atomic delivery of one file into a directory.
///
/// The steps are separate calls on purpose. [stage] copies the bytes to a
/// staged name in the SAME directory and verifies them; [commit] renames
/// that staged file onto the final name. Nothing ever writes the final name
/// directly, so a process killed at any instant leaves either the previous
/// file or no file — never a half-written one under the name a user will open.
///
/// Rename is atomic only within one filesystem, which is why the staged file
/// is a sibling of the destination rather than a system temp file.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'delivery_artifact.dart';
import 'delivery_failure.dart';

/// Suffix marking a staged, not-yet-committed delivery. A kill between
/// [AtomicFileWrite.stage] and [AtomicFileWrite.commit] leaves one of these
/// behind; the next attempt for the same job and file overwrites it, so the
/// litter is bounded by the number of files in flight.
const String kStagedDeliverySuffix = '.nsdelivery-part';

/// A staged copy waiting to be committed onto its final name.
class AtomicFileWrite {
  /// Final path the file takes on [commit].
  final String finalPath;

  /// Path the bytes are written to first, a sibling of [finalPath].
  final String stagedPath;

  /// Checksum of the bytes as they were read back from [stagedPath].
  final String stagedChecksum;

  const AtomicFileWrite({
    required this.finalPath,
    required this.stagedPath,
    required this.stagedChecksum,
  });

  /// Copy [artifact] into [directory] under a staged name and verify the
  /// bytes that landed hash to [DeliveryFile.checksum].
  ///
  /// The staged name is derived from [jobId] and the file name, so a retry of
  /// the same delivery reuses it instead of accumulating one staged file per
  /// attempt.
  ///
  /// A checksum mismatch removes the staged file and throws — a partial copy
  /// is never left where a later attempt could mistake it for progress.
  static Future<AtomicFileWrite> stage({
    required DeliveryFile artifact,
    required Directory directory,
    required int jobId,
  }) async {
    final finalPath = p.join(directory.path, artifact.fileName);
    final stagedPath = p.join(
      directory.path,
      '.${artifact.fileName}.$jobId$kStagedDeliverySuffix',
    );
    final staged = File(stagedPath);

    try {
      await File(artifact.sourcePath).copy(stagedPath);
    } on PathAccessException catch (error) {
      throw DeliveryFailure(
        DeliveryFailureKind.permissionDenied,
        'Writing $stagedPath is not permitted',
        cause: error,
      );
    } on FileSystemException catch (error) {
      throw DeliveryFailure(
        _kindForWriteFailure(error),
        'Copying ${artifact.fileName} to ${directory.path} failed: '
        '${error.message}${await _remove(staged)}',
        cause: error,
      );
    }

    final landed = await sha256OfFile(staged);
    if (landed != artifact.checksum) {
      throw DeliveryFailure(
        DeliveryFailureKind.checksumMismatch,
        'The copy of ${artifact.fileName} in ${directory.path} hashes to '
        '$landed, not ${artifact.checksum}${await _remove(staged)}',
      );
    }

    return AtomicFileWrite(
      finalPath: finalPath,
      stagedPath: stagedPath,
      stagedChecksum: landed,
    );
  }

  /// Rename the staged copy onto [finalPath].
  ///
  /// This is the only call that creates the final name, and it is one
  /// filesystem operation.
  Future<void> commit() async {
    try {
      await File(stagedPath).rename(finalPath);
    } on PathAccessException catch (error) {
      throw DeliveryFailure(
        DeliveryFailureKind.permissionDenied,
        'Renaming onto $finalPath is not permitted',
        cause: error,
      );
    } on FileSystemException catch (error) {
      throw DeliveryFailure(
        DeliveryFailureKind.transportFailure,
        'Renaming ${p.basename(stagedPath)} onto ${p.basename(finalPath)} '
        'failed: ${error.message}',
        cause: error,
      );
    }
  }

  /// Remove the staged copy without committing it. Returns the sentence
  /// describing a cleanup that did not succeed, or an empty string.
  Future<String> abandon() => _remove(File(stagedPath));

  static DeliveryFailureKind _kindForWriteFailure(FileSystemException error) {
    // errno 28 is ENOSPC on every platform Nightshade ships to. A full
    // destination is retried overnight; anything else is a transport failure
    // until a clearer cause appears.
    if (error.osError?.errorCode == 28) {
      return DeliveryFailureKind.insufficientSpace;
    }
    return DeliveryFailureKind.transportFailure;
  }

  /// Delete [file] and return a sentence to append to the failure that is
  /// already being reported, or an empty string when the delete worked.
  ///
  /// A cleanup problem never replaces the delivery failure that caused it —
  /// the operator needs the first cause — so it rides along in the same
  /// message instead of being thrown or dropped.
  static Future<String> _remove(File file) async {
    try {
      if (await file.exists()) await file.delete();
      return '';
    } on FileSystemException catch (error) {
      return ' (the staged copy at ${file.path} could not be removed: '
          '${error.message}; the next attempt for this job overwrites it)';
    }
  }
}
