import '../../services/live_stacking_service.dart';

/// Models for the **Stack-and-Share Loop** — the workflow that takes a set of
/// captured light frames, optionally calibrates them, live-stacks them into a
/// single integration, stretches the result, and exports a share-ready image
/// (PNG / JPEG / annotated share card) plus AstroBin-style acquisition metadata.
///
/// These are plain immutable value classes (const constructor + [copyWith] +
/// value equality), matching the style of [LiveStackingConfig] /
/// [LiveStackingStats] in `live_stacking_service.dart` — no freezed / codegen.
///
/// Per project policy these models never silently swallow data: helpers like
/// [StackAndShareProgress.fraction] return well-defined values for degenerate
/// inputs (e.g. zero total frames) rather than producing NaN.

/// Configuration for a single Stack-and-Share run.
///
/// Wraps the underlying [LiveStackingConfig] (alignment + pixel-rejection
/// parameters) and layers the share-loop concerns on top: calibration,
/// auto-stretch, and frame-quality gating.
class StackAndShareConfig {
  /// Alignment and pixel-rejection parameters handed to the live-stacking
  /// engine. Defaults to the engine's own sensible defaults.
  final LiveStackingConfig stackingConfig;

  /// Whether each light frame should be calibrated (dark/flat/bias subtraction
  /// via the dark library) before being added to the stack.
  final bool applyCalibration;

  /// Whether the final integrated result should be auto-stretched for display
  /// and export.
  ///
  /// The integrated buffer lives only in memory during a run, so the stretch
  /// goes through the engine's in-memory screen-transfer (STF) path
  /// (`apiAutoStretchImage`) — the only stretch the engine can apply to an
  /// in-memory u16 buffer. There is deliberately no stretch-*method* knob: the
  /// method-aware path (`apiApplyStretch`) operates on a FITS file on disk, not
  /// the in-memory result, so offering five methods that all silently produced
  /// the same STF output would be exactly the "silent fallback" project policy
  /// forbids. The result viewer honours the same honest STF/Linear-only model.
  final bool autoStretch;

  /// Minimum per-frame quality score required for a frame to be included in the
  /// stack. Frames scoring below this threshold are excluded. A value of `0`
  /// admits every frame (no quality gate).
  final double minQualityScore;

  /// Whether frames the user (or runtime grading) marked as not accepted should
  /// be rejected from the stack.
  final bool rejectUnaccepted;

  /// Sensor acquisition mode for the run: `"auto"`, `"mono"`, or `"osc"`.
  ///
  /// This is the Stack-and-Share-level OSC knob; it is folded into the
  /// underlying [LiveStackingConfig.sensorMode] by [resolvedStackingConfig].
  /// Unlike the live engine (which defaults to `"mono"` to preserve historic
  /// single-channel behaviour byte-for-byte), the Stack-and-Share path defaults
  /// to `"auto"` so a colour camera's frames are debayered when they actually
  /// carry Bayer geometry without the user having to opt in.
  ///
  /// - `auto` — debayer only when the frame carries Bayer geometry (or
  ///   [bayerPatternOverride] is supplied); otherwise treat as mono.
  /// - `mono` — frames are single-channel luminance; never debayered.
  /// - `osc` — frames are a Bayer CFA mosaic that *must* be debayered to RGB;
  ///   an unresolvable pattern is a hard error native-side (no silent
  ///   mono-fallback that would scramble the colour mosaic).
  final String sensorMode;

  /// Explicit Bayer pattern override (`"RGGB"`/`"BGGR"`/`"GRBG"`/`"GBRG"`), or
  /// `null` to let an OSC/auto run fall back to the pattern the reference frame
  /// declares via its FITS `BAYERPAT` geometry. Folded into
  /// [LiveStackingConfig.bayerPattern]. An unrecognised string is a hard error
  /// native-side rather than a silent best-guess.
  final String? bayerPatternOverride;

  /// Demosaic quality for the OSC path: `"bilinear"`, `"vng"`, or
  /// `"superpixel"`. Folded into [LiveStackingConfig.demosaicQuality].
  ///
  /// Defaults to `"vng"` here — the Stack-and-Share path is the
  /// quality-oriented, post-capture integration, so it favours the
  /// higher-fidelity VNG demosaic over the live engine's `"bilinear"` default
  /// (which trades quality for the throughput a real-time EAA preview needs).
  /// An unrecognised value is a hard error native-side rather than a silent
  /// best-guess.
  final String demosaicQuality;

