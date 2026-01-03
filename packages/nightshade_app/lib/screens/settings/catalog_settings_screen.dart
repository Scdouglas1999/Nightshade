import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:file_selector/file_selector.dart';

/// Screen for managing astronomical catalog downloads and settings
class CatalogSettingsScreen extends ConsumerStatefulWidget {
  const CatalogSettingsScreen({super.key});

  @override
  ConsumerState<CatalogSettingsScreen> createState() => _CatalogSettingsScreenState();
}

class _CatalogSettingsScreenState extends ConsumerState<CatalogSettingsScreen> {
  CatalogStatus? _starStatus;
  CatalogStatus? _dsoStatus;
  CatalogStatus? _annotationStatus;
  bool _isLoading = true;
  bool _isDownloading = false;
  String _downloadStatus = '';
  double _downloadProgress = 0;
  String _currentDownload = '';
  CatalogPackage _selectedPackage = CatalogPackage.standard;
  AnnotationPackage _selectedAnnotationPackage = AnnotationPackage.standard;

  @override
  void initState() {
    super.initState();
    _loadCatalogStatus();
  }

  Future<void> _loadCatalogStatus() async {
    setState(() => _isLoading = true);

    try {
      final starStatus = await CatalogManager.instance.getStarCatalogStatus();
      final dsoStatus = await CatalogManager.instance.getDsoCatalogStatus();
      final annotationStatus = await CatalogManager.instance.getAnnotationCatalogStatus();

      if (mounted) {
        setState(() {
          _starStatus = starStatus;
          _dsoStatus = dsoStatus;
          _annotationStatus = annotationStatus;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showError('Failed to check catalog status: $e');
      }
    }
  }

  Future<void> _downloadCatalogs() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadStatus = 'Preparing download...';
    });

