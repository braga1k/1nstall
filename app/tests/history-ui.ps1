# Drives the History & diagnostics page of a built 1nstall.exe from outside, through UI Automation.
# Needs an interactive desktop.
#
# The application runs with --ui-test, so its history is the test-data folder beside the
# executable and nothing in the user's profile is read or written. The test writes a made-up
# history there. Nothing is installed or removed. Unless -SkipInventory is given, it asks WinGet
# what is installed, which only reads, to check that a retry is withheld while WinGet cannot
# prove that the app is missing.
# It also makes the engine fail on purpose, to check that the application reports it and goes on.
# With -StandIn (engine\target\debug\oracle-fixture.exe) it also gives the engine a complete
# inventory of the test's making, in place of PowerShell 7 and the WinGet module, and follows the
# retry of a failed install from its button to the selection.
param([Parameter(Mandatory)][string]$Exe, [switch]$SkipInventory, [string]$StandIn='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$automation=[Windows.Automation.AutomationElement]
$descendants=[Windows.Automation.TreeScope]::Descendants
$failed=0
function Check([string]$name,[bool]$condition) { if ($condition) { "PASS $name" } else { "FAIL $name"; $script:failed++ } }
function Property($field,$value) { New-Object Windows.Automation.PropertyCondition $field,$value }
function All($root,$type) { $root.FindAll($descendants,(Property ($automation::ControlTypeProperty) $type)) }
function Named($root,[string]$name) { $root.FindFirst($descendants,(Property ($automation::NameProperty) $name)) }
function ById($root,[string]$id) { $root.FindFirst($descendants,(Property ($automation::AutomationIdProperty) $id)) }
function Invoke($element) { $element.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 800 }
function Value($element) { $element.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value }
# Dialogs are windows of their own: look in the whole process.
function Everywhere($field,$value) {
    $automation::RootElement.FindFirst($descendants,(New-Object Windows.Automation.AndCondition (Property ($automation::ProcessIdProperty) $process.Id),(Property $field $value)))
}
function Texts($root) { @(All $root ([Windows.Automation.ControlType]::Text) | ForEach-Object { $_.Current.Name }) }
# The operations shown: each starts with its timestamp.
function Operations($root) { @(Texts $root | Where-Object { $_ -match '^\d{4}-\d\d-\d\d ' }) }
function Buttons($root,[string]$name) { @(All $root ([Windows.Automation.ControlType]::Button) | Where-Object { $_.Current.Name -eq $name }) }
function Save-History($records) {
    New-Item -ItemType Directory -Path (Split-Path $history) -Force | Out-Null
    [IO.File]::WriteAllText($history,(ConvertTo-Json -InputObject @($records) -Depth 3),(New-Object Text.UTF8Encoding $false))
}
function Operation([string]$time,[string]$action,[string]$id,[string]$name,[string]$outcome,[string]$message,[string]$log) {
    [ordered]@{Timestamp=$time;Action=$action;Id=$id;Source='winget';Name=$name;Outcome=$outcome;Message=$message;LogPath=$log;ExitCode=1}
}

$exe=(Resolve-Path -LiteralPath $Exe).Path
$folder=Split-Path $exe
$history=Join-Path $folder 'test-data\operations.json'
$logs=Join-Path $folder 'test-logs'
# The made-up history belongs to this test alone.
if (Test-Path -LiteralPath $history) { Remove-Item -LiteralPath $history }
$process=Start-Process -FilePath $exe -ArgumentList '--ui-test' -PassThru
try {
    $deadline=(Get-Date).AddSeconds(20)
    do { Start-Sleep -Milliseconds 100; $process.Refresh() } while ($process.MainWindowHandle -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline -and -not $process.HasExited)
    if ($process.MainWindowHandle -eq [IntPtr]::Zero) { throw 'The application showed no window.' }
    Start-Sleep -Milliseconds 1500
    $root=$automation::FromHandle($process.MainWindowHandle)

    Invoke (ById $root 'HistoryMode')
    $list=ById $root 'HistoryList'
    Check 'History shows its page and hides the library' ([bool]$list -and [bool](Named $root 'Operation history') -and -not (Named $root 'Details for 1Password'))
    Check 'an empty history says so' ((Texts $list) -contains 'Your operation history will appear here after installation or removal.' -and (Buttons $list 'Open detailed log').Count -eq 0)

    # A made-up history: a log inside the log folder, a log outside it, and a failed install of
    # a package the catalog does not have. Paths and addresses are for the diagnostics to redact.
    $inside=Join-Path $logs 'history-ui-fixture.log'; [IO.File]::WriteAllText($inside,'fixture')
    $outside=Join-Path $folder 'history-ui-outside.log'; [IO.File]::WriteAllText($outside,'fixture')
    $records=@(
        (Operation '2026-11-18 09:00:00' 'Remove' 'OracleFixture' 'Oldest fixture' 'Success' 'Removed. Log kept.' $inside),
        (Operation '2026-11-18 09:05:00' 'Install' 'No.Such.Package' 'Unknown fixture' 'Failed' 'Installer failed in C:\Users\someone\AppData\secret.txt for someone@example.com' $outside)
    )
    Save-History $records
    Invoke (Named $root 'Refresh history')
    $shown=Operations $list
    Check 'Refresh history shows the operations on record, newest first' ($shown.Count -eq 2 -and $shown[0] -like '2026-11-18 09:05:00 · Install · Unknown fixture · Failed*' -and $shown[1] -like '2026-11-18 09:00:00 · Remove · Oldest fixture · Success*')
    Check 'only the log inside the log folder can be opened' ((Buttons $list 'Open detailed log').Count -eq 1)
    Check 'a failed install outside the catalog offers no retry' ((Buttons $list 'Refresh & review installation again').Count -eq 0)

    # The diagnostics are shown for review, with paths and addresses removed.
    Invoke (Named $root 'Review diagnostic export…')
    $text=Everywhere ($automation::AutomationIdProperty) 'DiagnosticsText'
    $diagnostics=if ($text) { Value $text } else { '' }
    Check 'the diagnostics open for review' ($diagnostics.StartsWith('1nstall diagnostics (review before sharing)') -and $diagnostics -match 'Windows \d+\.\d+\.\d+\.\d+ · x64 True')
    Check 'they list the operations' ($diagnostics.Contains('2026-11-18 09:05:00 · Install · No.Such.Package · winget · Failed · 1'))
    Check 'paths and addresses are removed' ($diagnostics.Contains('Installer failed in <path>') -and -not $diagnostics.Contains('someone') -and -not $diagnostics.Contains('secret.txt'))
    Check 'they say nothing is sent' ($diagnostics.Contains('Nothing is sent automatically.') -and [bool](Everywhere ($automation::NameProperty) 'Save reviewed diagnostics…'))
    Invoke (Everywhere ($automation::NameProperty) 'Close')
    Check 'closing the diagnostics returns to the page' (-not (Everywhere ($automation::AutomationIdProperty) 'DiagnosticsText') -and [bool](ById $root 'HistoryList'))

    Invoke (Named $root 'Licenses & credits')
    $text=Everywhere ($automation::AutomationIdProperty) 'NoticesText'
    $notices=if ($text) { Value $text } else { '' }
    Check 'licences and credits name the adapted code and the Rust components' ($notices.Contains('Bulk Crap Uninstaller') -and $notices.Contains('Rust components of the 1nstall 4 engine') -and $notices.Contains('regex '))
    Invoke (Everywhere ($automation::NameProperty) 'Close')

    # Leaving the page hides it, from each of the other pages.
    Invoke (ById $root 'UninstallMode')
    Check 'Uninstall replaces the history page' ([bool](ById $root 'InstalledSearch') -and -not (ById $root 'HistoryList'))
    Invoke (ById $root 'HistoryMode')
    Invoke (Named $root 'Settings')
    Check 'Settings replaces the history page' ([bool](ById $root 'ThemeChoice') -and -not (ById $root 'HistoryList'))
    Invoke (ById $root 'HistoryMode')
    Check 'History replaces the Settings page' ([bool](ById $root 'HistoryList') -and -not (ById $root 'ThemeChoice'))
    Invoke (ById $root 'InstallMode')
    Check 'Install brings the library back' ([bool](Named $root 'Details for 1Password') -and -not (ById $root 'HistoryList'))

    if (-not $SkipInventory) {
        # A failed install may be reviewed again only for an app known to be missing. The WinGet
        # export this build reads lists what is installed and cannot prove absence, so the retry
        # must be withheld. (Offering it needs the complete inventory, which is not built in yet.)
        $refresh=Named $root 'Refresh'
        Invoke $refresh
        $deadline=(Get-Date).AddSeconds(90)
        do { Start-Sleep -Milliseconds 500 } while (-not $refresh.Current.IsEnabled -and (Get-Date) -lt $deadline)
        Check 'the inventory finishes' ($refresh.Current.IsEnabled)
        Start-Sleep -Milliseconds 500
        $catalog=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $cards=@(All $root ([Windows.Automation.ControlType]::CheckBox))
        $absent=$null
        foreach ($app in $catalog) {
            if (@($app.Ids).Count -ne 1 -or @($catalog | Where-Object { $_.Ids -contains $app.Ids[0] }).Count -ne 1) { continue }
            $card=$cards | Where-Object { $_.Current.Name -eq $app.Name } | Select-Object -First 1
            if ($card -and $card.Current.ItemStatus -notlike 'Installed*') { $absent=$app; $state=$card.Current.ItemStatus; break }
        }
        # With PowerShell 7 and the WinGet module on this machine the inventory is complete, and
        # the app is known to be missing; the last part of this test covers that case.
        $partial=$state -like 'Unknown*'
        Check "an app WinGet does not list ($($absent.Name)) is unknown with the partial inventory, missing with the complete one ($state)" ([bool]$absent -and ($partial -or $state -eq 'Not installed'))
        if ($absent -and $partial) {
            Save-History @((Operation '2026-11-18 09:10:00' 'Install' $absent.Ids[0] $absent.Name 'Failed' 'The installer failed.' ''))
            Invoke (ById $root 'HistoryMode')
            $list=ById $root 'HistoryList'
            Check 'its failed install is on record' (@(Operations $list).Count -eq 1 -and @(Operations $list)[0] -like "2026-11-18 09:10:00 · Install · $($absent.Name) · Failed*")
            Check 'the retry is withheld while the state is unknown' ((Buttons $list 'Refresh & review installation again').Count -eq 0)
            Invoke (ById $root 'InstallMode')
        }
    }

    # The engine fails on purpose. The application says so and goes on.
    Invoke (ById $root 'TestFailure')
    $box=Everywhere ($automation::ClassNameProperty) '#32770'
    # A message box is a system dialog: its text is a Static control.
    $said=if ($box) { (@($box.FindAll($descendants,(Property ($automation::ClassNameProperty) 'Static'))) | ForEach-Object { $_.Current.Name }) -join ' ' } else { '' }
    Check 'an internal engine failure is shown, with its reason' ($said.Contains('1nstall could not finish that action because of an internal error.') -and $said.Contains('Deliberate failure for the tests'))
    if ($box) { $box.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close(); Start-Sleep -Milliseconds 800 }
    Check 'the application is still running after it' (-not $process.HasExited -and -not (Everywhere ($automation::ClassNameProperty) '#32770'))
    Invoke (ById $root 'UninstallMode'); Invoke (ById $root 'InstallMode')
    Check 'and still works' ([bool](Named $root 'Details for 1Password'))
    $session=Get-ChildItem -LiteralPath $logs -Filter ('session-*-'+$process.Id+'.log') | Select-Object -First 1
    Check 'the failure is in the session log' ([bool]$session -and (Get-Content -LiteralPath $session.FullName -Raw) -match 'Internal error: Deliberate failure for the tests')
} finally {
    if (-not $process.HasExited) { $process.CloseMainWindow() | Out-Null; if (-not $process.WaitForExit(5000)) { $process.Kill() } }
    foreach ($fixture in @($history,(Join-Path $logs 'history-ui-fixture.log'),(Join-Path $folder 'history-ui-outside.log'))) { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture } }
}
if ($StandIn) {
    # The complete inventory says what is NOT installed. Here it lists 7-Zip only.
    $shell7=Join-Path $folder 'test-data\pwsh.exe'
    New-Item -ItemType Directory -Path (Split-Path $shell7) -Force | Out-Null
    Copy-Item -LiteralPath (Resolve-Path -LiteralPath $StandIn).Path -Destination $shell7 -Force
    [IO.File]::WriteAllText($shell7+'.out','[{"Id":"7zip.7zip","Name":"7-Zip","Source":"winget","InstalledVersion":"24.09"}]')
    Save-History @(
        (Operation '2026-11-18 10:00:00' 'Install' '7zip.7zip' '7-Zip' 'Failed' 'The installer failed.' ''),
        (Operation '2026-11-18 10:05:00' 'Install' 'Notepad++.Notepad++' 'Notepad++' 'Failed' 'The installer failed.' '')
    )
    $env:ONEINSTALL_TEST_SHELL7=$shell7
    try { $process=Start-Process -FilePath $exe -ArgumentList '--ui-test' -PassThru } finally { Remove-Item Env:ONEINSTALL_TEST_SHELL7 -ErrorAction SilentlyContinue }
    try {
        $deadline=(Get-Date).AddSeconds(20)
        do { Start-Sleep -Milliseconds 100; $process.Refresh() } while ($process.MainWindowHandle -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline -and -not $process.HasExited)
        Start-Sleep -Milliseconds 1500
        $root=$automation::FromHandle($process.MainWindowHandle)
        $refresh=Named $root 'Refresh'
        Invoke $refresh
        $deadline=(Get-Date).AddSeconds(60)
        do { Start-Sleep -Milliseconds 400 } while (-not $refresh.Current.IsEnabled -and (Get-Date) -lt $deadline)
        Start-Sleep -Milliseconds 500
        $cards=@(All $root ([Windows.Automation.ControlType]::CheckBox))
        $present=($cards | Where-Object { $_.Current.Name -eq '7-Zip' } | Select-Object -First 1).Current.ItemStatus
        $missing=($cards | Where-Object { $_.Current.Name -eq 'Notepad++' } | Select-Object -First 1).Current.ItemStatus
        Check "with a complete inventory a listed app is installed and an unlisted one is not ($present; $missing)" ($present -eq 'Installed · 24.09' -and $missing -eq 'Not installed')
        Invoke (ById $root 'HistoryMode')
        $list=ById $root 'HistoryList'
        $retry=@(Buttons $list 'Refresh & review installation again')
        Check "only the failed install of the app that is missing offers a retry ($($retry.Count))" ($retry.Count -eq 1)
        if ($retry.Count -eq 1) {
            Invoke $retry[0] 1500
            $deadline=(Get-Date).AddSeconds(60)
            do { Start-Sleep -Milliseconds 400; $rechecked=Named $root 'State rechecked. Review the installation again.' } while (-not $rechecked -and (Get-Date) -lt $deadline)
            Check 'the retry reads the state again and returns to the library' ([bool]$rechecked -and [bool](Named $root 'Details for 1Password') -and -not (ById $root 'HistoryList'))
            Check 'and selects that app for a new review, without installing anything' ([bool](Named $root '1 app selected') -and [bool](Named $root 'Remove Notepad++ from selection') -and @(Get-Content -LiteralPath $history -Raw | ConvertFrom-Json).Count -le 2)
        }
    } finally {
        if (-not $process.HasExited) { $process.CloseMainWindow() | Out-Null; if (-not $process.WaitForExit(5000)) { $process.Kill() } }
        foreach ($fixture in @($history,$shell7,($shell7+'.out'))) { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture } }
    }
}
"history ui: $failed failed"
if ($failed) { exit 1 }
