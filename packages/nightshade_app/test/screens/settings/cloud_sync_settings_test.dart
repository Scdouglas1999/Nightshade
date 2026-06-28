// Widget tests for [CloudSyncCard] — the "Backup & Sync" settings card —
// after S3-compatible support landed alongside WebDAV.
//
// What these lock in (the regressions a reviewer would fear most):
//
//   1. defaults_to_webdav_and_shows_webdav_fields — a pre-existing install
//      (provider resolves to WebDAV) shows the WebDAV fields, never the S3
//      ones. This is the back-compat hinge surfaced in the UI.
//   2. selecting_s3_reveals_s3_fields_and_hides_webdav — switching the
//      provider dropdown swaps the field set: endpoint/region/bucket/access
//      key/secret key + the MinIO path-style toggle appear; the WebDAV
//      server-URL field is gone.
//   3. successful_s3_test_connection_saves_then_probes_s3 — Test Connection
//      first persists the entered S3 config (provider==s3, secret via the
//      `password` param) then runs the connection probe; a green path shows
//      no failure.
//   4. saving_s3_routes_secret_via_password_param_not_config — Save hands the
//      service an S3 [SyncConfig] (which structurally cannot carry a secret)
//      plus the typed secret through the separate `password` parameter — the
//      card never smuggles the secret into a settings-bound field. The
//      keyring-vs-app_settings persistence split itself is pinned by the core
//      cloud_sync_service_test.
//   5. empty_required_s3_field_blocks_save — an empty S3 endpoint is rejected
//      inline with an error snackbar and saveConfig is never called.
//
// Why a hand-written fake instead of a real SyncService over in-memory drift:
// under `testWidgets` the binding runs in a fake-async zone, and a real drift
// query started from the card's initState `_load()` never resolves while the
// test pumps — it deadlocks. The fake keeps every method a synchronous-ish
// microtask so the card loads deterministically, and records the exact
// (config, password) the card saved so the secret-routing contract is
// asserted directly.

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/widgets/cloud_sync_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/mock_database.dart';

/// In-memory [SyncService] double. The super-constructor deps are inert: the
/// database is never queried (so no drift async escapes the fake-async zone),
/// and every method the card calls is overridden to resolve immediately.
class _FakeSyncService extends SyncService {
  _FakeSyncService({
    required super.backupService,
    required super.settingsDao,
    required super.secretsStore,
    required super.logger,
    this.config = const SyncConfig(machineName: 'test-rig'),
  });

  SyncConfig config;
  bool storedWebdavSecret = false;
  bool storedS3Secret = false;

  int saveCalls = 0;
  SyncConfig? lastSavedConfig;
  String? lastSavedPassword;

  int testConnectionCalls = 0;
  bool failTestConnection = false;

  @override
  Future<SyncConfig> loadConfig() async => config;

  @override
  Future<bool> hasStoredSecret(SyncProvider provider) async =>
      provider == SyncProvider.s3 ? storedS3Secret : storedWebdavSecret;

  @override
  Future<bool> hasStoredPassword() async => storedWebdavSecret;

  @override
  Future<SyncStatus> status() async => SyncStatus(
        configured: config.isConfigured,
        autoPushEnabled: config.autoPushEnabled,
        machineName: config.machineName,
        serverUrl: config.provider == SyncProvider.s3
            ? config.s3Endpoint
            : config.serverUrl,
        pushInProgress: false,
      );

  @override
  Future<void> saveConfig(SyncConfig config, {String? password}) async {
    saveCalls++;
    lastSavedConfig = config;
    lastSavedPassword = password;
    this.config = config;
    if (password != null && password.isNotEmpty) {
      if (config.provider == SyncProvider.s3) {
        storedS3Secret = true;
      } else {
        storedWebdavSecret = true;
      }
    }
  }

  @override
  Future<void> testConnection() async {
    testConnectionCalls++;
    if (failTestConnection) {
      throw const SyncTargetException(
        'invalid credentials',
        kind: SyncTargetErrorKind.unknown,
      );
    }
  }
}

LoggingService _testLogger(Directory tempDir) => LoggingService(
      applicationSupportDirectoryProvider: () async => tempDir,
      nativeInitWithLogging: ({String? logDirectory}) {},
      nativeInit: () {},
      currentLogFileProvider: () => null,
    );

/// Pump [CloudSyncCard] with [service] overriding the production provider and
/// drain the card's async `_load()` with bounded pumps (a bare pumpAndSettle
/// would wait forever on the loading CircularProgressIndicator animation).
Future<void> _pumpCard(WidgetTester tester, SyncService service) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1000, 1400);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [syncServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(
          body: SingleChildScrollView(child: CloudSyncCard()),
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find
        .byType(DropdownButtonFormField<SyncProvider>)
        .evaluate()
        .isNotEmpty) {
      break;
    }
  }
}

/// Enter [text] into the [TextField] whose decoration label is [label]. The
/// label renders as a Text descendant of the TextField, so an ancestor lookup
/// uniquely identifies the field.
Future<void> _enter(WidgetTester tester, String label, String text) async {
  final field = find.ancestor(
    of: find.text(label),
    matching: find.byType(TextField),
  );
  expect(field, findsOneWidget, reason: 'expected a field labelled "$label"');
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> _selectS3(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<SyncProvider>));
  await tester.pumpAndSettle();
  // The S3 entry only exists in the opened menu overlay (the closed button
  // shows the current WebDAV value), so `.last` targets the menu item.
  await tester.tap(find.text('S3-compatible (AWS, MinIO, Backblaze B2)').last);
  await tester.pumpAndSettle();
}

