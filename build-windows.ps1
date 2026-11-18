# Builds the 1nstall release: the Rust engine, then one .NET Framework executable that carries
# it, with the notices, the build metadata and the checksums beside it in dist\.
# Needs a Rust toolchain (see engine\Cargo.toml for the version). The C# side uses only the
# compiler and MSBuild that ship with Windows.
param([string]$CertificateThumbprint='', [string]$TimestampServer='')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null

# Every Rust component linked into the engine must be named, with its version, in the notices
# shown under Licenses & credits. A dependency that changed stops the build until they agree.
$noticesPath = Join-Path $root 'licenses\THIRD-PARTY-NOTICES.txt'
$notices = [IO.File]::ReadAllText($noticesPath)
$buildOnly = @()
if ($notices -match '(?m)^Used only while building, and not part of 1nstall\.exe:\r?\n\s+(.+)\.\r?$') { $buildOnly = @($Matches[1] -split ',\s*') }
Push-Location (Join-Path $root 'engine')
try {
    $ErrorActionPreference = 'Continue'
    $tree = @(& cargo tree --locked -p oneinstall-ffi --edges normal --prefix none 2>$null)
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0 -or -not $tree.Count) { throw 'Could not list the engine dependencies.' }
} finally { Pop-Location }
$unnamed = @($tree | ForEach-Object { if ($_ -match '^(\S+) v(\S+)') { [pscustomobject]@{Name=$Matches[1];Version=$Matches[2]} } } |
    Where-Object { $_.Name -notlike 'oneinstall-*' -and $buildOnly -notcontains $_.Name -and -not $notices.Contains($_.Name+' '+$_.Version+' - ') } |
    ForEach-Object { $_.Name+' '+$_.Version } | Sort-Object -Unique)
if ($unnamed.Count) { throw ('licenses\THIRD-PARTY-NOTICES.txt does not name: '+($unnamed -join ', ')) }

$line = & (Join-Path $root 'app\build.ps1') -Out $dist | Select-Object -Last 1
$exe = Join-Path $dist '1nstall.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Build failed.' }
$target = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $root 'engine\target' }
$engine = Join-Path $target 'release\oneinstall_engine.dll'

if ($CertificateThumbprint) {
    if ($TimestampServer -notmatch '^https://[^\s]+$') { throw 'An HTTPS timestamp server is required for signing.' }
    $certificate=Get-Item -LiteralPath ('Cert:\CurrentUser\My\'+$CertificateThumbprint) -ErrorAction Stop
    if (-not $certificate.HasPrivateKey -or @($certificate.EnhancedKeyUsageList | Where-Object ObjectId -eq '1.3.6.1.5.5.7.3.3').Count -eq 0) { throw 'Select an authorized code-signing certificate with a private key.' }
    $signed=Set-AuthenticodeSignature -LiteralPath $exe -Certificate $certificate -TimestampServer $TimestampServer -HashAlgorithm SHA256
    if ($signed.Status -ne 'Valid') { throw ('Signing could not be verified: '+$signed.StatusMessage) }
}
Copy-Item -LiteralPath $noticesPath -Destination (Join-Path $dist 'THIRD-PARTY-NOTICES.txt') -Force

# What the executable is built from. Build outputs inside the engine folders are not inputs.
$inputs = New-Object 'System.Collections.Generic.List[string]'
foreach ($name in @('catalog.json','profiles.json','locales.json','interface.xaml','src/1nstall.ico','src/app.manifest','src/motion.cs','src/appearance.cs','src/window-helper.cs','src/update-helper.cs','licenses/THIRD-PARTY-NOTICES.txt','build-windows.ps1','app/build.ps1','app/1nstall.csproj','engine/Cargo.toml','engine/Cargo.lock')) { $inputs.Add($name) }
foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $root 'app') -Filter '*.cs' -File)) { $inputs.Add('app/'+$file.Name) }
foreach ($crate in @('core','platform','ffi')) {
    $folder = Join-Path $root ('engine\'+$crate)
    foreach ($file in (Get-ChildItem -LiteralPath $folder -Recurse -File | Where-Object { $_.FullName -notmatch '\\target\\' })) {
        $inputs.Add(('engine/'+$crate+'/'+$file.FullName.Substring($folder.Length+1)).Replace('\','/'))
    }
}
$hashes=[ordered]@{}
foreach ($inputPath in ($inputs | Sort-Object -Unique)) { $hashes[$inputPath]=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root $inputPath)).Hash.ToLowerInvariant() }

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
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$metadata=[ordered]@{
    Product='1nstall'; Version=([Reflection.AssemblyName]::GetAssemblyName($exe).Version).ToString(3); BuiltAtUtc=[DateTime]::UtcNow.ToString('o');
    UpstreamBase='d158884bb63bc0b11de5de84ee15189e3b334d22'; SourceCommit=$commit; SourceDirty=$sourceDirty;
    Windows=[Environment]::OSVersion.Version.ToString(); PowerShell=$PSVersionTable.PSVersion.ToString();
    Compiler=$compiler; CompilerSHA256=(Get-FileHash $compiler -Algorithm SHA256).Hash.ToLowerInvariant();
    Rust=((& rustc --version | Out-String).Trim()); Cargo=((& cargo --version | Out-String).Trim());
    Signed=([bool]$CertificateThumbprint); ExeSHA256=(Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant();
    EngineSHA256=(Get-FileHash $engine -Algorithm SHA256).Hash.ToLowerInvariant();
    Inputs=$hashes
}
$metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dist 'BUILD-INFO.json') -Encoding UTF8
$sums=@('1nstall.exe','BUILD-INFO.json','THIRD-PARTY-NOTICES.txt') | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $dist $_) -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$_ }
[IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS.txt'),[string[]]$sums,[Text.UTF8Encoding]::new($false))
Write-Output $line
Write-Output "$dist\1nstall.exe"
