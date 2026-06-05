part of '../settings_widgets.dart';

class SettingsPage extends StatelessWidget {
  final String title;

  final String description;

  final List<Widget> children;

  final bool isMobile;

  /// If true, don't show title/description (used when mobile header already shows title)

  final bool hideHeader;

  const SettingsPage({
    super.key,
    required this.title,
    required this.description,
    required this.children,
    this.isMobile = false,
    this.hideHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final padding = isMobile
        ? NightshadeTokens.paddingLg
        : const EdgeInsets.all(NightshadeTokens.space3xl);

    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideHeader) ...[
            Text(
              title,
              style:
                  (isMobile ? NightshadeTypography.h3 : NightshadeTypography.h2)
                      .copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceXs),
            Text(
              description,
              style: (isMobile
                      ? NightshadeTypography.caption
                      : NightshadeTypography.bodySm)
                  .copyWith(color: colors.textSecondary),
            ),
            SizedBox(
                height: isMobile
                    ? NightshadeTokens.spaceXl
                    : NightshadeTokens.space3xl),
          ],
          ...children,
        ],
      ),
    );
  }
}

class SettingsLoadingState extends StatelessWidget {
  final bool isMobile;

  final String message;

  const SettingsLoadingState({
    super.key,
    this.isMobile = false,
    this.message = 'Loading settings...',
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final padding = isMobile
        ? NightshadeTokens.paddingLg
        : const EdgeInsets.all(NightshadeTokens.space3xl);

    return SingleChildScrollView(
      padding: padding,
      child: ShimmerLoading(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 220,
              height: isMobile ? 24 : 28,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: NightshadeTokens.borderRadiusMd,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Container(
              width: 320,
              height: 14,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
              ),
            ),
            SizedBox(
                height: isMobile
                    ? NightshadeTokens.spaceXl
                    : NightshadeTokens.space3xl),
            for (var i = 0; i < 2; i++) ...[
              Container(
                width: 140,
                height: 18,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusSm),
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              Container(
                width: double.infinity,
                height: isMobile ? 164 : 188,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(
                      isMobile ? 10 : NightshadeTokens.radiusLg),
                  border: Border.all(color: colors.border),
                ),
              ),
              SizedBox(height: isMobile ? NightshadeTokens.spaceXl : 28),
            ],
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: NightshadeTokens.spaceSm),
                child: Text(
                  message,
                  style: (isMobile
                          ? NightshadeTypography.caption
                          : NightshadeTypography.bodySm)
                      .copyWith(color: colors.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsErrorState extends StatelessWidget {
  final bool isMobile;

  final Object error;

  final VoidCallback? onRetry;

  const SettingsErrorState({
    super.key,
    required this.error,
    this.isMobile = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final horizontalPadding =
        isMobile ? NightshadeTokens.spaceLg : NightshadeTokens.space2xl;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogMaxWidth(context, 520),
        ),
        child: Padding(
          padding: EdgeInsets.all(horizontalPadding),
          child: Container(
            padding: EdgeInsets.all(isMobile
                ? NightshadeTokens.spaceXl
                : NightshadeTokens.space2xl),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: NightshadeTokens.borderRadiusMd,
              border: Border.all(color: colors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: NightshadeDecorations.iconChip(
                    colors.error,
                    borderRadius: NightshadeTokens.borderRadiusMd,
                  ),
                  child: Icon(
                    LucideIcons.alertTriangle,
                    color: colors.error,
                  ),
                ),
                const SizedBox(height: NightshadeTokens.spaceLg),
                Text(
                  'Failed to load settings',
                  textAlign: TextAlign.center,
                  style: NightshadeTypography.bold(
                    isMobile
                        ? NightshadeTypography.bodyLg
                        : NightshadeTypography.bodyLg.copyWith(fontSize: NightshadeTypography.fontSize18),
                  ).copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: (isMobile
                          ? NightshadeTypography.caption
                          : NightshadeTypography.bodySm)
                      .copyWith(color: colors.textSecondary),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: NightshadeTokens.spaceLg),
                  NightshadeButton(
                    label: 'Retry',
                    icon: LucideIcons.refreshCw,
                    onPressed: onRetry,
                    size: isMobile ? ButtonSize.small : ButtonSize.medium,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A section container with a title and grouped settings rows.
