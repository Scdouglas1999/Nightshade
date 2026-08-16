part of '../analytics_screen.dart';

class _SessionDetailDialog extends ConsumerWidget {
  final ImagingSession session;

  const _SessionDetailDialog({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final imagesAsyncValue = ref.watch(dbSessionImagesProvider(session.id));
    final isRemote = ref.watch(backendProvider) is NetworkBackend;
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NightshadeTypography.h4.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d, yyyy HH:mm')
                              .format(session.startTime),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: NightshadeTypography.fontSize12,
                              color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  // Action buttons scroll horizontally so they never overflow
                  // the header on narrow (phone-width) dialogs.
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Open the Session Review / Morning Report (cull +
                          // integrate).
                          IconButton(
                            key: const ValueKey('session_detail_review'),
                            icon: const Icon(LucideIcons.sparkles, size: 18),
                            onPressed: () {
                              if (isRemote) {
                                context.showInfoSnackBar(
                                  'Session Review is available on the imaging host.',
                                );
                                return;
                              }
                              Navigator.of(context).pop();
                              context.push(
                                  '/session-review?session=${session.id}');
                            },
                            tooltip: isRemote
                                ? 'Review on imaging host'
                                : 'Review & Integrate',
                          ),
                          // View the rich Feature-A session report.
                          IconButton(
                            icon:
                                const Icon(LucideIcons.fileBarChart, size: 18),
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
                            icon: const Icon(LucideIcons.fileSpreadsheet,
                                size: 18),
                            onPressed: () => _exportCsv(context, ref),
                            tooltip: l10n.text('analyticsExportCsv'),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.fileText, size: 18),
                            onPressed: () => _exportReport(context, ref),
                            tooltip: l10n.text('analyticsExportHtml'),
                          ),
                          // Share only exists where the OS has a share sheet.
                          // On desktop `shareXFiles()` is unimplemented, and
                          // the CSV button beside it already writes the same
                          // file and shows its path.
                          if (Platform.isAndroid || Platform.isIOS)
                            IconButton(
                              icon: const Icon(LucideIcons.share, size: 18),
                              onPressed: () => _exportAndShare(context, ref),
                              tooltip: l10n.text('share'),
                            ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 18),
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: l10n.text('commonClose'),
                          ),
                        ],
                      ),
                    ),
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
          style: NightshadeTypography.h5.copyWith(
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
        const SizedBox(height: 6),
        // These counters come from the session's own light-frame tallies, while
        // the image list below holds every frame written to disk. Unlabelled,
        // "Total Exposures 12" over "Images (16)" reads as one count the app
        // cannot keep straight.
        Text(
          l10n.text('analyticsExposureCountsLightOnly'),
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            color: colors.textMuted,
          ),
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
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textSecondary),
        ),
        Text(
          value,
          style: NightshadeTypography.h5.copyWith(
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
    final lightCount = images
        .where((image) => image.frameType.toLowerCase() == 'light')
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.text(
            'analyticsImages',
            params: {'count': images.length.toString()},
          ),
          style: NightshadeTypography.h5.copyWith(
            color: colors.textPrimary,
          ),
        ),
        // Says what the list is made of, so it can be compared with the
        // light-only exposure counters above it.
        if (images.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            context.l10n.text(
              'analyticsFrameMix',
              params: {
                'light': lightCount.toString(),
                'calibration': (images.length - lightCount).toString(),
              },
            ),
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textMuted,
            ),
          ),
        ],
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
          await revealExportedFile(
            context,
            filePath,
            subject: 'Nightshade session data',
          );
        }
        return;
      }
      final clock = ref.read(clockProvider);
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
        nowProvider: clock.now,
      );

      // The export lands in getApplicationDocumentsDirectory(), which is the
      // private sandbox on Android/iOS — an "Exported to: <path>" line there
      // names a file the user cannot open, so hand it to the share sheet.
      final filePath = await exportService.exportToJson(session.id);

      if (context.mounted) {
        await revealExportedFile(
          context,
          filePath,
          subject: 'Nightshade session data',
        );
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
          await revealExportedFile(
            context,
            filePath,
            subject: 'Nightshade session data',
          );
        }
        return;
      }
      final clock = ref.read(clockProvider);
      final exportService = SessionExportService(
        sessionsDao: ref.read(sessionsDaoProvider),
        imagesDao: ref.read(imagesDaoProvider),
        nowProvider: clock.now,
      );

      // Same sandbox problem as the JSON export: reveal rather than announce
      // a path the phone user can never reach.
      final filePath = await exportService.exportToCsv(session.id);

      if (context.mounted) {
        await revealExportedFile(
          context,
          filePath,
          subject: 'Nightshade session data',
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: $e');
      }
    }
  }

  /// Export the session to CSV and hand it to the platform's reachable
  /// destination.
  ///
  /// Routed through [revealExportedFile] — share sheet on Android/iOS, path
  /// snackbar on desktop — because `Share.shareXFiles` is unimplemented on the
  /// shipping desktop build.
  Future<void> _exportAndShare(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      final String filePath;
      if (backend is NetworkBackend) {
        filePath = await _saveRemoteExport(backend, session.id, 'csv');
      } else {
        final clock = ref.read(clockProvider);
        final exportService = SessionExportService(
          sessionsDao: ref.read(sessionsDaoProvider),
          imagesDao: ref.read(imagesDaoProvider),
          nowProvider: clock.now,
        );
        // CSV is the most universal format to hand off.
        filePath = await exportService.exportToCsv(session.id);
      }

      if (!context.mounted) return;
      await revealExportedFile(
        context,
        filePath,
        subject: 'Session data for ${session.name ?? "session"}',
      );
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Export failed: $e');
      }
    }
  }

  Future<void> _exportReport(BuildContext context, WidgetRef ref) async {
    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final filePath = await _saveRemoteExport(backend, session.id, 'html');
        if (context.mounted) {
          await revealExportedFile(
            context,
            filePath,
            subject: 'Nightshade session report',
          );
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
        await revealExportedFile(
          context,
          filePath,
          subject: 'Nightshade session report',
        );
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
  int sessionId, {
  required Duration interval,
}) =>
    _pollRemoteImages(
      () => _fetchRemoteSessionImages(backend, sessionId),
      interval: interval,
    );

Stream<List<DbCapturedImage>> _pollRemoteStandaloneImages(
  NetworkBackend backend, {
  required Duration interval,
}) =>
    _pollRemoteImages(
      () => _fetchRemoteStandaloneImages(backend),
      interval: interval,
    );

Stream<List<DbCapturedImage>> _pollRemoteImages(
  Future<List<DbCapturedImage>> Function() fetch, {
  required Duration interval,
}) =>
    resilientDistinctPoll(
      fetch: fetch,
      unchanged: listEquals,
      interval: interval,
    );

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
