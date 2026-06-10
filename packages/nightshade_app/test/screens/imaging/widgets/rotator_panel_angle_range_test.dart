// Widget tests for RotatorPanel Go-To angle range wiring (component C10).
//
// Scope:
//   1. out_of_range_rejected_with_caps_window — when RotatorCapabilities
//      reports minAngleDeg=0/maxAngleDeg=270, entering 300 surfaces the
//      out-of-range error and never dispatches the move.
//   2. in_range_accepted_with_caps_window — 200 (inside 0..270) passes
//      validation and dispatches moveRotatorTo with no error snackbar.
//   3. null_range_falls_back_to_full_turn — when the rotator can move
//      absolutely but reports no angle bounds (min/maxAngleDeg == null),
//      360 is accepted (dispatched) and 361 is rejected, proving the 0..360
//      fallback.
//   4. hint_reflects_caps_window / hint_reflects_fallback — the input hint
//      shows the resolved range ('0.0 - 270.0' with bounds, '0.0 - 360.0'
//      without).
//   5. inverted_caps_range_falls_back — degenerate driver data (min >= max)
//      is treated as missing and falls back to the full-turn window.
//
// Note: the Go-To section is itself gated on canMoveAbsolute (DEV-P3-1), so
// every fixture sets canMoveAbsolute=true; the "no bounds" case is modeled by
// null min/maxAngleDeg, not by fully-absent capabilities.
//
// We assert on the error-snackbar text (validation is pure and runs before
// any backend call) and on a recording DeviceService that captures the
// dispatched target angle — a direct, non-flaky check of exactly the
// range-validation behavior C10 owns.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/imaging/widgets/rotator_panel.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../harness/harness.dart';

const _kDeviceId = 'simulator:rotator:0';

/// A [RotatorStateNotifier] seeded to a connected, idle device so the panel
/// renders the Go-To section (which is gated on `canMoveAbsolute`) and
/// resolves capabilities for the matching device id.
class _ConnectedRotatorNotifier extends RotatorStateNotifier {
  _ConnectedRotatorNotifier(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = const RotatorState(
      connectionState: DeviceConnectionState.connected,
      deviceId: _kDeviceId,
      deviceName: 'Simulated Rotator',
      position: 0,
    );
  }
}

/// A [DeviceService] that records absolute-move targets instead of driving a
/// backend, so accepted moves are observable without polling timers. The
/// real constructor still runs (wiring sub-controllers against the harness
/// MockBackend); only [moveRotatorTo] is intercepted.
class _RecordingDeviceService extends DeviceService {
  _RecordingDeviceService(super.ref, super.backend);

  final List<double> moveToTargets = [];

  @override
  Future<void> moveRotatorTo(double angle) async {
    moveToTargets.add(angle);
  }
}

List<Override> _overrides(RotatorCapabilities? caps) => [
      rotatorStateProvider.overrideWith(_ConnectedRotatorNotifier.new),
      equipmentRotatorCapabilitiesProvider(_kDeviceId)
          .overrideWith((ref) async => caps),
      deviceServiceProvider.overrideWith((ref) {
        final backend = ref.watch(backendProvider);
        final service = _RecordingDeviceService(ref, backend);
        ref.onDispose(service.dispose);
        return service;
      }),
    ];

/// Pumps the panel and returns the recording service so tests can assert on
/// dispatched move targets. The service is resolved from the harness
/// container so it is available even in tests that never trigger a move.
Future<_RecordingDeviceService> _pumpPanel(
  WidgetTester tester,
  RotatorCapabilities? caps,
) async {
  final handle = await pumpAppScreen(
    tester,
    const RotatorPanel(colors: NightshadeColors.dark),
    extraOverrides: _overrides(caps),
    settle: false,
  );
  // Drain the capability FutureProvider override into the tree.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
  return handle.container.read(deviceServiceProvider)
      as _RecordingDeviceService;
}

