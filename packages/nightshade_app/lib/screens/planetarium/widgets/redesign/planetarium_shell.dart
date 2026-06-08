part of '../../planetarium_screen.dart';

/// Adaptive "top command bar + dockable panels" planetarium layout.
///
/// ONE layout for desktop and phone. Structure:
///
/// ```
/// Column[
///   PlanetariumCommandBar,
///   Expanded[ Stack[
///     FullScreenSkyView (fills),
///     FovRingsOverlay / MultiFovOverlay,
///     CompassHud / SkyMinimap,
///     BottomInfoBar (bottom), TimeControlPanel (bottom-center),
///     right-docked Layers / Plan panels (desktop) ,
///     ObjectInfoPopup,
///   ] ]
/// ]
/// ```
///
/// On phone (`width < BreakpointTokens.breakpointPhone`) the right-docked panels
/// become bottom sheets and the command bar condenses (collapses the View
/// segment into Tools). The Plan/Object panel reuses the existing SidebarTabs
/// (Tonight/Catalog/Lists/Search/Info) + SearchHeader.
extension _PlanetariumShell on _PlanetariumScreenState {
  Widget _buildShell(BuildContext context, NightshadeColors colors,
      SelectedObjectState selectedObject) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = Responsive.isPhone(context) ||
            BreakpointTokens.isPhone(constraints.maxWidth);

