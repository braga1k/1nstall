# Loaded in the app scope only with -ManagerTest. All inventory/history data is fictional.
$testData=Join-Path ([IO.Path]::GetTempPath()) ('1nstall-ui-'+[guid]::NewGuid().ToString('N'))
[OneInstallPackages]::DataRoot=$testData
$window.Add_ContentRendered({
    function Assert-UI($Value,[string]$Message) { if (-not $Value) { throw $Message } }
    function Pump-UI {
        $frame=New-Object Windows.Threading.DispatcherFrame; $pulse=New-Object Windows.Threading.DispatcherTimer
        $pulse.Interval=[TimeSpan]::FromMilliseconds(100)
        $pulse.Add_Tick({ $pulse.Stop(); $frame.Continue=$false }); $pulse.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
    }
    function Capture-UI([string]$Suffix,[double]$Scale=1) {
        if (-not $PreviewPath) { return }
        $window.UpdateLayout(); Update-CardLayout; Pump-UI
        $image=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]($window.ActualWidth*$Scale),[int]($window.ActualHeight*$Scale),96*$Scale,96*$Scale,[Windows.Media.PixelFormats]::Pbgra32)
        $image.Render($window); $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
        $path=[IO.Path]::ChangeExtension($PreviewPath,$Suffix+'.png'); $stream=[IO.File]::Create($path)
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
    }
    function Capture-TestDialog($Dialog,[string]$Suffix) {
        if (-not $PreviewPath) { return }
        $Dialog.UpdateLayout()
        $image=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$Dialog.ActualWidth,[int]$Dialog.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $image.Render($Dialog); $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
        $stream=[IO.File]::Create([IO.Path]::ChangeExtension($PreviewPath,$Suffix+'.png'))
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
    }
    try {
        $script:libraryView='Essentials'; Update-Filter; Pump-UI
        Assert-UI ($ui.Cards.Children.Count -eq $script:essentials.Count -and $window.FindName('Welcome').Visibility -eq 'Visible') 'Essentials starting view failed.'
        Set-GlassAppearance $false
        Capture-UI 'welcome'
        Set-GlassAppearance $true; Capture-UI 'glass'
        foreach ($scale in @(1,1.5,2)) { Capture-UI ('render-'+[int]($scale*100)) $scale }
        $ui.Search.Text='Equalizer'
        Assert-UI ($checks['apo'].Visibility -eq 'Visible') 'Essentials search failed to reach full catalog.'
        $ui.Search.Clear()
        $inv=New-Object PackageInventory; $inv.Complete=$true
        $p=New-Object PackageRecord; $p.Id='VideoLAN.VLC'; $p.Name='Publisher identity fixture'; $p.Source='winget'; $p.InstalledVersion='3.0.20'; $p.AvailableVersion='3.0.21'; $p.UpdateAvailable=$true
        $inv.Packages.Add($p); $script:libraryInventory=$inv; Update-LibraryStates
        Assert-UI ($script:installedLabels['extra_vlc'].Text -eq 'Installed · 3.0.20') 'Library exact installed state failed.'
        Assert-UI ($script:installedLabels['affinity'].Text -eq 'Unknown') 'Guided app falsely identified.'
        $inv.Packages.Add($p); Update-LibraryStates
        Assert-UI ($script:installedLabels['extra_vlc'].Text.StartsWith('Unknown')) 'Multiple registrations were hidden.'
        $inv.Packages.RemoveAt(1); Update-LibraryStates
        $script:libraryView='Installed'; Update-Filter
        Assert-UI ($ui.Cards.Children.Count -eq 1 -and $ui.Cards.Children[0].Tag -eq 'extra_vlc') 'Installed filter failed.'
        Capture-UI 'installed'
        $script:libraryView='All apps'; Update-Filter
        $ui.Search.Focus() | Out-Null; $window.UpdateLayout(); Pump-UI
        Assert-UI $ui.Search.IsKeyboardFocused 'Search could not receive keyboard focus.'
        $ui.Search.MoveFocus([Windows.Input.TraversalRequest]::new([Windows.Input.FocusNavigationDirection]::Next)) | Out-Null
        Assert-UI ($null -ne [Windows.Input.Keyboard]::FocusedElement) 'Tab traversal lost focus.'
        $checks['extra_vlc'].Focus() | Out-Null
        Show-AppDetails 'extra_vlc' # automatic close in test mode; does not launch website
        $script:updateRows=@($p)
        Show-ManagerPage 'Updates'; Pump-UI
        Assert-UI (-not $p.Selected -and -not $ui.ReviewUpdates.IsEnabled) 'Updates were preselected or could execute without review.'
        Capture-UI 'updates'
        [OneInstallPackages]::SetHold($p.Id,$true)
        $p.Held=$true; $p.HoldReason='Held in 1nstall only'; Render-Updates
        Assert-UI ([OneInstallPackages]::Exclusions() -contains $p.Id) 'UI hold not persisted.'
        Capture-UI 'held'
        [OneInstallPackages]::Record('Update',$p.Id,'winget','Example VLC','Failed','Simulated offline download failure. Check connectivity and retry after refresh.',-1,$null) | Out-Null
        [OneInstallPackages]::Record('Install','Fixture.Restart','winget','Example Editor','Restart required','Simulated restart-required fixture; no real app installed.',3010,$null) | Out-Null
        Show-ManagerPage 'History'; Pump-UI; Capture-UI 'history'
        Assert-UI ($ui.ManagerList.Children.Count -eq 2) 'History did not render per-app outcomes.'
        Show-Diagnostics
        $rows=@(@{Key='extra_vlc';Name='VLC';State='Already installed · 3.0.20'},@{Key='app1';Name='Firefox';State='Missing · catalog package'},@{Key='';Name='Unknown publisher app';State='Unavailable in this catalog'},@{Key='affinity';Name='Affinity';State='Manual installation required'})
        Show-SetupPreview $rows 'Snapshot import preview' | Out-Null
        Set-AppMode 'Install'; $script:managerPage.Visibility='Collapsed'
        $script:libraryView='Essentials'; Update-Filter; Pump-UI
        $window.Width=760; $window.Height=600; Pump-UI; Capture-UI 'narrow'
        Assert-UI ($ui.LibraryScroll.ViewportWidth -gt 240 -and $ui.Cards.ItemWidth -gt 100) 'Narrow library unusable.'
        $window.Width=1240; Pump-UI
        $window.Close()
    } finally {
        $resolved=[IO.Path]::GetFullPath($testData); $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if (-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^1nstall-ui-[a-f0-9]{32}$') { throw 'UI fixture escaped temporary root.' }
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
})
