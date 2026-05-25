import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/nightshade_app.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/error_snackbar.dart';

/// Phone-native Science tab — status, session KPIs, solve health, campaign
/// progress, and quick actions (grade frames, export report).
class ScienceTab extends ConsumerWidget {
  const ScienceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final activeSessionId = ref.watch(sessionStateProvider).dbSessionId;
    final images = activeSessionId == null
        ? const <DbCapturedImage>[]
        : ref.watch(dbSessionImagesProvider(activeSessionId)).valueOrNull ??
            const [];
    final lightFrames = images
        .where((img) => img.frameType.toLowerCase() == 'light')
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: () async {
        if (activeSessionId != null) {
          ref.invalidate(sessionFrameCalibrationsProvider(activeSessionId));
          ref.invalidate(sessionTransparencySamplesProvider(activeSessionId));
          ref.invalidate(sessionFrameQualityMetricsProvider(activeSessionId));
          ref.invalidate(dbSessionImagesProvider(activeSessionId));
        }
      },
      color: colors.primary,
      backgroundColor: colors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const ScienceStatusBanner(),
          const SizedBox(height: 12),
          const ScienceSessionSummary(),
          const SizedBox(height: 12),
          ScienceSolveRateCard(colors: colors, lightFrames: lightFrames),
          const SizedBox(height: 12),
          const ScienceCampaignStrip(),
          if (activeSessionId != null && lightFrames.isNotEmpty) ...[
            const SizedBox(height: 16),
            _QuickActions(
              colors: colors,
              sessionId: activeSessionId,
              lightFrames: lightFrames,
            ),
          ],
          if (activeSessionId == null) ...[
            const SizedBox(height: 24),
            _IdleHint(colors: colors),
          ],
        ],
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  final NightshadeColors colors;
  final int sessionId;
  final List<DbCapturedImage> lightFrames;

  const _QuickActions({
    required this.colors,
    required this.sessionId,
    required this.lightFrames,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Session actions',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            NightshadeButton(
              label: 'Grade ${lightFrames.length} frames',
              icon: LucideIcons.sliders,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: () async {
                final rejected = await ImageGraderDialog.show(
                  context,
                  frames: lightFrames,
                  sessionId: sessionId,
                );
                if (rejected != null &&
                    rejected > 0 &&
                    context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Rejected $rejected frame(s)'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
            NightshadeButton(
              label: 'Export science report',
              icon: LucideIcons.fileText,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Generating science report…'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                try {
                  final file = await ref
                      .read(scienceReportExporterProvider)
                      .exportToDisk(sessionId);
                  if (!context.mounted) return;
                  messenger.clearSnackBars();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Saved to ${file.path}'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (e) {
                  // [Wave 6D error parsing] — render ServerError as
                  // "<message> (<code>)" with the right severity tint
                  // via the shared mobile helper.
                  if (!context.mounted) return;
                  showApiErrorWithPrefix(context, 'Export failed', e);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _IdleHint extends StatelessWidget {
  final NightshadeColors colors;
  const _IdleHint({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.flaskConical,
              color: colors.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Start a session and capture plate-solved lights to populate '
              'photometry, transparency, and field-quality trends. Open the '
              'desktop Analytics → Science tab for light curves and overlays.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
