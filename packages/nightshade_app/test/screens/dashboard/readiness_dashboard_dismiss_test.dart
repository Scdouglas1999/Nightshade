// Tests for the dashboard readiness-card dismissal (Polish #2).
//
// The user reported the dashboard "warnings" surface felt intrusive because it
// could not be dismissed — it only auto-collapsed once the rig was fully ready.
// The fix adds a session-scoped, issue-signature-keyed dismissal:
//   * readinessIssueSignature(report)   — stable id of the outstanding-issue set
//   * readinessCardDismissedProvider    — the signature the user last waved off
//   * readinessCardVisibleProvider      — show iff not-ready AND not-dismissed
//
// The key behavioural guarantee — and the reason for keying on a signature
// rather than a plain bool — is that dismissing the CURRENT warnings must NOT
// permanently silence a genuinely NEW problem. These tests pin that.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/widgets/readiness_dashboard_card.dart';
import 'package:nightshade_core/nightshade_core.dart';

ReadinessReport _report(List<ReadinessItem> items) => ReadinessReport(items: items);

const _ready = ReadinessItem(
  id: ReadinessItemId.location,
  title: 'Location',
  detail: 'ok',
  level: ReadinessLevel.ready,
);

const _locationBlocked = ReadinessItem(
  id: ReadinessItemId.location,
  title: 'Location',
  detail: 'No observing location set.',
  level: ReadinessLevel.blocked,
);

const _solverCaution = ReadinessItem(
  id: ReadinessItemId.plateSolver,
  title: 'Plate solver',
  detail: 'Not configured.',
  level: ReadinessLevel.caution,
);

ProviderContainer _containerFor(ReadinessReport report) {
  final c = ProviderContainer(
    overrides: [readinessReportProvider.overrideWithValue(report)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('readinessIssueSignature', () {
    test('is identical for the same outstanding-issue set', () {
      final a = readinessIssueSignature(_report([_locationBlocked, _solverCaution]));
      // Order of items must not matter — signature sorts ids.
      final b = readinessIssueSignature(_report([_solverCaution, _locationBlocked]));
      expect(a, b);
    });

    test('differs when a new issue appears', () {
      final before = readinessIssueSignature(_report([_locationBlocked]));
      final after =
          readinessIssueSignature(_report([_locationBlocked, _solverCaution]));
      expect(before, isNot(after));
    });
  });

  group('readinessCardVisibleProvider', () {
    test('a fully-ready report hides the card', () {
      final c = _containerFor(_report([_ready]));
      expect(c.read(readinessCardVisibleProvider), isFalse);
    });

    test('an outstanding issue shows the card by default', () {
      final c = _containerFor(_report([_locationBlocked]));
      expect(c.read(readinessCardVisibleProvider), isTrue);
    });

    test('dismissing the current issue set hides the card', () {
      final report = _report([_locationBlocked]);
      final c = _containerFor(report);
      expect(c.read(readinessCardVisibleProvider), isTrue);

      c.read(readinessCardDismissedProvider.notifier).state =
          readinessIssueSignature(report);

      expect(c.read(readinessCardVisibleProvider), isFalse,
          reason: 'After dismissing the exact issue signature the card hides.');
    });

    test('a NEW issue re-surfaces the card despite an earlier dismissal', () {
      // User dismisses the location warning...
      final first = _report([_locationBlocked]);
      final c = _containerFor(first);
      c.read(readinessCardDismissedProvider.notifier).state =
          readinessIssueSignature(first);
      expect(c.read(readinessCardVisibleProvider), isFalse);

      // ...then a second, different problem arises. The stored signature no
      // longer matches, so the card must reappear — a dismissal must never
      // permanently silence genuinely new warnings.
      final c2 = ProviderContainer(
        overrides: [
          readinessReportProvider
              .overrideWithValue(_report([_locationBlocked, _solverCaution])),
        ],
      );
      addTearDown(c2.dispose);
      c2.read(readinessCardDismissedProvider.notifier).state =
          readinessIssueSignature(first);

      expect(c2.read(readinessCardVisibleProvider), isTrue,
          reason: 'A new issue set yields a new signature → card re-shows.');
    });
  });
}
