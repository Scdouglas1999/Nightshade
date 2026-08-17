// How a session resolves to something the Darkroom can open.
//
// This is what the Analytics session dialog and the Stack Result header both
// lean on. The failure it guards against is a "Refine in Darkroom" control that
// opens an empty editor: a night that was never integrated, a master still
// accumulating with no FITS written, or a remote client with no access to the
// host's disk each has to produce a sentence, not a blank screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/utils/darkroom_navigation.dart';
import 'package:nightshade_core/nightshade_core.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _PinnedBackend extends BackendNotifier {
  _PinnedBackend(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

/// A resolver that answers with a scripted set instead of reading a database.
class _ScriptedResolver implements DawnMasterResolver {
  _ScriptedResolver(this.set);

  final DawnMasterSet set;

  @override
  Future<DawnMasterSet> resolve(int sessionId) async => set;
}

DawnMaster _master(int id) => DawnMaster(
      masterId: id,
      targetId: 1,
      name: 'M31 Ha',
      filter: 'Ha',
      masterFitsPath: '/masters/m31_ha.fits',
      channels: 1,
      width: 4000,
      height: 3000,
      frameCount: 40,
      totalIntegrationSeconds: 12000,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Run [body] with a WidgetRef from a mounted Consumer.
  Future<T> withRef<T>(
    WidgetTester tester,
    List<Override> overrides,
    Future<T> Function(WidgetRef ref) body,
  ) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    return body(captured);
  }

  testWidgets('a night with a master resolves to that master', (tester) async {
    final target = await withRef(
      tester,
      [
        backendProvider.overrideWith(
          (ref) => _PinnedBackend(ref, DisconnectedBackend()),
        ),
        dawnMasterResolverProvider.overrideWithValue(
          _ScriptedResolver(
            DawnMasterSet(
              sessionId: 3,
              masters: [_master(11), _master(12)],
              withoutFile: const [],
            ),
          ),
        ),
      ],
      (ref) => resolveDarkroomTargetForSession(ref, 3),
    );

    expect(target.masterId, 11);
    expect(target.unavailableReason, isNull);
  });

  testWidgets('a remote client is told where the Darkroom lives', (
    tester,
  ) async {
    final target = await withRef(
      tester,
      [
        backendProvider.overrideWith(
          (ref) => _PinnedBackend(ref, _MockNetworkBackend()),
        ),
        dawnMasterResolverProvider.overrideWithValue(
          _ScriptedResolver(
            DawnMasterSet(
              sessionId: 3,
              masters: [_master(11)],
              withoutFile: const [],
            ),
          ),
        ),
      ],
      (ref) => resolveDarkroomTargetForSession(ref, 3),
    );

    expect(target.masterId, isNull);
    expect(target.unavailableReason, contains('imaging host'));
  });

  testWidgets('a night that was never integrated says so', (tester) async {
    final target = await withRef(
      tester,
      [
        backendProvider.overrideWith(
          (ref) => _PinnedBackend(ref, DisconnectedBackend()),
        ),
        dawnMasterResolverProvider.overrideWithValue(
          _ScriptedResolver(
            const DawnMasterSet(
              sessionId: 3,
              masters: [],
              withoutFile: [],
            ),
          ),
        ),
      ],
      (ref) => resolveDarkroomTargetForSession(ref, 3),
    );

    expect(target.masterId, isNull);
    expect(target.unavailableReason, contains('no integrated master yet'));
  });

  testWidgets('an accumulating master repeats the resolver\'s own reason', (
    tester,
  ) async {
    final target = await withRef(
      tester,
      [
        backendProvider.overrideWith(
          (ref) => _PinnedBackend(ref, DisconnectedBackend()),
        ),
        dawnMasterResolverProvider.overrideWithValue(
          _ScriptedResolver(
            const DawnMasterSet(
              sessionId: 3,
              masters: [],
              withoutFile: [
                DawnMasterWithoutFile(
                  masterId: 4,
                  name: 'M31 Ha',
                  reason: 'this master is still accumulating',
                ),
              ],
            ),
          ),
        ),
      ],
      (ref) => resolveDarkroomTargetForSession(ref, 3),
    );

    expect(target.masterId, isNull);
    expect(
        target.unavailableReason, 'M31 Ha: this master is still accumulating.');
  });
}
