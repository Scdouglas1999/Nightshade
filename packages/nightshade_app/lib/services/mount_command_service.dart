import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../models/command_action_result.dart';

/// Provider for the MountCommandService.
final mountCommandServiceProvider = Provider((ref) => MountCommandService(ref));

/// Centralized service for all mount control actions.
///
/// This eliminates duplicate mount command implementations across screens.
/// All mount control buttons should use this service instead of implementing
/// their own try/catch patterns with deviceServiceProvider.
class MountCommandService {
  final Ref _ref;

  MountCommandService(this._ref);

  DeviceService get _deviceService => _ref.read(deviceServiceProvider);
  MountState? get _mountState => _ref.read(mountStateProvider);
  NightshadeBackend get _backend => _ref.read(backendProvider);

  /// Returns true if a mount is currently connected.
  bool get isConnected =>
      _mountState?.connectionState == DeviceConnectionState.connected;

  Future<MountCapabilities?> _getCapabilities() async {
    final deviceId = _mountState?.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      return null;
    }
    try {
      return await _backend.getMountCapabilities(deviceId);
    } catch (_) {
      return null;
    }
  }

  /// Toggles between parked and unparked state.
  Future<CommandActionResult> togglePark() async {
    final mountState = _mountState;
    if (mountState == null || !isConnected) {
      return const CommandActionResult.failure('No mount connected');
    }

    final unparkRequested = mountState.isParked;
    try {
      final capabilities = await _getCapabilities();
      if (unparkRequested) {
        if (capabilities != null && !capabilities.canUnpark) {
          return const CommandActionResult.failure(
            'This mount reports that unpark is unsupported',
          );
        }
        await _deviceService.unparkMount();
      } else {
        if (capabilities != null && !capabilities.canPark) {
          return const CommandActionResult.failure(
            'This mount reports that park is unsupported',
          );
        }
        await _deviceService.parkMount();
      }
      return CommandActionResult.ok;
    } catch (e) {
      final operation = unparkRequested ? 'unpark' : 'park';
      return CommandActionResult.failure(
        'Failed to $operation mount: $e',
      );
    }
  }

  /// Parks the mount.
  Future<CommandActionResult> park() async {
    if (!isConnected) {
      return const CommandActionResult.failure('No mount connected');
    }
    try {
      final capabilities = await _getCapabilities();
      if (capabilities != null && !capabilities.canPark) {
        return const CommandActionResult.failure(
          'This mount reports that park is unsupported',
        );
      }
      await _deviceService.parkMount();
      return CommandActionResult.ok;
    } catch (e) {
      return CommandActionResult.failure('Failed to park mount: $e');
    }
  }

  /// Unparks the mount.
  Future<CommandActionResult> unpark() async {
    if (!isConnected) {
      return const CommandActionResult.failure('No mount connected');
    }
    try {
      final capabilities = await _getCapabilities();
      if (capabilities != null && !capabilities.canUnpark) {
        return const CommandActionResult.failure(
          'This mount reports that unpark is unsupported',
        );
      }
      await _deviceService.unparkMount();
      return CommandActionResult.ok;
    } catch (e) {
      return CommandActionResult.failure('Failed to unpark mount: $e');
    }
  }

  /// Slews the mount to the specified RA/Dec coordinates.
  Future<CommandActionResult> slewTo(double ra, double dec,
      {bool showFeedback = true}) async {
    if (!isConnected) {
      return const CommandActionResult.failure('No mount connected');
    }
    try {
      await _deviceService.slewMountToCoordinates(ra, dec);
      if (showFeedback) {
        return const CommandActionResult.success(
          message: 'Slewing to target...',
          feedbackType: CommandFeedbackType.info,
        );
      }
      return CommandActionResult.ok;
    } catch (e) {
      return CommandActionResult.failure('Slew failed: $e');
    }
  }

  /// Aborts any current slew operation.
  Future<CommandActionResult> abortSlew({bool showFeedback = true}) async {
    if (!isConnected) {
      return const CommandActionResult.failure('No mount connected');
    }
    try {
      await _deviceService.abortMountSlew();
      if (showFeedback) {
        return const CommandActionResult.success(
          message: 'Mount slew aborted',
        );
      }
      return CommandActionResult.ok;
    } catch (e) {
      return CommandActionResult.failure('Failed to abort slew: $e');
    }
  }

  /// Sets the mount tracking state.
  Future<CommandActionResult> setTracking(bool enabled) async {
    if (!isConnected) {
      return const CommandActionResult.failure('No mount connected');
    }
    try {
      final capabilities = await _getCapabilities();
      if (capabilities != null && !capabilities.canSetTracking) {
        return const CommandActionResult.failure(
          'This mount reports that tracking control is unsupported',
        );
      }
      await _deviceService.setMountTracking(enabled);
      return CommandActionResult.ok;
    } catch (e) {
      return CommandActionResult.failure('Failed to set tracking: $e');
    }
  }

  /// Toggles the mount tracking state.
  Future<CommandActionResult> toggleTracking() async {
    if (!isConnected || _mountState == null) {
      return const CommandActionResult.failure('No mount connected');
    }
    return setTracking(!_mountState!.isTracking);
  }

  /// Syncs the mount to the specified RA/Dec coordinates.
  Future<CommandActionResult> sync(double ra, double dec) async {
    if (!isConnected) {
      return const CommandActionResult.failure('No mount connected');
    }
    try {
      await _deviceService.syncMountToCoordinates(ra, dec);
      return const CommandActionResult.success(
        message: 'Mount synced to coordinates',
      );
    } catch (e) {
      return CommandActionResult.failure('Sync failed: $e');
    }
  }

  /// Sends a pulse guide command in the specified direction.
  Future<CommandActionResult> pulseGuide(String direction,
      {int durationMs = 500}) async {
    if (!isConnected) {
      return const CommandActionResult.failure('No mount connected');
    }
    try {
      await _deviceService.pulseGuidMount(
          direction: direction, durationMs: durationMs);
      return CommandActionResult.ok;
    } catch (e) {
      return CommandActionResult.failure('Pulse guide failed: $e');
    }
  }
}
