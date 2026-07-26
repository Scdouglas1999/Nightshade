import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import '../view_controls.dart'
    show ProjectionSelectorButton, QualitySettingsButton;
import '../mobile_widgets.dart' show CompassCalibrationDialog;
import '../../providers/device_orientation_provider.dart';
import '../../../../services/mount_command_service.dart';
import '../../../../widgets/tutorial_keys/planetarium_keys.dart';

/// Top command bar for the redesigned planetarium shell.
///
/// One slim, full-width strip of icon-button segments (Search · View · Layers ·
/// Tools · Mount · Panels) that replaces the old left rail + right FilterSidebar
/// + top-overlay toggle cluster + mobile FAB column. Each segment uses the same
/// [CommandBarIconButton] visual idiom so the whole bar reads as one language.
///
/// The bar is the only chrome that mounts persistent controls; the Layers panel
/// (visibility) and the Plan/Object panel (Tonight/Catalog/Lists/Search/Info)
/// are toggled from here and dock on the right of the shell.
class PlanetariumCommandBar extends ConsumerWidget {
  const PlanetariumCommandBar({
    super.key,
    required this.compact,
    required this.layersOpen,
    required this.panelOpen,
    required this.showFov,
    required this.onToggleLayers,
    required this.onTogglePanel,
    required this.onOpenSearch,
    required this.onToggleFov,
    required this.onResetView,
    required this.onExportChart,
  });

  /// Phone-tier layout: collapse the less-used View segment into Tools so the
  /// bar fits a narrow viewport.
  final bool compact;
  final bool layersOpen;
  final bool panelOpen;
  final bool showFov;
  final VoidCallback onToggleLayers;
  final VoidCallback onTogglePanel;
  final VoidCallback onOpenSearch;
  final VoidCallback onToggleFov;
  final VoidCallback onResetView;
  final VoidCallback onExportChart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final viewState = ref.watch(skyViewStateProvider);
    final mountState = ref.watch(mountStateProvider);
    final mountConnected =
        mountState.connectionState == DeviceConnectionState.connected;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          // ---- Search ------------------------------------------------------
          _SearchEntry(onTap: onOpenSearch, compact: compact),
          const _BarDivider(),
          // ---- View --------------------------------------------------------
          CommandBarIconButton(
            icon: NightshadeIcons.home,
            tooltip: 'Reset view (center 0,0, FOV 60)',
            onTap: onResetView,
          ),
          if (!compact) ...[
            CommandBarIconButton(
              icon: NightshadeIcons.layers,
              tooltip: viewState.viewMode == SkyViewMode.horizontal
                  ? 'Alt/Az view — tap for Equatorial'
                  : 'Equatorial view — tap for Alt/Az',
              isActive: viewState.viewMode == SkyViewMode.horizontal,
              onTap: () {
                final notifier = ref.read(skyViewStateProvider.notifier);
                notifier.setViewMode(
                  viewState.viewMode == SkyViewMode.horizontal
                      ? SkyViewMode.equatorial
                      : SkyViewMode.horizontal,
                );
              },
            ),
            _BarHostedButton(child: ProjectionSelectorButton(colors: colors)),
          ],
          const _BarDivider(),
          // ---- Layers ------------------------------------------------------
          CommandBarIconButton(
            icon: NightshadeIcons.list,
            tooltip: 'Layers',
            isActive: layersOpen,
            onTap: onToggleLayers,
          ),
          const _BarDivider(),
          // ---- Tools (overflow) -------------------------------------------
          _ToolsMenu(
            colors: colors,
            compact: compact,
            showFov: showFov,
            viewState: viewState,
            onToggleFov: onToggleFov,
            onExportChart: onExportChart,
          ),
          const Spacer(),
          // ---- Mount (only when connected) --------------------------------
          if (mountConnected) ...[
            _MountControls(mountState: mountState),
            const _BarDivider(),
          ],
          // ---- Panels ------------------------------------------------------
          CommandBarIconButton(
            key: PlanetariumTutorialKeys.search,
            icon: LucideIcons.panelRight,
            tooltip: 'Plan / object panel',
            isActive: panelOpen,
            onTap: onTogglePanel,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// Compact search entry that opens the Plan/Object panel on its Search tab.
class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap, required this.compact});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    if (compact) {
      return CommandBarIconButton(
        icon: NightshadeIcons.search,
        tooltip: 'Search',
        onTap: onTap,
      );
    }
    return NightshadeTooltip(
      message: 'Search the sky',
      position: NightshadeTooltipPosition.bottom,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        child: Container(
          height: 32,
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.surfaceAlt.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            border: Border.all(color: colors.border.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Icon(NightshadeIcons.search, size: 15, color: colors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Search',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize13,
                    color: colors.textMuted,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.8),
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline4),
                  border:
                      Border.all(color: colors.border.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '⌘K',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize10,
                    color: colors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slew / stop mount controls, shown only when a mount is connected.
class _MountControls extends ConsumerWidget {
  const _MountControls({required this.mountState});

  final MountState mountState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSlewing = mountState.isSlewing;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CommandBarIconButton(
          icon: LucideIcons.octagon,
          tooltip: 'Stop slew',
          isDestructive: true,
          enabled: isSlewing,
          onTap: isSlewing
              ? () => ref.read(mountCommandServiceProvider).abortSlew()
              : null,
        ),
      ],
    );
  }
}

