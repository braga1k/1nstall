# Checks of the release that need a throw-away machine: building again from the source archive
# alone, signing with a test certificate, and how long the packaged executable takes to start
# here. Run on a CI runner, never on a PC that is in use: it installs a self-signed
# certificate as a trusted root of the machine.
#   .\scripts\release-checks.ps1 -Assets <folder with the release assets> -DisposableEnvironment
param([Parameter(Mandatory)][string]$Assets, [string]$Work='C:\rc', [switch]$DisposableEnvironment)
if (-not $DisposableEnvironment) { throw 'Run only on a disposable machine, with -DisposableEnvironment.' }
$ErrorActionPreference='Stop'
$failed=0
function Check([string]$name,[bool]$condition) { if ($condition) { "PASS $name" } else { "FAIL $name"; $script:failed++ } }
function Hash([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Self-Test([string]$exe) {
    $run=Start-Process -FilePath $exe -ArgumentList '--self-test' -Wait -PassThru -WindowStyle Hidden
    $log=Join-Path (Split-Path $exe) 'self-test.log'
    $passed=if (Test-Path -LiteralPath $log) { @(Get-Content -LiteralPath $log | Where-Object { $_ -like 'PASS *' }).Count } else { 0 }
    [pscustomobject]@{ Code=$run.ExitCode; Passed=$passed }
}
$assets=(Resolve-Path -LiteralPath $Assets).Path
$archive=@(Get-ChildItem -LiteralPath $assets -Filter '1nstall-*-source.zip')
if ($archive.Count -ne 1) { throw 'Expected one source archive among the assets.' }
if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Path $Work | Out-Null

# 1. The source archive alone builds the application: no Git history, nothing else.
$source=Join-Path $Work 'src'
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($archive[0].FullName,$source)
Check 'the source archive carries no Git history' (-not (Test-Path -LiteralPath (Join-Path $source '.git')))
$record=Get-Content -LiteralPath (Join-Path $source 'RELEASE-SOURCE.json') -Raw | ConvertFrom-Json
$output=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'build-windows.ps1') 2>&1 | ForEach-Object { "$_" })
$built=Join-Path $source 'dist\1nstall.exe'
Check "the source archive builds the executable (exit $LASTEXITCODE; $($output | Select-Object -Last 2 | Select-Object -First 1))" ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $built))
if (Test-Path -LiteralPath $built) {
    $info=Get-Content -LiteralPath (Join-Path $source 'dist\BUILD-INFO.json') -Raw | ConvertFrom-Json
    Check "a build without Git says its commit is unknown, not a wrong one (commit '$($info.SourceCommit)', dirty '$($info.SourceDirty)')" ($null -eq $info.SourceCommit -and $null -eq $info.SourceDirty)
    $different=@($record.Inputs.PSObject.Properties | Where-Object { $info.Inputs.($_.Name) -ne $_.Value } | ForEach-Object { $_.Name })
    Check "it is built from the same inputs as the release ($(@($record.Inputs.PSObject.Properties).Count) files; different: $($different -join ', '))" ($different.Count -eq 0 -and @($info.Inputs.PSObject.Properties).Count -eq @($record.Inputs.PSObject.Properties).Count)
    $test=Self-Test $built
    Check "the executable built from the archive passes its self-test ($($test.Passed) checks, exit $($test.Code))" ($test.Code -eq 0 -and $test.Passed -ge 31)
    $released=Join-Path $assets '1nstall.exe'
    "NOTE built from the archive: $((Get-Item -LiteralPath $built).Length) bytes, sha256 $(Hash $built); released: $((Get-Item -LiteralPath $released).Length) bytes, sha256 $(Hash $released); engine identical: $($info.EngineSHA256 -eq (Get-Content -LiteralPath (Join-Path $assets 'BUILD-INFO.json') -Raw | ConvertFrom-Json).EngineSHA256)"

    # 2. The optional code signing, with a certificate made here and trusted on this machine only.
    $certificate=New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=1nstall test signing (not a release certificate)' -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddDays(2)
    $exported=Join-Path $Work 'test-signing.cer'
    Export-Certificate -Cert $certificate -FilePath $exported | Out-Null
    Import-Certificate -FilePath $exported -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Import-Certificate -FilePath $exported -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null
    $signedWith=$null
    foreach ($server in 'https://timestamp.digicert.com','https://timestamp.sectigo.com','https://timestamp.globalsign.com/tsa/r6advanced1') {
        $output=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'build-windows.ps1') -CertificateThumbprint $certificate.Thumbprint -TimestampServer $server 2>&1 | ForEach-Object { "$_" })
        if ($LASTEXITCODE -eq 0) { $signedWith=$server; break }
        "NOTE signing with $server did not work: $(($output | Where-Object { $_ -match 'Signing|timestamp|certificate' } | Select-Object -Last 1))"
    }
    Check "the build signs the executable when given a certificate and a timestamp server ($signedWith)" ([bool]$signedWith)
    if ($signedWith) {
        $signature=Get-AuthenticodeSignature -LiteralPath $built
        Check "the signature is valid and timestamped ($($signature.Status); signer $($signature.SignerCertificate.Subject))" ($signature.Status -eq 'Valid' -and $signature.SignerCertificate.Thumbprint -eq $certificate.Thumbprint -and $null -ne $signature.TimeStamperCertificate)
        $info=Get-Content -LiteralPath (Join-Path $source 'dist\BUILD-INFO.json') -Raw | ConvertFrom-Json
        Check 'the build record says the executable is signed, with the hash of the signed file' ($info.Signed -eq $true -and $info.ExeSHA256 -eq (Hash $built))
        $test=Self-Test $built
        Check "the signed executable passes its self-test ($($test.Passed) checks, exit $($test.Code))" ($test.Code -eq 0 -and $test.Passed -ge 31)
        $identity=[Reflection.AssemblyName]::GetAssemblyName($built)
        Check "the 3.6 updater still accepts the signed executable ($($identity.Name) $($identity.Version))" ($identity.Name -ceq '1nstall' -and $identity.Version.ToString(3) -eq $info.Version)
    }
}

# 3. How long the packaged executable takes to be ready on this machine, and its peak memory.
$place=Join-Path $Work 'm'; New-Item -ItemType Directory -Path $place | Out-Null
Copy-Item -LiteralPath (Join-Path $assets '1nstall.exe') -Destination $place
$ready=@(); $peaks=@()
foreach ($round in 1..6) {
    $run=Start-Process -FilePath (Join-Path $place '1nstall.exe') -ArgumentList '--startup-test' -Wait -PassThru
    $log=Join-Path $place 'startup-test.log'
    if ($run.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $log)) { continue }
    $text=Get-Content -LiteralPath $log -Raw
    if ($text -match '(?m)^READY (\d+)') { $ready+=[int]$Matches[1] }
    if ($text -match 'Mark peak working set (\d+) MB') { $peaks+=[int]$Matches[1] }
}
Check "the packaged executable reaches the ready mark here ($($ready.Count) of 6 runs)" ($ready.Count -eq 6)
if ($ready.Count) {
    $warm=@($ready | Select-Object -Skip 1 | Sort-Object)
    "NOTE start-up on this runner ($([Environment]::OSVersion.Version), $([Environment]::ProcessorCount) processors, no graphics card): first run $($ready[0]) ms; then median $($warm[[int][Math]::Floor($warm.Count/2)]) ms (from $($warm[0]) to $($warm[-1])); peak working set $(($peaks | Measure-Object -Maximum).Maximum) MB"
}
"release checks: $failed failed"
if ($failed) { exit 1 }
