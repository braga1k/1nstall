param([string]$Repo=(Split-Path (Split-Path $PSScriptRoot)))
# Manual check: needs a normal, non-elevated desktop session with UAC on, and one click on the UAC prompt.
# Reproduces the launch and wait of RemoveAsync (uninstall-helper.cs:349-356) with a harmless command
# that only waits 6 seconds. Nothing is installed, removed or changed.
# Recorded on 3.6.0: the control returns normally; the elevated case throws Win32Exception 5, which RemoveAsync reports as Failed.
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $Repo 'src/uninstall-helper.cs'))) -ReferencedAssemblies System.dll,System.Core.dll,System.Web.Extensions.dll
[Threading.Thread]::CurrentThread.CurrentUICulture=[Globalization.CultureInfo]::GetCultureInfo('en-US')
function Invoke-Case([string]$label,[bool]$elevated) {
    $start=New-Object Diagnostics.ProcessStartInfo((Join-Path $env:SystemRoot 'System32\cmd.exe'),'/c timeout /t 6 /nobreak')
    $start.UseShellExecute=$true
    if ($elevated) { $start.Verb='runas' }
    $clock=[Diagnostics.Stopwatch]::StartNew()
    try {
        $launchedAt=[DateTime]::UtcNow
        $process=[Diagnostics.Process]::Start($start)
        [OneInstallUninstall]::WaitForUninstaller($process,$launchedAt)
        '{0}: returned normally after {1:n1}s; uninstaller exit code {2}' -f $label,$clock.Elapsed.TotalSeconds,$process.ExitCode
    }
    catch {
        $failure=$_.Exception.GetBaseException()
        $native=''; if ($failure -is [ComponentModel.Win32Exception]) { $native=' native error '+$failure.NativeErrorCode }
        # Same mapping as the catch in RemoveAsync (uninstall-helper.cs:369).
        $outcome='Failed'
        if ($failure -is [ComponentModel.Win32Exception] -and $failure.NativeErrorCode -eq 1223) { $outcome='Cancelled' }
        elseif ($failure -is [TimeoutException]) { $outcome='Unknown' }
        '{0}: threw {1}{2} after {3:n1}s: "{4}" -> 3.6 would report "{5}"' -f $label,$failure.GetType().Name,$native,$clock.Elapsed.TotalSeconds,$failure.Message,$outcome
    }
}
Invoke-Case 'control, not elevated' $false
Invoke-Case 'elevated through UAC' $true
