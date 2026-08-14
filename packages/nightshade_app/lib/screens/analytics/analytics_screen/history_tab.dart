// ignore_for_file: unused_element_parameter

part of '../analytics_screen.dart';

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab({super.key});

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _timeFilter = 'All Time';
  String _targetFilter = kAllTargetsFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesTimeFilter(DateTime when) {
    final now = DateTime.now();
    return switch (_timeFilter) {
      'This Month' => when.year == now.year && when.month == now.month,
      'This Year' => when.year == now.year,
      _ => true,
    };
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _timeFilter = 'All Time';
      _targetFilter = kAllTargetsFilter;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final sessionsAsyncValue = ref.watch(allSessionsProvider);
    final targetNamesAsync = ref.watch(sessionTargetNamesProvider);
    // Frames shot outside a sequence carry no imaging_sessions row, so this tab
    // used to deny a night that Analytics ▸ Session was displaying at the time.
    // They are not a run and are not listed as one — they get their own entry,
    // named for what they are.
    final quickCaptures = (ref.watch(standaloneImagesProvider).valueOrNull ??
            const <DbCapturedImage>[])
        .where((image) => image.frameType.toLowerCase() == 'light')
        .toList(growable: false);
    // Target names for the filter predicate: the dropdown lists real target
    // names, so matching a session needs its targetId resolved.
    final targetNameById = {
      for (final t
          in ref.watch(allDbTargetsProvider).valueOrNull ?? const <DbTarget>[])
        t.id: t.name,
    };
    final l10n = context.l10n;

    // Get target list from sessions, fallback to default if loading/error
    final targetList = targetNamesAsync.when(
      data: (targets) => targets,
      loading: () => const [kAllTargetsFilter],
      error: (_, __) => const [kAllTargetsFilter],
    );

    // Reset target filter if current selection no longer exists
    if (!targetList.contains(_targetFilter)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _targetFilter = kAllTargetsFilter);
        }
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < BreakpointTokens.breakpointPhone;

        final searchField = NightshadeTextField(
          controller: _searchController,
          hint: l10n.text('analyticsSearchSessions'),
          prefixIcon: LucideIcons.search,
          onChanged: (v) => setState(() => _searchQuery = v),
        );
        // On phone the dropdowns are full-width, so expand them to fill and
        // ellipsize rather than size to intrinsic content (which a narrow box
        // would overflow).
        final timeDropdown = NightshadeDropdown(
          value: _timeFilter,
          items: const ['All Time', 'This Month', 'This Year'],
          isExpanded: isPhone,
          onChanged: (v) => setState(() => _timeFilter = v ?? 'All Time'),
        );
        final targetDropdown = NightshadeDropdown(
          value: _targetFilter,
          items: targetList,
          isExpanded: isPhone,
          onChanged: (v) => setState(() => _targetFilter = v ?? 'All Targets'),
        );

        // Phone: each control gets its own full-width row so the dropdown's
        // internal label+icon never gets squeezed into an overflowing box.
        // Desktop keeps the single inline filter row.
        final Widget filters = isPhone
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchField,
                  const SizedBox(height: 12),
                  timeDropdown,
                  const SizedBox(height: 12),
                  targetDropdown,
                ],
              )
            : Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 16),
                  timeDropdown,
                  const SizedBox(width: 16),
                  targetDropdown,
                ],
              );

        return Padding(
          padding: EdgeInsets.all(isPhone ? 16.0 : 24.0),
          child: Column(
            children: [
              filters,
              const SizedBox(height: 24),
              // Session list
              Expanded(
                child: sessionsAsyncValue.when(
                  data: (sessions) {
                    if (sessions.isEmpty && quickCaptures.isEmpty) {
                      return AnalyticsEmptyState(
                        icon: LucideIcons.folderOpen,
                        title: l10n.text('analyticsNoSessionHistory'),
                        body: l10n.text('analyticsNoSessionHistoryDesc'),
                      );
                    }

                    // Filter sessions based on search query and target filter
                    final filteredSessions = sessions.where((session) {
                      // Search filter
                      final nameMatch = _searchQuery.isEmpty ||
                          (session.name
                                  ?.toLowerCase()
                                  .contains(_searchQuery.toLowerCase()) ??
                              false);
                      // Target filter (real targets — session names are
                      // filterable through the search field above).
                      final targetMatch = sessionMatchesTargetFilter(
                        session,
                        _targetFilter,
                        targetNameById,
                      );
                      // Time filter
                      final timeMatch = _matchesTimeFilter(session.startTime);
                      return nameMatch && targetMatch && timeMatch;
                    }).toList();

                    // The quick-capture entry is not filterable by target or
                    // session name — it has neither — so it is only suppressed
                    // by the time filter, which it can answer.
                    final showQuickCaptures = quickCaptures.isNotEmpty &&
                        _searchQuery.isEmpty &&
                        _targetFilter == kAllTargetsFilter &&
                        quickCaptures.any(
                          (image) => _matchesTimeFilter(image.capturedAt),
                        );

                    if (filteredSessions.isEmpty && !showQuickCaptures) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.searchX,
                                size: 48, color: colors.textMuted),
                            const SizedBox(height: 16),
                            Text(
                              'No sessions match your filters',
                              style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize14,
                                  color: colors.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            NightshadeButton(
                              label: 'Clear filters',
                              variant: ButtonVariant.outline,
                              size: ButtonSize.small,
                              onPressed: _clearFilters,
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount:
                          filteredSessions.length + (showQuickCaptures ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (showQuickCaptures && index == 0) {
                          return _QuickCaptureHistoryCard(
                            lights: quickCaptures,
                            hasSequenceRuns: filteredSessions.isNotEmpty,
                          );
                        }
                        final session = filteredSessions[
                            index - (showQuickCaptures ? 1 : 0)];
                        return _SessionHistoryCard(session: session);
                      },
                    );
                  },
                  // Skeleton list mirrors the real history card geometry so the
                  // page doesn't reflow when sessions resolve.
                  loading: () => const _SessionHistorySkeletonList(),
                  error: (err, stack) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.alertCircle,
                              size: 48, color: colors.error),
                          const SizedBox(height: 16),
                          Text(
                            'Error loading sessions',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: NightshadeTypography.fontSize14,
                                color: colors.error),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            err.toString(),
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: NightshadeTypography.fontSize12,
                                color: colors.textMuted),
                          ),
                          const SizedBox(height: 12),
                          NightshadeButton(
                            label: 'Retry',
                            variant: ButtonVariant.outline,
                            size: ButtonSize.small,
                            onPressed: () =>
                                ref.invalidate(allSessionsProvider),
                          ),
                        ],
                      ),
                    ),
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

