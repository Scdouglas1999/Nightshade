part of '../analytics_screen.dart';

class _SessionDetailDialog extends ConsumerWidget {
  final ImagingSession session;

  const _SessionDetailDialog({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final imagesAsyncValue = ref.watch(dbSessionImagesProvider(session.id));
    final l10n = context.l10n;

    return Dialog(
      backgroundColor: colors.surface,
      child: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 600,
          designMaxHeight: 700,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.name ?? l10n.text('analyticsUnnamedSession'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d, yyyy HH:mm')
                              .format(session.startTime),
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  // View the rich Feature-A session report.
                  IconButton(
                    icon: const Icon(LucideIcons.fileBarChart, size: 18),
                    onPressed: () =>
                        SessionReportDialog.show(context, session.id),
                    tooltip: 'Session Report',
                  ),
                  // Export buttons
                  IconButton(
                    icon: const Icon(LucideIcons.fileJson, size: 18),
                    onPressed: () => _exportJson(context, ref),
                    tooltip: l10n.text('analyticsExportJson'),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.fileSpreadsheet, size: 18),
                    onPressed: () => _exportCsv(context, ref),
                    tooltip: l10n.text('analyticsExportCsv'),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.fileText, size: 18),
                    onPressed: () => _exportReport(context, ref),
                    tooltip: l10n.text('analyticsExportHtml'),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.share, size: 18),
                    onPressed: () => _exportAndShare(context, ref),
                    tooltip: l10n.text('share'),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Statistics
                    _buildStatisticsSection(context, colors),
                    const SizedBox(height: 16),

                    // Images
                    imagesAsyncValue.when(
                      data: (images) =>
                          _buildImagesSection(context, colors, images),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, stack) => Text(
                        'Error loading images: $err',
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsSection(
      BuildContext context, NightshadeColors colors) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.text('analyticsStatistics'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildStat(
              l10n.text('analyticsTotalExposures'),
              session.totalExposures.toString(),
              colors,
            ),
            _buildStat(
              l10n.text('analyticsSuccessful'),
              session.successfulExposures.toString(),
              colors,
            ),
            _buildStat(
              l10n.text('analyticsFailed'),
              session.failedExposures.toString(),
              colors,
            ),
            _buildStat(
              l10n.text('analyticsIntegration'),
              '${(session.totalIntegrationSecs / 3600).toStringAsFixed(2)}h',
              colors,
            ),
            if (session.avgHfr != null)
              _buildStat(
                l10n.text('analyticsAvgHfr'),
                session.avgHfr!.toStringAsFixed(2),
                colors,
              ),
            if (session.avgGuidingRms != null)
              _buildStat(
                l10n.text('analyticsAvgRms'),
                session.avgGuidingRms!.toStringAsFixed(2),
                colors,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value, NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildImagesSection(
    BuildContext context,
    NightshadeColors colors,
    List<DbCapturedImage> images,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.text(
            'analyticsImages',
            params: {'count': images.length.toString()},
          ),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ImageThumbnailStrip(images: images),
      ],
    );
  }

  Future<void> _exportJson(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final filePath = await _saveRemoteExport(backend, session.id, 'json');
        if (context.mounted) {
          context.showSuccessSnackBar('Exported to: $filePath');
        }
        return;
      }
      final clock = ref.read(clockProvider);
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
        nowProvider: clock.now,
      );

      final filePath = await exportService.exportToJson(session.id);

      if (context.mounted) {
        context.showSuccessSnackBar('Exported to: $filePath');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: $e');
      }
    }
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final filePath = await _saveRemoteExport(backend, session.id, 'csv');
        if (context.mounted) {
          context.showSuccessSnackBar('Exported to: $filePath');
        }
        return;
      }
      final clock = ref.read(clockProvider);
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
        nowProvider: clock.now,
      );

      final filePath = await exportService.exportToCsv(session.id);

      if (context.mounted) {
        context.showSuccessSnackBar('Exported to: $filePath');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: $e');
      }
    }
  }

  Future<void> _exportAndShare(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final filePath = await _saveRemoteExport(backend, session.id, 'csv');
        await Share.shareXFiles([XFile(filePath)],
            text: 'Session data for ${session.name ?? "session"}');
        return;
      }
      final clock = ref.read(clockProvider);
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
        nowProvider: clock.now,
      );

      // Export to CSV for sharing (more universal format)
      final filePath = await exportService.exportToCsv(session.id);

      // Share the file
      await Share.shareXFiles([XFile(filePath)],
          text: 'Session data for ${session.name ?? "session"}');
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Share failed: $e');
      }
    }
  }

  Future<void> _exportReport(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final filePath = await _saveRemoteExport(backend, session.id, 'html');
        if (context.mounted) {
          context.showSuccessSnackBar('Report exported to: $filePath');
        }
        return;
      }
      final clock = ref.read(clockProvider);
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
        nowProvider: clock.now,
      );

      final filePath = await exportService.exportToHtml(session.id);

      if (context.mounted) {
        context.showSuccessSnackBar('Report exported to: $filePath');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Report export failed: $e');
      }
    }
  }
}

Stream<List<DbCapturedImage>> _pollRemoteSessionImages(
  NetworkBackend backend,
  int sessionId,
) async* {
  yield await _fetchRemoteSessionImages(backend, sessionId);
  while (true) {
    await Future.delayed(const Duration(seconds: 10));
    yield await _fetchRemoteSessionImages(backend, sessionId);
  }
}

Stream<List<DbCapturedImage>> _pollRemoteStandaloneImages(
  NetworkBackend backend,
) async* {
  yield await _fetchRemoteStandaloneImages(backend);
  while (true) {
    await Future.delayed(const Duration(seconds: 10));
    yield await _fetchRemoteStandaloneImages(backend);
  }
}

Future<List<DbCapturedImage>> _fetchRemoteSessionImages(
  NetworkBackend backend,
  int sessionId,
) async {
  final rows = await backend.getSessionImageRows(sessionId);
  return rows.map(DbCapturedImage.fromJson).toList(growable: false);
}

Future<List<DbCapturedImage>> _fetchRemoteStandaloneImages(
  NetworkBackend backend,
) async {
  final rows = await backend.getStandaloneImageRows();
  return rows.map(DbCapturedImage.fromJson).toList(growable: false);
}

Future<String> _saveRemoteExport(
  NetworkBackend backend,
  int sessionId,
  String format,
) async {
  final bytes = await backend.downloadSessionExport(sessionId, format);
  final docsDir = await getApplicationDocumentsDirectory();
  final exportDir = Directory(path.join(docsDir.path, 'Nightshade', 'exports'));
  if (!await exportDir.exists()) {
    await exportDir.create(recursive: true);
  }
  final fileName =
      'session_${sessionId}_${DateTime.now().millisecondsSinceEpoch}.$format';
  final filePath = path.join(exportDir.path, fileName);
  await File(filePath).writeAsBytes(bytes, flush: true);
  return filePath;
}
