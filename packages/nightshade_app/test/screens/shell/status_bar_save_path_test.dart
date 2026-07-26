import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/shell/widgets/status_bar.dart';
import 'package:nightshade_core/nightshade_core.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

void main() {
  test('remote save-path status validates the imaging host path', () async {
    final backend = _MockNetworkBackend();
    when(
      () => backend.validateRemoteDirectory(
        r'Z:\Nightshade\Captures',
        mustExist: true,
        mustBeWritable: false,
      ),
    ).thenAnswer((_) async => const {'valid': true});

    final exists = await configuredSavePathExists(
      backend,
      r'Z:\Nightshade\Captures',
    );

    expect(exists, isTrue);
    verify(
      () => backend.validateRemoteDirectory(
        r'Z:\Nightshade\Captures',
        mustExist: true,
        mustBeWritable: false,
      ),
    ).called(1);
  });
}