        return Column(
          children: [
            PlanetariumCommandBar(
              compact: isPhone,
              layersOpen: !isPhone && _layersPanelOpen,
              panelOpen: !isPhone && _planPanelOpen,
              showFov: _showFOV,
              onToggleLayers: () => _toggleShellPanel(_ShellPanel.layers,
                  isPhone: isPhone, colors: colors),
              onTogglePanel: () => _toggleShellPanel(_ShellPanel.plan,
                  isPhone: isPhone, colors: colors),
              onOpenSearch: () =>
                  _openPlanPanelOnSearch(isPhone: isPhone, colors: colors),
              onToggleFov: () => _update(() => _showFOV = !_showFOV),
              onResetView: _resetView,
              onExportChart: () => _exportFinderChart(context),
            ),
            Expanded(
              child: Stack(
                key: _skyViewKey,
                children: [
                  // --- Sky canvas (fills) ---
                  Positioned.fill(
                    child: GestureDetector(
                      onSecondaryTapUp: (details) =>
                          _showContextMenu(context, details.globalPosition),
                      child: Consumer(
                        builder: (context, ref, _) {
                          final observedIds = ref
                                  .watch(observedCatalogIdsProvider)
                                  .valueOrNull ??
                              {};
                          final listedIds = ref
                                  .watch(listedCatalogIdsProvider)
                                  .valueOrNull ??
                              {};
                          final bortleClass = ref.watch(bortleClassProvider);
                          final horizonProfile =
                              ref.watch(horizonProfileProvider);
                          return FullScreenSkyView(
                            key: PlanetariumTutorialKeys.skyView,
                            showFOV: _showFOV,
                            onObjectTapped: _handleObjectTapped,
                            observedObjectIds: observedIds,
                            listedObjectIds: listedIds,
                            bortleClass: bortleClass,
                            measurementMode:
                                ref.watch(measurementModeProvider),
                            horizonAltitudes: horizonProfile.isFlat
                                ? null
                                : List<double>.generate(
                                    360,
                                    (az) => horizonProfile
                                        .altitudeAtAzimuth(az.toDouble())),
                          );
                        },
                      ),
                    ),
                  ),

                  // --- FOV reference rings ---
                  Positioned.fill(
                    child: Consumer(
                      builder: (context, ref, _) {
                        if (!ref.watch(showFovRingsProvider)) {
                          return const SizedBox.shrink();
                        }
                        final viewState = ref.watch(skyViewStateProvider);
                        return IgnorePointer(
                          child: FovRingsOverlay(
                            fieldOfView: viewState.fieldOfView,
                            centerRA: viewState.centerRA,
                            centerDec: viewState.centerDec,
                          ),
                        );
                      },
                    ),
                  ),

                  // --- Multi-rig FOV framing presets (interactive) ---
                  if (_showFOV)
                    Positioned.fill(
                      child: Consumer(
                        builder: (context, ref, _) {
                          final viewState = ref.watch(skyViewStateProvider);
                          return MultiFovOverlay(
                            centerRaHours: viewState.centerRA,
                            centerDecDeg: viewState.centerDec,
                            fieldOfViewDeg: viewState.fieldOfView,
                            viewRotationDeg: viewState.rotation,
                          );
                        },
                      ),
                    ),

                  // --- Performance HUD (debug / opt-in) ---
                  if (kDebugMode || ref.watch(showPerfHudProvider))
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _PerfHud(colors: colors),
                    ),

                  // --- Compass HUD ---
                  Positioned(
                    left: AdaptiveSizing.of(context).edgePadding,
                    bottom: 56,
                    child: Consumer(
                      builder: (context, ref, _) {
                        if (!ref.watch(showCompassHudProvider)) {
                          return const SizedBox.shrink();
                        }
                        final sizing = AdaptiveSizing.of(context);
                        final (az, alt) = ref.watch(viewCenterAltAzProvider);
                        return CompassHud(
                          azimuth: az,
                          altitude: alt,
                          size: sizing.compassSize,
                          showAltitude: !sizing.useCondensedHud,
                        );
                      },
                    ),
                  ),

                  // --- Mini-map ---
                  Positioned(
                    right: AdaptiveSizing.of(context).edgePadding,
                    bottom: 56,
                    child: Consumer(
                      builder: (context, ref, _) {
                        if (!ref.watch(showMinimapProvider)) {
                          return const SizedBox.shrink();
                        }
                        final sizing = AdaptiveSizing.of(context);
                        final (az, alt) = ref.watch(viewCenterAltAzProvider);
                        final viewState = ref.watch(skyViewStateProvider);
                        return SkyMinimap(
                          azimuth: az,
                          altitude: alt,
                          fieldOfView: viewState.fieldOfView,
                          rotation: viewState.rotation,
                          size: sizing.minimapSize,
                          onTap: (tapAz, tapAlt) {
                            final location =
                                ref.read(observerLocationProvider);
                            final time = ref.read(observationTimeProvider);
                            final lst =
                                AstronomyCalculations.localSiderealTime(
                                    time.time, location.longitude);
                            final (ra, dec) =
                                AstronomyCalculations.horizontalToEquatorial(
                              altDeg: tapAlt,
                              azDeg: tapAz,
                              latitudeDeg: location.latitude,
                              lstHours: lst,
                            );
                            ref
                                .read(skyViewStateProvider.notifier)
                                .setCenter(ra / 15, dec);
                          },
                        );
                      },
                    ),
                  ),

                  // --- Time-travel panel (bottom-center) ---
                  Positioned(
                    bottom: 44,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: TimeControlPanel(
                        backgroundColor:
                            colors.surface.withValues(alpha: 0.9),
                        textColor: colors.textPrimary,
                        accentColor: colors.accent,
                        compact: isPhone,
                      ),
                    ),
                  ),

                  // --- Info bar (slim, bottom) ---
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: BottomInfoBar(colors: colors),
                  ),

                  // --- Right-docked panels (desktop only) ---
                  if (!isPhone && _layersPanelOpen)
                    Positioned(
                      top: 0,
                      right: 0,
                      bottom: 0,
                      child: _DockedPanel(
                        colors: colors,
                        width: _shellPanelWidth(constraints.maxWidth),
                        child: LayersPanel(
                          showFov: _showFOV,
                          onToggleFov: () =>
                              _update(() => _showFOV = !_showFOV),
                          onClose: () =>
                              _update(() => _layersPanelOpen = false),
                        ),
                      ),
                    ),
                  if (!isPhone && _planPanelOpen)
                    Positioned(
                      top: 0,
                      right: 0,
                      bottom: 0,
                      child: _DockedPanel(
                        colors: colors,
                        width: _shellPanelWidth(constraints.maxWidth),
                        child: _buildPlanPanelContent(
                          colors,
                          selectedObject,
                          onClose: () =>
                              _update(() => _planPanelOpen = false),
                        ),
                      ),
                    ),

                  // --- Object info popup (on selection) ---
                  if (_showPopup && _popupObject != null)
                    ObjectInfoPopup(
                      colors: colors,
                      object: _popupObject!,
                      coordinates:
                          _popupCoordinates ?? _popupObject!.coordinates,
                      selectedObjectState: selectedObject,
                      position: _popupPosition,
                      onDismiss: _dismissPopup,
                      onSendToFraming: _sendToFraming,
                      onAddToSequencer: _addToSequencer,
                      onSlewToTarget: _handleSlewToTarget,
                      onSlewAndCenter: () => _handleSlewAndCenter(
                        _popupCoordinates ?? _popupObject!.coordinates,
                        _popupObject!.name,
                      ),
                      onSlewCenterRotate: () => _handleSlewCenterRotate(
                        _popupCoordinates ?? _popupObject!.coordinates,
                        _popupObject!.name,
                      ),
                      onExportChart: () => _exportFinderChart(context),
                      hasRotator:
                          ref.watch(rotatorStateProvider).connectionState ==
                              DeviceConnectionState.connected,
                    ),

                  if (_showHelpOverlay)
                    _KeyboardShortcutsOverlay(
                      onDismiss: () =>
                          _update(() => _showHelpOverlay = false),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  double _shellPanelWidth(double maxWidth) {
    return clampPanelWidth(maxWidth, fraction: 0.30, min: 280, max: 380);
  }

  /// Plan/object panel content — reuses the exact desktop composition:
  /// [SearchHeader] + DefaultTabController(5) hosting [SidebarTabs] and the five
  /// tab bodies.
  Widget _buildPlanPanelContent(
    NightshadeColors colors,
    SelectedObjectState selectedObject, {
    VoidCallback? onClose,
  }) {
    return Column(
      children: [
        if (onClose != null)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: Icon(NightshadeIcons.close,
                  size: 18, color: colors.textSecondary),
              tooltip: 'Close',
              onPressed: onClose,
            ),
          ),
        SearchHeader(
          colors: colors,
          controller: _searchController,
          onSearch: (query) {
            ref.read(objectSearchProvider.notifier).search(query);
          },
        ),
        Expanded(
          child: DefaultTabController(
            length: 5,
            child: Column(
              children: [
                SidebarTabs(colors: colors),
                Expanded(
                  child: TabBarView(
                    children: [
                      TonightTab(colors: colors),
                      CatalogTab(colors: colors),
                      ListsTab(colors: colors),
                      SearchResultsTab(colors: colors),
                      Consumer(
                        builder: (context, ref, _) => InfoTab(
                          colors: colors,
                          selectedObject: ref.watch(selectedObjectProvider),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Toggle a docked panel. On desktop the panels are mutually exclusive (only
  /// one docks at a time). On phone they open as bottom sheets.
  void _toggleShellPanel(_ShellPanel panel,
      {required bool isPhone, required NightshadeColors colors}) {
    if (isPhone) {
      switch (panel) {
        case _ShellPanel.layers:
          _showLayersSheet(context, colors);
          break;
        case _ShellPanel.plan:
          _showSidebarPanelSheet(context, colors);
          break;
      }
      return;
    }
    _update(() {
      switch (panel) {
        case _ShellPanel.layers:
          _layersPanelOpen = !_layersPanelOpen;
          if (_layersPanelOpen) _planPanelOpen = false;
          break;
        case _ShellPanel.plan:
          _planPanelOpen = !_planPanelOpen;
          if (_planPanelOpen) _layersPanelOpen = false;
          break;
      }
    });
  }

  void _openPlanPanelOnSearch(
      {required bool isPhone, required NightshadeColors colors}) {
    if (isPhone) {
      _showMobileSearchDialog(context, colors);
      return;
    }
    _update(() {
      _planPanelOpen = true;
      _layersPanelOpen = false;
    });
  }

  /// Layers panel as a phone bottom sheet (full-width slide-up).
  void _showLayersSheet(BuildContext context, NightshadeColors colors) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(NightshadeTokens.radiusInline8)),
            border: Border.all(color: colors.border),
          ),
          child: SafeArea(
            top: false,
            child: LayersPanel(
              showFov: _showFOV,
              onToggleFov: () {
                _update(() => _showFOV = !_showFOV);
                Navigator.of(sheetContext).pop();
              },
              onClose: () => Navigator.of(sheetContext).pop(),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ShellPanel { layers, plan }

/// Right-docked panel container with an animated entrance.
class _DockedPanel extends StatelessWidget {
  const _DockedPanel({
    required this.colors,
    required this.width,
    required this.child,
  });

  final NightshadeColors colors;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: NightshadeTokens.durationNormal,
      curve: NightshadeTokens.curveSnappy,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(width * (1 - t), 0),
        child: Opacity(opacity: t, child: child),
      ),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(left: BorderSide(color: colors.border)),
        ),
        child: child,
      ),
    );
  }
}

/// Compact perf overlay (FPS / UI / GPU).
class _PerfHud extends ConsumerWidget {
  const _PerfHud({required this.colors});

  final NightshadeColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitor = ref.watch(performanceMonitorProvider);
    final refreshRate = ref.watch(displayRefreshRateProvider);
    final fps = monitor.estimatedFps;
    final cappedFps = fps > refreshRate ? refreshRate : fps;
    final buildMs = monitor.averageBuildTime;
    final rasterMs = monitor.averageRasterTime;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: DefaultTextStyle(
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: NightshadeTypography.fontSize12,
            fontWeight: FontWeight.w600,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'FPS ${cappedFps.toStringAsFixed(1)} / ${refreshRate.toStringAsFixed(0)}Hz',
              ),
              const SizedBox(height: 2),
              Text(
                'UI ${buildMs.toStringAsFixed(1)}ms  GPU ${rasterMs.toStringAsFixed(1)}ms',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
