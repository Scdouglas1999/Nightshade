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

  /// True when the "plate solve failed" state is really just "no solver is
  /// installed on this machine".
  ///
  /// Annotations are enabled by default and no plate solver ships with the app,
  /// so a fresh install showed a RED "Plate solve failed" error pinned over the
  /// imaging viewport after every single capture — even a plain manual snapshot
  /// (observed on the desktop build with the simulator camera). Nothing had
  /// failed: an optional external tool simply is not set up, which the
  /// Equipment readiness panel already reports as an advisory. This is the same
  /// distinction the pipeline already draws for `catalogsNotInstalled`, which is
  /// presented as a warning with a "go install it" hint rather than an error.
  static bool _isSolverMissing(AnnotationState state) {
    if (state.status != AnnotationStatus.plateSolveFailed) return false;
    final text =
        '${state.message ?? ''} ${state.errorDetails ?? ''}'.toLowerCase();
    return text.contains('no supported external plate solver') ||
        text.contains('plate solver is configured') ||
        text.contains('astap');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotationState = ref.watch(annotationStateProvider);
    final annotationSettings =
        ref.watch(annotationSettingsProvider).valueOrNull;
    final solverMissing = _isSolverMissing(annotationState);
    // Borrow the "prerequisite not installed" presentation (warning tone, not
    // error) while keeping solver-specific wording below.
    final presentationStatus = solverMissing
        ? AnnotationStatus.catalogsNotInstalled
        : annotationState.status;
    final secondaryMessage = solverMissing
        ? 'Optional: install ASTAP or set its path in Settings to label objects'
        : (annotationState.errorDetails ??
            _getActionHint(annotationState.status));

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
          color: _getBackgroundColor(presentationStatus),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          border: Border.all(
            color: _getBorderColor(presentationStatus),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _getStatusIcon(presentationStatus),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  solverMissing
                      ? 'No plate solver installed'
                      : (annotationState.message ??
                          _getStatusText(annotationState.status)),
                  style: TextStyle(
                    color: _getTextColor(presentationStatus),
                    fontSize: NightshadeTypography.fontSize11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (secondaryMessage != null)
                  Text(
                    secondaryMessage,
                    style: TextStyle(
                      color: _getTextColor(presentationStatus)
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
