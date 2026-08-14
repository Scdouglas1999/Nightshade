/// The ONE vocabulary for an exposure node's per-frame progress line.
///
/// SEQ-18 (three strikes) lived in the gap between two producers and one
/// parser. The sequencer writes a node's progress detail from two different
/// events, in two different wordings:
///
///   * `ExposureStarted`   -> "Frame 3/4 (R)"      — frame 3 is in flight
///   * `ExposureCompleted` -> "Completed 3/4"      — frame 3 is done
///
/// The run-dashboard card that renders those frames only ever understood the
/// FIRST wording. On the success path the last thing written for the node is
/// the second, so a run that captured every frame parsed as "no frames at all"
/// and the card read "0 / 4 frames" with four empty boxes — directly above the
/// four thumbnails it had just captured. A run STOPPED mid-frame ended on an
/// `ExposureStarted` line, parsed fine, and read "2 / 4" — which is exactly why
/// the defect looked specific to success and survived two fixes aimed at the
/// node's status instead of at the string on screen.
///
/// Producers call the formatters here, the card calls
/// [parseExposureProgressDetail], and
/// `test/providers/sequence/exposure_progress_vocabulary_test.dart` asserts
/// that everything a formatter can emit is something the parser understands. A
/// third wording cannot be introduced silently.
library;

/// What an exposure node's progress line says about its frames.
class ExposureFrameProgress {
  /// 1-based index of the frame the line names.
  final int frame;

  /// Frames planned for the node.
  final int total;

  /// True when [frame] is FINISHED (the `Completed n/m` wording); false when it
  /// is the frame currently being exposed (the `Frame n/m` wording).
  final bool frameCompleted;

  const ExposureFrameProgress({
    required this.frame,
    required this.total,
    required this.frameCompleted,
  });
}

/// The line written when frame [frame] of [total] starts exposing.
String formatExposureStartedDetail(int frame, int total, String? filter) =>
    'Frame $frame/$total${filter != null ? ' ($filter)' : ''}';

/// The line written when frame [frame] of [total] has been captured.
String formatExposureCompletedDetail(int frame, int total) =>
    'Completed $frame/$total';

final RegExp _startedPattern = RegExp(r'Frame (\d+)/(\d+)');
final RegExp _completedPattern = RegExp(r'Completed (\d+)/(\d+)');

/// Read an exposure node's progress line back, in EITHER wording.
///
/// Returns null when [detail] is not an exposure progress line (an empty
/// detail, or another instruction's).
ExposureFrameProgress? parseExposureProgressDetail(String detail) {
  final completed = _completedPattern.firstMatch(detail);
  if (completed != null) {
    return ExposureFrameProgress(
      frame: int.parse(completed.group(1)!),
      total: int.parse(completed.group(2)!),
      frameCompleted: true,
    );
  }
  final started = _startedPattern.firstMatch(detail);
  if (started != null) {
    return ExposureFrameProgress(
      frame: int.parse(started.group(1)!),
      total: int.parse(started.group(2)!),
      frameCompleted: false,
    );
  }
  return null;
}
