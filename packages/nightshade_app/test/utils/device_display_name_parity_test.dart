// WD-EQ-2, second strike on the two-implementations trap.
//
// Two Dart formatters turn a device id into words:
//   * nightshade_core `friendlyNameFromDeviceId` — the no-discovery fallback
//     used by DeviceService AND by the run dashboard's RECENT EVENTS feed;
//   * nightshade_app `formatDeviceId` — the richer UI formatter.
// Wave D added a humanizer that called the first one; Wave E found the
// Dashboard still reading `Guider · native:builtin_guider:multi_star`,
// `Filter Wheel · sim_filterwheel_1`, `Focuser · sim_focuser_1`, because the
// first formatter had no arm for any id a hardware-free operator can produce.
//
// These tests pin the exact ids from that dump and then assert both formatters
// agree, so fixing one and shipping the other cannot happen silently again.
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/utils/device_format_utils.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  group('friendlyNameFromDeviceId names the ids Wave E saw on screen', () {
    test('the built-in guider', () {
      expect(
        friendlyNameFromDeviceId('native:builtin_guider:multi_star'),
        'Built-in Multi-Star Guider',
      );
    });

    test('the simulators', () {
      expect(friendlyNameFromDeviceId('sim_camera_1'), 'Simulated Camera');
      expect(friendlyNameFromDeviceId('sim_mount_1'), 'Simulated Mount');
      expect(friendlyNameFromDeviceId('sim_focuser_1'), 'Simulated Focuser');
      expect(
        friendlyNameFromDeviceId('sim_filterwheel_1'),
        'Simulated Filter Wheel',
      );
      expect(friendlyNameFromDeviceId('sim_rotator_1'), 'Simulated Rotator');
      expect(friendlyNameFromDeviceId('sim_dome_1'), 'Simulated Dome');
      expect(
        friendlyNameFromDeviceId('sim_weather_1'),
        'Simulated Weather Station',
      );
      expect(
        friendlyNameFromDeviceId('sim_safety_monitor_1'),
        'Simulated Safety Monitor',
      );
      expect(
        friendlyNameFromDeviceId('sim_switch_1'),
        'Simulated Power Switch',
      );
      expect(
        friendlyNameFromDeviceId('sim_cover_calibrator_1'),
        'Simulated Flat Panel',
      );
    });

    test('a second simulator of a type is numbered, not duplicated', () {
      expect(friendlyNameFromDeviceId('sim_camera_2'), 'Simulated Camera 2');
    });

    test('an unknown id is still returned unchanged', () {
      expect(friendlyNameFromDeviceId('sim_not_a_device'), 'sim_not_a_device');
      expect(friendlyNameFromDeviceId('indi:localhost:7624:Foo'),
          'indi:localhost:7624:Foo');
    });

    test('no id these tests cover leaks a raw routing key', () {
      const onScreen = [
        'native:builtin_guider:multi_star',
        'sim_camera_1',
        'sim_filterwheel_1',
        'sim_focuser_1',
      ];
      for (final id in onScreen) {
        expect(
          friendlyNameFromDeviceId(id),
          isNot(id),
          reason: '$id reached the Dashboard feed verbatim in Wave E',
        );
      }
    });
  });

  test('the two formatters agree on every id they both know', () {
    // The parity guard. `formatDeviceId` is allowed to be richer for vendor
    // ids; for the ids below it must not invent a second name.
    const shared = [
      'native:builtin_guider:multi_star',
      'sim_camera_1',
      'sim_mount_1',
      'sim_focuser_1',
      'sim_filterwheel_1',
      'sim_rotator_1',
      'sim_dome_1',
      'sim_weather_1',
      'sim_safety_monitor_1',
      'sim_switch_1',
      'sim_cover_calibrator_1',
    ];
    for (final id in shared) {
      expect(
        formatDeviceId(id),
        friendlyNameFromDeviceId(id),
        reason: 'formatDeviceId and friendlyNameFromDeviceId disagree on $id',
      );
    }
  });
}
