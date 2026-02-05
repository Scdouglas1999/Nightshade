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
    description: 'Capture L, R, G, B filter sequence while dark',
    category: SnippetCategory.filterSequence,
    iconName: 'palette',
    nodeData: [
      {
        'nodeType': 'Loop',
        'name': 'LRGB Cycle',
        'conditionType': 'whileDark',
        'children': [
          {
            'nodeType': 'TakeExposure',
            'name': 'Luminance',
            'filter': 'L',
            'filterIndex': 0,
            'durationSecs': 120.0,
            'count': 1,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'Red',
            'filter': 'R',
            'filterIndex': 1,
            'durationSecs': 120.0,
            'count': 1,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'Green',
            'filter': 'G',
            'filterIndex': 2,
            'durationSecs': 120.0,
            'count': 1,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'Blue',
            'filter': 'B',
            'filterIndex': 3,
            'durationSecs': 120.0,
            'count': 1,
            'frameType': 'light',
          },
        ],
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// HFR-triggered autofocus - re-focus when HFR exceeds threshold
  static final hfrTriggeredAf = TemplateSnippet(
    id: 'builtin-hfr-triggered-af',
    name: 'HFR-Triggered AF',
    description: 'Re-focus when HFR exceeds threshold',
    category: SnippetCategory.autofocus,
    iconName: 'focus',
    nodeData: [
      {
        'nodeType': 'Conditional',
        'name': 'HFR Above Threshold',
        'conditionType': 'hfrAbove',
        'thresholdValue': 3.0,
        'children': [
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
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// Temperature-drift autofocus - re-focus on temperature change
  static final tempDriftAf = TemplateSnippet(
    id: 'builtin-temp-drift-af',
    name: 'Temperature-Drift AF',
    description: 'Re-focus on temperature change >2C',
    category: SnippetCategory.autofocus,
    iconName: 'focus',
    nodeData: [
      {
        'nodeType': 'Conditional',
        'name': 'Temperature Changed',
        'conditionType': 'temperatureChange',
        'thresholdValue': 2.0,
        'children': [
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
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// Per-filter autofocus with offsets - focus on L, apply offsets for RGB
  static final perFilterAf = TemplateSnippet(
    id: 'builtin-per-filter-af',
    name: 'Per-Filter AF Offsets',
    description: 'Autofocus on L, apply offsets for RGB',
    category: SnippetCategory.autofocus,
    iconName: 'focus',
    nodeData: [
      {
        'nodeType': 'InstructionSet',
        'name': 'Per-Filter AF',
        'children': [
          {
            'nodeType': 'ChangeFilter',
            'name': 'Switch to L',
            'filter': 'L',
            'filterIndex': 0,
          },
          {
            'nodeType': 'Autofocus',
            'name': 'Autofocus on L',
            'method': 'vCurve',
            'stepSize': 100,
            'stepsOut': 7,
            'exposuresPerPoint': 1,
            'exposureDuration': 3.0,
          },
          {
            'nodeType': 'FilterOffset',
            'name': 'R Filter Offset',
            'filter': 'R',
            'filterIndex': 1,
            'offsetSteps': 50,
          },
          {
            'nodeType': 'FilterOffset',
            'name': 'G Filter Offset',
            'filter': 'G',
            'filterIndex': 2,
            'offsetSteps': 25,
          },
          {
            'nodeType': 'FilterOffset',
            'name': 'B Filter Offset',
            'filter': 'B',
            'filterIndex': 3,
            'offsetSteps': 75,
          },
        ],
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// Aggressive dither - 10px dither for walking noise reduction
  static final aggressiveDither = TemplateSnippet(
    id: 'builtin-aggressive-dither',
    name: 'Aggressive Dither',
    description: '10px dither for walking noise reduction',
    category: SnippetCategory.dithering,
    iconName: 'move',
    nodeData: [
      {
        'nodeType': 'Dither',
        'name': 'Aggressive Dither',
        'pixels': 10.0,
        'settleTime': 45.0,
        'settlePixels': 1.0,
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// Gentle dither - 3px dither for fast settle time
  static final gentleDither = TemplateSnippet(
    id: 'builtin-gentle-dither',
    name: 'Gentle Dither',
    description: '3px dither for fast settle time',
    category: SnippetCategory.dithering,
    iconName: 'move',
    nodeData: [
      {
        'nodeType': 'Dither',
        'name': 'Gentle Dither',
        'pixels': 3.0,
        'settleTime': 20.0,
        'settlePixels': 2.0,
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// Dither every N exposures - dither after every 3 exposures
  static final ditherEveryN = TemplateSnippet(
    id: 'builtin-dither-every-n',
    name: 'Dither Every N',
    description: 'Dither after every 3 exposures',
    category: SnippetCategory.dithering,
    iconName: 'repeat',
    nodeData: [
      {
        'nodeType': 'InstructionSet',
        'name': 'Dither Every 3',
        'children': [
          {
            'nodeType': 'Loop',
            'name': 'Exposure Set',
            'count': 3,
            'children': [
              {
                'nodeType': 'TakeExposure',
                'name': 'Light Frame',
                'durationSecs': 120.0,
                'count': 1,
                'frameType': 'light',
              },
            ],
          },
          {
            'nodeType': 'Dither',
            'name': 'Dither',
            'pixels': 5.0,
            'settleTime': 30.0,
            'settlePixels': 1.5,
          },
        ],
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// Ha-OIII bicolor - two-filter narrowband imaging
  static final haOiiiBicolor = TemplateSnippet(
    id: 'builtin-ha-oiii-bicolor',
    name: 'Ha-OIII Bicolor',
    description: 'Two-filter narrowband imaging',
    category: SnippetCategory.filterSequence,
    iconName: 'filter',
    nodeData: [
      {
        'nodeType': 'Loop',
        'name': 'Ha-OIII Cycle',
        'conditionType': 'whileDark',
        'children': [
          {
            'nodeType': 'TakeExposure',
            'name': 'Ha',
            'filter': 'Ha',
            'filterIndex': 4,
            'durationSecs': 180.0,
            'count': 1,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'OIII',
            'filter': 'OIII',
            'filterIndex': 5,
            'durationSecs': 180.0,
            'count': 1,
            'frameType': 'light',
          },
        ],
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// SHO Hubble Palette - full narrowband imaging
  static final shoHubble = TemplateSnippet(
    id: 'builtin-sho-hubble',
    name: 'SHO Hubble Palette',
    description: 'Full narrowband SII, Ha, OIII imaging',
    category: SnippetCategory.filterSequence,
    iconName: 'star',
    nodeData: [
      {
        'nodeType': 'Loop',
        'name': 'SHO Cycle',
        'conditionType': 'whileDark',
        'children': [
          {
            'nodeType': 'TakeExposure',
            'name': 'SII',
            'filter': 'SII',
            'filterIndex': 6,
            'durationSecs': 180.0,
            'count': 1,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'Ha',
            'filter': 'Ha',
            'filterIndex': 4,
            'durationSecs': 180.0,
            'count': 1,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'OIII',
            'filter': 'OIII',
            'filterIndex': 5,
            'durationSecs': 180.0,
            'count': 1,
            'frameType': 'light',
          },
        ],
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// LRGB + Ha Enhanced - broadband with Ha accent
  static final lrgbHaEnhanced = TemplateSnippet(
    id: 'builtin-lrgb-ha-enhanced',
    name: 'LRGB + Ha Enhanced',
    description: 'Broadband LRGB with Ha accent',
    category: SnippetCategory.filterSequence,
    iconName: 'layers',
    nodeData: [
      {
        'nodeType': 'Loop',
        'name': 'LRGB+Ha Cycle',
        'conditionType': 'whileDark',
        'children': [
          {
            'nodeType': 'TakeExposure',
            'name': 'Luminance',
            'filter': 'L',
            'filterIndex': 0,
            'durationSecs': 120.0,
            'count': 1,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'Red',
            'filter': 'R',
            'filterIndex': 1,
            'durationSecs': 120.0,
            'count': 1,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'Green',
            'filter': 'G',
            'filterIndex': 2,
            'durationSecs': 120.0,
            'count': 1,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'Blue',
            'filter': 'B',
            'filterIndex': 3,
            'durationSecs': 120.0,
            'count': 1,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'Ha',
            'filter': 'Ha',
            'filterIndex': 4,
            'durationSecs': 180.0,
            'count': 1,
            'frameType': 'light',
          },
        ],
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// OSC No Filter - for one-shot color cameras
  static final oscNoFilter = TemplateSnippet(
    id: 'builtin-osc-no-filter',
    name: 'OSC No Filter',
    description: 'For one-shot color cameras without filters',
    category: SnippetCategory.filterSequence,
    iconName: 'camera',
    nodeData: [
      {
        'nodeType': 'Loop',
        'name': 'OSC Cycle',
        'conditionType': 'whileDark',
        'children': [
          {
            'nodeType': 'TakeExposure',
            'name': 'Light Frame',
            'durationSecs': 120.0,
            'count': 1,
            'frameType': 'light',
          },
        ],
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// Dual Narrowband - Ha and OIII rotation
  static final dualNarrowband = TemplateSnippet(
    id: 'builtin-dual-narrowband',
    name: 'Dual Narrowband',
    description: 'Ha and OIII filter rotation',
    category: SnippetCategory.filterSequence,
    iconName: 'zap',
    nodeData: [
      {
        'nodeType': 'Loop',
        'name': 'Dual NB Cycle',
        'conditionType': 'whileDark',
        'children': [
          {
            'nodeType': 'TakeExposure',
            'name': 'Ha',
            'filter': 'Ha',
            'filterIndex': 4,
            'durationSecs': 180.0,
            'count': 1,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'OIII',
            'filter': 'OIII',
            'filterIndex': 5,
            'durationSecs': 180.0,
            'count': 1,
            'frameType': 'light',
          },
        ],
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// RGB Only - no luminance channel
  static final rgbOnly = TemplateSnippet(
    id: 'builtin-rgb-only',
    name: 'RGB Only',
    description: 'RGB imaging without luminance channel',
    category: SnippetCategory.filterSequence,
    iconName: 'grid',
    nodeData: [
      {
        'nodeType': 'Loop',
        'name': 'RGB Cycle',
        'conditionType': 'whileDark',
        'children': [
          {
            'nodeType': 'TakeExposure',
            'name': 'Red',
            'filter': 'R',
            'filterIndex': 1,
            'durationSecs': 120.0,
            'count': 1,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'Green',
            'filter': 'G',
            'filterIndex': 2,
            'durationSecs': 120.0,
            'count': 1,
            'frameType': 'light',
          },
          {
            'nodeType': 'TakeExposure',
            'name': 'Blue',
            'filter': 'B',
            'filterIndex': 3,
            'durationSecs': 120.0,
            'count': 1,
            'frameType': 'light',
          },
        ],
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// Weather Pause - pause and retry on bad weather
  static final weatherPause = TemplateSnippet(
    id: 'builtin-weather-pause',
    name: 'Weather Pause',
    description: 'Pause and park on unsafe weather, resume when safe',
    category: SnippetCategory.safety,
    iconName: 'cloud-off',
    nodeData: [
      {
        'nodeType': 'Conditional',
        'name': 'Weather Unsafe',
        'conditionType': 'weatherUnsafe',
        'children': [
          {
            'nodeType': 'InstructionSet',
            'name': 'Weather Response',
            'children': [
              {
                'nodeType': 'StopGuiding',
                'name': 'Stop Guiding',
              },
              {
                'nodeType': 'Park',
                'name': 'Park Mount',
                'waitUntilParked': true,
              },
              {
                'nodeType': 'Loop',
                'name': 'Wait for Safe Weather',
                'conditionType': 'whileWeatherUnsafe',
                'children': [
                  {
                    'nodeType': 'WaitTime',
                    'name': 'Wait 5 Minutes',
                    'durationMinutes': 5.0,
                  },
                ],
              },
              {
                'nodeType': 'Unpark',
                'name': 'Unpark Mount',
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
      },
    ],
    isBuiltIn: true,
    createdAt: DateTime(2024, 1, 1),
  );

  /// Guiding Recovery - auto-restart guiding on failure
  static final guidingRecovery = TemplateSnippet(
    id: 'builtin-guiding-recovery',
    name: 'Guiding Recovery',
    description: 'Auto-restart guiding on failure with retries',
    category: SnippetCategory.safety,
    iconName: 'refresh-cw',
    nodeData: [
      {
        'nodeType': 'Recovery',
        'name': 'Guiding Recovery',
        'maxRetries': 3,
        'retryDelaySeconds': 5.0,
        'children': [
          {
            'nodeType': 'InstructionSet',
            'name': 'Restart Guiding',
            'children': [
              {
                'nodeType': 'StopGuiding',
                'name': 'Stop Guiding',
              },
              {
                'nodeType': 'WaitTime',
                'name': 'Wait Before Restart',
                'durationMinutes': 0.5,
              },
              {
                'nodeType': 'StartGuiding',
                'name': 'Start Guiding',
                'settlePixels': 1.5,
                'settleTime': 10.0,
                'settleTimeout': 60.0,
                'autoSelectStar': true,
              },
              {
                'nodeType': 'Dither',
                'name': 'Settle Dither',
                'pixels': 3.0,
                'settleTime': 15.0,
                'settlePixels': 1.5,
              },
            ],
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
        // Autofocus snippets
        autofocusRoutine,
        hfrTriggeredAf,
        tempDriftAf,
        perFilterAf,
        // Dithering snippets
        ditherAfterEach,
        aggressiveDither,
        gentleDither,
        ditherEveryN,
        // Filter sequence snippets
        lrgbFilterCycle,
        haOiiiBicolor,
        shoHubble,
        lrgbHaEnhanced,
        oscNoFilter,
        dualNarrowband,
        rgbOnly,
        // Safety snippets
        safetyCheck,
        weatherPause,
        guidingRecovery,
        // Calibration snippets
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
