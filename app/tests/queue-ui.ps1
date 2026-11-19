# Drives the install queue of a built 1nstall.exe from outside, through UI Automation, with a
# stand-in for WinGet that installs nothing. Needs an interactive desktop.
#
# The application runs with --ui-test: nothing in the user's profile is read or written, no
# browser is opened, and the only program run to "install" is the stand-in given here. Build it
# with:  cargo build -p oneinstall-harness --bin oracle-fixture   (in engine\)
param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$StandIn)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$automation=[Windows.Automation.AutomationElement]
$descendants=[Windows.Automation.TreeScope]::Descendants
$failed=0
function Check([string]$name,[bool]$condition) { if ($condition) { "PASS $name" } else { "FAIL $name"; $script:failed++ } }
function Named($root,[string]$name) { $root.FindFirst($descendants,(New-Object Windows.Automation.PropertyCondition ($automation::NameProperty),$name)) }
function ById($root,[string]$id) { $root.FindFirst($descendants,(New-Object Windows.Automation.PropertyCondition ($automation::AutomationIdProperty),$id)) }
function Toggle($element) { $element.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle(); Start-Sleep -Milliseconds 600 }
function Invoke($element) { $element.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 800 }
function Everywhere([string]$name) {
    $condition=New-Object Windows.Automation.AndCondition (New-Object Windows.Automation.PropertyCondition ($automation::ProcessIdProperty),$process.Id),(New-Object Windows.Automation.PropertyCondition ($automation::NameProperty),$name)
    $automation::RootElement.FindFirst($descendants,$condition)
}
function Start-App([string]$standIn,[hashtable]$environment=@{}) {
    $env:ONEINSTALL_TEST_WINGET=$standIn
    foreach ($name in $environment.Keys) { Set-Item -Path "Env:$name" -Value $environment[$name] }
    try { $script:process=Start-Process -FilePath $exe -ArgumentList '--ui-test' -PassThru } finally {
        Remove-Item Env:ONEINSTALL_TEST_WINGET -ErrorAction SilentlyContinue
        foreach ($name in $environment.Keys) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    }
    $deadline=(Get-Date).AddSeconds(20)
    do { Start-Sleep -Milliseconds 100; $process.Refresh() } while ($process.MainWindowHandle -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline -and -not $process.HasExited)
    if ($process.MainWindowHandle -eq [IntPtr]::Zero) { throw 'The application showed no window.' }
    Start-Sleep -Milliseconds 1500
    $automation::FromHandle($process.MainWindowHandle)
}
function Stop-App { if (-not $process.HasExited) { $process.CloseMainWindow() | Out-Null; if (-not $process.WaitForExit(5000)) { $process.Kill() } } }

$exe=(Resolve-Path -LiteralPath $Exe).Path
$standIn=(Resolve-Path -LiteralPath $StandIn).Path
$folder=Split-Path $exe
$history=Join-Path $folder 'test-data\operations.json'
$logs=Join-Path $folder 'test-logs'
foreach ($stale in @((Join-Path $folder 'test-data'),$logs)) { if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Recurse -Force } }
$userHistory=Join-Path $env:LOCALAPPDATA '1nstall\operations.json'
function Fingerprint { if (Test-Path -LiteralPath $userHistory) { (Get-FileHash -LiteralPath $userHistory).Hash } else { 'absent' } }
$before=Fingerprint

# 1. Without a stand-in, the test mode refuses to install anything.
$root=Start-App ''
try {
    Toggle (Named $root '7-Zip')
    Invoke (ById $root 'Install')
    $start=Everywhere 'Start installation'
    Check 'Install opens the review window' ([bool]$start -and [bool](Everywhere 'Ready to install?'))
    Check 'nothing can start before the licences are accepted' (-not $start.Current.IsEnabled)
    Toggle (Everywhere 'I accept the app licenses and WinGet source terms.')
    Check 'accepting the licences enables the start' ($start.Current.IsEnabled)
    Invoke $start
    Check 'with no stand-in, the test mode refuses to install' ([bool](Named $root 'Could not start. See the logs for details.'))
    Check 'and the selection can be changed again' ((Named $root '7-Zip').Current.IsEnabled)
} finally { Stop-App }
Check 'nothing was recorded' (-not (Test-Path -LiteralPath $history))

