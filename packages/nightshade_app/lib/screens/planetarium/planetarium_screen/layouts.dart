part of '../planetarium_screen.dart';

extension _PlanetariumScreenLayouts on _PlanetariumScreenState {
  Widget _buildMobileLayout(BuildContext context, NightshadeColors colors,
      SelectedObjectState selectedObject) {
    final sizing = AdaptiveSizing.of(context);
    final media = MediaQuery.of(context);
    final topBarHeight = media.padding.top + 48;
    final viewControlsTop = topBarHeight + 8;
    final slewControlsTop = viewControlsTop + 128;
    final bottomHudInset = media.padding.bottom + 48;
    final timePanelBottom = bottomHudInset + 2;
    final fabColumnBottom = bottomHudInset + 12;

    return Stack(
      key: _skyViewKey,
      children: [
        Positioned.fill(
          child: GestureDetector(
            onSecondaryTapUp: (details) =>
                _showContextMenu(context, details.globalPosition),
            child: Consumer(
              builder: (context, ref, _) {
                final observedIds =
                    ref.watch(observedCatalogIdsProvider).valueOrNull ?? {};
                final listedIds =
                    ref.watch(listedCatalogIdsProvider).valueOrNull ?? {};
                final bortleClass = ref.watch(bortleClassProvider);
                final horizonProfile = ref.watch(horizonProfileProvider);
                return FullScreenSkyView(
                  key: PlanetariumTutorialKeys.skyView,
                  showFOV: _showFOV,
                  onObjectTapped: _handleObjectTapped,
                  observedObjectIds: observedIds,
                  listedObjectIds: listedIds,
                  bortleClass: bortleClass,
                  horizonAltitudes: horizonProfile.isFlat
                      ? null
                      : List<double>.generate(
                          360,
                          (az) =>
                              horizonProfile.altitudeAtAzimuth(az.toDouble())),
                );
              },
            ),
          ),
        ),

        // FOV reference rings (Telrad / finder) — non-interactive angular
        // overlay centered on the view center. Scales with zoom.
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

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: MobileTopOverlay(colors: colors),
        ),

        Positioned(
          top: viewControlsTop,
          left: sizing.edgePadding,
          child: MobileViewControls(
            colors: colors,
            showFOV: _showFOV,
            onToggleFOV: () => _update(() => _showFOV = !_showFOV),
          ),
        ),

        Positioned(
          top: slewControlsTop,
          left: sizing.edgePadding,
          child: MobileSlewControls(
            colors: colors,
            slewMode: _slewMode,
            onToggleSlewMode: _toggleSlewMode,
            onStopSlew: _handleStopSlew,
          ),
        ),

        Positioned(
          left: sizing.edgePadding,
          bottom: 90 + sizing.edgePadding,
          child: Consumer(
            builder: (context, ref, _) {
              final showCompass = ref.watch(showCompassHudProvider);
              if (!showCompass) return const SizedBox.shrink();

              final (az, alt) = ref.watch(viewCenterAltAzProvider);
              return CompassHud(
                azimuth: az,
                altitude: alt,
                size: 60,
                showAltitude: false,
              );
            },
          ),
        ),

        Positioned(
          right: sizing.edgePadding,
          bottom: 200 + sizing.edgePadding,
          child: Consumer(
            builder: (context, ref, _) {
              final showMinimap = ref.watch(showMinimapProvider);
              if (!showMinimap) return const SizedBox.shrink();

              final (az, alt) = ref.watch(viewCenterAltAzProvider);
              final viewState = ref.watch(skyViewStateProvider);

              return SkyMinimap(
                azimuth: az,
                altitude: alt,
                fieldOfView: viewState.fieldOfView,
                rotation: viewState.rotation,
                size: 80,
                onTap: (tapAz, tapAlt) {
                  final location = ref.read(observerLocationProvider);
                  final time = ref.read(observationTimeProvider);
                  final lst = AstronomyCalculations.localSiderealTime(
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

        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: MobileBottomInfoBar(colors: colors),
        ),

        Positioned(
          bottom: timePanelBottom,
          left: sizing.edgePadding,
          child: TimeControlPanel(
            backgroundColor: colors.surface.withValues(alpha: 0.9),
            textColor: colors.textPrimary,
            accentColor: colors.accent,
            compact: true,
          ),
        ),

        Positioned(
          right: sizing.edgePadding,
          bottom: fabColumnBottom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                key: PlanetariumTutorialKeys.search,
                heroTag: 'search_fab',
                backgroundColor: colors.surface.withValues(alpha: 0.9),
                onPressed: () => _showMobileSearchDialog(context, colors),
                child: Icon(LucideIcons.search,
                    size: 20, color: colors.textPrimary),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.small(
                key: PlanetariumTutorialKeys.filterBtn,
                heroTag: 'filter_fab',
                backgroundColor: colors.surface.withValues(alpha: 0.9),
                onPressed: () => _showFilterBottomSheet(context),
                child: Icon(LucideIcons.slidersHorizontal,
                    size: 20, color: colors.textPrimary),
              ),
              const SizedBox(height: 12),
              if (selectedObject.object != null)
                FloatingActionButton(
                  heroTag: 'info_fab',
                  backgroundColor: colors.primary,
                  onPressed: () => _showObjectInfoBottomSheet(context, colors),
                  child: const Icon(LucideIcons.info,
                      size: 24, color: Colors.white),
                ),
            ],
          ),
        ),

        // MobileSelectedObjectHud removed: the ObjectInfoPopup (shown on click)
        // provides the same information plus detailed coordinates, alt/az,
        // and multiple action buttons. Having both caused duplicate cards.

        if (_showPopup && _popupObject != null)
          ObjectInfoPopup(
            colors: colors,
            object: _popupObject!,
            coordinates: _popupCoordinates ?? _popupObject!.coordinates,
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
            hasRotator: ref.watch(rotatorStateProvider).connectionState ==
                DeviceConnectionState.connected,
          ),

        if (_showHelpOverlay)
          _KeyboardShortcutsOverlay(
            onDismiss: () => _update(() => _showHelpOverlay = false),
          ),
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context, NightshadeColors colors,
      SelectedObjectState selectedObject) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelMax = clampPanelWidth(
          constraints.maxWidth,
          fraction: 0.38,
          min: 250,
          max: 500,
        );
        final panelInitial = clampPanelWidth(
          constraints.maxWidth,
          fraction: 0.28,
          min: 250,
          max: 340,
        );
        final panelMin = math.min(
          panelMax,
          clampPanelWidth(
            constraints.maxWidth,
            fraction: 0.22,
            min: 200,
            max: 280,
          ),
        );

        return Stack(
          children: [
            Row(
              children: [
                Expanded(
                  child: Stack(
                    key: _skyViewKey,
                    children: [
                      GestureDetector(
                        onSecondaryTapUp: (details) =>
                            _showContextMenu(context, details.globalPosition),
                        child: Consumer(
                          builder: (context, ref, _) {
                            final observedIds = ref
                                    .watch(observedCatalogIdsProvider)
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
                              bortleClass: bortleClass,
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

                      // FOV reference rings (Telrad / finder) — non-interactive
                      // angular overlay centered on the view center. Scales with
                      // zoom via skyViewState FOV.
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

                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: SizedBox(
                          width: double.infinity,
                          child: TopOverlay(colors: colors),
                        ),
                      ),

                      if (kDebugMode || ref.watch(showPerfHudProvider))
                        Positioned(
                          top: 60,
                          right: 16,
                          child: Consumer(
                            builder: (context, ref, _) {
                              final monitor =
                                  ref.watch(performanceMonitorProvider);
                              final refreshRate =
                                  ref.watch(displayRefreshRateProvider);
                              final fps = monitor.estimatedFps;
                              final cappedFps =
                                  fps > refreshRate ? refreshRate : fps;
                              final buildMs = monitor.averageBuildTime;
                              final rasterMs = monitor.averageRasterTime;

                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.surface.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: colors.border),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  child: DefaultTextStyle(
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: SizedBox(
                          width: double.infinity,
                          child: BottomInfoBar(colors: colors),
                        ),
                      ),

                      // Left tool rail — view controls stacked directly above the
                      // slew controls in a single scrollable column. Previously
                      // these were two independently-Positioned panels (top:60 and
                      // a fixed top:220); as ViewControls grew past ~160px tall it
                      // overran the slew panel and they overlapped. Binding the
                      // rail between top:60 and bottom:120 lets it scroll on short
                      // windows instead of colliding with the bottom panels.
                      Positioned(
                        top: 60,
                        left: 16,
                        bottom: 120,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ViewControls(
                                colors: colors,
                                showFOV: _showFOV,
                                onToggleFOV: () =>
                                    _update(() => _showFOV = !_showFOV),
                              ),
                              const SizedBox(height: 8),
                              SlewControls(
                                colors: colors,
                                slewMode: _slewMode,
                                onToggleSlewMode: _toggleSlewMode,
                                onStopSlew: _handleStopSlew,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // SelectedObjectHud removed: the ObjectInfoPopup (shown on click)
                      // provides the same information plus detailed coordinates, alt/az,
                      // and multiple action buttons. Having both caused duplicate cards.

                      Positioned(
                        left: AdaptiveSizing.of(context).edgePadding,
                        bottom: AdaptiveSizing.of(context).edgePadding,
                        child: Consumer(
                          builder: (context, ref, _) {
                            final showCompass =
                                ref.watch(showCompassHudProvider);
                            if (!showCompass) {
                              return const SizedBox.shrink();
                            }

                            final sizing = AdaptiveSizing.of(context);
                            final (az, alt) =
                                ref.watch(viewCenterAltAzProvider);
                            return CompassHud(
                              azimuth: az,
                              altitude: alt,
                              size: sizing.compassSize,
                              showAltitude: !sizing.useCondensedHud,
                            );
                          },
                        ),
                      ),

                      Positioned(
                        right: AdaptiveSizing.of(context).edgePadding,
                        bottom: AdaptiveSizing.of(context).edgePadding,
                        child: Consumer(
                          builder: (context, ref, _) {
                            final showMinimap = ref.watch(showMinimapProvider);
                            if (!showMinimap) {
                              return const SizedBox.shrink();
                            }

                            final sizing = AdaptiveSizing.of(context);
                            final (az, alt) =
                                ref.watch(viewCenterAltAzProvider);
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

                                final (ra, dec) = AstronomyCalculations
                                    .horizontalToEquatorial(
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

                      // Time-travel panel — centered along the bottom so it clears
                      // the compass HUD (bottom-left), the mini-map (bottom-right)
                      // and the full-width info bar (bottom:0). It used to sit at
                      // bottom:110/left:16, overlapping the compass and the left
                      // tool rail.
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
                            compact: false,
                          ),
                        ),
                      ),

                      Positioned(
                        top: 60,
                        right: 0,
                        bottom: 0,
                        child: FilterSidebar(
                          isExpanded: _filterSidebarExpanded,
                          onToggle: () => _update(() =>
                              _filterSidebarExpanded = !_filterSidebarExpanded),
                        ),
                      ),
                    ],
                  ),
                ),
                ResizablePanel(
                  initialWidth: panelInitial,
                  minWidth: panelMin,
                  maxWidth: panelMax,
                  side: ResizeSide.left,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border(left: BorderSide(color: colors.border)),
                    ),
                    child: Column(
                      children: [
                        SearchHeader(
                          colors: colors,
                          controller: _searchController,
                          onSearch: (query) {
                            ref
                                .read(objectSearchProvider.notifier)
                                .search(query);
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
                                      InfoTab(
                                          colors: colors,
                                          selectedObject: selectedObject),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_showPopup && _popupObject != null)
              ObjectInfoPopup(
                colors: colors,
                object: _popupObject!,
                coordinates: _popupCoordinates ?? _popupObject!.coordinates,
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
                hasRotator: ref.watch(rotatorStateProvider).connectionState ==
                    DeviceConnectionState.connected,
              ),
            if (_showHelpOverlay)
              _KeyboardShortcutsOverlay(
                onDismiss: () => _update(() => _showHelpOverlay = false),
              ),
          ],
        );
      },
    );
  }
}
