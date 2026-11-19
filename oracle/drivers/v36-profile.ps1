# Reads the files 1nstall keeps in the profile of the current Windows user with the 3.6
# helpers, and prints one line per file: how many records, and a fingerprint of what was read.
# It only reads, and prints no content. The Rust test engine\harness\tests\real_profile.rs
# prints the same lines for the Rust engine; the two must be equal.
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot)
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $repo 'src/package-helper.cs'))) -ReferencedAssemblies System.dll,System.Core.dll,System.Web.Extensions.dll
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $repo 'src/uninstall-helper.cs'))) -ReferencedAssemblies System.dll,System.Core.dll,System.Web.Extensions.dll
Add-Type -TypeDefinition @'
public static class ProfileFingerprint {
    // FNV-1a, 64 bits, over the UTF-8 bytes.
    public static string Of(string text) {
        ulong hash=14695981039346656037UL;
        foreach(byte value in System.Text.Encoding.UTF8.GetBytes(text)) { hash^=value; unchecked { hash*=1099511628211UL; } }
        return hash.ToString("x16");
    }
}
'@
$field=[string][char]0x1F; $record=[string][char]0x1E
function Flag($value) { if ($value) { '1' } else { '0' } }
$rows=@([OneInstallPackages]::History())
$unreadable=-not [string]::IsNullOrEmpty([OneInstallPackages]::HistoryError)
$lines=@($rows | ForEach-Object { @($_.Timestamp,$_.Action,$_.Id,$_.Source,$_.Name,$_.Outcome,$_.Message,$_.LogPath,[string]$_.ExitCode) -join $field })
"profile operations: count=$($rows.Count) unreadable=$(Flag $unreadable) fingerprint=$([ProfileFingerprint]::Of($lines -join $record))"
$apps=@([OneInstallUninstall]::LoadHistory())
$lines=@($apps | ForEach-Object { @($_.Id,$_.Name,$_.Publisher,$_.Version,$_.Kind,$_.Location,$_.Command,$_.RegistryPath,$_.PackageFamily,(Flag $_.Machine),(Flag $_.View32),(Flag $_.Msi),(Flag $_.RemovalVerified),(Flag $_.OwnershipVerified),(Flag $_.IdentityVerified),[string]$_.RestartRequestedAt,(Flag $_.CanRemove),[string]$_.SizeKB) -join $field })
"profile removals: count=$($apps.Count) fingerprint=$([ProfileFingerprint]::Of($lines -join $record))"
