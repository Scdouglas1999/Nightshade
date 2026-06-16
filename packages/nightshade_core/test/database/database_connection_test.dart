import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ns_db_connection_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('database directory override pins the Drift database path', () async {
    final dbDir = Directory(p.join(tempDir.path, 'daemon-db'));
    final docsDir = Directory(p.join(tempDir.path, 'documents'));

    final file = await resolveDefaultDatabaseFile(
      environment: {nightshadeDatabaseDirEnv: dbDir.path},
      documentsDirectoryProvider: () async => docsDir,
    );

    expect(file.path, p.join(dbDir.path, 'nightshade.db'));
  });

  test(
    'empty database directory override falls back to Documents path',
    () async {
      final docsDir = Directory(p.join(tempDir.path, 'documents'));

      final file = await resolveDefaultDatabaseFile(
        environment: {nightshadeDatabaseDirEnv: '   '},
        documentsDirectoryProvider: () async => docsDir,
      );

      expect(file.path, p.join(docsDir.path, 'Nightshade', 'nightshade.db'));
    },
  );
}
