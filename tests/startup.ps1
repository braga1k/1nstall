# Measures the actual native executable through its first rendered, idle UI.
param([string]$Executable=(Join-Path (Split-Path $PSScriptRoot) 'dist/1nstall.exe'), [int]$Samples=5)
$ErrorActionPreference='Stop'
$exe=(Resolve-Path -LiteralPath $Executable).Path
$log=Join-Path (Split-Path $exe) 'startup-test.log'
$rows=@()
for ($i=0;$i -lt $Samples;$i++) {
    $process=Start-Process -FilePath $exe -ArgumentList '--startup-test' -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(20000)) { $process.Kill(); throw 'Startup exceeded 20 seconds.' }
    if ($process.ExitCode -ne 0) { throw (Get-Content (Join-Path (Split-Path $exe) '1nstall-startup-error.log') -Raw) }
    $ready=@(Get-Content -LiteralPath $log | Where-Object { $_ -match '^READY [0-9]+$' })
    if ($ready.Count -ne 1) { throw 'Missing readiness measurement.' }
    $rows += [pscustomobject]@{Sample=$i+1;ReadyMs=[long]($ready[0].Substring(6))}
}
$output=Join-Path (Split-Path $exe) 'startup-timings.json'
$rows | ConvertTo-Json | Set-Content -LiteralPath $output -Encoding UTF8
$rows | Format-Table -AutoSize
