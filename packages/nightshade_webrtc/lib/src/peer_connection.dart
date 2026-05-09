import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// WebRTC peer connection for Nightshade remote control
class NightshadePeerConnection {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  bool _isInitiator = false;
  bool _isDisposed = false;
  bool _manualClose = false;
  bool _isReconnecting = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  final _messageController = StreamController<String>.broadcast();
  Stream<String> get onMessage => _messageController.stream;

  final _connectionStateController = StreamController<RTCPeerConnectionState>.broadcast();
  Stream<RTCPeerConnectionState> get onConnectionState => _connectionStateController.stream;

  final _iceCandidateController = StreamController<RTCIceCandidate>.broadcast();
  /// Stream of ICE candidates that must be relayed to the remote peer
  /// via the signaling channel.
  Stream<RTCIceCandidate> get onLocalIceCandidate => _iceCandidateController.stream;

  final _localDescriptionController =
      StreamController<RTCSessionDescription>.broadcast();
  Stream<RTCSessionDescription> get onLocalDescription =>
      _localDescriptionController.stream;

  bool get isConnected => _peerConnection?.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  /// Initialize the peer connection
  Future<void> initialize({bool isInitiator = false}) async {
    if (_isDisposed) {
      throw StateError('NightshadePeerConnection has been disposed');
    }

    _manualClose = false;
    _isInitiator = isInitiator;
    _cancelReconnect();
    await _closePeerResources();

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    _peerConnection = await createPeerConnection(config);

    _peerConnection!.onConnectionState = (state) {
      _connectionStateController.add(state);
      _handleConnectionState(state);
    };

    _peerConnection!.onIceCandidate = (candidate) {
      _iceCandidateController.add(candidate);
    };

    _peerConnection!.onDataChannel = (channel) {
      _dataChannel = channel;
      _setupDataChannel();
    };

    if (isInitiator) {
      _dataChannel = await _peerConnection!.createDataChannel(
        'nightshade',
        RTCDataChannelInit(),
      );
      _setupDataChannel();
    }
  }
  
  void _setupDataChannel() {
    _dataChannel?.onMessage = (message) {
      _messageController.add(message.text);
    };
  }
  
  /// Create an offer (initiator)
  Future<RTCSessionDescription> createOffer() async {
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _localDescriptionController.add(offer);
    return offer;
  }
  
  /// Create an answer (receiver)
  Future<RTCSessionDescription> createAnswer(RTCSessionDescription offer) async {
    await _peerConnection!.setRemoteDescription(offer);
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    _localDescriptionController.add(answer);
    return answer;
  }
  
  /// Set remote answer
  Future<void> setRemoteAnswer(RTCSessionDescription answer) async {
    await _peerConnection!.setRemoteDescription(answer);
  }
  
  /// Add ICE candidate
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    await _peerConnection!.addCandidate(candidate);
  }
  
  /// Send a message over the data channel
  void send(String message) {
    _dataChannel?.send(RTCDataChannelMessage(message));
  }
  
  /// Close the connection
  Future<void> close() async {
    _manualClose = true;
    _cancelReconnect();
    await _closePeerResources();
  }
  
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await close();
    _messageController.close();
    _connectionStateController.close();
    _iceCandidateController.close();
    _localDescriptionController.close();
  }

  void _handleConnectionState(RTCPeerConnectionState state) {
    if (_manualClose || _isDisposed) {
      return;
    }

    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _reconnectAttempt = 0;
        _cancelReconnect();
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _scheduleReconnect();
        break;
      default:
        break;
    }
  }

  void _scheduleReconnect() {
    if (_isReconnecting || _isDisposed) {
      return;
    }

    _cancelReconnect();
    final delaySeconds = (_reconnectAttempt + 1).clamp(1, 5);
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _isReconnecting = true;
      try {
        await initialize(isInitiator: _isInitiator);
        if (_isInitiator) {
          await createOffer();
        }
        _reconnectAttempt++;
      } catch (_) {
        _reconnectAttempt++;
        _isReconnecting = false;
        _scheduleReconnect();
        return;
      }
      _isReconnecting = false;
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
  }

  Future<void> _closePeerResources() async {
    await _dataChannel?.close();
    await _peerConnection?.close();
    _peerConnection = null;
    _dataChannel = null;
  }
}



