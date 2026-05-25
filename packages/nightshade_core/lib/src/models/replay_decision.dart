import 'dart:convert';

/// Wave 8 Replay Debug — categorical bucket for [ReplayDecision].
///
/// Wire keys are the snake_case identifiers Rust persists into the
/// `sequence_decisions.category` column. Adding variants is safe;
/// renaming is not.
enum DecisionCategory {
  schedulerPick('scheduler_pick'),
  triggerFired('trigger_fired'),
  recoveryEntered('recovery_entered'),
  budgetMet('budget_met'),
  adaptiveSwap('adaptive_swap'),
  frameAccepted('frame_accepted'),
  frameRejected('frame_rejected'),
  pluginNodeInvoked('plugin_node_invoked'),
  manualIntervention('manual_intervention'),
  systemEvent('system_event'),
  /// Unknown wire key — only happens if Rust adds a new variant
  /// before the Dart enum updates. We deliberately surface it as
  /// distinct so the Replay UI can render an "unknown" badge instead
  /// of silently dropping the row.
  unknown('unknown');

  const DecisionCategory(this.wireKey);

  /// Stable snake_case identifier used by the bridge + the
  /// `sequence_decisions.category` column.
  final String wireKey;

  /// Parse a wire key into the enum. Returns [DecisionCategory.unknown]
  /// for unrecognised inputs rather than throwing — we'd rather show
  /// the row with a placeholder than crash the replay feed.
  static DecisionCategory fromWireKey(String s) {
    for (final c in DecisionCategory.values) {
      if (c.wireKey == s) return c;
    }
    return DecisionCategory.unknown;
  }

  /// Human-readable label for the filter chip / row badge.
  String get displayLabel {
    switch (this) {
      case DecisionCategory.schedulerPick:
        return 'Scheduler pick';
      case DecisionCategory.triggerFired:
        return 'Trigger fired';
      case DecisionCategory.recoveryEntered:
        return 'Recovery';
      case DecisionCategory.budgetMet:
        return 'Budget met';
      case DecisionCategory.adaptiveSwap:
        return 'Adaptive swap';
      case DecisionCategory.frameAccepted:
        return 'Frame accepted';
      case DecisionCategory.frameRejected:
        return 'Frame rejected';
      case DecisionCategory.pluginNodeInvoked:
        return 'Plugin node';
      case DecisionCategory.manualIntervention:
        return 'Operator';
      case DecisionCategory.systemEvent:
        return 'System';
      case DecisionCategory.unknown:
        return 'Unknown';
    }
  }
}

/// Wave 8 Replay Debug — one persisted decision row from the
/// `sequence_decisions` table. Immutable; rebuilt from the JSON blob on
/// every read.
class ReplayDecision {
  ReplayDecision({
    required this.id,
    required this.sequenceRunId,
    required this.timestamp,
    required this.category,
    required this.summary,
    required this.details,
    this.nodeId,
  });

  /// Auto-increment row id. `null` for in-flight decisions that
  /// haven't been persisted yet (the live event stream emits these
  /// before the DB write completes).
  final int? id;

  /// FK to `sequence_runs.id`. May be `null` when the decision was
  /// emitted outside a tracked run (rare; the executor only emits
  /// inside the spawned task post-start, but the field models the
  /// schema honestly).
  final int? sequenceRunId;

  /// UTC timestamp the decision was made.
  final DateTime timestamp;

  /// Category bucket.
  final DecisionCategory category;

  /// One-line human-readable summary.
  final String summary;

  /// Opaque structured details (the JSON-decoded map). Empty map when
  /// the emit site did not attach any extra payload.
  final Map<String, dynamic> details;

  /// Optional node id this decision is associated with (scheduler /
  /// target / exposure).
  final String? nodeId;

  /// Construct from the bridge's [SequencerEvent.DecisionLogged]
  /// payload. `id` is left `null` because the row hasn't been inserted
  /// yet; the service writes it and re-reads to get the assigned id.
  factory ReplayDecision.fromBridgeEvent({
    required String timestampIso,
    required String categoryWireKey,
    required String summary,
    required String detailsJson,
    String? nodeId,
    int? sequenceRunId,
  }) {
    final ts = DateTime.tryParse(timestampIso) ?? DateTime.now().toUtc();
    Map<String, dynamic> parsed;
    if (detailsJson.isEmpty) {
      parsed = const {};
    } else {
      try {
        final decoded = jsonDecode(detailsJson);
        parsed = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } on FormatException {
        // Loud-fail policy (CLAUDE.md): we keep the row but mark the
        // payload as malformed so the replay UI can render it instead
        // of silently dropping. Production code never lands here —
        // Rust always emits valid JSON via serde_json::to_string.
        parsed = <String, dynamic>{
          '__parse_error': 'malformed JSON',
          '__raw': detailsJson,
        };
      }
    }
    return ReplayDecision(
      id: null,
      sequenceRunId: sequenceRunId,
      timestamp: ts.toUtc(),
      category: DecisionCategory.fromWireKey(categoryWireKey),
      summary: summary,
      details: parsed,
      nodeId: nodeId,
    );
  }

  /// Construct from a raw DB row map (the keys are the column names).
  factory ReplayDecision.fromDbRow(Map<String, Object?> row) {
    final detailsJson = (row['details_json'] as String?) ?? '{}';
    Map<String, dynamic> parsed;
    try {
      final decoded = jsonDecode(detailsJson);
      parsed = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      parsed = <String, dynamic>{
        '__parse_error': 'malformed JSON',
        '__raw': detailsJson,
      };
    }
    // Timestamps are stored as INTEGER millis since epoch (UTC) so
    // sorting + range queries hit the index. DateTime.fromMillisecondsSinceEpoch
    // returns a local-time DateTime; we flip to UTC explicitly so the
    // wall-clock comparisons in the replay UI are timezone-correct.
    final tsMillis = (row['timestamp_unix_ms'] as int?) ?? 0;
    return ReplayDecision(
      id: row['id'] as int?,
      sequenceRunId: row['sequence_run_id'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(tsMillis, isUtc: true),
      category: DecisionCategory.fromWireKey(
        (row['category'] as String?) ?? 'unknown',
      ),
      summary: (row['summary'] as String?) ?? '',
      details: parsed,
      nodeId: row['node_id'] as String?,
    );
  }

  /// Re-encode for storage. Used by the service when persisting a
  /// row received over the bridge.
  Map<String, Object?> toInsertColumns() => {
        'sequence_run_id': sequenceRunId,
        'timestamp_unix_ms': timestamp.toUtc().millisecondsSinceEpoch,
        'category': category.wireKey,
        'summary': summary,
        'details_json': jsonEncode(details),
        'node_id': nodeId,
      };

  ReplayDecision copyWith({int? id}) => ReplayDecision(
        id: id ?? this.id,
        sequenceRunId: sequenceRunId,
        timestamp: timestamp,
        category: category,
        summary: summary,
        details: details,
        nodeId: nodeId,
      );

  @override
  String toString() =>
      'ReplayDecision(id=$id, run=$sequenceRunId, ${category.wireKey}: $summary)';
}
