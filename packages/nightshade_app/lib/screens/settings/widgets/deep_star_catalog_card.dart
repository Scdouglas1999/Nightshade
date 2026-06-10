import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/confirm_dialog.dart';
import '../../../utils/snackbar_helper.dart';

/// Settings card for the downloadable **deep-star tier** (Tycho-2 / Gaia subset
/// below the bundled HYG floor).
///
/// Lets the user point at a self-hosted tileset base URL, download it with a
/// hash-verified progress bar, see install status, verify, and delete. The
/// tier renders only when zoomed in past the deep-star FOV threshold and the
/// "Deep stars" layer is enabled.
class DeepStarCatalogCard extends ConsumerStatefulWidget {
  const DeepStarCatalogCard({super.key});

  @override
  ConsumerState<DeepStarCatalogCard> createState() =>
      _DeepStarCatalogCardState();
}

class _DeepStarCatalogCardState extends ConsumerState<DeepStarCatalogCard> {
  final DeepStarCatalogManager _manager = DeepStarCatalogManager();
  late final TextEditingController _urlController = TextEditingController();

  DeepStarStatus? _status;
  bool _loading = true;
  bool _busy = false;
  DeepStarDownloadProgress? _progress;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final url = await _manager.getBaseUrl();
    final status = await _manager.status();
    if (!mounted) return;
    setState(() {
      _urlController.text = url;
      _status = status;
      _loading = false;
    });
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _cancelRequested = false;
      _progress = null;
    });
    try {
      await _manager.setBaseUrl(_urlController.text.trim());
      final ok = await _manager.download(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        isCancelled: () async => _cancelRequested,
      );
      if (!mounted) return;
      if (ok) {
        // Force the renderer's manifest provider to re-read.
        ref.read(deepStarManifestRefreshProvider.notifier).state++;
        ref.read(showDeepStarsProvider.notifier).state = true;
        context.showSuccessSnackBar('Deep-star tiles installed');
      } else {
        context.showInfoSnackBar('Download paused — resume any time');
      }
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Download failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
        await _refresh();
      }
    }
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      final result = await _manager.verify();
      if (!mounted) return;
      if (result.ok) {
        context.showSuccessSnackBar(
            'All ${result.tilesChecked} tiles verified');
      } else {
        context.showErrorSnackBar(
            '${result.missing.length} missing, ${result.corrupt.length} corrupt');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await ConfirmDialog.show(
      context: context,
      title: 'Delete Deep-Star Tiles',
      message: 'Remove the downloaded deep-star tier? The bundled HYG stars '
          'are unaffected.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirm) return;
    await _manager.delete();
    ref.read(deepStarManifestRefreshProvider.notifier).state++;
    ref.read(showDeepStarsProvider.notifier).state = false;
    if (mounted) {
      context.showInfoSnackBar('Deep-star tiles deleted');
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final status = _status;
    final isInstalled = status?.isInstalled ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(
          color: isInstalled
              ? colors.success.withValues(alpha: 0.3)
              : colors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(NightshadeIcons.star, color: colors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Deep-Star Tier (Tycho-2 / Gaia)',
                  style: NightshadeTypography.h4
                      .copyWith(color: colors.textPrimary),
                ),
              ),
              if (isInstalled)
                _Badge(
                  label: status!.isComplete ? 'Installed' : 'Partial',
                  color: status.isComplete ? colors.success : colors.warning,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Streams faint stars below the bundled HYG floor (~mag 11.5) as '
            'view-culled tiles when zoomed in. Host a tileset built with '
            'tools/catalog_prep and point the URL below at it.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize13,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            TextField(
              controller: _urlController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Tileset base URL',
                hintText: DeepStarCatalogManager.defaultBaseUrl,
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: NightshadeTypography.fontSize13,
              ),
            ),
            if (isInstalled) ...[
              const SizedBox(height: 12),
              Text(
                '${status!.manifest!.totalStars} stars across '
                '${status.tilesPresent}/${status.manifest!.tiles.length} tiles'
                '${status.installedAt != null ? " • installed ${_fmt(status.installedAt!)}" : ""}',
                style: TextStyle(
                  color: colors.textSecondary.withValues(alpha: 0.8),
                  fontSize: NightshadeTypography.fontSize11,
                ),
              ),
            ],
            if (_busy && _progress != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline4),
                child: LinearProgressIndicator(
                  value: _progress!.fraction,
                  backgroundColor: colors.border,
                  valueColor: AlwaysStoppedAnimation(colors.primary),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_progress!.verifying ? "Verifying" : "Downloading"} '
                '${_progress!.tilesDone}/${_progress!.tilesTotal} • '
                '${(_progress!.bytesDone / 1024).toStringAsFixed(0)} KiB',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize11,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                NightshadeButton(
                  label: _busy
                      ? (_cancelRequested ? 'Stopping…' : 'Downloading…')
                      : (isInstalled ? 'Re-download / Resume' : 'Download'),
                  icon: NightshadeIcons.download,
                  variant: ButtonVariant.primary,
                  onPressed: _busy ? null : _download,
                ),
                if (_busy)
                  NightshadeButton(
                    label: 'Pause',
                    icon: NightshadeIcons.close,
                    variant: ButtonVariant.outline,
                    onPressed: _cancelRequested
                        ? null
                        : () => setState(() => _cancelRequested = true),
                  ),
                if (isInstalled && !_busy) ...[
                  NightshadeButton(
                    label: 'Verify',
                    icon: NightshadeIcons.success,
                    variant: ButtonVariant.outline,
                    onPressed: _verify,
                  ),
                  NightshadeButton(
                    label: 'Delete',
                    icon: NightshadeIcons.delete,
                    variant: ButtonVariant.destructive,
                    onPressed: _delete,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
      ),
      child: Text(label,
          style: NightshadeTypography.labelQuiet.copyWith(color: color)),
    );
  }
}
