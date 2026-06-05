part of '../annotation_panel.dart';

class AnnotationObjectsPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final void Function(CelestialObjectAnnotation object) onObjectSelected;
  final String? selectedObjectId;

  const AnnotationObjectsPanel({
    super.key,
    required this.colors,
    required this.onObjectSelected,
    this.selectedObjectId,
  });

  @override
  ConsumerState<AnnotationObjectsPanel> createState() =>
      _AnnotationObjectsPanelState();
}

class _AnnotationObjectsPanelState
    extends ConsumerState<AnnotationObjectsPanel> {
  static const List<ObjectType> _filterTypes = [
    ObjectType.galaxy,
    ObjectType.nebula,
    ObjectType.planetaryNebula,
    ObjectType.starCluster,
    ObjectType.star,
    ObjectType.unknown,
  ];

  bool _filtersExpanded = false;
  String _searchQuery = '';
  bool _isReAnnotating = false;
  bool _isSaving = false;

  Future<void> _handleReAnnotate() async {
    if (_isReAnnotating) return;
    setState(() => _isReAnnotating = true);

    try {
      final annotationService = ref.read(annotationServiceProvider);
      await annotationService.reAnnotate();
    } finally {
      if (mounted) {
        setState(() => _isReAnnotating = false);
      }
    }
  }

  Future<void> _handleSaveAnnotatedImage() async {
    if (_isSaving) return;

    final annotation = ref.read(currentAnnotationProvider);
    final currentImage = ref.read(currentImageProvider);
    if (annotation == null || currentImage == null) {
      return;
    }

    final imagePath = currentImage.filePath;
    if (imagePath == null) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final settings = ref.read(annotationSettingsProvider).valueOrNull ??
          const AnnotationSettings();
      final markerStyle = ref.read(annotationMarkerStyleProvider).valueOrNull ??
          const AnnotationMarkerStyle();

      final width = currentImage.width;
      final height = currentImage.height;

      // Build a ui.Image from the CapturedImageData RGBA display buffer.
      // This works for all source formats (FITS, XISF, TIFF, PNG, etc.)
      // because displayData is always pre-processed to RGBA.
      final baseImage = await _rgbaBufferToImage(
        currentImage.displayData,
        width,
        height,
      );

      // Create a PictureRecorder to draw the composite
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // 1) Draw the base image
      canvas.drawImage(baseImage, Offset.zero, Paint());

      // 2) Draw annotation markers and labels on top using the same painter
      //    as the live overlay, but at 1:1 pixel scale (no zoom/offset).
      final painter = EnhancedAnnotationPainter(
        annotation: annotation,
        settings: settings,
        markerStyle: markerStyle,
        zoomLevel: 1.0,
        imageOffset: Offset.zero,
      );
      painter.paint(canvas, Size(width.toDouble(), height.toDouble()));

      // Finish recording
      final picture = recorder.endRecording();
      final compositeImage = await picture.toImage(width, height);
      final pngData =
          await compositeImage.toByteData(format: ui.ImageByteFormat.png);

      if (pngData == null) {
        throw StateError('Failed to encode annotated image as PNG');
      }

      // Build save path: original_annotated.png next to the original file
      final dir = p.dirname(imagePath);
      final baseName = p.basenameWithoutExtension(imagePath);
      final savePath = p.join(dir, '${baseName}_annotated.png');

      final outFile = File(savePath);
      await outFile.writeAsBytes(pngData.buffer.asUint8List());

      // Clean up native resources
      baseImage.dispose();
      compositeImage.dispose();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Annotated image saved to $savePath'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save annotated image: $e'),
            backgroundColor: NightshadeColors.of(context).error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Convert an RGBA pixel buffer to a [ui.Image].
  Future<ui.Image> _rgbaBufferToImage(
    Uint8List rgbaBytes,
    int width,
    int height,
  ) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaBytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Future<void> _exportCsv(List<CelestialObjectAnnotation> objects) async {
    if (objects.isEmpty) return;
    final timestamp = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());
    final csv = generateAnnotationCsv(objects);
    final path = await _saveExportFile(
      suggestedName: 'annotations_$timestamp.csv',
      content: csv,
      label: 'CSV files',
      extensions: ['csv'],
    );
    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Annotations exported to $path'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _exportDs9(List<CelestialObjectAnnotation> objects) async {
    if (objects.isEmpty) return;
    final timestamp = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());
    final reg = generateDs9RegionFile(objects);
    final path = await _saveExportFile(
      suggestedName: 'annotations_$timestamp.reg',
      content: reg,
      label: 'DS9 region files',
      extensions: ['reg'],
    );
    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('DS9 regions exported to $path'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final annotation = ref.watch(currentAnnotationProvider);
    final settings = ref.watch(annotationSettingsProvider).valueOrNull ??
        const AnnotationSettings();
    final sortMode = ref.watch(annotationPanelSortModeProvider);
    final objects = annotation?.objects ?? [];

    final typeCounts = <ObjectType, int>{};
    for (final obj in objects) {
      typeCounts[obj.type] = (typeCounts[obj.type] ?? 0) + 1;
    }

    // Apply visibility rules consistent with overlay rendering.
    final displayableObjects = objects.where((obj) {
      if (!obj.visible) return false;
      if (!isTypeVisibleFromSettings(obj.type, settings.visibleTypes)) {
        return false;
      }
      if (obj.magnitude != null) {
        if (obj.magnitude! > settings.magnitudeCutoff) return false;
        if (obj.magnitude! < settings.minMagnitude) return false;
      }
      return true;
    }).toList();

    // Apply search filter on top of display filters.
    final filteredObjects = displayableObjects.where((obj) {
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final nameMatch = obj.name.toLowerCase().contains(query);
        final commonNameMatch =
            obj.commonName?.toLowerCase().contains(query) ?? false;
        final catalogMatch =
            obj.catalogId?.toLowerCase().contains(query) ?? false;
        if (!nameMatch && !commonNameMatch && !catalogMatch) return false;
      }
      return true;
    }).toList();

    switch (sortMode) {
      case AnnotationPanelSortMode.brightness:
        filteredObjects.sort((a, b) {
          final aMag = a.magnitude ?? 99.0;
          final bMag = b.magnitude ?? 99.0;
          final magCompare = aMag.compareTo(bMag);
          if (magCompare != 0) return magCompare;
          return a.name.compareTo(b.name);
        });
      case AnnotationPanelSortMode.name:
        filteredObjects.sort((a, b) => a.name.compareTo(b.name));
      case AnnotationPanelSortMode.type:
        filteredObjects.sort((a, b) {
          final typeCompare = _getObjectTypeLabel(a.type)
              .compareTo(_getObjectTypeLabel(b.type));
          if (typeCompare != 0) return typeCompare;
          return (a.magnitude ?? 99.0).compareTo(b.magnitude ?? 99.0);
        });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = Responsive.previewOverlayMaxWidth(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width,
          maxAbsolute: 320,
        );
        return SizedBox(
          width: panelWidth,
          child: _buildPanelContent(
            annotation,
            filteredObjects,
            displayableObjects,
            settings,
            typeCounts,
          ),
        );
      },
    );
  }

  Widget _buildPanelContent(
    ImageAnnotation? annotation,
    List<CelestialObjectAnnotation> filteredObjects,
    List<CelestialObjectAnnotation> displayableObjects,
    AnnotationSettings settings,
    Map<ObjectType, int> typeCounts,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: widget.colors.surface,
        border: Border(
          left: BorderSide(color: widget.colors.border),
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(annotation, filteredObjects, displayableObjects),

          // Search bar
          AnnotationSearchBar(
            onChanged: (value) => setState(() => _searchQuery = value),
          ),

          // Filters section
          _buildFiltersSection(settings, typeCounts),

          Divider(height: 1, color: widget.colors.border),

          // Objects list
          Expanded(
            child: filteredObjects.isEmpty
                ? _buildEmptyState(annotation)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    // AnnotationObjectListItem fixed height: 28 icon +
                    // 8*2 vertical padding + 1 bottom border = 45.
                    itemExtent: 45,
                    itemCount: filteredObjects.length,
                    itemBuilder: (context, index) {
                      final object = filteredObjects[index];
                      return AnnotationObjectListItem(
                        object: object,
                        colors: widget.colors,
                        onTap: () => widget.onObjectSelected(object),
                        isSelected: widget.selectedObjectId == object.id,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    ImageAnnotation? annotation,
    List<CelestialObjectAnnotation> filteredObjects,
    List<CelestialObjectAnnotation> displayableObjects,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        border: Border(
          bottom: BorderSide(color: widget.colors.border),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.sparkle,
            size: 16,
            color: widget.colors.primary,
          ),
          const SizedBox(width: 8),
          Text(
            'Detected Objects',
            style: TextStyle(
              color: widget.colors.textPrimary,
              fontSize: NightshadeTypography.fontSize13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Object count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: NightshadeDecorations.tintedBadge(
              widget.colors.primary,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
            ),
            child: Text(
              '${filteredObjects.length}/${displayableObjects.length}',
              style: TextStyle(
                color: widget.colors.primary,
                fontSize: NightshadeTypography.fontSize11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<AnnotationPanelSortMode>(
            tooltip: 'Sort objects',
            color: widget.colors.surfaceElevated,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shape: _annotationMenuShape(widget.colors),
            onSelected: (value) => ref
                .read(annotationPanelSortModeProvider.notifier)
                .state = value,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: AnnotationPanelSortMode.brightness,
                child: Text(
                  'Sort: Brightness',
                  style:
                      TextStyle(color: widget.colors.textPrimary, fontSize: NightshadeTypography.fontSize12),
                ),
              ),
              PopupMenuItem(
                value: AnnotationPanelSortMode.name,
                child: Text(
                  'Sort: Name',
                  style:
                      TextStyle(color: widget.colors.textPrimary, fontSize: NightshadeTypography.fontSize12),
                ),
              ),
              PopupMenuItem(
                value: AnnotationPanelSortMode.type,
                child: Text(
                  'Sort: Type',
                  style:
                      TextStyle(color: widget.colors.textPrimary, fontSize: NightshadeTypography.fontSize12),
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                LucideIcons.arrowUpDown,
                size: 14,
                color: widget.colors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Re-annotate button
          _isReAnnotating
              ? const Padding(
                  padding: EdgeInsets.all(4),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : InkWell(
                  onTap: _handleReAnnotate,
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                  child: Tooltip(
                    message: 'Re-annotate image',
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        LucideIcons.refreshCw,
                        size: 14,
                        color: widget.colors.textMuted,
                      ),
                    ),
                  ),
                ),
          const SizedBox(width: 4),
          // Save annotated image button
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(4),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : InkWell(
                  onTap: annotation != null ? _handleSaveAnnotatedImage : null,
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                  child: Tooltip(
                    message: 'Save annotated image',
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        LucideIcons.download,
                        size: 14,
                        color: annotation != null
                            ? widget.colors.textMuted
                            : widget.colors.textMuted.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
          const SizedBox(width: 4),
          // Export menu
          PopupMenuButton<String>(
            tooltip: 'Export annotations',
            color: widget.colors.surfaceElevated,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shape: _annotationMenuShape(widget.colors),
            enabled: displayableObjects.isNotEmpty,
            onSelected: (value) {
              switch (value) {
                case 'csv':
                  unawaited(_exportCsv(displayableObjects));
                case 'ds9':
                  unawaited(_exportDs9(displayableObjects));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'csv',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.fileSpreadsheet,
                        size: 14, color: widget.colors.textPrimary),
                    const SizedBox(width: 8),
                    Text('Export CSV',
                        style: TextStyle(
                            color: widget.colors.textPrimary, fontSize: NightshadeTypography.fontSize12)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'ds9',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.map,
                        size: 14, color: widget.colors.textPrimary),
                    const SizedBox(width: 8),
                    Text('Export DS9 Regions',
                        style: TextStyle(
                            color: widget.colors.textPrimary, fontSize: NightshadeTypography.fontSize12)),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                LucideIcons.fileOutput,
                size: 14,
                color: displayableObjects.isNotEmpty
                    ? widget.colors.textMuted
                    : widget.colors.textMuted.withValues(alpha: 0.3),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Close button
          InkWell(
            onTap: () =>
                ref.read(annotationPanelVisibleProvider.notifier).state = false,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                LucideIcons.x,
                size: 16,
                color: widget.colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersSection(
    AnnotationSettings settings,
    Map<ObjectType, int> typeCounts,
  ) {
    return ExpansionTile(
      initiallyExpanded: _filtersExpanded,
      onExpansionChanged: (expanded) =>
          setState(() => _filtersExpanded = expanded),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      dense: true,
      title: Text(
        'Filters',
        style: TextStyle(
          color: widget.colors.textSecondary,
          fontSize: NightshadeTypography.fontSize12,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Icon(
        _filtersExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
        size: 16,
        color: widget.colors.textMuted,
      ),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            AnnotationQuickSettingChip(
              label:
                  settings.visibleTypes.contains(AnnotationObjectFilter.stars)
                      ? 'Stars On'
                      : 'Stars Off',
              isSelected:
                  settings.visibleTypes.contains(AnnotationObjectFilter.stars),
              colors: widget.colors,
              onTap: () {
                unawaited(
                  ref
                      .read(annotationSettingsProvider.notifier)
                      .toggleObjectType(AnnotationObjectFilter.stars),
                );
              },
            ),
            AnnotationQuickSettingChip(
              label: settings.showLabels ? 'Labels On' : 'Labels Off',
              isSelected: settings.showLabels,
              colors: widget.colors,
              onTap: () {
                unawaited(
                  ref
                      .read(annotationSettingsProvider.notifier)
                      .setShowLabels(!settings.showLabels),
                );
              },
            ),
            AnnotationQuickSettingChip(
              label: settings.showMagnitudes ? 'Mag On' : 'Mag Off',
              isSelected: settings.showMagnitudes,
              colors: widget.colors,
              onTap: () {
                unawaited(
                  ref
                      .read(annotationSettingsProvider.notifier)
                      .setShowMagnitudes(!settings.showMagnitudes),
                );
              },
            ),
            AnnotationQuickSettingChip(
              label: settings.compassEnabled ? 'Compass On' : 'Compass Off',
              isSelected: settings.compassEnabled,
              colors: widget.colors,
              onTap: () {
                unawaited(
                  ref
                      .read(annotationSettingsProvider.notifier)
                      .setCompassEnabled(!settings.compassEnabled),
                );
              },
            ),
            AnnotationQuickSettingChip(
              label:
                  settings.scaleBarEnabled ? 'Scale Bar On' : 'Scale Bar Off',
              isSelected: settings.scaleBarEnabled,
              colors: widget.colors,
              onTap: () {
                unawaited(
                  ref
                      .read(annotationSettingsProvider.notifier)
                      .setScaleBarEnabled(!settings.scaleBarEnabled),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: _filterTypes.map((type) {
            final isSelected =
                isTypeVisibleFromSettings(type, settings.visibleTypes);
            final count = _countForFilterType(type, typeCounts);
            return AnnotationFilterChip(
              label: _getObjectTypeLabel(type),
              count: count,
              isSelected: isSelected,
              colors: widget.colors,
              onTap: () {
                final notifier = ref.read(annotationSettingsProvider.notifier);
                final updated =
                    Set<AnnotationObjectFilter>.from(settings.visibleTypes);
                final typeFilters = filtersForObjectType(type);
                if (isSelected) {
                  updated.removeAll(typeFilters);
                } else {
                  updated.addAll(typeFilters);
                }
                unawaited(notifier.setObjectTypes(updated));
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: NightshadeButton(
            onPressed: () {
              unawaited(
                ref.read(annotationSettingsProvider.notifier).setObjectTypes(
                  {
                    AnnotationObjectFilter.galaxies,
                    AnnotationObjectFilter.nebulae,
                    AnnotationObjectFilter.starClusters,
                    AnnotationObjectFilter.planetaryNebulae,
                  },
                ),
              );
            },
            label: 'Reset to defaults',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildEmptyState(ImageAnnotation? annotation) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            annotation == null ? LucideIcons.sparkle : LucideIcons.searchX,
            size: 32,
            color: widget.colors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            annotation == null
                ? 'No image annotated'
                : _searchQuery.isNotEmpty
                    ? 'No matching objects'
                    : 'No objects match filters',
            style: TextStyle(
              color: widget.colors.textMuted,
              fontSize: NightshadeTypography.fontSize13,
            ),
          ),
        ],
      ),
    );
  }

  String _getObjectTypeLabel(ObjectType type) {
    switch (type) {
      case ObjectType.galaxy:
        return 'Galaxies';
      case ObjectType.nebula:
        return 'Nebulae';
      case ObjectType.starCluster:
        return 'Clusters';
      case ObjectType.planetaryNebula:
        return 'PN';
      case ObjectType.star:
        return 'Stars';
      case ObjectType.doubleStar:
        return 'Stars';
      case ObjectType.asterism:
        return 'Asterisms';
      case ObjectType.unknown:
        return 'Other';
    }
  }

  int _countForFilterType(ObjectType type, Map<ObjectType, int> typeCounts) {
    if (type == ObjectType.star) {
      return (typeCounts[ObjectType.star] ?? 0) +
          (typeCounts[ObjectType.doubleStar] ?? 0);
    }
    if (type == ObjectType.unknown) {
      return (typeCounts[ObjectType.unknown] ?? 0) +
          (typeCounts[ObjectType.asterism] ?? 0);
    }
    return typeCounts[type] ?? 0;
  }
}

/// Annotation panel adapted for use as a tab in the imaging panel tabs.
/// Contains object list, filters, search, re-annotate and save buttons.
