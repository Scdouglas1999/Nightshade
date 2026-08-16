// Equipment hint card, canvas controls, survey selector, zoom controls and scale indicator.
part of '../framing_canvas.dart';

/// The "no equipment configured" hint card in the canvas's top chrome.
///
/// Lives in the single top-chrome [Column] rather than an inline `Positioned`
/// pinned at a literal `top: 60`, where a wrapped toolbar row could end up
/// underneath it.
class _EquipmentHintCard extends StatelessWidget {
  final NightshadeColors colors;
  final double previewFovDegrees;

  const _EquipmentHintCard({
    required this.colors,
    required this.previewFovDegrees,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: NightshadeTokens.paddingMd,
      decoration: BoxDecoration(
        color:
            colors.info.withValues(alpha: NightshadeTokens.opacityStatusFill),
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(
          color: colors.info.withValues(alpha: NightshadeTokens.opacityHalf),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(NightshadeIcons.visible,
              size: NightshadeTokens.iconXs, color: colors.info),
          const SizedBox(width: NightshadeTokens.spaceSm),
          // Flexible so a narrow canvas ellipsizes rather than overflowing.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Preview: ${previewFovDegrees.toStringAsFixed(1)}° FOV',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NightshadeTypography.labelQuiet
                      .copyWith(color: colors.info),
                ),
                Text(
                  'Configure equipment for accurate framing',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NightshadeTypography.overline
                      .copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CanvasControls extends StatelessWidget {
  final NightshadeColors colors;
  final FramingState framingState;

  const _CanvasControls({
    required this.colors,
    required this.framingState,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        // The survey-source picker plus toggle chips. On a narrow phone canvas
        // there is not enough width to keep all of these on one line, so they
        // live in a [Wrap] that flows to a second line instead of overflowing.
        final chips = <Widget>[
          // Survey-source selector: a real NightshadeDropdown wired to the
          // framing notifier so changing the source refetches the imagery for
          // the new survey. No dead handler — selection drives setSurveySource.
          _SurveySourceSelector(
            colors: colors,
            source: framingState.surveySource,
            onChanged: (source) =>
                ref.read(framingProvider.notifier).setSurveySource(source),
          ),
          _ControlChip(
            icon: NightshadeIcons.grid,
            label: 'Grid',
            isActive: framingState.showGrid,
            colors: colors,
            onTap: () => ref.read(framingProvider.notifier).toggleGrid(),
          ),
          _ControlChip(
            icon: NightshadeIcons.tag,
            label: 'Labels',
            isActive: framingState.showLabels,
            colors: colors,
            onTap: () => ref.read(framingProvider.notifier).toggleLabels(),
          ),
          // Guide-star finder: highlights bright (V < 10) catalog stars inside
          // the imaging FOV as candidate autoguider guide stars.
          _ControlChip(
            icon: NightshadeIcons.guider,
            label: 'Guide Stars',
            isActive: framingState.showGuideStars,
            colors: colors,
            onTap: () => ref.read(framingProvider.notifier).toggleGuideStars(),
          ),
          // HiPS deep-survey tiles toggle. Only shown for surveys that have a
          // verified HiPS pyramid (the toggle would be inert otherwise — the
          // capability gate, hipsSurveyIsTileCapable, would keep tiles off);
          // for those surveys it flips hipsFramingEnabledProvider, the same
          // user preference hipsFramingActiveProvider combines with the
          // capability gate to mount/unmount the streamed tile mosaic.
          if (hipsSurveyIsTileCapable(framingState.surveySource))
            _ControlChip(
              icon: NightshadeIcons.sparkle,
              label: 'HiPS Tiles',
              isActive: ref.watch(hipsFramingEnabledProvider),
              colors: colors,
              onTap: () {
                final notifier = ref.read(hipsFramingEnabledProvider.notifier);
                notifier.state = !notifier.state;
              },
            ),
        ];

        final loading = framingState.isLoadingImage
            ? Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: NightshadeTokens.spaceMd,
                    vertical: NightshadeTokens.spaceSm),
                decoration: BoxDecoration(
                  color: colors.surfaceOverlay
                      .withValues(alpha: NightshadeTokens.opacityMuted),
                  borderRadius: NightshadeTokens.borderRadiusMd,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: NightshadeTokens.iconXs,
                      height: NightshadeTokens.iconXs,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: NightshadeTokens.spaceSm),
                    Text(
                      'Loading...',
                      style: NightshadeTypography.labelQuiet
                          .copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              )
            : null;

        // Chips take the available width (wrapping when needed); the loading
        // pill sits at the trailing edge on the first line. Using a Row with an
        // Expanded(Wrap) keeps the loading indicator right-aligned without a
        // Spacer (which would force everything onto one unbreakable line).
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: NightshadeTokens.spaceSm,
                runSpacing: NightshadeTokens.spaceSm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: chips,
              ),
            ),
            if (loading != null) ...[
              const SizedBox(width: NightshadeTokens.spaceSm),
              loading,
            ],
          ],
        );
      },
    );
  }
}