    try {
      // Download star catalog
      setState(() {
        _currentDownload = 'HYG Star Database';
        _downloadStatus = 'Downloading star catalog...';
      });
      
      final starSuccess = await CatalogManager.instance.downloadStarCatalog(
        package: _selectedPackage,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress.progress * 0.5; // First half
              _downloadStatus = progress.error ?? 
                'Downloading stars: ${(progress.progress * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );

      if (!starSuccess) {
        throw Exception('Star catalog download failed');
      }

      // Download DSO catalog
      setState(() {
        _currentDownload = 'OpenNGC';
        _downloadStatus = 'Downloading DSO catalog...';
      });
      
      final dsoSuccess = await CatalogManager.instance.downloadDsoCatalog(
        package: _selectedPackage,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = 0.5 + (progress.progress * 0.5); // Second half
              _downloadStatus = progress.error ?? 
                'Downloading DSOs: ${(progress.progress * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );

      if (!dsoSuccess) {
        throw Exception('DSO catalog download failed');
      }

      setState(() {
        _downloadStatus = 'Download complete!';
        _downloadProgress = 1.0;
      });

      // Reload status
      await _loadCatalogStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Catalogs downloaded successfully!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      _showError('Download failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _importCatalog(String type) async {
    const csvGroup = XTypeGroup(
      label: 'CSV files',
      extensions: ['csv'],
    );
    
    final result = await openFile(
      acceptedTypeGroups: [csvGroup],
      confirmButtonText: 'Select',
    );

    if (result != null) {
      setState(() {
        _isDownloading = true;
        _downloadStatus = 'Importing catalog...';
      });

      try {
        final success = await CatalogManager.instance.importCatalog(
          sourcePath: result.path,
          type: type,
        );

        if (success) {
          await _loadCatalogStatus();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Catalog imported successfully!'),
                backgroundColor: Colors.green.shade700,
              ),
            );
          }
        } else {
          _showError('Failed to import catalog');
        }
      } catch (e) {
        _showError('Import failed: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isDownloading = false;
          });
        }
      }
    }
  }

  Future<void> _deleteCatalogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Catalogs'),
        content: const Text(
          'Are you sure you want to delete all downloaded catalogs? '
          'You will need to download them again to use the planetarium features.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CatalogManager.instance.deleteCatalogs();
      await _loadCatalogStatus();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Catalogs deleted')),
        );
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Catalog Settings'),
        backgroundColor: colors.surface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Text(
                    'Astronomical Catalogs',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Download star and deep sky object catalogs to enable full planetarium functionality.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Download progress
                  if (_isDownloading) ...[
                    _buildDownloadProgress(colors),
                    const SizedBox(height: 32),
                  ],

                  // Star catalog card
                  _buildCatalogCard(
                    colors: colors,
                    title: 'HYG Star Database',
                    description: 'Combined Hipparcos, Yale, and Gliese star catalogs with ~120,000 stars',
                    sourceUrl: 'github.com/astronexus/HYG-Database',
                    status: _starStatus,
                    type: 'stars',
                    icon: Icons.star,
                  ),
                  const SizedBox(height: 16),

                  // DSO catalog card
                  _buildCatalogCard(
                    colors: colors,
                    title: 'OpenNGC',
                    description: 'Open source NGC/IC deep sky catalog with ~13,000 objects',
                    sourceUrl: 'github.com/mattiaverga/OpenNGC',
                    status: _dsoStatus,
                    type: 'dso',
                    icon: Icons.blur_circular,
                  ),
                  const SizedBox(height: 32),

                  // Annotation catalog section
                  _buildAnnotationCatalogSection(colors),
                  const SizedBox(height: 32),

                  // Download section
                  _buildDownloadSection(colors),
                  const SizedBox(height: 32),

                  // Actions
                  _buildActionsSection(colors),
                ],
              ),
            ),
    );
  }

  Widget _buildDownloadProgress(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(colors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Downloading: $_currentDownload',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _downloadProgress,
              backgroundColor: colors.border,
              valueColor: AlwaysStoppedAnimation(colors.primary),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _downloadStatus,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogCard({
    required NightshadeColors colors,
    required String title,
    required String description,
    required String sourceUrl,
    required CatalogStatus? status,
    required String type,
    required IconData icon,
  }) {
    final isInstalled = status?.isInstalled ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isInstalled
              ? Colors.green.withValues(alpha: 0.3)
              : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: colors.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isInstalled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Installed',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.folder_open, color: colors.textSecondary),
                onPressed: _isDownloading ? null : () => _importCatalog(type),
                tooltip: 'Import from file',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Source: $sourceUrl',
            style: TextStyle(
              color: colors.textSecondary.withValues(alpha: 0.7),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          if (isInstalled && status != null) ...[
            const SizedBox(height: 12),
            Divider(color: colors.border),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatusChip(
                  colors: colors,
                  label: 'Objects',
                  value: status.objectCount?.toString() ?? 'Unknown',
                ),
                const SizedBox(width: 16),
                _buildStatusChip(
                  colors: colors,
                  label: 'Package',
                  value: status.installedPackage?.displayName ?? 'Custom',
                ),
                const SizedBox(width: 16),
                if (status.installedDate != null)
                  _buildStatusChip(
                    colors: colors,
                    label: 'Installed',
                    value: _formatDate(status.installedDate!),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required NightshadeColors colors,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadSection(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Download Catalogs',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Select a package size based on your needs:',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          ...CatalogPackage.values.map((package) => _buildPackageOption(
            colors: colors,
            package: package,
          )),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isDownloading ? null : _downloadCatalogs,
              icon: const Icon(Icons.download),
              label: Text(_isDownloading ? 'Downloading...' : 'Download Selected Package'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageOption({
    required NightshadeColors colors,
    required CatalogPackage package,
  }) {
    final isSelected = _selectedPackage == package;

    return GestureDetector(
      onTap: _isDownloading ? null : () {
        setState(() => _selectedPackage = package);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.border.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: 16),
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '~${package.approximateSizeMB} MB',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    package.description,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stars: mag ≤ ${package.starMagnitudeLimit.toStringAsFixed(1)} • '
                    'DSOs: mag ≤ ${package.dsoMagnitudeLimit.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: colors.textSecondary.withValues(alpha: 0.7),
                      fontSize: 11,
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

  Widget _buildActionsSection(NightshadeColors colors) {
    final hasInstalledCatalogs = (_starStatus?.isInstalled ?? false) ||
                                  (_dsoStatus?.isInstalled ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Actions',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _isDownloading ? null : _loadCatalogStatus,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Status'),
            ),
            const SizedBox(width: 12),
            if (hasInstalledCatalogs)
              OutlinedButton.icon(
                onPressed: _isDownloading ? null : _deleteCatalogs,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('Delete Catalogs'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnnotationCatalogSection(NightshadeColors colors) {
    final isInstalled = _annotationStatus?.isInstalled ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isInstalled
              ? Colors.green.withValues(alpha: 0.3)
              : colors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.label_outline, color: colors.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'GLADE+ Galaxy Catalog',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isInstalled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Installed',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Galaxy List for the Advanced Detector Era - up to 22.5M galaxies for deep image annotation',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Source: glade.elte.hu via vizier.cds.unistra.fr',
            style: TextStyle(
              color: colors.textSecondary.withValues(alpha: 0.7),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          if (isInstalled && _annotationStatus != null) ...[
            const SizedBox(height: 12),
            Divider(color: colors.border),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatusChip(
                  colors: colors,
                  label: 'Objects',
                  value: _annotationStatus!.objectCount?.toString() ?? 'Unknown',
                ),
                const SizedBox(width: 16),
                _buildStatusChip(
                  colors: colors,
                  label: 'Package',
                  value: _annotationStatus!.installedPackage?.displayName ?? 'Custom',
                ),
                const SizedBox(width: 16),
                if (_annotationStatus!.installedDate != null)
                  _buildStatusChip(
                    colors: colors,
                    label: 'Installed',
                    value: _formatDate(_annotationStatus!.installedDate!),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          if (!isInstalled) ...[
            // Tier selection for annotation catalog
            Text(
              'Select catalog tier:',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            ...AnnotationPackage.values.map((package) => _buildAnnotationPackageOption(
              colors: colors,
              package: package,
            )),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isDownloading ? null : _downloadAnnotationCatalog,
                icon: const Icon(Icons.download, size: 18),
                label: Text('Download ${_selectedAnnotationPackage.displayName} (~${_selectedAnnotationPackage.approximateSizeMB} MB)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Optional manual import
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isDownloading ? null : _importAnnotationCatalog,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Or Import from File (CSV)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isDownloading ? null : _deleteAnnotationCatalog,
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                label: const Text('Delete Annotation Catalog'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnnotationPackageOption({
    required NightshadeColors colors,
    required AnnotationPackage package,
  }) {
    final isSelected = _selectedAnnotationPackage == package;

    return GestureDetector(
      onTap: _isDownloading ? null : () {
        setState(() => _selectedAnnotationPackage = package);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.border.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
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
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          package == AnnotationPackage.complete
                              ? '~${(package.approximateSizeMB / 1000).toStringAsFixed(1)} GB'
                              : '~${package.approximateSizeMB} MB',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    package.description,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
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

  Future<void> _downloadAnnotationCatalog() async {
    setState(() {
      _isDownloading = true;
      _currentDownload = 'GLADE+ Galaxy Catalog';
      _downloadStatus = 'Downloading annotation catalog...';
      _downloadProgress = 0;
    });

    try {
      final success = await CatalogManager.instance.downloadAnnotationCatalog(
        package: _selectedAnnotationPackage,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress.progress;
              _downloadStatus = progress.error ??
                  'Downloading: ${(progress.bytesReceived / 1024 / 1024).toStringAsFixed(1)} MB';
            });
          }
        },
      );

      if (!success) {
        throw Exception('Annotation catalog download failed');
      }

      await _loadCatalogStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('GLADE+ catalog downloaded successfully!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      _showError('Download failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _importAnnotationCatalog() async {
    const csvGroup = XTypeGroup(
      label: 'CSV files',
      extensions: ['csv'],
    );

    final result = await openFile(
      acceptedTypeGroups: [csvGroup],
      confirmButtonText: 'Import',
    );

    if (result != null) {
      setState(() {
        _isDownloading = true;
        _downloadStatus = 'Importing annotation catalog...';
      });

      try {
        final success = await CatalogManager.instance.importAnnotationCatalog(
          sourcePath: result.path,
          package: AnnotationPackage.standard, // Default package for manual imports
        );

        if (success) {
          await _loadCatalogStatus();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('GLADE+ catalog imported successfully!'),
                backgroundColor: Colors.green.shade700,
              ),
            );
          }
        } else {
          _showError('Failed to import annotation catalog');
        }
      } catch (e) {
        _showError('Import failed: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isDownloading = false;
          });
        }
      }
    }
  }

  Future<void> _deleteAnnotationCatalog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Annotation Catalog'),
        content: const Text(
          'Are you sure you want to delete the annotation catalog? '
          'You will need to download it again to use image annotation features.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CatalogManager.instance.deleteAnnotationCatalog();
      await _loadCatalogStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Annotation catalog deleted')),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