/// Tools overflow menu. Houses the less-frequent canvas toggles plus the
/// quality / export popups (hosted as live widgets so they keep their own menus).
class _ToolsMenu extends ConsumerWidget {
  const _ToolsMenu({
    required this.colors,
    required this.compact,
    required this.showFov,
    required this.viewState,
    required this.onToggleFov,
    required this.onExportChart,
  });

  final NightshadeColors colors;
  final bool compact;
  final bool showFov;
  final SkyViewState viewState;
  final VoidCallback onToggleFov;
  final VoidCallback onExportChart;

  void _toggle(WidgetRef ref, StateProvider<bool> p) {
    final n = ref.read(p.notifier);
    n.state = !n.state;
  }

  // Gyro sky aiming is a phone-only sensor feature. Mirrors
  // MobileViewControls._handleGyroscopeToggle: first activation requires the
  // one-time compass-calibration acknowledgement; turning aiming off also drops
  // mount sync.
  void _handleGyroscopeToggle(BuildContext context, WidgetRef ref) {
    final isEnabled = ref.read(gyroscopeAimingEnabledProvider);
    if (!isEnabled) {
      final calibrated = ref.read(compassCalibrationAcknowledgedProvider);
      if (!calibrated) {
        _showCalibrationDialog(context, ref);
        return;
      }
    } else {
      ref.read(gyroscopeMountSyncProvider.notifier).state = false;
    }
    ref.read(gyroscopeAimingEnabledProvider.notifier).state = !isEnabled;
  }