# 2. With the stand-in: one automatic app, and a guided app that requires another guided app.
$root=Start-App $standIn
try {
    Toggle (Named $root '7-Zip')
    Toggle (Named $root 'Peace GUI')
    Check 'three apps are planned' ([bool](Named $root '3 apps selected'))
    Invoke (ById $root 'Install')
    Check 'the review lists the plan in order' ([bool](Everywhere '7-Zip  ·  Automatic') -and [bool](Everywhere 'Equalizer APO  ·  Guided') -and [bool](Everywhere 'Peace GUI  ·  Guided'))
    # Back leaves everything as it was.
    Invoke (Everywhere 'Back')
    Check 'Back starts nothing' (-not (Test-Path -LiteralPath $history) -and (Named $root '7-Zip').Current.IsEnabled)
    Invoke (ById $root 'Install')
    Toggle (Everywhere 'I accept the app licenses and WinGet source terms.')
    Invoke (Everywhere 'Start installation')
    $deadline=(Get-Date).AddSeconds(60)
    do { Start-Sleep -Milliseconds 300; $finished=Named $root 'Queue finished · 0 failed · 2 manual installs pending.' } while (-not $finished -and (Get-Date) -lt $deadline)
    Check 'the queue runs to its end and reports the totals' ([bool]$finished)
    # The stand-in exits with success but installs nothing, so the app must not be called a success.
    Check 'an installer that proves nothing is not a success' ([bool](Named $root 'Unknown · refresh to verify'))
    Check 'a guided app is left pending' ([bool](Named $root 'Manual install pending · official website'))
    Check 'an app whose requirement is unverified is held back' ([bool](Named $root 'Manual action required · dependency not verified: apo'))
    Check 'the selection can be changed again' ((Named $root '7-Zip').Current.IsEnabled -and [bool](Named $root 'Remove 7-Zip from selection'))
    $progress=ById $root 'Progress'
    Check "the progress bar is full ($($progress.GetCurrentPattern([Windows.Automation.RangeValuePattern]::Pattern).Current.Value))" ($progress.GetCurrentPattern([Windows.Automation.RangeValuePattern]::Pattern).Current.Value -eq 100)
} finally { Stop-App }
$records=if (Test-Path -LiteralPath $history) { @((Get-Content -LiteralPath $history -Raw | ConvertFrom-Json)) } else { @() }
Check "three operations were recorded beside the executable ($($records.Count))" ($records.Count -eq 3)
$session=@(Get-ChildItem -LiteralPath $logs -Filter ('session-*-'+$process.Id+'.log') -ErrorAction SilentlyContinue | Select-Object -Last 1)
$log=if ($session) { Get-Content -LiteralPath $session[0].FullName -Raw } else { '' }
Check 'the session log names the queue and each outcome' ($log -match 'Queue started: 7-Zip, Equalizer APO, Peace GUI' -and $log -match '7-Zip: Unknown' -and $log -match 'Peace GUI: Manual action required')
Check 'no browser was opened: the page was only recorded' ($log -match 'Would open: https?://')

function Wait-Named($root,[string]$name,[int]$seconds=60) {
    $deadline=(Get-Date).AddSeconds($seconds)
    do { $found=Named $root $name; if ($found) { return $found }; Start-Sleep -Milliseconds 200 } while ((Get-Date) -lt $deadline)
    return $null
}
function Start-Queue($root,[string[]]$apps) {
    foreach ($app in $apps) { Toggle (Named $root $app) }
    Invoke (ById $root 'Install')
    Toggle (Everywhere 'I accept the app licenses and WinGet source terms.')
    Invoke (Everywhere 'Start installation')
}
function Records { if (Test-Path -LiteralPath $history) { @((Get-Content -LiteralPath $history -Raw | ConvertFrom-Json)) } else { @() } }

