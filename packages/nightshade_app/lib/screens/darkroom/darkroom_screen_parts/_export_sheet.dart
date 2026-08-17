part of '../darkroom_screen.dart';

/// Where an export writes, as a seam a test can script.
///
/// Mirrors `stackResultSavePickerProvider`: the production picker is a platform
/// dialog on desktop and a sandbox path plus the share sheet on touch, and
/// neither can run inside a widget test.
typedef DarkroomSavePicker = Future<String?> Function({
  required String suggestedName,
  required List<String> allowedExtensions,
  required String confirmButtonText,
});

Future<String?> _defaultDarkroomSavePicker({
  required String suggestedName,
  required List<String> allowedExtensions,
  required String confirmButtonText,
}) async {
  final target = await chooseExportTarget(
    suggestedName: suggestedName,
    acceptedTypeGroups: [
      XTypeGroup(
        label: allowedExtensions.map((e) => e.toUpperCase()).join(' / '),
        extensions: allowedExtensions,
      ),
    ],
    confirmButtonText: confirmButtonText,
  );
  return target?.path;
}

/// Override point for the Darkroom export destination (tests script this).
final darkroomSavePickerProvider = Provider<DarkroomSavePicker>(
  (ref) => _defaultDarkroomSavePicker,
);

/// Which stage of the stack an export materialises.
enum _DarkroomExportStageKind {
  /// The master's own pixels. The recipe still travels with the file as
  /// provenance, recorded as not applied.
  linear,

  /// The stack replayed through one step — a post-gradient or starless master,
  /// rendered on demand rather than stored.
  afterStep,

  /// The whole stack.
  finalStack;

  /// The wire token the export entry point reads.
  String get wire {
    switch (this) {
      case _DarkroomExportStageKind.linear:
        return 'linear';
      case _DarkroomExportStageKind.afterStep:
        return 'afterStep';
      case _DarkroomExportStageKind.finalStack:
        return 'final';
    }
  }
}

/// A file format an export can write.
enum _DarkroomExportFormat {
  fits,
  png,
  jpeg,
  tiff;

  String get wire => name;

  String get label {
    switch (this) {
      case _DarkroomExportFormat.fits:
        return 'FITS';
      case _DarkroomExportFormat.png:
        return 'PNG';
      case _DarkroomExportFormat.jpeg:
        return 'JPEG';
      case _DarkroomExportFormat.tiff:
        return 'TIFF';
    }
  }

  /// The extensions the save picker offers for this format.
  List<String> get extensions {
    switch (this) {
      case _DarkroomExportFormat.fits:
        return const ['fits', 'fit'];
      case _DarkroomExportFormat.png:
        return const ['png'];
      case _DarkroomExportFormat.jpeg:
        return const ['jpg', 'jpeg'];
      case _DarkroomExportFormat.tiff:
        return const ['tif', 'tiff'];
    }
  }

  /// True when the format quantises the engine's `F32` samples into 8/16-bit
  /// integers, which is what needs a display mapping to be meaningful.
  bool get isRaster => this != _DarkroomExportFormat.fits;
}

/// Whether the pixels a chosen stage produces have left the linear domain.
enum _DarkroomStageDomain {
  /// Still linear ADU: no display mapping, so a raster of it is refused unless
  /// the operator asks for the engine's own screen transfer.
  linear,

  /// A stretched operation has run, so the samples already carry a display
  /// mapping and a raster is a faithful quantisation of them.
  stretched,

  /// This build cannot say which — the operation catalogue is missing, or the
  /// stack carries an operation whose stage this build does not model. Treated
  /// as linear, because inventing a mapping is the failure this whole path
  /// exists to prevent.
  undetermined,
}

/// The export sheet: which stage, which format, and the rules stated where the
/// operator can read them.
///
/// **The refusal is a choice, never a silent stretch.** The engine refuses a
/// PNG/JPEG/TIFF of a still-linear stage, because linear ADU has no display
/// mapping. This sheet shows those formats disabled with that sentence, and one
/// switch turns the engine's own auto stretch on and enables them. Nothing here
/// stretches anything by itself, and the reply names the transfer that was
/// applied.
class _DarkroomExportSheet extends ConsumerStatefulWidget {
  final int recipeId;
  final String recipeName;
  final String baseMasterPath;
  final RecipeAuthor author;
  final List<DarkroomStep> steps;
  final DarkroomCatalog? catalog;
  final List<DarkroomStepReport> reports;

