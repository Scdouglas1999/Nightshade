/// Tutorial step definition
class TutorialStep {
  /// Unique identifier for this step
  final String id;

  /// Title of this step
  final String title;

  /// Description/instruction for the user
  final String description;

  /// GlobalKey identifier to find the target widget (null = no spotlight)
  final String? targetKey;

  /// Position of the tooltip relative to the target
  final TooltipPosition position;

  /// Whether this step can be skipped
  final bool canSkip;

  /// Order in the tutorial sequence
  final int order;

  /// Tutorial category this step belongs to
  final TutorialCategory category;

  /// Optional action to highlight (e.g., "Click here")
  final String? action;

  const TutorialStep({
    required this.id,
    required this.title,
    required this.description,
    this.targetKey,
    this.position = TooltipPosition.bottom,
    this.canSkip = true,
    required this.order,
    required this.category,
    this.action,
  });
}

/// Position of the tutorial tooltip
enum TooltipPosition {
  top,
  bottom,
  left,
  right,
  center,
}

/// Tutorial categories
enum TutorialCategory {
  gettingStarted,
  equipment,
  imaging,
  sequencer,
  planetarium,
  framing,
  flatWizard,
  analytics,
}

/// Tutorial progress state
class TutorialProgress {
  /// Completed tutorial step IDs
  final Set<String> completedSteps;

  /// Whether the initial tour has been shown
  final bool hasSeenInitialTour;

  /// Whether tutorials are globally enabled
  final bool tutorialsEnabled;

  /// Currently active tutorial (null = none)
  final TutorialCategory? activeCategory;

  /// Current step index in active tutorial
  final int currentStepIndex;

  const TutorialProgress({
    this.completedSteps = const {},
    this.hasSeenInitialTour = false,
    this.tutorialsEnabled = true,
    this.activeCategory,
    this.currentStepIndex = 0,
  });

  TutorialProgress copyWith({
    Set<String>? completedSteps,
    bool? hasSeenInitialTour,
    bool? tutorialsEnabled,
    TutorialCategory? activeCategory,
    int? currentStepIndex,
    bool clearActiveCategory = false,
  }) {
    return TutorialProgress(
      completedSteps: completedSteps ?? this.completedSteps,
      hasSeenInitialTour: hasSeenInitialTour ?? this.hasSeenInitialTour,
      tutorialsEnabled: tutorialsEnabled ?? this.tutorialsEnabled,
      activeCategory: clearActiveCategory ? null : (activeCategory ?? this.activeCategory),
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
    );
  }

  bool isStepCompleted(String stepId) => completedSteps.contains(stepId);
}

