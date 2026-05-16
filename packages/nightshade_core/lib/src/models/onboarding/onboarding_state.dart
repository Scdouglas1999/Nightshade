import 'dart:convert';

import '../backend/device_types.dart';

/// Steps of the equipment-onboarding wizard in display order.
///
/// Why an explicit enum instead of an index: the wizard skips optional
/// steps based on the user's selections (e.g. focuser/filter wheel). Using
/// an enum lets [OnboardingDraft] persist which logical step the user is
/// on, even if the rendered step order changes between sessions.
enum OnboardingStep {
  welcome,
  drivers,
  camera,
  mount,
  focuser,
  filterWheel,
  guider,
  opticalTrain,
  captureDir,
  summary,
}

extension OnboardingStepOrder on OnboardingStep {
  /// Sequential index used for the progress dots in the wizard footer.
  int get order => OnboardingStep.values.indexOf(this);

  /// Total number of steps (constant; used for the "Step N of 10" label).
  static int get total => OnboardingStep.values.length;

  /// True for steps the user is allowed to skip without affecting profile
  /// validity. The wizard still renders them, but the Skip button is only
  /// visible (and only commits a null device id) on these.
  bool get isOptional {
    switch (this) {
      case OnboardingStep.focuser:
      case OnboardingStep.filterWheel:
      case OnboardingStep.guider:
        return true;
      case OnboardingStep.welcome:
      case OnboardingStep.drivers:
      case OnboardingStep.camera:
      case OnboardingStep.mount:
      case OnboardingStep.opticalTrain:
      case OnboardingStep.captureDir:
      case OnboardingStep.summary:
        return false;
    }
  }
}

/// Draft state for the equipment-onboarding wizard.
///
/// Persisted as JSON in `tutorial_progress.category =
/// OnboardingDraft.persistenceCategory`, with the JSON blob stored in a
/// separate app_settings row so the existing tutorial_progress schema does
/// not need a new column. The wizard reads and writes through
/// [OnboardingNotifier], which serializes via [toJson] / [fromJson].
///
/// Why a plain class instead of freezed: the wizard only mutates state via
/// copyWith and we want this model importable from tests without invoking
/// build_runner. Equality and hashCode are defined manually so widget
/// tests can assert on state without identity reference checks.
class OnboardingDraft {
  /// Category key used to mark the wizard as completed in
  /// `tutorial_progress`. Distinct from the first-night tutorial category
  /// so the two flows do not collide.
  static const String persistenceCategory = 'equipmentOnboarding';

  /// app_settings key under which the JSON draft is stored. Wiped when the
  /// user completes or dismisses the wizard so a fresh run starts clean.
  static const String draftSettingsKey = 'equipment_onboarding_draft';

  /// Current step the user is on. Survives an app restart mid-wizard.
  final OnboardingStep currentStep;

  /// Drivers the user opted to use for discovery. Multi-select.
  final Set<DriverType> selectedDrivers;

  /// Device ids picked at each step, keyed by the device-type slug. We use
  /// the slug rather than [DeviceType] so that the JSON form is stable
  /// across enum reorderings.
  final String? cameraId;
  final String? cameraName;
  final String? mountId;
  final String? mountName;
  final String? focuserId;
  final String? focuserName;
  final String? filterWheelId;
  final String? filterWheelName;
  final String? guiderId;
  final String? guiderName;

  /// Optical-train inputs. Pixel size is microns, focal length and
  /// aperture are millimeters, reducer is a multiplier (1.0 = no reducer).
  final double? pixelSizeMicrons;
  final double? focalLengthMm;
  final double? apertureMm;
  final double reducerFactor;

  /// Filter names captured per slot when a filter wheel is configured.
  /// Empty list when no filter wheel is selected.
  final List<String> filterNames;

  /// Capture directory the user picked. Validated writable before being
  /// committed to settings on the summary step.
  final String? captureDirectory;

  /// Profile name on the summary step. Defaulted to "My First Rig" the
  /// first time the summary renders, but the user can override it.
  final String? profileName;

