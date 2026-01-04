import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/src/database/database.dart' show CapturedImage;
import 'package:nightshade_core/nightshade_core.dart' show isRemoteModeProvider;

/// Horizontal scrollable strip of image thumbnails
class ImageThumbnailStrip extends StatelessWidget {
  final List<CapturedImage> images;
  final Function(CapturedImage)? onImageTap;

  const ImageThumbnailStrip({
    super.key,
    required this.images,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    if (images.isEmpty) {
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

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        itemBuilder: (context, index) {
          final image = images[index];
          return _ImageThumbnail(
            image: image,
            onTap: onImageTap != null ? () => onImageTap!(image) : null,
          );
        },
      ),
    );
  }
}

class _ImageThumbnail extends ConsumerWidget {
  final CapturedImage image;
  final VoidCallback? onTap;

  const _ImageThumbnail({
    required this.image,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isRemoteMode = ref.watch(isRemoteModeProvider);

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
              color: image.isAccepted ? colors.border : colors.error,
              width: image.isAccepted ? 1 : 2,
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
                              color: _getHfrColor(image.hfr!).withOpacity(0.9),
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
