import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for auxiliary device endpoints (Switch and Cover Calibrator)
class AuxiliaryHandlers {
  final ProviderContainer container;

  AuxiliaryHandlers(this.container);

  Future<List<DeviceInfo>> _connectedDevicesByType(DeviceType type) async {
    final backend = container.read(backendProvider);
    final connectedDevices = await backend.getConnectedDevices();
    return connectedDevices.where((d) => d.deviceType == type).toList();
  }

  Future<Map<String, dynamic>> _readSwitchStatus(
      String deviceId, String deviceName) async {
    final caps = await bridge.apiGetSwitchCapabilities(deviceId: deviceId);
    final switches = caps.switches
        .map((s) => {
              'id': s.index,
              'name': s.name,
              'type': s.isBoolean ? 'boolean' : 'analog',
              'value': s.isBoolean ? (s.value > 0.5) : s.value,
              'minValue': s.isBoolean ? null : s.minValue,
              'maxValue': s.isBoolean ? null : s.maxValue,
              'step': s.isBoolean ? null : s.step,
              'canWrite': s.canWrite,
              'description': s.description,
            })
        .toList();

    return {
      'connected': true,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'switchCount': caps.switchCount,
      'switches': switches,
    };
  }

  String _mapCoverState(bridge.CoverState state) {
    switch (state) {
      case bridge.CoverState.notPresent:
        return 'notPresent';
      case bridge.CoverState.closed:
        return 'closed';
      case bridge.CoverState.moving:
        return 'moving';
      case bridge.CoverState.open:
        return 'open';
      case bridge.CoverState.unknown:
        return 'unknown';
      case bridge.CoverState.error:
        return 'error';
    }
  }

  String _mapCalibratorState(bridge.CalibratorState state) {
    switch (state) {
      case bridge.CalibratorState.notPresent:
        return 'notPresent';
      case bridge.CalibratorState.off:
        return 'off';
      case bridge.CalibratorState.notReady:
        return 'notReady';
      case bridge.CalibratorState.ready:
        return 'ready';
      case bridge.CalibratorState.unknown:
        return 'unknown';
      case bridge.CalibratorState.error:
        return 'error';
    }
  }

  /// GET /api/switch/status
  Future<Response> handleSwitchStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      final switchDevices = await _connectedDevicesByType(DeviceType.switch_);

      if (deviceId.isEmpty) {
        if (switchDevices.isEmpty) {
          return jsonOk({
            'devicesConnected': 0,
            'devices': <Map<String, dynamic>>[],
            'message': 'No switch devices connected',
          });
        }

        final deviceStatuses = <Map<String, dynamic>>[];
        for (final d in switchDevices) {
          try {
            deviceStatuses.add(await _readSwitchStatus(d.id, d.name));
          } catch (e) {
            deviceStatuses.add({
              'connected': false,
              'deviceId': d.id,
              'deviceName': d.name,
              'error': e.toString(),
            });
          }
        }

        return jsonOk({
          'devicesConnected': switchDevices.length,
          'devices': deviceStatuses,
        });
      }

      final matchingSwitches = switchDevices.where((d) => d.id == deviceId);
      if (matchingSwitches.isEmpty) {
        return jsonNotFound(
          {
            'connected': false,
            'deviceId': deviceId,
            'error': 'Switch device not connected'
          },
        );
      }
      final switchDevice = matchingSwitches.first;
      return jsonOk(
          await _readSwitchStatus(switchDevice.id, switchDevice.name));
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  /// POST /api/switch/set
  Future<Response> handleSwitchSet(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      final switchId = payload['switchId'] as int?;
      final value = payload['value'];

      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({'error': 'deviceId is required'});
      }
      if (switchId == null) {
        return jsonBadRequest({'error': 'switchId is required'});
      }
      if (value == null) {
        return jsonBadRequest({'error': 'value is required'});
      }

      final connected = await _connectedDevicesByType(DeviceType.switch_);
      if (!connected.any((d) => d.id == deviceId)) {
        return jsonNotFound({
          'error': 'Switch device not connected',
          'deviceId': deviceId,
        });
      }