  const OnboardingDraft({
    this.currentStep = OnboardingStep.welcome,
    this.selectedDrivers = const {},
    this.cameraId,
    this.cameraName,
    this.mountId,
    this.mountName,
    this.focuserId,
    this.focuserName,
    this.filterWheelId,
    this.filterWheelName,
    this.guiderId,
    this.guiderName,
    this.pixelSizeMicrons,
    this.focalLengthMm,
    this.apertureMm,
    this.reducerFactor = 1.0,
    this.filterNames = const [],
    this.captureDirectory,
    this.profileName,
  });

  OnboardingDraft copyWith({
    OnboardingStep? currentStep,
    Set<DriverType>? selectedDrivers,
    String? cameraId,
    String? cameraName,
    String? mountId,
    String? mountName,
    String? focuserId,
    String? focuserName,
    String? filterWheelId,
    String? filterWheelName,
    String? guiderId,
    String? guiderName,
    double? pixelSizeMicrons,
    double? focalLengthMm,
    double? apertureMm,
    double? reducerFactor,
    List<String>? filterNames,
    String? captureDirectory,
    String? profileName,
    bool clearCamera = false,
    bool clearMount = false,
    bool clearFocuser = false,
    bool clearFilterWheel = false,
    bool clearGuider = false,
  }) {
    return OnboardingDraft(
      currentStep: currentStep ?? this.currentStep,
      selectedDrivers: selectedDrivers ?? this.selectedDrivers,
      cameraId: clearCamera ? null : (cameraId ?? this.cameraId),
      cameraName: clearCamera ? null : (cameraName ?? this.cameraName),
      mountId: clearMount ? null : (mountId ?? this.mountId),
      mountName: clearMount ? null : (mountName ?? this.mountName),
      focuserId: clearFocuser ? null : (focuserId ?? this.focuserId),
      focuserName: clearFocuser ? null : (focuserName ?? this.focuserName),
      filterWheelId:
          clearFilterWheel ? null : (filterWheelId ?? this.filterWheelId),
      filterWheelName:
          clearFilterWheel ? null : (filterWheelName ?? this.filterWheelName),
      guiderId: clearGuider ? null : (guiderId ?? this.guiderId),
      guiderName: clearGuider ? null : (guiderName ?? this.guiderName),
      pixelSizeMicrons: pixelSizeMicrons ?? this.pixelSizeMicrons,
      focalLengthMm: focalLengthMm ?? this.focalLengthMm,
      apertureMm: apertureMm ?? this.apertureMm,
      reducerFactor: reducerFactor ?? this.reducerFactor,
      filterNames: filterNames ?? this.filterNames,
      captureDirectory: captureDirectory ?? this.captureDirectory,
      profileName: profileName ?? this.profileName,
    );
  }

  /// Effective focal length after applying the reducer factor.
  /// Returns null if focal length is unset so callers don't have to guard.
  double? get effectiveFocalLengthMm {
    if (focalLengthMm == null) return null;
    return focalLengthMm! * reducerFactor;
  }

  /// Image scale in arcsec/pixel from pixel size + effective focal length.
  /// Formula: 206.265 * pixel_microns / focal_length_mm.
  /// Returns null when inputs are missing or focal length is zero so the
  /// UI can render "--" instead of a misleading "0.00".
  double? get imageScaleArcsecPerPixel {
    final fl = effectiveFocalLengthMm;
    if (fl == null || fl <= 0) return null;
    if (pixelSizeMicrons == null || pixelSizeMicrons! <= 0) return null;
    return 206.265 * pixelSizeMicrons! / fl;
  }

  Map<String, dynamic> toJson() => {
        'currentStep': currentStep.name,
        'selectedDrivers': selectedDrivers.map((d) => d.name).toList(),
        'cameraId': cameraId,
        'cameraName': cameraName,
        'mountId': mountId,
        'mountName': mountName,
        'focuserId': focuserId,
        'focuserName': focuserName,
        'filterWheelId': filterWheelId,
        'filterWheelName': filterWheelName,
        'guiderId': guiderId,
        'guiderName': guiderName,
        'pixelSizeMicrons': pixelSizeMicrons,
        'focalLengthMm': focalLengthMm,
        'apertureMm': apertureMm,
        'reducerFactor': reducerFactor,
        'filterNames': filterNames,
        'captureDirectory': captureDirectory,
        'profileName': profileName,
      };

