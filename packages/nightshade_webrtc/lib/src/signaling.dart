import 'dart:async';
import 'dart:io';

/// Signaling for WebRTC connection establishment
/// Uses local network mDNS discovery or manual IP entry
class NightshadeSignaling {
  static const int _signalingPort = 45678;
  
  ServerSocket? _server;
  Socket? _client;
  
  final _offerController = StreamController<String>.broadcast();
  Stream<String> get onOffer => _offerController.stream;
  
  final _answerController = StreamController<String>.broadcast();
  Stream<String> get onAnswer => _answerController.stream;
  
  final _candidateController = StreamController<String>.broadcast();
  Stream<String> get onCandidate => _candidateController.stream;
  
  /// Start listening for connections (desktop)
  Future<void> startServer() async {
    if (_server != null) {
      print('Signaling server is already running');
      return;
    }
    
    // Try multiple times with delays to handle TIME_WAIT states
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        _server = await ServerSocket.bind(InternetAddress.anyIPv4, _signalingPort, shared: true);
        
        _server!.listen((socket) {
          _handleConnection(socket);
        });
        return; // Success!
      } catch (e) {
        if (attempt < 2) {
          // Wait before retrying (exponential backoff)
          await Future.delayed(Duration(seconds: attempt + 1));
          continue;
        }
        // Last attempt failed
        print('Failed to start signaling server after 3 attempts: $e');
        rethrow;
      }
    }
  }
  
  /// Connect to a server (mobile)
  Future<void> connectTo(String host) async {
    _client = await Socket.connect(host, _signalingPort);
    _handleConnection(_client!);
  }
  
  void _handleConnection(Socket socket) {
    socket.listen((data) {
      final message = String.fromCharCodes(data);
      _handleMessage(message);
    });
  }
  
  void _handleMessage(String message) {
    if (message.startsWith('OFFER:')) {
      _offerController.add(message.substring(6));
    } else if (message.startsWith('ANSWER:')) {
      _answerController.add(message.substring(7));
    } else if (message.startsWith('CANDIDATE:')) {
      _candidateController.add(message.substring(10));
    }
  }
  
  /// Send an offer
  void sendOffer(String sdp) {
    _client?.write('OFFER:$sdp');
  }
  
  /// Send an answer
  void sendAnswer(String sdp) {
    _client?.write('ANSWER:$sdp');
  }
  
  /// Send an ICE candidate
  void sendCandidate(String candidate) {
    _client?.write('CANDIDATE:$candidate');
  }
  
  /// Get local IP address for display to user
  Future<String?> getLocalIp() async {
    final interfaces = await NetworkInterface.list();
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return null;
  }
  
  Future<void> close() async {
    await _client?.close();
    await _server?.close();
  }
  
  void dispose() {
    close();
    _offerController.close();
    _answerController.close();
    _candidateController.close();
  }
}



