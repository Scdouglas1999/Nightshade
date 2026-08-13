import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XTypeGroup;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
// Reaches the seam directly: the per-channel colour STF (_autoStretchColor)
// that matches the native OSC capture curve is not re-exported through the
// core barrel.
// ignore: implementation_imports
import 'package:nightshade_core/src/services/stacking_engine_seam.dart'
    show BridgeStackingEngineSeam, StackingEngineSeam;
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../widgets/astro_image_viewer.dart';

/// Signature of the save-file picker used by the Stack Result viewer to choose
/// an export destination.
///
/// Defaults to [_defaultSavePicker]; injected via
/// [stackResultSavePickerProvider] so widget tests can stub the picker without
/// invoking platform channels.
typedef StackResultSavePicker = Future<String?> Function({
  required String dialogTitle,
  required String fileName,
  required List<String> allowedExtensions,
});

/// Resolve the export destination for [fileName].
///
/// Goes through [chooseExportTarget] rather than `FilePicker.saveFile`: on
/// Android/iOS `file_picker` throws `ArgumentError('Bytes are required on
/// Android & iOS when saving a file.')` when called without `bytes:`, which
/// dead-ended all four actions in the phone-only overflow menu (the exported
/// bytes don't exist yet at picker time — the service renders them into the
/// chosen path). Desktop still gets the native save dialog; on touch the path
/// is inside the app sandbox and the caller finishes with the share sheet.
Future<String?> _defaultSavePicker({
  required String dialogTitle,
  required String fileName,
  required List<String> allowedExtensions,
}) async {
  final target = await chooseExportTarget(
    suggestedName: fileName,
    acceptedTypeGroups: [
      XTypeGroup(
        label: allowedExtensions.map((e) => e.toUpperCase()).join(' / '),
        extensions: allowedExtensions,
      ),
    ],
    confirmButtonText: dialogTitle,
  );
  return target?.path;
}

/// Signature of the OS share-sheet call used after an export completes.
///
/// Defaults to [Share.shareXFiles]; injected via [stackResultShareProvider] so
/// widget tests can assert the share without invoking the platform plugin.
typedef StackResultShare = Future<void> Function(
  String filePath, {
  required String text,
});

Future<void> _defaultShare(String filePath, {required String text}) async {
  await Share.shareXFiles([XFile(filePath)], text: text);
}

/// Override point for the save-file picker (tests stub this).
final stackResultSavePickerProvider =
    Provider<StackResultSavePicker>((ref) => _defaultSavePicker);

/// Override point for the OS share-sheet call (tests stub this).
final stackResultShareProvider =
    Provider<StackResultShare>((ref) => _defaultShare);

/// The stacking-engine seam used to auto-stretch the in-memory integrated
/// buffer for display.
///
/// Production uses [BridgeStackingEngineSeam]: a 1-channel (mono) buffer goes
/// through the native STF (`apiAutoStretchImage`), while a 3-channel
/// interleaved-RGB16 buffer goes through the seam's per-channel colour STF.
/// Exposed as a provider so widget tests can stub the auto-stretch without
/// loading the native dynamic library.
final stackResultStretchEngineProvider =
    Provider<StackingEngineSeam>((ref) => const BridgeStackingEngineSeam());

/// The display stretch applied to the integrated buffer in the viewer.
///
/// The viewer offers the two renderings it can produce *honestly* from the
/// retained u16 buffer: a MAD-based PixInsight Screen-Transfer-Function (STF)
/// auto-stretch, and a linear (unstretched) min/max mapping. Both honour the
/// buffer's channel layout — a mono plane renders to grayscale, an interleaved
/// RGB16 (OSC) integration renders in colour with a per-channel stretch. We
/// deliberately do not advertise stretch methods the in-memory engine cannot
/// apply — surfacing a control that silently produced identical output would
/// violate the project's "no silent fallback" rule.
enum StackViewerStretch {
  /// STF auto-stretch: the native single-channel STF
  /// ([ImagingBackend.autoStretchImage]) for a mono buffer, or the
  /// stacking-engine seam's per-channel colour STF for an interleaved-RGB16
  /// buffer.
  autoStf,

