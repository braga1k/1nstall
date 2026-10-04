# Public GitHub screenshots always use English, regardless of the host's language.
# SourceDirectory can point to an extracted release so documentation matches that release.
param([string]$SourceDirectory='', [Parameter(Mandatory=$true)][string]$PreviewDirectory)
$ErrorActionPreference='Stop'
if (-not $SourceDirectory) { $SourceDirectory=Split-Path $PSScriptRoot }
[IO.Directory]::CreateDirectory($PreviewDirectory) | Out-Null
$probe={
    $window.Add_ContentRendered({
        function Paint {
            $frame=New-Object Windows.Threading.DispatcherFrame; $timer=New-Object Windows.Threading.DispatcherTimer
            $timer.Interval=[TimeSpan]::FromMilliseconds(650)
            $timer.Add_Tick({ $timer.Stop(); $frame.Continue=$false }); $timer.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
        }
        function Capture([string]$Name) {
            $window.UpdateLayout(); Update-CardLayout; Paint
            if ($script:settings.Language -ne 'en' -or $ui.SettingsMode.Content -ne 'Settings') { throw 'Public screenshots must show the English interface.' }
            $image=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32); $image.Render($window)
            $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
            $stream=[IO.File]::Create((Join-Path $PreviewDirectory ($Name+'.png'))); try { $encoder.Save($stream) } finally { $stream.Dispose() }
        }
        try {
            $window.Width=1240; $window.Height=[Math]::Min(840,[Windows.SystemParameters]::WorkArea.Height-24)
            $script:settings.Language='en'; Apply-AppLanguage; Set-Selection @('extra_vlc')
            foreach ($appearance in @('Light','Dark')) {
                foreach ($accent in @($true,$false)) {
                    $script:settings.Theme=$appearance; $script:settings.WindowsAccent=$accent; $script:lastAccent=''; Update-WindowsAccent
                    $suffix=$appearance.ToLowerInvariant()+$(if ($accent) {''} else {'-monochrome'})
                    Set-AppMode 'Install'; Capture ('install-'+$suffix)
                    Show-AppSettings; Paint
                    $ui.AutoUpdateChoice.IsChecked=$true
                    $light=$script:settingsContent.Children[1].Child.Children[0]; $light.Opacity=1; $light.Tag=0
                    Move-GlassLight $light ([Windows.Point]::new($light.ActualWidth*.72,$light.ActualHeight*.62))
                    Capture ('settings-'+$suffix)
                }
            }
            # Fictional inventory: never expose personal software in public screenshots.
            $script:installedApps=@('Audio Tools','Code Editor','Design Studio','Document Reader','Media Player','Notes','Photo Editor','Video Editor' | ForEach-Object {
                $app=New-Object InstalledApp; $app.Id='screenshot-'+$_; $app.Name='Example '+$_; $app.Publisher='Example Studio'; $app.Version='2.0'; $app.Kind='Desktop'; $app.CanRemove=$true
                $app.Selected=($_ -eq 'Code Editor' -or $_ -eq 'Notes'); $app
            })
            $script:settings.Theme='Dark'; $script:settings.WindowsAccent=$true; $script:lastAccent=''; Update-WindowsAccent
            Set-AppMode 'Uninstall'; Update-InstalledFilter; Update-UninstallSelection
            Set-UiValue $ui.UninstallStatus 'Text' 'Preview with fictional apps - no installed application has been removed.'
            Capture 'uninstall-dark'
        } finally { $window.Close() }
    })
}
$source=[IO.File]::ReadAllText((Join-Path $SourceDirectory 'vexan_installers.ps1')).Replace('@@MANAGER_TEST@@',$probe.ToString())
. ([scriptblock]::Create($source)) -ResourceRoot $SourceDirectory -ManagerTest
