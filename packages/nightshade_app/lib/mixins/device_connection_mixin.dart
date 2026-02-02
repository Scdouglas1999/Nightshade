import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/snackbar_helper.dart';

/// Mixin that provides unified device connection/disconnection handling.
///
/// This eliminates duplicate connect/disconnect handler code across equipment screens.
/// All device connection handlers should use this mixin instead of implementing
/// their own try/catch/setState patterns.
mixin DeviceConnectionMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  /// Connects to a device with unified error handling.
  ///
  /// [deviceId] - The unique identifier of the device to connect
  /// [deviceName] - Display name for error messages
  /// [connectFn] - The async function that performs the actual connection
  /// [onConnected] - Optional callback after successful connection (e.g., for profile dialog)
  Future<void> connectDevice({
    required String deviceId,
    required String deviceName,
    required Future<void> Function(String) connectFn,
    Future<void> Function()? onConnected,
  }) async {
    if (_isConnecting) return;

    setState(() => _isConnecting = true);
    try {
      await connectFn(deviceId);

      if (onConnected != null && mounted) {
        await onConnected();
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to connect $deviceName: $e');
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  /// Disconnects from a device with unified error handling.
  ///
  /// [disconnectFn] - The async function that performs the actual disconnection
  /// [deviceType] - Display name for error messages (e.g., 'camera', 'mount')
  Future<void> disconnectDevice({
    required Future<void> Function() disconnectFn,
    required String deviceType,
  }) async {
    try {
      await disconnectFn();
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to disconnect $deviceType: $e');
      }
    }
  }
}
