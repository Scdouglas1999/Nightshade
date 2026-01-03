import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../models/update_manifest.dart';

/// Service for verifying update package integrity
class UpdateVerifier {
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
      final file = File('${directory.path}/$relativePath');

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

  /// Verify a downloaded package (ZIP file) before extraction
  Future<bool> verifyPackage(
    File packageFile,
    int expectedSize,
    String? expectedHash,
  ) async {
    if (!await packageFile.exists()) {
      return false;
    }

    // Check size
    final actualSize = await packageFile.length();
    if (actualSize != expectedSize) {
      return false;
    }

    // Check hash if provided
    if (expectedHash != null) {
      final actualHash = await hashFile(packageFile);
      if (actualHash.toLowerCase() != expectedHash.toLowerCase()) {
        return false;
      }
    }

    return true;
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
