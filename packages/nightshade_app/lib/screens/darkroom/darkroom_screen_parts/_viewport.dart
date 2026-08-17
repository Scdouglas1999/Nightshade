part of '../darkroom_screen.dart';

/// Screen pixels per MASTER pixel in the Darkroom viewport.
///
/// The number is NOT the viewer's own zoom: the preview is rendered from a
/// pyramid level, so a viewer scale of 1.0 over a level-2 preview draws one
/// screen pixel per FOUR master pixels. Every readout that says a percentage
/// must say it about the master, or it describes a picture that is not the
/// operator's data.
///
/// Defaults to 1.0 so a reader that runs before the first render has laid out
/// sees "unscaled" rather than zero. Published by [_DarkroomViewport], the only
/// widget that knows both the viewport and the render's level.
final darkroomDisplayScaleProvider = StateProvider<double>((ref) => 1.0);

/// Widest zoom the Darkroom viewport allows.
///
/// Higher than the viewer's own default because 1:1 on a master pixel means a
/// viewer scale of `1 / scaleFromMaster`: a level-4 preview needs 16× before a
/// screen pixel is a master pixel.
const double kDarkroomMaxViewerScale = 32.0;

/// Narrowest zoom the Darkroom viewport allows.
const double kDarkroomMinViewerScale = 0.05;

/// Step one press of the zoom buttons takes.
const double kDarkroomZoomStep = 1.25;

/// The rendered image, and the controls that move the view over it.
class _DarkroomViewport extends ConsumerStatefulWidget {
  final DarkroomState state;

  /// Re-check and re-render the committed stack now.
  final Future<void> Function() onRerender;

  const _DarkroomViewport({required this.state, required this.onRerender});

  @override
  ConsumerState<_DarkroomViewport> createState() => _DarkroomViewportState();
}

class _DarkroomViewportState extends ConsumerState<_DarkroomViewport> {
  /// Owned here, not by [_DarkroomImageSurface], because the fit / 1:1 / zoom
  /// controls drive it — and because a new render must not throw away the zoom
  /// and pan the operator set on the previous one.
  final TransformationController _transform = TransformationController();

