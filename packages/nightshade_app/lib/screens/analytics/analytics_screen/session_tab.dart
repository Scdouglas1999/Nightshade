// ignore_for_file: unused_element_parameter

part of '../analytics_screen.dart';

class _SessionTab extends ConsumerWidget {
  const _SessionTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final sessionState = ref.watch(sessionStateProvider);
    final duration = ref.watch(sessionDurationProvider);
    final l10n = context.l10n;

    // Get current session images if active, otherwise show standalone captures
    final bool isStandaloneMode = sessionState.dbSessionId == null;
    final imagesAsyncValue = sessionState.dbSessionId != null
        ? ref.watch(dbSessionImagesProvider(sessionState.dbSessionId!))
        : ref.watch(standaloneImagesProvider);
    void retryImages() {
      if (sessionState.dbSessionId != null) {
        ref.invalidate(dbSessionImagesProvider(sessionState.dbSessionId!));
      } else {
        ref.invalidate(standaloneImagesProvider);
      }
    }

    final String headerTitle;
    final String headerSubtitle;
    if (sessionState.isActive) {
      headerTitle = l10n.text('analyticsCurrentSession');
      headerSubtitle = sessionState.startTime != null
          ? l10n.text(
              'analyticsStarted',
              params: {
                'time': DateFormat('MMM d, yyyy HH:mm')
                    .format(sessionState.startTime!),
              },
            )
          : l10n.text('analyticsSessionInProgress');
    } else if (isStandaloneMode) {
      headerTitle = l10n.text('analyticsQuickCapture');
      headerSubtitle = l10n.text('analyticsQuickCaptureSubtitle');
    } else {
      headerTitle = l10n.text('analyticsNoActiveSession');
      headerSubtitle = l10n.text('analyticsNoSessionInProgress');
    }

    String standaloneMetric(String Function(List<DbCapturedImage>) value) {
      return imagesAsyncValue.when(
        data: value,
        loading: () => 'Loading…',
        error: (_, __) => 'Unavailable',
      );
    }

    List<DbCapturedImage> acceptedLights(List<DbCapturedImage> images) => images
        .where((image) =>
            image.isAccepted && image.frameType.toLowerCase() == 'light')
        .toList(growable: false);

