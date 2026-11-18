# Observation run of the 3.6 engine on a disposable machine (CI runner, VM or Sandbox).
# It records what 3.6 does; it does not assert. Stages:
#   tests     - runs the existing native removal tests that need a disposable environment
#   removal   - drives remove -> scan -> clean on fixture apps and records machine state at each step
#   inventory - records how 3.6 reads this machine's real uninstall registrations
#   winget    - installs real packages through the 3.6 install path, without and with Microsoft.WinGet.Client
param(
    [switch]$DisposableEnvironment,
    [Parameter(Mandatory)][ValidateSet('tests','removal','inventory','winget')][string]$Stage,
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
$utf8=New-Object Text.UTF8Encoding($false)

function Write-Annotation([string]$level,[string]$title,[string]$text) {
    $clean=$text.Replace('%','%25').Replace("`r",' ').Replace("`n",' ')
    if ($clean.Length -gt 3000) { $clean=$clean.Substring(0,3000)+' ...' }
    Write-Output ('::{0} title={1}::{2}' -f $level,$title,$clean)
}
# Publishes a file through annotations (gzip + base64, in chunks) so a recording can be read without downloading artifacts.
function Publish-Data([string]$title,[string]$path) {
    $bytes=[IO.File]::ReadAllBytes($path)
    $memory=New-Object IO.MemoryStream
    $gzip=New-Object IO.Compression.GZipStream($memory,[IO.Compression.CompressionMode]::Compress)
    $gzip.Write($bytes,0,$bytes.Length); $gzip.Close()
    $text=[Convert]::ToBase64String($memory.ToArray())
    $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $size=2800; $count=[int][Math]::Ceiling($text.Length/$size)
    for ($i=0;$i -lt $count;$i++) {
        Write-Output ('::notice title={0} [{1}/{2}] sha256 {3}::{4}' -f $title,($i+1),$count,$hash,$text.Substring($i*$size,[Math]::Min($size,$text.Length-$i*$size)))
    }
}
function Save-Json([string]$name,$value) { [IO.File]::WriteAllText((Join-Path $Out $name),(ConvertTo-CanonicalJson $value)+"`n",$utf8) }
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
function Get-Head([string]$text,[int]$length) {
    $clean=([regex]::Replace([string]$text,'[^\x20-\x7E]+',' ') -replace '\s+',' ').Trim()
    if ($clean.Length -gt $length) { $clean=$clean.Substring(0,$length)+' ...' }
    return $clean
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

if ($Stage -eq 'removal') {
    $arp='Software\Microsoft\Windows\CurrentVersion\Uninstall'
    $jumplist='Software\Microsoft\Windows\CurrentVersion\Search\JumplistData'
    $vendorKey='Software\OracleFixtureVendor'
    $vendorFolder=Join-Path $env:APPDATA 'OracleFixtureVendor'
    $toolsFolder=Join-Path $env:LOCALAPPDATA 'OracleFixtureTools'
    $pathTokens=@(@($env:LOCALAPPDATA,'{LOCALAPPDATA}'),@($env:APPDATA,'{APPDATA}'),@($env:USERPROFILE,'{USERPROFILE}'))
    # A stand-in publisher uninstaller. It only ever touches registrations whose key starts with "OracleFixture".
    $publisherCode=@'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using Microsoft.Win32;
class OraclePublisher {
    const string Arp=@"Software\Microsoft\Windows\CurrentVersion\Uninstall\";
    static int Main(string[] args) {
        if (args.Length!=2 || !args[1].StartsWith("OracleFixture")) return 2;
        string mode=args[0], key=args[1];
        if (mode=="cancel") return 1602;
        if (mode=="fail") return 1603;
        if (mode=="keep") return 0;
        if (mode=="child") {
            var start=new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,"leaf "+key) { UseShellExecute=false, CreateNoWindow=true };
            using (Process.Start(start)) { }
            return 0;
        }
        if (mode=="leaf") Thread.Sleep(1500);
        string location=null;
        using (var registration=Registry.CurrentUser.OpenSubKey(Arp+key)) { if (registration!=null) location=registration.GetValue("InstallLocation") as string; }
        if (!String.IsNullOrEmpty(location)) { string executable=Path.Combine(location,"editor.exe"); if (File.Exists(executable)) File.Delete(executable); }
        Registry.CurrentUser.DeleteSubKeyTree(Arp+key,false);
        return mode=="restart"?3010:0;
    }
}
'@
    New-Item -ItemType Directory -Path $toolsFolder -Force | Out-Null
    $publisher=Join-Path $toolsFolder 'publisher.exe'
    if (-not (Test-Path -LiteralPath $publisher)) { Add-Type -TypeDefinition $publisherCode -OutputAssembly $publisher -OutputType ConsoleApplication }

    function Normalize-Json([string]$json) {
        foreach ($pair in $pathTokens) { $json=[regex]::Replace($json,[regex]::Escape(([string]$pair[0]).Replace('\','\\')),[string]$pair[1],[Text.RegularExpressions.RegexOptions]::IgnoreCase) }
        $json=[regex]::Replace($json,'\d{8}-\d{6}-[0-9a-f]{8}','{STAMP}')
        return [regex]::Replace($json,'(?<![0-9A-Za-z])[0-9a-f]{32}(?![0-9A-Za-z])','{GUID}')
    }
    function Test-Key([string]$path) { $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path); if ($key) { $key.Dispose(); return $true }; return $false }
    function Get-Tree([string]$folder) {
        if (-not (Test-Path -LiteralPath $folder)) { return 'absent' }
        $rows=@(Get-ChildItem -LiteralPath $folder -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($folder.Length+1)+' ('+$_.Length+' B)' })
        return ,$rows
    }
    function Get-Shape($value) {
        if ($null -eq $value) { return 'null' }
        if ($value -is [string]) { return 'string' }
        if ($value -is [bool]) { return 'bool' }
        if ($value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal]) { return 'number' }
        if ($value -is [Management.Automation.PSCustomObject]) {
            $shape=[ordered]@{}
            foreach ($entry in $value.PSObject.Properties) { $shape[$entry.Name]=Get-Shape $entry.Value }
            return $shape
        }
        if ($value -is [Collections.IEnumerable]) { return 'array' }
        return $value.GetType().Name
    }
    function Read-JsonShape([string]$path) {
        if (-not (Test-Path -LiteralPath $path)) { return 'absent' }
        $bytes=[IO.File]::ReadAllBytes($path)
        $data=[IO.File]::ReadAllText($path) | ConvertFrom-Json
        $rows=@($data | ForEach-Object { $_ })
        $first=$null; if ($rows.Count -gt 0) { $first=$rows[0] }
        return [ordered]@{ Utf8Bom=($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF); Rows=$rows.Count; FirstRowShape=(Get-Shape $first) }
    }
    function Show-Backup([string]$folder) {
        if (-not $folder -or -not (Test-Path -LiteralPath $folder)) { return 'absent' }
        $files=@(Get-ChildItem -LiteralPath $folder -File)
        $exports=@($files | Where-Object { $_.Extension -eq '.reg' } | ForEach-Object {
            $bytes=[IO.File]::ReadAllBytes($_.FullName)
            $lines=@([Text.Encoding]::Unicode.GetString($bytes) -split "`r`n" | Where-Object { $_.StartsWith('[') })
            $firstKey=''; if ($lines.Count -gt 0) { $firstKey=[string]$lines[0] }
            [ordered]@{ FirstKey=$firstKey; Keys=$lines.Count; FirstBytes=[BitConverter]::ToString($bytes,0,[Math]::Min(4,$bytes.Length)); Bytes=$bytes.Length }
        } | Sort-Object { $_.FirstKey })
        $restore='absent'; $restorePath=Join-Path $folder 'RESTORE.txt'
        if (Test-Path -LiteralPath $restorePath) { $restore=@(Get-Content -LiteralPath $restorePath) }
        return [ordered]@{
            Folder=$folder; Files=@($files | ForEach-Object { $_.Name } | Sort-Object)
            RegistryExports=$exports; Restore=$restore
            ItemsJson=(Read-JsonShape (Join-Path $folder 'items.json')); ResultsJson=(Read-JsonShape (Join-Path $folder 'results.json'))
        }
    }
    function New-Fixture([string]$variant,[string]$mode,[bool]$withLocation,[string]$commandOverride) {
        $key='OracleFixture'+$variant; $product='Oracle'+$variant+' Editor'
        $install=Join-Path $env:LOCALAPPDATA ('Programs\'+$product)
        $data=Join-Path $vendorFolder $product
        $productKey=$vendorKey+'\'+$product
        New-Item -ItemType Directory -Path $install,$data -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $install 'editor.exe'),'fixture executable placeholder')
        [IO.File]::WriteAllText((Join-Path $install 'readme.txt'),'fixture program file')
        [IO.File]::WriteAllText((Join-Path $data 'settings.ini'),'fixture user settings')
        $settings=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($productKey); $settings.SetValue('Setting','1'); $settings.Dispose()
        $trace=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($jumplist)
        $trace.SetValue((Join-Path $install 'editor.exe'),1); $trace.SetValue((Join-Path ($install+'Sibling') 'editor.exe'),7); $trace.Dispose()
        $uninstaller=$publisher; $tools=$null
        if (-not $withLocation) {
            # No InstallLocation: 3.6 then derives the location from the uninstaller's own folder.
            $tools=Join-Path $env:LOCALAPPDATA ('Programs\Oracle'+$variant+' Tools')
            New-Item -ItemType Directory -Path $tools -Force | Out-Null
            $uninstaller=Join-Path $tools 'publisher.exe'; Copy-Item -LiteralPath $publisher -Destination $uninstaller -Force
        }
        $command='"'+$uninstaller+'" '+$mode+' '+$key; if ($commandOverride) { $command=$commandOverride }
        $registration=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($arp+'\'+$key)
        $registration.SetValue('DisplayName',$product+' 2.0 (x64)'); $registration.SetValue('Publisher','Oracle Fixture Vendor')
        $registration.SetValue('DisplayVersion','2.0'); $registration.SetValue('UninstallString',$command)
        if ($withLocation) { $registration.SetValue('InstallLocation',$install) }
        $registration.Dispose()
        return [ordered]@{ Variant=$variant; Mode=$mode; Install=$install; Data=$data; Tools=$tools; ProductKey=$productKey; RegistryPath=$arp+'\'+$key }
    }
    function Remove-Fixture($fixture) {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($fixture.RegistryPath,$false)
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($fixture.ProductKey,$false)
        $trace=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($jumplist,$true)
        if ($trace) { $trace.DeleteValue((Join-Path $fixture.Install 'editor.exe'),$false); $trace.DeleteValue((Join-Path ($fixture.Install+'Sibling') 'editor.exe'),$false); $trace.Dispose() }
        foreach ($folder in @($fixture.Install,$fixture.Data,$fixture.Tools)) { if ($folder -and (Test-Path -LiteralPath $folder)) { Remove-Item -LiteralPath $folder -Recurse -Force } }
    }
    function Get-State($fixture) {
        $trace=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($jumplist)
        $state=[ordered]@{
            Registration=(Test-Key $fixture.RegistryPath); InstallFolder=(Get-Tree $fixture.Install); DataFolder=(Get-Tree $fixture.Data)
            ProductKey=(Test-Key $fixture.ProductKey)
            TraceValue=($null -ne $trace.GetValue((Join-Path $fixture.Install 'editor.exe')))
            SiblingTraceValue=($null -ne $trace.GetValue((Join-Path ($fixture.Install+'Sibling') 'editor.exe')))
        }
        if ($fixture.Tools) { $state['ToolsFolder']=(Get-Tree $fixture.Tools) }
        $trace.Dispose()
        return $state
    }
    function Wait-Task($task,[int]$milliseconds) { if (-not $task.Wait($milliseconds)) { throw 'Operation timed out.' }; return $task.Result }
    function Show-Outcome($outcome) { return [ordered]@{ Name=$outcome.Name; Kind=$outcome.Kind; Path=$outcome.Path; Outcome=$outcome.Outcome; Message=$outcome.Message; ExitCode=$outcome.ExitCode } }
    function Show-Leftover($item) {
        return [ordered]@{ Kind=$item.Kind; Path=$item.Path; ValueName=$item.ValueName; Confidence=$item.Confidence; Reason=$item.Reason; Machine=$item.Machine; View32=$item.View32; Selected=$item.Selected; Files=$item.Files; Bytes=$item.Bytes }
    }
    function Show-Flags($app) {
        return [ordered]@{ Name=$app.Name; Location=$app.Location; RemovalVerified=$app.RemovalVerified; OwnershipVerified=$app.OwnershipVerified; IdentityVerified=$app.IdentityVerified; RestartPending=($app.RestartRequestedAt -ne 0) }
    }
    function Invoke-Variant($fixture) {
        $row=[ordered]@{ Variant=$fixture.Variant; Mode=$fixture.Mode }
        try {
            $row['StateBefore']=Get-State $fixture
            $inventory=[OneInstallUninstall]::Inventory()
            $found=@($inventory.Apps | Where-Object { $_.RegistryPath -eq $fixture.RegistryPath })
            $row['Listed']=$found.Count
            if ($found.Count -ne 1) { return $row }
            $app=$found[0]
            $row['Model']=Show-App $app
            $stage=$null; while ([OneInstallUninstall]::Stages.TryDequeue([ref]$stage)) { }
            $removal=Wait-Task ([OneInstallUninstall]::RemoveAsync([InstalledApp[]]@($app))) 120000
            $stages=New-Object System.Collections.ArrayList
            while ([OneInstallUninstall]::Stages.TryDequeue([ref]$stage)) { [void]$stages.Add($stage.Outcome) }
            $row['Remove']=[ordered]@{ Results=@($removal.Results | ForEach-Object { Show-Outcome $_ }); Messages=@($removal.Messages); Stages=$stages; AppAfter=(Show-Flags $app) }
            $row['StateAfterRemove']=Get-State $fixture
            $scan=Wait-Task ([OneInstallUninstall]::ScanAsync([InstalledApp[]]@($app))) 120000
            $leftovers=@($scan.Leftovers | Sort-Object Kind,Path,ValueName)
            $row['Scan']=[ordered]@{ ScannedApps=$scan.ScannedApps; IncompleteChecks=$scan.IncompleteChecks; Messages=@($scan.Messages); Leftovers=@($leftovers | ForEach-Object { Show-Leftover $_ }); AppAfter=(Show-Flags $app) }
            if ($leftovers.Count -gt 0) {
                $clean=Wait-Task ([OneInstallUninstall]::CleanAsync([LeftoverItem[]]$leftovers)) 120000
                $row['Clean']=[ordered]@{ Results=@($clean.Results | ForEach-Object { Show-Outcome $_ }); Messages=@($clean.Messages); RecycledBytes=$clean.RecycledBytes; Backup=(Show-Backup $clean.BackupFolder) }
            }
            $row['StateAfterClean']=Get-State $fixture
        }
        catch { $failure=$_.Exception.GetBaseException(); $row['Error']=$failure.GetType().Name+': '+$failure.Message }
        return $row
    }
    function Show-History {
        $path=[OneInstallUninstall]::HistoryFile
        if (-not (Test-Path -LiteralPath $path)) { return 'absent' }
        $bytes=[IO.File]::ReadAllBytes($path)
        $data=[IO.File]::ReadAllText($path) | ConvertFrom-Json
        $rows=@($data | ForEach-Object { $_ } | Where-Object { $_.RegistryPath -like '*OracleFixture*' } | Sort-Object RegistryPath)
        $first=$null; if ($rows.Count -gt 0) { $first=$rows[0] }
        return [ordered]@{
            File=$path; Utf8Bom=($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF); FixtureRows=$rows.Count; RowShape=(Get-Shape $first)
            Fixtures=@($rows | ForEach-Object { [ordered]@{ Id=$_.Id; Name=$_.Name; Location=$_.Location; Command=$_.Command; CanRemove=$_.CanRemove; RemovalVerified=$_.RemovalVerified; OwnershipVerified=$_.OwnershipVerified; IdentityVerified=$_.IdentityVerified; RestartPending=($_.RestartRequestedAt -ne 0) } })
        }
    }

    $shell='"'+(Join-Path $env:SystemRoot 'System32\cmd.exe')+'" /c exit 0'
    $variants=@(
        @('Alpha','clean',$true,''),      # uninstaller succeeds and leaves files, data, a product key and a trace
        @('Bravo','cancel',$true,''),     # uninstaller exits 1602
        @('Charlie','keep',$true,''),     # uninstaller exits 0 but the registration stays
        @('Delta','restart',$true,''),    # uninstaller exits 3010
        @('Echo','child',$true,''),       # launcher exits at once; a child finishes the removal 1.5 s later
        @('Foxtrot','fail',$true,''),     # uninstaller exits 1603
        @('Golf','clean',$false,''),      # no InstallLocation in the registration
        @('Hotel','keep',$true,$shell)    # uninstall command is a shell, which 3.6 refuses
    )
    $lines=New-Object 'System.Collections.Generic.List[string]'; $summary=New-Object 'System.Collections.Generic.List[string]'
    foreach ($variant in $variants) {
        $fixture=New-Fixture $variant[0] $variant[1] $variant[2] $variant[3]
        $row=Invoke-Variant $fixture
        $lines.Add((Normalize-Json (ConvertTo-CanonicalJson $row)))
        $verdict='not run'
        if ($row.Contains('Error')) { $verdict='ERROR '+$row['Error'] }
        elseif ($row.Contains('Remove')) {
            $verdict=[string]$row['Remove']['Results'][0]['Outcome']
            if ($row.Contains('Scan')) { $verdict+=', '+@($row['Scan']['Leftovers']).Count+' leftovers' }
            if ($row.Contains('Clean')) { $verdict+=', cleaned '+@($row['Clean']['Results'] | Where-Object { $_['Outcome'] -eq 'Success' }).Count }
        }
        $summary.Add($variant[0]+'='+$verdict)
        Remove-Fixture $fixture
    }
    $lines.Add((Normalize-Json (ConvertTo-CanonicalJson ([ordered]@{ History=(Show-History) }))))
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($vendorKey,$false)
    foreach ($folder in @($vendorFolder,$toolsFolder)) { if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue } }
    $file=Join-Path $Out 'removal.jsonl'
    [IO.File]::WriteAllText($file,([string]::Join("`n",$lines)+"`n"),$utf8)
    Write-Annotation 'notice' 'oracle removal' ([string]::Join('; ',$summary))
    Publish-Data 'oracle removal data' $file
    return
}

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
    $rejected=@($desktop | Where-Object { $_.Parsed.Contains('Error') } | ForEach-Object { [ordered]@{ Name=$_.Name; Command=$_.Command; Msi=$_.Msi; Verdict=$_.Parsed.Error } })
    $summary=[ordered]@{
        Desktop=$desktop.Count; Store=@($rows | Where-Object { $_.Kind -ne 'Desktop' }).Count; Warnings=@($inventory.Warnings).Count
        Msi=@($desktop | Where-Object { $_.Msi }).Count; Machine=@($desktop | Where-Object { $_.Machine }).Count; View32=@($desktop | Where-Object { $_.View32 }).Count
        NoLocation=@($desktop | Where-Object { -not $_.Location }).Count; CanRemove=@($desktop | Where-Object { $_.CanRemove }).Count
        Verdicts=$verdicts; Rejected=$rejected; RawExports=$exports
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
        Write-Annotation 'notice' 'oracle winget' 'winget.exe was not found on this image; the real-install scenarios were skipped.'
        return
    }
    [OneInstallPackages]::WinGetPath=$winget
    $logs=Join-Path $Out 'winget-logs'; New-Item -ItemType Directory -Path $logs -Force | Out-Null
    function Invoke-Probe([string]$file,[string]$arguments,[int]$timeout) {
        try { $result=[OneInstallPackages]::Run($file,$arguments,$timeout); return [ordered]@{ ExitCode=('0x{0:X8}' -f $result.ExitCode); Output=(Get-Head $result.Output 500); Error=(Get-Head $result.Error 300) } }
        catch { return [ordered]@{ Exception=(Get-Head $_.Exception.GetBaseException().Message 300) } }
    }
    function Show-Inventory($inventory) { return [ordered]@{ Complete=$inventory.Complete; Partial=$inventory.Partial; Packages=$inventory.Packages.Count; Message=(Get-Head $inventory.Message 300) } }
    function Invoke-Install([string]$package,[string]$name) {
        $ids=[string[]]@($package)
        $known=@([OneInstallUninstall]::Inventory().Apps | ForEach-Object { $_.Id })
        $before=[OneInstallPackages]::Inventory()
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $record=[OneInstallPackages]::Install($winget,$package,'winget',$name,$logs)
        $seconds=[int]$clock.Elapsed.TotalSeconds
        $after=[OneInstallPackages]::Inventory()
        return [ordered]@{
            Package=$package; Seconds=$seconds
            InventoryBefore=(Show-Inventory $before); StateBefore=[OneInstallPackages]::InstalledState($before,$ids,'winget')
            Record=[ordered]@{ Outcome=$record.Outcome; ExitCode=('0x{0:X8}' -f $record.ExitCode); Message=(Get-Head $record.Message 400) }
            InventoryAfter=(Show-Inventory $after); StateAfter=[OneInstallPackages]::InstalledState($after,$ids,'winget')
            NewRegistrations=@([OneInstallUninstall]::Inventory().Apps | Where-Object { $known -notcontains $_.Id } | ForEach-Object { Show-App $_ })
        }
    }
    $result=[ordered]@{ Present=$true; WinGetVersion=(Invoke-Probe $winget '--version' 60000) }
    # 1. Untouched machine: no Microsoft.WinGet.Client module.
    $result['WithoutModule']=Invoke-Install 'SumatraPDF.SumatraPDF' 'Sumatra PDF'
    # 2. Why the export fallback fails or works: the exact 3.6 command, then the same with source agreements accepted.
    $exportFile=Join-Path $Out 'export-probe.json'
    $export='export --output "'+$exportFile+'" --include-versions --disable-interactivity'
    $result['ExportAs36']=Invoke-Probe $winget $export 90000
    $result['ExportAcceptingAgreements']=Invoke-Probe $winget ($export+' --accept-source-agreements') 90000
    $result['ExportAs36Again']=Invoke-Probe $winget $export 90000
    # 3. Setup step 3.6 never performs itself: install the module, then repeat with a second package.
    $pwsh=Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (Test-Path -LiteralPath $pwsh) {
        $command='-NoLogo -NoProfile -NonInteractive -Command "Install-Module Microsoft.WinGet.Client -Scope AllUsers -Force -ErrorAction Stop; (Get-Module -ListAvailable Microsoft.WinGet.Client | Select-Object -First 1).Version.ToString()"'
        $result['ModuleInstall']=Invoke-Probe $pwsh $command 300000
        $result['WithModule']=Invoke-Install 'Notepad++.Notepad++' 'Notepad++'
        $complete=[OneInstallPackages]::Inventory()
        $result['FinalStates']=[ordered]@{
            Inventory=(Show-Inventory $complete)
            SumatraPDF=[OneInstallPackages]::InstalledState($complete,[string[]]@('SumatraPDF.SumatraPDF'),'winget')
            NotepadPlusPlus=[OneInstallPackages]::InstalledState($complete,[string[]]@('Notepad++.Notepad++'),'winget')
            SevenZipPreinstalled=[OneInstallPackages]::InstalledState($complete,[string[]]@('7zip.7zip'),'winget')
        }
    }
    else { $result['ModuleInstall']='PowerShell 7 is not installed in Program Files on this image.' }
    Save-Json 'winget.json' $result
    Publish-Data 'oracle winget data' (Join-Path $Out 'winget.json')
}
