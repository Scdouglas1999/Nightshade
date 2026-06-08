import 'dart:convert';

/// Geometric transform model used to register subs onto the reference grid.
///
/// Mirrors the native `registration::TransformKind` accepted by the
/// `api_integrate_session` JSON contract (`"similarity"` / `"affine"` /
/// `"homography"`).
enum TransformModel {
  /// 4 dof — translation + rotation + uniform scale. Minimal sample 2 pairs.
  similarity,

  /// 6 dof — handles small differential field rotation + plate-scale drift.
  /// The default for most rigs.
  affine,

  /// 8 dof projective — for wide fields / uncorrected optics.
  homography;

  /// Wire token consumed by the native `align.model` field.
  String get wire {
    switch (this) {
      case TransformModel.similarity:
        return 'similarity';
      case TransformModel.affine:
        return 'affine';
      case TransformModel.homography:
        return 'homography';
    }
  }

  static TransformModel fromWire(String value) {
    switch (value) {
      case 'similarity':
        return TransformModel.similarity;
      case 'affine':
        return TransformModel.affine;
      case 'homography':
        return TransformModel.homography;
      default:
        throw ArgumentError.value(value, 'value', 'unknown TransformModel');
    }
  }
}

/// Output-pixel interpolation kernel used when resampling a sub onto the
/// reference grid. Mirrors native `registration::Interpolator`.
enum Resampler {
  /// Fast, live-parity bilinear.
  bilinear,

  /// Cubic Catmull-Rom — good sharpness / ringing tradeoff.
  catmullRom,

  /// Windowed-sinc Lanczos (a=3). Highest quality; the PixInsight default.
  lanczos3;

  String get wire {
    switch (this) {
      case Resampler.bilinear:
        return 'bilinear';
      case Resampler.catmullRom:
        return 'catmullRom';
      case Resampler.lanczos3:
        return 'lanczos3';
    }
  }

  static Resampler fromWire(String value) {
    switch (value) {
      case 'bilinear':
        return Resampler.bilinear;
      case 'catmullRom':
        return Resampler.catmullRom;
      case 'lanczos3':
        return Resampler.lanczos3;
      default:
        throw ArgumentError.value(value, 'value', 'unknown Resampler');
    }
  }
}

/// Per-sub weighting formula. Mirrors native `frame_weighting::WeightFormula`.
enum WeightFormula {
  /// Weight ∝ SNR.
  snr,

  /// Weight ∝ SNR² (PixInsight PSF-Signal-Weight spirit). The default.
  snrSquared,

  /// Weight ∝ (fwhm_ref / fwhm).
  fwhmInverse,

  /// Custom exponents over SNR / FWHM / eccentricity.
  custom;

  String get wire {
    switch (this) {
      case WeightFormula.snr:
        return 'snr';
      case WeightFormula.snrSquared:
        return 'snrSquared';
      case WeightFormula.fwhmInverse:
        return 'fwhmInverse';
      case WeightFormula.custom:
        return 'custom';
    }
  }

  static WeightFormula fromWire(String value) {
    switch (value) {
      case 'snr':
        return WeightFormula.snr;
      case 'snrSquared':
        return WeightFormula.snrSquared;
      case 'fwhmInverse':
        return WeightFormula.fwhmInverse;
      case 'custom':
        return WeightFormula.custom;
      default:
        throw ArgumentError.value(value, 'value', 'unknown WeightFormula');
    }
  }
}

/// Photometric normalization mode applied before integration. Mirrors native
/// `normalization::NormMode`.
enum NormalizationMode {
  /// One global additive + multiplicative coefficient per channel.
  global,

  /// A coarse additive+multiplicative grid (bilinearly interpolated) to soak up
  /// gradient drift through the night. The "long night / moving moon" preset.
  local;

  String get wire {
    switch (this) {
      case NormalizationMode.global:
        return 'global';
      case NormalizationMode.local:
        return 'local';
    }
  }

