// Wave 5 Agent 5 — NotificationNode explicit-transports round-trip tests.
//
// The model gained an `explicitTransports` field. We need to make sure:
//   * Default construction = null (legacy nodes inherit the matrix rule).
//   * copyWith honours both "set to value" and "clear via flag".
//   * The Equatable props correctly include the new field (so the
//     sequence editor's dirty-check fires when only this changes).

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  test('NotificationNode default explicitTransports is null', () {
    final n = NotificationNode();
    expect(n.explicitTransports, isNull);
  });

  test('NotificationNode copyWith sets explicitTransports', () {
    final n = NotificationNode();
    final updated = n.copyWith(
      explicitTransports: const [NotificationTransportKind.discord],
    );
    expect(updated.explicitTransports, [NotificationTransportKind.discord]);
  });

  test('NotificationNode copyWith clears explicitTransports', () {
    final n = NotificationNode(
      explicitTransports: const [NotificationTransportKind.discord],
    );
    final updated = n.copyWith(clearExplicitTransports: true);
    expect(updated.explicitTransports, isNull);
  });

  test('NotificationNode equality reflects explicitTransports', () {
    final a = NotificationNode(
      title: 't',
      message: 'm',
      explicitTransports: const [NotificationTransportKind.discord],
    );
    final b = NotificationNode(
      title: 't',
      message: 'm',
      explicitTransports: const [NotificationTransportKind.discord],
      id: a.id,
    );
    expect(a, equals(b));

    final c = NotificationNode(
      title: 't',
      message: 'm',
      explicitTransports: const [NotificationTransportKind.telegram],
      id: a.id,
    );
    expect(a, isNot(equals(c)));
  });
}
