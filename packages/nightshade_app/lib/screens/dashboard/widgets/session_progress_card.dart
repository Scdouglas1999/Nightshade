import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import 'glass_card.dart';

class SessionProgressCard extends ConsumerWidget {
  final NightshadeColors colors;

  const SessionProgressCard({super.key, required this.colors});

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  String _formatIntegrationTime(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    return _formatDuration(duration);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionStateProvider);
    final progress = ref.watch(sessionProgressProvider);
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);

    final isActive = sessionState.isActive;
    final progressValue = progress.clamp(0.0, 1.0);
    final targetName = sessionState.targetName ?? 'No target';

    // Format exposure count
    final exposureText = '${sessionState.completedExposures}/${sessionState.totalExposures}';

    // Format integration time
    final integrationText = sessionState.totalIntegrationSecs > 0
        ? _formatIntegrationTime(sessionState.totalIntegrationSecs)
        : '0m';

    // Format elapsed time
    final elapsedText = sessionState.startTime != null
        ? _formatDuration(DateTime.now().difference(sessionState.startTime!))
        : '---';

    // Calculate remaining time
    String remainingText = '---';
    if (isActive && progressValue > 0 && progressValue < 1.0 && sessionState.startTime != null) {
      final elapsed = DateTime.now().difference(sessionState.startTime!);
      final estimatedTotal = Duration(
        milliseconds: (elapsed.inMilliseconds / progressValue).round(),
      );
      final remaining = estimatedTotal - elapsed;
      if (remaining.inMilliseconds > 0) {
        remainingText = _formatDuration(remaining);
      }
    }

    // Current exposure info
    final currentExpText = '${exposureSettings.exposureTime}s ${exposureSettings.filter ?? "L"}';

    return DashboardGlassCard(
      colors: colors,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with target name
          Row(
            children: [
              Icon(
                LucideIcons.target,
                size: 14,
                color: isActive ? colors.success : colors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isActive ? targetName : 'Sequence',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Text(
                  currentExpText,
                  style: TextStyle(fontSize: 10, color: colors.textSecondary),
                ),
              const SizedBox(width: 8),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive ? colors.success.withValues(alpha: 0.15) : colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isActive ? 'Running' : 'Idle',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: isActive ? colors.success : colors.textMuted,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Progress bar with percentage
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: progressValue,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [colors.primary, colors.accent]),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(progressValue * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Current exposure progress row (only show when actively exposing)
          if (exposureProgress.percent > 0 || exposureProgress.isDownloading)
            _ExposureProgressRow(
              progress: exposureProgress,
              exposureTime: exposureSettings.exposureTime,
              colors: colors,
            ),

          if (exposureProgress.percent > 0 || exposureProgress.isDownloading)
            const SizedBox(height: 6),

          // Stats grid - compact layout
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            decoration: BoxDecoration(
              color: colors.surfaceAlt.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                _CompactStat(label: 'Frm', value: exposureText, colors: colors),
                _CompactStat(label: 'Int', value: integrationText, colors: colors),
                _CompactStat(label: 'Elap', value: elapsedText, colors: colors),
                _CompactStat(label: 'Rem', value: remainingText, colors: colors, highlight: isActive),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows current exposure progress during active capture
class _ExposureProgressRow extends StatelessWidget {
  final ExposureProgress progress;
  final double exposureTime;
  final NightshadeColors colors;

  const _ExposureProgressRow({
    required this.progress,
    required this.exposureTime,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final elapsedText = progress.elapsed.toStringAsFixed(1);
    final totalText = exposureTime.toStringAsFixed(1);
    final progressPercent = (progress.percent / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            progress.isDownloading ? LucideIcons.download : LucideIcons.camera,
            size: 12,
            color: progress.isDownloading ? colors.info : colors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            progress.isDownloading
                ? 'Downloading...'
                : '$elapsedText s / $totalText s',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                widthFactor: progressPercent,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: progress.isDownloading ? colors.info : colors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact stat for dense information display
class _CompactStat extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final bool highlight;

  const _CompactStat({
    required this.label,
    required this.value,
    required this.colors,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: highlight ? colors.primary : colors.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 9, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// MiniStat used by FocusCard and other cards for compact stat display.
class DashboardMiniStat extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const DashboardMiniStat({
    super.key,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
