// Structural guards for the Windows runner. The corresponding runtime
// regression launches and normally closes the Release executable on Windows;
// these checks alone do not prove engine teardown is crash-free.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the message-loop exit destroys the Flutter view before COM teardown',
    () {
      final source = File('windows/runner/main.cpp').readAsStringSync();
      final loop = source.indexOf('::MSG msg');
      final destroy = source.indexOf('window.Destroy();', loop);
      final uninitialize = source.indexOf('::CoUninitialize();', loop);
      expect(loop, greaterThanOrEqualTo(0));
      expect(destroy, greaterThan(loop));
      expect(uninitialize, greaterThan(destroy));
    },
  );

  test('late font notifications tolerate an already-destroyed controller', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final fontCase = source.substring(source.indexOf('case WM_FONTCHANGE:'));
    expect(fontCase, contains('if (flutter_controller_) {'));
    expect(
      fontCase.indexOf('if (flutter_controller_) {'),
      lessThan(fontCase.indexOf('ReloadSystemFonts()')),
    );
  });
}
