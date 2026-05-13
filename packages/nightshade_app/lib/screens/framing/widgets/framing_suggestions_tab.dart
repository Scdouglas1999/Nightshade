import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart'
    hide TargetSearchState, targetSearchProvider;

import '../../suggestions/widgets/suggestion_card.dart';
import '../../suggestions/widgets/suggestion_filters.dart';

/// The Suggestions tab content (the second tab in the framing screen).
/// Renders a responsive grid/list of `TargetSuggestion`s with filter/refresh
/// affordances; reports user selection back to the parent so the framing tab
/// can adopt the chosen target.
class FramingSuggestionsTab extends ConsumerWidget {
  final void Function(TargetSuggestion suggestion) onTargetSelected;

  const FramingSuggestionsTab({
    super.key,
    required this.onTargetSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final suggestionsAsync = ref.watch(filteredSuggestionsProvider);

    return suggestionsAsync.when(
      data: (suggestions) => _buildDataState(context, ref, colors, suggestions),
      loading: () => _buildLoadingState(colors),
      error: (error, stackTrace) =>
          _buildErrorState(context, ref, colors, error),
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
        // Desktop (> 900): 2-3 columns
        final int crossAxisCount;
        if (width < NightshadeTokens.breakpointTablet) {
          crossAxisCount = 1;
        } else if (width < 1200) {
          crossAxisCount = 2;
        } else {
          crossAxisCount = 3;
        }

        final isMobile = width < NightshadeTokens.breakpointTablet;

        // On mobile, use RefreshIndicator for pull-to-refresh
        Widget content;
        if (crossAxisCount == 1) {
          // Single column ListView for mobile
          content = ListView.builder(
            padding: isMobile
                ? NightshadeTokens.screenPaddingCompact
                : NightshadeTokens.screenPadding,
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              return Padding(
                padding:
                    const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
                child: SuggestionCard(
                  suggestion: suggestions[index],
                  onViewInFraming: () => onTargetSelected(suggestions[index]),
                  onAddToSequence: () {
                    _addToSequence(context, ref, suggestions[index]);
                  },
                ),
              );
            },
          );
        } else {
          // Grid layout for tablet/desktop
          // Calculate card height for ~1.5 rows visible (matching mobile feel)
          final availableHeight = constraints.maxHeight;
          final cardHeight = (availableHeight * 0.6).clamp(280.0, 420.0);
          const hPad = NightshadeTokens.space2xl * 2;
          const gap = NightshadeTokens.spaceLg;
          final cardWidth =
              (width - hPad - (crossAxisCount - 1) * gap) / crossAxisCount;
          final aspectRatio = cardWidth / cardHeight;

          content = GridView.builder(
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
                onViewInFraming: () => onTargetSelected(suggestions[index]),
                onAddToSequence: () {
                  _addToSequence(context, ref, suggestions[index]);
                },
              );
            },
          );
        }

        // Wrap mobile layout with RefreshIndicator
        if (isMobile) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.read(refreshSuggestionsProvider.notifier).state++;
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
                  itemCount: 6,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(
                          bottom: NightshadeTokens.spaceMd),
                      child: _SuggestionCardSkeleton(colors: colors),
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
                  // Use GoRouter to navigate
                  GoRouter.of(context).go('/settings');
                },
              )
            else
              NightshadeButton(
                label: 'Adjust Filters',
                icon: LucideIcons.slidersHorizontal,
                variant: ButtonVariant.outline,
                onPressed: () => _showFilterSheet(context, ref, colors),
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

  void _showFilterSheet(
      BuildContext context, WidgetRef ref, NightshadeColors colors) {
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

  void _addToSequence(
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
}

/// Skeleton loading cards for suggestions
class _SuggestionCardSkeleton extends StatelessWidget {
  final NightshadeColors colors;

  const _SuggestionCardSkeleton({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
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
                  width: 60,
                  height: 24,
                  borderRadius: NightshadeTokens.radiusFull),
            ],
          ),
          SizedBox(height: NightshadeTokens.spaceMd),
          SkeletonText(width: 200, height: 14),
          SizedBox(height: NightshadeTokens.spaceSm),
          SkeletonText(width: double.infinity, height: 12, lines: 2),
          Spacer(),
          Row(
            children: [
              SkeletonBox(width: 80, height: 20),
              SizedBox(width: NightshadeTokens.spaceMd),
              SkeletonBox(width: 80, height: 20),
              SizedBox(width: NightshadeTokens.spaceMd),
              SkeletonBox(width: 80, height: 20),
            ],
          ),
        ],
      ),
    );
  }
}
