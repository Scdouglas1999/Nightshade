part of '../darkroom_screen.dart';

/// The recipe as an ordered list of step cards.
///
/// Each card carries three separate statements about its step and never lets
/// one stand in for another:
///
///  * what the recipe says — the operation, its version, its stage, and whether
///    it is switched on;
///  * what `validate` says — whether this build registers the operation and
///    whether its parameters are inside their documented ranges;
///  * what the last render DID — applied, off, or skipped with the operation's
///    own reason. A skip reason is always on the card, never behind the
///    expander: `color_calibrate` skipping for want of a catalogue is an
///    explanation the operator has to read, not a failure to hunt for.
class _DarkroomHistoryPanel extends StatefulWidget {
  final DarkroomState state;
  final void Function(int index) onToggle;
  final void Function(int index, String name, Object? value) onParamChanged;

  /// Asks the engine whether the candidate order is legal and, when it is,
  /// commits it. Answers false when the move was refused.
  final Future<bool> Function(int oldIndex, int newIndex) onReorder;

  const _DarkroomHistoryPanel({
    required this.state,
    required this.onToggle,
    required this.onParamChanged,
    required this.onReorder,
  });

  @override
  State<_DarkroomHistoryPanel> createState() => _DarkroomHistoryPanelState();
}

class _DarkroomHistoryPanelState extends State<_DarkroomHistoryPanel> {
  /// Which cards have their parameter controls open, by position in the stack.
  final Set<int> _expanded = <int>{};

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final state = widget.state;
    final steps = state.steps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'History stack',
          subtitle: steps.isEmpty
              ? 'No steps — this renders the linear master'
              : 'Applied top to bottom',
        ),
        if (state.recipeError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NightshadeTokens.spaceMd,
              NightshadeTokens.spaceSm,
              NightshadeTokens.spaceMd,
              0,
            ),
            child: NightshadeAlert(
              severity: NightshadeAlertSeverity.error,
              title: 'This stack does not validate',
              message: state.recipeError!,
              compact: true,
            ),
          ),
        if (state.catalogError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NightshadeTokens.spaceMd,
              NightshadeTokens.spaceSm,
              NightshadeTokens.spaceMd,
              0,
            ),
            child: NightshadeAlert(
              severity: NightshadeAlertSeverity.warning,
              message: state.catalogError!,
              compact: true,
            ),
          ),
        Expanded(
          child: steps.isEmpty
              ? const EmptyState.compact(
                  icon: NightshadeIcons.layers,
                  title: 'Nothing interpreted yet',
                  body:
                      'This recipe carries no operations, so the viewport is '
                      'the linear master itself.',
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
                  itemCount: steps.length,
                  buildDefaultDragHandles: false,
                  // The move is not committed until the engine has accepted the
                  // resulting order, so the list snaps back for the frame the
                  // check takes and then rebuilds in the new order. A move the
                  // engine refuses therefore never appears to have happened.
                  //
                  // onReorderItem, not onReorder: it reports the destination
                  // already adjusted for the removal, which is the index the
                  // controller inserts at.
                  onReorderItem: (oldIndex, newIndex) {
                    widget.onReorder(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) =>
                      _card(context, colors, state, index),
                ),
        ),
      ],
    );
  }

  Widget _card(
    BuildContext context,
    NightshadeColors colors,
    DarkroomState state,
    int index,
  ) {
    final step = state.steps[index];
    final spec = state.catalog?.specFor(step);
    final report = state.reportFor(index);
    final issue = state.issueFor(index);
    final expanded = _expanded.contains(index);

    return Padding(
      // Keyed on the step object, which survives a reorder unchanged, so the
      // list animates the card that moved rather than re-keying every row.
      key: ObjectKey(step),
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
      child: NightshadeCard(
        padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Semantics(
                    label: 'Reorder ${darkroomOpTitle(step.opId)}',
                    child: Padding(
                      padding: const EdgeInsets.only(
                        right: NightshadeTokens.spaceSm,
                      ),
                      child: Icon(
                        NightshadeIcons.move,
                        size: NightshadeTokens.iconSm,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        darkroomOpTitle(step.opId),
                        style: NightshadeTypography.labelStrong.copyWith(
                          color: step.enabled
                              ? colors.textPrimary
                              : colors.textMuted,
                        ),
                      ),
                      const SizedBox(height: NightshadeTokens.spaceXs),
                      Wrap(
                        spacing: NightshadeTokens.spaceXs,
                        runSpacing: NightshadeTokens.spaceXs,
                        children: [
                          _DarkroomTag(
                            label: 'v${step.opVersion}',
                            tooltip:
                                'The operation version this recipe was written '
                                'with. A recipe keeps rendering with its own '
                                'version, so improving an operation never '
                                'changes an existing recipe.',
                          ),
                          if (spec != null)
                            _DarkroomTag(
                              label: spec.stage.label,
                              tooltip: _stageTooltip(spec),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Semantics(
                  label: '${darkroomOpTitle(step.opId)} enabled',
                  child: NightshadeSwitch(
                    value: step.enabled,
                    compact: true,
                    onChanged: (_) => widget.onToggle(index),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            _outcomeLine(colors, step, report),
            if (report?.reason != null) ...[
              const SizedBox(height: NightshadeTokens.spaceXs),
              Text(
                report!.reason!,
                style: NightshadeTypography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
            if (issue != null && !issue.isClean) ...[
              const SizedBox(height: NightshadeTokens.spaceSm),
              NightshadeAlert(
                severity: NightshadeAlertSeverity.error,
                message: _issueMessage(step, issue),
                compact: true,
              ),
            ],
            if (spec != null && spec.params.isNotEmpty) ...[
              const SizedBox(height: NightshadeTokens.spaceSm),
              _expandToggle(colors, step, expanded, index),
              if (expanded) ...[
                const SizedBox(height: NightshadeTokens.spaceSm),
                for (final param in spec.params)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: NightshadeTokens.spaceMd,
                    ),
                    child: _paramControl(colors, index, step, param),
                  ),
              ],
            ] else if (spec == null && state.catalog != null) ...[
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                'This build registers no ${step.opId}@${step.opVersion}, so '
                'its parameters have no documented ranges to draw controls '
                'from. The stored values are left exactly as they are.',
                style: NightshadeTypography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _stageTooltip(DarkroomOpSpec spec) {
    switch (spec.stage) {
      case DarkroomOpStage.linear:
        return 'Emits linear pixels, so it has to run before the stretch. '
            'Dragging it below a stretched step is refused.';
      case DarkroomOpStage.stretched:
        return 'Emits stretched (display-domain) pixels. Everything after it '
            'works on the stretched image.';
      case DarkroomOpStage.unmodelled:
        return 'The registry names this operation\'s stage as '
            '"${spec.stageWire}", which this build does not model, so the '
            'ordering rule for it is whatever the engine says at validation.';
    }
  }

  String _issueMessage(DarkroomStep step, DarkroomStepIssue issue) {
    final engineMessage = issue.error;
    if (!issue.registered) {
      final latest = issue.latestVersion;
      final suffix = latest == null
          ? ''
          : ' The newest version this build registers is v$latest.';
      return 'This build registers no ${step.opId}@${step.opVersion}, so the '
          'render cannot run it.$suffix';
    }
    if (engineMessage != null) return engineMessage;
    return 'The engine refused this step without naming a reason.';
  }

  Widget _outcomeLine(
    NightshadeColors colors,
    DarkroomStep step,
    DarkroomStepReport? report,
  ) {
    final IconData icon;
    final Color tint;
    final String label;
    switch (report?.outcome) {
      case DarkroomStepOutcome.applied:
        icon = NightshadeIcons.check;
        tint = colors.success;
        label = 'Applied by the last render';
      case DarkroomStepOutcome.disabled:
        icon = NightshadeIcons.hidden;
        tint = colors.textMuted;
        label = 'Off — the render skipped it';
      case DarkroomStepOutcome.skipped:
        icon = NightshadeIcons.info;
        tint = colors.warning;
        label = 'Skipped, and here is why';
      case DarkroomStepOutcome.unreported:
        icon = NightshadeIcons.help;
        tint = colors.textMuted;
        label = 'The last render reported nothing for this step';
      case null:
        icon = NightshadeIcons.help;
        tint = colors.textMuted;
        label = step.enabled
            ? 'Not rendered yet'
            : 'Off — nothing has rendered it';
    }
    // Icon AND words, never colour alone: under the red-night palette success,
    // warning and error are all reds, so a badge that carried its meaning in
    // its fill would say nothing at the telescope.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: NightshadeTokens.iconXs, color: tint),
        const SizedBox(width: NightshadeTokens.spaceXs),
        Expanded(
          child: Text(
            label,
            style: NightshadeTypography.captionSm.copyWith(color: tint),
          ),
        ),
      ],
    );
  }

  Widget _expandToggle(
    NightshadeColors colors,
    DarkroomStep step,
    bool expanded,
    int index,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: NightshadeButton(
        label: expanded ? 'Hide parameters' : 'Parameters',
        icon: expanded
            ? NightshadeIcons.chevronUp
            : NightshadeIcons.chevronDown,
        variant: ButtonVariant.ghost,
        size: ButtonSize.small,
        onPressed: () => setState(() {
          if (expanded) {
            _expanded.remove(index);
          } else {
            _expanded.add(index);
          }
        }),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Parameter controls
  // -------------------------------------------------------------------

  /// One control per registry-documented parameter.
  ///
  /// The registry owns the type, the range and the default; nothing here
  /// invents a bound. A parameter whose key is absent from the step renders the
  /// operation's own default and says so, and the key is written only when the
  /// operator moves the control — so improving a default still reaches recipes
  /// that never overrode it.
  Widget _paramControl(
    NightshadeColors colors,
    int index,
    DarkroomStep step,
    DarkroomParamSpec spec,
  ) {
    final present = step.params.containsKey(spec.name);
    final effective = present ? step.params[spec.name] : spec.defaultValue;

    final Widget control;
    switch (spec.kind) {
      case DarkroomParamKind.number:
      case DarkroomParamKind.integer:
        control = _numberControl(colors, index, step, spec, effective);
      case DarkroomParamKind.enumerated:
        control = NightshadeDropdown(
          value: effective is String && spec.allowed.contains(effective)
              ? effective
              : null,
          hint: 'Choose ${spec.name}',
          items: spec.allowed,
          isExpanded: true,
          onChanged: (value) => widget.onParamChanged(index, spec.name, value),
        );
      case DarkroomParamKind.numberArray:
        control = _arrayControl(colors, index, step, spec, effective);
      case DarkroomParamKind.numberList:
      case DarkroomParamKind.unrepresented:
        control = _readOnlyValue(colors, spec, effective);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                spec.name,
                style: NightshadeTypography.labelSm.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (!present)
              _DarkroomTag(
                label: 'default',
                tooltip:
                    'This recipe stores no value for ${spec.name}, so the '
                    'operation reads its own documented default. Moving the '
                    'control writes a value; clearing it hands the parameter '
                    'back to the operation.',
              )
            else if (spec.defaultValue != null)
              Semantics(
                button: true,
                enabled: true,
                child: NightshadeButton(
                  label: 'Use default',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                  onPressed: () =>
                      widget.onParamChanged(index, spec.name, null),
                ),
              ),
          ],
        ),
        if (spec.summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceXs),
            child: Text(
              spec.summary,
              style: NightshadeTypography.captionSm.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        if (!spec.independent)
          Padding(
            padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceXs),
            child: Text(
              'Constrained together with another parameter of this step, so a '
              'value inside its own range can still be refused.',
              style: NightshadeTypography.captionSm.copyWith(
                color: colors.textMuted,
              ),
            ),
          ),
        control,
      ],
    );
  }

  Widget _numberControl(
    NightshadeColors colors,
    int index,
    DarkroomStep step,
    DarkroomParamSpec spec,
    Object? effective,
  ) {
    final isInteger = spec.kind == DarkroomParamKind.integer;
    final value = darkroomNumber(effective);
    final min = spec.min;
    final max = spec.max;

    if (spec.isSliderRanged && value != null && min != null && max != null) {
      final clamped = value.clamp(min, max);
      final span = max - min;
      return Row(
        children: [
          Expanded(
            child: NightshadeSlider(
              value: clamped,
              min: min,
              max: max,
              divisions: isInteger && span <= 64 ? span.round() : null,
              onChanged: (raw) => widget.onParamChanged(
                index,
                spec.name,
                isInteger ? raw.round() : raw,
              ),
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          SizedBox(
            width: 64,
            child: Text(
              _formatNumber(clamped, isInteger),
              textAlign: TextAlign.end,
              style: NightshadeTypography.monoSm.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      );
    }

    return _DarkroomNumberField(
      label: _rangeLabel(spec),
      value: value,
      onChanged: (parsed) => widget.onParamChanged(
        index,
        spec.name,
        parsed == null ? null : (isInteger ? parsed.round() : parsed),
      ),
    );
  }

  Widget _arrayControl(
    NightshadeColors colors,
    int index,
    DarkroomStep step,
    DarkroomParamSpec spec,
    Object? effective,
  ) {
    final length = spec.length;
    if (length == null || length <= 0) {
      return _readOnlyValue(colors, spec, effective);
    }
    final current = <double?>[
      for (var i = 0; i < length; i++)
        effective is List && i < effective.length
            ? darkroomNumber(effective[i])
            : null,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < length; i++) ...[
              if (i > 0) const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: _DarkroomNumberField(
                  label: '#${i + 1}',
                  value: current[i],
                  onChanged: (parsed) {
                    final next = List<double?>.from(current);
                    next[i] = parsed;
                    // The operation validates the array as a whole, so a
                    // partly-typed array is held here rather than written as a
                    // value the operation would refuse.
                    if (next.any((v) => v == null)) return;
                    widget.onParamChanged(index, spec.name, [
                      for (final v in next) v!,
                    ]);
                  },
                ),
              ),
            ],
          ],
        ),
        if (current.any((v) => v == null))
          Padding(
            padding: const EdgeInsets.only(top: NightshadeTokens.spaceXs),
            child: Text(
              'All $length values are needed before this parameter is written.',
              style: NightshadeTypography.captionSm.copyWith(
                color: colors.textMuted,
              ),
            ),
          ),
      ],
    );
  }

  /// A value this build draws no control for, shown as it is stored.
  ///
  /// The alternative — an invented control — would write values the operation
  /// may refuse, and a variable-length curve is edited with a curve editor
  /// rather than a row of boxes.
  Widget _readOnlyValue(
    NightshadeColors colors,
    DarkroomParamSpec spec,
    Object? effective,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: NightshadeTokens.borderRadiusSm,
            border: Border.all(color: colors.border),
          ),
          child: Text(
            effective == null ? 'no value stored' : '$effective',
            style: NightshadeTypography.monoSm.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          'This build\'s editor draws no control for a "${spec.kindWire}" '
          'parameter, so the stored value is shown and left alone.',
          style: NightshadeTypography.captionSm.copyWith(
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }

  static String _rangeLabel(DarkroomParamSpec spec) {
    final min = spec.min;
    final max = spec.max;
    if (min == null || max == null) return spec.name;
    return '${spec.name} (${_formatNumber(min, false)} … '
        '${_formatNumber(max, false)})';
  }

  static String _formatNumber(double value, bool isInteger) {
    if (isInteger) return value.round().toString();
    if (value == value.roundToDouble() && value.abs() < 1e6) {
      return value.toStringAsFixed(0);
    }
    if (value.abs() >= 1e6 || (value != 0 && value.abs() < 1e-3)) {
      return value.toStringAsExponential(2);
    }
    return value.toStringAsFixed(3);
  }
}

/// A numeric field that follows the value it is given without fighting the
/// operator's cursor.
///
/// The controller is seeded once and re-seeded only when the incoming value
/// differs from what the text already parses to — so an undo or a "use default"
/// updates the box, and typing into it does not.
class _DarkroomNumberField extends StatefulWidget {
  final String label;
  final double? value;

  /// Called with the parsed number, or null when the box was emptied — which
  /// hands the parameter back to the operation's own default.
  final ValueChanged<double?> onChanged;

  const _DarkroomNumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_DarkroomNumberField> createState() => _DarkroomNumberFieldState();
}

class _DarkroomNumberFieldState extends State<_DarkroomNumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value == null ? '' : _text(widget.value!),
  );
  bool _unparseable = false;

  @override
  void didUpdateWidget(covariant _DarkroomNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.value;
    final typed = double.tryParse(_controller.text.trim());
    if (incoming != typed) {
      _controller.text = incoming == null ? '' : _text(incoming);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _text(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toStringAsFixed(0);
    }
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    return NightshadeTextField(
      label: widget.label,
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9eE.+\-]')),
      ],
      errorText: _unparseable ? 'Not a number' : null,
      onChanged: (raw) {
        final text = raw.trim();
        if (text.isEmpty) {
          if (_unparseable) setState(() => _unparseable = false);
          widget.onChanged(null);
          return;
        }
        final parsed = double.tryParse(text);
        if (parsed == null || !parsed.isFinite) {
          if (!_unparseable) setState(() => _unparseable = true);
          return;
        }
        if (_unparseable) setState(() => _unparseable = false);
        widget.onChanged(parsed);
      },
    );
  }
}
