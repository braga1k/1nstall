# Loaded in the app scope only with -ManagerTest. All inventory/history data is fictional.
$testData=Join-Path ([IO.Path]::GetTempPath()) ('1nstall-ui-'+[guid]::NewGuid().ToString('N'))
[OneInstallPackages]::DataRoot=$testData
$window.Add_ContentRendered({
    [OneInstall.Motion]::TestOverride=$false; [OneInstall.Motion]::Stop()
    function Assert-UI($Value,[string]$Message) { if (-not $Value) { throw $Message } }
    function Pump-UI([int]$Milliseconds=100) {
        $frame=New-Object Windows.Threading.DispatcherFrame; $pulse=New-Object Windows.Threading.DispatcherTimer
        $pulse.Interval=[TimeSpan]::FromMilliseconds($Milliseconds)
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
    function Find-Visual($Element,[type]$Type) {
        if ($Element -is $Type) { return $Element }
        for ($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Element);$i++) {
            $found=Find-Visual ([Windows.Media.VisualTreeHelper]::GetChild($Element,$i)) $Type
            if ($found) { return $found }
        }
    }
    function Assert-MotionFits($Surface,$Viewport,[string]$Name) {
        $bounds=$Surface.TransformToAncestor($Viewport).TransformBounds([Windows.Rect]::new($Surface.RenderSize))
        Assert-UI ($bounds.Left -ge 0 -and $bounds.Top -ge 0 -and $bounds.Right -le $Viewport.ActualWidth+0.5 -and $bounds.Bottom -le $Viewport.ActualHeight+0.5) "$Name animation clipped: $bounds inside $($Viewport.RenderSize)"
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
            $columns=$ui.Cards.Columns
            $lastCard=$ui.Cards.Children[$columns-1]
            $cardRight=$lastCard.TranslatePoint([Windows.Point]::new($lastCard.ActualWidth,0),$window).X
            if ([Windows.Controls.Grid]::GetRow($group) -eq 1) { $edge=$frame } else { $edge=$ui.ClearSelection }
            $toolsRight=$edge.TranslatePoint([Windows.Point]::new($edge.ActualWidth,0),$window).X
            Assert-UI ([Math]::Abs($cardRight-$toolsRight) -lt 1) "Install toolbar alignment: width=$width card=$cardRight tools=$toolsRight slot=$(($ui.Cards.Width/$ui.Cards.Columns)) viewport=$($ui.LibraryScroll.ViewportWidth) header=$($window.FindName('InstallSearchRow').ActualWidth)"
            Assert-UI ($window.FindName('NavigationGlass').ActualWidth -eq $window.FindName('SetupGlass').ActualWidth) 'Side panels must have equal widths.'
            $nav=$window.FindName('NavigationGlass'); $side=$window.FindName('SetupGlass')
            $firstCard=$ui.Cards.Children[0]
            $leftGap=$firstCard.TranslatePoint([Windows.Point]::new(0,0),$window).X-$nav.TranslatePoint([Windows.Point]::new($nav.ActualWidth,0),$window).X
            $rightGap=$side.TranslatePoint([Windows.Point]::new(0,0),$window).X-$cardRight
            Assert-UI ([Math]::Abs($leftGap-20) -lt 1 -and [Math]::Abs($leftGap-$rightGap) -lt 1) "Install gutters differ at width ${width}: left=$leftGap right=$rightGap"
            $bar=Find-Visual $ui.LibraryScroll ([Windows.Controls.Primitives.ScrollBar])
            $barCenter=$bar.TranslatePoint([Windows.Point]::new($bar.ActualWidth/2,0),$window).X
            Assert-UI ([Math]::Abs($barCenter-($cardRight+$rightGap/2)) -lt 1) 'Install scrollbar is not centred in the gutter.'
            $activity=$window.FindName('InstallActivity')
            Assert-UI ([Math]::Abs($activity.TranslatePoint([Windows.Point]::new($activity.ActualWidth,0),$window).X-$cardRight) -lt 1) 'Install activity must end at the card edge.'
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
                $side=$window.FindName('RemovalGlass')
                $leftGap=$surface.TranslatePoint([Windows.Point]::new(0,0),$window).X-$nav.TranslatePoint([Windows.Point]::new($nav.ActualWidth,0),$window).X
                $rightGap=$side.TranslatePoint([Windows.Point]::new(0,0),$window).X-$cardRight
                Assert-UI ([Math]::Abs($leftGap-20) -lt 1 -and [Math]::Abs($leftGap-$rightGap) -lt 1) "Uninstall gutters differ: left=$leftGap right=$rightGap"
                $bar=Find-Visual $ui.InstalledList ([Windows.Controls.Primitives.ScrollBar])
                $barCenter=$bar.TranslatePoint([Windows.Point]::new($bar.ActualWidth/2,0),$window).X
                Assert-UI ([Math]::Abs($barCenter-($cardRight+$rightGap/2)) -lt 1) 'Uninstall scrollbar is not centred in the gutter.'
                $activity=$window.FindName('UninstallActivity')
                Assert-UI ([Math]::Abs($activity.TranslatePoint([Windows.Point]::new($activity.ActualWidth,0),$window).X-$cardRight) -lt 1) 'Removal activity must end at the card edge.'
            }
            $viewsCenter=$ui.InstalledAll.TranslatePoint([Windows.Point]::new(0,$ui.InstalledAll.ActualHeight/2),$window).Y
            Assert-UI ([Math]::Abs($brandCenter-$viewsCenter) -lt 1 -and [Math]::Abs($installCenter-$removalPoint.Y-$frame.ActualHeight/2) -lt 1) 'Uninstall header must align with the sidebar title and Install button.'
            Update-InstalledFilter; Pump-UI
            Capture-UI ('uninstall-toolbar-'+$width)
            Set-AppMode 'Install'; Pump-UI; Pump-UI; Pump-UI; Pump-UI; Pump-UI
            Capture-UI ('toolbar-'+$width)
        }
        $window.Width=1240; Set-AppMode 'Uninstall'; Pump-UI
        $box=Find-InstalledCheck ($ui.InstalledList.ItemContainerGenerator.ContainerFromIndex(0))
        $light=Get-InstalledCardLight $box
        Assert-UI ($light -and $light.ActualWidth -gt 0) 'Installed card is missing its hover light.'
        $savedMotion=${function:Test-MotionEnabled}; $savedGlass=$script:lastGlass
        try {
            function Test-MotionEnabled { return $true }
            $script:lastGlass=$true; $light.Tag=0
            $move=[Windows.Input.MouseEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0)
            $move.RoutedEvent=[Windows.Input.Mouse]::MouseMoveEvent
            $box.RaiseEvent($move)
            Assert-UI ([long]$light.Tag -gt 0 -and $light.Background.Center -eq $light.Background.GradientOrigin) 'Uninstall pointer movement did not update the light.'
            function Test-MotionEnabled { return $false }
            $light.Tag=0; $box.RaiseEvent($move)
            Assert-UI ([long]$light.Tag -eq 0) 'Uninstall light ignored reduced motion.'
            function Test-MotionEnabled { return $true }
            $script:lastGlass=$false; $box.RaiseEvent($move)
            Assert-UI ([long]$light.Tag -eq 0) 'Uninstall light ignored disabled glass effects.'
            $light.Opacity=1
            Move-GlassLight $light ([Windows.Point]::new($light.ActualWidth*0.75,$light.ActualHeight*0.3))
            Capture-UI 'uninstall-hover'
            $light.ClearValue([Windows.UIElement]::OpacityProperty)
        } finally { ${function:Test-MotionEnabled}=$savedMotion; $script:lastGlass=$savedGlass }
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
        $categorySlot=($ui.Cards.Width/$ui.Cards.Columns)
        foreach ($target in @('All apps','Browsers','AI Tools','Audio Production','Design & Photography','Audio Production','All apps')) {
            $button=@($categoryButtons | Where-Object Tag -eq $target)[0]
            if ($target -ne 'All apps') {
                $app=@($catalog | Where-Object Category -eq $target)[0]
                $categoryGroups[$app.CategoryGroup].IsExpanded=$true
            }
            $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Pump-UI; Pump-UI; Pump-UI; Pump-UI; Pump-UI
            Assert-UI (($ui.Cards.Width/$ui.Cards.Columns) -eq $categorySlot) 'Card size changed when a category did not need scrolling.'
            foreach ($card in $ui.Cards.Children) {
                Assert-UI ([Math]::Abs(${card}.ActualWidth-(($ui.Cards.Width/$ui.Cards.Columns)-8)) -lt 1) 'Category transition left a card wider than its grid slot.'
                $surface=$card.Template.FindName('Card',$card)
                if ($surface) {
                    Assert-UI ($surface.ActualWidth -le ($ui.Cards.Width/$ui.Cards.Columns)-8+1 -and $surface.CornerRadius.TopRight -eq 18 -and $surface.CornerRadius.BottomRight -eq 18) 'Card right edge was clipped or lost its rounded shape.'
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
        Assert-UI ($checks['extra_vlc'].Content.Children[2].Text -eq '✓ Installed' -and [object]::ReferenceEquals($checks['extra_vlc'].Background,$window.Resources['InstalledCardFill'])) 'Confirmed installed app was not greyed out.'
        Assert-UI ($checks['extra_vlc'].IsEnabled -and $null -eq $checks['extra_vlc'].ToolTip -and $null -eq $checks['extra_vlc'].Content.Children[3].ToolTip) 'Installed app lost interaction or retained a hover description.'
        Assert-UI ([Windows.Automation.AutomationProperties]::GetHelpText($checks['affinity']).Contains(' · Unknown · ')) 'Guided app falsely identified.'
        $inv.Packages.Add($p); Update-LibraryStates
        Assert-UI ([Windows.Automation.AutomationProperties]::GetHelpText($checks['extra_vlc']).Contains(' · Unknown')) 'Multiple registrations were hidden.'
        Assert-UI ($checks['extra_vlc'].Content.Children[2].Text -ne '✓ Installed' -and [object]::ReferenceEquals($checks['extra_vlc'].Background,$window.Resources['ContentFill'])) 'Ambiguous inventory left the installed appearance behind.'
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
        Assert-UI ($ui.LibraryScroll.ViewportWidth -gt 240 -and ($ui.Cards.Width/$ui.Cards.Columns) -gt 100) 'Narrow library unusable.'
        $window.Width=1240; $window.Height=[Math]::Min(840,[Windows.SystemParameters]::WorkArea.Height-24); Pump-UI
        Set-Selection @('extra_vlc')
        $originalSettings=$script:settings.Clone()
        foreach ($locale in $script:locales.PSObject.Properties) {
            $script:settings.Language=$locale.Name
            Apply-AppLanguage; Show-AppSettings; Pump-UI
            Assert-UI ($ui.SettingsMode.Content -eq $locale.Value.Strings.Settings) ('Settings was not translated: '+$locale.Name)
            Assert-UI ($ui.InstallMode.Content -eq $locale.Value.Strings.Install) ('Navigation was not translated: '+$locale.Name)
            Assert-UI ($script:settingsPage.Visibility -eq 'Visible' -and $script:settingsContent.ActualWidth -gt 350) ('Settings layout failed: '+$locale.Name)
            Assert-UI ($window.FindName('AppPanes').FlowDirection -eq $(if($locale.Value.Rtl){'RightToLeft'}else{'LeftToRight'})) 'Locale writing direction was not applied.'
            Assert-UI ($selected.ContainsKey('extra_vlc')) 'Changing language lost the app selection.'
            Set-AppMode 'Install'; $window.Width=1040; Pump-UI; Update-CardLayout; Pump-UI
            Assert-UI ($window.ActualWidth -ge 1040) 'Minimum width was not enforced.'
            foreach ($control in @($ui.Profiles,$ui.UserProfiles,$ui.ClearSelection)) {
                $row=$window.FindName('InstallSearchRow'); $bounds=$control.TransformToAncestor($row).TransformBounds([Windows.Rect]::new($control.RenderSize))
                Assert-UI ($bounds.Top -ge 0 -and $bounds.Left -ge 0 -and $bounds.Right -le $row.ActualWidth+1 -and $bounds.Bottom -le $row.ActualHeight+1) ('Translated profile tools clipped: '+$locale.Name+' '+$bounds)
            }
            Show-AppSettings; $window.Width=1240; Pump-UI
            Capture-UI ('settings-'+$locale.Name)
        }
        $script:settings.Language='pt-PT'; Apply-AppLanguage; Show-AppSettings
        $ui.ThemeChoice.SelectedIndex=1; Pump-UI
        Assert-UI $script:lightMode 'Light theme selector did not apply immediately.'
        $ui.ThemeChoice.Focus() | Out-Null; Pump-UI
        Assert-UI ($ui.ThemeChoice.Template.FindName('ChoiceFocus',$ui.ThemeChoice).Visibility -eq 'Visible') 'Settings keyboard focus is invisible.'
        Assert-UI ((Convert-UiText 'All apps · 325 apps') -notmatch 'All apps') 'A translated count retained the English category.'
        foreach ($textKey in @('TextPrimaryBrush','TextSecondaryBrush')) {
            $foreground=$window.Resources[$textKey].Color
            foreach ($stop in $window.Resources['ContentFill'].GradientStops) {
                Assert-UI (((Get-Luminance $stop.Color)+0.05)/((Get-Luminance $foreground)+0.05) -ge 4.5) 'Light material text contrast is too low.'
            }
        }
        $surface=$script:settingsContent.Children[1]; $light=$surface.Child.Children[0]
        $savedMotion=${function:Test-MotionEnabled}
        try {
            function Test-MotionEnabled { return $true }
            $light.Tag=0
            $move=[Windows.Input.MouseEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0); $move.RoutedEvent=[Windows.Input.Mouse]::MouseMoveEvent
            $ui.ThemeChoice.RaiseEvent($move)
            Assert-UI ([long]$light.Tag -gt 0) 'Settings controls did not bubble pointer movement to the surface light.'
            function Test-MotionEnabled { return $false }
            $light.Tag=0; $ui.ThemeChoice.RaiseEvent($move)
            Assert-UI ([long]$light.Tag -eq 0) 'Settings light ignored reduced motion.'
            $light.Opacity=1; Move-GlassLight $light ([Windows.Point]::new($light.ActualWidth*0.72,$light.ActualHeight*0.6))
        } finally { ${function:Test-MotionEnabled}=$savedMotion }
        Capture-UI 'settings-light-pt-PT'
        $ui.AccentChoice.IsChecked=$false; $ui.AccentChoice.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)); Pump-UI
        $color=Get-WindowsAccent
        Assert-UI ($color.R -eq $color.G -and $color.G -eq $color.B) 'Disabling Windows accent must select a neutral colour.'
        foreach ($appearance in @('Light','Dark')) {
            $script:settings.Theme=$appearance; Update-WindowsAccent; Pump-UI
            foreach ($key in @('ContentFill','GlassPanelFill','GlassControlFill','GlassEdge','CardEdge','AccentActionBrush')) {
                $brush=$window.Resources[$key]
                Assert-UI ($brush -is [Windows.Media.GradientBrush]) ('Material depth was flattened: '+$key)
                foreach ($stop in $brush.GradientStops) { Assert-UI ($stop.Color.R -eq $stop.Color.G -and $stop.Color.G -eq $stop.Color.B) ('A monochrome material retains colour: '+$key) }
            }
            foreach ($stop in $light.Background.GradientStops) { Assert-UI ($stop.Color.R -eq $stop.Color.G -and $stop.Color.G -eq $stop.Color.B) 'An already moved hover light retained its old accent.' }
            Capture-UI ('settings-mono-'+$appearance.ToLowerInvariant())
            Set-AppMode 'Install'; foreach ($wait in 1..5) { Pump-UI }; Capture-UI ('install-mono-'+$appearance.ToLowerInvariant())
            Set-AppMode 'Uninstall'; Pump-UI; Capture-UI ('uninstall-mono-'+$appearance.ToLowerInvariant())
            Show-AppSettings; Pump-UI
        }
        $script:settings.Theme='Light'; Update-WindowsAccent
        # Keep the system poll from restoring the real preference during this simulated case.
        $accentTimer.Stop()
        try {
            Set-GlassAppearance $false; Pump-UI
            Assert-UI ($window.Resources['GlassHighlightsOpacity'] -eq 0 -and $window.FindName('AmbientLight').Visibility -eq 'Collapsed') 'Opaque appearance retained light effects.'
            foreach ($stop in $window.Resources['GlassPanelFill'].GradientStops) { Assert-UI ($stop.Color.A -eq 255) 'Disabled transparency retained translucent panels.' }
        } finally { Set-GlassAppearance $true; $accentTimer.Start() }
        $ui.AccentChoice.IsChecked=$true; $ui.AccentChoice.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)); Pump-UI
        Capture-UI 'settings-light-accent-restored'
        Set-AppMode 'Install'; foreach ($wait in 1..5) { Pump-UI }; Capture-UI 'install-light-accent'
        $script:settings.WindowsAccent=$false; $script:lastAccent=''; Update-WindowsAccent; Show-AppSettings; Pump-UI
        $window.Width=830; Pump-UI; Capture-UI 'settings-narrow-pt-PT'
        Set-AppMode 'Install'; Pump-UI; Capture-UI 'install-light-pt-PT'
        Assert-UI ($script:settingsPage.Visibility -eq 'Collapsed' -and $selected.ContainsKey('extra_vlc')) 'Returning from Settings lost the selection.'
        $savedSettingsPath=$script:settingsPath; $savedTest=$script:settingsTest
        try {
            $script:settingsPath=Join-Path $testData 'settings.json'; $script:settingsTest=$false
            Assert-UI (Save-AppSettings) 'First preference save failed.'
            $script:settings.Theme='Dark'; Assert-UI (Save-AppSettings) 'Atomic preference replacement failed.'
            $saved=Get-Content -LiteralPath $script:settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert-UI ($saved.Language -eq 'pt-PT' -and $saved.Theme -eq 'Dark' -and -not $saved.WindowsAccent) 'Preferences did not persist.'
        } finally { $script:settingsPath=$savedSettingsPath; $script:settingsTest=$savedTest }
        $script:settings=$originalSettings; Apply-AppLanguage; Update-WindowsAccent
        Assert-UI ([OneInstallUpdate]::IsNewer('v3.3.0','3.2.0') -and -not [OneInstallUpdate]::IsNewer('v3.2.0','3.2.0.0') -and -not [OneInstallUpdate]::IsNewer('v3.3.0-beta','3.2.0') -and -not [OneInstallUpdate]::IsNewer('v3.1.0','3.2.0')) 'Update version comparison failed.'
        $old=Join-Path $testData 'old.exe'; $new=Join-Path $testData 'new.exe'
        [IO.File]::WriteAllText($old,'old version'); [IO.File]::WriteAllText($new,'new version')
        $oldHash=[OneInstallUpdate]::HashFile($old); $newHash=[OneInstallUpdate]::HashFile($new)
        $rejected=$false
        try { [OneInstallUpdate]::ReplaceVerified($new,$old,('0'*64),$oldHash) } catch { $rejected=$true }
        Assert-UI ($rejected -and [IO.File]::ReadAllText($old) -eq 'old version') 'A corrupt update modified the original executable.'
        [OneInstallUpdate]::ReplaceVerified($new,$old,$newHash,$oldHash)
        Assert-UI ([OneInstallUpdate]::HashFile($old) -eq $newHash -and [OneInstallUpdate]::HashFile($old+'.previous') -eq $oldHash) 'Atomic update did not preserve the previous version.'
        # Real WPF clocks, rapid intent changes and live reduced-motion cancellation.
        Set-AppMode 'Install'; $ui.Search.Clear(); Set-Selection @(); $window.UpdateLayout()
        [OneInstall.Motion]::TestOverride=$true
        [OneInstall.Motion]::Opening($window)
        Assert-UI ([OneInstall.Motion]::ActiveAnimations -gt 0 -and $ui.InstallMode.IsEnabled) 'Opening blocked input or did not animate.'
        foreach ($wait in 1..7) { Pump-UI }
        Assert-UI ([OneInstall.Motion]::Decorations -eq 0 -and [OneInstall.Motion]::ActiveAnimations -eq 0) 'Opening left clocks or decoration running.'
        $ui.LibraryScroll.ScrollToTop(); $ui.CategoriesHost.ScrollToTop(); Pump-UI
        $card=$ui.Cards.Children[0]; $card.ApplyTemplate() | Out-Null
        $surface=$card.Template.FindName('Card',$card)
        [OneInstall.Motion]::Hover($surface,$true); [OneInstall.Motion]::Pop($surface)
        [OneInstall.Motion]::Hover($categoryButtons[0],$true); [OneInstall.Motion]::Pop($categoryButtons[0])
        $header=$categoryGroups['Create'].Template.FindName('HeaderToggle',$categoryGroups['Create'])
        [OneInstall.Motion]::Hover($header,$true); [OneInstall.Motion]::Pop($header)
        Pump-UI 170
        Assert-UI ($surface.RenderTransform.Children[0].ScaleX -gt 1 -and $surface.RenderTransform.Children[1].Y -lt -1) 'Hover lift or click overshoot was removed.'
        Assert-MotionFits $surface (Find-Visual $ui.LibraryScroll ([Windows.Controls.ScrollContentPresenter])) 'First card'
        Assert-MotionFits $categoryButtons[0] (Find-Visual $ui.CategoriesHost ([Windows.Controls.ScrollContentPresenter])) 'All apps'
        Assert-MotionFits $header (Find-Visual $ui.CategoriesHost ([Windows.Controls.ScrollContentPresenter])) 'Category header'
        [OneInstall.Motion]::Stop()
        $key=[string]$ui.Cards.Children[0].Tag
        foreach ($click in 1..4) {
            Set-Selection @($key); Animate-SelectionFlight $key $true
            Assert-UI ($selected.ContainsKey($key) -and $ui.Install.IsEnabled) 'Animation delayed the real selection.'
            Remove-SelectedApp $key
            Assert-UI ($selected.Count -eq 0 -and -not $ui.Install.IsEnabled) 'Rapid deselect lost the final intent.'
            Assert-UI ([OneInstall.Motion]::Decorations -le 1) 'Reversing a selection left duplicate capsules.'
        }
        foreach ($wait in 1..7) { Pump-UI }
        Assert-UI ([OneInstall.Motion]::Decorations -eq 0 -and [OneInstall.Motion]::ActiveAnimations -eq 0) 'Selection left a capsule or a cancelled clock alive.'
        [OneInstall.Motion]::Result($ui.SelectedCount,$false)
        Assert-UI ([OneInstall.Motion]::Decorations -eq 0) 'Failure/manual result was celebrated as success.'
        [OneInstall.Motion]::Result($ui.SelectedCount,$true)
        Assert-UI ([OneInstall.Motion]::Decorations -eq 3) 'Verified success did not get its check, halo and window glow.'
        $glow=@($window.FindName('MotionOverlay').Children | Where-Object Tag -eq 'ConfirmationGlow')[0]
        Pump-UI 170
        Assert-UI ($glow.ActualWidth -eq $window.ActualWidth -and $glow.ActualHeight -eq $window.ActualHeight -and $glow.Opacity -gt 0 -and -not $glow.IsHitTestVisible) 'Confirmation glow must cover the window without blocking interaction.'
        [OneInstall.Motion]::Confirm()
        Assert-UI (@($window.FindName('MotionOverlay').Children | Where-Object Tag -eq 'ConfirmationGlow').Count -eq 1) 'Fast successes stacked window flashes.'
        Pump-UI 1200
        Assert-UI ([OneInstall.Motion]::Decorations -eq 0 -and [OneInstall.Motion]::ActiveAnimations -eq 0) 'Confirmation did not clean up.'
        Set-AppMode 'Uninstall'; Pump-UI 400; [OneInstall.Motion]::Stop()
        [OneInstallUninstall]::VerifiedRemovals.Enqueue('verified-removal-fixture')
        $uninstallTimer.Start(); Pump-UI 350; $uninstallTimer.Stop()
        Assert-UI (@($window.FindName('MotionOverlay').Children | Where-Object Tag -eq 'ConfirmationGlow').Count -eq 1) 'A verified removal did not confirm on the UI dispatcher.'
        Show-AppSettings; Show-ManagerPage 'History'; Set-AppMode 'Uninstall'; Set-AppMode 'Install'
        Assert-UI ($ui.InstallLibrary.Visibility -eq 'Visible' -and $ui.UninstallPage.Visibility -eq 'Collapsed' -and $script:settingsPage.Visibility -eq 'Collapsed' -and $script:managerPage.Visibility -eq 'Collapsed') 'Rapid navigation left the wrong page visible.'
        [OneInstall.Motion]::TestOverride=$false; [OneInstall.Motion]::Stop()
        Assert-UI ([OneInstall.Motion]::ActiveAnimations -eq 0 -and [OneInstall.Motion]::Decorations -eq 0) 'Reduced motion did not cancel active decoration.'
        [OneInstall.Motion]::Opening($window); Animate-CardClick $ui.Cards.Children[0]
        Assert-UI ([OneInstall.Motion]::ActiveAnimations -eq 0 -and [OneInstall.Motion]::Decorations -eq 0) 'Reduced motion started new clocks.'
        'PASS: non-blocking opening, rapid select/deselect, capsule cleanup, honest result feedback, rapid navigation and live reduced-motion cancellation.'
        [OneInstall.Motion]::TestOverride=$null
        $window.Close()
    } finally {
        $resolved=[IO.Path]::GetFullPath($testData); $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if (-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^1nstall-ui-[a-f0-9]{32}$') { throw 'UI fixture escaped temporary root.' }
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
})
