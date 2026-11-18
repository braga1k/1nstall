# Drives the install library of a built 1nstall.exe from outside, through UI Automation,
# and checks what a user of the 3.6 library relies on. Needs an interactive desktop.
# It selects and searches only; nothing is installed. The application runs with --ui-test,
# so nothing in the user's profile is read or written.
param([Parameter(Mandatory)][string]$Exe)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$automation=[Windows.Automation.AutomationElement]
$descendants=[Windows.Automation.TreeScope]::Descendants
$failed=0
function Check([string]$name,[bool]$condition) { if ($condition) { "PASS $name" } else { "FAIL $name"; $script:failed++ } }
function All($root,$type) { $root.FindAll($descendants,(New-Object Windows.Automation.PropertyCondition ($automation::ControlTypeProperty),$type)) }
function Named($root,[string]$name) { $root.FindFirst($descendants,(New-Object Windows.Automation.PropertyCondition ($automation::NameProperty),$name)) }
function Cards($root) { @(All $root ([Windows.Automation.ControlType]::CheckBox)) }

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

    # A card on screen has its content; one far down the list gets it when scrolled to.
    $first=$cards[0].Current.Name; $last=$cards[$cards.Count-1].Current.Name
    Check "the first card ($first) shows its Details button" ([bool](Named $root "Details for $first"))
    Check "the last card ($last) is not built before it is needed" (-not (Named $root "Details for $last"))
    $item=$null
    if ($cards[$cards.Count-1].TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern,[ref]$item)) { $item.ScrollIntoView() }
    else {
        $pane=@($root.FindAll($descendants,[Windows.Automation.Condition]::TrueCondition) | Where-Object { $scroll=$null; $_.TryGetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern,[ref]$scroll) -and $scroll.Current.VerticallyScrollable -and $scroll.Current.VerticalViewSize -lt 50 })[0]
        $pane.GetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern).SetScrollPercent(-1,100)
    }
    Start-Sleep -Milliseconds 700
    Check "the last card ($last) shows its Details button once scrolled to" ([bool](Named $root "Details for $last"))

    # Search keeps only the matching cards, and they are drawn.
    $search=@(All $root ([Windows.Automation.ControlType]::Edit))[0]
    $search.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('7-zip')
    Start-Sleep -Milliseconds 700
    $found=Cards $root
    Check "searching '7-zip' leaves one card ($($found.Count))" ($found.Count -eq 1 -and $found[0].Current.Name -eq '7-Zip')
    Check 'the found card shows its Details button' ([bool](Named $root 'Details for 7-Zip'))

    # Selecting it puts it in the selection panel; the selection survives clearing the search.
    $found[0].GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle()
    Start-Sleep -Milliseconds 500
    Check 'selecting the card adds a removable row' ([bool](Named $root 'Remove 7-Zip from selection'))
    Check 'the count reads 1 app selected' ([bool](Named $root '1 app selected'))
    $search.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('')
    Start-Sleep -Milliseconds 700
    $again=Cards $root
    Check "clearing the search restores every card ($($again.Count))" ($again.Count -eq $cards.Count)
    $selected=@($again | Where-Object { $_.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -eq 'On' })
    Check 'the selection survived the search' ($selected.Count -eq 1 -and $selected[0].Current.Name -eq '7-Zip')

    # A dependency is planned before the app that needs it.
    (Named $root 'Peace GUI').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle()
    Start-Sleep -Milliseconds 500
    $rows=@($root.FindAll($descendants,[Windows.Automation.Condition]::TrueCondition) | ForEach-Object { $_.Current.Name } | Where-Object { $_ -like 'Remove * from selection' })
    Check "the plan lists the dependency first ($($rows -join '; '))" (($rows -join '|') -eq 'Remove 7-Zip from selection|Remove Equalizer APO from selection|Remove Peace GUI from selection')

    # Removing a row clears that selection.
    (Named $root 'Remove 7-Zip from selection').GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Milliseconds 500
    Check 'removing a row clears its selection' (-not (Named $root 'Remove 7-Zip from selection') -and [bool](Named $root '1 app selected'))
} finally {
    if (-not $process.HasExited) { $process.CloseMainWindow() | Out-Null; if (-not $process.WaitForExit(3000)) { $process.Kill() } }
}
"library ui: $failed failed"
if ($failed) { exit 1 }
