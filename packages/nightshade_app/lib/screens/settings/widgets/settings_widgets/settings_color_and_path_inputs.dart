part of '../settings_widgets.dart';

class SettingsColorPicker extends StatefulWidget {
  /// The offered accents as `(hex, name)`. The name is not decoration: it is
  /// the swatch's accessible label and its tooltip, so a control whose only
  /// other description is its own pixels can be found and read.
  static const List<(String, String)> accentColors = [
    ('#5B9EC4', 'Cyan-blue'),
    ('#10B981', 'Emerald'),
    ('#F59E0B', 'Amber'),
    ('#EF4444', 'Red'),
    ('#2878A8', 'Deep sky'),
    ('#EC4899', 'Pink'),
    ('#06B6D4', 'Cyan'),
  ];

  final String selectedColor;

  /// May be asynchronous so a failed save can restore the confirmed color.
  final FutureOr<void> Function(String) onColorSelected;

  final bool isMobile;

  const SettingsColorPicker({
    super.key,
    required this.selectedColor,
    required this.onColorSelected,
    this.isMobile = false,
  });

  @override
  State<SettingsColorPicker> createState() => _SettingsColorPickerState();
}

class _SettingsColorPickerState extends State<SettingsColorPicker> {
  late String _selectedColor;
  int _editGeneration = 0;
  int _activeWrites = 0;
  Future<void> _writeTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.selectedColor;
  }

  @override
  void didUpdateWidget(covariant SettingsColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_activeWrites == 0) _selectedColor = widget.selectedColor;
  }

  void _selectColor(String color) {
    if (color.toLowerCase() == _selectedColor.toLowerCase()) return;
    final generation = ++_editGeneration;
    final callback = widget.onColorSelected;
    setState(() => _selectedColor = color);

    _activeWrites++;
    final operation = _writeTail.then((_) async {
      try {
        await Future<void>.sync(() => callback(color));
      } catch (e) {
        // The swatch snaps back to the confirmed colour, which is the honest
        // rendering, but the revert alone does not say a save was attempted
        // and refused. Log so a settings backend that is rejecting writes is
        // diagnosable instead of looking like a UI that ignores taps.
        developer.log(
          'Settings colour write failed; reverted the swatch to the last '
          'confirmed value: $e',
          name: 'SettingsInput',
          level: 900,
        );
        if (mounted && generation == _editGeneration) {
          setState(() => _selectedColor = widget.selectedColor);
        }
      } finally {
        _activeWrites--;
      }
    });
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    unawaited(operation);
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final circleSize = widget.isMobile ? 28.0 : 24.0;

    final spacing =
        widget.isMobile ? NightshadeTokens.spaceSm : NightshadeTokens.radiusSm;

    // Always wrap. A fixed `Row` of seven swatches needs ~210 px and cannot
    // shrink, so on a narrowed settings detail pane it pushed the last
    // swatches off-screen (unpickable) and overflowed by >100 px. `Wrap`
    // still renders as one line whenever the row has room.
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      alignment: WrapAlignment.end,
      children: SettingsColorPicker.accentColors.map((colorData) {
        final (hex, name) = colorData;

        return _buildColorCircle(colors, hex, name, circleSize);
      }).toList(),
    );
  }

  Widget _buildColorCircle(
    NightshadeColors colors,
    String hex,
    String name,
    double size,
  ) {
    final color = Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);

    final isSelected = _selectedColor.toLowerCase() == hex.toLowerCase();

    // These were seven bare GestureDetectors: no name, no role, no focus. The
    // live accessibility tree for Settings → Appearance listed "Accent color"
    // with ZERO children, so a screen-reader or keyboard user could neither
    // find the swatches nor tell which one was active — while the switch in the
    // row below reported itself as "toggle button … [off]". The colour names
    // were already in `accentColors` and simply thrown away; a swatch whose
    // only description is its pixels needs them most.
    return MergeSemantics(
      child: Semantics(
        // Semantics publishes isEnabled only when this field is given;
        // omitting it makes assistive tech announce a live control as
        // disabled. Measured on the running app 2026-08-09.
        enabled: true,
        button: true,
        inMutuallyExclusiveGroup: true,
        selected: isSelected,
        label: name,
        child: Tooltip(
          message: name,
          child: InkWell(
            key: ValueKey('settings-color-$hex'),
            onTap: () => _selectColor(hex),
            customBorder: const CircleBorder(),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? colors.textPrimary : colors.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Path input with browse button for file/directory selection.
///
/// The box only LOOKS like a text field when [onPathEntered] is supplied. It
/// used to look like one always: a bordered, filled box with a muted "Not set"
/// empty-state label that swallowed every keystroke, because it was a [Text]. On a
/// real rig the typed path is often the only way in — a UNC share, a NAS mount
/// that is not up yet, a folder on the imaging host — so the two storage rows
/// now accept one, and the rows that genuinely cannot (a solver executable the
/// app has to verify) render a plain label instead of inviting the attempt.
class SettingsPathInput extends StatefulWidget {
  final String path;

  final FutureOr<void> Function() onBrowse;

  /// Commit a hand-typed path. Null makes this control read-only.
  ///
  /// Called on Enter and on focus loss, only when the text differs from
  /// [path]. The callback owns validation: it may reject the value, in which
  /// case the field snaps back to [path] on the next build.
  final FutureOr<void> Function(String)? onPathEntered;

  final bool isMobile;

  /// If true, use flexible width (useful for stacked mobile layouts)

  final bool flexible;

  /// Identity of the backend/host that owns [onBrowse]. A changed identity
  /// invalidates an in-flight picker and immediately unlocks this control.
  final Object? authorityKey;

  const SettingsPathInput({
    super.key,
    required this.path,
    required this.onBrowse,
    this.onPathEntered,
    this.isMobile = false,
    this.flexible = false,
    this.authorityKey,
  });

  @override
  State<SettingsPathInput> createState() => _SettingsPathInputState();
}

class _SettingsPathInputState extends State<SettingsPathInput> {
  bool _browsing = false;
  int _browseGeneration = 0;

  TextEditingController? _controller;
  FocusNode? _focusNode;
  bool _committing = false;

  bool get _editable => widget.onPathEntered != null;

  @override
  void initState() {
    super.initState();
    if (_editable) {
      _controller = TextEditingController(text: widget.path);
      _focusNode = FocusNode()..addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    _focusNode?.removeListener(_onFocusChange);
    _focusNode?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SettingsPathInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_browsing && !identical(oldWidget.authorityKey, widget.authorityKey)) {
      _browseGeneration++;
      _browsing = false;
    }
    // Adopt the stored value whenever it is not being typed into: a browse, a
    // host switch, or a refused write all have to be visible here. Never while
    // focused, or the caret would jump under the operator's hands.
    final controller = _controller;
    if (controller != null &&
        !_committing &&
        _focusNode?.hasFocus != true &&
        controller.text != widget.path) {
      controller.text = widget.path;
    }
  }

  void _onFocusChange() {
    if (_focusNode?.hasFocus != true) {
      // Leaving the field commits it. Tabbing away or clicking elsewhere is
      // how people leave a path box; requiring Enter loses the edit silently.
      _commit();
    }
  }

  Future<void> _commit() async {
    final controller = _controller;
    final handler = widget.onPathEntered;
    if (controller == null || handler == null || _committing) return;
    final typed = controller.text;
    if (typed == widget.path) return;
    _committing = true;
    try {
      await Future<void>.sync(() => handler(typed));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not use that path: $error')),
        );
      }
    } finally {
      _committing = false;
      // Whatever the handler decided, the stored value is the truth.
      if (mounted && controller.text != widget.path) {
        setState(() => controller.text = widget.path);
      }
    }
  }

  Future<void> _browse() async {
    if (_browsing) return;
    final generation = ++_browseGeneration;
    setState(() => _browsing = true);
    try {
      await Future<void>.sync(widget.onBrowse);
    } catch (error) {
      if (mounted && generation == _browseGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update this path: $error')),
        );
      }
    } finally {
      if (mounted && generation == _browseGeneration) {
        setState(() => _browsing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final textStyle = (widget.isMobile
            ? NightshadeTypography.caption
            : NightshadeTypography.captionSm)
        .copyWith(
      color: widget.path.isEmpty ? colors.textMuted : colors.textPrimary,
    );
    final verticalPadding =
        widget.isMobile ? NightshadeTokens.spaceSm : NightshadeTokens.radiusSm;

    Widget pathContainer = _editable
        ? Container(
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: verticalPadding,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
              border: Border.all(color: colors.border),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: textStyle.copyWith(color: colors.textPrimary),
              maxLines: 1,
              // A path is longer than the box: keep the END visible, which is
              // the part that says which folder this is.
              textAlign: TextAlign.left,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Not set',
                hintStyle: textStyle.copyWith(color: colors.textMuted),
              ),
              onSubmitted: (_) => _commit(),
            ),
          )
        // Read-only: no border, no fill, no placeholder box — this is a label,
        // and dressing it as an input only invites typing that goes nowhere.
        : Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: verticalPadding + 1,
            ),
            child: Text(
              widget.path.isEmpty ? 'Not set' : widget.path,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          );

    final designWidth = widget.isMobile ? 140.0 : 180.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The browse button is the only way to change this path, so it must
        // never be the thing that gets pushed off the edge. When the row is
        // narrower than the design width can afford, fall back to the
        // flexible layout (path shrinks, button stays) instead of holding a
        // fixed 180 px box and overflowing.
        final flexible = widget.flexible ||
            (constraints.hasBoundedWidth &&
                constraints.maxWidth <
                    designWidth + _browseButtonAllowance + _spaceSm);
        return _buildRow(colors, pathContainer, designWidth, flexible);
      },
    );
  }

  /// Width reserved for the trailing browse button (icon + padding + border).
  static const double _browseButtonAllowance = 32;
  static const double _spaceSm = NightshadeTokens.spaceSm;

  Widget _buildRow(
    NightshadeColors colors,
    Widget pathContainer,
    double designWidth,
    bool flexible,
  ) {
    if (!flexible) {
      pathContainer = SizedBox(
        width: designWidth,
        child: pathContainer,
      );
    }

    return Row(
      mainAxisSize: flexible ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (flexible) Expanded(child: pathContainer) else pathContainer,
        const SizedBox(width: NightshadeTokens.spaceSm),
        GestureDetector(
          onTap: _browsing ? null : _browse,
          child: Container(
            padding: EdgeInsets.all(widget.isMobile
                ? NightshadeTokens.spaceSm
                : NightshadeTokens.radiusSm),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
              border: Border.all(color: colors.border),
            ),
            child: _browsing
                ? SizedBox.square(
                    dimension: widget.isMobile
                        ? NightshadeTokens.iconSm
                        : NightshadeTokens.iconXs,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  )
                : Icon(
                    LucideIcons.folderOpen,
                    size: widget.isMobile
                        ? NightshadeTokens.iconSm
                        : NightshadeTokens.iconXs,
                    color: colors.textSecondary,
                  ),
          ),
        ),
      ],
    );
  }
}

/// A clickable link-style button with an icon and label.
