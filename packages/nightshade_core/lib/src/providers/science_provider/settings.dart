part of '../science_provider.dart';

class ScienceSettings {
  final bool advancedModeEnabled;
  final bool overlayEnabled;
  final bool photometryEnabled;
  final bool photometricCalibrationEnabled;
  final bool transparencyEnabled;
  final bool psfMapEnabled;
  final bool astrometricResidualsEnabled;
  final bool movingObjectsEnabled;
  final bool narrowbandRatiosEnabled;
  final bool frameQualityMapsEnabled;
  final bool surface3dEnabled;
  final bool manualPurgeOnly;

  /// When true, after calibration + transparency complete the science
  /// pipeline writes a small set of standard keywords back onto the
  /// captured FITS file (MAGZP, MAGZPERR, MAGZPSRC, MAGZPNST, MAGLIM5,
  /// TRANSPAR, EXTINCT, NSHA_VER). This makes Nightshade's photometric and atmospheric
  /// measurements directly visible to PixInsight, AstroPixelProcessor,
  /// Siril, and any other tool that reads the original capture.
  ///
  /// Default true — explicit opt-out exists for users who want the
  /// captured frame's header to remain byte-identical to what the camera
  /// driver produced.
  final bool fitsHeaderWritebackEnabled;

  /// MPC observatory code (3 characters, e.g. "G40").
  /// Required for generating Minor Planet Center reports.
  final String mpcObservatoryCode;

  /// AAVSO observer code (up to 5 characters, e.g. "XYZ").
  /// Required for generating AAVSO Extended Format reports.
  final String aavsoObserverCode;

  /// Observer name written into the MPC ADES `observers`/`measurers` /
  /// `submitter` header blocks and the TNS `reporter` field. Free text.
  final String observerName;

  /// Astrometric reference catalog the plate-solver used (ADES `astCat`, e.g.
  /// "Gaia2"/"Gaia3"). Empty defaults to "UNK" in the ADES report (flagged).
  final String mpcAstrometricCatalog;

  // ── TNS bot credentials (non-secret identifiers; the API key is in the
  //    keyring via SecretField.tnsApiKey, never here). ──────────────────────

  /// TNS bot id (the integer in the mandatory `tns_marker` User-Agent header).
  final int tnsBotId;

  /// TNS bot name (the `name` field in the `tns_marker` User-Agent header).
  final String tnsBotName;

  /// TNS reporting-group id (`reporting_group_id` in the at_report JSON).
  final int tnsReportingGroupId;

  /// TNS data-source / survey id (`discovery_data_source_id`).
  final int tnsDataSourceId;

  /// Free-text reporter name(s) for the TNS `reporter` field. Falls back to
  /// [observerName] when empty.
  final String tnsReporterName;

  /// Use the TNS sandbox base URL (`sandbox.wis-tns.org`) instead of
  /// production. Production submits create real, public AT records.
  final bool tnsUseSandbox;

  /// When true, each captured light frame is evaluated against
  /// [frameGradeRulesJson] (or [FrameGradeRules.conservativeDefaults] when
  /// unset) and rejected in the database when it fails — same semantics as
  /// the Image Grader dialog, but automatic on every capture.
  final bool autoFrameGradingEnabled;

  /// JSON blob persisted via [FrameGradeRules.toJsonString]. Null uses
  /// conservative defaults while auto-grading is enabled.
  final String? frameGradeRulesJson;

  final bool scienceGuideCollapsed;