  static NormalizationMode fromWire(String value) {
    switch (value) {
      case 'global':
        return NormalizationMode.global;
      case 'local':
        return NormalizationMode.local;
      default:
        throw ArgumentError.value(value, 'value', 'unknown NormalizationMode');
    }
  }
}

/// Pixel combination operator. Mirrors native `integration::Combine`.
enum CombineMode {
  mean,
  median;

  String get wire => this == CombineMode.mean ? 'mean' : 'median';

  static CombineMode fromWire(String value) {
    switch (value) {
      case 'mean':
        return CombineMode.mean;
      case 'median':
        return CombineMode.median;
      default:
        throw ArgumentError.value(value, 'value', 'unknown CombineMode');
    }
  }
}

/// Pixel rejection algorithm. Mirrors native `integration::Reject` plus the
/// JSON-contract `"auto"` sentinel (the native side resolves `"auto"` by sub
/// count: `<8 → percentile`, `8–24 → winsorizedSigma`, `≥25 → linearFit`).
enum RejectAlgorithm {
  /// Let the engine pick by sub count (the smart default).
  auto,
  none,
  sigmaClip,
  winsorizedSigma,
  linearFit,
  percentile,
  minMax;

  String get wire {
    switch (this) {
      case RejectAlgorithm.auto:
        return 'auto';
      case RejectAlgorithm.none:
        return 'none';
      case RejectAlgorithm.sigmaClip:
        return 'sigmaClip';
      case RejectAlgorithm.winsorizedSigma:
        return 'winsorizedSigma';
      case RejectAlgorithm.linearFit:
        return 'linearFit';
      case RejectAlgorithm.percentile:
        return 'percentile';
      case RejectAlgorithm.minMax:
        return 'minMax';
    }
  }

  static RejectAlgorithm fromWire(String value) {
    switch (value) {
      case 'auto':
        return RejectAlgorithm.auto;
      case 'none':
        return RejectAlgorithm.none;
      case 'sigmaClip':
        return RejectAlgorithm.sigmaClip;
      case 'winsorizedSigma':
        return RejectAlgorithm.winsorizedSigma;
      case 'linearFit':
        return RejectAlgorithm.linearFit;
      case 'percentile':
        return RejectAlgorithm.percentile;
      case 'minMax':
        return RejectAlgorithm.minMax;
      default:
        throw ArgumentError.value(value, 'value', 'unknown RejectAlgorithm');
    }
  }

  /// The algorithm the native `"auto"` rule would resolve to for [subCount].
  /// Pure mirror of the documented native rule, exposed so the settings UI can
  /// show the operator *which* algorithm a given night will actually use.
  static RejectAlgorithm resolveAuto(int subCount) {
    if (subCount < 8) return RejectAlgorithm.percentile;
    if (subCount < 25) return RejectAlgorithm.winsorizedSigma;
    return RejectAlgorithm.linearFit;
  }
}

/// Output sample format of the integrated master.
enum OutputBitDepth {
  /// Archival linear 32-bit float (default — no quantisation).
  f32,

  /// 16-bit unsigned (smaller, lossy).
  u16;

  String get wire => this == OutputBitDepth.f32 ? 'f32' : 'u16';

  static OutputBitDepth fromWire(String value) {
    switch (value) {
      case 'f32':
        return OutputBitDepth.f32;
      case 'u16':
        return OutputBitDepth.u16;
      default:
        throw ArgumentError.value(value, 'value', 'unknown OutputBitDepth');
    }
  }
}

/// Named smart-default presets for [IntegrationSettings].
///
/// Each preset is a curated point in the (speed ↔ quality) tradeoff space; the
/// [IntegrationSettings.preset] factory materialises one. `balanced` is the
/// app-wide default.
enum IntegrationPreset {
  /// Fast: bilinear resample, lighter weighting — for quick look / huge sub
  /// counts where the user accepts a sharpness hit for speed.
  fast,

  /// Balanced (default): Lanczos-3, SNR² weighting, auto rejection, global
  /// normalization. The everyday archival setting.
  balanced,

