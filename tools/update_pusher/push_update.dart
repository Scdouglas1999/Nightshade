/// Nightshade Update Pusher
///
/// CLI tool to push updates to Nightshade instances on the local network.
/// Usage:
///   dart run tools/update_pusher/push_update.dart --discover
///   dart run tools/update_pusher/push_update.dart --push --target 192.168.1.50
///   dart run tools/update_pusher/push_update.dart --push --all

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int discoveryPort = 45679;
const int pushPort = 45680;
const String updatePushMessage = 'NIGHTSHADE_UPDATE_PUSH';
const String updateResponsePrefix = 'NIGHTSHADE_UPDATE_TARGET:';

class UpdateTarget {
  final String host;
  final int port;
  final String name;
  final String version;
  final int buildNumber;
  final bool isReceiving;

  UpdateTarget({
    required this.host,
    required this.port,
    required this.name,
    required this.version,
    required this.buildNumber,
    required this.isReceiving,
  });

  @override
  String toString() => '$name v$version ($host:$port)';
}

Future<void> main(List<String> args) async {
  print('Nightshade Update Pusher');
  print('========================\n');

  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    printUsage();
    return;
  }

  if (args.contains('--discover')) {
    await discoverTargets();
    return;
  }

  if (args.contains('--push')) {
    final packagePath = getArg(args, '--package') ?? findDefaultPackage();
    if (packagePath == null) {
      print('Error: No update package found. Run build_update_package.ps1 first.');
      exit(1);
    }

    final manifestPath = getArg(args, '--manifest') ?? findDefaultManifest();
    if (manifestPath == null) {
      print('Error: No manifest found. Run build_update_package.ps1 first.');
      exit(1);
    }

    if (args.contains('--all')) {
      await pushToAll(packagePath, manifestPath);
    } else {
      final target = getArg(args, '--target');
      if (target == null) {
        print('Error: Specify --target <ip> or --all');
        exit(1);
      }
      await pushToTarget(target, pushPort, packagePath, manifestPath);
    }
    return;
  }

  printUsage();
}

void printUsage() {
  print('Usage:');
  print('  dart run tools/update_pusher/push_update.dart --discover');
  print('    Discover Nightshade instances on the network\n');
  print('  dart run tools/update_pusher/push_update.dart --push --all');
  print('    Push update to all discovered instances\n');
  print('  dart run tools/update_pusher/push_update.dart --push --target <ip>');
  print('    Push update to a specific instance\n');
  print('Options:');
  print('  --package <path>   Path to update package (default: auto-detect)');
  print('  --manifest <path>  Path to manifest.json (default: auto-detect)');
}

String? getArg(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index >= 0 && index < args.length - 1) {
    return args[index + 1];
  }
  return null;
}

String? findDefaultPackage() {
  final candidates = [
    'apps/desktop/build/update/nightshade-update.zip',
    'build/update/nightshade-update.zip',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) {
      return path;
    }
  }
  return null;
}

String? findDefaultManifest() {
  final candidates = [
    'apps/desktop/build/update/manifest.json',
    'build/update/manifest.json',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) {
      return path;
    }
  }
  return null;
}

Future<List<UpdateTarget>> discoverTargets() async {
  print('Discovering Nightshade instances...\n');

  final targets = <UpdateTarget>[];
  final seen = <String>{};

  try {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;

    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          try {
            final message = utf8.decode(datagram.data);
            if (message.startsWith(updateResponsePrefix)) {
              final jsonStr = message.substring(updateResponsePrefix.length);
              final info = jsonDecode(jsonStr) as Map<String, dynamic>;
              final host = datagram.address.address;
              final key = '$host:${info['pushPort']}';

              if (!seen.contains(key)) {
                seen.add(key);
                final target = UpdateTarget(
                  host: host,
                  port: info['pushPort'] as int? ?? pushPort,
                  name: info['name'] as String? ?? 'Nightshade',
                  version: info['version'] as String? ?? 'unknown',
                  buildNumber: info['buildNumber'] as int? ?? 0,
                  isReceiving: info['isReceiving'] as bool? ?? false,
                );
                targets.add(target);
                print('  Found: $target${target.isReceiving ? " (busy)" : ""}');
              }
            }
          } catch (e) {
            // Ignore parse errors
          }
        }
      }
    });

    // Send discovery broadcast
    final discoveryData = utf8.encode(updatePushMessage);
    socket.send(discoveryData, InternetAddress('255.255.255.255'), discoveryPort);

    // Wait for responses
    await Future.delayed(const Duration(seconds: 3));
    socket.close();
  } catch (e) {
    print('Discovery error: $e');
  }

  if (targets.isEmpty) {
    print('No Nightshade instances found on the network.');
  } else {
    print('\nFound ${targets.length} instance(s).');
  }

  return targets;
}

Future<void> pushToAll(String packagePath, String manifestPath) async {
  final targets = await discoverTargets();
  if (targets.isEmpty) {
    print('\nNo targets to push to.');
    return;
  }

  print('\nPushing update to ${targets.length} target(s)...\n');

  for (final target in targets) {
    if (target.isReceiving) {
      print('Skipping ${target.name} (busy receiving another update)');
      continue;
    }
    await pushToTarget(target.host, target.port, packagePath, manifestPath);
  }
}

Future<void> pushToTarget(
  String host,
  int port,
  String packagePath,
  String manifestPath,
) async {
  print('Pushing to $host:$port...');

  try {
    // Read manifest
    final manifestContent = await File(manifestPath).readAsString();
    final manifest = jsonDecode(manifestContent) as Map<String, dynamic>;
    print('  Version: ${manifest['version']}');

    // Read package
    final packageFile = File(packagePath);
    final packageSize = await packageFile.length();
    print('  Package size: ${(packageSize / 1024 / 1024).toStringAsFixed(1)} MB');

    // Connect to target
    final socket = await Socket.connect(host, port);
    print('  Connected.');

    // Send manifest length (4 bytes, big-endian)
    final manifestBytes = utf8.encode(manifestContent);
    final lengthBytes = ByteData(4);
    lengthBytes.setInt32(0, manifestBytes.length, Endian.big);
    socket.add(lengthBytes.buffer.asUint8List());

    // Send manifest
    socket.add(manifestBytes);
    print('  Manifest sent.');

    // Wait for acknowledgment
    await socket.flush();

    // Send package in chunks with progress, flushing periodically
    final packageStream = packageFile.openRead();
    int sent = 0;
    int lastPercent = 0;
    int chunksSinceFlush = 0;

    await for (final chunk in packageStream) {
      socket.add(chunk);
      sent += chunk.length;
      chunksSinceFlush++;

      // Flush every 100 chunks (~6MB) to ensure data is sent
      if (chunksSinceFlush >= 100) {
        await socket.flush();
        chunksSinceFlush = 0;
      }

      final percent = (sent * 100 / packageSize).round();
      if (percent > lastPercent) {
        lastPercent = percent;
        stdout.write('\r  Uploading: $percent%');
      }
    }
    print('\r  Upload complete.     ');

    // Final flush to ensure all data is sent
    await socket.flush();

    // Close the socket to signal end-of-data to receiver
    // This allows the receiver's read loop to exit and process the update
    print('  Closing connection to signal end of transfer...');
    await socket.close();

    print('  Update sent successfully!');
    print('  The receiver will now verify and stage the update.');
    print('  Check the target machine for the update banner.');
  } catch (e) {
    print('  Failed: $e');
  }
}