  const ScienceSettings({
    this.advancedModeEnabled = false,
    this.overlayEnabled = true,
    this.photometryEnabled = true,
    this.photometricCalibrationEnabled = true,
    this.transparencyEnabled = true,
    this.psfMapEnabled = true,
    this.astrometricResidualsEnabled = true,
    this.movingObjectsEnabled = false,
    this.narrowbandRatiosEnabled = false,
    this.frameQualityMapsEnabled = true,
    this.surface3dEnabled = true,
    this.manualPurgeOnly = true,
    this.fitsHeaderWritebackEnabled = true,
    this.mpcObservatoryCode = '',
    this.aavsoObserverCode = '',
    this.observerName = '',
    this.mpcAstrometricCatalog = '',
    this.tnsBotId = 0,
    this.tnsBotName = '',
    this.tnsReportingGroupId = 0,
    this.tnsDataSourceId = 0,
    this.tnsReporterName = '',
    this.tnsUseSandbox = false,
    this.autoFrameGradingEnabled = false,
    this.frameGradeRulesJson,
    this.scienceGuideCollapsed = false,
  });

  /// Rules applied by [FrameAutoGrader] and shown in the Image Grader UI.
  FrameGradeRules resolvedFrameGradeRules() {
    final parsed = FrameGradeRules.fromJsonString(frameGradeRulesJson);
    if (parsed != null && !parsed.isEmpty) return parsed;
    if (autoFrameGradingEnabled) return FrameGradeRules.conservativeDefaults;
    return const FrameGradeRules();
  }

  ScienceSettings copyWith({
    bool? advancedModeEnabled,
    bool? overlayEnabled,
    bool? photometryEnabled,
    bool? photometricCalibrationEnabled,
    bool? transparencyEnabled,
    bool? psfMapEnabled,
    bool? astrometricResidualsEnabled,
    bool? movingObjectsEnabled,
    bool? narrowbandRatiosEnabled,
    bool? frameQualityMapsEnabled,
    bool? surface3dEnabled,
    bool? manualPurgeOnly,
    bool? fitsHeaderWritebackEnabled,
    String? mpcObservatoryCode,
    String? aavsoObserverCode,
    String? observerName,
    String? mpcAstrometricCatalog,
    int? tnsBotId,
    String? tnsBotName,
    int? tnsReportingGroupId,
    int? tnsDataSourceId,
    String? tnsReporterName,
    bool? tnsUseSandbox,
    bool? autoFrameGradingEnabled,
    String? frameGradeRulesJson,
    bool clearFrameGradeRulesJson = false,
    bool? scienceGuideCollapsed,
  }) {
    return ScienceSettings(
      advancedModeEnabled: advancedModeEnabled ?? this.advancedModeEnabled,
      overlayEnabled: overlayEnabled ?? this.overlayEnabled,
      photometryEnabled: photometryEnabled ?? this.photometryEnabled,
      photometricCalibrationEnabled:
          photometricCalibrationEnabled ?? this.photometricCalibrationEnabled,
      transparencyEnabled: transparencyEnabled ?? this.transparencyEnabled,
      psfMapEnabled: psfMapEnabled ?? this.psfMapEnabled,
      astrometricResidualsEnabled:
          astrometricResidualsEnabled ?? this.astrometricResidualsEnabled,
      movingObjectsEnabled: movingObjectsEnabled ?? this.movingObjectsEnabled,
      narrowbandRatiosEnabled:
          narrowbandRatiosEnabled ?? this.narrowbandRatiosEnabled,
      frameQualityMapsEnabled:
          frameQualityMapsEnabled ?? this.frameQualityMapsEnabled,
      surface3dEnabled: surface3dEnabled ?? this.surface3dEnabled,
      manualPurgeOnly: manualPurgeOnly ?? this.manualPurgeOnly,
      fitsHeaderWritebackEnabled:
          fitsHeaderWritebackEnabled ?? this.fitsHeaderWritebackEnabled,
      mpcObservatoryCode: mpcObservatoryCode ?? this.mpcObservatoryCode,
      aavsoObserverCode: aavsoObserverCode ?? this.aavsoObserverCode,
      observerName: observerName ?? this.observerName,
      mpcAstrometricCatalog:
          mpcAstrometricCatalog ?? this.mpcAstrometricCatalog,
      tnsBotId: tnsBotId ?? this.tnsBotId,
      tnsBotName: tnsBotName ?? this.tnsBotName,
      tnsReportingGroupId: tnsReportingGroupId ?? this.tnsReportingGroupId,
      tnsDataSourceId: tnsDataSourceId ?? this.tnsDataSourceId,
      tnsReporterName: tnsReporterName ?? this.tnsReporterName,
      tnsUseSandbox: tnsUseSandbox ?? this.tnsUseSandbox,
      autoFrameGradingEnabled:
          autoFrameGradingEnabled ?? this.autoFrameGradingEnabled,
      frameGradeRulesJson: clearFrameGradeRulesJson
          ? null
          : (frameGradeRulesJson ?? this.frameGradeRulesJson),
      scienceGuideCollapsed:
          scienceGuideCollapsed ?? this.scienceGuideCollapsed,
    );
  }
}