  /// Linear min/max normalisation: grayscale for a mono buffer, per-channel
  /// colour for an interleaved-RGB16 buffer.
  linear,
}

/// Stack Result Viewer screen (component C9).
///
/// Loads a persisted [StackAndShareResult] by [resultId] and renders its
/// integrated image with an [AstroImageViewer], a stats panel, and export /
/// share actions. The displayed pixels come from the live orchestrator state
/// ([stackAndShareProvider]) when this is the result that was just produced (so
/// the in-memory mono buffer is available for re-stretching); the persisted
/// [StackAndShareResult] row supplies the provenance stats and the fallback
/// path-on-disk for re-sharing a previously exported master.
///
/// When no result matches [resultId] the screen shows an [EmptyState] rather
/// than a blank canvas (errors are a feature).
class StackResultScreen extends ConsumerStatefulWidget {
  /// Database id of the [StackAndShareResult] to display, typically supplied via
  /// the `?id=` query parameter on the `/stack-result` route.
  final int resultId;

  const StackResultScreen({super.key, required this.resultId});

  @override
  ConsumerState<StackResultScreen> createState() => _StackResultScreenState();
}

class _StackResultScreenState extends ConsumerState<StackResultScreen> {
  StackViewerStretch _stretch = StackViewerStretch.autoStf;

  /// The RGBA buffer currently shown in the viewer. Recomputed from the mono
  /// buffer whenever [_stretch] changes. Null until the first render produces
  /// it (or when no mono buffer is available).
  Uint8List? _displayRgba;

  /// The mono buffer the current [_displayRgba] was rendered from. Tracked so we
  /// only recompute when the source actually changes.
  Uint16List? _renderedFrom;

  /// The (buffer, stretch) pair a render is currently in flight for, so a
  /// rebuild while it runs does not queue a second pass over the same pixels.
  Uint16List? _renderingBuffer;
  StackViewerStretch? _renderingStretch;

  /// Bumped per scheduled render; a result whose generation is stale is dropped
  /// rather than painted over a newer one.
  int _renderGeneration = 0;