/// Built-in tutorial definitions
class TutorialDefinitions {
  static const List<TutorialStep> gettingStarted = [
    // === WELCOME ===
    TutorialStep(
      id: 'welcome',
      title: 'Welcome to Nightshade',
      description: 'This comprehensive tour will guide you through all the features of Nightshade, your complete astrophotography suite. Let\'s explore each area of the application.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'navigation',
      title: 'Navigation Sidebar',
      description: 'The sidebar provides quick access to all areas of Nightshade. You can collapse it by clicking the button at the bottom. Each tab has a specific purpose - let\'s explore them all.',
      targetKey: 'side_navigation',
      position: TooltipPosition.right,
      order: 1,
      category: TutorialCategory.gettingStarted,
    ),

    // === DASHBOARD ===
    TutorialStep(
      id: 'dashboard_intro',
      title: 'Dashboard Overview',
      description: 'The Dashboard is your mission control center. It shows equipment connection status, current session progress, weather conditions, and quick actions.',
      targetKey: 'nav_dashboard',
      position: TooltipPosition.right,
      order: 2,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'dashboard_details',
      title: 'Dashboard Features',
      description: 'Here you\'ll find:\n• Equipment Status - See which devices are connected\n• Session Progress - Track frames captured and time remaining\n• Weather Widget - Current conditions from your location\n• Quick Actions - Start/stop sequences, park mount, warm CCD',
      position: TooltipPosition.center,
      order: 3,
      category: TutorialCategory.gettingStarted,
    ),

    // === EQUIPMENT ===
    TutorialStep(
      id: 'equipment_intro',
      title: 'Equipment Tab',
      description: 'The Equipment tab is where you connect and manage all your astrophotography gear.',
      targetKey: 'nav_equipment',
      position: TooltipPosition.right,
      order: 4,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'equipment_profiles',
      title: 'Equipment Profiles',
      description: 'Create and manage equipment profiles to save your setup configurations. If you have multiple telescopes or cameras, create a profile for each combination. Profiles store sensor size, pixel scale, focal length, and device connections.',
      position: TooltipPosition.center,
      order: 5,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'equipment_connections',
      title: 'Device Connections',
      description: 'Connect to your devices using:\n• ASCOM - Windows native drivers\n• INDI - Linux/macOS standard\n• Alpaca - Network-based ASCOM\n\nSelect a driver, click Connect, and Nightshade will communicate with your hardware.',
      position: TooltipPosition.center,
      order: 6,
      category: TutorialCategory.gettingStarted,
    ),

    // === IMAGING ===
    TutorialStep(
      id: 'imaging_intro',
      title: 'Imaging Tab',
      description: 'The Imaging tab is your camera control center for live viewing, focusing, and manual captures.',
      targetKey: 'nav_imaging',
      position: TooltipPosition.right,
      order: 7,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'imaging_preview',
      title: 'Live Preview Area',
      description: 'The main preview shows your camera\'s output. Use the toolbar to:\n• Zoom in/out and fit to window\n• Toggle crosshair for centering\n• Toggle grid overlay\n• Enable auto-stretch for faint objects',
      position: TooltipPosition.center,
      order: 8,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'imaging_controls',
      title: 'Capture Controls',
      description: 'The bottom panel lets you set exposure time, gain/ISO, binning, and cooling temperature. Use "Snapshot" for a single frame or "Loop" for continuous preview. The histogram shows your exposure levels.',
      position: TooltipPosition.center,
      order: 9,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'imaging_panels',
      title: 'Right Panel Tabs',
      description: 'The right panel has several tabs:\n• Capture - Exposure settings and frame type\n• Camera - Temperature, cooling, readout mode\n• Focus - Focuser control and HFR analysis\n• Guiding - PHD2/guide camera integration\n• Mount - Slew controls and tracking',
      position: TooltipPosition.center,
      order: 10,
      category: TutorialCategory.gettingStarted,
    ),

    // === SEQUENCER ===
    TutorialStep(
      id: 'sequencer_intro',
      title: 'Sequencer Tab',
      description: 'The Sequencer is the heart of automated imaging. Build complex imaging plans using a visual block-based editor.',
      targetKey: 'nav_sequencer',
      position: TooltipPosition.right,
      order: 11,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'sequencer_blocks',
      title: 'Sequence Blocks',
      description: 'Drag blocks from the left palette to build your sequence:\n• Target Group - Define what object to image\n• Capture - Take light frames with specific settings\n• Autofocus - Run focusing routine\n• Dither - Move slightly between frames\n• Meridian Flip - Handle mount flip automatically',
      position: TooltipPosition.center,
      order: 12,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'sequencer_workflow',
      title: 'Sequence Workflow',
      description: 'A typical sequence:\n1. Create Target Group with RA/Dec coordinates\n2. Add Capture blocks for each filter\n3. Insert Autofocus between long runs\n4. Add Dither to reduce fixed pattern noise\n5. Click Play to start automation!',
      position: TooltipPosition.center,
      order: 13,
      category: TutorialCategory.gettingStarted,
    ),

    // === PLANETARIUM ===
    TutorialStep(
      id: 'planetarium_intro',
      title: 'Planetarium Tab',
      description: 'The Planetarium is your interactive sky chart for finding and planning targets.',
      targetKey: 'nav_planetarium',
      position: TooltipPosition.right,
      order: 14,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'planetarium_navigation',
      title: 'Sky Navigation',
      description: 'Navigate the sky:\n• Click and drag to pan around\n• Scroll to zoom in/out\n• Double-click an object for details\n• Right-click to slew your mount\n\nThe sky updates in real-time showing what\'s visible now.',
      position: TooltipPosition.center,
      order: 15,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'planetarium_search',
      title: 'Object Search',
      description: 'Use the search bar to find objects by name (M31, NGC 7000, Vega) or catalog number. The target list shows altitude, transit time, and imaging window for planning your session.',
      position: TooltipPosition.center,
      order: 16,
      category: TutorialCategory.gettingStarted,
    ),

    // === FRAMING ===
    TutorialStep(
      id: 'framing_intro',
      title: 'Framing Tab',
      description: 'The Framing tool helps you compose your shots and plan mosaic projects.',
      targetKey: 'nav_framing',
      position: TooltipPosition.right,
      order: 17,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'framing_single',
      title: 'Single Frame Framing',
      description: 'Load a DSS/survey image of your target and overlay your camera\'s field of view. Rotate and position the frame to get the perfect composition before you start imaging.',
      position: TooltipPosition.center,
      order: 18,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'framing_mosaic',
      title: 'Mosaic Planning',
      description: 'For large objects, use the Mosaic panel to plan multi-panel projects:\n• Set rows and columns\n• Adjust overlap percentage\n• Choose panel ordering (row, snake, spiral)\n• Export panel coordinates to the Sequencer',
      position: TooltipPosition.center,
      order: 19,
      category: TutorialCategory.gettingStarted,
    ),

    // === ANALYTICS ===
    TutorialStep(
      id: 'analytics_intro',
      title: 'Analytics Tab',
      description: 'The Analytics tab provides insights into your imaging sessions.',
      targetKey: 'nav_analytics',
      position: TooltipPosition.right,
      order: 20,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'analytics_features',
      title: 'Session Analytics',
      description: 'Track your progress over time:\n• HFR trends - Monitor focus quality\n• Guiding graphs - RMS error over time\n• Sky conditions - Seeing and transparency logs\n• Session history - Review past imaging sessions\n• Statistics - Total integration time by target',
      position: TooltipPosition.center,
      order: 21,
      category: TutorialCategory.gettingStarted,
    ),

    // === FLAT WIZARD ===
    TutorialStep(
      id: 'flat_wizard_intro',
      title: 'Flat Wizard Tab',
      description: 'The Flat Wizard helps you capture perfect flat calibration frames.',
      targetKey: 'nav_flat_wizard',
      position: TooltipPosition.right,
      order: 22,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'flat_wizard_features',
      title: 'Flat Frame Acquisition',
      description: 'The Flat Wizard automates flat frame capture:\n• Set target ADU (typically 50% well depth)\n• Auto-calculate exposure time for each filter\n• Batch capture flats for multiple filters\n• Support for sky flats, panels, and EL panels\n• ADU histogram for exposure verification',
      position: TooltipPosition.center,
      order: 23,
      category: TutorialCategory.gettingStarted,
    ),

    // === COMPLETION ===
    TutorialStep(
      id: 'settings_tip',
      title: 'Settings & Preferences',
      description: 'Don\'t forget to check Settings (gear icon in title bar) to:\n• Configure your location for accurate sky calculations\n• Download star and DSO catalogs for the planetarium\n• Set up plate solving for precise pointing\n• Customize file naming and save paths',
      position: TooltipPosition.center,
      order: 24,
      category: TutorialCategory.gettingStarted,
    ),
    TutorialStep(
      id: 'tour_complete',
      title: 'You\'re Ready to Image!',
      description: 'That completes the tour of Nightshade. You now know where to find every feature. Start by connecting your equipment, then explore the planetarium to pick a target. Clear skies!',
      position: TooltipPosition.center,
      order: 25,
      category: TutorialCategory.gettingStarted,
    ),
  ];

