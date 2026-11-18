param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$Out, [int]$Fresh=3, [int]$Warm=10)
# Runs "<exe> --startup-test" repeatedly. Records the app's own timings, external wall-clock time and peak memory.
# "fresh" = runtime-cache folder beside the exe deleted first (helper DLLs re-extracted); "warm" = cache kept.
$ErrorActionPreference='Stop'
$exe=(Resolve-Path -LiteralPath $Exe).Path
$dir=Split-Path $exe
$log=Join-Path $dir 'startup-test.log'
$cache=Join-Path $dir 'runtime-cache'
function Run-Once([string]$kind,[int]$n) {
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $p=Start-Process -FilePath $exe -ArgumentList '--startup-test' -PassThru
    $peakWs=0L; $peakPrivate=0L
    while (-not $p.HasExited) {
        if ($clock.ElapsedMilliseconds -gt 60000) { $p.Kill(); throw "Run exceeded 60 s ($kind $n)." }
        try { $p.Refresh(); if ($p.PeakWorkingSet64 -gt $peakWs) { $peakWs=$p.PeakWorkingSet64 }; if ($p.PrivateMemorySize64 -gt $peakPrivate) { $peakPrivate=$p.PrivateMemorySize64 } } catch { }
        Start-Sleep -Milliseconds 15
    }
    $wall=$clock.ElapsedMilliseconds
    $row=[ordered]@{Kind=$kind; Sample=$n; ExitCode=$p.ExitCode; WallMs=$wall; PeakWorkingSetMB=[math]::Round($peakWs/1MB,1); PeakPrivateMB=[math]::Round($peakPrivate/1MB,1)}
    if (Test-Path -LiteralPath $log) {
        foreach ($line in Get-Content -LiteralPath $log) {
            if ($line -match '^(READY|FirstFrameMs|BeforeShowMs|LoadedMs|RenderMs) ([0-9]+)$') { $row[$(if ($Matches[1] -eq 'READY') { 'ReadyMs' } else { $Matches[1] })]=[long]$Matches[2] }
        }
    }
    [pscustomobject]$row
}
$rows=@()
for ($i=1; $i -le $Fresh; $i++) { if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Recurse -Force }; $rows+=Run-Once 'fresh' $i }
for ($i=1; $i -le $Warm; $i++) { $rows+=Run-Once 'warm' $i }
$os=Get-CimInstance Win32_OperatingSystem; $cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
$meta=[ordered]@{ExeBytes=(Get-Item -LiteralPath $exe).Length; ExeSha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant(); MeasuredAt=(Get-Date).ToString('s'); OS=$os.Caption+' '+$os.Version; Cpu=$cpu.Name.Trim(); LogicalCores=$cpu.NumberOfLogicalProcessors; RamGB=[math]::Round($os.TotalVisibleMemorySize/1MB,1)}
[ordered]@{Meta=$meta; Runs=$rows} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Out -Encoding UTF8
$rows | Format-Table -AutoSize | Out-String -Width 200
