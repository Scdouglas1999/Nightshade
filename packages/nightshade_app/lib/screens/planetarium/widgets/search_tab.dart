import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import '../planetarium_screen.dart';

class SearchResultsTab extends ConsumerWidget {
  final NightshadeColors colors;

  const SearchResultsTab({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(objectSearchProvider);

    if (searchState.query.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.search, size: 48, color: colors.textMuted),
            const SizedBox(height: 16),
            Text(
              'Search for objects',
              style: TextStyle(color: colors.textMuted),
            ),
            const SizedBox(height: 8),
            Text(
              'Try "M42", "Andromeda Galaxy", or "Sirius"',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              'Fuzzy matching: "Andromea" finds "Andromeda"',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
          ],
        ),
      );
    }

    if (searchState.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (searchState.results.isEmpty) {
      return Center(
        child: Text(
          'No results for "${searchState.query}"',
          style: TextStyle(color: colors.textMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: searchState.results.length,
      itemBuilder: (context, index) {
        final obj = searchState.results[index];
        return SearchResultCard(
          object: obj,
          colors: colors,
          onTap: () {
            ref.read(selectedObjectProvider.notifier).selectObject(obj);
            ref.read(skyViewStateProvider.notifier).lookAt(obj.coordinates);
          },
        );
      },
    );
  }
}

class SearchResultCard extends StatelessWidget {
  final CelestialObject object;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const SearchResultCard({
    super.key,
    required this.object,
    required this.colors,
    required this.onTap,
  });

  String _buildDsoSubtitle(DeepSkyObject dso) {
    final parts = <String>[];
    final (_, catalogTag) = getDsoDisplayInfo(dso);
    parts.add(catalogTag);
    // Show first common name if available and different from display name
    if (dso.commonNames != null && dso.commonNames!.isNotEmpty) {
      final firstName = dso.commonNames!.split(',').first.trim();
      final (displayName, _) = getDsoDisplayInfo(dso);
      if (firstName != displayName && firstName.isNotEmpty) {
        parts.add(firstName);
      }
    }
    parts.add(dso.type.displayName);
    return parts.join(' - ');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(
              object is Star ? LucideIcons.star : LucideIcons.circle,
              size: 16,
              color: object is Star ? Colors.yellow : colors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    object is DeepSkyObject
                        ? getDsoDisplayInfo(object as DeepSkyObject).$1
                        : object.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (object is DeepSkyObject) ...[
                    Text(
                      _buildDsoSubtitle(object as DeepSkyObject),
                      style: TextStyle(fontSize: 11, color: colors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else
                    Text(
                      object.id,
                      style: TextStyle(fontSize: 11, color: colors.textMuted),
                    ),
                ],
              ),
            ),
            if (object.magnitude != null)
              Text(
                'mag ${object.magnitude!.toStringAsFixed(1)}',
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
