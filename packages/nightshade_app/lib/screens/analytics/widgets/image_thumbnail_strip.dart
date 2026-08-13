import 'dart:io';
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show
        imagingBackendProvider,
        ImagingBackend,
        imagingRecordsRepositoryProvider,
        isRemoteModeProvider,
        DbCapturedImage,
        FramePhotometricCalibrationRow,
        FrameQualityAssessment,
        FrameQualityAssessmentService,
        FrameQualityLevel;

import '../../../utils/snackbar_helper.dart';
import '../analytics_screen.dart' show dbSessionImagesProvider;
import '../../../utils/filter_label.dart';
import 'frame_detail_dialog.dart';
import '../../../widgets/frame_thumbnail_loader.dart';

enum _QualityFilter {
  all,
  needsReview,
  poor,
}

/// Fixed height for the horizontal thumbnail rail (not a chart plot area).
const double kAnalyticsThumbnailRailHeight = 120;

/// Horizontal scrollable strip of image thumbnails.
///
/// Decorates each thumbnail with the existing quality badge plus a richer set
/// of science badges (plate-solve checkmark, zero-point chip when available)
/// and exposes an accept/reject context menu via long-press so users can flag
/// poor frames without losing them — implements the P3.4 "manual quality
/// gate, no auto-delete" pattern from the science gap list.
class ImageThumbnailStrip extends StatefulWidget {
  final List<DbCapturedImage> images;

  /// Overrides what a tap on a thumbnail does. When null the strip opens its
  /// own frame inspector — the rail is a gallery of the night's frames, and
  /// every caller in the app wants "show me this frame", so leaving the
  /// gesture inert unless a caller happened to supply a handler meant no
  /// caller ever did and clicking a thumbnail did nothing anywhere.
  final Function(DbCapturedImage)? onImageTap;

  /// Optional per-image calibration map (keyed by `image.id`). When supplied,
  /// the thumbnail strip renders a small ZP badge per frame and tints the
  /// border based on calibration status. Callers can omit this when they
  /// don't want to fetch calibrations for performance reasons.
  final Map<int, FramePhotometricCalibrationRow>? calibrationByImageId;

  const ImageThumbnailStrip({
    super.key,
    required this.images,
    this.onImageTap,
    this.calibrationByImageId,
  });

  @override
  State<ImageThumbnailStrip> createState() => _ImageThumbnailStripState();
}

class _ImageThumbnailStripState extends State<ImageThumbnailStrip> {
  _QualityFilter _qualityFilter = _QualityFilter.all;
  final ScrollController _railController = ScrollController();

  @override
  void dispose() {
    _railController.dispose();
    super.dispose();
  }

