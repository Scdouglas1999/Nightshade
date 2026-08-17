part of '../darkroom_screen.dart';

/// How long each side of a blink compare holds before the other takes over.
///
/// Long enough to read the frame, short enough that the eye holds the previous
/// one — the interval visual comparison has used since blink comparators were
/// mechanical.
const Duration kDarkroomBlinkInterval = Duration(milliseconds: 700);

/// How the compare pane draws its two recipes.
enum _DarkroomCompareMode {
  /// Both renders at once, side by side on a wide screen and stacked on a
  /// phone.
  sideBySide,

  /// One render at a time in the same rectangle, alternating. The only way to
  /// see a small change: two pictures side by side are compared by moving the
  /// eye, which loses exactly the differences a blink makes obvious.
  blink,
}

/// Two recipes over one master, rendered together.
///
/// **One transform, two viewers.** Both panes are handed the SAME
/// [TransformationController], so a drag-pan or a pinch in either moves both.
/// A per-pane controller kept in step by a callback would come apart the moment
/// the operator dragged, because a drag reaches no callback. The controller is
/// owned here and disposed here; the surface never disposes one it did not
/// create.
///
/// **Each pane mounts once.** Both modes build both panes — side by side paints
/// them together, blink paints one at a time — so neither swap tears a pane's
/// decoded frame down. Nothing in either path carries a `GlobalKey`: two panes
/// are the same widget type over the same data, and a shared static key is how
/// the second one silently fails to mount in a release build.
///
/// **Both sides render the same master at the same preview budget**, so they
/// answer at the same pyramid level and one transform describes both. What
/// differs on screen is therefore the recipe and nothing else — which is the
/// only reason an A/B compare means anything.
class _DarkroomCompareView extends ConsumerStatefulWidget {
  /// The open recipe's live state — including edits that have not reached the
  /// row yet, which is what makes "compare with the draft" meaningful.
  final DarkroomState aState;

  /// The label the A side carries.
  final String aLabel;

  /// The recipe rendered on the B side.
  final int bRecipeId;

  /// The label the B side carries.
  final String bLabel;

  /// Whether the B side is the dawn autopilot's own draft.
  final bool bIsAutopilotDraft;

  final _DarkroomCompareMode mode;

  const _DarkroomCompareView({
    required this.aState,
    required this.aLabel,
    required this.bRecipeId,
    required this.bLabel,
    required this.bIsAutopilotDraft,
    required this.mode,
  });

  @override
  ConsumerState<_DarkroomCompareView> createState() =>
      _DarkroomCompareViewState();
}

class _DarkroomCompareViewState extends ConsumerState<_DarkroomCompareView> {
  /// The transform both panes share. Owned here so the two viewers cannot
  /// disagree about where the operator is looking.
  final TransformationController _transform = TransformationController();

  Timer? _blink;

  /// Which side a blink is currently showing.
  bool _showingA = true;

  /// True while the operator holds the compare control down, which pins the B
  /// side up regardless of the blink.
  bool _held = false;

  @override
  void initState() {
    super.initState();
    if (widget.mode == _DarkroomCompareMode.blink) _startBlink();
  }

