// ignore_for_file: unused_field

part of '../bridge_stub.dart';

final _nativeBridge = _NativeBridgeImplementation();

/// Process-wide mutable state shared by the domain-specific bridge operations.
final class _NativeBridgeImplementation {
  bool _initialized = false;
  bool _nativeAvailable = false;
  DynamicLibrary? _nativeLib;
  String? _loadedNativeLibraryPath;
  final _eventController =
      StreamController<_FallbackNightshadeEvent>.broadcast();

  final Map<String, bool> _connectedDevices = {};
  final Map<String, DeviceInfo> _connectedDeviceInfo = {};

  final Map<DeviceType, List<DeviceInfo>> _discoveryCache = {};
  DateTime? _discoveryCacheTime;
  final _discoveryCacheTtl = const Duration(seconds: 60);
  Completer<void>? _discoverySweepInProgress;
  bool _ascomNotWindowsWarned = false;

  final Map<String, alpaca.AlpacaClient> _alpacaClients = {};
  final Map<String, alpaca.AlpacaDevice> _alpacaDevices = {};
  final Map<String, ascom.AscomDeviceClient> _ascomClients = {};
  phd2.Phd2Client? _phd2Client;

  SequencerState _sequencerState = SequencerState.idle;
  String? _loadedSequenceJson;
  bool _sequencerEventsSubscribed = false;
  bool _simulationMode = false;
}
