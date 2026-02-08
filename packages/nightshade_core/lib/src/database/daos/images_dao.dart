import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/captured_images.dart';
import '../tables/imaging_sessions.dart';
import '../tables/targets.dart';

part 'images_dao.g.dart';

@DriftAccessor(
    tables: [CapturedImages, ImageMetadata, ImagingSessions, Targets])
class ImagesDao extends DatabaseAccessor<NightshadeDatabase>
    with _$ImagesDaoMixin {
  ImagesDao(NightshadeDatabase db) : super(db);

  /// Get all images
  Future<List<CapturedImage>> getAllImages() {
    return (select(capturedImages)
          ..orderBy([(i) => OrderingTerm.desc(i.capturedAt)]))
        .get();
  }

  /// Get all images with pagination
  ///
  /// More efficient for displaying large image libraries.
  /// Use this instead of getAllImages() when dealing with hundreds or thousands of images.
  Future<List<CapturedImage>> getAllImagesPaginated({
    required int limit,
    required int offset,
  }) {
    return (select(capturedImages)
          ..orderBy([(i) => OrderingTerm.desc(i.capturedAt)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Get total image count
  Future<int> getImageCount() async {
    final countExp = capturedImages.id.count();
    final query = selectOnly(capturedImages)..addColumns([countExp]);
    final result = await query.getSingle();
    return result.read(countExp) ?? 0;
  }

  /// Get image count for a session
  Future<int> getImageCountForSession(int sessionId) async {
    final countExp = capturedImages.id.count();
    final query = selectOnly(capturedImages)
      ..addColumns([countExp])
      ..where(capturedImages.sessionId.equals(sessionId));
    final result = await query.getSingle();
    return result.read(countExp) ?? 0;
  }

  /// Watch all images
  Stream<List<CapturedImage>> watchAllImages() {
    return (select(capturedImages)
          ..orderBy([(i) => OrderingTerm.desc(i.capturedAt)]))
        .watch();
  }

  /// Get images for a session
  Future<List<CapturedImage>> getImagesForSession(int sessionId) {
    return (select(capturedImages)
          ..where((i) => i.sessionId.equals(sessionId))
          ..orderBy([(i) => OrderingTerm.asc(i.capturedAt)]))
        .get();
  }

  /// Get images for a session with pagination
  ///
  /// This is more efficient for large image sets as it only loads
  /// the requested page instead of all images.
  Future<List<CapturedImage>> getImagesForSessionPaginated({
    required int sessionId,
    required int limit,
    required int offset,
  }) {
    return (select(capturedImages)
          ..where((i) => i.sessionId.equals(sessionId))
          ..orderBy([(i) => OrderingTerm.asc(i.capturedAt)])
          ..limit(limit, offset: offset))
        .get();
  }

  /// Watch images for a session
  Stream<List<CapturedImage>> watchImagesForSession(int sessionId) {
    return (select(capturedImages)
          ..where((i) => i.sessionId.equals(sessionId))
          ..orderBy([(i) => OrderingTerm.asc(i.capturedAt)]))
        .watch();
  }

  /// Get images for a target
  Future<List<CapturedImage>> getImagesForTarget(int targetId) {
    return (select(capturedImages)
          ..where((i) => i.targetId.equals(targetId))
          ..orderBy([(i) => OrderingTerm.desc(i.capturedAt)]))
        .get();
  }

  /// Get image by ID
  Future<CapturedImage?> getImageById(int id) {
    return (select(capturedImages)..where((i) => i.id.equals(id)))
        .getSingleOrNull();
  }

  Future<CapturedImage?> getImageByFilePath(String filePath) {
    return (select(capturedImages)..where((i) => i.filePath.equals(filePath)))
        .getSingleOrNull();
  }

  Future<List<CapturedImage>> getRecentImagesForSession(
    int sessionId, {
    int limit = 5,
  }) {
    return (select(capturedImages)
          ..where((i) => i.sessionId.equals(sessionId))
          ..orderBy([(i) => OrderingTerm.desc(i.capturedAt)])
          ..limit(limit))
        .get();
  }

  /// Create a new image record
  Future<int> createImage(CapturedImagesCompanion image) {
    return into(capturedImages).insert(image);
  }

  /// Update an image
  Future<bool> updateImage(CapturedImage image) {
    return update(capturedImages).replace(image);
  }

  /// Delete an image record
  Future<int> deleteImage(int id) {
    return (delete(capturedImages)..where((i) => i.id.equals(id))).go();
  }

  /// Mark image as rejected
  Future<void> rejectImage(int id, String reason) {
    return (update(capturedImages)..where((i) => i.id.equals(id))).write(
      CapturedImagesCompanion(
        isAccepted: const Value(false),
        rejectionReason: Value(reason),
      ),
    );
  }

  /// Accept a previously rejected image
  Future<void> acceptImage(int id) {
    return (update(capturedImages)..where((i) => i.id.equals(id))).write(
      const CapturedImagesCompanion(
        isAccepted: Value(true),
        rejectionReason: Value(null),
      ),
    );
  }

  /// Get images by frame type
  Future<List<CapturedImage>> getImagesByFrameType(String frameType) {
    return (select(capturedImages)
          ..where((i) => i.frameType.equals(frameType))
          ..orderBy([(i) => OrderingTerm.desc(i.capturedAt)]))
        .get();
  }

  /// Watch recent standalone (sessionless) images — captures taken outside
  /// any sequence session.  Limited to the most recent [limit] images.
  Stream<List<CapturedImage>> watchStandaloneImages({int limit = 100}) {
    return (select(capturedImages)
          ..where((i) => i.sessionId.isNull())
          ..orderBy([(i) => OrderingTerm.desc(i.capturedAt)])
          ..limit(limit))
        .watch();
  }

  /// Get images by filter
  Future<List<CapturedImage>> getImagesByFilter(String filter) {
    return (select(capturedImages)
          ..where((i) => i.filter.equals(filter))
          ..orderBy([(i) => OrderingTerm.desc(i.capturedAt)]))
        .get();
  }

  /// Update plate solve result
  Future<void> updatePlateSolveResult(
    int id, {
    required double solvedRa,
    required double solvedDec,
    required double solvedRotation,
    required double solvedPixelScale,
  }) {
    return (update(capturedImages)..where((i) => i.id.equals(id))).write(
      CapturedImagesCompanion(
        isPlateSolved: const Value(true),
        solvedRa: Value(solvedRa),
        solvedDec: Value(solvedDec),
        solvedRotation: Value(solvedRotation),
        solvedPixelScale: Value(solvedPixelScale),
      ),
    );
  }

  /// Get image count by filter for a target
  Future<Map<String, int>> getFilterCountsForTarget(int targetId) async {
    final images = await getImagesForTarget(targetId);
    final counts = <String, int>{};

    for (final image in images) {
      if (image.filter != null && image.isAccepted) {
        counts[image.filter!] = (counts[image.filter!] ?? 0) + 1;
      }
    }

    return counts;
  }

  // Image metadata operations

  /// Get metadata for an image
  Future<List<ImageMetadatum>> getMetadataForImage(int imageId) {
    return (select(imageMetadata)..where((m) => m.imageId.equals(imageId)))
        .get();
  }

  /// Add metadata to an image
  Future<int> addMetadata(int imageId, String key, String value,
      {String? comment}) {
    return into(imageMetadata).insert(
      ImageMetadataCompanion.insert(
        imageId: imageId,
        key: key,
        value: value,
        comment: Value(comment),
      ),
    );
  }

  /// Add multiple metadata entries
  Future<void> addMetadataBatch(
      int imageId, Map<String, String> metadata) async {
    await batch((batch) {
      for (final entry in metadata.entries) {
        batch.insert(
          imageMetadata,
          ImageMetadataCompanion.insert(
            imageId: imageId,
            key: entry.key,
            value: entry.value,
          ),
        );
      }
    });
  }
}
