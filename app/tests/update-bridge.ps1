# Proves that the updater of 1nstall 3.6 accepts a 4.0 executable, and can apply it.
#
# Part 1 runs anywhere and only reads: it repeats the identity check of src/update-helper.cs
# ("Release executable version mismatch") against the built executable.
#
# Part 2 runs only with -DisposableEnvironment, because it writes to %LOCALAPPDATA%\1nstall.
# It runs the released 3.6 executable's own "--apply-update" step, the one 3.6 starts after a
# download, to replace an installed 3.6 with the 4.0 executable, then starts the result.
param(
    [Parameter(Mandatory)][string]$Exe,
    [string]$Version='4.0.0',
    [string]$Released36='',
    [switch]$DisposableEnvironment
)
$ErrorActionPreference='Stop'
$exe=(Resolve-Path -LiteralPath $Exe).Path
function Hash([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Encode([string]$value) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($value)) }

# Part 1. update-helper.cs: identity.Name!="1nstall" || new Version(Major,Minor,Build)!=new Version(result.Version)
$identity=[Reflection.AssemblyName]::GetAssemblyName($exe)
$accepted=($identity.Name -ceq '1nstall') -and ((New-Object Version $identity.Version.Major,$identity.Version.Minor,$identity.Version.Build) -eq (New-Object Version $Version))
"bridge identity: assembly '$($identity.Name)' version $($identity.Version) against release $Version -> $(if ($accepted) { 'accepted' } else { 'REFUSED' })"
if (-not $accepted) { throw 'The 3.6 updater would refuse this executable.' }

if (-not $DisposableEnvironment) { 'bridge apply: skipped; pass -DisposableEnvironment and -Released36 on a disposable machine'; return }
if (-not $Released36) { throw '-Released36 must point at the released 3.6 executable.' }
$old=(Resolve-Path -LiteralPath $Released36).Path
$oldIdentity=[Reflection.AssemblyName]::GetAssemblyName($old)
if ($oldIdentity.Version.Major -ne 3) { throw "Expected a 3.x executable, found $($oldIdentity.Version)." }

# Part 2. The layout OneInstallUpdate.Schedule creates: the verified download under Updates\<version>,
# and a copy of the installed (old) executable beside it as the worker.
$updates=Join-Path $env:LOCALAPPDATA "1nstall\Updates\$Version"
New-Item -ItemType Directory -Path $updates -Force | Out-Null
$source=Join-Path $updates '1nstall.exe'
Copy-Item -LiteralPath $exe -Destination $source -Force
$install=Join-Path $env:TEMP ('1nstall-bridge-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $install | Out-Null
$target=Join-Path $install '1nstall.exe'
Copy-Item -LiteralPath $old -Destination $target
$worker=Join-Path $updates ('apply-'+[Guid]::NewGuid().ToString('N')+'.exe')
Copy-Item -LiteralPath $target -Destination $worker
$newHash=Hash $source; $oldHash=Hash $target
# The worker waits for the process that scheduled the update; hand it one that has already ended.
$ended=Start-Process -FilePath "$env:WINDIR\System32\cmd.exe" -ArgumentList '/c exit' -PassThru -WindowStyle Hidden; $ended.WaitForExit()
$arguments=@('--apply-update',$ended.Id,(Encode $target),(Encode $source),$newHash,$oldHash,'0')
$apply=Start-Process -FilePath $worker -ArgumentList $arguments -PassThru -WindowStyle Hidden
if (-not $apply.WaitForExit(120000)) { $apply.Kill(); throw 'The 3.6 apply step did not finish in 120 s.' }
$errorLog=Join-Path $env:LOCALAPPDATA '1nstall\update-error.log'
if ($apply.ExitCode -ne 0) { throw ("The 3.6 apply step failed with exit code $($apply.ExitCode). "+$(if (Test-Path -LiteralPath $errorLog) { Get-Content -LiteralPath $errorLog -Raw } else { '' })) }
if ((Hash $target) -ne $newHash) { throw 'The installed executable was not replaced.' }
$previous=$target+'.previous'
if (-not (Test-Path -LiteralPath $previous) -or (Hash $previous) -ne $oldHash) { throw 'The previous executable was not kept.' }
$replaced=[Reflection.AssemblyName]::GetAssemblyName($target)
$check=Start-Process -FilePath $target -ArgumentList '--self-test' -PassThru -Wait -WindowStyle Hidden
if ($check.ExitCode -ne 0) { throw 'The updated executable failed its self-test.' }
"bridge apply: the released $($oldIdentity.Version) executable replaced itself with $($replaced.Version); previous copy kept; the updated executable passed its self-test"
Remove-Item -LiteralPath $worker -Force -ErrorAction SilentlyContinue
