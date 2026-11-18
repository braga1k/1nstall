# Starts a prototype normally, then looks at it from outside, the way an assistive tool would:
# through UI Automation. Optionally saves a picture of the window. Closes the prototype at the end.
param([Parameter(Mandatory)][string]$Exe, [string]$Arguments='', [string]$Picture='', [string]$Card='7-Zip', [int]$SettleMs=2500, [switch]$NoToggle)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class WindowPicture {
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32")] static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32")] static extern bool PrintWindow(IntPtr window, IntPtr target, uint flags);
    [DllImport("user32")] static extern bool SetProcessDPIAware();
    delegate bool EachWindow(IntPtr window, IntPtr state);
    [DllImport("user32")] static extern bool EnumWindows(EachWindow callback, IntPtr state);
    [DllImport("user32")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32")] static extern bool IsWindowVisible(IntPtr window);
    // The largest visible top-level window of a process: toolkits also create small helper windows.
    public static IntPtr Largest(int process) {
        IntPtr best=IntPtr.Zero; long area=0;
        EnumWindows(delegate(IntPtr window, IntPtr state) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if(owner==(uint)process && IsWindowVisible(window)) { Rect rect; GetWindowRect(window, out rect); long size=(long)(rect.Right-rect.Left)*(rect.Bottom-rect.Top); if(size>area) { area=size; best=window; } }
            return true;
        }, IntPtr.Zero);
        return area>=10000?best:IntPtr.Zero;
    }
    public static string Save(IntPtr window, string path) {
        SetProcessDPIAware();
        Rect rect; GetWindowRect(window, out rect);
        int width=rect.Right-rect.Left, height=rect.Bottom-rect.Top;
        using(var bitmap=new Bitmap(width,height)) {
            using(var graphics=Graphics.FromImage(bitmap)) { IntPtr target=graphics.GetHdc(); PrintWindow(window,target,2); graphics.ReleaseHdc(target); }
            bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        }
        return width+"x"+height;
    }
}
'@
$exe=(Resolve-Path -LiteralPath $Exe).Path
$startInfo=@{FilePath=$exe; PassThru=$true}; if ($Arguments) { $startInfo.ArgumentList=$Arguments }
$process=Start-Process @startInfo
try {
    $deadline=(Get-Date).AddSeconds(20)
    do { Start-Sleep -Milliseconds 100; $handle=[WindowPicture]::Largest($process.Id) } while ($handle -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline -and -not $process.HasExited)
    if ($handle -eq [IntPtr]::Zero) { throw 'The prototype showed no window.' }
    Start-Sleep -Milliseconds $SettleMs
    $automation=[Windows.Automation.AutomationElement]
    $root=$automation::FromHandle($handle)
    # A browser engine builds its accessibility tree only once a client asks; ask, then wait.
    $root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition) | Out-Null; Start-Sleep -Milliseconds 800
    $all=$root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
    $byType=@{}; $named=0
    foreach ($item in $all) { $type=$item.Current.ControlType.ProgrammaticName -replace '^ControlType\.',''; $byType[$type]=1+[int]$byType[$type]; if ($item.Current.Name) { $named++ } }
    $result=[ordered]@{Exe=Split-Path $exe -Leaf; Elements=$all.Count; Named=$named; CheckBoxes=[int]$byType['CheckBox']; Buttons=[int]$byType['Button']; Edits=[int]$byType['Edit']; Types=($byType.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Name+'='+$_.Value }) -join ' '}
    $condition=New-Object Windows.Automation.PropertyCondition ($automation::NameProperty), $Card
    $found=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,$condition)
    $result.CardFound=[bool]$found
    if ($found) {
        $result.CardType=$found.Current.ControlType.ProgrammaticName -replace '^ControlType\.',''
        $pattern=$null
        $result.CardHasToggle=$found.TryGetCurrentPattern([Windows.Automation.TogglePattern]::Pattern,[ref]$pattern)
        if ($result.CardHasToggle -and -not $NoToggle) {
            $before=$pattern.Current.ToggleState; $pattern.Toggle(); Start-Sleep -Milliseconds 600
            $result.ToggleWorked=($before -ne $pattern.Current.ToggleState)
            # The selection panel must now name the app a second time, as a queue row or its remove button.
            $again=$root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
            $result.QueueMentions=@($again | Where-Object { $_.Current.Name -like ('*'+$Card+'*') }).Count
        }
    }
    if ($Picture) { $result.Picture=[WindowPicture]::Save($handle,$Picture) }
    [pscustomobject]$result | ConvertTo-Json -Compress
} finally {
    if (-not $process.HasExited) { $process.CloseMainWindow() | Out-Null; if (-not $process.WaitForExit(3000)) { $process.Kill() } }
    # A WebView2 host leaves helper processes for a moment; they exit on their own.
}
