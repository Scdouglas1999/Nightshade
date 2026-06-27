import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/equipment_profile_remote_mapping.dart';
import '../services/logging_service.dart';
import 'backend_provider.dart';
import 'database_provider.dart';

/// Push the SQLite-active profile into the native (Rust) executor store so the
/// executor's `load_and_set_profile` side effects run.
///
/// SQLite is the single source of truth for profile READS on both master types
/// (desktop GUI + Pi-headless), but the Rust executor still resolves the active
/// profile from its OWN native store. Whenever the active profile changes from
/// the GUI (NOT via the REST `handleLoadProfile`, which already write-throughs),
/// the new active row must be pushed to the native store or headless sequencing
/// would keep stale (or empty) active-profile context.
///
/// Host/desktop-only: in remote (slave) mode the backend is a `NetworkBackend`,
/// which has no native store — the call is a no-op there, but callers should
/// gate on `isRemoteModeProvider` and route activation through the host REST
/// path instead. Best-effort: a native hiccup must not fail the GUI activation.
Future<void> writeActiveProfileThroughToRust(Ref ref, int profileId) async {
  try {
    final row = await ref
        .read(equipmentProfilesDaoProvider)
        .getProfileById(profileId);
    if (row == null) return;
    final remote = dbProfileToRemote(row);
    final backend = ref.read(profileSettingsBackendProvider);
    await backend.saveProfile(remote);
    await backend.loadProfile(remote.id);
  } on Object catch (e, stack) {
    ref
        .read(loggingServiceProvider)
        .debug(
          'Active-profile write-through to native store failed: $e',
          source: 'ProfileActivationWriteThrough',
          fields: {'error': e.toString(), 'stack': stack.toString()},
        );
  }
}

/// WidgetRef overload for GUI call sites (equipment screen, profile editor).
Future<void> writeActiveProfileThroughToRustFromWidget(
  WidgetRef ref,
  int profileId,
) async {
  try {
    final row = await ref
        .read(equipmentProfilesDaoProvider)
        .getProfileById(profileId);
    if (row == null) return;
    final remote = dbProfileToRemote(row);
    final backend = ref.read(profileSettingsBackendProvider);
    await backend.saveProfile(remote);
    await backend.loadProfile(remote.id);
  } on Object catch (e, stack) {
    ref
        .read(loggingServiceProvider)
        .debug(
          'Active-profile write-through to native store failed: $e',
          source: 'ProfileActivationWriteThrough',
          fields: {'error': e.toString(), 'stack': stack.toString()},
        );
  }
}
