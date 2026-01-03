import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/update_manifest.dart';
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

  final String _currentVersion;
  final int _currentBuildNumber;
  final UpdateVerifier _verifier;

  ServerSocket? _server;
  bool _isReceiving = false;

  /// Callback when an update push is complete
  void Function(UpdateManifest manifest, String stagingPath)? onUpdateReceived;

  /// Callback for push progress
  PushProgressCallback? onProgress;

  /// Callback for errors
  void Function(String error)? onError;

  LanPushReceiver({
    required String currentVersion,
    required int currentBuildNumber,
    UpdateVerifier? verifier,
  })  : _currentVersion = currentVersion,
        _currentBuildNumber = currentBuildNumber,
        _verifier = verifier ?? UpdateVerifier();

  /// Current version info for discovery response
  Map<String, dynamic> get versionInfo => {
        'version': _currentVersion,
        'buildNumber': _currentBuildNumber,
        'isReceiving': _isReceiving,
      };

  /// Start listening for LAN push connections
  Future<void> startServer() async {
    if (_server != null) return;

    _server = await ServerSocket.bind(InternetAddress.anyIPv4, pushPort);
    print('[LanPushReceiver] Listening on port $pushPort');

    _server!.listen(_handleConnection, onError: (error) {
      print('[LanPushReceiver] Server error: $error');
      onError?.call('Server error: $error');
    });
  }

  /// Stop the server
  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
  }

  /// Handle incoming connection from push tool
  void _handleConnection(Socket socket) async {
    final remoteAddress = socket.remoteAddress.address;
    print('[LanPushReceiver] Connection from $remoteAddress');

    if (_isReceiving) {
      // Already receiving an update, reject
      socket.write(jsonEncode({'error': 'Already receiving update'}));
      await socket.close();
      return;
    }

    _isReceiving = true;
    onProgress?.call(0, 0, 0, 'Connected to $remoteAddress');

    try {
      await _receiveUpdate(socket);
    } catch (e) {
      print('[LanPushReceiver] Error receiving update: $e');
      onError?.call(e.toString());
    } finally {
      _isReceiving = false;
      await socket.close();
    }
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

    await for (final chunk in socket) {
      buffer.add(chunk);

      // Step 1: Read manifest length
      if (manifestLength == null && buffer.length >= 4) {
        final bytes = buffer.takeBytes();
        manifestLength = ByteData.view(Uint8List.fromList(bytes.sublist(0, 4)).buffer)
            .getInt32(0, Endian.big);
        buffer.add(bytes.sublist(4));
        onProgress?.call(0, 0, 0, 'Receiving manifest...');
      }

      // Step 2: Read manifest JSON
      if (manifest == null && manifestLength != null && buffer.length >= manifestLength) {
        final bytes = buffer.takeBytes();
        final manifestJson = utf8.decode(bytes.sublist(0, manifestLength));
        manifest = UpdateManifest.fromJson(
          jsonDecode(manifestJson) as Map<String, dynamic>,
        );
        packageSize = manifest.compressedSize;

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

        onProgress?.call(
          receivedPackageBytes,
          packageSize!,
          receivedPackageBytes / packageSize,
          'Receiving ${manifest.version}...',
        );

        // Break out of loop once we've received all expected bytes
        if (receivedPackageBytes >= packageSize!) {
          print('[LanPushReceiver] All $receivedPackageBytes bytes received, breaking out of receive loop');
          break;
        }
      }
    }

    // Close package file
    await packageSink?.close();

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

    await _extractZip(packageFile, extractDir);

    onProgress?.call(actualSize, actualSize, 1.0, 'Verifying...');

    // Verify extracted files
    final verification = await _verifier.verifyDirectory(extractDir, manifest);
    if (!verification.success) {
      await extractDir.delete(recursive: true);
      throw Exception('Verification failed: $verification');
    }

    // Write ready marker
    final markerFile = File(path.join(staging.path, 'ready.json'));
    print('[LanPushReceiver] Writing ready marker to: ${markerFile.path}');
    await markerFile.writeAsString(jsonEncode({
      'version': manifest.version,
      'buildNumber': manifest.buildNumber,
      'stagedAt': DateTime.now().toIso8601String(),
      'extractPath': extractDir.path,
      'source': 'lan_push',
    }));
    print('[LanPushReceiver] Ready marker written successfully');

    // Send success response (may fail if pusher already disconnected, which is OK)
    try {
      socket.write(jsonEncode({
        'status': 'complete',
        'version': manifest.version,
      }));
      await socket.flush();
    } catch (e) {
      // Pusher may have disconnected - that's fine, update is complete
      print('[LanPushReceiver] Could not send completion response (pusher disconnected): $e');
    }

    onProgress?.call(actualSize, actualSize, 1.0, 'Update ready!');
    onUpdateReceived?.call(manifest, extractDir.path);
  }

  /// Extract ZIP archive
  Future<void> _extractZip(File zipFile, Directory destination) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filePath = path.join(destination.path, file.name);

      if (file.isFile) {
        final outFile = File(filePath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }
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
