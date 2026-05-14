// Barrel re-export for the nightshade_app widget-test harness.
//
// Tests should `import '<...>/test/harness/harness.dart';` to pull in
// everything they need in one go. Listing only the public API here makes
// the import surface obvious; tests that need internal pieces (e.g.
// TestBackendNotifier for a custom override) can still import the
// individual file directly.
//
// See: docs/code-quality/audit-tests.md §6.

export 'mock_backend.dart' show MockBackend, mockBackend;
export 'mock_database.dart' show mockDatabase;
export 'pump_app_screen.dart'
    show HarnessHandle, TestBackendNotifier, findByDataKey, pumpAppScreen;
