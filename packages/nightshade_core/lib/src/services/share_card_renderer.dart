// Stack-and-Share Loop — share-card renderer.
//
// The canonical, UI-free image-composition logic for the Stack-and-Share
// feature lives here. It owns three concerns that used to be duplicated
// inside `LiveStackingBroadcastService`:
//
//   1. **Percentile auto-stretch** of raw 16-bit luminance frames
//      (0.5%/99.5% black/white points) — the difference between a frame
//      that "looks like M42" and "looks like a black square."
//   2. **Watermark text** drawn bottom-left with a drop shadow, matching the
//      Astrobin / Cuiv outreach convention.
//   3. **Stat overlay** — a translucent rounded panel of [ShareStatLine]s
//      (title + labelled values) drawn per [ShareCardLayout].
//
// Two input paths are supported:
//
//   * [renderJpegFromMono] — for the live-stacking engine, which emits a
//     single-channel u16 luminance buffer that still needs stretching.
//   * [renderPngFromRgba] / [renderJpegFromRgba] — for the export service,
//     which already produced a stretched 8-bit RGBA result and only needs
//     the overlay + watermark composited on top.
//
// Pure Dart (the `image` package only) so the desktop, mobile, and headless
// builds all share one path, and so it is trivially unit-testable without a
// Flutter binding. Per project policy this code surfaces errors (a short
// buffer throws) rather than silently serving garbage.

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/imaging/stack_and_share_models.dart'
    show ShareCardFontScale, ShareCardLayout, ShareCardSpec, ShareStatLine;

/// Renders share-ready images (watermark + stretch + stat overlay) from either
/// raw mono u16 frames or already-stretched RGBA buffers.
///
/// Stateless and cheap to construct; a single instance can be reused for every
/// frame. [LiveStackingBroadcastService] holds one and delegates to it so the
/// broadcast and the Stack-and-Share export produce byte-identical overlays.
class ShareCardRenderer {
  const ShareCardRenderer();

  // ===========================================================================
  // Public API — mono u16 source (needs stretching)
  // ===========================================================================

  /// Render a single-channel u16 luminance buffer to a watermarked,
  /// stat-overlaid JPEG.
  ///
  /// The buffer is percentile-stretched (see [computeStretchEnds]), optionally
  /// downscaled to [ShareCardSpec.targetWidth]/[ShareCardSpec.targetHeight]
  /// preserving aspect ratio, then composited with the overlay defined by
  /// [spec].
  ///
  /// Throws [StateError] when [data] is shorter than `width * height` — a short
  /// buffer would corrupt the encode, and silently serving garbage would hide
  /// the bug.
  Uint8List renderJpegFromMono({
    required int width,
    required int height,
    required Uint16List data,
    required ShareCardSpec spec,
    int quality = 90,
  }) {
    final bitmap = _stretchMonoToRgb(
      width: width,
      height: height,
      data: data,
      targetWidth: spec.targetWidth,
      targetHeight: spec.targetHeight,
    );
    _composite(bitmap, spec);
    return Uint8List.fromList(img.encodeJpg(bitmap, quality: quality));
  }

  // ===========================================================================
  // Public API — already-stretched RGBA source
  // ===========================================================================

  /// Render an already-stretched 8-bit RGBA buffer to a watermarked,
  /// stat-overlaid PNG (lossless — the preferred archival/share format for the
  /// stacked master).
  ///
  /// The [rgba] buffer is interpreted as tightly-packed `R,G,B,A` bytes,
  /// `width * height * 4` long. Throws [StateError] on a short buffer.
  Uint8List renderPngFromRgba({
    required int width,
    required int height,
    required Uint8List rgba,
    required ShareCardSpec spec,
  }) {
    final bitmap = _rgbaToImage(width: width, height: height, rgba: rgba);
    _composite(bitmap, spec);
    return Uint8List.fromList(img.encodePng(bitmap));
  }

  /// Render an already-stretched 8-bit RGBA buffer to a watermarked,
  /// stat-overlaid JPEG. Same input contract as [renderPngFromRgba]; emits a
  /// compressed JPEG for size-constrained shares (social posts, LAN preview).
  Uint8List renderJpegFromRgba({
    required int width,
    required int height,
    required Uint8List rgba,
    required ShareCardSpec spec,
    int quality = 90,
  }) {
    final bitmap = _rgbaToImage(width: width, height: height, rgba: rgba);
    _composite(bitmap, spec);
    return Uint8List.fromList(img.encodeJpg(bitmap, quality: quality));
  }

