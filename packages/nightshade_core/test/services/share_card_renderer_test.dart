// Stack-and-Share Loop — tests for the share-card renderer.
//
// Covers the three concerns the renderer owns:
//   * Mono u16 → JPEG: encodes, decodes back to the requested dimensions.
//   * RGBA → PNG/JPEG: encodes the already-stretched export path.
//   * Overlay actually draws: a spec with watermark + stats produces a
//     different byte stream than a bare spec (proving the panel/watermark
//     touch pixels rather than no-op'ing).
//   * Percentile stretch maps a known min/max onto the full output range.
//   * Short / mis-dimensioned buffers throw rather than serving garbage.
//   * expandWatermarkTokens substitutes, escapes, and passes unknown tokens.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nightshade_core/src/models/imaging/stack_and_share_models.dart';
import 'package:nightshade_core/src/services/share_card_renderer.dart';

/// A smooth diagonal u16 gradient — gives the auto-stretch histogram something
/// non-trivial to fit, exercising the encode path beyond a flat-tone shortcut.
Uint16List _gradient(int width, int height) {
  final out = Uint16List(width * height);
  final maxSum = (width - 1) + (height - 1);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      out[y * width + x] = ((x + y) * 65535 ~/ maxSum).clamp(0, 65535);
    }
  }
  return out;
}

/// A tightly-packed opaque RGBA buffer with a horizontal red ramp.
Uint8List _rgbaRamp(int width, int height) {
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      out[i] = (x * 255 ~/ (width - 1)).clamp(0, 255); // R
      out[i + 1] = 32; // G
      out[i + 2] = 64; // B
      out[i + 3] = 255; // A (opaque)
    }
  }
  return out;
}

