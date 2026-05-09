# Hardware Availability Probe

- Generated: `2026-05-05T14:48:42.040807Z`
- Executable: `C:\Users\scdou\Documents\Nightshade2\apps/desktop/build/windows/x64/runner/Release/nightshade_desktop.exe`
- Full required real-or-simulator coverage: `false`
- Full required non-simulator coverage: `false`
- Scope: discovery only; this does not connect to devices or verify control actions.

Missing required real-or-simulator device classes: `filterWheel`, `rotator`, `dome`, `safetyMonitor`.
Missing required non-simulator device classes: `filterWheel`, `rotator`, `dome`, `safetyMonitor`.

| Device Type | Non-Simulator | Simulator | Devices |
| --- | ---: | ---: | --- |
| Camera | 2 | 1 | ascom:ascom:ASCOM.DSLR.Camera<br>ascom:ascom:ASCOM.ScdouglasFujifilm.Camera<br>simulator:sim_camera_1 |
| Mount | 2 | 0 | ascom:ascom:ASCOMDome.Telescope<br>ascom:ascom:ASCOM.ScdouglasFujifilm.Telescope |
| Focuser | 1 | 0 | ascom:ascom:ASCOM.GeminiFocuserPro.Focuser |
| Filter wheel | 0 | 0 | None |
| Rotator | 0 | 0 | None |
| Guider | 2 | 0 | native:native:builtin_guider:multi_star<br>native:phd2_guider |
| Dome | 0 | 0 | None |
| Weather | 2 | 0 | ascom:ascom:ASCOM.OCH.ObservingConditions<br>ascom:ascom:ASCOM.OpenWeatherMap.ObservingConditions |
| Safety monitor | 0 | 0 | None |
