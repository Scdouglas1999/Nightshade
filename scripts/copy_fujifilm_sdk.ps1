# Copy Fujifilm X Acquire SDK DLLs to the Flutter build output
# Run this after building or before testing with Fujifilm cameras
#
# Usage:
#   .\scripts\copy_fujifilm_sdk.ps1          # Copy to Debug build (default)
#   .\scripts\copy_fujifilm_sdk.ps1 -Release # Copy to Release build
#   .\scripts\copy_fujifilm_sdk.ps1 -Debug   # Copy to Debug build (explicit)

param(
    [switch]$Release,
    [switch]$Debug
)

$ErrorActionPreference = "Stop"

# Determine build configuration
if ($Release) {
    $buildConfig = "Release"
} elseif ($Debug) {
    $buildConfig = "Debug"
} else {
    $buildConfig = "Debug"  # Default
}

Write-Host "========================================"
Write-Host "Fujifilm X Acquire SDK Copy Script"
Write-Host "========================================"
Write-Host "Build configuration: $buildConfig"
Write-Host ""

# Search paths for Fujifilm SDK (in priority order)
$searchPaths = @(
    "C:\Users\scdou\Downloads\SDK13200\SDK13200\REDISTRIBUTABLES\Windows\64bit",
    "C:\Program Files\Fujifilm\X Acquire",
    "C:\Program Files (x86)\Fujifilm\X Acquire"
)

# Find the SDK source directory
$sourcePath = $null
foreach ($path in $searchPaths) {
    $testFile = Join-Path $path "XAPI.dll"
    if (Test-Path $testFile) {
        $sourcePath = $path
        Write-Host "Found Fujifilm SDK at: $sourcePath" -ForegroundColor Green
        break
    }
}

if (-not $sourcePath) {
    Write-Host "ERROR: Fujifilm X Acquire SDK not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Searched locations:" -ForegroundColor Yellow
    foreach ($path in $searchPaths) {
        Write-Host "  - $path" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Please install the Fujifilm X Acquire SDK or copy the DLLs to one of the above locations." -ForegroundColor Yellow
    exit 1
}

# Target directory
$targetDir = Join-Path $PSScriptRoot "..\apps\desktop\build\windows\x64\runner\$buildConfig"
$targetDir = [System.IO.Path]::GetFullPath($targetDir)

Write-Host "Target directory: $targetDir"
Write-Host ""

# Check if target directory exists
if (!(Test-Path $targetDir)) {
    Write-Host "WARNING: Target directory does not exist: $targetDir" -ForegroundColor Yellow
    Write-Host "Creating directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Write-Host "Created target directory" -ForegroundColor Green
}

# Build list of DLLs to copy
$dllsToExport = @("XAPI.dll")

# Add model-specific modules FF0000API.dll through FF0020API.dll
for ($i = 0; $i -le 20; $i++) {
    $dllName = "FF{0:D4}API.dll" -f $i
    $dllsToExport += $dllName
}

Write-Host "DLLs to copy:"
foreach ($dll in $dllsToExport) {
    Write-Host "  - $dll"
}
Write-Host ""

# Copy DLLs
$copiedCount = 0
$skippedCount = 0
$failedCount = 0

Write-Host "Copying files..."
Write-Host ""

foreach ($dll in $dllsToExport) {
    $sourceFile = Join-Path $sourcePath $dll
    $targetFile = Join-Path $targetDir $dll

    if (!(Test-Path $sourceFile)) {
        Write-Host "  SKIPPED: $dll (not found in SDK)" -ForegroundColor Yellow
        $skippedCount++
        continue
    }

    try {
        Copy-Item $sourceFile $targetFile -Force
        Write-Host "  COPIED: $dll" -ForegroundColor Green
        $copiedCount++
    }
    catch {
        Write-Host "  FAILED: $dll" -ForegroundColor Red
        Write-Host "    Error: $_" -ForegroundColor Red
        $failedCount++
    }
}

Write-Host ""
Write-Host "========================================"
Write-Host "Fujifilm SDK Copy Complete"
Write-Host "========================================"
Write-Host "Copied:  $copiedCount"
Write-Host "Skipped: $skippedCount (not found in SDK)"
if ($failedCount -gt 0) {
    Write-Host "Failed:  $failedCount" -ForegroundColor Red
} else {
    Write-Host "Failed:  $failedCount" -ForegroundColor Green
}

if ($failedCount -gt 0) {
    exit 1
}

Write-Host ""
Write-Host "Fujifilm SDK DLLs are ready in: $targetDir" -ForegroundColor Cyan
