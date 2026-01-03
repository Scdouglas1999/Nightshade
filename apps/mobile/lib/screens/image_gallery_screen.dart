import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path_provider/path_provider.dart';

/// Image Gallery Screen for mobile app
///
/// Displays a grid of images from a session with thumbnails, metadata,
/// and download functionality.
class ImageGalleryScreen extends ConsumerStatefulWidget {
  final int sessionId;
  final String sessionName;

  const ImageGalleryScreen({
    super.key,
    required this.sessionId,
    required this.sessionName,
  });

  @override
  ConsumerState<ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends ConsumerState<ImageGalleryScreen> {
  List<CapturedImage> _images = [];
  bool _isLoading = true;
  String? _error;
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloaded = {};

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final backend = ref.read(backendProvider);
      final images = await backend.getSessionImages(widget.sessionId);

      setState(() {
        _images = images;
        _isLoading = false;
      });

      // Check which images are already downloaded
      await _checkDownloadedImages();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _checkDownloadedImages() async {
    final dir = await getApplicationDocumentsDirectory();

    for (final image in _images) {
      final localPath = '${dir.path}/nightshade/sessions/${widget.sessionId}/${_getFileName(image)}';
      final exists = await File(localPath).exists();

      setState(() {
        _isDownloaded[image.id] = exists;
      });
    }
  }

  String _getFileName(CapturedImage image) {
    return image.filePath.split('/').last;
  }

  Future<void> _downloadImage(CapturedImage image) async {
    final dir = await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/nightshade/sessions/${widget.sessionId}/${_getFileName(image)}';

    setState(() {
      _downloadProgress[image.id] = 0.0;
    });

    try {
      final backend = ref.read(backendProvider);

      await backend.downloadImage(
        int.parse(image.id),
        localPath,
        onProgress: (progress) {
          setState(() {
            _downloadProgress[image.id] = progress;
          });
        },
      );

      setState(() {
        _downloadProgress.remove(image.id);
        _isDownloaded[image.id] = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded ${_getFileName(image)}')),
        );
      }
    } catch (e) {
      setState(() {
        _downloadProgress.remove(image.id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _downloadAllImages() async {
    final undownloaded = _images.where((img) => !(_isDownloaded[img.id] ?? false)).toList();

    if (undownloaded.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All images already downloaded')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download All'),
        content: Text('Download ${undownloaded.length} images?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final image in undownloaded) {
        await _downloadImage(image);
      }
    }
  }

  void _showImageDetails(CapturedImage image) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _ImageDetailSheet(
        image: image,
        isDownloaded: _isDownloaded[image.id] ?? false,
        onDownload: () {
          Navigator.pop(context);
          _downloadImage(image);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sessionName),
        actions: [
          if (_images.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download_for_offline),
              onPressed: _downloadAllImages,
              tooltip: 'Download All',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadImages,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_images.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('No images in this session'),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: _images.length,
      itemBuilder: (context, index) {
        final image = _images[index];
        return _ImageThumbnailCard(
          image: image,
          isDownloaded: _isDownloaded[image.id] ?? false,
          downloadProgress: _downloadProgress[image.id],
          onTap: () => _showImageDetails(image),
          onDownload: () => _downloadImage(image),
        );
      },
    );
  }
}

/// Image thumbnail card widget
class _ImageThumbnailCard extends ConsumerWidget {
  final CapturedImage image;
  final bool isDownloaded;
  final double? downloadProgress;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  const _ImageThumbnailCard({
    required this.image,
    required this.isDownloaded,
    this.downloadProgress,
    required this.onTap,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail image
            FutureBuilder<Image>(
              future: _loadThumbnail(ref),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return snapshot.data!;
                } else if (snapshot.hasError) {
                  return const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  );
                } else {
                  return const Center(child: CircularProgressIndicator());
                }
              },
            ),

            // Overlay with metadata
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${image.settings.exposureTime.toStringAsFixed(1)}s ${image.settings.frameType.displayName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (image.stats?.hfr != null)
                      Text(
                        'HFR: ${image.stats!.hfr!.toStringAsFixed(2)}" | ${image.stats!.starCount ?? 0} stars',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Download status overlay
            if (downloadProgress != null)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(value: downloadProgress),
                      const SizedBox(height: 8),
                      Text(
                        '${(downloadProgress! * 100).toInt()}%',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),

            // Download button
            if (!isDownloaded && downloadProgress == null)
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.download),
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                  onPressed: onDownload,
                ),
              ),

            // Downloaded indicator
            if (isDownloaded)
              const Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<Image> _loadThumbnail(WidgetRef ref) async {
    final backend = ref.read(backendProvider);
    final thumbnailData = await backend.getImageThumbnail(int.parse(image.id));

    return Image.memory(
      thumbnailData,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
  }
}

/// Image detail bottom sheet
class _ImageDetailSheet extends StatelessWidget {
  final CapturedImage image;
  final bool isDownloaded;
  final VoidCallback onDownload;

  const _ImageDetailSheet({
    required this.image,
    required this.isDownloaded,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Image Details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              if (!isDownloaded)
                ElevatedButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              if (isDownloaded)
                const Chip(
                  label: Text('Downloaded'),
                  backgroundColor: Colors.green,
                ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          _DetailRow(label: 'Captured', value: _formatDateTime(image.capturedAt)),
          _DetailRow(label: 'Exposure', value: '${image.settings.exposureTime}s'),
          _DetailRow(label: 'Frame Type', value: image.settings.frameType.displayName),
          _DetailRow(label: 'Binning', value: image.settings.binning),
          if (image.settings.filter != null)
            _DetailRow(label: 'Filter', value: image.settings.filter!),
          if (image.settings.gain > 0)
            _DetailRow(label: 'Gain', value: image.settings.gain.toString()),
          if (image.settings.offset > 0)
            _DetailRow(label: 'Offset', value: image.settings.offset.toString()),
          const SizedBox(height: 8),
          if (image.stats != null) ...[
            const Text('Quality Metrics', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            if (image.stats!.hfr != null)
              _DetailRow(label: 'HFR', value: '${image.stats!.hfr!.toStringAsFixed(2)}"'),
            if (image.stats!.starCount != null)
              _DetailRow(label: 'Stars', value: image.stats!.starCount.toString()),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Detail row widget
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
