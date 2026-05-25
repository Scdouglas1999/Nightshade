// Cellular/remote push delivery scaffold for critical notifications.
//
// P1-19's primary deliverable is the LAN UDP broadcaster in
// `lan_push_broadcaster.dart`. That covers the "phone is on the same
// Wi-Fi as the rig" case. The OTHER half — phone on cellular, hours
// away from the rig — needs an actual cloud push (FCM/APNs).
//
// We deliberately leave the cloud-side wiring *unimplemented* in this
// patch because:
//   - FCM requires a Firebase project, a service-account JSON or legacy
//     server key, and a per-app registration step on the device.
//   - APNs requires an Apple Developer Program membership, an APNs
//     auth-key (.p8), team ID, and a per-app token-based or
//     certificate-based pipeline.
//
// Both of those are *operator* setup steps, not code we can ship
// inside Nightshade. The audit explicitly asked for "integration
// points, don't implement the cloud-side wiring."
//
// What this file provides:
//   - The [RemotePushDelivery] abstract surface used by the headless
//     API server.
//   - Two concrete subclasses ([FcmRemotePushDelivery],
//     [ApnsRemotePushDelivery]) that throw [UnimplementedError] with
//     a doc-link message so it's obvious where to plug in.
//   - A [CompositeRemotePushDelivery] that fans out to multiple
//     deliveries so an operator can run FCM + APNs side-by-side once
//     both are wired.
//
// See `docs/remote-control.md#critical-push-notifications-fcm-apns`
// for the operator setup instructions.

import 'dart:async';

import 'lan_push_broadcaster.dart';

/// Abstract surface for delivering a [PushNotificationFrame] outside
/// the LAN — typically via FCM for Android or APNs for iOS. The
/// headless API server registers an implementation via
/// [HeadlessApiServer.setRemotePushDelivery] (see headless_api_server.dart);
/// frames that flow through the WebSocket fan-out are additionally
/// handed off here.
///
/// Implementations MUST be safe to call from the headless event loop —
/// they should not block. Use a `Future` for the per-frame work.
///
/// Errors:
///   - Implementations may throw on a misconfigured cloud account
///     (invalid key, expired credential). The headless server catches
///     these per-frame so one bad credential does not kill the
///     broadcaster.
abstract class RemotePushDelivery {
  /// Deliver [frame] to the cellular/remote channel. Implementations
  /// are responsible for matching `frame.severity` to the cloud-push
  /// priority field (FCM `priority`, APNs `apns-priority`).
  Future<void> deliver(PushNotificationFrame frame);

  /// Release any cloud-SDK handles. Idempotent. Called when the
  /// headless server stops.
  Future<void> dispose() async {}
}

/// Stub Firebase Cloud Messaging implementation.
///
/// **Not implemented.** Calling [deliver] throws [UnimplementedError]
/// with the doc reference. To enable FCM:
///
///   1. Create a Firebase project (https://console.firebase.google.com)
///      and download the service-account JSON.
///   2. Add the Firebase Cloud Messaging dependency to the headless
///      desktop runtime (server-side; not the mobile companion's
///      `firebase_messaging` — that's the *receiver* side).
///   3. Subclass [FcmRemotePushDelivery] and override [deliver] to call
///      the FCM HTTP v1 API: POST to
///      `https://fcm.googleapis.com/v1/projects/<projectId>/messages:send`
///      with an OAuth2 access token derived from the service account.
///   4. Pass the instance to `HeadlessApiServer.setRemotePushDelivery`.
///
/// See `docs/remote-control.md#critical-push-notifications-fcm-apns`
/// for the full procedure, including how Nightshade clients should
/// register their FCM device token via `POST /api/push/register-fcm`.
class FcmRemotePushDelivery implements RemotePushDelivery {
  @override
  Future<void> deliver(PushNotificationFrame frame) {
    throw UnimplementedError(
      'FcmRemotePushDelivery.deliver: FCM integration requires a '
      'Firebase project + service-account configuration. '
      'See docs/remote-control.md#critical-push-notifications-fcm-apns '
      'for the operator setup procedure. The LAN UDP broadcaster '
      'continues to work without FCM; only cellular delivery '
      'requires this hookup.',
    );
  }

  @override
  Future<void> dispose() async {}
}

/// Stub Apple Push Notification service implementation.
///
/// **Not implemented.** Calling [deliver] throws [UnimplementedError]
/// with the doc reference. To enable APNs:
///
///   1. In the Apple Developer Console, generate an APNs auth key
///      (.p8) and note the Key ID + Team ID + Bundle ID.
///   2. Add a JWT signer (apns + ES256) to the desktop runtime.
///   3. Subclass [ApnsRemotePushDelivery] and override [deliver] to
///      POST to `https://api.push.apple.com/3/device/<deviceToken>`
///      with the per-frame JSON payload and `apns-push-type: alert`.
///      Set `apns-priority: 10` for critical, `5` for warning.
///   4. Pass the instance to `HeadlessApiServer.setRemotePushDelivery`.
///
/// Nightshade also needs the
/// `com.apple.developer.usernotifications.critical-alerts` entitlement
/// on the mobile companion build (already prepped in Wave 1D). Without
/// it, an APNs-delivered "critical" alert falls back to "default"
/// interruption level and does NOT bypass Do Not Disturb. See
/// `apps/mobile/ios/CRITICAL_ALERTS_SETUP.md`.
class ApnsRemotePushDelivery implements RemotePushDelivery {
  @override
  Future<void> deliver(PushNotificationFrame frame) {
    throw UnimplementedError(
      'ApnsRemotePushDelivery.deliver: APNs integration requires an '
      'Apple Developer Program membership and an APNs auth key (.p8). '
      'See docs/remote-control.md#critical-push-notifications-fcm-apns '
      'for the operator setup procedure. The LAN UDP broadcaster '
      'continues to work without APNs; only cellular delivery '
      'requires this hookup.',
    );
  }

  @override
  Future<void> dispose() async {}
}

/// Fan-out delivery that forwards each frame to every wrapped
/// implementation. Lets an operator run FCM + APNs in parallel — one
/// instance per platform, both registered on the same server.
class CompositeRemotePushDelivery implements RemotePushDelivery {
  final List<RemotePushDelivery> deliveries;

  CompositeRemotePushDelivery(this.deliveries);

  @override
  Future<void> deliver(PushNotificationFrame frame) async {
    final futures = <Future<void>>[];
    for (final d in deliveries) {
      futures.add(d.deliver(frame));
    }
    // Wait for all but don't let one failure mask the others. The
    // headless server's outer try/catch logs each error individually
    // by catching at this boundary.
    await Future.wait(futures, eagerError: false);
  }

  @override
  Future<void> dispose() async {
    for (final d in deliveries) {
      try {
        await d.dispose();
      } catch (_) {
        // dispose() errors are not actionable at the composite level;
        // each delivery is responsible for its own clean shutdown.
      }
    }
  }
}
