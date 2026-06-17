import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import 'settings_widgets.dart';

/// Manage the connected appliance's plate-solve / star catalogs over the
/// network (`/api/catalog/*`). A freshly-imaged Pi ships with no catalogs, so
/// without this a remote operator could not populate them without SSH. Distinct
/// from the local "Catalog" settings, which manage the phone's own planetarium
/// catalogs. Remote-only — the local desktop manages its catalogs directly.
class RigCatalogSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const RigCatalogSettings({super.key, this.isMobile = false});

  @override
  ConsumerState<RigCatalogSettings> createState() => _RigCatalogSettingsState();
}

class _RigCatalogSettingsState extends ConsumerState<RigCatalogSettings> {
  List<RemoteCatalogStatus> _installed = const [];
  List<RemoteAvailableCatalog> _available = const [];
  bool _loading = false;
  bool _busy = false;
  String? _error;

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
      final status = await backend.getCatalogStatus();
      final available = await backend.listAvailableCatalogs();
      if (!mounted) return;
      setState(() {
        _installed = status.catalogs;
        _available = available;
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

  Future<void> _run(String label, Future<void> Function() action) async {
    final backend = _backend;
    if (backend == null) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) context.showSuccessSnackBar('$label started');
    } catch (e) {
      if (mounted) context.showErrorSnackBar('$label failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  static String _fmtBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  bool get _isInstalled => _installed.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final backend = _backend;

    return SettingsPage(
      title: 'Appliance Catalogs',
      description: 'Download and verify the rig\'s plate-solve / star catalogs',
      isMobile: widget.isMobile,
      hideHeader: widget.isMobile,
      children: [
        if (backend == null)
          _Info(
            colors: colors,
            icon: LucideIcons.info,
            text:
                'Connect to a remote appliance to manage its catalogs. This is '
                'separate from the phone\'s own planetarium catalogs.',
          )
        else ...[
          Row(
            children: [
              Text('Installed on appliance',
                  style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: NightshadeTypography.fontSize13,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              NightshadeButton(
                onPressed: _loading ? null : _refresh,
                label: 'Refresh',
                icon: LucideIcons.rotateCw,
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
              const SizedBox(width: 8),
              NightshadeButton(
                onPressed: (!_busy && _isInstalled)
                    ? () => _run('Reload', () => _backend!.reloadCatalogs())
                    : null,
                label: 'Reload',
                icon: LucideIcons.refreshCw,
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading && _installed.isEmpty)
            _Info(colors: colors, icon: LucideIcons.loader, text: 'Loading…')
          else if (_installed.isEmpty)
            _Info(
                colors: colors,
                icon: LucideIcons.alertTriangle,
                text: 'No catalogs installed on the appliance — plate-solving '
                    'needs at least one. Install from the list below.')
          else
            for (final c in _installed) _installedTile(colors, c),
          const SizedBox(height: 16),
          Text('Available to download',
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_available.isEmpty)
            _Info(
                colors: colors,
                icon: LucideIcons.info,
                text: _loading
                    ? 'Loading…'
                    : 'No catalog manifest available (the appliance has no '
                        'download source configured).')
          else
            for (final a in _available) _availableTile(colors, a),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _Info(
                colors: colors,
                icon: LucideIcons.alertTriangle,
                text: 'Error: $_error'),
          ],
        ],
      ],
    );
  }

  Widget _installedTile(NightshadeColors colors, RemoteCatalogStatus c) {
    final ok =
        c.status.toLowerCase() == 'ok' || c.status.toLowerCase() == 'installed';
    return NightshadeCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? LucideIcons.checkCircle : LucideIcons.alertTriangle,
                  size: 16, color: ok ? colors.success : colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(c.name,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: NightshadeTypography.fontSize14,
                        fontWeight: FontWeight.w600)),
              ),
              NightshadeButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        'Verify', () => _backend!.verifyCatalog(name: c.name)),
                label: 'Verify',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
              NightshadeButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        'Uninstall', () => _backend!.uninstallCatalog(c.name)),
                label: 'Remove',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${c.version ?? '—'} · ${_fmtBytes(c.sizeBytes)} · '
            '${c.objectCount != null ? '${c.objectCount} objects · ' : ''}${c.status}',
            style: TextStyle(
                color: colors.textMuted,
                fontSize: NightshadeTypography.fontSize12),
          ),
          if (c.errors.isNotEmpty)
            Text(c.errors.join('; '),
                style: TextStyle(
                    color: colors.error,
                    fontSize: NightshadeTypography.fontSize12)),
        ],
      ),
    );
  }

  Widget _availableTile(NightshadeColors colors, RemoteAvailableCatalog a) {
    final installed = _installed.any((c) => c.name == a.name);
    return NightshadeCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(a.displayName,
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: NightshadeTypography.fontSize14,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (a.requiredForPlateSolve) ...[
                      const SizedBox(width: 6),
                      Icon(LucideIcons.star, size: 12, color: colors.warning),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                    '${a.version} · ${_fmtBytes(a.sizeBytes)} · ${a.description}',
                    style: TextStyle(
                        color: colors.textMuted,
                        fontSize: NightshadeTypography.fontSize12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          NightshadeButton(
            onPressed: (_busy || installed)
                ? null
                : () =>
                    _run('Download', () => _backend!.downloadCatalog(a.name)),
            label: installed ? 'Installed' : 'Download',
            icon: installed ? LucideIcons.check : LucideIcons.download,
            variant: installed ? ButtonVariant.ghost : ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String text;

  const _Info({required this.colors, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
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