# 3. Stop midway. The stand-in now takes three seconds each time it runs, so the first app is
#    still installing when Stop is pressed: it is left to finish, and the second never starts.
Remove-Item -LiteralPath $history -ErrorAction SilentlyContinue
$root=Start-App $standIn @{ORACLE_FIXTURE_DELAY_MS='3000'}
try {
    Start-Queue $root @('7-Zip','Notepad++')
    Check 'the first app is installing' ([bool](Wait-Named $root 'Installing 7zip.7zip…' 15))
    $cancel=ById $root 'Cancel'
    Check 'a running queue offers Stop, and locks the selection' ([bool]$cancel -and $cancel.Current.IsEnabled -and -not (Named $root '7-Zip').Current.IsEnabled)
    $pressed=Get-Date
    Invoke $cancel
    Check 'Stop is acknowledged, and cannot be pressed twice' ([bool](Named $root 'Stopping after the current app.') -and -not (ById $root 'Cancel').Current.IsEnabled)
    $stopped=Wait-Named $root 'Queue stopped after the current app. Review the results.' 60
    $waited=[int]((Get-Date)-$pressed).TotalMilliseconds
    Check "the running installer is left to finish before the queue stops ($waited ms after Stop)" ([bool]$stopped -and $waited -gt 1500)
    Check 'the app that was running has its own result' ([bool](Named $root 'Unknown · refresh to verify'))
    Check 'the app that had not started is marked as such' ([bool](Named $root 'Cancelled · not started'))
    Check 'the selection can be changed again, and Stop is gone' ((Named $root '7-Zip').Current.IsEnabled -and -not (ById $root 'Cancel'))
} finally { Stop-App }
$records=Records
Check "both apps are on record: one outcome, one cancelled ($(@($records | ForEach-Object { $_.Name+' '+$_.Outcome }) -join '; '))" ($records.Count -eq 2 -and $records[0].Name -eq '7-Zip' -and $records[0].Outcome -eq 'Unknown' -and $records[1].Name -eq 'Notepad++' -and $records[1].Outcome -eq 'Cancelled')

# 4. Closing the window while a queue runs: the window stays until the installer has finished.
Remove-Item -LiteralPath $history -ErrorAction SilentlyContinue
$root=Start-App $standIn @{ORACLE_FIXTURE_DELAY_MS='3000'}
try {
    Start-Queue $root @('7-Zip','Notepad++')
    Check 'the first app is installing again' ([bool](Wait-Named $root 'Installing 7zip.7zip…' 15))
    $process.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 700
    Check 'closing does not abandon a running installer: the window stays' (-not $process.HasExited -and [bool](Named $root 'Wait for the current installer to finish, then close this window.'))
    $stopped=Wait-Named $root 'Queue stopped after the current app. Review the results.' 60
    Check 'the queue stops after the current app' ([bool]$stopped -and [bool](Named $root 'Cancelled · not started'))
    $process.CloseMainWindow() | Out-Null
    Check 'once the queue has ended, the window closes' ($process.WaitForExit(8000))
} finally { Stop-App }
$records=Records
Check "the interrupted run is on record ($(@($records | ForEach-Object { $_.Name+' '+$_.Outcome }) -join '; '))" ($records.Count -eq 2 -and $records[1].Outcome -eq 'Cancelled')

# 5. The engine fails inside the queue, on purpose. The queue ends, the window says so and goes on.
Remove-Item -LiteralPath $history -ErrorAction SilentlyContinue
$root=Start-App $standIn @{ONEINSTALL_TEST_QUEUE_FAILURE='1'}
try {
    Start-Queue $root @('7-Zip')
    $ended=Wait-Named $root 'The queue ended early because of an internal error. See the logs for details.' 30
    Check 'an internal failure of the queue is shown in the status line' ([bool]$ended)
    Check 'the application is still running, and the selection can be changed again' (-not $process.HasExited -and (Named $root '7-Zip').Current.IsEnabled -and -not (ById $root 'Cancel'))
    Toggle (Named $root '7-Zip')
    Check 'the selection still works' ([bool](Named $root '0 apps selected'))
    $failedSession=@(Get-ChildItem -LiteralPath $logs -Filter ('session-*-'+$process.Id+'.log'))
    $text=if ($failedSession) { Get-Content -LiteralPath $failedSession[0].FullName -Raw } else { '' }
    Check 'the reason is in the session log' ($text -match '1nstall could not finish the queue: Deliberate failure for the tests \(')
} finally { Stop-App }
Check 'the operation history of this Windows user was not touched' ((Fingerprint) -eq $before)
"queue ui: $failed failed"
if ($failed) { exit 1 }
