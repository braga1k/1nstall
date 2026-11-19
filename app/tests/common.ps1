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
    [DllImport("user32")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32")] public static extern IntPtr GetForegroundWindow();
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
function Invoke($element,[int]$wait=800) { $element.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds $wait }
function Toggle($element,[int]$wait=600) { $element.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle(); Start-Sleep -Milliseconds $wait }
function Value($element) { $element.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value }
function Set-Value($element,[string]$text,[int]$wait=700) { $element.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue($text); Start-Sleep -Milliseconds $wait }
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
function File-Name($dialog) { [UiNative]::GetText([IntPtr](File-Name-Box $dialog).Current.NativeWindowHandle) }
# The file dialog that is open, once it is ready to take a name.
function File-Dialog([int]$seconds=20) { Wait-Until { System-Dialogs | Where-Object { File-Name-Box $_ } | Select-Object -First 1 } $seconds }
# A message box: a system dialog with text and no file name.
function Message-Box([int]$seconds=10) { Wait-Until { System-Dialogs | Where-Object { -not (File-Name-Box $_) } | Select-Object -First 1 } $seconds }
function Message-Text($box) { (@($box.FindAll($descendants,(Property ($automation::ClassNameProperty) 'Static'))) | ForEach-Object { $_.Current.Name }) -join ' ' }
function Close-Dialog($dialog) { $dialog.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close(); Start-Sleep -Milliseconds 800 }
# Types the full path and presses the default button (Save or Open): command 1 of the dialog.
function Answer-FileDialog($dialog,[string]$path) {
    [UiNative]::SetText([IntPtr](File-Name-Box $dialog).Current.NativeWindowHandle,$path); Start-Sleep -Milliseconds 400
    [UiNative]::PostMessage([IntPtr]$dialog.Current.NativeWindowHandle,0x0111,[IntPtr]1,[IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 1200
}
