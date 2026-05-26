import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Live tail of session events with a severity-chip filter.
///
/// Subscribes directly to `backend.eventStream` so we receive the rich
/// core-typed `NightshadeEvent` (which already carries severity, category
/// and a free-form `data` map) rather than the FRB-typed payload-union
/// variant.
class LogTab extends ConsumerStatefulWidget {
  const LogTab({super.key});

  @override
  ConsumerState<LogTab> createState() => _LogTabState();
}

class _LogTabState extends ConsumerState<LogTab> {
  static const _maxEntries = 500;

  final List<NightshadeEvent> _events = [];
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<NightshadeEvent>? _subscription;
  NightshadeBackend? _subscribedBackend;
  final Set<EventSeverity> _enabledSeverities = {
    EventSeverity.info,
    EventSeverity.warning,
    EventSeverity.error,
    EventSeverity.critical,
  };
  bool _autoScroll = true;

  // [Wave 6E log tail] — when the active backend is a NetworkBackend, also
  // tail the server-side LoggingService entries via /api/logs/tail. These
  // appear in a separate ring buffer underneath the existing
  // NightshadeEvent feed because the two shapes don't share severity /
  // category enums; rendering them as plain text rows keeps the wiring
  // independent of W6D's backend-switch event-buffer clearing logic.
  StreamSubscription<LogEntry>? _serverLogSubscription;
  NetworkBackend? _subscribedServerLogBackend;
  final List<LogEntry> _serverLogEntries = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleUserScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _subscription?.cancel();
    _serverLogSubscription?.cancel();
    super.dispose();
  }

  void _handleUserScroll() {
    if (!_scrollController.hasClients) return;
    // ListView.builder with reverse=true: pos=0 means latest visible.
    // We turn auto-scroll back on when the user manually returns to the
    // bottom so the tail keeps following without forcing scrolls.
    final atBottom = _scrollController.position.pixels <= 8;
    if (atBottom != _autoScroll) {
      setState(() => _autoScroll = atBottom);
    }
  }

  void _ensureSubscription(NightshadeBackend backend) {
    if (identical(_subscribedBackend, backend)) return;
    // Wave 6D / P2-5 — flush the in-memory ring buffer whenever the
    // backend identity changes. Without this, switching from FFI to a
    // remote server (or reconnecting to a different host) would leave
    // the operator staring at stale events that have no relationship
    // to the device they are now controlling. We only flush on a
    // *change* — the initial subscription on first build keeps the
    // (already-empty) buffer intact.
    if (_subscribedBackend != null) {
      _events.clear();
    }
    _subscription?.cancel();
    _subscribedBackend = backend;
    _subscription = backend.eventStream.listen((event) {
      if (!mounted) return;
      setState(() {
        _events.add(event);
        if (_events.length > _maxEntries) {
          _events.removeRange(0, _events.length - _maxEntries);
        }
      });
    });
  }

  void _toggleSeverity(EventSeverity s) {
    setState(() {
      if (_enabledSeverities.contains(s)) {
        _enabledSeverities.remove(s);
      } else {
        _enabledSeverities.add(s);
      }
    });
  }

  void _clear() {
    setState(() {
      _events.clear();
      _serverLogEntries.clear();
    });
  }

  // [Wave 6E log tail] — open/close the SSE subscription to /api/logs/tail
  // on every backend change. The FFI backend has no remote logs (the local
  // LoggingService is already in-process), so we only subscribe when the
  // active backend is a [NetworkBackend].
  void _ensureServerLogSubscription(NightshadeBackend backend) {
    final networkBackend = backend is NetworkBackend ? backend : null;
    if (identical(_subscribedServerLogBackend, networkBackend)) return;
    _serverLogSubscription?.cancel();
    _serverLogSubscription = null;
    _subscribedServerLogBackend = networkBackend;
    if (networkBackend != null) {
      _serverLogEntries.clear();
      _serverLogSubscription = networkBackend.tailServerLogs().listen(
        (entry) {
          if (!mounted) return;
          setState(() {
            _serverLogEntries.add(entry);
            if (_serverLogEntries.length > _maxEntries) {
              _serverLogEntries.removeRange(
                0,
                _serverLogEntries.length - _maxEntries,
              );
            }
          });
        },
        onError: (Object _) {
          // tailServerLogs() auto-reconnects with backoff, so an error here
          // is informational. Surface the count via UI by leaving the tail
          // list intact; the next successful event resumes the stream.
        },
      );
    } else {
      _serverLogEntries.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch backend so we re-subscribe if the user disconnects/reconnects
    // mid-session (the stream object changes when the backend type does).
    final backend = ref.watch(backendProvider);
    _ensureSubscription(backend);
    _ensureServerLogSubscription(backend);

    final visible = _events
        .where((e) => _enabledSeverities.contains(e.severity))
        .toList(growable: false);
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          color: colors.surface,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final sev in EventSeverity.values)
                          _SeverityChip(
                            severity: sev,
                            enabled: _enabledSeverities.contains(sev),
                            count:
                                _events.where((e) => e.severity == sev).length,
                            onTap: () => _toggleSeverity(sev),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear log',
                    icon: const Icon(LucideIcons.trash2, size: 20),
                    onPressed: _events.isEmpty ? null : _clear,
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(height: 1, color: colors.border),
        // [Wave 6E log tail] — remote-server log entries (only when the
        // backend is a NetworkBackend). Rendered as a fixed-height panel
        // above the main event list so it doesn't disturb the existing
        // reverse=true scrolling on _events.
        if (_subscribedServerLogBackend != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: colors.surfaceAlt,
            child: Row(
              children: [
                Icon(LucideIcons.server, size: 14, color: colors.textMuted),
                const SizedBox(width: 6),
                Text(
                  'Server logs',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_serverLogEntries.length}',
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 140,
            child: _serverLogEntries.isEmpty
                ? Center(
                    child: Text(
                      'Waiting for server log entries…',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: _serverLogEntries.length,
                    itemBuilder: (context, i) {
                      final entry = _serverLogEntries[
                          _serverLogEntries.length - 1 - i];
                      return _ServerLogEntryTile(entry: entry, colors: colors);
                    },
                  ),
          ),
          Container(height: 1, color: colors.border),
        ],
        Expanded(
          child: visible.isEmpty
              ? EmptyState(
                  icon: LucideIcons.scrollText,
                  title:
                      _events.isEmpty ? 'Waiting for events' : 'Filtered out',
                  body: _events.isEmpty
                      ? 'New events from devices, imaging, and the sequencer '
                          'will appear here.'
                      : 'No events match the current severity filter.',
                )
              : ListView.builder(
                  controller: _scrollController,
                  // Reverse so new events appear at the bottom of the
                  // viewport but the underlying list keeps appending —
                  // we treat index 0 as the newest event.
                  reverse: true,
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final event = visible[visible.length - 1 - i];
                    return _EventTile(event: event);
                  },
                ),
        ),
      ],
    );
  }
}

