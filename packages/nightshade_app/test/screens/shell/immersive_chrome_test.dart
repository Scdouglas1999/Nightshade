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

    test('disabled controller ignores toggle/show/hide', () {
      final c = ImmersiveChromeController();
      c.hide();
      expect(c.state, isTrue, reason: 'manual ops are no-ops while disabled');
      c.toggle();
      expect(c.state, isTrue);
      c.dispose();
    });

    test('onRouteChanged shows and arms a one-shot idle auto-hide', () {
      fakeAsync((async) {
        final c = ImmersiveChromeController()..enabled = true;
        c.onRouteChanged();
        expect(c.state, isTrue);
        async.elapse(
            ImmersiveChromeController.idleTimeout + const Duration(seconds: 1));
        expect(c.state, isFalse, reason: 'auto-hides once after idle');
        c.dispose();
      });
    });

    test('manual hide is sticky — it does NOT auto-reveal', () {
      fakeAsync((async) {
        final c = ImmersiveChromeController()..enabled = true;
        c.hide();
        expect(c.state, isFalse);
        async.elapse(const Duration(seconds: 60));
        expect(c.state, isFalse, reason: 'stays hidden until explicitly shown');
        c.dispose();
      });
    });

    test('manual show pins visible (cancels the idle auto-hide)', () {
      fakeAsync((async) {
        final c = ImmersiveChromeController()..enabled = true;
        c.onRouteChanged(); // arms auto-hide
        c.show(); // user pins it visible
        async.elapse(const Duration(seconds: 60));
        expect(c.state, isTrue,
            reason: 'pinned: no auto-hide after manual show');
        c.dispose();
      });
    });

    test('toggle flips and stays put', () {
      final c = ImmersiveChromeController()..enabled = true;
      expect(c.state, isTrue);
      c.toggle();
      expect(c.state, isFalse);
      c.toggle();
      expect(c.state, isTrue);
      c.dispose();
    });

    test('navigating again re-shows after a manual hide', () {
      fakeAsync((async) {
        final c = ImmersiveChromeController()..enabled = true;
        c.hide();
        expect(c.state, isFalse);
        c.onRouteChanged();
        expect(c.state, isTrue,
            reason: 'a new screen reveals the chrome again');
        c.dispose();
      });
    });

    test('disabling re-pins visible and cancels any timer', () {
      fakeAsync((async) {
        final c = ImmersiveChromeController()..enabled = true;
        c.hide();
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
