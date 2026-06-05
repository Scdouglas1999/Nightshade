// Part of ../catalog_settings_screen.dart -- extracted for maintainability.
//
// Shared installed-catalog card and status-chip presentation helpers.
part of '../catalog_settings_screen.dart';

mixin _CatalogCardBuilders on ConsumerState<CatalogSettingsScreen> {
  bool get _isDownloading;

  Future<void> _importCatalog(String type);

  String _formatDate(DateTime date);

  Widget _buildCatalogCard({
    required BuildContext context,
    required String title,
    required String description,
    required String sourceUrl,
    required CatalogStatus? status,
    required String type,
    required IconData icon,
  }) {
    final colors = context.nightshadeColors;
    final isInstalled = status?.isInstalled ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(
          color: isInstalled
              ? colors.success.withValues(alpha: 0.3)
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
                decoration: NightshadeDecorations.iconChip(
                  colors.primary,
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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
                            fontSize: NightshadeTypography.fontSize16,
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
                              color: colors.success.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                            ),
                            child: Text(
                              'Installed',
                              style: TextStyle(
                                color: colors.success,
                                fontSize: NightshadeTypography.fontSize11,
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
                        fontSize: NightshadeTypography.fontSize13,
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
              fontSize: NightshadeTypography.fontSize11,
              fontFamily: 'monospace',
            ),
          ),
          if (isInstalled && status != null) ...[
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
                        value: status.objectCount?.toString() ?? 'Unknown',
                      ),
                      _buildStatusChip(
                        context: context,
                        label: 'Package',
                        value: status.installedPackage?.displayName ?? 'Custom',
                      ),
                      if (status.installedDate != null)
                        _buildStatusChip(
                          context: context,
                          label: 'Installed',
                          value: _formatDate(status.installedDate!),
                        ),
                    ],
                  )
                : Row(
                    children: [
                      _buildStatusChip(
                        context: context,
                        label: 'Objects',
                        value: status.objectCount?.toString() ?? 'Unknown',
                      ),
                      const SizedBox(width: 16),
                      _buildStatusChip(
                        context: context,
                        label: 'Package',
                        value: status.installedPackage?.displayName ?? 'Custom',
                      ),
                      const SizedBox(width: 16),
                      if (status.installedDate != null)
                        _buildStatusChip(
                          context: context,
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
    required BuildContext context,
    required String label,
    required String value,
  }) {
    final colors = context.nightshadeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: NightshadeTypography.fontSize11,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: NightshadeDecorations.statusChip(
            colors.textPrimary,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            bordered: false,
          ),
          child: Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: NightshadeTypography.fontSize13,
            ),
          ),
        ),
      ],
    );
  }
}