  /// Deserialize a draft. Returns the default draft on parse failure so a
  /// corrupted settings row never wedges the wizard — the user just starts
  /// over.
  factory OnboardingDraft.fromJson(Map<String, dynamic> json) {
    OnboardingStep parseStep(String? name) {
      for (final s in OnboardingStep.values) {
        if (s.name == name) return s;
      }
      return OnboardingStep.welcome;
    }

    Set<DriverType> parseDrivers(dynamic raw) {
      if (raw is! List) return const {};
      final result = <DriverType>{};
      for (final entry in raw) {
        if (entry is! String) continue;
        for (final d in DriverType.values) {
          if (d.name == entry) {
            result.add(d);
            break;
          }
        }
      }
      return result;
    }

    List<String> parseFilters(dynamic raw) {
      if (raw is! List) return const [];
      return raw.whereType<String>().toList();
    }

    return OnboardingDraft(
      currentStep: parseStep(json['currentStep'] as String?),
      selectedDrivers: parseDrivers(json['selectedDrivers']),
      cameraId: json['cameraId'] as String?,
      cameraName: json['cameraName'] as String?,
      mountId: json['mountId'] as String?,
      mountName: json['mountName'] as String?,
      focuserId: json['focuserId'] as String?,
      focuserName: json['focuserName'] as String?,
      filterWheelId: json['filterWheelId'] as String?,
      filterWheelName: json['filterWheelName'] as String?,
      guiderId: json['guiderId'] as String?,
      guiderName: json['guiderName'] as String?,
      pixelSizeMicrons: (json['pixelSizeMicrons'] as num?)?.toDouble(),
      focalLengthMm: (json['focalLengthMm'] as num?)?.toDouble(),
      apertureMm: (json['apertureMm'] as num?)?.toDouble(),
      reducerFactor: (json['reducerFactor'] as num?)?.toDouble() ?? 1.0,
      filterNames: parseFilters(json['filterNames']),
      captureDirectory: json['captureDirectory'] as String?,
      profileName: json['profileName'] as String?,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  /// Parses a JSON-encoded draft; returns a fresh draft if the string is
  /// null, empty, or not valid JSON. Errors are swallowed here on purpose:
  /// the draft is purely an optimization, never a source of truth.
  static OnboardingDraft fromJsonStringOrEmpty(String? raw) {
    if (raw == null || raw.isEmpty) return const OnboardingDraft();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const OnboardingDraft();
      return OnboardingDraft.fromJson(decoded);
    } catch (_) {
      return const OnboardingDraft();
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OnboardingDraft &&
        other.currentStep == currentStep &&
        _setEquals(other.selectedDrivers, selectedDrivers) &&
        other.cameraId == cameraId &&
        other.cameraName == cameraName &&
        other.mountId == mountId &&
        other.mountName == mountName &&
        other.focuserId == focuserId &&
        other.focuserName == focuserName &&
        other.filterWheelId == filterWheelId &&
        other.filterWheelName == filterWheelName &&
        other.guiderId == guiderId &&
        other.guiderName == guiderName &&
        other.pixelSizeMicrons == pixelSizeMicrons &&
        other.focalLengthMm == focalLengthMm &&
        other.apertureMm == apertureMm &&
        other.reducerFactor == reducerFactor &&
        _listEquals(other.filterNames, filterNames) &&
        other.captureDirectory == captureDirectory &&
        other.profileName == profileName;
  }

  @override
  int get hashCode => Object.hash(
        currentStep,
        Object.hashAllUnordered(selectedDrivers),
        cameraId,
        mountId,
        focuserId,
        filterWheelId,
        guiderId,
        pixelSizeMicrons,
        focalLengthMm,
        apertureMm,
        reducerFactor,
        Object.hashAll(filterNames),
        captureDirectory,
        profileName,
      );
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