  /// The box the viewer is laid out in, measured in the last build.
  Size _viewportSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    super.dispose();
  }

  /// Repaint the readout. The transform changes on wheel zoom, on drag-pan and
  /// on pinch, and only some of those pass through this widget, so the readout
  /// listens to the controller itself.
  ///
  /// One of those changes arrives from the frame after a layout: the surface
  /// measures its container in a layout callback and writes the initial fit to
  /// this controller. Marking this widget dirty from inside layout asks for a
  /// build during a layout that is already running — the request lands against
  /// a render object whose layout is in flight, is dropped when that layout
  /// finishes, and takes the enclosing panel layout's build scope down with it:
  /// every later rebuild of the viewport, the recipe panel and the history
  /// stack is skipped until a window resize forces a real relayout. Debug
  /// builds catch it on an assert inside the framework's own scheduler; release
  /// builds strip that assert, which is why the editor froze only when shipped.
  /// Repainting on the next frame is the same readout one frame later, and it
  /// is the only moment at which asking for a build is legal.
  void _onTransformChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  /// The viewer's own scale: screen pixels per RENDERED pixel.
  double get _viewerScale => _transform.value.getMaxScaleOnAxis();

  /// Screen pixels per MASTER pixel, or null when the render did not state the
  /// level it answered at.
  double? get _masterScale {
    final scale = widget.state.preview?.scaleFromMaster;
    if (scale == null) return null;
    return _viewerScale * scale;
  }

  /// Hand the measured scale to readers outside this subtree.
  ///
  /// Deferred to a post-frame callback because it is computed inside `build`
  /// and mutating a provider during a build is illegal. The equality guard
  /// makes this converge in one extra frame rather than looping.
  void _publishDisplayScale(double scale) {
    if (ref.read(darkroomDisplayScaleProvider) == scale) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(darkroomDisplayScaleProvider.notifier).state = scale;
    });
  }

  void _fit() {
    final preview = widget.state.preview;
    if (preview == null) return;
    final size = _viewportSize;
    if (size.width <= 0 || size.height <= 0) return;
    if (preview.width <= 0 || preview.height <= 0) return;
    final scaleX = size.width / preview.width;
    final scaleY = size.height / preview.height;
    final fit = scaleX < scaleY ? scaleX : scaleY;
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        (size.width - preview.width * fit) / 2,
        (size.height - preview.height * fit) / 2,
        0,
        1.0,
      )
      ..scaleByDouble(fit, fit, 1.0, 1.0);
  }

  /// One screen pixel per MASTER pixel, as close as the zoom ceiling allows.
  ///
  /// A coarse pyramid level cannot reach 1:1 inside the ceiling; the readout
  /// then shows the scale that was actually reached, so the picture is never
  /// labelled 100% when it is not.
  void _oneToOne() {
    final scale = widget.state.preview?.scaleFromMaster;
    if (scale == null) return;
    _scaleAboutCentre(1.0 / scale);
  }

  void _zoomBy(double factor) => _scaleAboutCentre(_viewerScale * factor);

  void _scaleAboutCentre(double target) {
    final size = _viewportSize;
    if (size.width <= 0 || size.height <= 0) return;
    final current = _viewerScale;
    if (current <= 0) return;
    final clamped = target.clamp(
      kDarkroomMinViewerScale,
      kDarkroomMaxViewerScale,
    );
    if (clamped == current) return;
    final factor = clamped / current;
    final focalX = size.width / 2;
    final focalY = size.height / 2;
    final matrix = Matrix4.identity()
      ..translateByDouble(focalX, focalY, 0, 1.0)
      ..scaleByDouble(factor, factor, 1.0, 1.0)
      ..translateByDouble(-focalX, -focalY, 0, 1.0);
    _transform.value = matrix * _transform.value;
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final state = widget.state;
    final masterScale = _masterScale;
    if (masterScale != null) _publishDisplayScale(masterScale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _controls(colors, state, masterScale),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewportSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return _canvas(colors, state);
            },
          ),
        ),
        _encodingStrip(colors, state),
      ],
    );
  }

  Widget _controls(
    NightshadeColors colors,
    DarkroomState state,
    double? masterScale,
  ) {
    final hasPreview = state.preview != null;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceXs,
      ),
      child: Wrap(
        spacing: NightshadeTokens.spaceXs,
        runSpacing: NightshadeTokens.spaceXs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          AccessibleIconButton(
            icon: NightshadeIcons.remove,
            label: 'Zoom out',
            size: NightshadeTokens.iconSm,
            onPressed: hasPreview ? () => _zoomBy(1 / kDarkroomZoomStep) : null,
          ),
          AccessibleIconButton(
            icon: NightshadeIcons.add,
            label: 'Zoom in',
            size: NightshadeTokens.iconSm,
            onPressed: hasPreview ? () => _zoomBy(kDarkroomZoomStep) : null,
          ),
          NightshadeButton(
            label: 'Fit',
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: hasPreview ? _fit : null,
          ),
          NightshadeButton(
            label: '1:1',
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed:
                state.preview?.scaleFromMaster == null ? null : _oneToOne,
          ),
          Semantics(
            label: masterScale == null
                ? 'Zoom relative to the master is unknown'
                : 'Zoom ${(masterScale * 100).round()} percent of the master',
            child: ExcludeSemantics(
              child: Text(
                masterScale == null
                    ? '—'
                    : '${(masterScale * 100).round()}% of master',
                style: NightshadeTypography.monoSm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
          if (state.preview?.level != null)
            _DarkroomTag(
              label: 'Level ${state.preview!.level}',
              tooltip:
                  'The pyramid level this preview was rendered from. Level 0 '
                  'is the master\'s own pixels; export always renders at full '
                  'resolution.',
            ),
        ],
      ),
    );
  }

  Widget _canvas(NightshadeColors colors, DarkroomState state) {
    final preview = state.preview;
    if (preview == null) {
      if (state.rendering) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      final renderError = state.renderError;
      if (renderError != null) {
        return EmptyState(
          icon: NightshadeIcons.imageOff,
          title: 'The render did not finish',
          body: renderError,
          action: NightshadeButton(
            label: 'Render again',
            icon: NightshadeIcons.refresh,
            onPressed: () => widget.onRerender(),
          ),
        );
      }
      if (state.cancelledPhase != null) {
        return EmptyState(
          icon: NightshadeIcons.stopCircle,
          title: 'The render was stopped',
          body: 'It stopped during ${state.cancelledPhase}, so there are no '
              'pixels to show yet.',
          action: NightshadeButton(
            label: 'Render again',
            icon: NightshadeIcons.refresh,
            onPressed: () => widget.onRerender(),
          ),
        );
      }
      return const EmptyState(
        icon: NightshadeIcons.image,
        title: 'Nothing rendered yet',
        body:
            'The recipe has not been rendered over this master. Adjust a step '
            'or press Render again.',
      );
    }

    // Why the pixels on screen are not the current stack's, when they are not.
    final failure = state.renderError;

    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: colors.background,
            child: _DarkroomImageSurface(
              preview: preview,
              transform: _transform,
              minScale: kDarkroomMinViewerScale,
              maxScale: kDarkroomMaxViewerScale,
            ),
          ),
        ),
        // A re-render keeps the previous picture on screen and marks it as
        // stale rather than blanking the canvas: an editor that flashes to
        // empty on every slider frame is unreadable.
        if (state.rendering)
          Positioned(
            top: NightshadeTokens.spaceSm,
            right: NightshadeTokens.spaceSm,
            child: _DarkroomTag(
              label: state.cancelRequested ? 'Stopping…' : 'Rendering…',
              tooltip:
                  'The picture below is the previous render until this one '
                  'lands.',
            ),
          ),
        // A render that FAILED leaves the same superseded picture up, so it
        // gets the same treatment: the staleness is marked here, on the pixels
        // it is about, and the engine's own reason is stated beside it. The
        // Recipe panel says it too, but at phone width that panel is a segment
        // the operator is not looking at — a picture is not labelled by a
        // sentence in a view that is not on screen.
        if (!state.rendering && failure != null) ...[
          Positioned(
            top: NightshadeTokens.spaceSm,
            right: NightshadeTokens.spaceSm,
            child: _DarkroomTag(
              label: 'Stale — the render did not finish',
              tooltip:
                  'The picture below is the last render that finished, not the '
                  'stack as it stands now: $failure',
            ),
          ),
          // Positioned.fill, so the alert is laid out inside the canvas rather
          // than growing past its top edge and painting over the zoom controls
          // on a short viewport.
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomCenter,
              // Over the viewer, not in place of it: a pan or a zoom of the
              // picture underneath still reaches the surface.
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
                  child: NightshadeAlert(
                    severity: NightshadeAlertSeverity.error,
                    title: 'The render did not finish',
                    message: '$failure\n\nThis picture is the last render that '
                        'finished, so it does not show the stack as it stands.',
                    compact: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _encodingStrip(NightshadeColors colors, DarkroomState state) {
    final preview = state.preview;
    if (preview == null) return const SizedBox.shrink();
    final encoding = preview.encoding;
    final screenTransfer = encoding.screenTransfer;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceXs,
      ),
      child: Wrap(
        spacing: NightshadeTokens.spaceSm,
        runSpacing: NightshadeTokens.spaceXs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            // The strip describes the render whose pixels are on screen. When
            // a later render failed, those pixels are the previous render's,
            // and saying so here keeps the strip from reading as an account of
            // the stack the operator is now editing.
            state.renderError == null || state.rendering
                ? 'Display transfer: ${encoding.sentence}'
                : 'Display transfer of the last render that finished: '
                    '${encoding.sentence}',
            style: NightshadeTypography.captionSm.copyWith(
              color: colors.textSecondary,
            ),
          ),
          // The lift's own numbers, behind the tag rather than on the strip:
          // they are what makes "display only" checkable, and they are the
          // engine's, not the recipe's.
          if (screenTransfer != null)
            _DarkroomTag(
              label: 'Screen transfer',
              tooltip: 'The display lift the engine applied, in its own '
                  'numbers: ${_describeParams(screenTransfer)}. It is not a '
                  'step of this recipe, so no export carries it.',
            ),
        ],
      ),
    );
  }

  /// A parameter map as `key value` pairs in a stable order.
  static String _describeParams(Map<String, dynamic> params) {
    final keys = params.keys.toList()..sort();
    return [for (final key in keys) '$key ${params[key]}'].join(', ');
  }
}

/// A small labelled tag with an explanation behind it.
///
/// Deliberately not colour-coded: under the red-night palette every semantic
/// hue collapses toward the same red, so a tag that carried meaning in its fill
/// alone would say nothing at the telescope.
class _DarkroomTag extends StatelessWidget {
  final String label;
  final String tooltip;

  const _DarkroomTag({required this.label, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceSm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: NightshadeTokens.borderRadiusSm,
          border: Border.all(color: colors.border),
        ),
        child: Text(
          label,
          style: NightshadeTypography.captionSm.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
