@echo off
title Nightshade Headless Server
color 0A
echo ========================================
echo Nightshade 2.0 - Headless Mode
echo ========================================
echo.
echo Starting headless server...
echo.
echo Make sure:
echo   1. Windows Firewall rules are set
echo   2. Both devices are on the same WiFi network
echo   3. Watch this window for connection info
echo.
echo Press Ctrl+C to stop the server
echo.
echo ========================================
echo.

cd /d "%~dp0"
if not exist "build\windows\x64\runner\Release\nightshade_desktop.exe" (
    echo ERROR: Executable not found!
    echo Please build the app first with: flutter build windows --target=lib/main_headless.dart
    pause
    exit /b 1
)

echo Running: build\windows\x64\runner\Release\nightshade_desktop.exe
echo.
echo NOTE: If you don't see output below, the app may be running but
echo       Flutter Windows apps don't show console output by default.
echo       Check Task Manager to see if the process is running.
echo.
echo ========================================
echo.

build\windows\x64\runner\Release\nightshade_desktop.exe

echo.
echo ========================================
echo Server stopped.
pause

