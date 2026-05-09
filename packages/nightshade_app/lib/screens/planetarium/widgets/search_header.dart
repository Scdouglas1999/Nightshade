import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import '../../../utils/coordinate_format_utils.dart';
import '../planetarium_screen.dart';

class SearchHeader extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final TextEditingController controller;
  final ValueChanged<String> onSearch;

  const SearchHeader({
    super.key,
    required this.colors,
    required this.controller,
    required this.onSearch,
  });

  @override
  ConsumerState<SearchHeader> createState() => _SearchHeaderState();
}

class _SearchHeaderState extends ConsumerState<SearchHeader> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;
  CelestialCoordinate? _parsedCoordinate;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
    });
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _hideOverlay();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  /// Parse coordinate input like "RA 5h 35m, Dec -5d 23'"
  CelestialCoordinate? _parseCoordinates(String input) {
    // Try pattern like "RA 5h 35m, Dec -5d 23'" or "RA 5h 35m Dec -5 23"
    final pattern = RegExp(
        r'RA\s*(\d+)h\s*(\d+)m.*Dec\s*([+-]?\d+)[°d]?\s*(\d+)',
        caseSensitive: false);
    final match = pattern.firstMatch(input);

    if (match != null) {
      final raHours = double.parse(match.group(1)!);
      final raMinutes = double.parse(match.group(2)!);
      final decDegrees = double.parse(match.group(3)!);
      final decMinutes = double.parse(match.group(4)!);

      final ra = raHours + raMinutes / 60;
      final dec =
          decDegrees + (decDegrees >= 0 ? decMinutes / 60 : -decMinutes / 60);

      return CelestialCoordinate(ra: ra, dec: dec);
    }
    return null;
  }

  void _onTextChanged() {
    // Cancel previous debounce timer
    _debounceTimer?.cancel();

    // Check for coordinate input first
    _parsedCoordinate = _parseCoordinates(widget.controller.text);
    if (_parsedCoordinate != null) {
      // If coordinates were parsed, show overlay immediately
      _showOverlay();
      return;
    }

    if (widget.controller.text.length >= 2) {
      // Debounce search by 250ms for instant results as user types
      _debounceTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted) {
          ref
              .read(objectSearchProvider.notifier)
              .search(widget.controller.text);
          _showOverlay();
        }
      });
    } else {
      _hideOverlay();
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;

    // Don't show if query is too short (unless we have parsed coordinates)
    if (widget.controller.text.length < 2 && _parsedCoordinate == null) return;

    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 308, // Match container width minus padding
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 46), // Height of text field + padding
          child: Material(
            elevation: 8,
            color: widget.colors.surface,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: widget.colors.border),
                borderRadius: BorderRadius.circular(8),
                color: widget.colors.surface,
              ),
              constraints: const BoxConstraints(maxHeight: 450),
              child: Consumer(
                builder: (context, ref, child) {
                  // Check for parsed coordinates first
                  if (_parsedCoordinate != null) {
                    final coord = _parsedCoordinate!;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SearchCategoryHeader(
                          title: 'Coordinates',
                          icon: LucideIcons.compass,
                          colors: widget.colors,
                        ),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              // Navigate to parsed coordinates
                              ref
                                  .read(skyViewStateProvider.notifier)
                                  .setCenter(coord.ra, coord.dec);
                              _hideOverlay();
                              _focusNode.unfocus();
                            },
                            child: ListTile(
                              dense: true,
                              leading: Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: widget.colors.accent
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  LucideIcons.crosshair,
                                  size: 16,
                                  color: widget.colors.accent,
                                ),
                              ),
                              title: Text(
                                'Go to coordinates',
                                style:
                                    TextStyle(color: widget.colors.textPrimary),
                              ),
                              subtitle: Text(
                                'RA ${CoordinateFormatUtils.formatRACompact(coord.ra)}, Dec ${CoordinateFormatUtils.formatDec(coord.dec)}',
                                style: TextStyle(
                                    color: widget.colors.textMuted,
                                    fontSize: 11),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  final searchState = ref.watch(objectSearchProvider);

                  if (searchState.isSearching) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  if (searchState.results.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'No results found',
                        style: TextStyle(color: widget.colors.textMuted),
                      ),
                    );
                  }

                  // Show all results grouped by category, no hardcoded limit
                  final stars = searchState.results.whereType<Star>().toList();
                  final dsos =
                      searchState.results.whereType<DeepSkyObject>().toList();

                  if (stars.isEmpty && dsos.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'No results found',
                        style: TextStyle(color: widget.colors.textMuted),
                      ),
                    );
                  }

                  // Show result count
                  final totalCount = stars.length + dsos.length;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Result count header
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              widget.colors.surfaceAlt.withValues(alpha: 0.3),
                          border: Border(
                              bottom: BorderSide(
                                  color: widget.colors.border
                                      .withValues(alpha: 0.5))),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '$totalCount result${totalCount == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 10,
                                color: widget.colors.textMuted,
                              ),
                            ),
                            if (searchState.filters.hasActiveFilters) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: widget.colors.accent
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'filtered',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: widget.colors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          children: [
                            // DSO section
                            if (dsos.isNotEmpty) ...[
                              SearchCategoryHeader(
                                title: 'Deep Sky Objects (${dsos.length})',
                                icon: LucideIcons.sparkles,
                                colors: widget.colors,
                              ),
                              // Show first 20 DSOs in overlay, full list in Search tab
                              ...dsos
                                  .take(20)
                                  .map((dso) => _buildDsoResultTile(ref, dso)),
                              if (dsos.length > 20)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Text(
                                    '${dsos.length - 20} more in Search tab...',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: widget.colors.textMuted,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                            // Stars section
                            if (stars.isNotEmpty) ...[
                              SearchCategoryHeader(
                                title: 'Stars (${stars.length})',
                                icon: LucideIcons.star,
                                colors: widget.colors,
                              ),
                              ...stars.take(10).map(
                                  (star) => _buildStarResultTile(ref, star)),
                              if (stars.length > 10)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Text(
                                    '${stars.length - 10} more in Search tab...',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: widget.colors.textMuted,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  Widget _buildDsoResultTile(WidgetRef ref, DeepSkyObject dso) {
    final info = getDsoDisplayInfo(dso);
    final displayName = info.$1;
    final catalogTag = info.$2;
    // Show common name as subtitle if different from display name
    final commonName = dso.commonNames?.split(',').first.trim();
    final showCommonName = commonName != null &&
        commonName.isNotEmpty &&
        commonName != displayName;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.read(selectedObjectProvider.notifier).selectObject(dso);
          ref.read(skyViewStateProvider.notifier).lookAt(dso.coordinates);
          widget.onSearch(dso.name);
          _hideOverlay();
          _focusNode.unfocus();
        },
        child: ListTile(
          dense: true,
          leading: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              catalogTag,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: widget.colors.primary,
              ),
            ),
          ),
          title: Text(
            displayName,
            style: TextStyle(color: widget.colors.textPrimary),
          ),
          subtitle: Text(
            showCommonName
                ? '$commonName - ${dso.type.displayName}'
                : dso.type.displayName,
            style: TextStyle(color: widget.colors.textMuted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: dso.magnitude != null
              ? Text(
                  'mag ${dso.magnitude!.toStringAsFixed(1)}',
                  style:
                      TextStyle(color: widget.colors.textMuted, fontSize: 11),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildStarResultTile(WidgetRef ref, Star star) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.read(selectedObjectProvider.notifier).selectObject(star);
          ref.read(skyViewStateProvider.notifier).lookAt(star.coordinates);
          widget.onSearch(star.name);
          _hideOverlay();
          _focusNode.unfocus();
        },
        child: ListTile(
          dense: true,
          leading: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '\u2605',
              style: TextStyle(
                fontSize: 14,
                color: Colors.amber,
              ),
            ),
          ),
          title: Text(
            star.name,
            style: TextStyle(color: widget.colors.textPrimary),
          ),
          subtitle: Text(
            star.constellation != null
                ? 'Star - ${star.constellation}'
                : 'Star',
            style: TextStyle(color: widget.colors.textMuted, fontSize: 11),
          ),
          trailing: star.magnitude != null
              ? Text(
                  'mag ${star.magnitude!.toStringAsFixed(1)}',
                  style:
                      TextStyle(color: widget.colors.textMuted, fontSize: 11),
                )
              : null,
        ),
      ),
    );
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(objectSearchProvider);
    final filters = searchState.filters;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: widget.colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search field row
          Row(
            children: [
              Expanded(
                child: CompositedTransformTarget(
                  link: _layerLink,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    style: TextStyle(
                        fontSize: 13, color: widget.colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search objects, names...',
                      hintStyle: TextStyle(
                          fontSize: 13, color: widget.colors.textMuted),
                      prefixIcon: Icon(LucideIcons.search,
                          size: 16, color: widget.colors.textMuted),
                      suffixIcon: Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: widget.colors.background,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '\u2318K',
                          style: TextStyle(
                              fontSize: 10, color: widget.colors.textMuted),
                        ),
                      ),
                      filled: true,
                      fillColor: widget.colors.surfaceAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: widget.colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: widget.colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: widget.colors.primary),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                    onSubmitted: (value) {
                      widget.onSearch(value);
                      _hideOverlay();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Filter toggle button
              GestureDetector(
                onTap: () => setState(() => _showFilters = !_showFilters),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: filters.hasActiveFilters
                        ? widget.colors.accent.withValues(alpha: 0.2)
                        : widget.colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: filters.hasActiveFilters
                          ? widget.colors.accent.withValues(alpha: 0.5)
                          : widget.colors.border,
                    ),
                  ),
                  child: Icon(
                    LucideIcons.slidersHorizontal,
                    size: 14,
                    color: filters.hasActiveFilters
                        ? widget.colors.accent
                        : widget.colors.textMuted,
                  ),
                ),
              ),
            ],
          ),

          // Filter controls (collapsible)
          if (_showFilters) ...[
            const SizedBox(height: 12),
            _SearchFilterControls(
              colors: widget.colors,
              filters: filters,
              onFiltersChanged: (newFilters) {
                ref
                    .read(objectSearchProvider.notifier)
                    .updateFilters(newFilters);
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Filter controls panel for search
class _SearchFilterControls extends StatelessWidget {
  final NightshadeColors colors;
  final SearchFilters filters;
  final ValueChanged<SearchFilters> onFiltersChanged;

  const _SearchFilterControls({
    required this.colors,
    required this.filters,
    required this.onFiltersChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Object type filter chips
        Text(
          'Object Type',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: SearchObjectTypeFilter.values.map((type) {
            final isSelected = filters.typeFilter == type;
            return GestureDetector(
              onTap: () => onFiltersChanged(filters.copyWith(typeFilter: type)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.accent.withValues(alpha: 0.2)
                      : colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? colors.accent : colors.border,
                  ),
                ),
                child: Text(
                  _typeFilterLabel(type),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? colors.accent : colors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // Magnitude range
        Row(
          children: [
            Text(
              'Magnitude',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
              ),
            ),
            const Spacer(),
            if (filters.maxMagnitude != null)
              GestureDetector(
                onTap: () =>
                    onFiltersChanged(filters.copyWith(clearMaxMagnitude: true)),
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.accent,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'Max:',
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: colors.accent,
                  inactiveTrackColor: colors.border,
                  thumbColor: colors.accent,
                ),
                child: Slider(
                  value: filters.maxMagnitude ?? 20.0,
                  min: 1.0,
                  max: 20.0,
                  divisions: 38,
                  onChanged: (val) =>
                      onFiltersChanged(filters.copyWith(maxMagnitude: val)),
                ),
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                filters.maxMagnitude?.toStringAsFixed(1) ?? '--',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Observable now toggle
        GestureDetector(
          onTap: () => onFiltersChanged(
              filters.copyWith(observableNow: !filters.observableNow)),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: filters.observableNow
                      ? colors.accent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color:
                        filters.observableNow ? colors.accent : colors.border,
                    width: 1.5,
                  ),
                ),
                child: filters.observableNow
                    ? Icon(LucideIcons.check, size: 12, color: colors.surface)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Observable now (>10\u00b0 alt)',
                style: TextStyle(
                  fontSize: 11,
                  color: filters.observableNow
                      ? colors.textPrimary
                      : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Constellation filter
        Row(
          children: [
            Text(
              'Constellation:',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 28,
                child: TextField(
                  style: TextStyle(fontSize: 11, color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g. Orion',
                    hintStyle: TextStyle(fontSize: 11, color: colors.textMuted),
                    filled: true,
                    fillColor: colors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.primary),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    if (val.isEmpty) {
                      onFiltersChanged(
                          filters.copyWith(clearConstellation: true));
                    } else {
                      onFiltersChanged(
                          filters.copyWith(constellationFilter: val));
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _typeFilterLabel(SearchObjectTypeFilter type) {
    switch (type) {
      case SearchObjectTypeFilter.all:
        return 'All';
      case SearchObjectTypeFilter.stars:
        return 'Stars';
      case SearchObjectTypeFilter.galaxies:
        return 'Galaxies';
      case SearchObjectTypeFilter.nebulae:
        return 'Nebulae';
      case SearchObjectTypeFilter.clusters:
        return 'Clusters';
    }
  }
}

/// Category header for grouped search results
class SearchCategoryHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final NightshadeColors colors;

  const SearchCategoryHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        border: Border(
            bottom: BorderSide(color: colors.border.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: colors.textMuted),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