  /// True while an export/share operation is running, used to disable the
  /// action buttons so a user cannot launch two save pickers at once.
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final resultAsync = ref.watch(stackResultViewerProvider(widget.resultId));
    final previewAsync = ref.watch(
      stackResultPreviewProvider(widget.resultId),
    );
    final liveState = ref.watch(stackAndShareProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: resultAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (error, _) => _buildNotFound(context, error),
        data: (result) => _buildLoaded(
          context,
          colors,
          result,
          liveState,
          previewAsync,
        ),
      ),
    );
  }

  Widget _buildNotFound(BuildContext context, Object error) {
    final isMissing =
        (error is ServerError && error.code == 'stack_result_not_found') ||
            (error is StateError &&
                error.toString().contains('No stacked result found'));
    return EmptyState(
      icon: NightshadeIcons.imageOff,
      title: isMissing ? 'Result not found' : 'Could not load result',
      body: isMissing
          ? 'No stacked result exists for id ${widget.resultId}. It may have '
              'been deleted.'
          : _resultLoadErrorMessage(error),
    );
  }

  String _resultLoadErrorMessage(Object error) {
    final message = _cleanErrorMessage(error);
    return message.isEmpty
        ? 'The imaging host could not be reached. Try again when the '
            'connection is available.'
        : message;
  }

  Widget _buildLoaded(
    BuildContext context,
    NightshadeColors colors,
    StackAndShareResult result,
    StackAndShareState liveState,
    AsyncValue<Uint8List?> previewAsync,
  ) {
    // The in-memory integrated buffer is only available when this screen is
    // showing the run that just completed (the live orchestrator retains it).
    // Match by id so a stale buffer from a different run is never used. The
    // buffer is a single mono plane for a mono stack and interleaved RGB16 for
    // an OSC stack — [channels] selects how the stretch interprets it.
    final isOwnRun = liveState.result?.id == result.id;
    final mono = isOwnRun ? liveState.resultMono : null;
    final channels = isOwnRun ? liveState.resultChannels : result.channels;
    final durableRgba = previewAsync.when(
      data: (value) => value,
      loading: () => null,
      error: (_, __) => null,
    );
    final rgba = _resolveDisplayRgba(
      result,
      liveState,
      mono,
      channels,
      durableRgba,
    );

    final subtitle = '${result.framesStacked} frame'
        '${result.framesStacked == 1 ? '' : 's'} · '
        '${formatHms(result.integrationSecs)} integration';

    return Column(
      children: [
        ScreenHeader(
          title: result.targetName ?? 'Stacked Result',
          subtitle: subtitle,
          icon: NightshadeIcons.image,
          trailing: _buildActions(context, colors, result, rgba),
        ),
        Expanded(
          // [Responsive.isMobile] is device-class aware: on a mobile OS it keys
          // off the SHORTEST side, so a landscape phone or foldable cover screen
          // (e.g. the Galaxy Z Fold 6 cover at 905x369 — wide long edge, short
          // 369 edge) resolves to the scrollable mobile layout instead of the
          // desktop viewer+320px split, whose fixed side panel would crowd the
          // viewer at that height. On desktop the live window width still drives
          // the split as before.
          child: Responsive.isMobile(context)
              ? _buildMobileLayout(
                  context,
                  colors,
                  result,
                  rgba,
                  mono,
                  previewAsync,
                )
              : _buildDesktopLayout(
                  context,
                  colors,
                  result,
                  rgba,
                  mono,
                  previewAsync,
                ),
        ),
      ],
    );
  }

  Widget _buildActions(
    BuildContext context,
    NightshadeColors colors,
    StackAndShareResult result,
    Uint8List? rgba,
  ) {
    final canExport = !_exporting && rgba != null;

    // On a phone the four export buttons cannot share the ScreenHeader's Row
    // with the title without overflowing the ~430 px width, so collapse them
    // into a single overflow menu. The header trailing then stays narrow in
    // both orientations. Wider layouts keep the inline button row.
    if (Responsive.isPhone(context)) {
      return PopupMenuButton<_StackResultAction>(
        icon: Icon(NightshadeIcons.share, color: colors.textPrimary),
        tooltip: 'Export / share',
        enabled: !_exporting,
        onSelected: (action) {
          switch (action) {
            case _StackResultAction.png:
              if (rgba != null) _export(result, rgba, ShareExportFormat.png);
            case _StackResultAction.jpeg:
              if (rgba != null) _export(result, rgba, ShareExportFormat.jpeg);
            case _StackResultAction.shareCard:
              if (rgba != null) {
                _export(result, rgba, ShareExportFormat.shareCard);
              }
            case _StackResultAction.astroBin:
              _exportAstroBin(result);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _StackResultAction.png,
            enabled: canExport,
            child: const _ActionMenuRow(
              icon: LucideIcons.fileImage,
              label: 'Export PNG',
            ),
          ),
          PopupMenuItem(
            value: _StackResultAction.jpeg,
            enabled: canExport,
            child: const _ActionMenuRow(
              icon: NightshadeIcons.image,
              label: 'Export JPEG',
            ),
          ),
          PopupMenuItem(
            value: _StackResultAction.shareCard,
            enabled: canExport,
            child: const _ActionMenuRow(
              icon: NightshadeIcons.share,
              label: 'Share Card',
            ),
          ),
          const PopupMenuItem(
            value: _StackResultAction.astroBin,
            child: _ActionMenuRow(
              icon: NightshadeIcons.file,
              label: 'AstroBin',
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: NightshadeTokens.spaceSm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        NightshadeButton(
          label: 'Export PNG',
          icon: LucideIcons.fileImage,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          isLoading: _exporting,
          onPressed: canExport
              ? () => _export(result, rgba, ShareExportFormat.png)
              : null,
        ),
        NightshadeButton(
          label: 'Export JPEG',
          icon: NightshadeIcons.image,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: canExport
              ? () => _export(result, rgba, ShareExportFormat.jpeg)
              : null,
        ),
        NightshadeButton(
          label: 'Share Card',
          icon: NightshadeIcons.share,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: canExport
              ? () => _export(result, rgba, ShareExportFormat.shareCard)
              : null,
        ),
        NightshadeButton(
          label: 'AstroBin',
          icon: NightshadeIcons.file,
          size: ButtonSize.small,
          onPressed: !_exporting ? () => _exportAstroBin(result) : null,
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    NightshadeColors colors,
    StackAndShareResult result,
    Uint8List? rgba,
    Uint16List? mono,
    AsyncValue<Uint8List?> previewAsync,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _buildViewer(context, colors, result, rgba, previewAsync),
        ),
        Container(
          width: 320,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: colors.border)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
            child: _buildSidePanel(context, colors, result, mono),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    NightshadeColors colors,
    StackAndShareResult result,
    Uint8List? rgba,
    Uint16List? mono,
    AsyncValue<Uint8List?> previewAsync,
  ) {
    // Phone portrait is too short to give the viewer a flexible Expanded AND a
    // 40%-capped panel without the viewer's contents (e.g. the EmptyState
    // column, or the stat list) clipping. Scroll the whole surface instead and
    // give the viewer a fixed, generous slice of the viewport height. The panel
    // flows beneath it and the page scrolls if the combined height exceeds the
    // screen — nothing is hidden behind a rigid flex.
    final viewerHeight =
        (MediaQuery.sizeOf(context).height * 0.5).clamp(240.0, 520.0);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: viewerHeight,
            child: _buildViewer(
              context,
              colors,
              result,
              rgba,
              previewAsync,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.border)),
            ),
            padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
            child: _buildSidePanel(context, colors, result, mono),
          ),
        ],
      ),
    );
  }

  Widget _buildViewer(
    BuildContext context,
    NightshadeColors colors,
    StackAndShareResult result,
    Uint8List? rgba,
    AsyncValue<Uint8List?> previewAsync,
  ) {
    if (rgba == null) {
      // A scheduled stretch owns the viewer until it lands — otherwise the
      // first frame of a freshly stacked result would read "Image not
      // available" for the image it is in the middle of rendering.
      if (_renderPending) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      return previewAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (error, _) => EmptyState(
          icon: NightshadeIcons.imageOff,
          title: 'Preview unavailable',
          body: _previewErrorMessage(error),
        ),
        data: (_) => const EmptyState(
          icon: NightshadeIcons.imageOff,
          title: 'Image not available',
          body: 'This legacy result has no durable preview. Re-run Stack & '
              'Share to recreate it.',
        ),
      );
    }
    return Container(
      color: colors.background,
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: AstroImageViewer(
        imageData: rgba,
        width: result.width,
        height: result.height,
        isColor: true,
      ),
    );
  }

  Widget _buildSidePanel(
    BuildContext context,
    NightshadeColors colors,
    StackAndShareResult result,
    Uint16List? mono,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionHeader(title: 'Display'),
        const SizedBox(height: NightshadeTokens.spaceSm),
        _buildStretchControl(colors, mono),
        const SizedBox(height: NightshadeTokens.space2xl),
        const SectionHeader(title: 'Integration'),
        const SizedBox(height: NightshadeTokens.spaceSm),
        _StatRow(
          label: 'Integration',
          value: formatHms(result.integrationSecs),
        ),
        _StatRow(
          label: 'Frames stacked',
          value: '${result.framesStacked}',
        ),
        _StatRow(
          label: 'Rejected',
          value: '${result.framesRejected}',
        ),
        _StatRow(
          label: 'Avg residual',
          value: '${result.avgAlignmentResidual.toStringAsFixed(2)} px',
        ),
        if (result.avgHfr != null)
          _StatRow(
            label: 'Avg HFR',
            value: '${result.avgHfr!.toStringAsFixed(2)} px',
          ),
        if (result.filter != null)
          _StatRow(label: 'Filter', value: result.filter!),
        _StatRow(
          label: 'Dimensions',
          value: '${result.width} × ${result.height}',
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Row(
          children: [
            StatusPill(
              icon: NightshadeIcons.layers,
              label: 'Attempted',
              value: '${result.framesAttempted}',
              status: StatusPillStatus.inactive,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStretchControl(NightshadeColors colors, Uint16List? mono) {
    // Re-stretching needs the in-memory mono buffer; without it the control is
    // disabled (an already-exported result has only RGBA on disk).
    final canRestretch = mono != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Stretch',
          style: NightshadeTypography.label.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        NightshadeDropdown(
          isExpanded: true,
          value: _stretch.name,
          items: StackViewerStretch.values.map((s) => s.name).toList(),
          itemLabels: StackViewerStretch.values.map(_stretchLabel).toList(),
          onChanged: canRestretch
              ? (name) {
                  if (name == null) return;
                  final next = StackViewerStretch.values
                      .firstWhere((s) => s.name == name);
                  if (next == _stretch) return;
                  setState(() {
                    _stretch = next;
                    // Force a recompute on the next build by clearing the cache.
                    _renderedFrom = null;
                  });
                }
              : null,
        ),
        if (!canRestretch) ...[
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            'Re-stretch is available only for a freshly stacked result still in '
            'memory.',
            style: NightshadeTypography.caption.copyWith(
              color: colors.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  /// Resolve the RGBA to show: recompute from the in-memory integrated buffer
  /// for the current stretch when available, else fall back to the
  /// orchestrator's already-stretched RGBA (matched by id).
  ///
  /// [channels] describes [buffer]'s layout (`1` = mono plane, `3` = interleaved
  /// RGB16) so the stretch renders an OSC integration in colour rather than
  /// misreading interleaved samples as a mono plane.
  Uint8List? _resolveDisplayRgba(
    StackAndShareResult result,
    StackAndShareState liveState,
    Uint16List? buffer,
    int channels,
    Uint8List? durablePreview,
  ) {
    if (buffer != null) {
      // Recompute only when the source buffer or selected stretch changed. The
      // render itself is scheduled, never awaited here: it is tens of millions
      // of iterations plus a width*height*4 allocation, and this runs inside
      // `build`.
      if (!identical(_renderedFrom, buffer) || _displayRgba == null) {
        _scheduleStretch(result, buffer, channels);
      }
      return _displayRgba;
    }
    // No in-memory buffer: use the orchestrator's stretched RGBA if it belongs
    // to this result, otherwise nothing is renderable in-app.
    if (liveState.result?.id == result.id && liveState.resultRgba != null) {
      return liveState.resultRgba;
    }
    return durablePreview;
  }

  /// True while a stretch is in flight and nothing has been painted yet.
  bool get _renderPending => _renderingBuffer != null && _displayRgba == null;

  /// Kick a render of [buffer] under the current stretch, at most once per
  /// (buffer, stretch) pair. Called from the build path, so it must not call
  /// `setState` synchronously — only the completion does.
  void _scheduleStretch(
    StackAndShareResult result,
    Uint16List buffer,
    int channels,
  ) {
    if (identical(_renderingBuffer, buffer) && _renderingStretch == _stretch) {
      return;
    }
    _renderingBuffer = buffer;
    _renderingStretch = _stretch;
    final generation = ++_renderGeneration;
    unawaited(() async {
      Uint8List? rgba;
      try {
        rgba = await _renderStretch(result, buffer, channels);
      } catch (_) {
        // A failed stretch leaves the previous pixels (or the empty state) up
        // rather than tearing the screen down; the buffer is still exportable.
        rgba = null;
      }
      if (!mounted || generation != _renderGeneration) return;
      setState(() {
        if (rgba != null) {
          _displayRgba = rgba;
          _renderedFrom = buffer;
        }
        _renderingBuffer = null;
        _renderingStretch = null;
      });
    }());
  }

  String _previewErrorMessage(Object error) {
    final message = _cleanErrorMessage(error);
    return message.isEmpty ? 'The saved preview could not be opened.' : message;
  }

  String _cleanErrorMessage(Object error) {
    var message = error.toString().trim();
    for (final prefix in const [
      'StateError: ',
      'Bad state: ',
      'FormatException: ',
    ]) {
      if (message.startsWith(prefix)) {
        message = message.substring(prefix.length).trim();
      }
    }
    return message;
  }

  /// Render [buffer] to display RGBA under the current [_stretch].
  ///
  /// Branches on [channels]:
  ///   * `1` (mono) — [StackViewerStretch.autoStf] delegates to the native
  ///     single-channel STF; [StackViewerStretch.linear] does a min/max linear
  ///     map to grayscale.
  ///   * `3` (interleaved RGB16, OSC) — [StackViewerStretch.autoStf] delegates
  ///     to the stacking-engine seam's per-channel colour STF (the same curve
  ///     the native colour-capture path produces); [StackViewerStretch.linear]
  ///     does a per-channel min/max linear map preserving colour balance.
  ///
  /// Both stretches are genuine, distinct renderings — neither is a no-op nor a
  /// grayscale fallback for colour data.
  /// The STF branches call synchronous seams in `nightshade_core`
  /// ([ImagingBackend.autoStretchImage] and [StackingEngineSeam.autoStretch]),
  /// so they still occupy this isolate — but off the build phase, after the
  /// frame is on screen. Moving them to a worker needs those two APIs to become
  /// asynchronous, which is a `nightshade_core` change.
  Future<Uint8List> _renderStretch(
    StackAndShareResult result,
    Uint16List buffer,
    int channels,
  ) async {
    switch (_stretch) {
      case StackViewerStretch.autoStf:
        if (channels == 3) {
          return ref.read(stackResultStretchEngineProvider).autoStretch(
                width: result.width,
                height: result.height,
                data: buffer,
                channels: 3,
              );
        }
        return ref.read(imagingBackendProvider).autoStretchImage(
              width: result.width,
              height: result.height,
              data: buffer,
            );
      case StackViewerStretch.linear:
        final pixelCount = result.width * result.height;
        return channels == 3
            ? Isolate.run(() => renderLinearColorRgba(buffer, pixelCount))
            : Isolate.run(() => renderLinearGrayRgba(buffer));
    }
  }

  static String _stretchLabel(StackViewerStretch stretch) {
    return switch (stretch) {
      StackViewerStretch.autoStf => 'Auto (STF)',
      StackViewerStretch.linear => 'Linear',
    };
  }

  // ===========================================================================
  // Export / share
  // ===========================================================================

  /// Suggested file name (no directory) for [result] in [format].
  String _suggestedFileName(StackAndShareResult result, String extension) {
    final base = (result.targetName ?? 'stack')
        .replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final safeBase = base.isEmpty ? 'stack' : base;
    return '$safeBase.$extension';
  }

  Future<void> _export(
    StackAndShareResult result,
    Uint8List rgba,
    ShareExportFormat format,
  ) async {
    if (_exporting) return;
    final picker = ref.read(stackResultSavePickerProvider);
    final share = ref.read(stackResultShareProvider);
    final service = ref.read(stackShareExportServiceProvider);
    final stampPersistedResult = ref.read(backendProvider) is! NetworkBackend;

    final (extension, allowed, title) = switch (format) {
      ShareExportFormat.png => ('png', ['png'], 'Export PNG'),
      ShareExportFormat.jpeg => ('jpg', ['jpg', 'jpeg'], 'Export JPEG'),
      ShareExportFormat.shareCard => (
          'png',
          ['png', 'jpg', 'jpeg'],
          'Export Share Card'
        ),
    };

    setState(() => _exporting = true);
    try {
      final outputPath = await picker(
        dialogTitle: title,
        fileName: _suggestedFileName(result, extension),
        allowedExtensions: allowed,
      );
      if (outputPath == null || !mounted) return;

      final cardSpec = format == ShareExportFormat.shareCard
          ? _buildShareCardSpec(result)
          : null;
      final written = await service.exportImage(
        result: result,
        rgba: rgba,
        format: format,
        outputPath: outputPath,
        cardSpec: cardSpec,
        // Remote ids belong to the imaging host. Never stamp a controller-local
        // row that happens to share the same integer id.
        stampPersistedResult: stampPersistedResult,
      );
      if (!mounted) return;
      NightshadeToastHelper.show(
        context: context,
        message: 'Exported ${p.basename(written)}',
        severity: NightshadeAlertSeverity.success,
      );

      // The share card always hands the written file to the OS share sheet. On
      // Android/iOS so must PNG/JPEG: there is no save dialog on those
      // platforms, so the export landed in the app sandbox and the toast alone
      // would name a file the user cannot open. On desktop those two stay
      // save-only — the user picked the path. A share failure never means the
      // export failed — the file is already on disk — so it surfaces as a
      // non-fatal warning.
      final handOffToShareSheet = format == ShareExportFormat.shareCard ||
          Platform.isAndroid ||
          Platform.isIOS;
      if (handOffToShareSheet) {
        try {
          // share_plus is a UI dependency, so the call lives at this boundary.
          await share(written, text: result.targetName ?? 'Stacked result');
        } catch (e) {
          if (!mounted) return;
          NightshadeToastHelper.show(
            context: context,
            message: 'Saved, but sharing failed.',
            severity: NightshadeAlertSeverity.warning,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      await ErrorDialog.show(
        context,
        title: 'Export failed',
        message: 'Could not export the stacked image.',
        technicalDetails: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Build the annotated share-card spec from the run's stats.
  ///
  /// The card carries whatever colour the export's RGBA buffer holds — for an
  /// OSC result that buffer is the per-channel-stretched colour rendering, so
  /// the PNG / JPEG / share-card output is colour automatically; this spec only
  /// supplies the overlay geometry + stat text and is colour-agnostic.
  ShareCardSpec _buildShareCardSpec(StackAndShareResult result) {
    return ShareCardSpec(
      title: result.targetName ?? 'Stacked result',
      targetWidth: result.width,
      targetHeight: result.height,
      stats: [
        ShareStatLine(
          label: 'Integration',
          value: formatHms(result.integrationSecs),
        ),
        ShareStatLine(label: 'Frames', value: '${result.framesStacked}'),
        if (result.filter != null)
          ShareStatLine(label: 'Filter', value: result.filter!),
      ],
    );
  }

  /// The night the subs were acquired: the imaging session's start time when
  /// the result is attached to one. Falls back to null so the service uses the
  /// run's own timestamp — restacking last month's data would otherwise stamp
  /// the CSV with today.
  ///
  /// Awaits the session list rather than reading it synchronously: nothing on
  /// this screen watches [allSessionsProvider], so at the moment the export
  /// button is tapped the stream has not emitted and `.valueOrNull` is null —
  /// which silently produced exactly the today-stamped CSV this exists to
  /// prevent. The timeout keeps a stalled remote session poll from hanging the
  /// export; the run timestamp is then the honest fallback.
  Future<DateTime?> _acquisitionDate(StackAndShareResult result) async {
    final sessionId = result.sessionId;
    if (sessionId == null) return null;
    final sessions = await ref.read(allSessionsProvider.future).timeout(
          const Duration(seconds: 5),
          onTimeout: () => const <ImagingSession>[],
        );
    for (final session in sessions) {
      if (session.id == sessionId) return session.startTime;
    }
    return null;
  }

  Future<void> _exportAstroBin(StackAndShareResult result) async {
    final picker = ref.read(stackResultSavePickerProvider);
    final share = ref.read(stackResultShareProvider);
    final service = ref.read(stackShareExportServiceProvider);

    // CSV first: it is the format AstroBin's acquisition importer reads, so the
    // button does what its name promises with one file. The picker still allows
    // .md / .json for anyone who wants the copy-paste block or the payload, and
    // the service honours whichever extension comes back.
    final outputPath = await picker(
      dialogTitle: 'Export AstroBin acquisition details',
      fileName: _suggestedFileName(result, 'csv'),
      allowedExtensions: ['csv', 'md', 'json'],
    );
    if (outputPath == null) return;
    if (!mounted) return;

    setState(() => _exporting = true);
    try {
      // Awaited, not handed over as a Future: `acquisitionDate` is a
      // `DateTime?`, so passing the un-awaited future does not compile at all —
      // and the shape it would have taken if it did (a truthy non-null Future)
      // is exactly the silent today-stamped CSV this lookup exists to prevent.
      final acquisitionDate = await _acquisitionDate(result);
      if (!mounted) return;
      final meta = service.buildAstroBinMetadata(
        result: result,
        acquisitionDate: acquisitionDate,
      );
      final exportedPath = await service.exportAstroBinAcquisition(
        meta: meta,
        outputPath: outputPath,
      );
      await share(
        exportedPath,
        text: 'AstroBin acquisition details: ${result.targetName ?? ''}',
      );
      if (!mounted) return;
      NightshadeToastHelper.show(
        context: context,
        message: 'AstroBin sidecar exported',
        severity: NightshadeAlertSeverity.success,
      );
    } catch (e) {
      if (!mounted) return;
      await ErrorDialog.show(
        context,
        title: 'AstroBin export failed',
        message: 'Could not write the AstroBin acquisition sidecar.',
        technicalDetails: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// Export/share actions surfaced through the phone overflow menu (the four
/// inline header buttons do not fit a phone-width [ScreenHeader] Row).
enum _StackResultAction { png, jpeg, shareCard, astroBin }

/// Icon + label row for a [_StackResultAction] popup-menu entry.
class _ActionMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ActionMenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: NightshadeTokens.iconSm, color: colors.textSecondary),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Text(
          label,
          style: NightshadeTypography.bodySm.copyWith(
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// A label-left, value-right stat row using monospace tabular value type.
class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NightshadeTokens.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label,
              style: NightshadeTypography.bodySm.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: NightshadeTypography.mono.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The linear-stretch pixel loops, top-level so they can run in a worker
/// isolate via `Isolate.run` — the closure that calls them captures only the
/// buffer and the pixel count, both of which cross an isolate boundary.
///
/// A 6000x4000 master is 24 million pixels: two full passes plus a 96 MB
/// allocation. On the UI isolate, inside `build`, that is a frame stall the
/// operator sees as the app hanging.
/// Linear min/max normalisation of a u16 mono buffer to grayscale RGBA.
Uint8List renderLinearGrayRgba(Uint16List mono) {
  var min = 65535;
  var max = 0;
  for (final v in mono) {
    if (v < min) min = v;
    if (v > max) max = v;
  }
  final span = max - min;
  final out = Uint8List(mono.length * 4);
  for (var i = 0; i < mono.length; i++) {
    final g = span <= 0 ? 0 : (((mono[i] - min) * 255) ~/ span);
    final o = i * 4;
    out[o] = g;
    out[o + 1] = g;
    out[o + 2] = g;
    out[o + 3] = 255;
  }
  return out;
}

/// Per-channel linear min/max normalisation of an interleaved RGB16 buffer to
/// RGBA. Each channel is stretched against its own extent so the colour
/// balance is preserved rather than dominated by the brightest channel.
Uint8List renderLinearColorRgba(Uint16List rgb, int pixelCount) {
  var rMin = 65535, gMin = 65535, bMin = 65535;
  var rMax = 0, gMax = 0, bMax = 0;
  for (var i = 0; i < pixelCount; i++) {
    final base = i * 3;
    final r = rgb[base];
    final g = rgb[base + 1];
    final b = rgb[base + 2];
    if (r < rMin) rMin = r;
    if (r > rMax) rMax = r;
    if (g < gMin) gMin = g;
    if (g > gMax) gMax = g;
    if (b < bMin) bMin = b;
    if (b > bMax) bMax = b;
  }
  final rSpan = rMax - rMin;
  final gSpan = gMax - gMin;
  final bSpan = bMax - bMin;
  final out = Uint8List(pixelCount * 4);
  for (var i = 0; i < pixelCount; i++) {
    final base = i * 3;
    final o = i * 4;
    out[o] = rSpan <= 0 ? 0 : (((rgb[base] - rMin) * 255) ~/ rSpan);
    out[o + 1] = gSpan <= 0 ? 0 : (((rgb[base + 1] - gMin) * 255) ~/ gSpan);
    out[o + 2] = bSpan <= 0 ? 0 : (((rgb[base + 2] - bMin) * 255) ~/ bSpan);
    out[o + 3] = 255;
  }
  return out;
}
