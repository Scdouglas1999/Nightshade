// ignore_for_file: invalid_use_of_protected_member
// Content, download, package and annotation section builders of _CatalogSettingsScreenState.
part of '../catalog_settings_screen.dart';

extension _CatalogSettingsViewBuilders on _CatalogSettingsScreenState {
  Widget _buildContent(BuildContext context) {
    final colors = context.nightshadeColors;
    final isRemote = ref.watch(backendProvider) is NetworkBackend;
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
        if (_isDownloading && !_isDeleting) ...[
          _buildDownloadProgress(context),
          const SizedBox(height: 32),
        ],

        // Whose catalogs these are. Reading the local filesystem while driving
        // a rig told the operator a capability was installed on the machine
        // that did not have it.
        if (isRemote) ...[
          _buildRigScopeNotice(context),
          const SizedBox(height: 24),
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
          usedFor:
              'Required for plate solving; draws the star field in the planetarium and finder.',
          // The version the resolver would actually download, not a literal
          // that has to be remembered when the asset rolls. A hardcoded '4.2'
          // here outlived the move to hyg_v44 and made the newest fetchable
          // catalog advertise an update to a version the app cannot get.
          latestVersion: hygStarCatalog.version,
          rigStatus: isRemote ? _rigStatusFor('stars') : null,
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
          usedFor:
              'Powers deep-sky target search, framing, and on-image NGC/IC labels.',
          latestVersion: openNgcCatalog.version,
          rigStatus: isRemote ? _rigStatusFor('dso') : null,
        ),
        const SizedBox(height: 32),

        // Annotation catalog section
        _buildAnnotationCatalogSection(context, isRemote),
        const SizedBox(height: 32),

        // Deep-star tier (downloadable Tycho-2 / Gaia subset).
        const DeepStarCatalogCard(),
        const SizedBox(height: 16),

        // Live MPC / TLE element refresh.
        const ElementRefreshCard(),
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
    final isNetworkDownload =
        CatalogManager.instance.activeDownloads.isNotEmpty;
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
              Expanded(
                child: Text(
                  '${isNetworkDownload ? 'Downloading' : 'Importing'}: '
                  '$_currentDownload',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Cancellation only applies to a real network download in flight
              // (imports are atomic and finish immediately).
              if (CatalogManager.instance.activeDownloads.isNotEmpty)
                NightshadeButton(
                  onPressed: _cancelRequested ? null : _requestCancelDownload,
                  icon: NightshadeIcons.close,
                  label: _cancelRequested ? 'Cancelling…' : 'Cancel',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
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
          // There is ONE dataset. The three-tier selector that stood here —
          // Essential / Standard / Complete, each with its own size, star count
          // and "Stars: mag <= x.x" — downloaded the same two files whichever
          // was chosen, so two installs into an empty catalog directory
          // produced byte-identical files the card then described with
          // different depths. Say what arrives, once.
          Text(
            'One download installs both catalogs:',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize13,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'HYG Star Database - '
            '~${formatCatalogCount(kInstalledStarApproxCount)} stars, '
            'complete to mag ${kHygFaintFloorMag.toStringAsFixed(1)}',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'OpenNGC - '
            '~${formatCatalogCount(kInstalledDsoApproxCount)} deep-sky objects '
            '(NGC / IC)',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'About $kInstalledCatalogApproxSizeMB MB on disk.',
            style: TextStyle(
              color: colors.textSecondary.withValues(alpha: 0.7),
              fontSize: NightshadeTypography.fontSize11,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: NightshadeButton(
              label: _isDeleting
                  ? 'Deleting catalogs…'
                  : _isDownloading
                      ? 'Downloading...'
                      : 'Download Catalogs',
              icon: NightshadeIcons.download,
              variant: ButtonVariant.primary,
              onPressed: _isDownloading ? null : _downloadCatalogs,
            ),
          ),
        ],
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
                      isLoading:
                          _deleteTarget == _CatalogDeleteTarget.starAndDso,
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
                      isLoading:
                          _deleteTarget == _CatalogDeleteTarget.starAndDso,
                    ),
                ],
              ),
      ],
    );
  }

  Widget _buildAnnotationCatalogSection(BuildContext context, bool isRemote) {
    final colors = context.nightshadeColors;
    final isInstalled = _annotationStatus?.isInstalled ?? false;
    final rigStatus = isRemote ? _rigStatusFor('annotation') : null;

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
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline8),
                ),
                child:
                    Icon(NightshadeIcons.tag, color: colors.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'GLADE+ Galaxy Catalog',
                          style: NightshadeTypography.h4
                              .copyWith(color: colors.textPrimary),
                        ),
                        if (isInstalled)
                          _buildBadge(
                            context: context,
                            label: rigStatus == null
                                ? 'Installed'
                                : 'On this device',
                            color: colors.success,
                          ),
                        if (rigStatus != null)
                          _buildBadge(
                            context: context,
                            label:
                                _CatalogCardBuilders._rigHasCatalog(rigStatus)
                                    ? 'On the rig'
                                    : 'Not on the rig',
                            color:
                                _CatalogCardBuilders._rigHasCatalog(rigStatus)
                                    ? colors.success
                                    : colors.warning,
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
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(NightshadeIcons.info,
                  size: 14, color: colors.textSecondary.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Labels faint galaxies on solved images. Optional — only needed '
                  'for deep-field annotation, not for capture or plate solving.',
                  style: TextStyle(
                    color: colors.textSecondary.withValues(alpha: 0.9),
                    fontSize: NightshadeTypography.fontSize12,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildStatusChip(
                  context: context,
                  label: 'Objects',
                  value: _formatCount(_annotationStatus!.objectCount),
                ),
                _buildStatusChip(
                  context: context,
                  label: 'Size',
                  value: _formatBytes(_annotationStatus!.fileSizeBytes),
                ),
                // No "Package" chip here either — see the note on the shared
                // installed-catalog card in card_builders.dart. The download
                // tier was a placebo and has been retired; printing the grade
                // off the legacy sidecar labels the user's install with
                // something they can no longer choose and that never described
                // the bytes on disk.
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
                isLoading: _deleteTarget == _CatalogDeleteTarget.annotation,
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
                      Flexible(
                        child: Text(
                          package.displayName,
                          style: NightshadeTypography.h5
                              .copyWith(color: colors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                          borderRadius: BorderRadius.circular(
                              NightshadeTokens.radiusInline4),
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
}
