param([string]$PreviewDirectory='', [switch]$ItemScrolling)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
$probe={
    $window.Add_ContentRendered({
        function Pump([int]$Milliseconds=80) {
            $frame=New-Object Windows.Threading.DispatcherFrame; $timer=New-Object Windows.Threading.DispatcherTimer
            $timer.Interval=[TimeSpan]::FromMilliseconds($Milliseconds)
            $timer.Add_Tick({ $timer.Stop(); $frame.Continue=$false }); $timer.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
        }
        function Find-Visual($Element,[type]$Type) {
            if ($Element -is $Type) { return $Element }
            for ($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Element);$i++) {
                $found=Find-Visual ([Windows.Media.VisualTreeHelper]::GetChild($Element,$i)) $Type
                if ($found) { return $found }
            }
        }
        function Check-End($Scroll,$Last,[string]$Name,[double]$MaxGap=19) {
            $Scroll.ScrollToEnd(); Pump; $window.UpdateLayout(); Pump
            if ($Last -is [scriptblock]) { $Last=& $Last }
            $viewport=Find-Visual $Scroll ([Windows.Controls.ScrollContentPresenter])
            $bottom=$Last.TranslatePoint([Windows.Point]::new(0,$Last.ActualHeight),$viewport).Y
            $gap=$viewport.ActualHeight-$bottom
            if ($Scroll.ScrollableHeight -gt 0 -and ($gap -lt -1 -or $gap -gt $MaxGap -or [Math]::Abs($Scroll.VerticalOffset-$Scroll.ScrollableHeight) -gt 1)) { throw "$Name leaves a $gap DIP tail (offset $($Scroll.VerticalOffset), end $($Scroll.ScrollableHeight))." }
            if ($Scroll.ScrollableHeight -gt 0) { Write-Host "$Name bottom gap: $([Math]::Round($gap,2)) DIP" }
            else { Write-Host "$Name does not scroll (content fits)." }
        }
        function Capture([string]$Name) {
            if (-not $PreviewDirectory) { return }
            [IO.Directory]::CreateDirectory($PreviewDirectory) | Out-Null
            $image=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32); $image.Render($window)
            $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
            $stream=[IO.File]::Create((Join-Path $PreviewDirectory ($Name+'.png'))); try { $encoder.Save($stream) } finally { $stream.Dispose() }
        }
        try {
            [OneInstall.Motion]::TestOverride=$false; [OneInstall.Motion]::Stop()
            $script:settings.Language='en'; Apply-AppLanguage
            $script:settings.Theme='Dark'; $script:settings.WindowsAccent=$false; $script:lastAccent=''; Update-WindowsAccent
            $script:installedApps=@(1..73 | ForEach-Object { $app=New-Object InstalledApp; $app.Id='scroll-fixture-'+$_; $app.Name=('Example app {0:d2}' -f $_); if ($_ % 3 -eq 0) { $app.Name+=' with a longer name that wraps on a narrow viewport to cover rows of different heights' }; $app.Publisher='UI fixture'; $app.Version='1.0'; $app.Kind='Desktop'; $app.CanRemove=($_ % 7 -ne 0); $app })
            if ($ItemScrolling) { [Windows.Controls.VirtualizingPanel]::SetScrollUnit($ui.InstalledList,'Item') }
            foreach ($size in @(@(1040,540),@(1240,840),@(1440,900))) {
                $window.Width=$size[0]; $window.Height=$size[1]; Set-AppMode 'Uninstall'; Update-InstalledFilter; Pump
                $scroll=Find-Visual $ui.InstalledList ([Windows.Controls.ScrollViewer]); $scroll.ScrollToEnd(); Pump 200
                $last=$ui.InstalledList.ItemContainerGenerator.ContainerFromIndex($ui.InstalledList.Items.Count-1)
                if (-not $last) { throw 'Last installed app was not realized.' }
                $card=Find-Visual $last ([Windows.Controls.Border])
                Capture ('uninstall-end-'+$size[0])
                Check-End $scroll $card ('Uninstall '+$size[0]) 12
                $ui.InstalledSearch.Text='Example app 73'; Update-InstalledFilter; Pump
                if ($scroll.VerticalOffset -ne 0 -or $scroll.ScrollableHeight -ne 0) { throw 'Filtering to one app retained an empty scroll range.' }
                $ui.InstalledSearch.Clear(); Update-InstalledFilter; Pump
                Set-AppMode 'Install'; $script:libraryView='All apps'; Update-Filter; Update-CardLayout; Pump
                Check-End $ui.LibraryScroll $ui.Cards.Children[$ui.Cards.Children.Count-1] ('Install '+$size[0]) 14
                Capture ('install-end-'+$size[0])
                Set-Selection @($catalog | Select-Object -First 25 | ForEach-Object Key); Pump
                Check-End $ui.QueuePanel.Parent $ui.QueuePanel.Children[$ui.QueuePanel.Children.Count-1] 'Install selection' 12
                Set-Selection @(); Pump
                if ($ui.QueuePanel.Parent.ScrollableHeight -ne 0) { throw 'Clearing selection retained an empty scroll range.' }
                Set-AppMode 'Uninstall'; foreach ($app in $script:installedApps) { $app.Selected=$app.CanRemove }; Update-UninstallSelection; Pump
                Check-End $ui.UninstallQueuePanel.Parent { $ui.UninstallQueuePanel.Children[$ui.UninstallQueuePanel.Children.Count-1] } 'Removal selection' 12
                foreach ($app in $script:installedApps) { $app.Selected=$false }; Update-UninstallSelection
                Show-AppSettings; Pump
                Check-End $script:settingsPage $script:settingsContent.Children[$script:settingsContent.Children.Count-1] 'Settings' 14
                Capture ('settings-end-'+$size[0])
            }
            $window.Width=1040; $window.Height=540; Set-AppMode 'Install'
            foreach ($group in $categoryGroups.Values) { $group.IsExpanded=$true }; Pump
            Check-End $ui.CategoriesHost $ui.Categories.Children[$ui.Categories.Children.Count-1] 'Categories' 10
            foreach ($group in $categoryGroups.Values) { $group.IsExpanded=$false }; Pump
            if ($ui.CategoriesHost.VerticalOffset -gt $ui.CategoriesHost.ScrollableHeight) { throw 'Category collapse did not clamp the offset.' }
            Show-AppSettings; Pump; $ui.LanguageChoice.IsDropDownOpen=$true; Pump
            $popup=$ui.LanguageChoice.Template.FindName('PART_Popup',$ui.LanguageChoice); $scroll=Find-Visual $popup.Child ([Windows.Controls.ScrollViewer])
            $scroll.ScrollToEnd(); Pump
            $last=$ui.LanguageChoice.ItemContainerGenerator.ContainerFromIndex($ui.LanguageChoice.Items.Count-1)
            Check-End $scroll $last 'Language menu' 2
            $ui.LanguageChoice.IsDropDownOpen=$false
            Set-AppMode 'Install'; Pump; $profileMenu.MaxHeight=300; $profileMenu.IsOpen=$true; Pump
            $scroll=Find-Visual $profileMenu ([Windows.Controls.ScrollViewer]); $scroll.ScrollToEnd(); Pump
            Check-End $scroll $profileMenu.Items[$profileMenu.Items.Count-1] 'Profile menu' 2
            $profileMenu.IsOpen=$false
            Show-ManagerPage 'History'; $ui.ManagerList.Children.Clear()
            foreach ($i in 1..40) { $row=New-Label ('History fixture '+$i) '#C2CADE' 13; $row.Margin='0,0,0,18'; $ui.ManagerList.Children.Add($row) | Out-Null }; Pump
            Check-End $ui.ManagerList.Parent $ui.ManagerList.Children[39] 'History' 19
            $info=New-InfoDialog 'Scroll fixture' ((1..80 | ForEach-Object { 'Diagnostic line '+$_ }) -join "`r`n")
            $info.Window.Show(); Pump; $info.Text.ScrollToEnd(); Pump
            if ([Math]::Abs($info.Text.VerticalOffset+$info.Text.ViewportHeight-$info.Text.ExtentHeight) -gt 1) { throw 'Diagnostic text did not reach its end.' }
            $info.Window.Close()
            # The review/details dialogs use the same physical StackPanel/ScrollViewer layout.
            $info=New-InfoDialog 'Review scroll fixture' ''; $info.Dock.Children.Remove($info.Text)
            $list=New-Object Windows.Controls.StackPanel; $scroll=New-Object Windows.Controls.ScrollViewer
            $scroll.VerticalScrollBarVisibility='Auto'; $scroll.Content=$list; $info.Dock.Children.Add($scroll) | Out-Null
            foreach ($i in 1..40) { $row=New-Label ('Review item '+$i) '#C2CADE' 13; $row.Margin='0,12,0,0'; $list.Children.Add($row) | Out-Null }
            $info.Window.Show(); Pump; Check-End $scroll $list.Children[39] 'Review dialog' 2; $info.Window.Close()
            Write-Host 'PASS: scroll endpoints, mixed row heights, filtering, resizing, selections, categories, settings, language/profile menus, history and dialogs.'
        } finally { $window.Close() }
    })
}
$source=[IO.File]::ReadAllText((Join-Path $repo 'vexan_installers.ps1')).Replace('@@MANAGER_TEST@@',$probe.ToString())
. ([scriptblock]::Create($source)) -ResourceRoot $repo -ManagerTest
