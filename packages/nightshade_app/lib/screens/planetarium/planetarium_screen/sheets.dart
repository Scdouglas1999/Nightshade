// ignore_for_file: invalid_use_of_protected_member
// Part of ../planetarium_screen.dart -- extracted for maintainability.
//
// Filter, context-menu, object-info, sidebar and mobile-search sheet presenters.
part of '../planetarium_screen.dart';

extension _PlanetariumScreenSheets on _PlanetariumScreenState {
  void _showFilterBottomSheet(BuildContext context) {
    // Tokenized colors so Red Night theme keeps its red wash across mobile
    // filter sheets — audit §4.15.
    final colors = NightshadeColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surfaceOverlay,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(NightshadeTokens.radiusInline8)),
      ),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final config = ref.watch(skyRenderConfigProvider);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textMuted,
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Filters',
                    style: TextStyle(
                        fontSize: NightshadeTypography.fontSize18,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Stars'),
                    value: config.showStars,
                    onChanged: (_) => ref
                        .read(skyRenderConfigProvider.notifier)
                        .toggleStars(),
                  ),
                  SwitchListTile(
                    title: const Text('Planets'),
                    value: config.showPlanets,
                    onChanged: (_) => ref
                        .read(skyRenderConfigProvider.notifier)
                        .togglePlanets(),
                  ),
                  SwitchListTile(
                    title: const Text('Deep Sky'),
                    value: config.showDSOs,
                    onChanged: (_) =>
                        ref.read(skyRenderConfigProvider.notifier).toggleDSOs(),
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Grid'),
                    value: config.showCoordinateGrid,
                    onChanged: (_) =>
                        ref.read(skyRenderConfigProvider.notifier).toggleGrid(),
                  ),
                  SwitchListTile(
                    title: const Text('Constellations'),
                    value: config.showConstellationLines,
                    onChanged: (_) => ref
                        .read(skyRenderConfigProvider.notifier)
                        .toggleConstellationLines(),
                  ),
                  SwitchListTile(
                    // Scoped in the title because the ground is terrain that
                    // occludes, and only the horizon view has terrain: the
                    // equatorial star atlas draws no ground at all, so an
                    // unqualified "Ground" switch would do nothing there.
                    title: const Text('Ground (horizon view)'),
                    value: ref.watch(showGroundPlaneProvider),
                    onChanged: (v) =>
                        ref.read(showGroundPlaneProvider.notifier).state = v,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'reset',
          child: Row(
            children: [
              Icon(NightshadeIcons.home, size: 16),
              SizedBox(width: 8),
              Text('Reset View'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'grid',
          child: Row(
            children: [
              Icon(NightshadeIcons.grid, size: 16),
              SizedBox(width: 8),
              Text('Toggle Grid'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'constellations',
          child: Row(
            children: [
              Icon(NightshadeIcons.activity, size: 16),
              SizedBox(width: 8),
              Text('Toggle Constellations'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'fov',
          child: Row(
            children: [
              Icon(NightshadeIcons.frame, size: 16),
              SizedBox(width: 8),
              Text('Toggle FOV Overlay'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'reset':
          _resetView();
          break;
        case 'grid':
          ref.read(skyRenderConfigProvider.notifier).toggleGrid();
          break;
        case 'constellations':
          ref.read(skyRenderConfigProvider.notifier).toggleConstellationLines();
          break;
        case 'fov':
          _update(() => _showFOV = !_showFOV);
          break;
      }
    });
  }

  void _showObjectInfoBottomSheet(
      BuildContext context, NightshadeColors colors) {
    final selectedObject = ref.read(selectedObjectProvider);
    if (selectedObject.object == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(NightshadeTokens.radiusInline8)),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline2),
                  ),
                ),
              ),
              Expanded(
                child: MobileObjectInfoContent(
                  colors: colors,
                  scrollController: scrollController,
                  selectedObject: selectedObject,
                  onSendToFraming: _sendToFraming,
                  onAddToSequencer: _addToSequencer,
                  onAddToQueue: () {
                    final object = selectedObject.object;
                    if (object != null) _addToTargetQueue(object);
                  },
                  onSlewToTarget: _handleSlewToTarget,
                  onSlewAndCenter: () {
                    final coords = selectedObject.coordinates;
                    if (coords != null && selectedObject.object != null) {
                      _handleSlewAndCenter(coords, selectedObject.object!.name);
                    }
                  },
                  hasRotator: ref.watch(rotatorStateProvider).connectionState ==
                      DeviceConnectionState.connected,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Surfaces the desktop side-column (SidebarTabs → Tonight / Catalog / Lists
  /// / Search / Info) on phones as a draggable bottom sheet. The mobile layout
  /// has no room for the always-visible side panel, so it lives behind a FAB.
  ///
  /// We reuse the exact desktop composition — [SearchHeader] +
  /// [DefaultTabController] (length 5) hosting [SidebarTabs] and the five tab
  /// bodies — so there is no divergent mobile state. The tab bodies rely on a
  /// bounded height (they contain `Expanded`/`ListView`), which the
  /// [DraggableScrollableSheet]'s sized child provides.
  void _showSidebarPanelSheet(BuildContext context, NightshadeColors colors) {
    // On a very short landscape window (e.g. the Z Fold cover ~369px), open the
    // sheet essentially full-height so the compact header leaves real room for
    // the tab content; on a roomy portrait phone a smaller initial peek is fine.
    final shortScreen = MediaQuery.of(context).size.height < 450;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: shortScreen ? 0.97 : 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.97,
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
            child: Column(
              children: [
                Center(
                  child: Container(
                    margin:
                        EdgeInsets.symmetric(vertical: shortScreen ? 5 : 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textMuted,
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline2),
                    ),
                  ),
                ),
                SearchHeader(
                  colors: colors,
                  controller: _searchController,
                  // The Search tab below renders these results already.
                  showResultSuggestions: false,
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
                              // Live-watch the selection so picking an object in
                              // Catalog/Search/Tonight immediately populates Info
                              // without closing the sheet.
                              Consumer(
                                builder: (context, ref, _) => InfoTab(
                                  colors: colors,
                                  selectedObject:
                                      ref.watch(selectedObjectProvider),
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
            ),
          ),
        ),
      ),
    );
  }

  void _showMobileSearchDialog(BuildContext context, NightshadeColors colors) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
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
          child: MobileSearchSheet(
            colors: colors,
            scrollController: scrollController,
            onObjectSelected: (obj) {
              ref.read(selectedObjectProvider.notifier).selectObject(obj);
              ref.read(skyViewStateProvider.notifier).lookAt(obj.coordinates);
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
  }
}