/// History's entry for frames captured outside any sequence.
///
/// These live in `captured_images` with no `session_id` and no
/// `imaging_sessions` row, so History listed nothing for a night that Analytics
/// ▸ Session was showing at that moment. They are a real part of the night's
/// record and belong here — labelled as what they are, not dressed up as a run.
class _QuickCaptureHistoryCard extends StatelessWidget {
  final List<DbCapturedImage> lights;
  final bool hasSequenceRuns;

  const _QuickCaptureHistoryCard({
    required this.lights,
    required this.hasSequenceRuns,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final times = lights.map((image) => image.capturedAt).toList()..sort();
    final integration = lights.fold<double>(
      0,
      (sum, image) =>
          image.exposureDuration.isFinite && image.exposureDuration > 0
              ? sum + image.exposureDuration
              : sum,
    );
    final format = DateFormat('MMM d, yyyy HH:mm');
    final span = times.first == times.last
        ? format.format(times.first)
        : '${format.format(times.first)} – ${DateFormat('HH:mm').format(times.last)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NightshadeCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.camera,
                      size: 16, color: colors.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    'Quick captures',
                    style: NightshadeTypography.h5
                        .copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                span,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${lights.length} light frames taken outside a sequence, '
                '${_formatAnalyticsIntegration(integration)} of integration. '
                'They have no run record, so they carry no status, no target '
                'and no per-run diagnostics — open Analytics ▸ Session to '
                'review them frame by frame.',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textMuted,
                  height: 1.4,
                ),
              ),
              if (!hasSequenceRuns) ...[
                const SizedBox(height: 8),
                Text(
                  'No sequence runs are recorded for this filter.',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
