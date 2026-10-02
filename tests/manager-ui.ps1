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
    function Find-InstalledCheck($Element) {
        if ($Element -is [Windows.Controls.CheckBox]) { return $Element }
        if (-not $Element) { return }
        for ($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Element);$i++) {
            $found=Find-InstalledCheck ([Windows.Media.VisualTreeHelper]::GetChild($Element,$i))
            if ($found) { return $found }
        }
    }
    function Assert-InstalledChecks {
        for ($i=0;$i -lt $ui.InstalledList.Items.Count;$i++) {
            $box=Find-InstalledCheck ($ui.InstalledList.ItemContainerGenerator.ContainerFromIndex($i))
            if ($box) { Assert-UI ($box.IsChecked -eq $ui.InstalledList.Items[$i].Selected) 'Installed checkbox and selection model are out of sync.' }
        }
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
        $script:libraryView='All apps'; Update-Filter; Pump-UI
        Assert-UI ($catalog[0].Name -eq '1Password' -and $catalog[1].Name -eq '7-Zip' -and $catalog[-1].Name.StartsWith('.NET')) 'Library must place numbers first and symbol-prefixed names last.'
        Set-Selection @('extra_vlc'); Pump-UI
        $queueScroll=$ui.QueuePanel.Parent
        $removeX=$script:removeButtons['extra_vlc'].TranslatePoint([Windows.Point]::new(0,0),$window).X
        Assert-UI ($queueScroll.ExtentHeight -le $queueScroll.ViewportHeight) 'Short setup fixture must not scroll.'
        Set-Selection @($catalog | Select-Object -First 20 | ForEach-Object { $_.Key }); Pump-UI
        $firstKey=[string]$ui.QueuePanel.Children[0].Tag
        $scrollX=$script:removeButtons[$firstKey].TranslatePoint([Windows.Point]::new(0,0),$window).X
        Assert-UI ($queueScroll.ExtentHeight -gt $queueScroll.ViewportHeight -and [Math]::Abs($scrollX-$removeX) -lt 1) 'Setup remove buttons shifted when scrollbar became necessary.'
        Capture-UI 'setup-scroll'
        Set-Selection @('extra_vlc'); Pump-UI; Capture-UI 'setup-short'
        Set-Selection @(); Pump-UI
        Assert-UI ($ui.Cards.Children.Count -eq $catalog.Count -and $null -eq $window.FindName('Welcome') -and -not $script:viewButtons.ContainsKey('Essentials')) 'Library must open with all apps and no Essentials view.'
        if ($nativeCards) {
            $realized=@($checks.Values | Where-Object { $_.ReadLocalValue([Windows.Controls.Control]::TemplateProperty) -eq [Windows.DependencyProperty]::UnsetValue })
            Assert-UI ($realized.Count -gt 0 -and $realized.Count -lt 60) 'Native startup must render the viewport without constructing every card template.'
        }
        # Guided-method copy used to wrap at narrow column widths and clip Details.
        $ui.Search.Text='FileZilla'; Pump-UI; Pump-UI
        $filezilla=$checks['daily_filezilla']
        foreach ($width in @(830,948,1050,1140,1240,1320,1500,1920,948)) {
            $window.Width=$width; Pump-UI; Update-CardLayout; Pump-UI; Pump-UI
            $details=$filezilla.Content.Children[3]
            $buttonBottom=$details.TranslatePoint([Windows.Point]::new(0,$details.ActualHeight),$filezilla).Y
            Assert-UI ($details.ActualHeight -ge 28 -and $buttonBottom -le $filezilla.ActualHeight-12) "Guided card clipped Details at width $width (bottom $buttonBottom / height $($filezilla.ActualHeight))."
            Assert-UI ($filezilla.Content.Children[2].ActualHeight -le 18) 'Installation method must stay on one line.'
            if ($width -eq 948) { Capture-UI 'filezilla-narrow' }
        }
        $ui.Search.Clear(); Pump-UI; Pump-UI
        $script:installedApps=@(1..20 | ForEach-Object {
            $app=New-Object InstalledApp; $app.Id='alignment-'+$_; $app.Name='Example app '+$_; $app.Publisher='UI fixture'; $app.Version='1.0'; $app.Kind='Desktop'; $app.CanRemove=$true; $app
        })
        foreach ($width in @(830,1050,1240,1500)) {
            $window.Width=$width; Pump-UI; Update-CardLayout; Pump-UI
            $frame=$window.FindName('LibrarySearchFrame'); $installPoint=$frame.TranslatePoint([Windows.Point]::new(0,0),$window)
            $installWidth=$frame.ActualWidth; $installHeight=$frame.ActualHeight
            $installGap=$ui.Profiles.TranslatePoint([Windows.Point]::new(0,0),$window).X-$installPoint.X-$installWidth
            $group=$window.FindName('ProfilesTools'); $point=$group.TranslatePoint([Windows.Point]::new(0,0),$window)
            Assert-UI ($point.X+$group.ActualWidth -le $ui.InstallLibrary.TranslatePoint([Windows.Point]::new(0,0),$window).X+$ui.InstallLibrary.ActualWidth+1) 'Profiles must fit beside search or below it at narrow widths.'
            $columns=[int][Math]::Floor($ui.LibraryScroll.ViewportWidth/$ui.Cards.ItemWidth)
            $lastCard=$ui.Cards.Children[$columns-1]
            $cardRight=$lastCard.TranslatePoint([Windows.Point]::new($lastCard.ActualWidth,0),$window).X
            if ([Windows.Controls.Grid]::GetRow($group) -eq 1) { $edge=$frame } else { $edge=$ui.ClearSelection }
            $toolsRight=$edge.TranslatePoint([Windows.Point]::new($edge.ActualWidth,0),$window).X
            Assert-UI ([Math]::Abs($cardRight-$toolsRight) -lt 1) "Install toolbar alignment: width=$width card=$cardRight tools=$toolsRight slot=$($ui.Cards.ItemWidth) viewport=$($ui.LibraryScroll.ViewportWidth) header=$($window.FindName('InstallSearchRow').ActualWidth)"
            Assert-UI ($window.FindName('NavigationGlass').ActualWidth -eq $window.FindName('SetupGlass').ActualWidth) 'Side panels must have equal widths.'
            $brand=$window.FindName('BrandHeader')
            $logo=$window.FindName('BrandLogo')
            $logoCenter=$logo.TranslatePoint([Windows.Point]::new($logo.ActualWidth/2,0),$window).X
            $navCenter=$ui.InstallMode.TranslatePoint([Windows.Point]::new($ui.InstallMode.ActualWidth/2,0),$window).X
            Assert-UI ([Math]::Abs($logoCenter-$navCenter) -lt 1) 'Logo must be centered above the navigation buttons.'
            Assert-UI ($window.FindName('SetupHeading').Text -eq 'Selection' -and $window.FindName('RemovalHeading').Text -eq 'Selection') 'Both selection panels must use the same heading.'
            $brandCenter=$brand.TranslatePoint([Windows.Point]::new(0,$brand.ActualHeight/2),$window).Y
            $installCenter=$ui.InstallMode.TranslatePoint([Windows.Point]::new(0,$ui.InstallMode.ActualHeight/2),$window).Y
            $all=$script:viewButtons['All apps']
            $viewsCenter=$all.TranslatePoint([Windows.Point]::new(0,$all.ActualHeight/2),$window).Y
            Assert-UI ([Math]::Abs($brandCenter-$viewsCenter) -lt 1 -and [Math]::Abs($installCenter-$installPoint.Y-$installHeight/2) -lt 1) "Install header alignment failed: title=$brandCenter filters=$viewsCenter sidebar=$installCenter search=$($installPoint.Y+$installHeight/2)"
            Set-AppMode 'Uninstall'; Pump-UI; Update-CardLayout; Pump-UI
            $frame=$window.FindName('InstalledSearchFrame'); $removalPoint=$frame.TranslatePoint([Windows.Point]::new(0,0),$window)
            Assert-UI ([Math]::Abs($installPoint.X-$removalPoint.X) -lt 1 -and [Math]::Abs($installPoint.Y-$removalPoint.Y) -lt 1 -and $frame.ActualWidth -ge $installWidth-1 -and $installHeight -eq $frame.ActualHeight) 'Search position/height changed, or Uninstall failed to use available width.'
            if ([Windows.Controls.Grid]::GetRow($group) -eq 0) {
                $removalGap=$ui.RefreshInstalled.TranslatePoint([Windows.Point]::new(0,0),$window).X-$removalPoint.X-$frame.ActualWidth
                Assert-UI ([Math]::Abs($installGap-$removalGap) -lt 1 -and [Math]::Abs($removalGap-12) -lt 1) 'Search-to-action spacing must be 12 DIP in both sections.'
            }
            $ui.InstalledSearch.Text='fixture'; $window.FindName('ClearInstalledSearch').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Assert-UI ($ui.InstalledSearch.Text -eq '') 'Installed clear-search button failed.'
            foreach ($count in @(20,1)) {
                $ui.InstalledList.ItemsSource=@($script:installedApps | Select-Object -First $count); Pump-UI
                $container=$ui.InstalledList.ItemContainerGenerator.ContainerFromIndex(0)
                $presenter=[Windows.Media.VisualTreeHelper]::GetChild($container,0)
                $surface=[Windows.Media.VisualTreeHelper]::GetChild($presenter,0)
                $cardRight=$surface.TranslatePoint([Windows.Point]::new($surface.ActualWidth,0),$window).X
                $toolsRight=$ui.WindowsAppsSettings.TranslatePoint([Windows.Point]::new($ui.WindowsAppsSettings.ActualWidth,0),$window).X
                Assert-UI ([Math]::Abs($cardRight-$toolsRight) -lt 1) "Uninstall toolbar must align with its cards: card=$cardRight tools=$toolsRight"
            }
            $viewsCenter=$ui.InstalledAll.TranslatePoint([Windows.Point]::new(0,$ui.InstalledAll.ActualHeight/2),$window).Y
            Assert-UI ([Math]::Abs($brandCenter-$viewsCenter) -lt 1 -and [Math]::Abs($installCenter-$removalPoint.Y-$frame.ActualHeight/2) -lt 1) 'Uninstall header must align with the sidebar title and Install button.'
            Update-InstalledFilter; Pump-UI
            Capture-UI ('uninstall-toolbar-'+$width)
            Set-AppMode 'Install'; Pump-UI; Pump-UI; Pump-UI; Pump-UI; Pump-UI
            Capture-UI ('toolbar-'+$width)
        }
        $window.Width=1240; Set-AppMode 'Uninstall'; Pump-UI
        $first=$script:installedApps[0]; $second=$script:installedApps[1]
        $second.Name=$first.Name # Same display name must not conflate registrations.
        foreach ($i in @(0,1)) {
            $box=Find-InstalledCheck ($ui.InstalledList.ItemContainerGenerator.ContainerFromIndex($i))
            $peer=[Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($box)
            $peer.GetPattern([Windows.Automation.Peers.PatternInterface]::Toggle).Toggle()
        }
        Pump-UI; Assert-InstalledChecks
        Assert-UI ($first.Selected -and $second.Selected) 'Checkbox interaction did not select the underlying apps.'
        Assert-UI ($ui.UninstallQueuePanel.Children.Count -eq 2) 'Selected installed apps must appear in the removal panel.'
        $ui.InstalledSearch.Text='no matching fixture'; Pump-UI
        Assert-UI ($ui.UninstallQueuePanel.Children.Count -eq 2) 'Search hid apps from the removal selection.'
        $remove=$ui.UninstallQueuePanel.Children[0].Children[0].Children[1]
        $remove.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)); Pump-UI
        Assert-UI (-not $first.Selected -and $second.Selected -and $ui.UninstallSelectedCount.Text -eq '1 app selected') 'Removal selection x changed the wrong registration.'
        $ui.InstalledSearch.Clear(); Pump-UI; Assert-InstalledChecks
        $remove=$ui.UninstallQueuePanel.Children[0].Children[0].Children[1]
        $shortX=$remove.TranslatePoint([Windows.Point]::new(0,0),$window).X
        foreach ($app in $script:installedApps) { $app.Selected=$true }
        Update-UninstallSelection; Pump-UI; Pump-UI
        $scroll=$window.FindName('UninstallQueueScroll')
        $remove=$ui.UninstallQueuePanel.Children[0].Children[0].Children[1]
        Assert-UI ($ui.UninstallQueuePanel.Children.Count -eq 20 -and $scroll.ExtentHeight -gt $scroll.ViewportHeight -and [Math]::Abs($remove.TranslatePoint([Windows.Point]::new(0,0),$window).X-$shortX) -lt 1) 'Removal selection must scroll without shifting its x buttons.'
        Capture-UI 'uninstall-selection-scroll'
        $ui.ClearUninstallSelection.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)); Pump-UI
        Assert-InstalledChecks
        Assert-UI (@($script:installedApps | Where-Object Selected).Count -eq 0 -and -not $ui.ReviewUninstall.IsEnabled) 'Clear did not reset removal selection.'
        foreach ($app in @($script:installedApps | Select-Object -First 4)) { $app.Selected=$true }
        Update-UninstallSelection; Pump-UI; Assert-InstalledChecks
        $light=$window.FindName('RemovalReflection'); $light.Tag=0
        $before=$light.Background.Center
        Move-GlassLight $light ([Windows.Point]::new($light.ActualWidth*0.75,$light.ActualHeight*0.4))
        Assert-UI ($light.Background.Center -ne $before -and $window.FindName('RemovalBackdrop').Background -is [Windows.Media.VisualBrush]) 'Removal panel lost its interactive glass layer.'
        Set-GlassAppearance $false
        Assert-UI ($window.FindName('RemovalBackdrop').Visibility -eq 'Collapsed' -and $light.Opacity -eq 0) 'Removal glass ignored disabled visual effects.'
        Set-GlassAppearance $true; Pump-UI
        Capture-UI 'uninstall-selection'
        $window.Width=830; $window.Height=540; Pump-UI; Pump-UI
        Assert-UI ($scroll.ViewportHeight -ge 100 -and $ui.ReviewUninstall.TranslatePoint([Windows.Point]::new(0,$ui.ReviewUninstall.ActualHeight),$window).Y -lt $window.ActualHeight) 'Compact removal panel clipped its list or review action.'
        Capture-UI 'uninstall-selection-compact'
        $window.Width=1240; $window.Height=840
        $ui.ClearUninstallSelection.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)); Set-AppMode 'Install'; Pump-UI
        $window.Width=1240; Pump-UI; Update-CardLayout; Pump-UI
        # Swap equally sized category grids: returning cards must not keep widths
        # inherited from All apps while the scrollbar was present.
        $categorySlot=$ui.Cards.ItemWidth
        foreach ($target in @('All apps','Browsers','AI Tools','Audio Production','Design & Photography','Audio Production','All apps')) {
            $button=@($categoryButtons | Where-Object Tag -eq $target)[0]
            if ($target -ne 'All apps') {
                $app=@($catalog | Where-Object Category -eq $target)[0]
                $categoryGroups[$app.CategoryGroup].IsExpanded=$true
            }
            $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Pump-UI; Pump-UI; Pump-UI; Pump-UI; Pump-UI
            Assert-UI ($ui.Cards.ItemWidth -eq $categorySlot) 'Card size changed when a category did not need scrolling.'
            foreach ($card in $ui.Cards.Children) {
                Assert-UI ([Math]::Abs($card.Width-($ui.Cards.ItemWidth-8)) -lt 1) 'Category transition left a card wider than its grid slot.'
                $surface=$card.Template.FindName('Card',$card)
                if ($surface) {
                    Assert-UI ($surface.ActualWidth -le $ui.Cards.ItemWidth-8+1 -and $surface.CornerRadius.TopRight -eq 18 -and $surface.CornerRadius.BottomRight -eq 18) 'Card right edge was clipped or lost its rounded shape.'
                }
            }
            foreach ($categoryButton in $categoryButtons) {
                Assert-UI ($categoryButton.Content.Text -eq [string]$categoryButton.Tag) 'Category name contains a selection glyph.'
                Assert-UI ($categoryButton.IsChecked -eq ($categoryButton.Tag -eq $target)) 'Category selection differs from the filter.'
                $categoryButton.ApplyTemplate()
                Assert-UI ($null -eq $categoryButton.Template.FindName('ButtonBevel',$categoryButton)) 'Category row inherited a glass button bevel.'
                Assert-UI ($null -eq $categoryButton.Template.FindName('SelectedMarker',$categoryButton)) 'Category row still contains a vertical selection marker.'
            }
            if ($target -eq 'Browsers') {
                $label=$button.Content
                Assert-UI ($label.FontFamily.Source -eq 'Segoe UI' -and $label.FontSize -eq 14 -and [Windows.Media.TextOptions]::GetTextRenderingMode($label) -eq 'Grayscale') 'Category text lost its static font or smoothing.'
                Assert-UI ($label.ActualWidth -ge $label.DesiredSize.Width -and $label.ActualHeight -ge $label.DesiredSize.Height) 'Browsers text is clipped.'
                Assert-UI ($label.Effect -is [Windows.Media.Effects.DropShadowEffect] -and $label.Effect.BlurRadius -le 2 -and $label.Effect.ShadowDepth -eq 1) 'Primary text must retain a short, smooth shadow.'
                $ancestor=[Windows.Media.VisualTreeHelper]::GetParent($label)
                while ($ancestor -is [Windows.Media.Visual]) {
                    if ($ancestor -is [Windows.UIElement]) { Assert-UI (-not $ancestor.Effect) 'Category text is rasterized through an ancestor effect.' }
                    $ancestor=[Windows.Media.VisualTreeHelper]::GetParent($ancestor)
                }
                $peer=[Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($button)
                $selection=$peer.GetPattern([Windows.Automation.Peers.PatternInterface]::SelectionItem)
                Assert-UI ($selection -and $selection.IsSelected -and $peer.GetName() -eq 'Browsers' -and $ui.Cards.Children.Count -eq 16) 'Browsers must expose its selected state and 16 catalog apps.'
                $categoryGroups['Create'].IsExpanded=$true
                Assert-UI ($button.IsChecked -and $script:category -eq 'Browsers') 'Expanding a group changed the selected category.'
                $categoryGroups['Everyday'].IsExpanded=$true
            }
            if ($target -in @('Browsers','Audio Production')) { Capture-UI ('category-'+$target.Replace(' ','-')) }
        }
        $browser=@($categoryButtons | Where-Object Tag -eq 'Browsers')[0]
        $peer=[Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($browser)
        $peer.GetPattern([Windows.Automation.Peers.PatternInterface]::SelectionItem).Select()
        Assert-UI ($script:category -eq 'Browsers' -and $ui.Cards.Children.Count -eq 16) 'Screen-reader selection failed to filter Browsers.'
        $categoryGroups['Everyday'].IsExpanded=$true; $browser.Focus() | Out-Null; Pump-UI
        foreach ($scale in @(1,1.25,1.5,2)) { Capture-UI ('text-'+[int]($scale*100)) $scale }
        $categoryButtons[0].IsChecked=$true; Pump-UI
        foreach ($group in $categoryGroups.Values) { $group.IsExpanded=$false }
        Set-GlassAppearance $false
        Assert-UI ($window.Resources['TextShadowOpacity'] -eq 0) 'Text depth must respect disabled visual effects.'
        Capture-UI 'welcome'
        Set-GlassAppearance $true; Assert-UI ($window.Resources['TextShadowOpacity'] -eq 0.32) 'Text depth did not restore.'; Capture-UI 'glass'
        foreach ($scale in @(1,1.5,2)) { Capture-UI ('render-'+[int]($scale*100)) $scale }
        $primaryBrush=$window.Resources['TextPrimaryBrush']; Update-WindowsAccent
        Assert-UI ([object]::ReferenceEquals($primaryBrush,$window.Resources['TextPrimaryBrush'])) 'Unchanged Windows theme must not replace brushes every tick.'
        Assert-UI ([Math]::Abs([FirstInstallWindow]::Luminance(255,255,255)-1) -lt 0.000001 -and [FirstInstallWindow]::Luminance(0,0,0) -eq 0 -and [Math]::Abs([FirstInstallWindow]::Luminance(255,0,0)-0.2126) -lt 0.000001) 'Native luminance calculation changed contrast.'
        $ui.Search.Text='Equalizer'
        Assert-UI ($checks['apo'].Visibility -eq 'Visible') 'Library search failed to reach full catalog.'
        $ui.Search.Clear()
        $inv=New-Object PackageInventory; $inv.Complete=$true
        $p=New-Object PackageRecord; $p.Id='VideoLAN.VLC'; $p.Name='Publisher identity fixture'; $p.Source='winget'; $p.InstalledVersion='3.0.20'
        $inv.Packages.Add($p); $script:libraryInventory=$inv; Update-LibraryStates
        Assert-UI ([Windows.Automation.AutomationProperties]::GetHelpText($checks['extra_vlc']).Contains(' · Installed · 3.0.20 · ')) 'Library exact installed state failed.'
        Assert-UI ([Windows.Automation.AutomationProperties]::GetHelpText($checks['affinity']).Contains(' · Unknown · ')) 'Guided app falsely identified.'
        $inv.Packages.Add($p); Update-LibraryStates
        Assert-UI ([Windows.Automation.AutomationProperties]::GetHelpText($checks['extra_vlc']).Contains(' · Unknown')) 'Multiple registrations were hidden.'
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
        Assert-UI (-not $ui.ContainsKey('UpdatesMode') -and $null -eq [OneInstallPackages].GetMethod('UpdateAsync')) 'Update feature must be removed from UI and service.'
        [OneInstallPackages]::Record('Update',$p.Id,'winget','Example VLC','Failed','Simulated offline download failure. Check connectivity and retry after refresh.',-1,$null) | Out-Null
        [OneInstallPackages]::Record('Install','Fixture.Restart','winget','Example Editor','Restart required','Simulated restart-required fixture; no real app installed.',3010,$null) | Out-Null
        Show-ManagerPage 'History'; Pump-UI; Capture-UI 'history'
        Assert-UI ($ui.ManagerList.Children.Count -eq 2) 'History did not render per-app outcomes.'
        Show-ThirdPartyNotices
        Show-Diagnostics
        $rows=@(@{Key='extra_vlc';Name='VLC';State='Already installed · 3.0.20'},@{Key='app1';Name='Firefox';State='Missing · catalog package'},@{Key='';Name='Unknown publisher app';State='Unavailable in this catalog'},@{Key='affinity';Name='Affinity';State='Manual installation required'})
        Show-SetupPreview $rows 'Snapshot import preview' | Out-Null
        Set-AppMode 'Install'; $script:managerPage.Visibility='Collapsed'
        $script:libraryView='All apps'; Update-Filter; Pump-UI
        $window.Width=830; $window.Height=600; Pump-UI; Capture-UI 'narrow'
        Assert-UI ($ui.LibraryScroll.ViewportWidth -gt 240 -and $ui.Cards.ItemWidth -gt 100) 'Narrow library unusable.'
        $window.Width=1240; Pump-UI
        $window.Close()
    } finally {
        $resolved=[IO.Path]::GetFullPath($testData); $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if (-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^1nstall-ui-[a-f0-9]{32}$') { throw 'UI fixture escaped temporary root.' }
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
})
