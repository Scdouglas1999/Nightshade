/// Shape of the spotlight cutout
enum SpotlightShape {
  circle,
  roundedRect,
  pill,
}

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

  /// Type of required action: "click", "input", "navigate", or null for passive
  final String? requiredAction;

  /// Widget key that completes the step (for interactive steps)
  final String? actionTarget;

  /// Can user click through the spotlight? Default true
  final bool isInteractive;

  /// Shape of the spotlight cutout
  final SpotlightShape spotlightShape;

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
    this.requiredAction,
    this.actionTarget,
    this.isInteractive = true,
    this.spotlightShape = SpotlightShape.roundedRect,
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

/// Tutorial categories - focused mini-tours
enum TutorialCategory {
  // ============================================================
  // WORKFLOW TOURS (existing)
  // ============================================================

  /// Connect -> Expose -> View (5 steps max)
  firstLight,

  /// Profiles -> Drivers -> Connect (4 steps max)
  equipmentSetup,

  /// Planetarium -> Search -> Slew -> Frame (4 steps max)
  targetPlanning,

  /// Sequencer basics -> Build -> Run (5 steps max)
  automatedImaging,

  /// Flat wizard workflow (3 steps max)
  calibrationFrames,

  /// Optional: Analytics, weather (4 steps max)
  advancedFeatures,

  // ============================================================
  // SCREEN-SPECIFIC TOURS (12 screens)
  // ============================================================

  /// Dashboard screen deep tour (12 steps)
  dashboardTour,

  /// Equipment screen deep tour (10 steps)
  equipmentTour,

  /// Imaging screen deep tour (15 steps)
  imagingTour,

  /// Guiding screen deep tour (10 steps)
  guidingTour,

  /// Sequencer screen deep tour (12 steps)
  sequencerTour,

  /// Planetarium screen deep tour (10 steps)
  planetariumTour,

  /// Framing screen deep tour (10 steps)
  framingTour,

  /// Analytics screen deep tour (8 steps)
  analyticsTour,

  /// Flat Wizard screen deep tour (8 steps)
  flatWizardTour,

  /// Weather screen deep tour (8 steps)
  weatherTour,

  /// Settings screen deep tour (10 steps)
  settingsTour,

  /// Polar Alignment screen deep tour (10 steps)
  polarAlignmentTour,
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
      activeCategory:
          clearActiveCategory ? null : (activeCategory ?? this.activeCategory),
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
    );
  }

  bool isStepCompleted(String stepId) => completedSteps.contains(stepId);
}

