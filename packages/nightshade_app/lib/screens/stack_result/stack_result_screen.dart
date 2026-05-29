import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
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

/// The display stretch applied to the integrated mono buffer in the viewer.
///
/// The native in-memory stacker exposes exactly one auto-stretch
/// ([bridge.apiAutoStretchImage], a fixed STF), so the viewer offers the two
/// renderings it can produce *honestly* from the retained u16 mono buffer:
/// the STF auto-stretch, and a linear (unstretched) mapping. We deliberately do
/// not advertise stretch methods the in-memory engine cannot apply — surfacing
/// a control that silently produced identical output would violate the project's
/// "no silent fallback" rule.
enum StackViewerStretch {
  /// Native STF auto-stretch via [bridge.apiAutoStretchImage].
  autoStf,

  /// Linear normalisation of the u16 mono buffer to grayscale RGBA.
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
    // The in-memory mono buffer is only available when this screen is showing
    // the run that just completed (the live orchestrator retains it). Match by
    // id so a stale buffer from a different run is never used.
    final mono = (liveState.result?.id == result.id) ? liveState.resultMono : null;
    final rgba = _resolveDisplayRgba(result, liveState, mono);

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
    return Column(
      children: [
        Expanded(child: _buildViewer(context, colors, result, rgba)),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.border)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
            child: _buildSidePanel(context, colors, result, mono),
          ),
        ),
      ],
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

  /// Resolve the RGBA to show: recompute from the in-memory mono buffer for the
  /// current stretch when available, else fall back to the orchestrator's
  /// already-stretched RGBA (matched by id).
  Uint8List? _resolveDisplayRgba(
    StackAndShareResult result,
    StackAndShareState liveState,
    Uint16List? mono,
  ) {
    if (mono != null) {
      // Recompute only when the source buffer or selected stretch changed.
      if (!identical(_renderedFrom, mono) || _displayRgba == null) {
        _displayRgba = _renderStretch(result, mono);
        _renderedFrom = mono;
      }
      return _displayRgba;
    }
    // No mono buffer: use the orchestrator's stretched RGBA if it belongs to
    // this result, otherwise nothing is renderable in-app.
    if (liveState.result?.id == result.id && liveState.resultRgba != null) {
      return liveState.resultRgba;
    }
    return null;
  }

  /// Render [mono] to display RGBA under the current [_stretch].
  ///
  /// [StackViewerStretch.autoStf] delegates to the native STF auto-stretch;
  /// [StackViewerStretch.linear] performs a min/max linear normalisation to
  /// grayscale. Both are genuine, distinct renderings — neither is a no-op.
  Uint8List _renderStretch(StackAndShareResult result, Uint16List mono) {
    switch (_stretch) {
      case StackViewerStretch.autoStf:
        return bridge.apiAutoStretchImage(
          width: result.width,
          height: result.height,
          data: mono,
        );
      case StackViewerStretch.linear:
        return _linearGray(mono);
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