  /// Maximum quality: Lanczos-3, SNR² weighting, auto rejection, generates the
  /// rejection map, f32 output. (Distortion/drizzle remain off by default —
  /// they need real-data tuning, see the design doc's honest deferrals.)
  maximumQuality,

  /// Few subs (<8): percentile-clip rejection, which is robust when the sample
  /// column is too short for sigma statistics.
  fewSubs,

  /// Long night / moving gradient: local normalization grid to track sky-glow
  /// drift through the session.
  longNightGradient;

  /// Stable wire token for persistence.
  String get wire {
    switch (this) {
      case IntegrationPreset.fast:
        return 'fast';
      case IntegrationPreset.balanced:
        return 'balanced';
      case IntegrationPreset.maximumQuality:
        return 'maximumQuality';
      case IntegrationPreset.fewSubs:
        return 'fewSubs';
      case IntegrationPreset.longNightGradient:
        return 'longNightGradient';
    }
  }

  static IntegrationPreset? fromWire(String value) {
    for (final p in IntegrationPreset.values) {
      if (p.wire == value) return p;
    }
    return null;
  }

  /// Human-facing label.
  String get label {
    switch (this) {
      case IntegrationPreset.fast:
        return 'Fast';
      case IntegrationPreset.balanced:
        return 'Balanced';
      case IntegrationPreset.maximumQuality:
        return 'Maximum Quality';
      case IntegrationPreset.fewSubs:
        return 'Few Subs';
      case IntegrationPreset.longNightGradient:
        return 'Long Night / Gradient';
    }
  }
}

/// Immutable, fully-specified settings for one post-session batch integration
/// run — every advanced knob the native `api_integrate_session` pipeline
/// exposes, with smart defaults.
///
/// The model is the single source of truth the [PostSessionIntegrationService]
/// serialises into the native JSON `settings` block. It is intentionally a flat
/// value type (not freezed-generated, to avoid a codegen dependency in
/// `nightshade_core`) with value equality, `copyWith`, JSON round-trip, and
/// named presets.
///
/// JSON layout (`toBridgeSettings`) matches the native
/// `IntegrationSettingsArgs`:
/// `{ align:{...}, weighting:{...}, normalization:{...}, integration:{...} }`.
class IntegrationSettings {
  // --- Alignment ---
  /// Geometric transform model. Default: [TransformModel.affine].
  final TransformModel model;

  /// Resampling kernel. Default: [Resampler.lanczos3].
  final Resampler resampler;

  /// RANSAC inlier threshold in reference pixels. Default 2.0.
  final double ransacThresholdPx;

  /// Brightest-N reference stars used for matching. Default 60.
  final int maxRefStars;

  // --- Weighting ---
  /// Whether per-sub weighting is applied. Default true.
  final bool weightingEnabled;

  /// Weighting formula. Default [WeightFormula.snrSquared].
  final WeightFormula weighting;

  /// Custom SNR exponent (used only when [weighting] == custom). Default 2.0.
  final double snrPow;

  /// Custom FWHM exponent (used only when [weighting] == custom). Default 1.0.
  final double fwhmPow;

  /// Custom eccentricity exponent (custom only). Default 1.0.
  final double eccPow;

  // --- Normalization ---
  /// Whether normalization to the reference is applied. Default true.
  final bool normalizationEnabled;

  /// Normalization mode. Default [NormalizationMode.global].
  final NormalizationMode normalization;

  /// Local-grid rows (mode == local only). Default 8.
  final int localRows;

  /// Local-grid cols (mode == local only). Default 8.
  final int localCols;

  // --- Integration ---
  /// Pixel combine operator. Default [CombineMode.mean].
  final CombineMode combine;

  /// Rejection algorithm. Default [RejectAlgorithm.auto].
  final RejectAlgorithm reject;

  /// Low rejection threshold (σ for sigma family, fraction for percentile).
  /// Default 3.0.
  final double rejectLow;

  /// High rejection threshold. Default 3.0.
  final double rejectHigh;

  /// MinMax low count (reject == minMax only). Default 1.
  final int minMaxLow;

  /// MinMax high count (reject == minMax only). Default 1.
  final int minMaxHigh;

