// Correcting a rejected capture folder must clear the rejection.
//
// Live finding IMG-1: onboarding step 10 rejected a path that did not exist,
// and then kept saying "That folder does not exist." under a path the user had
// replaced with a real one. The verdict was computed on submit/focus-loss only,
// so retyping — the natural recovery — never re-ran the validator, and Next
// stayed dead. Back-then-Next remounted the step and accepted the very same
// text, which is what proved the check was right and only its result was stale.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/onboarding/steps/capture_dir_step.dart';
import 'package:nightshade_core/nightshade_core.dart';

class _TestOnboardingNotifier extends OnboardingNotifier {
  _TestOnboardingNotifier(super.ref);
}

class _Writer {
  final written = <String>[];
}

ProviderContainer _container({
  required _Writer writer,
  required Set<String> writableFolders,
  required NightshadeDatabase db,
}) {
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      onboardingDraftProvider.overrideWith(_TestOnboardingNotifier.new),
      onboardingCaptureDirectoryPickerProvider.overrideWithValue(
        (context, {required isRemote, required initialPath}) async => null,
      ),
      onboardingCaptureDirectoryValidatorProvider.overrideWithValue(
        (path) async => writableFolders.contains(path)
            ? null
            : 'That folder does not exist.',
      ),
      onboardingCaptureDirectoryWriterProvider.overrideWith((ref) {
        return (path) async {
          writer.written.add(path);
          await ref
              .read(onboardingDraftProvider.notifier)
              .setCaptureDirectory(path);
        };
      }),
    ],
  );
}

Widget _surface(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: OnboardingCaptureDirStep()),
    ),
  );
}

void main() {
  testWidgets('retyping a good path clears the rejection and commits it',
      (tester) async {
    final writer = _Writer();
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container =
        _container(writer: writer, writableFolders: {'/tmp'}, db: db);
    addTearDown(container.dispose);

    await tester.pumpWidget(_surface(container));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(onboardingCaptureDirFieldKey),
      '/tmp/does-not-exist',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('That folder does not exist.'), findsOneWidget);

    // The recovery a user actually performs: select all, type a real folder,
    // and expect the field to answer for what it now contains.
    await tester.enterText(find.byKey(onboardingCaptureDirFieldKey), '/tmp');
    await tester.pump();
    expect(
      find.text('That folder does not exist.'),
      findsNothing,
      reason: 'the rejection describes text that is no longer in the box',
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(writer.written, ['/tmp']);
    expect(find.text('Folder is writable.'), findsOneWidget);
  });

  testWidgets('an edit away from an accepted folder drops the green tick',
      (tester) async {
    final writer = _Writer();
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container =
        _container(writer: writer, writableFolders: {'/srv/captures'}, db: db);
    addTearDown(container.dispose);

    await tester.pumpWidget(_surface(container));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(onboardingCaptureDirFieldKey),
      '/srv/captures',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Folder is writable.'), findsOneWidget);

    await tester.enterText(
      find.byKey(onboardingCaptureDirFieldKey),
      '/srv/captures-typo',
    );
    await tester.pump();
    expect(find.text('Folder is writable.'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('That folder does not exist.'), findsOneWidget);
    expect(writer.written, ['/srv/captures']);
  });
}
