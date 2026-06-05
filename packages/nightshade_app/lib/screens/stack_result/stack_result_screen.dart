import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
// The stacking-engine seam owns the colour STF stretch (the native bridge only
// exposes the single-channel `apiAutoStretchImage`; its companion
// `_autoStretchColor` is the per-channel PixInsight STF that matches the
// native colour-capture path). The seam is not re-exported through the core
// barrel, so the result viewer reaches it directly to render an OSC result with
// the exact same curve a live colour capture would produce. (Matches the
// established `// ignore: implementation_imports` precedent in
// screens/imaging/widgets/stacking_panel.dart.)
// ignore: implementation_imports
import 'package:nightshade_core/src/services/stacking_engine_seam.dart'
    show BridgeStackingEngineSeam, StackingEngineSeam;
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../widgets/astro_image_viewer.dart';

/// Signature of the native save-file picker used by the Stack Result viewer to
/// choose an export destination.
///
/// Defaults to [FilePicker.platform.saveFile]; injected via
/// [stackResultSavePickerProvider] so widget tests can stub the picker without
/// invoking platform channels.
typedef StackResultSavePicker = Future<String?> Function({
  required String dialogTitle,
  required String fileName,
  required List<String> allowedExtensions,
});

Future<String?> _defaultSavePicker({
  required String dialogTitle,
  required String fileName,
  required List<String> allowedExtensions,
}) {
  return FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
  );
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
  /// ([bridge.apiAutoStretchImage]) for a mono buffer, or the stacking-engine
  /// seam's per-channel colour STF for an interleaved-RGB16 buffer.
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

  /// True while an export/share operation is running, used to disable the
  /// action buttons so a user cannot launch two save pickers at once.
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final resultAsync = ref.watch(stackResultViewerProvider(widget.resultId));
    final liveState = ref.watch(stackAndShareProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: resultAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (error, _) => _buildNotFound(context, error),
        data: (result) => _buildLoaded(context, colors, result, liveState),
      ),
    );
  }

  Widget _buildNotFound(BuildContext context, Object error) {
    return EmptyState(
      icon: LucideIcons.imageOff,
      title: 'Result not found',
      body: 'No stacked result exists for id ${widget.resultId}. It may have '
          'been deleted.\n\n$error',
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    NightshadeColors colors,
    StackAndShareResult result,
    StackAndShareState liveState,
  ) {
    // The in-memory integrated buffer is only available when this screen is
    // showing the run that just completed (the live orchestrator retains it).
    // Match by id so a stale buffer from a different run is never used. The
    // buffer is a single mono plane for a mono stack and interleaved RGB16 for
    // an OSC stack — [channels] selects how the stretch interprets it.
    final isOwnRun = liveState.result?.id == result.id;
    final mono = isOwnRun ? liveState.resultMono : null;
    final channels = isOwnRun ? liveState.resultChannels : result.channels;
    final rgba = _resolveDisplayRgba(result, liveState, mono, channels);

    final subtitle = '${result.framesStacked} frame'
        '${result.framesStacked == 1 ? '' : 's'} · '
        '${formatHms(result.integrationSecs)} integration';

    return Column(
      children: [
        ScreenHeader(
          title: result.targetName ?? 'Stacked Result',
          subtitle: subtitle,
          icon: LucideIcons.image,
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
              ? _buildMobileLayout(context, colors, result, rgba, mono)
              : _buildDesktopLayout(context, colors, result, rgba, mono),
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
        icon: Icon(LucideIcons.share2, color: colors.textPrimary),
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
              icon: LucideIcons.image,
              label: 'Export JPEG',
            ),
          ),
          PopupMenuItem(
            value: _StackResultAction.shareCard,
            enabled: canExport,
            child: const _ActionMenuRow(
              icon: LucideIcons.share2,
              label: 'Share Card',
            ),
          ),
          const PopupMenuItem(
            value: _StackResultAction.astroBin,
            child: _ActionMenuRow(
              icon: LucideIcons.fileText,
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
          icon: LucideIcons.image,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: canExport
              ? () => _export(result, rgba, ShareExportFormat.jpeg)
              : null,
        ),
        NightshadeButton(
          label: 'Share Card',
          icon: LucideIcons.share2,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: canExport
              ? () => _export(result, rgba, ShareExportFormat.shareCard)
              : null,
        ),
        NightshadeButton(
          label: 'AstroBin',
          icon: LucideIcons.fileText,
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
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildViewer(context, colors, result, rgba)),
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
            child: _buildViewer(context, colors, result, rgba),
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
  ) {
    if (rgba == null) {
      // No pixels in memory and no on-disk export to re-load: tell the user the
      // master is no longer resident rather than rendering a black canvas.
      return EmptyState(
        icon: LucideIcons.imageOff,
        title: 'Image not available',
        body: result.exportedImagePath != null
            ? 'This stacked master was exported to '
                '${result.exportedImagePath}. Re-run Stack & Share to view it '
                'in the app.'
            : 'The integrated pixels are no longer in memory. Re-run Stack & '
                'Share to view this result.',
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
              icon: LucideIcons.layers,
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
          itemLabels:
              StackViewerStretch.values.map(_stretchLabel).toList(),
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
  ) {
    if (buffer != null) {
      // Recompute only when the source buffer or selected stretch changed.
      if (!identical(_renderedFrom, buffer) || _displayRgba == null) {
        _displayRgba = _renderStretch(result, buffer, channels);
        _renderedFrom = buffer;
      }
      return _displayRgba;
    }
    // No in-memory buffer: use the orchestrator's stretched RGBA if it belongs
    // to this result, otherwise nothing is renderable in-app.
    if (liveState.result?.id == result.id && liveState.resultRgba != null) {
      return liveState.resultRgba;
    }
    return null;
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
  Uint8List _renderStretch(
    StackAndShareResult result,
    Uint16List buffer,
    int channels,
  ) {
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
        return bridge.apiAutoStretchImage(
          width: result.width,
          height: result.height,
          data: buffer,
        );
      case StackViewerStretch.linear:
        return channels == 3
            ? _linearColor(buffer, result.width * result.height)
            : _linearGray(buffer);
    }
  }

  /// Linear min/max normalisation of a u16 mono buffer to grayscale RGBA.
  Uint8List _linearGray(Uint16List mono) {
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
  Uint8List _linearColor(Uint16List rgb, int pixelCount) {
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
    final picker = ref.read(stackResultSavePickerProvider);
    final share = ref.read(stackResultShareProvider);
    final service = ref.read(stackShareExportServiceProvider);

    final (extension, allowed, title) = switch (format) {
      ShareExportFormat.png => ('png', ['png'], 'Export PNG'),
      ShareExportFormat.jpeg => ('jpg', ['jpg', 'jpeg'], 'Export JPEG'),
      ShareExportFormat.shareCard => ('png', ['png', 'jpg', 'jpeg'], 'Export Share Card'),
    };

    final outputPath = await picker(
      dialogTitle: title,
      fileName: _suggestedFileName(result, extension),
      allowedExtensions: allowed,
    );
    if (outputPath == null) return; // User cancelled the save picker.
    if (!mounted) return;

    setState(() => _exporting = true);
    try {
      final cardSpec = format == ShareExportFormat.shareCard
          ? _buildShareCardSpec(result)
          : null;
      final written = await service.exportImage(
        result: result,
        rgba: rgba,
        format: format,
        outputPath: outputPath,
        cardSpec: cardSpec,
      );
      // Package-boundary share call lives here (share_plus is a UI dependency).
      await share(written, text: result.targetName ?? 'Stacked result');
      if (!mounted) return;
      NightshadeToastHelper.show(
        context: context,
        message: 'Exported ${p.basename(written)}',
        severity: NightshadeAlertSeverity.success,
      );
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

  Future<void> _exportAstroBin(StackAndShareResult result) async {
    final picker = ref.read(stackResultSavePickerProvider);
    final share = ref.read(stackResultShareProvider);
    final service = ref.read(stackShareExportServiceProvider);

    final outputPath = await picker(
      dialogTitle: 'Export AstroBin acquisition details',
      fileName: _suggestedFileName(result, 'md'),
      allowedExtensions: ['md'],
    );
    if (outputPath == null) return;
    if (!mounted) return;

    setState(() => _exporting = true);
    try {
      final meta = service.buildAstroBinMetadata(result: result);
      final markdownPath = await service.exportAstroBinSidecar(
        meta: meta,
        outputPath: outputPath,
      );
      await share(
        markdownPath,
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
