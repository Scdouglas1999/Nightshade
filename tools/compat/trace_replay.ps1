param(
    [string]$TraceDir = "tools/compat/traces",
    [string]$Out = "reports/compat/trace-replay"
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

$root = RepoRoot
$tracePath = Join-Path $root $TraceDir
$outDir = Join-Path $root $Out
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path $tracePath | Out-Null

$results = @()
$traces = @(Get-ChildItem -LiteralPath $tracePath -Filter "*.json" -File -ErrorAction SilentlyContinue)
foreach ($trace in $traces) {
    try {
        $doc = Get-Content -LiteralPath $trace.FullName -Raw | ConvertFrom-Json
        $missing = @()
        foreach ($field in @("vendor", "driver_type", "device_type", "events")) {
            if (-not $doc.PSObject.Properties[$field]) { $missing += $field }
        }
        if ($missing.Count -gt 0) {
            $results += [pscustomobject]@{ trace=$trace.Name; status="fail"; detail="missing fields: $($missing -join ', ')" }
            continue
        }
        $eventCount = @($doc.events).Count
        if ($eventCount -eq 0) {
            $results += [pscustomobject]@{ trace=$trace.Name; status="fail"; detail="trace contains no events" }
            continue
        }
        $results += [pscustomobject]@{ trace=$trace.Name; status="pass"; detail="$eventCount events validated for $($doc.vendor) $($doc.driver_type)" }
    } catch {
        $results += [pscustomobject]@{ trace=$trace.Name; status="fail"; detail=$_.Exception.Message }
    }
}

if ($traces.Count -eq 0) {
    $results += [pscustomobject]@{ trace=$null; status="blocked"; detail="trace harness ready; no captured real-device traces have been supplied" }
}

$results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outDir "trace-replay.json") -Encoding UTF8
$pass = @($results | Where-Object status -eq "pass").Count
$fail = @($results | Where-Object status -eq "fail").Count
$blocked = @($results | Where-Object status -eq "blocked").Count
Write-Host "record/replay trace validation: $pass pass, $fail fail, $blocked blocked"
if ($fail -gt 0) { exit 1 }
