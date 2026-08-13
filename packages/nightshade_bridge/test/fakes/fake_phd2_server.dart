/// A minimal in-process PHD2 server for driving [Phd2Client] tests over a real
/// loopback TCP socket.
///
/// PHD2 speaks line-delimited (\r\n) JSON-RPC 2.0 over TCP. This fake binds a
/// real [ServerSocket] on 127.0.0.1:0, accepts a single client connection, and
/// lets the test:
///   - register canned RPC responses by method name (so the client's
///     `connect()` handshake `get_app_state` resolves immediately),
///   - inspect the decoded requests the client sent,
///   - push arbitrary event/response lines back to the client.

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FakePhd2Server {
  FakePhd2Server._(this._serverSocket);

  final ServerSocket _serverSocket;
  Socket? _client;
  final _buffer = StringBuffer();

  /// Decoded request maps the client has sent, in order.
  final List<Map<String, dynamic>> requests = [];

  /// Canned results keyed by RPC method name. The value is returned as the
  /// JSON-RPC `result` field with the request's `id` echoed back.
  final Map<String, Object?> _cannedResults = {};

  /// Completes once the client socket has connected.
  final _connected = Completer<void>();

  int get port => _serverSocket.port;
  String get host => _serverSocket.address.address;

  /// Bind a fresh server on an ephemeral loopback port.
  static Future<FakePhd2Server> start() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final server = FakePhd2Server._(socket);
    server._listen();
    return server;
  }

  void _listen() {
    _serverSocket.listen((client) {
      _client = client;
      if (!_connected.isCompleted) _connected.complete();
      client.listen(
        _onData,
        onError: (_) {},
        onDone: () {},
        cancelOnError: false,
      );
    });
  }

  void _onData(List<int> data) {
    _buffer.write(utf8.decode(data));
    final content = _buffer.toString();
    final lines = content.split('\r\n');
    // Keep a trailing partial line (if any) in the buffer.
    final keepPartial = !content.endsWith('\r\n');
    _buffer.clear();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (keepPartial && i == lines.length - 1) {
        _buffer.write(line);
        continue;
      }
      _handleLine(line);
    }
  }

  void _handleLine(String line) {
    Map<String, dynamic> req;
    try {
      req = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    requests.add(req);
    final method = req['method'] as String?;
    final id = req['id'];
    if (method != null && _cannedResults.containsKey(method) && id != null) {
      sendLine(
        jsonEncode({
          'jsonrpc': '2.0',
          'result': _cannedResults[method],
          'id': id,
        }),
      );
    }
  }

  /// Register a canned RPC result for [method].
  void respondTo(String method, Object? result) {
    _cannedResults[method] = result;
  }

  /// Wait until the client TCP connection has been accepted.
  Future<void> awaitClient() => _connected.future;

  /// Wait until at least [count] requests have been received.
  Future<void> awaitRequests(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (requests.length < count) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'Timed out waiting for $count requests (got ${requests.length})',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Send a raw line to the connected client (a `\r\n` terminator is appended).
  void sendLine(String line) {
    _client?.write('$line\r\n');
  }

  /// Send a JSON event/message object to the client.
  void sendJson(Map<String, dynamic> message) {
    sendLine(jsonEncode(message));
  }

  /// Write [text] verbatim (no `\r\n` appended) and flush, then yield long
  /// enough for the bytes to land in the client's socket stream on their own.
  ///
  /// Used to split a single protocol frame across two TCP reads, which is what
  /// PHD2 does for any payload larger than the path MTU (e.g. `get_star_image`).
  Future<void> sendChunk(String text) async {
    final client = _client;
    if (client == null) return;
    client.write(text);
    await client.flush();
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }

  /// Write raw [bytes] verbatim and flush, with the same per-chunk delivery
  /// guarantee as [sendChunk]. Lets a test place a multi-byte UTF-8 sequence
  /// on the wire exactly as PHD2 encodes it.
  Future<void> sendRawBytes(List<int> bytes) async {
    final client = _client;
    if (client == null) return;
    client.add(bytes);
    await client.flush();
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }

  /// Send a JSON-RPC error response correlated to [id].
  void sendError(Object id, int code, String message) {
    sendJson({
      'jsonrpc': '2.0',
      'error': {'code': code, 'message': message},
      'id': id,
    });
  }

  Future<void> close() async {
    await _client?.close();
    await _serverSocket.close();
  }
}