  void _showCalibrationDialog(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (context) => const CompassCalibrationDialog(),
    ).then((result) {
      if (result == true) {
        ref.read(compassCalibrationAcknowledgedProvider.notifier).state = true;
        ref.read(gyroscopeAimingEnabledProvider.notifier).state = true;
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final measurement = ref.watch(measurementModeProvider);
    final fovRings = ref.watch(showFovRingsProvider);
    final nightVision = ref.watch(nightVisionModeProvider);
    final compass = ref.watch(showCompassHudProvider);
    final minimap = ref.watch(showMinimapProvider);
    final perfHud = ref.watch(showPerfHudProvider);
    // Gyro sky aiming (phone-only): the sensors and the calibration dialog
    // only exist on mobile, so gate the item on platform, not the width-based
    // `compact` flag.
    final gyroAiming = ref.watch(gyroscopeAimingEnabledProvider);
    final gyroMountSync = ref.watch(gyroscopeMountSyncProvider);
    final mountConnected = ref.watch(mountStateProvider).connectionState ==
        DeviceConnectionState.connected;
    final isMobilePlatform = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;

    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String label, {
      bool active = false,
    }) {
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (active)
              Icon(NightshadeIcons.success, size: 14, color: colors.accent),
          ],
        ),
      );
    }

    return NightshadeTooltip(
      message: 'Tools',
      position: NightshadeTooltipPosition.bottom,
      child: PopupMenuButton<String>(
        tooltip: '',
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          side: BorderSide(color: colors.border),
        ),
        icon: Icon(NightshadeIcons.settings2,
            size: 18, color: colors.textSecondary),
        onSelected: (value) {
          switch (value) {
            case 'measurement':
              _toggle(ref, measurementModeProvider);
              break;
            case 'fov':
              onToggleFov();
              break;
            case 'fovRings':
              _toggle(ref, showFovRingsProvider);
              break;
            case 'nightVision':
              _toggle(ref, nightVisionModeProvider);
              break;
            case 'compass':
              _toggle(ref, showCompassHudProvider);
              break;
            case 'gyroAim':
              _handleGyroscopeToggle(context, ref);
              break;
            case 'gyroMountSync':
              _toggle(ref, gyroscopeMountSyncProvider);
              break;
            case 'minimap':
              _toggle(ref, showMinimapProvider);
              break;
            case 'perfHud':
              _toggle(ref, showPerfHudProvider);
              break;
            case 'export':
              onExportChart();
              break;
            case 'altaz':
              final n = ref.read(skyViewStateProvider.notifier);
              n.setViewMode(viewState.viewMode == SkyViewMode.horizontal
                  ? SkyViewMode.equatorial
                  : SkyViewMode.horizontal);
              break;
          }
        },
        itemBuilder: (context) => [
          // On phone the View segment collapses into here.
          if (compact)
            item(
              'altaz',
              NightshadeIcons.layers,
              viewState.viewMode == SkyViewMode.horizontal
                  ? 'Alt/Az view'
                  : 'Equatorial view',
              active: viewState.viewMode == SkyViewMode.horizontal,
            ),
          if (compact)
            PopupMenuItem<String>(
              value: 'projection_host',
              enabled: false,
              child: Row(
                children: [
                  Icon(NightshadeIcons.globe,
                      size: 16, color: colors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Projection',
                        style: TextStyle(color: colors.textPrimary)),
                  ),
                  ProjectionSelectorButton(colors: colors),
                ],
              ),
            ),
          item(
              'measurement', NightshadeIcons.ruler, 'Measure (separation / PA)',
              active: measurement),
          item('fov', NightshadeIcons.frame, 'FOV indicator', active: showFov),
          item(
              'fovRings', NightshadeIcons.target, 'FOV rings (Telrad / finder)',
              active: fovRings),
          item('nightVision', NightshadeIcons.moon, 'Night vision (red)',
              active: nightVision),
          item('compass', NightshadeIcons.compass, 'Compass HUD',
              active: compass),
          if (isMobilePlatform)
            item('gyroAim', LucideIcons.move3d, 'Gyro sky aiming',
                active: gyroAiming),
          if (isMobilePlatform && gyroAiming && mountConnected)
            item('gyroMountSync', NightshadeIcons.star, 'Sync mount to aim',
                active: gyroMountSync),
          item('minimap', NightshadeIcons.map, 'Minimap', active: minimap),
          const PopupMenuDivider(),
          // Render quality + export are hosted live so they keep their own
          // submenus; tapping the row delegates into them.
          PopupMenuItem<String>(
            value: 'quality_host',
            enabled: false,
            child: Row(
              children: [
                Icon(NightshadeIcons.settings2,
                    size: 16, color: colors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Render quality',
                      style: TextStyle(color: colors.textPrimary)),
                ),
                QualitySettingsButton(colors: colors),
              ],
            ),
          ),
          item('export', NightshadeIcons.download, 'Export finder chart'),
          const PopupMenuDivider(),
          item('perfHud', NightshadeIcons.activity,
              'Performance overlay (debug)',
              active: perfHud),
        ],
      ),
    );
  }
}

/// Shared icon-button idiom for the whole command bar — one visual language,
/// active state via tokens, with a tooltip.
class CommandBarIconButton extends StatefulWidget {
  const CommandBarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.isActive = false,
    this.isDestructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isActive;
  final bool isDestructive;
  final bool enabled;

  @override
  State<CommandBarIconButton> createState() => _CommandBarIconButtonState();
}

class _CommandBarIconButtonState extends State<CommandBarIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final enabled = widget.enabled && widget.onTap != null;

    Color fg;
    if (!enabled) {
      fg = colors.textMuted.withValues(alpha: 0.4);
    } else if (widget.isDestructive) {
      fg = colors.error;
    } else if (widget.isActive) {
      fg = colors.accent;
    } else {
      fg = colors.textSecondary;
    }

    final bg = widget.isActive
        ? colors.accent.withValues(alpha: 0.15)
        : (_hovered && enabled
            ? colors.surfaceAlt.withValues(alpha: 0.6)
            : Colors.transparent);

    return NightshadeTooltip(
      message: widget.tooltip,
      position: NightshadeTooltipPosition.bottom,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: enabled ? widget.onTap : null,
            child: AnimatedContainer(
              duration: NightshadeTokens.durationFast,
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                border: widget.isActive
                    ? Border.all(color: colors.accent.withValues(alpha: 0.45))
                    : null,
              ),
              child: Icon(widget.icon, size: 17, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin vertical separator between command-bar segments.
class _BarDivider extends StatelessWidget {
  const _BarDivider();

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: colors.border.withValues(alpha: 0.5),
    );
  }
}

/// Wraps a legacy HUD popup button (white-on-dark) so it sits comfortably in the
/// themed command bar at the right size.
class _BarHostedButton extends StatelessWidget {
  const _BarHostedButton({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: Center(child: child),
    );
  }
}