/// On-canvas survey-source picker.
///
/// A [NightshadeDropdown] (the canonical design-system selector) fronted by the
/// `layers` glyph so it reads as part of the chip strip, wired straight to
/// [FramingNotifier.setSurveySource]. Selecting a source refetches the survey
/// imagery for that band (the refetch lives in the notifier).
class _SurveySourceSelector extends StatelessWidget {
  final NightshadeColors colors;
  final SurveySource source;
  final ValueChanged<SurveySource> onChanged;

  const _SurveySourceSelector({
    required this.colors,
    required this.source,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // The dropdown keys on the enum name and maps back to the enum on change so
    // SurveySource stays the single source of truth (no string parsing of
    // display names).
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceOverlay
            .withValues(alpha: NightshadeTokens.opacityHalf),
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(
          color:
              colors.border.withValues(alpha: NightshadeTokens.opacitySubtle),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: NightshadeTokens.spaceMd),
          Icon(
            NightshadeIcons.layers,
            size: NightshadeTokens.iconXs,
            color: colors.textSecondary,
          ),
          const SizedBox(width: NightshadeTokens.spaceXs),
          // A TIGHT width (not just a minimum) for the widest survey label
          // ('WISE 12μm' / 'DSS2 Blue' / 'SDSS Color') plus the dropdown's own
          // 12px horizontal padding and its chevron.
          //
          // Two things depend on this. First: left to size itself inside the
          // toolbar's [Wrap], the button was squeezed against the neighbouring
          // chrome and lost the first character of the selection ('DSS2 Red'
          // rendered as ')SS2 Red', '2MASS J' as '?MASS J') — the control
          // misreporting which survey was on screen. Second: `isExpanded` uses
          // an internal Expanded, which asserts on the unbounded width a Wrap
          // hands its children, so the box must be tight rather than a
          // ConstrainedBox(minWidth:).
          SizedBox(
            width: 148,
            child: NightshadeDropdown(
              value: source.name,
              isDense: true,
              isExpanded: true,
              items: SurveySource.values.map((s) => s.name).toList(),
              itemLabels:
                  SurveySource.values.map((s) => s.displayName).toList(),
              onChanged: (name) {
                if (name == null) return;
                onChanged(SurveySource.values.byName(name));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final NightshadeColors colors;
  final VoidCallback? onTap;

  const _ControlChip({
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.colors,
    this.onTap,
  });

  @override
  State<_ControlChip> createState() => _ControlChipState();
}

class _ControlChipState extends State<_ControlChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: NightshadeTokens.durationQuick,
          padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceMd,
              vertical: NightshadeTokens.spaceSm),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.colors.primary
                    .withValues(alpha: NightshadeTokens.opacityMedium)
                : widget.colors.surfaceOverlay.withValues(
                    alpha: _isHovered
                        ? NightshadeTokens.opacityHoverBorder
                        : NightshadeTokens.opacityHalf),
            borderRadius: NightshadeTokens.borderRadiusMd,
            border: Border.all(
              color: widget.isActive
                  ? widget.colors.primary
                      .withValues(alpha: NightshadeTokens.opacityHalf)
                  : widget.colors.border
                      .withValues(alpha: NightshadeTokens.opacitySubtle),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: NightshadeTokens.iconXs,
                color: widget.isActive
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: NightshadeTokens.spaceXs),
              Text(
                widget.label,
                style: NightshadeTypography.labelQuiet.copyWith(
                  color: widget.isActive
                      ? widget.colors.primary
                      : widget.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final NightshadeColors colors;
  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _ZoomControls({
    required this.colors,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: NightshadeTokens.paddingXs,
      decoration: BoxDecoration(
        color: colors.surfaceOverlay
            .withValues(alpha: NightshadeTokens.opacityHoverBorder),
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
              icon: NightshadeIcons.add, colors: colors, onTap: onZoomIn),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceXs),
            child: Text(
              '${(zoom * 100).round()}%',
              style: NightshadeTypography.withTabular(
                NightshadeTypography.overline
                    .copyWith(color: colors.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          _ZoomButton(
              icon: NightshadeIcons.remove, colors: colors, onTap: onZoomOut),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Container(height: 1, width: 20, color: colors.border),
          const SizedBox(height: NightshadeTokens.spaceXs),
          _ZoomButton(
              icon: NightshadeIcons.expand, colors: colors, onTap: onReset),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatefulWidget {
  final IconData icon;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _ZoomButton({
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_ZoomButton> createState() => _ZoomButtonState();
}

class _ZoomButtonState extends State<_ZoomButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: NightshadeTokens.durationQuick,
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _isHovered ? widget.colors.surfaceAlt : Colors.transparent,
            borderRadius: NightshadeTokens.borderRadiusXs,
          ),
          child: Icon(
            widget.icon,
            size: NightshadeTokens.iconXs,
            color: widget.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// On-canvas scale bar showing a real angular distance derived from the shared
/// [FramingPlateScale].
///
/// The bar targets a ~60px length, converts that to degrees through
/// [FramingPlateScale.pixelsPerDegree] (the same scale the imagery and overlays
/// use), snaps it to a "nice" arcminute / degree increment, and then sizes the
/// bar to the *exact* on-screen length of that snapped value so the rule and
/// its label always agree.
class _ScaleIndicator extends StatelessWidget {
  final NightshadeColors colors;
  final double zoom;
  final FramingPlateScale plateScale;
  final Size canvasSize;

  const _ScaleIndicator({
    required this.colors,
    required this.zoom,
    required this.plateScale,
    required this.canvasSize,
  });

  /// Candidate scale-bar lengths, in arcminutes, from 1' up to 5°. The renderer
  /// picks the largest entry whose on-screen length does not exceed the target
  /// bar width, so the bar grows and shrinks through familiar astronomical
  /// increments as the user zooms.
  static const List<double> _niceArcminSteps = [
    1,
    2,
    5,
    10,
    15,
    30,
    60,
    120,
    300,
  ];

  /// Target on-screen length of the scale bar, in logical pixels, before
  /// snapping to the nearest nice value.
  static const double _targetBarPx = 60;

  @override
  Widget build(BuildContext context) {
    final pixelsPerDegree =
        canvasSize.isEmpty ? 0.0 : plateScale.pixelsPerDegree(canvasSize, zoom);
    final pixelsPerArcmin = pixelsPerDegree / 60.0;

    // Choose the largest nice step that still fits within the target width;
    // fall back to the smallest step when even 1' is wider than the target
    // (extreme zoom-in) so the bar always represents a real, labelled distance.
    double stepArcmin = _niceArcminSteps.first;
    if (pixelsPerArcmin.isFinite && pixelsPerArcmin > 0) {
      for (final candidate in _niceArcminSteps) {
        if (candidate * pixelsPerArcmin <= _targetBarPx) {
          stepArcmin = candidate;
        } else {
          break;
        }
      }
    }

    final barLength = (stepArcmin * pixelsPerArcmin)
        .clamp(NightshadeTokens.space3xl, _targetBarPx * 1.5);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceMd,
          vertical: NightshadeTokens.spaceSm),
      decoration: BoxDecoration(
        color: colors.surfaceOverlay
            .withValues(alpha: NightshadeTokens.opacityHoverBorder),
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scale',
            style:
                NightshadeTypography.overline.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Row(
            children: [
              Container(
                width: barLength,
                height: 3,
                decoration: BoxDecoration(
                  color: colors.textSecondary,
                  borderRadius: NightshadeTokens.borderRadiusXs,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceXs),
              Text(
                _formatScaleLabel(stepArcmin),
                style: NightshadeTypography.withTabular(
                  NightshadeTypography.labelQuiet
                      .copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Formats an arcminute span as a compact astronomical label: values that are
  /// a whole number of degrees read as e.g. `2°`, otherwise as arcminutes
  /// (`15'`).
  String _formatScaleLabel(double arcmin) {
    if (arcmin >= 60 && arcmin % 60 == 0) {
      return '${(arcmin / 60).toStringAsFixed(0)}°';
    }
    return "${arcmin.toStringAsFixed(0)}'";
  }
}
