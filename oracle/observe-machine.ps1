# Observation run of the 3.6 engine on a disposable machine (CI runner, VM or Sandbox).
# It records what 3.6 does; it does not assert. Stages:
#   tests     - runs the existing native removal tests that need a disposable environment
#   inventory - records how 3.6 reads this machine's real uninstall registrations
#   winget    - installs one real package through the 3.6 install path and records the outcome
param(
    [switch]$DisposableEnvironment,
    [Parameter(Mandatory)][ValidateSet('tests','inventory','winget')][string]$Stage,
    [Parameter(Mandatory)][string]$Out
)
if (-not $DisposableEnvironment) { throw 'Run only on a disposable machine (CI runner, VM or Sandbox) with -DisposableEnvironment.' }
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\json.ps1')
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$Out=(Resolve-Path -LiteralPath $Out).Path
$english=[Globalization.CultureInfo]::GetCultureInfo('en-US')
[Threading.Thread]::CurrentThread.CurrentCulture=$english
[Threading.Thread]::CurrentThread.CurrentUICulture=$english

function Write-Annotation([string]$level,[string]$title,[string]$text) {
    $clean=$text.Replace('%','%25').Replace("`r",' ').Replace("`n",' ')
    if ($clean.Length -gt 3000) { $clean=$clean.Substring(0,3000)+' ...' }
    Write-Output ('::{0} title={1}::{2}' -f $level,$title,$clean)
}
function Save-Json([string]$name,$value) {
    [IO.File]::WriteAllText((Join-Path $Out $name),(ConvertTo-CanonicalJson $value)+"`n",(New-Object Text.UTF8Encoding($false)))
}
function Import-Helpers {
    foreach ($helper in @('package-helper.cs','uninstall-helper.cs')) {
        Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $repo ('src/'+$helper)))) -ReferencedAssemblies System.dll,System.Core.dll,System.Web.Extensions.dll
    }
}
function Show-App($app) {
    $row=[ordered]@{
        Id=$app.Id; Name=$app.Name; Publisher=$app.Publisher; Version=$app.Version; Kind=$app.Kind; Location=$app.Location
        Command=$app.Command; RegistryPath=$app.RegistryPath; PackageFamily=$app.PackageFamily
        Machine=$app.Machine; View32=$app.View32; Msi=$app.Msi; CanRemove=$app.CanRemove; SizeKB=$app.SizeKB
    }
    if ($app.Kind -eq 'Desktop') {
        try { $start=[OneInstallUninstall]::GetCommand($app); $row['Parsed']=[ordered]@{ FileName=$start.FileName; Arguments=$start.Arguments } }
        catch { $row['Parsed']=[ordered]@{ Error=$_.Exception.GetBaseException().Message } }
    }
    return $row
}

