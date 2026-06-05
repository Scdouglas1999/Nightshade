part of '../annotation_panel.dart';

class AnnotationTabPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const AnnotationTabPanel({super.key, required this.colors});

  @override
  ConsumerState<AnnotationTabPanel> createState() => _AnnotationTabPanelState();
}

class _AnnotationTabPanelState extends ConsumerState<AnnotationTabPanel> {
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

      final baseImage = await _rgbaBufferToImage(
        currentImage.displayData,
        width,
        height,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      canvas.drawImage(baseImage, Offset.zero, Paint());

      final painter = EnhancedAnnotationPainter(
        annotation: annotation,
        settings: settings,
        markerStyle: markerStyle,
        zoomLevel: 1.0,
        imageOffset: Offset.zero,
      );
      painter.paint(canvas, Size(width.toDouble(), height.toDouble()));

      final picture = recorder.endRecording();
      final compositeImage = await picture.toImage(width, height);
      final pngData =
          await compositeImage.toByteData(format: ui.ImageByteFormat.png);

      if (pngData == null) {
        throw StateError('Failed to encode annotated image as PNG');
      }

      final dir = p.dirname(imagePath);
      final baseName = p.basenameWithoutExtension(imagePath);
      final savePath = p.join(dir, '${baseName}_annotated.png');

      final outFile = File(savePath);
      await outFile.writeAsBytes(pngData.buffer.asUint8List());

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

  void _onObjectSelected(CelestialObjectAnnotation object) {
    ref.read(selectedAnnotationObjectProvider.notifier).state = object;
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

  Future<void> _saveAsPreset() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _PresetNameDialog(),
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      await ref
          .read(annotationPresetsProvider.notifier)
          .saveCurrentAsPreset(name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Preset "$name" saved'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save preset: $e'),
            backgroundColor: NightshadeColors.of(context).error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _applyPreset(String name) async {
    try {
      // Search both built-in and user presets
      final userPresets =
          ref.read(annotationPresetsProvider).valueOrNull ?? const [];
      final allPresets = [...builtInAnnotationPresets, ...userPresets];
      final preset = allPresets.where((p) => p.name == name).firstOrNull;
      if (preset == null) {
        throw StateError('Preset "$name" not found');
      }
      await ref.read(annotationSettingsProvider.notifier).applyPreset(preset);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to apply preset: $e'),
            backgroundColor: NightshadeColors.of(context).error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _deletePreset(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => NightshadeDialog(
        title: 'Delete Preset',
        icon: LucideIcons.trash2,
        width: 420,
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            label: 'Cancel',
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: 'Delete',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
          ),
        ],
        child: Text('Delete preset "$name"? This cannot be undone.'),
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(annotationPresetsProvider.notifier).deletePreset(name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Preset "$name" deleted'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete preset: $e'),
            backgroundColor: NightshadeColors.of(context).error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final annotation = ref.watch(currentAnnotationProvider);
    final settings = ref.watch(annotationSettingsProvider).valueOrNull ??
        const AnnotationSettings();
    final sortMode = ref.watch(annotationPanelSortModeProvider);
    final selectedObject = ref.watch(selectedAnnotationObjectProvider);
    final presetsAsync = ref.watch(annotationPresetsProvider);
    final presets = [
      ...builtInAnnotationPresets,
      ...(presetsAsync.valueOrNull ?? const [])
    ];
    final objects = annotation?.objects ?? [];

    final typeCounts = <ObjectType, int>{};
    for (final obj in objects) {
      typeCounts[obj.type] = (typeCounts[obj.type] ?? 0) + 1;
    }

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

    return Column(
      children: [
        // Toolbar row with actions
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: widget.colors.border),
            ),
          ),
          child: Row(
            children: [
              // Object count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: NightshadeDecorations.tintedBadge(
                  widget.colors.primary,
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
                ),
                child: Text(
                  '${filteredObjects.length}/${displayableObjects.length} objects',
                  style: TextStyle(
                    color: widget.colors.primary,
                    fontSize: NightshadeTypography.fontSize11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              // Sort menu
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
                      style: TextStyle(
                          color: widget.colors.textPrimary, fontSize: NightshadeTypography.fontSize12),
                    ),
                  ),
                  PopupMenuItem(
                    value: AnnotationPanelSortMode.name,
                    child: Text(
                      'Sort: Name',
                      style: TextStyle(
                          color: widget.colors.textPrimary, fontSize: NightshadeTypography.fontSize12),
                    ),
                  ),
                  PopupMenuItem(
                    value: AnnotationPanelSortMode.type,
                    child: Text(
                      'Sort: Type',
                      style: TextStyle(
                          color: widget.colors.textPrimary, fontSize: NightshadeTypography.fontSize12),
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
                      onTap:
                          annotation != null ? _handleSaveAnnotatedImage : null,
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
                                : widget.colors.textMuted
                                    .withValues(alpha: 0.3),
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
                      children: [
                        Icon(LucideIcons.fileSpreadsheet,
                            size: 14, color: widget.colors.textPrimary),
                        const SizedBox(width: 8),
                        Text('Export CSV',
                            style: TextStyle(
                                color: widget.colors.textPrimary,
                                fontSize: NightshadeTypography.fontSize12)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'ds9',
                    child: Row(
                      children: [
                        Icon(LucideIcons.map,
                            size: 14, color: widget.colors.textPrimary),
                        const SizedBox(width: 8),
                        Text('Export DS9 Regions',
                            style: TextStyle(
                                color: widget.colors.textPrimary,
                                fontSize: NightshadeTypography.fontSize12)),
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
              // Presets menu
              PopupMenuButton<String>(
                tooltip: 'Annotation presets',
                color: widget.colors.surfaceElevated,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                shape: _annotationMenuShape(widget.colors),
                onSelected: (value) {
                  if (value == '_save_as_preset') {
                    unawaited(_saveAsPreset());
                  } else if (value.startsWith('_delete:')) {
                    unawaited(_deletePreset(value.substring(8)));
                  } else {
                    unawaited(_applyPreset(value));
                  }
                },
                itemBuilder: (context) {
                  final items = <PopupMenuEntry<String>>[];
                  for (final preset in presets) {
                    items.add(PopupMenuItem(
                      value: preset.name,
                      child: Row(
                        children: [
                          Icon(
                            preset.isBuiltIn
                                ? LucideIcons.bookmark
                                : LucideIcons.user,
                            size: 14,
                            color: widget.colors.textPrimary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              preset.name,
                              style: TextStyle(
                                color: widget.colors.textPrimary,
                                fontSize: NightshadeTypography.fontSize12,
                              ),
                            ),
                          ),
                          if (!preset.isBuiltIn)
                            InkWell(
                              onTap: () {
                                Navigator.of(context).pop();
                                unawaited(_deletePreset(preset.name));
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  LucideIcons.trash2,
                                  size: 12,
                                  color: widget.colors.textMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ));
                  }
                  items.add(const PopupMenuDivider());
                  items.add(PopupMenuItem(
                    value: '_save_as_preset',
                    child: Row(
                      children: [
                        Icon(LucideIcons.save,
                            size: 14, color: widget.colors.primary),
                        const SizedBox(width: 8),
                        Text('Save as Preset',
                            style: TextStyle(
                                color: widget.colors.primary, fontSize: NightshadeTypography.fontSize12)),
                      ],
                    ),
                  ));
                  return items;
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    LucideIcons.layoutTemplate,
                    size: 14,
                    color: widget.colors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Search bar
        AnnotationSearchBar(
          onChanged: (value) => setState(() => _searchQuery = value),
        ),

        // Filters section
        ExpansionTile(
          initiallyExpanded: _filtersExpanded,
          onExpansionChanged: (expanded) =>
              setState(() => _filtersExpanded = expanded),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                  label: settings.visibleTypes
                          .contains(AnnotationObjectFilter.stars)
                      ? 'Stars On'
                      : 'Stars Off',
                  isSelected: settings.visibleTypes
                      .contains(AnnotationObjectFilter.stars),
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
                  label: settings.scaleBarEnabled
                      ? 'Scale Bar On'
                      : 'Scale Bar Off',
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
                AnnotationQuickSettingChip(
                  label: settings.showSolveResiduals
                      ? 'Residuals On'
                      : 'Residuals Off',
                  isSelected: settings.showSolveResiduals,
                  colors: widget.colors,
                  onTap: () {
                    unawaited(
                      ref
                          .read(annotationSettingsProvider.notifier)
                          .setShowSolveResiduals(!settings.showSolveResiduals),
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
                    final notifier =
                        ref.read(annotationSettingsProvider.notifier);
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
                    ref
                        .read(annotationSettingsProvider.notifier)
                        .setObjectTypes(
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
        ),

        Divider(height: 1, color: widget.colors.border),

        // Annotation status indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: AnnotationStatusIndicator(colors: widget.colors),
        ),

        // Objects list
        Expanded(
          child: filteredObjects.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        annotation == null
                            ? LucideIcons.sparkle
                            : LucideIcons.searchX,
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
                      if (annotation == null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Capture an image to see detected objects',
                          style: TextStyle(
                            color:
                                widget.colors.textMuted.withValues(alpha: 0.7),
                            fontSize: NightshadeTypography.fontSize11,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
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
                      onTap: () => _onObjectSelected(object),
                      isSelected: selectedObject?.id == object.id,
                    );
                  },
                ),
        ),
      ],
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

/// Floating chip row showing the brightest annotated objects on the image.
/// Always visible regardless of annotation fade settings.
/// Tapping a chip selects that object in the annotation panel.
