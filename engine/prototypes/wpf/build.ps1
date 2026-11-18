# Prototype 3 of 3: the 3.6 WPF interface, without PowerShell, over the Rust engine DLL.
# Uses only the .NET Framework compiler and MSBuild that ship with Windows, as build-windows.ps1 does.
param([Parameter(Mandatory)][string]$Out, [Parameter(Mandatory)][string]$EngineDll)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
New-Item -ItemType Directory -Path (Join-Path $Out 'ui-src') -Force | Out-Null
$Out = (Resolve-Path $Out).Path
$xaml = [IO.File]::ReadAllText((Join-Path $root 'interface.xaml')).Replace('<Window xmlns=', '<Window x:Class="OneInstall.MainWindow" xmlns=')
[IO.File]::WriteAllText((Join-Path $Out 'ui-src\interface.xaml'), $xaml)
& "$framework\MSBuild.exe" (Join-Path $PSScriptRoot 'ui.csproj') /nologo /verbosity:minimal "/p:Out=$Out" "/p:Root=$root"
if ($LASTEXITCODE -ne 0) { throw 'Compiled interface build failed.' }
$wpf = Join-Path $framework 'WPF'
& "$framework\csc.exe" /nologo /target:winexe /platform:x64 /optimize+ /warnaserror+ /reference:System.Core.dll /reference:System.Web.Extensions.dll /reference:System.Xaml.dll "/reference:$wpf\PresentationFramework.dll" "/reference:$wpf\PresentationCore.dll" "/reference:$wpf\WindowsBase.dll" "/reference:$Out\1nstall.UI.dll" "/win32manifest:$root\src\app.manifest" "/win32icon:$root\src\1nstall.ico" "/out:$Out\oneinstall-wpf.exe" (Join-Path $PSScriptRoot 'Program.cs') "$root\src\appearance.cs" "$root\src\window-helper.cs"
if ($LASTEXITCODE -ne 0) { throw 'Host build failed.' }
Copy-Item -LiteralPath $EngineDll -Destination (Join-Path $Out 'oneinstall_ffi.dll') -Force
Remove-Item -LiteralPath (Join-Path $Out 'ui-obj'), (Join-Path $Out 'ui-src') -Recurse -Force
Get-ChildItem -LiteralPath $Out -File | Select-Object Name, Length
