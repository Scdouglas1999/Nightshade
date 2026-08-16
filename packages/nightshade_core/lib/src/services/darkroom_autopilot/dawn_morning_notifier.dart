/// The morning notification: the one message a dawn job sends.
///
/// It goes out through [NotificationService.notify], which is the seam that
/// fans a message out to the unified [NotificationRouter] (and from there to
/// the phone through `SystemPushTransport`, the documented sole producer of
/// mobile pushes) as well as the legacy Discord/Pushover webhooks. Enqueuing a
/// push directly here would bypass the router, which is how the existing
/// "master ready" push became unroutable and unmutable; this path does not
/// repeat that.
///
/// **The gate is reported, never worked around.** `notificationsEnabled` and
/// `notifyOnSequenceComplete` are live delivery gates on
/// [NotificationEvent.sequenceComplete], the family the end of a night's
/// processing belongs to. When either is off the job records that the operator
/// turned it off and names the flag — it does not reroute through an ungated
/// event family to make the message arrive anyway.
library;

import '../../providers/settings_provider.dart';
import '../notification_service.dart';
import 'dawn_job_report.dart';

/// Sends the morning message for a finished dawn job.
abstract class DawnMorningNotifier {
  /// Announce [report]. Returns what happened, including the reason nothing
  /// was sent.
  Future<DawnNotificationDecision> announce(DawnJobReport report);
}

/// The production notifier: one [NotificationService.notify] call, gated by the
/// operator's own event flags.
class NotificationServiceDawnNotifier implements DawnMorningNotifier {
  final NotificationService _notifications;
  final AppSettingsState? Function() _settings;

  const NotificationServiceDawnNotifier({
    required NotificationService notifications,
    required AppSettingsState? Function() settings,
  }) : _notifications = notifications,
       _settings = settings;

  @override
  Future<DawnNotificationDecision> announce(DawnJobReport report) async {
    final settings = _settings();
    if (settings == null) {
      return const DawnNotificationDecision(
        sent: false,
        reason:
            'The notification settings have not loaded, so no gate could be '
            'read and nothing was sent.',
      );
    }
    if (!settings.notificationsEnabled) {
      return const DawnNotificationDecision(
        sent: false,
        reason:
            'Notifications are switched off in Settings, so the morning '
            'message was not sent.',
      );
    }
    if (!settings.notifyOnSequenceComplete) {
      return const DawnNotificationDecision(
        sent: false,
        reason:
            'The "Sequence Complete" event alert is switched off, and the end '
            'of the night\'s processing belongs to that family, so the '
            'morning message was not sent.',
      );
    }

    final accepted = await _notifications.notify(
      event: NotificationEvent.sequenceComplete,
      title: report.headline,
      message: report.body,
    );
    return DawnNotificationDecision(
      sent: true,
      reason: accepted
          ? 'Sent through the notification router and accepted by at least '
                'one configured webhook.'
          : 'Sent through the notification router, which fans it out to the '
                'routed transports including the phone; no Discord or '
                'Pushover webhook accepted it, because none is configured or '
                'both refused.',
    );
  }
}
