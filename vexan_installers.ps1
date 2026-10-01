#requires -Version 5.1
[CmdletBinding()]
param([switch]$CatalogOnly, [switch]$SelfTest, [switch]$SmokeTest, [string]$PreviewPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$catalogJson = @'
@@CATALOG@@
'@
$xamlText = @'
@@XAML@@
'@
if ($catalogJson.Trim().StartsWith('@@')) {
    $catalogJson = Get-Content (Join-Path $PSScriptRoot 'catalog.json') -Raw -Encoding UTF8
    $xamlText = Get-Content (Join-Path $PSScriptRoot 'interface.xaml') -Raw -Encoding UTF8
}
$thirdPartyNotices = @'
@@THIRD_PARTY_NOTICES@@
'@
if ($thirdPartyNotices.Trim().StartsWith('@@')) { $thirdPartyNotices=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'licenses/THIRD-PARTY-NOTICES.txt')) }
$iconData = '@@ICON@@'
if ($iconData.StartsWith('@@')) { $iconData=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'src/1nstall.ico'))) }
# Windows PowerShell 5.1 emits JSON arrays as one pipeline object; enumerate explicitly.
$catalog = @($catalogJson | ConvertFrom-Json | ForEach-Object { $_ })
$byKey = @{}
foreach ($app in $catalog) { $byKey[$app.Key] = $app }
$profilesJson = @'
@@PROFILES@@
'@
if ($profilesJson.Trim().StartsWith('@@')) { $profilesJson=Get-Content (Join-Path $PSScriptRoot 'profiles.json') -Raw -Encoding UTF8 }
$profiles=@($profilesJson | ConvertFrom-Json | ForEach-Object { $_ })
$profilesByKey=@{}
foreach ($profile in $profiles) { $profilesByKey[$profile.Key]=$profile }
function Test-AppCategory($App,[string]$Category) {
    return ($Category -eq 'All apps' -or $App.Category -eq $Category -or $App.AlsoIn -contains $Category)
}
function Get-Plan([string[]]$Keys) {
    $seen = @{}
    $ordered = New-Object 'System.Collections.Generic.List[object]'
    foreach ($key in $Keys) {
        if (-not $byKey.ContainsKey($key)) { throw "Unknown application: $key" }
        foreach ($dependency in $byKey[$key].Requires) {
            if (-not $seen.ContainsKey($dependency)) { $ordered.Add($byKey[$dependency]); $seen[$dependency] = $true }
        }
        if (-not $seen.ContainsKey($key)) { $ordered.Add($byKey[$key]); $seen[$key] = $true }
    }
    return $ordered.ToArray()
}
if ($CatalogOnly) { $catalogJson; return }
$uninstallCode = @'
@@UNINSTALL_HELPER@@
'@
if ($uninstallCode.Trim().StartsWith('@@')) { $uninstallCode=Get-Content (Join-Path $PSScriptRoot 'src/uninstall-helper.cs') -Raw -Encoding UTF8 }
if (-not ('OneInstallUninstall' -as [type])) {
    Add-Type -TypeDefinition $uninstallCode -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll')
}
if ($SelfTest) {
    [OneInstallUninstall]::SelfTest()
    if ($profiles.Count -ne 20 -or $profilesByKey.Count -ne $profiles.Count) { throw 'Invalid built-in profiles.' }
    foreach ($profile in $profiles) {
        if (-not $profile.Name -or -not $profile.Description -or $profile.Apps.Count -eq 0) { throw 'Incomplete profile.' }
        if (@($profile.Apps | Select-Object -Unique).Count -ne $profile.Apps.Count) { throw 'Duplicate profile app.' }
        Get-Plan @($profile.Apps) | Out-Null
    }
    if ($profilesByKey['audio'].Apps -contains 'flstudio' -or $profilesByKey['audio'].Apps -contains 'peace' -or $profilesByKey['gaming'].Apps -contains 'ts3') { throw 'Profiles bundle competing or unrelated tools.' }
    foreach ($key in $profilesByKey['opensource'].Apps) { if ($byKey[$key].OpenSource -ne $true) { throw 'Open-source profile includes an unverified license.' } }
    if ($catalog.Count -eq 0 -or $byKey.Count -ne $catalog.Count) { throw 'Invalid catalog.' }
    $packageIds=@($catalog | ForEach-Object { $_.Ids })
    if (@($packageIds | Select-Object -Unique).Count -ne $packageIds.Count) { throw 'Duplicate package IDs.' }
    foreach ($app in $catalog) {
        if (-not $app.Name -or -not $app.Description -or -not $app.Category) { throw 'Missing catalog copy.' }
        if ($app.CategoryGroup -notin @('Everyday','Create','Files & Storage','PC & Tools') -or
            @($app.AlsoIn | Select-Object -Unique).Count -ne $app.AlsoIn.Count -or $app.AlsoIn -contains $app.Category) { throw 'Invalid category navigation.' }
        foreach ($category in $app.AlsoIn) { if ($catalog.Category -notcontains $category) { throw 'Unknown secondary category.' } }
        if (($app.Ids.Count -gt 0) -eq (-not [string]::IsNullOrEmpty($app.Url))) { throw 'Each app needs exactly one installation method.' }
        foreach ($dependency in $app.Requires) { if (-not $byKey.ContainsKey($dependency)) { throw 'Missing dependency.' } }
    }
    $plan = @(Get-Plan @('peace','apo','ts3','peace'))
    if (($plan.Key -join ',') -ne 'apo,peace,ts3') { throw 'Invalid dependency order.' }
    $rejected = $false
    try { Get-Plan @('untrusted') | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unknown profile ID was accepted.' }
    if ($byKey['ts3'].Ids[0] -ne 'TeamSpeakSystems.TeamSpeakClient') { throw 'Incorrect TeamSpeak client.' }
    if ($byKey['resolve'].Category -ne 'Video Editing' -or (Test-AppCategory $byKey['resolve'] 'Media Players') -or
        -not (Test-AppCategory $byKey['extra_blender'] 'Video Editing') -or
        -not (Test-AppCategory $byKey['daily_adobe_creative_cloud'] 'Audio Production') -or
        $byKey['apo'].Category -ne 'Audio Controls' -or $byKey['winutil_plex'].Category -ne 'Media Servers') { throw 'Task-based category regression.' }
    'PASS: catalog, task categories and secondary workflows, dependencies, package IDs, 20 grouped built-in profiles, open-source profile licenses and TeamSpeak 3.'
    return
}
Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase')
$windowCode = @'
@@WINDOW_HELPER@@
'@
if ($windowCode.Trim().StartsWith('@@')) { $windowCode=Get-Content (Join-Path $PSScriptRoot 'src/window-helper.cs') -Raw -Encoding UTF8 }
if (-not ('FirstInstallWindow' -as [type])) { Add-Type -TypeDefinition $windowCode }
try {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem) { throw 'Requires 64-bit Windows.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Open the executable or use powershell.exe -STA -File vexan_installers.ps1.' }
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xamlText)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    # UISettings exposes the actual Windows accent, including automatic wallpaper colors.
    $script:accentSettings=$null
    try {
        [Windows.UI.ViewManagement.UISettings,Windows.UI.ViewManagement,ContentType=WindowsRuntime] | Out-Null
        $script:accentSettings=[Windows.UI.ViewManagement.UISettings]::new()
    } catch { }
    function Get-WindowsAccent {
        try {
            if ($null -ne $script:accentSettings) {
                $color=$script:accentSettings.GetColorValue([Windows.UI.ViewManagement.UIColorType]::Accent)
                return [Windows.Media.Color]::FromRgb($color.R,$color.G,$color.B)
            }
        } catch { }
        $color=[Windows.SystemParameters]::WindowGlassColor
        return [Windows.Media.Color]::FromRgb($color.R,$color.G,$color.B)
    }
    function Mix-Accent([Windows.Media.Color]$Color,[Windows.Media.Color]$Other,[double]$Amount) {
        return [Windows.Media.Color]::FromRgb([byte]($Color.R*(1-$Amount)+$Other.R*$Amount),[byte]($Color.G*(1-$Amount)+$Other.G*$Amount),[byte]($Color.B*(1-$Amount)+$Other.B*$Amount))
    }
    function Get-Luminance([Windows.Media.Color]$Color) {
        $values=@($Color.R,$Color.G,$Color.B) | ForEach-Object {
            $v=$_/255.0
            if ($v -le 0.04045) { $v/12.92 } else { [Math]::Pow(($v+0.055)/1.055,2.4) }
        }
        return 0.2126*$values[0]+0.7152*$values[1]+0.0722*$values[2]
    }
    $script:nativeGlass=$false
    function Update-NativeGlass {
        $handle=[Windows.Interop.WindowInteropHelper]::new($window).Handle
        if ($handle -eq [IntPtr]::Zero) { return }
        $script:backdropResult=[FirstInstallWindow]::SetBackdrop($handle,($script:lastGlass -eq $true))
        $script:nativeGlass=($script:lastGlass -eq $true -and $script:backdropResult -eq 0)
        $source=[Windows.Interop.HwndSource]::FromHwnd($handle)
        $chrome=[Windows.Shell.WindowChrome]::GetWindowChrome($window)
        if ($script:nativeGlass) {
            $chrome.GlassFrameThickness=[Windows.Thickness]::new(-1)
            $source.CompositionTarget.BackgroundColor=[Windows.Media.Colors]::Transparent
            $window.Background=[Windows.Media.Brushes]::Transparent
            $window.FindName('AmbientLight').Opacity=0.5
        } else {
            $chrome.GlassFrameThickness=[Windows.Thickness]::new(0)
            $source.CompositionTarget.BackgroundColor=[Windows.Media.ColorConverter]::ConvertFromString('#08091A')
            $window.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'WindowFill')
            $window.FindName('AmbientLight').Opacity=1
        }
        [FirstInstallWindow]::Apply($handle) | Out-Null
        Set-AccentPalette (Get-WindowsAccent)
    }
    $script:lastGlass=$null
    $script:glassBrushes=@{}
    $script:glassTemplates=@{}
    foreach ($key in @('GlassPanelFill','GlassControlFill','GlassEdge','GlassMenuFill','ContentFill','CardEdge')) { $script:glassTemplates[$key]=$window.Resources[$key] }
    function Set-AccentPalette([Windows.Media.Color]$Color) {
        $white=[Windows.Media.Colors]::White
        $base=[Windows.Media.ColorConverter]::ConvertFromString('#21283B')
        $text=$Color
        for ($i=0;$i -lt 20 -and ((Get-Luminance $text)+0.05)/((Get-Luminance $base)+0.05) -lt 4.5;$i++) { $text=Mix-Accent $text $white 0.12 }
        $foreground=if ((Get-Luminance $Color) -gt 0.179) { [Windows.Media.Colors]::Black } else { $white }
        $palette=@{
            AccentBrush=$Color
            AccentTextBrush=$text
            AccentForegroundBrush=$foreground
            AccentMutedBrush=(Mix-Accent $text $base 0.25)
            AccentHoverBrush=(Mix-Accent $text $white 0.15)
            AccentSurfaceBrush=(Mix-Accent $Color $base 0.82)
        }
        foreach ($key in $palette.Keys) {
            $window.Resources[$key]=[Windows.Media.SolidColorBrush]::new($palette[$key])
        }
        $action=[Windows.Media.LinearGradientBrush]::new()
        $action.StartPoint=[Windows.Point]::new(0,0); $action.EndPoint=[Windows.Point]::new(0.25,1)
        $contrastColor=if ($foreground -eq $white) { [Windows.Media.Colors]::Black } else { $white }
        $action.GradientStops.Add([Windows.Media.GradientStop]::new((Mix-Accent $Color $contrastColor 0.22),0))
        $action.GradientStops.Add([Windows.Media.GradientStop]::new($Color,0.4))
        $action.GradientStops.Add([Windows.Media.GradientStop]::new((Mix-Accent $Color $contrastColor 0.12),1))
        $window.Resources['AccentActionBrush']=$action
        $dark=[Windows.Media.ColorConverter]::ConvertFromString('#080B14')
        $backgroundTint=[Windows.Media.Color]::FromRgb((255-$Color.R),(255-$Color.G),(255-$Color.B))
        $background=Mix-Accent $backgroundTint $dark 0.96
        $window.Resources['OpaqueWindowFill']=[Windows.Media.SolidColorBrush]::new($background)
        $background.A=if ($script:nativeGlass) { 224 } else { 255 }
        $window.Resources['WindowFill']=[Windows.Media.SolidColorBrush]::new($background)
        foreach ($key in $script:glassTemplates.Keys) {
            $brush=$script:glassTemplates[$key].CloneCurrentValue()
            if ($brush -is [Windows.Media.GradientBrush]) {
                foreach ($stop in $brush.GradientStops) {
                    $alpha=$stop.Color.A
                    $tint=Mix-Accent $(if ($key -in @('GlassEdge','CardEdge')) { $Color } else { $backgroundTint }) $stop.Color $(if ($key -in @('GlassEdge','CardEdge')) { 0.72 } else { 0.86 })
                    if ($key -in @('GlassPanelFill','ContentFill','GlassControlFill')) {
                        for ($i=0;$i -lt 20 -and (Get-Luminance $tint) -gt 0.065;$i++) { $tint=Mix-Accent $tint ([Windows.Media.Colors]::Black) 0.08 }
                    }
                    $tint.A=$alpha; $stop.Color=$tint
                }
            }
            $script:glassBrushes[$key]=$brush
            if ($script:lastGlass -ne $false) { $window.Resources[$key]=$brush }
        }
        foreach ($number in @(1,2,3)) {
            $gradient=$window.FindName('AmbientGradient'+$number)
            if ($null -eq $gradient) { continue }
            $light=Mix-Accent $(if ($number -eq 2) { $Color } else { $backgroundTint }) ([Windows.Media.ColorConverter]::ConvertFromString($(if ($number -eq 2) { '#607BAA' } else { '#AB8FE0' }))) 0.45
            for ($i=0;$i -lt 20 -and (Get-Luminance $light) -gt 0.10;$i++) { $light=Mix-Accent $light ([Windows.Media.Colors]::Black) 0.08 }
            foreach ($stop in $gradient.GradientStops) { $tint=$light; $tint.A=$stop.Color.A; $stop.Color=$tint }
        }
        $script:lastAccent=$Color.ToString()
    }
    $script:lastGlass=$null
    function Set-GlassAppearance([bool]$Enabled) {
        $opaque=@{GlassPanelFill='#1C2235'; GlassControlFill='#252D43'; GlassEdge='#7F8BA5'; GlassMenuFill='#1C2235'; ContentFill='#21283B'; CardEdge='#57617B'}
        foreach ($key in $script:glassBrushes.Keys) {
            $window.Resources[$key]=if ($Enabled) { $script:glassBrushes[$key] } else { [Windows.Media.BrushConverter]::new().ConvertFromString($opaque[$key]) }
        }
        $window.FindName('AmbientLight').Visibility=if ($Enabled) { 'Visible' } else { 'Collapsed' }
        $window.Resources['GlassHighlightsOpacity']=if ($Enabled) { [double]1 } else { [double]0 }
        foreach ($name in @('NavigationBackdrop','SetupBackdrop')) { $window.FindName($name).Visibility=if ($Enabled) { 'Visible' } else { 'Collapsed' } }
        foreach ($name in @('NavigationGlass','SetupGlass')) {
            $pane=$window.FindName($name)
            if ($Enabled) { $pane.ClearValue([Windows.UIElement]::EffectProperty); $pane.Background='Transparent' } else { $pane.Effect=$null; $pane.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,'GlassPanelFill') }
        }
        $script:lastGlass=$Enabled
        Update-NativeGlass
    }
    function Update-WindowsAccent {
        $color=Get-WindowsAccent
        if ($color.ToString() -ne $script:lastAccent) { Set-AccentPalette $color }
        $glass=-not [Windows.SystemParameters]::HighContrast
        try { if ($null -ne $script:accentSettings) { $glass=$glass -and $script:accentSettings.AdvancedEffectsEnabled } } catch { }
        if ($glass -ne $script:lastGlass) { Set-GlassAppearance $glass }
    }
    $script:lastAccent=''
    Update-WindowsAccent
    # Poll on the WPF dispatcher: WinRT change callbacks otherwise run outside the PS runspace.
    $accentTimer=New-Object Windows.Threading.DispatcherTimer
    $accentTimer.Interval=[TimeSpan]::FromSeconds(1)
    $accentTimer.Add_Tick({ Update-WindowsAccent })
    $window.Add_Closed({ $accentTimer.Stop() })
    $accentTimer.Start()
    $window.Add_SourceInitialized({
        $script:cornerResult=[FirstInstallWindow]::Apply([Windows.Interop.WindowInteropHelper]::new($window).Handle)
        Update-NativeGlass
    })
    $iconStream=[IO.MemoryStream]::new([Convert]::FromBase64String($iconData))
    $window.Icon=[Windows.Media.Imaging.BitmapFrame]::Create($iconStream,[Windows.Media.Imaging.BitmapCreateOptions]::None,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $iconStream.Dispose()
    $window.Height=[Math]::Min(840,[Windows.SystemParameters]::WorkArea.Height-24)
    $ui = @{}
    foreach ($name in @('Categories','Search','ClearSearch','ResultCount','UserProfiles','ClearSelection','Cards','Empty','LogBox','SelectedCount','SaveSetup','Import','Export','QueuePanel','Status','Progress','Install','Cancel','OpenLogs','Environment','MinimizeWindow','MaximizeWindow','CloseWindow','MaximizeGlyph','LibraryScroll','InstallMode','UninstallMode','InstallLibrary','CategoriesHost','UninstallNavigation','NavigationHeading','UninstallPage','InstalledSearch','RefreshInstalled','WindowsAppsSettings','InstalledList','InstalledEmpty','InstalledAll','InstalledDesktop','InstalledStore','UninstallSelectedCount','ClearUninstallSelection','CheckLeftovers','OpenUninstallBackups','ReviewUninstall','StopUninstall','UninstallStatus','UninstallLog')) { $ui[$name] = $window.FindName($name) }
    $ui.Profiles=$window.FindName('Profiles')
    $window.FindName('ThirdPartyNotices').Add_Click({
        $noticePath=Join-Path $env:LOCALAPPDATA '1nstall/THIRD-PARTY-NOTICES.txt'
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($noticePath)) | Out-Null
        [IO.File]::WriteAllText($noticePath,$thirdPartyNotices,[Text.UTF8Encoding]::new($true))
        Start-Process notepad.exe -ArgumentList ('"{0}"' -f $noticePath)
    })
    $ui.MinimizeWindow.Add_Click({ $window.WindowState='Minimized' })
    $ui.MaximizeWindow.Add_Click({
        if ($window.WindowState -eq 'Maximized') { $window.WindowState='Normal' }
        else { $window.WindowState='Maximized' }
    })
    $ui.CloseWindow.Add_Click({ $window.Close() })
    $window.FindName('BrandHeader').Add_MouseLeftButtonDown({ param($sender,$eventArgs)
        if ($eventArgs.ClickCount -eq 2) { $ui.MaximizeWindow.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
        else { $window.DragMove() }
        $eventArgs.Handled=$true
    })
    $window.Add_StateChanged({
        $maximized=$window.WindowState -eq 'Maximized'
        $ui.MaximizeWindow.ToolTip=if ($maximized) { 'Restore' } else { 'Maximize' }
        [Windows.Automation.AutomationProperties]::SetName($ui.MaximizeWindow,[string]$ui.MaximizeWindow.ToolTip)
        $ui.MaximizeGlyph.Data=if ($maximized) { 'M 2,0 L 10,0 10,8 M 0,2 L 8,2 8,10 0,10 Z' } else { 'M 0,0 L 10,0 10,10 0,10 Z' }
    })
    $selected = @{}
    $checks = @{}
    $statuses = @{}
    $category = 'All apps'
    $busy = $false
    $syncing = $false
    $job = $null
    $logDir = if ($SmokeTest) { Join-Path $PSScriptRoot 'test-logs' } else { Join-Path $env:LOCALAPPDATA '1nstall\Logs' }
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logPath = Join-Path $logDir ('session-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$PID)
    $wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
    $winget = if ($wingetCommand) { $wingetCommand.Source } else { '' }
    $ui.Environment.Text = if ($winget) { 'WinGet ready · {0} apps to explore' -f $catalog.Count } else { 'WinGet is missing. Install App Installer to enable automatic installs.' }
    function Add-Log([string]$Message) {
        $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'),$Message
        $ui.LogBox.AppendText($line + "`r`n")
        $ui.LogBox.ScrollToEnd()
        try { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 } catch { $ui.Status.Text = 'Could not save the log to disk.' }
    }
    function New-Label([string]$Text, [string]$Color='#F3F5F7', [double]$Size=13) {
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = $Text; $label.Foreground = $Color; $label.FontSize = $Size
        $label.TextWrapping = 'Wrap'
        $label.FontFamily=if ($Size -ge 20) { $window.Resources['HeadingFont'] } else { $window.FontFamily }
        return $label
    }
    function Test-MotionEnabled {
        return [Windows.SystemParameters]::ClientAreaAnimation -and -not [Windows.SystemParameters]::HighContrast
    }
    function Animate-Value($Target,$Property,[double]$From,[double]$To,[int]$Milliseconds=160) {
        $Target.BeginAnimation($Property,$null)
        $Target.SetValue($Property,$To)
        if (-not (Test-MotionEnabled) -or -not $window.IsVisible -or [Math]::Abs($From-$To) -lt 0.001) { return }
        $animation=[Windows.Media.Animation.DoubleAnimation]::new($From,$To,[Windows.Duration]::new([TimeSpan]::FromMilliseconds($Milliseconds)))
        $ease=[Windows.Media.Animation.CubicEase]::new(); $ease.EasingMode='EaseOut'
        $animation.EasingFunction=$ease; $animation.FillBehavior='Stop'
        $Target.BeginAnimation($Property,$animation,[Windows.Media.Animation.HandoffBehavior]::SnapshotAndReplace)
    }
    function Animate-Appearance($Element,[double]$Offset=5) {
        Animate-Value $Element ([Windows.UIElement]::OpacityProperty) 0.72 1
        $move=[Windows.Media.TranslateTransform]::new(); $Element.RenderTransform=$move
        Animate-Value $move ([Windows.Media.TranslateTransform]::YProperty) $Offset 0
    }
    function Animate-CardEntrance($Card,[int]$Delay) {
        $Card.ApplyTemplate()
        $surface=$Card.Template.FindName('Card',$Card)
        if ($null -eq $surface) { return }
        $surface.RenderTransformOrigin=[Windows.Point]::new(0.5,0.5)
        $group=[Windows.Media.TransformGroup]::new()
        $scale=[Windows.Media.ScaleTransform]::new(1,1)
        $move=[Windows.Media.TranslateTransform]::new()
        $group.Children.Add($scale); $group.Children.Add($move); $surface.RenderTransform=$group
        foreach ($spec in @(@($surface,[Windows.UIElement]::OpacityProperty,0.15,1),@($move,[Windows.Media.TranslateTransform]::YProperty,10,0))) {
            $target=$spec[0]; $property=$spec[1]
            $target.BeginAnimation($property,$null); $target.SetValue($property,[double]$spec[3])
            if (-not (Test-MotionEnabled) -or -not $window.IsVisible) { continue }
            $frames=[Windows.Media.Animation.DoubleAnimationUsingKeyFrames]::new()
            $frames.KeyFrames.Add([Windows.Media.Animation.DiscreteDoubleKeyFrame]::new([double]$spec[2],[Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::Zero)))
            $frames.KeyFrames.Add([Windows.Media.Animation.DiscreteDoubleKeyFrame]::new([double]$spec[2],[Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($Delay))))
            $ease=[Windows.Media.Animation.CubicEase]::new(); $ease.EasingMode='EaseOut'
            $frames.KeyFrames.Add([Windows.Media.Animation.EasingDoubleKeyFrame]::new([double]$spec[3],[Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($Delay+180)),$ease))
            $frames.FillBehavior='Stop'
            $target.BeginAnimation($property,$frames,[Windows.Media.Animation.HandoffBehavior]::SnapshotAndReplace)
        }
    }
    function Animate-Library {
        if (-not $window.IsVisible) { return }
        $ui.Cards.UpdateLayout()
        $index=0
        foreach ($card in $ui.Cards.Children) {
            $y=$card.TranslatePoint([Windows.Point]::new(0,0),$ui.Cards).Y
            # Only stagger the current viewport; long catalogs must not queue seconds of motion.
            $delay=if ($y -lt $ui.LibraryScroll.ViewportHeight) { [Math]::Min(240,$index*35) } else { 0 }
            if ($y -lt $ui.LibraryScroll.ViewportHeight) { Animate-CardEntrance $card $delay; $index++ }
            else {
                $card.ApplyTemplate(); $surface=$card.Template.FindName('Card',$card)
                if ($surface) { $surface.BeginAnimation([Windows.UIElement]::OpacityProperty,$null); $surface.Opacity=1; $surface.RenderTransform=[Windows.Media.Transform]::Identity }
            }
        }
    }
    function Animate-CardClick($Card) {
        $Card.ApplyTemplate(); $surface=$Card.Template.FindName('Card',$Card)
        if (-not $surface) { return }
        $surface.BeginAnimation([Windows.UIElement]::OpacityProperty,$null); $surface.Opacity=1
        $scale=[Windows.Media.ScaleTransform]::new(1,1)
        $surface.RenderTransformOrigin=[Windows.Point]::new(0.5,0.5); $surface.RenderTransform=$scale
        Animate-Value $scale ([Windows.Media.ScaleTransform]::ScaleXProperty) 0.965 1 170
        Animate-Value $scale ([Windows.Media.ScaleTransform]::ScaleYProperty) 0.965 1 170
    }
    $window.Add_ContentRendered({ Animate-Library })
    function Enable-HoverMotion($Element) {
        $Element.Add_MouseMove({ param($sender,$eventArgs)
            if (-not $script:lastGlass -or -not (Test-MotionEnabled)) { return }
            $sender.ApplyTemplate()
            $light=$sender.Template.FindName('HoverLight',$sender)
            if ($light) { Move-GlassLight $light ($eventArgs.GetPosition($light)) }
        })
    }
    function Move-GlassLight($Light,[Windows.Point]$Position) {
        if ($Light.ActualWidth -le 0 -or $Light.ActualHeight -le 0) { return }
        $now=[DateTime]::UtcNow.Ticks
        if ($now-[long]$Light.Tag -lt 250000) { return }
        $Light.Tag=$now
        if ($Light.Background.IsFrozen) { $Light.Background=$Light.Background.CloneCurrentValue() }
        $point=[Windows.Point]::new([Math]::Max(0.0,[Math]::Min(1.0,$Position.X/$Light.ActualWidth)),[Math]::Max(0.0,[Math]::Min(1.0,$Position.Y/$Light.ActualHeight)))
        $Light.Background.Center=$point; $Light.Background.GradientOrigin=$point
    }
    function Update-GlassBackdrops {
        $ambient=$window.FindName('AmbientLight')
        foreach ($name in @('Navigation','Setup')) {
            $pane=$window.FindName($name+'Glass'); $backdrop=$window.FindName($name+'Backdrop')
            if ($pane.ActualWidth -le 0 -or $pane.ActualHeight -le 0) { continue }
            if ($backdrop.Background -isnot [Windows.Media.VisualBrush]) {
                $backdrop.Background=[Windows.Media.VisualBrush]::new($ambient)
                $backdrop.Background.ViewboxUnits='Absolute'; $backdrop.Background.Stretch='Fill'; $backdrop.Background.AutoLayoutContent=$false
            }
            $origin=$pane.TranslatePoint([Windows.Point]::new(0,0),$ambient)
            $backdrop.Background.Viewbox=[Windows.Rect]::new($origin.X,$origin.Y,$pane.ActualWidth,$pane.ActualHeight)
        }
    }
    foreach ($name in @('NavigationGlass','SetupGlass')) {
        $pane=$window.FindName($name)
        $pane.Add_SizeChanged({ Update-GlassBackdrops })
        $pane.Add_MouseMove({ param($sender,$eventArgs)
            if ($script:lastGlass -and (Test-MotionEnabled)) {
                $light=$window.FindName($sender.Name.Replace('Glass','Reflection'))
                Move-GlassLight $light ($eventArgs.GetPosition($light))
            }
        })
    }
    $window.Add_Loaded({ Update-GlassBackdrops })
    foreach ($control in $ui.Values) { if ($control -is [Windows.Controls.Button]) { Enable-HoverMotion $control } }
    function Set-QueueProgress([double]$Value) {
        Animate-Value $ui.Progress ([Windows.Controls.Primitives.RangeBase]::ValueProperty) $ui.Progress.Value $Value 200
    }
    function Update-Selection {
        $script:syncing = $true
        foreach ($app in $catalog) { $checks[$app.Key].IsChecked = $selected.ContainsKey($app.Key) }
        $script:syncing = $false
        $ui.SelectedCount.Text = '{0} apps selected' -f $selected.Count
        $ui.Install.IsEnabled = ($selected.Count -gt 0 -and -not $busy)
        $ui.SaveSetup.IsEnabled=($selected.Count -gt 0 -and -not $busy)
        $script:removeButtons=@{}
        $script:statusLabels=@{}
        $oldRows=@{}
        foreach ($child in $ui.QueuePanel.Children) { if ($child.Tag) { $oldRows[[string]$child.Tag]=$child.TranslatePoint([Windows.Point]::new(0,0),$ui.QueuePanel).Y } }
        $ui.QueuePanel.Children.Clear()
        if ($selected.Count -eq 0) {
            $label = New-Label 'Your next setup starts here. Select apps from the library.' '#B0BCD2'
            $label.Margin = '0,15,0,0'; $ui.QueuePanel.Children.Add($label) | Out-Null
        }
        foreach ($app in @(Get-Plan @($catalog | Where-Object { $selected.ContainsKey($_.Key) } | ForEach-Object { $_.Key }))) {
            $panel = New-Object Windows.Controls.StackPanel; $panel.Margin = '0,8,0,9'; $panel.Tag=$app.Key
            $title = New-Label $app.Name; $title.FontWeight = 'SemiBold'
            $row=New-Object Windows.Controls.Grid
            $row.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
            $actionColumn=New-Object Windows.Controls.ColumnDefinition; $actionColumn.Width='Auto'
            $row.ColumnDefinitions.Add($actionColumn)
            $title.Margin='0,0,8,0'; $title.VerticalAlignment='Center'
            $row.Children.Add($title) | Out-Null
            $remove=New-Object Windows.Controls.Button
            $remove.Content='×'; $remove.Tag=$app.Key; $remove.Width=32; $remove.MinHeight=32
            $remove.Padding='0'; $remove.Margin='0'; $remove.FontSize=18
            $remove.Background='Transparent'; $remove.BorderThickness='0'
            $remove.ToolTip='Remove '+$app.Name+' from your setup'
            [Windows.Automation.AutomationProperties]::SetName($remove,'Remove '+$app.Name)
            $remove.IsEnabled=-not $busy
            Enable-HoverMotion $remove
            [Windows.Controls.Grid]::SetColumn($remove,1)
            $remove.Add_Click({ param($sender,$eventArgs) Remove-SelectedApp ([string]$sender.Tag) })
            $script:removeButtons[$app.Key]=$remove
            $row.Children.Add($remove) | Out-Null
            $panel.Children.Add($row) | Out-Null
            $text = if ($statuses.ContainsKey($app.Key)) { $statuses[$app.Key] } elseif ($app.Ids.Count) { 'Automatic · WinGet' } else { 'Guided · official website' }
            $label = New-Label $text '#C2CADE' 12; $label.Margin = '0,4,0,0'
            $script:statusLabels[$app.Key]=$label
            $panel.Children.Add($label) | Out-Null
            $ui.QueuePanel.Children.Add($panel) | Out-Null
        }
        if ($window.IsVisible) {
            $ui.QueuePanel.UpdateLayout()
            foreach ($row in $ui.QueuePanel.Children) {
                if (-not $row.Tag) { continue }
                if ($oldRows.ContainsKey([string]$row.Tag)) {
                    $delta=$oldRows[[string]$row.Tag]-$row.TranslatePoint([Windows.Point]::new(0,0),$ui.QueuePanel).Y
                    $move=[Windows.Media.TranslateTransform]::new(); $row.RenderTransform=$move
                    Animate-Value $move ([Windows.Media.TranslateTransform]::YProperty) ([Math]::Max(-32,[Math]::Min(32,$delta))) 0
                } else { Animate-Appearance $row }
            }
        }
    }
    function Set-AppStatus([string]$Key,[string]$Text) {
        $statuses[$Key]=$Text
        $script:statusLabels[$Key].Text=$Text
        Add-Log ($byKey[$Key].Name + ': ' + $Text)
    }
    function Remove-SelectedApp([string]$Key) {
        if ($script:busy) { return }
        $selected.Remove($Key); $statuses.Remove($Key)
        foreach ($item in $catalog) {
            if ($item.Requires -contains $Key) { $selected.Remove($item.Key); $statuses.Remove($item.Key) }
        }
        Update-Selection
        $ui.Status.Text='Selection updated. Review before installing.'
    }
    function Set-Selection([string[]]$Keys) {
        $selected.Clear(); $statuses.Clear()
        foreach ($app in @(Get-Plan $Keys)) { $selected[$app.Key] = $true }
        Update-Selection
        $ui.Status.Text=if ($selected.Count) { 'Selection updated. Review before installing.' } else { 'Ready when you are.' }
    }
    function Update-Filter {
        $query = $ui.Search.Text.Trim()
        $count = 0
        # Fixed ItemWidth reserves a slot even for a collapsed child in WrapPanel.
        # Keep checkbox instances in $checks, but only attach matching cards.
        $ui.Cards.Children.Clear()
        foreach ($app in $catalog) {
            $match = (Test-AppCategory $app $category) -and
                (($app.Name + ' ' + $app.Category + ' ' + ($app.AlsoIn -join ' ') + ' ' + $app.Description).IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0)
            $checks[$app.Key].Visibility = if ($match) { 'Visible' } else { 'Collapsed' }
            $checks[$app.Key].Content.Children[1].Text=if ($app.AlsoIn -contains $category) { $category } else { $app.Category }
            if ($match) { $ui.Cards.Children.Add($checks[$app.Key]) | Out-Null; $count++ }
        }
        $ui.ResultCount.Text = "$category · $count apps"
        $ui.Empty.Visibility = if ($count -eq 0) { 'Visible' } else { 'Collapsed' }
        $ui.LibraryScroll.ScrollToTop()
        Animate-Library
    }
    foreach ($app in $catalog) {
        $check = New-Object Windows.Controls.CheckBox
        Enable-HoverMotion $check
        $check.Style = $window.Resources['CardCheck']; $check.Tag = $app.Key
        $check.Width = 184; $check.Margin = '0,0,8,8'; $check.MinHeight = 104
        $method = if ($app.Ids.Count) { 'Automatic · WinGet: ' + ($app.Ids -join ', ') } else { 'Guided · official website: ' + $app.Url }
        $help = $app.Description + "`n" + $app.Category + ' · ' + $app.LicenseLabel + "`n" + $method
        if ($app.AlsoIn.Count) { $help += "`nAlso in: " + ($app.AlsoIn -join ', ') }
        $tooltip = New-Object Windows.Controls.ToolTip
        $tooltip.Background='#23272F'; $tooltip.Foreground='#F3F5F7'; $tooltip.BorderBrush='#343A44'
        $tooltip.Padding='12'; $tooltip.MaxWidth=360
        $tooltip.Content = New-Label ($app.Name + "`n`n" + $help) '#F3F5F7' 12
        $check.ToolTip = $tooltip
        [Windows.Automation.AutomationProperties]::SetName($check,$app.Name)
        [Windows.Automation.AutomationProperties]::SetHelpText($check,$help)
        $content = New-Object Windows.Controls.StackPanel
        $name = New-Label $app.Name '#F3F5F7' 14
        $name.FontWeight = 'SemiBold'; $name.Height = 36; $name.LineHeight = 18
        $name.LineStackingStrategy = 'BlockLineHeight'
        $name.TextTrimming = 'CharacterEllipsis'; $name.Margin = '0,0,0,4'
        $content.Children.Add($name) | Out-Null
        $categoryLabel = New-Label $app.Category '#C2CADE' 11
        $categoryLabel.TextWrapping = 'NoWrap'; $categoryLabel.TextTrimming = 'CharacterEllipsis'
        $content.Children.Add($categoryLabel) | Out-Null
        $mode = if ($app.Ids.Count) { 'Automatic' } else { 'Guided install ↗' }
        $badge = New-Label $mode '#C2CADE' 11; $badge.Margin = '0,4,0,0'
        $content.Children.Add($badge) | Out-Null
        $check.Content = $content
        $check.Add_Click({
            param($sender,$eventArgs)
            if ($script:syncing -or $script:busy) { return }
            $key = [string]$sender.Tag
            if ($sender.IsChecked) {
                foreach ($item in @(Get-Plan @($key))) { $selected[$item.Key] = $true }
            } else {
                $selected.Remove($key)
                foreach ($item in $catalog) { if ($item.Requires -contains $key) { $selected.Remove($item.Key) } }
            }
            Update-Selection
            Animate-CardClick $sender
        })
        $checks[$app.Key] = $check; $ui.Cards.Children.Add($check) | Out-Null
    }
    $categoryButtons=New-Object 'System.Collections.Generic.List[object]'
    $categoryGroups=@{}
    foreach ($group in @('All apps','Everyday','Create','Files & Storage','PC & Tools')) {
        $categoryPanel=$ui.Categories
        $groupCategories=@('All apps')
        if ($group -ne 'All apps') {
            $categoryPanel=New-Object Windows.Controls.StackPanel
            $expander=New-Object Windows.Controls.Expander
            $expander.Header=$group; $expander.Content=$categoryPanel
            $expander.Style=$window.Resources['CategoryGroup']
            $expander.Add_Expanded({ param($sender,$eventArgs)
                foreach ($other in $categoryGroups.Values) { if ($other -ne $sender) { $other.IsExpanded=$false } }
            })
            $expander.Foreground='#DCE1E7'; $expander.Margin='0,4,0,4'; $expander.MinHeight=32
            $expander.IsExpanded=$false
            [Windows.Automation.AutomationProperties]::SetName($expander,$group+' categories')
            $categoryGroups[$group]=$expander
            $ui.Categories.Children.Add($expander) | Out-Null
            $groupCategories=@($catalog | Where-Object { $_.CategoryGroup -eq $group } | ForEach-Object { $_.Category } | Sort-Object -Unique)
        }
        foreach ($cat in $groupCategories) {
        $button = New-Object Windows.Controls.Button
        $button.Content = New-Label $(if ($cat -eq $category) { '› ' + $cat } else { $cat }) '#DCE1E7' 12
        Enable-HoverMotion $button
        $button.Tag = $cat; $button.Margin = '0,0,0,3'
        $button.Padding = '8,8'; $button.HorizontalContentAlignment = 'Left'
        if ($cat -eq $category) { $button.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentSurfaceBrush') } else { $button.Background='Transparent' }
        $button.BorderThickness = '1'; $button.BorderBrush = 'Transparent'
        $button.Add_Click({
            param($sender,$eventArgs)
            $script:category = [string]$sender.Tag
            foreach ($b in $categoryButtons) { $b.Content.Text = if ($b.Tag -eq $script:category) { '› ' + $b.Tag } else { $b.Tag }; if ($b.Tag -eq $script:category) { $b.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentSurfaceBrush') } else { $b.Background='Transparent' } }
            Update-Filter
            $ui.LibraryScroll.ScrollToTop()
        })
        $categoryButtons.Add($button)
        $categoryPanel.Children.Add($button) | Out-Null
        }
    }
    $ui.Search.Add_TextChanged({ Update-Filter })
    $ui.ClearSearch.Add_Click({ $ui.Search.Clear(); $ui.Search.Focus() | Out-Null })
    $window.Add_PreviewKeyDown({
        param($sender,$e)
        if ($e.Key -eq 'F' -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) {
            $searchBox=if ($script:mode -eq 'Uninstall') { $ui.InstalledSearch } else { $ui.Search }; $searchBox.Focus() | Out-Null; $searchBox.SelectAll(); $e.Handled=$true
        }
    })
    $ui.ClearSelection.Add_Click({ Set-Selection @() })
    function Apply-Profile([string]$Key) {
        if ($script:busy) { return }
        $profile=$profilesByKey[$Key]
        Set-Selection @($profile.Apps)
        $ui.Status.Text=$profile.Name + ' profile applied. Review your apps before installing.'
    }
    $profileItems=@{}
    $profileMenu=New-Object Windows.Controls.ContextMenu
    $profileMenu.Resources=$window.Resources
    $profileMenu.PlacementTarget=$ui.Profiles; $profileMenu.Placement='Bottom'
    $profileMenu.MaxHeight=[Math]::Min(640,[Math]::Max(300,[Windows.SystemParameters]::WorkArea.Height-100))
    foreach ($group in @('Everyday & Work','Create','Files & Privacy','PC & Tools')) {
        if ($profileMenu.Items.Count) { $profileMenu.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null }
        $heading=New-Object Windows.Controls.MenuItem; $heading.Header=$group; $heading.IsEnabled=$false; $heading.FontWeight='SemiBold'; $heading.FontSize=11; $heading.Padding='10,6'
        $profileMenu.Items.Add($heading) | Out-Null
        foreach ($profile in @($profiles | Where-Object { $_.Group -eq $group })) {
            $plan=@(Get-Plan @($profile.Apps))
            $item=New-Object Windows.Controls.MenuItem; $item.Header=$profile.Name+' ('+$plan.Count+' apps)'; $item.Tag=$profile.Key; $item.Padding='10,6'
            $tip=New-Label ($profile.Description+"`n`n"+($plan.Name -join ', ')) '#F3F5F7' 12; $tip.MaxWidth=420; $item.ToolTip=$tip
            [Windows.Automation.AutomationProperties]::SetName($item,$profile.Name+' profile, '+$plan.Count+' apps')
            $item.Add_Click({ param($sender,$eventArgs) Apply-Profile ([string]$sender.Tag); $profileMenu.IsOpen=$false })
            $profileItems[$profile.Key]=$item; $profileMenu.Items.Add($item) | Out-Null
        }
    }
    $profileMenu.Add_Opened({ Animate-Appearance $profileMenu 3 })
    $ui.Profiles.ToolTip='Choose a profile to select its apps. Review and adjust before installing.'
    $ui.Profiles.Add_Click({ $profileMenu.IsOpen=$true })
    $userProfileMenu=New-Object Windows.Controls.ContextMenu
    $userProfileMenu.Resources=$window.Resources
    $userProfileMenu.PlacementTarget=$ui.UserProfiles
    $userProfileMenu.Placement='Bottom'
    $userProfileMenu.Add_Opened({ Animate-Appearance $userProfileMenu 3 })
    foreach ($action in @(@('Export','Save current selection...'),@('Import','Load saved profile...'))) {
        $item=New-Object Windows.Controls.MenuItem
        $item.Header=$action[1]
        $ui[$action[0]]=$item
        $userProfileMenu.Items.Add($item) | Out-Null
    }
    $ui.UserProfiles.Add_Click({
        $ui.Export.IsEnabled=($selected.Count -gt 0)
        $userProfileMenu.IsOpen=$true
    })
    function Save-UserProfile([string]$Path) {
        if ($selected.Count -eq 0) { throw 'Select at least one app before saving a profile.' }
        @{Version=1; Apps=@($catalog | Where-Object { $selected.ContainsKey($_.Key) } | ForEach-Object { $_.Key })} | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop
    }
    function Load-UserProfile([string]$Path) {
        if ((Get-Item -LiteralPath $Path -ErrorAction Stop).Length -gt 65536) { throw 'The profile file is too large.' }
        $savedProfile=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($savedProfile.Version -ne 1 -or $null -eq $savedProfile.Apps) { throw 'Invalid profile.' }
        $plan=@(Get-Plan @($savedProfile.Apps))
        Set-Selection @($plan | ForEach-Object { $_.Key })
        $ui.Status.Text='User profile loaded. Review your apps before installing.'
    }
    $ui.OpenLogs.Add_Click({ Start-Process explorer.exe -ArgumentList ('"{0}"' -f $logDir) })
    $saveProfileAction={
        $dialog = New-Object Microsoft.Win32.SaveFileDialog
        $dialog.Filter = '1nstall profile (*.json)|*.json'; $dialog.FileName = 'my-setup.json'
        if ($dialog.ShowDialog($window)) {
            try {
                Save-UserProfile $dialog.FileName
                Add-Log 'Profile saved.'
            } catch { [Windows.MessageBox]::Show($window,$_.Exception.Message,'Could not save profile') | Out-Null }
        }
    }
    $ui.Export.Add_Click($saveProfileAction)
    $ui.SaveSetup.Add_Click($saveProfileAction)
    $ui.Import.Add_Click({
        $dialog = New-Object Microsoft.Win32.OpenFileDialog; $dialog.Filter = '1nstall profile (*.json)|*.json'
        if ($dialog.ShowDialog($window)) {
            try {
                Load-UserProfile $dialog.FileName
                Add-Log 'Profile imported.'
            } catch { [Windows.MessageBox]::Show($window,$_.Exception.Message,'Could not import profile') | Out-Null }
        }
    })
    function Confirm-Plan($Plan) {
        $dialog = New-Object Windows.Window
        $dialog.WindowStyle='SingleBorderWindow'
        $dialog.Add_SourceInitialized({ [FirstInstallWindow]::Apply([Windows.Interop.WindowInteropHelper]::new($dialog).Handle) | Out-Null })
        $dialogChrome=New-Object Windows.Shell.WindowChrome
        $dialogChrome.CaptionHeight=48; $dialogChrome.ResizeBorderThickness='6'
        $dialogChrome.GlassFrameThickness='0'; $dialogChrome.UseAeroCaptionButtons=$false
        [Windows.Shell.WindowChrome]::SetWindowChrome($dialog,$dialogChrome)
        $dialog.Icon=$window.Icon; $dialog.Title='Review installation'; $dialog.Width=580; $dialog.Height=570; $dialog.Owner=$window
        $dialog.WindowStartupLocation='CenterOwner'; $dialog.Background='#101526'; $dialog.Foreground='#F3F5F7'
        $dialog.MinWidth=540; $dialog.MinHeight=540; $dialog.FontSize=13
        $dialog.FontFamily=$window.FontFamily; $dialog.Resources=$window.Resources
        $dock=New-Object Windows.Controls.DockPanel; $dock.Margin='20'
        $surface=New-Object Windows.Controls.Border; $surface.Style=$window.Resources['GlassPanel']; $surface.Margin='12'; $surface.Child=$dock; $dialog.Content=$surface
        $title=New-Label 'Ready to install?' '#F3F5F7' 23; $title.Margin='0,0,0,18'
        [Windows.Controls.DockPanel]::SetDock($title,'Top'); $dock.Children.Add($title) | Out-Null
        $bottom=New-Object Windows.Controls.StackPanel
        [Windows.Controls.DockPanel]::SetDock($bottom,'Bottom'); $dock.Children.Add($bottom) | Out-Null
        $info=New-Label 'Guided apps open their official websites for manual installation. For Peace, install Equalizer APO first, choose your audio device and follow any restart instructions before setting up Peace.' '#C2CADE' 12
        $info.Margin='0,16,0,16'; $bottom.Children.Add($info) | Out-Null
        $agree=New-Object Windows.Controls.CheckBox; $agree.Content='I accept the app licenses and WinGet source terms.'; $agree.Foreground='#F3F5F7'; $agree.Margin='0,0,0,16'
        $bottom.Children.Add($agree) | Out-Null
        $go=New-Object Windows.Controls.Button; $go.Content='Start installation'; $go.IsEnabled=$false; $go.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentBrush'); $go.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'AccentForegroundBrush')
        $agree.Add_Checked({ $go.IsEnabled=$true }); $agree.Add_Unchecked({ $go.IsEnabled=$false })
        $go.Add_Click({ $dialog.DialogResult=$true }); $bottom.Children.Add($go) | Out-Null
        $back=New-Object Windows.Controls.Button; $back.Content='Back'; $back.IsCancel=$true; $back.Margin='0,8,8,0'
        $back.Add_Click({ $dialog.DialogResult=$false }); $bottom.Children.Add($back) | Out-Null
        $scroll=New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility='Auto'
        $list=New-Object Windows.Controls.StackPanel; $scroll.Content=$list
        foreach ($app in $Plan) {
            $mode=if ($app.Ids.Count) { 'Automatic' } else { 'Guided' }
            $label=New-Label ($app.Name + '  ·  ' + $mode) '#D7DFE8' 14; $label.Margin='0,5'
            $list.Children.Add($label) | Out-Null
        }
        $dock.Children.Add($scroll) | Out-Null
        if ($SmokeTest) {
            $dialog.Add_ContentRendered({
                if ($agree.IsChecked -or $go.IsEnabled) { throw 'Installation must require explicit consent.' }
                if ([Windows.Shell.WindowChrome]::GetWindowChrome($dialog).GlassFrameThickness.Top -ne 0) { throw 'Review dialog chrome mismatch.' }
                if ($PreviewPath) {
                    $image=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$dialog.ActualWidth,[int]$dialog.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                    $image.Render($dialog)
                    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
                    $stream=[IO.File]::Create([IO.Path]::ChangeExtension($PreviewPath,'review.png'))
                    try { $encoder.Save($stream) } finally { $stream.Dispose() }
                }
                $dialog.DialogResult=$false
            })
        }
        return $dialog.ShowDialog() -eq $true
    }
    $worker = {
        param($Plan,$Winget,$Events,$Control,$LogDir)
        $ErrorActionPreference='Stop'
        function Emit($Type,$Key,$Text) { $Events.Enqueue(@{Type=$Type;Key=$Key;Text=$Text}) }
        try {
            foreach ($app in $Plan) {
                if ($Control.Stop) { break }
                Emit 'status' $app.Key 'Preparing…'
                if ($app.Url) {
                    Emit 'url' $app.Key $app.Url
                    Emit 'status' $app.Key 'Manual install pending · official website'
                    Emit 'progress' $app.Key ''
                    continue
                }
                $failed=$false; $restart=$false; $allExisting=$true
                foreach ($id in $app.Ids) {
                    Emit 'status' $app.Key ('Installing ' + $id + '…')
                    $out=Join-Path $LogDir (([guid]::NewGuid().ToString('N'))+'.out.log')
                    $err=$out+'.err.log'
                    try {
                        # All arguments come from the embedded catalogue, never from imported profiles.
                        $arguments=@('install','--id',$id,'--exact','--source','winget','--no-upgrade','--accept-source-agreements','--accept-package-agreements','--disable-interactivity')
                        $process=Start-Process -FilePath $Winget -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
                        $null=$process.Handle
                        $process.WaitForExit()
                        $code=$process.ExitCode
                        $process.Dispose()
                        foreach ($path in @($out,$err)) {
                            if (Test-Path -LiteralPath $path) { Emit 'log' $app.Key (Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue) }
                        }
                        $hex='{0:X8}' -f ([long]$code -band 4294967295)
                        if ($code -eq 0) { $allExisting=$false }
                        elseif ($hex -eq '8A15002B') { }
                        elseif ($code -eq 3010) { $restart=$true; $allExisting=$false }
                        else { $failed=$true; Emit 'log' $app.Key ("$id : code $code / 0x$hex") }
                    } catch { $failed=$true; Emit 'log' $app.Key $_.Exception.Message }
                }
                $state=if ($failed) { 'Failed · see logs' } elseif ($restart) { 'Completed · restart required' } elseif ($allExisting) { 'Already installed / no upgrade' } else { 'Completed' }
                Emit 'status' $app.Key $state
                Emit 'progress' $app.Key ''
            }
        } catch { Emit 'error' '' $_.Exception.Message }
        finally { Emit 'done' '' '' }
    }
    function Set-Busy([bool]$Value) {
        $script:busy=$Value
        foreach ($name in @('UserProfiles','Profiles','ClearSelection','Import','UninstallMode')) { $ui[$name].IsEnabled = -not $Value }
        if ($Value) { $profileMenu.IsOpen=$false; $userProfileMenu.IsOpen=$false }
        foreach ($check in $checks.Values) { $check.IsEnabled = -not $Value }
        $ui.Cancel.Visibility=if ($Value) { 'Visible' } else { 'Collapsed' }
        $ui.Cancel.IsEnabled=$Value
        Update-Selection
    }
    $ui.Install.Add_Click({
        if ($script:busy) { return }
        $plan=@(Get-Plan @($catalog | Where-Object { $selected.ContainsKey($_.Key) } | ForEach-Object { $_.Key }))
        if (-not $plan.Count -or -not (Confirm-Plan $plan)) { return }
        if (-not $winget -and @($plan | Where-Object { $_.Ids.Count -gt 0 }).Count) {
            [Windows.MessageBox]::Show($window,'Install or update App Installer in the Microsoft Store, then reopen 1nstall.','WinGet missing') | Out-Null
            Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'
            return
        }
        $script:events=New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        $script:control=[hashtable]::Synchronized(@{Stop=$false})
        $script:total=$plan.Count; $script:completed=0
        $statuses.Clear(); foreach ($app in $plan) { $statuses[$app.Key]='Queued' }
        Set-QueueProgress 0; $ui.Status.Text='Installation in progress…'
        Set-Busy $true
        try {
            $script:job=[PowerShell]::Create()
            $null=$script:job.AddScript($worker.ToString()).AddArgument($plan).AddArgument($winget).AddArgument($script:events).AddArgument($script:control).AddArgument($logDir)
            $script:async=$script:job.BeginInvoke()
            $timer.Start()
            Add-Log ('Queue started: ' + ($plan.Name -join ', '))
        } catch {
            Add-Log $_.Exception.Message
            if ($script:job) { $script:job.Dispose(); $script:job=$null }
            $timer.Stop()
            Set-Busy $false
            $ui.Status.Text='Could not start. See the logs for details.'
        }
    })
    $ui.Cancel.Add_Click({
        if ($script:busy) { $script:control.Stop=$true; $ui.Cancel.IsEnabled=$false; $ui.Status.Text='Stopping after the current app.'; Add-Log 'Stop requested. Waiting for the current installer.' }
    })
    $timer=New-Object Windows.Threading.DispatcherTimer
    $timer.Interval=[TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if (-not $script:job) { return }
        $event=$null
        while ($script:events.TryDequeue([ref]$event)) {
            switch ($event.Type) {
                'status' { Set-AppStatus $event.Key $event.Text }
                'log' { if ($event.Text) { Add-Log $event.Text } }
                'error' { Add-Log $event.Text; $ui.Status.Text='Something went wrong. See the logs for details.' }
                'url' {
                    try { Start-Process $event.Text }
                    catch { Add-Log ('Could not open: ' + $event.Text) }
                }
                'progress' { $script:completed++; Set-QueueProgress (100*$script:completed/$script:total); $ui.Status.Text="$script:completed of $script:total processed" }
            }
        }
        if ($script:async.IsCompleted -and $script:events.IsEmpty) {
            $timer.Stop()
            try { $script:job.EndInvoke($script:async) | Out-Null; foreach ($err in $script:job.Streams.Error) { Add-Log $err.ToString() } }
            catch { Add-Log $_.Exception.Message }
            $script:job.Dispose(); $script:job=$null
            foreach ($key in @($statuses.Keys)) { if ($statuses[$key] -eq 'Queued') { $statuses[$key]='Not started' } elseif ($statuses[$key] -like 'Installing*' -or $statuses[$key] -like 'Preparing*') { $statuses[$key]='Failed · operation interrupted' } }
            $failed=@($statuses.Values | Where-Object { $_ -like 'Failed*' }).Count
            $manual=@($statuses.Values | Where-Object { $_ -like 'Manual*' }).Count
            $ui.Status.Text="Queue finished · $failed failed · $manual manual installs pending."
            if ($script:control.Stop) { $ui.Status.Text='Queue stopped after the current app. Review the results.' }
            Set-Busy $false
        }
    })
    function Update-CardLayout {
        $available=$ui.LibraryScroll.ViewportWidth
        if ($available -le 0 -or [double]::IsInfinity($available)) { return }
        # Use the measured viewport, never the size of the children being resized.
        # One spare DIP per slot avoids an extra wrap at fractional display scaling.
        $columns=[Math]::Max(1,[Math]::Min(6,[Math]::Floor(($available+8)/192)))
        $slot=[Math]::Floor($available/$columns)-1
        $ui.Cards.ItemWidth=$slot
        foreach ($check in $checks.Values) { $check.Width=[Math]::Max(100,$slot-8) }
    }
    $ui.LibraryScroll.Add_ScrollChanged({
        param($sender,$scrollEvent)
        if ($scrollEvent.ViewportWidthChange -ne 0) { Update-CardLayout }
    })
    $window.Add_Loaded({ Update-CardLayout })
    $window.Add_Closing({
        param($sender,$eventArgs)
        if ($script:busy) {
            $eventArgs.Cancel=$true
            $script:control.Stop=$true
            $ui.Status.Text='Wait for the current installer to finish, then close this window.'
            $ui.Cancel.IsEnabled=$false
        }
    })
    $script:mode='Install'
    $script:installedApps=@()
    $script:installedKind='All'
    $script:uninstallTask=$null
    $script:uninstallOperation=''
    $script:uninstallOutcome=''
    $script:uninstallTargets=@([OneInstallUninstall]::LoadHistory())
    $script:removalDialog=$null
    $uninstallTimer=New-Object Windows.Threading.DispatcherTimer
    $uninstallTimer.Interval=[TimeSpan]::FromMilliseconds(200)
    function Add-UninstallLog([string]$Text) {
        $line='[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'),$Text
        $ui.UninstallLog.AppendText($line+"`r`n"); $ui.UninstallLog.ScrollToEnd()
        try { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 } catch { }
    }
    function Update-UninstallSelection {
        $count=@($script:installedApps | Where-Object { $_.Selected -and $_.CanRemove }).Count
        $ui.UninstallSelectedCount.Text="$count $(if ($count -eq 1) { 'app' } else { 'apps' }) selected"
        $ui.ReviewUninstall.IsEnabled=($count -gt 0 -and -not $script:uninstallTask)
        $ui.ClearUninstallSelection.IsEnabled=($count -gt 0 -and -not $script:uninstallTask)
        $ui.CheckLeftovers.IsEnabled=($script:uninstallTargets.Count -gt 0 -and -not $script:uninstallTask)
    }
    function Update-InstalledFilter {
        $query=$ui.InstalledSearch.Text.Trim()
        $matches=@($script:installedApps | Where-Object {
            ($script:installedKind -eq 'All' -or $_.Kind -eq $script:installedKind) -and
            ($_.Name+' '+$_.Publisher).IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $ui.InstalledList.ItemsSource=$matches
        $ui.InstalledEmpty.Text=if ($script:uninstallTask -and $script:uninstallOperation -eq 'Inventory') { 'Reading installed apps…' } else { 'No apps found. Try another search or choose Refresh.' }
        $ui.InstalledEmpty.Visibility=if ($matches.Count -eq 0) { 'Visible' } else { 'Collapsed' }
        if ($script:mode -eq 'Uninstall') { $ui.ResultCount.Text='Installed · '+$matches.Count+' apps' }
        foreach ($name in @('InstalledAll','InstalledDesktop','InstalledStore')) {
            if ($ui[$name].Tag -eq $script:installedKind) { $ui[$name].SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentSurfaceBrush') }
            else { $ui[$name].SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'GlassControlFill') }
        }
    }
    function Set-UninstallTask($Task,[string]$Operation) {
        if ($script:uninstallTask) { throw 'A removal operation is already running.' }
        $script:uninstallTask=$Task; $script:uninstallOperation=$Operation
        foreach ($name in @('RefreshInstalled','InstalledList','InstallMode','ReviewUninstall','CheckLeftovers','ClearUninstallSelection')) { $ui[$name].IsEnabled=$false }
        $ui.StopUninstall.Visibility=if ($Operation -eq 'Remove') { 'Visible' } else { 'Collapsed' }
        $ui.StopUninstall.IsEnabled=$true
        $uninstallTimer.Start()
    }
    function Refresh-InstalledApps {
        if ($script:uninstallTask -or $SmokeTest) { return }
        $ui.UninstallStatus.Text='Reading desktop and Microsoft Store apps…'
        Set-UninstallTask ([OneInstallUninstall]::InventoryAsync()) 'Inventory'
        Update-InstalledFilter
    }
    function Start-LeftoverScan {
        $ui.UninstallStatus.Text='Checking removed apps and protecting shared folders...'
        Set-UninstallTask ([OneInstallUninstall]::ScanAsync([InstalledApp[]]$script:uninstallTargets)) 'Scan'
    }
    function Set-AppMode([string]$Mode) {
        if ($script:busy -or $script:uninstallTask) { return }
        $script:mode=$Mode; $uninstall=$Mode -eq 'Uninstall'
        $ui.InstallLibrary.Visibility=if ($uninstall) { 'Collapsed' } else { 'Visible' }
        $window.FindName('SetupGlass').Visibility=if ($uninstall) { 'Collapsed' } else { 'Visible' }
        $ui.CategoriesHost.Visibility=if ($uninstall) { 'Collapsed' } else { 'Visible' }
        $ui.UninstallNavigation.Visibility=if ($uninstall) { 'Visible' } else { 'Collapsed' }
        $ui.UninstallPage.Visibility=if ($uninstall) { 'Visible' } else { 'Collapsed' }
        $window.FindName('WindowControls').Margin=if ($uninstall) { '0,14,26,0' } else { '0,30,30,0' }
        $ui.NavigationHeading.Text=if ($uninstall) { 'THIS PC' } else { 'LIBRARY' }
        foreach ($name in @('InstallMode','UninstallMode')) {
            if ($name -eq $Mode+'Mode') { $ui[$name].SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentSurfaceBrush') }
            else { $ui[$name].Background='Transparent' }
        }
        if ($uninstall) {
            Update-InstalledFilter; Update-UninstallSelection
            if ($script:installedApps.Count -eq 0) { Refresh-InstalledApps }
        } else { Update-Filter }
    }
    function Show-RemovalReview($Items,[bool]$Leftovers=$false) {
        $dialog=New-Object Windows.Window; $script:removalDialog=$dialog
        $dialog.Title=if ($Leftovers) { 'Review leftovers · 1nstall' } else { 'Review removal · 1nstall' }
        $dialog.Width=760; $dialog.Height=[Math]::Min(660,[Windows.SystemParameters]::WorkArea.Height-40)
        $dialog.MinWidth=560; $dialog.MinHeight=450; $dialog.Owner=$window; $dialog.Icon=$window.Icon
        $dialog.WindowStartupLocation='CenterOwner'; $dialog.FontFamily=$window.FontFamily; $dialog.FontSize=13
        $chrome=New-Object Windows.Shell.WindowChrome; $chrome.CaptionHeight=24; $chrome.ResizeBorderThickness='6'; $chrome.GlassFrameThickness='0'; $chrome.UseAeroCaptionButtons=$false
        [Windows.Shell.WindowChrome]::SetWindowChrome($dialog,$chrome); $dialog.ShowInTaskbar=$false
        $dialog.Resources=$window.Resources; $dialog.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'OpaqueWindowFill'); $dialog.Foreground='#F3F5F7'
        $dialog.Add_SourceInitialized({ [FirstInstallWindow]::Apply([Windows.Interop.WindowInteropHelper]::new($dialog).Handle) | Out-Null })
        $dock=New-Object Windows.Controls.DockPanel; $dock.Margin='24'; $dialog.Content=$dock
        $head=New-Object Windows.Controls.StackPanel
        $head.Children.Add((New-Label $(if ($Leftovers) { 'Keep what matters' } else { 'Ready to make some room?' }) '#F3F5F7' 27)) | Out-Null
        $copy=if ($Leftovers) { 'Possible leftovers need your judgment. Product folders can contain settings, saves or personal app data. Choose only what you want to remove. Files go to the Recycle Bin; registry keys are backed up first.' } else { 'These apps will be removed one at a time using their own uninstallers. Finish any dialogs they open. Microsoft Store removal affects your current Windows account. Back up app data you want to keep.' }
        $note=New-Label $copy '#C2CADE' 13; $note.Margin='0,10,0,18'; $head.Children.Add($note) | Out-Null
        [Windows.Controls.DockPanel]::SetDock($head,'Top'); $dock.Children.Add($head) | Out-Null
        $bottom=New-Object Windows.Controls.StackPanel
        [Windows.Controls.DockPanel]::SetDock($bottom,'Bottom'); $dock.Children.Add($bottom) | Out-Null
        $agree=New-Object Windows.Controls.CheckBox; $agree.Style=$window.Resources['InstalledCheck']
        $agree.Content=New-Label $(if ($Leftovers) { 'I reviewed the selected paths and want to remove their contents.' } else { 'I reviewed this list and want to remove these apps and their app data.' })
        $agree.Margin='0,18,0,16'; $bottom.Children.Add($agree) | Out-Null
        $actions=New-Object Windows.Controls.StackPanel; $actions.Orientation='Horizontal'; $actions.HorizontalAlignment='Right'; $bottom.Children.Add($actions) | Out-Null
        $back=New-Object Windows.Controls.Button; $back.Content='Keep / go back'; $back.IsCancel=$true; $back.Add_Click({ $dialog.DialogResult=$false }); $actions.Children.Add($back) | Out-Null
        $go=New-Object Windows.Controls.Button; $go.Content=if ($Leftovers) { 'Remove selected leftovers' } else { 'Remove '+$Items.Count+' apps' }
        $go.IsEnabled=$false; $go.Margin='0'; $go.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentActionBrush'); $go.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'AccentForegroundBrush')
        $go.Add_Click({ $dialog.DialogResult=$true }); $actions.Children.Add($go) | Out-Null
        $scroll=New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility='Auto'; $scroll.HorizontalScrollBarVisibility='Disabled'
        $list=New-Object Windows.Controls.StackPanel; $scroll.Content=$list; $dock.Children.Add($scroll) | Out-Null
        if ($Leftovers) {
            $selectionBar=New-Object Windows.Controls.StackPanel; $selectionBar.Orientation='Horizontal'; $selectionBar.Margin='0,0,0,12'
            $selectAll=New-Object Windows.Controls.Button; $selectAll.Content='Select all'; $selectAll.Padding='12,6'
            $clearAll=New-Object Windows.Controls.Button; $clearAll.Content='Clear selection'; $clearAll.Padding='12,6'
            $selectAll.Add_Click({ foreach ($row in $list.Children) { $row.Child.IsChecked=$true } })
            $clearAll.Add_Click({ foreach ($row in $list.Children) { $row.Child.IsChecked=$false } })
            $selectionBar.Children.Add($selectAll) | Out-Null; $selectionBar.Children.Add($clearAll) | Out-Null
            $head.Children.Add($selectionBar) | Out-Null
        }
        foreach ($entry in $Items) {
            $surface=New-Object Windows.Controls.Border; $surface.Background=$window.Resources['ContentFill']; $surface.BorderBrush=$window.Resources['CardEdge']; $surface.BorderThickness='1'; $surface.CornerRadius='16'; $surface.Padding='16'; $surface.Margin='0,0,8,10'
            $labels=New-Object Windows.Controls.StackPanel; $surface.Child=$labels
            $name=if ($Leftovers) { $entry.AppName+' · '+$entry.Kind } else { $entry.Name }
            $title=New-Label $name '#F3F5F7' 15; $title.FontWeight='SemiBold'; $labels.Children.Add($title) | Out-Null
            $detail=if ($Leftovers) { $(if ($entry.Kind -eq 'Registry') { $(if ($entry.Machine) { 'HKLM' } else { 'HKCU' })+' · '+$(if ($entry.View32) { '32-bit' } else { '64-bit' })+' · ' } else { '' })+$entry.Detail } else { $entry.Detail }
            $subtitle=New-Label $detail '#C2CADE' 12; $subtitle.Margin='0,7,0,0'; $labels.Children.Add($subtitle) | Out-Null
            if ($Leftovers) {
                $check=New-Object Windows.Controls.CheckBox; $check.Style=$window.Resources['InstalledCheck']; $check.Content=$labels; $check.Tag=$entry; $surface.Child=$check
                $entry.Selected=$false
                $check.Add_Checked({ param($sender,$eventArgs) $sender.Tag.Selected=$true; $go.IsEnabled=$agree.IsChecked -and @($Items | Where-Object Selected).Count -gt 0 })
                $check.Add_Unchecked({ param($sender,$eventArgs) $sender.Tag.Selected=$false; $go.IsEnabled=$agree.IsChecked -and @($Items | Where-Object Selected).Count -gt 0 })
            }
            $list.Children.Add($surface) | Out-Null
        }
        $agree.Add_Checked({ $go.IsEnabled=(-not $Leftovers -or @($Items | Where-Object Selected).Count -gt 0) })
        $agree.Add_Unchecked({ $go.IsEnabled=$false })
        if ($SmokeTest) {
            $dialog.Add_ContentRendered({
                if ($go.IsEnabled -or $agree.IsChecked -or ($Leftovers -and @($Items | Where-Object Selected).Count -gt 0)) { throw 'Removal review does not require fresh consent.' }
                if ($Leftovers) {
                    $selectAll.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                    if (@($Items | Where-Object Selected).Count -ne $Items.Count -or $go.IsEnabled -or $agree.IsChecked) { throw 'Select all failed or bypassed cleanup consent.' }
                    $agree.IsChecked=$true
                    if (-not $go.IsEnabled) { throw 'Selected leftovers cannot proceed after consent.' }
                    $clearAll.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                    if (@($Items | Where-Object Selected).Count -gt 0 -or $go.IsEnabled) { throw 'Clear leftovers selection did not disable cleanup.' }
                    $agree.IsChecked=$false
                    $check=$list.Children[0].Child; $check.IsChecked=$true
                    if ($go.IsEnabled) { throw 'Leftover selection bypassed review consent.' }
                    $agree.IsChecked=$true
                    if (-not $go.IsEnabled) { throw 'Reviewed leftover selection cannot proceed.' }
                    $check.IsChecked=$false
                    if ($go.IsEnabled) { throw 'Empty leftover removal was enabled.' }
                    $agree.IsChecked=$false
                }
                if ($PreviewPath) {
                    $image=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$dialog.ActualWidth,[int]$dialog.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                    $image.Render($dialog); $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
                    $stream=[IO.File]::Create([IO.Path]::ChangeExtension($PreviewPath,$(if ($Leftovers) { 'leftovers.png' } else { 'removal.png' }))); try { $encoder.Save($stream) } finally { $stream.Dispose() }
                }
                $dialog.DialogResult=$false
            })
        }
        return $dialog.ShowDialog() -eq $true
    }
    $uninstallTimer.Add_Tick({
        $message=''
        while ([OneInstallUninstall]::Progress.TryDequeue([ref]$message)) { $ui.UninstallStatus.Text=$message; Add-UninstallLog $message }
        if (-not $script:uninstallTask -or -not $script:uninstallTask.IsCompleted) { return }
        $uninstallTimer.Stop()
        $operation=$script:uninstallOperation; $task=$script:uninstallTask
        $script:uninstallTask=$null
        foreach ($name in @('RefreshInstalled','InstalledList','InstallMode')) { $ui[$name].IsEnabled=$true }
        $ui.StopUninstall.Visibility='Collapsed'
        try {
            if ($task.IsFaulted) { throw $task.Exception.GetBaseException().Message }
            $result=$task.Result
            if ($operation -eq 'Inventory') {
                $script:installedApps=@($result.Apps)
                foreach ($message in $result.Warnings) { Add-UninstallLog $message }
                $ui.UninstallStatus.Text=if ($script:uninstallOutcome) { $script:uninstallOutcome } else { $installedApps.Count.ToString()+' installed apps · '+$result.Warnings.Count+' scan warnings. Review details in Removal activity.' }
                Update-InstalledFilter
            } else {
                foreach ($message in $result.Messages) { Add-UninstallLog $message }
                if ($operation -eq 'Remove') {
                    $script:uninstallTargets=@([OneInstallUninstall]::LoadHistory())
                    Start-LeftoverScan
                } elseif ($operation -eq 'Scan') {
                    $items=@($result.Leftovers)
                    $diskCount=@($items | Where-Object Kind -eq 'Folder').Count
                    $registryCount=@($items | Where-Object Kind -eq 'Registry').Count
                    $script:uninstallOutcome=if ($items.Count -gt 0) { $items.Count.ToString()+" possible leftovers found ($diskCount disk / $registryCount registry). Review paths before removal." } else { 'No leftovers found (0 disk / 0 registry) in the checked locations. See Removal activity for scan details.' }
                    $ui.UninstallStatus.Text=$script:uninstallOutcome
                    Add-UninstallLog $script:uninstallOutcome
                    if ($items.Count -gt 0 -and (Show-RemovalReview $items $true)) {
                        $chosen=[LeftoverItem[]]@($items | Where-Object Selected)
                        if ($chosen.Count -gt 0) { Set-UninstallTask ([OneInstallUninstall]::CleanAsync($chosen)) 'Clean' }
                    }
                    if (-not $script:uninstallTask) { Refresh-InstalledApps }
                } elseif ($operation -eq 'Clean') {
                    Add-UninstallLog ('Backups and item record: '+$result.BackupFolder)
                    $script:uninstallOutcome='Cleanup finished. Review item results in Removal activity. Registry backups are available in Open backups.'
                    $ui.UninstallStatus.Text=$script:uninstallOutcome
                    Refresh-InstalledApps
                }
            }
        } catch { Add-UninstallLog $_.Exception.Message; $ui.UninstallStatus.Text='Could not complete this step. Review Removal activity and try again.' }
        Update-UninstallSelection
    })
    $ui.InstallMode.Add_Click({ Set-AppMode 'Install' })
    $ui.UninstallMode.Add_Click({ Set-AppMode 'Uninstall' })
    $ui.RefreshInstalled.Add_Click({ Refresh-InstalledApps })
    $ui.WindowsAppsSettings.Add_Click({ Start-Process 'ms-settings:appsfeatures' })
    $ui.InstalledSearch.Add_TextChanged({ Update-InstalledFilter })
    foreach ($name in @('InstalledAll','InstalledDesktop','InstalledStore')) {
        $ui[$name].Add_Click({ param($sender,$eventArgs) $script:installedKind=[string]$sender.Tag; Update-InstalledFilter })
    }
    $ui.InstalledList.AddHandler([Windows.Controls.Primitives.ToggleButton]::CheckedEvent,[Windows.RoutedEventHandler]{ Update-UninstallSelection })
    $ui.InstalledList.AddHandler([Windows.Controls.Primitives.ToggleButton]::UncheckedEvent,[Windows.RoutedEventHandler]{ Update-UninstallSelection })
    $ui.ClearUninstallSelection.Add_Click({ foreach ($app in $script:installedApps) { $app.Selected=$false }; Update-UninstallSelection })
    $ui.ReviewUninstall.Add_Click({
        if ($script:uninstallTask -or $SmokeTest) { return }
        $plan=[InstalledApp[]]@($script:installedApps | Where-Object { $_.Selected -and $_.CanRemove })
        if ($plan.Count -gt 0 -and (Show-RemovalReview $plan)) { $script:uninstallOutcome=''; Set-UninstallTask ([OneInstallUninstall]::RemoveAsync($plan)) 'Remove' }
    })
    $ui.StopUninstall.Add_Click({ [OneInstallUninstall]::StopRequested=$true; $ui.StopUninstall.IsEnabled=$false; $ui.UninstallStatus.Text='Waiting for the current uninstaller. The next app will be kept.' })
    $ui.CheckLeftovers.Add_Click({
        if ($script:uninstallTask -or $SmokeTest -or $script:uninstallTargets.Count -eq 0) { return }
        Start-LeftoverScan
    })
    $ui.OpenUninstallBackups.Add_Click({
        $folder=Join-Path $env:LOCALAPPDATA '1nstall\Backups'; New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Start-Process explorer.exe -ArgumentList ('"{0}"' -f $folder)
    })
    $window.Add_Closing({ param($sender,$eventArgs)
        if ($script:uninstallTask) {
            $eventArgs.Cancel=$true; [OneInstallUninstall]::StopRequested=$true
            $ui.UninstallStatus.Text='Wait for the current removal/check to finish, then close this window.'
        }
    })
    $window.Add_Closed({ $uninstallTimer.Stop() })
    Set-AppMode 'Install'

    Update-Selection; Update-Filter
    if ($SmokeTest) {
        if ($category -ne 'All apps' -or @($categoryGroups.Values | Where-Object IsExpanded).Count -ne 0 -or $ui.Cards.Children.Count -ne $catalog.Count) { throw 'Startup must show All apps with every category group closed.' }
        Set-GlassAppearance $false
        $window.UpdateLayout()
        foreach ($name in @('NavigationGlass','SetupGlass')) {
            $pane=$window.FindName($name)
            if ($pane.Background -isnot [Windows.Media.SolidColorBrush] -or $pane.Background.Color.A -ne 255 -or $pane.Effect) { throw 'Opaque glass fallback failed.' }
        }
        if ($window.FindName('AmbientLight').Visibility -ne 'Collapsed' -or $ui.Profiles.Background.Color.A -ne 255) { throw 'Transparency fallback did not reach controls and background.' }
        Set-GlassAppearance $true
        $window.UpdateLayout()
        if ($window.Resources['GlassPanelFill'] -isnot [Windows.Media.LinearGradientBrush] -or $window.FindName('AmbientLight').Visibility -ne 'Visible') { throw 'Glass appearance did not restore.' }
        Update-WindowsAccent
        foreach ($app in $catalog) {
            $card=$checks[$app.Key]
            if ($card.MinHeight -ne 104 -or $card.Content.Children.Count -ne 3 -or
                [Windows.Automation.AutomationProperties]::GetName($card) -ne $app.Name -or
                -not [Windows.Automation.AutomationProperties]::GetHelpText($card).Contains($app.Description) -or
                -not $card.ToolTip.Content.Text.Contains($app.LicenseLabel)) { throw 'Compact card lost app details or accessibility.' }
        }
        Set-Selection @('peace','ts3')
        if ($selected.Count -ne 3) { throw 'Selection did not add the dependency.' }
        $queueRow=$ui.QueuePanel.Children[0]
        $statusLabel=$script:statusLabels[[string]$queueRow.Tag]
        Set-AppStatus ([string]$queueRow.Tag) 'Preparing…'
        Set-AppStatus ([string]$queueRow.Tag) 'Completed'
        if (-not [object]::ReferenceEquals($queueRow,$ui.QueuePanel.Children[0]) -or
            -not [object]::ReferenceEquals($statusLabel,$script:statusLabels[[string]$queueRow.Tag]) -or
            $statusLabel.Text -ne 'Completed' -or $statuses[[string]$queueRow.Tag] -ne 'Completed' -or
            $selected.Count -ne 3 -or -not $checks['peace'].IsChecked) { throw 'Status update rebuilt the queue or changed selection.' }
        if ($timer.IsEnabled) { throw 'Queue timer is running while idle.' }
        $ui.Search.Text='TeamSpeak'
        if ($checks['ts3'].Visibility -ne 'Visible' -or $checks['apo'].Visibility -ne 'Collapsed') { throw 'Invalid search results.' }
        $ui.ClearSearch.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($ui.Search.Text -ne '' -or $selected.Count -ne 3) { throw 'Clearing search changed the selection.' }
        Apply-Profile 'gaming'
        if ($selected.Count -ne $profilesByKey['gaming'].Apps.Count -or -not $selected.ContainsKey('app3') -or -not $selected.ContainsKey('extra_playnite')) { throw 'Invalid Gaming profile.' }
        foreach ($sample in @('#0078D4','#D13438','#001020','#FFFF99')) {
            Set-AccentPalette ([Windows.Media.ColorConverter]::ConvertFromString($sample))
            if ($ui.Install.Background.GradientStops[1].Color.ToString() -ne ('#FF'+$sample.Substring(1))) { throw 'Accent did not update the primary button.' }
            $fgLum=Get-Luminance $ui.Install.Foreground.Color
            foreach ($stop in $ui.Install.Background.GradientStops) {
                $lum=Get-Luminance $stop.Color
                if (([Math]::Max($lum,$fgLum)+0.05)/([Math]::Min($lum,$fgLum)+0.05) -lt 4.5) { throw 'Insufficient accent button contrast.' }
            }
        }
        Update-WindowsAccent
        if ($ui.Install.Background.GradientStops[1].Color -ne (Get-WindowsAccent)) { throw 'Windows accent mismatch.' }
        Set-Selection @('affinity','peace','extra_vlc')
        $ui.Search.Text='LocalSend'
        $script:removeButtons['affinity'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($selected.ContainsKey('affinity') -or $checks['affinity'].IsChecked -or $ui.Search.Text -ne 'LocalSend') { throw 'Setup removal did not preserve the filtered view.' }
        $script:removeButtons['apo'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($selected.ContainsKey('peace') -or $selected.ContainsKey('apo') -or $selected.Count -ne 1) { throw 'Setup removal left a broken dependency.' }
        Set-Busy $true
        if ($ui.SaveSetup.IsEnabled -or $script:removeButtons['extra_vlc'].IsEnabled) { throw 'Setup actions enabled while installing.' }
        Set-Busy $false
        Set-Selection @()
        if ($ui.SaveSetup.IsEnabled) { throw 'Empty setup can be saved.' }
        $ui.Search.Text=''
        $testProfile=Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString()+'.json')
        try {
            Set-Selection @('peace','ts3')
            Save-UserProfile $testProfile
            Set-Selection @('extra_vlc')
            Load-UserProfile $testProfile
            if ($selected.Count -ne 3 -or -not $selected.ContainsKey('peace') -or -not $selected.ContainsKey('apo') -or -not $selected.ContainsKey('ts3')) { throw 'User profile round trip failed.' }
            '{"Version":1,"Apps":["unknown-app"]}' | Set-Content -LiteralPath $testProfile
            $rejected=$false
            try { Load-UserProfile $testProfile } catch { $rejected=$true }
            if (-not $rejected -or $selected.Count -ne 3) { throw 'Invalid user profile changed selection.' }
        } finally { Remove-Item -LiteralPath $testProfile -ErrorAction SilentlyContinue }
        if ($window.FindName('Creator') -or $window.FindName('Gaming')) { throw 'Old profile shortcuts remain.' }
        if ($userProfileMenu.Items.Count -ne 2) { throw 'Missing user profile actions.' }
        foreach ($profile in $profiles) {
            Apply-Profile $profile.Key
            $expectedPlan=@(Get-Plan @($profile.Apps))
            if ($selected.Count -ne $expectedPlan.Count) { throw 'Profile did not replace the selection.' }
            foreach ($entry in $expectedPlan) { if (-not $selected.ContainsKey($entry.Key)) { throw 'Profile selection is incomplete.' } }
            if ($script:busy -or $script:job) { throw 'Applying a profile started an installation.' }
        }
        $ui.ClearSelection.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($selected.Count -ne 0 -or $ui.Install.IsEnabled) { throw 'Clearing selection did not disable installation.' }
        $checks['peace'].IsChecked=$true
        $checks['peace'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($selected.Count -ne 2 -or -not $selected.ContainsKey('apo')) { throw 'Selecting Peace did not add APO.' }
        $checks['apo'].IsChecked=$false
        $checks['apo'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($selected.Count -ne 0) { throw 'Removing APO did not remove Peace.' }
        $ui.Search.Text='LocalSend'
        if ($checks['extra_localsend'].Visibility -ne 'Visible' -or $checks['ts3'].Visibility -ne 'Collapsed') { throw 'New app search failed.' }
        $ui.Search.Clear()
        foreach ($button in $categoryButtons) {
            if ($button.Tag -eq 'Security & Privacy') { $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
        }
        if ($checks['extra_keepassxc'].Visibility -ne 'Visible' -or $checks['extra_vlc'].Visibility -ne 'Collapsed') { throw 'New category filter failed.' }
        foreach ($button in $categoryButtons) {
            if ($button.Tag -eq 'All apps') { $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
        }
        $window.Add_ContentRendered({
            function Wait-WindowMessages {
                $frame=New-Object Windows.Threading.DispatcherFrame
                $pulse=New-Object Windows.Threading.DispatcherTimer
                $pulse.Interval=[TimeSpan]::FromMilliseconds(100)
                $pulse.Add_Tick({ $pulse.Stop(); $frame.Continue=$false })
                $pulse.Start()
                [Windows.Threading.Dispatcher]::PushFrame($frame)
            }
            function Get-DrawnText($Drawing) {
                if ($Drawing -is [Windows.Media.GlyphRunDrawing]) { return (-join $Drawing.GlyphRun.Characters) }
                if ($Drawing -is [Windows.Media.DrawingGroup]) {
                    return (-join @($Drawing.Children | ForEach-Object { Get-DrawnText $_ }))
                }
            }
            $chrome=[Windows.Shell.WindowChrome]::GetWindowChrome($window)
            if ($window.WindowStyle -ne 'None' -or $chrome.CaptionHeight -ne 12 -or $chrome.GlassFrameThickness.Top -ne $(if ($script:nativeGlass) { -1 } else { 0 })) { throw 'Seamless window chrome not applied.' }
            $nativeFrameHandle=[Windows.Interop.WindowInteropHelper]::new($window).Handle
            if ([FirstInstallWindow]::ReadNativeFrameEnabled($nativeFrameHandle) -ne 0) { throw 'DWM native frame painting is still enabled.' }
            if ($window.FindName('WindowRim')) { throw 'Outer accent rim must be removed.' }
            if ($window.FontFamily.Source -notlike '*Segoe UI Variable Text*') { throw 'New body typography was not applied.' }
            foreach ($mode in @('Install','Uninstall')) {
                Set-AppMode $mode; Wait-WindowMessages; $window.Activate() | Out-Null
                $search=if ($mode -eq 'Install') { $ui.Search } else { $ui.InstalledSearch }
                $hint=$window.FindName($(if ($mode -eq 'Install') { 'SearchPlaceholder' } else { 'InstalledSearchPlaceholder' }))
                $search.Clear(); $ui.InstallMode.Focus() | Out-Null; Wait-WindowMessages
                if ($hint.Visibility -ne 'Visible') { throw 'Empty unfocused search needs its hint.' }
                $search.Focus() | Out-Null; Wait-WindowMessages
                if (-not $search.IsKeyboardFocusWithin -or $hint.Visibility -ne 'Collapsed') { throw 'Focused search hint must disappear.' }
                $search.Text='existing query'; $ui.InstallMode.Focus() | Out-Null; Wait-WindowMessages
                if ($hint.Visibility -ne 'Collapsed' -or $search.Text -ne 'existing query') { throw 'Search text must remain visible and unchanged.' }
                $search.Clear()
            }
            Set-AppMode 'Install'; Wait-WindowMessages
            $brand=$window.FindName('BrandHeader')
            if ($brand.Children.Count -ne 1 -or $brand.Children[0] -isnot [Windows.Controls.TextBlock] -or $brand.Children[0].Text -ne '1nstall') { throw 'Brand header must contain only the wordmark.' }
            if ((Get-DrawnText ([Windows.Media.VisualTreeHelper]::GetDrawing($window.FindName('SetupHeading')))) -ne 'Your setup') { throw 'Integrated window controls clipped the setup heading.' }
            if ($script:nativeGlass -and [FirstInstallWindow]::ReadBackdrop([Windows.Interop.WindowInteropHelper]::new($window).Handle) -ne 3) { throw 'Native Desktop Acrylic was not applied.' }
            Set-GlassAppearance $false
            if ($window.Resources['WindowFill'].Color.A -ne 255 -or $script:nativeGlass) { throw 'Native transparency did not become opaque.' }
            Set-GlassAppearance $true
            if ([FirstInstallWindow]::ReadNativeFrameEnabled($nativeFrameHandle) -ne 0) { throw 'DWM frame reappeared after changing transparency.' }
            $windowsBuild=[int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
            if ($windowsBuild -ge 22000 -and $script:cornerResult -ne 0) { throw "Windows 11 rounded-corner request failed: $script:cornerResult" }
            if ($script:cornerResult -eq 0 -and [FirstInstallWindow]::ReadCornerPreference([Windows.Interop.WindowInteropHelper]::new($window).Handle) -ne 2) { throw 'Native rounded-corner preference not applied.' }
            if ($ui.LibraryScroll.TranslatePoint([Windows.Point]::new(0,0),$window).Y -gt 160) { throw 'Library header is taking too much space.' }
            $originalWidth=$window.Width
            foreach ($testWidth in @(980,1060,1240,1500)) {
                $window.Width=$testWidth
                Wait-WindowMessages
                $window.UpdateLayout()
                Update-CardLayout
                $window.UpdateLayout()
                $visible=@($ui.Cards.Children | Where-Object { $_.Visibility -eq 'Visible' })
                $first=$visible[0].TranslatePoint([Windows.Point]::new(0,0),$ui.Cards)
                $second=$visible[1].TranslatePoint([Windows.Point]::new(0,0),$ui.Cards)
                if ([Math]::Abs($first.Y-$second.Y) -gt 1 -or $second.X -le $first.X) { throw "Grid collapsed to a list at width $testWidth." }
                if ($visible[1].ActualWidth -lt 170) { throw "Cards are too narrow at width $testWidth." }
                foreach ($runtime in @($catalog | Where-Object { $_.Name -like '.NET Desktop Runtime *' })) {
                    $title=$checks[$runtime.Key].Content.Children[0]
                    $drawn=Get-DrawnText ([Windows.Media.VisualTreeHelper]::GetDrawing($title))
                    if (($drawn -replace '\s','') -ne ($runtime.Name -replace '\s','')) { throw "Runtime version is hidden at width ${testWidth}: $($runtime.Name)." }
                }
                # Sample the rendered background, including the translucent layers.
                $image=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $image.Render($window)
                foreach ($label in @($ui.ResultCount,$ui.SelectedCount,$visible[0].Content.Children[1])) {
                    $point=$label.TranslatePoint([Windows.Point]::new(1,$label.ActualHeight+2),$window)
                    $pixel=New-Object byte[] 4
                    $image.CopyPixels([Windows.Int32Rect]::new([int]$point.X,[int]$point.Y,1,1),$pixel,4,0)
                    # Composite translucent WPF pixels over the brightest possible desktop.
                    for ($channel=0;$channel -lt 3;$channel++) { $pixel[$channel]=[byte][Math]::Min(255,[int]$pixel[$channel]+255-[int]$pixel[3]) }
                    $background=Get-Luminance ([Windows.Media.Color]::FromRgb($pixel[2],$pixel[1],$pixel[0]))
                    $foreground=Get-Luminance $label.Foreground.Color
                    if (([Math]::Max($background,$foreground)+0.05)/([Math]::Min($background,$foreground)+0.05) -lt 4.5) { throw "Insufficient rendered label contrast at width ${testWidth}: $($label.Name), bg=$background, fg=$foreground." }
                }
                if ($PreviewPath -and $testWidth -eq 980) {
                    Wait-WindowMessages; Wait-WindowMessages; Wait-WindowMessages; Wait-WindowMessages
                    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                    $bitmap.Render($window)
                    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                    $stream=[IO.File]::Create([IO.Path]::ChangeExtension($PreviewPath,'narrow.png'))
                    try { $encoder.Save($stream) } finally { $stream.Dispose() }
                }
            }
            $window.Width=$originalWidth
            Wait-WindowMessages
            $window.UpdateLayout()
            # Filtering must compact the actual grid, not just hide its contents.
            Set-Selection @('peace','extra_vlc')
            if ($categoryGroups.Count -ne 4 -or $categoryButtons.Count -ne 25) { throw 'Grouped category navigation lost a category.' }
            foreach ($group in $categoryGroups.Values) {
                $group.IsExpanded=$true
                $window.UpdateLayout()
                if ($group.Content.Children.Count -eq 0 -or $group.Content.Children[0].ActualHeight -lt 32) { throw 'Category group cannot expose its buttons.' }
                $group.IsExpanded=$false
            }
            $categoryGroups['Everyday'].IsExpanded=$true
            foreach ($categoryButton in $categoryButtons) {
                $categoryButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                $window.UpdateLayout()
                Update-CardLayout
                $window.UpdateLayout()
                $expected=@($catalog | Where-Object { Test-AppCategory $_ ([string]$categoryButton.Tag) })
                if ($ui.Cards.Children.Count -ne $expected.Count) { throw "Hidden cards still occupy grid slots in $($categoryButton.Tag)." }
                if ($expected.Count) {
                    $position=$ui.Cards.Children[0].TranslatePoint([Windows.Point]::new(0,0),$ui.Cards)
                    if ([Math]::Abs($position.X) -gt 1 -or [Math]::Abs($position.Y) -gt 1) { throw 'Filtered grid does not start at the first cell.' }
                    for ($i=0;$i -lt $expected.Count;$i++) {
                        if ($ui.Cards.Children[$i].Tag -ne $expected[$i].Key) { throw 'Filtering changed catalog order.' }
                    }
                }
            }
            $videoButton=@($categoryButtons | Where-Object { $_.Tag -eq 'Video Editing' })[0]
            $videoButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            if ($checks['resolve'].Visibility -ne 'Visible' -or $checks['extra_blender'].Visibility -ne 'Visible' -or
                $checks['daily_adobe_creative_cloud'].Visibility -ne 'Visible' -or $checks['extra_vlc'].Visibility -ne 'Collapsed' -or
                $checks['daily_adobe_creative_cloud'].Content.Children[1].Text -ne 'Video Editing') { throw 'Video editing is mixed with playback or lost multi-purpose apps.' }
            if ($PreviewPath) {
                $categoryGroups['Create'].IsExpanded=$true
                Set-Selection @('resolve','extra_blender')
                $window.UpdateLayout()
                Wait-WindowMessages; Wait-WindowMessages; Wait-WindowMessages; Wait-WindowMessages
                $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($window)
                $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                $stream=[IO.File]::Create([IO.Path]::ChangeExtension($PreviewPath,'editing.png'))
                try { $encoder.Save($stream) } finally { $stream.Dispose() }
                Set-Selection @('peace','extra_vlc')
                $categoryGroups['Create'].IsExpanded=$false
            }
            foreach ($categoryButton in $categoryButtons) {
                if ($categoryButton.Tag -eq 'All apps') { $categoryButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
            }
            $ui.Search.Text='LocalSend'
            $window.UpdateLayout()
            if ($ui.Cards.Children.Count -ne 1 -or $ui.Cards.Children[0].Tag -ne 'extra_localsend') { throw 'Search results did not compact.' }
            $ui.Search.Text='__no_matching_apps__'
            $window.UpdateLayout()
            if ($ui.Cards.Children.Count -ne 0 -or $ui.Empty.Visibility -ne 'Visible') { throw 'Empty search left grid slots behind.' }
            $ui.Search.Clear()
            $window.UpdateLayout()
            if ($ui.Cards.Children.Count -ne $catalog.Count -or $selected.Count -ne 3 -or -not $checks['peace'].IsChecked -or -not $checks['apo'].IsChecked -or -not $checks['extra_vlc'].IsChecked) { throw 'Filtering lost selected apps or dependencies.' }
            Set-Selection @()
            $ui.LibraryScroll.UpdateLayout()
            $bar=$ui.LibraryScroll.Template.FindName('PART_VerticalScrollBar',$ui.LibraryScroll)
            $bar.ApplyTemplate() | Out-Null
            $track=$bar.Template.FindName('PART_Track',$bar)
            if ($null -eq $track -or $bar.ActualWidth -ne 12) { throw 'Minimal scrollbar template not applied.' }
            if ($track.Thumb.ActualHeight -lt 48) { throw "Scrollbar thumb is too short: $($track.Thumb.ActualHeight)." }
            $track.Thumb.ApplyTemplate() | Out-Null
            $handle=$track.Thumb.Template.FindName('Handle',$track.Thumb)
            if ($null -eq $handle -or $handle.Background.Color -ne $window.Resources['AccentMutedBrush'].Color) { throw 'Scrollbar palette mismatch.' }
            [Windows.Controls.Primitives.ScrollBar]::PageDownCommand.Execute($null,$bar)
            $ui.LibraryScroll.UpdateLayout()
            if ($ui.LibraryScroll.VerticalOffset -le 0) { throw 'Scrollbar page-down failed.' }
            $previousOffset=$ui.LibraryScroll.VerticalOffset
            $track.Thumb.RaiseEvent([Windows.Controls.Primitives.DragDeltaEventArgs]::new(0,12))
            $ui.LibraryScroll.UpdateLayout()
            if ($ui.LibraryScroll.VerticalOffset -le $previousOffset) { throw 'Scrollbar drag failed.' }
            $ui.LibraryScroll.ScrollToBottom()
            $ui.LibraryScroll.UpdateLayout()
            if ([Math]::Abs($ui.LibraryScroll.VerticalOffset-$ui.LibraryScroll.ScrollableHeight) -gt 1) { throw 'The last applications cannot be reached.' }
            $ui.LibraryScroll.ScrollToTop()
            $ui.LibraryScroll.UpdateLayout()
            $ui.Profiles.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Wait-WindowMessages
            if (-not $profileMenu.IsOpen -or $profileItems.Count -ne $profiles.Count -or $window.OwnedWindows.Count -ne 0) { throw 'Profiles must open a menu, not another window.' }
            $before=@($selected.Keys)
            if ($PreviewPath) {
                $profileMenu.UpdateLayout()
                $image=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$profileMenu.ActualWidth,[int]$profileMenu.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $image.Render($profileMenu); $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
                $stream=[IO.File]::Create([IO.Path]::ChangeExtension($PreviewPath,'profiles.png')); try { $encoder.Save($stream) } finally { $stream.Dispose() }
            }
            $profileItems['creator'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
            if ($profileMenu.IsOpen -or $selected.Count -ne $profilesByKey['creator'].Apps.Count -or $script:busy -or $script:job) { throw 'Profile menu did not apply a reviewable selection.' }
            Set-Selection $before
            $ui.UserProfiles.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            $window.UpdateLayout()
            if (-not $userProfileMenu.IsOpen -or $userProfileMenu.Background.Color -ne $window.Resources['GlassMenuFill'].Color) { throw 'User profiles menu failed to open with the app theme.' }
            $userProfileMenu.IsOpen=$false
            Wait-WindowMessages
            $window.Activate() | Out-Null
            $ui.MaximizeWindow.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Wait-WindowMessages
            if ($window.WindowState -ne 'Maximized' -or $ui.MaximizeWindow.ToolTip -ne 'Restore') { throw "Maximize button failed: state=$($window.WindowState), tooltip=$($ui.MaximizeWindow.ToolTip)." }
            $ui.MaximizeWindow.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Wait-WindowMessages
            if ($window.WindowState -ne 'Normal') { throw 'Restore button failed.' }
            if ([FirstInstallWindow]::ReadNativeFrameEnabled($nativeFrameHandle) -ne 0) { throw 'DWM frame reappeared after maximize/restore.' }
            $ui.MinimizeWindow.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            Wait-WindowMessages
            if ($window.WindowState -ne 'Minimized') { throw 'Minimize button failed.' }
            $window.WindowState='Normal'
            Wait-WindowMessages
            if (Confirm-Plan @(Get-Plan @('peace','extra_vlc'))) { throw 'Review test must cancel.' }
            foreach ($group in $categoryGroups.Values) { $group.IsExpanded=$false }
            $window.UpdateLayout()
            if ($PreviewPath) {
                $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($window)
                $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                $stream=[IO.File]::Create($PreviewPath)
                try { $encoder.Save($stream) } finally { $stream.Dispose() }
            }
            foreach ($sample in @('#0078D4','#D13438','#001020','#FFFF99','#00CC88','#FF00FF','#FFFFFF','#000000')) {
                Set-AccentPalette ([Windows.Media.ColorConverter]::ConvertFromString($sample))
                $window.UpdateLayout(); Update-GlassBackdrops
                $image=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $image.Render($window)
                foreach ($label in @($ui.ResultCount,$ui.SelectedCount,$checks['winutil_dotnet10'].Content.Children[1])) {
                    $point=$label.TranslatePoint([Windows.Point]::new(1,$label.ActualHeight+2),$window)
                    $pixel=New-Object byte[] 4; $image.CopyPixels([Windows.Int32Rect]::new([int]$point.X,[int]$point.Y,1,1),$pixel,4,0)
                    for ($channel=0;$channel -lt 3;$channel++) { $pixel[$channel]=[byte][Math]::Min(255,[int]$pixel[$channel]+255-[int]$pixel[3]) }
                    $bg=Get-Luminance ([Windows.Media.Color]::FromRgb($pixel[2],$pixel[1],$pixel[0])); $fg=Get-Luminance $label.Foreground.Color
                    if (([Math]::Max($bg,$fg)+0.05)/([Math]::Min($bg,$fg)+0.05) -lt 4.5) { throw "Glass label contrast failed for accent ${sample}: $($label.Name), bg=$bg, fg=$fg." }
                }
                if ((Get-Luminance $window.Resources['WindowFill'].Color) -gt 0.02) { throw 'Adaptive window background became too bright.' }
                foreach ($name in @('Navigation','Setup')) {
                    $pane=$window.FindName($name+'Glass'); $brush=$window.FindName($name+'Backdrop').Background
                    if ($brush -isnot [Windows.Media.VisualBrush] -or [Math]::Abs($brush.Viewbox.Width-$pane.ActualWidth) -gt 1) { throw 'Glass sampling does not match the pane.' }
                }
            }
            Update-WindowsAccent
            $light=$window.FindName('NavigationReflection'); $light.Tag=0
            Move-GlassLight $light ([Windows.Point]::new($light.ActualWidth*0.75,$light.ActualHeight*0.3))
            if ([Math]::Abs($light.Background.Center.X-0.75) -gt 0.01 -or [Math]::Abs($light.Background.Center.Y-0.3) -gt 0.01) { throw "Glass reflection does not follow the pointer: $($light.ActualWidth)x$($light.ActualHeight), center=$($light.Background.Center), enabled=$script:lastGlass." }
            $light.Background.Center=[Windows.Point]::new(0.2,0.06); $light.Background.GradientOrigin=$light.Background.Center
            # Removal checks use fictional rows and cancel review; never run an uninstaller here.
            $fixture=New-Object InstalledApp; $fixture.Id='fixture-desktop'; $fixture.Name='Example Editor'; $fixture.Publisher='Example Studio'; $fixture.Version='2.0'; $fixture.Kind='Desktop'; $fixture.CanRemove=$true
            $storeFixture=New-Object InstalledApp; $storeFixture.Id='fixture-store'; $storeFixture.Name='Example Notes'; $storeFixture.Publisher='Example Studio'; $storeFixture.Kind='Microsoft Store'; $storeFixture.CanRemove=$true
            $completion=New-Object 'System.Threading.Tasks.TaskCompletionSource[AppInventory]'
            Set-AppMode 'Uninstall'; $window.UpdateLayout(); Wait-WindowMessages
            Set-UninstallTask $completion.Task 'Inventory'
            if ($ui.InstallMode.IsEnabled -or $ui.RefreshInstalled.IsEnabled -or $ui.InstalledList.IsEnabled) { throw 'Removal task did not lock conflicting actions.' }
            $window.UpdateLayout(); Wait-WindowMessages
            $loadingImage=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
            $loadingImage.Render($window)
            $loadingPoint=$ui.InstalledList.TranslatePoint([Windows.Point]::new($ui.InstalledList.ActualWidth/2,$ui.InstalledList.ActualHeight/2),$window)
            $loadingPixel=New-Object byte[] 4
            $loadingImage.CopyPixels([Windows.Int32Rect]::new([int]$loadingPoint.X,[int]$loadingPoint.Y,1,1),$loadingPixel,4,0)
            if ($loadingPixel[0] -gt 200 -and $loadingPixel[1] -gt 200 -and $loadingPixel[2] -gt 200) { throw 'Installed list flashed white during the disabled/loading state.' }
            $inventoryFixture=New-Object AppInventory; $inventoryFixture.Apps.Add($fixture); $inventoryFixture.Apps.Add($storeFixture)
            $completion.SetResult($inventoryFixture)
            Wait-WindowMessages; Wait-WindowMessages; Wait-WindowMessages
            if ($script:uninstallTask -or $uninstallTimer.IsEnabled -or -not $ui.RefreshInstalled.IsEnabled -or $script:installedApps.Count -ne 2) { throw 'Inventory task did not complete on the dispatcher.' }
            $failure=New-Object 'System.Threading.Tasks.TaskCompletionSource[AppInventory]'
            Set-UninstallTask $failure.Task 'Inventory'; $failure.SetException([InvalidOperationException]::new('Simulated scan failure'))
            Wait-WindowMessages; Wait-WindowMessages; Wait-WindowMessages
            if ($script:uninstallTask -or $ui.UninstallStatus.Text -notlike 'Could not complete*' -or -not $ui.InstallMode.IsEnabled) { throw 'Removal task failure left the app locked.' }
            $ui.UninstallStatus.Text='Preview with fictional apps · no installed application has been removed.'
            Set-AppMode 'Uninstall'; $window.UpdateLayout(); Wait-WindowMessages
            if ($ui.InstalledList.Items.Count -ne 2 -or $ui.InstallLibrary.Visibility -ne 'Collapsed' -or $ui.CategoriesHost.Visibility -ne 'Collapsed') { throw 'Uninstall mode did not replace the library.' }
            if ($ui.InstalledAll.TranslatePoint([Windows.Point]::new(0,0),$window).Y -gt 20 -or $ui.InstallLibrary.Margin.Top -ne 12) { throw 'Header still reserves an empty title-bar band.' }
            function Find-RowCheck($Element) {
                if ($Element -is [Windows.Controls.CheckBox]) { return $Element }
                for ($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Element);$i++) {
                    $found=Find-RowCheck ([Windows.Media.VisualTreeHelper]::GetChild($Element,$i)); if ($found) { return $found }
                }
            }
            $rowCheck=Find-RowCheck ($ui.InstalledList.ItemContainerGenerator.ContainerFromIndex(0))
            if (-not $rowCheck) { throw 'Installed-app row is not reachable.' }
            $box=$rowCheck.Template.FindName('TickBox',$rowCheck)
            $hit=$rowCheck.InputHitTest($box.TranslatePoint([Windows.Point]::new(9,9),$rowCheck))
            while ($hit -and $hit -ne $rowCheck) { $hit=[Windows.Media.VisualTreeHelper]::GetParent($hit) }
            if ($hit -ne $rowCheck) { throw 'Empty checkbox center does not route clicks to the checkbox.' }
            $rowCheck.IsChecked=$true; Wait-WindowMessages
            if (-not $fixture.Selected) { throw 'Installed checkbox did not update its model.' }
            if (-not $ui.ReviewUninstall.IsEnabled -or $ui.UninstallSelectedCount.Text -ne '1 app selected') { throw 'Installed-app selection did not enable review.' }
            $ui.InstalledSearch.Text='Notes'
            if ($ui.InstalledList.Items.Count -ne 1 -or -not $fixture.Selected) { throw 'Installed search lost the removal selection.' }
            $ui.InstalledSearch.Clear(); $script:installedKind='Microsoft Store'; Update-InstalledFilter
            if ($ui.InstalledList.Items.Count -ne 1 -or $ui.InstalledList.Items[0].Kind -ne 'Microsoft Store') { throw 'Installed source filtering failed.' }
            $script:installedKind='All'; Update-InstalledFilter
            if (Show-RemovalReview @($fixture)) { throw 'Removal smoke test must cancel.' }
            $leftover=New-Object LeftoverItem; $leftover.AppName=$fixture.Name; $leftover.Kind='Folder'; $leftover.Path='C:\Example only\Example Editor'; $leftover.Reason='Fictional preview · not a scanned path'; $leftover.Owner=$fixture
            $registryLeftover=New-Object LeftoverItem; $registryLeftover.AppName=$fixture.Name; $registryLeftover.Kind='Registry'; $registryLeftover.Path='Software\Example Studio\Example Editor'; $registryLeftover.Reason='Fictional preview · backup before removal'; $registryLeftover.Owner=$fixture
            if (Show-RemovalReview @($leftover,$registryLeftover) $true) { throw 'Leftover smoke test must cancel.' }
            if ($script:uninstallTask -or $uninstallTimer.IsEnabled) { throw 'Removal tests started an operation.' }
            # Exercise the actual dispatcher Remove -> Scan transition with inert task results.
            $savedScanner=${function:Start-LeftoverScan}
            $script:scanCompletion=New-Object 'System.Threading.Tasks.TaskCompletionSource[RemovalResult]'
            $script:scanRequests=0
            try {
                function Start-LeftoverScan { $script:scanRequests++; Set-UninstallTask $script:scanCompletion.Task 'Scan' }
                $removed=New-Object 'System.Threading.Tasks.TaskCompletionSource[RemovalResult]'
                Set-UninstallTask $removed.Task 'Remove'; $removed.SetResult((New-Object RemovalResult))
                Wait-WindowMessages; Wait-WindowMessages; Wait-WindowMessages
                if ($script:scanRequests -ne 1 -or $script:uninstallOperation -ne 'Scan' -or $ui.CheckLeftovers.IsEnabled) { throw 'Removal did not automatically start protected leftover scanning.' }
                $scanResult=New-Object RemovalResult; $scanResult.Leftovers.Add($leftover); $scanResult.Leftovers.Add($registryLeftover)
                $script:scanCompletion.SetResult($scanResult)
                for ($i=0;$i -lt 8 -and $script:uninstallTask;$i++) { Wait-WindowMessages }
                if ($script:uninstallTask -or $ui.UninstallStatus.Text -notlike '2 possible leftovers found (1 disk / 1 registry)*') { throw 'Mixed disk/registry scan did not open review or started cleanup without consent.' }
                $refreshed=New-Object 'System.Threading.Tasks.TaskCompletionSource[AppInventory]'
                Set-UninstallTask $refreshed.Task 'Inventory'; $refreshed.SetResult($inventoryFixture)
                Wait-WindowMessages; Wait-WindowMessages; Wait-WindowMessages
                if ($ui.UninstallStatus.Text -ne $script:uninstallOutcome) { throw 'Inventory refresh erased the leftover result.' }
            } finally { ${function:Start-LeftoverScan}=$savedScanner; $script:uninstallOutcome='' }
            if ($PreviewPath) {
                $image=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32); $image.Render($window)
                $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
                $stream=[IO.File]::Create([IO.Path]::ChangeExtension($PreviewPath,'uninstall.png')); try { $encoder.Save($stream) } finally { $stream.Dispose() }
            }
            $ui.ClearUninstallSelection.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            if ($fixture.Selected -or $ui.ReviewUninstall.IsEnabled) { throw 'Clearing removal selection failed.' }
            Set-AppMode 'Install'; $window.UpdateLayout()
            if ($window.FindName('WindowControls').Margin.Top -ne 30) { throw 'Integrated controls did not return to the setup header.' }
            if ($category -ne 'All apps' -or $ui.Cards.Children.Count -ne $catalog.Count) { throw 'Returning to Install lost the library.' }
            Set-QueueProgress 65
            $savedMotionFunction=${function:Test-MotionEnabled}
            try {
                function Test-MotionEnabled { return $true }
                $testCard=$checks['affinity']
                Animate-CardEntrance $testCard 70
                $testSurface=$testCard.Template.FindName('Card',$testCard)
                if (-not $testSurface.HasAnimatedProperties) { throw 'Card entrance animation did not start.' }
                Animate-CardClick $testCard
                if (-not $testSurface.RenderTransform.HasAnimatedProperties) { throw 'Click feedback did not start.' }
                Wait-WindowMessages; Wait-WindowMessages; Wait-WindowMessages
                if ($testSurface.RenderTransform.ScaleX -ne 1 -or $testSurface.Opacity -ne 1) { throw 'Card animation did not settle.' }
                function Test-MotionEnabled { return $false }
                Animate-CardEntrance $testCard 70
                Animate-CardClick $testCard
                if ($testSurface.HasAnimatedProperties -or $testSurface.RenderTransform.HasAnimatedProperties -or $testSurface.RenderTransform.ScaleX -ne 1) { throw 'Card motion ignored reduced motion.' }
                Set-QueueProgress 100
                Animate-Appearance $ui.Cards
                if ($ui.Progress.Value -ne 100 -or $ui.Progress.HasAnimatedProperties -or $ui.Cards.Opacity -ne 1 -or $ui.Cards.HasAnimatedProperties -or $ui.Cards.RenderTransform.Y -ne 0) { throw 'Reduced motion did not apply final state immediately.' }
            } finally { ${function:Test-MotionEnabled}=$savedMotionFunction }
            $ui.CloseWindow.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        })
        $window.ShowDialog() | Out-Null
        'PASS: grouped task categories and secondary workflows, opaque glass fallback and restoration, rendered label contrast, in-place queue updates, idle queue timer, compact cards and visible runtime versions, packed search grids, selection and dependencies, motion and reduced-motion fallback, setup editing, Windows accent, profile save/load and rejection, 20 profiles, adaptive background and eight rendered accent palettes, profile dropdown without a new window, removal search/review and leftover consent, four grid widths, scrolling and window controls.'
        return
    }
    $window.ShowDialog() | Out-Null
    $timer.Stop()
} catch {
    if ($SmokeTest) { throw }
    [Windows.MessageBox]::Show($_.Exception.ToString(),'1nstall — error','OK','Error') | Out-Null
    exit 1
}
