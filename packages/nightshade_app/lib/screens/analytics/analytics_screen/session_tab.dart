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

    final summaryStats = [
      ResponsiveStat(
        label: l10n.text('analyticsDuration'),
        value: duration,
      ),
      ResponsiveStat(
        label: l10n.text('analyticsExposures'),
        value: sessionState.isActive
            ? '${sessionState.completedExposures}/${sessionState.totalExposures}'
            : '---',
      ),
      ResponsiveStat(
        label: l10n.text('analyticsIntegration'),
        value: sessionState.isActive
            ? '${(sessionState.totalIntegrationSecs / 60).toStringAsFixed(1)}m'
            : '---',
      ),
      ResponsiveStat(
        label: l10n.text('analyticsAvgHfr'),
        value: sessionState.avgHfr != null
            ? sessionState.avgHfr!.toStringAsFixed(2)
            : '---',
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
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize16,
                          fontWeight: FontWeight.w600,
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
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize14,
                          fontWeight: FontWeight.w600,
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
    return Center(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 12 : 20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(compact ? 12 : 16),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: onRetry == null ? colors.primary : colors.error,
            ),
            SizedBox(height: compact ? 8 : 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  color: colors.textSecondary,
                ),
                maxLines: compact ? 2 : 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (onRetry != null) ...[
              SizedBox(height: compact ? 8 : 12),
              NightshadeButton(
                label: 'Retry',
                icon: LucideIcons.refreshCw,
                size: compact ? ButtonSize.small : ButtonSize.medium,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
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
    return _pollRemoteSessionImages(backend, sessionId);
  }
  return ref.watch(imagesDaoProvider).watchImagesForSession(sessionId);
});

/// Provider for watching standalone (sessionless) images
final standaloneImagesProvider = StreamProvider<List<DbCapturedImage>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteStandaloneImages(backend);
  }
  return ref.watch(imagesDaoProvider).watchStandaloneImages();
});

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
