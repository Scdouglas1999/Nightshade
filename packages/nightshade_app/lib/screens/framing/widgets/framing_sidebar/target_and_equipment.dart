part of '../framing_sidebar.dart';

/// Target search section: SIMBAD-backed name search, results dropdown, and
/// manual RA/Dec entry fields. The controllers are owned by the parent screen
/// so navigating away and back preserves the input state.
class FramingTargetSearch extends ConsumerWidget {
  final NightshadeColors colors;
  final TargetSearchState searchState;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final TextEditingController raController;
  final TextEditingController decController;
  final ValueChanged<FramingTarget> onTargetSelected;
  final ValueChanged<String> onResolveByName;
  final VoidCallback onGoToManualCoordinates;

  const FramingTargetSearch({
    super.key,
    required this.colors,
    required this.searchState,
    required this.searchController,
    required this.searchFocusNode,
    required this.raController,
    required this.decController,
    required this.onTargetSelected,
    required this.onResolveByName,
    required this.onGoToManualCoordinates,
  });

  IconData _iconForType(TargetType? type) {
    switch (type) {
      case TargetType.galaxy:
        return LucideIcons.circle;
      case TargetType.nebula:
        return LucideIcons.cloud;
      case TargetType.cluster:
        return LucideIcons.sparkles;
      case TargetType.star:
        return LucideIcons.star;
      case TargetType.planet:
        return LucideIcons.globe;
      default:
        return LucideIcons.target;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Target',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: FramingTutorialKeys.targetSearch,
            controller: searchController,
            focusNode: searchFocusNode,
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search by name (M42, NGC7000, Orion)',
              hintStyle: TextStyle(fontSize: 12, color: colors.textMuted),
              prefixIcon:
                  Icon(LucideIcons.search, size: 14, color: colors.textMuted),
              suffixIcon: searchState.isSearching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(LucideIcons.x,
                              size: 14, color: colors.textMuted),
                          onPressed: () {
                            searchController.clear();
                            ref.read(targetSearchProvider.notifier).clear();
                          },
                        )
                      : null,
              filled: true,
              fillColor: colors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.primary),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (value) {
              ref.read(targetSearchProvider.notifier).search(value);
            },
            onSubmitted: (value) {
              if (searchState.results.isNotEmpty) {
                onTargetSelected(searchState.results.first);
              } else if (value.isNotEmpty) {
                onResolveByName(value);
              }
            },
          ),

          // Search results dropdown
          if (searchState.results.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: searchState.results.length,
                itemBuilder: (context, index) {
                  final target = searchState.results[index];
                  return InkWell(
                    onTap: () => onTargetSelected(target),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            _iconForType(target.type),
                            size: 14,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  target.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                if (target.catalogId != null &&
                                    target.catalogId != target.name)
                                  Text(
                                    target.catalogId!,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (target.magnitude != null)
                            Text(
                              'mag ${target.magnitude!.toStringAsFixed(1)}',
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // Manual coordinate entry
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: raController,
                  style: TextStyle(fontSize: 11, color: colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'RA',
                    labelStyle:
                        TextStyle(fontSize: 10, color: colors.textMuted),
                    hintText: '05h 35m 17s',
                    hintStyle: TextStyle(fontSize: 10, color: colors.textMuted),
                    filled: true,
                    fillColor: colors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: decController,
                  style: TextStyle(fontSize: 11, color: colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Dec',
                    labelStyle:
                        TextStyle(fontSize: 10, color: colors.textMuted),
                    hintText: '-05° 23\' 28"',
                    hintStyle: TextStyle(fontSize: 10, color: colors.textMuted),
                    filled: true,
                    fillColor: colors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FramingSmallIconButton(
                icon: LucideIcons.arrowRight,
                tooltip: 'Go to coordinates',
                colors: colors,
                onTap: onGoToManualCoordinates,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Equipment summary section in the sidebar: status badge plus a context card
/// for the current `EquipmentStatus` (noProfile / noFocalLength /
/// noCameraSpecs / ready) and a warning for default sensor specs.
class FramingEquipmentSection extends StatelessWidget {
  final NightshadeColors colors;
  final AsyncValue<FramingEquipmentResult> equipmentAsync;

  const FramingEquipmentSection({
    super.key,
    required this.colors,
    required this.equipmentAsync,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Equipment',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            equipmentAsync.when(
              data: (result) {
                if (result.isReady) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.checkCircle,
                          size: 12, color: colors.success),
                      const SizedBox(width: 4),
                      Text(
                        result.profileName ?? 'Ready',
                        style: TextStyle(fontSize: 10, color: colors.success),
                      ),
                    ],
                  );
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.alertCircle,
                        size: 12, color: colors.warning),
                    const SizedBox(width: 4),
                    Text(
                      'Not Configured',
                      style: TextStyle(fontSize: 10, color: colors.warning),
                    ),
                  ],
                );
              },
              loading: () => const SizedBox(),
              error: (error, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.alertCircle, size: 12, color: colors.error),
                  const SizedBox(width: 4),
                  Text(
                    'Error',
                    style: TextStyle(fontSize: 10, color: colors.error),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        equipmentAsync.when(
          data: (result) {
            switch (result.status) {
              case EquipmentStatus.noProfile:
                return FramingEquipmentWarningCard(
                  colors: colors,
                  icon: LucideIcons.settings,
                  title: 'No Equipment Profile',
                  message:
                      'Create and activate an equipment profile in Settings → Equipment to enable framing preview.',
                  actionLabel: 'Open Settings',
                  onAction: () {
                    // Navigate to settings
                  },
                );

              case EquipmentStatus.noFocalLength:
                return FramingEquipmentWarningCard(
                  colors: colors,
                  icon: LucideIcons.focus,
                  title: 'Optical Specs Missing',
                  message:
                      'Set the focal length in profile "${result.profileName}" to enable FOV preview.',
                  actionLabel: 'Edit Profile',
                  onAction: () {
                    // Navigate to profile editor
                  },
                );

              case EquipmentStatus.noCameraSpecs:
                return FramingEquipmentWarningCard(
                  colors: colors,
                  icon: LucideIcons.camera,
                  title: 'Camera Not Configured',
                  message:
                      'Connect a camera or configure camera specs to enable accurate FOV preview.',
                  actionLabel: null,
                  onAction: null,
                );

              case EquipmentStatus.ready:
                final equipment = result.equipment!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FramingInfoRow(
                      label: 'Camera',
                      value: equipment.cameraName,
                      colors: colors,
                    ),
                    const SizedBox(height: 6),
                    FramingInfoRow(
                      label: 'Telescope',
                      value:
                          '${equipment.effectiveFocalLength.round()}mm f/${equipment.focalRatio.toStringAsFixed(1)}',
                      colors: colors,
                    ),
                    if (result.message != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: NightshadeDecorations.emphasisSurface(
                          colors.warning,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.info,
                                size: 12, color: colors.warning),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                result.message!,
                                style: TextStyle(
                                    fontSize: 10, color: colors.warning),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
            }
          },
          loading: () => const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => FramingEquipmentWarningCard(
            colors: colors,
            icon: LucideIcons.alertTriangle,
            title: 'Error Loading Equipment',
            message: e.toString(),
            actionLabel: null,
            onAction: null,
          ),
        ),
      ],
    );
  }
}
