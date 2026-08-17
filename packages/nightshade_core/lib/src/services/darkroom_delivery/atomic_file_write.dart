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

/// Re-type [failure] — raised reading a file that lives in the DESTINATION —
/// by asking which side actually went away.
///
/// [sha256OfFile] cannot know whose file it is holding, so it calls every
/// unreadable path [DeliveryFailureKind.sourceMissing]: terminal, and phrased
/// as the rig having lost the master. Every file delivery reads BACK — the
/// staged copy, the name already sitting at the destination — is on the far
/// side, so that verdict blames the night's data for an unmounted NAS and
/// records `failed` on an attempt the sweep would have survived.
///
/// [sourcePath] is stat-ed here, at failure time, rather than trusted from the
/// describe pass minutes ago: a source still on the rig means the DESTINATION
/// is what disappeared, which is exactly the failure another attempt fixes.
///
/// [failure] comes from [sha256OfFile], whose message already names the file it
/// could not read, so the destination path is not repeated here — what is
/// added is the verdict on the OTHER side.
Future<DeliveryFailure> destinationReadFailure({
  required String sourcePath,
  required DeliveryFailure failure,
}) async {
  final cause = failure.cause ?? failure;
  if (!await File(sourcePath).exists()) {
    return DeliveryFailure(
      DeliveryFailureKind.sourceMissing,
      '${failure.message}. $sourcePath is no longer on the rig either, so the '
      'artifact itself is gone',
      cause: cause,
    );
  }
  if (failure.kind == DeliveryFailureKind.permissionDenied) {
    return DeliveryFailure(
      DeliveryFailureKind.permissionDenied,
      '${failure.message}. That is the destination\'s copy and $sourcePath is '
      'still on the rig, so the destination is what refused the read',
      cause: cause,
    );
  }
  return DeliveryFailure(
    DeliveryFailureKind.destinationUnreachable,
    '${failure.message}. That is the destination\'s copy and $sourcePath is '
    'still on the rig, so the destination went away, not the artifact',
    cause: cause,
  );
}

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
    } on FileSystemException catch (error) {
      throw await _copyFailure(
        artifact: artifact,
        directory: directory,
        staged: staged,
        error: error,
      );
    }

    final String landed;
    try {
      landed = await sha256OfFile(staged);
    } on DeliveryFailure catch (failure) {
      final typed = await destinationReadFailure(
        sourcePath: artifact.sourcePath,
        failure: failure,
      );
      throw DeliveryFailure(
        typed.kind,
        '${typed.message}${await _remove(staged)}',
        cause: typed.cause,
      );
    }
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

  /// Type a copy that the operating system refused, by which side it was
  /// complaining about.
  ///
  /// The copy reads the rig and writes the destination, so one
  /// [FileSystemException] can mean either. A full destination is its own
  /// kind; otherwise the SOURCE is stat-ed HERE, because a master that
  /// vanished between the describe pass and this copy is terminal — no later
  /// attempt finds it — while everything else belongs to the destination and
  /// is worth another attempt.
  static Future<DeliveryFailure> _copyFailure({
    required DeliveryFile artifact,
    required Directory directory,
    required File staged,
    required FileSystemException error,
  }) async {
    final trailer = await _remove(staged);
    // errno 28 is ENOSPC on every platform Nightshade ships to. A full
    // destination is retried overnight; space is freed by other things
    // finishing.
    if (error.osError?.errorCode == 28) {
      return DeliveryFailure(
        DeliveryFailureKind.insufficientSpace,
        'Copying ${artifact.fileName} to ${directory.path} failed: '
        '${error.message}$trailer',
        cause: error,
      );
    }
    if (!await File(artifact.sourcePath).exists()) {
      return DeliveryFailure(
        DeliveryFailureKind.sourceMissing,
        'Copying ${artifact.fileName} to ${directory.path} failed '
        '(${error.message}) and ${artifact.sourcePath} is no longer on the '
        'rig$trailer',
        cause: error,
      );
    }
    if (error is PathAccessException) {
      return DeliveryFailure(
        DeliveryFailureKind.permissionDenied,
        'Copying ${artifact.fileName} to ${directory.path} is not permitted '
        '(${error.message}); ${artifact.sourcePath} is still on the '
        'rig$trailer',
        cause: error,
      );
    }
    return DeliveryFailure(
      DeliveryFailureKind.transportFailure,
      'Copying ${artifact.fileName} to ${directory.path} failed: '
      '${error.message}; ${artifact.sourcePath} is still on the rig$trailer',
      cause: error,
    );
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
