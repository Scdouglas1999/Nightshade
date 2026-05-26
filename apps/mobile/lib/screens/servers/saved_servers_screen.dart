// Wave 7E — Saved servers screen.
//
// Surfaces every server the operator has paired with so they can roam
// between rigs without re-running discovery / re-pairing. Composes
// SavedServersService for persistence and the existing BackendNotifier
// for live connection switching.
//
// UX contract (per brief):
//   * Each row: display name, last-connected relative time, dot
//     indicator showing last-known reachability.
//   * Tap a row → open that server (BackendNotifier.connect + persist
//     into EnhancedNightshadeDiscovery so the auto-reconnect path also
//     updates).
//   * Long-press → rename / edit notes / remove.
//   * FAB → kicks off the existing pairing flow (passes the new host
//     through the same SavedServersService.upsert path so the row is
//     visible immediately).
//   * Pull-to-refresh → pings each saved host's /api/info and refreshes
//     the reachability dots.
//
// We do *not* duplicate the QR / mDNS discovery UI from main.dart's
// connection screen; "Add a server" routes back through the existing
// pairing helper exposed to the screen via the [onAddServer] callback
// so there's one canonical pairing path.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../services/saved_servers_service.dart';

/// Async snapshot of the saved-server list — drives the screen state.
final _savedServersListProvider =
    FutureProvider.autoDispose<List<SavedServer>>((ref) async {
  final service = ref.watch(savedServersServiceProvider);
  return service.loadAll();
});

/// Per-entry reachability cache keyed by [SavedServer.id]. We populate
/// it lazily on screen first build and on pull-to-refresh; the screen
/// doesn't auto-ping on a timer because every saved row would spawn an
/// HTTP request as soon as the screen opens.
class _ReachabilityNotifier extends StateNotifier<Map<String, bool?>> {
  _ReachabilityNotifier() : super(const {});

  void setStatus(String id, bool? reachable) {
    state = {...state, id: reachable};
  }

  void clearAll() {
    state = const {};
  }
}

final _reachabilityProvider =
    StateNotifierProvider.autoDispose<_ReachabilityNotifier, Map<String, bool?>>(
  (ref) => _ReachabilityNotifier(),
);

/// Saved-server list screen.
///
/// [onAddServer] launches the existing pairing flow — provided by the
/// caller (`main.dart`'s connection shell) so we don't fork the QR /
/// manual-entry plumbing.
///
/// [onServerSelected] fires AFTER the BackendNotifier.connect call
/// resolves for a saved entry. Most callers pop back to the dashboard
/// here; tests pass a no-op.
class SavedServersScreen extends ConsumerStatefulWidget {
  /// Async callback that runs the existing pairing flow and returns
  /// the freshly-paired record (or `null` if the user cancelled).
  final Future<SavedServer?> Function(BuildContext context)? onAddServer;

  /// Called after a saved entry successfully reconnects. `null` lets
  /// the screen close via the default Navigator.pop.
  final void Function(BuildContext context, SavedServer server)?
      onServerSelected;

  const SavedServersScreen({
    super.key,
    this.onAddServer,
    this.onServerSelected,
  });

  @override
  ConsumerState<SavedServersScreen> createState() =>
      _SavedServersScreenState();
}

