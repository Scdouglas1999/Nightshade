/// Truthful "can a critical alert actually reach a phone?" state for the
/// notification settings surface.
///
/// The "Push critical alerts to mobile" row used to render as a plain ON
/// switch whatever the real delivery state was. On Android that claim was
/// never true in a stock build — the FCM client is a dormant scaffold pending
/// Firebase provisioning (`apps/mobile/android/app/google-services.json` is
/// absent), so the phone logs
/// `FCM not configured (no google-services.json); push registration dormant`
/// and never registers a token. The switch therefore asserted a capability the
/// system did not have.
///
/// Two authorities answer the question, depending on where this code runs:
///   * a remote controller (phone/tablet paired to a host) asks the host over
///     `GET /api/push/targets` — its own local pairing DB knows nothing about
///     who has registered with the host;
///   * the host itself reads the same `PairingDatabase` its headless server
///     writes push tokens into, plus the on-disk `push_config.json` that
///     decides whether a cloud channel exists at all.
library;

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';
import 'package:path_provider/path_provider.dart';

/// The pairing database the host's headless server stores push tokens in.
///
/// A separate Drift connection to the same file the server uses — the same
/// thing `PairingNotifier` already does for the paired-device list. Overridable
/// so tests can supply an in-memory database.
final pushPairingDatabaseProvider = Provider<PairingDatabase>((ref) {
  final db = PairingDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Whether the HOST has a cloud push channel configured. Overridable in tests.
final hostCloudPushConfiguredProvider = FutureProvider<bool>((ref) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final config = await PushConfig.load(appSupportDir: dir.path);
    return config.hasCloudChannel || config.mock;
  } on MissingPluginException {
    // No platform channel (widget tests / headless harness) — we cannot claim
    // a channel exists.
    return false;
  } catch (_) {
    return false;
  }
});

/// Whether a critical alert could actually be delivered to a phone right now.
///
/// Never throws: a host that cannot be reached is reported as "cannot
/// deliver", which is the honest answer — an alert really would not arrive.
final pushDeliveryTargetsProvider = FutureProvider<PushDeliveryTargets>((
  ref,
) async {
  final backend = ref.watch(backendProvider);

  if (backend is DisconnectedBackend) {
    return PushDeliveryTargets.none;
  }

  if (backend is NetworkBackend) {
    try {
      return await backend.getPushDeliveryTargets();
    } catch (_) {
      // An unreachable/older host cannot be shown as "delivery works".
      return PushDeliveryTargets.none;
    }
  }

  // Local host.
  try {
    final db = ref.watch(pushPairingDatabaseProvider);
    final tokens = await db.getAllPushTokens();
    final deviceIds = <String>{};
    var fcm = 0;
    var apns = 0;
    for (final token in tokens) {
      deviceIds.add(token.deviceId);
      switch (token.platform) {
        case 'fcm':
          fcm++;
        case 'apns':
          apns++;
      }
    }
    final cloudConfigured =
        await ref.watch(hostCloudPushConfiguredProvider.future);
    return PushDeliveryTargets(
      registeredDeviceCount: deviceIds.length,
      fcmTokenCount: fcm,
      apnsTokenCount: apns,
      cloudDeliveryConfigured: cloudConfigured,
    );
  } catch (_) {
    return PushDeliveryTargets.none;
  }
});
