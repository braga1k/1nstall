param([Parameter(Mandatory)][string]$Repo)
# Read-only probes on a normal, non-elevated desktop session. Nothing is installed, removed or accepted.
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $Repo 'src/package-helper.cs'))) -ReferencedAssemblies System.dll,System.Core.dll,System.Web.Extensions.dll
[Threading.Thread]::CurrentThread.CurrentUICulture=[Globalization.CultureInfo]::GetCultureInfo('en-US')
function Head([string]$text,[int]$n) { $c=([regex]::Replace([string]$text,'[^\x20-\x7E]+',' ') -replace '\s+',' ').Trim(); if ($c.Length -gt $n) { $c=$c.Substring(0,$n)+' ...' }; $c }

'--- 1. How 3.6 reads the installed inventory on this PC'
[OneInstallPackages]::DataRoot=Join-Path ([IO.Path]::GetTempPath()) ('oracle-local-'+[guid]::NewGuid().ToString('N'))
$winget=[OneInstallPackages]::FindWinGet(); [OneInstallPackages]::WinGetPath=$winget
'winget found: '+[bool]$winget
$version=[OneInstallPackages]::Run($winget,'--version',60000); 'winget version: '+$version.Output.Trim()
$clock=[Diagnostics.Stopwatch]::StartNew(); $inventory=[OneInstallPackages]::Inventory()
'Inventory: Complete={0} Partial={1} Packages={2} in {3:n1}s' -f $inventory.Complete,$inventory.Partial,$inventory.Packages.Count,$clock.Elapsed.TotalSeconds
'Message: '+(Head $inventory.Message 330)

'--- 2. The exact export command 3.6 uses, on its own'
$file=Join-Path ([IO.Path]::GetTempPath()) ('oracle-export-'+[guid]::NewGuid().ToString('N')+'.json')
$export=[OneInstallPackages]::Run($winget,('export --output "'+$file+'" --include-versions --disable-interactivity'),90000)
'export exit code: 0x{0:X8}' -f $export.ExitCode
if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }

'--- 3. WinGet COM API activation from this non-elevated session'
$manifest=Get-AppxPackage Microsoft.DesktopAppInstaller | Get-AppxPackageManifest
$classes=@($manifest.Package.Extensions.Extension | Where-Object { $_.Category -eq 'windows.comServer' } | ForEach-Object { $_.ComServer.ExeServer } | ForEach-Object { [pscustomobject]@{ Executable=$_.Executable; Classes=@($_.Class | ForEach-Object { $_.Id+' '+$_.DisplayName }) } })
foreach ($server in $classes) { 'COM server '+$server.Executable+': '+($server.Classes.Count)+' classes'; $server.Classes | ForEach-Object { '    '+$_ } }
$clsid='C53A4F16-787E-42A4-B304-29EFFB4BF597'
'PackageManager CLSID declared in the manifest: '+[bool](@($classes | ForEach-Object { $_.Classes }) -match $clsid)
try {
    $clock.Restart()
    $manager=[Activator]::CreateInstance([type]::GetTypeFromCLSID([guid]$clsid))
    'activation: OK in {0:n1}s, object type {1}' -f $clock.Elapsed.TotalSeconds,$manager.GetType().FullName
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($manager)
}
catch { $e=$_.Exception.GetBaseException(); 'activation: FAILED {0} 0x{1:X8} {2}' -f $e.GetType().Name,$e.HResult,(Head $e.Message 200) }
