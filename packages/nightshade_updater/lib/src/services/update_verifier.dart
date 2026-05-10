import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;
import '../models/update_manifest.dart';

/// Service for verifying update package integrity
class UpdateVerifier {
  final String _trustedPublicKeyBase64;
  final Ed25519 _signatureAlgorithm;

  UpdateVerifier({
    String trustedPublicKeyBase64 = const String.fromEnvironment(
      'NIGHTSHADE_UPDATE_PUBLIC_KEY',
    ),
    Ed25519? signatureAlgorithm,
  })  : _trustedPublicKeyBase64 = trustedPublicKeyBase64,
        _signatureAlgorithm = signatureAlgorithm ?? Ed25519();

  /// Whether this verifier has a trusted Ed25519 public key compiled in.
  ///
  /// Used by entry points like the LAN push receiver to refuse to start
  /// when no key is available (§7A.7) — without a key, signature
  /// verification cannot run and an attacker on the LAN could push an
  /// unsigned manifest. Returning false here means "this build cannot
  /// authenticate any update; do not accept update bytes."
  bool get hasTrustedPublicKey => _trustedPublicKeyBase64.isNotEmpty;

  /// Calculate SHA256 hash of a file
  Future<String> hashFile(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// Calculate SHA256 hash of bytes
  String hashBytes(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Verify a single file against expected hash
  Future<bool> verifyFile(File file, String expectedHash) async {
    if (!await file.exists()) {
      return false;
    }
    final actualHash = await hashFile(file);
    return actualHash.toLowerCase() == expectedHash.toLowerCase();
  }

  /// Verify all files in a directory against manifest
  Future<VerificationResult> verifyDirectory(
    Directory directory,
    UpdateManifest manifest,
  ) async {
    final missingFiles = <String>[];
    final corruptedFiles = <String, String>{};
    final verifiedFiles = <String>[];

    for (final entry in manifest.files.entries) {
      final relativePath = entry.key;
      final fileInfo = entry.value;
      final file = await _resolveManifestFile(directory, relativePath);
      if (file == null) {
        corruptedFiles[relativePath] = 'unsafe path';
        continue;
      }

      if (!await file.exists()) {
        missingFiles.add(relativePath);
        continue;
      }

      final actualHash = await hashFile(file);
      if (actualHash.toLowerCase() != fileInfo.sha256.toLowerCase()) {
        corruptedFiles[relativePath] = actualHash;
      } else {
        verifiedFiles.add(relativePath);
      }
    }

    return VerificationResult(
      success: missingFiles.isEmpty && corruptedFiles.isEmpty,
      verifiedFiles: verifiedFiles,
      missingFiles: missingFiles,
      corruptedFiles: corruptedFiles,
    );
  }

  Future<File?> _resolveManifestFile(
    Directory directory,
    String relativePath,
  ) async {
    final portablePath = relativePath.replaceAll('\\', '/');
    if (portablePath.isEmpty ||
        path.posix.isAbsolute(portablePath) ||
        RegExp(r'^[a-zA-Z]:/').hasMatch(portablePath) ||
        portablePath.startsWith('//')) {
      return null;
    }

    final normalized = path.posix.normalize(portablePath);
    if (normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        normalized.contains('/../') ||
        normalized.split('/').any((part) => part.isEmpty || part == '.')) {
      return null;
    }

    final root = await directory.resolveSymbolicLinks();
    final file = File(path.joinAll([root, ...normalized.split('/')]));
    if (await file.exists()) {
      final resolvedFile = await file.resolveSymbolicLinks();
      if (!_isWithinDirectory(root, resolvedFile)) {
        return null;
      }
    }
    return file;
  }

  bool _isWithinDirectory(String root, String candidate) {
    final normalizedRoot = _normalizeForComparison(path.normalize(root));
    final normalizedCandidate =
        _normalizeForComparison(path.normalize(candidate));
    if (normalizedCandidate == normalizedRoot) {
      return true;
    }
    final rootWithSeparator = normalizedRoot.endsWith(path.separator)
        ? normalizedRoot
        : '$normalizedRoot${path.separator}';
    return normalizedCandidate.startsWith(rootWithSeparator);
  }

  String _normalizeForComparison(String value) {
    return Platform.isWindows ? value.toLowerCase() : value;
  }

  /// Verify a downloaded package (ZIP file) before extraction
  Future<bool> verifyPackage(
    File packageFile,
    UpdateManifest manifest,
  ) async {
    if (!await packageFile.exists()) {
      return false;
    }

    // Check size
    final actualSize = await packageFile.length();
    if (actualSize != manifest.compressedSize) {
      return false;
    }

    if (manifest.packageSha256 == null || manifest.packageSha256!.isEmpty) {
      return false;
    }

    final actualHash = await hashFile(packageFile);
    if (actualHash.toLowerCase() != manifest.packageSha256!.toLowerCase()) {
      return false;
    }

    if (!_requiresManifestSignature(manifest)) {
      return true;
    }

    return verifyManifestSignature(manifest);
  }

  Future<bool> verifyManifestSignature(UpdateManifest manifest) async {
    if (manifest.signature == null ||
        manifest.signature!.isEmpty ||
        _trustedPublicKeyBase64.isEmpty) {
      return false;
    }

    try {
      final payloadBytes = utf8.encode(_canonicalManifestPayload(manifest));
      final publicKey = SimplePublicKey(
        base64Decode(_trustedPublicKeyBase64),
        type: KeyPairType.ed25519,
      );
      final signature = Signature(
        base64Decode(manifest.signature!),
        publicKey: publicKey,
      );
      return await _signatureAlgorithm.verify(payloadBytes,
          signature: signature);
    } catch (e) {
      developer.log(
        'Signature verification error: $e',
        name: 'UpdateVerifier',
        level: 900,
      );
      return false;
    }
  }

  String _canonicalManifestPayload(UpdateManifest manifest) {
    final sortedFiles = manifest.files.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final payload = <String, dynamic>{
      'version': manifest.version,
      'buildNumber': manifest.buildNumber,
      'releaseDate': manifest.releaseDate.toUtc().toIso8601String(),
      'platform': manifest.platform,
      'arch': manifest.arch,
      'minVersion': manifest.minVersion,
      'files': {
        for (final entry in sortedFiles)
          entry.key: {
            'path': entry.value.path,
            'size': entry.value.size,
            'sha256': entry.value.sha256,
          },
      },
      'totalSize': manifest.totalSize,
      'compressedSize': manifest.compressedSize,
      'packageSha256': manifest.packageSha256,
      'downloadUrl': manifest.downloadUrl,
      'releaseNotes': manifest.releaseNotes,
    };
    return jsonEncode(payload);
  }

  bool _requiresManifestSignature(UpdateManifest manifest) {
    final hasTrustedKey = _trustedPublicKeyBase64.isNotEmpty;
    final hasSignature =
        manifest.signature != null && manifest.signature!.isNotEmpty;
    return hasTrustedKey || hasSignature;
  }
}

/// Result of verifying a directory against a manifest
class VerificationResult {
  final bool success;
  final List<String> verifiedFiles;
  final List<String> missingFiles;
  final Map<String, String> corruptedFiles; // path -> actual hash

  VerificationResult({
    required this.success,
    required this.verifiedFiles,
    required this.missingFiles,
    required this.corruptedFiles,
  });

  @override
  String toString() {
    if (success) {
      return 'Verification successful: ${verifiedFiles.length} files verified';
    }
    final issues = <String>[];
    if (missingFiles.isNotEmpty) {
      issues.add('Missing: ${missingFiles.join(", ")}');
    }
    if (corruptedFiles.isNotEmpty) {
      issues.add('Corrupted: ${corruptedFiles.keys.join(", ")}');
    }
    return 'Verification failed: ${issues.join("; ")}';
  }
}
