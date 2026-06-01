import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/filter_wheel_selector.dart';
import 'panel_widgets.dart';

/// Shared maximum width for the imaging screen's bottom control panel.
///
/// The panel sits beneath the live preview's [Expanded]; without a cap it
/// stretches edge-to-edge on wide monitors, pushing the Capture / Exposure /
/// Filter / Display groups far apart and wasting the horizontal space that
/// would otherwise let the image canvas breathe. Centring the panel at this
/// width keeps the controls in a single comfortable cluster and visually
/// anchors them under the image. Picked to comfortably fit the expanded
/// Capture + Exposure + Filter groups side-by-side at typical desktop sizes
/// while still reflowing via [Wrap] when the window is narrower than this.
const double kImagingControlPanelMaxWidth = 920.0;

/// Session-scoped collapse state for the imaging screen's bottom control panel.
///
/// Each section remembers its own expanded/collapsed state for the lifetime of
/// the app session (matching the equipment screen's rail/section collapse
/// providers — see `equipmentHealthExpandedProvider`). Collapsing a section
/// frees vertical space so the live preview's `Expanded` grows to fill it,
/// which is the whole point of this layout: give the image most of the screen
/// for review while keeping every control one tap away.
///
/// Defaults:
/// * Quick-capture stays EXPANDED so the full Capture / Exposure / Loop /
///   Filter / Display controls are visible on first load. When collapsed it
///   does NOT disappear — it shrinks to a thin "quick capture" bar that still
///   exposes filter switching + exposure + the snapshot button inline.
/// * Stats (temp / RMS / HFR) and Display both default to EXPANDED, and
///   collapse away entirely to a thin header bar you can re-open.
final imagingCaptureSectionExpandedProvider =
    StateProvider<bool>((ref) => true);
final imagingStatsSectionExpandedProvider = StateProvider<bool>((ref) => true);
final imagingDisplaySectionExpandedProvider =
    StateProvider<bool>((ref) => true);