  const StackAndShareConfig({
    this.stackingConfig = const LiveStackingConfig(),
    this.applyCalibration = true,
    this.autoStretch = true,
    this.minQualityScore = 0,
    this.rejectUnaccepted = true,
    this.sensorMode = 'auto',
    this.bayerPatternOverride,
    this.demosaicQuality = 'vng',
  });

  /// Default configuration for a typical Stack-and-Share run.
  static const defaults = StackAndShareConfig();

  /// The [stackingConfig] with this config's OSC knobs ([sensorMode],
  /// [bayerPatternOverride], [demosaicQuality]) folded in.
  ///
  /// This is the config the orchestrator hands to the live-stacking engine: it
  /// guarantees the Stack-and-Share-level colour intent always reaches the
  /// engine, regardless of what defaults the wrapped [stackingConfig] carried.
  LiveStackingConfig get resolvedStackingConfig => stackingConfig.copyWith(
        sensorMode: sensorMode,
        bayerPattern: bayerPatternOverride,
        demosaicQuality: demosaicQuality,
      );

  StackAndShareConfig copyWith({
    LiveStackingConfig? stackingConfig,
    bool? applyCalibration,
    bool? autoStretch,
    double? minQualityScore,
    bool? rejectUnaccepted,
    String? sensorMode,
    String? bayerPatternOverride,
    String? demosaicQuality,
  }) {
    return StackAndShareConfig(
      stackingConfig: stackingConfig ?? this.stackingConfig,
      applyCalibration: applyCalibration ?? this.applyCalibration,
      autoStretch: autoStretch ?? this.autoStretch,
      minQualityScore: minQualityScore ?? this.minQualityScore,
      rejectUnaccepted: rejectUnaccepted ?? this.rejectUnaccepted,
      sensorMode: sensorMode ?? this.sensorMode,
      bayerPatternOverride: bayerPatternOverride ?? this.bayerPatternOverride,
      demosaicQuality: demosaicQuality ?? this.demosaicQuality,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StackAndShareConfig &&
          runtimeType == other.runtimeType &&
          stackingConfig == other.stackingConfig &&
          applyCalibration == other.applyCalibration &&
          autoStretch == other.autoStretch &&
          minQualityScore == other.minQualityScore &&
          rejectUnaccepted == other.rejectUnaccepted &&
          sensorMode == other.sensorMode &&
          bayerPatternOverride == other.bayerPatternOverride &&
          demosaicQuality == other.demosaicQuality;

  @override
  int get hashCode => Object.hash(
        stackingConfig,
        applyCalibration,
        autoStretch,
        minQualityScore,
        rejectUnaccepted,
        sensorMode,
        bayerPatternOverride,
        demosaicQuality,
      );
}

/// Lifecycle phases of a Stack-and-Share run, in execution order.
enum StackAndSharePhase {
  /// No run is in progress.
  idle,

  /// Choosing which light frames to include.
  selectingLights,

  /// Applying dark/flat/bias calibration to selected lights.
  calibrating,

  /// Aligning and integrating frames into the live stack.
  stacking,

  /// Applying the auto-stretch to the integrated result.
  stretching,

  /// Rendering and writing the share artifacts to disk.
  exporting,

  /// The run finished successfully.
  complete,

  /// The run failed; inspect the surfaced error for the cause.
  error,
}

/// Live progress for an in-flight Stack-and-Share run.
class StackAndShareProgress {
  /// The current lifecycle phase.
  final StackAndSharePhase phase;

  /// Total number of frames the run intends to process.
  final int framesTotal;

  /// Number of frames processed so far (accepted into, or rejected from, the
  /// stack — i.e. frames the engine has finished examining).
  final int framesProcessed;

  /// Number of frames rejected during processing (alignment failure, below
  /// quality threshold, or not accepted).
  final int framesRejected;

  /// The file currently being processed, if any.
  final String? currentFile;

  const StackAndShareProgress({
    this.phase = StackAndSharePhase.idle,
    this.framesTotal = 0,
    this.framesProcessed = 0,
    this.framesRejected = 0,
    this.currentFile,
  });

  /// Fraction of the run completed, in the range `[0.0, 1.0]`.
  ///
  /// Returns `0.0` when [framesTotal] is zero (rather than NaN) so progress UI
  /// renders a sane empty bar. The result is clamped to `[0.0, 1.0]` to guard
  /// against [framesProcessed] transiently exceeding [framesTotal].
  double get fraction {
    if (framesTotal <= 0) return 0.0;
    final raw = framesProcessed / framesTotal;
    if (raw < 0.0) return 0.0;
    if (raw > 1.0) return 1.0;
    return raw;
  }

  StackAndShareProgress copyWith({
    StackAndSharePhase? phase,
    int? framesTotal,
    int? framesProcessed,
    int? framesRejected,
    String? currentFile,
  }) {
    return StackAndShareProgress(
      phase: phase ?? this.phase,
      framesTotal: framesTotal ?? this.framesTotal,
      framesProcessed: framesProcessed ?? this.framesProcessed,
      framesRejected: framesRejected ?? this.framesRejected,
      currentFile: currentFile ?? this.currentFile,
    );
  }

  /// Like [copyWith] but allows explicitly clearing [currentFile] back to null
  /// (e.g. when transitioning to a phase with no active file).
  StackAndShareProgress clearCurrentFile() {
    return StackAndShareProgress(
      phase: phase,
      framesTotal: framesTotal,
      framesProcessed: framesProcessed,
      framesRejected: framesRejected,
      currentFile: null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StackAndShareProgress &&
          runtimeType == other.runtimeType &&
          phase == other.phase &&
          framesTotal == other.framesTotal &&
          framesProcessed == other.framesProcessed &&
          framesRejected == other.framesRejected &&
          currentFile == other.currentFile;

  @override
  int get hashCode => Object.hash(
        phase,
        framesTotal,
        framesProcessed,
        framesRejected,
        currentFile,
      );
}

/// A single light frame considered for a Stack-and-Share run.
class StackedFrameSelection {
  /// Database id of the captured image (`captured_images.id`).
  final int imageId;

  /// Absolute path to the frame on disk.
  final String filePath;

  /// Filter the frame was captured through, if known (e.g. `'L'`, `'Ha'`).
  final String? filter;

  /// Per-frame quality score, if computed. Higher is better.
  final double? qualityScore;

  /// Whether this frame is the alignment reference for the stack.
  final bool isReference;

  const StackedFrameSelection({
    required this.imageId,
    required this.filePath,
    this.filter,
    this.qualityScore,
    this.isReference = false,
  });

  StackedFrameSelection copyWith({
    int? imageId,
    String? filePath,
    String? filter,
    double? qualityScore,
    bool? isReference,
  }) {
    return StackedFrameSelection(
      imageId: imageId ?? this.imageId,
      filePath: filePath ?? this.filePath,
      filter: filter ?? this.filter,
      qualityScore: qualityScore ?? this.qualityScore,
      isReference: isReference ?? this.isReference,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StackedFrameSelection &&
          runtimeType == other.runtimeType &&
          imageId == other.imageId &&
          filePath == other.filePath &&
          filter == other.filter &&
          qualityScore == other.qualityScore &&
          isReference == other.isReference;

  @override
  int get hashCode =>
      Object.hash(imageId, filePath, filter, qualityScore, isReference);
}

/// Summary of which frames were selected for, and which were excluded from, a
/// Stack-and-Share run, with derived per-filter and integration totals.
class StackSelectionSummary {
  /// Frames included in the stack.
  final List<StackedFrameSelection> selected;

  /// Frames excluded from the stack (below quality, wrong filter, rejected).
  final List<StackedFrameSelection> excluded;

  /// Path of the alignment reference frame, if one was chosen.
  final String? referencePath;

  /// Count of selected frames per filter (filter name → frame count).
  final Map<String, int> perFilterCounts;

  /// Total integration time of the selected frames, in seconds.
  final double totalIntegrationSecs;

  /// Name of the target being stacked, if known.
  final String? targetName;

  const StackSelectionSummary({
    this.selected = const [],
    this.excluded = const [],
    this.referencePath,
    this.perFilterCounts = const {},
    this.totalIntegrationSecs = 0,
    this.targetName,
  });

  /// Number of frames selected for the stack.
  int get selectedCount => selected.length;

  /// Number of frames excluded from the stack.
  int get excludedCount => excluded.length;

  StackSelectionSummary copyWith({
    List<StackedFrameSelection>? selected,
    List<StackedFrameSelection>? excluded,
    String? referencePath,
    Map<String, int>? perFilterCounts,
    double? totalIntegrationSecs,
    String? targetName,
  }) {
    return StackSelectionSummary(
      selected: selected ?? this.selected,
      excluded: excluded ?? this.excluded,
      referencePath: referencePath ?? this.referencePath,
      perFilterCounts: perFilterCounts ?? this.perFilterCounts,
      totalIntegrationSecs: totalIntegrationSecs ?? this.totalIntegrationSecs,
      targetName: targetName ?? this.targetName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StackSelectionSummary &&
          runtimeType == other.runtimeType &&
          _listEquals(selected, other.selected) &&
          _listEquals(excluded, other.excluded) &&
          referencePath == other.referencePath &&
          _mapEquals(perFilterCounts, other.perFilterCounts) &&
          totalIntegrationSecs == other.totalIntegrationSecs &&
          targetName == other.targetName;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(selected),
        Object.hashAll(excluded),
        referencePath,
        Object.hashAll(
          perFilterCounts.entries
              .map((e) => Object.hash(e.key, e.value))
              .toList()
            ..sort(),
        ),
        totalIntegrationSecs,
        targetName,
      );
}

/// Final result of a completed Stack-and-Share run. Persisted alongside the
/// session/target so a stacked master can be re-shared later.
class StackAndShareResult {
  /// Database id, if persisted.
  final int? id;

  /// Owning imaging session id, if any.
  final int? sessionId;

  /// Target id, if any.
  final int? targetId;

  /// Target name, denormalised for display.
  final String? targetName;

  /// Width of the integrated image in pixels.
  final int width;

  /// Height of the integrated image in pixels.
  final int height;

  /// Number of frames that made it into the integration.
  final int framesStacked;

  /// Number of frames the run attempted (stacked + rejected).
  final int framesAttempted;

  /// Total integration time of the stacked frames, in seconds.
  final double integrationSecs;

  /// Average alignment residual across stacked frames, in pixels.
  final double avgAlignmentResidual;

  /// Average HFR (half-flux radius) across stacked frames, if measured.
  final double? avgHfr;

  /// Filter of the stack, if mono / single-filter.
  final String? filter;

  /// Whether the integrated result is a colour (OSC/RGB) stack rather than a
  /// single-channel monochrome stack. Defaults to `false` (mono) so existing
  /// persisted results round-trip unchanged.
  final bool isColor;

  /// Channel count of the integrated result: `1` for a monochrome stack, `3`
  /// for an interleaved-RGB OSC stack. Defaults to `1`. Kept distinct from
  /// [isColor] so a future multi-channel layout (e.g. RGBA) is representable
  /// without overloading the boolean.
  final int channels;

  /// When the stack was produced.
  final DateTime createdAt;

  /// Path to the exported, share-ready image, if exported.
  final String? exportedImagePath;

  /// Underlying live-stacking statistics for the run.
  final LiveStackingStats stats;

  const StackAndShareResult({
    this.id,
    this.sessionId,
    this.targetId,
    this.targetName,
    required this.width,
    required this.height,
    required this.framesStacked,
    required this.framesAttempted,
    required this.integrationSecs,
    required this.avgAlignmentResidual,
    this.avgHfr,
    this.filter,
    this.isColor = false,
    this.channels = 1,
    required this.createdAt,
    this.exportedImagePath,
    this.stats = const LiveStackingStats(),
  });

  /// Number of frames rejected during the run.
  int get framesRejected =>
      (framesAttempted - framesStacked).clamp(0, framesAttempted);

  StackAndShareResult copyWith({
    int? id,
    int? sessionId,
    int? targetId,
    String? targetName,
    int? width,
    int? height,
    int? framesStacked,
    int? framesAttempted,
    double? integrationSecs,
    double? avgAlignmentResidual,
    double? avgHfr,
    String? filter,
    bool? isColor,
    int? channels,
    DateTime? createdAt,
    String? exportedImagePath,
    LiveStackingStats? stats,
  }) {
    return StackAndShareResult(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      targetId: targetId ?? this.targetId,
      targetName: targetName ?? this.targetName,
      width: width ?? this.width,
      height: height ?? this.height,
      framesStacked: framesStacked ?? this.framesStacked,
      framesAttempted: framesAttempted ?? this.framesAttempted,
      integrationSecs: integrationSecs ?? this.integrationSecs,
      avgAlignmentResidual: avgAlignmentResidual ?? this.avgAlignmentResidual,
      avgHfr: avgHfr ?? this.avgHfr,
      filter: filter ?? this.filter,
      isColor: isColor ?? this.isColor,
      channels: channels ?? this.channels,
      createdAt: createdAt ?? this.createdAt,
      exportedImagePath: exportedImagePath ?? this.exportedImagePath,
      stats: stats ?? this.stats,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StackAndShareResult &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sessionId == other.sessionId &&
          targetId == other.targetId &&
          targetName == other.targetName &&
          width == other.width &&
          height == other.height &&
          framesStacked == other.framesStacked &&
          framesAttempted == other.framesAttempted &&
          integrationSecs == other.integrationSecs &&
          avgAlignmentResidual == other.avgAlignmentResidual &&
          avgHfr == other.avgHfr &&
          filter == other.filter &&
          isColor == other.isColor &&
          channels == other.channels &&
          createdAt == other.createdAt &&
          exportedImagePath == other.exportedImagePath &&
          stats == other.stats;

  @override
  int get hashCode => Object.hashAll([
        id,
        sessionId,
        targetId,
        targetName,
        width,
        height,
        framesStacked,
        framesAttempted,
        integrationSecs,
        avgAlignmentResidual,
        avgHfr,
        filter,
        isColor,
        channels,
        createdAt,
        exportedImagePath,
        stats,
      ]);
}

/// Layout options for the annotated share card.
enum ShareCardLayout {
  /// A translucent stat bar pinned to the bottom edge of the image.
  bottomBar,

  /// A compact stat card floated in a corner of the image.
  cornerCard,
}

/// Overlay glyph-size policy for a [ShareCardSpec].
///
/// The renderer normally derives the bitmap font from the rendered image
/// height (~4% of height) so an overlay scales sensibly from a thumbnail to a
/// 4K master. Some callers need a fixed size instead — notably the live
/// broadcast, which historically drew its watermark at the largest built-in
/// font (arial48) regardless of the 720px thumbnail it renders at, and must
/// keep that look so the outreach overlay does not shrink.
enum ShareCardFontScale {
  /// Pick the font from the rendered image height (the default, scales).
  scaleToHeight,

  /// Always use the small built-in bitmap font (arial14).
  small,

  /// Always use the medium built-in bitmap font (arial24).
  medium,

  /// Always use the large built-in bitmap font (arial48).
  large,
}

/// A single labelled statistic rendered on a share card.
class ShareStatLine {
  /// The stat label (e.g. `'Integration'`).
  final String label;

  /// The stat value (e.g. `'2h12m'`).
  final String value;

  const ShareStatLine({required this.label, required this.value});

  ShareStatLine copyWith({String? label, String? value}) {
    return ShareStatLine(
      label: label ?? this.label,
      value: value ?? this.value,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShareStatLine &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          value == other.value;

  @override
  int get hashCode => Object.hash(label, value);
}

/// Specification for rendering an annotated share card over a stacked image.
class ShareCardSpec {
  /// Card title (typically the target name).
  final String title;

  /// Stat lines rendered on the card.
  final List<ShareStatLine> stats;

  /// Optional watermark text overlaid on the image.
  final String? watermark;

  /// Target render width in pixels.
  final int targetWidth;

  /// Target render height in pixels.
  final int targetHeight;

  /// Layout of the stat overlay.
  final ShareCardLayout layout;

  /// Glyph-size policy for the watermark + stat overlay. Defaults to
  /// [ShareCardFontScale.scaleToHeight] so an overlay scales with the rendered
  /// image; callers that need a fixed glyph size (e.g. the broadcast's
  /// historical arial48 watermark) override it.
  final ShareCardFontScale fontScale;

  const ShareCardSpec({
    required this.title,
    this.stats = const [],
    this.watermark,
    this.targetWidth = 1080,
    this.targetHeight = 1080,
    this.layout = ShareCardLayout.bottomBar,
    this.fontScale = ShareCardFontScale.scaleToHeight,
  });

  ShareCardSpec copyWith({
    String? title,
    List<ShareStatLine>? stats,
    String? watermark,
    int? targetWidth,
    int? targetHeight,
    ShareCardLayout? layout,
    ShareCardFontScale? fontScale,
  }) {
    return ShareCardSpec(
      title: title ?? this.title,
      stats: stats ?? this.stats,
      watermark: watermark ?? this.watermark,
      targetWidth: targetWidth ?? this.targetWidth,
      targetHeight: targetHeight ?? this.targetHeight,
      layout: layout ?? this.layout,
      fontScale: fontScale ?? this.fontScale,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShareCardSpec &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          _listEquals(stats, other.stats) &&
          watermark == other.watermark &&
          targetWidth == other.targetWidth &&
          targetHeight == other.targetHeight &&
          layout == other.layout &&
          fontScale == other.fontScale;

  @override
  int get hashCode => Object.hash(
        title,
        Object.hashAll(stats),
        watermark,
        targetWidth,
        targetHeight,
        layout,
        fontScale,
      );
}

/// Output format for a Stack-and-Share export.
enum ShareExportFormat {
  /// Lossless PNG of the stacked image.
  png,

  /// Compressed JPEG of the stacked image.
  jpeg,

  /// Annotated share card (image + stat overlay).
  shareCard,
}

/// AstroBin-style acquisition metadata for a stacked image.
///
/// Produces the standard acquisition block AstroBin expects: an integration
/// summary plus equipment details, renderable as Markdown for a forum/social
/// post or serialised to JSON for an API submission.
class AstroBinExportMetadata {
  /// Image / target title.
  final String? title;

  /// AstroBin subject type (e.g. `'Deep sky'`, `'Solar system'`).
  final String subjectType;

  /// Total integration time in seconds.
  final double integrationSecs;

  /// Number of light frames integrated.
  final int frames;

  /// Telescope / optical train description.
  final String? telescope;

  /// Camera description.
  final String? camera;

  /// Filter used, if single-filter.
  final String? filter;

  /// Focal length in millimetres.
  final double? focalLength;

  /// Aperture in millimetres.
  final double? aperture;

  const AstroBinExportMetadata({
    this.title,
    this.subjectType = 'Deep sky',
    required this.integrationSecs,
    required this.frames,
    this.telescope,
    this.camera,
    this.filter,
    this.focalLength,
    this.aperture,
  });

  /// Per-frame exposure in seconds, derived from total integration and frame
  /// count. Returns `0` when there are no frames (rather than dividing by zero).
  double get perFrameExposureSecs {
    if (frames <= 0) return 0;
    return integrationSecs / frames;
  }

  /// Integration time formatted as zero-padded `HH:MM:SS`, the canonical form
  /// for an AstroBin acquisition block.
  String get integrationHms => formatHms(integrationSecs);

  /// Focal ratio (f-number), if both [focalLength] and [aperture] are known and
  /// the aperture is non-zero.
  double? get focalRatio {
    final fl = focalLength;
    final ap = aperture;
    if (fl == null || ap == null || ap <= 0) return null;
    return fl / ap;
  }

  AstroBinExportMetadata copyWith({
    String? title,
    String? subjectType,
    double? integrationSecs,
    int? frames,
    String? telescope,
    String? camera,
    String? filter,
    double? focalLength,
    double? aperture,
  }) {
    return AstroBinExportMetadata(
      title: title ?? this.title,
      subjectType: subjectType ?? this.subjectType,
      integrationSecs: integrationSecs ?? this.integrationSecs,
      frames: frames ?? this.frames,
      telescope: telescope ?? this.telescope,
      camera: camera ?? this.camera,
      filter: filter ?? this.filter,
      focalLength: focalLength ?? this.focalLength,
      aperture: aperture ?? this.aperture,
    );
  }

  /// Renders the acquisition block as Markdown suitable for an AstroBin
  /// description or a social post.
  ///
  /// Always includes the **Integration** line with the `HH:MM:SS` HMS string,
  /// the frames × exposure breakdown, and the subject type; equipment lines are
  /// included only when their corresponding fields are populated.
  String toMarkdown() {
    final buf = StringBuffer();
    final heading = title?.trim();
    if (heading != null && heading.isNotEmpty) {
      buf.writeln('## $heading');
      buf.writeln();
    }

    buf.writeln('**Subject type:** $subjectType');
    buf.writeln(
      '**Frames:** $frames x ${_trimNum(perFrameExposureSecs)}s',
    );
    buf.writeln('**Integration:** $integrationHms');

    final tele = telescope?.trim();
    if (tele != null && tele.isNotEmpty) {
      buf.writeln('**Telescope:** $tele');
    }
    final cam = camera?.trim();
    if (cam != null && cam.isNotEmpty) {
      buf.writeln('**Camera:** $cam');
    }
    final filt = filter?.trim();
    if (filt != null && filt.isNotEmpty) {
      buf.writeln('**Filter:** $filt');
    }
    if (focalLength != null) {
      buf.writeln('**Focal length:** ${_trimNum(focalLength!)} mm');
    }
    if (aperture != null) {
      buf.writeln('**Aperture:** ${_trimNum(aperture!)} mm');
    }
    final fRatio = focalRatio;
    if (fRatio != null) {
      buf.writeln('**Focal ratio:** f/${fRatio.toStringAsFixed(1)}');
    }

    return buf.toString().trimRight();
  }

  /// Serialises the metadata to a JSON-compatible map. Optional fields are
  /// omitted when null so the payload stays minimal.
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'subjectType': subjectType,
      'integrationSecs': integrationSecs,
      'integrationHms': integrationHms,
      'frames': frames,
      'perFrameExposureSecs': perFrameExposureSecs,
    };
    if (title != null) json['title'] = title;
    if (telescope != null) json['telescope'] = telescope;
    if (camera != null) json['camera'] = camera;
    if (filter != null) json['filter'] = filter;
    if (focalLength != null) json['focalLength'] = focalLength;
    if (aperture != null) json['aperture'] = aperture;
    final fRatio = focalRatio;
    if (fRatio != null) json['focalRatio'] = fRatio;
    return json;
  }

  factory AstroBinExportMetadata.fromJson(Map<String, dynamic> json) {
    return AstroBinExportMetadata(
      title: json['title'] as String?,
      subjectType: (json['subjectType'] as String?) ?? 'Deep sky',
      integrationSecs: (json['integrationSecs'] as num?)?.toDouble() ?? 0,
      frames: (json['frames'] as num?)?.toInt() ?? 0,
      telescope: json['telescope'] as String?,
      camera: json['camera'] as String?,
      filter: json['filter'] as String?,
      focalLength: (json['focalLength'] as num?)?.toDouble(),
      aperture: (json['aperture'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AstroBinExportMetadata &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          subjectType == other.subjectType &&
          integrationSecs == other.integrationSecs &&
          frames == other.frames &&
          telescope == other.telescope &&
          camera == other.camera &&
          filter == other.filter &&
          focalLength == other.focalLength &&
          aperture == other.aperture;

  @override
  int get hashCode => Object.hash(
        title,
        subjectType,
        integrationSecs,
        frames,
        telescope,
        camera,
        filter,
        focalLength,
        aperture,
      );
}

/// Formats a duration in seconds as zero-padded `HH:MM:SS`.
///
/// Negative inputs are treated as zero. This is the canonical acquisition-block
/// format (distinct from the compact `2h12m` watermark form used elsewhere).
String formatHms(double seconds) {
  final total = seconds <= 0 ? 0 : seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)}';
}

/// Formats a number without a trailing `.0` for whole values, otherwise with a
/// single decimal place (e.g. `120` → `'120'`, `2.5` → `'2.5'`).
String _trimNum(double value) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