class ScienceSettingsNotifier extends AsyncNotifier<ScienceSettings> {
  static const _keys = {
    'advancedMode': 'science.advanced_mode.enabled',
    'overlay': 'science.overlay.enabled',
    'photometry': 'science.feature.photometry',
    'photometricCalibration': 'science.feature.photometric_calibration',
    'transparency': 'science.feature.transparency',
    'psfMap': 'science.feature.psf_map',
    'astrometricResiduals': 'science.feature.astrometric_residuals',
    'movingObjects': 'science.feature.moving_objects',
    'narrowbandRatios': 'science.feature.narrowband_ratios',
    'frameQualityMaps': 'science.feature.frame_quality_maps',
    'surface3d': 'science.feature.surface3d',
    'manualPurgeOnly': 'science.retention.manual_purge_only',
    'fitsHeaderWriteback': 'science.writeback.fits_header_enabled',
    'mpcObservatoryCode': 'science.mpc.observatory_code',
    'aavsoObserverCode': 'science.aavso.observer_code',
    'observerName': 'science.observer.name',
    'mpcAstrometricCatalog': 'science.mpc.ast_cat',
    'tnsBotId': 'science.tns.bot_id',
    'tnsBotName': 'science.tns.bot_name',
    'tnsReportingGroupId': 'science.tns.group_id',
    'tnsDataSourceId': 'science.tns.source_id',
    'tnsReporterName': 'science.tns.reporter',
    'tnsUseSandbox': 'science.tns.use_sandbox',
    'autoFrameGrading': 'science.grading.auto_enabled',
    'frameGradeRules': 'science.grading.rules_json',
    'guideCollapsed': 'science.guide.collapsed',
  };

  @override
  Future<ScienceSettings> build() async {
    final settings = await _loadScienceSettingsMap(ref);

    return ScienceSettings(
      advancedModeEnabled: _parseBool(settings[_keys['advancedMode']], false),
      overlayEnabled: _parseBool(settings[_keys['overlay']], true),
      photometryEnabled: _parseBool(settings[_keys['photometry']], true),
      photometricCalibrationEnabled: _parseBool(
        settings[_keys['photometricCalibration']],
        true,
      ),
      transparencyEnabled: _parseBool(settings[_keys['transparency']], true),
      psfMapEnabled: _parseBool(settings[_keys['psfMap']], true),
      astrometricResidualsEnabled: _parseBool(
        settings[_keys['astrometricResiduals']],
        true,
      ),
      movingObjectsEnabled: _parseBool(settings[_keys['movingObjects']], false),
      narrowbandRatiosEnabled: _parseBool(
        settings[_keys['narrowbandRatios']],
        false,
      ),
      frameQualityMapsEnabled: _parseBool(
        settings[_keys['frameQualityMaps']],
        true,
      ),
      surface3dEnabled: _parseBool(settings[_keys['surface3d']], true),
      manualPurgeOnly: _parseBool(settings[_keys['manualPurgeOnly']], true),
      fitsHeaderWritebackEnabled: _parseBool(
        settings[_keys['fitsHeaderWriteback']],
        true,
      ),
      mpcObservatoryCode: settings[_keys['mpcObservatoryCode']] ?? '',
      aavsoObserverCode: settings[_keys['aavsoObserverCode']] ?? '',
      observerName: settings[_keys['observerName']] ?? '',
      mpcAstrometricCatalog: settings[_keys['mpcAstrometricCatalog']] ?? '',
      tnsBotId: int.tryParse(settings[_keys['tnsBotId']] ?? '') ?? 0,
      tnsBotName: settings[_keys['tnsBotName']] ?? '',
      tnsReportingGroupId:
          int.tryParse(settings[_keys['tnsReportingGroupId']] ?? '') ?? 0,
      tnsDataSourceId:
          int.tryParse(settings[_keys['tnsDataSourceId']] ?? '') ?? 0,
      tnsReporterName: settings[_keys['tnsReporterName']] ?? '',
      tnsUseSandbox: _parseBool(settings[_keys['tnsUseSandbox']], false),
      autoFrameGradingEnabled:
          _parseBool(settings[_keys['autoFrameGrading']], false) ||
          _parseBool(settings['image_grading_enabled'], false),
      frameGradeRulesJson: settings[_keys['frameGradeRules']],
      scienceGuideCollapsed: _parseBool(
        settings[_keys['guideCollapsed']],
        false,
      ),
    );
  }

