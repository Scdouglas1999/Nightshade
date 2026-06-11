/// Tests for INDI XML discovery parsing via [NativeBridge.apiDiscoverIndiAtAddress].
///
/// The bridge connects over TCP, sends `<getProperties>`, and parses the INDI
/// property-vector XML the server returns to infer device types. We exercise
/// that parser end-to-end against a loopback [ServerSocket] that replays canned
/// INDI XML, covering device-type inference, multi-device responses, malformed
/// XML resilience, and unknown-property filtering.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

/// A loopback INDI server that replies to the first inbound data with [xml].
class _FakeIndiServer {
  _FakeIndiServer._(this._socket, this._xml);

  final ServerSocket _socket;
  final String _xml;

  static Future<_FakeIndiServer> start(String xml) async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final server = _FakeIndiServer._(socket, xml);
    server._listen();
    return server;
  }

  int get port => _socket.port;
  String get host => _socket.address.address;

  void _listen() {
    _socket.listen((client) {
      client.listen(
        (_) {
          // Respond to the getProperties request with the canned XML, then end
          // the stream so the bridge's read loop completes promptly.
          client.add(utf8.encode(_xml));
          client.flush().then((_) => client.close());
        },
        onError: (_) {},
        cancelOnError: false,
      );
    });
  }

  Future<void> close() => _socket.close();
}

void main() {
  Future<List<DeviceInfo>> discover(String xml) async {
    final server = await _FakeIndiServer.start(xml);
    try {
      return await NativeBridge.apiDiscoverIndiAtAddress(
        host: server.host,
        port: server.port,
      );
    } finally {
      await server.close();
    }
  }

  group('INDI device-type inference', () {
    test('CCD_EXPOSURE property -> camera', () async {
      const xml = '''
<indilib>
  <defNumberVector device="ZWO CCD" name="CCD_EXPOSURE">
    <defNumber name="CCD_EXPOSURE_VALUE">1.0</defNumber>
  </defNumberVector>
</indilib>''';
      final devices = await discover(xml);
      expect(devices, hasLength(1));
      expect(devices.single.deviceType, DeviceType.camera);
      expect(devices.single.name, 'ZWO CCD');
      expect(devices.single.driverType, DriverType.indi);
    });

    test('EQUATORIAL_EOD_COORD -> mount', () async {
      const xml = '''
<indilib>
  <defNumberVector device="EQMod Mount" name="EQUATORIAL_EOD_COORD"/>
</indilib>''';
      final devices = await discover(xml);
      expect(devices.single.deviceType, DeviceType.mount);
    });

    test('ABS_FOCUS_POSITION -> focuser', () async {
      const xml = '''
<indilib>
  <defNumberVector device="Focuser Simulator" name="ABS_FOCUS_POSITION"/>
</indilib>''';
      final devices = await discover(xml);
      expect(devices.single.deviceType, DeviceType.focuser);
    });

    test('FILTER_SLOT -> filter wheel', () async {
      const xml = '''
<indilib>
  <defNumberVector device="EFW" name="FILTER_SLOT"/>
  <defTextVector device="EFW" name="FILTER_NAME"/>
</indilib>''';
      final devices = await discover(xml);
      expect(devices.single.deviceType, DeviceType.filterWheel);
    });

    test('WEATHER_TEMPERATURE -> weather', () async {
      const xml = '''
<indilib>
  <defNumberVector device="Weather Watcher" name="WEATHER_TEMPERATURE"/>
</indilib>''';
      final devices = await discover(xml);
      expect(devices.single.deviceType, DeviceType.weather);
    });

    test('switch and light vectors contribute to type inference', () async {
      const xml = '''
<indilib>
  <defSwitchVector device="Dome" name="DOME_PARK"/>
  <defSwitchVector device="Dome" name="DOME_SHUTTER"/>
</indilib>''';
      final devices = await discover(xml);
      expect(devices.single.deviceType, DeviceType.dome);
    });
  });

  group('INDI multi-device and filtering', () {
    test('parses multiple distinct devices from one response', () async {
      const xml = '''
<indilib>
  <defNumberVector device="Cam" name="CCD_EXPOSURE"/>
  <defNumberVector device="Scope" name="TELESCOPE_PARK"/>
  <defNumberVector device="Foc" name="REL_FOCUS_POSITION"/>
</indilib>''';
      final devices = await discover(xml);
      final byType = {for (final d in devices) d.deviceType: d.name};
      expect(byType[DeviceType.camera], 'Cam');
      expect(byType[DeviceType.mount], 'Scope');
      expect(byType[DeviceType.focuser], 'Foc');
    });

    test('device with only unrecognized properties is filtered out', () async {
      const xml = '''
<indilib>
  <defTextVector device="Mystery" name="SOME_RANDOM_PROP"/>
  <defNumberVector device="Mystery" name="ANOTHER_ONE"/>
</indilib>''';
      final devices = await discover(xml);
      expect(devices, isEmpty);
    });

    test('aggregates properties across vectors for one device', () async {
      // Type-defining property arrives in a later vector than a generic one.
      const xml = '''
<indilib>
  <defTextVector device="Combo" name="DRIVER_INFO"/>
  <defNumberVector device="Combo" name="CCD1"/>
</indilib>''';
      final devices = await discover(xml);
      expect(devices.single.deviceType, DeviceType.camera);
    });

    test('device id encodes host and port', () async {
      const xml = '''
<indilib>
  <defNumberVector device="Cam" name="CCD_EXPOSURE"/>
</indilib>''';
      final server = await _FakeIndiServer.start(xml);
      try {
        final devices = await NativeBridge.apiDiscoverIndiAtAddress(
          host: server.host,
          port: server.port,
        );
        expect(devices.single.id, 'indi:${server.host}:${server.port}:Cam');
      } finally {
        await server.close();
      }
    });
  });

  group('INDI malformed input resilience', () {
    test('malformed XML yields an empty list, not a throw', () async {
      const xml = '<indilib><defNumberVector device="X" name="CCD_EXPOSURE">';
      final devices = await discover(xml);
      expect(devices, isEmpty);
    });

    test('empty response yields an empty list', () async {
      final devices = await discover('');
      expect(devices, isEmpty);
    });

    test('vector missing device attribute is skipped', () async {
      const xml = '''
<indilib>
  <defNumberVector name="CCD_EXPOSURE"/>
</indilib>''';
      final devices = await discover(xml);
      expect(devices, isEmpty);
    });
  });
}