  /// The catalogue stars the editor lends `color_calibrate` on every render.
  /// The export lends the same ones, or the colour step would record itself
  /// skipped for want of a catalogue the editor plainly had.
  final List<Map<String, dynamic>> catalogStars;

  const _DarkroomExportSheet({
    required this.recipeId,
    required this.recipeName,
    required this.baseMasterPath,
    required this.author,
    required this.steps,
    required this.catalog,
    required this.reports,
    required this.catalogStars,
  });

  /// Show the sheet over [context].
  static Future<void> show(
    BuildContext context, {
    required int recipeId,
    required String recipeName,
    required String baseMasterPath,
    required RecipeAuthor author,
    required List<DarkroomStep> steps,
    required DarkroomCatalog? catalog,
    required List<DarkroomStepReport> reports,
    required List<Map<String, dynamic>> catalogStars,
  }) {
    return showDialog<void>(
      context: context,
      // A render is inside the engine while this is up; dismissing the barrier
      // would leave it running with nothing left to report its outcome to.
      barrierDismissible: false,
      builder: (_) => _DarkroomExportSheet(
        recipeId: recipeId,
        recipeName: recipeName,
        baseMasterPath: baseMasterPath,
        author: author,
        steps: steps,
        catalog: catalog,
        reports: reports,
        catalogStars: catalogStars,
      ),
    );
  }

  @override
  ConsumerState<_DarkroomExportSheet> createState() =>
      _DarkroomExportSheetState();
}

class _DarkroomExportSheetState extends ConsumerState<_DarkroomExportSheet> {
  _DarkroomExportStageKind _stageKind = _DarkroomExportStageKind.finalStack;

  /// The step an `afterStep` export stops at. Null until one is chosen.
  int? _afterStep;

  _DarkroomExportFormat _format = _DarkroomExportFormat.fits;

  /// Whether the 8/16-bit files are rendered through the engine's own auto
  /// stretch. Off by default: turning it on is the operator saying they want a
  /// display rendering rather than the data.
  bool _screenTransfer = false;

  /// True while an export is inside the engine.
  bool _exporting = false;

  /// The id the running export is cancellable under.
  String? _renderId;

  /// True once a stop has been asked for and before the export answers.
  bool _cancelRequested = false;

  /// What the last export wrote, in the words the reply gave.
  String? _result;

  /// Why the last export produced no file, when it was stopped rather than
  /// failed.
  String? _stopped;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final domain = _domain();
    final rasterAllowed =
        domain == _DarkroomStageDomain.stretched || _screenTransfer;

