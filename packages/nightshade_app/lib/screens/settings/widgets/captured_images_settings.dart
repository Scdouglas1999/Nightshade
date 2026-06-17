import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
// `ConnectionState` collides with Flutter's FutureBuilder enum; we only use
// Flutter's here.
import 'package:nightshade_core/nightshade_core.dart' hide ConnectionState;
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import 'settings_widgets.dart';

/// Browse the frames captured on the connected appliance.
///
/// The headless server already serves the listing (`GET /api/images`),
/// thumbnails (`/api/images/<id>/thumbnail`), and downloads — there just was no
/// mobile UI consuming them, so a remote operator could not see what the rig
/// had shot. This grid fetches thumbnails on demand (cached) and shows frame
/// metadata. Remote-only; the local desktop has its own image browser.
class CapturedImagesSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const CapturedImagesSettings({super.key, this.isMobile = false});

  @override
  ConsumerState<CapturedImagesSettings> createState() =>
      _CapturedImagesSettingsState();
}

class _CapturedImagesSettingsState
    extends ConsumerState<CapturedImagesSettings> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = false;
  String? _error;
  final Map<int, Uint8List> _thumbCache = {};

  NetworkBackend? get _backend {
    final b = ref.read(backendProvider);
    return b is NetworkBackend ? b : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final backend = _backend;
    if (backend == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await backend.getAllImageRows();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  int? _idOf(Map<String, dynamic> row) {
    final v = row['id'] ?? row['imageId'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  String _labelOf(Map<String, dynamic> row) {
    final target = row['targetName'] ?? row['target'];
    final filter = row['filter'];
    final file = row['fileName'] ?? row['filename'] ?? row['path'];
    final parts = <String>[
      if (target is String && target.isNotEmpty) target,
      if (filter is String && filter.isNotEmpty) filter,
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    if (file is String && file.isNotEmpty) return file.split('/').last;
    return 'Frame';
  }

  Future<Uint8List?> _thumb(int id) async {
    final cached = _thumbCache[id];
    if (cached != null) return cached;
    final backend = _backend;
    if (backend == null) return null;
    try {
      final bytes = await backend.getImageThumbnail(id);
      _thumbCache[id] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final backend = _backend;

    return SettingsPage(
      title: 'Captured Images',
      description: 'Browse frames captured on the connected appliance',
      isMobile: widget.isMobile,
      hideHeader: widget.isMobile,
      children: [
        if (backend == null)
          _info(colors, LucideIcons.info,
              'Connect to a remote appliance to browse its captured frames.')
        else ...[
          Row(
            children: [
              Text('${_rows.length} frame${_rows.length == 1 ? '' : 's'}',
                  style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: NightshadeTypography.fontSize13)),
              const Spacer(),
              NightshadeButton(
                onPressed: _loading ? null : _refresh,
                label: 'Refresh',
                icon: LucideIcons.rotateCw,
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading && _rows.isEmpty)
            _info(colors, LucideIcons.loader, 'Loading…')
          else if (_rows.isEmpty)
            _info(colors, LucideIcons.image,
                'No frames captured on the appliance yet.')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: widget.isMobile ? 120 : 160,
                childAspectRatio: 1,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final row = _rows[i];
                final id = _idOf(row);
                return _GalleryTile(
                  colors: colors,
                  label: _labelOf(row),
                  accepted: row['isAccepted'] == true,
                  thumb: id == null ? null : () => _thumb(id),
                  onTap: id == null ? null : () => _showFull(id, _labelOf(row)),
                );
              },
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _info(colors, LucideIcons.alertTriangle, 'Error: $_error'),
          ],
        ],
      ],
    );
  }

  Future<void> _showFull(int id, String label) async {
    final bytes = await _thumb(id);
    if (!mounted || bytes == null) {
      if (mounted) context.showErrorSnackBar('Could not load $label');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            Flexible(child: InteractiveViewer(child: Image.memory(bytes))),
          ],
        ),
      ),
    );
  }

  Widget _info(NightshadeColors colors, IconData icon, String text) {
    return NightshadeCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize13)),
          ),
        ],
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final bool accepted;
  final Future<Uint8List?> Function()? thumb;
  final VoidCallback? onTap;

  const _GalleryTile({
    required this.colors,
    required this.label,
    required this.accepted,
    required this.thumb,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: colors.background),
            if (thumb != null)
              FutureBuilder<Uint8List?>(
                future: thumb!(),
                builder: (context, snap) {
                  final bytes = snap.data;
                  if (bytes == null) {
                    return Center(
                      child: snap.connectionState == ConnectionState.done
                          ? Icon(LucideIcons.imageOff,
                              size: 20, color: colors.textMuted)
                          : const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  return Image.memory(bytes, fit: BoxFit.cover);
                },
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                color: Colors.black54,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
            if (!accepted)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(LucideIcons.xCircle, size: 14, color: colors.error),
              ),
          ],
        ),
      ),
    );
  }
}