/// Built-in tutorial definitions
class TutorialDefinitions {
  // ============================================================
  // FIRST LIGHT TOUR (5 steps)
  // Connect -> Expose -> View
  // ============================================================
  static const List<TutorialStep> firstLight = [
    TutorialStep(
      id: 'fl_welcome',
      title: 'Welcome to Nightshade',
      description:
          'Let\'s capture your first image! In this quick tour, you\'ll connect your camera, take a snapshot, and view the result. Click Next to begin.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.firstLight,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'fl_navigate_equipment',
      title: 'Navigate to Equipment',
      description:
          'Click the Equipment tab in the sidebar to access device connections. This is where you\'ll connect your camera.',
      targetKey: 'nav_equipment',
      position: TooltipPosition.right,
      order: 1,
      category: TutorialCategory.firstLight,
      requiredAction: 'click',
      actionTarget: 'nav_equipment',
      isInteractive: true,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'fl_connect_camera',
      title: 'Connect Your Camera',
      description:
          'Select your camera from the dropdown and click the Connect button. Once connected, the status indicator will turn green.',
      targetKey: 'camera_connect_button',
      position: TooltipPosition.bottom,
      order: 2,
      category: TutorialCategory.firstLight,
      requiredAction: 'click',
      actionTarget: 'camera_connect_button',
      isInteractive: true,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'fl_take_snapshot',
      title: 'Take a Snapshot',
      description:
          'Navigate to the Imaging tab and click the Snapshot button to capture a single frame. Adjust exposure time if needed before capturing.',
      targetKey: 'snapshot_button',
      position: TooltipPosition.top,
      order: 3,
      category: TutorialCategory.firstLight,
      requiredAction: 'click',
      actionTarget: 'snapshot_button',
      isInteractive: true,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'fl_success',
      title: 'Congratulations!',
      description:
          'You\'ve captured your first image with Nightshade! Your image appears in the preview area. Explore the other tours to learn about automated imaging, target planning, and more.',
      position: TooltipPosition.center,
      order: 4,
      category: TutorialCategory.firstLight,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // EQUIPMENT SETUP TOUR (4 steps)
  // Profiles -> Drivers -> Connect
  // ============================================================
  static const List<TutorialStep> equipmentSetup = [
    TutorialStep(
      id: 'eq_profiles_overview',
      title: 'Equipment Profiles',
      description:
          'Click the Profiles tab to manage your equipment configurations. Profiles save your telescope, camera, and accessory combinations for quick switching.',
      targetKey: 'profiles_tab',
      position: TooltipPosition.bottom,
      order: 0,
      category: TutorialCategory.equipmentSetup,
      requiredAction: 'click',
      actionTarget: 'profiles_tab',
      isInteractive: true,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'eq_create_profile',
      title: 'Create a Profile',
      description:
          'Click the New Profile button to create a configuration. Enter your sensor size, pixel scale, and focal length. These values enable accurate field-of-view calculations.',
      targetKey: 'new_profile_button',
      position: TooltipPosition.bottom,
      order: 1,
      category: TutorialCategory.equipmentSetup,
      requiredAction: 'click',
      actionTarget: 'new_profile_button',
      isInteractive: true,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'eq_connect_devices',
      title: 'Connect Devices',
      description:
          'Click the Connections tab to connect your hardware. Use ASCOM COM only on Windows, Alpaca for ASCOM network devices, INDI through a reachable server, and Native only where the release includes the needed SDK.',
      targetKey: 'connections_tab',
      position: TooltipPosition.bottom,
      order: 2,
      category: TutorialCategory.equipmentSetup,
      requiredAction: 'click',
      actionTarget: 'connections_tab',
      isInteractive: true,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'eq_verify_status',
      title: 'Verify Connections',
      description:
          'Check the status indicators for each device. Green means connected and ready. If a device shows red, click it to view error details and troubleshoot.',
      targetKey: 'device_status_panel',
      position: TooltipPosition.left,
      order: 3,
      category: TutorialCategory.equipmentSetup,
      isInteractive: false,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // TARGET PLANNING TOUR (4 steps)
  // Planetarium -> Search -> Slew -> Frame
  // ============================================================
  static const List<TutorialStep> targetPlanning = [
    TutorialStep(
      id: 'tp_planetarium',
      title: 'Open the Planetarium',
      description:
          'Click the Planetarium tab to access the interactive sky chart. This shows your current sky with all visible objects based on your location and time.',
      targetKey: 'nav_planetarium',
      position: TooltipPosition.right,
      order: 0,
      category: TutorialCategory.targetPlanning,
      requiredAction: 'click',
      actionTarget: 'nav_planetarium',
      isInteractive: true,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'tp_search',
      title: 'Search for Objects',
      description:
          'Click the search bar and type an object name (like M31, NGC 7000, or Vega). Select from the results to center the planetarium on that object.',
      targetKey: 'planetarium_search',
      position: TooltipPosition.bottom,
      order: 1,
      category: TutorialCategory.targetPlanning,
      requiredAction: 'input',
      actionTarget: 'planetarium_search',
      isInteractive: true,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'tp_slew',
      title: 'Slew to Target',
      description:
          'Right-click the object and select "Slew Here" to point your mount at the target. Ensure your mount is connected before slewing.',
      targetKey: 'slew_button',
      position: TooltipPosition.bottom,
      order: 2,
      category: TutorialCategory.targetPlanning,
      requiredAction: 'click',
      actionTarget: 'slew_button',
      isInteractive: true,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'tp_framing',
      title: 'Frame Your Shot',
      description:
          'Navigate to the Framing tab to compose your image. Drag and rotate the field-of-view rectangle to find the perfect composition before imaging.',
      targetKey: 'nav_framing',
      position: TooltipPosition.right,
      order: 3,
      category: TutorialCategory.targetPlanning,
      requiredAction: 'click',
      actionTarget: 'nav_framing',
      isInteractive: true,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // AUTOMATED IMAGING TOUR (5 steps)
  // Sequencer basics -> Build -> Run
  // ============================================================
  static const List<TutorialStep> automatedImaging = [
    TutorialStep(
      id: 'ai_sequencer_intro',
      title: 'Meet the Sequencer',
      description:
          'Click the Sequencer tab to access automated imaging. The Sequencer runs your imaging plan unattended, handling slews, exposures, autofocus, and more.',
      targetKey: 'nav_sequencer',
      position: TooltipPosition.right,
      order: 0,
      category: TutorialCategory.automatedImaging,
      requiredAction: 'click',
      actionTarget: 'nav_sequencer',
      isInteractive: true,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'ai_add_blocks',
      title: 'Add Sequence Blocks',
      description:
          'Drag blocks from the left palette onto the canvas. Start with a Target Group block, then add Capture blocks for your exposures. Each block configures one part of your workflow.',
      targetKey: 'sequence_palette',
      position: TooltipPosition.right,
      order: 1,
      category: TutorialCategory.automatedImaging,
      isInteractive: true,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'ai_configure',
      title: 'Configure Capture Settings',
      description:
          'Click a Capture block to configure it. Set the filter, exposure time, gain, and number of frames. Add multiple Capture blocks for different filters (LRGB, narrowband).',
      targetKey: 'capture_block_config',
      position: TooltipPosition.left,
      order: 2,
      category: TutorialCategory.automatedImaging,
      requiredAction: 'click',
      actionTarget: 'capture_block_config',
      isInteractive: true,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'ai_run',
      title: 'Run the Sequence',
      description:
          'Click the Play button to start your sequence. Nightshade will execute each block in order, automatically handling equipment control and image saving.',
      targetKey: 'sequence_play_button',
      position: TooltipPosition.bottom,
      order: 3,
      category: TutorialCategory.automatedImaging,
      requiredAction: 'click',
      actionTarget: 'sequence_play_button',
      isInteractive: true,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'ai_monitor',
      title: 'Monitor Progress',
      description:
          'Watch the progress panel as your sequence runs. Green checkmarks indicate completed blocks. Click Pause to interrupt, or Stop to end the session. Images save automatically.',
      targetKey: 'sequence_progress_panel',
      position: TooltipPosition.left,
      order: 4,
      category: TutorialCategory.automatedImaging,
      isInteractive: false,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // CALIBRATION FRAMES TOUR (3 steps)
  // Flat wizard workflow
  // ============================================================
  static const List<TutorialStep> calibrationFrames = [
    TutorialStep(
      id: 'cf_what_are_flats',
      title: 'What Are Flat Frames?',
      description:
          'Flat frames correct for vignetting and dust spots in your optical system. Navigate to the Flat Wizard tab to capture them easily.',
      targetKey: 'nav_flat_wizard',
      position: TooltipPosition.right,
      order: 0,
      category: TutorialCategory.calibrationFrames,
      requiredAction: 'click',
      actionTarget: 'nav_flat_wizard',
      isInteractive: true,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'cf_wizard_setup',
      title: 'Configure the Wizard',
      description:
          'Select your flat source (sky flats, light panel, or EL panel). Set the target ADU level (typically 50% of your camera\'s well depth). The wizard will calculate exposure times automatically.',
      targetKey: 'flat_wizard_config',
      position: TooltipPosition.left,
      order: 1,
      category: TutorialCategory.calibrationFrames,
      isInteractive: true,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'cf_capture_flats',
      title: 'Capture Flat Frames',
      description:
          'Click Start to begin capturing. The wizard takes test exposures, adjusts timing, then captures your specified number of flats per filter. Watch the ADU histogram to verify exposure.',
      targetKey: 'flat_wizard_start',
      position: TooltipPosition.top,
      order: 2,
      category: TutorialCategory.calibrationFrames,
      requiredAction: 'click',
      actionTarget: 'flat_wizard_start',
      isInteractive: true,
      spotlightShape: SpotlightShape.circle,
    ),
  ];

  // ============================================================
  // ADVANCED FEATURES TOUR (4 steps)
  // Analytics, weather, history, settings
  // ============================================================
  static const List<TutorialStep> advancedFeatures = [
    TutorialStep(
      id: 'af_analytics',
      title: 'Session Analytics',
      description:
          'Click the Analytics tab to review your imaging performance. View HFR trends, guiding accuracy, and sky conditions over time to identify areas for improvement.',
      targetKey: 'nav_analytics',
      position: TooltipPosition.right,
      order: 0,
      category: TutorialCategory.advancedFeatures,
      requiredAction: 'click',
      actionTarget: 'nav_analytics',
      isInteractive: true,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'af_weather',
      title: 'Weather Integration',
      description:
          'Check the weather widget on the Dashboard for current conditions. Configure alerts in Settings to pause imaging when clouds approach or humidity rises.',
      targetKey: 'weather_widget',
      position: TooltipPosition.left,
      order: 1,
      category: TutorialCategory.advancedFeatures,
      isInteractive: false,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'af_history',
      title: 'Session History',
      description:
          'Click the History tab in Analytics to browse past sessions. Review captured frames, total integration time, and conditions for each imaging night.',
      targetKey: 'history_tab',
      position: TooltipPosition.bottom,
      order: 2,
      category: TutorialCategory.advancedFeatures,
      requiredAction: 'click',
      actionTarget: 'history_tab',
      isInteractive: true,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'af_settings',
      title: 'Customize Settings',
      description:
          'Click the Settings icon in the title bar to configure your location, file paths, plate solving, and other preferences. Set your coordinates for accurate sky calculations.',
      targetKey: 'settings_button',
      position: TooltipPosition.bottom,
      order: 3,
      category: TutorialCategory.advancedFeatures,
      requiredAction: 'click',
      actionTarget: 'settings_button',
      isInteractive: true,
      spotlightShape: SpotlightShape.circle,
    ),
  ];

  // ============================================================
  // DASHBOARD TOUR (12 steps)
  // ============================================================
  static const List<TutorialStep> dashboardTour = [
    TutorialStep(
      id: 'dt_welcome',
      title: 'Welcome to Dashboard',
      description:
          'The Dashboard is your mission control for astrophotography. It provides an at-a-glance view of all active systems and lets you customize the layout to match your workflow.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.dashboardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'dt_edit_button',
      title: 'Customize Layout',
      description:
          'Click the Edit button to rearrange dashboard widgets. Drag widgets to reorder them, resize panels, or hide ones you don\'t need. Your layout is saved automatically.',
      targetKey: 'dashboard_edit_button',
      position: TooltipPosition.bottom,
      order: 1,
      category: TutorialCategory.dashboardTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'dt_live_preview',
      title: 'Live Image Preview',
      description:
          'This panel shows your latest captured image with real-time updates during exposures. Use pinch to zoom and pan to inspect details.',
      targetKey: 'dashboard_live_preview',
      position: TooltipPosition.left,
      order: 2,
      category: TutorialCategory.dashboardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'dt_capture_controls',
      title: 'Quick Capture',
      description:
          'Take snapshots or start loop exposures directly from the Dashboard without navigating away. Perfect for quick focus checks or framing adjustments.',
      targetKey: 'dashboard_capture_controls',
      position: TooltipPosition.left,
      order: 3,
      category: TutorialCategory.dashboardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'dt_session_widget',
      title: 'Session Progress',
      description:
          'Track your current imaging session: total frames captured, integration time accumulated, and estimated time remaining. Click to view detailed session statistics.',
      targetKey: 'dashboard_session_widget',
      position: TooltipPosition.left,
      order: 4,
      category: TutorialCategory.dashboardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'dt_weather_widget',
      title: 'Weather Status',
      description:
          'Monitor current weather conditions including cloud cover, humidity, and approaching weather systems. Alerts appear here when conditions threaten your imaging session.',
      targetKey: 'dashboard_weather_widget',
      position: TooltipPosition.left,
      order: 5,
      category: TutorialCategory.dashboardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'dt_guiding_widget',
      title: 'Guiding Status',
      description:
          'View real-time guiding performance from PHD2. The graph shows RA/Dec errors, and RMS values indicate tracking accuracy. Green means excellent guiding.',
      targetKey: 'dashboard_guiding_widget',
      position: TooltipPosition.left,
      order: 6,
      category: TutorialCategory.dashboardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'dt_mount_widget',
      title: 'Mount Position',
      description:
          'See your mount\'s current coordinates, tracking status, and pier side. Quick slew controls let you center objects or park the mount without leaving the Dashboard.',
      targetKey: 'dashboard_mount_widget',
      position: TooltipPosition.left,
      order: 7,
      category: TutorialCategory.dashboardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'dt_focuser_widget',
      title: 'Focuser Control',
      description:
          'Monitor focus position and temperature. Run autofocus routines or make manual adjustments. The temperature compensation feature keeps focus sharp as the night cools.',
      targetKey: 'dashboard_focuser_widget',
      position: TooltipPosition.left,
      order: 8,
      category: TutorialCategory.dashboardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'dt_equipment_status',
      title: 'Equipment Overview',
      description:
          'See connection status for all your devices at a glance. Green indicates connected, red means disconnected. Click any device to jump to its detailed controls.',
      targetKey: 'dashboard_equipment_status',
      position: TooltipPosition.left,
      order: 9,
      category: TutorialCategory.dashboardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'dt_sequence_widget',
      title: 'Active Sequence',
      description:
          'When a sequence is running, this widget shows current progress, active target, and remaining time. Pause or abort the sequence directly from here.',
      targetKey: 'dashboard_sequence_widget',
      position: TooltipPosition.left,
      order: 10,
      category: TutorialCategory.dashboardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'dt_complete',
      title: 'Dashboard Complete',
      description:
          'You\'ve learned the Dashboard basics! Customize the layout to fit your workflow. The Dashboard adapts to show what matters most during your imaging sessions.',
      position: TooltipPosition.center,
      order: 11,
      category: TutorialCategory.dashboardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // EQUIPMENT TOUR (10 steps)
  // ============================================================
  static const List<TutorialStep> equipmentTour = [
    TutorialStep(
      id: 'et_welcome',
      title: 'Equipment Management',
      description:
          'The Equipment screen is where you configure and connect all your astrophotography gear. Create profiles to quickly switch between different setups.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.equipmentTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'et_profile_selector',
      title: 'Equipment Profiles',
      description:
          'Select from saved equipment profiles. Each profile stores your telescope, camera, and accessory configurations. Switch profiles when changing imaging rigs.',
      targetKey: 'equipment_profile_selector',
      position: TooltipPosition.bottom,
      order: 1,
      category: TutorialCategory.equipmentTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'et_create_profile',
      title: 'Create Profile',
      description:
          'Click to create a new equipment profile. Enter your sensor dimensions, pixel size, and focal length to enable accurate field-of-view calculations throughout Nightshade.',
      targetKey: 'equipment_create_profile_btn',
      position: TooltipPosition.bottom,
      order: 2,
      category: TutorialCategory.equipmentTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'et_quick_connect',
      title: 'Quick Connect',
      description:
          'The Quick Connect bar shows your most-used devices. Click a device icon to instantly connect or disconnect. Green means connected, gray means available.',
      targetKey: 'equipment_quick_connect_bar',
      position: TooltipPosition.bottom,
      order: 3,
      category: TutorialCategory.equipmentTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'et_discovery_tab',
      title: 'Device Discovery',
      description:
          'The Discovery tab scans for available devices. It can find Windows ASCOM COM drivers, configured or reachable INDI servers, and Alpaca devices on your network when those backends are in scope for the release.',
      targetKey: 'equipment_discovery_tab',
      position: TooltipPosition.bottom,
      order: 4,
      category: TutorialCategory.equipmentTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'et_connected_tab',
      title: 'Connected Devices',
      description:
          'View all currently connected devices here. Each device shows its status, and you can access detailed settings by clicking on it.',
      targetKey: 'equipment_connected_tab',
      position: TooltipPosition.bottom,
      order: 5,
      category: TutorialCategory.equipmentTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'et_settings_tab',
      title: 'Device Settings',
      description:
          'Configure advanced device settings here. Set default gain, offset, cooling targets for cameras, or tracking rates for mounts.',
      targetKey: 'equipment_settings_tab',
      position: TooltipPosition.bottom,
      order: 6,
      category: TutorialCategory.equipmentTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'et_camera_card',
      title: 'Camera Controls',
      description:
          'Your camera\'s detailed settings: gain, offset, binning, readout mode, and cooling. Set the target temperature and watch the cooler reach equilibrium.',
      targetKey: 'equipment_camera_card',
      position: TooltipPosition.left,
      order: 7,
      category: TutorialCategory.equipmentTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'et_mount_card',
      title: 'Mount Controls',
      description:
          'Mount settings include tracking rate, guide rate, and slew speed. Park positions, home commands, and meridian flip settings are configured here.',
      targetKey: 'equipment_mount_card',
      position: TooltipPosition.left,
      order: 8,
      category: TutorialCategory.equipmentTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'et_complete',
      title: 'Equipment Ready',
      description:
          'You\'re now familiar with equipment management! Create profiles for each of your setups and use Quick Connect for fast session startup.',
      position: TooltipPosition.center,
      order: 9,
      category: TutorialCategory.equipmentTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // IMAGING TOUR (15 steps)
  // ============================================================
  static const List<TutorialStep> imagingTour = [
    TutorialStep(
      id: 'it_welcome',
      title: 'The Imaging Screen',
      description:
          'The Imaging screen is your primary interface for capturing images. Control your camera, view live images, and monitor image quality all in one place.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'it_tab_bar',
      title: 'Navigation Tabs',
      description:
          'Switch between Capture, Mount, and Focus tabs. Each tab provides specialized controls for different aspects of your imaging workflow.',
      targetKey: 'imaging_tab_bar',
      position: TooltipPosition.bottom,
      order: 1,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'it_preview_area',
      title: 'Image Preview',
      description:
          'Your captured images appear here with auto-stretch applied. Pinch to zoom, drag to pan, and double-tap to reset the view. The crosshair marks the image center.',
      targetKey: 'imaging_preview_area',
      position: TooltipPosition.left,
      order: 2,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'it_zoom_controls',
      title: 'Zoom Controls',
      description:
          'Zoom in to inspect star shapes and check focus. The 1:1 button shows actual pixels. Use zoom during focusing to see the tightest star shapes.',
      targetKey: 'imaging_zoom_controls',
      position: TooltipPosition.left,
      order: 3,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'it_exposure_slider',
      title: 'Exposure Time',
      description:
          'Set your exposure duration here. For focusing, use short exposures (1-3 seconds). For imaging, typical exposures range from 60-300 seconds depending on your target.',
      targetKey: 'imaging_exposure_slider',
      position: TooltipPosition.right,
      order: 4,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'it_gain_control',
      title: 'Gain Setting',
      description:
          'Adjust camera gain (sensitivity). Higher gain means brighter images but more noise. Find your camera\'s unity gain or optimal gain for best results.',
      targetKey: 'imaging_gain_control',
      position: TooltipPosition.right,
      order: 5,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'it_filter_selector',
      title: 'Filter Selection',
      description:
          'Choose the active filter from your filter wheel. Nightshade remembers focus offsets for each filter and applies them automatically.',
      targetKey: 'imaging_filter_selector',
      position: TooltipPosition.right,
      order: 6,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'it_snapshot_btn',
      title: 'Snapshot Button',
      description:
          'Take a single exposure with current settings. The image appears in the preview when complete. Use snapshots for framing and focus checks.',
      targetKey: 'imaging_snapshot_btn',
      position: TooltipPosition.top,
      order: 7,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'it_loop_btn',
      title: 'Loop Capture',
      description:
          'Start continuous exposures that repeat until stopped. Essential for focusing — watch the stars tighten as you adjust. HFR updates with each frame.',
      targetKey: 'imaging_loop_btn',
      position: TooltipPosition.top,
      order: 8,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'it_abort_btn',
      title: 'Abort Button',
      description:
          'Stop the current exposure immediately. The partial image is discarded. Use this when you need to make quick adjustments.',
      targetKey: 'imaging_abort_btn',
      position: TooltipPosition.top,
      order: 9,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'it_stats_panel',
      title: 'Image Statistics',
      description:
          'View key metrics: HFR (star size), median ADU, detected stars, and more. Lower HFR means better focus. Watch these numbers during your session.',
      targetKey: 'imaging_stats_panel',
      position: TooltipPosition.left,
      order: 10,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'it_mount_tab',
      title: 'Mount Tab',
      description:
          'Access mount controls without leaving the Imaging screen. Slew to coordinates, sync position, or make fine adjustments while viewing your image.',
      targetKey: 'imaging_mount_tab',
      position: TooltipPosition.bottom,
      order: 11,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'it_focus_tab',
      title: 'Focus Tab',
      description:
          'Run autofocus routines or manually adjust focus position. The focus graph shows your V-curve. Temperature compensation keeps focus sharp all night.',
      targetKey: 'imaging_focus_tab',
      position: TooltipPosition.bottom,
      order: 12,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'it_histogram',
      title: 'Histogram',
      description:
          'The histogram shows the brightness distribution of your image. A well-exposed light frame should have the peak slightly left of center.',
      targetKey: 'imaging_histogram',
      position: TooltipPosition.top,
      order: 13,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'it_complete',
      title: 'Imaging Mastered',
      description:
          'You know the Imaging screen! Use Loop mode for focusing, check HFR for quality, and keep an eye on your histogram for proper exposure.',
      position: TooltipPosition.center,
      order: 14,
      category: TutorialCategory.imagingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // GUIDING TOUR (10 steps)
  // ============================================================
  static const List<TutorialStep> guidingTour = [
    TutorialStep(
      id: 'gt_welcome',
      title: 'PHD2 Guiding',
      description:
          'The Guiding screen connects to PHD2 for autoguiding. Monitor guide star tracking, view correction graphs, and control guiding directly from Nightshade.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.guidingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'gt_connect_btn',
      title: 'Connect to PHD2',
      description:
          'Click to connect to PHD2. Ensure PHD2 is running and its server is enabled. Once connected, Nightshade can start/stop guiding and receive performance data.',
      targetKey: 'guiding_connect_btn',
      position: TooltipPosition.bottom,
      order: 1,
      category: TutorialCategory.guidingTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'gt_status_bar',
      title: 'Connection Status',
      description:
          'Shows the current PHD2 connection state and guiding status. Green means actively guiding, yellow means calibrating, red indicates an issue.',
      targetKey: 'guiding_status_bar',
      position: TooltipPosition.bottom,
      order: 2,
      category: TutorialCategory.guidingTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'gt_star_view',
      title: 'Guide Star View',
      description:
          'See your guide star in real-time. The crosshair shows the lock position. A stable, non-saturated star makes the best guide star.',
      targetKey: 'guiding_star_view',
      position: TooltipPosition.left,
      order: 3,
      category: TutorialCategory.guidingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'gt_target_display',
      title: 'Target Display',
      description:
          'The target shows guide corrections as dots. Tight clustering near center indicates excellent guiding. Spread-out dots suggest issues to investigate.',
      targetKey: 'guiding_target_display',
      position: TooltipPosition.left,
      order: 4,
      category: TutorialCategory.guidingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'gt_graph',
      title: 'Guiding Graph',
      description:
          'The graph shows RA (blue) and Dec (red) corrections over time. Flat lines near zero mean perfect tracking. Regular patterns may indicate periodic error.',
      targetKey: 'guiding_graph',
      position: TooltipPosition.top,
      order: 5,
      category: TutorialCategory.guidingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'gt_rms_display',
      title: 'RMS Statistics',
      description:
          'RMS values quantify guiding accuracy in arcseconds. Lower is better. Under 1" total RMS is excellent for most setups. Watch for trends over time.',
      targetKey: 'guiding_rms_display',
      position: TooltipPosition.left,
      order: 6,
      category: TutorialCategory.guidingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'gt_controls',
      title: 'Guiding Controls',
      description:
          'Start, stop, and pause guiding. Dither between exposures for better stacking. These controls sync with your active sequence automatically.',
      targetKey: 'guiding_controls',
      position: TooltipPosition.top,
      order: 7,
      category: TutorialCategory.guidingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'gt_brain_btn',
      title: 'PHD2 Brain',
      description:
          'Open PHD2\'s advanced settings (the "Brain"). Fine-tune guide algorithms, calibration settings, and more. Most users won\'t need to change these.',
      targetKey: 'guiding_brain_btn',
      position: TooltipPosition.left,
      order: 8,
      category: TutorialCategory.guidingTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'gt_complete',
      title: 'Guiding Ready',
      description:
          'You understand the Guiding screen! For best results, select a bright but unsaturated guide star and aim for sub-arcsecond RMS values.',
      position: TooltipPosition.center,
      order: 9,
      category: TutorialCategory.guidingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // SEQUENCER TOUR (12 steps)
  // ============================================================
  static const List<TutorialStep> sequencerTour = [
    TutorialStep(
      id: 'st_welcome',
      title: 'The Sequencer',
      description:
          'The Sequencer automates your entire imaging session. Build sequences with drag-and-drop, save templates, and let Nightshade image all night unattended.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.sequencerTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'st_tab_builder',
      title: 'Builder Tab',
      description:
          'Create and edit sequences in the Builder. Drag nodes from the palette onto the canvas, connect them, and configure each step of your workflow.',
      targetKey: 'sequencer_tab_builder',
      position: TooltipPosition.bottom,
      order: 1,
      category: TutorialCategory.sequencerTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'st_tab_targets',
      title: 'Targets Tab',
      description:
          'Manage your imaging targets here. Import from planetarium, create mosaics, or load target lists. Each target becomes a sequence group.',
      targetKey: 'sequencer_tab_targets',
      position: TooltipPosition.bottom,
      order: 2,
      category: TutorialCategory.sequencerTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'st_tab_templates',
      title: 'Templates Tab',
      description:
          'Save and load sequence templates. Create templates for common workflows like LRGB imaging, narrowband, or quick snapshots.',
      targetKey: 'sequencer_tab_templates',
      position: TooltipPosition.bottom,
      order: 3,
      category: TutorialCategory.sequencerTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'st_node_palette',
      title: 'Node Palette',
      description:
          'Drag nodes from here onto the canvas. Choose from Target nodes, Capture nodes, Autofocus, Filter changes, Dither, and more.',
      targetKey: 'sequencer_node_palette',
      position: TooltipPosition.right,
      order: 4,
      category: TutorialCategory.sequencerTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'st_canvas',
      title: 'Sequence Canvas',
      description:
          'Build your sequence visually. Connect nodes to define execution flow. The sequence runs top-to-bottom, branching where you connect multiple paths.',
      targetKey: 'sequencer_canvas',
      position: TooltipPosition.left,
      order: 5,
      category: TutorialCategory.sequencerTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'st_target_node',
      title: 'Target Nodes',
      description:
          'Target nodes slew to objects and center using plate solving. Add coordinates manually or import from the Planetarium or Framing screens.',
      targetKey: 'sequencer_target_node',
      position: TooltipPosition.left,
      order: 6,
      category: TutorialCategory.sequencerTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'st_capture_node',
      title: 'Capture Nodes',
      description:
          'Capture nodes take your images. Configure filter, exposure, gain, and frame count. Add multiple Capture nodes for multi-filter imaging.',
      targetKey: 'sequencer_capture_node',
      position: TooltipPosition.left,
      order: 7,
      category: TutorialCategory.sequencerTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'st_properties_panel',
      title: 'Properties Panel',
      description:
          'Select any node to view and edit its properties here. Set exposure times, filter selections, loop counts, and advanced options.',
      targetKey: 'sequencer_properties_panel',
      position: TooltipPosition.left,
      order: 8,
      category: TutorialCategory.sequencerTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'st_toolbar',
      title: 'Sequence Toolbar',
      description:
          'Control sequence execution from the toolbar. Play starts the sequence, Pause holds execution, and Stop ends the session. Save your sequences frequently!',
      targetKey: 'sequencer_toolbar',
      position: TooltipPosition.bottom,
      order: 9,
      category: TutorialCategory.sequencerTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'st_progress_bar',
      title: 'Progress Indicator',
      description:
          'Track sequence progress here. See completed, current, and remaining steps. Estimated completion time updates based on actual performance.',
      targetKey: 'sequencer_progress_bar',
      position: TooltipPosition.top,
      order: 10,
      category: TutorialCategory.sequencerTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'st_complete',
      title: 'Sequencer Expert',
      description:
          'You\'ve mastered the Sequencer! Build sequences for unattended imaging, save templates for quick setup, and let Nightshade do the work.',
      position: TooltipPosition.center,
      order: 11,
      category: TutorialCategory.sequencerTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // PLANETARIUM TOUR (10 steps)
  // ============================================================
  static const List<TutorialStep> planetariumTour = [
    TutorialStep(
      id: 'pt_welcome',
      title: 'Interactive Sky Chart',
      description:
          'The Planetarium shows the sky as seen from your location. Find targets, plan observations, and slew your mount directly to objects of interest.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.planetariumTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'pt_sky_view',
      title: 'Sky View',
      description:
          'Drag to pan across the sky, pinch to zoom. Stars are colored by spectral type. Deep sky objects show their catalog designations and approximate sizes.',
      targetKey: 'planetarium_sky_view',
      position: TooltipPosition.center,
      order: 1,
      category: TutorialCategory.planetariumTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'pt_search',
      title: 'Search Bar',
      description:
          'Search for any object by name, catalog number, or coordinates. Type "M31", "NGC 7000", or "Vega" and select from matching results.',
      targetKey: 'planetarium_search',
      position: TooltipPosition.bottom,
      order: 2,
      category: TutorialCategory.planetariumTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'pt_filter_btn',
      title: 'Filter Controls',
      description:
          'Show or hide different object types. Filter by catalog (Messier, NGC, IC), object type (galaxies, nebulae, clusters), or magnitude limit.',
      targetKey: 'planetarium_filter_btn',
      position: TooltipPosition.bottom,
      order: 3,
      category: TutorialCategory.planetariumTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'pt_fov_toggle',
      title: 'FOV Overlay',
      description:
          'Toggle your camera\'s field of view overlay. The rectangle shows exactly what your sensor will capture. Essential for framing planning.',
      targetKey: 'planetarium_fov_toggle',
      position: TooltipPosition.bottom,
      order: 4,
      category: TutorialCategory.planetariumTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'pt_slew_btn',
      title: 'Slew Mode',
      description:
          'Enable slew mode, then tap any location to command your mount. The mount will slew to the selected coordinates. Requires a connected mount.',
      targetKey: 'planetarium_slew_btn',
      position: TooltipPosition.bottom,
      order: 5,
      category: TutorialCategory.planetariumTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'pt_object_popup',
      title: 'Object Information',
      description:
          'Tap any object to see details: name, coordinates, magnitude, size, and rise/set times. Links connect to online databases for more information.',
      targetKey: 'planetarium_object_popup',
      position: TooltipPosition.center,
      order: 6,
      category: TutorialCategory.planetariumTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'pt_send_framing',
      title: 'Send to Framing',
      description:
          'Send the selected object to the Framing screen to compose your shot. Adjust rotation and exact positioning before starting your sequence.',
      targetKey: 'planetarium_send_framing',
      position: TooltipPosition.top,
      order: 7,
      category: TutorialCategory.planetariumTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'pt_add_sequence',
      title: 'Add to Sequencer',
      description:
          'Add the object directly to your sequence as a new target. Nightshade creates a target node with proper coordinates ready for capture.',
      targetKey: 'planetarium_add_sequence',
      position: TooltipPosition.top,
      order: 8,
      category: TutorialCategory.planetariumTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'pt_complete',
      title: 'Sky Explorer',
      description:
          'You know the Planetarium! Use it to discover targets, check visibility windows, and plan your imaging sessions around the best observing conditions.',
      position: TooltipPosition.center,
      order: 9,
      category: TutorialCategory.planetariumTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // FRAMING TOUR (10 steps)
  // ============================================================
  static const List<TutorialStep> framingTour = [
    TutorialStep(
      id: 'ft_welcome',
      title: 'Framing Assistant',
      description:
          'The Framing screen helps you compose the perfect shot. Position your target, rotate the field, and plan mosaics before you start imaging.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.framingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'ft_target_search',
      title: 'Target Search',
      description:
          'Search for your target by name or enter coordinates directly. The view centers on your selection with a survey image background.',
      targetKey: 'framing_target_search',
      position: TooltipPosition.bottom,
      order: 1,
      category: TutorialCategory.framingTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'ft_canvas',
      title: 'Framing Canvas',
      description:
          'The canvas shows a survey image of your target area. Drag to reposition, pinch to zoom. Your camera\'s field of view is overlaid on top.',
      targetKey: 'framing_canvas',
      position: TooltipPosition.center,
      order: 2,
      category: TutorialCategory.framingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'ft_fov_rect',
      title: 'FOV Rectangle',
      description:
          'This rectangle represents your sensor\'s field of view. Drag to position, use the corner handles to rotate. The coordinates update as you adjust.',
      targetKey: 'framing_fov_rect',
      position: TooltipPosition.center,
      order: 3,
      category: TutorialCategory.framingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'ft_rotation',
      title: 'Rotation Control',
      description:
          'Set the exact camera rotation angle here. Match your rotator position or find the optimal angle for your composition.',
      targetKey: 'framing_rotation',
      position: TooltipPosition.left,
      order: 4,
      category: TutorialCategory.framingTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'ft_coordinates',
      title: 'Coordinates',
      description:
          'View and fine-tune the exact RA/Dec coordinates. These are the coordinates that will be sent to your mount when you slew.',
      targetKey: 'framing_coordinates',
      position: TooltipPosition.left,
      order: 5,
      category: TutorialCategory.framingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'ft_altitude_chart',
      title: 'Altitude Chart',
      description:
          'See when your target is highest in the sky. The chart shows altitude over the night with the optimal imaging window highlighted.',
      targetKey: 'framing_altitude_chart',
      position: TooltipPosition.top,
      order: 6,
      category: TutorialCategory.framingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'ft_mosaic_btn',
      title: 'Mosaic Planning',
      description:
          'Create multi-panel mosaics for large targets. Set overlap percentage, panel count, and Nightshade calculates all the pointing positions.',
      targetKey: 'framing_mosaic_btn',
      position: TooltipPosition.left,
      order: 7,
      category: TutorialCategory.framingTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'ft_slew_btn',
      title: 'Slew to Frame',
      description:
          'Send the framed coordinates to your mount. The mount slews to position and can plate solve to verify pointing accuracy.',
      targetKey: 'framing_slew_btn',
      position: TooltipPosition.left,
      order: 8,
      category: TutorialCategory.framingTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'ft_complete',
      title: 'Perfect Framing',
      description:
          'You\'ve learned framing! Take time to compose your shots before imaging. Good framing makes the difference between a snapshot and a stunning image.',
      position: TooltipPosition.center,
      order: 9,
      category: TutorialCategory.framingTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // ANALYTICS TOUR (8 steps)
  // ============================================================
  static const List<TutorialStep> analyticsTour = [
    TutorialStep(
      id: 'at_welcome',
      title: 'Session Analytics',
      description:
          'The Analytics screen tracks your imaging performance over time. Review sessions, identify trends, and improve your technique with data-driven insights.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.analyticsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'at_session_tab',
      title: 'Current Session',
      description:
          'View statistics for your active imaging session. Track frames captured, total integration time, and quality metrics in real-time.',
      targetKey: 'analytics_session_tab',
      position: TooltipPosition.bottom,
      order: 1,
      category: TutorialCategory.analyticsTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'at_history_tab',
      title: 'Session History',
      description:
          'Browse past imaging sessions. Each session shows the date, target, total frames, and conditions. Click any session for detailed analysis.',
      targetKey: 'analytics_history_tab',
      position: TooltipPosition.bottom,
      order: 2,
      category: TutorialCategory.analyticsTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'at_equipment_tab',
      title: 'Equipment Stats',
      description:
          'Track performance by equipment. See which camera/telescope combinations produce the best results and identify gear that needs attention.',
      targetKey: 'analytics_equipment_tab',
      position: TooltipPosition.bottom,
      order: 3,
      category: TutorialCategory.analyticsTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'at_hfr_chart',
      title: 'HFR Chart',
      description:
          'The HFR (Half Flux Radius) chart shows focus quality over time. Sudden increases indicate focus drift. Temperature correlation helps predict when to refocus.',
      targetKey: 'analytics_hfr_chart',
      position: TooltipPosition.left,
      order: 4,
      category: TutorialCategory.analyticsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'at_guiding_chart',
      title: 'Guiding Chart',
      description:
          'Review guiding performance throughout your session. Identify periods of poor seeing or mount issues. Correlate with image quality for best frames.',
      targetKey: 'analytics_guiding_chart',
      position: TooltipPosition.left,
      order: 5,
      category: TutorialCategory.analyticsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'at_thumbnails',
      title: 'Captured Images',
      description:
          'Browse thumbnails of all captured frames. Click any image for full-size view with metadata. Flag best frames or mark rejects for stacking.',
      targetKey: 'analytics_thumbnails',
      position: TooltipPosition.top,
      order: 6,
      category: TutorialCategory.analyticsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'at_complete',
      title: 'Data Insights',
      description:
          'Use Analytics to continuously improve! Track trends across sessions, identify optimal conditions, and refine your imaging technique over time.',
      position: TooltipPosition.center,
      order: 7,
      category: TutorialCategory.analyticsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // FLAT WIZARD TOUR (8 steps)
  // ============================================================
  static const List<TutorialStep> flatWizardTour = [
    TutorialStep(
      id: 'fwt_welcome',
      title: 'Flat Frame Wizard',
      description:
          'The Flat Wizard automates flat frame capture. It calculates optimal exposure times and captures flats for all your filters with minimal effort.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.flatWizardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'fwt_tabs',
      title: 'Capture Modes',
      description:
          'Choose between Sky Flats (twilight), Panel Flats (light panel), or Manual mode. Each mode optimizes the workflow for your flat source.',
      targetKey: 'flat_tabs',
      position: TooltipPosition.bottom,
      order: 1,
      category: TutorialCategory.flatWizardTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'fwt_filter_select',
      title: 'Filter Selection',
      description:
          'Select which filters to capture flats for. The wizard captures flats in optimal order for sky flats (brightest to dimmest at dusk).',
      targetKey: 'flat_filter_select',
      position: TooltipPosition.left,
      order: 2,
      category: TutorialCategory.flatWizardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'fwt_target_adu',
      title: 'Target ADU',
      description:
          'Set the target brightness level for your flats. Typically 30-50% of your camera\'s full well capacity. The wizard adjusts exposure to hit this target.',
      targetKey: 'flat_target_adu',
      position: TooltipPosition.left,
      order: 3,
      category: TutorialCategory.flatWizardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'fwt_frame_count',
      title: 'Frame Count',
      description:
          'Specify how many flats to capture per filter. 20-30 flats per filter provides good signal for master flat creation.',
      targetKey: 'flat_frame_count',
      position: TooltipPosition.left,
      order: 4,
      category: TutorialCategory.flatWizardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'fwt_preview',
      title: 'Preview Panel',
      description:
          'Watch the live preview as flats are captured. The histogram shows ADU distribution. Adjust exposure if the histogram isn\'t centered on your target.',
      targetKey: 'flat_preview',
      position: TooltipPosition.left,
      order: 5,
      category: TutorialCategory.flatWizardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'fwt_start_btn',
      title: 'Start Capture',
      description:
          'Click Start to begin the flat capture sequence. The wizard handles exposure calculation, filter changes, and file naming automatically.',
      targetKey: 'flat_start_btn',
      position: TooltipPosition.top,
      order: 6,
      category: TutorialCategory.flatWizardTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'fwt_complete',
      title: 'Flats Made Easy',
      description:
          'Flat frames are essential for clean images. Use the wizard at dusk or dawn for sky flats, or anytime with a flat panel. Consistent flats = better stacks!',
      position: TooltipPosition.center,
      order: 7,
      category: TutorialCategory.flatWizardTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // WEATHER TOUR (8 steps)
  // ============================================================
  static const List<TutorialStep> weatherTour = [
    TutorialStep(
      id: 'wt_welcome',
      title: 'Weather Monitoring',
      description:
          'The Weather screen provides detailed forecasting and real-time conditions. Plan sessions around clear skies and protect your equipment from incoming weather.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.weatherTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'wt_radar_map',
      title: 'Radar Map',
      description:
          'Live radar shows precipitation and cloud cover in your area. The animation shows movement direction. Plan around approaching systems.',
      targetKey: 'weather_radar_map',
      position: TooltipPosition.left,
      order: 1,
      category: TutorialCategory.weatherTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'wt_timeline',
      title: 'Timeline',
      description:
          'Scrub through the forecast timeline to see predicted conditions hour by hour. Find the optimal imaging window for tonight.',
      targetKey: 'weather_timeline',
      position: TooltipPosition.top,
      order: 2,
      category: TutorialCategory.weatherTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'wt_status_card',
      title: 'Conditions',
      description:
          'Current conditions at a glance: temperature, humidity, dew point, wind, and cloud cover. The imaging safety indicator shows if conditions are favorable.',
      targetKey: 'weather_status_card',
      position: TooltipPosition.left,
      order: 3,
      category: TutorialCategory.weatherTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'wt_alert_radius',
      title: 'Alert Radius',
      description:
          'Set the distance at which approaching weather triggers alerts. Smaller radius for permanent setups, larger for time to pack up portable gear.',
      targetKey: 'weather_alert_radius',
      position: TooltipPosition.left,
      order: 4,
      category: TutorialCategory.weatherTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'wt_cloud_motion',
      title: 'Cloud Motion',
      description:
          'AI-powered cloud motion analysis predicts when clouds will reach your location. Get advance warning before conditions deteriorate.',
      targetKey: 'weather_cloud_motion',
      position: TooltipPosition.left,
      order: 5,
      category: TutorialCategory.weatherTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'wt_refresh_btn',
      title: 'Refresh',
      description:
          'Manually refresh weather data. Automatic updates occur every 15 minutes, but you can force an update when conditions are changing rapidly.',
      targetKey: 'weather_refresh_btn',
      position: TooltipPosition.left,
      order: 6,
      category: TutorialCategory.weatherTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'wt_complete',
      title: 'Weather Aware',
      description:
          'Stay ahead of the weather! Configure alerts in Settings to automatically pause sequences when conditions threaten. Protect your gear and optimize imaging time.',
      position: TooltipPosition.center,
      order: 7,
      category: TutorialCategory.weatherTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // SETTINGS TOUR (10 steps)
  // ============================================================
  static const List<TutorialStep> settingsTour = [
    TutorialStep(
      id: 'stt_welcome',
      title: 'Application Settings',
      description:
          'Configure Nightshade to match your setup and preferences. Location, file paths, plate solving, and appearance options are all here.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.settingsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'stt_categories',
      title: 'Categories',
      description:
          'Settings are organized into categories. Click any category to view and modify its options. Changes save automatically.',
      targetKey: 'settings_categories',
      position: TooltipPosition.right,
      order: 1,
      category: TutorialCategory.settingsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'stt_connection',
      title: 'Connection',
      description:
          'Configure how Nightshade connects to equipment. Set ASCOM/INDI/Alpaca preferences, network timeouts, and auto-reconnect behavior.',
      targetKey: 'settings_connection',
      position: TooltipPosition.right,
      order: 2,
      category: TutorialCategory.settingsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'stt_location',
      title: 'Location',
      description:
          'Set your observatory coordinates. Accurate location is essential for planetarium calculations, altitude predictions, and meridian flip timing.',
      targetKey: 'settings_location',
      position: TooltipPosition.right,
      order: 3,
      category: TutorialCategory.settingsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'stt_appearance',
      title: 'Appearance',
      description:
          'Customize the look and feel. Choose dark or light themes, accent colors, and font sizes. Night mode preserves your dark adaptation.',
      targetKey: 'settings_appearance',
      position: TooltipPosition.right,
      order: 4,
      category: TutorialCategory.settingsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'stt_file_paths',
      title: 'File Paths',
      description:
          'Configure where images are saved. Set up folder structures with date, target, and filter substitutions. Keep your image library organized.',
      targetKey: 'settings_file_paths',
      position: TooltipPosition.right,
      order: 5,
      category: TutorialCategory.settingsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'stt_plate_solving',
      title: 'Plate Solving',
      description:
          'Configure your plate solver. Set paths to solver binaries, index files, and search parameters. Local solving is faster than online services.',
      targetKey: 'settings_plate_solving',
      position: TooltipPosition.right,
      order: 6,
      category: TutorialCategory.settingsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'stt_notifications',
      title: 'Notifications',
      description:
          'Control when and how Nightshade alerts you. Set up email, SMS, or push notifications for sequence completion, errors, or weather alerts.',
      targetKey: 'settings_notifications',
      position: TooltipPosition.right,
      order: 7,
      category: TutorialCategory.settingsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'stt_help',
      title: 'Help & Tutorials',
      description:
          'Access all tutorials from here. Reset tutorial progress, view documentation, or contact support. Tutorials can be replayed anytime.',
      targetKey: 'settings_help',
      position: TooltipPosition.right,
      order: 8,
      category: TutorialCategory.settingsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'stt_complete',
      title: 'Personalized',
      description:
          'Nightshade is now configured to your preferences! Revisit Settings anytime to fine-tune your experience as you discover what works best.',
      position: TooltipPosition.center,
      order: 9,
      category: TutorialCategory.settingsTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  // ============================================================
  // POLAR ALIGNMENT TOUR (10 steps)
  // ============================================================
  static const List<TutorialStep> polarAlignmentTour = [
    TutorialStep(
      id: 'pat_welcome',
      title: 'Polar Alignment',
      description:
          'The Polar Alignment wizard helps you achieve accurate polar alignment using plate solving. No need for a polar scope - just follow the guided process.',
      position: TooltipPosition.center,
      order: 0,
      category: TutorialCategory.polarAlignmentTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'pat_hemisphere',
      title: 'Hemisphere',
      description:
          'Select your hemisphere. This determines whether to use Polaris (north) or Sigma Octantis (south) as the reference point.',
      targetKey: 'polar_hemisphere',
      position: TooltipPosition.right,
      order: 1,
      category: TutorialCategory.polarAlignmentTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'pat_exposure',
      title: 'Exposure Time',
      description:
          'Set the exposure time for measurement images. Longer exposures improve accuracy but take more time. 2-5 seconds usually works well.',
      targetKey: 'polar_exposure',
      position: TooltipPosition.right,
      order: 2,
      category: TutorialCategory.polarAlignmentTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'pat_step_size',
      title: 'Step Size',
      description:
          'The mount rotation between measurements. Larger steps are faster but less precise. 30 degrees is a good starting point.',
      targetKey: 'polar_step_size',
      position: TooltipPosition.right,
      order: 3,
      category: TutorialCategory.polarAlignmentTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'pat_start_btn',
      title: 'Start',
      description:
          'Begin the alignment process. Nightshade will take images, rotate the mount, and calculate your polar alignment error.',
      targetKey: 'polar_start_btn',
      position: TooltipPosition.right,
      order: 4,
      category: TutorialCategory.polarAlignmentTour,
      spotlightShape: SpotlightShape.circle,
    ),
    TutorialStep(
      id: 'pat_image_view',
      title: 'Measurement',
      description:
          'Watch as Nightshade captures and plate solves images. Each solve refines the polar alignment calculation. The process typically takes 2-3 images.',
      targetKey: 'polar_image_view',
      position: TooltipPosition.left,
      order: 5,
      category: TutorialCategory.polarAlignmentTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'pat_error_display',
      title: 'Error Display',
      description:
          'Your polar alignment error in arcminutes. For visual observing, under 10\' is fine. For imaging, aim for under 2\' for excellent tracking.',
      targetKey: 'polar_error_display',
      position: TooltipPosition.left,
      order: 6,
      category: TutorialCategory.polarAlignmentTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'pat_adjustment',
      title: 'Adjustment Guide',
      description:
          'Follow the arrows to adjust your mount\'s altitude and azimuth knobs. The display updates in real-time as you make adjustments.',
      targetKey: 'polar_adjustment',
      position: TooltipPosition.left,
      order: 7,
      category: TutorialCategory.polarAlignmentTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
    TutorialStep(
      id: 'pat_progress',
      title: 'Progress Steps',
      description:
          'Track your progress through the alignment process. Each step shows completion status. Re-measure after adjustments to verify improvement.',
      targetKey: 'polar_progress',
      position: TooltipPosition.top,
      order: 8,
      category: TutorialCategory.polarAlignmentTour,
      spotlightShape: SpotlightShape.pill,
    ),
    TutorialStep(
      id: 'pat_complete',
      title: 'Alignment Complete',
      description:
          'Great polar alignment means better tracking and easier guiding. Re-run the wizard periodically if your setup isn\'t permanent.',
      position: TooltipPosition.center,
      order: 9,
      category: TutorialCategory.polarAlignmentTour,
      spotlightShape: SpotlightShape.roundedRect,
    ),
  ];

  static List<TutorialStep> getStepsForCategory(TutorialCategory category) {
    switch (category) {
      case TutorialCategory.firstLight:
        return firstLight;
      case TutorialCategory.equipmentSetup:
        return equipmentSetup;
      case TutorialCategory.targetPlanning:
        return targetPlanning;
      case TutorialCategory.automatedImaging:
        return automatedImaging;
      case TutorialCategory.calibrationFrames:
        return calibrationFrames;
      case TutorialCategory.advancedFeatures:
        return advancedFeatures;
      // Screen-specific tours
      case TutorialCategory.dashboardTour:
        return dashboardTour;
      case TutorialCategory.equipmentTour:
        return equipmentTour;
      case TutorialCategory.imagingTour:
        return imagingTour;
      case TutorialCategory.guidingTour:
        return guidingTour;
      case TutorialCategory.sequencerTour:
        return sequencerTour;
      case TutorialCategory.planetariumTour:
        return planetariumTour;
      case TutorialCategory.framingTour:
        return framingTour;
      case TutorialCategory.analyticsTour:
        return analyticsTour;
      case TutorialCategory.flatWizardTour:
        return flatWizardTour;
      case TutorialCategory.weatherTour:
        return weatherTour;
      case TutorialCategory.settingsTour:
        return settingsTour;
      case TutorialCategory.polarAlignmentTour:
        return polarAlignmentTour;
    }
  }
}
