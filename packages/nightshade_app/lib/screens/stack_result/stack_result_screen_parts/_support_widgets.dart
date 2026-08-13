// Part of ../stack_result_screen.dart -- extracted for maintainability.
//
// Action menu rows, stat rows and the linear RGBA renderers.
part of '../stack_result_screen.dart';

/// Export/share actions surfaced through the phone overflow menu (the four
/// inline header buttons do not fit a phone-width [ScreenHeader] Row).
enum _StackResultAction { png, jpeg, shareCard, astroBin }

/// Icon + label row for a [_StackResultAction] popup-menu entry.
class _ActionMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ActionMenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: NightshadeTokens.iconSm, color: colors.textSecondary),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Text(
          label,
          style: NightshadeTypography.bodySm.copyWith(
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// A label-left, value-right stat row using monospace tabular value type.
class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label,
              style: NightshadeTypography.bodySm.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: NightshadeTypography.mono.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The linear-stretch pixel loops, top-level so they can run in a worker
/// isolate via `Isolate.run` — the closure that calls them captures only the
/// buffer and the pixel count, both of which cross an isolate boundary.
///
/// A 6000x4000 master is 24 million pixels: two full passes plus a 96 MB
/// allocation. On the UI isolate, inside `build`, that is a frame stall the
/// operator sees as the app hanging.
/// Linear min/max normalisation of a u16 mono buffer to grayscale RGBA.
Uint8List renderLinearGrayRgba(Uint16List mono) {
  var min = 65535;
  var max = 0;
  for (final v in mono) {
    if (v < min) min = v;
    if (v > max) max = v;
  }
  final span = max - min;
  final out = Uint8List(mono.length * 4);
  for (var i = 0; i < mono.length; i++) {
    final g = span <= 0 ? 0 : (((mono[i] - min) * 255) ~/ span);
    final o = i * 4;
    out[o] = g;
    out[o + 1] = g;
    out[o + 2] = g;
    out[o + 3] = 255;
  }
  return out;
}

/// Per-channel linear min/max normalisation of an interleaved RGB16 buffer to
/// RGBA. Each channel is stretched against its own extent so the colour
/// balance is preserved rather than dominated by the brightest channel.
Uint8List renderLinearColorRgba(Uint16List rgb, int pixelCount) {
  var rMin = 65535, gMin = 65535, bMin = 65535;
  var rMax = 0, gMax = 0, bMax = 0;
  for (var i = 0; i < pixelCount; i++) {
    final base = i * 3;
    final r = rgb[base];
    final g = rgb[base + 1];
    final b = rgb[base + 2];
    if (r < rMin) rMin = r;
    if (r > rMax) rMax = r;
    if (g < gMin) gMin = g;
    if (g > gMax) gMax = g;
    if (b < bMin) bMin = b;
    if (b > bMax) bMax = b;
  }
  final rSpan = rMax - rMin;
  final gSpan = gMax - gMin;
  final bSpan = bMax - bMin;
  final out = Uint8List(pixelCount * 4);
  for (var i = 0; i < pixelCount; i++) {
    final base = i * 3;
    final o = i * 4;
    out[o] = rSpan <= 0 ? 0 : (((rgb[base] - rMin) * 255) ~/ rSpan);
    out[o + 1] = gSpan <= 0 ? 0 : (((rgb[base + 1] - gMin) * 255) ~/ gSpan);
    out[o + 2] = bSpan <= 0 ? 0 : (((rgb[base + 2] - bMin) * 255) ~/ bSpan);
    out[o + 3] = 255;
  }
  return out;
}