  Future<void> _setSetting(String key, bool value) async {
    await _writeScienceSettings(ref, {key: value.toString()});
  }

  Future<void> _setStringSetting(String key, String value) async {
    await _writeScienceSettings(ref, {key: value});
  }

  Future<void> setAdvancedModeEnabled(bool enabled) async {
    await _setSetting(_keys['advancedMode']!, enabled);
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(
        advancedModeEnabled: enabled,
      ),
    );
  }

  Future<void> setOverlayEnabled(bool enabled) async {
    await _setSetting(_keys['overlay']!, enabled);
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(
        overlayEnabled: enabled,
      ),
    );
  }

  Future<void> setFeatureEnabled(ScienceFeature feature, bool enabled) async {
    switch (feature) {
      case ScienceFeature.photometry:
        await _setSetting(_keys['photometry']!, enabled);
        state = AsyncData(
          (state.value ?? const ScienceSettings()).copyWith(
            photometryEnabled: enabled,
          ),
        );
        break;
      case ScienceFeature.photometricCalibration:
        await _setSetting(_keys['photometricCalibration']!, enabled);
        state = AsyncData(
          (state.value ?? const ScienceSettings()).copyWith(
            photometricCalibrationEnabled: enabled,
          ),
        );
        break;
      case ScienceFeature.transparency:
        await _setSetting(_keys['transparency']!, enabled);
        state = AsyncData(
          (state.value ?? const ScienceSettings()).copyWith(
            transparencyEnabled: enabled,
          ),
        );
        break;
      case ScienceFeature.psfMap:
        await _setSetting(_keys['psfMap']!, enabled);
        state = AsyncData(
          (state.value ?? const ScienceSettings()).copyWith(
            psfMapEnabled: enabled,
          ),
        );
        break;
      case ScienceFeature.astrometricResiduals:
        await _setSetting(_keys['astrometricResiduals']!, enabled);
        state = AsyncData(
          (state.value ?? const ScienceSettings()).copyWith(
            astrometricResidualsEnabled: enabled,
          ),
        );
        break;
      case ScienceFeature.movingObjects:
        await _setSetting(_keys['movingObjects']!, enabled);
        state = AsyncData(
          (state.value ?? const ScienceSettings()).copyWith(
            movingObjectsEnabled: enabled,
          ),
        );
        break;
      case ScienceFeature.narrowbandRatios:
        await _setSetting(_keys['narrowbandRatios']!, enabled);
        state = AsyncData(
          (state.value ?? const ScienceSettings()).copyWith(
            narrowbandRatiosEnabled: enabled,
          ),
        );
        break;
      case ScienceFeature.frameQualityMaps:
        await _setSetting(_keys['frameQualityMaps']!, enabled);
        state = AsyncData(
          (state.value ?? const ScienceSettings()).copyWith(
            frameQualityMapsEnabled: enabled,
          ),
        );
        break;
      case ScienceFeature.surface3d:
        await _setSetting(_keys['surface3d']!, enabled);
        state = AsyncData(
          (state.value ?? const ScienceSettings()).copyWith(
            surface3dEnabled: enabled,
          ),
        );
        break;
    }
  }

  Future<void> setMpcObservatoryCode(String code) async {
    await _setStringSetting(_keys['mpcObservatoryCode']!, code);
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(
        mpcObservatoryCode: code,
      ),
    );
  }

  Future<void> setAavsoObserverCode(String code) async {
    await _setStringSetting(_keys['aavsoObserverCode']!, code);
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(
        aavsoObserverCode: code,
      ),
    );
  }

  Future<void> setObserverName(String name) async {
    await _setStringSetting(_keys['observerName']!, name);
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(observerName: name),
    );
  }

  Future<void> setMpcAstrometricCatalog(String catalog) async {
    await _setStringSetting(_keys['mpcAstrometricCatalog']!, catalog);
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(
        mpcAstrometricCatalog: catalog,
      ),
    );
  }

  Future<void> setTnsBotId(int id) async {
    await _setStringSetting(_keys['tnsBotId']!, id.toString());
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(tnsBotId: id),
    );
  }

  Future<void> setTnsBotName(String name) async {
    await _setStringSetting(_keys['tnsBotName']!, name);
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(tnsBotName: name),
    );
  }

  Future<void> setTnsReportingGroupId(int id) async {
    await _setStringSetting(_keys['tnsReportingGroupId']!, id.toString());
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(
        tnsReportingGroupId: id,
      ),
    );
  }

  Future<void> setTnsDataSourceId(int id) async {
    await _setStringSetting(_keys['tnsDataSourceId']!, id.toString());
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(tnsDataSourceId: id),
    );
  }

  Future<void> setTnsReporterName(String name) async {
    await _setStringSetting(_keys['tnsReporterName']!, name);
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(tnsReporterName: name),
    );
  }

  Future<void> setTnsUseSandbox(bool enabled) async {
    await _setSetting(_keys['tnsUseSandbox']!, enabled);
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(tnsUseSandbox: enabled),
    );
  }

  Future<void> setFitsHeaderWritebackEnabled(bool enabled) async {
    await _setSetting(_keys['fitsHeaderWriteback']!, enabled);
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(
        fitsHeaderWritebackEnabled: enabled,
      ),
    );
  }

  Future<void> setAutoFrameGradingEnabled(bool enabled) async {
    await _setSetting(_keys['autoFrameGrading']!, enabled);
    await ref.read(appSettingsProvider.notifier).setEnableImageGrading(enabled);
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(
        autoFrameGradingEnabled: enabled,
      ),
    );
  }

  Future<void> setScienceGuideCollapsed(bool collapsed) async {
    await _setSetting(_keys['guideCollapsed']!, collapsed);
    state = AsyncData(
      (state.value ?? const ScienceSettings()).copyWith(
        scienceGuideCollapsed: collapsed,
      ),
    );
  }

  Future<void> setFrameGradeRules(FrameGradeRules rules) async {
    final json = rules.isEmpty ? '' : rules.toJsonString();
    await _writeScienceSettings(ref, {_keys['frameGradeRules']!: json});
    // copyWith treats a null json as "keep current", so clearing the rules
    // must go through the explicit clear flag or stale thresholds keep
    // grading frames until the next app restart.
    state = AsyncData(
      json.isEmpty
          ? (state.value ?? const ScienceSettings()).copyWith(
              clearFrameGradeRulesJson: true,
            )
          : (state.value ?? const ScienceSettings()).copyWith(
              frameGradeRulesJson: json,
            ),
    );
  }

  bool _parseBool(String? value, bool fallback) {
    if (value == null) {
      return fallback;
    }
    return value.toLowerCase() == 'true';
  }
}

final scienceSettingsProvider =
    AsyncNotifierProvider<ScienceSettingsNotifier, ScienceSettings>(
      ScienceSettingsNotifier.new,
    );