  /// Emit the per-pixel rejection-count map alongside the master. Default true.
  final bool generateRejectionMap;

  /// Apply self-derived cosmetic (hot/cold transient) correction per light
  /// before registration. Default true.
  final bool cosmeticCorrection;

  /// Output sample format. Default [OutputBitDepth.f32].
  final OutputBitDepth outputBitDepth;

  // --- Cull recommendation (advisory; consumed by the UI, not the native side) ---
  /// Whether to recommend an auto-cull of the worst subs. Default true.
  final bool autoCull;

  /// Cull percentile (drop subs below this weight percentile, 0..1). Default
  /// 0.10 (worst 10%).
  final double cullPercentile;

  /// The preset this configuration was materialised from, or null if it was
  /// hand-edited away from any preset. Persisted for UI round-trip only.
  final IntegrationPreset? sourcePreset;

  const IntegrationSettings({
    this.model = TransformModel.affine,
    this.resampler = Resampler.lanczos3,
    this.ransacThresholdPx = 2.0,
    this.maxRefStars = 60,
    this.weightingEnabled = true,
    this.weighting = WeightFormula.snrSquared,
    this.snrPow = 2.0,
    this.fwhmPow = 1.0,
    this.eccPow = 1.0,
    this.normalizationEnabled = true,
    this.normalization = NormalizationMode.global,
    this.localRows = 8,
    this.localCols = 8,
    this.combine = CombineMode.mean,
    this.reject = RejectAlgorithm.auto,
    this.rejectLow = 3.0,
    this.rejectHigh = 3.0,
    this.minMaxLow = 1,
    this.minMaxHigh = 1,
    this.generateRejectionMap = true,
    this.cosmeticCorrection = true,
    this.outputBitDepth = OutputBitDepth.f32,
    this.autoCull = true,
    this.cullPercentile = 0.10,
    this.sourcePreset,
  });

  /// The app-wide default (== [IntegrationPreset.balanced]).
  static const IntegrationSettings defaults = IntegrationSettings(
    sourcePreset: IntegrationPreset.balanced,
  );

  /// Materialise a named [preset].
  factory IntegrationSettings.preset(IntegrationPreset preset) {
    switch (preset) {
      case IntegrationPreset.fast:
        return const IntegrationSettings(
          resampler: Resampler.bilinear,
          weighting: WeightFormula.snr,
          generateRejectionMap: false,
          cosmeticCorrection: false,
          sourcePreset: IntegrationPreset.fast,
        );
      case IntegrationPreset.balanced:
        return const IntegrationSettings(
          sourcePreset: IntegrationPreset.balanced,
        );
      case IntegrationPreset.maximumQuality:
        return const IntegrationSettings(
          resampler: Resampler.lanczos3,
          weighting: WeightFormula.snrSquared,
          generateRejectionMap: true,
          cosmeticCorrection: true,
          outputBitDepth: OutputBitDepth.f32,
          sourcePreset: IntegrationPreset.maximumQuality,
        );
      case IntegrationPreset.fewSubs:
        return const IntegrationSettings(
          reject: RejectAlgorithm.percentile,
          // Percentile thresholds are fractions in (0, 1), not σ.
          rejectLow: 0.2,
          rejectHigh: 0.1,
          sourcePreset: IntegrationPreset.fewSubs,
        );
      case IntegrationPreset.longNightGradient:
        return const IntegrationSettings(
          normalization: NormalizationMode.local,
          sourcePreset: IntegrationPreset.longNightGradient,
        );
    }
  }

