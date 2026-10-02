# Build with the .NET Framework compiler included in Windows.
param([string]$CertificateThumbprint='', [string]$TimestampServer='')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$source = [IO.File]::ReadAllText((Join-Path $root 'vexan_installers.ps1'))
$source = $source.Replace('@@CATALOG@@', [IO.File]::ReadAllText((Join-Path $root 'catalog.json')))
$source = $source.Replace('@@XAML@@', [IO.File]::ReadAllText((Join-Path $root 'interface.xaml')))
$source = $source.Replace('@@ICON@@', [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root 'src\1nstall.ico'))))
$source = $source.Replace('@@WINDOW_HELPER@@', [IO.File]::ReadAllText((Join-Path $root 'src\window-helper.cs')))
$source = $source.Replace('@@PROFILES@@', [IO.File]::ReadAllText((Join-Path $root 'profiles.json')))
$source = $source.Replace('@@UNINSTALL_HELPER@@', [IO.File]::ReadAllText((Join-Path $root 'src\uninstall-helper.cs')))
$source = $source.Replace('@@THIRD_PARTY_NOTICES@@', [IO.File]::ReadAllText((Join-Path $root 'licenses\THIRD-PARTY-NOTICES.txt')))
$source = $source.Replace('@@PACKAGE_HELPER@@', [IO.File]::ReadAllText((Join-Path $root 'src\package-helper.cs')))
$source = $source.Replace('@@MANAGER_UI@@', [IO.File]::ReadAllText((Join-Path $root 'src\manager-ui.ps1')))
$source = $source.Replace('@@MANAGER_TEST@@', [IO.File]::ReadAllText((Join-Path $root 'tests\manager-ui.ps1')))
$payload = Join-Path $dist '1nstall.embedded.ps1'
[IO.File]::WriteAllText($payload, $source, [Text.UTF8Encoding]::new($true))
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /warnaserror+ /reference:System.Windows.Forms.dll "/win32manifest:$root\src\app.manifest" "/win32icon:$root\src\1nstall.ico" "/resource:$payload,1nstall.Payload" "/out:$dist\1nstall.exe" "$root\src\launcher.cs"
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
$exe=Join-Path $dist '1nstall.exe'
if ($CertificateThumbprint) {
    if ($TimestampServer -notmatch '^https://[^\s]+$') { throw 'An HTTPS timestamp server is required for signing.' }
    $certificate=Get-Item -LiteralPath ('Cert:\CurrentUser\My\'+$CertificateThumbprint) -ErrorAction Stop
    if (-not $certificate.HasPrivateKey -or @($certificate.EnhancedKeyUsageList | Where-Object ObjectId -eq '1.3.6.1.5.5.7.3.3').Count -eq 0) { throw 'Select an authorized code-signing certificate with a private key.' }
    $signed=Set-AuthenticodeSignature -LiteralPath $exe -Certificate $certificate -TimestampServer $TimestampServer -HashAlgorithm SHA256
    if ($signed.Status -ne 'Valid') { throw ('Signing could not be verified: '+$signed.StatusMessage) }
}
Copy-Item -LiteralPath (Join-Path $root 'licenses\THIRD-PARTY-NOTICES.txt') -Destination (Join-Path $dist 'THIRD-PARTY-NOTICES.txt')
$inputs=@('vexan_installers.ps1','catalog.json','profiles.json','interface.xaml','src/1nstall.ico','src/package-helper.cs','src/manager-ui.ps1','src/uninstall-helper.cs','src/window-helper.cs','src/launcher.cs','src/app.manifest','tests/manager-ui.ps1','licenses/THIRD-PARTY-NOTICES.txt','build-windows.ps1')
$hashes=[ordered]@{}
foreach ($inputPath in $inputs) { $hashes[$inputPath]=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root $inputPath)).Hash.ToLowerInvariant() }
$commit=$null; $sourceDirty=$null
if (Get-Command git -ErrorAction SilentlyContinue) {
    try {
        # An extracted source ZIP must not inherit a parent directory's unrelated Git identity.
        $prefix=(& git -C $root rev-parse --show-prefix 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $prefix -eq '') {
            $revision=(& git -C $root rev-parse HEAD 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -eq 0) {
                $commit=$revision
                $status=(& git -C $root status --porcelain 2>$null | Out-String)
                if ($LASTEXITCODE -eq 0) { $sourceDirty=-not [string]::IsNullOrWhiteSpace($status) }
            }
        }
    } catch { } # Git is optional for source-ZIP builds; unavailable provenance remains null.
}
$metadata=[ordered]@{
    Product='1nstall'; Version='3.2.0-review'; BuiltAtUtc=[DateTime]::UtcNow.ToString('o');
    UpstreamBase='c97f780a05726bbaaea11d0636170a9126bd0cf5'; SourceCommit=$commit; SourceDirty=$sourceDirty;
    Windows=[Environment]::OSVersion.Version.ToString(); PowerShell=$PSVersionTable.PSVersion.ToString();
    Compiler=$compiler; CompilerSHA256=(Get-FileHash $compiler -Algorithm SHA256).Hash.ToLowerInvariant();
    Signed=([bool]$CertificateThumbprint); ExeSHA256=(Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant();
    Inputs=$hashes
}
$metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dist 'BUILD-INFO.json') -Encoding UTF8
$sums=@('1nstall.exe','BUILD-INFO.json','THIRD-PARTY-NOTICES.txt') | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $dist $_) -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$_ }
[IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS.txt'),[string[]]$sums,[Text.UTF8Encoding]::new($false))
Write-Output "$dist\1nstall.exe"
