# Drives the Settings page of a built 1nstall.exe from outside, through UI Automation.
# The application runs with --ui-test, so nothing in the user's profile is read or written;
# the script checks that too. Needs an interactive desktop.
param([Parameter(Mandatory)][string]$Exe, [string]$Pictures='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class SettingsPicture {
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32")] static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32")] static extern bool PrintWindow(IntPtr window, IntPtr target, uint flags);
    public static void Save(IntPtr window, string path) {
        Rect rect; GetWindowRect(window, out rect);
        using(var bitmap=new Bitmap(rect.Right-rect.Left,rect.Bottom-rect.Top)) {
            using(var graphics=Graphics.FromImage(bitmap)) { IntPtr target=graphics.GetHdc(); PrintWindow(window,target,2); graphics.ReleaseHdc(target); }
            bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        }
    }
}
'@
$automation=[Windows.Automation.AutomationElement]
$descendants=[Windows.Automation.TreeScope]::Descendants
$failed=0
function Check([string]$name,[bool]$condition) { if ($condition) { "PASS $name" } else { "FAIL $name"; $script:failed++ } }
function Named($root,[string]$name) { $root.FindFirst($descendants,(New-Object Windows.Automation.PropertyCondition ($automation::NameProperty),$name)) }
function All($root,$type) { $root.FindAll($descendants,(New-Object Windows.Automation.PropertyCondition ($automation::ControlTypeProperty),$type)) }
function ById($root,[string]$id) { $root.FindFirst($descendants,(New-Object Windows.Automation.PropertyCondition ($automation::AutomationIdProperty),$id)) }
function Invoke($element) { $element.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 600 }
function Choose($root,[string]$id,[string]$item) {
    $combo=ById $root $id
    $combo.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Expand(); Start-Sleep -Milliseconds 400
    $script:lastOptionCount=@(All $combo ([Windows.Automation.ControlType]::ListItem)).Count
    $option=Named $combo $item
    if (-not $option) { throw "No option '$item' in $id." }
    $option.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 300
    $combo.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse(); Start-Sleep -Milliseconds 800
}
function Picture([string]$name) { if ($Pictures) { New-Item -ItemType Directory -Path $Pictures -Force | Out-Null; [SettingsPicture]::Save($process.MainWindowHandle,(Join-Path $Pictures ($name+'.png'))) } }

$saved=Join-Path $env:LOCALAPPDATA '1nstall\settings.json'
function Fingerprint { if (Test-Path -LiteralPath $saved) { (Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash } else { 'absent' } }
$before=Fingerprint

$exe=(Resolve-Path -LiteralPath $Exe).Path
$process=Start-Process -FilePath $exe -ArgumentList '--ui-test' -PassThru
try {
    $deadline=(Get-Date).AddSeconds(20)
    do { Start-Sleep -Milliseconds 100; $process.Refresh() } while ($process.MainWindowHandle -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline -and -not $process.HasExited)
    if ($process.MainWindowHandle -eq [IntPtr]::Zero) { throw 'The application showed no window.' }
    Start-Sleep -Milliseconds 1500
    $root=$automation::FromHandle($process.MainWindowHandle)
    $window=$root.Current.BoundingRectangle
    Picture 'dark-en'

    # A selection made before changing language must survive it.
    (Named $root '7-Zip').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle(); Start-Sleep -Milliseconds 500
    Check 'the test mode starts in English' ([bool](Named $root '1 app selected'))

    Invoke (Named $root 'Settings')
    Check 'the Settings page opens with its four choices' ([bool](ById $root 'ThemeChoice') -and [bool](ById $root 'AccentChoice') -and [bool](ById $root 'LanguageChoice') -and [bool](ById $root 'AutoUpdateChoice'))
    Check 'the library is hidden while Settings is open' (-not (Named $root 'Details for 1Password'))
    Check 'no update check runs in the test mode' ([bool](Named $root 'Updates are checked in the background.'))
    Picture 'settings-dark-en'

    Choose $root 'LanguageChoice' 'Português (Portugal)'
    Check 'Portuguese translates the navigation' ([bool](Named $root 'Instalar') -and [bool](Named $root 'Desinstalar'))
    Check 'Portuguese translates the Settings page' ([bool](Named $root 'Definições') -and [bool](Named $root 'Idioma'))
    Check "every language is offered, plus the system choice ($script:lastOptionCount)" ($script:lastOptionCount -eq 52)
    # The selection panel is hidden while Settings is open; look at it in the library.
    Invoke (Named $root 'Instalar')
    Check 'a counted text is translated through its pattern' ([bool](Named $root '1 app selecionada'))
    Check 'a selection row is translated' ([bool](Named $root 'Automático · WinGet'))
    # The button keeps its English automation name in every language, as in 3.6.
    Invoke (Named $root 'Settings')
    Picture 'settings-dark-pt'

    # Right-to-left: the navigation pane moves to the right-hand side of the window.
    $leftToRight=(Named $root 'Instalar').Current.BoundingRectangle
    Choose $root 'LanguageChoice' 'العربية'
    $install=(All $root ([Windows.Automation.ControlType]::Button)) | Where-Object { $_.Current.AutomationId -eq 'InstallMode' } | Select-Object -First 1
    $rightToLeft=$install.Current.BoundingRectangle
    Check "Arabic mirrors the layout (navigation from x=$([int]($leftToRight.X-$window.X)) to x=$([int]($rightToLeft.X-$window.X)))" (($leftToRight.X-$window.X) -lt $window.Width/2 -and ($rightToLeft.X-$window.X) -gt $window.Width/2)
    Picture 'settings-dark-ar'

    Choose $root 'LanguageChoice' 'English'
    Check 'English comes back' ([bool](Named $root 'Install') -and [bool](Named $root 'Language'))

    Choose $root 'ThemeChoice' 'Light'
    Picture 'settings-light-en'
    (ById $root 'AccentChoice').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle(); Start-Sleep -Milliseconds 800
    Picture 'settings-light-monochrome'
    (ById $root 'AccentChoice').GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle(); Start-Sleep -Milliseconds 500
    Choose $root 'ThemeChoice' 'Dark'

    # Back to the library: the selection made at the start is still there.
    Invoke (Named $root 'Install')
    $selected=@((All $root ([Windows.Automation.ControlType]::CheckBox)) | Where-Object { $_.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -eq 'On' })
    Check 'the selection survived the language and theme changes' ($selected.Count -eq 1 -and $selected[0].Current.Name -eq '7-Zip')
    Check 'the library is back' ([bool](Named $root 'Details for 1Password') -and [bool](Named $root 'Remove 7-Zip from selection'))
    Check 'the count is back in English' ([bool](Named $root '1 app selected'))
    Picture 'library-dark-en-after'
} finally {
    if (-not $process.HasExited) { $process.CloseMainWindow() | Out-Null; if (-not $process.WaitForExit(3000)) { $process.Kill() } }
}
Check 'the saved settings of this Windows user were not touched' ((Fingerprint) -eq $before)
"settings ui: $failed failed"
if ($failed) { exit 1 }
