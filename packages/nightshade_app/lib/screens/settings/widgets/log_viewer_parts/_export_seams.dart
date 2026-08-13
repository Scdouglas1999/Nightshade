// Part of ../log_viewer.dart -- extracted for maintainability.
//
// Log export scope, target-picker seam and default export directory.
part of '../log_viewer.dart';

/// What a log export covers.
enum LogExportScope {
  /// Only the entries the viewer is currently showing, after its filters.
  visible,

  /// Every retained on-disk log file plus the in-memory Dart entries.
  fullHistory,
}

/// Resolves where a log export is written. Injected so a widget test can drive
/// the real Export button without a native save dialog.
typedef LogExportTargetPicker = Future<ExportTarget?> Function(
  String suggestedName,
);

/// Export used to write straight to the ROOT of the user's Documents folder
/// with no picker and no size warning — 18 MB of concatenated rotated logs
/// appeared next to their personal files, and not in the `exports/` directory
/// every other in-app export uses. This asks, and defaults to `exports/`.
final logExportTargetPickerProvider = Provider<LogExportTargetPicker>((ref) {
  return (suggestedName) async => chooseExportTarget(
        suggestedName: suggestedName,
        initialDirectory: await defaultLogExportDirectory(),
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Text files', extensions: ['txt']),
        ],
      );
});

/// The directory the app's other exports go to, created on demand.
///
/// Returns null when it cannot be resolved or created, which leaves the save
/// dialog at its own default rather than failing the export.
Future<String?> defaultLogExportDirectory() async {
  try {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/Nightshade/exports');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory.path;
  } catch (_) {
    return null;
  }
}
