# Run with Windows PowerShell -STA. Samples only these two disposable test windows.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Drawing
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot) 'src/window-helper.cs')))
function Pump {
    $frame=New-Object Windows.Threading.DispatcherFrame
    $timer=New-Object Windows.Threading.DispatcherTimer
    $timer.Interval=[TimeSpan]::FromMilliseconds(300)
    $timer.Add_Tick({ $timer.Stop(); $frame.Continue=$false })
    $timer.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
}
$behind=New-Object Windows.Window; $front=New-Object Windows.Window
$area=[Windows.SystemParameters]::WorkArea
foreach ($window in @($behind,$front)) {
    $window.Width=420; $window.Height=300; $window.Left=$area.Left+80; $window.Top=$area.Top+80
    $window.WindowStyle='None'; $window.ResizeMode='NoResize'; $window.ShowInTaskbar=$false
}
$behind.Background='White'
$behind.Topmost=$true; $front.Topmost=$true
$front.WindowStyle='None'; $front.ResizeMode='CanResize'
$front.Background='Transparent'
$chrome=New-Object Windows.Shell.WindowChrome; $chrome.GlassFrameThickness='-1'; $chrome.CaptionHeight=0
[Windows.Shell.WindowChrome]::SetWindowChrome($front,$chrome)
$surface=New-Object Windows.Controls.Grid; $surface.Background='#E0101220'; $front.Content=$surface
$front.Add_SourceInitialized({
    $handle=[Windows.Interop.WindowInteropHelper]::new($front).Handle
    [FirstInstallWindow]::Apply($handle) | Out-Null
    $script:result=[FirstInstallWindow]::SetBackdrop($handle,$true)
    [Windows.Interop.HwndSource]::FromHwnd($handle).CompositionTarget.BackgroundColor=[Windows.Media.Colors]::Transparent
})
$bitmap=New-Object Drawing.Bitmap 1,1
$graphics=[Drawing.Graphics]::FromImage($bitmap)
try {
    $behind.Show(); $front.Show(); $front.Activate() | Out-Null
    if ($script:result -ne 0) { Write-Output 'SKIP: this Windows version does not support Desktop Acrylic.'; return }
    Pump; Pump
    if ([FirstInstallWindow]::ReadNativeFrameEnabled([Windows.Interop.WindowInteropHelper]::new($front).Handle) -ne 0) { throw 'Native accent frame remains enabled.' }
    $point=$surface.PointToScreen([Windows.Point]::new(200,150))
    $front.Hide(); Pump
    $graphics.CopyFromScreen([int]$point.X,[int]$point.Y,0,0,[Drawing.Size]::new(1,1))
    Write-Output ('Test backing window: '+$bitmap.GetPixel(0,0).ToString())
    $front.Show(); $front.Activate() | Out-Null; Pump; Pump
    $graphics.CopyFromScreen([int]$point.X,[int]$point.Y,0,0,[Drawing.Size]::new(1,1))
    $light=$bitmap.GetPixel(0,0)
    $behind.Background='Black'; Pump; Pump
    $graphics.CopyFromScreen([int]$point.X,[int]$point.Y,0,0,[Drawing.Size]::new(1,1))
    $dark=$bitmap.GetPixel(0,0)
    if ($light.ToArgb() -eq $dark.ToArgb()) { throw ('Desktop backdrop did not respond to the test window behind it: '+$light.ToString()) }
    $front.Width=440; Pump
    $handle=[Windows.Interop.WindowInteropHelper]::new($front).Handle
    if ([FirstInstallWindow]::ReadNativeFrameEnabled($handle) -ne 0) { throw 'Native frame reappeared after resizing and focus change.' }
    if ([FirstInstallWindow]::ReadBackdrop($handle) -ne 3) { throw 'Desktop Acrylic attribute was not retained.' }
    [FirstInstallWindow]::SetBackdrop($handle,$false) | Out-Null
    if ([FirstInstallWindow]::ReadBackdrop($handle) -ne 1) { throw 'Desktop Acrylic could not be disabled.' }
    Write-Output ('PASS: live desktop composition responds to white/black test windows: '+$light.ToString()+' -> '+$dark.ToString()+'. Native effect can be disabled.')
} finally { $graphics.Dispose(); $bitmap.Dispose(); $front.Close(); $behind.Close() }