    return NightshadeDialog(
      title: 'Export "${widget.recipeName}"',
      icon: NightshadeIcons.download,
      width: 640,
      closeEnabled: !_exporting,
      actions: [
        if (_exporting)
          NightshadeButton(
            label: _cancelRequested ? 'Stopping…' : 'Stop',
            icon: NightshadeIcons.stop,
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
            onPressed: _cancelRequested ? null : _stop,
          )
        else
          NightshadeButton(
            label: 'Close',
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(context).pop(),
          ),
        NightshadeButton(
          label: 'Export',
          icon: NightshadeIcons.download,
          size: ButtonSize.small,
          isLoading: _exporting,
          onPressed: _exporting || !_canExport(rasterAllowed) ? null : _export,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _stagePicker(colors),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _formatPicker(colors, domain, rasterAllowed),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _provenanceNote(colors),
          if (_stopped != null) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            NightshadeAlert(
              severity: NightshadeAlertSeverity.info,
              message: _stopped!,
              compact: true,
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            NightshadeAlert(
              severity: NightshadeAlertSeverity.success,
              title: 'Written',
              message: _result!,
              compact: true,
            ),
          ],
          if (_exporting) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            NightshadeProgressBar(
              // The engine reports no fraction for an export, so the bar is
              // indeterminate rather than inventing progress.
              value: 0.0,
              indeterminate: true,
              style: NightshadeProgressStyle.standard,
              state: NightshadeProgressState.normal,
              label: _cancelRequested
                  ? 'Stopping at the next step boundary…'
                  : 'Rendering the ${_stageLabel()} at full resolution…',
            ),
          ],
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Pickers
  // -----------------------------------------------------------------------

  Widget _stagePicker(NightshadeColors colors) {
    final hasSteps = widget.steps.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Stage',
          style: NightshadeTypography.labelSm.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Wrap(
          spacing: NightshadeTokens.spaceXs,
          runSpacing: NightshadeTokens.spaceXs,
          children: [
            NightshadeChip(
              label: 'Linear master',
              selected: _stageKind == _DarkroomExportStageKind.linear,
              onTap: () => _setStage(_DarkroomExportStageKind.linear),
            ),
            Tooltip(
              message: hasSteps
                  ? 'Replay the stack through one step and write what it '
                      'produced.'
                  : 'This recipe carries no steps, so there is no step to stop '
                      'after. Add one, or export the linear master.',
              child: NightshadeChip(
                label: 'After a step',
                selected: _stageKind == _DarkroomExportStageKind.afterStep,
                enabled: hasSteps,
                onTap: hasSteps
                    ? () => _setStage(_DarkroomExportStageKind.afterStep)
                    : null,
              ),
            ),
            NightshadeChip(
              label: 'Final',
              selected: _stageKind == _DarkroomExportStageKind.finalStack,
              onTap: () => _setStage(_DarkroomExportStageKind.finalStack),
            ),
          ],
        ),
        if (_stageKind == _DarkroomExportStageKind.afterStep) ...[
          const SizedBox(height: NightshadeTokens.spaceSm),
          NightshadeDropdown(
            value: _afterStep == null ? null : _stepOptionFor(_afterStep!),
            hint: 'Choose the step to stop after',
            isExpanded: true,
            items: [
              for (var i = 0; i < widget.steps.length; i++) _stepOptionFor(i),
            ],
            onChanged: _exporting
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _afterStep = _stepIndexOf(value);
                      _result = null;
                      _stopped = null;
                      // A different cut is a different stage; see [_setStage].
                      _screenTransfer = false;
                    });
                  },
          ),
        ],
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          _stageExplanation(),
          style: NightshadeTypography.captionSm.copyWith(
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _formatPicker(
    NightshadeColors colors,
    _DarkroomStageDomain domain,
    bool rasterAllowed,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Format',
          style: NightshadeTypography.labelSm.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Wrap(
          spacing: NightshadeTokens.spaceXs,
          runSpacing: NightshadeTokens.spaceXs,
          children: [
            for (final format in _DarkroomExportFormat.values)
              Tooltip(
                message: format.isRaster && !rasterAllowed
                    ? _rasterRefusal(domain)
                    : _formatNote(format),
                child: NightshadeChip(
                  label: format.label,
                  selected: _format == format,
                  enabled: !format.isRaster || rasterAllowed,
                  onTap: !format.isRaster || rasterAllowed
                      ? () => setState(() {
                            _format = format;
                            _result = null;
                            _stopped = null;
                          })
                      : null,
                ),
              ),
          ],
        ),
        if (!rasterAllowed) ...[
          const SizedBox(height: NightshadeTokens.spaceSm),
          // The refusal is on screen, not only in a tooltip: a disabled chip
          // whose reason lives behind a hover says nothing on a touch screen.
          NightshadeAlert(
            severity: NightshadeAlertSeverity.info,
            title: 'PNG, JPEG and TIFF are unavailable for this stage',
            message: _rasterRefusal(domain),
            compact: true,
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          NightshadeSwitchRow(
            label: 'Render the 8/16-bit files through the auto stretch',
            subtitle:
                'Uses the engine\'s own auto stretch to give these linear '
                'pixels a display mapping. The recipe is not changed and the '
                'reply names the transfer that was applied — a FITS export of '
                'the same stage still carries the linear data.',
            value: _screenTransfer,
            onChanged: _exporting
                ? null
                : (value) => setState(() {
                      _screenTransfer = value;
                      _result = null;
                      _stopped = null;
                    }),
          ),
        ],
      ],
    );
  }

  Widget _provenanceNote(NightshadeColors colors) {
    return Text(
      'Every export carries this recipe: a FITS gets HISTORY cards naming each '
      'step and its outcome plus the recipe\'s own canonical JSON, and a '
      '.nsrecipe sidecar is written beside whichever file is chosen so the '
      'recipe survives outside the database.',
      style: NightshadeTypography.captionSm.copyWith(color: colors.textMuted),
    );
  }

  // -----------------------------------------------------------------------
  // The stage / domain rules
  // -----------------------------------------------------------------------

