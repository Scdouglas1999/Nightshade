Attempting to load native library from: C:\Program Files\Nightshade\nightshade_bridge.dll
Successfully loaded native library from: C:\Program Files\Nightshade\nightshade_bridge.dll
[NativeBridge] Initializing RustLib for native device discovery...
[NativeBridge] RustLib will attempt to load the native library automatically
←[2m2026-01-06T01:22:08.646544Z←[0m ←[32m INFO←[0m Nightshade Native Bridge initialized with file logging
←[2m2026-01-06T01:22:08.646893Z←[0m ←[32m INFO←[0m Log directory: C:\Users\scdou\AppData\Roaming\com.example\nightshade_desktop\logs
←[2m2026-01-06T01:22:08.647799Z←[0m ←[34mDEBUG←[0m Created multi-threaded Tokio runtime
←[2m2026-01-06T01:22:08.648054Z←[0m ←[32m INFO←[0m Nightshade Native API initialized
[NativeBridge] Native bridge API initialized with logging to: C:\Users\scdou\AppData\Roaming\com.example\nightshade_desktop\logs
[NativeBridge] Native bridge version: 0.1.0
[NativeBridge] Γ£ô Native bridge ready - will discover native ZWO, ASCOM, and Alpaca devices
Nightshade Native Bridge: Loaded native library
CatalogManager initialized with directory: C:\Users\scdou\AppData\Roaming\com.example\nightshade_desktop\catalogs
[MAIN] Creating web server with device handlers...
[WebServer] Initialized with:
[WebServer]   devicesHandler: REGISTERED
[WebServer]   sequenceStatusHandler: NULL
[WebServer]   API-only mode: true
[MAIN] Starting web server...
Nightshade web server started on port 8080
Access at: http://localhost:8080
[MAIN] Web server started for mobile access on port 8080
[MAIN] Event stream forwarding enabled
[MAIN] Starting UDP broadcast for auto-discovery...
←[2m2026-01-06T01:22:08.967659Z←[0m ←[32m INFO←[0m [API_EVENT_STREAM] Starting event stream function (buffer size: 4096)
[MAIN] Broadcasting on UDP port 45679←[2m2026-01-06T01:22:08.968001Z←[0m ←[32m INFO←[0m [API_EVENT_STREAM] Subscribed to event bus

[mDNS] mDNS advertising skipped - using UDP broadcast instead
[MAIN] mDNS service advertised as _nightshade._tcp←[2m2026-01-06T01:22:08.968675Z←[0m ←[32m INFO←[0m [API_EVENT_STREAM] Sent ready signal to Dart

[LanPushReceiver] Listening on port 45680
[MAIN] LAN push receiver started on port 45680
[UpdatePushDiscovery] Listening for update push discovery on port 45679
[MAIN] Update push discovery responder started
WebRTC signaling server started
←[2m2026-01-06T01:22:08.977779Z←[0m ←[32m INFO←[0m [API_EVENT_STREAM] Starting event stream function (buffer size: 4096)
←[2m2026-01-06T01:22:08.978094Z←[0m ←[32m INFO←[0m [API_EVENT_STREAM] Subscribed to event bus
←[2m2026-01-06T01:22:08.978900Z←[0m ←[32m INFO←[0m [API_EVENT_STREAM] Sent ready signal to Dart
SessionService: Checking for incomplete sessions...
[FFI-BACKEND] setLocation called with lat=40.007714, lon=-75.397448, elev=0.0
[FFI-BACKEND] bridgeLoc: lat=40.007714, lon=-75.397448, elev=0.0
[FFI-BACKEND] Calling apiSetLocation...
[NativeBridge] Setting location via native: lat=40.007714, lon=-75.397448
[RUST-API] api_set_location called with lat=40.007714, lon=-75.397448, elev=0
←[2m2026-01-06T01:22:09.043076Z←[0m ←[32m INFO←[0m [API] api_set_location called with lat=40.007714, lon=-75.397448, elev=0
[RUST-STATE] set_observer_location called
[RUST-STATE] Setting observer location: lat=40.007714, lon=-75.397448, elev=0
←[2m2026-01-06T01:22:09.051400Z←[0m ←[32m INFO←[0m Setting observer location: lat=40.007714, lon=-75.397448, elev=0
[RUST-STATE] Observer location updated in memory (try_write succeeded)
←[2m2026-01-06T01:22:09.067291Z←[0m ←[34mDEBUG←[0m Observer location updated in memory
[RUST-API] api_set_location succeeded
←[2m2026-01-06T01:22:09.071303Z←[0m ←[32m INFO←[0m [API] api_set_location succeeded
[NativeBridge] Location set via native successfully
[FFI-BACKEND] apiSetLocation returned
SessionService: Found 2 incomplete session(s)
Error checking for incomplete sessions: Null check operator used on a null value
[AutoDiscovery] Starting background device discovery...
←[2m2026-01-06T01:22:09.881585Z←[0m ←[32m INFO←[0m Discovering Dome devices
←[2m2026-01-06T01:22:09.881558Z←[0m ←[32m INFO←[0m Discovering Camera devices
←[2m2026-01-06T01:22:09.881567Z←[0m ←[32m INFO←[0m Discovering Guider devices
←[2m2026-01-06T01:22:09.881576Z←[0m ←[32m INFO←[0m Discovering Weather devices
←[2m2026-01-06T01:22:09.881569Z←[0m ←[32m INFO←[0m Discovering Rotator devices
←[2m2026-01-06T01:22:09.881574Z←[0m ←[32m INFO←[0m Discovering Focuser devices
←[2m2026-01-06T01:22:09.881574Z←[0m ←[32m INFO←[0m Discovering Mount devices
←[2m2026-01-06T01:22:09.881626Z←[0m ←[32m INFO←[0m Discovering Filter Wheel devices
←[2m2026-01-06T01:22:09.882162Z←[0m ←[32m INFO←[0m Running full ASCOM/Alpaca discovery (will cache results)...
←[2m2026-01-06T01:22:09.882960Z←[0m ←[32m INFO←[0m Discovering Safety Monitor devices
←[2m2026-01-06T01:22:09.883850Z←[0m ←[32m INFO←[0m Discovering Mount devices
←[2m2026-01-06T01:22:09.884546Z←[0m ←[32m INFO←[0m Discovering Guider devices
←[2m2026-01-06T01:22:09.888249Z←[0m ←[32m INFO←[0m Discovering Weather devices
←[2m2026-01-06T01:22:09.909521Z←[0m ←[32m INFO←[0m Discovering Safety Monitor devices
←[2m2026-01-06T01:22:09.910712Z←[0m ←[32m INFO←[0m Discovering Switch devices
←[2m2026-01-06T01:22:09.894774Z←[0m ←[32m INFO←[0m Discovering Filter Wheel devices
←[2m2026-01-06T01:22:09.895650Z←[0m ←[32m INFO←[0m Scanning ASCOM registry: SOFTWARE\ASCOM\Camera Drivers
←[2m2026-01-06T01:22:09.896500Z←[0m ←[32m INFO←[0m Discovering Switch devices
←[2m2026-01-06T01:22:09.897808Z←[0m ←[32m INFO←[0m Discovering Focuser devices
←[2m2026-01-06T01:22:09.906733Z←[0m ←[32m INFO←[0m Discovering Dome devices
←[2m2026-01-06T01:22:09.892026Z←[0m ←[32m INFO←[0m Discovering Cover Calibrator devices
←[2m2026-01-06T01:22:09.893589Z←[0m ←[32m INFO←[0m Discovering Mount devices
←[2m2026-01-06T01:22:09.911730Z←[0m ←[32m INFO←[0m Discovering Dome devices
←[2m2026-01-06T01:22:09.913216Z←[0m ←[32m INFO←[0m Discovering Guider devices
←[2m2026-01-06T01:22:09.914150Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.ASICamera2.Camera - ASI Camera (1)
←[2m2026-01-06T01:22:09.914818Z←[0m ←[32m INFO←[0m Discovering Cover Calibrator devices
←[2m2026-01-06T01:22:09.919051Z←[0m ←[32m INFO←[0m Discovering Filter Wheel devices
←[2m2026-01-06T01:22:09.921287Z←[0m ←[32m INFO←[0m Discovering Rotator devices
←[2m2026-01-06T01:22:09.922643Z←[0m ←[32m INFO←[0m Discovering Camera devices
←[2m2026-01-06T01:22:09.923606Z←[0m ←[32m INFO←[0m Discovering Focuser devices
←[2m2026-01-06T01:22:09.924744Z←[0m ←[32m INFO←[0m Discovering Rotator devices
←[2m2026-01-06T01:22:09.925859Z←[0m ←[32m INFO←[0m Discovering Weather devices
←[2m2026-01-06T01:22:09.927427Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.ASICamera2_2.Camera - ASI Camera (2)
←[2m2026-01-06T01:22:09.928111Z←[0m ←[32m INFO←[0m Discovering Camera devices
←[2m2026-01-06T01:22:09.929372Z←[0m ←[32m INFO←[0m Discovering Safety Monitor devices
←[2m2026-01-06T01:22:09.930094Z←[0m ←[32m INFO←[0m Discovering Switch devices
←[2m2026-01-06T01:22:09.936525Z←[0m ←[32m INFO←[0m Discovering Cover Calibrator devices
←[2m2026-01-06T01:22:09.937763Z←[0m ←[32m INFO←[0m Discovering Alpaca devices at localhost:11111
←[2m2026-01-06T01:22:09.939004Z←[0m ←[32m INFO←[0m Discovering INDI devices at localhost:7624
←[2m2026-01-06T01:22:09.941773Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.JustAHub.Camera - ASCOM JustAHub Camera
←[2m2026-01-06T01:22:09.948628Z←[0m ←[34mDEBUG←[0m starting new connection: http://localhost:11111/
←[2m2026-01-06T01:22:09.958038Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.OmniSim.Camera - ASCOM OmniSim Camera
←[2m2026-01-06T01:22:09.961766Z←[0m ←[34mDEBUG←[0m resolving host="localhost"
←[2m2026-01-06T01:22:09.961964Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.ScdouglasFujifilm.Camera - Fujifilm Camera (Scdouglas)
←[2m2026-01-06T01:22:09.963967Z←[0m ←[34mDEBUG←[0m connecting to [::1]:11111
←[2m2026-01-06T01:22:09.965159Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.Simulator.Camera - Camera V3 simulator
←[2m2026-01-06T01:22:09.967759Z←[0m ←[32m INFO←[0m Found ASCOM driver: CCDSimulator.Camera - Simulator
←[2m2026-01-06T01:22:09.968611Z←[0m ←[32m INFO←[0m Found 7 ASCOM Camera drivers
←[2m2026-01-06T01:22:09.969912Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM JustAHub Camera (ASCOM.JustAHub.Camera)
←[2m2026-01-06T01:22:09.970963Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM OmniSim Camera (ASCOM.OmniSim.Camera)
←[2m2026-01-06T01:22:09.971997Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: Camera V3 simulator (ASCOM.Simulator.Camera)
←[2m2026-01-06T01:22:09.973270Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: Simulator (CCDSimulator.Camera)
←[2m2026-01-06T01:22:09.974661Z←[0m ←[32m INFO←[0m Scanning ASCOM registry: SOFTWARE\ASCOM\Telescope Drivers
[UpdateManager] Checking for staged updates...←[2m2026-01-06T01:22:09.976542Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.ASIMount.Telescope - ASI Mount

←[2m2026-01-06T01:22:09.982327Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.DeviceHub.Telescope - Device Hub Telescope
←[2m2026-01-06T01:22:09.983163Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.OmniSim.Telescope - ASCOM OmniSim Telescope
←[2m2026-01-06T01:22:09.984188Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.PegasusAstroNYX101.Telescope - PegasusAstro NYX101
[UpdateManager] Showing banner for version: 2.2.0
←[2m2026-01-06T01:22:09.984889Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.PegasusAstroNYX88.Telescope - PegasusAstro NYX88
[UpdateManager] Found staged update: 2.2.0
[UpdateManager] Showing banner for version: 2.2.0←[2m2026-01-06T01:22:09.987204Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.Simulator.Telescope - Telescope Simulator for .NET

←[2m2026-01-06T01:22:09.993162Z←[0m ←[32m INFO←[0m Found ASCOM driver: ScopeSim.Telescope - Simulator
←[2m2026-01-06T01:22:09.998292Z←[0m ←[32m INFO←[0m Found 7 ASCOM Telescope drivers
←[2m2026-01-06T01:22:10.000513Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: Device Hub Telescope (ASCOM.DeviceHub.Telescope)
←[2m2026-01-06T01:22:10.002204Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM OmniSim Telescope (ASCOM.OmniSim.Telescope)
←[2m2026-01-06T01:22:10.004720Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: Telescope Simulator for .NET (ASCOM.Simulator.Telescope)
←[2m2026-01-06T01:22:10.006257Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: Simulator (ScopeSim.Telescope)
←[2m2026-01-06T01:22:10.007957Z←[0m ←[32m INFO←[0m Scanning ASCOM registry: SOFTWARE\ASCOM\Focuser Drivers
←[2m2026-01-06T01:22:10.009232Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.DeviceHub.Focuser - Device Hub Focuser
←[2m2026-01-06T01:22:10.013572Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.EAF.Focuser - ZWO Focuser (1)
←[2m2026-01-06T01:22:10.014298Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.EAF_2.Focuser - ZWO Focuser (2)
←[2m2026-01-06T01:22:10.014923Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.OmniSim.Focuser - ASCOM OmniSim Focuser
←[2m2026-01-06T01:22:10.015685Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.PegasusAstroFocuser 1 - PegasusAstro Focuser 1
←[2m2026-01-06T01:22:10.016215Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.PegasusAstroFocuser 2 - PegasusAstro Focuser 2
←[2m2026-01-06T01:22:10.016882Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.PegasusAstroFocuser 3 - PegasusAstro Focuser 3
←[2m2026-01-06T01:22:10.017598Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.PegasusAstroFocuser 4 - PegasusAstro Focuser 4
←[2m2026-01-06T01:22:10.019151Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.PegasusAstroFocuser 5 - PegasusAstro Focuser 5
←[2m2026-01-06T01:22:10.020910Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.Simulator.Focuser - ASCOM Simulator Focuser Driver
←[2m2026-01-06T01:22:10.022975Z←[0m ←[32m INFO←[0m Found ASCOM driver: FocusSim.Focuser - Simulator
←[2m2026-01-06T01:22:10.027391Z←[0m ←[32m INFO←[0m Found 11 ASCOM Focuser drivers
←[2m2026-01-06T01:22:10.028025Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: Device Hub Focuser (ASCOM.DeviceHub.Focuser)
←[2m2026-01-06T01:22:10.028776Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM OmniSim Focuser (ASCOM.OmniSim.Focuser)
←[2m2026-01-06T01:22:10.029387Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM Simulator Focuser Driver (ASCOM.Simulator.Focuser)
←[2m2026-01-06T01:22:10.029934Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: Simulator (FocusSim.Focuser)
←[2m2026-01-06T01:22:10.030473Z←[0m ←[32m INFO←[0m Scanning ASCOM registry: SOFTWARE\ASCOM\FilterWheel Drivers
←[2m2026-01-06T01:22:10.031064Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.EFW2.FilterWheel - ZWO FilterWheel (1)
←[2m2026-01-06T01:22:10.031655Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.EFW2_2.FilterWheel - ZWO FilterWheel (2)
←[2m2026-01-06T01:22:10.032259Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.JustAHub.FilterWheel - ASCOM JustAHub Filter Wheel
←[2m2026-01-06T01:22:10.032797Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.OmniSim.FilterWheel - ASCOM OmniSim FilterWheel
←[2m2026-01-06T01:22:10.033509Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.PegasusAstroIndigo.FilterWheel - PegasusAstro Indigo
←[2m2026-01-06T01:22:10.035165Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.Simulator.FilterWheel - Filter Wheel Simulator [.Net]
←[2m2026-01-06T01:22:10.036659Z←[0m ←[32m INFO←[0m Found ASCOM driver: FilterWheelSim.FilterWheel - Simulator
←[2m2026-01-06T01:22:10.037922Z←[0m ←[32m INFO←[0m Found 7 ASCOM FilterWheel drivers
←[2m2026-01-06T01:22:10.039360Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM JustAHub Filter Wheel (ASCOM.JustAHub.FilterWheel)
←[2m2026-01-06T01:22:10.045046Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM OmniSim FilterWheel (ASCOM.OmniSim.FilterWheel)
←[2m2026-01-06T01:22:10.045818Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: Filter Wheel Simulator [.Net] (ASCOM.Simulator.FilterWheel)
←[2m2026-01-06T01:22:10.046412Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: Simulator (FilterWheelSim.FilterWheel)
←[2m2026-01-06T01:22:10.046957Z←[0m ←[32m INFO←[0m Scanning ASCOM registry: SOFTWARE\ASCOM\Rotator Drivers
←[2m2026-01-06T01:22:10.047562Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.ASICAA.Rotator - ZWO CAA
←[2m2026-01-06T01:22:10.048086Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.OmniSim.Rotator - ASCOM OmniSim Rotator
←[2m2026-01-06T01:22:10.048889Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.PegasusAstro.Rotator 1 - PegasusAstro Rotator 1
←[2m2026-01-06T01:22:10.049717Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.PegasusAstro.Rotator 2 - PegasusAstro Rotator 2
←[2m2026-01-06T01:22:10.049985Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.Simulator.Rotator - Rotator Simulator .NET
←[2m2026-01-06T01:22:10.051197Z←[0m ←[32m INFO←[0m Found 5 ASCOM Rotator drivers
←[2m2026-01-06T01:22:10.053965Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM OmniSim Rotator (ASCOM.OmniSim.Rotator)
←[2m2026-01-06T01:22:10.055090Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: Rotator Simulator .NET (ASCOM.Simulator.Rotator)
←[2m2026-01-06T01:22:10.060382Z←[0m ←[32m INFO←[0m Scanning ASCOM registry: SOFTWARE\ASCOM\Dome Drivers
←[2m2026-01-06T01:22:10.061333Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.DeviceHub.Dome - Device Hub Dome
←[2m2026-01-06T01:22:10.062091Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.OmniSim.Dome - ASCOM OmniSim Dome
←[2m2026-01-06T01:22:10.063125Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.Simulator.Dome - Dome Simulator .NET
←[2m2026-01-06T01:22:10.063824Z←[0m ←[32m INFO←[0m Found ASCOM driver: DomeSim.Dome - Simulator
←[2m2026-01-06T01:22:10.064429Z←[0m ←[32m INFO←[0m Found 4 ASCOM Dome drivers
←[2m2026-01-06T01:22:10.065031Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: Device Hub Dome (ASCOM.DeviceHub.Dome)
←[2m2026-01-06T01:22:10.065632Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM OmniSim Dome (ASCOM.OmniSim.Dome)
←[2m2026-01-06T01:22:10.066328Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: Dome Simulator .NET (ASCOM.Simulator.Dome)
←[2m2026-01-06T01:22:10.067611Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: Simulator (DomeSim.Dome)
←[2m2026-01-06T01:22:10.068288Z←[0m ←[32m INFO←[0m Scanning ASCOM registry: SOFTWARE\ASCOM\ObservingConditions Drivers
←[2m2026-01-06T01:22:10.069044Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.Device1.ObservingConditions - PegasusAstro ObservingConditions 1
←[2m2026-01-06T01:22:10.070459Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.Device2.ObservingConditions - PegasusAstro ObservingConditions 2
←[2m2026-01-06T01:22:10.076449Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.OCH.ObservingConditions - ASCOM Observing Conditions Hub (OCH)
←[2m2026-01-06T01:22:10.077964Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.OmniSim.ObservingConditions - ASCOM OmniSim ObservingConditions
←[2m2026-01-06T01:22:10.078929Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.OpenWeatherMap.ObservingConditions - OpenWeatherMap ObservingConditions
←[2m2026-01-06T01:22:10.080579Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.Simulator.ObservingConditions - ASCOM Observing Conditions Simulator
←[2m2026-01-06T01:22:10.082209Z←[0m ←[32m INFO←[0m Found 6 ASCOM ObservingConditions drivers
←[2m2026-01-06T01:22:10.083375Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM OmniSim ObservingConditions (ASCOM.OmniSim.ObservingConditions)
←[2m2026-01-06T01:22:10.084278Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM Observing Conditions Simulator (ASCOM.Simulator.ObservingConditions)
←[2m2026-01-06T01:22:10.085016Z←[0m ←[32m INFO←[0m Scanning ASCOM registry: SOFTWARE\ASCOM\SafetyMonitor Drivers
←[2m2026-01-06T01:22:10.085881Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.OmniSim.SafetyMonitor - ASCOM OmniSim SafetyMonitor
←[2m2026-01-06T01:22:10.086674Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.Simulator.SafetyMonitor - ASCOM Simulator SafetyMonitor Driver
←[2m2026-01-06T01:22:10.093639Z←[0m ←[32m INFO←[0m Found 2 ASCOM SafetyMonitor drivers
←[2m2026-01-06T01:22:10.120247Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM OmniSim SafetyMonitor (ASCOM.OmniSim.SafetyMonitor)
←[2m2026-01-06T01:22:10.122451Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM Simulator SafetyMonitor Driver (ASCOM.Simulator.SafetyMonitor)
←[2m2026-01-06T01:22:10.123143Z←[0m ←[32m INFO←[0m Scanning ASCOM registry: SOFTWARE\ASCOM\CoverCalibrator Drivers
←[2m2026-01-06T01:22:10.124707Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.OmniSim.CoverCalibrator - ASCOM OmniSim CoverCalibrator
←[2m2026-01-06T01:22:10.125874Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.PegasusAstroCoverCalibrator 1 - PegasusAstro FlatMaster 1
←[2m2026-01-06T01:22:10.127326Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.PegasusAstroCoverCalibrator 2 - PegasusAstro FlatMaster 2
←[2m2026-01-06T01:22:10.128517Z←[0m ←[32m INFO←[0m Found ASCOM driver: ASCOM.Simulator.CoverCalibrator - ASCOM CoverCalibrator Simulator
←[2m2026-01-06T01:22:10.130055Z←[0m ←[32m INFO←[0m Found 4 ASCOM CoverCalibrator drivers
←[2m2026-01-06T01:22:10.130852Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM OmniSim CoverCalibrator (ASCOM.OmniSim.CoverCalibrator)
←[2m2026-01-06T01:22:10.131556Z←[0m ←[34mDEBUG←[0m Filtering out ASCOM device: ASCOM CoverCalibrator Simulator (ASCOM.Simulator.CoverCalibrator)
←[2m2026-01-06T01:22:10.132199Z←[0m ←[32m INFO←[0m ASCOM discovery complete: found 25 drivers
←[2m2026-01-06T01:22:10.138840Z←[0m ←[34mDEBUG←[0m Sent discovery broadcast 1/3
←[2m2026-01-06T01:22:10.266118Z←[0m ←[34mDEBUG←[0m connecting to 127.0.0.1:11111
←[2m2026-01-06T01:22:10.340926Z←[0m ←[34mDEBUG←[0m Sent discovery broadcast 2/3
←[2m2026-01-06T01:22:10.542477Z←[0m ←[34mDEBUG←[0m Sent discovery broadcast 3/3
←[2m2026-01-06T01:22:10.543286Z←[0m ←[32m INFO←[0m Discovered Alpaca server at 192.168.1.58:80
←[2m2026-01-06T01:22:11.840997Z←[0m ←[32m INFO←[0m Discovering Camera devices
[UpdateManager] Error: UpdateException: Update server URL not configured
←[2m2026-01-06T01:22:12.545203Z←[0m ←[34mDEBUG←[0m starting new connection: http://192.168.1.58/
←[2m2026-01-06T01:22:12.545451Z←[0m ←[34mDEBUG←[0m connecting to 192.168.1.58:80
←[2m2026-01-06T01:22:12.573924Z←[0m ←[34mDEBUG←[0m connected to 192.168.1.58:80
←[2m2026-01-06T01:22:12.575818Z←[0m ←[34mDEBUG←[0m flushed 82 bytes
←[2m2026-01-06T01:22:12.597048Z←[0m ←[34mDEBUG←[0m parsed 3 headers
←[2m2026-01-06T01:22:12.597485Z←[0m ←[34mDEBUG←[0m incoming body is content-length (224 bytes)
←[2m2026-01-06T01:22:12.603004Z←[0m ←[34mDEBUG←[0m incoming body completed
←[2m2026-01-06T01:22:12.608217Z←[0m ←[33m WARN←[0m Failed to get devices from 192.168.1.58:80: error decoding response body: missing field `UniqueId` at line 1 column 125
←[2m2026-01-06T01:22:12.613044Z←[0m ←[32m INFO←[0m Alpaca discovery complete: found 0 devices
←[2m2026-01-06T01:22:12.615535Z←[0m ←[32m INFO←[0m Starting native device discovery sequence...
←[2m2026-01-06T01:22:12.617554Z←[0m ←[32m INFO←[0m Discovering ZWO cameras...
←[2m2026-01-06T01:22:12.621557Z←[0m ←[34mDEBUG←[0m Trying to load ASI SDK from: ASICamera2.dll
←[2m2026-01-06T01:22:12.633516Z←[0m ←[32m INFO←[0m Found ASI SDK at: ASICamera2.dll
←[2m2026-01-06T01:22:12.635753Z←[0m ←[32m INFO←[0m Successfully loaded all ASI SDK functions from: ASICamera2.dll
←[2m2026-01-06T01:22:12.638166Z←[0m ←[32m INFO←[0m Discovering ZWO cameras via native ASI SDK...
←[2m2026-01-06T01:22:12.656136Z←[0m ←[32m INFO←[0m ASI SDK reports 2 connected camera(s)
←[2m2026-01-06T01:22:12.664898Z←[0m ←[32m INFO←[0m Found ZWO camera: ZWO ASI178MM (ID: 0)
←[2m2026-01-06T01:22:12.684850Z←[0m ←[32m INFO←[0m Found ZWO camera: ZWO ASI1600MM-Cool (ID: 1)
←[2m2026-01-06T01:22:12.685301Z←[0m ←[32m INFO←[0m Found 2 ZWO cameras
←[2m2026-01-06T01:22:12.693291Z←[0m ←[32m INFO←[0m ZWO camera discovery complete.
←[2m2026-01-06T01:22:12.703434Z←[0m ←[32m INFO←[0m Discovering QHY cameras...
←[2m2026-01-06T01:22:12.716626Z←[0m ←[32m INFO←[0m Loaded QHY SDK from: qhyccd.dll
←[2m2026-01-06T01:22:13.721339Z←[0m ←[32m INFO←[0m QHY SDK initialized successfully
←[2m2026-01-06T01:22:13.722196Z←[0m ←[32m INFO←[0m Found 0 QHY cameras
←[2m2026-01-06T01:22:13.725470Z←[0m ←[34mDEBUG←[0m QHY discovery completed successfully, found 0 cameras
←[2m2026-01-06T01:22:13.726678Z←[0m ←[32m INFO←[0m Found 0 QHY cameras
←[2m2026-01-06T01:22:13.727622Z←[0m ←[32m INFO←[0m QHY camera discovery complete.
←[2m2026-01-06T01:22:13.729071Z←[0m ←[32m INFO←[0m Discovering Player One cameras...
←[2m2026-01-06T01:22:13.735784Z←[0m ←[32m INFO←[0m Loaded Player One SDK from: PlayerOneCamera.dll
←[2m2026-01-06T01:22:13.737159Z←[0m ←[32m INFO←[0m Found 0 Player One cameras
←[2m2026-01-06T01:22:13.738361Z←[0m ←[32m INFO←[0m Player One camera discovery complete.
←[2m2026-01-06T01:22:13.739589Z←[0m ←[32m INFO←[0m Discovering ZWO EAF focusers...
←[2m2026-01-06T01:22:13.743595Z←[0m ←[32m INFO←[0m Discovering ZWO EAF focusers via native SDK...
←[2m2026-01-06T01:22:13.779396Z←[0m ←[32m INFO←[0m EAF SDK reports 1 connected focuser(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Discovering Alpaca devices (UDP broadcast)...
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 2 native Cover Calibrator(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 2 native Cover Calibrator(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 4 native Weather(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 2 native Cover Calibrator(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 4 native Weather(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[ASCOM] Not on Windows, skipping ASCOM discovery
←[2m2026-01-06T01:22:14.100519Z←[0m ←[32m INFO←[0m Found PHD2 Guiding (Running: true, Installed: true)
Alpaca discovery already in progress, waiting...
←[2m2026-01-06T01:22:14.101036Z←[0m ←[32m INFO←[0m Found PHD2 Guiding (Running: true, Installed: true)
[NativeBridge] Found 4 native Weather(s)
[ASCOM] Not on Windows, skipping ASCOM discovery←[2m2026-01-06T01:22:14.102426Z←[0m ←[32m INFO←[0m Found PHD2 Guiding (Running: true, Installed: true)

Alpaca discovery already in progress, waiting...
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
Discovered Alpaca server at 192.168.1.58:80
[NativeBridge] Found 1 native Guider(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 1 native Guider(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 1 native Guider(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
←[2m2026-01-06T01:22:14.925426Z←[0m ←[32m INFO←[0m Found ZWO EAF: EAF (ID: 0, SN: Some("0F229270323C0A91"))
←[2m2026-01-06T01:22:14.925833Z←[0m ←[32m INFO←[0m Found 1 ZWO EAF focusers
←[2m2026-01-06T01:22:14.928426Z←[0m ←[32m INFO←[0m ZWO EAF discovery complete.
←[2m2026-01-06T01:22:14.930296Z←[0m ←[32m INFO←[0m Discovering ZWO EFW filter wheels...
←[2m2026-01-06T01:22:14.933078Z←[0m ←[32m INFO←[0m Discovering ZWO EFW filter wheels via native SDK...
←[2m2026-01-06T01:22:14.966008Z←[0m ←[32m INFO←[0m EFW SDK reports 1 connected filter wheel(s)
←[2m2026-01-06T01:22:15.189516Z←[0m ←[32m INFO←[0m Found ZWO EFW: EFW (ID: 0, 8 slots, SN: None)
←[2m2026-01-06T01:22:15.189918Z←[0m ←[32m INFO←[0m Found 1 ZWO EFW filter wheels
←[2m2026-01-06T01:22:15.192152Z←[0m ←[32m INFO←[0m ZWO EFW discovery complete.
←[2m2026-01-06T01:22:15.192978Z←[0m ←[32m INFO←[0m Discovering QHY filter wheels...
←[2m2026-01-06T01:22:15.193957Z←[0m ←[32m INFO←[0m Found 0 QHY filter wheels
←[2m2026-01-06T01:22:15.194641Z←[0m ←[32m INFO←[0m QHY CFW discovery complete.
←[2m2026-01-06T01:22:15.195745Z←[0m ←[32m INFO←[0m Discovering SVBony cameras...
←[2m2026-01-06T01:22:15.205238Z←[0m ←[32m INFO←[0m Found 0 SVBony cameras
←[2m2026-01-06T01:22:15.205712Z←[0m ←[32m INFO←[0m SVBony camera discovery complete.
←[2m2026-01-06T01:22:15.207632Z←[0m ←[32m INFO←[0m Discovering Atik cameras...
←[2m2026-01-06T01:22:15.249506Z←[0m ←[32m INFO←[0m Found 0 Atik cameras
←[2m2026-01-06T01:22:15.250569Z←[0m ←[32m INFO←[0m Atik camera discovery complete.
←[2m2026-01-06T01:22:15.254889Z←[0m ←[32m INFO←[0m Discovering FLI cameras...
←[2m2026-01-06T01:22:15.259288Z←[0m ←[32m INFO←[0m Found 0 FLI cameras
←[2m2026-01-06T01:22:15.261157Z←[0m ←[32m INFO←[0m FLI camera discovery complete.
←[2m2026-01-06T01:22:15.265249Z←[0m ←[32m INFO←[0m Discovering FLI focusers...
←[2m2026-01-06T01:22:15.265882Z←[0m ←[32m INFO←[0m Found 0 FLI focusers
←[2m2026-01-06T01:22:15.266545Z←[0m ←[32m INFO←[0m FLI focuser discovery complete.
←[2m2026-01-06T01:22:15.267312Z←[0m ←[32m INFO←[0m Discovering FLI filter wheels...
←[2m2026-01-06T01:22:15.268286Z←[0m ←[32m INFO←[0m Found 0 FLI filter wheels
←[2m2026-01-06T01:22:15.270735Z←[0m ←[32m INFO←[0m FLI filter wheel discovery complete.
←[2m2026-01-06T01:22:15.273112Z←[0m ←[32m INFO←[0m Discovering Touptek/OGMA cameras...
←[2m2026-01-06T01:22:15.301290Z←[0m ←[32m INFO←[0m Found 0 Touptek cameras
←[2m2026-01-06T01:22:15.301651Z←[0m ←[32m INFO←[0m Touptek discovery complete.
←[2m2026-01-06T01:22:15.304573Z←[0m ←[32m INFO←[0m Discovering Moravian cameras...
←[2m2026-01-06T01:22:15.318764Z←[0m ←[32m INFO←[0m Found 0 Moravian cameras
←[2m2026-01-06T01:22:15.321761Z←[0m ←[32m INFO←[0m Moravian discovery complete.
←[2m2026-01-06T01:22:15.327028Z←[0m ←[32m INFO←[0m Discovering Sky-Watcher mounts...
←[2m2026-01-06T01:22:15.352660Z←[0m ←[32m INFO←[0m Sky-Watcher discovery: found 2 serial ports to scan
←[2m2026-01-06T01:22:15.352918Z←[0m ←[34mDEBUG←[0m Trying COM4 at 115200 baud for Sky-Watcher
←[2m2026-01-06T01:22:15.361779Z←[0m ←[34mDEBUG←[0m Trying COM3 at 115200 baud for Sky-Watcher
←[2m2026-01-06T01:22:15.369839Z←[0m ←[32m INFO←[0m Sky-Watcher discovery complete: found 0 mounts
←[2m2026-01-06T01:22:15.373867Z←[0m ←[32m INFO←[0m Found 0 Sky-Watcher mounts
←[2m2026-01-06T01:22:15.380340Z←[0m ←[32m INFO←[0m Sky-Watcher discovery complete.
←[2m2026-01-06T01:22:15.586531Z←[0m ←[32m INFO←[0m Discovering iOptron mounts...
←[2m2026-01-06T01:22:15.596162Z←[0m ←[32m INFO←[0m iOptron discovery: found 2 serial ports to scan
←[2m2026-01-06T01:22:15.596343Z←[0m ←[34mDEBUG←[0m Trying COM4 at 9600 baud for iOptron
←[2m2026-01-06T01:22:15.597183Z←[0m ←[34mDEBUG←[0m Trying COM4 at 115200 baud for iOptron
←[2m2026-01-06T01:22:15.597976Z←[0m ←[34mDEBUG←[0m Trying COM3 at 9600 baud for iOptron
←[2m2026-01-06T01:22:15.598566Z←[0m ←[34mDEBUG←[0m Trying COM3 at 115200 baud for iOptron
←[2m2026-01-06T01:22:15.599179Z←[0m ←[32m INFO←[0m iOptron discovery complete: found 0 mounts
←[2m2026-01-06T01:22:15.599629Z←[0m ←[32m INFO←[0m Found 0 iOptron mounts
←[2m2026-01-06T01:22:15.600309Z←[0m ←[32m INFO←[0m iOptron discovery complete.
←[2m2026-01-06T01:22:15.801144Z←[0m ←[32m INFO←[0m Discovering LX200 mounts...
←[2m2026-01-06T01:22:15.814205Z←[0m ←[32m INFO←[0m LX200 discovery: found 2 serial ports to scan
←[2m2026-01-06T01:22:15.814760Z←[0m ←[34mDEBUG←[0m Checking port COM4 (USB (VID:0403 PID:6015 USB Serial Port (COM4)))
←[2m2026-01-06T01:22:15.815800Z←[0m ←[34mDEBUG←[0m Trying COM4 at 115200 baud
←[2m2026-01-06T01:22:15.817773Z←[0m ←[34mDEBUG←[0m Port COM4 is locked by another application (possibly ASCOM driver) - skipping LX200 scan
←[2m2026-01-06T01:22:15.819175Z←[0m ←[34mDEBUG←[0m Checking port COM3 (USB (VID:303A PID:1001 USB Serial Device (COM3)))
←[2m2026-01-06T01:22:15.820316Z←[0m ←[34mDEBUG←[0m Trying COM3 at 115200 baud
←[2m2026-01-06T01:22:15.821942Z←[0m ←[34mDEBUG←[0m Port COM3 is locked by another application (possibly ASCOM driver) - skipping LX200 scan
←[2m2026-01-06T01:22:15.823357Z←[0m ←[32m INFO←[0m LX200 discovery complete: found 0 mounts
←[2m2026-01-06T01:22:15.824782Z←[0m ←[32m INFO←[0m Found 0 LX200 mounts
←[2m2026-01-06T01:22:15.832628Z←[0m ←[32m INFO←[0m LX200 discovery complete.
←[2m2026-01-06T01:22:15.833788Z←[0m ←[32m INFO←[0m Native device discovery finished. Found 4 total devices.
←[2m2026-01-06T01:22:15.835012Z←[0m ←[32m INFO←[0m Found native device: ZWO ASI178MM #1 (ZWO)
←[2m2026-01-06T01:22:15.836404Z←[0m ←[32m INFO←[0m Found native device: ZWO ASI1600MM-Cool #2 (ZWO)
[NativeBridge] Found 6 native Camera(s)←[2m2026-01-06T01:22:15.838470Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.0s old)

[ASCOM] Not on Windows, skipping ASCOM discovery
←[2m2026-01-06T01:22:15.840020Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.0s old)
Alpaca discovery already in progress, waiting...
←[2m2026-01-06T01:22:15.848815Z←[0m ←[32m INFO←[0m Found native device: EAF (0F229270323C0A91) (ZWO)
←[2m2026-01-06T01:22:15.851613Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.0s old)
[NativeBridge] Found 3 native Rotator(s)
←[2m2026-01-06T01:22:15.852943Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.0s old)
[ASCOM] Not on Windows, skipping ASCOM discovery
←[2m2026-01-06T01:22:15.854336Z←[0m ←[32m INFO←[0m Found native device: EFW #1 (ZWO)
Alpaca discovery already in progress, waiting...
←[2m2026-01-06T01:22:15.859254Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.0s old)
[NativeBridge] Found 8 native Focuser(s)
[ASCOM] Not on Windows, skipping ASCOM discovery←[2m2026-01-06T01:22:15.865076Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.0s old)

Alpaca discovery already in progress, waiting...
←[2m2026-01-06T01:22:15.866314Z←[0m ←[32m INFO←[0m Found native device: EFW #1 (ZWO)
[NativeBridge] Found 3 native Mount(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
←[2m2026-01-06T01:22:15.867791Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.0s old)
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 4 native Filter Wheel(s)←[2m2026-01-06T01:22:15.869060Z←[0m ←[32m INFO←[0m Found native device: EAF (0F229270323C0A91) (ZWO)

[ASCOM] Not on Windows, skipping ASCOM discovery
←[2m2026-01-06T01:22:15.869079Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.0s old)
Alpaca discovery already in progress, waiting...
←[2m2026-01-06T01:22:15.872680Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.0s old)
[NativeBridge] Found 3 native Mount(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
←[2m2026-01-06T01:22:15.880554Z←[0m ←[32m INFO←[0m Found native device: EFW #1 (ZWO)
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 4 native Filter Wheel(s)
[ASCOM] Not on Windows, skipping ASCOM discovery←[2m2026-01-06T01:22:15.883194Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.0s old)

Alpaca discovery already in progress, waiting...←[2m2026-01-06T01:22:15.885832Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.1s old)

[NativeBridge] Found 8 native Focuser(s)
←[2m2026-01-06T01:22:15.888214Z←[0m ←[32m INFO←[0m Found native device: ZWO ASI178MM #1 (ZWO)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
←[2m2026-01-06T01:22:15.888238Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.1s old)
[NativeBridge] Found 3 native Mount(s)
[ASCOM] Not on Windows, skipping ASCOM discovery←[2m2026-01-06T01:22:15.894997Z←[0m ←[32m INFO←[0m Found native device: EAF (0F229270323C0A91) (ZWO)

Alpaca discovery already in progress, waiting...
←[2m2026-01-06T01:22:15.893238Z←[0m ←[32m INFO←[0m Found native device: ZWO ASI1600MM-Cool #2 (ZWO)
[NativeBridge] Found 4 native Filter Wheel(s)
←[2m2026-01-06T01:22:15.896221Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.1s old)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...←[2m2026-01-06T01:22:15.898148Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.1s old)

←[2m2026-01-06T01:22:15.899288Z←[0m ←[32m INFO←[0m Found native device: ZWO ASI178MM #1 (ZWO)
←[2m2026-01-06T01:22:15.899968Z←[0m ←[32m INFO←[0m Found native device: ZWO ASI1600MM-Cool #2 (ZWO)
[NativeBridge] Found 3 native Rotator(s)
←[2m2026-01-06T01:22:15.900736Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.1s old)
[ASCOM] Not on Windows, skipping ASCOM discovery
←[2m2026-01-06T01:22:15.902804Z←[0m ←[32m INFO←[0m Found native device: ZWO ASI178MM #1 (ZWO)
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 8 native Focuser(s)←[2m2026-01-06T01:22:15.907431Z←[0m ←[32m INFO←[0m Found native device: ZWO ASI1600MM-Cool #2 (ZWO)

[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 6 native Camera(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 3 native Rotator(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 6 native Camera(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
[NativeBridge] Found 6 native Camera(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Alpaca discovery already in progress, waiting...
Discovering PHD2 instances...
Discovering PHD2 instances...
Discovering PHD2 instances...
Found Alpaca Mount: NYX101
Found Alpaca Mount: NYX101
Found Alpaca Mount: NYX101
[NativeBridge] Attempting native connection for native:zwo:1...
←[2m2026-01-06T01:22:16.126280Z←[0m ←[32m INFO←[0m Connecting to Camera device: native:zwo:1
←[2m2026-01-06T01:22:16.131190Z←[0m ←[32m INFO←[0m Connecting to Camera device: native:zwo:1
←[2m2026-01-06T01:22:16.132290Z←[0m ←[32m INFO←[0m Device native:zwo:1 not registered, discovering and registering...
←[2m2026-01-06T01:22:16.133394Z←[0m ←[32m INFO←[0m Discovering Camera devices
←[2m2026-01-06T01:22:16.134548Z←[0m ←[34mDEBUG←[0m Using cached ASCOM/Alpaca discovery (25 ASCOM, 0 Alpaca devices, 3.5s old)
←[2m2026-01-06T01:22:16.136045Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 0.3s old)
←[2m2026-01-06T01:22:16.137582Z←[0m ←[32m INFO←[0m Found native device: ZWO ASI178MM #1 (ZWO)
←[2m2026-01-06T01:22:16.139052Z←[0m ←[32m INFO←[0m Found native device: ZWO ASI1600MM-Cool #2 (ZWO)
←[2m2026-01-06T01:22:16.140206Z←[0m ←[32m INFO←[0m Registered device: ZWO ASI1600MM-Cool (native:zwo:1)
Scanning local network for PHD2 instances...
←[2m2026-01-06T01:22:16.141174Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
Scanning local network for PHD2 instances...
←[2m2026-01-06T01:22:16.141216Z←[0m ←[32m INFO←[0m Connecting to ZWO camera ID 1...
Scanning local network for PHD2 instances...
←[2m2026-01-06T01:22:16.148058Z←[0m ←[34mDEBUG←[0m Loading camera info for ID 1
Scanning subnet: 192.168.1
←[2m2026-01-06T01:22:16.164766Z←[0m ←[34mDEBUG←[0m Camera info loaded successfully
←[2m2026-01-06T01:22:16.165481Z←[0m ←[34mDEBUG←[0m Opening camera ID 1
←[2m2026-01-06T01:22:16.179620Z←[0m ←[34mDEBUG←[0m Camera opened successfully
Scanning subnet: 192.168.1
←[2m2026-01-06T01:22:16.180067Z←[0m ←[34mDEBUG←[0m Initializing camera ID 1
Scanning subnet: 192.168.1
←[2m2026-01-06T01:22:16.863931Z←[0m ←[34mDEBUG←[0m Camera initialized successfully
←[2m2026-01-06T01:22:16.864359Z←[0m ←[34mDEBUG←[0m Setting ROI format: 4656x3520, bin 1, Raw16
←[2m2026-01-06T01:22:16.940330Z←[0m ←[34mDEBUG←[0m ROI format set successfully
←[2m2026-01-06T01:22:16.940971Z←[0m ←[34mDEBUG←[0m Reading current gain and offset
←[2m2026-01-06T01:22:16.943470Z←[0m ←[34mDEBUG←[0m Current gain: 139
←[2m2026-01-06T01:22:16.944407Z←[0m ←[34mDEBUG←[0m Current offset: 21
←[2m2026-01-06T01:22:16.946311Z←[0m ←[32m INFO←[0m Successfully connected to ZWO camera: ZWO ASI1600MM-Cool
←[2m2026-01-06T01:22:16.949933Z←[0m ←[32m INFO←[0m Connected to native camera: ZWO ASI1600MM-Cool
←[2m2026-01-06T01:22:16.955921Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:16.955964Z←[0m ←[32m INFO←[0m Starting heartbeat for device native:zwo:1 (type: Camera, driver: Native): interval=10s, threshold=3, auto_reconnect=false
←[2m2026-01-06T01:22:16.956873Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:16.958349Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:16.958380Z←[0m ←[32m INFO←[0m Auto-started heartbeat for device native:zwo:1
[NativeBridge] Γ£ô Successfully connected to native:zwo:1 via native bridge
←[2m2026-01-06T01:22:16.960041Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:16.961723Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[MISMATCH CHECK] Profile: "native:zwo:1" vs Connected: "native:zwo:1"
←[2m2026-01-06T01:22:16.964722Z←[0m ←[32m INFO←[0m Starting heartbeat monitoring for Camera device: native:zwo:1 (interval: 10000ms)
[MISMATCH CHECK] Direct match - no mismatch
←[2m2026-01-06T01:22:16.980821Z←[0m ←[34mDEBUG←[0m Heartbeat task stopped cleanly for native:zwo:1
←[2m2026-01-06T01:22:16.983582Z←[0m ←[32m INFO←[0m Starting heartbeat for device native:zwo:1 (type: Camera, driver: Native): interval=10s, threshold=3, auto_reconnect=false
←[2m2026-01-06T01:22:16.983645Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:16.984627Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:16.985926Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:16.987193Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:16.999993Z←[0m ←[32m INFO←[0m Discovering Mount devices
←[2m2026-01-06T01:22:17.000270Z←[0m ←[34mDEBUG←[0m Using cached ASCOM/Alpaca discovery (25 ASCOM, 0 Alpaca devices, 4.4s old)
←[2m2026-01-06T01:22:17.002997Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 1.2s old)
[NativeBridge] Found 3 native Mount(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
Found Alpaca Mount: NYX101
[NativeBridge] Attempting native connection for ascom:ASCOM.PegasusAstroNYX101.Telescope...
←[2m2026-01-06T01:22:17.010972Z←[0m ←[32m INFO←[0m Connecting to Mount device: ascom:ASCOM.PegasusAstroNYX101.Telescope
←[2m2026-01-06T01:22:17.016262Z←[0m ←[32m INFO←[0m Connecting to Mount device: ascom:ASCOM.PegasusAstroNYX101.Telescope
←[2m2026-01-06T01:22:17.018315Z←[0m ←[32m INFO←[0m Device ascom:ASCOM.PegasusAstroNYX101.Telescope not registered, discovering and registering...
←[2m2026-01-06T01:22:17.019576Z←[0m ←[32m INFO←[0m Discovering Mount devices
←[2m2026-01-06T01:22:17.020428Z←[0m ←[34mDEBUG←[0m Using cached ASCOM/Alpaca discovery (25 ASCOM, 0 Alpaca devices, 4.4s old)
←[2m2026-01-06T01:22:17.021656Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 1.2s old)
←[2m2026-01-06T01:22:17.023304Z←[0m ←[32m INFO←[0m Registered device: PegasusAstro NYX101 (ascom:ASCOM.PegasusAstroNYX101.Telescope)
←[2m2026-01-06T01:22:17.024761Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[MISMATCH CHECK] Profile: "native:zwo:1" vs Connected: "native:zwo:1"←[2m2026-01-06T01:22:17.025048Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)

[MISMATCH CHECK] Direct match - no mismatch
←[2m2026-01-06T01:22:17.066978Z←[0m ←[32m INFO←[0m Created ASCOM COM object for: ASCOM.PegasusAstroNYX101.Telescope
←[2m2026-01-06T01:22:19.097561Z←[0m ←[32m INFO←[0m ASCOM device ASCOM.PegasusAstroNYX101.Telescope connected
←[2m2026-01-06T01:22:19.098017Z←[0m ←[32m INFO←[0m Starting heartbeat for device ascom:ASCOM.PegasusAstroNYX101.Telescope (type: Mount, driver: Ascom): interval=5s, threshold=2, auto_reconnect=true
←[2m2026-01-06T01:22:19.098033Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:19.099602Z←[0m ←[32m INFO←[0m Auto-started heartbeat for device ascom:ASCOM.PegasusAstroNYX101.Telescope
←[2m2026-01-06T01:22:19.099623Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:19.100380Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[NativeBridge] Γ£ô Successfully connected to ascom:ASCOM.PegasusAstroNYX101.Telescope via native bridge
←[2m2026-01-06T01:22:19.102868Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:19.105720Z←[0m ←[32m INFO←[0m Starting heartbeat monitoring for Mount device: ascom:ASCOM.PegasusAstroNYX101.Telescope (interval: 10000ms)
←[2m2026-01-06T01:22:19.107451Z←[0m ←[34mDEBUG←[0m Heartbeat task stopped cleanly for ascom:ASCOM.PegasusAstroNYX101.Telescope
←[2m2026-01-06T01:22:19.109049Z←[0m ←[32m INFO←[0m Starting heartbeat for device ascom:ASCOM.PegasusAstroNYX101.Telescope (type: Mount, driver: Ascom): interval=10s, threshold=2, auto_reconnect=true
←[2m2026-01-06T01:22:19.109076Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[MISMATCH CHECK] Profile: "native:zwo:1" vs Connected: "native:zwo:1"
←[2m2026-01-06T01:22:19.110812Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[MISMATCH CHECK] Direct match - no mismatch
←[2m2026-01-06T01:22:19.111350Z←[0m ←[32m INFO←[0m Discovering Focuser devices
[MISMATCH CHECK] Profile: "ascom:ASCOM.PegasusAstroNYX101.Telescope" vs Connected: "ascom:ASCOM.PegasusAstroNYX101.Telescope"
[MISMATCH CHECK] Direct match - no mismatch←[2m2026-01-06T01:22:19.116508Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)

←[2m2026-01-06T01:22:19.126250Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:19.126778Z←[0m ←[34mDEBUG←[0m Using cached ASCOM/Alpaca discovery (25 ASCOM, 0 Alpaca devices, 6.5s old)
←[2m2026-01-06T01:22:19.130888Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 3.3s old)
←[2m2026-01-06T01:22:19.131373Z←[0m ←[32m INFO←[0m Found native device: EAF (0F229270323C0A91) (ZWO)
[NativeBridge] Found 8 native Focuser(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
[NativeBridge] Attempting native connection for native:zwo_eaf:0...
[MISMATCH CHECK] Profile: "native:zwo:1" vs Connected: "native:zwo:1"
←[2m2026-01-06T01:22:19.149415Z←[0m ←[32m INFO←[0m Connecting to Focuser device: native:zwo_eaf:0
[MISMATCH CHECK] Direct match - no mismatch
←[2m2026-01-06T01:22:19.163020Z←[0m ←[32m INFO←[0m Connecting to Focuser device: native:zwo_eaf:0
[MISMATCH CHECK] Profile: "ascom:ASCOM.PegasusAstroNYX101.Telescope" vs Connected: "ascom:ASCOM.PegasusAstroNYX101.Telescope"
←[2m2026-01-06T01:22:19.164403Z←[0m ←[32m INFO←[0m Device native:zwo_eaf:0 not registered, discovering and registering...
[MISMATCH CHECK] Direct match - no mismatch
←[2m2026-01-06T01:22:19.165649Z←[0m ←[32m INFO←[0m Discovering Focuser devices
←[2m2026-01-06T01:22:19.166751Z←[0m ←[34mDEBUG←[0m Using cached ASCOM/Alpaca discovery (25 ASCOM, 0 Alpaca devices, 6.6s old)
←[2m2026-01-06T01:22:19.167793Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 3.3s old)
←[2m2026-01-06T01:22:19.168576Z←[0m ←[32m INFO←[0m Found native device: EAF (0F229270323C0A91) (ZWO)
←[2m2026-01-06T01:22:19.169808Z←[0m ←[32m INFO←[0m Registered device: EAF (native:zwo_eaf:0)
←[2m2026-01-06T01:22:19.171442Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:19.171502Z←[0m ←[32m INFO←[0m Connecting to ZWO EAF focuser ID 0...
Found PHD2 at localhost:4400
Found PHD2 at localhost:4400
Found PHD2 at localhost:4400
[AutoDiscovery] Background discovery completed
←[2m2026-01-06T01:22:19.718615Z←[0m ←[32m INFO←[0m Connected to ZWO EAF: EAF (max step: 600000)
←[2m2026-01-06T01:22:19.719174Z←[0m ←[32m INFO←[0m Connected to native focuser: EAF
←[2m2026-01-06T01:22:19.722663Z←[0m ←[32m INFO←[0m Starting heartbeat for device native:zwo_eaf:0 (type: Focuser, driver: Native): interval=15s, threshold=3, auto_reconnect=false
←[2m2026-01-06T01:22:19.723999Z←[0m ←[32m INFO←[0m Auto-started heartbeat for device native:zwo_eaf:0
[NativeBridge] Γ£ô Successfully connected to native:zwo_eaf:0 via native bridge
←[2m2026-01-06T01:22:19.724065Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:19.722714Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:19.728300Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
←[2m2026-01-06T01:22:19.731396Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[MISMATCH CHECK] Profile: "native:zwo:1" vs Connected: "native:zwo:1"
←[2m2026-01-06T01:22:19.734056Z←[0m ←[32m INFO←[0m Discovering Filter Wheel devices
[MISMATCH CHECK] Direct match - no mismatch←[2m2026-01-06T01:22:19.735378Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)

[MISMATCH CHECK] Profile: "ascom:ASCOM.PegasusAstroNYX101.Telescope" vs Connected: "ascom:ASCOM.PegasusAstroNYX101.Telescope"
←[2m2026-01-06T01:22:19.737064Z←[0m ←[34mDEBUG←[0m Using cached ASCOM/Alpaca discovery (25 ASCOM, 0 Alpaca devices, 7.1s old)
[MISMATCH CHECK] Direct match - no mismatch
←[2m2026-01-06T01:22:19.746546Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 3.9s old)
[MISMATCH CHECK] Profile: "native:zwo_eaf:0" vs Connected: "native:zwo_eaf:0"
[MISMATCH CHECK] Direct match - no mismatch←[2m2026-01-06T01:22:19.747496Z←[0m ←[32m INFO←[0m Found native device: EFW #1 (ZWO)

[NativeBridge] Found 4 native Filter Wheel(s)
[ASCOM] Not on Windows, skipping ASCOM discovery
[NativeBridge] Attempting native connection for native:zwo_efw:0...
←[2m2026-01-06T01:22:19.765223Z←[0m ←[32m INFO←[0m Connecting to Filter Wheel device: native:zwo_efw:0
←[2m2026-01-06T01:22:19.767796Z←[0m ←[32m INFO←[0m Connecting to Filter Wheel device: native:zwo_efw:0
←[2m2026-01-06T01:22:19.768743Z←[0m ←[32m INFO←[0m Device native:zwo_efw:0 not registered, discovering and registering...
←[2m2026-01-06T01:22:19.770267Z←[0m ←[32m INFO←[0m Discovering Filter Wheel devices
←[2m2026-01-06T01:22:19.771442Z←[0m ←[34mDEBUG←[0m Using cached ASCOM/Alpaca discovery (25 ASCOM, 0 Alpaca devices, 7.2s old)
←[2m2026-01-06T01:22:19.775026Z←[0m ←[34mDEBUG←[0m Using cached discovery results (4 devices, 3.9s old)
←[2m2026-01-06T01:22:19.776026Z←[0m ←[32m INFO←[0m Found native device: EFW #1 (ZWO)
←[2m2026-01-06T01:22:19.776643Z←[0m ←[32m INFO←[0m Registered device: EFW (native:zwo_efw:0)
←[2m2026-01-06T01:22:19.777357Z←[0m ←[32m INFO←[0m Connecting to ZWO EFW filter wheel ID 0...
←[2m2026-01-06T01:22:19.777364Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[MISMATCH CHECK] Profile: "native:zwo:1" vs Connected: "native:zwo:1"
[MISMATCH CHECK] Direct match - no mismatch
[MISMATCH CHECK] Profile: "ascom:ASCOM.PegasusAstroNYX101.Telescope" vs Connected: "ascom:ASCOM.PegasusAstroNYX101.Telescope"
[MISMATCH CHECK] Direct match - no mismatch
[MISMATCH CHECK] Profile: "native:zwo_eaf:0" vs Connected: "native:zwo_eaf:0"
[MISMATCH CHECK] Direct match - no mismatch
←[2m2026-01-06T01:22:19.997260Z←[0m ←[32m INFO←[0m Connected to ZWO EFW: EFW (8 slots)
←[2m2026-01-06T01:22:19.997637Z←[0m ←[32m INFO←[0m Connected to native filter wheel: EFW
←[2m2026-01-06T01:22:19.999303Z←[0m ←[32m INFO←[0m Starting heartbeat for device native:zwo_efw:0 (type: Filter Wheel, driver: Native): interval=20s, threshold=3, auto_reconnect=false
←[2m2026-01-06T01:22:20.000110Z←[0m ←[32m INFO←[0m Auto-started heartbeat for device native:zwo_efw:0
[NativeBridge] Γ£ô Successfully connected to native:zwo_efw:0 via native bridge
←[2m2026-01-06T01:22:19.999363Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[MISMATCH CHECK] Profile: "native:zwo:1" vs Connected: "native:zwo:1"←[2m2026-01-06T01:22:20.000157Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)

[MISMATCH CHECK] Direct match - no mismatch
←[2m2026-01-06T01:22:20.001854Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[MISMATCH CHECK] Profile: "ascom:ASCOM.PegasusAstroNYX101.Telescope" vs Connected: "ascom:ASCOM.PegasusAstroNYX101.Telescope"
←[2m2026-01-06T01:22:20.004343Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)
[MISMATCH CHECK] Direct match - no mismatch
[MISMATCH CHECK] Profile: "native:zwo_eaf:0" vs Connected: "native:zwo_eaf:0"←[2m2026-01-06T01:22:20.007279Z←[0m ←[34mDEBUG←[0m [API_EVENT_STREAM] Forwarding event to Dart: Discriminant(0)

[MISMATCH CHECK] Direct match - no mismatch
[MISMATCH CHECK] Profile: "native:zwo_efw:0" vs Connected: "native:zwo_efw:0"
[MISMATCH CHECK] Direct match - no mismatch
PHD2 Version: 2.6.13
[MISMATCH CHECK] Profile: "native:zwo:1" vs Connected: "native:zwo:1"
[MISMATCH CHECK] Direct match - no mismatch
[MISMATCH CHECK] Profile: "ascom:ASCOM.PegasusAstroNYX101.Telescope" vs Connected: "ascom:ASCOM.PegasusAstroNYX101.Telescope"
[MISMATCH CHECK] Direct match - no mismatch
[MISMATCH CHECK] Profile: "native:zwo_eaf:0" vs Connected: "native:zwo_eaf:0"
[MISMATCH CHECK] Direct match - no mismatch
[MISMATCH CHECK] Profile: "native:zwo_efw:0" vs Connected: "native:zwo_efw:0"
[MISMATCH CHECK] Direct match - no mismatch
[MISMATCH CHECK] Profile: "phd2_guider" vs Connected: "PHD2 Guiding"
[MISMATCH CHECK] Profile: "native:zwo:1" vs Connected: "native:zwo:1"
[MISMATCH CHECK] Direct match - no mismatch
[MISMATCH CHECK] Profile: "ascom:ASCOM.PegasusAstroNYX101.Telescope" vs Connected: "ascom:ASCOM.PegasusAstroNYX101.Telescope"
[MISMATCH CHECK] Direct match - no mismatch
[MISMATCH CHECK] Profile: "native:zwo_eaf:0" vs Connected: "native:zwo_eaf:0"
[MISMATCH CHECK] Direct match - no mismatch
[MISMATCH CHECK] Profile: "native:zwo_efw:0" vs Connected: "native:zwo_efw:0"
[MISMATCH CHECK] Direct match - no mismatch
[MISMATCH CHECK] Profile: "phd2_guider" vs Connected: "PHD2 Guiding"
