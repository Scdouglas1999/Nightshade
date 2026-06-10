import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'notification_routing_settings.dart';
import 'settings_widgets.dart';

class NotificationSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const NotificationSettings({super.key, this.isMobile = false});

  @override
  ConsumerState<NotificationSettings> createState() =>
      _NotificationSettingsState();
}

class _NotificationSettingsState extends ConsumerState<NotificationSettings> {
  final _discordController = TextEditingController();
  final _pushoverKeyController = TextEditingController();
  final _pushoverUserController = TextEditingController();
  bool _initialized = false;
  bool _testingDiscord = false;
  bool _testingPushover = false;
  bool _testingPushToMobile = false;

  @override
  void dispose() {
    _discordController.dispose();
    _pushoverKeyController.dispose();
    _pushoverUserController.dispose();
    super.dispose();
  }

  Future<void> _testDiscord() async {
    if (_discordController.text.isEmpty) {
      context.showWarningSnackBar('Please enter a Discord webhook URL');
      return;
    }

    setState(() => _testingDiscord = true);
    try {
      final notificationService = ref.read(notificationServiceProvider);
      final success =
          await notificationService.testDiscordWebhook(_discordController.text);
      if (mounted) {
        if (success) {
          context.showSuccessSnackBar(
              'Discord test notification sent successfully!');
        } else {
          context.showErrorSnackBar(
              'Failed to send Discord notification. Check your webhook URL.');
        }
      }
    } finally {
      if (mounted) setState(() => _testingDiscord = false);
    }
  }

  Future<void> _testPushover() async {
    if (_pushoverKeyController.text.isEmpty ||
        _pushoverUserController.text.isEmpty) {
      context.showWarningSnackBar('Please enter both API key and User key');
      return;
    }

    setState(() => _testingPushover = true);
    try {
      final notificationService = ref.read(notificationServiceProvider);
      final success = await notificationService.testPushover(
        _pushoverKeyController.text,
        _pushoverUserController.text,
      );
      if (mounted) {
        if (success) {
          context.showSuccessSnackBar(
              'Pushover test notification sent successfully!');
        } else {
          context.showErrorSnackBar(
              'Failed to send Pushover notification. Check your API and User keys.');
        }
      }
    } finally {
      if (mounted) setState(() => _testingPushover = false);
    }
  }

  void _initControllers(AppSettingsState settings) {
    if (!_initialized) {
      _discordController.text = settings.discordWebhook;
      _pushoverKeyController.text = settings.pushoverKey;
      _pushoverUserController.text = settings.pushoverUser;
      _initialized = true;
    }
  }

