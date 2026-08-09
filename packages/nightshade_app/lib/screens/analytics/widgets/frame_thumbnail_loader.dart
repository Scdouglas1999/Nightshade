import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show
        DbCapturedImage,
        imagingBackendProvider,
        isRemoteModeProvider,
        loggingServiceProvider;

/// Result of asking the backend (and then the local disk) for a frame's
/// preview bytes.
class FrameThumbnailPayload {
  /// Decoded preview bytes, when the backend had a cached thumbnail.
  final Uint8List? bytes;

  /// Whether the frame's own file is readable on this machine. False in remote
  /// mode, where the file lives on the host.
  final bool fileExists;

  /// Why no bytes came back, for a tooltip. Null when nothing went wrong.
  final String? errorMessage;

  const FrameThumbnailPayload({
    this.bytes,
    required this.fileExists,
    this.errorMessage,
  });
}

/// True for the container formats Flutter's image decoders cannot open.
///
/// A FITS/XISF path must never be handed to `Image.file`: it renders as a
/// broken-image glyph rather than as the frame.
bool isFitsLikePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.fits') ||
      lower.endsWith('.fit') ||
      lower.endsWith('.fts') ||
      lower.endsWith('.xisf');
}

/// Fetches a frame's preview, preferring the backend's thumbnail cache and
/// falling back to the local file.
///
/// Shared by the Analytics thumbnail rail and the frame inspector it opens so
/// the two can never disagree about whether a frame is viewable.
Future<FrameThumbnailPayload> loadFrameThumbnail(
  WidgetRef ref,
  DbCapturedImage image,
) async {
  final backend = ref.read(imagingBackendProvider);
  String? backendError;
  try {
    final bytes = await backend.getImageThumbnail(image.id);
    if (bytes.isNotEmpty) {
      return FrameThumbnailPayload(bytes: bytes, fileExists: true);
    }
    backendError =
        'Thumbnail not found in backend cache for image ${image.id}.';
  } catch (error) {
    backendError =
        'Backend thumbnail request failed for image ${image.id}: $error';
    ref.read(loggingServiceProvider).warning(
          'loadFrameThumbnail: $backendError',
          source: 'FrameThumbnail',
        );
  }

  // In remote mode the frame's path names a file on the HOST, so probing it
  // here would report the operator's own disk.
  if (ref.read(isRemoteModeProvider)) {
    return FrameThumbnailPayload(
      fileExists: false,
      errorMessage: backendError,
    );
  }

  try {
    final exists = await File(image.filePath).exists();
    return FrameThumbnailPayload(
      fileExists: exists,
      errorMessage: backendError,
    );
  } catch (error) {
    final localError =
        'Failed to check local image file "${image.filePath}": $error';
    ref.read(loggingServiceProvider).warning(
          'loadFrameThumbnail: $localError',
          source: 'FrameThumbnail',
        );
    return FrameThumbnailPayload(
      fileExists: false,
      errorMessage: '$backendError\n$localError',
    );
  }
}
