import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'widgets/suggestion_card.dart';
import 'widgets/suggestion_filters.dart';
import 'widgets/transient_alerts_panel.dart';

/// Screen displaying tonight's target suggestions based on visibility,
/// scoring, and imaging progress.
///
/// Shows a responsive grid/list of suggestion cards with filtering options
/// and pull-to-refresh on mobile.
class SuggestionsScreen extends ConsumerWidget {
  const SuggestionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final suggestionsAsync = ref.watch(filteredSuggestionsProvider);
    final filterCount = ref.watch(activeFilterCountProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Column(
          children: [
            // App bar header
            _SuggestionsHeader(
              colors: colors,
              activeFilterCount: filterCount,
              onRefresh: () {
                ref.read(refreshSuggestionsProvider.notifier).state++;
              },
              onFilterTap: () => _showFilterSheet(context, ref),
            ),

            // Main content area
            Expanded(
              child: suggestionsAsync.when(
                data: (suggestions) =>
                    _buildDataState(context, ref, colors, suggestions),
                loading: () => _buildLoadingState(colors),
                error: (error, stackTrace) =>
                    _buildErrorState(context, ref, colors, error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataState(
    BuildContext context,
    WidgetRef ref,
    NightshadeColors colors,
    List<TargetSuggestion> suggestions,
  ) {
    if (suggestions.isEmpty) {
      return _buildEmptyState(context, ref, colors);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // Determine column count based on width
        // Mobile (< 600): single column
        // Tablet (600-900): 2 columns
        // Desktop (> 900): 2 columns
        final int crossAxisCount;
        if (width < NightshadeTokens.breakpointTablet) {
          crossAxisCount = 1;
        } else {
          crossAxisCount = 2;
        }

        final isMobile = width < NightshadeTokens.breakpointTablet;
        final isWideDesktop = width >= NightshadeTokens.breakpointDesktop;

        // On mobile, use RefreshIndicator for pull-to-refresh
        Widget content;
        if (crossAxisCount == 1) {
          // Single column ListView for mobile
          // Calculate card height based on available screen height
          // We want roughly 1.5 cards visible at a time for easy scrolling
          // while keeping altitude plots legible
          final availableHeight = constraints.maxHeight;
          final cardHeight = (availableHeight * 0.6).clamp(280.0, 420.0);

          content = ListView.builder(
            padding: isMobile
                ? NightshadeTokens.screenPaddingCompact
                : NightshadeTokens.screenPadding,
            // +1 for the transient alerts panel at the top on mobile
            itemCount: suggestions.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
                  child: TransientAlertsPanel(),
                );
              }
              final suggestionIndex = index - 1;
              return Padding(
                padding:
                    const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
                child: SizedBox(
                  height: cardHeight,
                  child: SuggestionCard(
                    suggestion: suggestions[suggestionIndex],
                    onViewInFraming: () {
                      _navigateToFraming(
                          context, ref, suggestions[suggestionIndex]);
                    },
                    onAddToSequence: () {
                      _showAddToSequenceDialog(
                          context, ref, suggestions[suggestionIndex]);
                    },
                  ),
                ),
              );
            },
          );
        } else if (isWideDesktop) {
          // Wide desktop: suggestions grid + transient alerts sidebar
          final sidebarWidth = 340.0;
          final gridWidth =
              width - sidebarWidth - NightshadeTokens.spaceLg - 48;
          final availableHeight = constraints.maxHeight;
          final cardHeight = (availableHeight * 0.6).clamp(280.0, 420.0);
          final cardWidth = (gridWidth - NightshadeTokens.spaceLg) / 2;
          final aspectRatio = cardWidth / cardHeight;

          content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Suggestion grid
              Expanded(
                child: GridView.builder(
                  padding: NightshadeTokens.screenPadding,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: NightshadeTokens.spaceLg,
                    mainAxisSpacing: NightshadeTokens.spaceLg,
                    childAspectRatio: aspectRatio,
                  ),
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    return SuggestionCard(
                      suggestion: suggestions[index],
                      onViewInFraming: () {
                        _navigateToFraming(context, ref, suggestions[index]);
                      },
                      onAddToSequence: () {
                        _showAddToSequenceDialog(
                            context, ref, suggestions[index]);
                      },
                    );
                  },
                ),
              ),

              const SizedBox(width: NightshadeTokens.spaceLg),

              // Transient alerts sidebar
              SizedBox(
                width: sidebarWidth,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    vertical: NightshadeTokens.spaceLg,
                  ),
                  child: const TransientAlertsPanel(),
                ),
              ),
            ],
          );
        } else {
          // Tablet: grid layout with transient alerts above
          final availableHeight = constraints.maxHeight;
          final cardHeight = (availableHeight * 0.6).clamp(280.0, 420.0);
          const hPad = NightshadeTokens.space2xl * 2;
          const gap = NightshadeTokens.spaceLg;
          final cardWidth =
              (width - hPad - (crossAxisCount - 1) * gap) / crossAxisCount;
          final aspectRatio = cardWidth / cardHeight;

          content = CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  NightshadeTokens.space2xl,
                  NightshadeTokens.spaceLg,
                  NightshadeTokens.space2xl,
                  NightshadeTokens.spaceMd,
                ),
                sliver: const SliverToBoxAdapter(
                  child: TransientAlertsPanel(),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NightshadeTokens.space2xl,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: NightshadeTokens.spaceLg,
                    mainAxisSpacing: NightshadeTokens.spaceLg,
                    childAspectRatio: aspectRatio,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return SuggestionCard(
                        suggestion: suggestions[index],
                        onViewInFraming: () {
                          _navigateToFraming(context, ref, suggestions[index]);
                        },
                        onAddToSequence: () {
                          _showAddToSequenceDialog(
                              context, ref, suggestions[index]);
                        },
                      );
                    },
                    childCount: suggestions.length,
                  ),
                ),
              ),
              const SliverPadding(
                padding: EdgeInsets.only(bottom: NightshadeTokens.spaceLg),
              ),
            ],
          );
        }

        // Wrap mobile layout with RefreshIndicator
        if (isMobile) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.read(refreshSuggestionsProvider.notifier).state++;
              // Wait for the provider to complete
              await ref.read(tonightSuggestionsProvider.future);
            },
            color: colors.primary,
            backgroundColor: colors.surface,
            child: content,
          );
        }

        return content;
      },
    );
  }

  Widget _buildLoadingState(NightshadeColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobile = width < NightshadeTokens.breakpointTablet;
        final crossAxisCount = isMobile ? 1 : 2;

        // Match data-state card sizing
        final availableHeight = constraints.maxHeight;
        final cardHeight = (availableHeight * 0.6).clamp(280.0, 420.0);
        const hPad = NightshadeTokens.space2xl * 2;
        const gap = NightshadeTokens.spaceLg;
        final cardWidth =
            (width - hPad - (crossAxisCount - 1) * gap) / crossAxisCount;
        final aspectRatio = cardWidth / cardHeight;

        // Show shimmer loading states
        return ShimmerLoading(
          child: crossAxisCount == 1
              ? ListView.builder(
                  padding: isMobile
                      ? NightshadeTokens.screenPaddingCompact
                      : NightshadeTokens.screenPadding,
                  itemCount: 3,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(
                          bottom: NightshadeTokens.spaceMd),
                      child: SizedBox(
                        height: cardHeight,
                        child: _SuggestionCardSkeleton(colors: colors),
                      ),
                    );
                  },
                )
              : GridView.builder(
                  padding: NightshadeTokens.screenPadding,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: NightshadeTokens.spaceLg,
                    mainAxisSpacing: NightshadeTokens.spaceLg,
                    childAspectRatio: aspectRatio,
                  ),
                  itemCount: 6,
                  itemBuilder: (context, index) {
                    return _SuggestionCardSkeleton(colors: colors);
                  },
                ),
        );
      },
    );
  }

  Widget _buildEmptyState(
      BuildContext context, WidgetRef ref, NightshadeColors colors) {
    // Check if location is configured
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final hasLocation = settings != null &&
        !(settings.latitude == 0.0 && settings.longitude == 0.0);

    return Center(
      child: Padding(
        padding: NightshadeTokens.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasLocation ? LucideIcons.moonStar : LucideIcons.mapPin,
              size: NightshadeTokens.icon2xl,
              color: colors.textMuted,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            Text(
              hasLocation
                  ? 'No targets visible tonight'
                  : 'Location not configured',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              hasLocation
                  ? 'All targets in your database are below the minimum altitude or have low scores for tonight\'s conditions.'
                  : 'Set your observer location in Settings to see target suggestions for your area.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceXl),
            if (!hasLocation)
              NightshadeButton(
                label: 'Open Settings',
                icon: LucideIcons.settings,
                onPressed: () {
                  context.go('/settings');
                },
              )
            else
              NightshadeButton(
                label: 'Adjust Filters',
                icon: LucideIcons.slidersHorizontal,
                variant: ButtonVariant.outline,
                onPressed: () => _showFilterSheet(context, ref),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    WidgetRef ref,
    NightshadeColors colors,
    Object error,
  ) {
    return Center(
      child: Padding(
        padding: NightshadeTokens.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.alertCircle,
              size: NightshadeTokens.icon2xl,
              color: colors.error,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            Text(
              'Failed to load suggestions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceXl),
            NightshadeButton(
              label: 'Retry',
              icon: LucideIcons.refreshCw,
              onPressed: () {
                ref.read(refreshSuggestionsProvider.notifier).state++;
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NightshadeTokens.radiusLg),
        ),
      ),
      builder: (context) {
        return const SuggestionFilters(showAsSheet: true);
      },
    );
  }

  void _showAddToSequenceDialog(
    BuildContext context,
    WidgetRef ref,
    TargetSuggestion suggestion,
  ) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            'Add to Sequence',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: Text(
            'Add "${suggestion.targetName}" to the current sequence?',
            style: TextStyle(color: colors.textSecondary),
          ),
          actions: [
            NightshadeButton(
              onPressed: () => Navigator.of(context).pop(),
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            NightshadeButton(
              label: 'Add',
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: () {
                // Create a TargetHeaderNode for the suggestion
                final targetNode = TargetHeaderNode(
                  targetName: suggestion.targetName,
                  raHours: suggestion.raHours,
                  decDegrees: suggestion.decDegrees,
                );

                // Add target to sequence via provider
                // This will auto-create a sequence if one doesn't exist
                ref
                    .read(currentSequenceProvider.notifier)
                    .addTargetHeader(targetNode);

                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added ${suggestion.targetName} to sequence'),
                    backgroundColor: colors.success,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _navigateToFraming(
    BuildContext context,
    WidgetRef ref,
    TargetSuggestion suggestion,
  ) {
    // Set the target in the framing provider before navigating
    ref.read(framingProvider.notifier).setTargetCoordinates(
          suggestion.raHours,
          suggestion.decDegrees,
          name: suggestion.targetName,
        );

    // Navigate to framing screen
    context.go('/framing');
  }
}

/// Header widget for the suggestions screen with title, refresh, and filter buttons.
class _SuggestionsHeader extends StatelessWidget {
  final NightshadeColors colors;
  final int activeFilterCount;
  final VoidCallback onRefresh;
  final VoidCallback onFilterTap;

  const _SuggestionsHeader({
    required this.colors,
    required this.activeFilterCount,
    required this.onRefresh,
    required this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return Container(
      height: NightshadeTokens.appBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: NightshadeTokens.spaceLg),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Text(
            "Tonight's Suggestions",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw,
                size: NightshadeTokens.iconMd),
            onPressed: onRefresh,
            tooltip: 'Refresh suggestions',
            color: colors.textSecondary,
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(LucideIcons.slidersHorizontal,
                    size: NightshadeTokens.iconMd),
                onPressed: onFilterTap,
                tooltip: 'Filter options',
                color: colors.textSecondary,
              ),
              if (activeFilterCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$activeFilterCount',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: onPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton loading cards for suggestions.
class _SuggestionCardSkeleton extends StatelessWidget {
  final NightshadeColors colors;

  const _SuggestionCardSkeleton({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
      ),
      padding: NightshadeTokens.cardPadding,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 150, height: 18),
              Spacer(),
              SkeletonBox(
                  width: 44,
                  height: 44,
                  borderRadius: NightshadeTokens.radiusFull),
            ],
          ),
          SizedBox(height: NightshadeTokens.spaceMd),
          SkeletonText(width: 200, height: 14),
          SizedBox(height: NightshadeTokens.spaceSm),
          // Altitude plot empty-state container - expands to fill available space
          Expanded(
            child: SkeletonBox(
              width: double.infinity,
              height: double.infinity,
              borderRadius: NightshadeTokens.radiusSm,
            ),
          ),
          SizedBox(height: NightshadeTokens.spaceSm),
          Row(
            children: [
              SkeletonBox(width: 60, height: 28),
              SizedBox(width: NightshadeTokens.spaceMd),
              SkeletonBox(width: 60, height: 28),
              SizedBox(width: NightshadeTokens.spaceMd),
              SkeletonBox(width: 60, height: 28),
              SizedBox(width: NightshadeTokens.spaceMd),
              SkeletonBox(width: 60, height: 28),
            ],
          ),
          SizedBox(height: NightshadeTokens.spaceMd),
          Row(
            children: [
              Expanded(child: SkeletonBox(width: double.infinity, height: 36)),
              SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(child: SkeletonBox(width: double.infinity, height: 36)),
            ],
          ),
        ],
      ),
    );
  }
}
