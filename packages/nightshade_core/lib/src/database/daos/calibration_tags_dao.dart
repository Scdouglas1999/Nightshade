import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/calibration/calibration_library_models.dart';
import '../../providers/database_provider.dart';
import '../database.dart';

/// One row of the v46 `calibration_tags` table: user tags / notes plus the
/// FITS-enriched camera-id cache for a `(master_type, master_id)` artifact.
class CalibrationTagEntry {
  final int id;
  final CalibrationMasterType masterType;
  final int masterId;
  final List<String> tags;
  final String? notes;
  final String? cameraId;
  final DateTime updatedAt;

  const CalibrationTagEntry({
    required this.id,
    required this.masterType,
    required this.masterId,
    required this.tags,
    required this.notes,
    required this.cameraId,
    required this.updatedAt,
  });
}

/// Data-access object for the v46 `calibration_tags` table.
///
/// Like [FlatLibraryDao] / [MosaicProjectsDao], the table is managed with raw
/// DDL (see `NightshadeDatabase._createCalibrationTagsTable`) and this DAO is
/// a plain class reading/writing via `customSelect`/`customStatement` — the
/// dominant v27+ convention, requiring no Drift codegen pass.
///
/// Identity is `UNIQUE(master_type, master_id)` where `master_id` is the row
/// id in the artifact's source table (`dark_library` / `flat_library` /
/// `defect_maps`). Upserts merge: a null argument leaves the stored value
/// untouched, so setting tags never clobbers the camera-id cache and vice
/// versa.
class CalibrationTagsDao {
  CalibrationTagsDao(this._db);

  final NightshadeDatabase _db;

  static const String _columns =
      'id, master_type, master_id, tags_json, notes, camera_id, updated_at';

  /// Merge-upsert the row for `(type, masterId)`. Null fields keep the
  /// previously stored value; to clear notes pass `clearNotes: true`.
  Future<void> upsert(
    CalibrationMasterType type,
    int masterId, {
    List<String>? tags,
    String? notes,
    bool clearNotes = false,
    String? cameraId,
  }) async {
    final wireType = calibrationMasterTypeWireName(type);
    final existing = await getForMaster(type, masterId);
    final nowSecs = _toEpochSeconds(DateTime.now());

    final mergedTags = tags ?? existing?.tags ?? const <String>[];
    final mergedNotes = clearNotes ? null : (notes ?? existing?.notes);
    final mergedCamera = cameraId ?? existing?.cameraId;

    if (existing == null) {
      await _db.customInsert(
        'INSERT INTO calibration_tags('
        'master_type, master_id, tags_json, notes, camera_id, updated_at'
        ') VALUES (?, ?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(wireType),
          Variable<int>(masterId),
          Variable<String>(jsonEncode(mergedTags)),
          Variable<String>(mergedNotes),
          Variable<String>(mergedCamera),
          Variable<int>(nowSecs),
        ],
      );
      return;
    }

    await _db.customUpdate(
      'UPDATE calibration_tags SET tags_json = ?, notes = ?, camera_id = ?, '
      'updated_at = ? WHERE master_type = ? AND master_id = ?',
      variables: [
        Variable<String>(jsonEncode(mergedTags)),
        Variable<String>(mergedNotes),
        Variable<String>(mergedCamera),
        Variable<int>(nowSecs),
        Variable<String>(wireType),
        Variable<int>(masterId),
      ],
      updateKind: UpdateKind.update,
    );
  }

  /// The row for one artifact, or null when never tagged/enriched.
  Future<CalibrationTagEntry?> getForMaster(
      CalibrationMasterType type, int masterId) async {
    final rows = await _db.customSelect(
      'SELECT $_columns FROM calibration_tags '
      'WHERE master_type = ? AND master_id = ? LIMIT 1',
      variables: [
        Variable<String>(calibrationMasterTypeWireName(type)),
        Variable<int>(masterId),
      ],
    ).get();
    if (rows.isEmpty) return null;
    return _mapRow(rows.first);
  }

  /// Every row, keyed `'<wireType>:<masterId>'` for O(1) joining onto a
  /// listed library page.
  Future<Map<String, CalibrationTagEntry>> getAllKeyed() async {
    final rows =
        await _db.customSelect('SELECT $_columns FROM calibration_tags').get();
    final out = <String, CalibrationTagEntry>{};
    for (final row in rows) {
      final entry = _mapRow(row);
      if (entry == null) continue;
      out['${calibrationMasterTypeWireName(entry.masterType)}:'
          '${entry.masterId}'] = entry;
    }
    return out;
  }

  /// Remove the annotation row when its artifact is deleted.
  Future<int> deleteForMaster(CalibrationMasterType type, int masterId) {
    return _db.customUpdate(
      'DELETE FROM calibration_tags WHERE master_type = ? AND master_id = ?',
      variables: [
        Variable<String>(calibrationMasterTypeWireName(type)),
        Variable<int>(masterId),
      ],
      updateKind: UpdateKind.delete,
    );
  }

  CalibrationTagEntry? _mapRow(QueryRow row) {
    final type = calibrationMasterTypeFromWire(row.read<String>('master_type'));
    if (type == null) return null; // Unknown future type — skip, don't throw.
    return CalibrationTagEntry(
      id: row.read<int>('id'),
      masterType: type,
      masterId: row.read<int>('master_id'),
      tags: _decodeTags(row.read<String>('tags_json')),
      notes: row.readNullable<String>('notes'),
      cameraId: row.readNullable<String>('camera_id'),
      updatedAt: _fromEpochSeconds(row.read<int>('updated_at')),
    );
  }

  static List<String> _decodeTags(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } on FormatException {
      // Corrupt tags JSON degrades to "no tags" — the artifact row itself is
      // authoritative and must stay listable.
    }
    return const [];
  }

  static int _toEpochSeconds(DateTime when) =>
      when.toUtc().millisecondsSinceEpoch ~/ 1000;

  static DateTime _fromEpochSeconds(int seconds) =>
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

/// Riverpod provider for [CalibrationTagsDao].
final calibrationTagsDaoProvider = Provider<CalibrationTagsDao>((ref) {
  return CalibrationTagsDao(ref.watch(databaseProvider));
});
