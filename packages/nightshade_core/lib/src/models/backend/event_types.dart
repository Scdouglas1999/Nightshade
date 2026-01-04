/// Event types for Nightshade backend communication.
///
/// These types are used to communicate events between the Rust backend
/// and Dart frontend, as well as across network boundaries for remote operation.

/// Event severity levels
enum EventSeverity {
  info,
  warning,
  error,
  critical,
}

/// Event categories for filtering and routing
enum EventCategory {
  equipment,
  imaging,
  guiding,
  sequencer,
  safety,
  system,
  polarAlignment,
}

/// Nightshade event for backend-to-frontend communication
class NightshadeEvent {
  final int timestamp;
  final EventSeverity severity;
  final EventCategory category;
  final String eventType;
  final Map<String, dynamic> data;

  const NightshadeEvent({
    required this.timestamp,
    required this.severity,
    required this.category,
    required this.eventType,
    required this.data,
  });

  /// Convert to JSON for wire protocol (WebSocket/HTTP)
  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'severity': severity.name,
        'category': category.name,
        'eventType': eventType,
        'data': data,
      };

  /// Create from JSON (used by NetworkBackend)
  factory NightshadeEvent.fromJson(Map<String, dynamic> json) {
    return NightshadeEvent(
      timestamp: json['timestamp'] as int,
      severity: EventSeverity.values.firstWhere(
        (e) => e.name == json['severity'],
        orElse: () => EventSeverity.info,
      ),
      category: EventCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => EventCategory.system,
      ),
      eventType: json['eventType'] as String,
      data: Map<String, dynamic>.from(json['data'] as Map),
    );
  }

  @override
  String toString() =>
      'NightshadeEvent($eventType, $category, $severity, $data)';
}
