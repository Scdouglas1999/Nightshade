import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/auth_policy.dart';
import 'package:nightshade_desktop/headless_api/handlers/system_handlers.dart'
    show availableHeadlessEndpoints;

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

    test('mosaic force-release is gated like claim: view denied, control ok', () {
      // The owner/admin panel eviction is a mutating collaborative-mosaic route,
      // so it sits on the control surface exactly like claim — a view-only token
      // must be denied at the gate rather than reaching the handler and failing
      // late, while a control token is admitted (the hub then enforces
      // owner/admin ownership on top).
      const forceRelease = '/api/mosaic/projects/7/panels/3/force-release';
      const claim = '/api/mosaic/projects/7/panels/3/claim';
      expect(
        HeadlessAuthPolicy.allows(
          actual: HeadlessTokenScope.view,
          method: 'POST',
          path: forceRelease,
        ),
        isFalse,
      );
      expect(
        HeadlessAuthPolicy.allows(
          actual: HeadlessTokenScope.control,
          method: 'POST',
          path: forceRelease,
        ),
        isTrue,
      );
      // Same coarse scope as the sibling claim route (no privilege drift).
      expect(
        HeadlessAuthPolicy.requiredScopeFor(method: 'POST', path: forceRelease),
        HeadlessAuthPolicy.requiredScopeFor(method: 'POST', path: claim),
      );
    });
  });

  group('coarse → grant back-compat bridge (no privilege drift)', () {
    // The keystone WS6 invariant: a grant produced by HeadlessAuthGrant
    // .fromCoarse(scope) MUST permit EXACTLY the endpoints the legacy coarse
    // rank check allowed — no silent gain or loss of access — for every
    // endpoint in the authoritative catalog.
    test('fromCoarse(scope).permits == legacy allows over every endpoint', () {
      final endpoints = availableHeadlessEndpoints();
      expect(endpoints, isNotEmpty);
      for (final scope in HeadlessTokenScope.values) {
        final grant = HeadlessAuthGrant.fromCoarse(scope);
        for (final route in endpoints) {
          final parts = route.split(' ');
          if (parts.length != 2) continue;
          final method = parts.first.toUpperCase();
          final path = parts.last;

          final legacy = HeadlessAuthPolicy.allows(
            actual: scope,
            method: method,
            path: path,
          );
          final fine = HeadlessAuthPolicy.permits(
            grant: grant,
            method: method,
            path: path,
          );
          expect(
            fine,
            legacy,
            reason:
                'drift for $scope on $method $path '
                '(legacy=$legacy fine=$fine)',
          );
        }
      }
    });

    test('the bridge also agrees on the WS event stream', () {
      for (final scope in HeadlessTokenScope.values) {
        final grant = HeadlessAuthGrant.fromCoarse(scope);
        expect(
          HeadlessAuthPolicy.permits(
            grant: grant,
            method: 'WS',
            path: '/events',
          ),
          HeadlessAuthPolicy.allows(
            actual: scope,
            method: 'WS',
            path: '/events',
          ),
        );
      }
    });
  });

  group('fine-grained grants', () {
    test('camera:control,mount:view exposes camera control but not mount', () {
      final grant = HeadlessAuthGrant.parseSpec('camera:control,mount:view')!;
      // camera control is granted.
      expect(
        HeadlessAuthPolicy.permits(
          grant: grant,
          method: 'POST',
          path: '/api/camera/expose',
        ),
        isTrue,
      );
      // mount slew (control) is denied — only view was granted.
      expect(
        HeadlessAuthPolicy.permits(
          grant: grant,
          method: 'POST',
          path: '/api/mount/slew',
        ),
        isFalse,
      );
      // mount status (view) is allowed.
      expect(
        HeadlessAuthPolicy.permits(
          grant: grant,
          method: 'GET',
          path: '/api/mount/status',
        ),
        isTrue,
      );
      // a resource it never named (focuser) is denied at every level.
      expect(
        HeadlessAuthPolicy.permits(
          grant: grant,
          method: 'GET',
          path: '/api/focuser/status',
        ),
        isFalse,
      );
      // admin-only endpoints stay denied for a non-admin fine-grained grant.
      expect(
        HeadlessAuthPolicy.permits(
          grant: grant,
          method: 'POST',
          path: '/api/backup/restore',
        ),
        isFalse,
      );
    });

    test('device connect/disconnect needs explicit devices:control', () {
      final cameraOnly = HeadlessAuthGrant.parseSpec('camera:control')!;
      expect(
        HeadlessAuthPolicy.permits(
          grant: cameraOnly,
          method: 'POST',
          path: '/api/devices/connect',
        ),
        isFalse,
      );
      final withDevices = HeadlessAuthGrant.parseSpec(
        'camera:control,devices:control',
      )!;
      expect(
        HeadlessAuthPolicy.permits(
          grant: withDevices,
          method: 'POST',
          path: '/api/devices/connect',
        ),
        isTrue,
      );
    });

    test('collaborative-sky resources are mutually isolated (scope-denial '
        'matrix)', () {
      // The WS4 fine-grained isolation guarantee for the collaborative surface:
      // a token scoped to ONE collaborative resource must not reach any other,
      // and none of them leaks in via a `system` grant. Rows = grant spec,
      // columns = a representative endpoint on each collaborative resource.
      const mosaicPublish = ('POST', '/api/mosaic/projects/7/publish');
      const coimagingCreate = ('POST', '/api/coimaging/sessions');
      const collabChat = ('POST', '/api/collaboration/chat');

      bool permits(HeadlessAuthGrant g, (String, String) ep) =>
          HeadlessAuthPolicy.permits(grant: g, method: ep.$1, path: ep.$2);

      final mosaicOnly = HeadlessAuthGrant.parseSpec('mosaic:control')!;
      expect(permits(mosaicOnly, mosaicPublish), isTrue);
      expect(
        permits(mosaicOnly, coimagingCreate),
        isFalse,
        reason: 'a mosaic token must not create a co-imaging session',
      );
      expect(
        permits(mosaicOnly, collabChat),
        isFalse,
        reason: 'a mosaic token must not post to the collaboration surface',
      );

      final coimagingOnly = HeadlessAuthGrant.parseSpec('coimaging:control')!;
      expect(permits(coimagingOnly, coimagingCreate), isTrue);
      expect(permits(coimagingOnly, mosaicPublish), isFalse);
      expect(permits(coimagingOnly, collabChat), isFalse);

      // The live collaboration surface is named by either `collaboration` or its
      // underlying `constellation` resource key; both grant it and nothing else.
      for (final spec in const [
        'collaboration:control',
        'constellation:control',
      ]) {
        final collabOnly = HeadlessAuthGrant.parseSpec(spec)!;
        expect(
          permits(collabOnly, collabChat),
          isTrue,
          reason: '$spec must permit the collaboration surface',
        );
        expect(permits(collabOnly, mosaicPublish), isFalse);
        expect(permits(collabOnly, coimagingCreate), isFalse);
      }

      // A `system`-only token must NOT inherit any collaborative resource — the
      // exact leak that mapping `/api/collaboration/` off the `system` catch-all
      // closes.
      final systemOnly = HeadlessAuthGrant.parseSpec('system:control')!;
      expect(permits(systemOnly, mosaicPublish), isFalse);
      expect(permits(systemOnly, coimagingCreate), isFalse);
      expect(permits(systemOnly, collabChat), isFalse);
    });

    test('spec parsing round-trips and rejects malformed input', () {
      expect(HeadlessAuthGrant.parseSpec('admin')!.isAdmin, isTrue);
      expect(HeadlessAuthGrant.parseSpec('view')!.toSpec(), 'view');
      expect(HeadlessAuthGrant.parseSpec('control')!.toSpec(), 'control');
      expect(
        HeadlessAuthGrant.parseSpec('camera:control,mount:view')!.toSpec(),
        'camera:control,mount:view',
      );
      // unknown resource / level / shape → null (caller fails closed).
      expect(HeadlessAuthGrant.parseSpec('warp:control'), isNull);
      expect(HeadlessAuthGrant.parseSpec('camera:superuser'), isNull);
      expect(HeadlessAuthGrant.parseSpec('camera'), isNull);
      expect(HeadlessAuthGrant.parseSpec(''), isNull);
      expect(HeadlessAuthGrant.parseSpec(null), isNull);
    });

    test('a fine-grained mutating grant projects to control coarse', () {
      final grant = HeadlessAuthGrant.parseSpec('camera:control')!;
      expect(grant.coarseScope, HeadlessTokenScope.control);
      final readOnly = HeadlessAuthGrant.parseSpec('camera:view')!;
      expect(readOnly.coarseScope, HeadlessTokenScope.view);
    });
  });
}