/// [Wave 6E log tail] — Compact tile for a remote server log entry. Kept
/// separate from `_EventTile` because LogEntry has its own enum
/// (LogLevel) and there's no need to map between the two schemas.
class _ServerLogEntryTile extends StatelessWidget {
  final LogEntry entry;
  final NightshadeColors colors;
  const _ServerLogEntryTile({required this.entry, required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = _logLevelColor(entry.level, colors);
    final ts = entry.timestamp.toLocal();
    final timeStr =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: c, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timeStr,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 6),
          Text(
            entry.level.name.toUpperCase(),
            style: TextStyle(
              color: c,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              entry.source != null
                  ? '[${entry.source}] ${entry.message}'
                  : entry.message,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _logLevelColor(LogLevel level, NightshadeColors colors) {
    switch (level) {
      case LogLevel.debug:
        return colors.textMuted;
      case LogLevel.info:
        return colors.info;
      case LogLevel.warning:
        return colors.warning;
      case LogLevel.error:
        return colors.error;
      case LogLevel.critical:
        return colors.error;
    }
  }
}

class _SeverityChip extends StatelessWidget {
  final EventSeverity severity;
  final bool enabled;
  final int count;
  final VoidCallback onTap;

  const _SeverityChip({
    required this.severity,
    required this.enabled,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final c = _severityColor(severity, colors);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
      child: Container(
        // 44 pt tap height — important on phones where chips usually
        // collapse to 28 dp and end up impossible to hit reliably.
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: enabled
            ? NightshadeDecorations.selectedSurface(
                c,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusFull),
                fillAlpha: 0.2,
              )
            : BoxDecoration(
                color: colors.surfaceAlt,
                border: Border.all(color: colors.border),
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusFull),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_severityIcon(severity), size: 14, color: c),
            const SizedBox(width: 6),
            Text(
              _severityLabel(severity),
              style: TextStyle(
                color: enabled ? c : colors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  color: enabled ? c : colors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final NightshadeEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final c = _severityColor(event.severity, colors);
    final ts = DateTime.fromMillisecondsSinceEpoch(event.timestamp);
    final timeStr =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
    final message = _eventMessage(event);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: c, width: 3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                timeStr,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _categoryLabel(event.category),
                  style: TextStyle(
                    color: c,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  event.eventType,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(
              message,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color _severityColor(EventSeverity s, NightshadeColors colors) {
  return switch (s) {
    EventSeverity.info => colors.info,
    EventSeverity.warning => colors.warning,
    EventSeverity.error => colors.error,
    EventSeverity.critical => colors.error,
  };
}

IconData _severityIcon(EventSeverity s) {
  return switch (s) {
    EventSeverity.info => LucideIcons.info,
    EventSeverity.warning => LucideIcons.alertTriangle,
    EventSeverity.error => LucideIcons.alertCircle,
    EventSeverity.critical => LucideIcons.alertOctagon,
  };
}

String _severityLabel(EventSeverity s) {
  return switch (s) {
    EventSeverity.info => 'Info',
    EventSeverity.warning => 'Warning',
    EventSeverity.error => 'Error',
    EventSeverity.critical => 'Critical',
  };
}

String _categoryLabel(EventCategory c) {
  return switch (c) {
    EventCategory.equipment => 'DEVICE',
    EventCategory.imaging => 'IMAGE',
    EventCategory.guiding => 'GUIDE',
    EventCategory.sequencer => 'SEQ',
    EventCategory.safety => 'SAFETY',
    EventCategory.system => 'SYS',
    EventCategory.polarAlignment => 'PA',
    // Wave 3 / P1-2 P1-3: long-running job lifecycle events.
    EventCategory.job => 'JOB',
    // Wave 3 / P1-5: session-ownership lifecycle events.
    EventCategory.session => 'SESSION',
    // Wave 4C: catalog (sequence library, target catalogs, etc.) sync events.
    EventCategory.catalog => 'CATALOG',
  };
}

String? _eventMessage(NightshadeEvent event) {
  final data = event.data;
  for (final key in const ['message', 'error', 'reason', 'detail']) {
    final v = data[key];
    if (v is String && v.isNotEmpty) return v;
  }
  return null;
}
