import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:nightshade_core/nightshade_core.dart';

/// Result of encoding a host [CapturedImageResult.displayData] buffer to JPEG.
class DisplayBufferJpegEncodeResult {
  const DisplayBufferJpegEncodeResult({
    required this.bytes,
    required this.encodedWidth,
    required this.encodedHeight,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.metaHeaderValue,
  });

  final Uint8List bytes;
  final int encodedWidth;
  final int encodedHeight;
  final int sourceWidth;
  final int sourceHeight;

  /// Value for the `x-image-meta` response header (base64 JSON).
  final String metaHeaderValue;
}

/// Encode stretched RGBA [CapturedImageResult.displayData] to JPEG.
///
/// Returns `null` when the display buffer size does not match width×height×4.
DisplayBufferJpegEncodeResult? encodeCapturedImageDisplayBufferToJpeg(
  CapturedImageResult image, {
  int maxWidth = 0,
  int quality = 85,
}) {
  final expected = image.width * image.height * 4;
  if (image.displayData.length != expected) {
    return null;
  }

  final rgba = Uint8List.fromList(image.displayData);
  var bitmap = img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );

  var encodedWidth = image.width;
  var encodedHeight = image.height;
  if (maxWidth > 0 && image.width > maxWidth) {
    encodedHeight = (image.height * (maxWidth / image.width)).round().clamp(
      1,
      1 << 16,
    );
    encodedWidth = maxWidth;
    bitmap = img.copyResize(bitmap, width: encodedWidth, height: encodedHeight);
  }

  final jpeg = img.encodeJpg(bitmap, quality: quality.clamp(1, 100));
  final metaJson = jsonEncode({
    'width': image.width,
    'height': image.height,
    'encodedWidth': encodedWidth,
    'encodedHeight': encodedHeight,
    'histogram': image.histogram,
    'stats': image.stats.toJson(),
    'exposureTime': image.exposureTime,
    'timestamp': image.timestamp,
    'isColor': image.isColor,
  });

  return DisplayBufferJpegEncodeResult(
    bytes: Uint8List.fromList(jpeg),
    encodedWidth: encodedWidth,
    encodedHeight: encodedHeight,
    sourceWidth: image.width,
    sourceHeight: image.height,
    metaHeaderValue: base64Encode(utf8.encode(metaJson)),
  );
}

/// Decode the `x-image-meta` header produced by [encodeCapturedImageDisplayBufferToJpeg].
Map<String, dynamic> decodeImageMetaHeader(String headerValue) {
  final decoded = utf8.decode(base64Decode(headerValue));
  return jsonDecode(decoded) as Map<String, dynamic>;
}
