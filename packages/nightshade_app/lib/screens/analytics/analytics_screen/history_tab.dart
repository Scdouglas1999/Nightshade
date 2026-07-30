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
                    if (sessions.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.folderOpen,
                                size: 48, color: colors.textMuted),
                            const SizedBox(height: 16),
                            Text(
                              l10n.text('analyticsNoSessionHistory'),
                              style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize14,
                                  color: colors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.text('analyticsNoSessionHistoryDesc'),
                              style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize12,
                                  color: colors.textMuted),
                            ),
                          ],
                        ),
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
                      bool timeMatch = true;
                      if (_timeFilter == 'This Month') {
                        final now = DateTime.now();
                        timeMatch = session.startTime.year == now.year &&
                            session.startTime.month == now.month;
                      } else if (_timeFilter == 'This Year') {
                        timeMatch =
                            session.startTime.year == DateTime.now().year;
                      }
                      return nameMatch && targetMatch && timeMatch;
                    }).toList();

                    if (filteredSessions.isEmpty) {
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
                      itemCount: filteredSessions.length,
                      itemBuilder: (context, index) {
                        final session = filteredSessions[index];
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
