import 'package:nightshade_hub/nightshade_hub.dart';
import 'package:test/test.dart';

void main() {
  group('PasswordHasher', () {
    // Low iteration count keeps the test fast; production uses the default.
    final hasher = PasswordHasher(iterations: 1000);

    test('verifies a correct password and rejects a wrong one', () {
      final stored = hasher.hash('correct horse battery staple');
      expect(hasher.verify('correct horse battery staple', stored), isTrue);
      expect(hasher.verify('Tr0ub4dor&3', stored), isFalse);
    });

    test('two hashes of the same password differ (random salt)', () {
      final a = hasher.hash('same');
      final b = hasher.hash('same');
      expect(a, isNot(equals(b)));
      expect(hasher.verify('same', a), isTrue);
      expect(hasher.verify('same', b), isTrue);
    });

    test('malformed stored value never authenticates', () {
      expect(hasher.verify('x', 'not-a-real-hash'), isFalse);
      expect(hasher.verify('x', r'pbkdf2-sha256$abc$def'), isFalse);
      expect(hasher.verify('x', ''), isFalse);
    });
  });

  group('TokenService + AccountService', () {
    late HubDatabase db;
    late TokenService tokens;
    late AccountService accounts;

    setUp(() {
      db = HubDatabase.open(':memory:');
      tokens = TokenService(db);
      accounts = AccountService(
        db,
        tokens,
        hasher: PasswordHasher(iterations: 1000),
      );
    });

    tearDown(() => db.dispose());

    test('signup issues a resolvable contribute token', () {
      final result = accounts.signup(
        publicKey: 'pk-1',
        displayName: 'Alice',
        password: 'pw',
      );
      expect(result.account.trust, AccountService.defaultTrust);
      final identity = tokens.resolve(result.bearerToken);
      expect(identity, isNotNull);
      expect(identity!.accountId, result.account.id);
      expect(identity.scope, HubScope.contribute);
    });

    test('duplicate public key conflicts', () {
      accounts.signup(publicKey: 'pk-1', displayName: 'Alice');
      expect(
        () => accounts.signup(publicKey: 'pk-1', displayName: 'Bob'),
        throwsA(isA<AccountConflict>()),
      );
    });

    test('login with right password issues a token, wrong returns null', () {
      accounts.signup(publicKey: 'pk-1', displayName: 'Alice', password: 'pw');
      expect(accounts.login(publicKey: 'pk-1', password: 'pw'), isNotNull);
      expect(accounts.login(publicKey: 'pk-1', password: 'nope'), isNull);
      expect(accounts.login(publicKey: 'pk-x', password: 'pw'), isNull);
    });

    test('admin scope satisfies lower scopes', () {
      expect(HubScope.admin.satisfies(HubScope.read), isTrue);
      expect(HubScope.admin.satisfies(HubScope.contribute), isTrue);
      expect(HubScope.contribute.satisfies(HubScope.admin), isFalse);
      expect(HubScope.read.satisfies(HubScope.contribute), isFalse);
    });

    test('unknown token resolves to null', () {
      expect(tokens.resolve('deadbeef'), isNull);
    });

    test('expired token is purged on resolve', () {
      final result = accounts.signup(publicKey: 'pk', displayName: 'A');
      // Issue an already-expired token directly.
      final expired = tokens.issue(
        accountId: result.account.id,
        scope: HubScope.read,
        lifetime: const Duration(milliseconds: -1),
      );
      expect(tokens.resolve(expired), isNull);
    });
  });

  group('LoginThrottle (per-account lockout)', () {
    test('locks an account after maxFailures within the window', () {
      final throttle = LoginThrottle(
        maxFailures: 3,
        window: const Duration(minutes: 15),
        lockout: const Duration(minutes: 15),
      );
      final t0 = DateTime(2026, 6, 20, 22);
      expect(throttle.isLocked('pk', now: t0), isFalse);
      expect(throttle.recordFailure('pk', now: t0), isFalse);
      expect(throttle.recordFailure('pk', now: t0), isFalse);
      // The third failure trips the lock.
      expect(throttle.recordFailure('pk', now: t0), isTrue);
      expect(throttle.isLocked('pk', now: t0), isTrue);
      expect(throttle.retryAfterSeconds('pk', now: t0), greaterThan(0));
    });

    test('lockout expires after the lockout duration', () {
      final throttle = LoginThrottle(
        maxFailures: 2,
        lockout: const Duration(minutes: 10),
        window: const Duration(minutes: 10),
      );
      final t0 = DateTime(2026, 6, 20, 22);
      throttle.recordFailure('pk', now: t0);
      throttle.recordFailure('pk', now: t0);
      expect(throttle.isLocked('pk', now: t0), isTrue);
      final later = t0.add(const Duration(minutes: 11));
      expect(throttle.isLocked('pk', now: later), isFalse);
    });

    test('a success clears the failure counter', () {
      final throttle = LoginThrottle(maxFailures: 3);
      final t0 = DateTime(2026, 6, 20, 22);
      throttle.recordFailure('pk', now: t0);
      throttle.recordFailure('pk', now: t0);
      throttle.recordSuccess('pk');
      // Two fresh failures should not yet lock (counter was reset).
      expect(throttle.recordFailure('pk', now: t0), isFalse);
      expect(throttle.recordFailure('pk', now: t0), isFalse);
      expect(throttle.isLocked('pk', now: t0), isFalse);
    });

    test('lockout is per-account, not shared across accounts', () {
      final throttle = LoginThrottle(maxFailures: 2);
      final t0 = DateTime(2026, 6, 20, 22);
      throttle.recordFailure('victim', now: t0);
      throttle.recordFailure('victim', now: t0);
      expect(throttle.isLocked('victim', now: t0), isTrue);
      // A different account is unaffected — the lock does not bleed across keys.
      expect(throttle.isLocked('other', now: t0), isFalse);
    });
  });

  group('secret policy', () {
    test('rejects known placeholders and short/low-variety secrets', () {
      expect(secretWeakness('change-me'), isNotNull);
      expect(secretWeakness('CHANGE-ME'), isNotNull); // case-insensitive
      expect(secretWeakness('secret'), isNotNull);
      expect(secretWeakness('short'), isNotNull); // too short
      expect(
        secretWeakness('aaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
        isNotNull,
      ); // variety
      expect(secretWeakness(''), isNotNull);
    });

    test('accepts a high-entropy secret', () {
      expect(secretWeakness('nshub-3f9a2b7c1d8e4f06a5b9c2d1e0f3a4b5'), isNull);
      expect(secretWeakness('correct horse battery staple 42!!'), isNull);
    });
  });

  group('trust model', () {
    test('no history sits at the prior', () {
      final t = computeTrust(
        meanResidual: null,
        acceptedFrames: 0,
        rejectedFrames: 0,
      );
      expect(t, closeTo(AccountService.defaultTrust, 1e-9));
    });

    test('clean low-residual contributor earns trust up', () {
      final t = computeTrust(
        meanResidual: 0.1,
        acceptedFrames: 500,
        rejectedFrames: 0,
      );
      expect(t, greaterThan(0.9));
    });

    test('a poisoner is driven toward the floor', () {
      final t = computeTrust(
        meanResidual: 8.0,
        acceptedFrames: 0,
        rejectedFrames: 100,
      );
      expect(t, lessThan(0.1));
      expect(t, greaterThanOrEqualTo(0.05));
    });
  });
}
