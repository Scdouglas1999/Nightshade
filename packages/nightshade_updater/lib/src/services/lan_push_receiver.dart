import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/update_manifest.dart';
import 'archive_extraction.dart';
import 'update_verifier.dart';

/// Callback for push progress updates
typedef PushProgressCallback = void Function(
  int receivedBytes,
  int totalBytes,
  double progress,
  String message,
);

/// Service for receiving LAN push updates from dev machine
class LanPushReceiver {
  static const int pushPort = 45680;

  /// Maximum time to wait for the authentication message before closing the connection
  static const Duration _authTimeout = Duration(seconds: 10);

  /// Hard cap on the total package bytes accepted over a single LAN push
  /// connection, independent of what the manifest claims (§7A.7). A
  /// malicious or mis-signed manifest could declare a giant
  /// `compressedSize` and fill the filesystem before signature failure
  /// is observed; this cap lets us bail before the disk is exhausted.
  /// 1 GiB matches the largest legitimate Nightshade installer by an
  /// order of magnitude, which leaves plenty of headroom.
  static const int maxPackageBytes = 1024 * 1024 * 1024;

  final String _currentVersion;
  final int _currentBuildNumber;
  final UpdateVerifier _verifier;
  final int _serverPort;

  /// Pre-shared key required from push clients for authentication.
  /// Must be set before starting the server. Generate with [generatePushSecret].
  String? _pushSecret;

  ServerSocket? _server;
  _ReceiveState _receiveState = _ReceiveState.idle;

  /// Callback when an update push is complete
  void Function(UpdateManifest manifest, String stagingPath)? onUpdateReceived;

  /// Callback for push progress
  PushProgressCallback? onProgress;

  /// Callback for errors
  void Function(String error)? onError;

  LanPushReceiver({
    required String currentVersion,
    required int currentBuildNumber,
    String? pushSecret,
    UpdateVerifier? verifier,
    int serverPort = pushPort,
  })  : _currentVersion = currentVersion,
        _currentBuildNumber = currentBuildNumber,
        _pushSecret = pushSecret,
        _serverPort = serverPort,
        _verifier = verifier ?? UpdateVerifier();

  /// Set the pre-shared push secret. Must be called before [startServer].
  void setPushSecret(String secret) {
    _pushSecret = secret;
  }

  /// Generate a cryptographically secure push secret (64 hex characters).
  static String generatePushSecret() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Current version info for discovery response
  Map<String, dynamic> get versionInfo => {
        'version': _currentVersion,
        'buildNumber': _currentBuildNumber,
        'isReceiving': _receiveState != _ReceiveState.idle,
      };

  /// Start listening for LAN push connections.
  /// A push secret must be configured via the constructor or [setPushSecret]
  /// before calling this method.
  ///
  /// Refuses to start if no `NIGHTSHADE_UPDATE_PUBLIC_KEY` was compiled
  /// into the build (§7A.7): without a trusted public key the receiver
  /// cannot verify the Ed25519 signature on the manifest, which means
  /// any LAN-attached attacker who guesses the push secret could ship
  /// arbitrary code. Better to be loudly disabled than silently
  /// vulnerable.
  Future<void> startServer() async {
    if (_server != null) return;

    if (!_verifier.hasTrustedPublicKey) {
      throw StateError(
        'LAN push receiver disabled: no trusted public key compiled in. '
        'Build with --dart-define=NIGHTSHADE_UPDATE_PUBLIC_KEY=... to enable.',
      );
    }

    if (_pushSecret == null || _pushSecret!.isEmpty) {
      throw StateError(
        'Push secret must be configured before starting the server. '
        'Call setPushSecret() or pass pushSecret to the constructor.',
      );
    }

    _server = await ServerSocket.bind(InternetAddress.anyIPv4, _serverPort);
    developer.log('Listening on port $_serverPort',
        name: 'LanPushReceiver', level: 800);

    _server!.listen(_handleConnection, onError: (error) {
      developer.log('Server error: $error',
          name: 'LanPushReceiver', level: 1000);
      onError?.call('Server error: $error');
    });
  }

