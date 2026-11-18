# Drives the Uninstall page of a built 1nstall.exe from outside, through UI Automation.
# Needs an interactive desktop.
#
# This test only reads. It lists the installed apps, filters and searches them, selects one and
# opens the removal review, then always goes back: it never confirms a removal. The application
# runs with --ui-test, where the engine refuses to remove or clean anything in any case.
param([Parameter(Mandatory)][string]$Exe)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$automation=[Windows.Automation.AutomationElement]
$descendants=[Windows.Automation.TreeScope]::Descendants
$failed=0
function Check([string]$name,[bool]$condition) { if ($condition) { "PASS $name" } else { "FAIL $name"; $script:failed++ } }
function All($root,$type) { $root.FindAll($descendants,(New-Object Windows.Automation.PropertyCondition ($automation::ControlTypeProperty),$type)) }
function Named($root,[string]$name) { $root.FindFirst($descendants,(New-Object Windows.Automation.PropertyCondition ($automation::NameProperty),$name)) }
function ById($root,[string]$id) { $root.FindFirst($descendants,(New-Object Windows.Automation.PropertyCondition ($automation::AutomationIdProperty),$id)) }
function Toggle($element) { $element.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle(); Start-Sleep -Milliseconds 700 }
function Invoke($element) { $element.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 800 }
function Everywhere([string]$property,[string]$value) {
    $field=if ($property -eq 'Id') { $automation::AutomationIdProperty } else { $automation::NameProperty }
    $condition=New-Object Windows.Automation.AndCondition (New-Object Windows.Automation.PropertyCondition ($automation::ProcessIdProperty),$process.Id),(New-Object Windows.Automation.PropertyCondition $field,$value)
    $automation::RootElement.FindFirst($descendants,$condition)
}
# The heading reads "Installed · N apps".
function Shown($root) { $heading=(ById $root 'ResultCount').Current.Name; if ($heading -match '^Installed · (\d+) apps$') { [int]$Matches[1] } else { -1 } }

$exe=(Resolve-Path -LiteralPath $Exe).Path
$process=Start-Process -FilePath $exe -ArgumentList '--ui-test' -PassThru
try {
    $deadline=(Get-Date).AddSeconds(20)
    do { Start-Sleep -Milliseconds 100; $process.Refresh() } while ($process.MainWindowHandle -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline -and -not $process.HasExited)
    if ($process.MainWindowHandle -eq [IntPtr]::Zero) { throw 'The application showed no window.' }
    Start-Sleep -Milliseconds 1500
    $root=$automation::FromHandle($process.MainWindowHandle)

    Invoke (ById $root 'UninstallMode')
    Check 'Uninstall shows its page and hides the library' ([bool](ById $root 'InstalledSearch') -and -not (Named $root 'Details for 1Password'))
    # Opening the page reads the installed apps; wait for the count.
    $status=ById $root 'UninstallStatus'
    $deadline=(Get-Date).AddSeconds(120)
    do { Start-Sleep -Milliseconds 400; $text=$status.Current.Name } while ($text -notmatch '^\d+ installed apps · \d+ scan warnings' -and (Get-Date) -lt $deadline)
    Check "the installed apps are read ($text)" ($text -match '^(\d+) installed apps · (\d+) scan warnings')
    $total=if ($text -match '^(\d+) installed apps') { [int]$Matches[1] } else { 0 }
    Check "the heading counts the same apps ($(Shown $root))" ($total -gt 0 -and (Shown $root) -eq $total)
    Check 'nothing is selected and nothing can be removed yet' ([bool](Named $root '0 apps selected') -and -not (ById $root 'ReviewUninstall').Current.IsEnabled)

    # Desktop and Microsoft Store split the list between them.
    Invoke (ById $root 'InstalledDesktop'); $desktop=Shown $root
    Invoke (ById $root 'InstalledStore'); $store=Shown $root
    Invoke (ById $root 'InstalledAll')
    Check "Desktop ($desktop) and Microsoft Store ($store) add up to all ($total)" ($desktop -gt 0 -and $desktop+$store -eq $total -and (Shown $root) -eq $total)

    # Search narrows the list by name or publisher.
    $search=ById $root 'InstalledSearch'
    $search.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('zzz-no-such-app-zzz'); Start-Sleep -Milliseconds 700
    Check 'a search with no match shows none' ((Shown $root) -eq 0)
    $search.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue(''); Start-Sleep -Milliseconds 700
    Check 'clearing the search brings every app back' ((Shown $root) -eq $total)

    # Select the first app that can be removed, and open the review.
    $list=ById $root 'InstalledList'
    $switch=@(All $list ([Windows.Automation.ControlType]::CheckBox) | Where-Object { $_.Current.IsEnabled })[0]
    $name=$switch.Current.Name
    Toggle $switch
    Check "selecting an app ($name) adds it to the selection" ([bool](Named $root '1 app selected') -and [bool](Named $root "Remove $name from selection"))
    $review=ById $root 'ReviewUninstall'
    Check 'a selected app can be reviewed' ($review.Current.IsEnabled)
    Invoke $review
    $proceed=Everywhere 'Id' 'RemovalProceed'
    Check 'the review names what would be removed' ([bool]$proceed -and $proceed.Current.Name -eq 'Remove 1 apps' -and [bool](Everywhere 'Name' 'Ready to make some room?'))
    Check 'nothing can be removed before fresh consent' (-not $proceed.Current.IsEnabled)
    Toggle (Everywhere 'Id' 'RemovalConsent')
    Check 'consent enables the removal' ($proceed.Current.IsEnabled)
    # This test never proceeds. It goes back.
    Invoke (Everywhere 'Name' 'Keep / go back')
    Check 'going back closes the review and starts nothing' (-not (Everywhere 'Id' 'RemovalProceed') -and -not (ById $root 'StopUninstall') -and (ById $root 'RefreshInstalled').Current.IsEnabled)
    Check 'the app is still selected, and still installed' ([bool](Named $root '1 app selected') -and (Shown $root) -eq $total)

    Invoke (ById $root 'ClearUninstallSelection')
    Check 'Clear selection empties it' ([bool](Named $root '0 apps selected') -and -not (ById $root 'ReviewUninstall').Current.IsEnabled)
    Check 'no leftover check is offered without recorded removals' (-not (ById $root 'CheckLeftovers').Current.IsEnabled)

    Invoke (ById $root 'InstallMode')
    Check 'Install brings the library back' ([bool](Named $root 'Details for 1Password') -and -not (ById $root 'InstalledSearch'))
} finally {
    if (-not $process.HasExited) { $process.CloseMainWindow() | Out-Null; if (-not $process.WaitForExit(5000)) { $process.Kill() } }
}
"uninstall ui: $failed failed"
if ($failed) { exit 1 }
