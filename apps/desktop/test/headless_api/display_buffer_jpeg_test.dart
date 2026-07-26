import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/display_buffer_jpeg.dart';

void main() {
  test('offset-less native frame timestamps are serialized as UTC', () {
    expect(
      capturedImageTimestampUtc('2026-07-23T23:34:35'),
      '2026-07-23T23:34:35.000Z',
    );
  });

  test('JPEG metadata preserves the captured instant across offsets', () {
    const image = CapturedImageResult(
      width: 1,
      height: 1,
      displayData: [0, 0, 0, 255],
      histogram: [1],
      stats: ImageStatsResult(
        min: 0,
        max: 0,
        mean: 0,
        median: 0,
        stdDev: 0,
        starCount: 0,
      ),
      exposureTime: 1,
      timestamp: '2026-07-23T19:34:35-04:00',
    );

    final encoded = encodeCapturedImageDisplayBufferToJpeg(image);
    expect(encoded, isNotNull);
    final metadata = decodeImageMetaHeader(encoded!.metaHeaderValue);
    expect(metadata['timestamp'], '2026-07-23T23:34:35.000Z');
  });
}
