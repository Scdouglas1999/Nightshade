import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Callback for download progress updates
typedef DownloadProgressCallback = void Function(
  int downloadedBytes,
  int totalBytes,
  double progress,
);

/// Service for downloading update packages with progress tracking
class UpdateDownloader {
  final http.Client _client;

  UpdateDownloader({http.Client? client}) : _client = client ?? http.Client();

  /// Download a file from URL to destination with progress tracking
  ///
  /// Supports resume via Range header if server supports it.
  Future<File> download(
    String url,
    String destinationPath, {
    DownloadProgressCallback? onProgress,
    int? expectedSize,
  }) async {
    final destination = File(destinationPath);
    final parent = destination.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    // Check for partial download (for resume support)
    int existingBytes = 0;
    if (await destination.exists()) {
      existingBytes = await destination.length();
    }

    // Make request with Range header if resuming
    final request = http.Request('GET', Uri.parse(url));
    if (existingBytes > 0) {
      request.headers['Range'] = 'bytes=$existingBytes-';
    }

    final streamedResponse = await _client.send(request);

    // Check if server supports range requests
    final isPartialContent = streamedResponse.statusCode == 206;
    final isFullContent = streamedResponse.statusCode == 200;

    if (!isPartialContent && !isFullContent) {
      throw DownloadException(
        'Server returned ${streamedResponse.statusCode}',
        streamedResponse.statusCode,
      );
    }

    // If full content, we need to start fresh
    if (isFullContent && existingBytes > 0) {
      existingBytes = 0;
      await destination.delete();
    }

    // Determine total size
    int totalBytes;
    if (isPartialContent) {
      // Parse Content-Range header: bytes 1000-2000/3000
      final contentRange = streamedResponse.headers['content-range'];
      if (contentRange != null) {
        final match = RegExp(r'bytes \d+-\d+/(\d+)').firstMatch(contentRange);
        totalBytes = match != null ? int.parse(match.group(1)!) : expectedSize ?? 0;
      } else {
        totalBytes = expectedSize ?? existingBytes + streamedResponse.contentLength!;
      }
    } else {
      totalBytes = streamedResponse.contentLength ?? expectedSize ?? 0;
    }

    // Open file for writing (append if resuming)
    final sink = destination.openWrite(mode: isPartialContent ? FileMode.append : FileMode.write);

    int downloadedBytes = existingBytes;

    try {
      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        if (onProgress != null && totalBytes > 0) {
          final progress = downloadedBytes / totalBytes;
          onProgress(downloadedBytes, totalBytes, progress.clamp(0.0, 1.0));
        }
      }
    } finally {
      await sink.close();
    }

    return destination;
  }

  /// Check if a URL supports range requests (for resume)
  Future<bool> supportsResume(String url) async {
    try {
      final response = await _client.head(Uri.parse(url));
      return response.headers['accept-ranges'] == 'bytes';
    } catch (e) {
      return false;
    }
  }

  /// Get the content length of a URL without downloading
  Future<int?> getContentLength(String url) async {
    try {
      final response = await _client.head(Uri.parse(url));
      final length = response.headers['content-length'];
      return length != null ? int.tryParse(length) : null;
    } catch (e) {
      return null;
    }
  }

  /// Cancel any ongoing downloads (dispose the client)
  void dispose() {
    _client.close();
  }
}

/// Exception thrown when download fails
class DownloadException implements Exception {
  final String message;
  final int? statusCode;

  DownloadException(this.message, [this.statusCode]);

  @override
  String toString() => 'DownloadException: $message (status: $statusCode)';
}
