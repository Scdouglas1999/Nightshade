import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;
import '../../../widgets/annotation_overlay.dart';
import '../imaging_science_state.dart';
import 'annotation_filters.dart';
import 'panel_widgets.dart';
import 'annotation_search.dart';
import 'annotation_quick_settings.dart';
import 'annotation_object_list.dart';

// ---------------------------------------------------------------------------
// Export helpers
// ---------------------------------------------------------------------------

String _objectTypeName(ObjectType type) {
  switch (type) {
    case ObjectType.galaxy:
      return 'Galaxy';
    case ObjectType.nebula:
      return 'Nebula';
    case ObjectType.starCluster:
      return 'Star Cluster';
    case ObjectType.planetaryNebula:
      return 'Planetary Nebula';
    case ObjectType.star:
      return 'Star';
    case ObjectType.doubleStar:
      return 'Double Star';
    case ObjectType.asterism:
      return 'Asterism';
    case ObjectType.unknown:
      return 'Unknown';
  }
}

/// Generate CSV content from a list of annotated objects.
/// Columns: name, catalogId, type, ra_hours, dec_degrees, magnitude, size_arcmin
String generateAnnotationCsv(List<CelestialObjectAnnotation> objects) {
  final buf = StringBuffer();
  buf.writeln('name,catalogId,type,ra_hours,dec_degrees,magnitude,size_arcmin');
  for (final obj in objects) {
    final name = _csvEscape(obj.commonName ?? obj.name);
    final catalogId = _csvEscape(obj.catalogId ?? '');
    final type = _csvEscape(_objectTypeName(obj.type));
    // RA is stored in degrees; convert to hours (degrees / 15)
    final raHours = (obj.ra / 15.0).toStringAsFixed(8);
    final dec = obj.dec.toStringAsFixed(6);
    final mag = obj.magnitude?.toStringAsFixed(2) ?? '';
    final size = obj.size?.toStringAsFixed(2) ?? '';
    buf.writeln('$name,$catalogId,$type,$raHours,$dec,$mag,$size');
  }
  return buf.toString();
}

String _csvEscape(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// Generate a DS9 region file (FK5) from a list of annotated objects.
String generateDs9RegionFile(List<CelestialObjectAnnotation> objects) {
  final buf = StringBuffer();
  buf.writeln('# Region file format: DS9 version 4.1');
  buf.writeln('global color=green dashlist=8 3 width=1');
  buf.writeln('fk5');
  for (final obj in objects) {
    // RA stored in degrees — DS9 FK5 uses degrees for RA and Dec
    final raDeg = obj.ra.toStringAsFixed(4);
    final decDeg = obj.dec.toStringAsFixed(4);
    // Radius: use object size if available, otherwise default to 1 arcmin
    final radiusArcmin =
        obj.size != null && obj.size! > 0 ? obj.size! / 2.0 : 1.0;
    final radiusStr = "${radiusArcmin.toStringAsFixed(1)}'";
    final label = obj.commonName ?? obj.name;
    buf.writeln('circle($raDeg,$decDeg,$radiusStr) # text={$label}');
  }
  return buf.toString();
}

/// Show a file save dialog and write [content] to the chosen path.
/// Returns the saved path, or null if the user cancelled.
Future<String?> _saveExportFile({
  required String suggestedName,
  required String content,
  required String label,
  required List<String> extensions,
}) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [
      XTypeGroup(label: label, extensions: extensions),
    ],
  );
  if (location == null) return null;

  final file = File(location.path);
  await file.writeAsString(content);
  return location.path;
}

/// Provider for the annotation sidebar panel visibility state
final annotationPanelVisibleProvider = StateProvider<bool>((ref) => false);

enum AnnotationPanelSortMode { brightness, name, type }

final annotationPanelSortModeProvider =
    StateProvider<AnnotationPanelSortMode>((ref) {
  return AnnotationPanelSortMode.brightness;
});