class _SavedServersScreenState extends ConsumerState<SavedServersScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final asyncList = ref.watch(_savedServersListProvider);
    final reachability = ref.watch(_reachabilityProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Text(
          'Saved servers',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
      ),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Failed to load saved servers: $e',
              style: TextStyle(color: colors.error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (servers) {
          if (servers.isEmpty) {
            return _EmptyState(colors: colors);
          }
          return RefreshIndicator(
            onRefresh: () => _refreshReachability(servers),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: servers.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: colors.border),
              itemBuilder: (context, index) {
                final server = servers[index];
                final reach = reachability[server.id];
                return _SavedServerRow(
                  server: server,
                  reachable: reach,
                  busy: _busy,
                  colors: colors,
                  onTap: () => _activateServer(server),
                  onLongPress: () => _showRowMenu(server),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Add server'),
        onPressed: _busy ? null : _handleAddServer,
      ),
    );
  }

  Future<void> _refreshReachability(List<SavedServer> servers) async {
    // Concurrent pings so the indicator refresh feels snappy. The
    // remote-protocol package's testServerConnection has a built-in 5s
    // timeout; we cap the whole batch at 6s so the spinner doesn't
    // hang on an unreachable host.
    final notifier = ref.read(_reachabilityProvider.notifier);
    final futures = <Future<void>>[];
    for (final s in servers) {
      futures.add(_pingOne(s, notifier));
    }
    await Future.wait(futures).timeout(
      const Duration(seconds: 6),
      onTimeout: () {
        // Outstanding pings keep running in the background; the
        // notifier will update each one as it lands. Don't propagate
        // the timeout — the user's pull-to-refresh is already done.
        return <void>[];
      },
    );
  }

  Future<void> _pingOne(
      SavedServer s, _ReachabilityNotifier notifier) async {
    try {
      final token = await ref
          .read(savedServersServiceProvider)
          .tokenFor(s.id);
      final ok = await EnhancedNightshadeDiscovery.testServerConnection(
        s.host,
        s.port,
        authToken: token,
      );
      if (!mounted) return;
      notifier.setStatus(s.id, ok);
    } catch (_) {
      if (!mounted) return;
      notifier.setStatus(s.id, false);
    }
  }

  Future<void> _activateServer(SavedServer server) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(savedServersServiceProvider);
      final token = await service.tokenFor(server.id);
      // Sanity-check reachability before swapping backends — a fail-
      // fast here keeps the dashboard from booting into a hung WS.
      final ok = await EnhancedNightshadeDiscovery.testServerConnection(
        server.host,
        server.port,
        authToken: token,
      );
      if (!ok) {
        if (!mounted) return;
        _showSnack('Could not reach ${server.displayName}',
            isError: true);
        ref
            .read(_reachabilityProvider.notifier)
            .setStatus(server.id, false);
        return;
      }
      final viewerId = (token != null && token.isNotEmpty)
          ? computeServerFingerprint(token)
          : server.id;
      await ref.read(backendProvider.notifier).connect(
            server.host,
            server.port,
            authToken: token,
            collaborationViewerId: viewerId,
            collaborationDeviceName: server.id,
            collaborationDisplayName: server.displayName,
          );
      // Mirror the active server into the legacy single-slot record so
      // auto-reconnect on cold start still works. Also re-stamp our
      // own lastConnectedAt + reachability cache.
      final discovered = DiscoveredServer(
        name: server.displayName,
        host: server.host,
        webPort: server.port,
        signalingPort: 45678,
        version: '2.0.0',
        mode: 'headless',
        authToken: token,
        authRequired: token != null,
        pairingSupported: true,
        fingerprint: server.pinnedFingerprint,
      );
      await EnhancedNightshadeDiscovery.saveLastServer(discovered);
      await service.touchLastConnected(server.id);
      ref.read(_reachabilityProvider.notifier).setStatus(server.id, true);
      ref.invalidate(_savedServersListProvider);
      if (!mounted) return;
      if (widget.onServerSelected != null) {
        widget.onServerSelected!(context, server);
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to open ${server.displayName}: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleAddServer() async {
    if (widget.onAddServer == null) {
      _showSnack(
        'Adding new servers from this screen is not enabled in this build.',
        isError: true,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final added = await widget.onAddServer!(context);
      if (!mounted) return;
      if (added != null) {
        ref.invalidate(_savedServersListProvider);
        _showSnack('Added ${added.displayName}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRowMenu(SavedServer server) async {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final action = await showModalBottomSheet<_RowMenuAction>(
      context: context,
      backgroundColor: colors.surface,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(LucideIcons.edit, color: colors.textPrimary),
                title: Text('Rename',
                    style: TextStyle(color: colors.textPrimary)),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_RowMenuAction.rename),
              ),
              ListTile(
                leading:
                    Icon(LucideIcons.fileText, color: colors.textPrimary),
                title: Text('Edit notes',
                    style: TextStyle(color: colors.textPrimary)),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_RowMenuAction.notes),
              ),
              ListTile(
                leading: Icon(LucideIcons.trash, color: colors.error),
                title: Text('Remove',
                    style: TextStyle(color: colors.error)),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_RowMenuAction.remove),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _RowMenuAction.rename:
        await _renameServer(server);
        break;
      case _RowMenuAction.notes:
        await _editNotes(server);
        break;
      case _RowMenuAction.remove:
        await _confirmAndRemove(server);
        break;
    }
  }

  Future<void> _renameServer(SavedServer server) async {
    final controller = TextEditingController(text: server.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename server'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (newName == null || newName.isEmpty || newName == server.displayName) {
      return;
    }
    await ref
        .read(savedServersServiceProvider)
        .rename(server.id, newName);
    ref.invalidate(_savedServersListProvider);
  }

  Future<void> _editNotes(SavedServer server) async {
    final controller = TextEditingController(text: server.notes);
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Notes'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            maxLength: 280,
            decoration: const InputDecoration(
              labelText: 'Notes',
              helperText: 'Up to 280 characters',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (updated == null) return;
    await ref
        .read(savedServersServiceProvider)
        .setNotes(server.id, updated.trim());
    ref.invalidate(_savedServersListProvider);
  }

  Future<void> _confirmAndRemove(SavedServer server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Remove ${server.displayName}?'),
          content: const Text(
            'The bearer token and stored fingerprint will be wiped. '
            'Re-pair if you want to use this server again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await ref.read(savedServersServiceProvider).removeById(server.id);
    ref.invalidate(_savedServersListProvider);
    ref.read(_reachabilityProvider.notifier).setStatus(server.id, null);
  }

  void _showSnack(String message, {bool isError = false}) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? colors.error : null,
      ),
    );
  }
}

enum _RowMenuAction { rename, notes, remove }

class _EmptyState extends StatelessWidget {
  final NightshadeColors colors;
  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.server, size: 36, color: colors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'No saved servers yet',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pair with a Nightshade host using the "Add server" button '
              'to start the roaming list.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedServerRow extends StatelessWidget {
  final SavedServer server;
  final bool? reachable;
  final bool busy;
  final NightshadeColors colors;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SavedServerRow({
    required this.server,
    required this.reachable,
    required this.busy,
    required this.colors,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = reachable == null
        ? colors.textSecondary.withValues(alpha: 0.4)
        : (reachable! ? colors.success : colors.error);
    final dotLabel = reachable == null
        ? 'Reachability unknown'
        : (reachable! ? 'Reachable' : 'Unreachable');
    final secondary = _secondaryLine();
    return InkWell(
      onTap: busy ? null : onTap,
      onLongPress: busy ? null : onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Semantics(
              label: dotLabel,
              child: Container(
                width: 12,
                height: 12,
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.displayName,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    secondary,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (server.notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      server.notes,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(LucideIcons.chevronRight,
                size: 18, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }

  String _secondaryLine() {
    final hostPort = '${server.host}:${server.port}';
    final last = server.lastConnectedAt;
    if (last == null) return '$hostPort · never connected';
    return '$hostPort · ${_formatRelative(last)}';
  }

  static String _formatRelative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.isNegative) return 'just now';
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }
}