    final summaryStats = [
      ResponsiveStat(
        label: l10n.text('analyticsDuration'),
        value: sessionState.isActive ? duration : '—',
      ),
      ResponsiveStat(
        label: l10n.text('analyticsExposures'),
        value: sessionState.isActive
            ? '${sessionState.completedExposures}/${sessionState.totalExposures}'
            : isStandaloneMode
                ? standaloneMetric((images) => '${images.length}')
                : '—',
      ),
      ResponsiveStat(
        label: l10n.text('analyticsIntegration'),
        value: sessionState.isActive
            ? '${(sessionState.totalIntegrationSecs / 60).toStringAsFixed(1)}m'
            : isStandaloneMode
                ? standaloneMetric((images) {
                    final seconds = acceptedLights(images).fold<double>(
                      0,
                      (sum, image) => image.exposureDuration.isFinite &&
                              image.exposureDuration > 0
                          ? sum + image.exposureDuration
                          : sum,
                    );
                    return _formatAnalyticsIntegration(seconds);
                  })
                : '—',
      ),
      ResponsiveStat(
        label: l10n.text('analyticsAvgHfr'),
        value: sessionState.isActive
            ? sessionState.avgHfr?.toStringAsFixed(2) ?? '—'
            : isStandaloneMode
                ? standaloneMetric((images) {
                    final hfrs = acceptedLights(images)
                        .map((image) => image.hfr)
                        .whereType<double>()
                        .where((value) => value.isFinite && value >= 0)
                        .toList(growable: false);
                    if (hfrs.isEmpty) return 'No data';
                    final average =
                        hfrs.fold<double>(0, (sum, value) => sum + value) /
                            hfrs.length;
                    return average.toStringAsFixed(2);
                  })
                : '—',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < BreakpointTokens.breakpointPhone;
        final outerPadding = EdgeInsets.all(isPhone ? 16.0 : 24.0);

        Widget chartGrid(List<DbCapturedImage> images) {
          final hfr =
              HfrChart(key: AnalyticsTutorialKeys.hfrChart, images: images);
          final guiding = GuidingRmsChart(
              key: AnalyticsTutorialKeys.guidingChart, images: images);
          final focuser = FocuserPositionChart(images: images);
          final temperature = TemperatureChart(images: images);

          // Phone: a single column of full-width charts so each reads at the
          // viewport width. Tablet/desktop keep the 2-up grid.
          if (isPhone) {
            return Column(
              children: [
                hfr,
                const SizedBox(height: 16),
                guiding,
                const SizedBox(height: 16),
                focuser,
                const SizedBox(height: 16),
                temperature,
              ],
            );
          }
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: hfr),
                  const SizedBox(width: 16),
                  Expanded(child: guiding),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: focuser),
                  const SizedBox(width: 16),
                  Expanded(child: temperature),
                ],
              ),
            ],
          );
        }

        return SingleChildScrollView(
          padding: outerPadding,
          child: Column(
            children: [
              // Session summary bar — header stacks above a reflowing stat
              // strip so the four metrics never overflow a phone column.
              NightshadeCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headerTitle,
                        style: NightshadeTypography.h4.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        headerSubtitle,
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ResponsiveStatStrip(stats: summaryStats),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Graph grid
              imagesAsyncValue.when(
                data: chartGrid,
                loading: () => _AnalyticsAsyncState(
                  colors: colors,
                  icon: LucideIcons.lineChart,
                  message: 'Loading analytics charts...',
                ),
                error: (err, stack) => _AnalyticsAsyncState(
                  colors: colors,
                  icon: LucideIcons.alertTriangle,
                  message: 'Failed to load analytics charts',
                  detail: err.toString(),
                  onRetry: retryImages,
                ),
              ),

              const SizedBox(height: 24),

              // Captured images strip
              NightshadeCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.text('analyticsCapturedImages'),
                        style: NightshadeTypography.h5.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.text('analyticsQualityAdvisory'),
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize11,
                          color: colors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      imagesAsyncValue.when(
                        data: (images) => ImageThumbnailStrip(
                            key: AnalyticsTutorialKeys.thumbnails,
                            images: images),
                        loading: () => SizedBox(
                          height: kAnalyticsThumbnailRailHeight,
                          child: _AnalyticsAsyncState(
                            colors: colors,
                            icon: LucideIcons.image,
                            message: 'Loading images...',
                            compact: true,
                          ),
                        ),
                        error: (err, stack) => SizedBox(
                          height: kAnalyticsThumbnailRailHeight,
                          child: _AnalyticsAsyncState(
                            colors: colors,
                            icon: LucideIcons.alertTriangle,
                            message: 'Failed to load images',
                            detail: err.toString(),
                            compact: true,
                            onRetry: retryImages,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnalyticsAsyncState extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String message;
  final String? detail;
  final VoidCallback? onRetry;
  final bool compact;

  const _AnalyticsAsyncState({
    required this.colors,
    required this.icon,
    required this.message,
    this.detail,
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          message,
          textAlign: compact ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 12 : 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(
            detail!,
            textAlign: compact ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              color: colors.textSecondary,
            ),
            maxLines: compact ? 2 : 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    if (compact) {
      return Center(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: NightshadeTokens.borderRadiusLg,
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: onRetry == null ? colors.primary : colors.error,
              ),
              const SizedBox(width: 10),
              Expanded(child: text),
              if (onRetry != null) ...[
                const SizedBox(width: 8),
                NightshadeButton(
                  label: 'Retry',
                  icon: LucideIcons.refreshCw,
                  size: ButtonSize.small,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: NightshadeTokens.borderRadiusXl,
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: onRetry == null ? colors.primary : colors.error,
            ),
            const SizedBox(height: 12),
            text,
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              NightshadeButton(
                label: 'Retry',
                icon: LucideIcons.refreshCw,
                size: ButtonSize.medium,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatAnalyticsIntegration(double seconds) {
  if (!seconds.isFinite || seconds <= 0) return 'No data';
  final rounded = seconds.round();
  if (rounded < 60) return '${rounded}s';
  if (rounded < 3600) {
    final minutes = rounded ~/ 60;
    final remainder = rounded % 60;
    return remainder == 0 ? '${minutes}m' : '${minutes}m ${remainder}s';
  }
  final hours = rounded ~/ 3600;
  final minutes = (rounded % 3600) ~/ 60;
  return '${hours}h ${minutes}m';
}

/// Provider for watching session images (Drift rows) on the Analytics screen.
///
/// Renamed from `sessionImagesProvider` (which collided with the
/// in-memory `sessionImagesProvider` in nightshade_core) so importers don't
/// have to `hide` either declaration.
final dbSessionImagesProvider =
    StreamProvider.family<List<DbCapturedImage>, int>((ref, sessionId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteSessionImages(
      backend,
      sessionId,
      interval: ref.watch(analyticsRemoteImagePollIntervalProvider),
    );
  }
  return ref.watch(imagesDaoProvider).watchImagesForSession(sessionId);
});

/// Provider for watching standalone (sessionless) images
final standaloneImagesProvider = StreamProvider<List<DbCapturedImage>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteStandaloneImages(
      backend,
      interval: ref.watch(analyticsRemoteImagePollIntervalProvider),
    );
  }
  return ref.watch(imagesDaoProvider).watchStandaloneImages();
});

/// Remote image catalogs are low-churn and do not need to hammer the host.
/// Exposed so tests can exercise retry/distinct behavior without waiting 10s.
final analyticsRemoteImagePollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 10),
);

/// Provider for unique target names derived from sessions
/// Returns a list of unique session names to use as target filter options
final sessionTargetNamesProvider = Provider<AsyncValue<List<String>>>((ref) {
  final sessionsAsync = ref.watch(allSessionsProvider);
  return sessionsAsync.when(
    data: (sessions) {
      // Extract unique non-null session names
      final uniqueNames = sessions
          .map((s) => s.name)
          .where((name) => name != null && name.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList()
        ..sort();
      return AsyncValue.data(['All Targets', ...uniqueNames]);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});
