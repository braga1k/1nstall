# Headless Windows regression checks. Only a GUID-owned temporary tree is written.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot
foreach ($helper in @('package-helper.cs','uninstall-helper.cs')) {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $root ('src/'+$helper)))) -ReferencedAssemblies System.dll,System.Core.dll,System.Web.Extensions.dll
}
function Assert($Condition,[string]$Text) { if (-not $Condition) { throw $Text } }
function Reject([scriptblock]$Action,[string]$Text) { $caught=$false; try { & $Action } catch { $caught=$true }; Assert $caught $Text }
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('1nstall-regression-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
[OneInstallPackages]::DataRoot=Join-Path $fixtureRoot 'data'
$tests=0
try {
    $compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    $fixture=Join-Path $fixtureRoot 'package fixture.exe'
    & $compiler /nologo /target:exe /reference:System.Web.Extensions.dll "/out:$fixture" (Join-Path $PSScriptRoot 'process-fixture.cs')
    Assert ($LASTEXITCODE -eq 0) 'Fixture compiler failed.'
    $originalWinget=[OneInstallPackages]::WinGetPath; $originalPath=$env:PATH
    try {
        [OneInstallPackages]::WinGetPath=$fixture
        Assert ([OneInstallPackages]::FindWinGet() -eq $fixture) 'Explicit WinGet path was not found.'
        $wingetFixture=Join-Path $fixtureRoot 'winget.exe'; [IO.File]::WriteAllText($wingetFixture,'fixture')
        [OneInstallPackages]::WinGetPath=Join-Path $fixtureRoot 'missing.exe'; $env:PATH=$fixtureRoot
        Assert ([OneInstallPackages]::FindWinGet() -eq $wingetFixture) 'WinGet PATH fallback failed.'
        $tests+=2
    } finally { [OneInstallPackages]::WinGetPath=$originalWinget; $env:PATH=$originalPath }
    $args=@('', 'path with spaces\', 'quote" and trailing\', 'normal', 'a&b', 'C:\folder\')
    $r=[OneInstallPackages]::Run($fixture,(@($args | ForEach-Object { [OneInstallPackages]::Quote($_) }) -join ' '),10000)
    $parsed=@($r.Output | ConvertFrom-Json | ForEach-Object { $_ })
    Assert ($parsed.Count -eq $args.Count) 'Argument count changed.'
    for ($i=0;$i -lt $args.Count;$i++) { Assert ($parsed[$i] -ceq $args[$i]) 'Argument escaping changed input.' }; $tests++
    Assert ([OneInstallUninstall]::QuoteArgument('C:\folder\') -ceq [OneInstallPackages]::Quote('C:\folder\')) 'Registry trailing-backslash quoting mismatch.'; $tests++
    $r=[OneInstallPackages]::Run($fixture,'pipes',10000)
    Assert ($r.Output.Length -eq 200000 -and $r.Error.Length -eq 200000) 'Parallel pipe drain failed.'; $tests++
    foreach ($bad in @('App;Remove-Item','--all','$(malicious)','App ID')) { Reject { [OneInstallPackages]::Arguments($bad,'winget') } 'Executable package input accepted.'; $tests++ }
    $command=[OneInstallPackages]::Arguments('Fixture.App','winget')
    Assert ($command -match '--exact' -and $command -match '--no-upgrade' -and $command -notmatch '--all|--force|--include-pinned|--allow-reboot') 'Install must not become an update or override scope.'; $tests++
    Assert ($null -eq [OneInstallPackages].GetMethod('UpdateAsync')) 'Update service still exists.'; $tests++
    $inventory=New-Object PackageInventory
    Assert ([OneInstallPackages]::InstalledState($inventory,[string[]]@('Fixture.App'),'winget') -eq 'Unknown') 'Unavailable inventory claimed absence.'; $tests++
    $inventory.Complete=$true
    Assert ([OneInstallPackages]::InstalledState($inventory,[string[]]@('Fixture.App'),'winget') -eq 'Not installed') 'Complete identity inventory failed.'; $tests++
    $p=New-Object PackageRecord; $p.Id='Fixture.App'; $p.Name='Different display name'; $p.Source='winget'; $p.InstalledVersion='1.0'; $inventory.Packages.Add($p)
    Assert ([OneInstallPackages]::InstalledState($inventory,[string[]]@('Fixture.App'),'winget') -eq 'Installed · 1.0') 'Exact identity ignored.'; $tests++
    Assert ([OneInstallPackages]::InstalledState($inventory,[string[]]@('Fixture.Other'),'winget') -eq 'Not installed') 'Display name match used.'; $tests++
    $inventory.Packages.Add($p)
    Assert ([OneInstallPackages]::InstalledState($inventory,[string[]]@('Fixture.App'),'winget').StartsWith('Unknown')) 'Ambiguous/multiple scopes confirmed.'; $tests++
    Assert ([OneInstallPackages]::InstalledState($inventory,[string[]]@(),'winget') -eq 'Unknown') 'Guided app claimed installed.'; $tests++
    $partial=[OneInstallPackages]::ParseExport('{"Sources":[{"SourceDetails":{"Name":"winget"},"Packages":[{"PackageIdentifier":"Fixture.App","Version":"1.0"}]}]}')
    Assert ([OneInstallPackages]::InstalledState($partial,[string[]]@('Fixture.App'),'winget') -eq 'Installed · 1.0') 'Structured export identity was not recognized.'; $tests++
    Assert ([OneInstallPackages]::InstalledState($partial,[string[]]@('Fixture.Missing'),'winget').StartsWith('Unknown')) 'Omission from partial export claimed absence.'; $tests++
    Reject { [OneInstallPackages]::ParseExport('{"Sources":[{"SourceDetails":{"Name":"winget"},"Packages":[{"PackageIdentifier":"--all"}]}]}') } 'Invalid export identity accepted.'; $tests++
    Reject { [OneInstallPackages]::ParseExport('{}') } 'Malformed export shape accepted.'; $tests++
    $inventory.Packages.RemoveAt(1)
    foreach ($case in @(@(0,'Unknown'),@(3010,'Restart required'),@(1641,'Restart required'),@(1602,'Cancelled'),@(1603,'Failed'))) { Assert ([OneInstallPackages]::Outcome($case[0]) -eq $case[1]) 'Outcome classification failed.'; $tests++ }
    foreach ($hex in @('8A150109','8A15010A','8A15010B')) { Assert ([OneInstallPackages]::Outcome([int]([Convert]::ToInt64($hex,16)-4294967296)) -eq 'Restart required') 'WinGet restart HRESULT failed.'; $tests++ }
    $r=[OneInstallPackages]::Install($fixture,'Fixture.Failure','winget','Fixture',(Join-Path $fixtureRoot 'logs')); Assert ($r.Outcome -eq 'Failed') 'Failed installer claimed success.'; $tests++
    $r=[OneInstallPackages]::Install($fixture,'Fixture.Restart','winget','Fixture',(Join-Path $fixtureRoot 'logs')); Assert ($r.Outcome -eq 'Restart required') 'Restart installer lost outcome.'; $tests++
    $r=[OneInstallPackages]::Install($fixture,'Fixture.Cancelled','winget','Fixture',(Join-Path $fixtureRoot 'logs')); Assert ($r.Outcome -eq 'Cancelled') 'Cancelled installer lost outcome.'; $tests++
    $r=[OneInstallPackages]::Install($fixture,'Fixture.Offline','winget','Fixture',(Join-Path $fixtureRoot 'logs')); Assert ($r.Outcome -eq 'Failed' -and $r.Message -match 'connectivity') 'Offline failure lost actionable explanation.'; $tests++
    $r=[OneInstallPackages]::Install($fixture,'Fixture.Success','winget','Fixture',(Join-Path $fixtureRoot 'logs')); Assert ($r.Outcome -eq 'Unknown') 'Zero-exit process claimed installed identity.'; $tests++
    $r=[OneInstallPackages]::Install((Join-Path $fixtureRoot 'missing.exe'),'Fixture.App','winget','Fixture',(Join-Path $fixtureRoot 'logs')); Assert ($r.Outcome -eq 'Failed') 'Missing WinGet claimed success.'; $tests++
    # Extract the trusted planner and worker from source without starting WPF.
    $source=[IO.File]::ReadAllText((Join-Path $root 'vexan_installers.ps1'))
    $ast=[System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
    $definition=$ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-Plan' },$true)
    . ([scriptblock]::Create($definition.Extent.Text))
    $byKey=@{A=[pscustomobject]@{Key='A';Requires=@('B')};B=[pscustomobject]@{Key='B';Requires=@('C')};C=[pscustomobject]@{Key='C';Requires=@()}}
    Assert ((@(Get-Plan @('A','B')).Key -join ',') -eq 'C,B,A') 'Transitive dependency order failed.'; $tests++
    $byKey.C.Requires=@('A'); Reject { Get-Plan @('A') } 'Dependency cycle accepted.'; $tests++
    $byKey.C.Requires=@('missing'); Reject { Get-Plan @('A') } 'Unknown transitive dependency accepted.'; $tests++
    $start=$source.IndexOf('    $worker = {'); $end=$source.IndexOf('    function Set-Busy',$start)
    . ([scriptblock]::Create($source.Substring($start,$end-$start)))
    $plan=@([pscustomobject]@{Key='dependency';Name='Dependency';Requires=@();Ids=@('Fixture.Failure');Url=''},[pscustomobject]@{Key='dependent';Name='Dependent';Requires=@('dependency');Ids=@('Fixture.Success');Url=''})
    $events=New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'; $control=@{Stop=$false}
    & $worker $plan $fixture $events $control (Join-Path $fixtureRoot 'logs')
    $history=@([OneInstallPackages]::History())
    Assert (@($history | Where-Object { $_.Id -eq 'Fixture.Success' -and $_.Name -eq 'Dependent' }).Count -eq 0) 'Dependent installer ran after failure.'
    Assert (@($history | Where-Object { $_.Id -eq 'dependent' -and $_.Outcome -eq 'Manual action required' }).Count -eq 1) 'Dependency failure not reported.'; $tests++
    $control.Stop=$true; & $worker $plan $fixture $events $control (Join-Path $fixtureRoot 'logs')
    Assert (@([OneInstallPackages]::History() | Where-Object Outcome -eq 'Cancelled').Count -ge 3) 'Stop did not report unstarted items.'; $tests++
    $plan[0].Ids=@('Fixture.SlowFailure'); $plan[0].Key='slow'; $plan[1].Requires=@('slow')
    $control=[hashtable]::Synchronized(@{Stop=$false}); $job=[PowerShell]::Create()
    try {
        $null=$job.AddScript($worker.ToString()).AddArgument($plan).AddArgument($fixture).AddArgument($events).AddArgument($control).AddArgument((Join-Path $fixtureRoot 'logs'))
        $async=$job.BeginInvoke(); $marker=Join-Path $fixtureRoot 'started.flag'
        for ($i=0;$i -lt 100 -and -not (Test-Path -LiteralPath $marker);$i++) { Start-Sleep -Milliseconds 20 }
        Assert (Test-Path -LiteralPath $marker) 'Running fixture did not start.'
        $control.Stop=$true; $job.EndInvoke($async) | Out-Null
        Assert (@([OneInstallPackages]::History() | Where-Object { $_.Id -eq 'Fixture.SlowFailure' -and $_.Outcome -eq 'Failed' }).Count -eq 1) 'Stop interrupted current installer.'
        Assert (@([OneInstallPackages]::History() | Where-Object { $_.Id -eq 'dependent' -and $_.Outcome -eq 'Cancelled' }).Count -ge 2) 'Stop started next installer.'; $tests++
    } finally { $job.Dispose() }
    $file=Join-Path $fixtureRoot 'setup.json'
    $entry=New-Object SetupEntry; $entry.Id='Fixture.App'; $entry.Source='winget'; $entry.Name='Fixture'; $entry.Version='1.0'
    [OneInstallPackages]::SaveSetup($file,[SetupEntry[]]@($entry))
    Assert ([OneInstallPackages]::ReadSetup($file).Apps[0].Id -eq 'Fixture.App') 'Snapshot round trip failed.'; $tests++
    foreach ($invalid in @('{"Version":1,"Apps":["A"],"Command":"cmd.exe"}','{"Version":1,"Apps":"A"}','{"Version":1,"Apps":["A","A"]}','{"Version":2,"Kind":"1nstall-selection","Apps":[{"Id":"--all","Source":"winget","Name":"A","Version":"1"}]}','{"Version":99,"Apps":["A"]}','malformed')) { [IO.File]::WriteAllText($file,$invalid); Reject { [OneInstallPackages]::ReadSetup($file) } 'Malformed/executable profile accepted.'; $tests++ }
    [IO.File]::WriteAllText($file,'{"Version":1,"Apps":["A"]}'); Assert ([OneInstallPackages]::ReadSetup($file).Keys[0] -eq 'A') 'Legacy profile rejected.'; $tests++
    [IO.File]::WriteAllText($file,('x'*65537)); Reject { [OneInstallPackages]::ReadSetup($file) } 'Oversized profile accepted.'; $tests++
    $redacted=[OneInstallPackages]::Redact('C:\Users\Alice\private\log.txt password=secret123'+"`n"+'Bearer token123 alice@example.com https://host/?token=secret')
    Assert ($redacted -notmatch 'Alice|private|secret123|token123|alice@example|token=secret') 'Diagnostic redaction leaked fixture values.'; $tests++
    [OneInstallUninstall]::SelfTest(); $tests++
    foreach ($badHistory in @('malformed','[null]')) {
        [IO.File]::WriteAllText([OneInstallPackages]::HistoryPath,$badHistory)
        $r=[OneInstallPackages]::Record('Install','Fixture.App','winget','Fixture','Unknown','Fixture',0,$null)
        Assert ($r.Message -match 'preserved' -and [IO.File]::ReadAllText([OneInstallPackages]::HistoryPath) -eq $badHistory) 'Corrupt history overwritten silently.'; $tests++
    }
    Write-Output "PASS: $tests headless regression checks. Simulated outcomes, disposable process/filesystem fixtures; no publisher installer or personal app modified."
} finally {
    $resolved=[IO.Path]::GetFullPath($fixtureRoot)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^1nstall-regression-[a-f0-9]{32}$') { throw 'Fixture escaped temporary root.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
