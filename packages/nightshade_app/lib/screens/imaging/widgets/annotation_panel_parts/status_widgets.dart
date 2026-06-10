part of '../annotation_panel.dart';

class AnnotationCatalogBanner extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onDismiss;
  final VoidCallback onSetup;

  const AnnotationCatalogBanner({
    super.key,
    required this.colors,
    required this.onDismiss,
    required this.onSetup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: NightshadeTokens.opacityMedium),
        border: Border(
          bottom: BorderSide(
            color: colors.primary
                .withValues(alpha: NightshadeTokens.opacityStrong),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(NightshadeIcons.info, size: 16, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Annotations are enabled but no catalog is installed. Download the annotation catalog to identify objects in your images.',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: NightshadeTypography.fontSize12,
              ),
            ),
          ),
          const SizedBox(width: 16),
          NightshadeButton(
            onPressed: onSetup,
            label: 'Setup',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          IconButton(
            icon:
                Icon(NightshadeIcons.close, size: 16, color: colors.textMuted),
            onPressed: onDismiss,
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

/// Status indicator for the live annotation pipeline
class AnnotationStatusIndicator extends ConsumerWidget {
  final NightshadeColors colors;

  const AnnotationStatusIndicator({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotationState = ref.watch(annotationStateProvider);
    final annotationSettings =
        ref.watch(annotationSettingsProvider).valueOrNull;
    final secondaryMessage =
        annotationState.errorDetails ?? _getActionHint(annotationState.status);

    // Don't show anything if annotations are disabled
    if (annotationSettings != null && !annotationSettings.enabled) {
      return const SizedBox.shrink();
    }

    // Don't show idle state (reduces visual clutter)
    if (annotationState.status == AnnotationStatus.idle) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _getBackgroundColor(annotationState.status),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          border: Border.all(
            color: _getBorderColor(annotationState.status),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _getStatusIcon(annotationState.status),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  annotationState.message ??
                      _getStatusText(annotationState.status),
                  style: TextStyle(
                    color: _getTextColor(annotationState.status),
                    fontSize: NightshadeTypography.fontSize11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (secondaryMessage != null)
                  Text(
                    secondaryMessage,
                    style: TextStyle(
                      color: _getTextColor(annotationState.status)
                          .withValues(alpha: 0.7),
                      fontSize: NightshadeTypography.fontSize10,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getBackgroundColor(AnnotationStatus status) {
    return AnnotationStatusColors.background(status, colors);
  }

  Color _getBorderColor(AnnotationStatus status) {
    return AnnotationStatusColors.border(status, colors);
  }

  Color _getTextColor(AnnotationStatus status) {
    return AnnotationStatusColors.text(status, colors);
  }

  Widget _getStatusIcon(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.checkingCatalogs:
      case AnnotationStatus.plateSolving:
      case AnnotationStatus.searchingCatalogs:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(_getTextColor(status)),
          ),
        );
      case AnnotationStatus.complete:
        return Icon(NightshadeIcons.success,
            size: 14, color: _getTextColor(status));
      case AnnotationStatus.error:
      case AnnotationStatus.plateSolveFailed:
        return Icon(LucideIcons.alertCircle,
            size: 14, color: _getTextColor(status));
      case AnnotationStatus.catalogsNotInstalled:
        return Icon(NightshadeIcons.warning,
            size: 14, color: _getTextColor(status));
      case AnnotationStatus.idle:
        return const SizedBox.shrink();
    }
  }

  String _getStatusText(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.checkingCatalogs:
        return 'Checking catalogs...';
      case AnnotationStatus.plateSolving:
        return 'Plate solving...';
      case AnnotationStatus.searchingCatalogs:
        return 'Searching catalogs...';
      case AnnotationStatus.complete:
        return 'Annotation complete';
      case AnnotationStatus.error:
        return 'Annotation error';
      case AnnotationStatus.plateSolveFailed:
        return 'Plate solve failed';
      case AnnotationStatus.catalogsNotInstalled:
        return 'No catalogs installed';
      case AnnotationStatus.idle:
        return '';
    }
  }

  String? _getActionHint(AnnotationStatus status) {
    switch (status) {
      case AnnotationStatus.catalogsNotInstalled:
        return 'Install catalogs in Settings > Catalogs';
      case AnnotationStatus.plateSolveFailed:
        return 'Check solver config, focus, and star signal';
      case AnnotationStatus.error:
        return 'Capture a fresh frame to retry';
      case AnnotationStatus.checkingCatalogs:
      case AnnotationStatus.plateSolving:
      case AnnotationStatus.searchingCatalogs:
      case AnnotationStatus.complete:
      case AnnotationStatus.idle:
        return null;
    }
  }
}

/// Sidebar panel showing list of detected celestial objects
