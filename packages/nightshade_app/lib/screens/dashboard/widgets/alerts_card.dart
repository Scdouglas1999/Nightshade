import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../widgets/operation_status_bar.dart';
import 'glass_card.dart';

class AlertsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const AlertsCard({super.key, required this.colors});

  NightshadeAlertSeverity _mapSeverity(UiNotificationLevel level) {
    return switch (level) {
      UiNotificationLevel.info => NightshadeAlertSeverity.info,
      UiNotificationLevel.success => NightshadeAlertSeverity.success,
      UiNotificationLevel.warning => NightshadeAlertSeverity.warning,
      UiNotificationLevel.error => NightshadeAlertSeverity.error,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(uiNotificationProvider);
    final hasOperation = ref.watch(hasActiveOperationProvider);
    final recent = notifications.reversed.take(2).toList(); // Show fewer in compact

    return DashboardGlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.bell,
                  size: 16,
                  color: colors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Alerts',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (notifications.isNotEmpty)
                NightshadeButton(
                  onPressed: () => ref
                      .read(uiNotificationProvider.notifier)
                      .clearAll(),
                  label: 'Clear',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasOperation) ...[
            const OperationStatusBar(),
            const SizedBox(height: 8),
          ],
          if (recent.isEmpty && !hasOperation)
            Text(
              'No active alerts.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            )
          else
            Column(
              children: recent
                  .map(
                    (notification) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: NightshadeAlert(
                        message: notification.message,
                        title: notification.title,
                        severity: _mapSeverity(notification.level),
                        compact: true,
                        onDismiss: () => ref
                            .read(uiNotificationProvider.notifier)
                            .dismiss(notification.id),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}
