import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Resolve and create the directory this host uses for sequencer crash-recovery
/// checkpoints.
///
/// The layout belongs to the host, never to a connected client: a remote client
/// runs on a different filesystem, so a path it supplies is at best meaningless
/// and at worst unwritable, which turns a mid-night crash into an unrecoverable
/// night. Throws a [FileSystemException] when the resolved directory is not
/// absolute, cannot be created, or cannot be written to, so an unusable
/// checkpoint location fails loudly instead of being accepted silently.
Future<Directory> resolveHostCheckpointDirectory() async {
  final supportDir = await getApplicationSupportDirectory();
  final directory = Directory(
    '${supportDir.path}${Platform.pathSeparator}checkpoints',
  );
  if (!directory.isAbsolute) {
    throw FileSystemException(
      'the host checkpoint directory must be an absolute path',
      directory.path,
    );
  }
  await directory.create(recursive: true);
  final probe = File(
    '${directory.path}${Platform.pathSeparator}'
    '.nightshade-write-probe-${DateTime.now().microsecondsSinceEpoch}',
  );
  await probe.writeAsString('');
  await probe.delete();
  return directory;
}
