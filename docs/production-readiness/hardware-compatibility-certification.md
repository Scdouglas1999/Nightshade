# Hardware Compatibility Certification

Nightshade cannot fully prove physical hardware behavior without attached devices, but this suite pushes software-only confidence as high as possible.

## What The Suite Proves

- SDK artifacts for each declared manufacturer target are present.
- Windows DLL exports are checked as runtime SDK evidence.
- Nightshade native, Alpaca, mount protocol, and bridge tests run through real project code.
- Fake-SDK contracts build shim DLLs for ZWO `ASICamera2.dll`, `EAF_focuser.dll`, and `EFW_filter.dll`; Atik `AtikCameras.dll`; and SVBONY `SVBCameraSDK.dll`, then drive the production native drivers through discovery, connect, controls, exposure/capture, image download, focuser, and filter-wheel paths.
- The local Alpaca simulator contract drives camera, filter wheel, and telescope clients through realistic ASCOM Alpaca flows.
- Alpaca negative-path coverage confirms device `ErrorNumber` responses and malformed image payloads surface as failures instead of false passes.
- Reports are split by target, function, model, and model capability so partial support is visible.

## What It Still Cannot Prove

- USB/serial electrical behavior, firmware timing, or real driver installation edge cases.
- Sensor readout correctness, cooler performance, mechanical filter/focuser movement, or mount motion accuracy.
- Long overnight reliability with disconnects, dew, power sag, meridian flips, and recovery.
- License-gated SDK support where the SDK cannot legally be downloaded or redistributed.

## Run

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\compat\hardware_compat.ps1 -Mode run -Strict -Out reports\compat\current-run
```

Generated outputs:

- `reports/compat/current-run/results.json`
- `reports/compat/current-run/compatibility-report.md`
- `reports/compat/current-run/junit.xml`

## Verdicts

`pass` means all declared software evidence for that target is present and all configured commands passed.

`fail` means a concrete compatibility claim broke: missing runtime exports, missing function evidence, or a failing command.

`blocked` means the suite is prevented from making a support claim because a license-gated SDK, conformance tool, platform-specific simulator, or native implementation is missing.

`skipped` means the target does not apply to the current OS, such as Linux-only INDI simulator coverage on Windows.

## Confidence Tiers

From weakest to strongest:

1. Header/source symbol evidence.
2. DLL export evidence from SDK binaries.
3. Nightshade no-hardware SDK/discovery tests.
4. Fake SDK shim tests that drive production native drivers.
5. Local protocol simulator tests with success and fault injection.
6. Official conformance/simulator tests, such as ASCOM ConformU or INDI simulators.
7. Real hardware smoke and soak tests.

The current suite reaches tiers 2-5 for many native and Alpaca paths, while explicitly blocking unsupported or inaccessible areas.
