# Disposable native regression: our GUID-owned registrations and executable only.
param([switch]$DisposableEnvironment)
if (-not $DisposableEnvironment) { throw 'Run only in a disposable Windows VM/Sandbox with -DisposableEnvironment.' }
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $repo 'src/uninstall-helper.cs'))) -ReferencedAssemblies System.dll,System.Core.dll,System.Web.Extensions.dll
$token='1nstallQueue_'+[guid]::NewGuid().ToString('N')
$fixture=Join-Path ([IO.Path]::GetTempPath()) $token
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$exe=Join-Path $fixture 'publisher.exe'
$code=@'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using Microsoft.Win32;
class Publisher {
    static int Main(string[] args) {
        string root=AppDomain.CurrentDomain.BaseDirectory, key=args[1];
        if (!Path.GetFileName(root.TrimEnd('\\')).StartsWith("1nstallQueue_")) return 1;
        if (args[0]=="root" || args[0]=="child") {
            if (args[0]=="root") File.WriteAllText(Path.Combine(root,key+".started"),"started");
            var start=new ProcessStartInfo(Path.Combine(root,"publisher.exe"),(args[0]=="root"?"child":"leaf")+" "+key) { UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden };
            using (var child=Process.Start(start)) { if (args[0]=="child") Thread.Sleep(400); }
            return 0;
        }
        // Registration disappears before disk cleanup finishes; the queue must still wait.
        if (!key.EndsWith("cancel")) Registry.CurrentUser.DeleteSubKeyTree(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\"+key,false);
        File.WriteAllText(Path.Combine(root,key+".working"),"working");
        Thread.Sleep(5000);
        File.WriteAllText(Path.Combine(root,key+".finished"),"finished");
        return key.EndsWith("cancel")?1602:0;
    }
}
'@
Add-Type -TypeDefinition $code -OutputAssembly $exe -OutputType ConsoleApplication
$keys=@()
$savedHistory=if (Test-Path -LiteralPath ([OneInstallUninstall]::HistoryFile)) { [IO.File]::ReadAllBytes([OneInstallUninstall]::HistoryFile) } else { $null }
function Register([string]$Suffix) {
    $key=$token+$Suffix; $script:keys+=,$key
    $path='Software\Microsoft\Windows\CurrentVersion\Uninstall\'+$key
    $reg=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path)
    try { $reg.SetValue('DisplayName',$key); $reg.SetValue('UninstallString','"'+$exe+'" root '+$key); $reg.SetValue('InstallLocation',$fixture) } finally { $reg.Dispose() }
    $app=New-Object InstalledApp; $app.Id='HKCU64:'+$key; $app.Name=$key; $app.Kind='Desktop'; $app.RegistryPath=$path; $app.CanRemove=$true; $app.Selected=$true
    return $app
}
function Wait-Working($App,$Task) {
    $marker=Join-Path $fixture ($App.Name+'.working'); $until=[DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path -LiteralPath $marker) -and [DateTime]::UtcNow -lt $until) { if ($Task.IsCompleted) { throw 'Removal completed before child started.' }; Start-Sleep -Milliseconds 50 }
    if (-not (Test-Path -LiteralPath $marker) -or $Task.IsCompleted) { throw 'Publisher fixture failed to remain active.' }
}
try {
    $first=Register 'first'; $second=Register 'second'
    $task=[OneInstallUninstall]::RemoveAsync([InstalledApp[]]@($first,$second)); Wait-Working $first $task
    if (-not $first.Selected -or -not $second.Selected) { throw 'Recording history deselected live queue models.' }
    Start-Sleep -Milliseconds 1200
    if ($task.IsCompleted -or (Test-Path -LiteralPath (Join-Path $fixture ($second.Name+'.started')))) { throw 'Queue advanced while a descendant was still removing files.' }
    if (-not $task.Wait(60000)) { throw 'Sequential removal timed out.' }
    if (-not $first.Selected -or -not $second.Selected -or @([OneInstallUninstall]::LoadHistory() | Where-Object Selected).Count -gt 0) { throw 'Live selection was cleared or persisted into history.' }
    if (@($task.Result.Results | Where-Object Outcome -ne 'Success').Count -gt 0 -or -not (Test-Path -LiteralPath (Join-Path $fixture ($second.Name+'.finished')))) { throw 'Completed descendants were not verified.' }
    $events=@(); $event=$null; while ([OneInstallUninstall]::Stages.TryDequeue([ref]$event)) { $events+=,$event }
    foreach ($app in @($first,$second)) {
        $states=@($events | Where-Object Id -eq $app.Id | ForEach-Object Outcome)
        if (($states -join '|') -ne ('Preparing'+[char]0x2026+'|Removing'+[char]0x2026+'|Verifying'+[char]0x2026+'|Success')) { throw 'Incorrect per-app stage sequence.' }
    }
    $current=Register 'stopCurrent'; $next=Register 'notStarted'
    $task=[OneInstallUninstall]::RemoveAsync([InstalledApp[]]@($current,$next)); Wait-Working $current $task
    [OneInstallUninstall]::StopRequested=$true
    if ($task.IsCompleted -or -not $task.Wait(60000) -or $task.Result.Results[0].Outcome -ne 'Success' -or $task.Result.Results[1].Outcome -ne 'Cancelled' -or (Test-Path -LiteralPath (Join-Path $fixture ($next.Name+'.started')))) { throw 'Stop did not wait for current child and keep the next app.' }
    $cancel=Register 'cancel'
    $task=[OneInstallUninstall]::RemoveAsync([InstalledApp[]]@($cancel))
    if (-not $task.Wait(60000) -or $task.Result.Results[0].Outcome -ne 'Manual action required' -or $cancel.RemovalVerified) { throw 'Cancelled child was incorrectly reported as success.' }
    Write-Output 'PASS: native launcher/child/grandchild completion, early registration removal, sequential queue, phase events, stop-after-current and cancelled child without false success.'
} finally {
    foreach ($key in $keys) { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree(('Software\Microsoft\Windows\CurrentVersion\Uninstall\'+$key),$false) }
    if ($null -ne $savedHistory) { [IO.File]::WriteAllBytes([OneInstallUninstall]::HistoryFile,$savedHistory) }
    else { [IO.File]::Delete([OneInstallUninstall]::HistoryFile) }
    $resolved=[IO.Path]::GetFullPath($fixture)
    if ([IO.Path]::GetFileName($resolved) -ne $token -or -not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture cleanup boundary failed.' }
    # Allow our short-lived fixture descendants to exit even if an assertion failed.
    Start-Sleep -Seconds 6
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
