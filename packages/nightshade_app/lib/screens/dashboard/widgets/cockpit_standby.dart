import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../sequencer/widgets/smart_night_dialog.dart';

/// Cohesive standby hero shown on the Dashboard when nothing is running.
///
/// The Dashboard doubles as the app home screen. When no sequence is active
/// and the camera isn't manually capturing, each cockpit panel would otherwise
/// show its own scattered idle state. This replaces all of that with a single
/// centered hero: a "no run active" message, a primary **Plan Tonight** CTA
/// (the Smart Night wizard), a last-run summary that deep-links to the
/// Sequencer, and a compact readiness glance of the core devices.
///
/// The branch that chooses standby vs. the live cockpit lives in
/// `dashboard_screen.dart`; this widget assumes it is only built while idle.
class CockpitStandby extends ConsumerWidget {
  final NightshadeColors colors;

  const CockpitStandby({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                LucideIcons.moonStar,
                size: 40,
                color: colors.textMuted,
              ),
              const SizedBox(height: 16),
              Text(
                'No run active',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your cockpit is on standby. Build tonight\'s plan to start '
                'imaging, or open the Sequencer to load an existing sequence.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: NightshadeButton(
                  label: 'Plan Tonight',
                  icon: LucideIcons.sparkles,
                  variant: ButtonVariant.primary,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const SmartNightDialog(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _LastRunSummary(colors: colors),
              const SizedBox(height: 16),
              _ReadinessGlance(colors: colors),
            ],
          ),
        ),
      ),
    );
  }
}

class _LastRunSummary extends ConsumerWidget {
  final NightshadeColors colors;

  const _LastRunSummary({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsAsync = ref.watch(sequenceRunsProvider);

    // watchAllRuns() orders by startedAt desc, so the head is the newest run.
    final lastRun = runsAsync.maybeWhen(
      data: (runs) => runs.isEmpty ? null : runs.first,
      orElse: () => null,
    );

    if (lastRun == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: NightshadeTokens.borderRadiusMd,
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.history, size: 16, color: colors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No runs yet — your first night will appear here.',
                style: TextStyle(fontSize: 12.5, color: colors.textMuted),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(
            _statusIcon(lastRun.status),
            size: 16,
            color: _statusColor(lastRun.status, colors),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Last run: ${lastRun.sequenceName}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_statusLabel(lastRun.status)} · '
                  '${_relativeTime(lastRun.startedAt)}',
                  style: NightshadeTypography.withTabular(
                    TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          NightshadeButton(
            label: 'Open last run',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            // History deep-linking by run id isn't a stable route, so we link
            // to the Sequencer where the History tab surfaces the run list.
            onPressed: () => context.go('/sequencer'),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return LucideIcons.checkCircle;
      case 'failed':
        return LucideIcons.xCircle;
      case 'aborted':
        return LucideIcons.octagon;
      case 'running':
        return LucideIcons.activity;
      default:
        return LucideIcons.history;
    }
  }

  Color _statusColor(String status, NightshadeColors colors) {
    switch (status) {
      case 'completed':
        return colors.success;
      case 'failed':
      case 'aborted':
        return colors.error;
      case 'running':
        return colors.info;
      default:
        return colors.textMuted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      case 'aborted':
        return 'Aborted';
      case 'running':
        return 'Running';
      default:
        return status.isEmpty
            ? 'Unknown'
            : '${status[0].toUpperCase()}${status.substring(1)}';
    }
  }

  String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.isNegative) return 'just now';
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    final d = diff.inDays;
    if (d < 30) return '$d day${d == 1 ? '' : 's'} ago';
    final months = (d / 30).floor();
    return '$months month${months == 1 ? '' : 's'} ago';
  }
}

/// Compact readiness glance: connection state for the core devices plus the
/// camera's cooler temperature. Reads the same `*StateProvider` selects the
/// command bar's quick-stats strip uses so standby and the live cockpit agree.
class _ReadinessGlance extends ConsumerWidget {
  final NightshadeColors colors;

  const _ReadinessGlance({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraConnected =
        ref.watch(cameraStateProvider.select((s) => s.connectionState)) ==
            DeviceConnectionState.connected;
    final cameraTemp =
        ref.watch(cameraStateProvider.select((s) => s.temperature));
    final mountConnected =
        ref.watch(mountStateProvider.select((s) => s.connectionState)) ==
            DeviceConnectionState.connected;
    final guiderConnected =
        ref.watch(guiderStateProvider.select((s) => s.connectionState)) ==
            DeviceConnectionState.connected;
    final focuserConnected =
        ref.watch(focuserStateProvider.select((s) => s.connectionState)) ==
            DeviceConnectionState.connected;

    final coolerLabel = cameraConnected && cameraTemp != null
        ? '${cameraTemp.toStringAsFixed(1)}°C'
        : null;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _ReadinessChip(
          colors: colors,
          icon: LucideIcons.camera,
          label: 'Camera',
          connected: cameraConnected,
          detail: coolerLabel,
        ),
        _ReadinessChip(
          colors: colors,
          icon: LucideIcons.move3d,
          label: 'Mount',
          connected: mountConnected,
        ),
        _ReadinessChip(
          colors: colors,
          icon: LucideIcons.crosshair,
          label: 'Guider',
          connected: guiderConnected,
        ),
        _ReadinessChip(
          colors: colors,
          icon: LucideIcons.focus,
          label: 'Focuser',
          connected: focuserConnected,
        ),
      ],
    );
  }
}

class _ReadinessChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final bool connected;
  final String? detail;

  const _ReadinessChip({
    required this.colors,
    required this.icon,
    required this.label,
    required this.connected,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final accent = connected ? colors.success : colors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          StatusDot(color: accent, size: 8),
          if (detail != null) ...[
            const SizedBox(width: 6),
            Text(
              detail!,
              style: NightshadeTypography.withTabular(
                TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
