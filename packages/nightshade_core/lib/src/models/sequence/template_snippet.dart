import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';

part 'template_snippet.freezed.dart';
part 'template_snippet.g.dart';

/// Category for template snippets
enum SnippetCategory {
  /// Autofocus routines
  autofocus,

  /// Dithering patterns
  dithering,

  /// Filter sequence workflows
  filterSequence,

  /// Calibration routines (meridian flip, polar alignment, etc.)
  calibration,

  /// Safety checks (weather, guiding, etc.)
  safety,

  /// User-created custom snippets
  custom,
}

/// A reusable template snippet that can be inserted into sequences
@freezed
class TemplateSnippet with _$TemplateSnippet {
  const TemplateSnippet._();

  const factory TemplateSnippet({
    /// Unique identifier for this snippet
    required String id,

    /// Display name for the snippet
    required String name,

    /// Description of what this snippet does
    required String description,

    /// Category for organization
    required SnippetCategory category,

    /// Lucide icon name (e.g., 'focus', 'filter', 'shield')
    required String iconName,

    /// Serialized node data for recreation when inserting
    required List<Map<String, dynamic>> nodeData,

    /// Whether this is a built-in snippet (cannot be deleted)
    @Default(false) bool isBuiltIn,

    /// When this snippet was created
    required DateTime createdAt,
  }) = _TemplateSnippet;

  factory TemplateSnippet.fromJson(Map<String, dynamic> json) =>
      _$TemplateSnippetFromJson(json);

  /// Create a new custom snippet
  factory TemplateSnippet.custom({
    required String name,
    required String description,
    required String iconName,
    required List<Map<String, dynamic>> nodeData,
    SnippetCategory category = SnippetCategory.custom,
  }) {
    return TemplateSnippet(
      id: const Uuid().v4(),
      name: name,
      description: description,
      category: category,
      iconName: iconName,
      nodeData: nodeData,
      isBuiltIn: false,
      createdAt: DateTime.now(),
    );
  }
}

/// Built-in template snippets that come with Nightshade
class BuiltInSnippets {
  BuiltInSnippets._();

  /// Autofocus routine with current settings
  static final autofocusRoutine = TemplateSnippet(
    id: 'builtin-autofocus-routine',
    name: 'Autofocus Routine',
    description: 'Run autofocus with current settings',
    category: SnippetCategory.autofocus,
    iconName: 'focus',
    nodeData: [
      {
        'nodeType': 'Autofocus',
        'name': 'Autofocus',
        'method': 'vCurve',
        'stepSize': 100,
        'stepsOut': 7,
        'exposuresPerPoint': 1,
        'exposureDuration': 3.0,
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// LRGB filter cycle for broadband imaging
  static final lrgbFilterCycle = TemplateSnippet(
    id: 'builtin-lrgb-filter-cycle',
    name: 'LRGB Filter Cycle',
    description: 'Capture L, R, G, B filter sequence',
    category: SnippetCategory.filterSequence,
    iconName: 'palette',
    nodeData: [
      {
        'nodeType': 'InstructionSet',
        'name': 'LRGB Cycle',
        'children': [
          {
            'nodeType': 'TakeExposure',
            'name': 'Luminance',
            'filter': 'L',
            'filterIndex': 0,
            'durationSecs': 300.0,
            'count': 10,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'Red',
            'filter': 'R',
            'filterIndex': 1,
            'durationSecs': 300.0,
            'count': 5,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'Green',
            'filter': 'G',
            'filterIndex': 2,
            'durationSecs': 300.0,
            'count': 5,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'Blue',
            'filter': 'B',
            'filterIndex': 3,
            'durationSecs': 300.0,
            'count': 5,
            'frameType': 'light',
          },
        ],
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// Dither between exposures
  static final ditherAfterEach = TemplateSnippet(
    id: 'builtin-dither-after-each',
    name: 'Dither After Each',
    description: 'Dither between exposures',
    category: SnippetCategory.dithering,
    iconName: 'move',
    nodeData: [
      {
        'nodeType': 'Dither',
        'name': 'Dither',
        'pixels': 5.0,
        'settleTime': 30.0,
        'settlePixels': 1.5,
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// Safety check before continuing imaging
  static final safetyCheck = TemplateSnippet(
    id: 'builtin-safety-check',
    name: 'Safety Check',
    description: 'Check weather and guiding before continuing',
    category: SnippetCategory.safety,
    iconName: 'shield',
    nodeData: [
      {
        'nodeType': 'Conditional',
        'name': 'Weather Safe Check',
        'conditionType': 'weatherSafe',
        'children': [
          {
            'nodeType': 'Conditional',
            'name': 'Guiding RMS Check',
            'conditionType': 'guidingRmsBelow',
            'thresholdValue': 2.0,
          },
        ],
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// Handle meridian flip with re-centering
  static final meridianFlipHandler = TemplateSnippet(
    id: 'builtin-meridian-flip-handler',
    name: 'Meridian Flip Handler',
    description: 'Handle meridian flip with re-centering',
    category: SnippetCategory.calibration,
    iconName: 'rotate-cw',
    nodeData: [
      {
        'nodeType': 'InstructionSet',
        'name': 'Meridian Flip Sequence',
        'children': [
          {
            'nodeType': 'StopGuiding',
            'name': 'Stop Guiding',
          },
          {
            'nodeType': 'MeridianFlip',
            'name': 'Meridian Flip',
            'minutesPastMeridian': 5.0,
            'pauseGuiding': true,
            'autoCenter': true,
            'settleTime': 10.0,
          },
          {
            'nodeType': 'CenterTarget',
            'name': 'Re-center Target',
            'accuracyArcsec': 5.0,
            'maxAttempts': 5,
            'useTargetCoords': true,
          },
          {
            'nodeType': 'StartGuiding',
            'name': 'Resume Guiding',
            'settlePixels': 1.5,
            'settleTime': 10.0,
            'settleTimeout': 60.0,
            'autoSelectStar': true,
          },
        ],
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// All built-in snippets
  static List<TemplateSnippet> get all => [
        autofocusRoutine,
        lrgbFilterCycle,
        ditherAfterEach,
        safetyCheck,
        meridianFlipHandler,
      ];

  /// Get built-in snippets by category
  static List<TemplateSnippet> byCategory(SnippetCategory category) {
    return all.where((s) => s.category == category).toList();
  }

  /// Get a built-in snippet by ID
  static TemplateSnippet? byId(String id) {
    try {
      return all.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }
}
