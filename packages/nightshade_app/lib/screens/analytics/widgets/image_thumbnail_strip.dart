import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/src/database/database.dart' show CapturedImage;
import 'package:nightshade_core/nightshade_core.dart'
    show
        isRemoteModeProvider,
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
  final List<CapturedImage> images;
  final Function(CapturedImage)? onImageTap;

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

class _ImageThumbnail extends ConsumerWidget {
  final CapturedImage image;
  final FrameQualityAssessment? assessment;
  final VoidCallback? onTap;

  const _ImageThumbnail({
    required this.image,
    this.assessment,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final qualityColor = _getQualityColor(colors);
    final qualityBorderColor = !image.isAccepted ? colors.error : qualityColor;
    final qualityBorderWidth = image.isAccepted &&
            assessment != null &&
            assessment!.level == FrameQualityLevel.good
        ? 1.0
        : 2.0;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: onTap,
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
              // Thumbnail placeholder (would show actual image preview in production)
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
                      if (assessment != null)
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
                                assessment!.label.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),

                      // File exists check - in remote mode, assume file exists on server
                      Center(
                        child: FutureBuilder<bool>(
                          future: _fileExists(image.filePath, isRemoteMode),
                          builder: (context, snapshot) {
                            if (snapshot.data == true) {
                              return Icon(
                                Icons.image,
                                size: 32,
                                color: colors.textMuted,
                              );
                            } else {
                              return Icon(
                                Icons.broken_image,
                                size: 32,
                                color: colors.textMuted,
                              );
                            }
                          },
                        ),
                      ),

                      // Quality badge
                      if (image.hfr != null)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getHfrColor(image.hfr!)
                                  .withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              image.hfr!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                      // Rejection indicator
                      if (!image.isAccepted)
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
                            child: const Text(
                              'REJECTED',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Image info
              Padding(
                padding: const EdgeInsets.all(4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      image.filter ?? 'L',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${image.exposureDuration.toInt()}s',
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.textSecondary,
                      ),
                    ),
                    if (assessment != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${assessment!.advisoryScore.toStringAsFixed(0)} score',
                              style: TextStyle(
                                fontSize: 8,
                                color: qualityColor,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (assessment!.needsReview &&
                              assessment!.reasons.isNotEmpty)
                            Tooltip(
                              message: assessment!.reasons.join('\n'),
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

  Future<bool> _fileExists(String path, bool isRemoteMode) async {
    // In remote mode, the file path refers to the server filesystem
    // We can't check it locally, so assume it exists
    if (isRemoteMode) {
      return true;
    }
    try {
      return await File(path).exists();
    } catch (e) {
      return false;
    }
  }

  String _qualityTooltip() {
    if (assessment == null) return 'No quality assessment';
    if (assessment!.reasons.isEmpty) return assessment!.label;
    return '${assessment!.label}\n${assessment!.reasons.join('\n')}';
  }

  Color _getQualityColor(NightshadeColors colors) {
    if (!image.isAccepted) return colors.error;
    final value = assessment;
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

  Color _getHfrColor(double hfr) {
    // Good HFR is typically < 2.5, excellent < 2.0
    // Bad HFR is > 4.0
    if (hfr < 2.0) {
      return Colors.green;
    } else if (hfr < 2.5) {
      return Colors.lightGreen;
    } else if (hfr < 3.5) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
}