  void _setStage(_DarkroomExportStageKind kind) {
    setState(() {
      _stageKind = kind;
      _result = null;
      _stopped = null;
      // The rule is per stage: whether these pixels need a display mapping is a
      // fact about the stage that was chosen, so the choice is re-made rather
      // than carried across from a different one.
      _screenTransfer = false;
      if (kind == _DarkroomExportStageKind.afterStep && _afterStep == null) {
        _afterStep = widget.steps.isEmpty ? null : widget.steps.length - 1;
      }
    });
  }

  String _stepOptionFor(int index) =>
      '${index + 1}. ${darkroomOpTitle(widget.steps[index].opId)}';

  int? _stepIndexOf(String option) {
    for (var i = 0; i < widget.steps.length; i++) {
      if (_stepOptionFor(i) == option) return i;
    }
    return null;
  }

  String _stageLabel() {
    switch (_stageKind) {
      case _DarkroomExportStageKind.linear:
        return 'linear master';
      case _DarkroomExportStageKind.afterStep:
        final index = _afterStep;
        return index == null
            ? 'chosen step'
            : 'stack through step ${index + 1}';
      case _DarkroomExportStageKind.finalStack:
        return 'final stack';
    }
  }

  String _stageExplanation() {
    switch (_stageKind) {
      case _DarkroomExportStageKind.linear:
        return 'The master\'s own pixels, untouched. The recipe rides along as '
            'provenance and is recorded as not applied.';
      case _DarkroomExportStageKind.afterStep:
        return 'The stack replayed from the start through the chosen step. '
            'Steps below it are not applied.';
      case _DarkroomExportStageKind.finalStack:
        return 'Every enabled step, at the master\'s full resolution — not the '
            'pyramid level the viewport renders from.';
    }
  }

  /// The last index a chosen stage renders through, or null when the stage
  /// applies no step at all.
  int? _cutIndex() {
    switch (_stageKind) {
      case _DarkroomExportStageKind.linear:
        return null;
      case _DarkroomExportStageKind.afterStep:
        return _afterStep;
      case _DarkroomExportStageKind.finalStack:
        return widget.steps.isEmpty ? null : widget.steps.length - 1;
    }
  }

  /// Whether the chosen stage's pixels have left the linear domain.
  ///
  /// The engine decides this from its own render report — an APPLIED step whose
  /// operation emits stretched pixels. This mirrors that rule from the recipe
  /// and the catalogue so the sheet can state it BEFORE the export runs. When
  /// the catalogue is missing, or the stack carries an operation this build does
  /// not register, the answer is [_DarkroomStageDomain.undetermined] rather than
  /// a guess.
  _DarkroomStageDomain _domain() {
    final cut = _cutIndex();
    if (cut == null) return _DarkroomStageDomain.linear;
    final catalog = widget.catalog;
    if (catalog == null) return _DarkroomStageDomain.undetermined;

    var undetermined = false;
    for (var i = 0; i <= cut && i < widget.steps.length; i++) {
      final step = widget.steps[i];
      if (!step.enabled) continue;
      final spec = catalog.specFor(step);
      if (spec == null || spec.stage == DarkroomOpStage.unmodelled) {
        undetermined = true;
        continue;
      }
      if (spec.stage != DarkroomOpStage.stretched) continue;
      // A step the last render skipped changed nothing, so it left the pixels
      // where they were. An unreported step is not evidence either way, so it
      // counts as having run — the direction that keeps a linear file from
      // being quantised as if it had a display mapping.
      final report = _reportFor(i);
      if (report?.outcome == DarkroomStepOutcome.skipped) continue;
      return _DarkroomStageDomain.stretched;
    }
    return undetermined
        ? _DarkroomStageDomain.undetermined
        : _DarkroomStageDomain.linear;
  }

  DarkroomStepReport? _reportFor(int index) {
    for (final report in widget.reports) {
      if (report.index == index) return report;
    }
    return null;
  }

