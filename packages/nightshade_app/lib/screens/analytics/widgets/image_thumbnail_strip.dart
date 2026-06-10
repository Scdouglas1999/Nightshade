import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show
        imagingBackendProvider,
        imagesDaoProvider,
        isRemoteModeProvider,
        loggingServiceProvider,
        DbCapturedImage,
        FramePhotometricCalibrationRow,
        FrameQualityAssessment,
        FrameQualityAssessmentService,
        FrameQualityLevel;

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
    final assessments = assessor.assessBatch(widget.images);
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
            _SummaryChip(
              label: 'Total',
              value: summary.total,
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
          // Thumbnail rail — fixed height (not chart-like).
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
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  // Fixed-width thumbnails (100w + 8 right padding = 108).
                  itemExtent: 108,
                  itemCount: filteredImages.length,
                  itemBuilder: (context, index) {
                    final image = filteredImages[index];
                    return _ImageThumbnail(
                      image: image,
                      assessment: assessments[image.id],
                      calibration: widget.calibrationByImageId?[image.id],
                      onTap: widget.onImageTap != null
                          ? () => widget.onImageTap!(image)
                          : null,
                    );
                  },
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

class _ThumbnailPayload {
  final Uint8List? bytes;
  final bool fileExists;
  final String? errorMessage;

  const _ThumbnailPayload({
    this.bytes,
    required this.fileExists,
    this.errorMessage,
  });
}

class _ImageThumbnail extends ConsumerStatefulWidget {
  final DbCapturedImage image;
  final FrameQualityAssessment? assessment;
  final FramePhotometricCalibrationRow? calibration;
  final VoidCallback? onTap;

  const _ImageThumbnail({
    required this.image,
    this.assessment,
    this.calibration,
    this.onTap,
  });

  @override
  ConsumerState<_ImageThumbnail> createState() => _ImageThumbnailState();
}

class _ImageThumbnailState extends ConsumerState<_ImageThumbnail> {
  late Future<_ThumbnailPayload> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _ImageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.id != widget.image.id ||
        oldWidget.image.filePath != widget.image.filePath) {
      _thumbnailFuture = _loadThumbnail();
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
        onTap: widget.onTap,
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
                      if (widget.assessment != null)
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
                                widget.assessment!.label.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: NightshadeTypography.fontSize8,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFFFFFF),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Center(
                        child: FutureBuilder<_ThumbnailPayload>(
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
                                const _ThumbnailPayload(fileExists: false);

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
                                !_isFITSLikePath(widget.image.filePath) &&
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
                                    'Zero-point ${widget.calibration!.zeroPoint!.toStringAsFixed(2)} Â· '
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
                      widget.image.filter ?? 'L',
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

  Future<_ThumbnailPayload> _loadThumbnail() async {
    final backend = ref.read(imagingBackendProvider);
    String? backendError;
    try {
      final bytes = await backend.getImageThumbnail(widget.image.id);
      if (bytes.isNotEmpty) {
        return _ThumbnailPayload(bytes: bytes, fileExists: true);
      }
      backendError =
          'Thumbnail not found in backend cache for image ${widget.image.id}.';
    } catch (error) {
      backendError =
          'Backend thumbnail request failed for image ${widget.image.id}: $error';
      ref.read(loggingServiceProvider).warning(
          'ImageThumbnailStrip: $backendError',
          source: 'ImageThumbnailStrip');
    }

    if (ref.read(isRemoteModeProvider)) {
      return _ThumbnailPayload(
        fileExists: false,
        errorMessage: backendError,
      );
    }

    try {
      final exists = await File(widget.image.filePath).exists();
      if (exists) {
        return _ThumbnailPayload(fileExists: true, errorMessage: backendError);
      }
      return _ThumbnailPayload(
        fileExists: false,
        errorMessage: backendError,
      );
    } catch (error) {
      final localError =
          'Failed to check local image file "${widget.image.filePath}": $error';
      ref.read(loggingServiceProvider).warning(
          'ImageThumbnailStrip: $localError',
          source: 'ImageThumbnailStrip');
      return _ThumbnailPayload(
        fileExists: false,
        errorMessage: '$backendError\n$localError',
      );
    }
  }

  bool _isFITSLikePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.fits') ||
        lower.endsWith('.fit') ||
        lower.endsWith('.fts') ||
        lower.endsWith('.xisf');
  }

  String _qualityTooltip() {
    if (widget.assessment == null) return 'No quality assessment';
    if (widget.assessment!.reasons.isEmpty) return widget.assessment!.label;
    return '${widget.assessment!.label}\n${widget.assessment!.reasons.join('\n')}';
  }

  Color _getQualityColor(NightshadeColors colors) {
    if (!widget.image.isAccepted) return colors.error;
    final value = widget.assessment;
    if (value == null) return colors.border;

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
    if (!mounted || action == null) return;
    switch (action) {
      case _FrameMenuAction.accept:
        await ref.read(imagesDaoProvider).acceptImage(widget.image.id);
        break;
      case _FrameMenuAction.reject:
        await ref
            .read(imagesDaoProvider)
            .rejectImage(widget.image.id, 'Manual quality flag');
        break;
      case _FrameMenuAction.info:
        if (!mounted) return;
        _showCalibrationDetails(context);
        break;
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
