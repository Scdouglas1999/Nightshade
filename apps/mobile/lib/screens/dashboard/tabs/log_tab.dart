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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleUserScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _subscription?.cancel();
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
    setState(_events.clear);
  }

  @override
  Widget build(BuildContext context) {
    // Watch backend so we re-subscribe if the user disconnects/reconnects
    // mid-session (the stream object changes when the backend type does).
    final backend = ref.watch(backendProvider);
    _ensureSubscription(backend);

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
                            count: _events
                                .where((e) => e.severity == sev)
                                .length,
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
        Expanded(
          child: visible.isEmpty
              ? EmptyState(
                  icon: LucideIcons.scrollText,
                  title: _events.isEmpty ? 'Waiting for events' : 'Filtered out',
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
      borderRadius: BorderRadius.circular(20),
      child: Container(
        // 44 pt tap height — important on phones where chips usually
        // collapse to 28 dp and end up impossible to hit reliably.
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: enabled ? c.withValues(alpha: 0.2) : colors.surfaceAlt,
          border: Border.all(
            color: enabled ? c : colors.border,
          ),
          borderRadius: BorderRadius.circular(20),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
