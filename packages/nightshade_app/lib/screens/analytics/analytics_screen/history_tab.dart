// ignore_for_file: unused_element_parameter

part of '../analytics_screen.dart';

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab({super.key});

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  String _searchQuery = '';
  String _timeFilter = 'All Time';
  String _targetFilter = 'All Targets';

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final sessionsAsyncValue = ref.watch(allSessionsProvider);
    final targetNamesAsync = ref.watch(sessionTargetNamesProvider);
    final l10n = context.l10n;

    // Get target list from sessions, fallback to default if loading/error
    final targetList = targetNamesAsync.when(
      data: (targets) => targets,
      loading: () => const ['All Targets'],
      error: (_, __) => const ['All Targets'],
    );

    // Reset target filter if current selection no longer exists
    if (!targetList.contains(_targetFilter)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _targetFilter = 'All Targets');
        }
      });
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Filters
          Row(
            children: [
              Expanded(
                child: NightshadeTextField(
                  hint: l10n.text('analyticsSearchSessions'),
                  prefixIcon: LucideIcons.search,
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 16),
              NightshadeDropdown(
                value: _timeFilter,
                items: const ['All Time', 'This Month', 'This Year'],
                onChanged: (v) => setState(() => _timeFilter = v ?? 'All Time'),
              ),
              const SizedBox(width: 16),
              NightshadeDropdown(
                value: _targetFilter,
                items: targetList,
                onChanged: (v) =>
                    setState(() => _targetFilter = v ?? 'All Targets'),
              ),
            ],
          ),

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
                              fontSize: 14, color: colors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.text('analyticsNoSessionHistoryDesc'),
                          style:
                              TextStyle(fontSize: 12, color: colors.textMuted),
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
                  // Target filter
                  final targetMatch = _targetFilter == 'All Targets' ||
                      session.name == _targetFilter;
                  // Time filter
                  bool timeMatch = true;
                  if (_timeFilter == 'This Month') {
                    final now = DateTime.now();
                    timeMatch = session.startTime.year == now.year &&
                        session.startTime.month == now.month;
                  } else if (_timeFilter == 'This Year') {
                    timeMatch = session.startTime.year == DateTime.now().year;
                  }
                  return nameMatch && targetMatch && timeMatch;
                }).toList();

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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.alertCircle,
                        size: 48, color: colors.error),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading sessions',
                      style: TextStyle(fontSize: 14, color: colors.error),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      err.toString(),
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
