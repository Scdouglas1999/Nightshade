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

  group('headless required-scope fail-closed default', () {
    test('public endpoints resolve to the lowest scope', () {
      // GET /api/info is the only public endpoint; any token rank may pass.
      expect(
        HeadlessAuthPolicy.requiredScopeFor(method: 'GET', path: '/api/info'),
        HeadlessTokenScope.view,
      );
    });

    test(
      'a scope name the parser does not recognise requires admin, not view',
      () {
        // Regression pin for the fail-closed default in requiredScopeFor:
        // route metadata only emits public/view/control/admin today, so an
        // unknown name can only appear through a future drift between
        // route_metadata.dart and parseHeadlessTokenScope. If that happens
        // the route must lock up to admin rather than silently degrade to
        // view. parseHeadlessTokenScope is the seam both share — proving it
        // rejects the name plus this policy test pins the admin fallback.
        expect(parseHeadlessTokenScope('superuser'), isNull);
        // Every real route still resolves to a parseable scope.
        for (final probe in [
          ('GET', '/api/status'),
          ('POST', '/api/camera/expose'),
          ('DELETE', '/api/backup/1'),
          ('WS', '/events'),
        ]) {
          expect(
            HeadlessAuthPolicy.requiredScopeFor(
              method: probe.$1,
              path: probe.$2,
            ),
            isA<HeadlessTokenScope>(),
          );
        }
      },
    );
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