void main() {
  const renderer = ShareCardRenderer();

  group('ShareCardRenderer.renderJpegFromMono', () {
    test('encodes a decodable JPEG at the requested target dimensions', () {
      const spec = ShareCardSpec(
        title: 'M42',
        targetWidth: 64,
        targetHeight: 64,
      );
      final bytes = renderer.renderJpegFromMono(
        width: 64,
        height: 64,
        data: _gradient(64, 64),
        spec: spec,
      );
      expect(bytes, isNotEmpty);
      // JPEG SOI magic bytes.
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xD8);

      final decoded = img.decodeJpg(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 64);
      expect(decoded.height, 64);
    });

    test('aspect-fit downscales a wide source into the target box', () {
      // 128x64 source (2:1) into a 64x64 box → fits to 64x32.
      const spec = ShareCardSpec(
        title: '',
        targetWidth: 64,
        targetHeight: 64,
      );
      final bytes = renderer.renderJpegFromMono(
        width: 128,
        height: 64,
        data: _gradient(128, 64),
        spec: spec,
      );
      final decoded = img.decodeJpg(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 64);
      expect(decoded.height, 32);
    });

    test('honours the quality parameter (lower quality = smaller file)', () {
      const spec = ShareCardSpec(title: '', targetWidth: 128, targetHeight: 128);
      final data = _gradient(128, 128);
      final hi = renderer.renderJpegFromMono(
        width: 128,
        height: 128,
        data: data,
        spec: spec,
        quality: 95,
      );
      final lo = renderer.renderJpegFromMono(
        width: 128,
        height: 128,
        data: data,
        spec: spec,
        quality: 30,
      );
      expect(lo.length, lessThan(hi.length));
    });

    test('throws on a buffer shorter than width*height', () {
      const spec = ShareCardSpec(title: '', targetWidth: 8, targetHeight: 8);
      expect(
        () => renderer.renderJpegFromMono(
          width: 8,
          height: 8,
          data: Uint16List(8 * 8 - 1),
          spec: spec,
        ),
        throwsStateError,
      );
    });

    test('throws on non-positive dimensions', () {
      const spec = ShareCardSpec(title: '', targetWidth: 8, targetHeight: 8);
      expect(
        () => renderer.renderJpegFromMono(
          width: 0,
          height: 8,
          data: Uint16List(8),
          spec: spec,
        ),
        throwsStateError,
      );
    });
  });

  group('ShareCardRenderer RGBA paths', () {
    test('renderPngFromRgba encodes a decodable PNG at source dimensions', () {
      const spec = ShareCardSpec(
        title: 'NGC 7000',
        targetWidth: 96,
        targetHeight: 96,
      );
      final bytes = renderer.renderPngFromRgba(
        width: 96,
        height: 96,
        rgba: _rgbaRamp(96, 96),
        spec: spec,
      );
      expect(bytes, isNotEmpty);
      // PNG 8-byte signature.
      expect(bytes.sublist(0, 8),
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final decoded = img.decodePng(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 96);
      expect(decoded.height, 96);
    });

    test('renderJpegFromRgba encodes a decodable JPEG', () {
      const spec = ShareCardSpec(title: '', targetWidth: 96, targetHeight: 96);
      final bytes = renderer.renderJpegFromRgba(
        width: 96,
        height: 96,
        rgba: _rgbaRamp(96, 96),
        spec: spec,
      );
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xD8);
      expect(img.decodeJpg(bytes), isNotNull);
    });

    test('throws on a short RGBA buffer', () {
      const spec = ShareCardSpec(title: '', targetWidth: 8, targetHeight: 8);
      expect(
        () => renderer.renderPngFromRgba(
          width: 8,
          height: 8,
          rgba: Uint8List(8 * 8 * 4 - 1),
          spec: spec,
        ),
        throwsStateError,
      );
    });
  });

  group('overlay actually draws pixels', () {
    // A flat mid-grey source means a bare spec produces a uniform image. Any
    // overlay (watermark, stat panel) must perturb the bytes, proving it draws.

    test('watermark changes the output vs a bare spec', () {
      const bare = ShareCardSpec(title: '', targetWidth: 128, targetHeight: 128);
      const marked = ShareCardSpec(
        title: '',
        watermark: 'Nightshade',
        targetWidth: 128,
        targetHeight: 128,
      );
      final a = renderer.renderPngFromRgba(
        width: 128,
        height: 128,
        rgba: _opaqueGrey(128, 128),
        spec: bare,
      );
      final b = renderer.renderPngFromRgba(
        width: 128,
        height: 128,
        rgba: _opaqueGrey(128, 128),
        spec: marked,
      );
      expect(_pixelsDiffer(a, b), isTrue,
          reason: 'watermark must perturb the rendered pixels');
    });

    test('stat panel (bottomBar) changes the output vs a bare spec', () {
      const bare = ShareCardSpec(title: '', targetWidth: 160, targetHeight: 120);
      const withStats = ShareCardSpec(
        title: 'M31',
        stats: [
          ShareStatLine(label: 'Integration', value: '2h12m'),
          ShareStatLine(label: 'Frames', value: '132'),
        ],
        targetWidth: 160,
        targetHeight: 120,
      );
      final a = renderer.renderPngFromRgba(
        width: 160,
        height: 120,
        rgba: _opaqueGrey(160, 120),
        spec: bare,
      );
      final b = renderer.renderPngFromRgba(
        width: 160,
        height: 120,
        rgba: _opaqueGrey(160, 120),
        spec: withStats,
      );
      expect(_pixelsDiffer(a, b), isTrue,
          reason: 'stat panel must perturb the rendered pixels');
    });

    test('stat panel (cornerCard) changes the output vs a bare spec', () {
      const bare = ShareCardSpec(title: '', targetWidth: 160, targetHeight: 120);
      const corner = ShareCardSpec(
        title: 'M31',
        stats: [ShareStatLine(label: 'Frames', value: '132')],
        layout: ShareCardLayout.cornerCard,
        targetWidth: 160,
        targetHeight: 120,
      );
      final a = renderer.renderPngFromRgba(
        width: 160,
        height: 120,
        rgba: _opaqueGrey(160, 120),
        spec: bare,
      );
      final b = renderer.renderPngFromRgba(
        width: 160,
        height: 120,
        rgba: _opaqueGrey(160, 120),
        spec: corner,
      );
      expect(_pixelsDiffer(a, b), isTrue,
          reason: 'corner card must perturb the rendered pixels');
    });

    test('bottomBar and cornerCard layouts differ from each other', () {
      const bar = ShareCardSpec(
        title: 'M31',
        stats: [ShareStatLine(label: 'Frames', value: '132')],
        targetWidth: 200,
        targetHeight: 160,
      );
      const corner = ShareCardSpec(
        title: 'M31',
        stats: [ShareStatLine(label: 'Frames', value: '132')],
        layout: ShareCardLayout.cornerCard,
        targetWidth: 200,
        targetHeight: 160,
      );
      final a = renderer.renderPngFromRgba(
        width: 200,
        height: 160,
        rgba: _opaqueGrey(200, 160),
        spec: bar,
      );
      final b = renderer.renderPngFromRgba(
        width: 200,
        height: 160,
        rgba: _opaqueGrey(200, 160),
        spec: corner,
      );
      expect(_pixelsDiffer(a, b), isTrue);
    });
  });

  group('ShareCardRenderer.computeStretchEnds', () {
    test('maps a clean two-tone histogram to its min/max', () {
      // 1000 samples: bulk at 1000, a few at 50000. The 0.5/99.5 percentiles
      // land inside the dominant tone and the high tail respectively.
      final data = Uint16List(1000);
      for (var i = 0; i < 990; i++) {
        data[i] = 1000;
      }
      for (var i = 990; i < 1000; i++) {
        data[i] = 50000;
      }
      final (black, white) = renderer.computeStretchEnds(data);
      expect(black, 1000);
      expect(white, 50000);
    });

    test('a known full-range ramp stretches min→0 / max→255', () {
      // 256 distinct values 0..65535. After the percentile stretch the darkest
      // input maps to near 0 and the brightest near 255 in the decoded image.
      const w = 256;
      const h = 4;
      final data = Uint16List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          data[y * w + x] = (x * 65535 ~/ (w - 1)).clamp(0, 65535);
        }
      }
      // Render at native size (no downscale) through the mono path so the
      // stretch is exactly what computeStretchEnds produced.
      const spec = ShareCardSpec(title: '', targetWidth: w, targetHeight: h);
      final jpeg = renderer.renderJpegFromMono(
        width: w,
        height: h,
        data: data,
        spec: spec,
      );
      final decoded = img.decodeJpg(jpeg)!;
      final left = decoded.getPixel(0, 0);
      final right = decoded.getPixel(w - 1, 0);
      // Leftmost (darkest) pixel near black, rightmost near white. JPEG is
      // lossy so allow generous tolerance.
      expect(left.r, lessThan(40));
      expect(right.r, greaterThan(215));
    });

    test('degenerate single-tone data falls back to full range', () {
      final data = Uint16List.fromList(List<int>.filled(100, 12345));
      final (black, white) = renderer.computeStretchEnds(data);
      expect(black, 0);
      expect(white, 65535);
    });

    test('empty data falls back to full range', () {
      final (black, white) = renderer.computeStretchEnds(Uint16List(0));
      expect(black, 0);
      expect(white, 65535);
    });
  });

  group('font resolution (fontForHeight / fontForSpec)', () {
    test('height-based policy scales the font with the image height', () {
      // ~4% line-height thresholds: <500px → arial14, 500..999px → arial24,
      // >=1000px → arial48.
      expect(renderer.fontForHeight(256), img.arial14);
      expect(renderer.fontForHeight(720), img.arial24);
      expect(renderer.fontForHeight(2160), img.arial48);
    });

    test('scaleToHeight spec defers to the height-based policy', () {
      const spec = ShareCardSpec(
        title: '',
        targetWidth: 1280,
        targetHeight: 720,
        fontScale: ShareCardFontScale.scaleToHeight,
      );
      expect(renderer.fontForSpec(spec, 720), img.arial24);
    });

    test(
        'broadcast 720px frame keeps the historical arial48 watermark via the '
        'large fontScale (regression guard)', () {
      // The pre-extraction broadcast drew its watermark at arial48 regardless
      // of the 720px thumbnail. The height-based policy alone would pick
      // arial24 (720*0.04=28.8), halving the glyph size — so the broadcast spec
      // pins ShareCardFontScale.large. This asserts that override wins.
      const broadcastSpec = ShareCardSpec(
        title: '',
        watermark: 'Nightshade',
        targetWidth: 1280,
        targetHeight: 720,
        fontScale: ShareCardFontScale.large,
      );
      expect(renderer.fontForSpec(broadcastSpec, 720), img.arial48);
      // And it does not silently match the height-based pick.
      expect(renderer.fontForSpec(broadcastSpec, 720),
          isNot(renderer.fontForHeight(720)));
    });

    test('fixed small / medium scales pin their fonts regardless of height', () {
      const small = ShareCardSpec(
        title: '',
        targetWidth: 1280,
        targetHeight: 720,
        fontScale: ShareCardFontScale.small,
      );
      const medium = ShareCardSpec(
        title: '',
        targetWidth: 1280,
        targetHeight: 720,
        fontScale: ShareCardFontScale.medium,
      );
      expect(renderer.fontForSpec(small, 2160), img.arial14);
      expect(renderer.fontForSpec(medium, 256), img.arial24);
    });
  });

  group('expandWatermarkTokens', () {
    test('substitutes known tokens from the map', () {
      final out = expandWatermarkTokens(
        r'${target} — ${integration.hms} (${frames})',
        {
          'target': 'M42',
          'integration.hms': '2h12m',
          'frames': '132',
        },
      );
      expect(out, 'M42 — 2h12m (132)');
    });

    test('passes unknown tokens through unmodified', () {
      final out = expandWatermarkTokens(r'${not.a.token}', {});
      expect(out, r'${not.a.token}');
    });

    test('leaves an unterminated brace literal', () {
      final out = expandWatermarkTokens(r'cost is ${5', {'5': 'x'});
      expect(out, r'cost is ${5');
    });

    test('trims whitespace inside the token braces', () {
      final out = expandWatermarkTokens(r'${ target }', {'target': 'M31'});
      expect(out, 'M31');
    });

    test('renders plain text with no tokens unchanged', () {
      expect(expandWatermarkTokens('just text', {}), 'just text');
    });
  });
}

/// Build a fully-opaque flat-grey RGBA buffer (mid grey) for overlay tests.
Uint8List _opaqueGrey(int w, int h) {
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    out[i * 4] = 100;
    out[i * 4 + 1] = 100;
    out[i * 4 + 2] = 100;
    out[i * 4 + 3] = 255;
  }
  return out;
}

/// True when two encoded images decode to different pixel data. Decoding
/// normalises away encoder-metadata noise so we compare actual rendered pixels.
bool _pixelsDiffer(Uint8List a, Uint8List b) {
  final ia = img.decodePng(a);
  final ib = img.decodePng(b);
  if (ia == null || ib == null) return a.length != b.length;
  if (ia.width != ib.width || ia.height != ib.height) return true;
  for (var y = 0; y < ia.height; y++) {
    for (var x = 0; x < ia.width; x++) {
      final pa = ia.getPixel(x, y);
      final pb = ib.getPixel(x, y);
      if (pa.r != pb.r || pa.g != pb.g || pa.b != pb.b) return true;
    }
  }
  return false;
}
