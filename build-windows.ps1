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
$source = $source.Replace('@@WINDOW_HELPER@@', '')
$source = $source.Replace('@@MOTION_HELPER@@', '')
$source = $source.Replace('@@APPEARANCE_HELPER@@', '')
$source = $source.Replace('@@PROFILES@@', [IO.File]::ReadAllText((Join-Path $root 'profiles.json')))
$source = $source.Replace('@@UNINSTALL_HELPER@@', '')
$source = $source.Replace('@@THIRD_PARTY_NOTICES@@', [IO.File]::ReadAllText((Join-Path $root 'licenses\THIRD-PARTY-NOTICES.txt')))
$source = $source.Replace('@@PACKAGE_HELPER@@', '')
$settings=[IO.File]::ReadAllText((Join-Path $root 'src\settings.ps1')).Replace('@@LOCALES@@',[IO.File]::ReadAllText((Join-Path $root 'locales.json')))
$source = $source.Replace('@@SETTINGS@@', [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($settings)))
$source = $source.Replace('@@UPDATE_HELPER@@', [IO.File]::ReadAllText((Join-Path $root 'src\update-helper.cs')))
$source = $source.Replace('@@MANAGER_UI@@', [IO.File]::ReadAllText((Join-Path $root 'src\manager-ui.ps1')))
$source = $source.Replace('@@MANAGER_TEST@@', [IO.File]::ReadAllText((Join-Path $root 'tests\manager-ui.ps1')))
$payload = Join-Path $dist '1nstall.embedded.ps1'
[IO.File]::WriteAllText($payload, $source, [Text.UTF8Encoding]::new($true))
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$helpers=Join-Path $dist '1nstall.Helpers.dll'
& $compiler /nologo /target:library /platform:x64 /optimize+ /warnaserror+ /reference:System.Web.Extensions.dll "/out:$helpers" "$root\src\package-helper.cs" "$root\src\uninstall-helper.cs" "$root\src\window-helper.cs" "$root\src\update-helper.cs"
if ($LASTEXITCODE -ne 0) { throw 'Helper build failed.' }
$compiledXaml=[IO.File]::ReadAllText((Join-Path $root 'interface.xaml')).Replace('<Window xmlns=', '<Window x:Class="OneInstall.MainWindow" xmlns=')
[IO.File]::WriteAllText((Join-Path $dist 'interface.xaml'),$compiledXaml)
& "$env:WINDIR/Microsoft.NET/Framework64/v4.0.30319/MSBuild.exe" "$root\src\ui.csproj" /nologo /verbosity:minimal
if ($LASTEXITCODE -ne 0) { throw 'Compiled interface build failed.' }
# Reuse the app's vector symbol, rather than maintain a second splash logo.
$document=[xml][IO.File]::ReadAllText((Join-Path $root 'interface.xaml'))
$symbol=$document.SelectSingleNode("//*[local-name()='DrawingImage']")
$symbol.RemoveAttribute('Key','http://schemas.microsoft.com/winfx/2006/xaml')
[IO.File]::WriteAllText((Join-Path $dist 'symbol.xaml'),$symbol.OuterXml)
$sma=(Get-ChildItem "$env:WINDIR/Microsoft.NET/assembly/GAC_MSIL/System.Management.Automation" -Recurse -Filter System.Management.Automation.dll | Select-Object -First 1).FullName
$wpf=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/WPF'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /warnaserror+ "/reference:$sma" /reference:System.Core.dll /reference:System.Web.Extensions.dll /reference:System.Xaml.dll "/reference:$wpf\PresentationFramework.dll" "/reference:$wpf\PresentationCore.dll" "/reference:$wpf\WindowsBase.dll" "/win32manifest:$root\src\app.manifest" "/win32icon:$root\src\1nstall.ico" "/resource:$payload,1nstall.Payload" "/resource:$dist\symbol.xaml,1nstall.Symbol" "/resource:$root\catalog.json,1nstall.Catalog" "/resource:$helpers,1nstall.Helpers" "/resource:$dist\1nstall.UI.dll,1nstall.UI" "/out:$dist\1nstall.exe" "$root\src\launcher.cs" "$root\src\startup.cs" "$root\src\appearance.cs"
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
$inputs=@('vexan_installers.ps1','catalog.json','profiles.json','interface.xaml','src/1nstall.ico','src/package-helper.cs','src/manager-ui.ps1','src/uninstall-helper.cs','src/window-helper.cs','src/launcher.cs','src/ui-helper.cs','src/motion.cs','src/startup.cs','src/appearance.cs','src/ui.csproj','src/settings.ps1','src/update-helper.cs','locales.json','src/app.manifest','tests/manager-ui.ps1','licenses/THIRD-PARTY-NOTICES.txt','build-windows.ps1')
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
    Product='1nstall'; Version='3.5.0'; BuiltAtUtc=[DateTime]::UtcNow.ToString('o');
    UpstreamBase='d158884bb63bc0b11de5de84ee15189e3b334d22'; SourceCommit=$commit; SourceDirty=$sourceDirty;
    Windows=[Environment]::OSVersion.Version.ToString(); PowerShell=$PSVersionTable.PSVersion.ToString();
    Compiler=$compiler; CompilerSHA256=(Get-FileHash $compiler -Algorithm SHA256).Hash.ToLowerInvariant();
    Signed=([bool]$CertificateThumbprint); ExeSHA256=(Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant();
    Inputs=$hashes
}
$metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dist 'BUILD-INFO.json') -Encoding UTF8
$sums=@('1nstall.exe','BUILD-INFO.json','THIRD-PARTY-NOTICES.txt') | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $dist $_) -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$_ }
[IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS.txt'),[string[]]$sums,[Text.UTF8Encoding]::new($false))
Write-Output "$dist\1nstall.exe"