/// A thin, tappable header bar that toggles a collapsible imaging section.
///
/// Mirrors the equipment-screen collapsible-panel header (`_HealthHeaderBar`):
/// an icon, a title, an optional trailing summary widget, and a chevron that
/// rotates between down (expanded) and right (collapsed). Kept inside the
/// imaging folder rather than promoted to `nightshade_ui` because the design
/// system has no generic collapsible-section primitive yet and the brief
/// forbids modifying `nightshade_ui`.
class CollapsibleSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isExpanded;
  final VoidCallback onToggle;
  final NightshadeColors colors;

  /// Optional widget shown on the right side of the header (e.g. a compact
  /// summary of the collapsed content, or inline quick controls). Placed
  /// before the chevron.
  final Widget? trailing;

  const CollapsibleSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.isExpanded,
    required this.onToggle,
    required this.colors,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: NightshadeTokens.borderRadiusSm,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceMd,
          vertical: NightshadeTokens.spaceSm,
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: colors.textMuted),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Text(
              title,
              style: TextStyle(
                fontSize: NightshadeTokens.fontSizePanelCaption,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(child: trailing!),
            ] else
              const Spacer(),
            Icon(
              isExpanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
              size: 16,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// A collapsible section: a tappable header bar plus an animated body that
/// cross-fades to zero height when collapsed.
///
/// Uses [AnimatedCrossFade] exactly like the equipment health panel so the
/// collapse animation matches the rest of the app. The [collapsedTrailing]
/// (when supplied) is rendered inline in the header while collapsed, so a
/// section can keep critical controls reachable even in its thin-bar state —
/// this is how the quick-capture bar keeps filter + exposure + snapshot live
/// without expanding.
class CollapsibleControlSection extends ConsumerWidget {
  final IconData icon;
  final String title;
  final StateProvider<bool> expandedProvider;
  final NightshadeColors colors;
  final Widget child;

  /// Inline controls shown in the header only while the section is collapsed.
  final Widget? collapsedTrailing;

  /// Summary shown in the header only while the section is collapsed and no
  /// [collapsedTrailing] is provided (e.g. the stats readout).
  final Widget? collapsedSummary;

  const CollapsibleControlSection({
    super.key,
    required this.icon,
    required this.title,
    required this.expandedProvider,
    required this.colors,
    required this.child,
    this.collapsedTrailing,
    this.collapsedSummary,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpanded = ref.watch(expandedProvider);

    final Widget? trailing =
        isExpanded ? null : (collapsedTrailing ?? collapsedSummary);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CollapsibleSectionHeader(
          icon: icon,
          title: title,
          isExpanded: isExpanded,
          onToggle: () {
            ref.read(expandedProvider.notifier).state = !isExpanded;
          },
          colors: colors,
          trailing: trailing,
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(
              NightshadeTokens.spaceMd,
              0,
              NightshadeTokens.spaceMd,
              NightshadeTokens.spaceMd,
            ),
            child: child,
          ),
          crossFadeState:
              isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

/// Inline one-line summary of the temp / RMS / HFR readouts, shown in the
/// Stats section header while that section is collapsed so the operator can
/// still glance at sensor temperature, guide RMS, and last-frame HFR without
/// expanding. Reads the same providers as `QuickStatsPanel`.
class QuickStatsSummary extends ConsumerWidget {
  final NightshadeColors colors;

  const QuickStatsSummary({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraStateProvider);
    final guiderState = ref.watch(guiderStateProvider);
    final lastStats = ref.watch(lastImageStatsProvider);

    String tempValue = '---';
    if (cameraState.connectionState == DeviceConnectionState.connected) {
      tempValue = cameraState.temperature != null
          ? '${cameraState.temperature!.toStringAsFixed(1)}°C'
          : 'N/A';
    }

    String rmsValue = '---';
    if (guiderState.connectionState == DeviceConnectionState.connected &&
        guiderState.isGuiding &&
        guiderState.rmsTotal != null) {
      rmsValue = '${guiderState.rmsTotal!.toStringAsFixed(2)}"';
    }

    String hfrValue = '---';
    if (lastStats?.hfr != null) {
      hfrValue = lastStats!.hfr!.toStringAsFixed(2);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.max,
      children: [
        _summaryChip(LucideIcons.thermometer, tempValue),
        const SizedBox(width: NightshadeTokens.spaceMd),
        _summaryChip(LucideIcons.activity, rmsValue),
        const SizedBox(width: NightshadeTokens.spaceMd),
        _summaryChip(LucideIcons.target, hfrValue),
      ],
    );
  }

  Widget _summaryChip(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: colors.textMuted),
        const SizedBox(width: NightshadeTokens.spaceXs),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// The polished collapsed-state toolbar for the Quick Capture section.
///
/// Rendered inline in the section header while Quick Capture is collapsed, it
/// keeps the three most-used controls one tap away without expanding the panel:
///
///   * a quick filter selector (the connected profile's filters), and
///   * a grouped duration field + Snapshot action, right-aligned.
///
/// Layout intent (the previous bar jammed everything hard-left with mismatched
/// heights, which read as unfinished):
///
///   [ ⛛ filters (scrolls, fades) ] │ [ Dur 30s ][ Snapshot ]
///    └─ Flexible, yields space ──┘  └─ fixed, grouped on a card ─┘
///
/// The filter strip lives in a [Flexible] so it surrenders width to the
/// duration + Snapshot cluster, and scrolls horizontally with a soft fade on
/// the trailing edge when a profile has more filters than fit — so a 8-filter
/// LRGB+SHO wheel never blows out the row. The duration field and Snapshot
/// button share one [surfaceAlt] pill so they read as a single "fire a frame"
/// group, with a divider separating them from filter switching.
///
/// This is a pure presentation widget: capture state and the snapshot handler
/// stay owned by the imaging screen and flow in as parameters, so the bar has
/// no opinion about how a frame is taken.
class QuickCaptureBar extends ConsumerWidget {
  final NightshadeColors colors;
  final ExposureSettings exposureSettings;
  final bool isConnected;
  final bool isCapturing;
  final bool isSingleCapture;

  /// Host suffix appended to the duration label in remote-control mode.
  final String hostSuffix;

  /// Called when the duration field commits a new (parsed, > 0) value.
  final ValueChanged<double> onDurationChanged;

  /// Fired when the Snapshot button is tapped.
  final VoidCallback onSnapshot;

  const QuickCaptureBar({
    super.key,
    required this.colors,
    required this.exposureSettings,
    required this.isConnected,
    required this.isCapturing,
    required this.isSingleCapture,
    required this.hostSuffix,
    required this.onDurationChanged,
    required this.onSnapshot,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasFilters =
        ref.watch(filterWheelStateProvider).filterNames.isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        // Filter switching — yields width to the capture cluster on the right
        // and scrolls (with a trailing fade) when a profile has many filters.
        if (hasFilters) ...[
          Flexible(
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFFFFFFFF),
                  Colors.transparent,
                ],
                stops: [0.0, 0.9, 1.0],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: const SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.only(right: NightshadeTokens.spaceMd),
                child: FilterWheelSelector(
                  style: FilterSelectorStyle.buttons,
                  compact: true,
                ),
              ),
            ),
          ),
          // Divider grouping filters apart from the capture cluster.
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceMd,
            ),
            color: colors.border,
          ),
        ] else
          const Spacer(),
        // Capture cluster: duration + Snapshot share one pill so they read as a
        // single "fire a frame" group with matched control heights.
        _CaptureCluster(
          colors: colors,
          exposureSettings: exposureSettings,
          isConnected: isConnected,
          isCapturing: isCapturing,
          isSingleCapture: isSingleCapture,
          hostSuffix: hostSuffix,
          onDurationChanged: onDurationChanged,
          onSnapshot: onSnapshot,
        ),
      ],
    );
  }
}

