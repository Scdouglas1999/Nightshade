# Nightshade Development Build Script
# =====================================
# This script ensures all build artifacts are in sync:
#   1. Regenerates Flutter Rust Bridge bindings
#   2. Rebuilds the Rust native library
#   3. Copies DLLs to Flutter app directories
#   4. Optionally runs the Flutter app
#
# Usage:
#   .\scripts\dev.ps1           # Full rebuild + run
#   .\scripts\dev.ps1 -NoRun    # Full rebuild, don't run
#   .\scripts\dev.ps1 -SkipFrb  # Skip FRB regeneration (faster if only Dart changed)

param(
    [switch]$NoRun,
    [switch]$SkipFrb,
    [switch]$Release,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Step($msg) { Write-Host ("`n==> " + $msg) -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host ("  [OK] " + $msg) -ForegroundColor Green }
function Write-Warn($msg) { Write-Host ("  [!] " + $msg) -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host ("  [X] " + $msg) -ForegroundColor Red }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$NativeDir = Join-Path $ProjectRoot "native\nightshade_native"
$DesktopDir = Join-Path $ProjectRoot "apps\desktop"
$BridgeDir = Join-Path $ProjectRoot "packages\nightshade_bridge"

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Magenta
Write-Host "           Nightshade Development Build Script                    " -ForegroundColor Magenta
Write-Host "==================================================================" -ForegroundColor Magenta
Write-Host ""

# ---------------------------
# Step 0: Clean if requested
# ---------------------------
if ($Clean) {
    Write-Step "Cleaning build artifacts..."

    Set-Location $DesktopDir
    flutter clean 2>$null
    Write-Ok "Flutter cleaned"

    Set-Location $NativeDir
    cargo clean 2>$null
    Write-Ok "Cargo cleaned"
}

# ---------------------------
# Step 1: Set up environment for ffigen
# ---------------------------
Write-Step "Setting up build environment..."

# Detect LLVM version
$LlvmVersions = Get-ChildItem "C:\Program Files\LLVM\lib\clang" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
if ($LlvmVersions) {
    $LlvmVersion = $LlvmVersions | Sort-Object -Descending | Select-Object -First 1
    Write-Ok ("Found LLVM " + $LlvmVersion)
} else {
    Write-Err "LLVM not found at C:\Program Files\LLVM"
    exit 1
}

# Detect MSVC version
$MsvcVersions = Get-ChildItem "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
if ($MsvcVersions) {
    $MsvcVersion = $MsvcVersions | Sort-Object -Descending | Select-Object -First 1
    Write-Ok ("Found MSVC " + $MsvcVersion)
} else {
    Write-Err "MSVC not found"
    exit 1
}

# Detect Windows SDK version
$SdkVersions = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\Include" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^\d+\." } | Select-Object -ExpandProperty Name
if ($SdkVersions) {
    $SdkVersion = $SdkVersions | Sort-Object -Descending | Select-Object -First 1
    Write-Ok ("Found Windows SDK " + $SdkVersion)
} else {
    Write-Err "Windows SDK not found"
    exit 1
}

# Set CPATH for ffigen (required for stdbool.h)
$env:CPATH = @(
    "C:\Program Files\LLVM\lib\clang\$LlvmVersion\include",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\$MsvcVersion\include",
    "C:\Program Files (x86)\Windows Kits\10\Include\$SdkVersion\ucrt",
    "C:\Program Files (x86)\Windows Kits\10\Include\$SdkVersion\um",
    "C:\Program Files (x86)\Windows Kits\10\Include\$SdkVersion\shared"
) -join ";"

Write-Ok "CPATH configured for ffigen"

# ---------------------------
# Step 2: Regenerate FRB bindings
# ---------------------------
if (-not $SkipFrb) {
    Write-Step "Regenerating Flutter Rust Bridge bindings..."

    Set-Location $NativeDir

    $frbOutput = flutter_rust_bridge_codegen generate 2>&1

    if ($LASTEXITCODE -ne 0 -and $frbOutput -notmatch "Done!") {
        Write-Err "FRB codegen failed"
        Write-Host $frbOutput
        exit 1
    }

    if ($frbOutput -match "SEVERE") {
        Write-Warn "FRB completed with warnings (this is usually OK)"
    } else {
        Write-Ok "FRB bindings regenerated"
    }
} else {
    Write-Warn "Skipping FRB regeneration (SkipFrb flag set)"
}

