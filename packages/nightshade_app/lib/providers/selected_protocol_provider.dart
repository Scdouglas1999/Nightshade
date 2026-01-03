import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../screens/equipment/equipment_screen.dart';

/// Provider for the currently selected device protocol
final selectedProtocolProvider = StateProvider<DeviceProtocol>((ref) {
  // Default to ASCOM on Windows, Alpaca on others
  return Platform.isWindows ? DeviceProtocol.ascom : DeviceProtocol.alpaca;
});
