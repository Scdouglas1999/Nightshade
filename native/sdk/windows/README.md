# Bundled vendor device SDKs (Windows)

Native camera/focuser/filter-wheel drivers are loaded at runtime by the native
bridge (`native/nightshade_native/native/src/vendor/*`). The loader
(`sdk_loader.rs`) searches **next to `nightshade_desktop.exe` first**, then the
vendor's install path (`C:\Program Files\<vendor>\...`).

Any `*.dll` placed in this folder is copied next to the executable by
`scripts/stage_windows_release.ps1` and shipped in the release zip, so devices
connect without the user installing the vendor's driver package separately.

These vendor SDK binaries are **not committed** (license + size). Drop the
redistributable 64-bit DLLs here before cutting a release. Expected filenames
(must match exactly — the loader looks for these names):

| Vendor | DLL(s) |
| --- | --- |
| ZWO (ASI) | `ASICamera2.dll`, `EAF_focuser.dll`, `EFW_filter.dll` |
| Player One | `PlayerOneCamera.dll`, `PlayerOnePW.dll` |
| QHYCCD | `qhyccd.dll`, `gXusb.dll` |
| SVBony | `SVBCameraSDK.dll` |
| Touptek | `toupcam.dll` |
| Altair | `altaircam.dll` |
| OGMAVision | `ogmacam.dll` |
| Mallincam | `mallincam.dll` |
| Atik | `AtikCameras.dll` |
| FLI | `libfli.dll` |
| Moravian | `XAPI.dll` |
| gPhoto2 (DSLR) | `gphoto2.dll`, `libgphoto2.dll` |

All DLLs must be 64-bit (the staging script asserts this). Sources are each
vendor's official SDK download; only the freely-redistributable SDKs should be
bundled.
