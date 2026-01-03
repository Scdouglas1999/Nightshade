# Build script for Nightshade native Rust library (Windows PowerShell)
# Builds for Windows

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$NativeDir = Join-Path $ProjectRoot "native\nightshade_native"

Set-Location $NativeDir

Write-Host "Building Nightshade native library..."
Write-Host "Project root: $ProjectRoot"
Write-Host "Native dir: $NativeDir"

# Build for Windows
Write-Host "Building for Windows..."
cargo build --release --manifest-path bridge\Cargo.toml

# Copy to Flutter app directory
$LibName = "nightshade_bridge.dll"
$TargetDir = Join-Path $ProjectRoot "apps\desktop\build\windows\x64\runner\Release"
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
Copy-Item "target\release\$LibName" -Destination $TargetDir -Force
Write-Host "Copied $LibName to $TargetDir"

Write-Host "Build complete!"