if ($Stage -eq 'tests') {
    $results=New-Object System.Collections.ArrayList
    foreach ($test in @('uninstall.ps1','uninstall-process.ps1')) {
        $name=[IO.Path]::GetFileNameWithoutExtension($test)
        $log=Join-Path $Out ('test-'+$name+'.out.txt'); $errorLog=Join-Path $Out ('test-'+$name+'.err.txt')
        $arguments=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $repo ('tests\'+$test))+'"'),'-DisposableEnvironment')
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $process=Start-Process -FilePath powershell.exe -ArgumentList $arguments -RedirectStandardOutput $log -RedirectStandardError $errorLog -PassThru
        $null=$process.Handle
        $finished=$process.WaitForExit(300000)
        if (-not $finished) { $process.Kill(); $process.WaitForExit() }
        $output=@(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue | Where-Object { $_ })
        $errors=@(Get-Content -LiteralPath $errorLog -ErrorAction SilentlyContinue | Where-Object { $_ })
        $last=''; if ($output.Count -gt 0) { $last=[string]$output[$output.Count-1] }
        $code=$null; if ($finished) { $code=$process.ExitCode }
        $passed=($finished -and $code -eq 0 -and $last.StartsWith('PASS'))
        $row=[ordered]@{ Test=$test; Finished=$finished; ExitCode=$code; Seconds=[int]$clock.Elapsed.TotalSeconds; Passed=$passed; LastLine=$last; Error=([string]::Join(' | ',@($errors | Select-Object -First 6))) }
        [void]$results.Add($row)
        $level='notice'; $word='PASSED'; $detail=$last
        if (-not $passed) { $level='warning'; $word='FAILED'; $detail='exit='+$code+' finished='+$finished+' '+$row.Error }
        Write-Annotation $level ('oracle tests: '+$test) ('{0} in {1}s: {2}' -f $word,$row.Seconds,$detail)
    }
    Save-Json 'tests.json' $results
    return
}

Import-Helpers

if ($Stage -eq 'inventory') {
    $inventory=[OneInstallUninstall]::Inventory()
    $rows=@($inventory.Apps | ForEach-Object { Show-App $_ })
    Save-Json 'inventory-v36.json' ([ordered]@{ Warnings=@($inventory.Warnings); Apps=$rows })
    $exports=New-Object System.Collections.ArrayList
    foreach ($hive in @('HKLM','HKCU')) {
        foreach ($view in @('64','32')) {
            $file=Join-Path $Out ('raw-uninstall-'+$hive+'-'+$view+'.reg')
            & reg.exe export ($hive+'\Software\Microsoft\Windows\CurrentVersion\Uninstall') $file /y ('/reg:'+$view) | Out-Null
            [void]$exports.Add([ordered]@{ Hive=$hive; View=$view; ExitCode=$LASTEXITCODE; Bytes=$(if (Test-Path -LiteralPath $file) { (Get-Item -LiteralPath $file).Length } else { 0 }) })
        }
    }
    $desktop=@($rows | Where-Object { $_.Kind -eq 'Desktop' })
    $counts=@{}
    foreach ($row in $desktop) {
        $verdict='accepted'; if ($row.Parsed.Contains('Error')) { $verdict=[string]$row.Parsed.Error }
        if (-not $counts.ContainsKey($verdict)) { $counts[$verdict]=0 }; $counts[$verdict]++
    }
    $verdicts=[ordered]@{}
    foreach ($verdict in @($counts.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Name })) { $verdicts[$verdict]=$counts[$verdict] }
    $summary=[ordered]@{
        Desktop=$desktop.Count; Store=@($rows | Where-Object { $_.Kind -ne 'Desktop' }).Count; Warnings=@($inventory.Warnings).Count
        Msi=@($desktop | Where-Object { $_.Msi }).Count; Machine=@($desktop | Where-Object { $_.Machine }).Count; View32=@($desktop | Where-Object { $_.View32 }).Count
        NoLocation=@($desktop | Where-Object { -not $_.Location }).Count; CanRemove=@($desktop | Where-Object { $_.CanRemove }).Count
        Verdicts=$verdicts; RawExports=$exports
    }
    Save-Json 'inventory-summary.json' $summary
    Write-Annotation 'notice' 'oracle inventory' (ConvertTo-CanonicalJson $summary)
    return
}

if ($Stage -eq 'winget') {
    [OneInstallPackages]::DataRoot=Join-Path $Out 'data'
    $winget=[OneInstallPackages]::FindWinGet()
    if (-not $winget) {
        Save-Json 'winget.json' ([ordered]@{ Present=$false })
        Write-Annotation 'notice' 'oracle winget' 'winget.exe was not found on this image; the real-install scenario was skipped.'
        return
    }
    [OneInstallPackages]::WinGetPath=$winget
    $package='7zip.7zip'; $ids=[string[]]@($package)
    $version=[OneInstallPackages]::Run($winget,'--version',60000)
    $before=@([OneInstallUninstall]::Inventory().Apps | ForEach-Object { $_.Id })
    $inventoryBefore=[OneInstallPackages]::Inventory()
    $stateBefore=[OneInstallPackages]::InstalledState($inventoryBefore,$ids,'winget')
    $logs=Join-Path $Out 'winget-logs'; New-Item -ItemType Directory -Path $logs -Force | Out-Null
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $record=[OneInstallPackages]::Install($winget,$package,'winget','7-Zip',$logs)
    $seconds=[int]$clock.Elapsed.TotalSeconds
    $inventoryAfter=[OneInstallPackages]::Inventory()
    $stateAfter=[OneInstallPackages]::InstalledState($inventoryAfter,$ids,'winget')
    $registrations=@([OneInstallUninstall]::Inventory().Apps | Where-Object { $before -notcontains $_.Id } | ForEach-Object { Show-App $_ })
    $result=[ordered]@{
        Present=$true; WinGetVersion=([string]$version.Output).Trim(); Package=$package; Seconds=$seconds
        InventoryBefore=[ordered]@{ Complete=$inventoryBefore.Complete; Partial=$inventoryBefore.Partial; Message=$inventoryBefore.Message; Packages=$inventoryBefore.Packages.Count }
        StateBefore=$stateBefore
        Record=[ordered]@{ Action=$record.Action; Id=$record.Id; Source=$record.Source; Name=$record.Name; Outcome=$record.Outcome; Message=$record.Message; ExitCode=$record.ExitCode }
        InventoryAfter=[ordered]@{ Complete=$inventoryAfter.Complete; Partial=$inventoryAfter.Partial; Message=$inventoryAfter.Message; Packages=$inventoryAfter.Packages.Count }
        StateAfter=$stateAfter
        NewRegistrations=$registrations
    }
    Save-Json 'winget.json' $result
    Write-Annotation 'notice' 'oracle winget' (ConvertTo-CanonicalJson $result)
}