  static const List<TutorialStep> equipment = [
    TutorialStep(
      id: 'equipment_profiles',
      title: 'Equipment Profiles',
      description: 'Create profiles to save your equipment configurations. You can have different profiles for different setups.',
      targetKey: 'profiles_tab',
      position: TooltipPosition.bottom,
      order: 0,
      category: TutorialCategory.equipment,
    ),
    TutorialStep(
      id: 'equipment_connect',
      title: 'Connect Devices',
      description: 'Use the Connections tab to connect to your ASCOM, INDI, or Alpaca devices.',
      targetKey: 'connections_tab',
      position: TooltipPosition.bottom,
      order: 1,
      category: TutorialCategory.equipment,
    ),
  ];

  static const List<TutorialStep> imaging = [
    TutorialStep(
      id: 'imaging_preview',
      title: 'Image Preview',
      description: 'Your captured images appear here. Use the stretch controls to adjust the display.',
      targetKey: 'image_preview',
      position: TooltipPosition.left,
      order: 0,
      category: TutorialCategory.imaging,
    ),
    TutorialStep(
      id: 'imaging_histogram',
      title: 'Histogram',
      description: 'Monitor your image histogram to ensure proper exposure and avoid clipping.',
      targetKey: 'histogram_panel',
      position: TooltipPosition.top,
      order: 1,
      category: TutorialCategory.imaging,
    ),
    TutorialStep(
      id: 'imaging_capture',
      title: 'Capture Controls',
      description: 'Set your exposure time, gain, and other camera settings here.',
      targetKey: 'capture_panel',
      position: TooltipPosition.left,
      order: 2,
      category: TutorialCategory.imaging,
    ),
  ];

  static List<TutorialStep> getStepsForCategory(TutorialCategory category) {
    switch (category) {
      case TutorialCategory.gettingStarted:
        return gettingStarted;
      case TutorialCategory.equipment:
        return equipment;
      case TutorialCategory.imaging:
        return imaging;
      default:
        return [];
    }
  }
}
