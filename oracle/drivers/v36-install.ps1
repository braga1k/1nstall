# Installs a few made-up packages with the 3.6 helpers and a stand-in for WinGet that installs
# nothing, and prints the outcome of each. The stand-in writes every command line it receives
# to the file named by ORACLE_FIXTURE_RECORD, which the caller sets. The Rust test
# engine\harness\tests\install_sequence.rs does the same with the Rust engine and compares.
param([Parameter(Mandatory)][string]$StandIn, [Parameter(Mandatory)][string]$Work, [Parameter(Mandatory)][string]$Ids)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot)
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $repo 'src/package-helper.cs'))) -ReferencedAssemblies System.dll,System.Core.dll,System.Web.Extensions.dll
# The history goes to the work folder, and the stand-in takes the place of WinGet everywhere.
[OneInstallPackages]::DataRoot=$Work
[OneInstallPackages]::WinGetPath=$StandIn
foreach ($id in ($Ids -split ',')) {
    $record=[OneInstallPackages]::Install($StandIn,$id,'winget','Fixture',(Join-Path $Work 'logs'))
    "install $id -> $($record.Outcome) $($record.ExitCode)"
}
