# Drives the install library of a built 1nstall.exe from outside, through UI Automation,
# and checks what a user of the 3.6 library relies on. Needs an interactive desktop.
# It selects, searches and reads; nothing is installed. The application runs with --ui-test,
# so nothing in the user's profile is read or written. The last part runs "winget export",
# which only reads; pass -SkipInventory to leave it out.
param([Parameter(Mandatory)][string]$Exe, [switch]$SkipInventory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$automation=[Windows.Automation.AutomationElement]
$descendants=[Windows.Automation.TreeScope]::Descendants
$failed=0
function Check([string]$name,[bool]$condition) { if ($condition) { "PASS $name" } else { "FAIL $name"; $script:failed++ } }
function All($root,$type) { $root.FindAll($descendants,(New-Object Windows.Automation.PropertyCondition ($automation::ControlTypeProperty),$type)) }
function Named($root,[string]$name) { $root.FindFirst($descendants,(New-Object Windows.Automation.PropertyCondition ($automation::NameProperty),$name)) }
function Cards($root) { @(All $root ([Windows.Automation.ControlType]::CheckBox)) }
function Toggle($element) { $element.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle(); Start-Sleep -Milliseconds 600 }
function Invoke($element) { $element.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 700 }
function Checked($root) { @(Cards $root | Where-Object { $_.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -eq 'On' } | ForEach-Object { $_.Current.Name }) }
function Rows($root) { @($root.FindAll($descendants,[Windows.Automation.Condition]::TrueCondition) | ForEach-Object { $_.Current.Name } | Where-Object { $_ -like 'Remove * from selection' }) }
# Everything this process shows, including dialogs and menus, which are windows of their own.
function Everywhere([string]$name) {
    $condition=New-Object Windows.Automation.AndCondition (New-Object Windows.Automation.PropertyCondition ($automation::ProcessIdProperty),$process.Id),(New-Object Windows.Automation.PropertyCondition ($automation::NameProperty),$name)
    $automation::RootElement.FindFirst($descendants,$condition)
}

$exe=(Resolve-Path -LiteralPath $Exe).Path
$process=Start-Process -FilePath $exe -ArgumentList '--ui-test' -PassThru
try {
    $deadline=(Get-Date).AddSeconds(20)
    do { Start-Sleep -Milliseconds 100; $process.Refresh() } while ($process.MainWindowHandle -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline -and -not $process.HasExited)
    if ($process.MainWindowHandle -eq [IntPtr]::Zero) { throw 'The application showed no window.' }
    Start-Sleep -Milliseconds 1500
    $root=$automation::FromHandle($process.MainWindowHandle)

    # Every app is a named, toggleable card, whether or not it is on screen.
    $cards=Cards $root
    Check "every catalog app is a card ($($cards.Count))" ($cards.Count -ge 300)
    Check 'every card has a name' (@($cards | Where-Object { -not $_.Current.Name }).Count -eq 0)
    Check 'the heading counts them' ([bool](Named $root "All apps · $($cards.Count) apps"))

    # A card on screen has its content; one far down the list gets it when scrolled to.
    $first=$cards[0].Current.Name; $last=$cards[$cards.Count-1].Current.Name
    Check "the first card ($first) shows its Details button" ([bool](Named $root "Details for $first"))
    Check "the last card ($last) is not built before it is needed" (-not (Named $root "Details for $last"))
    $pane=@($root.FindAll($descendants,[Windows.Automation.Condition]::TrueCondition) | Where-Object { $scroll=$null; $_.TryGetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern,[ref]$scroll) -and $scroll.Current.VerticallyScrollable -and $scroll.Current.VerticalViewSize -lt 50 })[0]
    $pane.GetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern).SetScrollPercent(-1,100)
    Start-Sleep -Milliseconds 700
    Check "the last card ($last) shows its Details button once scrolled to" ([bool](Named $root "Details for $last"))

    # Search keeps only the matching cards, and they are drawn.
    $search=@(All $root ([Windows.Automation.ControlType]::Edit))[0]
    $search.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('7-zip'); Start-Sleep -Milliseconds 700
    $found=Cards $root
    Check "searching '7-zip' leaves one card ($($found.Count))" ($found.Count -eq 1 -and $found[0].Current.Name -eq '7-Zip')
    Check 'the found card shows its Details button' ([bool](Named $root 'Details for 7-Zip'))

    # Selecting through the toggle action, as an assistive tool does, reaches the selection.
    Toggle $found[0]
    Check 'selecting the card adds a removable row' ([bool](Named $root 'Remove 7-Zip from selection'))
    Check 'the count reads 1 app selected' ([bool](Named $root '1 app selected'))
    $search.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue(''); Start-Sleep -Milliseconds 700
    Check "clearing the search restores every card ($(@(Cards $root).Count))" (@(Cards $root).Count -eq $cards.Count)
    Check 'the selection survived the search' ((Checked $root) -join '|' -eq '7-Zip')

    # An app brings what it requires into the selection, as in 3.6: both are selected and counted.
    Toggle (Named $root 'Peace GUI')
    Check "an app selects what it requires ($((Checked $root) -join ', '))" (((Checked $root) -join '|') -eq '7-Zip|Equalizer APO|Peace GUI')
    Check 'requirements are counted' ([bool](Named $root '3 apps selected'))
    Check "the plan lists the requirement first ($((Rows $root) -join '; '))" (((Rows $root) -join '|') -eq 'Remove 7-Zip from selection|Remove Equalizer APO from selection|Remove Peace GUI from selection')
    # Removing a requirement removes what needed it.
    Invoke (Named $root 'Remove Equalizer APO from selection')
    Check "removing a requirement removes what needed it ($((Checked $root) -join ', '))" (((Checked $root) -join '|') -eq '7-Zip' -and [bool](Named $root '1 app selected'))

    # The details window. Selecting an app further down scrolled the list to it; go back up.
    $pane.GetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern).SetScrollPercent(-1,0); Start-Sleep -Milliseconds 700
    Invoke (Named $root 'Details for 7-Zip')
    $details=Everywhere 'Close details'
    Check 'Details opens a window for the app' ([bool]$details -and [bool](Everywhere 'Automatic · WinGet') -and [bool](Everywhere 'None declared'))
    if ($details) { Invoke $details }
    Check 'the details window closes' (-not (Everywhere 'Close details'))

    # A category keeps only its apps; All apps brings the rest back.
    $group=Named $root 'Files & Storage categories'
    $group.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Expand(); Start-Sleep -Milliseconds 500
    $category=@(All $root ([Windows.Automation.ControlType]::RadioButton) | Where-Object { $_.Current.Name -eq 'Files & Downloads' })[0]
    $category.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 800
    $inCategory=@(Cards $root).Count
    Check "a category keeps only its apps ($inCategory)" ($inCategory -gt 0 -and $inCategory -lt $cards.Count -and [bool](Named $root "Files & Downloads · $inCategory apps"))
    Check 'the selection survived the category' ((Checked $root) -contains '7-Zip')
    $everything=@(All $root ([Windows.Automation.ControlType]::RadioButton) | Where-Object { $_.Current.Name -eq 'All apps' })[0]
    $everything.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 800
    Check 'All apps brings every card back' (@(Cards $root).Count -eq $cards.Count)

    # A built-in profile replaces the selection with its apps.
    Invoke (Named $root 'All profiles')
    $profile=Everywhere 'Everyday essentials profile, 9 apps'
    Check 'the profile menu lists the built-in profiles' ([bool]$profile)
    if ($profile) {
        Invoke $profile
        Check "a profile selects its apps ($(@(Checked $root).Count))" (@(Checked $root).Count -eq 9 -and [bool](Named $root '9 apps selected') -and [bool](Named $root 'Everyday essentials profile applied. Review your apps before installing.'))
    }
    Invoke (Named $root 'Clear selection')
    Check 'Clear selection empties it' (@(Checked $root).Count -eq 0 -and [bool](Named $root '0 apps selected') -and [bool](Named $root 'Ready when you are.'))

    if (-not $SkipInventory) {
        # Refresh asks WinGet what is installed; Installed then shows only those apps.
        $refresh=Named $root 'Refresh'
        Invoke $refresh
        $deadline=(Get-Date).AddSeconds(90)
        do { Start-Sleep -Milliseconds 500 } while (-not $refresh.Current.IsEnabled -and (Get-Date) -lt $deadline)
        Check 'the inventory finishes' ($refresh.Current.IsEnabled)
        Start-Sleep -Milliseconds 500
        $marked=@(Cards $root | Where-Object { $_.Current.ItemStatus -like 'Installed ·*' }).Count
        Invoke (Named $root 'Installed')
        $shown=@(Cards $root).Count
        Check "the Installed view shows the installed apps ($shown shown, $marked marked)" ($shown -eq $marked -and [bool](Named $root "Installed · $shown apps"))
        # Two controls are named All apps: the category and the view. This is the view button.
        Invoke (@(All $root ([Windows.Automation.ControlType]::Button) | Where-Object { $_.Current.Name -eq 'All apps' })[0])
        Check 'All apps brings every card back again' (@(Cards $root).Count -eq $cards.Count)
    }
} finally {
    if (-not $process.HasExited) { $process.CloseMainWindow() | Out-Null; if (-not $process.WaitForExit(3000)) { $process.Kill() } }
}
"library ui: $failed failed"
if ($failed) { exit 1 }
