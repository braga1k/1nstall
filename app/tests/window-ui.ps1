# Drives the main window of a built 1nstall.exe from outside, through UI Automation: its
# smallest size, maximising, the names assistive tools read, every language, both themes and,
# with -Keyboard, the keyboard. Needs an interactive desktop.
#
# The application runs with --ui-test, so nothing in the user's profile is read or written and
# nothing is installed or removed. -Keyboard sends real key presses to whichever window is in
# front: use it only on a desktop nobody is working on. -Pictures names a folder for pictures
# of the window in each state.
param([Parameter(Mandatory)][string]$Exe, [switch]$Keyboard, [string]$Pictures='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
function Rectangle($element) { $element.Current.BoundingRectangle }
function Named-AnyCase($root,[string]$name) { $root.FindFirst($descendants,(New-Object Windows.Automation.PropertyCondition ($automation::NameProperty),$name,([Windows.Automation.PropertyConditionFlags]::IgnoreCase))) }
function Inside($outer,$inner) { -not $inner.IsEmpty -and $inner.Left -ge $outer.Left-1 -and $inner.Top -ge $outer.Top-1 -and $inner.Right -le $outer.Right+1 -and $inner.Bottom -le $outer.Bottom+1 }
function Choose($root,[string]$id,[string]$item) {
    $combo=ById $root $id
    $combo.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Expand(); Start-Sleep -Milliseconds 350
    $option=Named $combo $item
    if (-not $option) { $combo.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse(); return $false }
    $option.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 250
    $combo.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse(); Start-Sleep -Milliseconds 600
    return $true
}
# Controls a person operates. Each needs a name for a screen reader to say.
$operable=@([Windows.Automation.ControlType]::Button,[Windows.Automation.ControlType]::CheckBox,[Windows.Automation.ControlType]::RadioButton,[Windows.Automation.ControlType]::ComboBox,[Windows.Automation.ControlType]::Edit,[Windows.Automation.ControlType]::MenuItem,[Windows.Automation.ControlType]::Hyperlink)
function Unnamed($root) {
    $found=@()
    foreach ($type in $operable) {
        foreach ($element in (All $root $type)) {
            $current=$element.Current
            # Not counted: the invisible button of the test mode, and the two halves of a scroll bar's
            # track, which Windows names by their role.
            if (-not $current.Name -and -not $current.IsOffscreen -and $current.AutomationId -ne 'TestFailure' -and $current.ClassName -ne 'RepeatButton') { $found+=($type.ProgrammaticName -replace '^ControlType\.','')+'#'+$current.AutomationId+'('+$current.ClassName+')' }
        }
    }
    $found
}

$exe=(Resolve-Path -LiteralPath $Exe).Path
$locales=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\locales.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$root=Start-App
try {
    $handle=$process.MainWindowHandle
    $scale=[UiNative]::GetDpiForWindow($handle)/96.0
    $dark=Picture $Pictures 'library-dark'

    # 1. The smallest size. The window may not get smaller than the size its layout needs.
    $transform=$root.GetCurrentPattern([Windows.Automation.TransformPattern]::Pattern)
    Check 'the window can be resized' ($transform.Current.CanResize)
    $transform.Resize(400,300); Start-Sleep -Milliseconds 900
    $window=Rectangle $root
    $minimum="$([int]($window.Width/$scale)) x $([int]($window.Height/$scale))"
    Check "asked for 400 x 300, the window stops at its smallest size ($minimum at scale $scale)" ([Math]::Abs($window.Width/$scale-1040) -le 2 -and [Math]::Abs($window.Height/$scale-540) -le 2)
    $outside=@()
    foreach ($id in 'InstallMode','UninstallMode','HistoryMode','Search','Profiles','UserProfiles','Install','MinimizeWindow','MaximizeWindow','CloseWindow') {
        $element=ById $root $id
        if (-not $element -or -not (Inside $window (Rectangle $element))) { $outside+=$id }
    }
    if (-not (Inside $window (Rectangle (Named $root 'Settings')))) { $outside+='Settings' }
    Check "at the smallest size the library keeps its controls inside the window ($($outside -join ', '))" ($outside.Count -eq 0)
    Check 'and still shows cards' ([bool](Named $root 'Details for 1Password'))
    Picture $Pictures 'library-smallest' | Out-Null
    Invoke (ById $root 'UninstallMode')
    Wait-Until { (ById $root 'UninstallStatus').Current.Name -match '^\d+ installed apps' } 120 400 | Out-Null
    $outside=@()
    foreach ($id in 'InstalledSearch','RefreshInstalled','ReviewUninstall','ClearUninstallSelection','InstalledAll','InstalledDesktop','InstalledStore') {
        $element=ById $root $id
        if (-not $element -or -not (Inside $window (Rectangle $element))) { $outside+=$id }
    }
    Check "at the smallest size the Uninstall page keeps its controls inside the window ($($outside -join ', '))" ($outside.Count -eq 0)
    Picture $Pictures 'uninstall-smallest' | Out-Null
    $unnamed=@(Unnamed $root)
    Check "every control of the Uninstall page has a name to read ($($unnamed -join ', '))" ($unnamed.Count -eq 0)
    Invoke (ById $root 'InstallMode')

    # 2. Maximise, restore, minimise.
    $state=$root.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern)
    $state.SetWindowVisualState([Windows.Automation.WindowVisualState]::Maximized); Start-Sleep -Milliseconds 900
    $maximized=Rectangle $root
    Check "maximising fills the screen and the button offers Restore ($([int]$maximized.Width) x $([int]$maximized.Height))" ($maximized.Width -ge $window.Width -and (ById $root 'MaximizeWindow').Current.Name -eq 'Restore')
    Picture $Pictures 'library-maximized' | Out-Null
    $state.SetWindowVisualState([Windows.Automation.WindowVisualState]::Normal); Start-Sleep -Milliseconds 900
    Check 'restoring brings the size back and the button offers Maximize' ([Math]::Abs((Rectangle $root).Width-$window.Width) -le 2 -and (ById $root 'MaximizeWindow').Current.Name -eq 'Maximize')
    $state.SetWindowVisualState([Windows.Automation.WindowVisualState]::Minimized); Start-Sleep -Milliseconds 700
    $state.SetWindowVisualState([Windows.Automation.WindowVisualState]::Normal); Start-Sleep -Milliseconds 900
    Check 'the window comes back from minimised with its content' ([bool](Named $root 'Details for 1Password') -and -not $process.HasExited)
    $transform.Resize([int](1240*$scale),[int](800*$scale)); Start-Sleep -Milliseconds 900

    # 3. Names for assistive tools, on the remaining pages.
    $unnamed=@(Unnamed $root)
    Check "every control of the library has a name to read ($($unnamed -join ', '))" ($unnamed.Count -eq 0)
    $cards=Cards $root
    $silent=@($cards | Where-Object { -not $_.Current.HelpText -and -not $_.Current.IsOffscreen }).Count
    Check "every card on screen describes its app ($silent without a description)" ($silent -eq 0)
    Invoke (ById $root 'HistoryMode')
    $unnamed=@(Unnamed $root)
    Check "every control of the History page has a name to read ($($unnamed -join ', '))" ($unnamed.Count -eq 0)
    Picture $Pictures 'history-dark' | Out-Null
    Invoke (Named $root 'Settings')
    $unnamed=@(Unnamed $root)
    Check "every control of the Settings page has a name to read ($($unnamed -join ', '))" ($unnamed.Count -eq 0)
    Picture $Pictures 'settings-dark' | Out-Null

    # 4. Every language: the page is translated as locales.json says, and right-to-left
    #    languages mirror the window.
    $window=Rectangle $root
    $keys='Theme','Language','Accent colour','Install','Uninstall'
    $wrong=@(); $unmirrored=@(); $caseOnly=@(); $tried=0
    foreach ($code in $locales.PSObject.Properties.Name) {
        $language=$locales.$code
        if (-not (Choose $root 'LanguageChoice' $language.Name)) { $wrong+="$code (not offered)"; continue }
        $tried++
        foreach ($key in $keys) {
            $expected=if ($code -ne 'en' -and $language.Strings.PSObject.Properties[$key]) { $language.Strings.$key } else { $key }
            if (-not (Wait-Until { Named-AnyCase $root $expected } 4 200)) { $wrong+="$code '$key' (expected '$expected')"; break }
            if (-not (Named $root $expected)) { $caseOnly+="$code '$expected'" }
        }
        $navigation=(ById $root 'InstallMode').Current.BoundingRectangle
        $onRight=($navigation.X-$window.X) -gt $window.Width/2
        if ([bool]$language.Rtl -ne $onRight) { $unmirrored+=$code }
        if ($Pictures -and ($code -in 'pt-PT','ar','ja','de')) { Picture $Pictures ('settings-'+$code) | Out-Null }
        if ($process.HasExited) { throw "The application closed while showing $code." }
    }
    Check "every language is offered and translates the page as its file says ($tried tried; wrong: $($wrong -join ', '))" ($tried -eq @($locales.PSObject.Properties).Count -and $wrong.Count -eq 0)
    # Inherited from 3.6, which compares the shown text with the new one without regard to case:
    # going straight from one language to another whose word differs only in capitals keeps
    # the capitals of the first until the application is restarted.
    "NOTE shown with the capitals of the language chosen before it: $(if ($caseOnly.Count) { $caseOnly -join ', ' } else { 'none' })"
    $rightToLeft=@($locales.PSObject.Properties | Where-Object { $_.Value.Rtl } | ForEach-Object { $_.Name })
    Check "right-to-left languages mirror the window, the others do not ($($rightToLeft -join ', '); wrong: $($unmirrored -join ', '))" ($rightToLeft.Count -gt 0 -and $unmirrored.Count -eq 0)
    Choose $root 'LanguageChoice' 'English' | Out-Null
    Check 'English comes back' ([bool](Named $root 'Language') -and [bool](Named $root 'Theme'))

    # 5. Both themes are drawn: the light one is clearly brighter than the dark one.
    Invoke (ById $root 'InstallMode')
    $folder=if ($Pictures) { $Pictures } else { Join-Path (Split-Path $exe) 'test-pictures' }
    $dark=Picture $folder 'theme-dark'
    Invoke (Named $root 'Settings'); Choose $root 'ThemeChoice' 'Light' | Out-Null; Invoke (ById $root 'InstallMode')
    $light=Picture $folder 'theme-light'
    $darkLevel=[int][UiNative]::Brightness($dark); $lightLevel=[int][UiNative]::Brightness($light)
    Check "the dark theme is dark and the light theme is light (brightness $darkLevel and $lightLevel of 255)" ($darkLevel -lt 110 -and $lightLevel -gt 150)
    Check "both pictures show a drawn window, not a blank one (detail $([Math]::Round([UiNative]::Detail($dark),2)) and $([Math]::Round([UiNative]::Detail($light),2)))" ([UiNative]::Detail($dark) -gt 0.2 -and [UiNative]::Detail($light) -gt 0.2)
    Invoke (Named $root 'Settings'); Choose $root 'ThemeChoice' 'Dark' | Out-Null; Invoke (ById $root 'InstallMode')

    if ($Keyboard) {
        # 6. The keyboard, with real key presses.
        Add-Type -AssemblyName System.Windows.Forms
        function Press([string]$keys,[int]$wait=700) {
            # Keys go to the window in front. A dialog of the application is left in front;
            # only when another program is in front is the main window brought back.
            if ([UiNative]::ForegroundProcess() -ne $process.Id) { [UiNative]::SetForegroundWindow($process.MainWindowHandle) | Out-Null; Start-Sleep -Milliseconds 300 }
            [System.Windows.Forms.SendKeys]::SendWait($keys); Start-Sleep -Milliseconds $wait
        }
        function Focused { try { $automation::FocusedElement.Current } catch { $null } }
        # Gives an element the keyboard focus, and says why when Windows refuses.
        function Focus($element,[string]$what) {
            try { $element.SetFocus(); Start-Sleep -Milliseconds 400; return $true }
            catch { "NOTE $what could not take the focus: $($_.Exception.InnerException.Message); focusable $($element.Current.IsKeyboardFocusable), enabled $($element.Current.IsEnabled), off screen $($element.Current.IsOffscreen), window in front $([UiNative]::GetForegroundWindow() -eq $process.MainWindowHandle)"; return $false }
        }
        # Another program's window in front (a system prompt left by an earlier test, for one)
        # would take the keys: on this throw-away desktop it is asked to close.
        foreach ($attempt in 1..4) {
            [UiNative]::SetForegroundWindow($process.MainWindowHandle) | Out-Null; Start-Sleep -Milliseconds 500
            if ([UiNative]::ForegroundProcess() -eq $process.Id) { break }
            $front=[UiNative]::GetForegroundWindow()
            "NOTE in front of the application: '$([UiNative]::GetText($front))' of $((Get-Process -Id ([UiNative]::ForegroundProcess()) -ErrorAction SilentlyContinue).ProcessName); asking it to close"
            [UiNative]::PostMessage($front,0x0010,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null; Start-Sleep -Milliseconds 1200
        }
        Check 'the window takes the keyboard' ([UiNative]::GetForegroundWindow() -eq $process.MainWindowHandle)
        Press '^f'
        Check "Ctrl+F goes to the search box ($((Focused).AutomationId))" ((Focused).AutomationId -eq 'Search')
        Press '7-zip' 900
        $found=Cards $root
        Check "typing searches ($($found.Count) card)" ($found.Count -eq 1 -and $found[0].Current.Name -eq '7-Zip')
        $focused=Focus $found[0] 'the card'
        Check 'a card takes the keyboard focus' $focused
        Press ' '
        Check 'Space on a card selects it' ([bool](Named $root '1 app selected') -and [bool](Named $root 'Remove 7-Zip from selection'))
        Press '{F1}' 1200
        Check 'F1 on a card opens its details' ([bool](Everywhere-Named 'Close details'))
        Press '{ESC}' 900
        Check 'Esc closes the details' (-not (Everywhere-Named 'Close details'))
        Focus (Named $root '7-Zip') 'the card, again' | Out-Null
        $before=(Focused).Name
        Press '{TAB}'
        $after=(Focused)
        Check "Tab moves on from the card ($before -> $($after.Name))" ($after -and ($after.Name -ne $before -or $after.AutomationId))
        Invoke (ById $root 'ClearSearch')
        Invoke (ById $root 'UninstallMode')
        [UiNative]::SetForegroundWindow($process.MainWindowHandle) | Out-Null; Start-Sleep -Milliseconds 300
        Press '^f'
        Check "on the Uninstall page Ctrl+F goes to its own search box ($((Focused).AutomationId))" ((Focused).AutomationId -eq 'InstalledSearch')
        Invoke (ById $root 'InstallMode')
        [UiNative]::SetForegroundWindow($process.MainWindowHandle) | Out-Null; Start-Sleep -Milliseconds 300
        Press '%{F4}' 1500
        Check 'Alt+F4 closes the application' ($process.WaitForExit(8000))
    }
} finally { Stop-App }
"window ui: $failed failed"
if ($failed) { exit 1 }