  String _rasterRefusal(_DarkroomStageDomain domain) {
    switch (domain) {
      case _DarkroomStageDomain.stretched:
        return 'These pixels already carry a display mapping.';
      case _DarkroomStageDomain.linear:
        return 'The ${_stageLabel()} is still linear ADU and has no display '
            'mapping, so quantising it into 8 or 16 bits would show almost '
            'nothing. Export FITS to keep the linear pixels, or switch on the '
            'auto stretch below to render the 8/16-bit files through the '
            'engine\'s own transfer.';
      case _DarkroomStageDomain.undetermined:
        return widget.catalog == null
            ? 'The operation catalogue could not be read, so this build cannot '
                'tell whether the ${_stageLabel()} has a display mapping. '
                'FITS keeps whatever the pixels are; switch on the auto '
                'stretch to render the 8/16-bit files through the engine\'s '
                'own transfer.'
            : 'This stack carries an operation whose stage this build does not '
                'model, so whether the ${_stageLabel()} has a display '
                'mapping is unstated. FITS keeps whatever the pixels are; '
                'switch on the auto stretch to render the 8/16-bit files '
                'through the engine\'s own transfer.';
    }
  }

  String _formatNote(_DarkroomExportFormat format) {
    switch (format) {
      case _DarkroomExportFormat.fits:
        return 'The engine\'s own F32 samples, with the master\'s astrometry '
            'and the recipe in HISTORY cards. Always available, at every '
            'stage.';
      case _DarkroomExportFormat.png:
        return '16-bit PNG, quantised from the render\'s samples.';
      case _DarkroomExportFormat.jpeg:
        return '8-bit JPEG at the engine\'s documented default quality; the '
            'reply names the value used.';
      case _DarkroomExportFormat.tiff:
        return '16-bit TIFF, quantised from the render\'s samples.';
    }
  }

  bool _canExport(bool rasterAllowed) {
    if (_stageKind == _DarkroomExportStageKind.afterStep &&
        _afterStep == null) {
      return false;
    }
    if (_format.isRaster && !rasterAllowed) return false;
    return true;
  }

  // -----------------------------------------------------------------------
  // Running the export
  // -----------------------------------------------------------------------

  /// The file-name fragment for an `afterStep` export.
  ///
  /// Reads the chosen step itself, so the name says which operation the file
  /// stopped after. The Export button stays disabled until a step is chosen, so
  /// the unchosen case never reaches a file name; if it somehow did, the
  /// fragment says "afterStep" rather than naming a step nobody picked.
  String _afterStepSlug() {
    final index = _afterStep;
    if (index == null || index >= widget.steps.length) return 'afterStep';
    return 'step${index + 1}-${widget.steps[index].opId}';
  }

  String _suggestedFileName() {
    final stage = switch (_stageKind) {
      _DarkroomExportStageKind.linear => 'linear',
      _DarkroomExportStageKind.afterStep => _afterStepSlug(),
      _DarkroomExportStageKind.finalStack => 'final',
    };
    final base = sanitizeExportFileName(
      widget.recipeName.isEmpty
          ? 'recipe-${widget.recipeId}'
          : widget.recipeName,
    ).replaceAll(' ', '_');
    return '$base-$stage.${_format.extensions.first}';
  }

  Future<void> _export() async {
    if (_exporting) return;
    final picker = ref.read(darkroomSavePickerProvider);
    final darkroom = ref.read(darkroomSeamProvider);

    setState(() {
      _exporting = true;
      _cancelRequested = false;
      _result = null;
      _stopped = null;
    });
    final renderId = 'darkroom-export-${widget.recipeId}-'
        '${DateTime.now().microsecondsSinceEpoch}';
    _renderId = renderId;

    try {
      final outputPath = await picker(
        suggestedName: _suggestedFileName(),
        allowedExtensions: _format.extensions,
        confirmButtonText: 'Export ${_format.label}',
      );
      if (outputPath == null || !mounted) return;

      final reply = await darkroom.renderExport(
        recipeJson: encodeDarkroomRecipe(
          recipeId: widget.recipeId,
          baseMasterRef: widget.baseMasterPath,
          author: widget.author,
          steps: widget.steps,
        ),
        args: {
          'masterPath': widget.baseMasterPath,
          'renderId': renderId,
          'stage': {
            'kind': _stageKind.wire,
            if (_stageKind == _DarkroomExportStageKind.afterStep)
              'index': _afterStep,
          },
          'outputs': [
            {'format': _format.wire, 'path': outputPath},
          ],
          // Named rather than derived: the engine only derives a sidecar path
          // from a FITS output, and a raster export with no sidecar would leave
          // the recipe behind in the database alone.
          'sidecarPath': '$outputPath.nsrecipe',
          'writeSidecar': true,
          'screenTransfer': _screenTransfer,
          if (widget.catalogStars.isNotEmpty)
            'catalogStars': widget.catalogStars,
        },
      );
      if (!mounted) return;
      setState(() => _result = _describeReply(reply, outputPath));
      if (!context.mounted) return;
      NightshadeToastHelper.show(
        context: context,
        message: 'Exported ${p.basename(outputPath)}',
        severity: NightshadeAlertSeverity.success,
      );
      await revealExportedFile(
        context,
        outputPath,
        subject: 'Nightshade Darkroom export',
      );
    } on DarkroomCancelledOutcome catch (cancelled) {
      if (!mounted) return;
      // The engine honours a stop before it writes, so a stopped export leaves
      // no half-written file behind.
      setState(
        () => _stopped =
            'The export was stopped during ${cancelled.phase}. No file was '
                'written.',
      );
    } on DarkroomSeamException catch (error) {
      if (!mounted) return;
      await _reportFailure(error.message);
    } catch (error) {
      if (!mounted) return;
      await _reportFailure('$error');
    } finally {
      _renderId = null;
      if (mounted) {
        setState(() {
          _exporting = false;
          _cancelRequested = false;
        });
      }
    }
  }

