import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show
        backendProvider,
        isRemoteModeProvider,
        loggingServiceProvider,
        DbCapturedImage,
        FrameQualityAssessment,
        FrameQualityAssessmentService,
        FrameQualityLevel;

enum _QualityFilter {
  all,
  needsReview,
  poor,
}

/// Horizontal scrollable strip of image thumbnails
class ImageThumbnailStrip extends StatefulWidget {
  final List<DbCapturedImage> images;
  final Function(DbCapturedImage)? onImageTap;

  const ImageThumbnailStrip({
    super.key,
    required this.images,
    this.onImageTap,
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    const assessor = FrameQualityAssessmentService();
    final assessments = assessor.assessBatch(widget.images);
    final summary = assessor.summarize(assessments);
    final filteredImages = widget.images
        .where((image) => _matchesFilter(assessments[image.id]))
        .toList();

    if (widget.images.isEmpty) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'No images captured in this session',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
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
          height: 120,
          child: filteredImages.isEmpty
              ? Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: Center(
                    child: Text(
                      'No frames match "${_filterLabel(_qualityFilter)}"',
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
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
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
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
  final VoidCallback? onTap;

  const _ImageThumbnail({
    required this.image,
    this.assessment,
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;
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
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 100,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
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
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.assessment!.label.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 8,
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
                                    Icons.broken_image,
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
                                    Icons.image,
                                    size: 32,
                                    color: colors.textMuted,
                                  ),
                                ),
                              );
                            }

                            if (payload.fileExists) {
                              return Icon(
                                Icons.image,
                                size: 32,
                                color: colors.textMuted,
                              );
                            }

                            if (payload.errorMessage != null) {
                              return Tooltip(
                                message: payload.errorMessage!,
                                child: Icon(
                                  Icons.error_outline,
                                  size: 32,
                                  color: colors.error,
                                ),
                              );
                            }

                            return Icon(
                              Icons.broken_image,
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
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.image.hfr!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFFFFFF),
                              ),
                            ),
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
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'REJECTED',
                              style: TextStyle(
                                fontSize: 8,
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
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${widget.image.exposureDuration.toInt()}s',
                      style: TextStyle(
                        fontSize: 9,
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
                                fontSize: 8,
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
                                Icons.info_outline,
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
    final backend = ref.read(backendProvider);
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
}
