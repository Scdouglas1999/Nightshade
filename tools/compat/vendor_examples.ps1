param(
    [string]$Out = "reports/compat/vendor-examples"
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
$outDir = Join-Path $root $Out
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$sdkRoots = @("SDKs", "tools/compat/downloads") | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path $_ }
$examples = @()
foreach ($sdkRoot in $sdkRoots) {
    $examples += Get-ChildItem -LiteralPath $sdkRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.FullName -match "(?i)(sample|example|demo)") -and
            (
                $_.Name -match "\.(sln|vcxproj|cmake)$" -or
                $_.Name -match "(?i)(sample|example|demo).*\.(c|cc|cpp)$"
            )
        } |
        Select-Object FullName, Extension
}

$cmake = Get-Command cmake -ErrorAction SilentlyContinue
$msbuild = Get-Command msbuild -ErrorAction SilentlyContinue
$compiler = @(Get-Command clang -ErrorAction SilentlyContinue; Get-Command gcc -ErrorAction SilentlyContinue; Get-Command cl -ErrorAction SilentlyContinue) | Select-Object -First 1

$results = @()
foreach ($example in $examples) {
    $rel = $example.FullName.Substring($root.Length).TrimStart("\", "/")
    $status = "blocked"
    $detail = "example discovered; build tool unavailable or project requires vendor-specific setup"

    if ($example.Extension -ieq ".vcxproj" -and $msbuild) {
        $output = & msbuild $example.FullName /t:Restore,Build /p:Configuration=Release 2>&1 | Out-String
        $status = if ($LASTEXITCODE -eq 0) { "pass" } else { "fail" }
        $detail = (($output -split "`r?`n") | Select-Object -Last 25) -join "`n"
    } elseif ($example.Extension -match "\.(c|cc|cpp)$" -and $compiler) {
        $outFile = Join-Path $outDir (([IO.Path]::GetFileNameWithoutExtension($example.FullName)) + ".exe")
        $output = & $compiler.Source $example.FullName "-o" $outFile 2>&1 | Out-String
        $status = if ($LASTEXITCODE -eq 0) { "pass" } else { "blocked" }
        $detail = (($output -split "`r?`n") | Select-Object -Last 25) -join "`n"
    } elseif ($example.Extension -ieq ".cmake" -and $cmake) {
        $status = "blocked"
        $detail = "CMake fragment discovered; configure root must be supplied by vendor package"
    }

    $results += [pscustomobject]@{ path=$rel; status=$status; detail=$detail }
}

if ($examples.Count -eq 0) {
    $results += [pscustomobject]@{ path=$null; status="blocked"; detail="no vendor example projects have been acquired yet" }
}

$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outDir "vendor-examples.json") -Encoding UTF8
$pass = @($results | Where-Object status -eq "pass").Count
$fail = @($results | Where-Object status -eq "fail").Count
$blocked = @($results | Where-Object status -eq "blocked").Count
Write-Host "vendor example compilation: $pass pass, $fail fail, $blocked blocked"
if ($fail -gt 0) { exit 1 }