  /// Build settings with the *smart* knobs auto-chosen from the sub population.
  ///
  /// This is the "smart" entry point: it starts from [IntegrationPreset.balanced]
  /// and adapts the few knobs that genuinely depend on the data:
  ///
  /// - **Rejection** is left as [RejectAlgorithm.auto] (the native side then
  ///   resolves it by [subCount]); the resolved algorithm is surfaced via
  ///   [resolvedReject].
  /// - **Percentile thresholds** are substituted when `subCount < 8` so the
  ///   in-(0,1) fractions are used instead of σ.
  /// - **Normalization** switches to [NormalizationMode.local] when
  ///   [longNight] is set (gradient drift through the night).
  /// - **Resampler** drops to bilinear only when [preferSpeed] is set (e.g. a
  ///   very large sub count where the user opted for the Fast preset).
  ///
  /// Distortion correction and drizzle stay OFF: they are algorithmically sound
  /// but need real-data tuning (see the design doc), so smart defaults never
  /// silently enable them.
  factory IntegrationSettings.smartDefaults({
    required int subCount,
    bool longNight = false,
    bool preferSpeed = false,
  }) {
    final base = preferSpeed
        ? IntegrationSettings.preset(IntegrationPreset.fast)
        : IntegrationSettings.preset(IntegrationPreset.balanced);

    final wantsPercentile = subCount < 8;
    return base.copyWith(
      reject: RejectAlgorithm.auto,
      rejectLow: wantsPercentile ? 0.2 : base.rejectLow,
      rejectHigh: wantsPercentile ? 0.1 : base.rejectHigh,
      normalization:
          longNight ? NormalizationMode.local : base.normalization,
      // A hand-tuned smart config is no longer tied to a single named preset.
      clearSourcePreset: true,
    );
  }

  /// The concrete rejection algorithm this configuration will use for a stack of
  /// [subCount] subs (resolving [RejectAlgorithm.auto] via the native rule).
  RejectAlgorithm resolvedReject(int subCount) {
    if (reject == RejectAlgorithm.auto) {
      return RejectAlgorithm.resolveAuto(subCount);
    }
    return reject;
  }

  IntegrationSettings copyWith({
    TransformModel? model,
    Resampler? resampler,
    double? ransacThresholdPx,
    int? maxRefStars,
    bool? weightingEnabled,
    WeightFormula? weighting,
    double? snrPow,
    double? fwhmPow,
    double? eccPow,
    bool? normalizationEnabled,
    NormalizationMode? normalization,
    int? localRows,
    int? localCols,
    CombineMode? combine,
    RejectAlgorithm? reject,
    double? rejectLow,
    double? rejectHigh,
    int? minMaxLow,
    int? minMaxHigh,
    bool? generateRejectionMap,
    bool? cosmeticCorrection,
    OutputBitDepth? outputBitDepth,
    bool? autoCull,
    double? cullPercentile,
    IntegrationPreset? sourcePreset,
    bool clearSourcePreset = false,
  }) {
    return IntegrationSettings(
      model: model ?? this.model,
      resampler: resampler ?? this.resampler,
      ransacThresholdPx: ransacThresholdPx ?? this.ransacThresholdPx,
      maxRefStars: maxRefStars ?? this.maxRefStars,
      weightingEnabled: weightingEnabled ?? this.weightingEnabled,
      weighting: weighting ?? this.weighting,
      snrPow: snrPow ?? this.snrPow,
      fwhmPow: fwhmPow ?? this.fwhmPow,
      eccPow: eccPow ?? this.eccPow,
      normalizationEnabled: normalizationEnabled ?? this.normalizationEnabled,
      normalization: normalization ?? this.normalization,
      localRows: localRows ?? this.localRows,
      localCols: localCols ?? this.localCols,
      combine: combine ?? this.combine,
      reject: reject ?? this.reject,
      rejectLow: rejectLow ?? this.rejectLow,
      rejectHigh: rejectHigh ?? this.rejectHigh,
      minMaxLow: minMaxLow ?? this.minMaxLow,
      minMaxHigh: minMaxHigh ?? this.minMaxHigh,
      generateRejectionMap: generateRejectionMap ?? this.generateRejectionMap,
      cosmeticCorrection: cosmeticCorrection ?? this.cosmeticCorrection,
      outputBitDepth: outputBitDepth ?? this.outputBitDepth,
      autoCull: autoCull ?? this.autoCull,
      cullPercentile: cullPercentile ?? this.cullPercentile,
      sourcePreset:
          clearSourcePreset ? null : (sourcePreset ?? this.sourcePreset),
    );
  }

