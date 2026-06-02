import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/immersive_chrome.dart';

void main() {
  group('ImmersiveChromeController', () {
    test('starts visible and disabled (pinned)', () {
      final c = ImmersiveChromeController();
      expect(c.state, isTrue);
      expect(c.enabled, isFalse);
      c.dispose();
    });

    test('disabled controller ignores poke/conceal (stays pinned visible)', () {
      final c = ImmersiveChromeController();
      c.conceal();
      expect(c.state, isTrue, reason: 'conceal is a no-op while disabled');
      c.dispose();
    });

    test('enabling starts an idle countdown that hides the chrome', () {
      fakeAsync((async) {
        final c = ImmersiveChromeController()..enabled = true;
        expect(c.state, isTrue);
        async.elapse(ImmersiveChromeController.idleTimeout +
            const Duration(seconds: 1));
        expect(c.state, isFalse, reason: 'auto-hides after idle');
        c.dispose();
      });
    });

    test('poke reveals and restarts the idle countdown', () {
      fakeAsync((async) {
        final c = ImmersiveChromeController()..enabled = true;
        // Let it hide.
        async.elapse(const Duration(seconds: 6));
        expect(c.state, isFalse);
        // Interaction brings it back...
        c.poke();
        expect(c.state, isTrue);
        // ...and it stays while interactions keep coming within the window.
        async.elapse(const Duration(seconds: 4));
        c.poke();
        async.elapse(const Duration(seconds: 4));
        expect(c.state, isTrue, reason: 'repeated pokes keep it visible');
        // Then idle out.
        async.elapse(const Duration(seconds: 6));
        expect(c.state, isFalse);
        c.dispose();
      });
    });

    test('hold pins visible until released, then resumes auto-hide', () {
      fakeAsync((async) {
        final c = ImmersiveChromeController()..enabled = true;
        c.pushHold();
        async.elapse(const Duration(seconds: 30));
        expect(c.state, isTrue, reason: 'held visible (e.g. a sheet is open)');
        c.popHold();
        async.elapse(const Duration(seconds: 6));
        expect(c.state, isFalse, reason: 'auto-hide resumes after release');
        c.dispose();
      });
    });

    test('disabling re-pins visible and cancels the timer', () {
      fakeAsync((async) {
        final c = ImmersiveChromeController()..enabled = true;
        async.elapse(const Duration(seconds: 6));
        expect(c.state, isFalse);
        c.enabled = false;
        expect(c.state, isTrue, reason: 'desktop/tablet pins chrome visible');
        async.elapse(const Duration(seconds: 30));
        expect(c.state, isTrue);
        c.dispose();
      });
    });
  });
}
