<#
.SYNOPSIS
    Build a Nightshade update package for OTA distribution.

.DESCRIPTION
    This script creates a ZIP update package with manifest from the built
    Flutter desktop release. Run after 'melos run dev:norun' or a release build.

.PARAMETER SkipBuild
    Skip the Flutter build step (use existing build output).

.PARAMETER OutputDir
    Output directory for the update package. Defaults to apps/desktop/build/update.

.EXAMPLE
    .\build_update_package.ps1
    Build Flutter app and create update package.

.EXAMPLE
    .\build_update_package.ps1 -SkipBuild
    Create update package from existing build output.
#>

param(
    [switch]$SkipBuild,
    [string]$OutputDir = "apps/desktop/build/update"
)

$ErrorActionPreference = "Stop"

Write-Host "Nightshade Update Package Builder" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan

# Navigate to repo root
Push-Location $PSScriptRoot\..

try {
    # Read version info
    Write-Host "`nReading version.yaml..." -ForegroundColor Yellow
    $versionYaml = Get-Content "version.yaml" -Raw
    $version = [regex]::Match($versionYaml, 'version:\s*"?([^"\s]+)"?').Groups[1].Value
    $buildNumber = [int][regex]::Match($versionYaml, 'build_number:\s*(\d+)').Groups[1].Value
    $channel = [regex]::Match($versionYaml, 'channel:\s*"?([^"\s]+)"?').Groups[1].Value

    Write-Host "  Version: $version" -ForegroundColor Gray
    Write-Host "  Build: $buildNumber" -ForegroundColor Gray
    Write-Host "  Channel: $channel" -ForegroundColor Gray

    # Build if not skipping
    if (-not $SkipBuild) {
        Write-Host "`nBuilding Nightshade..." -ForegroundColor Yellow
        melos run dev:norun
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed"
        }
    }

    # Verify release build exists
    $releaseDir = "apps/desktop/build/windows/x64/runner/Release"
    if (-not (Test-Path $releaseDir)) {
        throw "Release build not found at $releaseDir. Run 'melos run dev:norun' first."
    }

    # Build the updater executable (required for OTA updates to work)
    Write-Host "`nBuilding updater.exe..." -ForegroundColor Yellow
    $rustDir = "native/nightshade_native"
    Push-Location $rustDir
    cargo build --release --package nightshade_updater
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        throw "Updater build failed"
    }
    Pop-Location

    # Copy updater.exe to the release directory
    $updaterSource = Join-Path $rustDir "target/release/updater.exe"
    $updaterDest = Join-Path $releaseDir "updater.exe"
    if (-not (Test-Path $updaterSource)) {
        throw "Updater not found at $updaterSource"
    }
    Copy-Item $updaterSource $updaterDest -Force
    Write-Host "  Copied updater.exe to release directory" -ForegroundColor Gray

    # Create output directory
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    # Calculate file hashes
    Write-Host "`nCalculating file hashes..." -ForegroundColor Yellow
    $files = @{}
    $totalSize = 0

    Get-ChildItem -Path $releaseDir -Recurse -File | ForEach-Object {
        $relativePath = $_.FullName.Substring((Resolve-Path $releaseDir).Path.Length + 1).Replace("\", "/")
        $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
        $size = $_.Length
        $totalSize += $size

        $files[$relativePath] = @{
            path = $relativePath
            size = $size
            sha256 = $hash
        }

        Write-Host "  $relativePath ($([math]::Round($size/1024, 1)) KB)" -ForegroundColor Gray
    }

    Write-Host "  Total: $([math]::Round($totalSize/1024/1024, 1)) MB uncompressed" -ForegroundColor Gray

    # Create ZIP package
    $packageName = "nightshade-$version-windows-x64.zip"
    $packagePath = Join-Path $OutputDir $packageName
    $tempPackagePath = Join-Path $OutputDir "nightshade-update.zip"

    Write-Host "`nCreating ZIP package..." -ForegroundColor Yellow

    # Remove existing package
    if (Test-Path $packagePath) {
        Remove-Item $packagePath -Force
    }
    if (Test-Path $tempPackagePath) {
        Remove-Item $tempPackagePath -Force
    }

    # Create ZIP
    Compress-Archive -Path "$releaseDir\*" -DestinationPath $packagePath -CompressionLevel Optimal

    # Also create a generic name for the pusher tool
    Copy-Item $packagePath $tempPackagePath

    $compressedSize = (Get-Item $packagePath).Length
    Write-Host "  Compressed: $([math]::Round($compressedSize/1024/1024, 1)) MB" -ForegroundColor Gray

    # Create manifest
    Write-Host "`nGenerating manifest..." -ForegroundColor Yellow

    $manifest = @{
        version = $version
        buildNumber = $buildNumber
        releaseDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        platform = "windows"
        arch = "x64"
        minVersion = "2.0.0"
        files = $files
        totalSize = $totalSize
        compressedSize = $compressedSize
        downloadUrl = "https://updates.nightshade.app/releases/$version/$packageName"
        releaseNotes = "Update to version $version"
    }

    $manifestPath = Join-Path $OutputDir "manifest.json"
    $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath -Encoding UTF8

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "Update package created successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "`nPackage: $packagePath" -ForegroundColor Gray
    Write-Host "Manifest: $manifestPath" -ForegroundColor Gray
    Write-Host "`nTo push to imaging laptop:" -ForegroundColor Yellow
    Write-Host "  .\tools\update_pusher\push_update.ps1 -Discover" -ForegroundColor White
    Write-Host "  .\tools\update_pusher\push_update.ps1 -All" -ForegroundColor White
}
finally {
    Pop-Location
}