  /// The native `settings` block for `api_integrate_session` /
  /// `api_master_accumulate` (the `IntegrationSettingsArgs` shape). Keys are
  /// camelCase to match the native `#[serde(rename_all = "camelCase")]`.
  ///
  /// `cosmeticCorrection` is intentionally NOT in this map — it lives on the
  /// native `calibration` block, and [PostSessionIntegrationService] places it
  /// there.
  Map<String, dynamic> toBridgeSettings() {
    return {
      'align': {
        'model': model.wire,
        'resampler': resampler.wire,
        'ransacThresholdPx': ransacThresholdPx,
        'maxRefStars': maxRefStars,
      },
      'weighting': {
        'enabled': weightingEnabled,
        'formula': weighting.wire,
        'snrPow': snrPow,
        'fwhmPow': fwhmPow,
        'eccPow': eccPow,
      },
      'normalization': {
        'enabled': normalizationEnabled,
        'mode': normalization.wire,
        'localRows': localRows,
        'localCols': localCols,
      },
      'integration': {
        'combine': combine.wire,
        'reject': reject.wire,
        'rejectLow': rejectLow,
        'rejectHigh': rejectHigh,
        'minMaxLow': minMaxLow,
        'minMaxHigh': minMaxHigh,
        'generateRejectionMap': generateRejectionMap,
        'outputBitDepth': outputBitDepth.wire,
      },
    };
  }

  /// Full persistence map (every knob, including the advisory cull knobs and the
  /// source preset). Stored as JSON in the `integrated_masters.settings_json`
  /// column and the app-settings default key.
  Map<String, dynamic> toJson() {
    return {
      'model': model.wire,
      'resampler': resampler.wire,
      'ransacThresholdPx': ransacThresholdPx,
      'maxRefStars': maxRefStars,
      'weightingEnabled': weightingEnabled,
      'weighting': weighting.wire,
      'snrPow': snrPow,
      'fwhmPow': fwhmPow,
      'eccPow': eccPow,
      'normalizationEnabled': normalizationEnabled,
      'normalization': normalization.wire,
      'localRows': localRows,
      'localCols': localCols,
      'combine': combine.wire,
      'reject': reject.wire,
      'rejectLow': rejectLow,
      'rejectHigh': rejectHigh,
      'minMaxLow': minMaxLow,
      'minMaxHigh': minMaxHigh,
      'generateRejectionMap': generateRejectionMap,
      'cosmeticCorrection': cosmeticCorrection,
      'outputBitDepth': outputBitDepth.wire,
      'autoCull': autoCull,
      'cullPercentile': cullPercentile,
      if (sourcePreset != null) 'sourcePreset': sourcePreset!.wire,
    };
  }