/// The right-aligned duration + Snapshot grouping of [QuickCaptureBar].
///
/// Both controls live on a single rounded [surfaceAlt] pill with a divider
/// between them so the eye reads "set the exposure, then fire" as one unit
/// instead of two stray controls. The duration uses a compact inline field
/// (label beside the value, not stacked) to keep the bar a single tidy line.
class _CaptureCluster extends StatefulWidget {
  final NightshadeColors colors;
  final ExposureSettings exposureSettings;
  final bool isConnected;
  final bool isCapturing;
  final bool isSingleCapture;
  final String hostSuffix;
  final ValueChanged<double> onDurationChanged;
  final VoidCallback onSnapshot;

  const _CaptureCluster({
    required this.colors,
    required this.exposureSettings,
    required this.isConnected,
    required this.isCapturing,
    required this.isSingleCapture,
    required this.hostSuffix,
    required this.onDurationChanged,
    required this.onSnapshot,
  });

  @override
  State<_CaptureCluster> createState() => _CaptureClusterState();
}

class _CaptureClusterState extends State<_CaptureCluster> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatted);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(_CaptureCluster oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mirror EditableCompactInput: only adopt external changes while the field
    // is idle, so we never clobber the value mid-edit.
    if (!_isEditing && _formatted != _controller.text) {
      _controller.text = _formatted;
    }
  }

  String get _formatted =>
      widget.exposureSettings.exposureTime.toStringAsFixed(0);

  void _commit() {
    setState(() => _isEditing = false);
    final parsed = double.tryParse(_controller.text);
    if (parsed != null && parsed > 0) {
      widget.onDurationChanged(parsed);
    } else {
      // Reject invalid input by snapping back to the last good value.
      _controller.text = _formatted;
    }
  }

  void _beginEdit() {
    setState(() => _isEditing = true);
    _focusNode.requestFocus();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final captureEnabled = widget.isConnected && !widget.isCapturing;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusButton,
        border: Border.all(
          color: _isEditing ? colors.primary : colors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Inline duration field.
          GestureDetector(
            onTap: _beginEdit,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NightshadeTokens.spaceMd,
                vertical: NightshadeTokens.spaceSm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Dur${widget.hostSuffix}',
                    style: TextStyle(
                      fontSize: NightshadeTokens.fontSizePanelCaption,
                      fontWeight: FontWeight.w600,
                      color: colors.textMuted,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  SizedBox(
                    width: 34,
                    child: _isEditing
                        ? TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            textAlign: TextAlign.right,
                            keyboardType: TextInputType.number,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              color: colors.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onSubmitted: (_) => _commit(),
                          )
                        : Text(
                            _formatted,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              color: colors.textPrimary,
                            ),
                          ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    's',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Divider between "set exposure" and "fire".
          Container(width: 1, height: 24, color: colors.border),
          // Snapshot action.
          SmallButton(
            label: widget.isSingleCapture ? 'Taking...' : 'Snapshot',
            icon: widget.isSingleCapture
                ? LucideIcons.loader2
                : LucideIcons.camera,
            colors: colors,
            isEnabled: captureEnabled,
            onTap: widget.onSnapshot,
          ),
        ],
      ),
    );
  }
}
