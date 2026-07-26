/// A truthful snapshot of whether a critical alert can actually be pushed to a
/// phone right now.
///
/// Exists because the "Push critical alerts to mobile" setting used to render
/// as a plain ON switch regardless of whether ANY device could receive a push.
/// On Android that was never true in a stock build: the FCM client is a dormant
/// scaffold pending Firebase provisioning (`google-services.json` is absent),
/// so the phone logs
/// `FCM not configured (no google-services.json); push registration dormant`
/// and never registers a token. The switch therefore asserted a capability the
/// system did not have.
///
/// Two independent things must both hold for a push to land:
///   * at least one paired device has registered a push token
///     ([registeredDeviceCount] > 0), and
///   * the host has a cloud delivery channel configured
///     ([cloudDeliveryConfigured]) — an FCM service account / APNs key, or an
///     explicit mock for local dev.
///
/// [canDeliver] is the single question the UI should ask.
library;

class PushDeliveryTargets {
  /// Paired devices with at least one registered push token.
  final int registeredDeviceCount;

  /// Registered Android (FCM) tokens.
  final int fcmTokenCount;

  /// Registered iOS (APNs) tokens.
  final int apnsTokenCount;

  /// Whether the host has a remote push delivery channel wired at all.
  final bool cloudDeliveryConfigured;

  const PushDeliveryTargets({
    required this.registeredDeviceCount,
    required this.fcmTokenCount,
    required this.apnsTokenCount,
    required this.cloudDeliveryConfigured,
  });

  /// Nothing registered, nothing configured — the honest default before a
  /// host has answered.
  static const PushDeliveryTargets none = PushDeliveryTargets(
    registeredDeviceCount: 0,
    fcmTokenCount: 0,
    apnsTokenCount: 0,
    cloudDeliveryConfigured: false,
  );

  /// Whether a critical alert could actually reach a phone right now.
  bool get canDeliver => registeredDeviceCount > 0 && cloudDeliveryConfigured;

  /// Why delivery is impossible, or `null` when it is possible. Phrased for
  /// direct display to an operator.
  String? get blockedReason {
    if (registeredDeviceCount == 0 && !cloudDeliveryConfigured) {
      return 'No device has registered for push, and this host has no push '
          'delivery configured';
    }
    if (registeredDeviceCount == 0) {
      return 'No paired device has registered for push';
    }
    if (!cloudDeliveryConfigured) {
      return 'This host has no push delivery configured';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'registeredDeviceCount': registeredDeviceCount,
    'fcmTokenCount': fcmTokenCount,
    'apnsTokenCount': apnsTokenCount,
    'cloudDeliveryConfigured': cloudDeliveryConfigured,
    // Derived, but sent so a client cannot drift from the host's own verdict.
    'canDeliver': canDeliver,
  };

  factory PushDeliveryTargets.fromJson(Map<String, dynamic> json) {
    return PushDeliveryTargets(
      registeredDeviceCount:
          (json['registeredDeviceCount'] as num?)?.toInt() ?? 0,
      fcmTokenCount: (json['fcmTokenCount'] as num?)?.toInt() ?? 0,
      apnsTokenCount: (json['apnsTokenCount'] as num?)?.toInt() ?? 0,
      cloudDeliveryConfigured:
          json['cloudDeliveryConfigured'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushDeliveryTargets &&
          other.registeredDeviceCount == registeredDeviceCount &&
          other.fcmTokenCount == fcmTokenCount &&
          other.apnsTokenCount == apnsTokenCount &&
          other.cloudDeliveryConfigured == cloudDeliveryConfigured;

  @override
  int get hashCode => Object.hash(
    registeredDeviceCount,
    fcmTokenCount,
    apnsTokenCount,
    cloudDeliveryConfigured,
  );

  @override
  String toString() =>
      'PushDeliveryTargets(devices: $registeredDeviceCount, '
      'fcm: $fcmTokenCount, apns: $apnsTokenCount, '
      'cloudDeliveryConfigured: $cloudDeliveryConfigured)';
}
