part of '../imaging_service.dart';

extension _ImagingServiceFilePaths on ImagingService {
  /// Generate file path for captured image.
  ///
  /// The user's [NamingPattern.pattern] is interpreted as a `/`-separated
  /// path *including the filename*: every segment before the final `/` is a
  /// subdirectory, and the final segment is the filename stem (the extension
  /// is appended from [NamingPattern.format]). The default pattern
  /// `$TARGET/$FRAMETYPE/$TARGET_$FILTER_$EXPTIME_$FRAMENUM` therefore yields
  /// e.g. `M31/Light/M31_L_120.0_0001.fits` under the configured base
  /// directory. This matches the convention implemented by the Rust
  /// `FilenameGenerator` in `native/nightshade_native/imaging/src/naming.rs`.
  ///
  /// All `$VARIABLE` tokens are validated against [_patternVariables]; any
  /// unknown token raises an [Exception] (errors are a feature here:
  /// silently leaving e.g. `$BANANA` in the filename would hide a typo in the
  /// user's pattern for weeks).
  ///
  /// Date/time substitutions (`$DATE`, `$TIME`, `$DATETIME`) use **UTC** so
  /// the path matches the FITS `DATE-OBS` keyword written by the Rust
  /// `FitsHeader::captureTimestamp` path (which also uses UTC). A 19:00 PST
  /// frame is grouped under the UTC date 03:00 the next morning — i.e. the
  /// folder name matches the timestamp embedded in the file.
  Future<String> _generateImageFilePath({
    required AppSettingsState appSettings,
    required ExposureSettings exposureSettings,
    String? targetName,
    required int frameNumber,
    required DateTime timestamp,
  }) async {
    final basePath = appSettings.imageOutputPath;
    if (basePath.isEmpty) {
      throw const ValidationException(
        message: 'Image output path not configured',
        userMessage: 'No image output path is configured',
      );
    }

    // Get naming pattern from imaging provider
    final namingPattern = _ref.read(namingPatternProvider);

    final substitutions = _buildPatternSubstitutions(
      exposureSettings: exposureSettings,
      targetName: targetName,
      frameNumber: frameNumber,
      timestamp: timestamp,
    );

    final fullPath = ImagingService.buildImageFilePath(
      pattern: namingPattern.pattern,
      basePath: basePath,
      extension: namingPattern.format.extension,
      substitutions: substitutions,
    );

    // Create directory if needed
    final directory = Directory(path.dirname(fullPath));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return _ensureUniqueFilePath(fullPath);
  }

  Future<String> _ensureUniqueFilePath(String desiredPath) async {
    var candidate = desiredPath;
    var suffix = 1;

    while (await File(candidate).exists()) {
      final directory = path.dirname(desiredPath);
      final baseName = path.basenameWithoutExtension(desiredPath);
      final extension = path.extension(desiredPath);
      candidate = path.join(
        directory,
        '${baseName}_${suffix.toString().padLeft(3, '0')}$extension',
      );
      suffix++;
    }

    return candidate;
  }

  /// Save FITS file via Rust backend
  ///
  /// Uses the optimized saveFitsFromLastCapture API which reads raw image data
  /// directly from Rust-side storage, avoiding expensive FFI data transfers.
}
