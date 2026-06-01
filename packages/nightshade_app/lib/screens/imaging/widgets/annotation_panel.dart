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

part 'annotation_panel_parts/status_widgets.dart';
part 'annotation_panel_parts/objects_panel.dart';
part 'annotation_panel_parts/tab_panel.dart';
part 'annotation_panel_parts/mini_chips.dart';
part 'annotation_panel_parts/preset_name_dialog.dart';

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

ShapeBorder _annotationMenuShape(NightshadeColors colors) {
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
    side: BorderSide(color: colors.border),
  );
}

/// Banner shown when annotation catalog is not installed
