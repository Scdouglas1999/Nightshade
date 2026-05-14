import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_widgets.dart';

class NotificationSettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const NotificationSettings(
      {super.key, required this.colors, this.isMobile = false});

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
        colors: widget.colors,
        isMobile: widget.isMobile,
      ),
      error: (error, stack) => SettingsErrorState(
        colors: widget.colors,
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
          colors: widget.colors,
          children: [
            SettingsSection(
              title: 'General',
              colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            SettingsSection(
              title: 'Notification Events',
              colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  isLast: true,
                  colors: widget.colors,
                ),
              ],
            ),
            SettingsSection(
              title: 'Push to Mobile',
              colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                  colors: widget.colors,
                ),
              ],
            ),
            SettingsSection(
              title: 'Discord',
              colors: widget.colors,
              children: [
                SettingRow(
                  icon: LucideIcons.messageSquare,
                  title: 'Webhook URL',
                  subtitle: 'Discord channel webhook for notifications',
                  trailing: SettingsTextInput(
                    controller: _discordController,
                    hint: 'https://discord.com/api/webhooks/...',
                    width: 260,
                    obscure: true,
                    onChanged: (value) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setDiscordWebhook(value);
                    },
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                  colors: widget.colors,
                ),
              ],
            ),
            SettingsSection(
              title: 'Pushover',
              colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                    colors: widget.colors,
                  ),
                  colors: widget.colors,
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
                  colors: widget.colors,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
