# Shared by the interface tests that drive a built 1nstall.exe from outside, through UI
# Automation. Dot-source it:  . (Join-Path $PSScriptRoot 'common.ps1')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class UiNative {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32")] public static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32")] static extern bool PrintWindow(IntPtr window, IntPtr target, uint flags);
    [DllImport("user32")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32",CharSet=CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, string lParam);
    [DllImport("user32",CharSet=CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, System.Text.StringBuilder lParam);
    // The text of a classic control of another program, and setting it (WM_GETTEXT, WM_SETTEXT).
    public static string GetText(IntPtr window) { var text=new System.Text.StringBuilder(2048); SendMessage(window,0x000D,(IntPtr)text.Capacity,text); return text.ToString(); }
    public static void SetText(IntPtr window, string text) { SendMessage(window,0x000C,IntPtr.Zero,text); }
    [DllImport("user32")] static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    // Replaces the text of an edit box the way typing does: select all, replace the selection,
    // and mark the box as changed by the user (EM_SETSEL, EM_REPLACESEL, EM_SETMODIFY). The
    // Save dialog of some Windows versions ignores a name that was only set with WM_SETTEXT.
    public static void TypeText(IntPtr window, string text) {
        SendMessage(window,0x00B1,IntPtr.Zero,(IntPtr)(-1));
        SendMessage(window,0x00C2,(IntPtr)1,text);
        SendMessage(window,0x00B9,(IntPtr)1,IntPtr.Zero);
    }
    [DllImport("user32")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    // The process that owns the window in front.
    public static int ForegroundProcess() { uint process; GetWindowThreadProcessId(GetForegroundWindow(), out process); return (int)process; }
    [DllImport("user32")] public static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32")] public static extern uint GetDpiForWindow(IntPtr window);
    [StructLayout(LayoutKind.Sequential)] struct HighContrast { public uint Size; public uint Flags; public IntPtr DefaultScheme; }
    [DllImport("user32", SetLastError=true)] static extern bool SystemParametersInfo(uint action, uint size, ref HighContrast data, uint change);
    // Switches the high contrast of Windows on or off for this user (SPI_SETHIGHCONTRAST), and
    // tells every program. For disposable machines.
    public static bool SetHighContrast(bool on) {
        var data=new HighContrast(); data.Size=(uint)Marshal.SizeOf(typeof(HighContrast));
        if(!SystemParametersInfo(0x0042,data.Size,ref data,0)) return false;
        data.Flags=on?(data.Flags|1u):(data.Flags&~1u);
        return SystemParametersInfo(0x0043,data.Size,ref data,3);
    }
    public static void Save(IntPtr window, string path) {
        Rect rect; GetWindowRect(window, out rect);
        using(var bitmap=new Bitmap(rect.Right-rect.Left,rect.Bottom-rect.Top)) {
            using(var graphics=Graphics.FromImage(bitmap)) { IntPtr target=graphics.GetHdc(); PrintWindow(window,target,2); graphics.ReleaseHdc(target); }
            bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        }
    }
    // The share of pixels that are not one flat colour: a drawn window has many.
    public static double Detail(string path) {
        using(var bitmap=new Bitmap(path)) {
            var counts=new System.Collections.Generic.Dictionary<int,int>(); int total=0;
            for(int y=0;y<bitmap.Height;y+=4) for(int x=0;x<bitmap.Width;x+=4) { int colour=bitmap.GetPixel(x,y).ToArgb(); int seen; counts.TryGetValue(colour,out seen); counts[colour]=seen+1; total++; }
            int most=0; foreach(var count in counts.Values) if(count>most) most=count;
            return total==0?0:1.0-(double)most/total;
        }
    }
    // The average brightness of a picture, 0 (black) to 255 (white).
    public static double Brightness(string path) {
        using(var bitmap=new Bitmap(path)) {
            double sum=0; int total=0;
            for(int y=0;y<bitmap.Height;y+=4) for(int x=0;x<bitmap.Width;x+=4) { var colour=bitmap.GetPixel(x,y); sum+=(colour.R+colour.G+colour.B)/3.0; total++; }
            return total==0?0:sum/total;
        }
    }
}
'@
$automation=[Windows.Automation.AutomationElement]
$descendants=[Windows.Automation.TreeScope]::Descendants
$children=[Windows.Automation.TreeScope]::Children
$failed=0
function Check([string]$name,[bool]$condition) { if ($condition) { "PASS $name" } else { "FAIL $name"; $script:failed++ } }
function Property($field,$value) { New-Object Windows.Automation.PropertyCondition $field,$value }
function All($root,$type) { $root.FindAll($descendants,(Property ($automation::ControlTypeProperty) $type)) }
function Named($root,[string]$name) { $root.FindFirst($descendants,(Property ($automation::NameProperty) $name)) }
function ById($root,[string]$id) { $root.FindFirst($descendants,(Property ($automation::AutomationIdProperty) $id)) }
# An element that was not found is named by the line that asked for it.
function Need($element,[string]$action) { if (-not $element) { throw "$action`: the element was not found (line $((Get-PSCallStack)[2].ScriptLineNumber) of $(Split-Path -Leaf (Get-PSCallStack)[2].ScriptName))" } }
function Invoke($element,[int]$wait=800) { Need $element 'Invoke'; $element.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds $wait }
function Toggle($element,[int]$wait=600) { Need $element 'Toggle'; $element.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle(); Start-Sleep -Milliseconds $wait }
function Value($element) { $element.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value }
function Set-Value($element,[string]$text,[int]$wait=700) { Need $element 'Set-Value'; $element.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue($text); Start-Sleep -Milliseconds $wait }
function Texts($root) { @(All $root ([Windows.Automation.ControlType]::Text) | ForEach-Object { $_.Current.Name }) }
function Buttons($root,[string]$name) { @(All $root ([Windows.Automation.ControlType]::Button) | Where-Object { $_.Current.Name -eq $name }) }
function Cards($root) { @(All $root ([Windows.Automation.ControlType]::CheckBox)) }
function Checked($root) { @(Cards $root | Where-Object { $_.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -eq 'On' } | ForEach-Object { $_.Current.Name }) }
# Repeats a question until it has an answer, and returns it (or nothing when time runs out).
function Wait-Until([scriptblock]$question,[int]$seconds=20,[int]$step=250) {
    $deadline=(Get-Date).AddSeconds($seconds)
    do { $answer=& $question; if ($answer) { return $answer }; Start-Sleep -Milliseconds $step } while ((Get-Date) -lt $deadline)
    return $null
}
# Every top-level window of the application: the main window, dialogs and open menus.
function Windows-Of { @($automation::RootElement.FindAll($children,(Property ($automation::ProcessIdProperty) $process.Id))) }
# Dialogs and menus are windows of their own: look in the whole process.
function Everywhere($field,$value) {
    foreach ($window in (Windows-Of)) {
        if ($window.GetCurrentPropertyValue($field) -eq $value) { return $window }
        $found=$window.FindFirst($descendants,(Property $field $value)); if ($found) { return $found }
    }
    return $null
}
# The window of the application that shows an element with this name: a dialog, which UI
# Automation lists inside the window that owns it, or else the main window.
function Window-With([string]$name) {
    foreach ($top in (Windows-Of)) {
        $inner=@(All $top ([Windows.Automation.ControlType]::Window) | Where-Object { Named $_ $name })
        if ($inner.Count) { return $inner[$inner.Count-1] }
        if (Named $top $name) { return $top }
    }
    return $null
}
function Everywhere-Named([string]$name) { Everywhere ($automation::NameProperty) $name }
function Everywhere-Id([string]$id) { Everywhere ($automation::AutomationIdProperty) $id }

# Starts the application and returns its main window. Environment variables are set for it only.
function Start-App([string]$arguments='--ui-test',[hashtable]$environment=@{}) {
    foreach ($name in $environment.Keys) { Set-Item -Path "Env:$name" -Value $environment[$name] }
    try {
        if ($arguments) { $script:process=Start-Process -FilePath $exe -ArgumentList $arguments -PassThru } else { $script:process=Start-Process -FilePath $exe -PassThru }
    } finally { foreach ($name in $environment.Keys) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue } }
    $deadline=(Get-Date).AddSeconds(30)
    do { Start-Sleep -Milliseconds 100; $process.Refresh() } while ($process.MainWindowHandle -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline -and -not $process.HasExited)
    if ($process.MainWindowHandle -eq [IntPtr]::Zero) { throw 'The application showed no window.' }
    Start-Sleep -Milliseconds 1500
    $automation::FromHandle($process.MainWindowHandle)
}
function Stop-App([int]$milliseconds=5000) { if ($process -and -not $process.HasExited) { $process.CloseMainWindow() | Out-Null; if (-not $process.WaitForExit($milliseconds)) { $process.Kill() } } }
function Picture([string]$folder,[string]$name) {
    if (-not $folder) { return $null }
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $path=Join-Path $folder ($name+'.png'); [UiNative]::Save($process.MainWindowHandle,$path); $path
}

# System dialogs of the application (window class #32770): message boxes and file dialogs.
function System-Dialogs { @(Windows-Of | ForEach-Object { if ($_.Current.ClassName -eq '#32770') { $_ }; $_.FindAll($descendants,(Property ($automation::ClassNameProperty) '#32770')) }) }
# The box of a file dialog that takes the file name: a classic Edit control, numbered 1001 in
# the Save dialog and 1148 in the Open dialog.
function File-Name-Box($dialog) {
    foreach ($id in '1001','1148') {
        $box=@($dialog.FindAll($descendants,(Property ($automation::AutomationIdProperty) $id)) | Where-Object { $_.Current.ClassName -eq 'Edit' })
        if ($box.Count) { return $box[0] }
    }
    return $null
}
function File-Name($dialog) {
    $box=File-Name-Box $dialog; if (-not $box) { return '' }
    $handle=[IntPtr]$box.Current.NativeWindowHandle
    if ($handle -ne [IntPtr]::Zero) { return [UiNative]::GetText($handle) }
    $pattern=$null; if ($box.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$pattern)) { return $pattern.Current.Value }
    return $box.Current.Name
}
function Set-File-Name($dialog,[string]$path) {
    $box=File-Name-Box $dialog; Need $box 'Set-File-Name'
    $handle=[IntPtr]$box.Current.NativeWindowHandle
    if ($handle -ne [IntPtr]::Zero) { [UiNative]::TypeText($handle,$path) } else { $box.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue($path) }
    Start-Sleep -Milliseconds 400
}
# What a system dialog is made of, in one line, for the report of a failed test.
function Describe-Dialog($dialog) {
    if (-not $dialog) { return 'no dialog' }
    $parts=@($dialog.FindAll($descendants,[Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.ClassName -in 'Edit','Button','ComboBox','ComboBoxEx32','Static' } | Select-Object -First 14 | ForEach-Object { "$($_.Current.ClassName)#$($_.Current.AutomationId)[$($_.Current.NativeWindowHandle -ne 0)]='$($_.Current.Name)'" })
    "'$($dialog.Current.Name)' $($parts -join ' ')"
}
# The file dialog that is open, once it is ready to take a name.
function File-Dialog([int]$seconds=20) {
    $dialog=Wait-Until { System-Dialogs | Where-Object { File-Name-Box $_ } | Select-Object -First 1 } $seconds
    # A slow machine shows the dialog before it has filled it in. Wait for it to settle.
    if ($dialog) { Start-Sleep -Milliseconds 1500 }
    $dialog
}
# A message box: a system dialog with text and no file name.
function Message-Box([int]$seconds=10) { Wait-Until { System-Dialogs | Where-Object { -not (File-Name-Box $_) } | Select-Object -First 1 } $seconds }
function Message-Text($box) { (@($box.FindAll($descendants,(Property ($automation::ClassNameProperty) 'Static'))) | ForEach-Object { $_.Current.Name }) -join ' ' }
function Close-Dialog($dialog) { $dialog.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close(); Start-Sleep -Milliseconds 800 }
# Types the full path and presses the default button (Save or Open): command 1 of the dialog.
function Answer-FileDialog($dialog,[string]$path) {
    foreach ($attempt in 1..3) {
        Set-File-Name $dialog $path
        $script:lastFileName=File-Name $dialog
        if ($script:lastFileName -eq $path) { break }
        Start-Sleep -Milliseconds 700
    }
    $script:lastFileAnswer='the command'
    $handle=[IntPtr]$dialog.Current.NativeWindowHandle
    [UiNative]::PostMessage($handle,0x0111,[IntPtr]1,[IntPtr]::Zero) | Out-Null
    # The dialog closes once it has accepted the name.
    $closed=Wait-Until { -not (System-Dialogs | Where-Object { [IntPtr]$_.Current.NativeWindowHandle -eq $handle }) } 8 300
    if (-not $closed) {
        $button=@($dialog.FindAll($descendants,(Property ($automation::AutomationIdProperty) '1')) | Where-Object { $_.Current.ClassName -eq 'Button' })
        $pattern=$null
        if ($button.Count -and $button[0].TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern,[ref]$pattern)) { $pattern.Invoke(); $script:lastFileAnswer='its button' } else { $script:lastFileAnswer='nothing: it stayed open' }
        Wait-Until { -not (System-Dialogs | Where-Object { [IntPtr]$_.Current.NativeWindowHandle -eq $handle }) } 8 300 | Out-Null
    }
    Start-Sleep -Milliseconds 600
}