Future<void> _fillS3(WidgetTester tester, {required String secret}) async {
  await _enter(tester, 'Endpoint', 'https://s3.us-east-1.amazonaws.com');
  await _enter(tester, 'Region', 'us-east-1');
  await _enter(tester, 'Bucket', 'astro-backups');
  await _enter(tester, 'Access key', 'AKIAEXAMPLE');
  await _enter(tester, 'Secret key', secret);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // One shared, never-queried database backs the inert fake-service deps, so
  // the drift "multiple databases" debug warning never fires.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late NightshadeDatabase db;
  late Directory tempDir;
  late LoggingService logger;

  setUpAll(() async {
    db = mockDatabase();
    tempDir = await Directory.systemTemp.createTemp('ns_cloud_sync_ui_');
    logger = _testLogger(tempDir);
  });

  tearDownAll(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  _FakeSyncService makeService({SyncConfig? initial}) => _FakeSyncService(
        backupService: BackupService(
          database: db,
          sequenceRepository: SequenceRepository(db.sequencesDao),
          logger: logger,
        ),
        settingsDao: SettingsDao(db),
        secretsStore: SecretsStore(InMemorySecureKeyValueStore()),
        logger: logger,
        config: initial ?? const SyncConfig(machineName: 'test-rig'),
      );

  testWidgets('defaults_to_webdav_and_shows_webdav_fields', (tester) async {
    await _pumpCard(tester, makeService());

    expect(find.byType(DropdownButtonFormField<SyncProvider>), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    // S3 fields absent until the provider is switched.
    expect(find.text('Endpoint'), findsNothing);
    expect(find.text('Region'), findsNothing);
    expect(find.text('Bucket'), findsNothing);
    expect(find.text('Access key'), findsNothing);
    expect(find.text('Secret key'), findsNothing);
  });

  testWidgets('selecting_s3_reveals_s3_fields_and_hides_webdav',
      (tester) async {
    await _pumpCard(tester, makeService());

    await _selectS3(tester);

    expect(find.text('Endpoint'), findsOneWidget);
    expect(find.text('Region'), findsOneWidget);
    expect(find.text('Bucket'), findsOneWidget);
    expect(find.text('Access key'), findsOneWidget);
    expect(find.text('Secret key'), findsOneWidget);
    expect(
      find.text('Path-style addressing (required for MinIO)'),
      findsOneWidget,
    );
    // WebDAV-only field gone; the shared machine-name field stays.
    expect(find.text('Server URL'), findsNothing);
    expect(find.text('Machine name'), findsOneWidget);
  });

  testWidgets('successful_s3_test_connection_saves_then_probes_s3',
      (tester) async {
    final service = makeService();
    await _pumpCard(tester, service);

    await _selectS3(tester);
    await _fillS3(tester, secret: 'the-secret');

    await tester.tap(find.widgetWithText(NightshadeButton, 'Test Connection'));
    await tester.pumpAndSettle();

    // Test Connection saved the entered config first, routing the secret via
    // the password param, then probed the (S3) target.
    expect(service.saveCalls, 1);
    expect(service.lastSavedConfig?.provider, SyncProvider.s3);
    expect(service.lastSavedConfig?.s3Bucket, 'astro-backups');
    expect(service.lastSavedPassword, 'the-secret');
    expect(service.testConnectionCalls, 1);
    expect(find.textContaining('Connection failed'), findsNothing);
  });

  testWidgets('saving_s3_routes_secret_via_password_param_not_config',
      (tester) async {
    final service = makeService();
    await _pumpCard(tester, service);

    await _selectS3(tester);
    await _fillS3(tester, secret: 'top-secret-value');

    await tester.tap(find.widgetWithText(NightshadeButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = service.lastSavedConfig;
    expect(service.saveCalls, 1);
    expect(saved, isNotNull);
    expect(saved!.provider, SyncProvider.s3);
    // Non-secret fields ride the config.
    expect(saved.s3Endpoint, 'https://s3.us-east-1.amazonaws.com');
    expect(saved.s3Region, 'us-east-1');
    expect(saved.s3Bucket, 'astro-backups');
    expect(saved.s3AccessKey, 'AKIAEXAMPLE');
    // The secret travels ONLY through the password param.
    expect(service.lastSavedPassword, 'top-secret-value');
    // It is never smuggled into a settings-bound config field.
    for (final field in [
      saved.serverUrl,
      saved.username,
      saved.s3Endpoint,
      saved.s3Region,
      saved.s3Bucket,
      saved.s3AccessKey,
      saved.machineName,
    ]) {
      expect(field.contains('top-secret-value'), isFalse,
          reason: 'secret leaked into a non-secret SyncConfig field');
    }
    // The service recorded the S3 secret (and not the WebDAV one).
    expect(await service.hasStoredSecret(SyncProvider.s3), isTrue);
    expect(await service.hasStoredSecret(SyncProvider.webdav), isFalse);
  });

  testWidgets('empty_required_s3_field_blocks_save', (tester) async {
    final service = makeService();
    await _pumpCard(tester, service);

    await _selectS3(tester);
    // Leave Endpoint empty; fill the rest.
    await _enter(tester, 'Region', 'us-east-1');
    await _enter(tester, 'Bucket', 'astro-backups');
    await _enter(tester, 'Access key', 'AKIAEXAMPLE');
    await _enter(tester, 'Secret key', 'top-secret-value');

    await tester.tap(find.widgetWithText(NightshadeButton, 'Save'));
    await tester.pump();

    expect(find.text('S3 endpoint is required.'), findsOneWidget);
    // Validation fired before any persistence.
    expect(service.saveCalls, 0);
    expect(await service.hasStoredSecret(SyncProvider.s3), isFalse);
  });
}
