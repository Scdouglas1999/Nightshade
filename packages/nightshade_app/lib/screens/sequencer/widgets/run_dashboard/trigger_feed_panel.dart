import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'run_dashboard_format.dart';
import 'run_dashboard_providers.dart';

/// Last-N executor / trigger events, color-coded by severity.
///
/// Genuinely new: there is no existing "executor event feed" widget. The
/// closest sibling is the global `uiNotificationProvider` toast queue,
/// but that one shows transient toasts and drops them. The dashboard
/// needs persistent visibility of recent triggers / pauses / safety
/// events so the operator can glance and see what's happened.
class RunDashboardTriggerFeed extends ConsumerWidget {
  /// Number of events to keep on screen.
  final int limit;

  const RunDashboardTriggerFeed({super.key, this.limit = 5});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final events = ref.watch(runDashboardRecentEventsProvider(limit));

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.bell, size: 14, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'RECENT EVENTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: NightshadeTokens.spaceMd),
              child: Text(
                'No events yet.',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            )
          else
            for (var i = 0; i < events.length; i++) ...[
              _EventRow(colors: colors, event: events[i]),
              if (i < events.length - 1)
                Divider(
                  height: NightshadeTokens.spaceSm * 2,
                  color: colors.border,
                ),
            ],
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final NightshadeColors colors;
  final RunDashboardEvent event;

  const _EventRow({required this.colors, required this.event});

  Color _severityColor() {
    switch (event.severity) {
      case RunDashboardEventSeverity.info:
        return colors.info;
      case RunDashboardEventSeverity.warning:
        return colors.warning;
      case RunDashboardEventSeverity.error:
        return colors.error;
      case RunDashboardEventSeverity.critical:
        return colors.error;
    }
  }

  IconData _severityIcon() {
    switch (event.severity) {
      case RunDashboardEventSeverity.info:
        return LucideIcons.info;
      case RunDashboardEventSeverity.warning:
        return LucideIcons.alertTriangle;
      case RunDashboardEventSeverity.error:
        return LucideIcons.alertOctagon;
      case RunDashboardEventSeverity.critical:
        return LucideIcons.flame;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _severityColor();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(_severityIcon(), size: 13, color: color),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    event.category,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      event.title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    formatTimeOfDay(event.time),
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              if (event.message.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  event.message,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
