part of '../network_backend.dart';

extension _NetworkBackendWireDecoding on _NetworkBackendTransport {
  // =========================================================================
  // Type Conversion Helpers
  // =========================================================================

  DriverType _parseDriverType(String str) {
    switch (str.toLowerCase()) {
      case 'ascom':
        return DriverType.ascom;
      case 'alpaca':
        return DriverType.alpaca;
      case 'indi':
        return DriverType.indi;
      case 'native':
        return DriverType.native;
      case 'simulator':
        return DriverType.simulator;
      default:
        throw Exception('Unknown driver type: $str');
    }
  }

  NightshadeEvent _eventFromJson(Map<String, dynamic> json) {
    return NightshadeEvent.fromWireJson(json);
  }
}
