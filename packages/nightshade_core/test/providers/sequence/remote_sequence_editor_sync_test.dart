import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(const Stream<NightshadeEvent>.empty());
    registerFallbackValue(Sequence.create(name: 'fallback', nodes: const {}));
  });

  group('remoteSequenceEditorSyncProvider', () {
    test('debounces saveFullSequence until edits settle', () {
      fakeAsync((async) {
        final backend = _MockNetworkBackend();
        when(
          () => backend.eventStream,
        ).thenAnswer((_) => const Stream<NightshadeEvent>.empty());
        when(
          () => backend.saveFullSequence(
            any(),
            isTemplate: any(named: 'isTemplate'),
            databaseId: any(named: 'databaseId'),
          ),
        ).thenAnswer((_) async => 99);

        final container = ProviderContainer(
          overrides: [
            backendProvider.overrideWith(
              (ref) => _FixedBackendNotifier(ref, backend),
            ),
          ],
        );

        container.read(remoteSequenceEditorSyncProvider);
        final editor = container.read(currentSequenceProvider.notifier);

        const rootId = 'root-remote-sync';
        editor.loadSequence(
          Sequence.create(
            name: 'Draft',
            nodes: {rootId: InstructionSetNode(id: rootId, name: 'Sequence')},
            rootNodeId: rootId,
          ),
        );
        editor.setName('Draft v2');

        async.elapse(const Duration(milliseconds: 500));
        verifyNever(
          () => backend.saveFullSequence(
            any(),
            isTemplate: any(named: 'isTemplate'),
            databaseId: any(named: 'databaseId'),
          ),
        );

        async.elapse(remoteSequenceAutoSaveDebounce);
        async.flushMicrotasks();

        verify(
          () => backend.saveFullSequence(
            any(
              that: predicate<Map<String, dynamic>>(
                (map) => map['name'] == 'Draft v2',
              ),
            ),
            isTemplate: false,
            databaseId: null,
          ),
        ).called(1);

        expect(container.read(currentSequenceProvider)?.databaseId, 99);
        expect(container.read(currentSequenceProvider.notifier).isDirty, false);

        container.dispose();
      });
    });

    test('does not save when sequence is clean after load', () {
      fakeAsync((async) {
        final backend = _MockNetworkBackend();
        when(
          () => backend.eventStream,
        ).thenAnswer((_) => const Stream<NightshadeEvent>.empty());

        final container = ProviderContainer(
          overrides: [
            backendProvider.overrideWith(
              (ref) => _FixedBackendNotifier(ref, backend),
            ),
          ],
        );

        container.read(remoteSequenceEditorSyncProvider);
        final editor = container.read(currentSequenceProvider.notifier);

        const rootId = 'root-clean-load';
        editor.loadSequence(
          Sequence.create(
            name: 'Loaded',
            databaseId: 5,
            nodes: {rootId: InstructionSetNode(id: rootId, name: 'Sequence')},
            rootNodeId: rootId,
          ),
        );

        async.elapse(remoteSequenceAutoSaveDebounce);
        async.flushMicrotasks();

        verifyNever(
          () => backend.saveFullSequence(
            any(),
            isTemplate: any(named: 'isTemplate'),
            databaseId: any(named: 'databaseId'),
          ),
        );

        container.dispose();
      });
    });

    test('saves after createSequence when user adds a node', () {
      fakeAsync((async) {
        final backend = _MockNetworkBackend();
        when(
          () => backend.eventStream,
        ).thenAnswer((_) => const Stream<NightshadeEvent>.empty());
        when(
          () => backend.saveFullSequence(
            any(),
            isTemplate: any(named: 'isTemplate'),
            databaseId: any(named: 'databaseId'),
          ),
        ).thenAnswer((_) async => 11);

        final container = ProviderContainer(
          overrides: [
            backendProvider.overrideWith(
              (ref) => _FixedBackendNotifier(ref, backend),
            ),
          ],
        );

        container.read(remoteSequenceEditorSyncProvider);
        final editor = container.read(currentSequenceProvider.notifier);
        editor.createSequence(name: 'New from tablet');

        const childId = 'child-node-remote';
        editor.addNode(
          InstructionSetNode(id: childId, name: 'Lights'),
          parentId: editor.state!.rootNodeId!,
        );

        async.elapse(remoteSequenceAutoSaveDebounce);
        async.flushMicrotasks();

        verify(
          () => backend.saveFullSequence(
            any(
              that: predicate<Map<String, dynamic>>(
                (map) => map['name'] == 'New from tablet',
              ),
            ),
            isTemplate: false,
            databaseId: null,
          ),
        ).called(1);

        container.dispose();
      });
    });
  });
}