  /// A plain vertical mouse wheel over a horizontal rail does nothing in
  /// Flutter by default, so the page scrolled underneath and the trailing
  /// frames of a 200-frame night were only reachable with shift+wheel — which
  /// nothing on screen advertised. Translate vertical wheel deltas into
  /// horizontal scrolling; horizontal deltas are left to the Scrollable, which
  /// already consumes them (handling both would double-scroll).
  ///
  /// The move goes through the pointer-signal resolver rather than straight to
  /// `jumpTo`, because a bare `Listener` callback does not consume the event:
  /// the enclosing page Scrollable still saw the same notch and the rail and
  /// the page scrolled together, sliding the rail out from under the pointer.
  /// Registering here also loses on purpose when the rail's own Scrollable has
  /// already claimed the notch (shift+wheel), which otherwise moved the rail
  /// twice — once by the Scrollable and once by this handler.
  void _handleRailScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.scrollDelta.dx != 0 || event.scrollDelta.dy == 0) return;
    if (!_railController.hasClients) return;
    final position = _railController.position;
    if (position.maxScrollExtent <= 0) return;
    final target = (position.pixels + event.scrollDelta.dy).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    // At either end the rail has nothing left to give, so the notch is left to
    // the page instead of being swallowed into a dead zone.
    if (target == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) {
        if (!_railController.hasClients) return;
        _railController.jumpTo(target);
      },
    );
  }

  bool _matchesFilter(FrameQualityAssessment? assessment) {
    switch (_qualityFilter) {
      case _QualityFilter.all:
        return true;
      case _QualityFilter.needsReview:
        return assessment?.level == FrameQualityLevel.needsReview;
      case _QualityFilter.poor:
        return assessment?.level == FrameQualityLevel.poor;
    }
  }

  /// Whether the assessor has any measurement to judge this frame on.
  ///
  /// Calibration frames (and lights whose analysis never ran) carry none, and
  /// the assessor's score is a decrement-only walk from a 75 default — with
  /// nothing to decrement it returns "Good" for a frame nobody measured.
  static bool _hasQualityMeasurement(DbCapturedImage image) =>
      image.hfr != null ||
      image.starCount != null ||
      image.guidingRmsTotal != null ||
      image.qualityScore != null;

  String _filterLabel(_QualityFilter filter) {
    switch (filter) {
      case _QualityFilter.all:
        return 'All';
      case _QualityFilter.needsReview:
        return 'Needs Review';
      case _QualityFilter.poor:
        return 'Poor';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    const assessor = FrameQualityAssessmentService();
    // Only frames the assessor can actually judge are handed to it. Its
    // advisory score starts at 75 and is only ever decremented by a metric, so
    // a frame with no HFR, no star count, no guiding RMS and no stored quality
    // score — every dark, flat and bias — came back "Good, 75 score" and was
    // counted in the Good chip. The session summary claimed 12 good frames
    // when 8 had been assessed good and 4 had never been measured at all.
    final gradable =
        widget.images.where(_hasQualityMeasurement).toList(growable: false);
    final ungradedCount = widget.images.length - gradable.length;
    final assessments = assessor.assessBatch(gradable);
    final summary = assessor.summarize(assessments);
    final filteredImages = widget.images
        .where((image) => _matchesFilter(assessments[image.id]))
        .toList();

    if (widget.images.isEmpty) {
      return Container(
        height: kAnalyticsThumbnailRailHeight,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        ),
        child: Center(
          child: Text(
            'No images captured in this session',
            style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textMuted),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SummaryChip(
              label: 'Good',
              value: summary.good,
              color: colors.success,
            ),
            _SummaryChip(
              label: 'Needs Review',
              value: summary.needsReview,
              color: colors.warning,
            ),
            _SummaryChip(
              label: 'Poor',
              value: summary.poor,
              color: colors.error,
            ),
            if (ungradedCount > 0)
              _SummaryChip(
                label: 'Unrated',
                value: ungradedCount,
                color: colors.textMuted,
              ),
            _SummaryChip(
              label: 'Total',
              value: widget.images.length,
              color: colors.info,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _QualityFilter.values
              .map(
                (filter) => _QualityFilterChip(
                  label: _filterLabel(filter),
                  selected: _qualityFilter == filter,
                  onTap: () => setState(() => _qualityFilter = filter),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        SizedBox(
          // Thumbnail rail — fixed height (not chart-like). The list reserves
          // the bottom 10px of it for the always-visible scrollbar rather than
          // growing, so the loading and error placeholders that use this same
          // constant stay the same height as the loaded rail.
          height: kAnalyticsThumbnailRailHeight,
          child: filteredImages.isEmpty
              ? Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline8),
                    border: Border.all(color: colors.border),
                  ),
                  child: Center(
                    child: Text(
                      'No frames match "${_filterLabel(_qualityFilter)}"',
                      style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
                          color: colors.textMuted),
                    ),
                  ),
                )
              : Listener(
                  onPointerSignal: _handleRailScroll,
                  child: Scrollbar(
                    controller: _railController,
                    // The rail is the only horizontal scroller on the page, and
                    // an overlay-only bar left "there are more frames" invisible
                    // until the user happened to drag it.
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _railController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(bottom: 10),
                      // Fixed-width thumbnails (100w + 8 right padding = 108).
                      itemExtent: 108,
                      itemCount: filteredImages.length,
                      itemBuilder: (context, index) {
                        final image = filteredImages[index];
                        return _ImageThumbnail(
                          image: image,
                          assessment: assessments[image.id],
                          calibration: widget.calibrationByImageId?[image.id],
                          onImageTap: widget.onImageTap,
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: NightshadeDecorations.tintedBadge(
        color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
      ),
      child: Text(
        '$label: $value',
        style: NightshadeTypography.labelStrongSm.copyWith(
          color: color,
        ),
      ),
    );
  }
}

class _QualityFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _QualityFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return ChoiceChip(
      label: Text(
        label,
        style: NightshadeTypography.labelStrongSm.copyWith(
          color: selected ? colors.textPrimary : colors.textSecondary,
        ),
      ),
      selected: selected,
      selectedColor: colors.primary.withValues(alpha: 0.2),
      backgroundColor: colors.surfaceAlt,
      side: BorderSide(color: selected ? colors.primary : colors.border),
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ImageThumbnail extends ConsumerStatefulWidget {
  final DbCapturedImage image;
  final FrameQualityAssessment? assessment;
  final FramePhotometricCalibrationRow? calibration;
  final Function(DbCapturedImage)? onImageTap;

  const _ImageThumbnail({
    required this.image,
    this.assessment,
    this.calibration,
    this.onImageTap,
  });

  @override
  ConsumerState<_ImageThumbnail> createState() => _ImageThumbnailState();
}

class _ImageThumbnailState extends ConsumerState<_ImageThumbnail> {
  late Future<FrameThumbnailPayload> _thumbnailFuture;
  ProviderSubscription<ImagingBackend>? _backendSubscription;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = loadFrameThumbnail(ref, widget.image);
    _backendSubscription = ref.listenManual<ImagingBackend>(
      imagingBackendProvider,
      (previous, next) {
        if (identical(previous, next) || !mounted) return;
        setState(() {
          _thumbnailFuture = loadFrameThumbnail(ref, widget.image);
        });
      },
    );
  }

  @override
  void dispose() {
    _backendSubscription?.close();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ImageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.id != widget.image.id ||
        oldWidget.image.filePath != widget.image.filePath) {
      _thumbnailFuture = loadFrameThumbnail(ref, widget.image);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final qualityColor = _getQualityColor(colors);
    final qualityBorderColor =
        !widget.image.isAccepted ? colors.error : qualityColor;
    final qualityBorderWidth = widget.image.isAccepted &&
            widget.assessment != null &&
            widget.assessment!.level == FrameQualityLevel.good
        ? 1.0
        : 2.0;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: _handleTap,
        onLongPress: () => _showFrameMenu(context),
        onSecondaryTap: () => _showFrameMenu(context),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        child: Container(
          width: 100,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            border: Border.all(
              color: qualityBorderColor,
              width: qualityBorderWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: FutureBuilder<FrameThumbnailPayload>(
                          future: _thumbnailFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                    ConnectionState.waiting &&
                                !snapshot.hasData) {
                              return const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                ),
                              );
                            }

                            final payload = snapshot.data ??
                                const FrameThumbnailPayload(fileExists: false);

                            if (payload.bytes != null &&
                                payload.bytes!.isNotEmpty) {
                              return ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  topRight: Radius.circular(8),
                                ),
                                child: Image.memory(
                                  payload.bytes!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (_, __, ___) => Icon(
                                    NightshadeIcons.imageOff,
                                    size: 32,
                                    color: colors.textMuted,
                                  ),
                                ),
                              );
                            }

                            if (payload.fileExists &&
                                isDisplayableImagePath(widget.image.filePath) &&
                                !isRemoteMode) {
                              return ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  topRight: Radius.circular(8),
                                ),
                                child: Image.file(
                                  File(widget.image.filePath),
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (_, __, ___) => Icon(
                                    NightshadeIcons.image,
                                    size: 32,
                                    color: colors.textMuted,
                                  ),
                                ),
                              );
                            }

                            if (payload.fileExists) {
                              return Icon(
                                NightshadeIcons.image,
                                size: 32,
                                color: colors.textMuted,
                              );
                            }

                            if (payload.errorMessage != null) {
                              return Tooltip(
                                message: payload.errorMessage!,
                                child: Icon(
                                  NightshadeIcons.error,
                                  size: 32,
                                  color: colors.error,
                                ),
                              );
                            }

                            return Icon(
                              NightshadeIcons.imageOff,
                              size: 32,
                              color: colors.textMuted,
                            );
                          },
                        ),
                      ),
                      // Quality badge (GOOD / NEEDS REVIEW / POOR) is added
                      // AFTER the thumbnail so it paints ON TOP of it. As the
                      // Stack's first child it was covered by every thumbnail
                      // that loaded (Image.memory, BoxFit.cover, infinite
                      // width/height), so the chip only ever appeared on frames
                      // whose image FAILED to load — exactly inverting the cull
                      // workflow it exists for.
                      //
                      // An unmeasured frame gets an explicit UNRATED chip
                      // rather than a missing badge, so "no grade" reads as a
                      // statement instead of as a rendering gap.
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Tooltip(
                          message: _qualityTooltip(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: qualityColor.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(
                                  NightshadeTokens.radiusInline4),
                            ),
                            child: Text(
                              widget.assessment?.label.toUpperCase() ??
                                  'UNRATED',
                              style: const TextStyle(
                                fontSize: NightshadeTypography.fontSize8,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFFFFFFF),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (widget.image.hfr != null)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getHfrColor(widget.image.hfr!, colors)
                                  .withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(
                                  NightshadeTokens.radiusInline4),
                            ),
                            child: Text(
                              widget.image.hfr!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: NightshadeTypography.fontSize9,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFFFFFF),
                              ),
                            ),
                          ),
                        ),
                      // P2.3 science badges: small solve checkmark + optional
                      // ZP chip. Sit bottom-right so they don't fight the HFR
                      // and quality badges, and only appear when there is
                      // something meaningful to report.
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.calibration?.zeroPoint != null)
                              _ScienceBadge(
                                tooltip:
                                    'Zero-point ${widget.calibration!.zeroPoint!.toStringAsFixed(2)} · '
                                    '${widget.calibration!.matchedStarCount} stars',
                                color: colors.info,
                                label:
                                    'ZP ${widget.calibration!.zeroPoint!.toStringAsFixed(1)}',
                              ),
                            if (widget.calibration?.zeroPoint != null &&
                                widget.image.isPlateSolved)
                              const SizedBox(width: 3),
                            if (widget.image.isPlateSolved)
                              _ScienceBadge(
                                tooltip: 'Plate solved',
                                color: colors.success,
                                icon: LucideIcons.crosshair,
                              ),
                          ],
                        ),
                      ),
                      if (!widget.image.isAccepted)
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.error,
                              borderRadius: BorderRadius.circular(
                                  NightshadeTokens.radiusInline4),
                            ),
                            child: Text(
                              'REJECTED',
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize8,
                                fontWeight: FontWeight.w700,
                                color: colors.background,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filterLabel(widget.image.filter),
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize10,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${widget.image.exposureDuration.toInt()}s',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize9,
                        color: colors.textSecondary,
                      ),
                    ),
                    if (widget.assessment != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${widget.assessment!.advisoryScore.toStringAsFixed(0)} score',
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize8,
                                color: qualityColor,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.assessment!.needsReview &&
                              widget.assessment!.reasons.isNotEmpty)
                            Tooltip(
                              message: widget.assessment!.reasons.join('\n'),
                              child: Icon(
                                NightshadeIcons.info,
                                size: 10,
                                color: qualityColor,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the frame inspector, unless the caller supplied its own handler.
  Future<void> _handleTap() async {
    final override = widget.onImageTap;
    if (override != null) {
      override(widget.image);
      return;
    }
    final changed = await showFrameDetailDialog(
      context,
      image: widget.image,
      assessment: widget.assessment,
      calibration: widget.calibration,
    );
    // Accepting/rejecting from the inspector has to reach the rail, the stat
    // strip and the four charts, all of which read the same polled provider.
    if (changed && mounted) ref.invalidate(dbSessionImagesProvider);
  }

  String _qualityTooltip() {
    if (widget.assessment == null) {
      return 'Not rated — this frame has no HFR, star count, guiding RMS or '
          'stored quality score to judge';
    }
    if (widget.assessment!.reasons.isEmpty) return widget.assessment!.label;
    return '${widget.assessment!.label}\n${widget.assessment!.reasons.join('\n')}';
  }

  Color _getQualityColor(NightshadeColors colors) {
    if (!widget.image.isAccepted) return colors.error;
    final value = widget.assessment;
    // Unrated frames get a neutral chip, not a quality colour.
    if (value == null) return colors.textMuted;

    switch (value.level) {
      case FrameQualityLevel.good:
        return colors.success;
      case FrameQualityLevel.needsReview:
        return colors.warning;
      case FrameQualityLevel.poor:
        return colors.error;
    }
  }

  Color _getHfrColor(double hfr, NightshadeColors colors) {
    if (hfr < 2.0) {
      return colors.success;
    } else if (hfr < 2.5) {
      return colors.info;
    } else if (hfr < 3.5) {
      return colors.warning;
    } else {
      return colors.error;
    }
  }

  Future<void> _showFrameMenu(BuildContext context) async {
    final colors = NightshadeColors.of(context);
    final isAccepted = widget.image.isAccepted;
    final backend = ref.read(imagingBackendProvider);
    final action = await showMenu<_FrameMenuAction>(
      context: context,
      position: _menuPosition(context),
      color: colors.surface,
      items: <PopupMenuEntry<_FrameMenuAction>>[
        PopupMenuItem(
          value: isAccepted ? _FrameMenuAction.reject : _FrameMenuAction.accept,
          child: Row(
            children: [
              Icon(
                isAccepted ? LucideIcons.flag : LucideIcons.check,
                size: 14,
                color: isAccepted ? colors.warning : colors.success,
              ),
              const SizedBox(width: 8),
              Text(
                isAccepted ? 'Flag as poor quality' : 'Restore as good',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: NightshadeTypography.fontSize12),
              ),
            ],
          ),
        ),
        if (widget.calibration != null)
          PopupMenuItem(
            value: _FrameMenuAction.info,
            child: Row(
              children: [
                Icon(LucideIcons.info, size: 14, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Show calibration details',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: NightshadeTypography.fontSize12),
                ),
              ],
            ),
          ),
      ],
    );
    if (!mounted || !context.mounted || action == null) return;
    if (!identical(ref.read(imagingBackendProvider), backend)) {
      context.showErrorSnackBar(
        'Connected rig changed; the frame was not modified',
      );
      return;
    }
    switch (action) {
      case _FrameMenuAction.accept:
        await _setAccepted(true);
        break;
      case _FrameMenuAction.reject:
        await _setAccepted(false);
        break;
      case _FrameMenuAction.info:
        if (!context.mounted) return;
        _showCalibrationDetails(context);
        break;
    }
  }

  /// Route accept/reject through the imaging-records repository so the write
  /// reaches the remote host in NetworkBackend mode (the local DAO would only
  /// mutate an empty companion DB), then refresh the polled session images.
  Future<void> _setAccepted(bool accepted) async {
    try {
      final repo = ref.read(imagingRecordsRepositoryProvider);
      if (accepted) {
        await repo.acceptImage(widget.image.id);
      } else {
        await repo.rejectImage(widget.image.id, 'Manual quality flag');
      }
      if (!mounted) return;
      ref.invalidate(dbSessionImagesProvider);
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Failed to update frame: $e');
    }
  }

  RelativeRect _menuPosition(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlay == null) {
      return const RelativeRect.fromLTRB(0, 0, 0, 0);
    }
    final tl = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    return RelativeRect.fromRect(
      Rect.fromPoints(tl, tl + const Offset(40, 40)),
      Offset.zero & overlay.size,
    );
  }

  void _showCalibrationDetails(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final c = widget.calibration;
    if (c == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Frame ${widget.image.fileName}',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: NightshadeTypography.fontSize15)),
        content: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            context,
            designMaxWidth: 420,
            designMaxHeight: 360,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow('Calibrated', c.isCalibrated ? 'Yes' : 'No', colors),
              _DetailRow(
                'Zero point',
                c.zeroPoint == null ? '—' : c.zeroPoint!.toStringAsFixed(3),
                colors,
              ),
              _DetailRow(
                  'Matched stars', c.matchedStarCount.toString(), colors),
              _DetailRow(
                'Fit RMS',
                '${c.calibrationRms.toStringAsFixed(3)} mag',
                colors,
              ),
              _DetailRow('Catalog', c.catalogSource, colors),
              _DetailRow('Solver', c.solverId, colors),
              if (c.limitingMag5Sigma != null)
                _DetailRow(
                  'Lim mag (5Ïƒ)',
                  c.limitingMag5Sigma!.toStringAsFixed(2),
                  colors,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

enum _FrameMenuAction { accept, reject, info }

class _ScienceBadge extends StatelessWidget {
  final String tooltip;
  final Color color;
  final String? label;
  final IconData? icon;

  const _ScienceBadge({
    required this.tooltip,
    required this.color,
    this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: label == null ? 3 : 4,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
        ),
        child: icon != null
            ? Icon(icon, size: 9, color: const Color(0xFFFFFFFF))
            : Text(
                label ?? '',
                style: const TextStyle(
                  fontSize: NightshadeTypography.fontSize8,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFFFFF),
                ),
              ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _DetailRow(this.label, this.value, this.colors);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: NightshadeTypography.h6.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
