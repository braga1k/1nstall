# Runs one test on GitHub Actions and reports it as annotations of the run: one notice with
# the totals, one notice per NOTE line and one error per FAIL line. The whole output goes to
# the log. A failed test also leaves a marker file, so that a last step can fail the job after
# every test has had its turn.
#   .\app\tests\report.ps1 -Title 'queue ui (windows-2025)' -Test { .\app\tests\queue-ui.ps1 -Exe ... }
param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][scriptblock]$Test, [string]$Markers='test-failures')
$ErrorActionPreference='Continue'
function Short([string]$text,[int]$length=900) { $flat=($text -replace '\s+',' ').Trim(); if ($flat.Length -gt $length) { $flat.Substring(0,$length) } else { $flat } }
$problem=$null
$global:LASTEXITCODE=0
# Lines are kept as they come, so that a test that stops early still reports what it did.
$lines=New-Object 'System.Collections.Generic.List[string]'
try { & $Test 2>&1 | ForEach-Object { $lines.Add("$_") } } catch { $problem="$_ [$((([string]$_.ScriptStackTrace) -split "`n" | Select-Object -First 3 | ForEach-Object { ($_ -replace '^at ','' -replace '[A-Za-z]:\\[^:]*\\','').Trim() }) -join ' < ')]" }
$code=$LASTEXITCODE
$lines | ForEach-Object { Write-Output $_ }
$passed=@($lines | Where-Object { $_ -like 'PASS *' }).Count
$failures=@($lines | Where-Object { $_ -like 'FAIL *' })
$notes=@($lines | Where-Object { $_ -like 'NOTE *' })
Write-Output "::notice title=$Title::$passed passed, $($failures.Count) failed$(if ($problem) { '; stopped early' })"
$notes | Select-Object -First 9 | ForEach-Object { Write-Output "::notice title=$Title::$(Short $_.Substring(5))" }
$failures | Select-Object -First 8 | ForEach-Object { Write-Output "::error title=$Title::$(Short $_.Substring(5))" }
if ($problem) { Write-Output "::error title=$Title::stopped: $(Short $problem)" }
if ($failures.Count -or $problem -or $code -ne 0 -or $passed -eq 0) {
    if (-not $failures.Count -and -not $problem) { Write-Output "::error title=$Title::ended with exit code $code and $passed checks passed: $(Short (($lines | Select-Object -Last 3) -join ' / '))" }
    New-Item -ItemType Directory -Path $Markers -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Markers (($Title -replace '[^A-Za-z0-9]+','-')+'.txt')) -Value 'failed'
    exit 1
}
