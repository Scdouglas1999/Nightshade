import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/auth_policy.dart';

void main() {
  group('headless token scope parsing', () {
    test('accepts documented scope aliases', () {
      expect(parseHeadlessTokenScope('view-only'), HeadlessTokenScope.view);
      expect(
        parseHeadlessTokenScope('imaging-control'),
        HeadlessTokenScope.control,
      );
      expect(parseHeadlessTokenScope('admin'), HeadlessTokenScope.admin);
    });

    test('rejects unknown scopes', () {
      expect(parseHeadlessTokenScope('operator'), isNull);
      expect(parseHeadlessTokenScope(null), isNull);
    });
  });

  group('headless auth policy', () {
    test('view tokens can read ordinary status endpoints and events', () {
      expect(
        HeadlessAuthPolicy.allows(
          actual: HeadlessTokenScope.view,
          method: 'GET',
          path: '/api/status',
        ),
        isTrue,
      );
      expect(
        HeadlessAuthPolicy.allows(
          actual: HeadlessTokenScope.view,
          method: 'WS',
          path: '/events',
        ),
        isTrue,
      );
    });

    test('view tokens cannot issue control commands or browse files', () {
      expect(
        HeadlessAuthPolicy.allows(
          actual: HeadlessTokenScope.view,
          method: 'POST',
          path: '/api/camera/expose',
        ),
        isFalse,
      );
      expect(
        HeadlessAuthPolicy.allows(
          actual: HeadlessTokenScope.view,
          method: 'GET',
          path: '/api/files/browse',
        ),
        isFalse,
      );
    });

    test('control tokens can operate devices but not administer backups', () {
      expect(
        HeadlessAuthPolicy.allows(
          actual: HeadlessTokenScope.control,
          method: 'POST',
          path: '/api/mount/slew',
        ),
        isTrue,
      );
      expect(
        HeadlessAuthPolicy.allows(
          actual: HeadlessTokenScope.control,
          method: 'POST',
          path: '/api/backup/restore',
        ),
        isFalse,
      );
    });

    test('admin tokens can access administrative endpoints', () {
      expect(
        HeadlessAuthPolicy.allows(
          actual: HeadlessTokenScope.admin,
          method: 'POST',
          path: '/api/backup/restore',
        ),
        isTrue,
      );
      expect(
        HeadlessAuthPolicy.allows(
          actual: HeadlessTokenScope.admin,
          method: 'GET',
          path: '/api/self-test',
        ),
        isTrue,
      );
    });
  });
}
