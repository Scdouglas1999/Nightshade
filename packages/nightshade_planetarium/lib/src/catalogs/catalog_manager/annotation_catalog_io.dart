part of '../catalog_manager.dart';

extension CatalogManagerAnnotationIo on CatalogManager {
  // =========================================================================
  // ANNOTATION CATALOG (GLADE+) METHODS
  // =========================================================================

  /// Check if annotation catalog is installed
  Future<CatalogStatus> _getAnnotationCatalogStatus() async {
    if (!isInitialized) return CatalogStatus.notInstalled();
    return _getCatalogStatus(gladePlusCatalog.fileName, 'annotation');
  }

  /// Download and install annotation catalog (GLADE+ via VizieR TAP)
  Future<bool> _downloadAnnotationCatalogEntry({
    AnnotationPackage package = AnnotationPackage.standard,
    void Function(DownloadProgress)? onProgress,
  }) async {
    return _downloadAnnotationCatalog(
      source: gladePlusCatalog,
      package: package,
      onProgress: onProgress,
    );
  }

  Future<bool> _downloadAnnotationCatalog({
    required CatalogSource source,
    required AnnotationPackage package,
    void Function(DownloadProgress)? onProgress,
  }) async {
    // Build the VizieR TAP URL based on the selected package tier
    final downloadUrl = buildGladePlusUrl(package);

    developer.log(
        '[Catalog] Starting download of ${source.name} (${package.displayName} tier)',
        name: 'CatalogManager',
        level: 800);
    developer.log('[Catalog] VizieR TAP URL: $downloadUrl',
        name: 'CatalogManager', level: 800);

    final progress = DownloadProgress.starting(source.name);
    _downloadController.add(progress);
    onProgress?.call(progress);

    try {
      if (!isInitialized) {
        throw StateError('CatalogManager not initialized');
      }

      final dir = Directory(catalogDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final client = http.Client();

      try {
        developer.log('[Catalog] Sending HTTP GET request to VizieR TAP...',
            name: 'CatalogManager', level: 800);

        final request = http.Request('GET', Uri.parse(downloadUrl));
        final streamedResponse = await client.send(request);

        developer.log(
            '[Catalog] Response status: ${streamedResponse.statusCode}',
            name: 'CatalogManager',
            level: 800);

        if (streamedResponse.statusCode != 200) {
          final errorMsg =
              'HTTP ${streamedResponse.statusCode}: Failed to download from VizieR TAP';
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

        // VizieR TAP returns CSV directly (not gzipped)
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

        // Write CSV data directly to file
        final finalBytes = Uint8List.fromList(downloadedBytes);
        sink.add(finalBytes);
        await sink.close();

        developer.log(
            '[Catalog] Download complete: $bytesReceived bytes written to $filePath',
            name: 'CatalogManager',
            level: 800);

        if (!await file.exists()) {
          throw Exception('File was not created after download');
        }

        final fileSize = await file.length();
        if (fileSize == 0) {
          throw Exception('Downloaded file is empty');
        }

        developer.log('[Catalog] File verified: $fileSize bytes',
            name: 'CatalogManager', level: 800);

        final objectCount = await _countObjects(filePath);
        await _saveAnnotationMetadata(source, package, objectCount);

        developer.log(
            '[Catalog] Annotation catalog saved with $objectCount objects',
            name: 'CatalogManager',
            level: 800);

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

  Future<void> _saveAnnotationMetadata(
    CatalogSource source,
    AnnotationPackage package,
    int objectCount,
  ) async {
    final metaPath = path.join(catalogDirectory, 'annotation_metadata.json');
    final metaFile = File(metaPath);

    final metadata = {
      'source': source.name,
      'version': source.version,
      'package': package.name,
      'magnitudeLimit': package.magnitudeLimit,
      'objectCount': objectCount,
      'installedDate': DateTime.now().toIso8601String(),
    };

    await metaFile.writeAsString(jsonEncode(metadata));
  }

  /// Import annotation catalog from a local file
  /// Accepts CSV files with galaxy data (e.g., from VizieR GLADE+ export)
  /// Expected format: CSV with columns for RA, Dec, magnitude, etc.
  Future<bool> _importAnnotationCatalog({
    required String sourcePath,
    AnnotationPackage package = AnnotationPackage.standard,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        developer.log('[Catalog] Import source file not found: $sourcePath',
            name: 'CatalogManager', level: 900);
        return false;
      }

      final destPath = path.join(catalogDirectory, gladePlusCatalog.fileName);

      // Copy the file
      await sourceFile.copy(destPath);

      // Count objects and save metadata
      final objectCount = await _countObjects(destPath);
      await _saveAnnotationMetadata(gladePlusCatalog, package, objectCount);

      developer.log(
          '[Catalog] Annotation catalog imported: $objectCount objects from $sourcePath',
          name: 'CatalogManager',
          level: 800);
      return true;
    } catch (e) {
      developer.log('[Catalog] Import annotation catalog error: $e',
          name: 'CatalogManager', level: 1000);
      return false;
    }
  }

  /// Delete annotation catalog
  Future<void> _deleteAnnotationCatalog() async {
    final files = [
      gladePlusCatalog.fileName,
      'annotation_metadata.json',
    ];

    for (final fileName in files) {
      final file = File(path.join(catalogDirectory, fileName));
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// Get installed annotation package info
  Future<AnnotationPackage?> _getInstalledAnnotationPackage() async {
    final status = await getAnnotationCatalogStatus();
    return status.installedPackage != null
        ? AnnotationPackage.values.firstWhere(
            (p) => p.name == status.installedPackage!.name,
            orElse: () => AnnotationPackage.standard,
          )
        : null;
  }
}
