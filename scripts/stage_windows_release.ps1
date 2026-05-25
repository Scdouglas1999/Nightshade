# Stage native/runtime DLLs next to the Windows desktop executable.
# Required after `flutter build windows` — Flutter does not copy the Rust bridge
# or LibRaw dependency into build\windows\x64\runner\Release.
#
# Usage:
#   .\scripts\stage_windows_release.ps1              # Release output
#   .\scripts\stage_windows_release.ps1 -Profile Debug

param(
    [ValidateSet('Release', 'Debug')]
    [string]$Profile = 'Release'
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$NativeDir = Join-Path $ProjectRoot 'native\nightshade_native'
$DesktopDir = Join-Path $ProjectRoot 'apps\desktop'
$OutputDir = Join-Path $DesktopDir "build\windows\x64\runner\$Profile"

if (-not (Test-Path $OutputDir)) {
    throw "Flutter output directory not found: $OutputDir`nRun flutter build windows first."
}

function Copy-RequiredFile($source, $dest) {
    if (-not (Test-Path $source)) {
        throw "Required file not found: $source"
    }
    Copy-Item -Path $source -Destination $dest -Force
    Write-Host "  -> $dest" -ForegroundColor Green
}

function Copy-OptionalFile($source, $dest) {
    if (Test-Path $source) {
        Copy-Item -Path $source -Destination $dest -Force
        Write-Host "  -> $dest" -ForegroundColor DarkGreen
    }
}

function Assert-Dll64Bit($path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
    if ($machine -ne 0x8664) {
        throw "DLL is not 64-bit: $path (machine=$machine)"
    }
}

Write-Host "Staging native DLLs for Windows $Profile -> $OutputDir" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# nightshade_bridge.dll (Rust)
# ---------------------------------------------------------------------------
$bridgeSource = Join-Path $NativeDir "target\$($Profile.ToLower())\nightshade_bridge.dll"
if (-not (Test-Path $bridgeSource)) {
    Write-Host "Bridge DLL missing; building cargo release..." -ForegroundColor Yellow
    Push-Location $NativeDir
    if ($Profile -eq 'Release') {
        cargo build --release --package nightshade_bridge
    } else {
        cargo build --package nightshade_bridge
    }
    Pop-Location
}

$bridgeDest = Join-Path $OutputDir 'nightshade_bridge.dll'
Write-Host "Copying nightshade_bridge.dll"
Copy-RequiredFile $bridgeSource $bridgeDest
Assert-Dll64Bit $bridgeDest
$srcHash = (Get-FileHash $bridgeSource -Algorithm SHA256).Hash
$dstHash = (Get-FileHash $bridgeDest -Algorithm SHA256).Hash
if ($srcHash -ne $dstHash) {
    throw "nightshade_bridge.dll copy verification failed (hash mismatch)"
}

# Also keep apps/desktop copies in sync (dev.ps1 / FRB expectations)
$bridgeMirrorDirs = @(
    (Join-Path $DesktopDir 'nightshade_bridge.dll'),
    (Join-Path $DesktopDir 'windows\nightshade_bridge.dll'),
    (Join-Path $DesktopDir "build\windows\x64\runner\Debug\nightshade_bridge.dll"),
    (Join-Path $DesktopDir "build\windows\x64\runner\Release\nightshade_bridge.dll")
)
foreach ($mirror in $bridgeMirrorDirs) {
    $mirrorDir = Split-Path -Parent $mirror
    if (Test-Path $mirrorDir) {
        Copy-Item -Path $bridgeSource -Destination $mirror -Force
    }
}

# ---------------------------------------------------------------------------
# libraw.dll (required to load nightshade_bridge.dll on Windows)
# ---------------------------------------------------------------------------
$librawSource = Join-Path $DesktopDir 'windows\runner\Release\libraw.dll'
if (-not (Test-Path $librawSource)) {
    $librawFallbacks = @(
        (Join-Path $ProjectRoot 'lib\libraw\libraw.dll'),
        (Join-Path $ProjectRoot 'libraw.dll')
    )
    foreach ($fb in $librawFallbacks) {
        if (Test-Path $fb) {
            $librawSource = $fb
            break
        }
    }
}

if (-not (Test-Path $librawSource)) {
    throw @"
libraw.dll not found. nightshade_bridge.dll depends on it and will not load.

Place a 64-bit RELEASE libraw.dll at:
  apps\desktop\windows\runner\Release\libraw.dll

Or run: .\scripts\copy_libraw.ps1
"@
}

$librawDest = Join-Path $OutputDir 'libraw.dll'
Write-Host "Copying libraw.dll"
Copy-RequiredFile $librawSource $librawDest
Assert-Dll64Bit $librawDest

# ---------------------------------------------------------------------------
# MSVC runtime (bundled for machines without VS installed)
# ---------------------------------------------------------------------------
Write-Host "Copying MSVC runtime DLLs (optional, from System32)"
$runtimeDlls = @(
    'vcruntime140.dll',
    'vcruntime140_1.dll',
    'msvcp140.dll'
)
foreach ($name in $runtimeDlls) {
    $src = Join-Path $env:SystemRoot "System32\$name"
    Copy-OptionalFile $src (Join-Path $OutputDir $name)
}

# ---------------------------------------------------------------------------
# Verify load chain
# ---------------------------------------------------------------------------
foreach ($required in @('nightshade_bridge.dll', 'libraw.dll')) {
    $path = Join-Path $OutputDir $required
    if (-not (Test-Path $path)) {
        throw "Staging incomplete: missing $required"
    }
}

Write-Host ""
Write-Host "Staging complete. Launch:" -ForegroundColor Yellow
Write-Host "  $(Join-Path $OutputDir 'nightshade_desktop.exe')"
