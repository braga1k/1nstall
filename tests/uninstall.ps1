# Native integration check. Only the newly created GUID fixture is modified; no app is uninstalled.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $root 'src\uninstall-helper.cs'))) -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll')
[OneInstallUninstall]::SelfTest()
function Wait-Check($Task) {
    if (-not $Task.Wait(90000)) { throw 'Native check timed out.' }
    return $Task.Result
}
$inventory=Wait-Check ([OneInstallUninstall]::InventoryAsync())
if ($inventory.Apps.Count -eq 0 -or @($inventory.Apps | Where-Object { -not $_.Name -or -not $_.Id }).Count -gt 0) { throw 'Installed inventory is empty or invalid.' }
Write-Output ('Inventory: {0} desktop, {1} Store, {2} warnings.' -f @($inventory.Apps | Where-Object Kind -eq 'Desktop').Count,@($inventory.Apps | Where-Object Kind -eq 'Microsoft Store').Count,$inventory.Warnings.Count)
foreach ($warning in $inventory.Warnings) { Write-Output $warning }
$name='1nstallFixture_'+[Guid]::NewGuid().ToString('N')
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) $name
$folder=Join-Path $fixtureRoot $name
$key='Software\'+$name
$registryFixture='HKCU:\'+$key
$backupFolder=$null
$product=$name+' Editor'
$vendor='1nstallVendor_'+[Guid]::NewGuid().ToString('N')
$dataRoot=Join-Path $env:LOCALAPPDATA $vendor
$dataFolder=Join-Path (Join-Path $dataRoot 'Settings') $product
$nestedKey='Software\'+$vendor+'\Settings\'+$product
$traceKey='Software\Microsoft\Windows\CurrentVersion\Search\JumplistData'
$traceValue=Join-Path $folder 'application.exe'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $folder 'fixture.txt'),'Disposable fixture, created by tests/uninstall.ps1.')
New-Item -Path $registryFixture -Force | Out-Null
New-ItemProperty -Path $registryFixture -Name Fixture -Value 'backup-me' -Force | Out-Null
New-Item -ItemType Directory -Path $dataFolder -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $dataFolder 'settings.ini'),'Disposable nested product fixture.')
New-Item -Path ('HKCU:\'+$nestedKey) -Force | Out-Null
New-ItemProperty -Path ('HKCU:\'+$nestedKey) -Name Fixture -Value 'nested-backup' -Force | Out-Null
$trace=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($traceKey,$true)
$sentinel=Join-Path ($folder+'Sibling') 'application.exe'
if ($trace) { $trace.SetValue($traceValue,42); $trace.SetValue($sentinel,7) }
try {
    $app=New-Object InstalledApp; $app.Name=$product+' v2.0'; $app.Publisher='A different recorded publisher'; $app.Kind='Desktop'; $app.Location=$folder
    $app.Id=$name; $app.RegistryPath='Software\Microsoft\Windows\CurrentVersion\Uninstall\'+$name
    $scan=Wait-Check ([OneInstallUninstall]::ScanAsync([InstalledApp[]]@($app)))
    $items=[LeftoverItem[]]@($scan.Leftovers | Where-Object { $_.Path -eq $folder -or ($_.Path -eq $key -and -not $_.Machine) })
    if ($items.Count -ne 2) { throw ('Fixture scan missed a disk/registry item: '+($scan.Messages -join ', ')) }
    $nested=[LeftoverItem[]]@($scan.Leftovers | Where-Object { $_.Path -eq $dataFolder -or ($_.Path -eq $nestedKey -and -not $_.Machine) })
    if ($nested.Count -ne 2) { throw 'Nested product discovery failed when publisher/path names differ.' }
    if ($trace) {
        $traceItems=[LeftoverItem[]]@($scan.Leftovers | Where-Object { $_.Path -eq $traceKey -and $_.ValueName -eq $traceValue -and -not $_.Machine })
        if ($traceItems.Count -ne 1 -or [OneInstallUninstall]::SafeRegistryValue($traceKey,$sentinel,$app,[InstalledApp[]]@())) { throw 'Exact registry-value path boundary failed.' }
        if ([OneInstallUninstall]::SafeRegistryValue($traceKey,$traceValue,$app,[InstalledApp[]]@($app))) { throw 'Registered/shared product trace was accepted.' }
        $items=[LeftoverItem[]]@($items+$traceItems)
    }
    $cleanup=Wait-Check ([OneInstallUninstall]::CleanAsync($items))
    $backupFolder=$cleanup.BackupFolder
    if ((Test-Path -LiteralPath $folder) -or (Test-Path -LiteralPath $registryFixture)) { throw ('Fixture cleanup failed: '+($cleanup.Messages -join ', ')) }
    $exports=@(Get-ChildItem -LiteralPath $backupFolder -Filter *.reg)
    if ($exports.Count -ne $(if ($trace) { 2 } else { 1 }) -or -not (($exports | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join '').Contains('backup-me')) { throw 'Registry export did not preserve the fixture value.' }
    if ($trace -and ($trace.GetValue($traceValue) -ne $null -or $trace.GetValue($sentinel) -ne 7)) { throw 'Value cleanup did not preserve the shared key and sibling value.' }
    if (-not (Test-Path -LiteralPath (Join-Path $backupFolder 'RESTORE.txt'))) { throw 'Registry restore/view instructions are missing.' }
    # Recycle Bin must contain this exact fixture; no permanent deletion fallback.
    $shell=New-Object -ComObject Shell.Application
    $recycled=@($shell.Namespace(10).Items() | Where-Object { $_.Name -eq $name })
    if ($recycled.Count -ne 1) { throw 'Fixture was not found in Recycle Bin.' }
    # Restore only this disposable fixture using Explorer's native move, then remove our own temp tree.
    $shell.Namespace($fixtureRoot).MoveHere($recycled[0],20)
    for ($i=0;$i -lt 20 -and -not (Test-Path -LiteralPath $folder);$i++) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath (Join-Path $folder 'fixture.txt'))) { throw 'Recycle Bin restore failed.' }
    Write-Output 'PASS: native inventory, protected/shared locations, versioned names, nested product discovery with different publisher names, value-only cleanup preserving siblings, registry backups and Recycle Bin round trip. No real app removed.'
} finally {
    # Verify resolved targets are inside the explicitly created fixture and backup roots before removal.
    $resolved=[IO.Path]::GetFullPath($fixtureRoot)
    if ($resolved -ne [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) $name))) { throw 'Fixture root mismatch.' }
    Remove-Item -LiteralPath $registryFixture -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    if ($trace) { $trace.DeleteValue($traceValue,$false); $trace.DeleteValue($sentinel,$false); $trace.Dispose() }
    if (-not [IO.Path]::GetFullPath($dataRoot).StartsWith([IO.Path]::GetFullPath($env:LOCALAPPDATA)+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Nested fixture escaped Local AppData.' }
    Remove-Item -LiteralPath $dataRoot -Recurse -Force
    Remove-Item -LiteralPath ('HKCU:\Software\'+$vendor) -Recurse -Force
    if ($backupFolder) {
        $backupRoot=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA '1nstall\Backups'))+'\'
        if (-not [IO.Path]::GetFullPath($backupFolder).StartsWith($backupRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Backup fixture escaped its root.' }
        Remove-Item -LiteralPath $backupFolder -Recurse -Force
    }
}
