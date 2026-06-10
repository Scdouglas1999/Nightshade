// Wave 8 — Replay Debug retention + clear-all settings page.
//
// Surfaces the two replay-debug keys persisted in `app_settings`:
//   * replay_debug.enabled              — runtime toggle. When false the
//                                          Rust executor stops emitting
//                                          DecisionLogged events.
//   * replay_debug.retention_days       — daily-prune cutoff used by
//                                          ReplayDebugService.pruneOlderThan
//                                          (called from AutoSaveService on
//                                          app start, once per day).
//
// Also surfaces a destructive "Clear all replay history" button so the
// user can wipe the table without waiting for the retention window to
// catch up. The button is wrapped in a confirm dialog because the
// underlying delete is irreversible.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';

class ReplayDebugSettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const ReplayDebugSettings({
    super.key,
    this.isMobile = false,
  });

  @override
  ConsumerState<ReplayDebugSettings> createState() =>
      _ReplayDebugSettingsState();
}

class _ReplayDebugSettingsState extends ConsumerState<ReplayDebugSettings> {
  final TextEditingController _retentionCtrl = TextEditingController();
  bool _hydrated = false;
  bool _isClearing = false;

  @override
  void dispose() {
    _retentionCtrl.dispose();
    super.dispose();
  }

  void _hydrate(int days) {
    if (_hydrated) return;
    _hydrated = true;
    _retentionCtrl.text = days.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isMobile = widget.isMobile;
    final enabledAsync = ref.watch(replayDebugEnabledProvider);
    final retentionAsync = ref.watch(replayDebugRetentionDaysProvider);

    if (enabledAsync.isLoading || retentionAsync.isLoading) {
      return SettingsLoadingState(isMobile: isMobile);
    }
    if (enabledAsync.hasError) {
      return SettingsErrorState(
        isMobile: isMobile,
        error: enabledAsync.error!,
        onRetry: () => ref.invalidate(replayDebugEnabledProvider),
      );
    }
    if (retentionAsync.hasError) {
      return SettingsErrorState(
        isMobile: isMobile,
        error: retentionAsync.error!,
        onRetry: () => ref.invalidate(replayDebugRetentionDaysProvider),
      );
    }

    final enabled = enabledAsync.value ?? true;
    final retentionDays =
        retentionAsync.value ?? replayDebugDefaultRetentionDays;
    _hydrate(retentionDays);

    final controller = ref.read(replayDebugSettingsControllerProvider);

    return SettingsPage(
      title: 'Replay Debug',
      description: 'Decision-log retention + cleanup for the retrospective '
          'Replay screen. Decisions older than the retention window '
          'are pruned automatically on app startup (once per day).',
      isMobile: isMobile,
      hideHeader: isMobile,
      children: [
        SettingsSection(
          title: 'Logging',
          isMobile: isMobile,
          children: [
            _row(
              icon: LucideIcons.history,
              title: 'Replay decision logging',
              subtitle: 'When enabled, every adaptive-swap pick, trigger '
                  'firing, frame accept/reject, and recovery entry is '
                  'persisted to the sequence_decisions table so the '
                  'Replay screen can rebuild the timeline after the '
                  'fact.',
              trailing: SettingsSwitch(
                value: enabled,
                onChanged: (value) async {
                  await controller.setEnabled(value);
                },
              ),
              isLast: false,
            ),
            _row(
              icon: LucideIcons.calendar,
              title: 'Retention (days)',
              subtitle: 'Decisions older than this are pruned daily. Range '
                  '1..3650. Default $replayDebugDefaultRetentionDays.',
              trailing: SizedBox(
                width: 96,
                child: SettingsNumberInput(
                  controller: _retentionCtrl,
                  suffix: 'd',
                  min: 1,
                  max: 3650,
                  decimals: 0,
                  onChanged: (v) async {
                    await controller.setRetentionDays(v.toInt());
                  },
                ),
              ),
              isLast: true,
            ),
          ],
        ),
        SettingsSection(
          title: 'Maintenance',
          isMobile: isMobile,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clear all replay history',
                    style: NightshadeTypography.labelStrong
                        .copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Wipes every persisted decision row across all runs. '
                    'This does not delete captured images, sessions, or '
                    'session notes — only the replay log.',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: NightshadeButton(
                      onPressed: _isClearing
                          ? null
                          : () => _confirmAndClear(controller),
                      icon: LucideIcons.trash2,
                      label: _isClearing
                          ? 'Clearing…'
                          : 'Clear all replay history',
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmAndClear(ReplayDebugSettingsController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all replay history?'),
        content: const Text(
          'This deletes every row in the sequence_decisions table. '
          'The Replay screen will show "No decisions recorded" for '
          'every past run until new decisions accumulate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isClearing = true);
    final removed = await c.clearAllHistory();
    if (!mounted) return;
    setState(() => _isClearing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cleared $removed replay decision row(s).'),
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget trailing,
    bool isLast = false,
  }) {
    if (widget.isMobile) {
      return SettingRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        isMobile: true,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SettingRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
      ),
    );
  }
}