  @override
  void didUpdateWidget(covariant _DarkroomCompareView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode != oldWidget.mode ||
        widget.bRecipeId != oldWidget.bRecipeId) {
      _stopBlink();
      _showingA = true;
      if (widget.mode == _DarkroomCompareMode.blink) _startBlink();
    }
  }

  @override
  void dispose() {
    _stopBlink();
    _transform.dispose();
    super.dispose();
  }

  void _startBlink() {
    _blink = Timer.periodic(kDarkroomBlinkInterval, (_) {
      if (!mounted) return;
      setState(() => _showingA = !_showingA);
    });
  }

  void _stopBlink() {
    _blink?.cancel();
    _blink = null;
  }

  bool get _blinking => _blink != null;

  /// Which side is on screen right now in blink mode: the hold wins over the
  /// timer, so "hold to compare" is a deliberate look rather than a race with
  /// the next tick.
  bool get _showA => _held ? false : _showingA;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final bState = ref.watch(
      darkroomControllerProvider(DarkroomScope.recipe(widget.bRecipeId)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _controls(colors, bState),
        Expanded(
          child: widget.mode == _DarkroomCompareMode.sideBySide
              ? _sideBySide(colors, bState)
              : _blinkPane(colors, bState),
        ),
      ],
    );
  }

  Widget _controls(NightshadeColors colors, DarkroomState bState) {
    final blinkMode = widget.mode == _DarkroomCompareMode.blink;
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
        spacing: NightshadeTokens.spaceSm,
        runSpacing: NightshadeTokens.spaceXs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _DarkroomTag(
            label: blinkMode ? (_showA ? 'Showing A' : 'Showing B') : 'A | B',
            tooltip: 'A is "${widget.aLabel}" — this editor\'s current stack, '
                'unsaved edits included. B is "${widget.bLabel}".',
          ),
          if (blinkMode)
            NightshadeButton(
              label: _blinking ? 'Pause blink' : 'Resume blink',
              icon: _blinking ? NightshadeIcons.pause : NightshadeIcons.play,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: () {
                if (_blinking) {
                  _stopBlink();
                } else {
                  _startBlink();
                }
                setState(() {});
              },
            ),
          // Blink only. Side by side already has both renders on screen, so
          // pinning B there changes nothing — and a control that publishes an
          // on/off state while changing nothing on screen is the shape of every
          // dead control in this app's history.
          if (blinkMode) _holdToCompare(),
          if (bState.rendering)
            const _DarkroomTag(
              label: 'B is rendering…',
              tooltip:
                  'The B side renders through the same engine as A, one recipe '
                  'at a time, so it can lag a moment behind.',
            ),
          if (bState.renderError != null)
            _DarkroomTag(
              label: 'B did not render',
              tooltip: bState.renderError!,
            ),
        ],
      ),
    );
  }

  /// Press-and-hold to see the other recipe, release to come back.
  ///
  /// The cheapest honest form of "compare with the draft": while it is held the
  /// B side is on screen, and B is whichever recipe the branch bar chose — the
  /// autopilot's draft when that is what was picked.
  Widget _holdToCompare() {
    return _DarkroomHoldToCompare(
      label: widget.bIsAutopilotDraft
          ? 'Hold to see the autopilot draft'
          : 'Hold to see ${widget.bLabel}',
      held: _held,
      onHeldChanged: (held) => setState(() => _held = held),
    );
  }

  Widget _sideBySide(NightshadeColors colors, DarkroomState bState) {
    final panes = [
      _pane(colors, widget.aLabel, 'A', widget.aState),
      _pane(colors, widget.bLabel, 'B', bState),
    ];
    // A phone reflows into a stack rather than shrinking both panes into
    // thumbnails: two 180-pixel-wide renders compare nothing.
    if (Responsive.isPhone(context)) {
      return Column(
        children: [
          Expanded(child: panes[0]),
          Container(height: 1, color: colors.border),
          Expanded(child: panes[1]),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: panes[0]),
        Container(width: 1, color: colors.border),
        Expanded(child: panes[1]),
      ],
    );
  }

  /// Blink keeps BOTH panes mounted and paints one of them.
  ///
  /// Building only the showing side tore the other one down on every tick, so
  /// each swap re-mounted a pane with no decoded frame and the comparator
  /// showed a blank for roughly half of each 700 ms cycle — destroying the
  /// afterimage that is the entire reason to blink rather than look side by
  /// side. Two mounted panes hold their own decoded frames, so the swap is a
  /// buffer change with nothing in between.
  ///
  /// [IndexedStack] rather than opacity or offstage: it lays both out, paints
  /// only the indexed one, and walks only that one for semantics, so the hidden
  /// recipe is not announced as being on screen.
  Widget _blinkPane(NightshadeColors colors, DarkroomState bState) {
    return IndexedStack(
      index: _showA ? 0 : 1,
      sizing: StackFit.expand,
      children: [
        _pane(colors, widget.aLabel, 'A', widget.aState),
        _pane(colors, widget.bLabel, 'B', bState),
      ],
    );
  }

  Widget _pane(
    NightshadeColors colors,
    String label,
    String side,
    DarkroomState state,
  ) {
    final preview = state.preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colors.surfaceAlt,
          padding: const EdgeInsets.symmetric(
            horizontal: NightshadeTokens.spaceMd,
            vertical: NightshadeTokens.spaceXs,
          ),
          child: Text(
            '$side · $label',
            style: NightshadeTypography.labelSm.copyWith(
              color: colors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: colors.background,
            child: preview == null
                ? _paneEmpty(state)
                : _DarkroomImageSurface(
                    preview: preview,
                    transform: _transform,
                    minScale: kDarkroomMinViewerScale,
                    maxScale: kDarkroomMaxViewerScale,
                  ),
          ),
        ),
        if (preview != null)
          Container(
            width: double.infinity,
            color: colors.surface,
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceMd,
              vertical: 2,
            ),
            child: Text(
              'Display transfer: ${preview.encoding}',
              style: NightshadeTypography.captionSm.copyWith(
                color: colors.textMuted,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _paneEmpty(DarkroomState state) {
    if (state.loading || state.rendering) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final loadError = state.loadError;
    if (loadError != null) {
      return EmptyState.compact(
        icon: NightshadeIcons.imageOff,
        title: 'This side could not be opened',
        body: loadError,
      );
    }
    final renderError = state.renderError;
    if (renderError != null) {
      return EmptyState.compact(
        icon: NightshadeIcons.imageOff,
        title: 'This side did not render',
        body: renderError,
      );
    }
    return const EmptyState.compact(
      icon: NightshadeIcons.image,
      title: 'Nothing rendered yet',
      body: 'This recipe has not produced a picture over the master yet.',
    );
  }
}

/// A press-and-hold control: held means "show the other recipe".
///
/// Hand-rolled rather than a [NightshadeButton] because the gesture IS the
/// control for a pointer. A button's callback fires on release, which is the
/// moment this affordance ends; wiring one to an empty closure to borrow the
/// styling would leave a control that looks pressable and does nothing on tap.
///
/// **A hold is not the only way to work it.** A press-and-hold cannot be
/// performed from a keyboard or from assistive tech, and the earlier shape —
/// `Semantics(button)` over an `ExcludeSemantics(GestureDetector)` — published
/// a node with no tap action and no enabled state, which the AT-SPI bridge
/// reported as `Hold to see … [DISABLED]`: a control that read as broken and
/// could not be operated at all. So the same control is also a TOGGLE: it
/// carries `toggled`, publishes tap and long-press actions, takes keyboard
/// focus, and Enter/Space pin the other recipe up and release it again. The
/// pointer path is unchanged — press pins, release comes back.
class _DarkroomHoldToCompare extends StatefulWidget {
  final String label;
  final bool held;
  final ValueChanged<bool> onHeldChanged;

  const _DarkroomHoldToCompare({
    required this.label,
    required this.held,
    required this.onHeldChanged,
  });

  @override
  State<_DarkroomHoldToCompare> createState() => _DarkroomHoldToCompareState();
}

class _DarkroomHoldToCompareState extends State<_DarkroomHoldToCompare> {
  /// True while the keyboard focus ring is on this control.
  bool _focused = false;

  void _toggle() => widget.onHeldChanged(!widget.held);

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final held = widget.held;
    final active = held || _focused;
    return Semantics(
      button: true,
      // Stated, not implied: `Semantics` publishes the isEnabled flag only when
      // the field is given, and without it the AT-SPI bridge reports the
      // working control as disabled.
      enabled: true,
      toggled: held,
      label: widget.label,
      hint: held
          ? 'Showing the other recipe. Release the press, or activate this '
              'control again, to come back.'
          : 'Press and hold to show the other recipe; release to come back. '
              'From a keyboard, activate it to pin the other recipe up and '
              'activate it again to come back.',
      // The actions the pointer gesture cannot offer assistive tech. Both land
      // on the same toggle, so an activation pins B up and the next one
      // releases it — the explicit release a hold has no way to express.
      onTap: _toggle,
      onLongPress: _toggle,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (value) {
          if (!mounted || _focused == value) return;
          setState(() => _focused = value);
        },
        actions: <Type, Action<Intent>>{
          // Enter and Space arrive as ActivateIntent from the app-level default
          // shortcuts; ButtonActivateIntent is the web variant.
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        // The gesture keeps its own semantics out of the way: a
        // `TapGestureRecognizer` publishes its own tap action, which would
        // collide with the one declared above and split this control into two
        // nodes — a named one with no action over an anonymous one with the
        // action.
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => widget.onHeldChanged(true),
            onTapUp: (_) => widget.onHeldChanged(false),
            onTapCancel: () => widget.onHeldChanged(false),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: NightshadeTokens.spaceSm,
                vertical: NightshadeTokens.spaceXs,
              ),
              decoration: BoxDecoration(
                color: held ? colors.surfaceAlt : colors.surface,
                borderRadius: NightshadeTokens.borderRadiusSm,
                border: Border.all(
                  color: active ? colors.primary : colors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    NightshadeIcons.visible,
                    size: NightshadeTokens.iconSm,
                    color: active ? colors.primary : colors.textSecondary,
                  ),
                  const SizedBox(width: NightshadeTokens.spaceXs),
                  Text(
                    widget.label,
                    style: NightshadeTypography.labelSm.copyWith(
                      color: active ? colors.primary : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
