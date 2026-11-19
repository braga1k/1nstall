# Drives the file dialogs of a built 1nstall.exe from outside, through UI Automation: saving
# and loading a selection, saving a snapshot of what is installed, and saving the diagnostics.
# Needs an interactive desktop.
#
# The application runs with --ui-test, so its own data stays beside the executable. The files
# are saved to, and loaded from, a folder beside the executable too. The Windows file dialog
# itself remembers the last folder used by this program, in the profile of the current user.
# Unless -SkipInventory is given, the test asks WinGet what is installed, which only reads.
# -OpenLog also opens a detailed log in Notepad and closes that Notepad again; leave it out on
# a desktop where a Notepad with unsaved work may be open.
param([Parameter(Mandatory)][string]$Exe, [switch]$SkipInventory, [switch]$OpenLog)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$ellipsis=[string][char]0x2026
function Menu-Item([string]$name) {
    Invoke (ById $root 'UserProfiles') 600
    $item=Wait-Until { Everywhere-Named $name } 5
    if (-not $item) { throw "No menu item '$name'." }
    # The item opens a modal window, so its action is started without waiting for it to return.
    $item.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Milliseconds 900
}

$exe=(Resolve-Path -LiteralPath $Exe).Path
$folder=Split-Path $exe
$work=Join-Path $folder 'test-files'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work | Out-Null
$history=Join-Path $folder 'test-data\operations.json'
if (Test-Path -LiteralPath $history) { Remove-Item -LiteralPath $history }
$logs=Join-Path $folder 'test-logs'
$root=Start-App
try {
    # 1. Save the current selection.
    Toggle (Named $root '7-Zip'); Toggle (Named $root 'Peace GUI')
    Check 'three apps are selected' ([bool](Named $root '3 apps selected'))
    $saved=Join-Path $work 'selection.json'
    Invoke (ById $root 'SaveSetup')
    $dialog=File-Dialog
    Check 'Save opens the Windows file dialog' ([bool]$dialog)
    if ($dialog) {
        # Windows shows the proposed name without its extension when extensions are hidden.
        $proposed=File-Name $dialog
        Check "it proposes a name ($proposed)" ($proposed -eq 'my-setup.json' -or $proposed -eq 'my-setup')
        if ($proposed -notlike 'my-setup*') { "NOTE the Save dialog as UI Automation sees it: $(Describe-Dialog $dialog)" }
        Answer-FileDialog $dialog $saved
    }
    $written=Wait-Until { Test-Path -LiteralPath $saved } 10
    if (-not $written) { "NOTE nothing was saved; dialogs still open: $(@(System-Dialogs | ForEach-Object { Describe-Dialog $_ }) -join ' || ')"; foreach ($open in (System-Dialogs)) { Close-Dialog $open } }
    $profile=if ($written) { Get-Content -LiteralPath $saved -Raw | ConvertFrom-Json } else { $null }
    Check "the selection is saved as a version 1 profile ($(@($profile.Apps) -join ', '))" ($profile -and $profile.Version -eq 1 -and (@($profile.Apps) -join '|') -eq 'extra_7zip|apo|peace')
    Check 'the dialog is closed and the window is usable' (-not (System-Dialogs).Count -and (ById $root 'Install').Current.IsEnabled)

    # 2. Cancelling a file dialog saves nothing.
    Invoke (ById $root 'SaveSetup')
    $dialog=File-Dialog
    if ($dialog) { Set-File-Name $dialog (Join-Path $work 'cancelled.json'); Close-Dialog $dialog }
    Check 'a cancelled dialog saves nothing' ([bool]$dialog -and -not (Test-Path -LiteralPath (Join-Path $work 'cancelled.json')) -and -not (System-Dialogs).Count)

    # 3. Load it back: preview first, then the selection.
    Invoke (ById $root 'ClearSelection')
    Check 'the selection is empty before loading' ([bool](Named $root '0 apps selected'))
    Menu-Item 'Load saved profile...'
    $dialog=File-Dialog
    Check 'Load opens the Windows file dialog' ([bool]$dialog)
    if ($dialog) { Answer-FileDialog $dialog $saved }
    $use=Wait-Until { Everywhere-Named 'Use selected apps' } 10
    Check 'the saved profile is previewed before anything is selected' ([bool]$use -and [bool](Everywhere-Named 'Preview portable setup') -and [bool](Named $root '0 apps selected'))
    if ($use) {
        $rows=@(Windows-Of | ForEach-Object { Cards $_ } | Where-Object { $_.Current.Name -like '* · *' } | ForEach-Object { $_.Current.Name })
        Check "the preview lists the three apps ($($rows -join '; '))" ($rows.Count -eq 3 -and $rows[0] -like '7-Zip · *' -and $rows[1] -like 'Equalizer APO · *' -and $rows[2] -like 'Peace GUI · *')
        Invoke $use
    }
    Check "loading restores the selection ($((Checked $root) -join ', '))" (((Checked $root) -join '|') -eq '7-Zip|Equalizer APO|Peace GUI' -and [bool](Named $root '3 apps selected'))

    # 4. A file that is not a selection is refused with a reason, and nothing changes.
    $damaged=Join-Path $work 'damaged.json'; [IO.File]::WriteAllText($damaged,'{"Version":1,"Apps":["extra_7zip",')
    Menu-Item 'Load saved profile...'
    $dialog=File-Dialog; if ($dialog) { Answer-FileDialog $dialog $damaged }
    $box=Message-Box
    Check "a damaged file is refused with a reason ($(if ($box) { $box.Current.Name+': '+(Message-Text $box) }))" ([bool]$box -and $box.Current.Name -eq 'Could not import profile' -and (Message-Text $box).Length -gt 0)
    if ($box) { Close-Dialog $box }
    Check 'the selection is unchanged after the refusal' (((Checked $root) -join '|') -eq '7-Zip|Equalizer APO|Peace GUI')

    # 5. A version 2 file with a package this catalog does not have: listed, but not selectable.
    $foreign=Join-Path $work 'foreign.json'
    [IO.File]::WriteAllText($foreign,'{"Version":2,"Kind":"1nstall-selection","Apps":[{"Id":"7zip.7zip","Source":"winget","Name":"7-Zip","Version":"24.09"},{"Id":"No.Such.Package","Source":"winget","Name":"Nothing Here","Version":"1.0"}]}')
    Menu-Item 'Load saved profile...'
    $dialog=File-Dialog; if ($dialog) { Answer-FileDialog $dialog $foreign }
    $use=Wait-Until { Everywhere-Named 'Use selected apps' } 10
    if ($use) {
        $choices=@(Windows-Of | ForEach-Object { Cards $_ } | Where-Object { $_.Current.Name -like '* · *' })
        $unknown=$choices | Where-Object { $_.Current.Name -like 'Nothing Here · Unavailable in this catalog*' } | Select-Object -First 1
        Check 'a package outside the catalog is shown and cannot be chosen' ([bool]$unknown -and -not $unknown.Current.IsEnabled)
        Check 'a package of the catalog shows its recorded version' ([bool]($choices | Where-Object { $_.Current.Name -like '7-Zip · * · recorded version 24.09' }))
        Invoke $use
    }
    Check "only the catalog app is selected ($((Checked $root) -join ', '))" ([bool]$use -and ((Checked $root) -join '|') -eq '7-Zip')

    # 6. The diagnostics are saved as the text that was reviewed.
    Invoke (ById $root 'HistoryMode')
    Invoke (Named $root ('Review diagnostic export'+$ellipsis))
    $text=Everywhere-Id 'DiagnosticsText'
    $reviewed=if ($text) { Value $text } else { '' }
    $diagnostics=Join-Path $work 'diagnostics.txt'
    Invoke (Everywhere-Named ('Save reviewed diagnostics'+$ellipsis))
    $dialog=File-Dialog
    if ($dialog) { Check "the diagnostics dialog proposes a name ($(File-Name $dialog))" ((File-Name $dialog) -in '1nstall-diagnostics.txt','1nstall-diagnostics'); Answer-FileDialog $dialog $diagnostics }
    $written=Wait-Until { Test-Path -LiteralPath $diagnostics } 10
    $bytes=if ($written) { [IO.File]::ReadAllBytes($diagnostics) } else { @() }
    $text=if ($written) { [IO.File]::ReadAllText($diagnostics) } else { '' }
    Check 'the saved diagnostics are the reviewed text, as UTF-8' ($written -and $reviewed.Length -gt 0 -and $text -eq $reviewed -and $bytes.Length -gt 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Invoke (Everywhere-Named 'Close')
    Invoke (ById $root 'InstallMode')

    # 7. A snapshot of what is installed needs an inventory first.
    Menu-Item ('Save installed setup snapshot'+$ellipsis)
    $box=Message-Box
    Check "without an inventory a snapshot is refused ($(if ($box) { $box.Current.Name }))" ([bool]$box -and $box.Current.Name -eq 'Inventory required')
    if ($box) { Close-Dialog $box }
    if (-not $SkipInventory) {
        $refresh=Named $root 'Refresh'
        Invoke $refresh
        Check 'the inventory finishes' ([bool](Wait-Until { $refresh.Current.IsEnabled } 120 500))
        Start-Sleep -Milliseconds 500
        Menu-Item ('Save installed setup snapshot'+$ellipsis)
        $use=Wait-Until { Everywhere-Named 'Use selected apps' } 10
        if ($use) {
            $listed=@(Windows-Of | ForEach-Object { Cards $_ } | Where-Object { $_.Current.Name -like '* · Installed · *' }).Count
            Check "the snapshot lists installed packages to choose from ($listed)" ($listed -gt 0 -and [bool](Everywhere-Named 'Select installed apps to save'))
            Invoke $use
            $snapshot=Join-Path $work 'snapshot.json'
            $dialog=File-Dialog
            if ($dialog) { Check "the snapshot dialog proposes a name ($(File-Name $dialog))" ((File-Name $dialog) -in 'installed-setup.json','installed-setup'); Answer-FileDialog $dialog $snapshot }
            $written=Wait-Until { Test-Path -LiteralPath $snapshot } 10
            $setup=if ($written) { Get-Content -LiteralPath $snapshot -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
            Check "the snapshot is a version 2 selection with every listed package ($(@($setup.Apps).Count))" ($setup -and $setup.Version -eq 2 -and $setup.Kind -eq '1nstall-selection' -and @($setup.Apps).Count -eq $listed -and @($setup.Apps | Where-Object { -not $_.Id -or -not $_.Source }).Count -eq 0)
            # And it loads back through the same preview.
            Menu-Item 'Load saved profile...'
            $dialog=File-Dialog; if ($dialog) { Answer-FileDialog $dialog $snapshot }
            $use=Wait-Until { Everywhere-Named 'Use selected apps' } 10
            $previewed=@(Windows-Of | ForEach-Object { Cards $_ } | Where-Object { $_.Current.Name -like '* · *' }).Count
            Check "the snapshot loads back into a preview of the same packages ($previewed)" ([bool]$use -and $previewed -eq $listed)
            if ($use) { Invoke (Everywhere-Named 'Close') }
        } else {
            # A machine where WinGet lists nothing it can identify has nothing to save, and one
            # where WinGet's export does not answer (its source terms were never accepted, for
            # one) still has no inventory.
            $box=Message-Box 3
            "NOTE no snapshot on this machine: $(if ($box) { $box.Current.Name+': '+(Message-Text $box) }); the Refresh button says: $($refresh.Current.HelpText)"
            Check "with nothing to list, the snapshot says why ($(if ($box) { $box.Current.Name }))" ([bool]$box -and $box.Current.Name -in 'Nothing to save','Inventory required')
            if ($box) { Close-Dialog $box }
        }
    }

    if ($OpenLog) {
        # 8. Open detailed log starts Notepad on the log of that operation.
        New-Item -ItemType Directory -Path (Split-Path $history) -Force | Out-Null
        $log=Join-Path $logs 'dialogs-ui-fixture.log'; [IO.File]::WriteAllText($log,'fixture log')
        $record=[ordered]@{Timestamp='2026-11-18 09:00:00';Action='Install';Id='7zip.7zip';Source='winget';Name='7-Zip';Outcome='Success';Message='Fixture.';LogPath=$log;ExitCode=0}
        [IO.File]::WriteAllText($history,(ConvertTo-Json -InputObject @($record) -Depth 3),(New-Object Text.UTF8Encoding $false))
        $before=@(Get-Process -Name notepad -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
        Invoke (ById $root 'HistoryMode')
        $open=@(Buttons (ById $root 'HistoryList') 'Open detailed log')
        Check 'the operation offers its detailed log' ($open.Count -eq 1)
        if ($open.Count) {
            Invoke $open[0] 1500
            $started=Wait-Until { @(Get-CimInstance Win32_Process -Filter "Name='notepad.exe'" | Where-Object { $before -notcontains $_.ProcessId -and $_.CommandLine -like '*dialogs-ui-fixture.log*' }) } 15
            Check "Open detailed log starts Notepad on that log ($(@($started | ForEach-Object { $_.CommandLine }) -join ' | '))" ([bool]$started)
            foreach ($instance in @($started)) { Stop-Process -Id $instance.ProcessId -Force -ErrorAction SilentlyContinue }
        }
        Invoke (ById $root 'InstallMode')
    }

    Check 'the application is still running, with no dialog left open' (-not $process.HasExited -and -not (System-Dialogs).Count)
    $session=Get-ChildItem -LiteralPath $logs -Filter ('session-*-'+$process.Id+'.log') | Select-Object -First 1
    $log=if ($session) { Get-Content -LiteralPath $session.FullName -Raw } else { '' }
    Check 'the session log records the saves and the imports' ($log -match 'Profile saved\.' -and $log -match 'Profile imported\.')
} finally {
    Stop-App
    if (Test-Path -LiteralPath $history) { Remove-Item -LiteralPath $history }
}
"dialogs ui: $failed failed"
if ($failed) { exit 1 }