  void _testPushToMobile() {
    setState(() => _testingPushToMobile = true);
    try {
      final pushService = ref.read(pushNotificationServiceProvider);
      pushService.sendTestNotification();
      if (mounted) {
        context.showSuccessSnackBar(
            'Test notification sent to connected mobile devices');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to send test notification: $e');
      }
    } finally {
      if (mounted) setState(() => _testingPushToMobile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final pushConfigAsync = ref.watch(pushNotificationConfigProvider);

    return settingsAsync.when(
      loading: () => SettingsLoadingState(
        isMobile: widget.isMobile,
      ),
      error: (error, stack) => SettingsErrorState(
        isMobile: widget.isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) {
        _initControllers(settings);
        final pushConfig =
            pushConfigAsync.valueOrNull ?? const PushNotificationConfig();

        return SettingsPage(
          key: SettingsTutorialKeys.notifications,
          title: 'Notifications',
          description: 'Configure alerts and notifications',
          children: [
            SettingsSection(
              title: 'General',
              children: [
                SettingRow(
                  icon: LucideIcons.bell,
                  title: 'Enable notifications',
                  subtitle: 'Send notifications for important events',
                  trailing: SettingsSwitch(
                    value: settings.notificationsEnabled,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setNotificationsEnabled(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.volume2,
                  title: 'Sound alerts',
                  subtitle: 'Play sounds for notifications',
                  trailing: SettingsSwitch(
                    value: settings.soundEnabled,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setSoundEnabled(value);
                    },
                  ),
                  isLast: true,
                ),
              ],
            ),
            SettingsSection(
              title: 'Notification Events',
              children: [
                SettingRow(
                  icon: LucideIcons.checkCircle,
                  title: 'Sequence complete',
                  subtitle: 'Notify when sequence finishes',
                  trailing: SettingsSwitch(
                    value: settings.notifyOnSequenceComplete,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setNotifyOnSequenceComplete(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.alertCircle,
                  title: 'Errors',
                  subtitle: 'Notify on errors and failures',
                  trailing: SettingsSwitch(
                    value: settings.notifyOnError,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setNotifyOnError(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.rotateCw,
                  title: 'Meridian flip',
                  subtitle: 'Notify when meridian flip occurs',
                  trailing: SettingsSwitch(
                    value: settings.notifyOnMeridianFlip,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setNotifyOnMeridianFlip(value);
                    },
                  ),
                  isLast: true,
                ),
              ],
            ),
            // Critical-event escalation: audible alert + cross-platform
            // push so the user walking away from the laptop / out to the
            // scope still gets a hard, attention-grabbing alert on a fail.
            SettingsSection(
              title: 'Critical events (unattended imaging)',
              children: [
                SettingRow(
                  icon: LucideIcons.bellRing,
                  title: 'Audible alert on critical events',
                  subtitle: 'Play the system bell when a critical error fires',
                  trailing: SettingsSwitch(
                    value: settings.audibleAlertsOnCritical,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setAudibleAlertsOnCritical(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.volume2,
                  title: 'Alert sound',
                  subtitle: 'Which sound to play when critical events fire',
                  trailing: SettingsDropdown(
                    value: settings.criticalAlertSound,
                    items: const ['systemBell', 'none'],
                    itemLabels: const ['System bell', 'None (silent)'],
                    onChanged: (value) {
                      if (value == null) return;
                      ref
                          .read(appSettingsProvider.notifier)
                          .setCriticalAlertSound(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.smartphone,
                  title: 'Push critical alerts to mobile',
                  subtitle:
                      'Forward critical events to paired phones (separate from per-event push toggles below)',
                  trailing: SettingsSwitch(
                    value: settings.pushCriticalAlerts,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setPushCriticalAlerts(value);
                    },
                  ),
                  isLast: true,
                ),
              ],
            ),
            SettingsSection(
              title: 'Push to Mobile',
              children: [
                SettingRow(
                  icon: LucideIcons.smartphone,
                  title: 'Enable push to mobile',
                  subtitle: 'Send alerts to connected mobile devices',
                  trailing: SettingsSwitch(
                    value: pushConfig.enabled,
                    onChanged: (value) {
                      ref
                          .read(pushNotificationConfigProvider.notifier)
                          .setEnabled(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.checkCircle,
                  title: 'Sequence completed',
                  subtitle: 'Push when sequence finishes',
                  trailing: SettingsSwitch(
                    value: pushConfig.notifySequenceCompleted &&
                        pushConfig.enabled,
                    onChanged: (value) {
                      if (!pushConfig.enabled) return;
                      ref
                          .read(pushNotificationConfigProvider.notifier)
                          .setNotifySequenceCompleted(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.alertTriangle,
                  title: 'Sequence failed',
                  subtitle: 'Push on sequence errors or stops',
                  trailing: SettingsSwitch(
                    value:
                        pushConfig.notifySequenceFailed && pushConfig.enabled,
                    onChanged: (value) {
                      if (!pushConfig.enabled) return;
                      ref
                          .read(pushNotificationConfigProvider.notifier)
                          .setNotifySequenceFailed(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.rotateCw,
                  title: 'Meridian flip',
                  subtitle: 'Push on meridian flip events',
                  trailing: SettingsSwitch(
                    value: pushConfig.notifyMeridianFlip && pushConfig.enabled,
                    onChanged: (value) {
                      if (!pushConfig.enabled) return;
                      ref
                          .read(pushNotificationConfigProvider.notifier)
                          .setNotifyMeridianFlip(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.cloudRain,
                  title: 'Weather unsafe',
                  subtitle: 'Push when safety monitor reports unsafe',
                  trailing: SettingsSwitch(
                    value: pushConfig.notifyWeatherUnsafe && pushConfig.enabled,
                    onChanged: (value) {
                      if (!pushConfig.enabled) return;
                      ref
                          .read(pushNotificationConfigProvider.notifier)
                          .setNotifyWeatherUnsafe(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.crosshair,
                  title: 'Guiding lost',
                  subtitle: 'Push when guide star is lost',
                  trailing: SettingsSwitch(
                    value: pushConfig.notifyGuidingLost && pushConfig.enabled,
                    onChanged: (value) {
                      if (!pushConfig.enabled) return;
                      ref
                          .read(pushNotificationConfigProvider.notifier)
                          .setNotifyGuidingLost(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.cameraOff,
                  title: 'Exposure failed',
                  subtitle: 'Push when camera exposure fails',
                  trailing: SettingsSwitch(
                    value:
                        pushConfig.notifyExposureFailed && pushConfig.enabled,
                    onChanged: (value) {
                      if (!pushConfig.enabled) return;
                      ref
                          .read(pushNotificationConfigProvider.notifier)
                          .setNotifyExposureFailed(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.focus,
                  title: 'Autofocus failed',
                  subtitle: 'Push when autofocus fails',
                  trailing: SettingsSwitch(
                    value:
                        pushConfig.notifyAutofocusFailed && pushConfig.enabled,
                    onChanged: (value) {
                      if (!pushConfig.enabled) return;
                      ref
                          .read(pushNotificationConfigProvider.notifier)
                          .setNotifyAutofocusFailed(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.unplug,
                  title: 'Equipment disconnected',
                  subtitle: 'Push when a device disconnects',
                  trailing: SettingsSwitch(
                    value: pushConfig.notifyEquipmentDisconnected &&
                        pushConfig.enabled,
                    onChanged: (value) {
                      if (!pushConfig.enabled) return;
                      ref
                          .read(pushNotificationConfigProvider.notifier)
                          .setNotifyEquipmentDisconnected(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.send,
                  title: 'Test push notification',
                  subtitle: 'Send a test notification to mobile devices',
                  trailing: NightshadeButton(
                    label: 'Test',
                    variant: ButtonVariant.primary,
                    size: ButtonSize.small,
                    isLoading: _testingPushToMobile,
                    onPressed: (pushConfig.enabled && !_testingPushToMobile)
                        ? _testPushToMobile
                        : null,
                  ),
                  isLast: true,
                ),
              ],
            ),
            SettingsSection(
              title: 'Discord',
              children: [
                SettingRow(
                  icon: LucideIcons.messageSquare,
                  title: 'Webhook URL',
                  subtitle: 'Discord channel webhook for notifications',
                  trailing: settingsTrailingTextInput(
                    context: context,
                    controller: _discordController,
                    hint: 'https://discord.com/api/webhooks/...',
                    isMobile: widget.isMobile,
                    obscure: true,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setDiscordWebhook(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.send,
                  title: 'Test Discord',
                  subtitle: 'Send a test notification to your Discord channel',
                  trailing: NightshadeButton(
                    label: 'Test',
                    variant: ButtonVariant.primary,
                    size: ButtonSize.small,
                    isLoading: _testingDiscord,
                    onPressed: _testingDiscord ? null : _testDiscord,
                  ),
                  isLast: true,
                ),
              ],
            ),
            SettingsSection(
              title: 'Pushover',
              children: [
                SettingRow(
                  icon: LucideIcons.key,
                  title: 'API Key',
                  subtitle: 'Pushover application API key',
                  trailing: SettingsTextInput(
                    controller: _pushoverKeyController,
                    hint: 'API key',
                    width: 200,
                    obscure: true,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setPushoverKey(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.user,
                  title: 'User Key',
                  subtitle: 'Pushover user/group key',
                  trailing: SettingsTextInput(
                    controller: _pushoverUserController,
                    hint: 'User key',
                    width: 200,
                    obscure: true,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setPushoverUser(value);
                    },
                  ),
                ),
                SettingRow(
                  icon: LucideIcons.send,
                  title: 'Test Pushover',
                  subtitle: 'Send a test notification to your device',
                  trailing: NightshadeButton(
                    label: 'Test',
                    variant: ButtonVariant.primary,
                    size: ButtonSize.small,
                    isLoading: _testingPushover,
                    onPressed: _testingPushover ? null : _testPushover,
                  ),
                  isLast: true,
                ),
              ],
            ),
            // Wave 5 — comprehensive per-event routing matrix +
            // Email/Webhook/Telegram/MQTT credentials. Lives inside the
            // same Notifications page so users see one place for every
            // transport. Routing-aware Pushover / Discord configs above
            // are separate keys to keep legacy NotificationService
            // (Discord + Pushover only) working unchanged.
            NotificationRoutingSettings(
              isMobile: widget.isMobile,
            ),
          ],
        );
      },
    );
  }
}
