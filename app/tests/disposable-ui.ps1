# Drives a built 1nstall.exe in its NORMAL mode, through UI Automation, and really changes the
# machine: it saves settings to the profile of the current user, removes fixture apps, cleans
# their leftovers and, with -Real, installs real apps with WinGet and removes them again with
# their own uninstallers. Run it only where the machine is thrown away afterwards: a CI runner.
# Needs an interactive desktop.
#
# -Publisher is the stand-in uninstaller of the fixture apps:
#   cargo build -p oneinstall-harness --bin oracle-publisher   (in engine\)
# Lines that start with NOTE report what was observed without judging it.
param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string]$Publisher,
    [switch]$DisposableEnvironment,
    [switch]$Real,
    # Only the part with real apps, for a run of its own.
    [switch]$RealOnly,
    [string]$Pictures=''
)
if (-not $DisposableEnvironment) { throw 'This test changes the machine. Run it only on a disposable machine, with -DisposableEnvironment.' }
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$ellipsis=[string][char]0x2026
$dot=[string][char]0xB7
$exe=(Resolve-Path -LiteralPath $Exe).Path
$publisher=(Resolve-Path -LiteralPath $Publisher).Path
$data=Join-Path $env:LOCALAPPDATA '1nstall'
$arp='Software\Microsoft\Windows\CurrentVersion\Uninstall'
function Registered([string]$key,[string]$hive='HKCU:') { Test-Path -LiteralPath (Join-Path $hive (Join-Path $arp $key)) }
# (The parentheses matter: Windows PowerShell hands the whole list over as one object otherwise.)
function Operations { $path=Join-Path $data 'operations.json'; if (Test-Path -LiteralPath $path) { @((Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)) } else { @() } }
function Choose($root,[string]$id,[string]$item) {
    $combo=ById $root $id
    $combo.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Expand(); Start-Sleep -Milliseconds 400
    (Named $combo $item).GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 300
    $combo.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse(); Start-Sleep -Milliseconds 800
}
function Status($root) { (ById $root 'UninstallStatus').Current.Name }
# Registers a fixture app for the current user. Its uninstaller is the stand-in publisher.
function New-Fixture([string]$key,[string]$product,[string]$mode,[switch]$WithFiles) {
    $install=Join-Path $env:LOCALAPPDATA ('Programs\'+$product)
    $vendor=Join-Path $env:APPDATA 'OracleWindowVendor'
    if ($WithFiles) {
        New-Item -ItemType Directory -Path $install,(Join-Path $vendor $product) -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $install 'editor.exe'),'fixture executable placeholder')
        [IO.File]::WriteAllText((Join-Path $install 'readme.txt'),'fixture program file')
        [IO.File]::WriteAllText((Join-Path (Join-Path $vendor $product) 'settings.ini'),'fixture user settings')
    }
    $registration=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($arp+'\'+$key)
    try {
        $registration.SetValue('DisplayName',$product+' 2.0'); $registration.SetValue('Publisher','OracleWindowVendor'); $registration.SetValue('DisplayVersion','2.0')
        if ($WithFiles) { $registration.SetValue('InstallLocation',$install) }
        $registration.SetValue('UninstallString','"'+$publisher+'" '+$mode+' '+$key)
    } finally { $registration.Dispose() }
    [pscustomobject]@{ Key=$key; Product=$product; Name=$product+' 2.0'; Install=$install; Data=(Join-Path $vendor $product) }
}
# Opens the Uninstall page and waits for the list of installed apps.
function Open-Uninstall($root) {
    Invoke (ById $root 'UninstallMode')
    Wait-Until { (Status $root) -match '^\d+ installed apps' } 180 400 | Out-Null
}
function Refresh-Installed($root) {
    Invoke (ById $root 'RefreshInstalled') 1200
    Wait-Until { (Status $root) -match '^\d+ installed apps' -and (ById $root 'RefreshInstalled').Current.IsEnabled } 180 400 | Out-Null
}
# Switches on the apps whose names start with the given texts. Returns how many were found.
function Select-Installed($root,[string[]]$names) {
    $found=0
    foreach ($name in $names) {
        Set-Value (ById $root 'InstalledSearch') $name 900
        $switch=@(Cards (ById $root 'InstalledList') | Where-Object { $_.Current.Name -like ($name+'*') -and $_.Current.IsEnabled })
        if ($switch.Count) { Toggle $switch[0]; $found++ }
    }
    Set-Value (ById $root 'InstalledSearch') '' 900
    $found
}
function Start-Removal($root) {
    Invoke (ById $root 'ReviewUninstall')
    Toggle (Everywhere-Id 'RemovalConsent')
    # The button opens the queue; its action is started without waiting for it to return.
    (Everywhere-Id 'RemovalProceed').GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Milliseconds 600
}
# Waits until the removal and the check that follows it are over: either the leftover review
# is open ('review'), or the page is idle again ('idle').
function Wait-Removal($root,[int]$seconds=300) {
    $working='Queued',('Preparing'+$ellipsis),('Removing'+$ellipsis),('Verifying'+$ellipsis)
    Wait-Until {
        if (Everywhere-Named 'Keep what matters') { return 'review' }
        $refresh=ById $root 'RefreshInstalled'
        # Idle only once the queue shows an outcome for every app: before the removal has
        # begun the page looks idle too.
        $stages=@(Stage-Texts $root)
        if ($refresh -and $refresh.Current.IsEnabled -and -not (ById $root 'StopUninstall') -and (Status $root) -notmatch 'Reading|Checking|Removing|Waiting|Wait for' -and $stages.Count -and -not ($stages | Where-Object { $working -contains $_ })) {
            # The review window may be about to appear: look again once it has had time to.
            Start-Sleep -Milliseconds 2000
            if (Everywhere-Named 'Keep what matters') { return 'review' }
            $refresh=ById $root 'RefreshInstalled'
            if ($refresh -and $refresh.Current.IsEnabled -and (Status $root) -notmatch 'Reading|Checking|Removing|Waiting|Wait for') { return 'idle' }
        }
        return $null
    } $seconds 400
}
function Stage-Texts($root) { @(Texts $root | Where-Object { $_ -in 'Success','Cancelled','Failed','Unknown','Manual action required','Restart required','Queued',('Preparing'+$ellipsis),('Removing'+$ellipsis),('Verifying'+$ellipsis) }) }

