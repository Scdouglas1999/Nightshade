/// The ONE rule for "are these two notifications the same statement?".
///
/// ## Why this is shared rather than reimplemented per surface
///
/// WD-EQ-3 survived two waves of fixes because each wave fixed a different
/// place. One failed connect of the built-in guider produces the same refusal
/// from two paths — the Dart connect path via `ErrorService.log` and the
/// backend's error event via `errorNotificationBridgeProvider` — and they differ
/// by ONE character:
///
///   Built-in guider requires an active profile with a guide focal length
///   Built-in guider requires an active profile with a guide focal length.
///
/// F-fix taught [NotificationRouter] to normalize that away. But in-app toasts
/// never pass through the router: both producers call
/// `UiNotificationNotifier.showError` directly, and the toast overlay collapsed
/// on the EXACT strings. So the recipe was right and the surface was wrong, and
/// live the operator still read one refusal twice (Wave G, waveG-01/02/03).
///
/// The rule now lives in one place and every surface that asks "have I already
/// said this?" calls it.
library;

final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _trailingCosmetics = RegExp(r'[\s.,;:!…]+$');

/// Cosmetic-insensitive form of a rendered string, used ONLY as a
/// de-duplication key — never as the copy that is shown.
///
/// Trailing sentence punctuation, case and internal whitespace runs are
/// differences between PRODUCERS of one statement, never differences the
/// operator can act on.
///
/// `?` is deliberately NOT stripped: a question and a statement are different
/// notifications ("Park the mount" is a report; "Park the mount?" is a prompt).
String normalizeNotificationSignature(String value) => value
    .trim()
    .replaceAll(_whitespaceRun, ' ')
    .replaceAll(_trailingCosmetics, '')
    .toLowerCase();

/// The signature of one rendered notification: what the operator SEES, keyed
/// cosmetically-insensitively. [discriminator] separates notifications that
/// share words but not meaning — the severity/level, or a transport kind.
String notificationContentSignature({
  required String discriminator,
  required String title,
  required String body,
}) =>
    '$discriminator|${normalizeNotificationSignature(title)}'
    '|${normalizeNotificationSignature(body)}';