  Future<void> _reportFailure(String raw) async {
    // The same humaniser the stack-and-share flow uses: the bridge's stringified
    // union is not a sentence, and the operator reads the payload inside it.
    final failure = describeStackShareFailure(raw);
    if (!context.mounted) return;
    await ErrorDialog.show(
      context,
      title: 'Export failed',
      message: failure.nextStep == null
          ? failure.message
          : '${failure.message}\n\n${failure.nextStep}',
      technicalDetails: failure.technical,
    );
  }

  /// Ask the running export to stop.
  ///
  /// Cooperative, like the preview render: the engine honours it at the next
  /// step boundary or pixel-budget poll, so the button says "Stopping…" until
  /// the export answers.
  Future<void> _stop() async {
    final renderId = _renderId;
    if (renderId == null || _cancelRequested) return;
    setState(() => _cancelRequested = true);
    try {
      await ref.read(darkroomSeamProvider).cancel({
        'op': 'cancel',
        'renderId': renderId,
      });
    } on DarkroomSeamException catch (error) {
      if (!mounted) return;
      setState(() {
        _cancelRequested = false;
        _stopped = 'The stop request did not reach the export: '
            '${error.message}';
      });
    }
  }

  /// What the reply says was written, in its own numbers.
  String _describeReply(Map<String, dynamic> reply, String outputPath) {
    final lines = <String>[];
    final outputs = reply['outputs'];
    if (outputs is List && outputs.isNotEmpty) {
      for (final entry in outputs) {
        if (entry is! Map<String, dynamic>) continue;
        final format = entry['format'];
        final path = entry['path'];
        final bytes = entry['bytes'];
        final width = entry['width'];
        final height = entry['height'];
        final clamped = entry['clampedSamples'];
        final quality = entry['quality'];
        lines.add(
          '${format ?? 'file'}: ${path ?? outputPath}'
          '${width != null && height != null ? ' — $width×$height' : ''}'
          '${bytes is int ? ', ${_bytes(bytes)}' : ''}'
          '${quality != null ? ', quality $quality' : ''}'
          '${clamped is int && clamped > 0 ? ', $clamped samples clamped' : ''}',
        );
      }
    } else {
      lines.add(
        'The engine reported no output entry, so what landed at $outputPath '
        'is unstated.',
      );
    }

    final sidecar = reply['sidecarPath'];
    final skipped = reply['sidecarSkippedReason'];
    if (sidecar is String && sidecar.isNotEmpty) {
      lines.add('Recipe sidecar: $sidecar');
    } else if (skipped is String && skipped.isNotEmpty) {
      lines.add('No recipe sidecar: $skipped');
    }

    final domain = reply['sourceDomain'];
    if (domain is String && domain.isNotEmpty) {
      lines.add('Source pixels: $domain');
    }
    final transfer = reply['screenTransfer'];
    lines.add(
      transfer == null
          ? 'No screen transfer was applied.'
          : 'The engine\'s auto stretch was applied to the 8/16-bit files '
              'only; the recipe was not changed.',
    );
    final fingerprint = reply['recipeFingerprint'];
    if (fingerprint is String && fingerprint.isNotEmpty) {
      lines.add('Recipe fingerprint: $fingerprint');
    }
    return lines.join('\n');
  }

  static String _bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
