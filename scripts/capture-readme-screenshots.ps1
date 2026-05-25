# Captures README screenshots from a built Windows desktop app and headless web dashboard.
# Requires: Release (or Debug) build at apps/desktop/build/windows/x64/runner/*/nightshade_desktop.exe
#
# Usage:
#   .\scripts\capture-readme-screenshots.ps1
#   .\scripts\capture-readme-screenshots.ps1 -Configuration Debug

param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',
    [switch]$SkipBuild,
    [switch]$SkipWeb
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$DesktopDir = Join-Path $ProjectRoot 'apps\desktop'
$Exe = Join-Path $DesktopDir "build\windows\x64\runner\$Configuration\nightshade_desktop.exe"
$OutDir = Join-Path $ProjectRoot 'assets\screenshots'
$HeadlessLog = Join-Path $env:TEMP 'nightshade-headless-screenshot.log'

if (-not $SkipBuild) {
    Write-Host '==> Building desktop app (NoRun, SkipFrb)...' -ForegroundColor Cyan
    & (Join-Path $ProjectRoot 'scripts\dev.ps1') -NoRun -SkipFrb
}

if (-not (Test-Path $Exe)) {
    throw "Executable not found: $Exe"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$DrawingDll = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\System.Drawing.dll'
$FormsDll = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\System.Windows.Forms.dll'
if (-not (Test-Path $DrawingDll)) {
    throw "System.Drawing.dll not found at $DrawingDll"
}

Add-Type @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class WinCapture {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern void SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int cButtons, int dwExtraInfo);
  public const int SW_RESTORE = 9;
  public const int MOUSEEVENTF_LEFTDOWN = 0x0002;
  public const int MOUSEEVENTF_LEFTUP = 0x0004;
  public const int MOUSEEVENTF_WHEEL = 0x0800;
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public static IntPtr FindByTitleSubstring(string needle) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((hWnd, lParam) => {
      if (!IsWindowVisible(hWnd)) return true;
      var sb = new StringBuilder(512);
      GetWindowText(hWnd, sb, sb.Capacity);
      var title = sb.ToString();
      if (title.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0) {
        found = hWnd;
        return false;
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
  public static void Click(int x, int y) {
    SetCursorPos(x, y);
    Thread.Sleep(80);
    mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
    mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
    Thread.Sleep(120);
  }
  public static void Wheel(int x, int y, int delta) {
    SetCursorPos(x, y);
    Thread.Sleep(60);
    mouse_event(MOUSEEVENTF_WHEEL, 0, 0, delta, 0);
    Thread.Sleep(150);
  }
  public static void CaptureWindow(IntPtr hWnd, string path) {
    ShowWindow(hWnd, SW_RESTORE);
    SetForegroundWindow(hWnd);
    Thread.Sleep(400);
    RECT r;
    if (!GetWindowRect(hWnd, out r)) throw new Exception("GetWindowRect failed");
    int w = r.Right - r.Left;
    int h = r.Bottom - r.Top;
    if (w < 200 || h < 200) throw new Exception("Window too small: " + w + "x" + h);
    using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
    using (var g = Graphics.FromImage(bmp)) {
      g.CopyFromScreen(r.Left, r.Top, 0, 0, new Size(w, h), CopyPixelOperation.SourceCopy);
      bmp.Save(path, ImageFormat.Png);
    }
  }
}
"@ -ReferencedAssemblies @($DrawingDll, $FormsDll)

function Get-AppWindowHandle {
    param([System.Diagnostics.Process]$Process)
    $h = $Process.MainWindowHandle
    if ($h -ne [IntPtr]::Zero) { return $h }
    # Flutter may register the HWND shortly after process start.
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        $Process.Refresh()
        $h = $Process.MainWindowHandle
        if ($h -ne [IntPtr]::Zero) { return $h }
    }
    throw "Nightshade process started but no main window handle (pid $($Process.Id))"
}

function Wait-AppProcess {
    param(
        [int]$ParentPid,
        [int]$TimeoutSec = 90
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $proc = Get-Process -Name 'nightshade_desktop' -ErrorAction SilentlyContinue |
            Where-Object { $_.Id -ne $ParentPid -or $_.MainWindowHandle -ne 0 } |
            Sort-Object StartTime -Descending |
            Select-Object -First 1
        if ($proc) { return $proc }
        Start-Sleep -Milliseconds 400
    }
    throw 'Timed out waiting for nightshade_desktop process'
}

function Get-WindowRect {
    param([IntPtr]$Window)
    $rect = New-Object WinCapture+RECT
    [void][WinCapture]::GetWindowRect($Window, [ref]$rect)
    return $rect
}

function Click-SidebarIndex {
    param(
        [IntPtr]$Window,
        [int]$Index
    )
    [WinCapture]::ShowWindow($Window, [WinCapture]::SW_RESTORE) | Out-Null
    [WinCapture]::SetForegroundWindow($Window) | Out-Null
    Start-Sleep -Milliseconds 300
    $rect = Get-WindowRect -Window $Window
    $x = $rect.Left + 110
    # Expanded nav rows are ~56px; title chrome ~96px before first item.
    $y = $rect.Top + 96 + ($Index * 56)
    [WinCapture]::Click($x, $y)
    Start-Sleep -Seconds 2
}

function Scroll-Sidebar {
    param([IntPtr]$Window, [int]$Steps = 3)
    $rect = Get-WindowRect -Window $Window
    $x = $rect.Left + 110
    $y = [int]($rect.Top + ($rect.Bottom - $rect.Top) * 0.45)
    for ($i = 0; $i -lt $Steps; $i++) {
        [WinCapture]::Wheel($x, $y, -240)
    }
    Start-Sleep -Milliseconds 400
}

function Dismiss-Overlays {
    param([IntPtr]$Window)
    $rect = Get-WindowRect -Window $Window
    # Weather banner snooze (top-right of banner)
    [WinCapture]::Click([int]($rect.Right - 120), [int]($rect.Top + 72))
    Start-Sleep -Milliseconds 400
    # Tutorial / tour "Maybe later" (bottom-right card)
    [WinCapture]::Click(
        [int]($rect.Left + ($rect.Right - $rect.Left) * 0.78),
        [int]($rect.Top + ($rect.Bottom - $rect.Top) * 0.82))
    Start-Sleep -Milliseconds 400
}

function Dismiss-WelcomeIfPresent {
    param([IntPtr]$Window)
    $rect = New-Object WinCapture+RECT
    [void][WinCapture]::GetWindowRect($Window, [ref]$rect)
    $cx = [int](($rect.Left + $rect.Right) / 2)
    $cy = [int]($rect.Top + ($rect.Bottom - $rect.Top) * 0.62)
    [WinCapture]::Click($cx, $cy)
    Start-Sleep -Seconds 2
}

Write-Host '==> Launching Nightshade desktop...' -ForegroundColor Cyan
$app = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe) -PassThru
try {
    $proc = Wait-AppProcess -ParentPid $app.Id
    $hwnd = Get-AppWindowHandle -Process $proc
    Write-Host ("  window: pid={0} title='{1}'" -f $proc.Id, $proc.MainWindowTitle) -ForegroundColor DarkGray
    Start-Sleep -Seconds 4
    Dismiss-WelcomeIfPresent -Window $hwnd
    Dismiss-WelcomeIfPresent -Window $hwnd

    Click-SidebarIndex -Window $hwnd -Index 0
    Start-Sleep -Seconds 1
    Dismiss-Overlays -Window $hwnd
    $dash = Join-Path $OutDir 'desktop-dashboard.png'
    [WinCapture]::CaptureWindow($hwnd, $dash)
    Write-Host "  saved $dash" -ForegroundColor Green

    Click-SidebarIndex -Window $hwnd -Index 4
    Dismiss-Overlays -Window $hwnd
    $seq = Join-Path $OutDir 'sequencer.png'
    [WinCapture]::CaptureWindow($hwnd, $seq)
    Write-Host "  saved $seq" -ForegroundColor Green

    Click-SidebarIndex -Window $hwnd -Index 0
    Start-Sleep -Seconds 1
    Click-SidebarIndex -Window $hwnd -Index 10
    Dismiss-Overlays -Window $hwnd
    $plan = Join-Path $OutDir 'plan-tonight.png'
    [WinCapture]::CaptureWindow($hwnd, $plan)
    Write-Host "  saved $plan" -ForegroundColor Green
}
finally {
    if (-not $app.HasExited) {
        Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
    }
}

if (-not $SkipWeb) {
    Write-Host '==> Capturing web dashboard (headless)...' -ForegroundColor Cyan
    $HeadlessErr = Join-Path $env:TEMP 'nightshade-headless-screenshot.err.log'
    if (Test-Path $HeadlessLog) { Remove-Item $HeadlessLog -Force }
    if (Test-Path $HeadlessErr) { Remove-Item $HeadlessErr -Force }
    $headless = Start-Process -FilePath $Exe `
        -ArgumentList '--headless', '--allow-unauthenticated-lan' `
        -WorkingDirectory (Split-Path $Exe) `
        -RedirectStandardOutput $HeadlessLog `
        -RedirectStandardError $HeadlessErr `
        -PassThru `
        -WindowStyle Hidden

    try {
        $ready = $false
        foreach ($i in 1..90) {
            Start-Sleep -Seconds 1
            try {
                $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/dashboard/' -UseBasicParsing -TimeoutSec 3
                if ($r.StatusCode -eq 200) { $ready = $true; break }
            } catch { }
        }
        if (-not $ready) { throw 'Headless server did not become ready on port 8080' }

        Start-Sleep -Seconds 4
        $webOut = Join-Path $OutDir 'web-dashboard.png'

        $edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
        if (-not (Test-Path $edge)) { $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
        if (Test-Path $edge) {
            & $edge --headless=new --disable-gpu --window-size=1600,900 "--screenshot=$webOut" 'http://127.0.0.1:8080/dashboard/' 2>$null
        }
        if (-not (Test-Path $webOut)) {
            Write-Warning 'Web screenshot via Edge headless failed. Start headless manually, open http://127.0.0.1:8080/dashboard/, and save a PNG to assets/screenshots/web-dashboard.png.'
        } else {
            Write-Host "  saved $webOut" -ForegroundColor Green
        }
    }
    finally {
        if (-not $headless.HasExited) {
            Stop-Process -Id $headless.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host '==> Done.' -ForegroundColor Cyan
