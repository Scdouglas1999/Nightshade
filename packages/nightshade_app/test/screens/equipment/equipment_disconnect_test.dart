import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/equipment/utils/equipment_disconnect.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  group('equipmentDisconnectShouldSkip — UI-P0-3', () {
    test('skips only disconnected state', () {
      expect(
        equipmentDisconnectShouldSkip(DeviceConnectionState.disconnected),
        isTrue,
      );
      expect(
        equipmentDisconnectShouldSkip(DeviceConnectionState.connected),
        isFalse,
      );
      expect(
        equipmentDisconnectShouldSkip(DeviceConnectionState.error),
        isFalse,
      );
    });
  });
}
