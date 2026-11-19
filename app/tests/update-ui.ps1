# Checks, downloads and applies an update from the Settings page of a built 1nstall.exe, in
# its NORMAL mode, against the real releases on GitHub. Needs an interactive desktop.
#
# The executable given here must be a build of the same code with a version number below the
# latest published release (the CI job builds one as 3.5.0): it then finds that release,
# downloads it, verifies it and replaces itself with it. What it must download is read from
# the checksum file of that release, unless -ExpectedHash names it. The test writes to
# %LOCALAPPDATA%\1nstall and replaces the executable, so it runs only on a disposable machine.
param([Parameter(Mandatory)][string]$Exe, [string]$ExpectedHash='', [switch]$DisposableEnvironment)
if (-not $DisposableEnvironment) { throw 'This test replaces the executable and writes to the profile. Run it only on a disposable machine, with -DisposableEnvironment.' }
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
function Hash([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
$exe=(Resolve-Path -LiteralPath $Exe).Path
$data=Join-Path $env:LOCALAPPDATA '1nstall'
$original=Hash $exe
if (-not $ExpectedHash) {
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $listed=Join-Path $env:TEMP ('1nstall-latest-sums-'+$PID+'.txt')
    Invoke-WebRequest -Uri 'https://github.com/braga1k/1nstall/releases/latest/download/SHA256SUMS.txt' -OutFile $listed -UseBasicParsing
    $ExpectedHash=@(Get-Content -LiteralPath $listed | Where-Object { $_ -match '^([a-f0-9]{64})\s+\*?1nstall\.exe\s*$' } | ForEach-Object { $Matches[1] })[0]
    Remove-Item -LiteralPath $listed
    if (-not $ExpectedHash) { throw 'The latest release lists no checksum for 1nstall.exe.' }
}
$identity=[Reflection.AssemblyName]::GetAssemblyName($exe)
Check "the build under test is numbered below the published releases ($($identity.Version))" ($identity.Version.Major -eq 3 -and $identity.Version.Minor -lt 6)
$root=Start-App ''
try {
    Invoke (Named $root 'Settings')
    $switch=ById $root 'AutoUpdateChoice'
    if ($switch.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -ne 'On') { Toggle $switch }
    $answers='Update ready. It will be applied when you close 1nstall.','1nstall is up to date.','Could not check or download the update. Try again later.'
    $answer=Wait-Until { Texts $root | Where-Object { $answers -contains $_ } | Select-Object -First 1 } 20 500
    if ($answer -ne $answers[0]) {
        Invoke (Named $root 'Check now') 1500
        $answer=Wait-Until { Texts $root | Where-Object { $_ -eq $answers[0] -or $_ -eq $answers[2] } | Select-Object -First 1 } 240 500
    }
    "NOTE the update check answered: $answer"
    if ($answer -eq $answers[2]) {
        # GitHub's public interface answers a limited number of requests per address and hour,
        # and CI machines share addresses. Without its answer there is nothing to test here.
        'NOTE GitHub did not answer the update check from this machine; the update was not exercised in this run'
        "update ui: $failed failed"
        if (-not $process.HasExited) { $process.Kill() }
        if ($failed) { exit 1 }
        return
    }
    Check 'the newer release is found, downloaded and verified' ($answer -eq $answers[0])
    $folder=@(Get-ChildItem -LiteralPath (Join-Path $data 'Updates') -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1)
    $downloaded=if ($folder.Count) { Join-Path $folder[0].FullName '1nstall.exe' } else { '' }
    Check "the download is the executable of the latest release ($(if ($folder.Count) { $folder[0].Name }): $(if ($downloaded -and (Test-Path -LiteralPath $downloaded)) { Hash $downloaded }))" ($downloaded -and (Test-Path -LiteralPath $downloaded) -and (Hash $downloaded) -eq $ExpectedHash)
    $apply=@(Buttons $root 'Restart and update')
    Check 'Restart and update is offered' ($apply.Count -eq 1 -and $apply[0].Current.IsEnabled)
    if ($apply.Count -eq 1 -and $apply[0].Current.IsEnabled) {
        Invoke $apply[0] 500
        Check 'the application closes to be replaced' ($process.WaitForExit(20000))
        $replaced=Wait-Until { (Hash $exe) -eq $ExpectedHash } 90 1000
        Check 'the executable was replaced by the downloaded release' ([bool]$replaced)
        Check 'the replaced executable is kept beside it' ((Test-Path -LiteralPath ($exe+'.previous')) -and (Hash ($exe+'.previous')) -eq $original)
        Check 'no update error was recorded' (-not (Test-Path -LiteralPath (Join-Path $data 'update-error.log')))
        # The update restarts the application: now the published release. It is closed again.
        $restarted=Wait-Until { @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq $exe }) } 30 1000
        Check 'the updated application was started again' ([bool]$restarted)
        Start-Sleep -Seconds 5
        foreach ($instance in @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq $exe -or ($_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*1nstall*') })) { Stop-Process -Id $instance.ProcessId -Force -ErrorAction SilentlyContinue }
    }
} finally { if ($process -and -not $process.HasExited) { $process.Kill() } }
"update ui: $failed failed"
if ($failed) { exit 1 }