      final maxSwitches = await bridge.apiSwitchGetMax(deviceId: deviceId);
      if (switchId < 0 || switchId >= maxSwitches) {
        return jsonBadRequest(
          {'error': 'switchId out of range (0..${maxSwitches - 1})'},
        );
      }

      if (value is bool) {
        await bridge.apiSwitchSetState(
          deviceId: deviceId,
          switchId: switchId,
          state: value,
        );
      } else if (value is num) {
        await bridge.apiSwitchSetValue(
          deviceId: deviceId,
          switchId: switchId,
          value: value.toDouble(),
        );
      } else {
        return jsonBadRequest({'error': 'value must be bool or number'});
      }

      return jsonOk({
        'status': 'ok',
        'deviceId': deviceId,
        'switchId': switchId,
        'value': value
      });
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  /// GET /api/cover/status
  Future<Response> handleCoverStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      if (deviceId.isEmpty) {
        return jsonBadRequest(
            {'error': 'deviceId query parameter is required'});
      }

      final covers = await _connectedDevicesByType(DeviceType.coverCalibrator);
      final matchingCovers = covers.where((d) => d.id == deviceId);
      if (matchingCovers.isEmpty) {
        return jsonNotFound(
          {
            'connected': false,
            'deviceId': deviceId,
            'error': 'Cover calibrator not connected'
          },
        );
      }
      final device = matchingCovers.first;

      final status =
          await bridge.apiCoverCalibratorGetStatus(deviceId: deviceId);
      final hasCover = status.coverState != bridge.CoverState.notPresent;
      final hasCalibrator =
          status.calibratorState != bridge.CalibratorState.notPresent;

      return jsonOk({
        'connected': status.connected,
        'deviceId': deviceId,
        'deviceName': device.name,
        'coverState': _mapCoverState(status.coverState),
        'calibratorState': _mapCalibratorState(status.calibratorState),
        'brightness': status.brightness,
        'maxBrightness': status.maxBrightness,
        'hasCover': hasCover,
        'hasCalibrator': hasCalibrator,
      });
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  /// POST /api/cover/open
  Future<Response> handleCoverOpen(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({'error': 'deviceId is required'});
      }
      await bridge.apiCoverCalibratorOpenCover(deviceId: deviceId);
      return jsonOk({'status': 'opening', 'deviceId': deviceId});
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  /// POST /api/cover/close
  Future<Response> handleCoverClose(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({'error': 'deviceId is required'});
      }
      await bridge.apiCoverCalibratorCloseCover(deviceId: deviceId);
      return jsonOk({'status': 'closing', 'deviceId': deviceId});
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  /// POST /api/cover/brightness
  Future<Response> handleCoverBrightness(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      final brightness = payload['brightness'] as int?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({'error': 'deviceId is required'});
      }
      if (brightness == null || brightness < 0) {
        return jsonBadRequest({
          'error': 'brightness must be a non-negative integer',
        });
      }
      await bridge.apiCoverCalibratorCalibratorOn(
        deviceId: deviceId,
        brightness: brightness,
      );
      return jsonOk(
        {'status': 'ok', 'deviceId': deviceId, 'brightness': brightness},
      );
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  /// POST /api/cover/calibrator-on
  Future<Response> handleCalibratorOn(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({'error': 'deviceId is required'});
      }
      final provided = payload['brightness'] as int?;
      final brightness = provided ?? 128;
      if (brightness < 0) {
        return jsonBadRequest({
          'error': 'brightness must be a non-negative integer',
        });
      }
      await bridge.apiCoverCalibratorCalibratorOn(
        deviceId: deviceId,
        brightness: brightness,
      );
      return jsonOk(
        {'status': 'on', 'deviceId': deviceId, 'brightness': brightness},
      );
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  /// POST /api/cover/calibrator-off
  Future<Response> handleCalibratorOff(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({'error': 'deviceId is required'});
      }
      await bridge.apiCoverCalibratorCalibratorOff(deviceId: deviceId);
      return jsonOk({'status': 'off', 'deviceId': deviceId});
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }
}
