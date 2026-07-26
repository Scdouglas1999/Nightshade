<#
.SYNOPSIS
    Build a Nightshade update package for OTA distribution.

.DESCRIPTION
    This script creates a ZIP update package with manifest from the built
    Flutter desktop release. Run after 'melos run dev:norun' or a release build.

.PARAMETER SkipBuild
    Skip the Flutter build step (use existing build output).

.PARAMETER SkipUpdaterBuild
    Skip building/copying updater.exe; require it to be staged in the release
    directory already. Used by CI, which builds + Authenticode-signs updater.exe
    in a prior step so the signed binary ends up inside the canonical archive.

.PARAMETER OutputDir
    Output directory for the update package. Defaults to apps/desktop/build/update.

.PARAMETER DownloadUrl
    URL baked into (and signed into) the manifest's downloadUrl. Must equal the
    real published asset URL, since it is part of the signed payload. Defaults to
    the legacy updates.nightshade.app path for local pushes.

.PARAMETER NoPusherCopy
    Skip writing the generic nightshade-update.zip copy used by the LAN pusher.
    Used by CI so the publish job's asset sweep does not pick up a stray zip.

.EXAMPLE
    .\build_update_package.ps1
    Build Flutter app and create update package.

.EXAMPLE
    .\build_update_package.ps1 -SkipBuild
    Create update package from existing build output.
#>

