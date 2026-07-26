import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/nightshade_app.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

class ScienceReportShareFile {
  final File file;
  final String mimeType;

  const ScienceReportShareFile({required this.file, required this.mimeType});
}

/// Stage the report that the mobile share sheet will receive.
///
/// Companion mode must ask the host to generate the report because the session
/// and science DAOs live on that host. Reading the phone's local DAOs can fail
/// with "session not found" or, if IDs collide, export an unrelated local row.
/// Local mode retains the Markdown exporter used by desktop.
Future<ScienceReportShareFile> stageScienceReportForShare({
  required NightshadeBackend backend,
  required int sessionId,
  required Future<File> Function() exportLocalMarkdown,
  Future<Directory> Function() temporaryDirectory = getTemporaryDirectory,
}) async {
  if (backend is NetworkBackend) {
    final bytes = await backend.generateObservationReport(sessionId);
    final directory = await temporaryDirectory();
    final file = File(
      p.join(directory.path, 'nightshade-science-session-$sessionId.pdf'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return ScienceReportShareFile(file: file, mimeType: 'application/pdf');
  }

  final file = await exportLocalMarkdown();
  return ScienceReportShareFile(file: file, mimeType: 'text/markdown');
}

typedef ScienceReportShare =
    Future<void> Function(String path, String mimeType, String subject);

final scienceReportShareProvider = Provider<ScienceReportShare>((ref) {
  return (path, mimeType, subject) async {
    await Share.shareXFiles([
      XFile(path, mimeType: mimeType),
    ], subject: subject);
  };
});

class _QuickActions extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final int sessionId;
  final List<DbCapturedImage> lightFrames;

  const _QuickActions({
    required this.colors,
    required this.sessionId,
    required this.lightFrames,
  });

  @override
  ConsumerState<_QuickActions> createState() => _QuickActionsState();
}

class _QuickActionsState extends ConsumerState<_QuickActions> {
  String? _pendingAction;

  Future<void> _gradeFrames() async {
    if (_pendingAction != null) return;
    setState(() => _pendingAction = 'grade');
    try {
      final rejected = await ImageGraderDialog.show(
        context,
        frames: widget.lightFrames,
        sessionId: widget.sessionId,
      );
      if (rejected != null && rejected > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rejected $rejected frame(s)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingAction = null);
    }
  }

  Future<void> _exportReport() async {
    if (_pendingAction != null) return;
    setState(() => _pendingAction = 'export');
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Preparing science report…'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    try {
      final exporter = ref.read(scienceReportExporterProvider);
      final staged = await stageScienceReportForShare(
        backend: ref.read(backendProvider),
        sessionId: widget.sessionId,
        exportLocalMarkdown: () => exporter.exportToDisk(widget.sessionId),
      );
      if (!mounted) return;
      messenger.clearSnackBars();
      await ref.read(scienceReportShareProvider)(
        staged.file.path,
        staged.mimeType,
        'Nightshade science report — session ${widget.sessionId}',
      );
    } catch (e) {
      if (!mounted) return;
      messenger.clearSnackBars();
      showApiErrorWithPrefix(context, 'Export failed', e);
    } finally {
      if (mounted) setState(() => _pendingAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _pendingAction != null;
    final colors = widget.colors;
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
              label: _pendingAction == 'grade'
                  ? 'Opening grader…'
                  : 'Grade ${widget.lightFrames.length} frames',
              icon: LucideIcons.sliders,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              isLoading: _pendingAction == 'grade',
              onPressed: busy ? null : _gradeFrames,
            ),
            const SizedBox(height: 8),
            NightshadeButton(
              label: _pendingAction == 'export'
                  ? 'Preparing report…'
                  : 'Export science report',
              icon: LucideIcons.fileText,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              isLoading: _pendingAction == 'export',
              onPressed: busy ? null : _exportReport,
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
          Icon(LucideIcons.flaskConical, color: colors.textSecondary, size: 20),
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
