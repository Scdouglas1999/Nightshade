part of '../catalog_manager.dart';

extension CatalogManagerLegacyIo on CatalogManager {
  /// Download and install star catalog
  Future<bool> _downloadStarCatalog({
    CatalogPackage package = CatalogPackage.standard,
    void Function(DownloadProgress)? onProgress,
  }) async {
    return _downloadCatalog(
      source: hygStarCatalog,
      type: 'stars',
      package: package,
      onProgress: onProgress,
    );
  }

  /// Download and install DSO catalog
  Future<bool> _downloadDsoCatalog({
    CatalogPackage package = CatalogPackage.standard,
    void Function(DownloadProgress)? onProgress,
  }) async {
    return _downloadCatalog(
      source: openNgcCatalog,
      type: 'dso',
      package: package,
      onProgress: onProgress,
    );
  }

  Future<bool> _downloadCatalog({
    required CatalogSource source,
    required String type,
    required CatalogPackage package,
    void Function(DownloadProgress)? onProgress,
  }) async {
    developer.log(
        '[Catalog] Starting download of ${source.name} from ${source.downloadUrl}',
        name: 'CatalogManager',
        level: 800);

    final progress = DownloadProgress.starting(source.name);
    _downloadController.add(progress);
    onProgress?.call(progress);

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
            level: 800);

        final request = http.Request('GET', Uri.parse(source.downloadUrl));
        final streamedResponse = await client.send(request);

        developer.log(
            '[Catalog] Response status: ${streamedResponse.statusCode}',
            name: 'CatalogManager',
            level: 800);

        if (streamedResponse.statusCode != 200) {
          final errorMsg =
              'HTTP ${streamedResponse.statusCode}: Failed to download from ${source.downloadUrl}';
          developer.log(errorMsg, name: 'CatalogManager', level: 1000);
          final error = DownloadProgress.error(source.name, errorMsg);
          _downloadController.add(error);
          onProgress?.call(error);
          return false;
        }

        final contentLength = streamedResponse.contentLength ?? 0;
        final filePath = path.join(catalogDirectory, source.fileName);
        final file = File(filePath);
        final sink = file.openWrite();

        developer.log(
            '[Catalog] Writing to $filePath, expected size: $contentLength bytes',
            name: 'CatalogManager',
            level: 800);

        // Check if the download is gzip compressed
        final isGzipped = source.downloadUrl.endsWith('.gz');

        var bytesReceived = 0;
        final downloadedBytes = <int>[];

        await for (final chunk in streamedResponse.stream) {
          downloadedBytes.addAll(chunk);
          bytesReceived += chunk.length;

          final prog = DownloadProgress(
            catalogName: source.name,
            progress: contentLength > 0 ? bytesReceived / contentLength : 0,
            bytesReceived: bytesReceived,
            totalBytes: contentLength,
            status:
                'Downloading... ${(bytesReceived / 1024 / 1024).toStringAsFixed(1)} MB',
          );
          _downloadController.add(prog);
          onProgress?.call(prog);
        }

        // Decompress if needed
        Uint8List finalBytes;
        if (isGzipped) {
          developer.log('[Catalog] Decompressing gzip data...',
              name: 'CatalogManager', level: 800);
          try {
            finalBytes = Uint8List.fromList(gzip.decode(downloadedBytes));
            developer.log(
                '[Catalog] Decompressed ${downloadedBytes.length} bytes to ${finalBytes.length} bytes',
                name: 'CatalogManager',
                level: 800);
          } catch (e) {
            developer.log('[Catalog] Gzip decompression failed: $e',
                name: 'CatalogManager', level: 900);
            // Try to use the data as-is (maybe it wasn't actually gzipped)
            finalBytes = Uint8List.fromList(downloadedBytes);
          }
        } else {
          finalBytes = Uint8List.fromList(downloadedBytes);
        }

        // Write to file
        sink.add(finalBytes);
        await sink.close();

        developer.log(
            '[Catalog] Download complete: $bytesReceived bytes written to $filePath',
            name: 'CatalogManager',
            level: 800);

        // Verify file was written
        if (!await file.exists()) {
          throw Exception('File was not created after download');
        }

        final fileSize = await file.length();
        if (fileSize == 0) {
          throw Exception('Downloaded file is empty');
        }

        developer.log('[Catalog] File verified: $fileSize bytes',
            name: 'CatalogManager', level: 800);

        // Count objects and save metadata
        final objectCount = await _countObjects(filePath);
        await _saveMetadata(type, source, package, objectCount);
        _invalidateLocalCatalogLoaders(
          stars: type == 'stars',
          dsos: type == 'dso',
        );

        developer.log('[Catalog] Catalog saved with $objectCount objects',
            name: 'CatalogManager', level: 800);

        final complete = DownloadProgress.complete(source.name, bytesReceived);
        _downloadController.add(complete);
        onProgress?.call(complete);

        return true;
      } finally {
        client.close();
      }
    } catch (e, stackTrace) {
      final errorMsg = 'Download error: $e';
      developer.log(errorMsg,
          name: 'CatalogManager',
          level: 1000,
          error: e,
          stackTrace: stackTrace);

      final error = DownloadProgress.error(source.name, errorMsg);
      _downloadController.add(error);
      onProgress?.call(error);
      return false;
    }
  }

  Future<int> _countObjects(String filePath) async {
    try {
      final file = File(filePath);
      final lines = await file.readAsLines();
      // Subtract 1 for header row
      return lines.length - 1;
    } catch (e) {
      developer.log('[Catalog] Error counting objects: $e',
          name: 'CatalogManager', level: 900);
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

    final metadata = {
      'source': source.name,
      'version': source.version,
      'package': package.name,
      'objectCount': objectCount,
      'installedDate': DateTime.now().toIso8601String(),
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

      final fileName =
          type == 'stars' ? hygStarCatalog.fileName : openNgcCatalog.fileName;
      final destPath = path.join(catalogDirectory, fileName);

      await sourceFile.copy(destPath);

      final objectCount = await _countObjects(destPath);
      final source = type == 'stars' ? hygStarCatalog : openNgcCatalog;
      await _saveMetadata(type, source, CatalogPackage.complete, objectCount);
      _invalidateLocalCatalogLoaders(
        stars: type == 'stars',
        dsos: type == 'dso',
      );

      return true;
    } catch (e) {
      developer.log('[Catalog] Import error: $e',
          name: 'CatalogManager', level: 1000);
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
