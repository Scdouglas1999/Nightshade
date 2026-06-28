// Image-output format defaults surfaced in Settings → Imaging. Owns the
// three knobs that affect how a captured frame is encoded on disk.
//
// Owns:
//   * imageFormat (FITS / XISF / TIFF)
//   * fileNamingPattern (template like `$TARGET_$FILTER_$DATE_$SEQ`)
//   * bitDepth (16-bit / 32-bit)
//
// Does NOT own:
//   * Save-path defaults → see `file_paths.dart`.
//   * Camera connect-time defaults (gain / offset / cooling) → see
//     `equipment.dart`.
//   * Live Pass/Reject grading → see `image_grading.dart`.
part of '../settings_provider.dart';

/// Setters for image-output format defaults.
extension ImagingSettingsSection on AppSettingsNotifier {
  Future<void> setImageFormat(String value) async {
    await _saveSetting('image_format', value);
    _patchState((s) => s.copyWith(imageFormat: value));
  }

  Future<void> setFileNamingPattern(String value) async {
    await _saveSetting('file_naming_pattern', value);
    _patchState((s) => s.copyWith(fileNamingPattern: value));
  }

  Future<void> setBitDepth(String value) async {
    await _saveSetting('bit_depth', value);
    _patchState((s) => s.copyWith(bitDepth: value));
  }
}
