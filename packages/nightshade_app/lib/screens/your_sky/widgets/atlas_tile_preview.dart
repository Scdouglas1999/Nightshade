import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Renders a finalized atlas tile (or a time-scrubbed `asOf` snapshot of it) as
/// an image, fetching the PNG path through [skyTileProvider]. Used by the region
/// card (deepest tile) and the region detail cutout panel.
///
/// On the desktop `FfiBackend` the bridge writes the PNG to a local cache path
/// and this loads it directly; on the mobile `NetworkBackend` the provider
/// resolves the same call over the headless atlas routes and yields a locally
/// cached file path, so the widget is backend-agnostic.
class AtlasTilePreview extends ConsumerWidget {
  final int tileId;
  final DateTime? asOf;
  final BoxFit fit;

  const AtlasTilePreview({
    super.key,
    required this.tileId,
    this.asOf,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final pngAsync =
        ref.watch(skyTileProvider(SkyTileQuery(tileId, asOf: asOf)));

    return pngAsync.when(
      data: (path) => _TileImage(path: path, fit: fit, colors: colors),
      loading: () => _PreviewState(
        colors: colors,
        child: const NightshadeCircularProgress(
          value: 0,
          indeterminate: true,
          size: NightshadeTokens.iconLg,
        ),
      ),
      error: (_, __) => _PreviewState(
        colors: colors,
        child: Icon(LucideIcons.imageOff,
            size: NightshadeTokens.iconLg, color: colors.textMuted),
      ),
    );
  }
}

class _TileImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final NightshadeColors colors;

  const _TileImage({
    required this.path,
    required this.fit,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) {
      return _PreviewState(
        colors: colors,
        child: Icon(LucideIcons.imageOff,
            size: NightshadeTokens.iconLg, color: colors.textMuted),
      );
    }
    return Image.file(
      file,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => _PreviewState(
        colors: colors,
        child: Icon(LucideIcons.imageOff,
            size: NightshadeTokens.iconLg, color: colors.textMuted),
      ),
    );
  }
}

class _PreviewState extends StatelessWidget {
  final NightshadeColors colors;
  final Widget child;

  const _PreviewState({required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.surfaceAlt,
      alignment: Alignment.center,
      child: child,
    );
  }
}
