import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Dialog for downloading annotation catalog (HyperLEDA + enriched OpenNGC)
class AnnotationCatalogDialog extends ConsumerStatefulWidget {
  final VoidCallback? onSkip;
  final VoidCallback? onComplete;

  const AnnotationCatalogDialog({
    super.key,
    this.onSkip,
    this.onComplete,
  });

  /// Show the annotation catalog download dialog
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AnnotationCatalogDialog(
        onSkip: () => Navigator.of(context).pop(false),
        onComplete: () => Navigator.of(context).pop(true),
      ),
    );
  }

  @override
  ConsumerState<AnnotationCatalogDialog> createState() => _AnnotationCatalogDialogState();
}

class _AnnotationCatalogDialogState extends ConsumerState<AnnotationCatalogDialog> {
  AnnotationPackage _selectedPackage = AnnotationPackage.standard;
  bool _isDownloading = false;
  double _progress = 0;
  String _statusMessage = '';
  String? _errorMessage;

  String _getPackageDescription(AnnotationPackage package) {
    switch (package) {
      case AnnotationPackage.essential:
        return 'Basic catalog with common objects. Includes Messier, NGC/IC, and bright galaxies to mag 15. Good for quick identification.';
      case AnnotationPackage.standard:
        return 'Standard catalog with more detail. Extends to mag 18 and includes galaxy morphology data. Recommended for most users.';
      case AnnotationPackage.complete:
        return 'Complete catalog with all available data. Includes faint galaxies to mag 20+, redshift data, and detailed morphology.';
    }
  }

  String _getPackageSizeMB(AnnotationPackage package) {
    switch (package) {
      case AnnotationPackage.essential:
        return '~15';
      case AnnotationPackage.standard:
        return '~50';
      case AnnotationPackage.complete:
        return '~150';
    }
  }

  String _getPackageObjectCount(AnnotationPackage package) {
    switch (package) {
      case AnnotationPackage.essential:
        return '~50,000 objects';
      case AnnotationPackage.standard:
        return '~500,000 objects';
      case AnnotationPackage.complete:
        return '~3,000,000 objects';
    }
  }

  Future<void> _downloadCatalog() async {
    setState(() {
      _isDownloading = true;
      _progress = 0;
      _statusMessage = 'Preparing download...';
      _errorMessage = null;
    });

    try {
      setState(() => _statusMessage = 'Downloading HyperLEDA Galaxy Catalog...');

      final success = await CatalogManager.instance.downloadAnnotationCatalog(
        package: _selectedPackage,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _progress = progress.progress;
              if (progress.error != null) {
                _errorMessage = progress.error;
              }
            });
          }
        },
      );

      if (!success) {
        throw Exception('Annotation catalog download failed');
      }

      setState(() {
        _progress = 1.0;
        _statusMessage = 'Download complete!';
      });

      // Brief pause to show completion
      await Future.delayed(const Duration(milliseconds: 500));

      widget.onComplete?.call();
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _errorMessage = e.toString();
        _statusMessage = 'Download failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 550,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    LucideIcons.tag,
                    color: colors.primary,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Annotation Catalog',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Identify objects in your images',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (!_isDownloading)
                  IconButton(
                    icon: Icon(LucideIcons.x, color: colors.textSecondary),
                    onPressed: widget.onSkip,
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // Description
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Download the annotation catalog to automatically identify objects in your plate-solved images.',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureRow(colors, LucideIcons.search, 'Deep object identification'),
                  const SizedBox(height: 8),
                  _buildFeatureRow(colors, LucideIcons.mousePointerClick, 'Click-to-identify any object'),
                  const SizedBox(height: 8),
                  _buildFeatureRow(colors, LucideIcons.database, 'HyperLEDA galaxy database'),
                  const SizedBox(height: 8),
                  _buildFeatureRow(colors, LucideIcons.sparkles, 'Messier & NGC/IC catalog enrichment'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Package selection (only when not downloading)
            if (!_isDownloading) ...[
              Text(
                'Select catalog depth:',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...AnnotationPackage.values.map((package) =>
                _buildPackageOption(colors, package)),
              const SizedBox(height: 24),
            ],

            // Download progress
            if (_isDownloading) ...[
              Text(
                _statusMessage,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: colors.border,
                  valueColor: AlwaysStoppedAnimation(colors.primary),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(_progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  Text(
                    '${_getPackageSizeMB(_selectedPackage)} MB',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Error message
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.alertCircle, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isDownloading)
                  NightshadeButton(
                    onPressed: widget.onSkip,
                    label: 'Maybe later',
                    variant: ButtonVariant.ghost,
                    size: ButtonSize.small,
                  ),
                const SizedBox(width: 12),
                NightshadeButton(
                  onPressed: _isDownloading ? null : _downloadCatalog,
                  icon: _isDownloading ? LucideIcons.loader2 : LucideIcons.download,
                  label: _isDownloading ? 'Downloading...' : 'Download',
                  isLoading: _isDownloading,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(NightshadeColors colors, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: colors.primary, size: 16),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildPackageOption(NightshadeColors colors, AnnotationPackage package) {
    final isSelected = _selectedPackage == package;
    final description = _getPackageDescription(package);
    final sizeMB = _getPackageSizeMB(package);
    final objectCount = _getPackageObjectCount(package);

    return GestureDetector(
      onTap: () => setState(() => _selectedPackage = package),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSelected ? LucideIcons.checkCircle2 : LucideIcons.circle,
              color: isSelected ? colors.primary : colors.textMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        package.name[0].toUpperCase() + package.name.substring(1),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$sizeMB MB',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          objectCount,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner widget to prompt annotation catalog download
class AnnotationCatalogBanner extends StatelessWidget {
  final VoidCallback onSetup;

  const AnnotationCatalogBanner({
    super.key,
    required this.onSetup,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primary.withValues(alpha: 0.1),
            colors.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.sparkles, color: colors.primary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enable Deep Object Identification',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Download catalog to identify objects in your images',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          NightshadeButton(
            onPressed: onSetup,
            icon: LucideIcons.download,
            label: 'Setup',
          ),
        ],
      ),
    );
  }
}
