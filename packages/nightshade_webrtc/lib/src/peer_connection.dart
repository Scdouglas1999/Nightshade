import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// WebRTC peer connection for Nightshade remote control
class NightshadePeerConnection {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  
  final _messageController = StreamController<String>.broadcast();
  Stream<String> get onMessage => _messageController.stream;
  
  final _connectionStateController = StreamController<RTCPeerConnectionState>.broadcast();
  Stream<RTCPeerConnectionState> get onConnectionState => _connectionStateController.stream;
  
  bool get isConnected => _peerConnection?.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
  
  /// Initialize the peer connection
  Future<void> initialize({bool isInitiator = false}) async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
    
    _peerConnection = await createPeerConnection(config);
    
    _peerConnection!.onConnectionState = (state) {
      _connectionStateController.add(state);
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
    return offer;
  }
  
  /// Create an answer (receiver)
  Future<RTCSessionDescription> createAnswer(RTCSessionDescription offer) async {
    await _peerConnection!.setRemoteDescription(offer);
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
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
    await _dataChannel?.close();
    await _peerConnection?.close();
    _peerConnection = null;
    _dataChannel = null;
  }
  
  void dispose() {
    close();
    _messageController.close();
    _connectionStateController.close();
  }
}




