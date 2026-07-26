import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../services/android_system_ui.dart';
import '../../../services/mobile_preferences.dart';
import '../../../services/notification_service.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(mobilePreferencesProvider);
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return prefsAsync.when(
      data: (prefs) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Display',
            colors: colors,
            children: [
              _SwitchRow(
                title: 'Immersive Android mode',
                subtitle: 'Hide the status bar while monitoring a session',
                value: prefs.androidImmersiveSticky,
                onChanged: (value) async {
                  await prefs.setAndroidImmersiveSticky(value);
                  ref.invalidate(mobilePreferencesProvider);
                  if (Platform.isAndroid) {
                    await applyAndroidSystemUiPreference(value);
                  }
                },
                colors: colors,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Notifications',
            colors: colors,
            children: [
              _SwitchRow(
                title: 'Sequence events',
                subtitle: 'Completion, stop, and failure alerts',
                value: prefs.notifySequence,
                onChanged: (value) async {
                  await prefs.setNotifySequence(value);
                  ref.invalidate(mobilePreferencesProvider);
                  MobileNotificationService().enableSequenceNotifications =
                      value;
                },
                colors: colors,
              ),
              _SwitchRow(
                title: 'Meridian flips',
                subtitle: 'Flip start and completion alerts',
                value: prefs.notifyMeridianFlip,
                onChanged: (value) async {
                  await prefs.setNotifyMeridianFlip(value);
                  ref.invalidate(mobilePreferencesProvider);
                },
                colors: colors,
              ),
              _SwitchRow(
                title: 'Safety and weather',
                subtitle: 'Unsafe weather and mount park alerts',
                value: prefs.notifySafety,
                onChanged: (value) async {
                  await prefs.setNotifySafety(value);
                  ref.invalidate(mobilePreferencesProvider);
                },
                colors: colors,
              ),
              _SwitchRow(
                title: 'Guiding lost',
                subtitle: 'Guide star and guider disconnect alerts',
                value: prefs.notifyGuiding,
                onChanged: (value) async {
                  await prefs.setNotifyGuiding(value);
                  ref.invalidate(mobilePreferencesProvider);
                },
                colors: colors,
              ),
              _SwitchRow(
                title: 'Exposure failures',
                subtitle: 'Camera exposure failure alerts',
                value: prefs.notifyExposureFailed,
                onChanged: (value) async {
                  await prefs.setNotifyExposureFailed(value);
                  ref.invalidate(mobilePreferencesProvider);
                },
                colors: colors,
              ),
              _SwitchRow(
                title: 'Autofocus failures',
                subtitle: 'Autofocus did not complete',
                value: prefs.notifyAutofocusFailed,
                onChanged: (value) async {
                  await prefs.setNotifyAutofocusFailed(value);
                  ref.invalidate(mobilePreferencesProvider);
                },
                colors: colors,
              ),
              _SwitchRow(
                title: 'Equipment disconnected',
                subtitle: 'Camera, mount, guider, and accessory disconnects',
                value: prefs.notifyEquipmentDisconnected,
                onChanged: (value) async {
                  await prefs.setNotifyEquipmentDisconnected(value);
                  ref.invalidate(mobilePreferencesProvider);
                },
                colors: colors,
              ),
              _SwitchRow(
                title: 'Low disk space',
                subtitle: 'Storage warnings from the desktop',
                value: prefs.notifyDiskLow,
                onChanged: (value) async {
                  await prefs.setNotifyDiskLow(value);
                  ref.invalidate(mobilePreferencesProvider);
                },
                colors: colors,
              ),
              _SwitchRow(
                title: 'Target completed',
                subtitle: 'Per-target completion alerts',
                value: prefs.notifyTargetCompleted,
                onChanged: (value) async {
                  await prefs.setNotifyTargetCompleted(value);
                  ref.invalidate(mobilePreferencesProvider);
                },
                colors: colors,
              ),
              _SwitchRow(
                title: 'Battery warnings',
                subtitle: 'Low battery and power-protection alerts',
                value: prefs.notifyBattery,
                onChanged: (value) async {
                  await prefs.setNotifyBattery(value);
                  ref.invalidate(mobilePreferencesProvider);
                },
                colors: colors,
                isLast: true,
              ),
            ],
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load settings: $error',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.error),
              ),
              const SizedBox(height: 16),
              NightshadeButton(
                label: 'Retry',
                onPressed: () => ref.invalidate(mobilePreferencesProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final NightshadeColors colors;

  const _Section({
    required this.title,
    required this.children,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              title,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;
  final NightshadeColors colors;
  final bool isLast;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.colors,
    this.isLast = false,
  });

  @override
  State<_SwitchRow> createState() => _SwitchRowState();
}

class _SwitchRowState extends State<_SwitchRow> {
  bool _saving = false;

  Future<void> _change(bool value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onChanged(value);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update ${widget.title}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: widget.colors.border.withValues(alpha: 0.5),
                ),
              ),
      ),
      child: SwitchListTile.adaptive(
        value: widget.value,
        onChanged: _saving ? null : _change,
        activeThumbColor: widget.colors.primary,
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  color: widget.colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_saving) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        subtitle: Text(
          widget.subtitle,
          style: TextStyle(color: widget.colors.textSecondary, fontSize: 12),
        ),
      ),
    );
  }
}