/// Banner shown when annotation catalog is not installed
class AnnotationCatalogBanner extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onDismiss;
  final VoidCallback onSetup;

  const AnnotationCatalogBanner({
    super.key,
    required this.colors,
    required this.onDismiss,
    required this.onSetup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(color: colors.primary.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 16, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Annotations are enabled but no catalog is installed. Download the annotation catalog to identify objects in your images.',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 16),
          NightshadeButton(
            onPressed: onSetup,
            label: 'Setup',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          IconButton(
            icon: Icon(LucideIcons.x, size: 16, color: colors.textMuted),
            onPressed: onDismiss,
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// Status indicator for the live annotation pipeline
class AnnotationStatusIndicator extends ConsumerWidget {
  final NightshadeColors colors;

  const AnnotationStatusIndicator({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotationState = ref.watch(annotationStateProvider);
    final annotationSettings =
        ref.watch(annotationSettingsProvider).valueOrNull;
    final secondaryMessage =
        annotationState.errorDetails ?? _getActionHint(annotationState.status);

    // Don't show anything if annotations are disabled
    if (annotationSettings != null && !annotationSettings.enabled) {
      return const SizedBox.shrink();
    }

    // Don't show idle state (reduces visual clutter)
    if (annotationState.status == AnnotationStatus.idle) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _getBackgroundColor(annotationState.status),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _getBorderColor(annotationState.status),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _getStatusIcon(annotationState.status),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  annotationState.message ??
                      _getStatusText(annotationState.status),
                  style: TextStyle(
                    color: _getTextColor(annotationState.status),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (secondaryMessage != null)
                  Text(
                    secondaryMessage,
                    style: TextStyle(
                      color: _getTextColor(annotationState.status)
                          .withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getBackgroundColor(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.checkingCatalogs:
      case AnnotationStatus.plateSolving:
      case AnnotationStatus.searchingCatalogs:
        return const Color(0xFF1E3A5F)
            .withValues(alpha: 0.9); // Blue for processing
      case AnnotationStatus.complete:
        return const Color(0xFF1E4620)
            .withValues(alpha: 0.9); // Green for success
      case AnnotationStatus.error:
      case AnnotationStatus.plateSolveFailed:
        return const Color(0xFF5F1E1E).withValues(alpha: 0.9); // Red for error
      case AnnotationStatus.catalogsNotInstalled:
        return const Color(0xFF5F4D1E)
            .withValues(alpha: 0.9); // Orange for warning
      case AnnotationStatus.idle:
        return Colors.transparent;
    }
  }

  Color _getBorderColor(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.checkingCatalogs:
      case AnnotationStatus.plateSolving:
      case AnnotationStatus.searchingCatalogs:
        return const Color(0xFF3B82F6).withValues(alpha: 0.5);
      case AnnotationStatus.complete:
        return const Color(0xFF22C55E).withValues(alpha: 0.5);
      case AnnotationStatus.error:
      case AnnotationStatus.plateSolveFailed:
        return const Color(0xFFEF4444).withValues(alpha: 0.5);
      case AnnotationStatus.catalogsNotInstalled:
        return const Color(0xFFF59E0B).withValues(alpha: 0.5);
      case AnnotationStatus.idle:
        return Colors.transparent;
    }
  }

  Color _getTextColor(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.checkingCatalogs:
      case AnnotationStatus.plateSolving:
      case AnnotationStatus.searchingCatalogs:
        return const Color(0xFF93C5FD);
      case AnnotationStatus.complete:
        return const Color(0xFF86EFAC);
      case AnnotationStatus.error:
      case AnnotationStatus.plateSolveFailed:
        return const Color(0xFFFCA5A5);
      case AnnotationStatus.catalogsNotInstalled:
        return const Color(0xFFFCD34D);
      case AnnotationStatus.idle:
        return Colors.white70;
    }
  }

  Widget _getStatusIcon(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.checkingCatalogs:
      case AnnotationStatus.plateSolving:
      case AnnotationStatus.searchingCatalogs:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(_getTextColor(status)),
          ),
        );
      case AnnotationStatus.complete:
        return Icon(LucideIcons.checkCircle,
            size: 14, color: _getTextColor(status));
      case AnnotationStatus.error:
      case AnnotationStatus.plateSolveFailed:
        return Icon(LucideIcons.alertCircle,
            size: 14, color: _getTextColor(status));
      case AnnotationStatus.catalogsNotInstalled:
        return Icon(LucideIcons.alertTriangle,
            size: 14, color: _getTextColor(status));
      case AnnotationStatus.idle:
        return const SizedBox.shrink();
    }
  }

  String _getStatusText(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.checkingCatalogs:
        return 'Checking catalogs...';
      case AnnotationStatus.plateSolving:
        return 'Plate solving...';
      case AnnotationStatus.searchingCatalogs:
        return 'Searching catalogs...';
      case AnnotationStatus.complete:
        return 'Annotation complete';
      case AnnotationStatus.error:
        return 'Annotation error';
      case AnnotationStatus.plateSolveFailed:
        return 'Plate solve failed';
      case AnnotationStatus.catalogsNotInstalled:
        return 'No catalogs installed';
      case AnnotationStatus.idle:
        return '';
    }
  }

  String? _getActionHint(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.catalogsNotInstalled:
        return 'Install catalogs in Settings > Catalogs';
      case AnnotationStatus.plateSolveFailed:
        return 'Check solver config, focus, and star signal';
      case AnnotationStatus.error:
        return 'Capture a fresh frame to retry';
      case AnnotationStatus.checkingCatalogs:
      case AnnotationStatus.plateSolving:
      case AnnotationStatus.searchingCatalogs:
      case AnnotationStatus.complete:
      case AnnotationStatus.idle:
        return null;
    }
  }
}

/// Sidebar panel showing list of detected celestial objects
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
            backgroundColor: Colors.red.shade800,
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

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: widget.colors.surface.withValues(alpha: 0.95),
        border: Border(
          left: BorderSide(color: widget.colors.border),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(annotation, filteredObjects, displayableObjects),

          // Search bar
          AnnotationSearchBar(
            colors: widget.colors,
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
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Object count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: widget.colors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${filteredObjects.length}/${displayableObjects.length}',
              style: TextStyle(
                color: widget.colors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<AnnotationPanelSortMode>(
            tooltip: 'Sort objects',
            color: widget.colors.surfaceAlt,
            onSelected: (value) => ref
                .read(annotationPanelSortModeProvider.notifier)
                .state = value,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: AnnotationPanelSortMode.brightness,
                child: Text(
                  'Sort: Brightness',
                  style:
                      TextStyle(color: widget.colors.textPrimary, fontSize: 12),
                ),
              ),
              PopupMenuItem(
                value: AnnotationPanelSortMode.name,
                child: Text(
                  'Sort: Name',
                  style:
                      TextStyle(color: widget.colors.textPrimary, fontSize: 12),
                ),
              ),
              PopupMenuItem(
                value: AnnotationPanelSortMode.type,
                child: Text(
                  'Sort: Type',
                  style:
                      TextStyle(color: widget.colors.textPrimary, fontSize: 12),
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
                  borderRadius: BorderRadius.circular(4),
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
                  borderRadius: BorderRadius.circular(4),
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
            color: widget.colors.surfaceAlt,
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
                            color: widget.colors.textPrimary, fontSize: 12)),
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
                            color: widget.colors.textPrimary, fontSize: 12)),
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
            borderRadius: BorderRadius.circular(4),
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
          fontSize: 12,
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
              fontSize: 13,
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
            backgroundColor: Colors.red.shade800,
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
      builder: (ctx) => _PresetNameDialog(colors: widget.colors),
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
            backgroundColor: Colors.red.shade800,
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
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _deletePreset(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Preset'),
        content: Text('Delete preset "$name"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
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
            backgroundColor: Colors.red.shade800,
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
                decoration: BoxDecoration(
                  color: widget.colors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${filteredObjects.length}/${displayableObjects.length} objects',
                  style: TextStyle(
                    color: widget.colors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              // Sort menu
              PopupMenuButton<AnnotationPanelSortMode>(
                tooltip: 'Sort objects',
                color: widget.colors.surfaceAlt,
                onSelected: (value) => ref
                    .read(annotationPanelSortModeProvider.notifier)
                    .state = value,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: AnnotationPanelSortMode.brightness,
                    child: Text(
                      'Sort: Brightness',
                      style: TextStyle(
                          color: widget.colors.textPrimary, fontSize: 12),
                    ),
                  ),
                  PopupMenuItem(
                    value: AnnotationPanelSortMode.name,
                    child: Text(
                      'Sort: Name',
                      style: TextStyle(
                          color: widget.colors.textPrimary, fontSize: 12),
                    ),
                  ),
                  PopupMenuItem(
                    value: AnnotationPanelSortMode.type,
                    child: Text(
                      'Sort: Type',
                      style: TextStyle(
                          color: widget.colors.textPrimary, fontSize: 12),
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
                      borderRadius: BorderRadius.circular(4),
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
                      borderRadius: BorderRadius.circular(4),
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
                color: widget.colors.surfaceAlt,
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
                                fontSize: 12)),
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
                                fontSize: 12)),
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
                color: widget.colors.surfaceAlt,
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
                                fontSize: 12,
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
                                color: widget.colors.primary, fontSize: 12)),
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
          colors: widget.colors,
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
              fontSize: 12,
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
                          fontSize: 13,
                        ),
                      ),
                      if (annotation == null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Capture an image to see detected objects',
                          style: TextStyle(
                            color:
                                widget.colors.textMuted.withValues(alpha: 0.7),
                            fontSize: 11,
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
class AnnotationMiniChips extends ConsumerWidget {
  final NightshadeColors colors;

  const AnnotationMiniChips({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotation = ref.watch(currentAnnotationProvider);
    final settings = ref.watch(annotationSettingsProvider).valueOrNull ??
        const AnnotationSettings();

    if (annotation == null || !settings.enabled) {
      return const SizedBox.shrink();
    }

    // Get visible objects, sorted by brightness (lowest magnitude = brightest)
    final visibleObjects = annotation.objects.where((obj) {
      if (!obj.visible) return false;
      if (!isTypeVisibleFromSettings(obj.type, settings.visibleTypes)) {
        return false;
      }
      if (obj.magnitude != null) {
        if (obj.magnitude! > settings.magnitudeCutoff) return false;
        if (obj.magnitude! < settings.minMagnitude) return false;
      }
      // Skip stars for the chip row - they're too numerous and not interesting
      if (obj.type == ObjectType.star || obj.type == ObjectType.doubleStar) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final aMag = a.magnitude ?? 99.0;
        final bMag = b.magnitude ?? 99.0;
        return aMag.compareTo(bMag);
      });

    // Take the 5 brightest non-star objects
    final topObjects = visibleObjects.take(5).toList();
    if (topObjects.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      ignoring: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: topObjects.map((obj) {
            return GestureDetector(
              onTap: () {
                ref.read(selectedAnnotationObjectProvider.notifier).state = obj;
                // Switch to the annotations tab when a chip is tapped
                ref.read(selectedImagingPanelProvider.notifier).state =
                    PanelTabs.annotationsTabIndex;
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  obj.commonName ?? obj.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _PresetNameDialog extends StatefulWidget {
  final NightshadeColors colors;
  const _PresetNameDialog({required this.colors});

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save Preset'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Preset name',
          hintText: 'e.g. Deep sky defaults',
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