  // ===========================================================================
  // Stretch + decode helpers
  // ===========================================================================

  /// Percentile-stretch a u16 luminance buffer into a 3-channel RGB
  /// [img.Image], optionally aspect-fit downscaled to the target box.
  img.Image _stretchMonoToRgb({
    required int width,
    required int height,
    required Uint16List data,
    required int targetWidth,
    required int targetHeight,
  }) {
    final expected = width * height;
    if (width <= 0 || height <= 0) {
      throw StateError(
        'Share-card mono source has non-positive dimensions '
        '(width=$width height=$height)',
      );
    }
    if (data.length < expected) {
      throw StateError(
        'Share-card mono buffer too small: ${data.length} < $expected '
        '(width=$width height=$height)',
      );
    }

    // Per-frame percentile stretch: black at the 0.5% percentile, white at the
    // 99.5%. Matches the desktop preview's default auto-stretch and looks
    // correct for the typical long-exposure DSO this is built for.
    final (blackPoint, whitePoint) = computeStretchEnds(data);
    final range = (whitePoint - blackPoint).clamp(1, 65535).toInt();

    final bytes = Uint8List(expected);
    for (var i = 0; i < expected; i++) {
      final value = data[i] - blackPoint;
      final scaled = (value * 255 ~/ range).clamp(0, 255);
      bytes[i] = scaled;
    }

    var bitmap = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: bytes.buffer,
      numChannels: 1,
      order: img.ChannelOrder.red,
      format: img.Format.uint8,
    );

    bitmap = _aspectFitResize(
      bitmap,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );

    // Promote to RGB so the overlay can render in colour. The pixel data is
    // luminance, so RGB == grey == identical channels.
    return bitmap.convert(numChannels: 3);
  }

  /// Build a 3-channel RGB [img.Image] from a tightly-packed RGBA buffer.
  ///
  /// The export pipeline produces RGBA; we drop alpha to RGB here because the
  /// stacked master is fully opaque and the overlay composites onto opaque
  /// pixels. Throws [StateError] on a short or mis-dimensioned buffer.
  img.Image _rgbaToImage({
    required int width,
    required int height,
    required Uint8List rgba,
  }) {
    if (width <= 0 || height <= 0) {
      throw StateError(
        'Share-card RGBA source has non-positive dimensions '
        '(width=$width height=$height)',
      );
    }
    final expected = width * height * 4;
    if (rgba.length < expected) {
      throw StateError(
        'Share-card RGBA buffer too small: ${rgba.length} < $expected '
        '(width=$width height=$height)',
      );
    }
    final bitmap = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
      format: img.Format.uint8,
    );
    // Composite onto opaque RGB so JPEG/PNG carry no surprise alpha and the
    // translucent overlay blends against the image, not transparency.
    return bitmap.convert(numChannels: 3);
  }

  /// Aspect-fit downscale [bitmap] so it fits inside the target box, preserving
  /// the source aspect ratio. A target dimension of `<= 0`, or a source that
  /// already matches the target, returns the bitmap unchanged.
  img.Image _aspectFitResize(
    img.Image bitmap, {
    required int targetWidth,
    required int targetHeight,
  }) {
    final width = bitmap.width;
    final height = bitmap.height;
    if (targetWidth <= 0 || targetHeight <= 0) return bitmap;
    if (width == targetWidth && height == targetHeight) return bitmap;

    final srcRatio = width / height;
    final tgtRatio = targetWidth / targetHeight;
    int outW;
    int outH;
    if (srcRatio > tgtRatio) {
      outW = targetWidth;
      outH = (targetWidth / srcRatio).round().clamp(1, targetHeight);
    } else {
      outH = targetHeight;
      outW = (targetHeight * srcRatio).round().clamp(1, targetWidth);
    }
    if (outW == width && outH == height) return bitmap;
    return img.copyResize(bitmap, width: outW, height: outH);
  }

  // ===========================================================================
  // Overlay compositing (watermark + stat panel)
  // ===========================================================================

  /// Draw the stat panel then the watermark onto [bitmap], in place. The
  /// watermark is drawn last so it always sits on top of the panel when the
  /// two would overlap.
  ///
  /// The font is resolved once from [spec] (so the panel and watermark share a
  /// glyph size) honouring [ShareCardSpec.fontScale].
  void _composite(img.Image bitmap, ShareCardSpec spec) {
    final font = fontForSpec(spec, bitmap.height);
    _drawStatPanel(bitmap, spec, font);

    final watermark = spec.watermark?.trim();
    if (watermark != null && watermark.isNotEmpty) {
      drawWatermark(bitmap, watermark, font: font);
    }
  }

  /// Resolve the bitmap font for [spec] at the given rendered [imageHeight],
  /// honouring [ShareCardSpec.fontScale]: a fixed scale pins a specific
  /// built-in font; [ShareCardFontScale.scaleToHeight] defers to
  /// [fontForHeight].
  ///
  /// Exposed (not private) so tests can assert which font a given spec/height
  /// resolves to — e.g. that the 720px broadcast frame keeps the historical
  /// arial48 watermark rather than silently dropping to arial24.
  img.BitmapFont fontForSpec(ShareCardSpec spec, int imageHeight) {
    return switch (spec.fontScale) {
      ShareCardFontScale.small => img.arial14,
      ShareCardFontScale.medium => img.arial24,
      ShareCardFontScale.large => img.arial48,
      ShareCardFontScale.scaleToHeight => fontForHeight(imageHeight),
    };
  }

  /// Pick a built-in bitmap font whose line height is roughly 4% of the image
  /// height, so the overlay scales sensibly from a 256px thumbnail to a 4K
  /// master without needing a TTF rasteriser.
  ///
  /// Exposed (not private) so tests can pin the height→font thresholds.
  img.BitmapFont fontForHeight(int imageHeight) {
    final target = imageHeight * 0.04;
    if (target >= 40) return img.arial48;
    if (target >= 20) return img.arial24;
    return img.arial14;
  }

  /// Measure the rendered pixel width of [text] in [font], summing per-glyph
  /// advances (matching how [img.drawString] lays glyphs out). Used to size the
  /// stat panel to its contents.
  int _measureText(img.BitmapFont font, String text) {
    var width = 0;
    for (final c in text.codeUnits) {
      final ch = font.characters[c];
      if (ch == null) continue;
      width += ch.xAdvance;
    }
    return width;
  }

  /// Draw the [ShareCardSpec.title] + [ShareCardSpec.stats] as a translucent
  /// rounded dark panel, positioned per [ShareCardSpec.layout]:
  ///
  ///   * [ShareCardLayout.bottomBar] — a full-width bar pinned to the bottom
  ///     edge, title on the left, stats laid out left-to-right after it.
  ///   * [ShareCardLayout.cornerCard] — a compact card floated in the
  ///     top-right corner, title on its own line above one stat per line.
  ///
  /// No-op when there is neither a title nor any stats (e.g. a watermark-only
  /// share), so a bare image isn't gratuitously darkened.
  void _drawStatPanel(img.Image bitmap, ShareCardSpec spec, img.BitmapFont font) {
    final title = spec.title.trim();
    final stats = spec.stats;
    if (title.isEmpty && stats.isEmpty) return;

    final lineHeight = font.lineHeight;
    // Geometry derived from the line height so it scales with the chosen font.
    final pad = (lineHeight * 0.5).round().clamp(4, 48);
    final gap = (lineHeight * 0.4).round().clamp(2, 32);
    final radius = (lineHeight * 0.35).round().clamp(2, 24);

    // Panel fill + stroke: a low-alpha dark fill keeps the underlying image
    // readable; a faint light stroke separates it from a bright nebula edge.
    final fill = img.ColorUint8.rgba(0, 0, 0, 140);
    final stroke = img.ColorUint8.rgba(255, 255, 255, 40);

    switch (spec.layout) {
      case ShareCardLayout.bottomBar:
        _drawBottomBar(
          bitmap,
          font: font,
          lineHeight: lineHeight,
          pad: pad,
          gap: gap,
          radius: radius,
          fill: fill,
          stroke: stroke,
          title: title,
          stats: stats,
        );
      case ShareCardLayout.cornerCard:
        _drawCornerCard(
          bitmap,
          font: font,
          lineHeight: lineHeight,
          pad: pad,
          gap: gap,
          radius: radius,
          fill: fill,
          stroke: stroke,
          title: title,
          stats: stats,
        );
    }
  }

  void _drawBottomBar(
    img.Image bitmap, {
    required img.BitmapFont font,
    required int lineHeight,
    required int pad,
    required int gap,
    required int radius,
    required img.Color fill,
    required img.Color stroke,
    required String title,
    required List<ShareStatLine> stats,
  }) {
    // A single-row bar: title, then each stat as "LABEL value" segments.
    final segments = <String>[
      if (title.isNotEmpty) title,
      for (final s in stats) '${s.label.trim()}  ${s.value.trim()}'.trim(),
    ];
    if (segments.isEmpty) return;

    final barHeight = lineHeight + pad * 2;
    final y0 = bitmap.height - barHeight;
    final y1 = bitmap.height - 1;

    img.fillRect(
      bitmap,
      x1: 0,
      y1: y0,
      x2: bitmap.width - 1,
      y2: y1,
      color: fill,
      radius: radius,
    );
    img.drawRect(
      bitmap,
      x1: 0,
      y1: y0,
      x2: bitmap.width - 1,
      y2: y1,
      color: stroke,
      radius: radius,
    );

    final textY = y0 + pad;
    var x = pad;
    // The title renders brighter than the stat segments for hierarchy.
    if (title.isNotEmpty) {
      img.drawString(
        bitmap,
        title,
        font: font,
        x: x + 1,
        y: textY + 1,
        color: img.ColorUint8.rgba(0, 0, 0, 200),
      );
      img.drawString(
        bitmap,
        title,
        font: font,
        x: x,
        y: textY,
        color: img.ColorUint8.rgb(255, 255, 255),
      );
      x += _measureText(font, title) + gap * 3;
    }
    final statColor = img.ColorUint8.rgb(210, 220, 235);
    for (final s in stats) {
      final segment = '${s.label.trim()}  ${s.value.trim()}'.trim();
      if (segment.isEmpty) continue;
      if (x >= bitmap.width - pad) break; // ran out of horizontal room
      img.drawString(
        bitmap,
        segment,
        font: font,
        x: x + 1,
        y: textY + 1,
        color: img.ColorUint8.rgba(0, 0, 0, 200),
      );
      img.drawString(
        bitmap,
        segment,
        font: font,
        x: x,
        y: textY,
        color: statColor,
      );
      x += _measureText(font, segment) + gap * 3;
    }
  }

  void _drawCornerCard(
    img.Image bitmap, {
    required img.BitmapFont font,
    required int lineHeight,
    required int pad,
    required int gap,
    required int radius,
    required img.Color fill,
    required img.Color stroke,
    required String title,
    required List<ShareStatLine> stats,
  }) {
    // Lay out the title on its own line, then one "label  value" per stat line.
    final lines = <String>[
      if (title.isNotEmpty) title,
      for (final s in stats) '${s.label.trim()}  ${s.value.trim()}'.trim(),
    ].where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return;

    // Card sized to its widest line + its line count.
    var contentWidth = 0;
    for (final line in lines) {
      final w = _measureText(font, line);
      if (w > contentWidth) contentWidth = w;
    }
    final cardWidth =
        (contentWidth + pad * 2).clamp(1, bitmap.width).toInt();
    final cardHeight = (lines.length * lineHeight +
            (lines.length - 1) * gap +
            pad * 2)
        .clamp(1, bitmap.height)
        .toInt();

    // Top-right corner with a small inset margin.
    final margin = pad;
    final x1 = (bitmap.width - margin - cardWidth).clamp(0, bitmap.width - 1);
    final y0 = margin.clamp(0, bitmap.height - 1);
    final x2 = (x1 + cardWidth).clamp(0, bitmap.width - 1);
    final y1 = (y0 + cardHeight).clamp(0, bitmap.height - 1);

    img.fillRect(
      bitmap,
      x1: x1,
      y1: y0,
      x2: x2,
      y2: y1,
      color: fill,
      radius: radius,
    );
    img.drawRect(
      bitmap,
      x1: x1,
      y1: y0,
      x2: x2,
      y2: y1,
      color: stroke,
      radius: radius,
    );

    final titleColor = img.ColorUint8.rgb(255, 255, 255);
    final statColor = img.ColorUint8.rgb(210, 220, 235);
    var ly = y0 + pad;
    final textX = x1 + pad;
    for (var i = 0; i < lines.length; i++) {
      final isTitle = title.isNotEmpty && i == 0;
      img.drawString(
        bitmap,
        lines[i],
        font: font,
        x: textX + 1,
        y: ly + 1,
        color: img.ColorUint8.rgba(0, 0, 0, 200),
      );
      img.drawString(
        bitmap,
        lines[i],
        font: font,
        x: textX,
        y: ly,
        color: isTitle ? titleColor : statColor,
      );
      ly += lineHeight + gap;
    }
  }

  // ===========================================================================
  // Watermark (bottom-left, drop shadow)
  // ===========================================================================

  /// Draw the watermark [text] onto [bitmap] in place, bottom-left, with a
  /// subtle dark drop shadow under a white fill — the convention Astrobin /
  /// Cuiv overlays use for outreach. No-op for empty text.
  ///
  /// [font] selects the glyph size; when omitted it scales with the image
  /// height via [fontForHeight].
  void drawWatermark(img.Image bitmap, String text, {img.BitmapFont? font}) {
    if (text.isEmpty) return;
    font ??= fontForHeight(bitmap.height);
    // Padding from the bottom-left corner; scales with image height so small
    // downscales still look right.
    final pad = (bitmap.height * 0.025).clamp(8, 64).toInt();
    final x = pad;
    final y = bitmap.height - pad - font.lineHeight;
    // Drop shadow for legibility on bright nebula edges.
    img.drawString(
      bitmap,
      text,
      font: font,
      x: x + 2,
      y: y + 2,
      color: img.ColorUint8.rgb(0, 0, 0),
    );
    img.drawString(
      bitmap,
      text,
      font: font,
      x: x,
      y: y,
      color: img.ColorUint8.rgb(255, 255, 255),
    );
  }

  // ===========================================================================
  // Percentile stretch
  // ===========================================================================

  /// Compute the 0.5%/99.5% percentile black/white points for the stretch.
  ///
  /// Builds a sparse histogram (a full 65536-bin array would be wasteful for
  /// small previews) and walks the unique values sorted. Falls back to the full
  /// `(0, 65535)` range when the histogram is empty or degenerate (a single
  /// tone), which would otherwise hand the encoder a divide-by-zero range.
  (int, int) computeStretchEnds(Uint16List data) {
    final counts = <int, int>{};
    for (final v in data) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final keys = counts.keys.toList()..sort();
    if (keys.isEmpty) return (0, 65535);
    final total = data.length;
    final lowTarget = (total * 0.005).floor();
    final highTarget = (total * 0.995).ceil();
    var acc = 0;
    int? black;
    int? white;
    for (final k in keys) {
      acc += counts[k]!;
      if (black == null && acc >= lowTarget) {
        black = k;
      }
      if (white == null && acc >= highTarget) {
        white = k;
      }
      if (black != null && white != null) break;
    }
    black ??= keys.first;
    white ??= keys.last;
    if (white <= black) {
      return (0, 65535);
    }
    return (black, white);
  }
}

/// Expand the small watermark template language shared by the broadcast
/// watermark and the Stack-and-Share share card.
///
/// Supports `${token}` substitutions from [tokens]; a `${` with no closing `}`
/// is left literal. Unknown tokens fall through as literal `${token}` text so a
/// user sees their typo rather than having it silently dropped (matching the
/// lenient behaviour the Run Dashboard's notification template uses).
///
/// The caller owns the token→value mapping (e.g. the broadcast builds it from
/// its `BroadcastSessionState`); this helper is purely the string machinery so
/// every caller interpolates identically.
String expandWatermarkTokens(String template, Map<String, String> tokens) {
  final buf = StringBuffer();
  var i = 0;
  while (i < template.length) {
    final ch = template[i];
    if (ch == r'$' && i + 1 < template.length && template[i + 1] == '{') {
      final close = template.indexOf('}', i + 2);
      if (close > 0) {
        final token = template.substring(i + 2, close).trim();
        final resolved = tokens[token];
        // Unknown tokens surface unmodified so the user can spot the typo.
        buf.write(resolved ?? '\${$token}');
        i = close + 1;
        continue;
      }
    }
    buf.write(ch);
    i++;
  }
  return buf.toString();
}
