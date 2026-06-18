part of '../catalog_manager.dart';

extension CatalogManagerLegacyIo on CatalogManager {
  /// Download and install star catalog
  Future<bool> _downloadStarCatalog({
    CatalogPackage package = CatalogPackage.standard,
    void Function(DownloadProgress)? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    return _downloadCatalog(
      source: hygStarCatalog,
      type: 'stars',
      package: package,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  /// Download and install DSO catalog
  Future<bool> _downloadDsoCatalog({
    CatalogPackage package = CatalogPackage.standard,
    void Function(DownloadProgress)? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    return _downloadCatalog(
      source: openNgcCatalog,
      type: 'dso',
      package: package,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  Future<bool> _downloadCatalog({
    required CatalogSource source,
    required String type,
    required CatalogPackage package,
    void Function(DownloadProgress)? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    developer.log(
      '[Catalog] Starting download of ${source.name} from ${source.downloadUrl}',
      name: 'CatalogManager',
      level: 800,
    );

    _emitProgress(
      DownloadProgress.starting(source.name, catalogKey: type),
      onProgress,
    );

    // Download into a sibling `.partial` file and only promote it onto the
    // live catalog path once the bytes are fully written and validated. This
    // keeps an existing install intact if the download fails or is abandoned
    // mid-flight, and guarantees the final path is never a truncated file.
    final filePath = path.join(catalogDirectory, source.fileName);
    final tempPath = '$filePath.partial';
    final tempFile = File(tempPath);

    try {
      // Ensure catalog directory exists
      if (!isInitialized) {
        throw StateError('CatalogManager not initialized');
      }

      final dir = Directory(catalogDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Use http package for better cross-platform compatibility
      final client = http.Client();

      try {
        developer.log(
          '[Catalog] Sending HTTP GET request to ${source.downloadUrl}',
          name: 'CatalogManager',
          level: 800,
        );

        final request = http.Request('GET', Uri.parse(source.downloadUrl));
        final streamedResponse = await client.send(request);

        developer.log(
          '[Catalog] Response status: ${streamedResponse.statusCode}',
          name: 'CatalogManager',
          level: 800,
        );

        if (streamedResponse.statusCode != 200) {
          final errorMsg =
              'HTTP ${streamedResponse.statusCode}: Failed to download from ${source.downloadUrl}';
          developer.log(errorMsg, name: 'CatalogManager', level: 1000);
          _emitProgress(
            DownloadProgress.error(source.name, errorMsg, catalogKey: type),
            onProgress,
          );
          return false;
        }

        final contentLength = streamedResponse.contentLength ?? 0;
        developer.log(
          '[Catalog] Writing to $tempPath, expected size: $contentLength bytes',
          name: 'CatalogManager',
          level: 800,
        );

        // Check if the download is gzip compressed
        final isGzipped = source.downloadUrl.endsWith('.gz');

        var bytesReceived = 0;
        var lastEmittedBytes = 0;
        // Coalesce progress so fast connections don't fire a setState per
        // network chunk (thousands/sec). Also the natural cadence at which we
        // poll the cancellation token.
        const emitThresholdBytes = 512 * 1024;

        Future<void> onChunk(int length) async {
          bytesReceived += length;
          if (bytesReceived - lastEmittedBytes < emitThresholdBytes) return;
          lastEmittedBytes = bytesReceived;
          _emitProgress(
            DownloadProgress(
              catalogName: source.name,
              catalogKey: type,
              progress: contentLength > 0 ? bytesReceived / contentLength : 0,
              bytesReceived: bytesReceived,
              totalBytes: contentLength,
              status:
                  'Downloading... ${(bytesReceived / 1024 / 1024).toStringAsFixed(1)} MB',
            ),
            onProgress,
          );
          if (isCancelled != null && await isCancelled()) {
            throw const CatalogCancelled();
          }
        }

        if (isGzipped) {
          // Gzip needs the whole compressed payload before it can decode, so
          // buffer the (smaller) compressed bytes, then write the inflated
          // result to the temp file in one shot.
          final compressed = BytesBuilder(copy: false);
          await for (final chunk in streamedResponse.stream) {
            compressed.add(chunk);
            await onChunk(chunk.length);
          }

          developer.log(
            '[Catalog] Decompressing gzip data...',
            name: 'CatalogManager',
            level: 800,
          );
          Uint8List finalBytes;
          final compressedBytes = compressed.takeBytes();
          try {
            finalBytes = Uint8List.fromList(gzip.decode(compressedBytes));
          } catch (e) {
            developer.log(
              '[Catalog] Gzip decompression failed: $e',
              name: 'CatalogManager',
              level: 900,
            );
            // Fall back to the raw payload (maybe it wasn't actually gzipped).
            finalBytes = Uint8List.fromList(compressedBytes);
          }
          await tempFile.writeAsBytes(finalBytes, flush: true);
        } else {
          // Stream straight to disk so we never hold the whole catalog in
          // memory (the GLADE+ "complete" tier is multiple GB).
          final sink = tempFile.openWrite();
          try {
            await for (final chunk in streamedResponse.stream) {
              sink.add(chunk);
              await onChunk(chunk.length);
            }
          } finally {
            await sink.close();
          }
        }

        // Validate the freshly written temp file before promoting it.
        if (!await tempFile.exists()) {
          throw Exception('File was not created after download');
        }
        final fileSize = await tempFile.length();
        if (fileSize == 0) {
          throw Exception('Downloaded file is empty');
        }

        developer.log(
          '[Catalog] Temp file verified: $fileSize bytes',
          name: 'CatalogManager',
          level: 800,
        );

        // Count objects, then atomically promote temp -> final.
        final objectCount = await _countObjects(tempPath);
        await _promoteTempFile(tempFile, filePath);
        await _saveMetadata(type, source, package, objectCount);
        _invalidateLocalCatalogLoaders(
          stars: type == 'stars',
          dsos: type == 'dso',
        );

        developer.log(
          '[Catalog] Catalog saved with $objectCount objects ($bytesReceived bytes received)',
          name: 'CatalogManager',
          level: 800,
        );

        _emitProgress(
          DownloadProgress.complete(
            source.name,
            bytesReceived,
            catalogKey: type,
          ),
          onProgress,
        );

        return true;
      } finally {
        client.close();
      }
    } on CatalogCancelled {
      developer.log(
        '[Catalog] Download of ${source.name} cancelled by user',
        name: 'CatalogManager',
        level: 800,
      );
      _emitProgress(
        DownloadProgress.cancelled(source.name, catalogKey: type),
        onProgress,
      );
      return false;
    } catch (e, stackTrace) {
      final errorMsg = 'Download error: $e';
      developer.log(
        errorMsg,
        name: 'CatalogManager',
        level: 1000,
        error: e,
        stackTrace: stackTrace,
      );

      _emitProgress(
        DownloadProgress.error(source.name, errorMsg, catalogKey: type),
        onProgress,
      );
      return false;
    } finally {
      // Never leave a half-written `.partial` behind, regardless of outcome
      // (on success it has already been renamed away).
      await _cleanupTempFile(tempFile);
    }
  }

  /// Atomically replace [finalPath] with [tempFile]. POSIX `rename` overwrites
  /// in place; Windows `rename` throws if the destination exists, so remove it
  /// first there. The replacement window is microseconds on the success path.
  Future<void> _promoteTempFile(File tempFile, String finalPath) async {
    final finalFile = File(finalPath);
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(finalPath);
  }

  Future<void> _cleanupTempFile(File tempFile) async {
    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (_) {
      // Best-effort cleanup; a stale `.partial` is harmless and ignored by
      // status checks (which only look at the final catalog path).
    }
  }

  Future<int> _countObjects(String filePath) async {
    try {
      // Stream the file through a line splitter rather than reading it whole:
      // catalogs range from a few MB up to multiple GB (GLADE+ complete), and
      // readAsLines() would load and materialize the entire file in memory.
      var lineCount = 0;
      final stream = File(
        filePath,
      ).openRead().transform(utf8.decoder).transform(const LineSplitter());
      await for (final _ in stream) {
        lineCount++;
      }
      // Subtract 1 for the header row (guard against an empty file).
      return lineCount > 0 ? lineCount - 1 : 0;
    } catch (e) {
      developer.log(
        '[Catalog] Error counting objects: $e',
        name: 'CatalogManager',
        level: 900,
      );
      return 0;
    }
  }

  Future<void> _saveMetadata(
    String type,
    CatalogSource source,
    CatalogPackage package,
    int objectCount,
  ) async {
    final metaPath = path.join(catalogDirectory, '${type}_metadata.json');
    final metaFile = File(metaPath);

    // Record the SHA-256 of the installed data file so a later
    // `POST /api/catalog/verify` has an expected digest to compare against —
    // without it, verify can only ever report `no_expected_hash`. Streamed
    // from disk rather than read whole to avoid a memory spike on the
    // multi-MB catalog payloads.
    String? sha256Hash;
    final dataFile = File(path.join(catalogDirectory, source.fileName));
    if (await dataFile.exists()) {
      try {
        final digest = await sha256.bind(dataFile.openRead()).first;
        sha256Hash = digest.toString();
      } catch (e) {
        developer.log(
          '[Catalog] _saveMetadata($type): sha256 computation failed: $e',
          name: 'CatalogManager',
          level: 900,
        );
      }
    }

    final metadata = {
      'source': source.name,
      'version': source.version,
      'package': package.name,
      'objectCount': objectCount,
      'installedDate': DateTime.now().toIso8601String(),
      if (sha256Hash != null) 'sha256': sha256Hash,
    };

    await metaFile.writeAsString(jsonEncode(metadata));
  }

  /// Import a catalog from a custom location
  Future<bool> _importCatalog({
    required String sourcePath,
    required String type, // 'stars' or 'dso'
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return false;
      }

      final fileName = type == 'stars'
          ? hygStarCatalog.fileName
          : openNgcCatalog.fileName;
      final destPath = path.join(catalogDirectory, fileName);
      final tempPath = '$destPath.partial';
      final tempFile = File(tempPath);

      try {
        // Copy to a temp file first, then atomically promote, so a failed copy
        // can't clobber a good existing catalog.
        await sourceFile.copy(tempPath);
        if (await tempFile.length() == 0) {
          throw Exception('Imported file is empty');
        }

        final objectCount = await _countObjects(tempPath);
        await _promoteTempFile(tempFile, destPath);
        final source = type == 'stars' ? hygStarCatalog : openNgcCatalog;
        await _saveMetadata(type, source, CatalogPackage.complete, objectCount);
        _invalidateLocalCatalogLoaders(
          stars: type == 'stars',
          dsos: type == 'dso',
        );

        return true;
      } finally {
        await _cleanupTempFile(tempFile);
      }
    } catch (e) {
      developer.log(
        '[Catalog] Import error: $e',
        name: 'CatalogManager',
        level: 1000,
      );
      return false;
    }
  }

  /// Delete installed catalogs
  Future<void> _deleteCatalogs() async {
    final files = [
      hygStarCatalog.fileName,
      openNgcCatalog.fileName,
      'stars_metadata.json',
      'dso_metadata.json',
    ];

    for (final fileName in files) {
      final file = File(path.join(catalogDirectory, fileName));
      if (await file.exists()) {
        await file.delete();
      }
    }
    _invalidateLocalCatalogLoaders(stars: true, dsos: true);
  }
}
