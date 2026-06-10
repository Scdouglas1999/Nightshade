import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/database.dart' as db;
import '../../services/imaging_records_repository.dart';
import '../../providers/science_provider.dart';
import '../../services/logging_service.dart';
import 'frame_grade_rules.dart';

/// Applies [FrameGradeRules] to a single frame immediately after capture.
///
/// This is the SGP-class "auto-reject bad subs" feature: thresholds are
/// evaluated on every light frame once its quality metrics are in the DB.
/// Rejection only flips `isAccepted` — files are never deleted.
class FrameAutoGrader {
  final Ref _ref;

  FrameAutoGrader(this._ref);

  /// Returns `true` when the frame was rejected, `false` when accepted or
  /// skipped, `null` when grading did not run (disabled / not a light).
  Future<bool?> gradeCapturedFrame({required db.CapturedImage image}) async {
    if (image.frameType.toLowerCase() != 'light') return null;
    if (!image.isAccepted) return false;

    final settings = await _ref.read(scienceSettingsProvider.future);
    if (!settings.autoFrameGradingEnabled) return null;

    final rules = settings.resolvedFrameGradeRules();
    if (rules.isEmpty) return null;

    final reason = rules.gradeFrame(image);
    if (reason == null) return false;

    await _ref
        .read(imagingRecordsRepositoryProvider)
        .rejectImage(image.id, reason);
    _ref
        .read(loggingServiceProvider)
        .info(
          'Auto-rejected frame ${image.id} (${image.fileName}): $reason',
          source: 'FrameAutoGrader',
        );
    return true;
  }
}

final frameAutoGraderProvider = Provider<FrameAutoGrader>((ref) {
  return FrameAutoGrader(ref);
});