# ---------------------------
# Step 3: Build Rust library
# ---------------------------
Write-Step "Building Rust native library..."

Set-Location $NativeDir

$cargoArgs = @("build", "--package", "nightshade_bridge", "--release")
$BuildProfile = "release"

cargo @cargoArgs

if ($LASTEXITCODE -ne 0) {
    Write-Err "Cargo build failed"
    exit 1
}

Write-Ok ("Rust library built (" + $BuildProfile + ")")

# ---------------------------
# Step 4: Copy DLLs to Flutter directories
# ---------------------------
Write-Step "Copying native library to Flutter app..."

$SourceDll = Join-Path $NativeDir ("target\" + $BuildProfile + "\nightshade_bridge.dll")

if (-not (Test-Path $SourceDll)) {
    Write-Err ("Built DLL not found at: " + $SourceDll)
    exit 1
}

$Destinations = @(
    (Join-Path $DesktopDir "nightshade_bridge.dll"),
    (Join-Path $DesktopDir "windows\nightshade_bridge.dll"),
    (Join-Path $DesktopDir "build\windows\x64\runner\Debug\nightshade_bridge.dll"),
    (Join-Path $DesktopDir "build\windows\x64\runner\Release\nightshade_bridge.dll")
)

foreach ($dest in $Destinations) {
    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item -Path $SourceDll -Destination $dest -Force
}

Write-Ok "DLL copied to Flutter app directories"

# Verify hash sync
$SourceHash = (Get-FileHash $SourceDll -Algorithm MD5).Hash.Substring(0, 8)
Write-Ok ("DLL hash: " + $SourceHash)

# Copy 64-bit libraw.dll (required dependency)
# Use the known 64-bit source from windows/runner/Release
$LibRawDll = Join-Path $ProjectRoot "apps/desktop/windows/runner/Release/libraw.dll"
if (-not (Test-Path $LibRawDll)) {
    # Fallback sources
    $fallbacks = @(
        (Join-Path $ProjectRoot "lib/libraw/libraw.dll"),
        (Join-Path $ProjectRoot "apps/desktop/windows/runner/Debug/libraw.dll"),
        (Join-Path $ProjectRoot "libraw.dll")
    )
    foreach ($fb in $fallbacks) {
        if (Test-Path $fb) {
            $LibRawDll = $fb
            Write-Host "  Using fallback libraw.dll: $fb" -ForegroundColor Yellow
            break
        }
    }
}

if (Test-Path $LibRawDll) {
    # Verify it's 64-bit before copying
    $bytes = [System.IO.File]::ReadAllBytes($LibRawDll)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
    if ($machine -ne 0x8664) {
        Write-Error "libraw.dll is NOT 64-bit! Found machine type: $machine (expected 0x8664 for AMD64)"
        Write-Error "Please ensure you have a 64-bit libraw.dll in apps/desktop/windows/runner/Release/"
        exit 1
    }

    foreach ($dest in $Destinations) {
        $destDir = Split-Path -Parent $dest
        if (Test-Path $destDir) {
            $librawDest = Join-Path $destDir "libraw.dll"
            Copy-Item -Path $LibRawDll -Destination $librawDest -Force
        }
    }
    Write-Ok "LibRaw DLL copied (verified 64-bit)"
} else {
    Write-Host "  Warning: libraw.dll not found, image processing may not work" -ForegroundColor Yellow
}

# ---------------------------
# Step 5: Run Flutter (optional)
# ---------------------------
if (-not $NoRun) {
    Write-Step "Starting Flutter app..."

    Set-Location $DesktopDir

    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor DarkGray
    Write-Host ""

    flutter run -d windows
} else {
    Write-Host ""
    Write-Ok "Build complete! Run with: flutter run -d windows"
    Write-Host ""
}
