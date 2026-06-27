// Cross-package parity test for the Nightshade version-compatibility policy.
//
// Two halves of the mobile connect flow gate on the policy:
//   * the pre-flight check uses NightshadeServerCompatibility (in
//     nightshade_remote_protocol), and
//   * the NetworkBackend WS-handshake gate uses RemoteApiCompatibility (in
//     nightshade_core).
//
// RemoteApiCompatibility now delegates to NightshadeServerCompatibility, so the
// two are structurally a single source of truth. This test is the standing
// guard that the delegation stays faithful: if anyone re-forks the policy, the
// constants or per-version verdicts diverge and this test fails CI.
//
// The mobile package depends on both packages, so it is the natural home for a
// test that imports both (nightshade_remote_protocol must not depend on
// nightshade_core, so the parity test cannot live there).

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';

void main() {
  group('RemoteApiCompatibility <-> NightshadeServerCompatibility parity', () {
    test('policy constants agree', () {
      expect(
        RemoteApiCompatibility.apiVersionHeader,
        NightshadeServerCompatibility.apiVersionHeader,
      );
      expect(
        RemoteApiCompatibility.minimumSupportedVersion.format(),
        NightshadeServerCompatibility.minimumSupportedVersion.format(),
      );
      expect(
        RemoteApiCompatibility.serverApiVersion.format(),
        NightshadeServerCompatibility.serverApiVersion.format(),
      );
      expect(
        RemoteApiCompatibility.clientApiVersion.format(),
        NightshadeServerCompatibility.clientApiVersion.format(),
      );
    });

    // A sweep that crosses every decision boundary: below-floor, exactly the
    // floor, in-band patch/minor, exactly the current, next-major, malformed,
    // and null.
    const versions = <String?>[
      null,
      '',
      'not-a-version',
      '1.9.9',
      '2.3.9',
      '2.4.0',
      '2.5.0',
      '2.6.0',
      '2.6.1',
      'v2.9.1+build.42',
      '3.0.0',
      '4.2.1',
    ];

    test('check() returns the same verdict + code for every version', () {
      for (final v in versions) {
        final core = RemoteApiCompatibility.check(v);
        final proto = NightshadeServerCompatibility.check(v);
        expect(
          core.isCompatible,
          proto.isCompatible,
          reason: 'isCompatible mismatch for server version "$v"',
        );
        expect(
          core.code,
          proto.code,
          reason: 'code mismatch for server version "$v"',
        );
        expect(
          core.message,
          proto.message,
          reason: 'message mismatch for server version "$v"',
        );
      }
    });

    test('checkClient() returns the same verdict + code for every version', () {
      for (final v in versions) {
        final core = RemoteApiCompatibility.checkClient(v);
        final proto = NightshadeServerCompatibility.checkClient(v);
        expect(
          core.isCompatible,
          proto.isCompatible,
          reason: 'isCompatible mismatch for client version "$v"',
        );
        expect(
          core.code,
          proto.code,
          reason: 'code mismatch for client version "$v"',
        );
        expect(
          core.message,
          proto.message,
          reason: 'message mismatch for client version "$v"',
        );
      }
    });
  });
}
