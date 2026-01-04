SessionService: Starting new session...
  Name: Narrowband (SHO) - Copy
  Target ID: null
  Profile ID: null
SessionService: Checkpoint timer started (interval: 5 min)
SessionService: Session started with ID: 45
SequenceExecutor: Syncing 7 filter names to driver: [L, R, G, B, Ha, OIII, SII]
←[2m2026-01-04T01:34:49.367889Z←[0m ←[32m INFO←[0m api_filterwheel_set_filter_names: Called with device_id='native:zwo_efw:0', names=["L", "R", "G", "B", "Ha", "OIII", "SII"]
←[2m2026-01-04T01:34:49.371347Z←[0m ←[32m INFO←[0m filter_wheel_set_filter_names: Setting filter names for 'native:zwo_efw:0': ["L", "R", "G", "B", "Ha", "OIII", "SII"]
←[2m2026-01-04T01:34:49.374563Z←[0m ←[32m INFO←[0m filter_wheel_set_filter_names: Successfully set 7 filter names
SequenceExecutor: Filter names synced successfully
[SEQUENCE] _startNativeExecution: settings=loaded
[SEQUENCE] Location from settings: lat=40.007714, lon=-75.397448, elev=0.0
[SEQUENCE] Syncing location to backend...
[FFI-BACKEND] setLocation called with lat=40.007714, lon=-75.397448, elev=0.0
[FFI-BACKEND] bridgeLoc: lat=40.007714, lon=-75.397448, elev=0.0
[FFI-BACKEND] Calling apiSetLocation...
[NativeBridge] Setting location via native: lat=40.007714, lon=-75.397448
[RUST-API] api_set_location called with lat=40.007714, lon=-75.397448, elev=0
←[2m2026-01-04T01:34:49.393053Z←[0m ←[32m INFO←[0m [API] api_set_location called with lat=40.007714, lon=-75.397448, elev=0
[RUST-STATE] set_observer_location called
[RUST-STATE] Setting observer location: lat=40.007714, lon=-75.397448, elev=0
←[2m2026-01-04T01:34:49.396092Z←[0m ←[32m INFO←[0m Setting observer location: lat=40.007714, lon=-75.397448, elev=0
[RUST-STATE] Observer location updated in memory (try_write succeeded)
←[2m2026-01-04T01:34:49.398219Z←[0m ←[34mDEBUG←[0m Observer location updated in memory
[RUST-API] api_set_location succeeded
←[2m2026-01-04T01:34:49.403121Z←[0m ←[32m INFO←[0m [API] api_set_location succeeded
[NativeBridge] Location set via native successfully
[FFI-BACKEND] apiSetLocation returned
[SEQUENCE] Location sync complete
←[2m2026-01-04T01:34:49.410773Z←[0m ←[32m INFO←[0m Setting sequencer simulation mode: false
[NativeBridge] Simulation mode via native: disabled
SequenceExecutor: Using profile filter names: [L, R, G, B, Ha, OIII, SII]
←[2m2026-01-04T01:34:49.413578Z←[0m ←[32m INFO←[0m Setting sequencer devices: camera=Some("native:zwo:1"), mount=Some("ascom:ASCOM.PegasusAstroNYX101.Telescope"), focuser=Some("native:zwo_eaf:0"), filterwheel=Some("native:zwo_efw:0"), rotator=None, filter_names=Some(["L", "R", "G", "B", "Ha", "OIII", "SII"])
←[2m2026-01-04T01:34:49.414449Z←[0m ←[32m INFO←[0m Syncing 7 filter names to native driver: ["L", "R", "G", "B", "Ha", "OIII", "SII"]
←[2m2026-01-04T01:34:49.415088Z←[0m ←[32m INFO←[0m filter_wheel_set_filter_names: Setting filter names for 'native:zwo_efw:0': ["L", "R", "G", "B", "Ha", "OIII", "SII"]
←[2m2026-01-04T01:34:49.415872Z←[0m ←[32m INFO←[0m filter_wheel_set_filter_names: Successfully set 7 filter names
[NativeBridge] Set sequencer devices: camera=native:zwo:1, mount=ascom:ASCOM.PegasusAstroNYX101.Telescope, focuser=native:zwo_eaf:0, filterwheel=native:zwo_efw:0, rotator=null, filterNames=[L, R, G, B, Ha, OIII, SII]
←[2m2026-01-04T01:34:49.423820Z←[0m ←[32m INFO←[0m Loading sequence from JSON
←[2m2026-01-04T01:34:49.425375Z←[0m ←[34mDEBUG←[0m Building node 'Narrowband Sequence' (id=1918b9cf-f3b6-4f38-b5ac-3d510aa8ca5e) with 2 children defined: ["05d83e14-62d5-4d8b-a240-b2a77a8afef0", "4be2674a-d118-4f0c-9741-586bf4a345bb"]
←[2m2026-01-04T01:34:49.426173Z←[0m ←[34mDEBUG←[0m   Adding child 'Narrowband Loop' (id=05d83e14-62d5-4d8b-a240-b2a77a8afef0) to 'Narrowband Sequence'
←[2m2026-01-04T01:34:49.427736Z←[0m ←[34mDEBUG←[0m Building node 'Narrowband Loop' (id=05d83e14-62d5-4d8b-a240-b2a77a8afef0) with 3 children defined: ["b2900721-b649-4109-aca9-eedce853c5b0", "cea6e7af-61a6-449c-85e0-349ca864c05f", "4ff8fef4-8930-46b1-bbd3-55f99aca08f8"]
←[2m2026-01-04T01:34:49.428787Z←[0m ←[34mDEBUG←[0m   Adding child 'H-alpha' (id=b2900721-b649-4109-aca9-eedce853c5b0) to 'Narrowband Loop'
←[2m2026-01-04T01:34:49.430882Z←[0m ←[34mDEBUG←[0m Building node 'H-alpha' (id=b2900721-b649-4109-aca9-eedce853c5b0) with 0 children defined: []
←[2m2026-01-04T01:34:49.437267Z←[0m ←[34mDEBUG←[0m   Adding child 'OIII' (id=cea6e7af-61a6-449c-85e0-349ca864c05f) to 'Narrowband Loop'
←[2m2026-01-04T01:34:49.454663Z←[0m ←[34mDEBUG←[0m Building node 'OIII' (id=cea6e7af-61a6-449c-85e0-349ca864c05f) with 0 children defined: []
←[2m2026-01-04T01:34:49.467070Z←[0m ←[34mDEBUG←[0m   Adding child 'SII' (id=4ff8fef4-8930-46b1-bbd3-55f99aca08f8) to 'Narrowband Loop'
←[2m2026-01-04T01:34:49.486721Z←[0m ←[34mDEBUG←[0m Building node 'SII' (id=4ff8fef4-8930-46b1-bbd3-55f99aca08f8) with 0 children defined: []
←[2m2026-01-04T01:34:49.488725Z←[0m ←[34mDEBUG←[0m   Adding child 'Warm Camera' (id=4be2674a-d118-4f0c-9741-586bf4a345bb) to 'Narrowband Sequence'
←[2m2026-01-04T01:34:49.490675Z←[0m ←[34mDEBUG←[0m Building node 'Warm Camera' (id=4be2674a-d118-4f0c-9741-586bf4a345bb) with 0 children defined: []
←[2m2026-01-04T01:34:49.492979Z←[0m ←[32m INFO←[0m Sequence loaded successfully
←[2m2026-01-04T01:34:49.497736Z←[0m ←[32m INFO←[0m [EVENT_SUB] Sequencer event subscription started
[NativeBridge] Subscribed to sequencer events via native
←[2m2026-01-04T01:34:49.500551Z←[0m ←[32m INFO←[0m [EVENT_SUB] Event listener task spawned
←[2m2026-01-04T01:34:49.504086Z←[0m ←[32m INFO←[0m Starting sequence execution
←[2m2026-01-04T01:34:49.506750Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(0)
←[2m2026-01-04T01:34:49.506807Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Started, category=EventCategory.sequencer
←[2m2026-01-04T01:34:49.506960Z←[0m ←[32m INFO←[0m [PROGRESS_CB] Emitting NodeStarted: id=1918b9cf-f3b6-4f38-b5ac-3d510aa8ca5e, name=Narrowband Sequence
←[2m2026-01-04T01:34:49.514760Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Executing: Narrowband Sequence
←[2m2026-01-04T01:34:49.535730Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Executing', rest=' Narrowband Sequence'
←[2m2026-01-04T01:34:49.536728Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' Narrowband Sequence'
←[2m2026-01-04T01:34:49.537852Z←[0m ←[32m INFO←[0m === LOOP ITERATION 1 STARTING ===
←[2m2026-01-04T01:34:49.540224Z←[0m ←[32m INFO←[0m Loop has 2 children
←[2m2026-01-04T01:34:49.545158Z←[0m ←[32m INFO←[0m   Child 0: 'Narrowband Loop' (id=05d83e14-62d5-4d8b-a240-b2a77a8afef0)
←[2m2026-01-04T01:34:49.551402Z←[0m ←[32m INFO←[0m   Child 1: 'Warm Camera' (id=4be2674a-d118-4f0c-9741-586bf4a345bb)
←[2m2026-01-04T01:34:49.561446Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Loop iteration 1
←[2m2026-01-04T01:34:49.574625Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:34:49.582310Z←[0m ←[32m INFO←[0m Resetting 2 children for iteration 1
←[2m2026-01-04T01:34:49.591082Z←[0m ←[32m INFO←[0m Children reset complete
←[2m2026-01-04T01:34:49.598329Z←[0m ←[32m INFO←[0m Starting execute_children_sequential for iteration 1
←[2m2026-01-04T01:34:49.600026Z←[0m ←[34mDEBUG←[0m execute_children_sequential: node 1918b9cf-f3b6-4f38-b5ac-3d510aa8ca5e has 2 children
←[2m2026-01-04T01:34:49.600781Z←[0m ←[32m INFO←[0m About to enter for loop with 2 children
←[2m2026-01-04T01:34:49.602355Z←[0m ←[32m INFO←[0m FOR LOOP ENTERED: iteration 0 of 2
←[2m2026-01-04T01:34:49.609106Z←[0m ←[32m INFO←[0m Executing child 1/2: 'Narrowband Loop' (id=05d83e14-62d5-4d8b-a240-b2a77a8afef0)
←[2m2026-01-04T01:34:49.615685Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Step 1/2: Narrowband Loop
←[2m2026-01-04T01:34:49.618216Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Step 1/2', rest=' Narrowband Loop'
←[2m2026-01-04T01:34:49.626874Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' Narrowband Loop'
←[2m2026-01-04T01:34:49.634083Z←[0m ←[32m INFO←[0m [PROGRESS_CB] Emitting NodeStarted: id=05d83e14-62d5-4d8b-a240-b2a77a8afef0, name=Narrowband Loop
←[2m2026-01-04T01:34:49.638193Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Executing: Narrowband Loop
←[2m2026-01-04T01:34:49.641649Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Executing', rest=' Narrowband Loop'
←[2m2026-01-04T01:34:49.643123Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' Narrowband Loop'
←[2m2026-01-04T01:34:49.645742Z←[0m ←[32m INFO←[0m === LOOP ITERATION 1 STARTING ===
←[2m2026-01-04T01:34:49.647741Z←[0m ←[32m INFO←[0m Loop has 3 children
←[2m2026-01-04T01:34:49.653262Z←[0m ←[32m INFO←[0m   Child 0: 'H-alpha' (id=b2900721-b649-4109-aca9-eedce853c5b0)
←[2m2026-01-04T01:34:49.656853Z←[0m ←[32m INFO←[0m   Child 1: 'OIII' (id=cea6e7af-61a6-449c-85e0-349ca864c05f)
←[2m2026-01-04T01:34:49.658133Z←[0m ←[32m INFO←[0m   Child 2: 'SII' (id=4ff8fef4-8930-46b1-bbd3-55f99aca08f8)
←[2m2026-01-04T01:34:49.659019Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Loop iteration 1
←[2m2026-01-04T01:34:49.661965Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:34:49.662616Z←[0m ←[32m INFO←[0m Resetting 3 children for iteration 1
←[2m2026-01-04T01:34:49.663143Z←[0m ←[32m INFO←[0m Children reset complete
←[2m2026-01-04T01:34:49.664670Z←[0m ←[32m INFO←[0m Starting execute_children_sequential for iteration 1
←[2m2026-01-04T01:34:49.670397Z←[0m ←[34mDEBUG←[0m execute_children_sequential: node 05d83e14-62d5-4d8b-a240-b2a77a8afef0 has 3 children
←[2m2026-01-04T01:34:49.675060Z←[0m ←[32m INFO←[0m About to enter for loop with 3 children
←[2m2026-01-04T01:34:49.677659Z←[0m ←[32m INFO←[0m FOR LOOP ENTERED: iteration 0 of 3
←[2m2026-01-04T01:34:49.683233Z←[0m ←[32m INFO←[0m Executing child 1/3: 'H-alpha' (id=b2900721-b649-4109-aca9-eedce853c5b0)
←[2m2026-01-04T01:34:49.685648Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Step 1/3: H-alpha
←[2m2026-01-04T01:34:49.687706Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Step 1/3', rest=' H-alpha'
←[2m2026-01-04T01:34:49.692878Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' H-alpha'
←[2m2026-01-04T01:34:49.700009Z←[0m ←[32m INFO←[0m [PROGRESS_CB] Emitting NodeStarted: id=b2900721-b649-4109-aca9-eedce853c5b0, name=H-alpha
←[2m2026-01-04T01:34:49.703646Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Executing: H-alpha
←[2m2026-01-04T01:34:49.707137Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Executing', rest=' H-alpha'
←[2m2026-01-04T01:34:49.711091Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' H-alpha'
←[2m2026-01-04T01:34:49.717807Z←[0m ←[32m INFO←[0m Starting 1 Ha x 2.0s exposures
←[2m2026-01-04T01:34:49.722027Z←[0m ←[32m INFO←[0m Changing to filter: Ha
←[2m2026-01-04T01:34:49.724467Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking up device_id='native:zwo_efw:0'
←[2m2026-01-04T01:34:49.730061Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Available devices in registry: ["native:zwo:1", "native:zwo_efw:0", "native:zwo_eaf:0", "ascom:ASCOM.PegasusAstroNYX101.Telescope"]
←[2m2026-01-04T01:34:49.735688Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Found device with driver_type=Native
←[2m2026-01-04T01:34:49.737150Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking for 'native:zwo_efw:0' in native_filter_wheels: ["native:zwo_efw:0"]
←[2m2026-01-04T01:34:49.738613Z←[0m ←[32m INFO←[0m filter_wheel_get_config: Returning 8 filter names: ["L", "R", "G", "B", "Ha", "OIII", "SII", "Filter 8"]
←[2m2026-01-04T01:34:49.748703Z←[0m ←[34mDEBUG←[0m Moving ZWO EFW to position 5
←[2m2026-01-04T01:34:49.748701Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(2)
←[2m2026-01-04T01:34:49.754461Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:34:49.759261Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:34:49.763781Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:34:49.764867Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(2)
←[2m2026-01-04T01:34:49.766626Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:34:49.769797Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:34:49.772095Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:34:49.774292Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(2)
←[2m2026-01-04T01:34:49.778442Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:34:49.952924Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:34:49.953386Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:34:49.956850Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-04T01:34:49.956875Z←[0m ←[32m INFO←[0m Capturing frame 1/1 (2.0s)
[SequenceProvider] Received event: type=FilterChanging, category=EventCategory.equipment←[2m2026-01-04T01:34:49.959011Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)

←[2m2026-01-04T01:34:49.960026Z←[0m ←[32m INFO←[0m Starting 2.0s exposure on camera native:zwo:1
[SequenceProvider] Received event: type=NodeStarted, category=EventCategory.sequencer
←[2m2026-01-04T01:34:49.962312Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:49.965594Z←[0m ←[32m INFO←[0m DeviceManager: camera_start_exposure for native:zwo:1 duration=2
←[2m2026-01-04T01:34:49.971464Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:34:49.973557Z←[0m ←[32m INFO←[0m DeviceManager: Starting Native SDK exposure
←[2m2026-01-04T01:34:49.975524Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:34:49.978842Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:49.981126Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:49.983816Z←[0m ←[32m INFO←[0m Started 2s exposure
[SequenceProvider] Received event: type=NodeStarted, category=EventCategory.sequencer
←[2m2026-01-04T01:34:49.989053Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:49.992169Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:49.992488Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:34:49.994165Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:34:50.006980Z←[0m ←[34mDEBUG←[0m Retrieved observer location: lat=40.007714, lon=-75.397448, elev=0
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:50.009859Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=NodeStarted, category=EventCategory.sequencer
←[2m2026-01-04T01:34:50.011085Z←[0m ←[34mDEBUG←[0m Observer location retrieved: lat=40.007714, lon=-75.397448
←[2m2026-01-04T01:34:50.019771Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:50.021958Z←[0m ←[34mDEBUG←[0m Observer location set for dawn trigger: 40.007714, -75.397448
←[2m2026-01-04T01:34:50.025069Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-04T01:34:50.035015Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=FilterChanged, category=EventCategory.equipment
←[2m2026-01-04T01:34:50.038661Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=ExposureStarted, category=EventCategory.imaging
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:50.093564Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:50.195248Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:50.297034Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:50.397676Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:50.499376Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:50.508379Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:34:50.601234Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
[IMAGING] AnnotationService initialized
←[2m2026-01-04T01:34:50.702891Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:50.804696Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:50.906458Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:51.009137Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:51.110849Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:51.212473Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:51.314262Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:51.415921Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:51.508743Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:34:51.516745Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:51.618637Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:51.720420Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:51.821449Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:51.924234Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:52.025902Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:52.127009Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:52.228342Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:52.331212Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:52.432799Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:52.507596Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:34:52.534658Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:52.636109Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:52.737774Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:52.840258Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:52.942048Z←[0m ←[32m INFO←[0m ZWO exposure status: 2 (Success)
←[2m2026-01-04T01:34:53.120788Z←[0m ←[32m INFO←[0m ZWO DIAGNOSTIC: Raw buffer stats - min=16, max=3584, avg=17, non_zero=16389120/16389120, img_type=2
←[2m2026-01-04T01:34:53.121559Z←[0m ←[32m INFO←[0m Downloaded 4656x3520 image (32778240 bytes, img_type=2)
←[2m2026-01-04T01:34:53.135790Z←[0m ←[32m INFO←[0m [EXPOSURE] Download complete: 4656x3520 (16389120 pixels)
←[2m2026-01-04T01:34:53.161419Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Starting image validation...
←[2m2026-01-04T01:34:53.207924Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] Stats: size=16389120, min=16, max=3584, mean=17, saturated=0.0%
←[2m2026-01-04T01:34:53.215852Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] PASSED: Image validated successfully
←[2m2026-01-04T01:34:53.216356Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Validation complete: valid=true
←[2m2026-01-04T01:34:53.939710Z←[0m ←[34mDEBUG←[0m Star rejected: sharpness 1.00 > max 0.70 (pos: 10.9,10.6)
←[2m2026-01-04T01:34:53.939916Z←[0m ←[34mDEBUG←[0m Star rejected: eccentricity 0.88 > max 0.70 (pos: 46.1,11.9)
←[2m2026-01-04T01:34:53.941086Z←[0m ←[34mDEBUG←[0m Star rejected: eccentricity 0.80 > max 0.70 (pos: 84.9,10.7)
←[2m2026-01-04T01:34:53.941774Z←[0m ←[34mDEBUG←[0m Star rejected: eccentricity 0.83 > max 0.70 (pos: 112.9,11.8)
←[2m2026-01-04T01:34:53.942517Z←[0m ←[34mDEBUG←[0m Star rejected: eccentricity 0.83 > max 0.70 (pos: 138.4,11.0)
←[2m2026-01-04T01:34:55.204159Z←[0m ←[32m INFO←[0m Stored image in unified storage for UI display
←[2m2026-01-04T01:34:55.213288Z←[0m ←[32m INFO←[0m Exposure complete: 4656x3520 image, Monochrome sensor
←[2m2026-01-04T01:34:55.213829Z←[0m ←[32m INFO←[0m [SEQ] Exposure completed: 4656x3520 image (16389120 pixels)
←[2m2026-01-04T01:34:56.903231Z←[0m ←[33m WARN←[0m Frame 1/1 - no stars detected for HFR calculation
←[2m2026-01-04T01:34:56.903826Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:34:56.910012Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:34:56.912406Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:56.914887Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureComplete, category=EventCategory.imaging←[2m2026-01-04T01:34:56.920696Z←[0m ←[34mDEBUG←[0m Updated trigger state exposure count: 1

[SEQ_PROVIDER] ExposureComplete imaging event received - fetching image for preview
←[2m2026-01-04T01:34:56.926265Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed 1 exposures (2s)
[SEQ_PROVIDER] _fetchAndDisplaySequenceImage called, duration=2.0s
←[2m2026-01-04T01:34:56.926927Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
[SEQ_PROVIDER] Calling bridge.apiGetLastImage()...
←[2m2026-01-04T01:34:56.928182Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed: H-alpha
←[2m2026-01-04T01:34:56.929401Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Completed', rest=' H-alpha'
←[2m2026-01-04T01:34:56.930050Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' H-alpha'
←[2m2026-01-04T01:34:56.928843Z←[0m ←[32m INFO←[0m API: api_get_last_image called
←[2m2026-01-04T01:34:56.930833Z←[0m ←[32m INFO←[0m Child 'H-alpha' completed with status: Success
←[2m2026-01-04T01:34:56.932007Z←[0m ←[32m INFO←[0m API: Returning stored image 4656x3520, display_data size: 16389120 bytes
←[2m2026-01-04T01:34:56.933595Z←[0m ←[32m INFO←[0m FOR LOOP ENTERED: iteration 1 of 3
←[2m2026-01-04T01:34:56.936159Z←[0m ←[32m INFO←[0m Executing child 2/3: 'OIII' (id=cea6e7af-61a6-449c-85e0-349ca864c05f)
[SEQ_PROVIDER] Got image: 4656x3520, displayData size: 16389120
←[2m2026-01-04T01:34:56.946636Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Step 2/3: OIII
←[2m2026-01-04T01:34:56.949703Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Step 2/3', rest=' OIII'
←[2m2026-01-04T01:34:56.956100Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' OIII'
←[2m2026-01-04T01:34:56.957474Z←[0m ←[32m INFO←[0m [PROGRESS_CB] Emitting NodeStarted: id=cea6e7af-61a6-449c-85e0-349ca864c05f, name=OIII
←[2m2026-01-04T01:34:56.958665Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Executing: OIII
←[2m2026-01-04T01:34:56.959696Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Executing', rest=' OIII'
←[2m2026-01-04T01:34:56.960732Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' OIII'
←[2m2026-01-04T01:34:56.962504Z←[0m ←[32m INFO←[0m Starting 1 OIII x 2.0s exposures
←[2m2026-01-04T01:34:56.964541Z←[0m ←[32m INFO←[0m Changing to filter: OIII
←[2m2026-01-04T01:34:56.965487Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking up device_id='native:zwo_efw:0'
[SEQ_PROVIDER] Setting currentImageProvider with image 4656x3520←[2m2026-01-04T01:34:56.966121Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Available devices in registry: ["native:zwo:1", "native:zwo_efw:0", "native:zwo_eaf:0", "ascom:ASCOM.PegasusAstroNYX101.Telescope"]

[SEQ_PROVIDER] Providers updated successfully!
←[2m2026-01-04T01:34:56.967165Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Found device with driver_type=Native
←[2m2026-01-04T01:34:56.968135Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking for 'native:zwo_efw:0' in native_filter_wheels: ["native:zwo_efw:0"]
←[2m2026-01-04T01:34:56.977040Z←[0m ←[32m INFO←[0m filter_wheel_get_config: Returning 8 filter names: ["L", "R", "G", "B", "Ha", "OIII", "SII", "Filter 8"]
←[2m2026-01-04T01:34:56.978869Z←[0m ←[34mDEBUG←[0m Moving ZWO EFW to position 6
←[2m2026-01-04T01:34:56.978899Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:34:56.980934Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:34:56.981750Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:34:56.982610Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:34:56.983673Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(2)
←[2m2026-01-04T01:34:56.985171Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:34:57.180420Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:34:57.180686Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:34:57.183633Z←[0m ←[32m INFO←[0m Capturing frame 1/1 (2.0s)
←[2m2026-01-04T01:34:57.183667Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[SequenceProvider] Received event: type=FilterChanging, category=EventCategory.equipment
←[2m2026-01-04T01:34:57.185636Z←[0m ←[32m INFO←[0m Starting 2.0s exposure on camera native:zwo:1
←[2m2026-01-04T01:34:57.191072Z←[0m ←[32m INFO←[0m DeviceManager: camera_start_exposure for native:zwo:1 duration=2
←[2m2026-01-04T01:34:57.187668Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:57.193470Z←[0m ←[32m INFO←[0m DeviceManager: Starting Native SDK exposure
←[2m2026-01-04T01:34:57.195526Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:57.198469Z←[0m ←[32m INFO←[0m Started 2s exposure
←[2m2026-01-04T01:34:57.199089Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:57.201641Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:34:57.207421Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:57.209678Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:34:57.211430Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=NodeStarted, category=EventCategory.sequencer
←[2m2026-01-04T01:34:57.216112Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:57.217270Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[SequenceProvider] Received event: type=FilterChanged, category=EventCategory.equipment←[2m2026-01-04T01:34:57.221519Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)

[SequenceProvider] Received event: type=ExposureStarted, category=EventCategory.imaging
←[2m2026-01-04T01:34:57.225318Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:34:57.249357Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:34:57.288215Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:34:57.304267Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:57.336326Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:34:57.405985Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:57.507698Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:34:57.508460Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:57.610367Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:57.713207Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:57.813971Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:57.914623Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:58.017410Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:58.120096Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:58.221745Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:58.323514Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:58.426252Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:58.508934Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:34:58.527074Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:58.628746Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:58.730295Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:58.833091Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:58.934907Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:59.035551Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:59.137306Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:59.239940Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:59.341775Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:59.443544Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:59.507383Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:34:59.544936Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:59.646572Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:59.749240Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:59.850965Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:34:59.952834Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:00.054612Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:00.156216Z←[0m ←[32m INFO←[0m ZWO exposure status: 2 (Success)
←[2m2026-01-04T01:35:00.340396Z←[0m ←[32m INFO←[0m ZWO DIAGNOSTIC: Raw buffer stats - min=16, max=3888, avg=18, non_zero=16389120/16389120, img_type=2
←[2m2026-01-04T01:35:00.340921Z←[0m ←[32m INFO←[0m Downloaded 4656x3520 image (32778240 bytes, img_type=2)
←[2m2026-01-04T01:35:00.345238Z←[0m ←[32m INFO←[0m [EXPOSURE] Download complete: 4656x3520 (16389120 pixels)
←[2m2026-01-04T01:35:00.345330Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:00.361452Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Starting image validation...
←[2m2026-01-04T01:35:00.418343Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] Stats: size=16389120, min=16, max=3888, mean=18, saturated=0.0%
←[2m2026-01-04T01:35:00.427373Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] PASSED: Image validated successfully
←[2m2026-01-04T01:35:00.428417Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Validation complete: valid=true
←[2m2026-01-04T01:35:02.691027Z←[0m ←[32m INFO←[0m Stored image in unified storage for UI display
←[2m2026-01-04T01:35:02.697892Z←[0m ←[32m INFO←[0m Exposure complete: 4656x3520 image, Monochrome sensor
←[2m2026-01-04T01:35:02.698341Z←[0m ←[32m INFO←[0m [SEQ] Exposure completed: 4656x3520 image (16389120 pixels)
←[2m2026-01-04T01:35:04.176312Z←[0m ←[33m WARN←[0m Frame 1/1 - no stars detected for HFR calculation
←[2m2026-01-04T01:35:04.177246Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:35:04.189073Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:04.190942Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureComplete, category=EventCategory.imaging
[SEQ_PROVIDER] ExposureComplete imaging event received - fetching image for preview
[SEQ_PROVIDER] _fetchAndDisplaySequenceImage called, duration=2.0s
[SEQ_PROVIDER] Calling bridge.apiGetLastImage()...
←[2m2026-01-04T01:35:04.200021Z←[0m ←[34mDEBUG←[0m Updated trigger state exposure count: 2
←[2m2026-01-04T01:35:04.203885Z←[0m ←[32m INFO←[0m API: api_get_last_image called
←[2m2026-01-04T01:35:04.209497Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed 1 exposures (2s)
←[2m2026-01-04T01:35:04.217210Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:04.215795Z←[0m ←[32m INFO←[0m API: Returning stored image 4656x3520, display_data size: 16389120 bytes
←[2m2026-01-04T01:35:04.218836Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed: OIII
←[2m2026-01-04T01:35:04.222258Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Completed', rest=' OIII'
←[2m2026-01-04T01:35:04.226698Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' OIII'
←[2m2026-01-04T01:35:04.230913Z←[0m ←[32m INFO←[0m Child 'OIII' completed with status: Success
←[2m2026-01-04T01:35:04.233050Z←[0m ←[32m INFO←[0m FOR LOOP ENTERED: iteration 2 of 3
[SEQ_PROVIDER] Got image: 4656x3520, displayData size: 16389120←[2m2026-01-04T01:35:04.234190Z←[0m ←[32m INFO←[0m Executing child 3/3: 'SII' (id=4ff8fef4-8930-46b1-bbd3-55f99aca08f8)

←[2m2026-01-04T01:35:04.235512Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Step 3/3: SII
←[2m2026-01-04T01:35:04.237126Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Step 3/3', rest=' SII'
←[2m2026-01-04T01:35:04.238988Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' SII'
←[2m2026-01-04T01:35:04.244402Z←[0m ←[32m INFO←[0m [PROGRESS_CB] Emitting NodeStarted: id=4ff8fef4-8930-46b1-bbd3-55f99aca08f8, name=SII
←[2m2026-01-04T01:35:04.246096Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Executing: SII
←[2m2026-01-04T01:35:04.247576Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Executing', rest=' SII'
←[2m2026-01-04T01:35:04.248686Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' SII'
←[2m2026-01-04T01:35:04.249470Z←[0m ←[32m INFO←[0m Starting 1 SII x 2.0s exposures
←[2m2026-01-04T01:35:04.250229Z←[0m ←[32m INFO←[0m Changing to filter: SII
[SEQ_PROVIDER] Setting currentImageProvider with image 4656x3520
←[2m2026-01-04T01:35:04.250969Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking up device_id='native:zwo_efw:0'
[SEQ_PROVIDER] Providers updated successfully!
←[2m2026-01-04T01:35:04.252445Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Available devices in registry: ["native:zwo:1", "native:zwo_efw:0", "native:zwo_eaf:0", "ascom:ASCOM.PegasusAstroNYX101.Telescope"]
←[2m2026-01-04T01:35:04.257163Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Found device with driver_type=Native
←[2m2026-01-04T01:35:04.264119Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking for 'native:zwo_efw:0' in native_filter_wheels: ["native:zwo_efw:0"]
←[2m2026-01-04T01:35:04.266203Z←[0m ←[32m INFO←[0m filter_wheel_get_config: Returning 8 filter names: ["L", "R", "G", "B", "Ha", "OIII", "SII", "Filter 8"]
←[2m2026-01-04T01:35:04.267953Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:04.268238Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:04.267963Z←[0m ←[34mDEBUG←[0m Moving ZWO EFW to position 7
←[2m2026-01-04T01:35:04.269700Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:04.272639Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:04.273616Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(2)
←[2m2026-01-04T01:35:04.274668Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:04.471381Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:35:04.472036Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:04.474212Z←[0m ←[32m INFO←[0m Capturing frame 1/1 (2.0s)
←[2m2026-01-04T01:35:04.475472Z←[0m ←[32m INFO←[0m Starting 2.0s exposure on camera native:zwo:1
←[2m2026-01-04T01:35:04.474235Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[SequenceProvider] Received event: type=FilterChanging, category=EventCategory.equipment
←[2m2026-01-04T01:35:04.476496Z←[0m ←[32m INFO←[0m DeviceManager: camera_start_exposure for native:zwo:1 duration=2
←[2m2026-01-04T01:35:04.477653Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer←[2m2026-01-04T01:35:04.479314Z←[0m ←[32m INFO←[0m DeviceManager: Starting Native SDK exposure

←[2m2026-01-04T01:35:04.483564Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:04.487310Z←[0m ←[32m INFO←[0m Started 2s exposure
←[2m2026-01-04T01:35:04.488205Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:04.489976Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:04.491242Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:04.497970Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:04.505529Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=NodeStarted, category=EventCategory.sequencer
←[2m2026-01-04T01:35:04.513157Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:04.516339Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-04T01:35:04.518521Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
←[2m2026-01-04T01:35:04.519993Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:04.536787Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
[SequenceProvider] Received event: type=FilterChanged, category=EventCategory.equipment
[SequenceProvider] Received event: type=ExposureStarted, category=EventCategory.imaging
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:04.585194Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:04.592612Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:04.635192Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:04.693889Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:04.722611Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:04.795777Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:04.897415Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:05.000026Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:05.101767Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:05.203807Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:05.305263Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:05.407097Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:05.508819Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:05.509613Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:05.610406Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:05.713185Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:05.814429Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:05.917136Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:06.018868Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:06.121186Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:06.222654Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:06.324339Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:06.426977Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:06.508778Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:06.528718Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:06.630405Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:06.733108Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:06.835024Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:06.936784Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:07.039339Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:07.141186Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:07.242780Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:07.344556Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:07.446314Z←[0m ←[32m INFO←[0m ZWO exposure status: 2 (Success)
←[2m2026-01-04T01:35:07.594124Z←[0m ←[32m INFO←[0m ZWO DIAGNOSTIC: Raw buffer stats - min=16, max=3552, avg=16, non_zero=16389120/16389120, img_type=2
←[2m2026-01-04T01:35:07.594828Z←[0m ←[32m INFO←[0m Downloaded 4656x3520 image (32778240 bytes, img_type=2)
←[2m2026-01-04T01:35:07.603085Z←[0m ←[32m INFO←[0m [EXPOSURE] Download complete: 4656x3520 (16389120 pixels)
←[2m2026-01-04T01:35:07.617660Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Starting image validation...
←[2m2026-01-04T01:35:07.674188Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] Stats: size=16389120, min=16, max=3552, mean=16, saturated=0.0%
←[2m2026-01-04T01:35:07.683893Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] PASSED: Image validated successfully
←[2m2026-01-04T01:35:07.684448Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Validation complete: valid=true
←[2m2026-01-04T01:35:09.314308Z←[0m ←[32m INFO←[0m Stored image in unified storage for UI display
←[2m2026-01-04T01:35:09.319056Z←[0m ←[32m INFO←[0m Exposure complete: 4656x3520 image, Monochrome sensor
←[2m2026-01-04T01:35:09.319377Z←[0m ←[32m INFO←[0m [SEQ] Exposure completed: 4656x3520 image (16389120 pixels)
←[2m2026-01-04T01:35:10.495938Z←[0m ←[33m WARN←[0m Frame 1/1 - no stars detected for HFR calculation
←[2m2026-01-04T01:35:10.496353Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:35:10.498394Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:10.499846Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:10.500783Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureComplete, category=EventCategory.imaging
[SEQ_PROVIDER] ExposureComplete imaging event received - fetching image for preview
[SEQ_PROVIDER] _fetchAndDisplaySequenceImage called, duration=2.0s
[SEQ_PROVIDER] Calling bridge.apiGetLastImage()...
←[2m2026-01-04T01:35:10.509008Z←[0m ←[32m INFO←[0m API: api_get_last_image called
←[2m2026-01-04T01:35:10.509036Z←[0m ←[34mDEBUG←[0m Updated trigger state exposure count: 3
←[2m2026-01-04T01:35:10.512945Z←[0m ←[32m INFO←[0m API: Returning stored image 4656x3520, display_data size: 16389120 bytes
←[2m2026-01-04T01:35:10.520676Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed 1 exposures (2s)
←[2m2026-01-04T01:35:10.525022Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:10.527404Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed: SII
←[2m2026-01-04T01:35:10.531121Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Completed', rest=' SII'
←[2m2026-01-04T01:35:10.533665Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' SII'
[SEQ_PROVIDER] Got image: 4656x3520, displayData size: 16389120
←[2m2026-01-04T01:35:10.535316Z←[0m ←[32m INFO←[0m Child 'SII' completed with status: Success
←[2m2026-01-04T01:35:10.542919Z←[0m ←[32m INFO←[0m execute_children_sequential completed with result: Success
←[2m2026-01-04T01:35:10.551356Z←[0m ←[32m INFO←[0m === LOOP ITERATION 2 STARTING ===
←[2m2026-01-04T01:35:10.554429Z←[0m ←[32m INFO←[0m Loop has 3 children
←[2m2026-01-04T01:35:10.557213Z←[0m ←[32m INFO←[0m   Child 0: 'H-alpha' (id=b2900721-b649-4109-aca9-eedce853c5b0)
[SEQ_PROVIDER] Setting currentImageProvider with image 4656x3520
←[2m2026-01-04T01:35:10.559531Z←[0m ←[32m INFO←[0m   Child 1: 'OIII' (id=cea6e7af-61a6-449c-85e0-349ca864c05f)
[SEQ_PROVIDER] Providers updated successfully!
←[2m2026-01-04T01:35:10.562104Z←[0m ←[32m INFO←[0m   Child 2: 'SII' (id=4ff8fef4-8930-46b1-bbd3-55f99aca08f8)
←[2m2026-01-04T01:35:10.563552Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Loop iteration 2
←[2m2026-01-04T01:35:10.566025Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:10.566795Z←[0m ←[32m INFO←[0m Resetting 3 children for iteration 2
←[2m2026-01-04T01:35:10.567512Z←[0m ←[32m INFO←[0m Children reset complete
←[2m2026-01-04T01:35:10.568155Z←[0m ←[32m INFO←[0m Starting execute_children_sequential for iteration 2
←[2m2026-01-04T01:35:10.569435Z←[0m ←[34mDEBUG←[0m execute_children_sequential: node 05d83e14-62d5-4d8b-a240-b2a77a8afef0 has 3 children
←[2m2026-01-04T01:35:10.570807Z←[0m ←[32m INFO←[0m About to enter for loop with 3 children
←[2m2026-01-04T01:35:10.572077Z←[0m ←[32m INFO←[0m FOR LOOP ENTERED: iteration 0 of 3
←[2m2026-01-04T01:35:10.573480Z←[0m ←[32m INFO←[0m Executing child 1/3: 'H-alpha' (id=b2900721-b649-4109-aca9-eedce853c5b0)
←[2m2026-01-04T01:35:10.577934Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Step 1/3: H-alpha
←[2m2026-01-04T01:35:10.578645Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Step 1/3', rest=' H-alpha'
←[2m2026-01-04T01:35:10.579344Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' H-alpha'
←[2m2026-01-04T01:35:10.579931Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Executing: H-alpha
←[2m2026-01-04T01:35:10.580571Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Executing', rest=' H-alpha'
←[2m2026-01-04T01:35:10.581228Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' H-alpha'
←[2m2026-01-04T01:35:10.581777Z←[0m ←[32m INFO←[0m Starting 1 Ha x 2.0s exposures
←[2m2026-01-04T01:35:10.582401Z←[0m ←[32m INFO←[0m Changing to filter: Ha
←[2m2026-01-04T01:35:10.582950Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking up device_id='native:zwo_efw:0'
←[2m2026-01-04T01:35:10.583572Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Available devices in registry: ["native:zwo:1", "native:zwo_efw:0", "native:zwo_eaf:0", "ascom:ASCOM.PegasusAstroNYX101.Telescope"]
←[2m2026-01-04T01:35:10.584347Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Found device with driver_type=Native
←[2m2026-01-04T01:35:10.585274Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking for 'native:zwo_efw:0' in native_filter_wheels: ["native:zwo_efw:0"]
←[2m2026-01-04T01:35:10.585557Z←[0m ←[32m INFO←[0m filter_wheel_get_config: Returning 8 filter names: ["L", "R", "G", "B", "Ha", "OIII", "SII", "Filter 8"]
←[2m2026-01-04T01:35:10.586690Z←[0m ←[34mDEBUG←[0m Moving ZWO EFW to position 5
←[2m2026-01-04T01:35:10.586763Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:10.588365Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:10.589264Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:10.590048Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:10.593751Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:10.594412Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:10.788602Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:35:10.789533Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:10.793583Z←[0m ←[32m INFO←[0m Capturing frame 1/1 (2.0s)
←[2m2026-01-04T01:35:10.793687Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-04T01:35:10.795666Z←[0m ←[32m INFO←[0m Starting 2.0s exposure on camera native:zwo:1
←[2m2026-01-04T01:35:10.798320Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:10.800255Z←[0m ←[32m INFO←[0m DeviceManager: camera_start_exposure for native:zwo:1 duration=2
←[2m2026-01-04T01:35:10.801570Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:10.802492Z←[0m ←[32m INFO←[0m DeviceManager: Starting Native SDK exposure
←[2m2026-01-04T01:35:10.804673Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:10.807669Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:10.808110Z←[0m ←[32m INFO←[0m Started 2s exposure
[SequenceProvider] Received event: type=FilterChanging, category=EventCategory.equipment←[2m2026-01-04T01:35:10.809085Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)

[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:10.810391Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer←[2m2026-01-04T01:35:10.818319Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)

[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:10.820064Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:10.822324Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:10.826140Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:10.835158Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=FilterChanged, category=EventCategory.equipment
[SequenceProvider] Received event: type=ExposureStarted, category=EventCategory.imaging
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:10.856515Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:10.905569Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:10.912919Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:10.952196Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:11.014521Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:11.116420Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:11.218967Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:11.320753Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:11.422464Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:11.508335Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:11.524408Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:11.626272Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:11.727879Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:11.829535Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:11.931212Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:12.033070Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:12.134643Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:12.236479Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:12.339210Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:12.441003Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:12.508750Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:12.542680Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:12.643466Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:12.745281Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:12.847039Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:12.948433Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:13.050182Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:13.151899Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:13.253686Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:13.355617Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:13.458248Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:13.508088Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:13.559936Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:13.660602Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:13.762335Z←[0m ←[32m INFO←[0m ZWO exposure status: 2 (Success)
←[2m2026-01-04T01:35:13.917763Z←[0m ←[32m INFO←[0m ZWO DIAGNOSTIC: Raw buffer stats - min=16, max=3680, avg=17, non_zero=16389120/16389120, img_type=2
←[2m2026-01-04T01:35:13.917996Z←[0m ←[32m INFO←[0m Downloaded 4656x3520 image (32778240 bytes, img_type=2)
←[2m2026-01-04T01:35:13.925306Z←[0m ←[32m INFO←[0m [EXPOSURE] Download complete: 4656x3520 (16389120 pixels)
←[2m2026-01-04T01:35:13.950721Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Starting image validation...
←[2m2026-01-04T01:35:14.013319Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] Stats: size=16389120, min=16, max=3680, mean=17, saturated=0.0%
←[2m2026-01-04T01:35:14.017721Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] PASSED: Image validated successfully
←[2m2026-01-04T01:35:14.017947Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Validation complete: valid=true
←[2m2026-01-04T01:35:16.021424Z←[0m ←[32m INFO←[0m Stored image in unified storage for UI display
←[2m2026-01-04T01:35:16.029218Z←[0m ←[32m INFO←[0m Exposure complete: 4656x3520 image, Monochrome sensor
←[2m2026-01-04T01:35:16.030149Z←[0m ←[32m INFO←[0m [SEQ] Exposure completed: 4656x3520 image (16389120 pixels)
←[2m2026-01-04T01:35:17.646501Z←[0m ←[33m WARN←[0m Frame 1/1 - no stars detected for HFR calculation
←[2m2026-01-04T01:35:17.646835Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:35:17.649727Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:17.652348Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:17.653052Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureComplete, category=EventCategory.imaging
[SEQ_PROVIDER] ExposureComplete imaging event received - fetching image for preview
[SEQ_PROVIDER] _fetchAndDisplaySequenceImage called, duration=2.0s
←[2m2026-01-04T01:35:17.659837Z←[0m ←[34mDEBUG←[0m Updated trigger state exposure count: 4
[SEQ_PROVIDER] Calling bridge.apiGetLastImage()...
←[2m2026-01-04T01:35:17.661898Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed 1 exposures (2s)
←[2m2026-01-04T01:35:17.665602Z←[0m ←[32m INFO←[0m API: api_get_last_image called
←[2m2026-01-04T01:35:17.668740Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:17.676247Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed: H-alpha
←[2m2026-01-04T01:35:17.677244Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Completed', rest=' H-alpha'
←[2m2026-01-04T01:35:17.672564Z←[0m ←[32m INFO←[0m API: Returning stored image 4656x3520, display_data size: 16389120 bytes
←[2m2026-01-04T01:35:17.678180Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' H-alpha'
←[2m2026-01-04T01:35:17.682359Z←[0m ←[32m INFO←[0m Child 'H-alpha' completed with status: Success
←[2m2026-01-04T01:35:17.683914Z←[0m ←[32m INFO←[0m FOR LOOP ENTERED: iteration 1 of 3
←[2m2026-01-04T01:35:17.685596Z←[0m ←[32m INFO←[0m Executing child 2/3: 'OIII' (id=cea6e7af-61a6-449c-85e0-349ca864c05f)
←[2m2026-01-04T01:35:17.688006Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Step 2/3: OIII
←[2m2026-01-04T01:35:17.689891Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Step 2/3', rest=' OIII'
[SEQ_PROVIDER] Got image: 4656x3520, displayData size: 16389120
←[2m2026-01-04T01:35:17.693077Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' OIII'
←[2m2026-01-04T01:35:17.700091Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Executing: OIII
←[2m2026-01-04T01:35:17.701593Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Executing', rest=' OIII'
←[2m2026-01-04T01:35:17.702983Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' OIII'
←[2m2026-01-04T01:35:17.704268Z←[0m ←[32m INFO←[0m Starting 1 OIII x 2.0s exposures
←[2m2026-01-04T01:35:17.705845Z←[0m ←[32m INFO←[0m Changing to filter: OIII
←[2m2026-01-04T01:35:17.708430Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking up device_id='native:zwo_efw:0'
←[2m2026-01-04T01:35:17.710308Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Available devices in registry: ["native:zwo:1", "native:zwo_efw:0", "native:zwo_eaf:0", "ascom:ASCOM.PegasusAstroNYX101.Telescope"]
←[2m2026-01-04T01:35:17.716846Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Found device with driver_type=Native
←[2m2026-01-04T01:35:17.718185Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking for 'native:zwo_efw:0' in native_filter_wheels: ["native:zwo_efw:0"]
←[2m2026-01-04T01:35:17.719628Z←[0m ←[32m INFO←[0m filter_wheel_get_config: Returning 8 filter names: ["L", "R", "G", "B", "Ha", "OIII", "SII", "Filter 8"]
[SEQ_PROVIDER] Setting currentImageProvider with image 4656x3520
←[2m2026-01-04T01:35:17.721790Z←[0m ←[34mDEBUG←[0m Moving ZWO EFW to position 6
[SEQ_PROVIDER] Providers updated successfully!
←[2m2026-01-04T01:35:17.721845Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:17.728982Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:17.734296Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:17.736503Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:17.738773Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:17.924824Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:35:17.925328Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:17.929058Z←[0m ←[32m INFO←[0m Capturing frame 1/1 (2.0s)
←[2m2026-01-04T01:35:17.929137Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[SequenceProvider] Received event: type=FilterChanging, category=EventCategory.equipment←[2m2026-01-04T01:35:17.934168Z←[0m ←[32m INFO←[0m Starting 2.0s exposure on camera native:zwo:1

←[2m2026-01-04T01:35:17.939793Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:17.943012Z←[0m ←[32m INFO←[0m DeviceManager: camera_start_exposure for native:zwo:1 duration=2
←[2m2026-01-04T01:35:17.945926Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:17.951690Z←[0m ←[32m INFO←[0m DeviceManager: Starting Native SDK exposure
←[2m2026-01-04T01:35:17.953507Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:17.956329Z←[0m ←[32m INFO←[0m Started 2s exposure
←[2m2026-01-04T01:35:17.956544Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:17.957928Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:17.959429Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:17.965106Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:17.972437Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-04T01:35:17.987122Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
←[2m2026-01-04T01:35:17.990275Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=FilterChanged, category=EventCategory.equipment
[SequenceProvider] Received event: type=ExposureStarted, category=EventCategory.imaging
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:18.004441Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:18.057881Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:18.059604Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:18.103219Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:18.161387Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:18.263912Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:18.365602Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:18.467371Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:18.509268Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:18.570083Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:18.671825Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:18.773577Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:18.875357Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:18.978016Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:19.079723Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:19.181430Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:19.284157Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:19.368940Z←[0m ←[32m INFO←[0m Saving checkpoint
[NativeBridge] Error saving checkpoint via native: NightshadeError.operationFailed(field0: No checkpoint manager configured)
Failed to save checkpoint: NightshadeError.operationFailed(field0: No checkpoint manager configured)
←[2m2026-01-04T01:35:19.385893Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:19.487747Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:19.508593Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:19.589537Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:19.691107Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:19.792884Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:19.894687Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:19.996466Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:20.098031Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:20.199929Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:20.301423Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:20.403153Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:20.504896Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:20.507889Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:20.606661Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
←[2m2026-01-04T01:35:20.708358Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[IMAGING] AnnotationService initialized
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:20.811368Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:20.913826Z←[0m ←[32m INFO←[0m ZWO exposure status: 2 (Success)
←[2m2026-01-04T01:35:21.077289Z←[0m ←[32m INFO←[0m ZWO DIAGNOSTIC: Raw buffer stats - min=16, max=3696, avg=18, non_zero=16389120/16389120, img_type=2
←[2m2026-01-04T01:35:21.077507Z←[0m ←[32m INFO←[0m Downloaded 4656x3520 image (32778240 bytes, img_type=2)
←[2m2026-01-04T01:35:21.081451Z←[0m ←[32m INFO←[0m [EXPOSURE] Download complete: 4656x3520 (16389120 pixels)
←[2m2026-01-04T01:35:21.097759Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Starting image validation...
←[2m2026-01-04T01:35:21.160175Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] Stats: size=16389120, min=16, max=3696, mean=18, saturated=0.0%
←[2m2026-01-04T01:35:21.164436Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] PASSED: Image validated successfully
←[2m2026-01-04T01:35:21.164639Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Validation complete: valid=true
←[2m2026-01-04T01:35:23.159129Z←[0m ←[32m INFO←[0m Stored image in unified storage for UI display
←[2m2026-01-04T01:35:23.165688Z←[0m ←[32m INFO←[0m Exposure complete: 4656x3520 image, Monochrome sensor
←[2m2026-01-04T01:35:23.166219Z←[0m ←[32m INFO←[0m [SEQ] Exposure completed: 4656x3520 image (16389120 pixels)
←[2m2026-01-04T01:35:24.802013Z←[0m ←[33m WARN←[0m Frame 1/1 - no stars detected for HFR calculation
←[2m2026-01-04T01:35:24.802325Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:35:24.804074Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:24.806310Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:24.808310Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureComplete, category=EventCategory.imaging
←[2m2026-01-04T01:35:24.813996Z←[0m ←[34mDEBUG←[0m Updated trigger state exposure count: 5
[SEQ_PROVIDER] ExposureComplete imaging event received - fetching image for preview
[SEQ_PROVIDER] _fetchAndDisplaySequenceImage called, duration=2.0s←[2m2026-01-04T01:35:24.821462Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed 1 exposures (2s)

[SEQ_PROVIDER] Calling bridge.apiGetLastImage()...←[2m2026-01-04T01:35:24.824557Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message

←[2m2026-01-04T01:35:24.831179Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed: OIII
←[2m2026-01-04T01:35:24.831202Z←[0m ←[32m INFO←[0m API: api_get_last_image called
←[2m2026-01-04T01:35:24.839092Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Completed', rest=' OIII'
←[2m2026-01-04T01:35:24.844027Z←[0m ←[32m INFO←[0m API: Returning stored image 4656x3520, display_data size: 16389120 bytes
←[2m2026-01-04T01:35:24.845628Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' OIII'
←[2m2026-01-04T01:35:24.850261Z←[0m ←[32m INFO←[0m Child 'OIII' completed with status: Success
←[2m2026-01-04T01:35:24.851648Z←[0m ←[32m INFO←[0m FOR LOOP ENTERED: iteration 2 of 3
←[2m2026-01-04T01:35:24.852489Z←[0m ←[32m INFO←[0m Executing child 3/3: 'SII' (id=4ff8fef4-8930-46b1-bbd3-55f99aca08f8)
←[2m2026-01-04T01:35:24.853513Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Step 3/3: SII
←[2m2026-01-04T01:35:24.854448Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Step 3/3', rest=' SII'
[SEQ_PROVIDER] Got image: 4656x3520, displayData size: 16389120
←[2m2026-01-04T01:35:24.855881Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' SII'
←[2m2026-01-04T01:35:24.857477Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Executing: SII
←[2m2026-01-04T01:35:24.858853Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Executing', rest=' SII'
←[2m2026-01-04T01:35:24.860401Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' SII'
←[2m2026-01-04T01:35:24.861990Z←[0m ←[32m INFO←[0m Starting 1 SII x 2.0s exposures
←[2m2026-01-04T01:35:24.866486Z←[0m ←[32m INFO←[0m Changing to filter: SII
←[2m2026-01-04T01:35:24.868843Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking up device_id='native:zwo_efw:0'
←[2m2026-01-04T01:35:24.870141Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Available devices in registry: ["native:zwo:1", "native:zwo_efw:0", "native:zwo_eaf:0", "ascom:ASCOM.PegasusAstroNYX101.Telescope"]
←[2m2026-01-04T01:35:24.871140Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Found device with driver_type=Native
[SEQ_PROVIDER] Setting currentImageProvider with image 4656x3520
←[2m2026-01-04T01:35:24.873537Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking for 'native:zwo_efw:0' in native_filter_wheels: ["native:zwo_efw:0"]
[SEQ_PROVIDER] Providers updated successfully!
←[2m2026-01-04T01:35:24.878536Z←[0m ←[32m INFO←[0m filter_wheel_get_config: Returning 8 filter names: ["L", "R", "G", "B", "Ha", "OIII", "SII", "Filter 8"]
←[2m2026-01-04T01:35:24.882697Z←[0m ←[34mDEBUG←[0m Moving ZWO EFW to position 7
←[2m2026-01-04T01:35:24.882720Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:24.883879Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:24.884956Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:24.885854Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:24.887258Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:25.084229Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:35:25.084638Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:25.093512Z←[0m ←[32m INFO←[0m Capturing frame 1/1 (2.0s)
←[2m2026-01-04T01:35:25.093536Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[SequenceProvider] Received event: type=FilterChanging, category=EventCategory.equipment
←[2m2026-01-04T01:35:25.094259Z←[0m ←[32m INFO←[0m Starting 2.0s exposure on camera native:zwo:1
←[2m2026-01-04T01:35:25.095030Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:25.098066Z←[0m ←[32m INFO←[0m DeviceManager: camera_start_exposure for native:zwo:1 duration=2
←[2m2026-01-04T01:35:25.103118Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:25.106580Z←[0m ←[32m INFO←[0m DeviceManager: Starting Native SDK exposure
←[2m2026-01-04T01:35:25.110220Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:25.116103Z←[0m ←[32m INFO←[0m Started 2s exposure
←[2m2026-01-04T01:35:25.120548Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer←[2m2026-01-04T01:35:25.139186Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)

←[2m2026-01-04T01:35:25.139276Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:25.147100Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:25.155676Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[SequenceProvider] Received event: type=FilterChanged, category=EventCategory.equipment←[2m2026-01-04T01:35:25.159967Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)

[SequenceProvider] Received event: type=ExposureStarted, category=EventCategory.imaging
←[2m2026-01-04T01:35:25.167715Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:25.229582Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:25.241065Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:25.294721Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:25.337885Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:25.342677Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:25.444350Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:25.509146Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:25.547096Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:25.648747Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:25.750456Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:25.852239Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:25.953992Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:26.055818Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:26.157360Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:26.260237Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:26.361918Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:26.463738Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:26.508509Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:26.565305Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:26.667986Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:26.768753Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:26.870322Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:26.973195Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:27.074760Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:27.176435Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:27.279242Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:27.380932Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:27.482617Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
←[2m2026-01-04T01:35:27.508587Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:27.584342Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
←[2m2026-01-04T01:35:27.687089Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:27.788853Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:27.890527Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:27.992351Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:28.095149Z←[0m ←[32m INFO←[0m ZWO exposure status: 2 (Success)
←[2m2026-01-04T01:35:28.215350Z←[0m ←[32m INFO←[0m ZWO DIAGNOSTIC: Raw buffer stats - min=16, max=3712, avg=16, non_zero=16389120/16389120, img_type=2
←[2m2026-01-04T01:35:28.215544Z←[0m ←[32m INFO←[0m Downloaded 4656x3520 image (32778240 bytes, img_type=2)
←[2m2026-01-04T01:35:28.219682Z←[0m ←[32m INFO←[0m [EXPOSURE] Download complete: 4656x3520 (16389120 pixels)
←[2m2026-01-04T01:35:28.231012Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Starting image validation...
←[2m2026-01-04T01:35:28.292971Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] Stats: size=16389120, min=16, max=3712, mean=16, saturated=0.0%
←[2m2026-01-04T01:35:28.301404Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] PASSED: Image validated successfully
←[2m2026-01-04T01:35:28.301636Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Validation complete: valid=true
←[2m2026-01-04T01:35:30.081974Z←[0m ←[32m INFO←[0m Stored image in unified storage for UI display
←[2m2026-01-04T01:35:30.086165Z←[0m ←[32m INFO←[0m Exposure complete: 4656x3520 image, Monochrome sensor
←[2m2026-01-04T01:35:30.086387Z←[0m ←[32m INFO←[0m [SEQ] Exposure completed: 4656x3520 image (16389120 pixels)
←[2m2026-01-04T01:35:31.341744Z←[0m ←[33m WARN←[0m Frame 1/1 - no stars detected for HFR calculation
←[2m2026-01-04T01:35:31.342079Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:35:31.345414Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:31.348330Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
←[2m2026-01-04T01:35:31.349955Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
←[2m2026-01-04T01:35:31.356380Z←[0m ←[34mDEBUG←[0m Updated trigger state exposure count: 6
←[2m2026-01-04T01:35:31.356806Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed 1 exposures (2s)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging←[2m2026-01-04T01:35:31.359169Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message

[SequenceProvider] Received event: type=ExposureComplete, category=EventCategory.imaging
←[2m2026-01-04T01:35:31.362184Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed: SII
[SEQ_PROVIDER] ExposureComplete imaging event received - fetching image for preview
[SEQ_PROVIDER] _fetchAndDisplaySequenceImage called, duration=2.0s←[2m2026-01-04T01:35:31.364063Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Completed', rest=' SII'

[SEQ_PROVIDER] Calling bridge.apiGetLastImage()...
←[2m2026-01-04T01:35:31.367297Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' SII'
←[2m2026-01-04T01:35:31.369330Z←[0m ←[32m INFO←[0m API: api_get_last_image called
←[2m2026-01-04T01:35:31.372009Z←[0m ←[32m INFO←[0m Child 'SII' completed with status: Success
←[2m2026-01-04T01:35:31.373708Z←[0m ←[32m INFO←[0m API: Returning stored image 4656x3520, display_data size: 16389120 bytes
←[2m2026-01-04T01:35:31.375747Z←[0m ←[32m INFO←[0m execute_children_sequential completed with result: Success
←[2m2026-01-04T01:35:31.383626Z←[0m ←[32m INFO←[0m === LOOP ITERATION 3 STARTING ===
←[2m2026-01-04T01:35:31.384615Z←[0m ←[32m INFO←[0m Loop has 3 children
←[2m2026-01-04T01:35:31.385607Z←[0m ←[32m INFO←[0m   Child 0: 'H-alpha' (id=b2900721-b649-4109-aca9-eedce853c5b0)
←[2m2026-01-04T01:35:31.388015Z←[0m ←[32m INFO←[0m   Child 1: 'OIII' (id=cea6e7af-61a6-449c-85e0-349ca864c05f)
←[2m2026-01-04T01:35:31.388712Z←[0m ←[32m INFO←[0m   Child 2: 'SII' (id=4ff8fef4-8930-46b1-bbd3-55f99aca08f8)
←[2m2026-01-04T01:35:31.391042Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Loop iteration 3
←[2m2026-01-04T01:35:31.398050Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
[SEQ_PROVIDER] Got image: 4656x3520, displayData size: 16389120
←[2m2026-01-04T01:35:31.399008Z←[0m ←[32m INFO←[0m Resetting 3 children for iteration 3
←[2m2026-01-04T01:35:31.401192Z←[0m ←[32m INFO←[0m Children reset complete
←[2m2026-01-04T01:35:31.404151Z←[0m ←[32m INFO←[0m Starting execute_children_sequential for iteration 3
←[2m2026-01-04T01:35:31.405270Z←[0m ←[34mDEBUG←[0m execute_children_sequential: node 05d83e14-62d5-4d8b-a240-b2a77a8afef0 has 3 children
←[2m2026-01-04T01:35:31.406408Z←[0m ←[32m INFO←[0m About to enter for loop with 3 children
←[2m2026-01-04T01:35:31.412206Z←[0m ←[32m INFO←[0m FOR LOOP ENTERED: iteration 0 of 3
←[2m2026-01-04T01:35:31.413520Z←[0m ←[32m INFO←[0m Executing child 1/3: 'H-alpha' (id=b2900721-b649-4109-aca9-eedce853c5b0)
←[2m2026-01-04T01:35:31.415050Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Step 1/3: H-alpha
←[2m2026-01-04T01:35:31.416289Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Step 1/3', rest=' H-alpha'
←[2m2026-01-04T01:35:31.417261Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' H-alpha'
←[2m2026-01-04T01:35:31.418977Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Executing: H-alpha
←[2m2026-01-04T01:35:31.420659Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Executing', rest=' H-alpha'
←[2m2026-01-04T01:35:31.421500Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' H-alpha'
←[2m2026-01-04T01:35:31.422309Z←[0m ←[32m INFO←[0m Starting 1 Ha x 2.0s exposures
←[2m2026-01-04T01:35:31.423289Z←[0m ←[32m INFO←[0m Changing to filter: Ha
←[2m2026-01-04T01:35:31.428515Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking up device_id='native:zwo_efw:0'
[SEQ_PROVIDER] Setting currentImageProvider with image 4656x3520
←[2m2026-01-04T01:35:31.429674Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Available devices in registry: ["native:zwo:1", "native:zwo_efw:0", "native:zwo_eaf:0", "ascom:ASCOM.PegasusAstroNYX101.Telescope"]
[SEQ_PROVIDER] Providers updated successfully!
←[2m2026-01-04T01:35:31.430951Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Found device with driver_type=Native
←[2m2026-01-04T01:35:31.434072Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking for 'native:zwo_efw:0' in native_filter_wheels: ["native:zwo_efw:0"]
←[2m2026-01-04T01:35:31.435861Z←[0m ←[32m INFO←[0m filter_wheel_get_config: Returning 8 filter names: ["L", "R", "G", "B", "Ha", "OIII", "SII", "Filter 8"]
←[2m2026-01-04T01:35:31.438975Z←[0m ←[34mDEBUG←[0m Moving ZWO EFW to position 5
←[2m2026-01-04T01:35:31.439096Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:31.445265Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:31.446346Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:31.448388Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:31.450563Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:31.453368Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:31.645600Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:35:31.645884Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:31.648525Z←[0m ←[32m INFO←[0m Capturing frame 1/1 (2.0s)
←[2m2026-01-04T01:35:31.648557Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[SequenceProvider] Received event: type=FilterChanging, category=EventCategory.equipment
←[2m2026-01-04T01:35:31.649325Z←[0m ←[32m INFO←[0m Starting 2.0s exposure on camera native:zwo:1
←[2m2026-01-04T01:35:31.650321Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer←[2m2026-01-04T01:35:31.653188Z←[0m ←[32m INFO←[0m DeviceManager: camera_start_exposure for native:zwo:1 duration=2

←[2m2026-01-04T01:35:31.655745Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:31.662421Z←[0m ←[32m INFO←[0m DeviceManager: Starting Native SDK exposure
←[2m2026-01-04T01:35:31.663885Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:31.666038Z←[0m ←[32m INFO←[0m Started 2s exposure
←[2m2026-01-04T01:35:31.667407Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer←[2m2026-01-04T01:35:31.668999Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe

[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:31.671320Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:31.677375Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:31.682797Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:31.690185Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[SequenceProvider] Received event: type=FilterChanged, category=EventCategory.equipment
←[2m2026-01-04T01:35:31.691777Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
←[2m2026-01-04T01:35:31.694098Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
[SequenceProvider] Received event: type=ExposureStarted, category=EventCategory.imaging
[SequenceProvider] Received event: type=Progress, category=EventCategory.sequencer
←[2m2026-01-04T01:35:31.740363Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:31.770796Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:31.803500Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:31.872543Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:31.882631Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:31.974380Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:32.076522Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:32.178290Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:32.281194Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:32.382696Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:32.484456Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:32.508362Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:32.587150Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:32.688959Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:32.790805Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:32.892325Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:32.994253Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:33.095875Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:33.197651Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:33.299263Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:33.400979Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:33.502705Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:33.508735Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:33.604513Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:33.706459Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:33.809099Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:33.910819Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:34.012423Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:34.115178Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:34.216881Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:34.318541Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:34.420271Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:34.508985Z←[0m ←[34mDEBUG←[0m No safety monitor configured, assuming safe
←[2m2026-01-04T01:35:34.521006Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:34.622907Z←[0m ←[32m INFO←[0m ZWO exposure status: 2 (Success)
←[2m2026-01-04T01:35:34.721149Z←[0m ←[32m INFO←[0m ZWO DIAGNOSTIC: Raw buffer stats - min=16, max=3760, avg=17, non_zero=16389120/16389120, img_type=2
←[2m2026-01-04T01:35:34.721460Z←[0m ←[32m INFO←[0m Downloaded 4656x3520 image (32778240 bytes, img_type=2)
←[2m2026-01-04T01:35:34.725177Z←[0m ←[32m INFO←[0m [EXPOSURE] Download complete: 4656x3520 (16389120 pixels)
←[2m2026-01-04T01:35:34.735825Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Starting image validation...
←[2m2026-01-04T01:35:34.782377Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] Stats: size=16389120, min=16, max=3760, mean=17, saturated=0.0%
←[2m2026-01-04T01:35:34.786237Z←[0m ←[34mDEBUG←[0m [IMAGE_VALIDATION] PASSED: Image validated successfully
←[2m2026-01-04T01:35:34.786707Z←[0m ←[34mDEBUG←[0m [EXPOSURE] Validation complete: valid=true
←[2m2026-01-04T01:35:36.479516Z←[0m ←[32m INFO←[0m Stored image in unified storage for UI display
←[2m2026-01-04T01:35:36.483462Z←[0m ←[32m INFO←[0m Exposure complete: 4656x3520 image, Monochrome sensor
←[2m2026-01-04T01:35:36.483696Z←[0m ←[32m INFO←[0m [SEQ] Exposure completed: 4656x3520 image (16389120 pixels)
←[2m2026-01-04T01:35:37.673626Z←[0m ←[33m WARN←[0m Frame 1/1 - no stars detected for HFR calculation
←[2m2026-01-04T01:35:37.673988Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Frame 1/1
←[2m2026-01-04T01:35:37.675537Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
←[2m2026-01-04T01:35:37.676373Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
[SequenceProvider] Received event: type=ExposureProgress, category=EventCategory.imaging
←[2m2026-01-04T01:35:37.677250Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(1)
←[2m2026-01-04T01:35:37.680901Z←[0m ←[34mDEBUG←[0m Updated trigger state exposure count: 7
[SequenceProvider] Received event: type=ExposureComplete, category=EventCategory.imaging
[SEQ_PROVIDER] ExposureComplete imaging event received - fetching image for preview
←[2m2026-01-04T01:35:37.681496Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed 1 exposures (2s)
[SEQ_PROVIDER] _fetchAndDisplaySequenceImage called, duration=2.0s
←[2m2026-01-04T01:35:37.685931Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No ':' found in message
[SEQ_PROVIDER] Calling bridge.apiGetLastImage()...
←[2m2026-01-04T01:35:37.687617Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed: H-alpha
←[2m2026-01-04T01:35:37.691128Z←[0m ←[32m INFO←[0m API: api_get_last_image called
←[2m2026-01-04T01:35:37.692380Z←[0m ←[32m INFO←[0m API: Returning stored image 4656x3520, display_data size: 16389120 bytes
←[2m2026-01-04T01:35:37.691165Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Completed', rest=' H-alpha'
←[2m2026-01-04T01:35:37.694510Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' H-alpha'
←[2m2026-01-04T01:35:37.695611Z←[0m ←[32m INFO←[0m Child 'H-alpha' completed with status: Success
←[2m2026-01-04T01:35:37.697303Z←[0m ←[32m INFO←[0m FOR LOOP ENTERED: iteration 1 of 3
←[2m2026-01-04T01:35:37.698448Z←[0m ←[32m INFO←[0m Executing child 2/3: 'OIII' (id=cea6e7af-61a6-449c-85e0-349ca864c05f)
←[2m2026-01-04T01:35:37.699282Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Step 2/3: OIII
[SEQ_PROVIDER] Got image: 4656x3520, displayData size: 16389120
←[2m2026-01-04T01:35:37.700095Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Step 2/3', rest=' OIII'
←[2m2026-01-04T01:35:37.701470Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' OIII'
←[2m2026-01-04T01:35:37.702204Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Executing: OIII
←[2m2026-01-04T01:35:37.703030Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Executing', rest=' OIII'
←[2m2026-01-04T01:35:37.707372Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' OIII'
←[2m2026-01-04T01:35:37.708926Z←[0m ←[32m INFO←[0m Starting 1 OIII x 2.0s exposures
←[2m2026-01-04T01:35:37.709990Z←[0m ←[32m INFO←[0m Changing to filter: OIII
←[2m2026-01-04T01:35:37.711270Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking up device_id='native:zwo_efw:0'
←[2m2026-01-04T01:35:37.712675Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Available devices in registry: ["native:zwo:1", "native:zwo_efw:0", "native:zwo_eaf:0", "ascom:ASCOM.PegasusAstroNYX101.Telescope"]
[SEQ_PROVIDER] Setting currentImageProvider with image 4656x3520
←[2m2026-01-04T01:35:37.714141Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Found device with driver_type=Native
[SEQ_PROVIDER] Providers updated successfully!
←[2m2026-01-04T01:35:37.715822Z←[0m ←[34mDEBUG←[0m filter_wheel_get_config: Looking for 'native:zwo_efw:0' in native_filter_wheels: ["native:zwo_efw:0"]
←[2m2026-01-04T01:35:37.720366Z←[0m ←[32m INFO←[0m filter_wheel_get_config: Returning 8 filter names: ["L", "R", "G", "B", "Ha", "OIII", "SII", "Filter 8"]
←[2m2026-01-04T01:35:37.725841Z←[0m ←[34mDEBUG←[0m Moving ZWO EFW to position 6
←[2m2026-01-04T01:35:37.725859Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:37.729275Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:37.731150Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:37.733374Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:37.734790Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
SessionService: Ending session 45 with status: stopped
←[2m2026-01-04T01:35:37.758850Z←[0m ←[32m INFO←[0m Stopping sequence execution
SessionService: Performing checkpoint for session 45...
SessionService: Checkpoint saved successfully
SessionService: Session finalized
  Completed: 0
  Failed: 0
  Integration: 0.0s
  Success rate: 100.0%
←[2m2026-01-04T01:35:37.861350Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(0)
←[2m2026-01-04T01:35:37.861558Z←[0m ←[32m INFO←[0m Clearing checkpoint
←[2m2026-01-04T01:35:37.928911Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed: OIII
←[2m2026-01-04T01:35:37.929295Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Completed', rest=' OIII'
←[2m2026-01-04T01:35:37.932683Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' OIII'
←[2m2026-01-04T01:35:37.933356Z←[0m ←[32m INFO←[0m Child 'OIII' completed with status: Cancelled
←[2m2026-01-04T01:35:37.933406Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-04T01:35:37.934449Z←[0m ←[32m INFO←[0m execute_children_sequential completed with result: Cancelled
←[2m2026-01-04T01:35:37.935276Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:37.936085Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed: Narrowband Loop
←[2m2026-01-04T01:35:37.937429Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:37.938422Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Completed', rest=' Narrowband Loop'
←[2m2026-01-04T01:35:37.939542Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:37.940416Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' Narrowband Loop'
←[2m2026-01-04T01:35:37.944389Z←[0m ←[32m INFO←[0m Child 'Narrowband Loop' completed with status: Cancelled
←[2m2026-01-04T01:35:37.945245Z←[0m ←[32m INFO←[0m execute_children_sequential completed with result: Cancelled
←[2m2026-01-04T01:35:37.946056Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Received message: Completed: Narrowband Sequence
←[2m2026-01-04T01:35:37.943448Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:37.946866Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] Parsed instruction='Completed', rest=' Narrowband Sequence'
←[2m2026-01-04T01:35:37.949793Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:37.951360Z←[0m ←[34mDEBUG←[0m [PROGRESS_CB] No '(' found in rest: ' Narrowband Sequence'
←[2m2026-01-04T01:35:37.952091Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:37.953308Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:37.954347Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-04T01:35:37.955128Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:37.955754Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:37.956623Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(1)
←[2m2026-01-04T01:35:37.961361Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
←[2m2026-01-04T01:35:37.963282Z←[0m ←[34mDEBUG←[0m [EVENT_SUB] Received event: Discriminant(0)
←[2m2026-01-04T01:35:37.964753Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(3)
