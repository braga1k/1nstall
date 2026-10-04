# Prepare release assets from a clean checkout and its source-built executable.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$dist=Join-Path $root 'dist'
$release=Join-Path $dist 'release'
$portable=Join-Path $dist 'portable-3.4.0'
$source=Join-Path $dist 'source-3.4.0'
$info=Get-Content -LiteralPath (Join-Path $dist 'BUILD-INFO.json') -Raw | ConvertFrom-Json
$head=(& git -C $root rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $head -or $info.SourceCommit -ne $head -or $null -eq $info.SourceDirty -or $info.SourceDirty) { throw 'Packaging requires a clean source build from this commit.' }
if ((& git -C $root status --porcelain | Out-String).Trim()) { throw 'Commit source changes before packaging.' }
foreach ($folder in @($release,$portable,$source)) {
    if (Test-Path -LiteralPath $folder) { throw ('Packaging output already exists; use a fresh checkout/build directory: '+$folder) }
    New-Item -ItemType Directory -Path $folder | Out-Null
}
foreach ($name in @('1nstall.exe','BUILD-INFO.json','THIRD-PARTY-NOTICES.txt','self-test.log')) {
    Copy-Item -LiteralPath (Join-Path $dist $name) -Destination (Join-Path $portable $name)
}
if ((Get-FileHash -LiteralPath (Join-Path $portable '1nstall.exe') -Algorithm SHA256).Hash.ToLowerInvariant() -ne $info.ExeSHA256) { throw 'Executable/build metadata mismatch.' }
Copy-Item -LiteralPath (Join-Path $root 'docs/releases/3.4.0.md') -Destination (Join-Path $portable 'README.md')
foreach ($name in @('VALIDATION.md','RELEASE-REVIEW.md','WINGET-CAPABILITIES.md','SETTINGS.md','localization.md')) {
    Copy-Item -LiteralPath (Join-Path $root ('docs/'+$name)) -Destination (Join-Path $portable $name)
}
foreach ($name in @('catalog.txt','reliability.txt','locales.txt')) {
    Copy-Item -LiteralPath (Join-Path $root ('test-logs/'+$name)) -Destination (Join-Path $portable ('CI-'+$name))
}
$portableSums=@(Get-ChildItem -LiteralPath $portable -File | Sort-Object Name | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$_.Name })
[IO.File]::WriteAllLines((Join-Path $portable 'SHA256SUMS.txt'),[string[]]$portableSums,[Text.UTF8Encoding]::new($false))
# Copy tracked working bytes, including Windows line endings, so build-input hashes match.
foreach ($file in (& git -C $root ls-files)) {
    $target=Join-Path $source $file
    New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $target
}
foreach ($inputFile in $info.Inputs.PSObject.Properties) {
    if ((Get-FileHash -LiteralPath (Join-Path $source $inputFile.Name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $inputFile.Value) { throw ('Source archive differs from build input: '+$inputFile.Name) }
}
[ordered]@{UpstreamBase=$info.UpstreamBase;ReleaseCommit=$head;Inputs=$info.Inputs} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $source 'RELEASE-SOURCE.json') -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($portable,(Join-Path $release '1nstall-3.4.0-Windows-x64.zip'))
[IO.Compression.ZipFile]::CreateFromDirectory($source,(Join-Path $release '1nstall-3.4.0-source.zip'))
foreach ($name in @('1nstall.exe','BUILD-INFO.json','THIRD-PARTY-NOTICES.txt','self-test.log','CI-catalog.txt','CI-reliability.txt','CI-locales.txt')) {
    Copy-Item -LiteralPath (Join-Path $portable $name) -Destination (Join-Path $release $name)
}
$sums=@(Get-ChildItem -LiteralPath $release -File | Sort-Object Name | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$_.Name })
[IO.File]::WriteAllLines((Join-Path $release 'SHA256SUMS.txt'),[string[]]$sums,[Text.UTF8Encoding]::new($false))
Write-Output 'PASS: portable/source archives, source-input hashes and release checksums verified.'
