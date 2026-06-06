import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:file_selector/file_selector.dart';

import '../../utils/confirm_dialog.dart';
import '../../utils/snackbar_helper.dart';

part 'catalog_settings_screen/card_builders.dart';

/// Screen for managing astronomical catalog downloads and settings
class CatalogSettingsScreen extends ConsumerStatefulWidget {
  final bool isMobile;

  const CatalogSettingsScreen({super.key, this.isMobile = false});

  @override
  ConsumerState<CatalogSettingsScreen> createState() =>
      _CatalogSettingsScreenState();
}

class _CatalogSettingsScreenState extends ConsumerState<CatalogSettingsScreen>
    with _CatalogCardBuilders {
  CatalogStatus? _starStatus;
  CatalogStatus? _dsoStatus;
  CatalogStatus? _annotationStatus;
  bool _isLoading = true;
  @override
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
      final annotationStatus =
          await CatalogManager.instance.getAnnotationCatalogStatus();

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
              _downloadProgress =
                  0.5 + (progress.progress * 0.5); // Second half
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
        context.showSuccessSnackBar('Catalogs downloaded successfully!');
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

  @override
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
            context.showSuccessSnackBar('Catalog imported successfully!');
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
    final confirm = await ConfirmDialog.show(
      context: context,
      title: 'Delete Catalogs',
      message: 'Are you sure you want to delete all downloaded catalogs? '
          'You will need to download them again to use the planetarium features.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );

    if (confirm) {
      await CatalogManager.instance.deleteCatalogs();
      await _loadCatalogStatus();

      if (mounted) {
        context.showInfoSnackBar('Catalogs deleted');
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      context.showErrorSnackBar(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final padding = widget.isMobile ? 16.0 : 24.0;

    // On mobile, skip Scaffold since parent provides structure
    if (widget.isMobile) {
      return _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: _buildContent(context),
            );
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Catalog Settings'),
        backgroundColor: colors.surface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: _buildContent(context),
            ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final colors = context.nightshadeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header - hide on mobile since parent shows it
        if (!widget.isMobile) ...[
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
        ],

        // Download progress
        if (_isDownloading) ...[
          _buildDownloadProgress(context),
          const SizedBox(height: 32),
        ],

        // Star catalog card
        _buildCatalogCard(
          context: context,
          title: 'HYG Star Database',
          description:
              'Combined Hipparcos, Yale, and Gliese star catalogs with ~120,000 stars',
          sourceUrl: 'github.com/astronexus/HYG-Database',
          status: _starStatus,
          type: 'stars',
          icon: NightshadeIcons.star,
        ),
        const SizedBox(height: 16),

        // DSO catalog card
        _buildCatalogCard(
          context: context,
          title: 'OpenNGC',
          description:
              'Open source NGC/IC deep sky catalog with ~13,000 objects',
          sourceUrl: 'github.com/mattiaverga/OpenNGC',
          status: _dsoStatus,
          type: 'dso',
          // KEEP MATERIAL: no clean Lucide "out-of-focus disc" glyph
          // (icon-migration-map.md flagged exception).
          icon: Icons.blur_circular,
        ),
        const SizedBox(height: 32),

        // Annotation catalog section
        _buildAnnotationCatalogSection(context),
        const SizedBox(height: 32),

        // Download section
        _buildDownloadSection(context),
        const SizedBox(height: 32),

        // Actions
        _buildActionsSection(context),
      ],
    );
  }

  Widget _buildDownloadProgress(BuildContext context) {
    final colors = context.nightshadeColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
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
              fontSize: NightshadeTypography.fontSize12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadSection(BuildContext context) {
    final colors = context.nightshadeColors;
    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusInline8,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Download Catalogs',
            style: NightshadeTypography.h4.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 16),
          Text(
            'Select a package size based on your needs:',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize13,
            ),
          ),
          const SizedBox(height: 16),
          ...CatalogPackage.values.map((package) => _buildPackageOption(
                context: context,
                package: package,
              )),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: NightshadeButton(
              label: _isDownloading
                  ? 'Downloading...'
                  : 'Download Selected Package',
              icon: NightshadeIcons.download,
              variant: ButtonVariant.primary,
              onPressed: _isDownloading ? null : _downloadCatalogs,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageOption({
    required BuildContext context,
    required CatalogPackage package,
  }) {
    final colors = context.nightshadeColors;
    final isSelected = _selectedPackage == package;

    return GestureDetector(
      onTap: _isDownloading
          ? null
          : () {
              setState(() => _selectedPackage = package);
            },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.border.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? NightshadeIcons.success : NightshadeIcons.circle,
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
                          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                        ),
                        child: Text(
                          '~${package.approximateSizeMB} MB',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: NightshadeTypography.fontSize11,
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
                      fontSize: NightshadeTypography.fontSize12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stars: mag ≤ ${package.starMagnitudeLimit.toStringAsFixed(1)} • '
                    'DSOs: mag ≤ ${package.dsoMagnitudeLimit.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: colors.textSecondary.withValues(alpha: 0.7),
                      fontSize: NightshadeTypography.fontSize11,
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

  Widget _buildActionsSection(BuildContext context) {
    final colors = context.nightshadeColors;
    final hasInstalledCatalogs = (_starStatus?.isInstalled ?? false) ||
        (_dsoStatus?.isInstalled ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Actions',
          style: NightshadeTypography.h4.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 16),
        widget.isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NightshadeButton(
                    label: 'Refresh Status',
                    icon: NightshadeIcons.refresh,
                    variant: ButtonVariant.outline,
                    onPressed: _isDownloading ? null : _loadCatalogStatus,
                  ),
                  if (hasInstalledCatalogs) ...[
                    const SizedBox(height: 8),
                    NightshadeButton(
                      label: 'Delete Catalogs',
                      icon: NightshadeIcons.delete,
                      variant: ButtonVariant.destructive,
                      onPressed: _isDownloading ? null : _deleteCatalogs,
                    ),
                  ],
                ],
              )
            : Row(
                children: [
                  NightshadeButton(
                    label: 'Refresh Status',
                    icon: NightshadeIcons.refresh,
                    variant: ButtonVariant.outline,
                    onPressed: _isDownloading ? null : _loadCatalogStatus,
                  ),
                  const SizedBox(width: 12),
                  if (hasInstalledCatalogs)
                    NightshadeButton(
                      label: 'Delete Catalogs',
                      icon: NightshadeIcons.delete,
                      variant: ButtonVariant.destructive,
                      onPressed: _isDownloading ? null : _deleteCatalogs,
                    ),
                ],
              ),
      ],
    );
  }

  Widget _buildAnnotationCatalogSection(BuildContext context) {
    final colors = context.nightshadeColors;
    final isInstalled = _annotationStatus?.isInstalled ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(
          color: isInstalled
              ? colors.success.withValues(alpha: 0.3)
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
                decoration: NightshadeDecorations.iconChip(
                  colors.primary,
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
                ),
                child:
                    Icon(NightshadeIcons.tag, color: colors.primary, size: 24),
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
                          style: NightshadeTypography.h4.copyWith(color: colors.textPrimary),
                        ),
                        const SizedBox(width: 8),
                        if (isInstalled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.success.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                            ),
                            child: Text(
                              'Installed',
                              style: NightshadeTypography.labelQuiet.copyWith(color: colors.success),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Galaxy List for the Advanced Detector Era - up to 22.5M galaxies for deep image annotation',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: NightshadeTypography.fontSize13,
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
              fontSize: NightshadeTypography.fontSize11,
              fontFamily: 'monospace',
            ),
          ),
          if (isInstalled && _annotationStatus != null) ...[
            const SizedBox(height: 12),
            Divider(color: colors.border),
            const SizedBox(height: 12),
            widget.isMobile
                ? Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _buildStatusChip(
                        context: context,
                        label: 'Objects',
                        value: _annotationStatus!.objectCount?.toString() ??
                            'Unknown',
                      ),
                      _buildStatusChip(
                        context: context,
                        label: 'Package',
                        value:
                            _annotationStatus!.installedPackage?.displayName ??
                                'Custom',
                      ),
                      if (_annotationStatus!.installedDate != null)
                        _buildStatusChip(
                          context: context,
                          label: 'Installed',
                          value: _formatDate(_annotationStatus!.installedDate!),
                        ),
                    ],
                  )
                : Row(
                    children: [
                      _buildStatusChip(
                        context: context,
                        label: 'Objects',
                        value: _annotationStatus!.objectCount?.toString() ??
                            'Unknown',
                      ),
                      const SizedBox(width: 16),
                      _buildStatusChip(
                        context: context,
                        label: 'Package',
                        value:
                            _annotationStatus!.installedPackage?.displayName ??
                                'Custom',
                      ),
                      const SizedBox(width: 16),
                      if (_annotationStatus!.installedDate != null)
                        _buildStatusChip(
                          context: context,
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
                fontSize: NightshadeTypography.fontSize13,
              ),
            ),
            const SizedBox(height: 12),
            ...AnnotationPackage.values
                .map((package) => _buildAnnotationPackageOption(
                      context: context,
                      package: package,
                    )),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                label:
                    'Download ${_selectedAnnotationPackage.displayName} (~${_selectedAnnotationPackage.approximateSizeMB} MB)',
                icon: NightshadeIcons.download,
                variant: ButtonVariant.primary,
                onPressed: _isDownloading ? null : _downloadAnnotationCatalog,
              ),
            ),
            const SizedBox(height: 12),
            // Optional manual import
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                label: 'Or Import from File (CSV)',
                icon: NightshadeIcons.folderOpen,
                variant: ButtonVariant.outline,
                onPressed: _isDownloading ? null : _importAnnotationCatalog,
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                label: 'Delete Annotation Catalog',
                icon: NightshadeIcons.delete,
                variant: ButtonVariant.destructive,
                onPressed: _isDownloading ? null : _deleteAnnotationCatalog,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnnotationPackageOption({
    required BuildContext context,
    required AnnotationPackage package,
  }) {
    final colors = context.nightshadeColors;
    final isSelected = _selectedAnnotationPackage == package;

    return GestureDetector(
      onTap: _isDownloading
          ? null
          : () {
              setState(() => _selectedAnnotationPackage = package);
            },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.border.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? NightshadeIcons.success : NightshadeIcons.circle,
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
                        style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                        ),
                        child: Text(
                          package == AnnotationPackage.complete
                              ? '~${(package.approximateSizeMB / 1000).toStringAsFixed(1)} GB'
                              : '~${package.approximateSizeMB} MB',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: NightshadeTypography.fontSize10,
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
                      fontSize: NightshadeTypography.fontSize11,
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
        context.showSuccessSnackBar('GLADE+ catalog downloaded successfully!');
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
          package:
              AnnotationPackage.standard, // Default package for manual imports
        );

        if (success) {
          await _loadCatalogStatus();
          if (mounted) {
            context
                .showSuccessSnackBar('GLADE+ catalog imported successfully!');
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
    final confirm = await ConfirmDialog.show(
      context: context,
      title: 'Delete Annotation Catalog',
      message: 'Are you sure you want to delete the annotation catalog? '
          'You will need to download it again to use image annotation features.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );

    if (confirm) {
      await CatalogManager.instance.deleteAnnotationCatalog();
      await _loadCatalogStatus();

      if (mounted) {
        context.showInfoSnackBar('Annotation catalog deleted');
      }
    }
  }

  @override
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
