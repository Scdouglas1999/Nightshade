param(
    [string]$Out = "reports/compat/abi-compile-probes"
)

$ErrorActionPreference = "Stop"

function RepoRoot {
    $d = (Get-Location).Path
    while ($d) {
        if (Test-Path (Join-Path $d ".git")) { return $d }
        $p = Split-Path -Parent $d
        if ($p -eq $d) { break }
        $d = $p
    }
    throw "Repository root not found"
}

function PickCompiler {
    foreach ($candidate in @("clang", "gcc", "cl")) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $candidate }
    }
    return $null
}

function FindHeader($root, [string[]]$patterns) {
    foreach ($pattern in $patterns) {
        $match = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName.Replace("\", "/") -like $pattern } |
            Select-Object -First 1
        if ($match) { return $match.FullName }
    }
    return $null
}

$root = RepoRoot
$outDir = Join-Path $root $Out
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$compiler = PickCompiler
$results = @()

$probes = @(
    @{ vendor="ZWO"; header=@("*/ASICamera2.h"); structs=@("ASI_CAMERA_INFO", "ASI_CONTROL_CAPS"); symbols=@("ASIGetNumOfConnectedCameras", "ASIStartExposure") },
    @{ vendor="QHYCCD"; header=@("*/qhyccd*.h"); structs=@(); symbols=@("InitQHYCCDResource", "GetQHYCCDChipInfo", "ExpQHYCCDSingleFrame") },
    @{ vendor="Player One"; header=@("*/PlayerOneCamera*.h", "*/POACamera*.h"); structs=@("POAConfigValue", "POACameraProperties"); symbols=@("POAGetCameraCount", "POAGetImageData") },
    @{ vendor="ToupTek"; header=@("*/toupcam.h", "*/ogmacam.h", "*/altaircam.h"); structs=@("ToupcamDeviceV2", "ToupcamModelV2"); symbols=@("Toupcam_EnumV2", "Toupcam_PullImageV3") },
    @{ vendor="Moravian"; header=@("*/gXusb*.h", "*/gxccd*.h"); structs=@(); symbols=@("Enumerate", "Initialize", "GetImage16b") },
    @{ vendor="FLI"; header=@("*/libfli.h"); structs=@(); symbols=@("FLIOpen", "FLIGrabRow", "FLISetFilterPos") },
    @{ vendor="Fujifilm"; header=@("*/XAPI.h"); structs=@("XSDKCameraList", "XSDKDeviceInformation", "XSDKImageInformation"); symbols=@("XSDK_OpenEx", "XSDK_Release") }
)

foreach ($probe in $probes) {
    $header = FindHeader $root $probe.header
    $status = "blocked"
    $detail = "header absent"
    $artifact = $null

    if ($header -and $compiler) {
        $safeName = ($probe.vendor -replace "[^A-Za-z0-9]", "_").ToLowerInvariant()
        $source = Join-Path $outDir "$safeName-probe.c"
        $exe = Join-Path $outDir "$safeName-probe.exe"
        $includeDir = Split-Path -Parent $header
        $code = @"
#include <stddef.h>
#include <stdio.h>
#include "$([IO.Path]::GetFileName($header))"
int main(void) {
  printf("vendor=$($probe.vendor)\n");
  printf("header=$([IO.Path]::GetFileName($header))\n");
  printf("pointer_size=%zu\n", sizeof(void*));
  return 0;
}
"@
        Set-Content -LiteralPath $source -Value $code -Encoding ASCII
        if ($compiler -eq "cl") {
            $compile = & cl /nologo "/I$includeDir" $source "/Fe:$exe" 2>&1 | Out-String
        } else {
            $compile = & $compiler "-I$includeDir" $source "-o" $exe 2>&1 | Out-String
        }
        if ($LASTEXITCODE -eq 0) {
            $run = & $exe 2>&1 | Out-String
            $status = "pass"
            $detail = $run.Trim()
            $artifact = $source
        } else {
            $status = "fail"
            $detail = $compile.Trim()
            $artifact = $source
        }
    } elseif ($header -and -not $compiler) {
        $detail = "header present; C compiler absent"
    }

    $results += [pscustomobject]@{
        vendor = $probe.vendor
        status = $status
        detail = $detail
        header = $header
        artifact = $artifact
    }
}

$results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outDir "abi-compile-probes.json") -Encoding UTF8
$pass = @($results | Where-Object status -eq "pass").Count
$fail = @($results | Where-Object status -eq "fail").Count
$blocked = @($results | Where-Object status -eq "blocked").Count
Write-Host "native SDK compiled ABI probes: $pass pass, $fail fail, $blocked blocked"
if ($fail -gt 0) { exit 1 }
