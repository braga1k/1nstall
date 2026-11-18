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
function Start-App([string]$standIn) {
    $env:ONEINSTALL_TEST_WINGET=$standIn
    try { $script:process=Start-Process -FilePath $exe -ArgumentList '--ui-test' -PassThru } finally { Remove-Item Env:ONEINSTALL_TEST_WINGET -ErrorAction SilentlyContinue }
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
$session=@(Get-ChildItem -LiteralPath $logs -Filter 'session-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1)
$log=if ($session) { Get-Content -LiteralPath $session[0].FullName -Raw } else { '' }
Check 'the session log names the queue and each outcome' ($log -match 'Queue started: 7-Zip, Equalizer APO, Peace GUI' -and $log -match '7-Zip: Unknown' -and $log -match 'Peace GUI: Manual action required')
Check 'no browser was opened: the page was only recorded' ($log -match 'Would open: https?://')
Check 'the operation history of this Windows user was not touched' ((Fingerprint) -eq $before)
"queue ui: $failed failed"
if ($failed) { exit 1 }