  /// Stop the server
  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
  }

  /// Handle incoming connection from push tool.
  /// Requires the client to send an authentication message as the first frame:
  ///   4 bytes (big-endian): length of auth JSON
  ///   N bytes: JSON with {"secret": "<push_secret>"}
  /// The server responds with {"auth": "ok"} or {"auth": "rejected"} and closes.
  void _handleConnection(Socket socket) async {
    final remoteAddress = socket.remoteAddress.address;
    developer.log('Connection from $remoteAddress',
        name: 'LanPushReceiver', level: 800);

    if (_receiveState != _ReceiveState.idle) {
      socket.write(jsonEncode({'error': 'Already receiving update'}));
      await socket.close();
      return;
    }

    _receiveState = _ReceiveState.authenticating;

    // --- Authentication phase ---
    try {
      final authenticated = await _authenticateClient(socket, remoteAddress);
      if (!authenticated) {
        return; // socket already closed by _authenticateClient
      }
    } catch (e) {
      developer.log(
        'Auth error from $remoteAddress: $e',
        name: 'LanPushReceiver',
        level: 1000,
      );
      try {
        socket.write(jsonEncode({'auth': 'rejected', 'reason': 'auth error'}));
        await socket.close();
      } catch (_) {}
      return;
    }

    _receiveState = _ReceiveState.receiving;
    onProgress?.call(0, 0, 0, 'Authenticated connection from $remoteAddress');

    try {
      await _receiveUpdate(socket);
    } catch (e) {
      developer.log('Error receiving update: $e',
          name: 'LanPushReceiver', level: 1000);
      onError?.call(e.toString());
    } finally {
      _receiveState = _ReceiveState.idle;
      await socket.close();
    }
  }

  /// Authenticate an incoming client connection.
  /// Protocol: client sends [4-byte big-endian length][JSON {"secret":"..."}].
  /// Returns true if authenticated, false otherwise (socket is closed on failure).
  Future<bool> _authenticateClient(Socket socket, String remoteAddress) async {
    final authBuffer = BytesBuilder();
    final completer = Completer<bool>();

    late StreamSubscription<Uint8List> subscription;
    Timer? timeout;

    timeout = Timer(_authTimeout, () {
      if (!completer.isCompleted) {
        developer.log(
          'Auth timeout from $remoteAddress',
          name: 'LanPushReceiver',
          level: 900,
        );
        socket.write(jsonEncode({'auth': 'rejected', 'reason': 'timeout'}));
        socket.close();
        subscription.cancel();
        completer.complete(false);
      }
    });

    subscription = socket.listen(
      (data) {
        authBuffer.add(data);
        final bytes = authBuffer.toBytes();

        // Need at least 4 bytes for the length prefix
        if (bytes.length < 4) return;

        final authLen =
            ByteData.view(Uint8List.fromList(bytes.sublist(0, 4)).buffer)
                .getInt32(0, Endian.big);

        // Sanity check: auth message should be small (< 4KB)
        if (authLen <= 0 || authLen > 4096) {
          developer.log(
            'Invalid auth length $authLen from $remoteAddress',
            name: 'LanPushReceiver',
            level: 1000,
          );
          socket.write(
              jsonEncode({'auth': 'rejected', 'reason': 'invalid frame'}));
          socket.close();
          subscription.cancel();
          timeout?.cancel();
          if (!completer.isCompleted) completer.complete(false);
          return;
        }

        // Wait until we have the full auth message
        if (bytes.length < 4 + authLen) return;

        // Parse the auth JSON
        subscription.cancel();
        timeout?.cancel();

        try {
          final authJson = utf8.decode(bytes.sublist(4, 4 + authLen));
          final authData = jsonDecode(authJson) as Map<String, dynamic>;
          final clientSecret = authData['secret'] as String?;

          if (clientSecret == null ||
              !_constantTimeCompare(clientSecret, _pushSecret!)) {
            developer.log(
              'Invalid push secret from $remoteAddress',
              name: 'LanPushReceiver',
              level: 1000,
            );
            socket.write(
                jsonEncode({'auth': 'rejected', 'reason': 'invalid secret'}));
            socket.close();
            if (!completer.isCompleted) completer.complete(false);
            return;
          }

          // Authentication successful
          developer.log(
            'Authenticated push client from $remoteAddress',
            name: 'LanPushReceiver',
            level: 800,
          );
          socket.write(jsonEncode({'auth': 'ok'}));
          if (!completer.isCompleted) completer.complete(true);
        } catch (e) {
          developer.log(
            'Failed to parse auth from $remoteAddress: $e',
            name: 'LanPushReceiver',
            level: 1000,
          );
          socket
              .write(jsonEncode({'auth': 'rejected', 'reason': 'parse error'}));
          socket.close();
          if (!completer.isCompleted) completer.complete(false);
        }
      },
      onError: (error) {
        timeout?.cancel();
        subscription.cancel();
        if (!completer.isCompleted) completer.complete(false);
      },
      onDone: () {
        timeout?.cancel();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    return completer.future;
  }

  /// Constant-time string comparison to prevent timing attacks
  static bool _constantTimeCompare(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Receive update data from socket
  Future<void> _receiveUpdate(Socket socket) async {
    // Protocol:
    // 1. Receive manifest length (4 bytes, big-endian)
    // 2. Receive manifest JSON
    // 3. Receive package data

    final buffer = BytesBuilder();
    UpdateManifest? manifest;
    int? manifestLength;
    int? packageSize;
    int receivedPackageBytes = 0;
    File? packageFile;
    IOSink? packageSink;

    final staging = await _getStagingDirectory();
    final packagePath = path.join(staging.path, 'update.zip');

    // Why try/finally: a throw inside the for-await loop (e.g. signature
    // failure, size-cap breach) used to leak the open package sink and
    // leave a partial update.zip on disk. Closing in finally guarantees
    // the file handle is released so the next attempt can re-open it
    // (and a separate cleanup below removes the partial bytes on
    // failure).
    var receiveSucceeded = false;
    try {
      await for (final chunk in socket) {
        buffer.add(chunk);

        // Step 1: Read manifest length
        if (manifestLength == null && buffer.length >= 4) {
          final bytes = buffer.takeBytes();
          manifestLength =
              ByteData.view(Uint8List.fromList(bytes.sublist(0, 4)).buffer)
                  .getInt32(0, Endian.big);
          buffer.add(bytes.sublist(4));
          onProgress?.call(0, 0, 0, 'Receiving manifest...');
        }

        // Step 2: Read manifest JSON
        if (manifest == null &&
            manifestLength != null &&
            buffer.length >= manifestLength) {
          final bytes = buffer.takeBytes();
          final manifestJson = utf8.decode(bytes.sublist(0, manifestLength));
          manifest = UpdateManifest.fromJson(
            jsonDecode(manifestJson) as Map<String, dynamic>,
          );
          // §7A.7: verify signature BEFORE we open update.zip for write
          // so a forged or unsigned manifest can never trigger
          // filesystem allocation.
          final manifestVerified =
              await _verifier.verifyManifestSignature(manifest);
          if (!manifestVerified) {
            throw Exception('Update manifest signature verification failed');
          }
          packageSize = manifest.compressedSize;

          // §7A.7: hard cap independent of manifest. Even after
          // signature verification we refuse oversized packages to
          // bound the worst case (e.g. a signed manifest with an
          // absurdly large size).
          if (packageSize > maxPackageBytes) {
            throw Exception(
              'Update package too large: $packageSize bytes exceeds '
              'LAN push hard cap of $maxPackageBytes bytes',
            );
          }

          // Open file for writing package
          packageFile = File(packagePath);
          packageSink = packageFile.openWrite();

          // Write remaining bytes to package
          final remaining = bytes.sublist(manifestLength);
          if (remaining.isNotEmpty) {
            packageSink.add(remaining);
            receivedPackageBytes += remaining.length;
          }

          onProgress?.call(
            receivedPackageBytes,
            packageSize,
            receivedPackageBytes / packageSize,
            'Receiving ${manifest.version}...',
          );

          // Send acknowledgment
          socket.write(jsonEncode({
            'status': 'receiving',
            'version': manifest.version,
          }));

          buffer.clear();
          continue;
        }

        // Step 3: Write package data
        if (manifest != null && packageSink != null) {
          final bytes = buffer.takeBytes();
          packageSink.add(bytes);
          receivedPackageBytes += bytes.length;

          // §7A.7: belt-and-suspenders cap on accumulated bytes. The
          // earlier manifest-size check is the primary defence; this
          // guards against a future code path that lets bytes through
          // without honouring `packageSize` (e.g. resumable transfers).
          if (receivedPackageBytes > maxPackageBytes) {
            throw Exception(
              'LAN push exceeded hard cap of $maxPackageBytes bytes '
              '(received $receivedPackageBytes)',
            );
          }

          onProgress?.call(
            receivedPackageBytes,
            packageSize!,
            receivedPackageBytes / packageSize,
            'Receiving ${manifest.version}...',
          );

          // Break out of loop once we've received all expected bytes
          if (receivedPackageBytes >= packageSize!) {
            developer.log(
                'All $receivedPackageBytes bytes received, breaking out of receive loop',
                name: 'LanPushReceiver');
            break;
          }
        }
      }
      receiveSucceeded = true;
    } finally {
      // Always release the file handle; otherwise a thrown error leaves
      // update.zip locked and the next push fails with a Windows
      // sharing-violation error.
      await packageSink?.close();
      if (!receiveSucceeded &&
          packageFile != null &&
          await packageFile.exists()) {
        // Why: a partial write is not a recoverable artefact — it
        // contains untrusted bytes that failed our cap or signature
        // checks. Leaving it on disk would let the verify step later
        // pick up garbage.
        try {
          await packageFile.delete();
        } catch (deleteError) {
          developer.log(
            'Failed to remove partial update.zip after receive error: '
            '$deleteError',
            name: 'LanPushReceiver',
            level: 1000,
          );
        }
      }
    }

    if (manifest == null || packageFile == null) {
      throw Exception('Incomplete transfer');
    }

    // Verify package size
    final actualSize = await packageFile.length();
    if (actualSize != manifest.compressedSize) {
      await packageFile.delete();
      throw Exception(
        'Size mismatch: expected ${manifest.compressedSize}, got $actualSize',
      );
    }

    onProgress?.call(actualSize, actualSize, 1.0, 'Extracting...');

    // Extract package
    final extractDir = Directory(path.join(staging.path, 'extracted'));
    if (await extractDir.exists()) {
      await extractDir.delete(recursive: true);
    }
    await extractDir.create(recursive: true);

    await extractZipSafely(packageFile, extractDir);

    onProgress?.call(actualSize, actualSize, 1.0, 'Verifying...');

    // Verify extracted files
    final verification = await _verifier.verifyDirectory(extractDir, manifest);
    if (!verification.success) {
      await extractDir.delete(recursive: true);
      throw Exception('Verification failed: $verification');
    }

    // Write ready marker
    final markerFile = File(path.join(staging.path, 'ready.json'));
    developer.log('Writing ready marker to: ${markerFile.path}',
        name: 'LanPushReceiver');
    await markerFile.writeAsString(jsonEncode({
      'version': manifest.version,
      'buildNumber': manifest.buildNumber,
      'stagedAt': DateTime.now().toIso8601String(),
      'extractPath': extractDir.path,
      'source': 'lan_push',
    }));
    developer.log('Ready marker written successfully', name: 'LanPushReceiver');

    // Send success response (may fail if pusher already disconnected, which is OK)
    try {
      socket.write(jsonEncode({
        'status': 'complete',
        'version': manifest.version,
      }));
      await socket.flush();
    } catch (e) {
      // Pusher may have disconnected - that's fine, update is complete
      developer.log(
          'Could not send completion response (pusher disconnected): $e',
          name: 'LanPushReceiver',
          level: 900);
    }

    onProgress?.call(actualSize, actualSize, 1.0, 'Update ready!');
    onUpdateReceived?.call(manifest, extractDir.path);
  }

  /// Get staging directory
  Future<Directory> _getStagingDirectory() async {
    final appData = await getApplicationSupportDirectory();
    final staging = Directory(path.join(appData.path, 'updates', 'staging'));
    if (!await staging.exists()) {
      await staging.create(recursive: true);
    }
    return staging;
  }

  /// Dispose resources
  void dispose() {
    stopServer();
  }
}

enum _ReceiveState {
  idle,
  authenticating,
  receiving,
}
