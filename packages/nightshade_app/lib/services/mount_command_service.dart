import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../utils/snackbar_helper.dart';

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

  /// Returns true if a mount is currently connected.
  bool get isConnected => _mountState?.connectionState == DeviceConnectionState.connected;

  /// Toggles between parked and unparked state.
  Future<bool> togglePark(BuildContext context) async {
    if (!isConnected) {
      context.showErrorSnackBar('No mount connected');
      return false;
    }
    try {
      if (_mountState!.isParked) {
        await _deviceService.unparkMount();
      } else {
        await _deviceService.parkMount();
      }
      return true;
    } catch (e) {
      context.showErrorSnackBar('Failed to ${_mountState!.isParked ? "unpark" : "park"} mount: $e');
      return false;
    }
  }

  /// Parks the mount.
  Future<bool> park(BuildContext context) async {
    if (!isConnected) {
      context.showErrorSnackBar('No mount connected');
      return false;
    }
    try {
      await _deviceService.parkMount();
      return true;
    } catch (e) {
      context.showErrorSnackBar('Failed to park mount: $e');
      return false;
    }
  }

  /// Unparks the mount.
  Future<bool> unpark(BuildContext context) async {
    if (!isConnected) {
      context.showErrorSnackBar('No mount connected');
      return false;
    }
    try {
      await _deviceService.unparkMount();
      return true;
    } catch (e) {
      context.showErrorSnackBar('Failed to unpark mount: $e');
      return false;
    }
  }

  /// Slews the mount to the specified RA/Dec coordinates.
  Future<bool> slewTo(BuildContext context, double ra, double dec, {bool showFeedback = true}) async {
    if (!isConnected) {
      context.showErrorSnackBar('No mount connected');
      return false;
    }
    try {
      await _deviceService.slewMountToCoordinates(ra, dec);
      if (showFeedback) context.showInfoSnackBar('Slewing to target...');
      return true;
    } catch (e) {
      context.showErrorSnackBar('Slew failed: $e');
      return false;
    }
  }

  /// Aborts any current slew operation.
  Future<bool> abortSlew(BuildContext context, {bool showFeedback = true}) async {
    if (!isConnected) {
      context.showErrorSnackBar('No mount connected');
      return false;
    }
    try {
      await _deviceService.abortMountSlew();
      if (showFeedback) context.showSuccessSnackBar('Mount slew aborted');
      return true;
    } catch (e) {
      context.showErrorSnackBar('Failed to abort slew: $e');
      return false;
    }
  }

  /// Sets the mount tracking state.
  Future<bool> setTracking(BuildContext context, bool enabled) async {
    if (!isConnected) {
      context.showErrorSnackBar('No mount connected');
      return false;
    }
    try {
      await _deviceService.setMountTracking(enabled);
      return true;
    } catch (e) {
      context.showErrorSnackBar('Failed to set tracking: $e');
      return false;
    }
  }

  /// Toggles the mount tracking state.
  Future<bool> toggleTracking(BuildContext context) async {
    if (!isConnected || _mountState == null) {
      context.showErrorSnackBar('No mount connected');
      return false;
    }
    return setTracking(context, !_mountState!.isTracking);
  }

  /// Syncs the mount to the specified RA/Dec coordinates.
  Future<bool> sync(BuildContext context, double ra, double dec) async {
    if (!isConnected) {
      context.showErrorSnackBar('No mount connected');
      return false;
    }
    try {
      await _deviceService.syncMountToCoordinates(ra, dec);
      context.showSuccessSnackBar('Mount synced to coordinates');
      return true;
    } catch (e) {
      context.showErrorSnackBar('Sync failed: $e');
      return false;
    }
  }

  /// Sends a pulse guide command in the specified direction.
  Future<bool> pulseGuide(BuildContext context, String direction, {int durationMs = 500}) async {
    if (!isConnected) {
      context.showErrorSnackBar('No mount connected');
      return false;
    }
    try {
      await _deviceService.pulseGuidMount(direction: direction, durationMs: durationMs);
      return true;
    } catch (e) {
      context.showErrorSnackBar('Pulse guide failed: $e');
      return false;
    }
  }
}
