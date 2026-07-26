// Notification routing settings panel.
//
// Lives alongside `notification_settings.dart` (the legacy push toggles)
// and is embedded inside that page. Exposes:
//   * Master "Routing enabled" switch
//   * One row per NotificationCategory showing the current transports +
//     an "Edit" pencil that opens the per-category editor dialog.
//   * Test-send buttons for every transport (email, webhook, Pushover,
//     Telegram, Discord, MQTT) with inline success / error display.
//   * Per-transport credential entry forms.
//
// Style mirrors the existing settings widgets (NightshadeColors,
// SettingsSection, SettingRow). We never write to a transport's secret
// fields without the user clicking Save so the obscure text field is a
// no-op for the unchanged case.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';

part 'notification_routing_settings/category_editor_dialog.dart';
part 'notification_routing_settings/transport_controls.dart';
part 'notification_routing_settings/email_transport_section.dart';
part 'notification_routing_settings/webhook_transport_section.dart';
part 'notification_routing_settings/pushover_transport_section.dart';
part 'notification_routing_settings/telegram_transport_section.dart';
part 'notification_routing_settings/discord_transport_section.dart';
part 'notification_routing_settings/mqtt_transport_section.dart';
part 'notification_routing_settings/home_assistant_section.dart';

class NotificationRoutingSettings extends ConsumerWidget {
  final bool isMobile;

  const NotificationRoutingSettings({
    super.key,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final backend = ref.watch(backendProvider);

    if (backend is NetworkBackend) {
      return Column(
        children: [
          const SettingsSection(
            title: 'Notification routing',
            children: [
              SettingRow(
                icon: LucideIcons.server,
                title: 'Configure routing on the Nightshade host',
                subtitle:
                    'Email, webhook, Pushover, Telegram, Discord, and MQTT '
                    'credentials are host-owned. This controller will not '
                    'write a separate local configuration or duplicate the '
                    'host’s sends.',
                trailing: SizedBox.shrink(),
                isLast: true,
              ),
            ],
          ),
          // Home Assistant already has strict remote host API parity, so it
          // remains editable from a controller while the other transports are
          // intentionally host-only.
          _HomeAssistantSection(isMobile: isMobile),
        ],
      );
    }
    final matrixAsync = ref.watch(notificationRoutingMatrixProvider);

    return matrixAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Could not load the notification routing matrix.',
              style: TextStyle(color: colors.error),
            ),
            const SizedBox(height: 6),
            Text(
              e.toString(),
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: NightshadeTypography.fontSize12,
              ),
            ),
            const SizedBox(height: 12),
            NightshadeButton(
              label: 'Retry routing settings',
              icon: LucideIcons.refreshCw,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: () =>
                  ref.invalidate(notificationRoutingMatrixProvider),
            ),
          ],
        ),
      ),
      data: (matrix) => _build(context, ref, matrix),
    );
  }

  Widget _build(
      BuildContext context, WidgetRef ref, NotificationRoutingMatrix matrix) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Routing master switch',
          children: [
            SettingRow(
              icon: LucideIcons.share2,
              title: 'Notification routing enabled',
              subtitle:
                  'When off, no per-category routing fires (legacy push still works)',
              trailing: SettingsSwitch(
                value: matrix.enabled,
                onChanged: (v) {
                  return ref
                      .read(notificationRoutingMatrixProvider.notifier)
                      .setEnabled(v);
                },
              ),
              isLast: true,
            ),
          ],
        ),
        SettingsSection(
          title: 'Per-event routing',
          children: [
            for (var i = 0; i < NotificationCategory.values.length; i++)
              _categoryRow(
                context,
                ref,
                NotificationCategory.values[i],
                matrix,
                isLast: i == NotificationCategory.values.length - 1,
              ),
          ],
        ),
        _TransportsSection(isMobile: isMobile),
      ],
    );
  }

  Widget _categoryRow(
    BuildContext context,
    WidgetRef ref,
    NotificationCategory category,
    NotificationRoutingMatrix matrix, {
    required bool isLast,
  }) {
    final rule = matrix.ruleFor(category);
    final summary = rule.enabled && rule.transports.isNotEmpty
        ? rule.transports.map((t) => t.label).join(' + ')
        : '(disabled)';

    return SettingRow(
      icon: _iconFor(category),
      title: category.label,
      subtitle: '→ $summary',
      trailing: NightshadeButton(
        label: 'Edit',
        variant: ButtonVariant.outline,
        size: ButtonSize.small,
        onPressed: () async {
          await showDialog<void>(
            context: context,
            builder: (_) => _CategoryEditorDialog(
              category: category,
              rule: rule,
              onSave: (updated) async {
                await ref
                    .read(notificationRoutingMatrixProvider.notifier)
                    .setRule(category, updated);
              },
            ),
          );
        },
      ),
      isLast: isLast,
    );
  }

  IconData _iconFor(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.sequenceStarted:
      case NotificationCategory.sequenceResumed:
        return LucideIcons.play;
      case NotificationCategory.sequenceCompleted:
        return LucideIcons.checkCircle;
      case NotificationCategory.sequenceFailed:
        return LucideIcons.alertOctagon;
      case NotificationCategory.sequencePaused:
        return LucideIcons.pause;
      case NotificationCategory.targetStarted:
      case NotificationCategory.targetCompleted:
        return LucideIcons.crosshair;
      case NotificationCategory.meridianFlipPerformed:
        return LucideIcons.rotateCw;
      case NotificationCategory.autofocusCompleted:
      case NotificationCategory.autofocusFailed:
        return LucideIcons.focus;
      case NotificationCategory.frameCaptured:
        return LucideIcons.camera;
      case NotificationCategory.frameRejected:
        return LucideIcons.cameraOff;
      case NotificationCategory.exposureFailed:
        return LucideIcons.alertTriangle;
      case NotificationCategory.recoveryStarted:
      case NotificationCategory.recoveryRecovered:
      case NotificationCategory.recoveryGaveUp:
        return LucideIcons.lifeBuoy;
      case NotificationCategory.guidingLost:
      case NotificationCategory.guidingRecovered:
        return LucideIcons.target;
      case NotificationCategory.weatherUnsafe:
      case NotificationCategory.weatherSafeAgain:
        return LucideIcons.cloudRain;
      case NotificationCategory.cloudArriving:
      case NotificationCategory.cloudOpening:
        return LucideIcons.cloud;
      case NotificationCategory.diskSpaceLow:
        return LucideIcons.hardDrive;
      case NotificationCategory.equipmentDisconnected:
        return LucideIcons.unplug;
      case NotificationCategory.triggerFired:
        return LucideIcons.zap;
      case NotificationCategory.transientDiscovered:
        return LucideIcons.sparkles;
      case NotificationCategory.custom:
        return LucideIcons.bell;
    }
  }
}

// ---------------------------------------------------------------------------
// Per-category editor dialog
// ---------------------------------------------------------------------------