if (-not $RealOnly) {
# ---------------------------------------------------------------------------------------------
# 0. With the theme left to Windows, the window follows Windows while it is open: the app
#    theme, then high contrast. Both are settings of this user, changed here and put back.
$personalize='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
function Set-AppTheme([int]$light) { if (-not (Test-Path -LiteralPath $personalize)) { New-Item -Path $personalize -Force | Out-Null }; Set-ItemProperty -Path $personalize -Name AppsUseLightTheme -Value $light -Type DWord }
function Level([string]$name) { [int][UiNative]::Brightness((Picture $shots $name)) }
$shots=if ($Pictures) { $Pictures } else { Join-Path (Split-Path $exe) 'test-pictures' }
$original=(Get-ItemProperty -Path $personalize -Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme
Set-AppTheme 0
$root=Start-App ''
try {
    $dark=Level 'windows-dark'
    Set-AppTheme 1; Start-Sleep -Milliseconds 3500
    $light=Level 'windows-light'
    Set-AppTheme 0; Start-Sleep -Milliseconds 3500
    $again=Level 'windows-dark-again'
    Check "the window follows the Windows app theme while open (brightness $dark, then $light, then $again of 255)" ($light -gt $dark+60 -and [Math]::Abs($again-$dark) -lt 25)
    $contrast=[UiNative]::SetHighContrast($true); Start-Sleep -Seconds 6
    $shown=Picture $shots 'windows-high-contrast'
    Check "high contrast switched on while open: the window is still there and drawn (switched: $contrast; detail $([Math]::Round([UiNative]::Detail($shown),2)))" ($contrast -and -not $process.HasExited -and [UiNative]::Detail($shown) -gt 0.05 -and [bool](Named $root 'Details for 1Password'))
    Invoke (ById $root 'UninstallMode'); Invoke (ById $root 'HistoryMode'); Invoke (Named $root 'Settings'); Invoke (ById $root 'InstallMode')
    Check 'every page opens in high contrast' (-not $process.HasExited -and [bool](Named $root 'Details for 1Password'))
    [UiNative]::SetHighContrast($false) | Out-Null; Start-Sleep -Seconds 6
    $back=Level 'windows-after-contrast'
    # Leaving high contrast, Windows puts back the theme it had before, with its own app theme.
    $now=(Get-ItemProperty -Path $personalize -Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme
    $expected=if ($now -eq 1) { $light } else { $dark }
    Check "switching high contrast off brings back the appearance of the theme Windows now has (app theme light: $now; brightness $back, expected about $expected)" (-not $process.HasExited -and [Math]::Abs($back-$expected) -lt 25)
} finally {
    [UiNative]::SetHighContrast($false) | Out-Null
    if ($null -eq $original) { Remove-ItemProperty -Path $personalize -Name AppsUseLightTheme -ErrorAction SilentlyContinue } else { Set-AppTheme $original }
    Stop-App
}

# ---------------------------------------------------------------------------------------------
# A. Settings are saved in the normal mode, and read again at the next start.
$settings=Join-Path $data 'settings.json'
$root=Start-App ''
try {
    Invoke (Named $root 'Settings')
    Choose $root 'ThemeChoice' 'Light'
    Choose $root 'LanguageChoice' 'Português (Portugal)'
    $saved=Wait-Until { if (Test-Path -LiteralPath $settings) { $read=Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json; if ($read.Language -eq 'pt-PT') { $read } } } 10
    Check "the normal mode saves the theme and the language ($(if ($saved) { $saved.Theme+', '+$saved.Language }))" ($saved -and $saved.Theme -eq 'Light' -and $saved.Language -eq 'pt-PT')
    # The two switches of this page listen for a click, as in 3.6. A person's click or Space key
    # is one; the toggle action of UI Automation, which some assistive tools use, is not.
    function Saved-Updates { [bool](Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json).AutoUpdate }
    $switch=ById $root 'AutoUpdateChoice'
    $start=Saved-Updates
    Add-Type -AssemblyName System.Windows.Forms
    [UiNative]::SetForegroundWindow($process.MainWindowHandle) | Out-Null; Start-Sleep -Milliseconds 300
    $switch.SetFocus(); Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait(' '); Start-Sleep -Milliseconds 700
    $first=Saved-Updates
    $switch.SetFocus(); Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait(' '); Start-Sleep -Milliseconds 700
    $second=Saved-Updates
    Check "the automatic updates switch is saved each time the Space key changes it ($start, $first, $second)" ($first -ne $start -and $second -eq $start)
    Toggle $switch
    $byAutomation=Saved-Updates
    "NOTE the same switch changed through the toggle action of UI Automation: shown $($switch.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState), saved $byAutomation (was $second)"
    if ($byAutomation -eq $second) { Toggle $switch }
    $leftover=@(Get-ChildItem -LiteralPath $data -Filter 'settings.json.*.tmp' -ErrorAction SilentlyContinue).Count
    Check 'saving leaves no temporary file behind' ($leftover -eq 0)
} finally { Stop-App }
$root=Start-App ''
try {
    Check 'the next start opens in the saved language' ([bool](Named $root 'Instalar') -and [bool](Named $root 'Desinstalar'))
    Invoke (Named $root 'Settings')
    $theme=(ById $root 'ThemeChoice').GetCurrentPattern([Windows.Automation.SelectionPattern]::Pattern).Current.GetSelection()
    Check "and with the saved theme chosen ($(@($theme | ForEach-Object { $_.Current.Name }) -join ', '))" (@($theme | Where-Object { $_.Current.Name -eq 'Claro' -or $_.Current.Name -eq 'Light' }).Count -eq 1)
    Choose $root 'LanguageChoice' 'English'
    Choose $root 'ThemeChoice' 'Dark'
    # The update check asks GitHub which release is the latest. Nothing newer than this build exists.
    Invoke (Named $root 'Check now') 1500
    $checked=Wait-Until { $shown=Texts $root | Where-Object { $_ -eq '1nstall is up to date.' -or $_ -eq 'Could not check or download the update. Try again later.' } | Select-Object -First 1; $shown } 60 500
    "NOTE Check now answered: $checked"
    Check 'Check now ends with an answer, and the application goes on' ([bool]$checked -and -not $process.HasExited)
    # The remembered library view.
    Invoke (ById $root 'InstallMode')
    Invoke (@(Buttons $root 'Installed')[0])
    $view=Wait-Until { $path=Join-Path $data 'preferences.json'; if (Test-Path -LiteralPath $path) { (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).View } } 10
    Check "the chosen library view is remembered ($view)" ($view -eq 'Installed')
    Invoke (@(Buttons $root 'All apps')[0])
} finally { Stop-App }

# ---------------------------------------------------------------------------------------------
# B. A fixture app is removed, its leftovers are reviewed and cleaned, all through the window.
$fixture=New-Fixture 'OracleFixtureWindow' 'OracleWindow Editor' 'clean' -WithFiles
$before=@(Operations).Count
$root=Start-App ''
try {
    Open-Uninstall $root
    Check 'the fixture app is listed among the installed apps' ((Select-Installed $root @($fixture.Name)) -eq 1 -and [bool](Named $root '1 app selected'))
    Start-Removal $root
    $state=Wait-Removal $root 300
    Check "the removal ends in the leftover review ($state)" ($state -eq 'review')
    Check 'the app is gone from Windows, and marked as removed' (-not (Registered $fixture.Key) -and (Stage-Texts $root) -contains 'Success')
    Check 'the uninstaller left the folders behind, as real ones do' ((Test-Path -LiteralPath $fixture.Install) -and (Test-Path -LiteralPath $fixture.Data))
    Picture $Pictures 'leftover-review' | Out-Null
    $review=Window-With 'Keep what matters'
    $offered=@(Cards $review | Where-Object { $_.Current.AutomationId -ne 'RemovalConsent' })
    $ours=@($offered | Where-Object { $_.Current.Name -like ($fixture.Name+'*') -or $_.Current.Name -like ($fixture.Product+'*') })
    "NOTE leftover review offered: $(@($offered | ForEach-Object { $_.Current.Name }) -join ' | ')"
    Check "the review offers the fixture's folders, and only things of the fixture ($($ours.Count) of $($offered.Count))" ($ours.Count -ge 2 -and $ours.Count -eq $offered.Count)
    $chosen=@($offered | Where-Object { $_.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -eq 'On' }).Count
    $proceed=Everywhere-Id 'RemovalProceed'
    Check 'nothing is chosen at first, and nothing can be removed' ($chosen -eq 0 -and -not $proceed.Current.IsEnabled)
    Toggle (Everywhere-Id 'RemovalConsent')
    Check 'consent alone, with nothing chosen, removes nothing' (-not $proceed.Current.IsEnabled)
    Invoke (Everywhere-Named 'Select linked paths')
    $linked=@($offered | Where-Object { $_.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -eq 'On' } | ForEach-Object { $_.Current.Name })
    Check "Select linked paths chooses the recorded installation folder only ($($linked -join ' | '))" ($linked.Count -eq 1 -and $linked[0] -like ('*'+$fixture.Install))
    Invoke (Everywhere-Named 'Select all')
    Check 'Select all chooses everything, and the removal can go on' (@($offered | Where-Object { $_.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -eq 'On' }).Count -eq $offered.Count -and $proceed.Current.IsEnabled)
    $proceed.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
    $done=Wait-Until { Named $root 'Cleanup complete' } 180 400
    Check 'the cleanup ends with its summary' ([bool]$done)
    Picture $Pictures 'cleanup-summary' | Out-Null
    $state=Wait-Removal $root 120
    $status=Status $root
    Check "the status counts what was done ($status)" ($status -match ('^\d+ recycled '+$dot+' \d+ registry removed '+$dot+' 0 not completed'))
    Check 'the folders are gone from their places' (-not (Test-Path -LiteralPath $fixture.Install) -and -not (Test-Path -LiteralPath $fixture.Data))
    $backup=@(Get-ChildItem -LiteralPath (Join-Path $data 'Backups') -Directory -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1)
    Check 'the backup folder records what was cleaned' ($backup.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $backup[0].FullName 'items.json')))
    $records=@(Operations | Select-Object -Skip $before)
    Check "the history has the removal and each cleaned item ($(@($records | ForEach-Object { $_.Action+' '+$_.Outcome }) -join '; '))" (@($records | Where-Object { $_.Action -eq 'Remove' -and $_.Outcome -eq 'Success' }).Count -ge 1 -and @($records | Where-Object { $_.Action -eq 'Cleanup' -and $_.Outcome -eq 'Success' }).Count -eq $offered.Count -and @($records | Where-Object { $_.Outcome -ne 'Success' }).Count -eq 0)
    Invoke (ById $root 'InstallMode'); Invoke (ById $root 'HistoryMode')
    $shown=@(Texts (ById $root 'HistoryList') | Where-Object { $_ -like ('* '+$dot+' Cleanup '+$dot+' '+$fixture.Name+' '+$dot+' Success*') }).Count
    Check "the History page shows the cleaned items ($shown)" ($shown -eq $offered.Count)
    Invoke (ById $root 'InstallMode')
} finally { Stop-App 15000 }
Remove-Item -LiteralPath (Join-Path $env:APPDATA 'OracleWindowVendor') -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------------------------
# C. Two apps are queued. Stop is pressed, and the window is asked to close, while the first
#    uninstaller is still working: it is left to finish, the second app is kept, and the
#    window stays until then.
$first=New-Fixture 'OracleFixtureStopOne' 'OracleStop Alpha' 'child'
$second=New-Fixture 'OracleFixtureStopTwo' 'OracleStop Beta' 'child'
$root=Start-App '' @{ORACLE_PUBLISHER_DELAY_MS='8000'}
try {
    Open-Uninstall $root
    Check 'both fixture apps are selected' ((Select-Installed $root @($first.Name,$second.Name)) -eq 2 -and [bool](Named $root '2 apps selected'))
    Start-Removal $root
    $removing=Wait-Until { (Stage-Texts $root) -contains ('Removing'+$ellipsis) } 60 200
    Check 'the first uninstaller is running' ([bool]$removing)
    $stop=ById $root 'StopUninstall'
    Check 'a running removal offers Stop' ([bool]$stop -and $stop.Current.IsEnabled)
    $pressed=Get-Date
    Invoke $stop 400
    Check "Stop is acknowledged ($(Status $root))" ((Status $root) -eq 'Waiting for the current uninstaller. The next app will be kept.')
    $process.CloseMainWindow() | Out-Null
    Start-Sleep -Milliseconds 800
    Check "closing does not abandon a running uninstaller: the window stays ($(Status $root))" (-not $process.HasExited -and (Status $root) -eq 'Wait for the current removal/check to finish, then close this window.')
    $state=Wait-Removal $root 300
    $waited=[int]((Get-Date)-$pressed).TotalMilliseconds
    if ($state -eq 'review') { Invoke (Everywhere-Named 'Keep / go back'); $state=Wait-Removal $root 120 }
    $stages=Stage-Texts $root
    Check "the first app was removed after its uninstaller finished, $waited ms after Stop ($($stages -join ', '))" ($waited -gt 3000 -and -not (Registered $first.Key) -and $stages -contains 'Success')
    Check 'the second app was kept, and says so' ((Registered $second.Key) -and $stages -contains 'Cancelled')
    $process.CloseMainWindow() | Out-Null
    Check 'once nothing is running, the window closes' ($process.WaitForExit(15000))
} finally { Stop-App 15000 }
foreach ($key in $first.Key,$second.Key) { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($arp+'\'+$key,$false) }
}

if ($Real) {
    # -----------------------------------------------------------------------------------------
    # D. Real apps: installed by WinGet through the window, then removed by their own
    #    uninstallers through the window. A helper presses the buttons of the uninstallers'
    #    own dialogs, as the person at the keyboard would.
    $apps=@(
        [pscustomobject]@{ Card='7-Zip'; Id='7zip.7zip'; Installed='7-Zip' },
        [pscustomobject]@{ Card='Notepad++'; Id='Notepad++.Notepad++'; Installed='Notepad++' },
        [pscustomobject]@{ Card='PuTTY'; Id='PuTTY.PuTTY'; Installed='PuTTY' },
        [pscustomobject]@{ Card='WinSCP'; Id='WinSCP.WinSCP'; Installed='WinSCP' }
    )
    function Listed([string]$id) { & winget list --id $id --exact --accept-source-agreements --disable-interactivity *> $null; $LASTEXITCODE -eq 0 }
    $before=@(Operations).Count
    $root=Start-App ''
    try {
        $version=(& winget --version | Out-String).Trim()
        foreach ($app in $apps) { Toggle (Named $root $app.Card) }
        Check "the real apps are selected ($(@(Checked $root) -join ', '))" (@(Checked $root).Count -eq $apps.Count)
        Invoke (ById $root 'Install')
        Toggle (Everywhere-Named 'I accept the app licenses and WinGet source terms.')
        Invoke (Everywhere-Named 'Start installation')
        $finished=Wait-Until { Texts $root | Where-Object { $_ -like 'Queue finished*' } | Select-Object -First 1 } 1500 1000
        Check 'the queue of real installs runs to its end' ([bool]$finished)
        $records=@(Operations | Select-Object -Skip $before)
        $summary=@()
        foreach ($app in $apps) {
            $record=$records | Where-Object { $_.Id -eq $app.Id } | Select-Object -Last 1
            $listed=Listed $app.Id
            $summary+="$($app.Card): $($record.Outcome), exit $($record.ExitCode), listed by WinGet $listed, $(([string]$record.Message) -replace '^Exact package identity verified: ','')"
            Check "$($app.Card): the recorded outcome agrees with what WinGet lists" ($record -and (($record.Outcome -eq 'Success') -eq $listed))
        }
        Wait-Until { (Named $root 'Refresh').Current.IsEnabled } 240 500 | Out-Null
        Start-Sleep -Milliseconds 800
        "NOTE real installs with WinGet $version ($finished): $($summary -join '; ')"
        Check 'the cards of the installed apps say so' (@(Cards $root | Where-Object { $_.Current.ItemStatus -like ('Installed '+$dot+'*') -and ($apps.Card -contains $_.Current.Name) }).Count -eq @($apps | Where-Object { Listed $_.Id }).Count)
        # Open detailed log, on a desktop where no one has a Notepad open.
        Invoke (ById $root 'HistoryMode')
        $open=@(Buttons (ById $root 'HistoryList') 'Open detailed log')
        Check "each real install offers its detailed log ($($open.Count))" ($open.Count -ge $apps.Count)
        if ($open.Count) {
            $known=@(Get-Process -Name notepad -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
            Invoke $open[0] 2000
            $started=Wait-Until { @(Get-CimInstance Win32_Process -Filter "Name='notepad.exe'" | Where-Object { $known -notcontains $_.ProcessId -and $_.CommandLine -like '*.log*' }) } 20
            Check "Open detailed log starts Notepad on a log ($(@($started | ForEach-Object { $_.CommandLine }) -join ' | '))" ([bool]$started)
            foreach ($instance in @($started)) { Stop-Process -Id $instance.ProcessId -Force -ErrorAction SilentlyContinue }
        }
        Invoke (ById $root 'InstallMode')

        # The uninstallers ask before they remove. This helper answers them.
        $helper=Start-Job -ArgumentList $process.Id -ScriptBlock {
            param($own)
            Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
            $automation=[Windows.Automation.AutomationElement]
            $wanted='Yes','&Yes','Uninstall','&Uninstall','Next >','&Next >','Close','&Close','Finish','&Finish','OK'
            $deadline=(Get-Date).AddMinutes(25)
            while ((Get-Date) -lt $deadline) {
                foreach ($window in $automation::RootElement.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)) {
                    try {
                        if ($window.Current.ProcessId -eq $own -or $window.Current.ClassName -in 'Shell_TrayWnd','Progman','WorkerW') { continue }
                        foreach ($button in $window.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition ($automation::ControlTypeProperty),([Windows.Automation.ControlType]::Button)))) {
                            if ($wanted -contains $button.Current.Name -and $button.Current.IsEnabled) {
                                "pressed '$($button.Current.Name)' in '$($window.Current.Name)'"
                                $button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 700; break
                            }
                        }
                    } catch { }
                }
                Start-Sleep -Milliseconds 700
            }
        }
        Open-Uninstall $root
        $installed=@($apps | Where-Object { Listed $_.Id })
        $selected=Select-Installed $root @($installed | ForEach-Object { $_.Installed })
        Check "the installed real apps are found in the list and selected ($selected of $($installed.Count))" ($selected -eq $installed.Count -and $selected -gt 0)
        $registrations=@{}; $commands=@()
        foreach ($view in 'HKLM:\SOFTWARE','HKLM:\SOFTWARE\WOW6432Node','HKCU:\SOFTWARE') {
            foreach ($key in @(Get-ChildItem -LiteralPath ($view+'\Microsoft\Windows\CurrentVersion\Uninstall') -ErrorAction SilentlyContinue)) {
                $name=[string]$key.GetValue('DisplayName')
                foreach ($app in $installed) { if ($name -like ($app.Installed+'*')) { $registrations[$app.Card]=$key.Name; $commands+="$($app.Card) [$($key.Name -replace '^HKEY_LOCAL_MACHINE','HKLM' -replace '^HKEY_CURRENT_USER','HKCU' -replace 'Microsoft\\Windows\\CurrentVersion\\Uninstall','...')]: $([string]$key.GetValue('UninstallString'))" } }
            }
        }
        "NOTE registered uninstallers: $($commands -join '; ')"
        $began=Get-Date
        Start-Removal $root
        $state=Wait-Removal $root 480
        if (-not $state) {
            # Say what the queue is waiting for: the programs started since it began, and the
            # windows on screen. The engine waits for everything an uninstaller starts.
            $started=@(Get-CimInstance Win32_Process | Where-Object { $_.CreationDate -gt $began -and $_.ProcessId -ne $PID } | ForEach-Object { $_.Name } | Sort-Object -Unique)
            $titles=@($automation::RootElement.FindAll($children,[Windows.Automation.Condition]::TrueCondition) | ForEach-Object { try { if ($_.Current.Name -and $_.Current.ProcessId -ne $process.Id) { $_.Current.Name } } catch { } } | Select-Object -First 10)
            $soFar=@(Receive-Job $helper -Keep -ErrorAction SilentlyContinue)
            "NOTE after 8 minutes the removal queue had not ended. Status: $(Status $root); stages: $((Stage-Texts $root) -join ', '); helper is $($helper.State) and pressed: $(($soFar | Select-Object -First 8) -join '; '); programs started since: $($started -join ', '); windows on screen: $($titles -join ' | ')"
            # A browser that an uninstaller opened is one such program. Close browsers and see.
            Get-Process -Name msedge,iexplore,chrome,firefox -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt $began } | Stop-Process -Force -ErrorAction SilentlyContinue
            $state=Wait-Removal $root 240
            "NOTE after closing the browsers opened since the removal began, the queue ended in: '$state'"
        }
        $stages=Stage-Texts $root
        "NOTE real removals ended in '$state' with stages: $($stages -join ', ')"
        Check 'the queue of real removals ends' ([bool]$state)
        "NOTE registrations still present after the removals: $(@($installed | ForEach-Object { $path=$registrations[$_.Card]; $_.Card+' '+$(if ($path) { Test-Path -LiteralPath ('Registry::'+$path) } else { 'not found before' }) }) -join '; ')"
        $gone=@($installed | Where-Object { $registrations[$_.Card] -and -not (Test-Path -LiteralPath ('Registry::'+$registrations[$_.Card])) }).Count
        $successes=@($stages | Where-Object { $_ -eq 'Success' }).Count
        Check "every app marked Success is really gone from Windows, and no other ($successes marked, $gone gone)" ($successes -eq $gone)
        Check 'at least one real app was removed by its own uninstaller' ($gone -ge 1)
        if ($state -eq 'review') {
            $review=Window-With 'Keep what matters'
            $offered=@(Cards $review | Where-Object { $_.Current.AutomationId -ne 'RemovalConsent' } | ForEach-Object { $_.Current.Name })
            "NOTE leftovers offered after the real removals ($($offered.Count)): $(($offered | Select-Object -First 12) -join ' | ')"
            $foreign=@($offered | Where-Object { $name=$_; -not ($installed | Where-Object { $name -like ($_.Installed+'*') }) })
            Check "every leftover offered belongs to an app that was just removed ($($foreign -join ' | '))" ($foreign.Count -eq 0)
            Picture $Pictures 'real-leftover-review' | Out-Null
            Invoke (Everywhere-Named 'Keep / go back')
            Wait-Removal $root 180 | Out-Null
        }
        Stop-Job $helper -ErrorAction SilentlyContinue
        $pressed=@(Receive-Job $helper -ErrorAction SilentlyContinue)
        "NOTE uninstaller dialogs answered: $(($pressed | Select-Object -First 14) -join '; ')"

        # A Microsoft Store app, when this image has one that can be removed.
        Invoke (ById $root 'InstalledStore')
        Start-Sleep -Milliseconds 900
        $store=@(Cards (ById $root 'InstalledList') | Where-Object { $_.Current.IsEnabled })
        if ($store.Count) {
            $name=$store[0].Current.Name
            $packagesBefore=@(Get-AppxPackage | ForEach-Object { $_.PackageFullName })
            Toggle $store[0]
            Start-Removal $root
            $state=Wait-Removal $root 300
            if ($state -eq 'review') { Invoke (Everywhere-Named 'Keep / go back'); Wait-Removal $root 120 | Out-Null }
            $packagesAfter=@(Get-AppxPackage | ForEach-Object { $_.PackageFullName })
            $removed=@($packagesBefore | Where-Object { $packagesAfter -notcontains $_ })
            $stages=Stage-Texts $root
            "NOTE Store app '$name': stages $($stages -join ', '); packages removed: $($removed -join ', ')"
            Check "a Microsoft Store app marked Success is really removed for this user ($name)" (($stages -contains 'Success') -eq ($removed.Count -ge 1))
        } else { 'NOTE this image has no removable Microsoft Store app in the list; that removal was not exercised' }
    } finally { Stop-App 20000; Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue }
}
"disposable ui: $failed failed"
if ($failed) { exit 1 }