RotatorCapabilities _caps({double? minAngle, double? maxAngle}) =>
    RotatorCapabilities(
      canMoveAbsolute: true,
      minAngleDeg: minAngle,
      maxAngleDeg: maxAngle,
    );

/// Enter [value] into the Go-To field and tap the Go To button, draining any
/// resulting snackbar/state frames so the next interaction sees a settled tree.
Future<void> _goTo(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField), value);
  await tester.pump();
  await tester.tap(find.text('Go To'));
  // Drain the validation snackbar / move-dispatch state change. The recording
  // service completes synchronously, so a few discrete pumps settle the tree
  // without risking a periodic-animation pumpAndSettle timeout.
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'out_of_range_rejected_with_caps_window: 300 rejected for 0..270 caps',
      (tester) async {
    final service = await _pumpPanel(tester, _caps(minAngle: 0, maxAngle: 270));

    await _goTo(tester, '300');

    expect(find.text('Angle must be between 0 and 270'), findsOneWidget,
        reason: 'Out-of-range angle must surface the caps-bounded error.');
    expect(service.moveToTargets, isEmpty,
        reason: 'A rejected angle must never dispatch a move.');
  });

  testWidgets(
      'in_range_accepted_with_caps_window: 200 dispatched for 0..270 caps',
      (tester) async {
    final service = await _pumpPanel(tester, _caps(minAngle: 0, maxAngle: 270));

    await _goTo(tester, '200');

    expect(find.textContaining('Angle must be between'), findsNothing,
        reason: 'An in-range angle must not surface the range error.');
    expect(service.moveToTargets, [200],
        reason: 'An in-range angle must dispatch moveRotatorTo.');
  });

  testWidgets('null_range_falls_back_to_full_turn: 360 accepted, 361 rejected',
      (tester) async {
    // A rotator that can move absolutely but does not report angle bounds
    // (minAngleDeg/maxAngleDeg == null). The Go-To section still renders
    // because canMoveAbsolute is true; validation must fall back to 0..360.
    final service = await _pumpPanel(tester, _caps());

    // 360 sits on the inclusive upper bound of the 0..360 fallback window.
    await _goTo(tester, '360');
    expect(service.moveToTargets, [360],
        reason: 'With a null range the fallback window is 0..360 inclusive, '
            'so 360 must be accepted.');

    // 361 is past the fallback ceiling and must be rejected.
    await _goTo(tester, '361');
    expect(find.text('Angle must be between 0 and 360'), findsOneWidget,
        reason: '361 exceeds the 0..360 fallback and must be rejected.');
    expect(service.moveToTargets, [360],
        reason: 'The rejected 361 must not add a second dispatched move.');
  });

  testWidgets('hint_reflects_caps_window: hint shows 0.0 - 270.0 for caps',
      (tester) async {
    await _pumpPanel(tester, _caps(minAngle: 0, maxAngle: 270));

    expect(find.text('0.0 - 270.0'), findsOneWidget,
        reason: 'The input hint must mirror the caps-derived range.');
  });

  testWidgets('hint_reflects_fallback: hint shows 0.0 - 360.0 for null range',
      (tester) async {
    await _pumpPanel(tester, _caps());

    expect(find.text('0.0 - 360.0'), findsOneWidget,
        reason: 'A null angle range must fall back to a 0..360 hint.');
  });

  testWidgets('inverted_caps_range_falls_back: min>=max ignored, uses 0..360',
      (tester) async {
    // Degenerate driver data (min >= max) must be treated as missing and fall
    // back to the full-turn window for both validation and the hint.
    final service =
        await _pumpPanel(tester, _caps(minAngle: 300, maxAngle: 100));

    expect(find.text('0.0 - 360.0'), findsOneWidget,
        reason: 'Inverted range must fall back to the 0..360 hint.');

    await _goTo(tester, '350');
    expect(find.textContaining('Angle must be between'), findsNothing,
        reason: '350 is valid under the 0..360 fallback.');
    expect(service.moveToTargets, [350]);
  });
}
