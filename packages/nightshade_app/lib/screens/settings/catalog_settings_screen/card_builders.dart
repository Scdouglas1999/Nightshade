// Part of ../catalog_settings_screen.dart -- extracted for maintainability.
//
// Shared installed-catalog card and status-chip presentation helpers.
part of '../catalog_settings_screen.dart';

mixin _CatalogCardBuilders on ConsumerState<CatalogSettingsScreen> {
  bool get _isDownloading;

  Future<void> _importCatalog(String type);

  String _formatDate(DateTime date);

  /// Whether an appliance-reported catalog status counts as usable there.
  static bool _rigHasCatalog(String status) =>
      status == 'installed' || status == 'ok';

  /// [rigStatus] is the connected appliance's status for this catalog, or null
  /// for a local session. When it is set, the install badges name WHICH machine
  /// holds the catalog — an unqualified "Installed" read off this device's own
  /// filesystem is a claim about the wrong machine.
  Widget _buildCatalogCard({
    required BuildContext context,
    required String title,
    required String description,
    required String sourceUrl,
    required CatalogStatus? status,
    required String type,
    required IconData icon,
    required String usedFor,
    String? latestVersion,
    String? rigStatus,
  }) {
    final colors = context.nightshadeColors;
    final isInstalled = status?.isInstalled ?? false;
    final updateAvailable = isInstalled &&
        latestVersion != null &&
        status?.version != null &&
        status!.version != latestVersion;

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
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline8),
                ),
                child: Icon(icon, color: colors.primary, size: 24),
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
                          title,
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
                            label: _rigHasCatalog(rigStatus)
                                ? 'On the rig'
                                : 'Not on the rig',
                            color: _rigHasCatalog(rigStatus)
                                ? colors.success
                                : colors.warning,
                          ),
                        if (updateAvailable)
                          _buildBadge(
                            context: context,
                            label: 'Update available',
                            color: colors.warning,
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
                icon: Icon(NightshadeIcons.folderOpen,
                    color: colors.textSecondary),
                onPressed: _isDownloading ? null : () => _importCatalog(type),
                tooltip: 'Import from file',
              ),
            ],
          ),
          const SizedBox(height: 10),
          // What this catalog powers — helps users decide whether they need it.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(NightshadeIcons.info,
                  size: 14, color: colors.textSecondary.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  usedFor,
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
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildStatusChip(
                  context: context,
                  label: 'Objects',
                  value: _formatCount(status.objectCount),
                ),
                _buildStatusChip(
                  context: context,
                  label: 'Size',
                  value: _formatBytes(status.fileSizeBytes),
                ),
                if (status.version != null)
                  _buildStatusChip(
                    context: context,
                    label: 'Version',
                    value: status.version!,
                  ),
                _buildStatusChip(
                  context: context,
                  label: 'Package',
                  value: status.installedPackage?.displayName ?? 'Custom',
                ),
                if (_magnitudeDepth(type, status.installedPackage) != null)
                  _buildStatusChip(
                    context: context,
                    label: 'Depth',
                    value: _magnitudeDepth(type, status.installedPackage)!,
                  ),
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

  /// Small rounded status/label badge (e.g. "Installed", "Update available").
  Widget _buildBadge({
    required BuildContext context,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
      ),
      child: Text(
        label,
        style: NightshadeTypography.labelQuiet.copyWith(color: color),
      ),
    );
  }

  /// Human-readable magnitude depth for the installed package, or null when it
  /// doesn't apply to this catalog type.
  String? _magnitudeDepth(String type, CatalogPackage? package) {
    if (package == null) return null;
    switch (type) {
      case 'stars':
        return 'mag ≤ ${package.starMagnitudeLimit.toStringAsFixed(1)}';
      case 'dso':
        return 'mag ≤ ${package.dsoMagnitudeLimit.toStringAsFixed(1)}';
      default:
        return null;
    }
  }

  String _formatCount(int? count) {
    if (count == null) return 'Unknown';
    if (count < 1000) return '$count';
    if (count < 1000000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return 'Unknown';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
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
            style:
                NightshadeTypography.label.copyWith(color: colors.textPrimary),
          ),
        ),
      ],
    );
  }
}