param(
    [switch]$SkipBuild,
    [switch]$SkipUpdaterBuild,
    [string]$OutputDir = "apps/desktop/build/update",
    [string]$DownloadUrl = "",
    [switch]$NoPusherCopy
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

    # SEC-001: OTA is fail-closed. Two distinct keys are involved:
    #   * NIGHTSHADE_UPDATE_PRIVATE_KEY signs THIS manifest (below).
    #   * NIGHTSHADE_UPDATE_PUBLIC_KEY must be embedded in the SHIPPED app
    #     binary at build time (see scripts/package_windows.ps1) for that
    #     binary to accept the signed update. A package signed here can only
    #     be applied by a build that carries the matching public key; an app
    #     built without it will refuse the update by design.
    if ([string]::IsNullOrWhiteSpace($env:NIGHTSHADE_UPDATE_PUBLIC_KEY)) {
        Write-Host "  NOTE: NIGHTSHADE_UPDATE_PUBLIC_KEY is not set in this shell." -ForegroundColor DarkYellow
        Write-Host "        The packaged app self-updates only if it was built with that key embedded (package_windows.ps1)." -ForegroundColor DarkYellow
    }

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

    # Build the updater executable (required for OTA updates to work). CI builds
    # and Authenticode-signs it in an earlier step, then passes -SkipUpdaterBuild
    # so the signed binary stays in the archive; here we only assert its presence.
    $rustDir = "native/nightshade_native"
    $updaterDest = Join-Path $releaseDir "updater.exe"
    if ($SkipUpdaterBuild) {
        if (-not (Test-Path $updaterDest)) {
            throw "-SkipUpdaterBuild set but updater.exe is not staged at $updaterDest"
        }
        Write-Host "`nReusing pre-staged updater.exe" -ForegroundColor Yellow
    } else {
        Write-Host "`nBuilding updater.exe..." -ForegroundColor Yellow
        Push-Location $rustDir
        cargo build --release --package nightshade_updater
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            throw "Updater build failed"
        }
        Pop-Location

        # Copy updater.exe to the release directory
        $updaterSource = Join-Path $rustDir "target/release/updater.exe"
        if (-not (Test-Path $updaterSource)) {
            throw "Updater not found at $updaterSource"
        }
        Copy-Item $updaterSource $updaterDest -Force
        Write-Host "  Copied updater.exe to release directory" -ForegroundColor Gray
    }

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

    # Also create a generic name for the pusher tool (skipped in CI so the
    # publish job's asset sweep does not pick up a stray zip).
    if (-not $NoPusherCopy) {
        Copy-Item $packagePath $tempPackagePath
    }

    $compressedSize = (Get-Item $packagePath).Length
    $packageSha256 = (Get-FileHash $packagePath -Algorithm SHA256).Hash.ToLower()
    Write-Host "  Compressed: $([math]::Round($compressedSize/1024/1024, 1)) MB" -ForegroundColor Gray
    Write-Host "  Package SHA-256: $packageSha256" -ForegroundColor Gray

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
        packageSha256 = $packageSha256
        downloadUrl = if ([string]::IsNullOrWhiteSpace($DownloadUrl)) {
            "https://updates.nightshade.app/releases/$version/$packageName"
        } else {
            $DownloadUrl
        }
        releaseNotes = "Update to version $version"
    }

    # Write the unsigned manifest first; the signer reads it back and produces
    # the canonical payload itself (see below) so the signed bytes come from the
    # same serializer the verifier uses.
    $manifestPath = Join-Path $OutputDir "manifest.json"
    $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath -Encoding UTF8

    $privateKeyBase64 = $env:NIGHTSHADE_UPDATE_PRIVATE_KEY
    if ($privateKeyBase64) {
        Write-Host "  Signing manifest with NIGHTSHADE_UPDATE_PRIVATE_KEY" -ForegroundColor Gray
        # CRITICAL byte-match: the canonical payload MUST be constructed by the
        # same language/serializer the runtime verifier uses
        # (update_verifier.dart _canonicalManifestPayload) or every signed
        # manifest is rejected. The verifier sorts the files map by key, emits
        # inner fields path/size/sha256, and re-serializes releaseDate via
        # DateTime.parse(...).toUtc().toIso8601String() (which appends .000ms,
        # something a PowerShell ConvertTo-Json -Compress of the raw string can
        # never reproduce). So we read the manifest we just wrote and rebuild the
        # payload in Dart, mirroring the verifier exactly, then jsonEncode + sign.
        $tempScript = Join-Path $OutputDir "sign_manifest.dart"
        $packageConfig = Join-Path $PSScriptRoot "..\packages\nightshade_updater\.dart_tool\package_config.json"
@"
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  final manifest = jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final privateKey = base64Decode(args[1]);
  final algorithm = Ed25519();
  final seed = privateKey.length >= 32 ? privateKey.sublist(0, 32) : privateKey;
  if (seed.length != 32) {
    stderr.writeln('Expected 32-byte Ed25519 private key seed');
    exit(1);
  }
  final files = manifest['files'] as Map<String, dynamic>;
  final sortedKeys = files.keys.toList()..sort((a, b) => a.compareTo(b));
  final payload = <String, dynamic>{
    'version': manifest['version'],
    'buildNumber': manifest['buildNumber'],
    'releaseDate':
        DateTime.parse(manifest['releaseDate'] as String).toUtc().toIso8601String(),
    'platform': manifest['platform'],
    'arch': manifest['arch'],
    'minVersion': manifest['minVersion'],
    'files': {
      for (final key in sortedKeys)
        key: {
          'path': (files[key] as Map)['path'],
          'size': (files[key] as Map)['size'],
          'sha256': (files[key] as Map)['sha256'],
        },
    },
    'totalSize': manifest['totalSize'],
    'compressedSize': manifest['compressedSize'],
    'packageSha256': manifest['packageSha256'],
    'downloadUrl': manifest['downloadUrl'],
    'releaseNotes': manifest['releaseNotes'],
  };
  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  final signature =
      await algorithm.sign(utf8.encode(jsonEncode(payload)), keyPair: keyPair);
  stdout.write(base64Encode(signature.bytes));
}
"@ | Set-Content $tempScript -Encoding UTF8
        $signature = dart --packages $packageConfig $tempScript $manifestPath $privateKeyBase64
        Remove-Item $tempScript -Force
        if ($LASTEXITCODE -ne 0) {
            throw "Manifest signing failed"
        }
        $manifest.signature = $signature.Trim()
        # Rewrite the manifest now that it carries the signature.
        $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath -Encoding UTF8
    } else {
        Write-Host "  OTA manifest unsigned (no NIGHTSHADE_UPDATE_PRIVATE_KEY); update is fail-closed-disabled" -ForegroundColor DarkYellow
    }

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
