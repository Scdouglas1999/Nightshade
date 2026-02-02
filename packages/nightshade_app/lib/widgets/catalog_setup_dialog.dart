import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Dialog shown when catalogs need to be downloaded
class CatalogSetupDialog extends ConsumerStatefulWidget {
  final VoidCallback? onSkip;
  final VoidCallback? onComplete;

  const CatalogSetupDialog({
    super.key,
    this.onSkip,
    this.onComplete,
  });

  /// Show the catalog setup dialog
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CatalogSetupDialog(
        onSkip: () => Navigator.of(context).pop(false),
        onComplete: () => Navigator.of(context).pop(true),
      ),
    );
  }

  @override
  ConsumerState<CatalogSetupDialog> createState() => _CatalogSetupDialogState();
}

class _CatalogSetupDialogState extends ConsumerState<CatalogSetupDialog> {
  CatalogPackage _selectedPackage = CatalogPackage.standard;
  bool _isDownloading = false;
  double _progress = 0;
  String _statusMessage = '';
  String? _errorMessage;

  Future<void> _downloadCatalogs() async {
    setState(() {
      _isDownloading = true;
      _progress = 0;
      _statusMessage = 'Starting download...';
      _errorMessage = null;
    });

    try {
      // Download star catalog
      setState(() => _statusMessage = 'Downloading HYG Star Database...');
      
      final starSuccess = await CatalogManager.instance.downloadStarCatalog(
        package: _selectedPackage,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _progress = progress.progress * 0.5;
              if (progress.error != null) {
                _errorMessage = progress.error;
              }
            });
          }
        },
      );

      if (!starSuccess) {
        throw Exception('Star catalog download failed');
      }

      // Download DSO catalog
      setState(() => _statusMessage = 'Downloading OpenNGC Catalog...');
      
      final dsoSuccess = await CatalogManager.instance.downloadDsoCatalog(
        package: _selectedPackage,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _progress = 0.5 + (progress.progress * 0.5);
              if (progress.error != null) {
                _errorMessage = progress.error;
              }
            });
          }
        },
      );

      if (!dsoSuccess) {
        throw Exception('DSO catalog download failed');
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
      child: ConstrainedBox(
        constraints: Responsive.dialogConstraints(
          context,
          preferredWidth: 500,
          minWidth: 350,
        ),
        child: Padding(
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
                    Icons.download_rounded,
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
                        'Catalog Setup',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Download star and DSO catalogs',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ],
                  ),
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
                    'The planetarium requires astronomical catalogs to display stars and deep sky objects.',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  _buildCatalogInfo(colors, 'HYG Star Database', '~120,000 stars'),
                  const SizedBox(height: 8),
                  _buildCatalogInfo(colors, 'OpenNGC', '~13,000 DSOs (NGC/IC)'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Package selection (only when not downloading)
            if (!_isDownloading) ...[
              Text(
                'Select package size:',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...CatalogPackage.values.map((package) => 
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
              Text(
                '${(_progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
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
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
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
                  TextButton(
                    onPressed: widget.onSkip,
                    child: Text(
                      'Skip for now',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isDownloading ? null : _downloadCatalogs,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: Text(_isDownloading ? 'Downloading...' : 'Download Now'),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCatalogInfo(NightshadeColors colors, String name, String detail) {
    return Row(
      children: [
        Icon(Icons.check_circle, color: colors.primary, size: 16),
        const SizedBox(width: 8),
        Text(
          name,
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          detail,
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildPackageOption(NightshadeColors colors, CatalogPackage package) {
    final isSelected = _selectedPackage == package;

    return GestureDetector(
      onTap: () => setState(() => _selectedPackage = package),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? colors.primary : colors.textSecondary,
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
                        package.displayName,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '~${package.approximateSizeMB} MB',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    package.description,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
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

/// Banner to show when catalogs are not installed
class CatalogRequiredBanner extends StatelessWidget {
  final VoidCallback onSetup;

  const CatalogRequiredBanner({
    super.key,
    required this.onSetup,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: colors.warning),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Catalogs Not Installed',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Download star and DSO catalogs to enable full planetarium functionality.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: onSetup,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Setup'),
          ),
        ],
      ),
    );
  }
}

