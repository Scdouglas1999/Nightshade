/// Sequencer status and checkpoint types.

/// Current status of the sequence executor
class SequencerStatus {
  /// Current state (idle, running, paused, stopped, error)
  final String state;

  /// ID of the currently executing node
  final String? currentNodeId;

  /// Human-readable name of the current node
  final String? currentNodeName;

  /// Overall progress (0.0 to 1.0)
  final double progress;

  /// Status message
  final String? message;

  const SequencerStatus({
    required this.state,
    this.currentNodeId,
    this.currentNodeName,
    required this.progress,
    this.message,
  });

  /// Create from JSON (for network transport)
  factory SequencerStatus.fromJson(Map<String, dynamic> json) {
    return SequencerStatus(
      state: json['state'] as String,
      currentNodeId: json['currentNodeId'] as String?,
      currentNodeName: json['currentNodeName'] as String?,
      progress: (json['progress'] as num).toDouble(),
      message: json['message'] as String?,
    );
  }

  /// Convert to JSON (for network transport)
  Map<String, dynamic> toJson() => {
        'state': state,
        'currentNodeId': currentNodeId,
        'currentNodeName': currentNodeName,
        'progress': progress,
        'message': message,
      };

  /// Check if sequencer is running
  bool get isRunning => state == 'running';

  /// Check if sequencer is paused
  bool get isPaused => state == 'paused';

  /// Check if sequencer is idle
  bool get isIdle => state == 'idle';
}

/// Checkpoint information for crash recovery
class CheckpointInfo {
  /// Name of the sequence
  final String sequenceName;

  /// When the checkpoint was saved
  final DateTime timestamp;

  /// Number of exposures completed before checkpoint
  final int completedExposures;

  /// Total integration time completed in seconds
  final double completedIntegrationSecs;

  /// Whether the checkpoint can be resumed
  final bool canResume;

  /// Age of the checkpoint in seconds
  final int ageSeconds;

  const CheckpointInfo({
    required this.sequenceName,
    required this.timestamp,
    required this.completedExposures,
    required this.completedIntegrationSecs,
    required this.canResume,
    required this.ageSeconds,
  });

  /// Create from JSON (for network transport)
  factory CheckpointInfo.fromJson(Map<String, dynamic> json) {
    return CheckpointInfo(
      sequenceName: json['sequenceName'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      completedExposures: json['completedExposures'] as int,
      completedIntegrationSecs:
          (json['completedIntegrationSecs'] as num).toDouble(),
      canResume: json['canResume'] as bool,
      ageSeconds: json['ageSeconds'] as int,
    );
  }

  /// Convert to JSON (for network transport)
  Map<String, dynamic> toJson() => {
        'sequenceName': sequenceName,
        'timestamp': timestamp.toIso8601String(),
        'completedExposures': completedExposures,
        'completedIntegrationSecs': completedIntegrationSecs,
        'canResume': canResume,
        'ageSeconds': ageSeconds,
      };

  /// Get a human-readable age string
  String get ageString {
    if (ageSeconds < 60) return '${ageSeconds}s ago';
    if (ageSeconds < 3600) return '${ageSeconds ~/ 60}m ago';
    if (ageSeconds < 86400) return '${ageSeconds ~/ 3600}h ago';
    return '${ageSeconds ~/ 86400}d ago';
  }
}
