import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import 'settings_widgets.dart';

/// Remote appliance update management (OTA).
///
/// Drives the headless server's `/api/system/update/*` surface so a tablet /
/// desktop operator can check for, stage, apply, and roll back appliance
/// updates without SSHing into the Pi. Only meaningful on a remote
/// (NetworkBackend) session — the local desktop updates itself through its own
/// installer — so the page degrades to an explanatory note off-network.
class UpdateSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const UpdateSettings({super.key, this.isMobile = false});

  @override
  ConsumerState<UpdateSettings> createState() => _UpdateSettingsState();
}

class _UpdateSettingsState extends ConsumerState<UpdateSettings> {
  RemoteVersionInfo? _version;
  RemoteUpdateStatus? _status;
  bool _loading = false;
  bool _busy = false;
  String? _loadError;
  Timer? _poll;

  NetworkBackend? get _backend {
    final b = ref.read(backendProvider);
    return b is NetworkBackend ? b : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  bool _isInProgress(String? state) =>
      state == 'checking' || state == 'downloading' || state == 'applying';

  Future<void> _refresh() async {
    final backend = _backend;
    if (backend == null) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final version = await backend.getSystemVersion();
      final status = await backend.getUpdateStatus();
      if (!mounted) return;
      setState(() {
        _version = version;
        _status = status;
        _loading = false;
      });
      // Keep polling status while an operation is mid-flight so progress
      // updates without the user manually refreshing.
      if (_isInProgress(status.state)) {
        _poll ??= Timer.periodic(
          const Duration(seconds: 2),
          (_) => _refreshStatusOnly(),
        );
      } else {
        _poll?.cancel();
        _poll = null;
      }
    } catch (e) {
      if (!mounted) return;
      // The `/api/system/update/*` + version routes are only registered when
      // the appliance has an update server configured; otherwise they 404.
      // Surface that as a clear "not enabled" note rather than a raw error.
      final msg = '$e';
      final notEnabled = msg.contains('404') ||
          msg.toLowerCase().contains('route not found') ||
          msg.toLowerCase().contains('not found');
      setState(() {
        _loading = false;
        _loadError = notEnabled
            ? 'Over-the-air updates aren\'t enabled on this appliance. Set '
                'NIGHTSHADE_UPDATE_SERVER on the rig (and restart it) to manage '
                'updates from here.'
            : msg;
      });
    }
  }

  Future<void> _refreshStatusOnly() async {
    final backend = _backend;
    if (backend == null) return;
    try {
      final status = await backend.getUpdateStatus();
      if (!mounted) return;
      setState(() => _status = status);
      if (!_isInProgress(status.state)) {
        _poll?.cancel();
        _poll = null;
      }
    } catch (_) {
      // transient — keep the last snapshot
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

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final backend = _backend;

    return SettingsPage(
      title: 'Appliance Updates',
      description: 'Check for, stage, and apply updates to the connected rig',
      isMobile: widget.isMobile,
      hideHeader: widget.isMobile,
      children: [
        if (backend == null)
          _InfoCard(
            colors: colors,
            icon: LucideIcons.info,
            text: 'Connect to a remote appliance to manage its updates. The '
                'local desktop app updates itself through its own installer.',
          )
        else ...[
          _buildVersionCard(colors),
          const SizedBox(height: 12),
          _buildStatusCard(colors),
          const SizedBox(height: 12),
          _buildActions(colors),
          if (_loadError != null) ...[
            const SizedBox(height: 12),
            _InfoCard(
              colors: colors,
              icon: LucideIcons.alertTriangle,
              text: 'Could not read update state: $_loadError',
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildVersionCard(NightshadeColors colors) {
    final v = _version;
    return NightshadeCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current Build',
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize12)),
          const SizedBox(height: 6),
          Text(
            v == null
                ? (_loading ? 'Loading…' : '—')
                : '${v.currentVersion} (build ${v.buildNumber})',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: NightshadeTypography.fontSize18,
                fontWeight: FontWeight.w700),
          ),
          if (v != null) ...[
            const SizedBox(height: 4),
            Text('Channel: ${v.channel} · ${v.platform}',
                style: TextStyle(
                    color: colors.textMuted,
                    fontSize: NightshadeTypography.fontSize12)),
            if (v.updateServerUrl != null && v.updateServerUrl!.isNotEmpty)
              Text('Update server: ${v.updateServerUrl}',
                  style: TextStyle(
                      color: colors.textMuted,
                      fontSize: NightshadeTypography.fontSize12))
            else
              Text('No update server configured (set NIGHTSHADE_UPDATE_SERVER)',
                  style: TextStyle(
                      color: colors.warning,
                      fontSize: NightshadeTypography.fontSize12)),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard(NightshadeColors colors) {
    final s = _status;
    final pct = s?.progressPct;
    return NightshadeCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Update Status',
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize12)),
          const SizedBox(height: 6),
          Text(s?.state ?? (_loading ? 'Loading…' : 'idle'),
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: NightshadeTypography.fontSize16,
                  fontWeight: FontWeight.w600)),
          if (s?.stagedVersion != null) ...[
            const SizedBox(height: 4),
            Text('Staged: ${s!.stagedVersion}',
                style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize13)),
          ],
          if (pct != null && _isInProgress(s?.state)) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: colors.border,
                color: colors.primary,
              ),
            ),
          ],
          if (s?.message != null && s!.message!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(s.message!,
                style: TextStyle(
                    color: colors.textMuted,
                    fontSize: NightshadeTypography.fontSize12)),
          ],
          if (s?.lastError != null && s!.lastError!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Last error: ${s.lastError}',
                style: TextStyle(
                    color: colors.error,
                    fontSize: NightshadeTypography.fontSize12)),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(NightshadeColors colors) {
    final state = _status?.state;
    final inProgress = _isInProgress(state);
    final hasStaged =
        state == 'staged' || (_status?.stagedVersion?.isNotEmpty ?? false);
    final canAct = !_busy && !inProgress;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        NightshadeButton(
          onPressed: canAct ? () => _run('Check', _doCheck) : null,
          label: 'Check for Updates',
          icon: LucideIcons.refreshCw,
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: canAct ? () => _run('Download', _doDownload) : null,
          label: 'Download',
          icon: LucideIcons.download,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: canAct && hasStaged ? () => _run('Apply', _doApply) : null,
          label: 'Apply Staged',
          icon: LucideIcons.checkCircle,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
        ),
        NightshadeButton(
          onPressed: canAct ? () => _run('Rollback', _doRollback) : null,
          label: 'Rollback',
          icon: LucideIcons.undo2,
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
        if (inProgress)
          NightshadeButton(
            onPressed: _busy ? null : () => _run('Abort', _doAbort),
            label: 'Abort',
            icon: LucideIcons.x,
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
        NightshadeButton(
          onPressed: _loading ? null : _refresh,
          label: 'Refresh',
          icon: LucideIcons.rotateCw,
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
      ],
    );
  }

  Future<void> _doCheck() async => _backend?.checkForUpdate();
  Future<void> _doDownload() async => _backend?.downloadUpdate();
  Future<void> _doApply() async => _backend?.applyUpdate();
  Future<void> _doRollback() async => _backend?.rollbackUpdate();
  Future<void> _doAbort() async => _backend?.abortUpdate();
}

class _InfoCard extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String text;

  const _InfoCard({
    required this.colors,
    required this.icon,
    required this.text,
  });

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
