import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/confirm_dialog.dart';
import '../../../utils/snackbar_helper.dart';
import 'settings_widgets.dart';

/// Manage the connected appliance's plate-solve / star catalogs over the
/// network (`/api/catalog/*`). A freshly-imaged Pi ships with no catalogs, so
/// without this a remote operator could not populate them without SSH. Distinct
/// from the local "Catalogs" settings, which manage this device's own
/// planetarium catalogs — this page ships on desktop too, so nothing here may
/// assume the client is a phone.
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
  Object? _actionToken;
  String? _busyAction;
  String? _busyCatalog;
  bool _confirmationOpen = false;
  String? _error;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;
  int _loadGeneration = 0;

  bool get _busy => _actionToken != null;

  NetworkBackend? get _backend {
    final b = ref.read(backendProvider);
    return b is NetworkBackend ? b : null;
  }

  @override
  void initState() {
    super.initState();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (identical(previous, next) || !mounted) return;
        _loadGeneration++;
        setState(() {
          _installed = const [];
          _available = const [];
          _error = null;
          _loading = next is NetworkBackend;
          _actionToken = null;
          _busyAction = null;
          _busyCatalog = null;
          _confirmationOpen = false;
        });
        if (next is NetworkBackend) unawaited(_refresh());
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _backendSubscription?.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    final backend = _backend;
    final generation = ++_loadGeneration;
    if (backend == null) {
      if (!mounted) return;
      setState(() {
        _installed = const [];
        _available = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait<Object>([
        backend.getCatalogStatus(),
        backend.listAvailableCatalogs(),
      ]);
      if (!_isCurrentLoad(backend, generation)) return;
      final status = responses[0] as RemoteCatalogStatusResponse;
      final available = responses[1] as List<RemoteAvailableCatalog>;
      setState(() {
        // The status endpoint returns every known catalog, including
        // `missing` rows. Missing rows must remain downloadable.
        _installed = status.catalogs
            .where((catalog) => catalog.status.toLowerCase() != 'missing')
            .toList(growable: false);
        _available = available;
        _loading = false;
      });
    } catch (e) {
      if (!_isCurrentLoad(backend, generation)) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  bool _isCurrentLoad(NetworkBackend backend, int generation) =>
      mounted &&
      generation == _loadGeneration &&
      identical(ref.read(backendProvider), backend);

  bool _isCurrentAction(NetworkBackend backend, Object token) =>
      mounted &&
      identical(_actionToken, token) &&
      identical(ref.read(backendProvider), backend);

  Future<void> _run({
    required String actionLabel,
    required String successMessage,
    String? catalogName,
    required Future<void> Function(NetworkBackend backend) action,
  }) async {
    if (_busy || _confirmationOpen) return;
    final backend = _backend;
    if (backend == null) return;
    final token = Object();
    setState(() {
      _actionToken = token;
      _busyAction = actionLabel;
      _busyCatalog = catalogName;
    });
    try {
      await action(backend);
      if (mounted && _isCurrentAction(backend, token)) {
        context.showSuccessSnackBar(successMessage);
      }
    } catch (e) {
      if (mounted && _isCurrentAction(backend, token)) {
        context
            .showErrorSnackBar('$actionLabel failed: ${_describeFailure(e)}');
      }
    } finally {
      if (_isCurrentAction(backend, token)) {
        setState(() {
          _actionToken = null;
          _busyAction = null;
          _busyCatalog = null;
        });
        await _refresh();
      }
    }
  }

  /// Mutating catalog routes are admin-scope on the appliance. A device paired
  /// with the default scope got a bare "Access denied: Token scope is not
  /// permitted for this endpoint", which reads as a product bug instead of the
  /// re-pair it actually needs.
  static String _describeFailure(Object error) {
    final text = '$error';
    if (text.contains('Token scope is not permitted') ||
        text.contains('Access denied')) {
      return 'this device is paired without admin access. Re-pair it with '
          'Admin access on the rig to manage appliance catalogs.';
    }
    return text;
  }

  Future<void> _downloadCatalog(RemoteAvailableCatalog catalog) {
    return _run(
      actionLabel: 'Download',
      successMessage: '${catalog.displayName} installed',
      catalogName: catalog.name,
      action: (backend) async {
        final accepted = await backend.downloadCatalog(catalog.name);
        final completed = accepted.isTerminal
            ? accepted
            : await backend.awaitJobCompletion(
                accepted.jobId,
                timeout: const Duration(minutes: 30),
              );
        if (completed.state != 'succeeded') {
          final detail = completed.error?['message'] ??
              completed.error?['code'] ??
              completed.state;
          throw StateError('catalog job ended ${completed.state}: $detail');
        }
      },
    );
  }

  Future<void> _verifyCatalog(RemoteCatalogStatus catalog) {
    return _run(
      actionLabel: 'Verify',
      successMessage: '${catalog.name} catalog verified',
      catalogName: catalog.name,
      action: (backend) async {
        final results = await backend.verifyCatalog(name: catalog.name);
        final result = results[catalog.name];
        if (result == null) {
          throw StateError('the appliance returned no verification result');
        }
        if (!result.ok) {
          final detail = result.errors.isEmpty
              ? 'hash verification did not match'
              : result.errors.join('; ');
          throw StateError(detail);
        }
      },
    );
  }

  Future<void> _confirmUninstall(RemoteCatalogStatus catalog) async {
    if (_busy || _confirmationOpen) return;
    final backend = _backend;
    if (backend == null) return;
    setState(() => _confirmationOpen = true);
    final bool confirmed;
    try {
      confirmed = await ConfirmDialog.show(
        context: context,
        title: 'Remove ${catalog.name} catalog?',
        message: 'Features that depend on this catalog will stop working on '
            'the appliance until it is downloaded again.',
        confirmLabel: 'Remove',
        isDestructive: true,
      );
    } finally {
      if (mounted) setState(() => _confirmationOpen = false);
    }
    if (!mounted || !confirmed) return;
    if (!identical(ref.read(backendProvider), backend)) {
      context.showInfoSnackBar('Rig changed; catalog removal cancelled');
      return;
    }
    await _run(
      actionLabel: 'Remove',
      successMessage: '${catalog.name} catalog removed',
      catalogName: catalog.name,
      action: (authority) => authority.uninstallCatalog(catalog.name),
    );
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
          // Give the disconnected state a direct path to connection setup.
          _NotConnected(colors: colors, isMobile: widget.isMobile)
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
                onPressed: (_loading || _busy) ? null : _refresh,
                label: 'Refresh',
                icon: LucideIcons.rotateCw,
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
              const SizedBox(width: 8),
              NightshadeButton(
                onPressed: (!_busy && _isInstalled)
                    ? () => _run(
                          actionLabel: 'Reload',
                          successMessage: 'Catalog loaders reloaded',
                          action: (backend) => backend.reloadCatalogs(),
                        )
                    : null,
                label: 'Reload',
                icon: LucideIcons.refreshCw,
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                isLoading: _busyAction == 'Reload',
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
                onPressed: (_busy || _confirmationOpen)
                    ? null
                    : () => _verifyCatalog(c),
                label: 'Verify',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                isLoading: _busyAction == 'Verify' && _busyCatalog == c.name,
              ),
              NightshadeButton(
                onPressed: (_busy || _confirmationOpen)
                    ? null
                    : () => _confirmUninstall(c),
                label: 'Remove',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                isLoading: _busyAction == 'Remove' && _busyCatalog == c.name,
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
    final installed = _installed.any(
      (c) => c.name.toLowerCase() == a.name.toLowerCase(),
    );
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
            onPressed: (_busy || installed) ? null : () => _downloadCatalog(a),
            label: installed ? 'Installed' : 'Download',
            icon: installed ? LucideIcons.check : LucideIcons.download,
            variant: installed ? ButtonVariant.ghost : ButtonVariant.primary,
            size: ButtonSize.small,
            isLoading: _busyAction == 'Download' && _busyCatalog == a.name,
          ),
        ],
      ),
    );
  }
}

/// Shown when no appliance is connected: says what this page needs in
/// platform-neutral terms and offers the one action that can satisfy it.
class _NotConnected extends StatelessWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const _NotConnected({required this.colors, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    return NightshadeCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 18, color: colors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This page manages the catalogs on a remote appliance, and '
                  'no appliance is connected. It is separate from this '
                  "device's own planetarium catalogs, which live under "
                  'Catalogs.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NightshadeButton(
                label: 'Connect an appliance',
                icon: LucideIcons.globe,
                variant: ButtonVariant.primary,
                size: ButtonSize.small,
                onPressed: router == null
                    ? null
                    : () => router.go('/settings?section=remote-access'),
              ),
              NightshadeButton(
                label: "This device's catalogs",
                icon: LucideIcons.library,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: router == null
                    ? null
                    : () => router.go('/settings?section=catalogs'),
              ),
            ],
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
