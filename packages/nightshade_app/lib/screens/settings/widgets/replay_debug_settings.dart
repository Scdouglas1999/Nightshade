// Replay Debug retention + clear-all settings page.
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
  bool _isClearing = false;
  int _clearGeneration = 0;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;

  @override
  void initState() {
    super.initState();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (identical(previous, next)) return;
        _clearGeneration++;
        if (mounted && _isClearing) {
          setState(() => _isClearing = false);
        }
      },
    );
  }

  @override
  void dispose() {
    _clearGeneration++;
    _backendSubscription?.close();
    _retentionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isMobile = widget.isMobile;
    final isRemote = ref.watch(isRemoteModeProvider);
    final enabledAsync = ref.watch(replayDebugEnabledProvider);
    final retentionAsync = ref.watch(replayDebugRetentionDaysProvider);

    if (enabledAsync.isLoading || retentionAsync.isLoading) {
      return SettingsLoadingState(isMobile: isMobile);
    }
    if (enabledAsync.hasError) {
      return SettingsErrorState(
        isMobile: isMobile,
        error: enabledAsync.error!,
        onRetry: () => ref
            .read(replayDebugSettingsControllerProvider)
            .invalidateSettings(),
      );
    }
    if (retentionAsync.hasError) {
      return SettingsErrorState(
        isMobile: isMobile,
        error: retentionAsync.error!,
        onRetry: () => ref
            .read(replayDebugSettingsControllerProvider)
            .invalidateSettings(),
      );
    }

    final enabled = enabledAsync.value ?? true;
    final retentionDays =
        retentionAsync.value ?? replayDebugDefaultRetentionDays;

    final controller = ref.read(replayDebugSettingsControllerProvider);
    final Object authorityKey =
        isRemote ? ref.watch(backendProvider) : ref.watch(databaseProvider);

    return SettingsPage(
      title: 'Replay Debug',
      description: '${isRemote ? 'Imaging-host ' : ''}decision-log retention '
          '+ cleanup for the retrospective '
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
                  try {
                    await controller.setEnabled(value);
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Could not change replay logging: $error',
                        ),
                      ),
                    );
                  }
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
                  authoritativeValue: retentionDays.toDouble(),
                  authorityKey: authorityKey,
                  suffix: 'd',
                  min: 1,
                  max: 3650,
                  decimals: 0,
                  onChanged: (v) async {
                    try {
                      await controller.setRetentionDays(v.toInt());
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Could not change replay retention: $error',
                          ),
                        ),
                      );
                    }
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
                      isLoading: _isClearing,
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
    if (_isClearing) return;
    final authority = ref.read(backendProvider);
    final generation = ++_clearGeneration;
    setState(() => _isClearing = true);

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
    if (!_isCurrentClear(generation, authority)) return;
    if (ok != true) {
      setState(() => _isClearing = false);
      return;
    }
    try {
      final removed = await c.clearAllHistory();
      if (mounted && _isCurrentClear(generation, authority)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cleared $removed replay decision row(s).'),
          ),
        );
      }
    } catch (error) {
      if (mounted && _isCurrentClear(generation, authority)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not clear replay history: $error')),
        );
      }
    } finally {
      if (_isCurrentClear(generation, authority)) {
        setState(() => _isClearing = false);
      }
    }
  }

  bool _isCurrentClear(int generation, NightshadeBackend authority) =>
      mounted &&
      generation == _clearGeneration &&
      _isClearing &&
      identical(ref.read(backendProvider), authority);

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