  /// Inverse of [toJson]. Missing keys fall back to the [defaults] value for
  /// that field, so older persisted blobs forward-migrate without error rather
  /// than throwing on a newly-added knob.
  factory IntegrationSettings.fromJson(Map<String, dynamic> json) {
    const d = IntegrationSettings.defaults;
    T pick<T>(String key, T fallback) =>
        json.containsKey(key) && json[key] is T ? json[key] as T : fallback;
    double pickNum(String key, double fallback) {
      final v = json[key];
      if (v is num) return v.toDouble();
      return fallback;
    }

    final presetWire = json['sourcePreset'];
    return IntegrationSettings(
      model: json.containsKey('model')
          ? TransformModel.fromWire(json['model'] as String)
          : d.model,
      resampler: json.containsKey('resampler')
          ? Resampler.fromWire(json['resampler'] as String)
          : d.resampler,
      ransacThresholdPx: pickNum('ransacThresholdPx', d.ransacThresholdPx),
      maxRefStars: pick<int>('maxRefStars', d.maxRefStars),
      weightingEnabled: pick<bool>('weightingEnabled', d.weightingEnabled),
      weighting: json.containsKey('weighting')
          ? WeightFormula.fromWire(json['weighting'] as String)
          : d.weighting,
      snrPow: pickNum('snrPow', d.snrPow),
      fwhmPow: pickNum('fwhmPow', d.fwhmPow),
      eccPow: pickNum('eccPow', d.eccPow),
      normalizationEnabled:
          pick<bool>('normalizationEnabled', d.normalizationEnabled),
      normalization: json.containsKey('normalization')
          ? NormalizationMode.fromWire(json['normalization'] as String)
          : d.normalization,
      localRows: pick<int>('localRows', d.localRows),
      localCols: pick<int>('localCols', d.localCols),
      combine: json.containsKey('combine')
          ? CombineMode.fromWire(json['combine'] as String)
          : d.combine,
      reject: json.containsKey('reject')
          ? RejectAlgorithm.fromWire(json['reject'] as String)
          : d.reject,
      rejectLow: pickNum('rejectLow', d.rejectLow),
      rejectHigh: pickNum('rejectHigh', d.rejectHigh),
      minMaxLow: pick<int>('minMaxLow', d.minMaxLow),
      minMaxHigh: pick<int>('minMaxHigh', d.minMaxHigh),
      generateRejectionMap:
          pick<bool>('generateRejectionMap', d.generateRejectionMap),
      cosmeticCorrection:
          pick<bool>('cosmeticCorrection', d.cosmeticCorrection),
      outputBitDepth: json.containsKey('outputBitDepth')
          ? OutputBitDepth.fromWire(json['outputBitDepth'] as String)
          : d.outputBitDepth,
      autoCull: pick<bool>('autoCull', d.autoCull),
      cullPercentile: pickNum('cullPercentile', d.cullPercentile),
      sourcePreset:
          presetWire is String ? IntegrationPreset.fromWire(presetWire) : null,
    );
  }

  /// JSON string form (for the `settings_json` DB column / app-settings value).
  String toJsonString() => jsonEncode(toJson());

  /// Parse a [toJsonString] blob. Returns [defaults] for null / blank / corrupt
  /// input rather than throwing — a stored-settings read should never crash the
  /// review screen.
  static IntegrationSettings fromJsonStringOrDefault(String? source) {
    if (source == null || source.trim().isEmpty) return defaults;
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) {
        return IntegrationSettings.fromJson(decoded);
      }
    } catch (_) {
      // Fall through to defaults on any decode/parse error.
    }
    return defaults;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IntegrationSettings &&
          model == other.model &&
          resampler == other.resampler &&
          ransacThresholdPx == other.ransacThresholdPx &&
          maxRefStars == other.maxRefStars &&
          weightingEnabled == other.weightingEnabled &&
          weighting == other.weighting &&
          snrPow == other.snrPow &&
          fwhmPow == other.fwhmPow &&
          eccPow == other.eccPow &&
          normalizationEnabled == other.normalizationEnabled &&
          normalization == other.normalization &&
          localRows == other.localRows &&
          localCols == other.localCols &&
          combine == other.combine &&
          reject == other.reject &&
          rejectLow == other.rejectLow &&
          rejectHigh == other.rejectHigh &&
          minMaxLow == other.minMaxLow &&
          minMaxHigh == other.minMaxHigh &&
          generateRejectionMap == other.generateRejectionMap &&
          cosmeticCorrection == other.cosmeticCorrection &&
          outputBitDepth == other.outputBitDepth &&
          autoCull == other.autoCull &&
          cullPercentile == other.cullPercentile &&
          sourcePreset == other.sourcePreset;

  @override
  int get hashCode => Object.hashAll([
        model,
        resampler,
        ransacThresholdPx,
        maxRefStars,
        weightingEnabled,
        weighting,
        snrPow,
        fwhmPow,
        eccPow,
        normalizationEnabled,
        normalization,
        localRows,
        localCols,
        combine,
        reject,
        rejectLow,
        rejectHigh,
        minMaxLow,
        minMaxHigh,
        generateRejectionMap,
        cosmeticCorrection,
        outputBitDepth,
        autoCull,
        cullPercentile,
        sourcePreset,
      ]);
}
