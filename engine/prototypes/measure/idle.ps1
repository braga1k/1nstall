# Starts a prototype normally, lets it settle, and reports the memory of its whole process tree at rest.
param([Parameter(Mandatory)][string]$Exe, [string]$Arguments='', [int]$SettleMs=8000)
$ErrorActionPreference='Stop'
$exe=(Resolve-Path -LiteralPath $Exe).Path
$startInfo=@{FilePath=$exe; PassThru=$true}; if ($Arguments) { $startInfo.ArgumentList=$Arguments }
$process=Start-Process @startInfo
try {
    Start-Sleep -Milliseconds $SettleMs
    $all=Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId
    $tree=@($process.Id); do { $more=@($all | Where-Object { $tree -contains $_.ParentProcessId -and $tree -notcontains $_.ProcessId } | ForEach-Object { [int]$_.ProcessId }); $tree+=$more } while ($more.Count)
    $working=0L; $private=0L
    foreach ($id in $tree) { try { $item=Get-Process -Id $id; $working+=$item.WorkingSet64; $private+=$item.PrivateMemorySize64 } catch { } }
    [pscustomobject]@{Exe=Split-Path $exe -Leaf; Arguments=$Arguments; Processes=$tree.Count; IdleWorkingSetMB=[math]::Round($working/1MB,1); IdlePrivateMB=[math]::Round($private/1MB,1)} | ConvertTo-Json -Compress
} finally {
    if (-not $process.HasExited) { $process.CloseMainWindow() | Out-Null; if (-not $process.WaitForExit(3000)) { $process.Kill() } }
}
