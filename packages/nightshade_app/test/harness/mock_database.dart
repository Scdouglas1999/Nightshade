// In-memory drift database factory for nightshade_app widget tests.
//
// Why this lives in nightshade_app/test/harness/ rather than reusing the
// existing helper at packages/nightshade_core/test/mocks/mock_database.dart:
// files under `test/` are not exportable across packages (Dart's test-layout
// convention). The package boundary forces this duplication — keep both
// helpers thin and behaviourally identical so tests work the same on either
// side of the boundary. See docs/code-quality/audit-tests.md §6.

import 'package:drift/native.dart';
import 'package:nightshade_core/src/database/database.dart';

/// Build a fresh in-memory `NightshadeDatabase` for a single widget test.
///
/// Every call returns a new isolated database — tests should call
/// `db.close()` in a `tearDown` (or use `addTearDown(db.close)` inside the
/// test) so the underlying sqlite handle is released before the next test
/// runs. `NativeDatabase.memory()` opens an in-process sqlite file with no
/// disk footprint, so parallel tests cannot interfere.
///
/// Why not pre-populate seed data here: tests have widely varying setup
/// requirements (some need an active profile, some need empty state, some
/// need a queued sequence). Seeding belongs in the test body, not the
/// harness, so the harness stays generic.
NightshadeDatabase mockDatabase() {
  return NightshadeDatabase.forTesting(NativeDatabase.memory());
}
