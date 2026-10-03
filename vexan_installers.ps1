#requires -Version 5.1
[CmdletBinding()]
param([switch]$CatalogOnly, [switch]$SelfTest, [switch]$SmokeTest, [switch]$ManagerTest, [string]$PreviewPath, [switch]$StartupTest, [string]$ResourceRoot=$PSScriptRoot)
if ($ManagerTest) { $SmokeTest=$true }
if ($StartupTest -and -not (Test-Path variable:StartupClock)) { $StartupClock=[Diagnostics.Stopwatch]::StartNew() }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$catalogJson = @'
@@CATALOG@@
'@
$xamlText = @'
@@XAML@@
'@
if ($catalogJson.Trim().StartsWith('@@')) {
    $catalogJson = Get-Content (Join-Path $ResourceRoot 'catalog.json') -Raw -Encoding UTF8
    $xamlText = Get-Content (Join-Path $ResourceRoot 'interface.xaml') -Raw -Encoding UTF8
}
$thirdPartyNotices = @'
@@THIRD_PARTY_NOTICES@@
'@
if ($thirdPartyNotices.Trim().StartsWith('@@')) { $thirdPartyNotices=[IO.File]::ReadAllText((Join-Path $ResourceRoot 'licenses/THIRD-PARTY-NOTICES.txt')) }
$iconData = '@@ICON@@'
if ($iconData.StartsWith('@@')) { $iconData=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $ResourceRoot 'src/1nstall.ico'))) }
# Windows PowerShell 5.1 emits JSON arrays as one pipeline object; enumerate explicitly.
$catalog = @($catalogJson | ConvertFrom-Json | ForEach-Object { $_ } | Sort-Object @{Expression={ if ($_.Name -match '^\p{Nd}') { 0 } elseif ($_.Name -match '^\p{L}') { 1 } else { 2 } }}, Name)
$byKey = @{}
foreach ($app in $catalog) { $byKey[$app.Key] = $app }
$profilesJson = @'
@@PROFILES@@
'@
if ($profilesJson.Trim().StartsWith('@@')) { $profilesJson=Get-Content (Join-Path $ResourceRoot 'profiles.json') -Raw -Encoding UTF8 }
$profiles=@($profilesJson | ConvertFrom-Json | ForEach-Object { $_ })
$profilesByKey=@{}
foreach ($profile in $profiles) { $profilesByKey[$profile.Key]=$profile }
function Test-AppCategory($App,[string]$Category) {
    return ($Category -eq 'All apps' -or $App.Category -eq $Category -or $App.AlsoIn -contains $Category)
}
function Get-Plan([string[]]$Keys) {
    $seen = @{}
    $visiting = @{}
    $ordered = New-Object 'System.Collections.Generic.List[object]'
    function Visit-Dependency([string]$key) {
        if (-not $byKey.ContainsKey($key)) { throw "Unknown application: $key" }
        if ($visiting.ContainsKey($key)) { throw "Dependency cycle at: $key" }
        if ($seen.ContainsKey($key)) { return }
        $visiting[$key]=$true
        foreach ($dependency in $byKey[$key].Requires) {
            Visit-Dependency $dependency
        }
        $visiting.Remove($key)
        $ordered.Add($byKey[$key]); $seen[$key] = $true
    }
    foreach ($key in $Keys) { Visit-Dependency $key }
    return $ordered.ToArray()
}
if ($CatalogOnly) { $catalogJson; return }
$helperAssembly=Join-Path $ResourceRoot '1nstall.Helpers.dll'
if (-not ('OneInstallPackages' -as [type]) -and (Test-Path -LiteralPath $helperAssembly)) { Add-Type -Path $helperAssembly }
$packageCode = @'
@@PACKAGE_HELPER@@
'@
if ($packageCode.Trim().StartsWith('@@')) { $packageCode=[IO.File]::ReadAllText((Join-Path $ResourceRoot 'src/package-helper.cs')) }
if (-not ('OneInstallPackages' -as [type])) { Add-Type -TypeDefinition $packageCode -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll') }
$uninstallCode = @'
@@UNINSTALL_HELPER@@
'@
if ($uninstallCode.Trim().StartsWith('@@')) { $uninstallCode=Get-Content (Join-Path $ResourceRoot 'src/uninstall-helper.cs') -Raw -Encoding UTF8 }
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
if (-not ('Windows.Window' -as [type])) { Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase') }
$windowCode = @'
@@WINDOW_HELPER@@
'@
if ($windowCode.Trim().StartsWith('@@')) { $windowCode=Get-Content (Join-Path $ResourceRoot 'src/window-helper.cs') -Raw -Encoding UTF8 }
if (-not ('FirstInstallWindow' -as [type])) { Add-Type -TypeDefinition $windowCode }
$settingsCode='@@SETTINGS@@'
if ($settingsCode.StartsWith('@@')) { $settingsCode=[IO.File]::ReadAllText((Join-Path $ResourceRoot 'src/settings.ps1')) } else { $settingsCode=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($settingsCode)) }
. ([scriptblock]::Create($settingsCode))
$updateCode=@'
@@UPDATE_HELPER@@
'@
if (-not ('OneInstallUpdate' -as [type])) {
    if ($updateCode.Trim().StartsWith('@@')) { $updateCode=[IO.File]::ReadAllText((Join-Path $ResourceRoot 'src/update-helper.cs')) }
    Add-Type -TypeDefinition $updateCode -ReferencedAssemblies @('System.dll','System.Core.dll','System.Web.Extensions.dll')
}
# UI starts here
try {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem) { throw 'Requires 64-bit Windows.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Open the executable or use powershell.exe -STA -File vexan_installers.ps1.' }
    if (Test-Path variable:NativeWindow) { $window=$NativeWindow }
    else {
        $compiledUI=Join-Path $ResourceRoot 'dist/1nstall.UI.dll'
        if (Test-Path -LiteralPath $compiledUI) { Add-Type -Path $compiledUI; $window=New-Object OneInstall.MainWindow }
        else { $reader=New-Object System.Xml.XmlNodeReader ([xml]$xamlText); $window=[Windows.Markup.XamlReader]::Load($reader) }
    }
    $nativeCards=('OneInstall.NativeUI' -as [type]) -ne $null
    # UISettings exposes the actual Windows accent, including automatic wallpaper colors.
    $script:accentSettings=$null
    try {
        [Windows.UI.ViewManagement.UISettings,Windows.UI.ViewManagement,ContentType=WindowsRuntime] | Out-Null
        $script:accentSettings=[Windows.UI.ViewManagement.UISettings]::new()
    } catch { }
    function Get-WindowsAccent {
        if (-not $script:settings.WindowsAccent) { return [Windows.Media.ColorConverter]::ConvertFromString($(if (Get-AppLightMode) { '#282828' } else { '#D0D0D0' })) }
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
        return [FirstInstallWindow]::Luminance($Color.R,$Color.G,$Color.B)
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
            $source.CompositionTarget.BackgroundColor=[Windows.Media.Colors]::Transparent
            $window.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'WindowFill')
            $window.FindName('AmbientLight').Opacity=1
        }
        [FirstInstallWindow]::Apply($handle,$script:lightMode) | Out-Null
        Set-AccentPalette (Get-WindowsAccent)
        Set-ContrastResources
    }
    $script:lastGlass=$null
    $script:glassBrushes=@{}
    $script:glassTemplates=@{}
    $script:decorationTemplates=@{}
    foreach ($key in @('BevelBrush','HoverEdgeBrush','CardHoverEdgeBrush','ReflectionEdgeBrush','SeparatorBrush','GroupFill','GroupEdge','GroupHoverFill','TextShadowColor','GlassShadowColor','ButtonLightColor','CardLightColor','ReflectionColor','ReflectionSoftColor')) { $script:decorationTemplates[$key]=$window.Resources[$key] }
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
        $window.Resources['TextShadowOpacity']=if ($Enabled) { [double]0.32 } else { [double]0 }
        foreach ($name in @('NavigationBackdrop','SetupBackdrop','RemovalBackdrop')) { $window.FindName($name).Visibility=if ($Enabled) { 'Visible' } else { 'Collapsed' } }
        foreach ($name in @('NavigationGlass','SetupGlass','RemovalGlass')) {
            $pane=$window.FindName($name)
            if ($Enabled) { $pane.Background='Transparent' } else { $pane.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,'GlassPanelFill') }
        }
        $script:lastGlass=$Enabled
        Update-NativeGlass
    }
    $script:lightMode=$false
    function Update-WindowsAccent {
        $changed=$false
        $light=Get-AppLightMode
        if ($light -ne $script:lightMode) { $script:lightMode=$light; $script:lastGlass=$null; $changed=$true }
        $color=Get-WindowsAccent
        $contrast=[Windows.SystemParameters]::HighContrast
        if ($contrast -ne $script:lastContrast) { $script:lastGlass=$null; Set-AccentPalette $color; $script:lastContrast=$contrast; $changed=$true }
        if ($color.ToString() -ne $script:lastAccent) { Set-AccentPalette $color; $changed=$true }
        $glass=-not [Windows.SystemParameters]::HighContrast
        try { if ($null -ne $script:accentSettings) { $glass=$glass -and $script:accentSettings.AdvancedEffectsEnabled } } catch { }
        if ($glass -ne $script:lastGlass) { Set-GlassAppearance $glass; $changed=$true }
        if ($changed) { Set-ContrastResources }
    }
    function Set-ContrastResources {
        $contrast=[Windows.SystemParameters]::HighContrast
        $window.Resources['TextPrimaryBrush']=if ($contrast) { [Windows.SystemColors]::WindowTextBrush } else { [Windows.Media.BrushConverter]::new().ConvertFromString('#F3F5F7') }
        $window.Resources['TextSecondaryBrush']=if ($contrast) { [Windows.SystemColors]::WindowTextBrush } else { [Windows.Media.BrushConverter]::new().ConvertFromString('#C2CADE') }
        $window.Resources['InputFill']=if ($contrast) { [Windows.SystemColors]::WindowBrush } else { [Windows.Media.BrushConverter]::new().ConvertFromString('#1B1E25') }
        $window.Resources['DialogFill']=if ($contrast) { [Windows.SystemColors]::WindowBrush } else { [Windows.Media.BrushConverter]::new().ConvertFromString('#101526') }
        $window.Resources['FocusBrush']=if ($contrast) { [Windows.SystemColors]::WindowTextBrush } else { [Windows.Media.Brushes]::White }
        $window.Resources['CheckBorderBrush']=if ($contrast) { [Windows.SystemColors]::WindowTextBrush } else { [Windows.Media.BrushConverter]::new().ConvertFromString('#A5AFC4') }
        if ($contrast) {
            foreach ($key in @('WindowFill','OpaqueWindowFill','DialogFill','InputFill','GlassPanelFill','GlassControlFill','GlassMenuFill','ContentFill')) { $window.Resources[$key]=[Windows.SystemColors]::WindowBrush }
            foreach ($key in @('GlassEdge','CardEdge')) { $window.Resources[$key]=[Windows.SystemColors]::WindowTextBrush }
            foreach ($key in @('AccentBrush','AccentActionBrush')) { $window.Resources[$key]=[Windows.SystemColors]::HighlightBrush }
            $window.Resources['AccentSurfaceBrush']=[Windows.SystemColors]::WindowBrush
            $window.Resources['AccentTextBrush']=[Windows.SystemColors]::WindowTextBrush
            $window.Resources['AccentForegroundBrush']=[Windows.SystemColors]::HighlightTextBrush
        }
        Set-AppMaterials
    }
    $script:lastAccent=''
    $script:lastContrast=$null
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
    foreach ($name in @('Categories','Search','ClearSearch','ResultCount','UserProfiles','ClearSelection','Cards','Empty','LogBox','SelectedCount','SaveSetup','Import','Export','QueuePanel','Status','Progress','Install','Cancel','OpenLogs','Environment','MinimizeWindow','MaximizeWindow','CloseWindow','MaximizeGlyph','LibraryScroll','InstallMode','UninstallMode','InstallLibrary','CategoriesHost','UninstallNavigation','NavigationHeading','UninstallPage','InstalledSearch','RefreshInstalled','WindowsAppsSettings','InstalledList','InstalledEmpty','InstalledAll','InstalledDesktop','InstalledStore','UninstallSelectedCount','UninstallQueuePanel','ClearUninstallSelection','CheckLeftovers','OpenUninstallBackups','ReviewUninstall','StopUninstall','UninstallStatus','UninstallLog')) { $ui[$name] = $window.FindName($name) }
    $ui.Profiles=$window.FindName('Profiles')
    $window.FindName('Donate').Add_Click({ Start-Process 'https://ko-fi.com/braga1k' })
    function Show-ThirdPartyNotices {
        $info=New-InfoDialog 'Licenses & credits' $thirdPartyNotices
        if ($ManagerTest) { $info.Window.Add_ContentRendered({ Capture-TestDialog $info.Window 'licenses'; $info.Window.Close() }) }
        $info.Window.ShowDialog() | Out-Null
    }
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
        Set-UiValue ($ui.MaximizeWindow) 'ToolTip' $(if ($maximized) { 'Restore' } else { 'Maximize' })
        [Windows.Automation.AutomationProperties]::SetName($ui.MaximizeWindow,[string]$ui.MaximizeWindow.ToolTip)
        $ui.MaximizeGlyph.Data=if ($maximized) { 'M 2,0 L 10,0 10,8 M 0,2 L 8,2 8,10 0,10 Z' } else { 'M 0,0 L 10,0 10,10 0,10 Z' }
    })
    $selected = @{}
    $checks = @{}
    $searchTexts = @{}
    $statuses = @{}
    $category = 'All apps'
    $script:libraryView='All apps'
    $script:viewButtons=@{}
    $busy = $false
    $syncing = $false
    $job = $null
    $logDir = if ($SmokeTest) { Join-Path $ResourceRoot 'test-logs' } else { Join-Path $env:LOCALAPPDATA '1nstall\Logs' }
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logPath = Join-Path $logDir ('session-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$PID)
    $winget = [OneInstallPackages]::FindWinGet()
    Set-UiValue ($ui.Environment) 'Text' $(if ($winget) { 'WinGet ready · {0} apps to explore' -f $catalog.Count } else { 'WinGet is missing. Install App Installer to enable automatic installs.' })
    function Add-Log([string]$Message) {
        $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Message
        $ui.LogBox.AppendText($line + "`r`n")
        $ui.LogBox.ScrollToEnd()
        try { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 } catch { Set-UiValue ($ui.Status) 'Text' $('Could not save the log to disk.') }
    }
    function New-Label([string]$Text, [string]$Color='#F3F5F7', [double]$Size=13) {
        $label = New-Object Windows.Controls.TextBlock
        Set-UiValue ($label) 'Text' $($Text); $label.FontSize = $Size
        $label.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$(if ($Color -in @('#F3F5F7','#DCE1E7','#D7DFE8','#FFFFFF')) { 'TextPrimaryBrush' } else { 'TextSecondaryBrush' }))
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
            else { break }
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
        if ($Light.Background.IsFrozen) { $Light.Background=$Light.Background.Clone() }
        $point=[Windows.Point]::new([Math]::Max(0.0,[Math]::Min(1.0,$Position.X/$Light.ActualWidth)),[Math]::Max(0.0,[Math]::Min(1.0,$Position.Y/$Light.ActualHeight)))
        $Light.Background.Center=$point; $Light.Background.GradientOrigin=$point
    }
    function Update-GlassBackdrops {
        $ambient=$window.FindName('AmbientLight')
        foreach ($name in @('Navigation','Setup','Removal')) {
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
    foreach ($name in @('NavigationGlass','SetupGlass','RemovalGlass')) {
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
    function New-SelectionRow($Tag,[string]$Name,[string]$Detail,[scriptblock]$Remove,[bool]$Enabled) {
        $panel=New-Object Windows.Controls.StackPanel; $panel.Margin='0,8,0,9'; $panel.Tag=$Tag
        $row=New-Object Windows.Controls.Grid
        $row.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
        $actionColumn=New-Object Windows.Controls.ColumnDefinition; $actionColumn.Width='Auto'; $row.ColumnDefinitions.Add($actionColumn)
        $title=New-Label $Name; $title.FontWeight='SemiBold'; $title.Margin='0,0,8,0'; $title.VerticalAlignment='Center'
        $row.Children.Add($title) | Out-Null
        $removeButton=New-Object Windows.Controls.Button
        Set-UiValue ($removeButton) 'Content' $('×'); $removeButton.Tag=$Tag; $removeButton.Width=32; $removeButton.MinHeight=32
        $removeButton.Padding='0'; $removeButton.Margin='0'; $removeButton.FontSize=18
        $removeButton.Background='Transparent'; $removeButton.BorderThickness='0'; $removeButton.IsEnabled=$Enabled
        Set-UiValue ($removeButton) 'ToolTip' $('Remove '+$Name+' from selection')
        [Windows.Automation.AutomationProperties]::SetName($removeButton,'Remove '+$Name+' from selection')
        Enable-HoverMotion $removeButton
        [Windows.Controls.Grid]::SetColumn($removeButton,1); $removeButton.Add_Click($Remove)
        $row.Children.Add($removeButton) | Out-Null; $panel.Children.Add($row) | Out-Null
        $label=New-Label $Detail '#C2CADE' 12; $label.Margin='0,4,0,0'; $panel.Children.Add($label) | Out-Null
        return $panel
    }
    function Update-Selection {
        $script:syncing = $true
        foreach ($app in $catalog) { $checks[$app.Key].IsChecked = $selected.ContainsKey($app.Key) }
        $script:syncing = $false
        Set-UiValue ($ui.SelectedCount) 'Text' $(if ($selected.Count -eq 1) { '1 app selected' } else { '{0} apps selected' -f $selected.Count })
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
            $text = if ($statuses.ContainsKey($app.Key)) { $statuses[$app.Key] } elseif ($app.Ids.Count) { 'Automatic · WinGet' } else { 'Guided · official website' }
            $panel=New-SelectionRow $app.Key $app.Name $text { param($sender,$eventArgs) Remove-SelectedApp ([string]$sender.Tag) } (-not $busy)
            $script:removeButtons[$app.Key]=$panel.Children[0].Children[1]
            $script:statusLabels[$app.Key]=$panel.Children[1]
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
        Set-UiValue ($script:statusLabels[$Key]) 'Text' $($Text)
        Add-Log ($byKey[$Key].Name + ': ' + $Text)
    }
    function Remove-SelectedApp([string]$Key) {
        if ($script:busy) { return }
        $selected.Remove($Key); $statuses.Remove($Key)
        do {
            $removed=$false
            foreach ($item in $catalog) {
                if ($selected.ContainsKey($item.Key) -and @($item.Requires | Where-Object { -not $selected.ContainsKey($_) }).Count) { $selected.Remove($item.Key); $statuses.Remove($item.Key); $removed=$true }
            }
        } while ($removed)
        Update-Selection
        Set-UiValue ($ui.Status) 'Text' $('Selection updated. Review before installing.')
    }
    function Set-Selection([string[]]$Keys) {
        $selected.Clear(); $statuses.Clear()
        foreach ($app in @(Get-Plan $Keys)) { $selected[$app.Key] = $true }
        Update-Selection
        Set-UiValue ($ui.Status) 'Text' $(if ($selected.Count) { 'Selection updated. Review before installing.' } else { 'Ready when you are.' })
    }
    function Update-Filter([switch]$ForceAnimation) {
        $query = $ui.Search.Text.Trim()
        $count = 0
        # Keep checkbox instances and selection, but only attach matching cards.
        $visible=New-Object 'System.Collections.Generic.List[object]'
        foreach ($app in $catalog) {
            $viewMatch=($script:libraryView -eq 'All apps' -or $query -ne '' -or
                ($script:libraryView -eq 'Installed' -and [OneInstallPackages]::InstalledState($script:libraryInventory,[string[]]$app.Ids,'winget').StartsWith('Installed ·')))
            $match = $viewMatch -and (Test-AppCategory $app $category) -and
                ($searchTexts[$app.Key].IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0)
            $visibility=if ($match) { 'Visible' } else { 'Collapsed' }
            if ($checks[$app.Key].Visibility -ne $visibility) { $checks[$app.Key].Visibility=$visibility }
            Set-UiValue ($checks[$app.Key].Content.Children[1]) 'Text' $(if ($app.AlsoIn -contains $category) { $category } else { $app.Category })
            if ($match) { $visible.Add($checks[$app.Key]); $count++ }
        }
        $changed=$ui.Cards.Children.Count -ne $visible.Count
        if (-not $changed) {
            for ($i=0; $i -lt $visible.Count; $i++) {
                if (-not [object]::ReferenceEquals($ui.Cards.Children[$i],$visible[$i])) { $changed=$true; break }
            }
        }
        if ($changed) {
            $ui.Cards.Children.Clear()
            foreach ($card in $visible) { $ui.Cards.Children.Add($card) | Out-Null }
        }
        Set-UiValue ($ui.ResultCount) 'Text' $("$category · $count apps")
        if ($script:libraryView -ne 'All apps' -and $query -eq '') { Set-UiValue ($ui.ResultCount) 'Text' $($script:libraryView+' · '+$count+' apps') }
        foreach ($view in $script:viewButtons.Keys) {
            if ($view -eq $script:libraryView) { $script:viewButtons[$view].SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentSurfaceBrush'); $script:viewButtons[$view].SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'AccentTextBrush') }
            else { $script:viewButtons[$view].SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'GlassControlFill'); $script:viewButtons[$view].SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'TextPrimaryBrush') }
        }
        foreach ($button in $categoryButtons) {
            $active=$script:libraryView -eq 'All apps' -and $button.Tag -eq $category
            $button.IsChecked=$active
        }
        if ($script:libraryView -eq 'Installed' -and $count -eq 0) { Set-UiValue ($ui.Empty) 'Text' $('No confirmed installed catalog apps. Refresh status; guided apps and unavailable inventory remain Unknown.') } else { Set-UiValue ($ui.Empty) 'Text' $('No apps found. Try another search or All apps.') }
        $ui.Empty.Visibility = if ($count -eq 0) { 'Visible' } else { 'Collapsed' }
        $ui.LibraryScroll.ScrollToTop()
        if ($nativeCards) { [OneInstall.NativeUI]::Realize($ui.Cards,$ui.LibraryScroll) }
        if ($changed -or $ForceAnimation) { Animate-Library }
    }
    if ($nativeCards -and $window.Resources.Contains('NativeChecks')) {
        $checks=$window.Resources['NativeChecks']; $searchTexts=$window.Resources['NativeSearchTexts']
    } else {
    foreach ($app in $catalog) {
        $searchTexts[$app.Key]=$app.Name+' '+$app.Category+' '+($app.AlsoIn -join ' ')+' '+$app.Description
        $method=if ($app.Ids.Count) { 'Automatic · WinGet: '+($app.Ids -join ', ') } else { 'Guided · official website: '+$app.Url }
        $help=$app.Description+"`n"+$app.Category+' · '+$app.LicenseLabel+"`n"+$method
        if ($app.AlsoIn.Count) { $help+="`nAlso in: "+($app.AlsoIn -join ', ') }
        if ($nativeCards) {
            $check=[OneInstall.NativeUI]::Card($window,$app.Key,$app.Name,$app.Category,$help,($app.Ids.Count -gt 0))
            Enable-HoverMotion $check
        } else {
        $check = New-Object Windows.Controls.CheckBox
        Enable-HoverMotion $check
        $check.Style = $window.Resources['CardCheck']; $check.Tag = $app.Key
        $check.Margin = '4,0,4,8'; $check.Height = 140; $check.MinHeight = 140
        $method = if ($app.Ids.Count) { 'Automatic · WinGet: ' + ($app.Ids -join ', ') } else { 'Guided · official website: ' + $app.Url }
        $help = $app.Description + "`n" + $app.Category + ' · ' + $app.LicenseLabel + "`n" + $method
        if ($app.AlsoIn.Count) { $help += "`nAlso in: " + ($app.AlsoIn -join ', ') }
        $tooltip = New-Object Windows.Controls.ToolTip
        $tooltip.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'DialogFill'); $tooltip.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'TextPrimaryBrush'); $tooltip.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty,'GlassEdge')
        $tooltip.Padding='12'; $tooltip.MaxWidth=360
        Set-UiValue ($tooltip) 'Content' $(New-Label ($app.Name + "`n`n" + $help) '#F3F5F7' 12)
        Set-UiValue ($check) 'ToolTip' $($tooltip)
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
        $badge.TextWrapping='NoWrap'; $badge.TextTrimming='CharacterEllipsis'
        $content.Children.Add($badge) | Out-Null
        Set-UiValue ($check) 'Content' $($content)
        }
        $checks[$app.Key] = $check; $ui.Cards.Children.Add($check) | Out-Null
    }
    }
    $ui.Cards.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent,[Windows.RoutedEventHandler]{
        param($sender,$eventArgs)
        $card=$eventArgs.Source
        if ($card -isnot [Windows.Controls.CheckBox] -or $script:syncing -or $script:busy) { return }
        $key=[string]$card.Tag
        if ($card.IsChecked) { foreach ($item in @(Get-Plan @($key))) { $selected[$item.Key]=$true } }
        else { Remove-SelectedApp $key }
        Update-Selection; Animate-CardClick $card
    })
    $ui.Cards.Add_MouseMove({ param($sender,$e)
        if (-not $script:lastGlass -or -not (Test-MotionEnabled)) { return }
        $element=$e.OriginalSource
        while ($element -is [Windows.Media.Visual] -and $element -isnot [Windows.Controls.CheckBox]) { $element=[Windows.Media.VisualTreeHelper]::GetParent($element) }
        if ($element -is [Windows.Controls.CheckBox]) {
            $light=$element.Template.FindName('HoverLight',$element)
            if ($light) { Move-GlassLight $light ($e.GetPosition($light)) }
        }
    })
    function Get-InstalledCardLight($Origin) {
        $item=[Windows.Controls.ItemsControl]::ContainerFromElement($ui.InstalledList,$Origin)
        if ($item -isnot [Windows.Controls.ListBoxItem]) { return $null }
        $presenter=[Windows.Media.VisualTreeHelper]::GetChild($item,0)
        return $ui.InstalledList.ItemTemplate.FindName('InstalledHoverLight',$presenter)
    }
    $ui.InstalledList.Add_MouseMove({ param($sender,$e)
        if (-not $script:lastGlass -or -not (Test-MotionEnabled)) { return }
        $light=Get-InstalledCardLight $e.OriginalSource
        if ($light) { Move-GlassLight $light ($e.GetPosition($light)) }
    })
    $categoryButtons=New-Object 'System.Collections.Generic.List[object]'
    $categoryGroups=@{}
    $selectCategory={
        param($sender,$eventArgs)
        if ($script:category -eq [string]$sender.Tag -and $script:libraryView -eq 'All apps') { return }
        $script:category=[string]$sender.Tag; $script:libraryView='All apps'
        Save-LibraryView; Update-Filter
    }
    foreach ($group in @('All apps','Everyday','Create','Files & Storage','PC & Tools')) {
        $categoryPanel=$ui.Categories
        $groupCategories=@('All apps')
        if ($group -ne 'All apps') {
            $categoryPanel=New-Object Windows.Controls.StackPanel
            $expander=New-Object Windows.Controls.Expander
            Set-UiValue ($expander) 'Header' $($group); Set-UiValue ($expander) 'Content' $($categoryPanel); $expander.FontWeight='SemiBold'
            $categoryPanel.Margin='10,0,0,0'
            $expander.Style=$window.Resources['CategoryGroup']
            $expander.Add_Expanded({ param($sender,$eventArgs)
                foreach ($other in $categoryGroups.Values) { if ($other -ne $sender) { $other.IsExpanded=$false } }
            })
            $expander.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'TextPrimaryBrush'); $expander.Margin='0,4,0,4'; $expander.MinHeight=32
            $expander.IsExpanded=$false
            [Windows.Automation.AutomationProperties]::SetName($expander,$group+' categories')
            $categoryGroups[$group]=$expander
            $ui.Categories.Children.Add($expander) | Out-Null
            $groupCategories=@($catalog | Where-Object { $_.CategoryGroup -eq $group } | ForEach-Object { $_.Category } | Sort-Object -Unique)
        }
        foreach ($cat in $groupCategories) {
        $button=New-Object Windows.Controls.RadioButton
        $button.Style=$window.Resources['CategoryItem']; $button.GroupName='LibraryCategories'; $button.Tag=$cat
        Set-UiValue ($button) 'Content' $(New-Label $cat '#DCE1E7' 14)
        [Windows.Automation.AutomationProperties]::SetName($button,$cat)
        if ($cat -eq 'All apps') { $button.Content.FontSize=14; $button.Margin='0,0,0,12' }
        $button.IsChecked=($cat -eq $category)
        $button.Add_Checked($selectCategory); $button.Add_Click($selectCategory)
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
        Set-UiValue ($ui.Status) 'Text' $($profile.Name + ' profile applied. Review your apps before installing.')
    }
    $profileItems=@{}
    $profileMenu=New-Object Windows.Controls.ContextMenu
    $profileMenu.Resources=$window.Resources
    $profileMenu.PlacementTarget=$ui.Profiles; $profileMenu.Placement='Bottom'
    $profileMenu.MaxHeight=[Math]::Min(640,[Math]::Max(300,[Windows.SystemParameters]::WorkArea.Height-100))
    foreach ($group in @('Everyday & Work','Create','Files & Privacy','PC & Tools')) {
        if ($profileMenu.Items.Count) { $profileMenu.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null }
        $heading=New-Object Windows.Controls.MenuItem; Set-UiValue ($heading) 'Header' $($group); $heading.IsEnabled=$false; $heading.FontWeight='SemiBold'; $heading.FontSize=11; $heading.Padding='10,6'
        $profileMenu.Items.Add($heading) | Out-Null
        foreach ($profile in @($profiles | Where-Object { $_.Group -eq $group })) {
            $plan=@(Get-Plan @($profile.Apps))
            $item=New-Object Windows.Controls.MenuItem; Set-UiValue ($item) 'Header' $($profile.Name+' ('+$plan.Count+' apps)'); $item.Tag=$profile.Key; $item.Padding='10,6'
            $tip=New-Label ($profile.Description+"`n`n"+($plan.Name -join ', ')) '#F3F5F7' 12; $tip.MaxWidth=420; Set-UiValue ($item) 'ToolTip' $($tip)
            [Windows.Automation.AutomationProperties]::SetName($item,$profile.Name+' profile, '+$plan.Count+' apps')
            $item.Add_Click({ param($sender,$eventArgs) Apply-Profile ([string]$sender.Tag); $profileMenu.IsOpen=$false })
            $profileItems[$profile.Key]=$item; $profileMenu.Items.Add($item) | Out-Null
        }
    }
    $profileMenu.Add_Opened({ Animate-Appearance $profileMenu 3 })
    Set-UiValue ($ui.Profiles) 'ToolTip' $('Choose a profile to select its apps. Review and adjust before installing.')
    $ui.Profiles.Add_Click({ $profileMenu.IsOpen=$true })
    $userProfileMenu=New-Object Windows.Controls.ContextMenu
    $userProfileMenu.Resources=$window.Resources
    $userProfileMenu.PlacementTarget=$ui.UserProfiles
    $userProfileMenu.Placement='Bottom'
    $userProfileMenu.Add_Opened({ Animate-Appearance $userProfileMenu 3 })
    foreach ($action in @(@('Export','Save current selection...'),@('Import','Load saved profile...'))) {
        $item=New-Object Windows.Controls.MenuItem
        Set-UiValue ($item) 'Header' $($action[1])
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
        Set-UiValue ($ui.Status) 'Text' $('User profile loaded. Review your apps before installing.')
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
        $dialog = New-Object Windows.Window; $dialog.FlowDirection=$window.FindName('AppPanes').FlowDirection; $dialog.Language=$window.Language
        $dialog.WindowStyle='SingleBorderWindow'
        $dialog.Add_SourceInitialized({ [FirstInstallWindow]::Apply([Windows.Interop.WindowInteropHelper]::new($dialog).Handle,$script:lightMode) | Out-Null })
        $dialogChrome=New-Object Windows.Shell.WindowChrome
        $dialogChrome.CaptionHeight=48; $dialogChrome.ResizeBorderThickness='6'
        $dialogChrome.GlassFrameThickness='0'; $dialogChrome.UseAeroCaptionButtons=$false
        [Windows.Shell.WindowChrome]::SetWindowChrome($dialog,$dialogChrome)
        $dialog.Icon=$window.Icon; Set-UiValue ($dialog) 'Title' $('Review installation'); $dialog.Width=580; $dialog.Height=570; $dialog.Owner=$window
        $dialog.WindowStartupLocation='CenterOwner'; $dialog.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'DialogFill'); $dialog.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'TextPrimaryBrush')
        $dialog.MinWidth=540; $dialog.MinHeight=540; $dialog.FontSize=13
        $dialog.FontFamily=$window.FontFamily; $dialog.Resources=$window.Resources
        $dock=New-Object Windows.Controls.DockPanel; $dock.Margin='20'
        $surface=New-Object Windows.Controls.Border; $surface.Style=$window.Resources['GlassPanel']; $surface.Margin='12'; $surface.Child=$dock; Set-UiValue ($dialog) 'Content' $($surface)
        $title=New-Label 'Ready to install?' '#F3F5F7' 23; $title.Margin='0,0,0,18'
        [Windows.Controls.DockPanel]::SetDock($title,'Top'); $dock.Children.Add($title) | Out-Null
        $bottom=New-Object Windows.Controls.StackPanel
        [Windows.Controls.DockPanel]::SetDock($bottom,'Bottom'); $dock.Children.Add($bottom) | Out-Null
        $info=New-Label 'Guided apps open their official websites for manual installation. For Peace, install Equalizer APO first, choose your audio device and follow any restart instructions before setting up Peace.' '#C2CADE' 12
        $info.Margin='0,16,0,16'; $bottom.Children.Add($info) | Out-Null
        $agree=New-Object Windows.Controls.CheckBox; Set-UiValue ($agree) 'Content' $('I accept the app licenses and WinGet source terms.'); $agree.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'TextPrimaryBrush'); $agree.Margin='0,0,0,16'
        $bottom.Children.Add($agree) | Out-Null
        $go=New-Object Windows.Controls.Button; Set-UiValue ($go) 'Content' $('Start installation'); $go.IsEnabled=$false; $go.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentBrush'); $go.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'AccentForegroundBrush')
        $agree.Add_Checked({ $go.IsEnabled=$true }); $agree.Add_Unchecked({ $go.IsEnabled=$false })
        $go.Add_Click({ $dialog.DialogResult=$true }); $bottom.Children.Add($go) | Out-Null
        $back=New-Object Windows.Controls.Button; Set-UiValue ($back) 'Content' $('Back'); $back.IsCancel=$true; $back.Margin='0,8,8,0'
        $back.Add_Click({ $dialog.DialogResult=$false }); $bottom.Children.Add($back) | Out-Null
        $scroll=New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility='Auto'
        $list=New-Object Windows.Controls.StackPanel; Set-UiValue ($scroll) 'Content' $($list)
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
        $outcomes=@{}
        try {
            foreach ($app in $Plan) {
                if ($Control.Stop) {
                    Emit 'status' $app.Key 'Cancelled · not started'; Emit 'progress' $app.Key ''
                    [OneInstallPackages]::Record('Install',$app.Key,'catalog',$app.Name,'Cancelled','Not started: stop after current requested.',0,$null) | Out-Null
                    continue
                }
                $blocked=@($app.Requires | Where-Object { -not $outcomes.ContainsKey($_) -or $outcomes[$_] -ne 'Success' })
                if ($blocked.Count) {
                    $outcomes[$app.Key]='Manual action required'
                    Emit 'status' $app.Key ('Manual action required · dependency not verified: '+($blocked -join ', '))
                    [OneInstallPackages]::Record('Install',$app.Key,'catalog',$app.Name,'Manual action required','Dependency not verified: '+($blocked -join ', '),0,$null) | Out-Null
                    Emit 'progress' $app.Key ''; continue
                }
                Emit 'status' $app.Key 'Preparing…'
                if ($app.Url) {
                    Emit 'url' $app.Key $app.Url
                    Emit 'status' $app.Key 'Manual install pending · official website'
                    $outcomes[$app.Key]='Manual action required'
                    [OneInstallPackages]::Record('Install',$app.Key,'guided',$app.Name,'Manual action required','Complete the official publisher installer, then refresh. Opening a website does not prove installation.',0,$null) | Out-Null
                    Emit 'progress' $app.Key ''
                    continue
                }
                $states=New-Object 'System.Collections.Generic.List[string]'
                foreach ($id in $app.Ids) {
                    Emit 'status' $app.Key ('Installing ' + $id + '…')
                    $out=Join-Path $LogDir (([guid]::NewGuid().ToString('N'))+'.out.log')
                    $err=$out+'.err.log'
                    try {
                        $result=[OneInstallPackages]::Install($Winget,$id,'winget',$app.Name,$LogDir)
                        $states.Add($result.Outcome); Emit 'log' $app.Key $result.Detail
                        if ($result.Outcome -ne 'Success') { break }
                    } catch { $states.Add('Failed'); Emit 'log' $app.Key $_.Exception.Message }
                }
                $state=if ($states -contains 'Failed') { 'Failed' } elseif ($states -contains 'Cancelled') { 'Cancelled' } elseif ($states -contains 'Restart required') { 'Restart required' } elseif ($states -contains 'Manual action required') { 'Manual action required' } elseif ($states -contains 'Unknown') { 'Unknown · refresh to verify' } else { 'Success' }
                $outcomes[$app.Key]=$state
                Emit 'status' $app.Key $state
                Emit 'progress' $app.Key ''
            }
        } catch { Emit 'error' '' $_.Exception.Message }
        finally { Emit 'done' '' '' }
    }
    function Set-Busy([bool]$Value) {
        $script:busy=$Value
        foreach ($name in @('UserProfiles','Profiles','ClearSelection','Import','UninstallMode','HistoryMode')) { if ($ui[$name]) { $ui[$name].IsEnabled = -not $Value } }
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
        Set-QueueProgress 0; Set-UiValue ($ui.Status) 'Text' $('Installation in progress…')
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
            Set-UiValue ($ui.Status) 'Text' $('Could not start. See the logs for details.')
        }
    })
    $ui.Cancel.Add_Click({
        if ($script:busy) { $script:control.Stop=$true; $ui.Cancel.IsEnabled=$false; Set-UiValue ($ui.Status) 'Text' $('Stopping after the current app.'); Add-Log 'Stop requested. Waiting for the current installer.' }
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
                'error' { Add-Log $event.Text; Set-UiValue ($ui.Status) 'Text' $('Something went wrong. See the logs for details.') }
                'url' {
                    try { Start-Process $event.Text }
                    catch { Add-Log ('Could not open: ' + $event.Text) }
                }
                'progress' { $script:completed++; Set-QueueProgress (100*$script:completed/$script:total); Set-UiValue ($ui.Status) 'Text' $("$script:completed of $script:total processed") }
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
            Set-UiValue ($ui.Status) 'Text' $("Queue finished · $failed failed · $manual manual installs pending.")
            if ($script:control.Stop) { Set-UiValue ($ui.Status) 'Text' $('Queue stopped after the current app. Review the results.') }
            Set-Busy $false
            Refresh-LibraryInventory
        }
    })
    function Update-CardLayout {
        foreach ($name in @('RemovalGuidance','LeftoverGuidance')) {
            $window.FindName($name).Visibility=if ($window.ActualHeight -lt 650) { 'Collapsed' } else { 'Visible' }
        }
        foreach ($pair in @(@('InstallSearchRow','ProfilesTools','LibrarySearchFrame'),@('UninstallSearchRow','RemovalTools','InstalledSearchFrame'))) {
            $row=$window.FindName($pair[0]); $tools=$window.FindName($pair[1]); $frame=$window.FindName($pair[2])
            $narrow=($ui.InstallLibrary.Parent.ColumnDefinitions[1].ActualWidth-32) -lt 540
            $row.ColumnDefinitions[1].Width=if ($narrow) { '0' } else { 'Auto' }
            $row.RowDefinitions[1].Height=if ($narrow) { '76' } else { '0' }
            [Windows.Controls.Grid]::SetRow($tools,$(if ($narrow) { 1 } else { 0 }))
            [Windows.Controls.Grid]::SetColumn($tools,$(if ($narrow) { 0 } else { 1 }))
            $tools.Margin=if ($narrow) { '0,8,0,0' } else { '0' }
            $tools.VerticalAlignment=if ($narrow) { 'Top' } else { 'Center' }
            $frame.Margin=if ($narrow) { '0' } else { '0,0,12,0' }
        }
        $available=$ui.LibraryScroll.ViewportWidth
        if ($available -le 0 -or [double]::IsInfinity($available)) { return }
        if ($nativeCards) {
            [OneInstall.NativeUI]::Layout($ui.Cards,$available,$ui.LibraryScroll.ViewportHeight,$ui.LibraryScroll.VerticalOffset)
        } else {
            $ui.Cards.Columns=[Math]::Max(1,[Math]::Min(6,[Math]::Floor(($available+8)/192)))
            $ui.Cards.Width=$available+8
        }
        $window.FindName('InstallSearchRow').Width=$available
    }
    $ui.LibraryScroll.Add_ScrollChanged({
        param($sender,$scrollEvent)
        if ($scrollEvent.ViewportWidthChange -ne 0) { Update-CardLayout }
        elseif ($nativeCards) { [OneInstall.NativeUI]::Realize($ui.Cards,$ui.LibraryScroll) }
    })
    $window.Add_Loaded({ Update-CardLayout })
    $window.Add_SizeChanged({ Update-CardLayout })
    $window.Add_Closing({
        param($sender,$eventArgs)
        if ($script:busy -and $script:job) {
            $eventArgs.Cancel=$true
            $script:control.Stop=$true
            Set-UiValue ($ui.Status) 'Text' $('Wait for the current installer to finish, then close this window.')
            $ui.Cancel.IsEnabled=$false
        }
    })
    $script:mode='Install'
    $script:installedApps=@()
    $script:installedKind='All'
    $script:syncingUninstallSelection=$false
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
        if ($script:syncingUninstallSelection) { return }
        $chosen=@($script:installedApps | Where-Object { $_.Selected -and $_.CanRemove })
        $count=$chosen.Count
        $ui.UninstallQueuePanel.Children.Clear()
        $ui.UninstallQueuePanel.IsEnabled=-not $script:uninstallTask
        if ($count -eq 0) {
            $label=New-Label 'Choose installed apps to add them to your selection.' '#C2CADE'
            $label.Margin='0,15,0,0'; $ui.UninstallQueuePanel.Children.Add($label) | Out-Null
        }
        foreach ($app in $chosen) {
            $detail=(@($app.Kind,$app.Version) | Where-Object { $_ }) -join ' · '
            $row=New-SelectionRow $app $app.Name $detail {
                param($sender,$eventArgs)
                if ($script:uninstallTask) { return }
                $sender.Tag.Selected=$false; Update-UninstallSelection
            } (-not $script:uninstallTask)
            $ui.UninstallQueuePanel.Children.Add($row) | Out-Null
        }
        Set-UiValue ($ui.UninstallSelectedCount) 'Text' $("$count $(if ($count -eq 1) { 'app' } else { 'apps' }) selected")
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
        # Give WPF native models, not pipeline PSObject wrappers, so INotifyPropertyChanged reaches checkboxes.
        $ui.InstalledList.ItemsSource=[InstalledApp[]]$matches
        Set-UiValue ($ui.InstalledEmpty) 'Text' $(if ($script:uninstallTask -and $script:uninstallOperation -eq 'Inventory') { 'Reading installed apps…' } else { 'No apps found. Try another search or choose Refresh.' })
        $ui.InstalledEmpty.Visibility=if ($matches.Count -eq 0) { 'Visible' } else { 'Collapsed' }
        if ($script:mode -eq 'Uninstall') { Set-UiValue ($ui.ResultCount) 'Text' $('Installed · '+$matches.Count+' apps') }
        foreach ($name in @('InstalledAll','InstalledDesktop','InstalledStore')) {
            if ($ui[$name].Tag -eq $script:installedKind) { $ui[$name].SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentSurfaceBrush') }
            else { $ui[$name].SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'GlassControlFill') }
        }
    }
    function Set-UninstallTask($Task,[string]$Operation) {
        if ($script:uninstallTask) { throw 'A removal operation is already running.' }
        $script:uninstallTask=$Task; $script:uninstallOperation=$Operation
        foreach ($name in @('RefreshInstalled','InstalledList','UninstallQueuePanel','InstallMode','ReviewUninstall','CheckLeftovers','ClearUninstallSelection')) { $ui[$name].IsEnabled=$false }
        $ui.StopUninstall.Visibility=if ($Operation -eq 'Remove') { 'Visible' } else { 'Collapsed' }
        $ui.StopUninstall.IsEnabled=$true
        $uninstallTimer.Start()
    }
    function Refresh-InstalledApps {
        if ($script:uninstallTask -or $SmokeTest) { return }
        Set-UiValue ($ui.UninstallStatus) 'Text' $('Reading desktop and Microsoft Store apps…')
        Set-UninstallTask ([OneInstallUninstall]::InventoryAsync()) 'Inventory'
        Update-InstalledFilter
    }
    function Start-LeftoverScan {
        Set-UiValue ($ui.UninstallStatus) 'Text' $('Checking removed apps and protecting shared folders...')
        Set-UninstallTask ([OneInstallUninstall]::ScanAsync([InstalledApp[]]$script:uninstallTargets)) 'Scan'
    }
    function Set-AppMode([string]$Mode) {
        if ($script:busy -or $script:uninstallTask) { return }
        if ($script:settingsPage) { $script:settingsPage.Visibility='Collapsed' }
        if ($ui.ContainsKey('SettingsMode')) { $ui.SettingsMode.Background='Transparent' }
        $script:mode=$Mode; $uninstall=$Mode -eq 'Uninstall'
        $ui.InstallLibrary.Visibility=if ($uninstall) { 'Collapsed' } else { 'Visible' }
        $window.FindName('SetupGlass').Visibility=if ($uninstall) { 'Collapsed' } else { 'Visible' }
        $ui.CategoriesHost.Visibility=if ($uninstall) { 'Collapsed' } else { 'Visible' }
        $ui.UninstallNavigation.Visibility=if ($uninstall) { 'Visible' } else { 'Collapsed' }
        $ui.UninstallPage.Visibility=if ($uninstall) { 'Visible' } else { 'Collapsed' }
        $window.FindName('WindowControls').Margin='0,30,30,0'
        Set-UiValue ($ui.NavigationHeading) 'Text' $(if ($uninstall) { 'THIS PC' } else { 'LIBRARY' })
        foreach ($name in @('InstallMode','UninstallMode','HistoryMode')) {
            if (-not $ui[$name]) { continue }
            if ($name -eq $Mode+'Mode') { $ui[$name].SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentSurfaceBrush') }
            else { $ui[$name].Background='Transparent' }
        }
        if ($uninstall) {
            Update-InstalledFilter; Update-UninstallSelection
            if ($script:installedApps.Count -eq 0) { Refresh-InstalledApps }
        } else { Update-Filter -ForceAnimation }
    }
    function Show-RemovalReview($Items,[bool]$Leftovers=$false) {
        $dialog=New-Object Windows.Window; $dialog.FlowDirection=$window.FindName('AppPanes').FlowDirection; $dialog.Language=$window.Language; $script:removalDialog=$dialog
        Set-UiValue ($dialog) 'Title' $(if ($Leftovers) { 'Review leftovers · 1nstall' } else { 'Review removal · 1nstall' })
        $dialog.Width=760; $dialog.Height=[Math]::Min(660,[Windows.SystemParameters]::WorkArea.Height-40)
        $dialog.MinWidth=560; $dialog.MinHeight=450; $dialog.Owner=$window; $dialog.Icon=$window.Icon
        $dialog.WindowStartupLocation='CenterOwner'; $dialog.FontFamily=$window.FontFamily; $dialog.FontSize=13
        $chrome=New-Object Windows.Shell.WindowChrome; $chrome.CaptionHeight=24; $chrome.ResizeBorderThickness='6'; $chrome.GlassFrameThickness='0'; $chrome.UseAeroCaptionButtons=$false
        [Windows.Shell.WindowChrome]::SetWindowChrome($dialog,$chrome); $dialog.ShowInTaskbar=$false
        $dialog.Resources=$window.Resources; $dialog.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'OpaqueWindowFill'); $dialog.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'TextPrimaryBrush')
        $dialog.Add_SourceInitialized({ [FirstInstallWindow]::Apply([Windows.Interop.WindowInteropHelper]::new($dialog).Handle,$script:lightMode) | Out-Null })
        $dock=New-Object Windows.Controls.DockPanel; $dock.Margin='24'; Set-UiValue ($dialog) 'Content' $($dock)
        $head=New-Object Windows.Controls.StackPanel
        $head.Children.Add((New-Label $(if ($Leftovers) { 'Keep what matters' } else { 'Ready to make some room?' }) '#F3F5F7' 27)) | Out-Null
        $copy=if ($Leftovers) { 'Possible leftovers need your judgment. Product folders can contain settings, saves or personal app data. Choose only what you want to remove. Files go to the Recycle Bin; registry keys are backed up first.' } else { 'These apps will be removed one at a time using their own uninstallers. Finish any dialogs they open. Microsoft Store removal affects your current Windows account. Back up app data you want to keep.' }
        $note=New-Label $copy '#C2CADE' 13; $note.Margin='0,10,0,18'; $head.Children.Add($note) | Out-Null
        [Windows.Controls.DockPanel]::SetDock($head,'Top'); $dock.Children.Add($head) | Out-Null
        $bottom=New-Object Windows.Controls.StackPanel
        [Windows.Controls.DockPanel]::SetDock($bottom,'Bottom'); $dock.Children.Add($bottom) | Out-Null
        $agree=New-Object Windows.Controls.CheckBox; $agree.Style=$window.Resources['InstalledCheck']
        Set-UiValue ($agree) 'Content' $(New-Label $(if ($Leftovers) { 'I reviewed the selected paths and want to remove their contents.' } else { 'I reviewed this list and want to remove these apps and their app data.' }))
        $agree.Margin='0,18,0,16'; $bottom.Children.Add($agree) | Out-Null
        $actions=New-Object Windows.Controls.StackPanel; $actions.Orientation='Horizontal'; $actions.HorizontalAlignment='Right'; $bottom.Children.Add($actions) | Out-Null
        $back=New-Object Windows.Controls.Button; Set-UiValue ($back) 'Content' $('Keep / go back'); $back.IsCancel=$true; $back.Add_Click({ $dialog.DialogResult=$false }); $actions.Children.Add($back) | Out-Null
        $go=New-Object Windows.Controls.Button; Set-UiValue ($go) 'Content' $(if ($Leftovers) { 'Remove selected leftovers' } else { 'Remove '+$Items.Count+' apps' })
        $go.IsEnabled=$false; $go.Margin='0'; $go.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentActionBrush'); $go.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'AccentForegroundBrush')
        $go.Add_Click({ $dialog.DialogResult=$true }); $actions.Children.Add($go) | Out-Null
        $scroll=New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility='Auto'; $scroll.HorizontalScrollBarVisibility='Disabled'
        $list=New-Object Windows.Controls.StackPanel; Set-UiValue ($scroll) 'Content' $($list); $dock.Children.Add($scroll) | Out-Null
        if ($Leftovers) {
            $selectionBar=New-Object Windows.Controls.StackPanel; $selectionBar.Orientation='Horizontal'; $selectionBar.Margin='0,0,0,12'
            $selectAll=New-Object Windows.Controls.Button; Set-UiValue ($selectAll) 'Content' $('Select all'); $selectAll.Padding='12,6'
            $clearAll=New-Object Windows.Controls.Button; Set-UiValue ($clearAll) 'Content' $('Clear selection'); $clearAll.Padding='12,6'
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
                $check=New-Object Windows.Controls.CheckBox; $check.Style=$window.Resources['InstalledCheck']; Set-UiValue ($check) 'Content' $($labels); $check.Tag=$entry; $surface.Child=$check
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
        while ([OneInstallUninstall]::Progress.TryDequeue([ref]$message)) { Set-UiValue ($ui.UninstallStatus) 'Text' $($message); Add-UninstallLog $message }
        if (-not $script:uninstallTask -or -not $script:uninstallTask.IsCompleted) { return }
        $uninstallTimer.Stop()
        $operation=$script:uninstallOperation; $task=$script:uninstallTask
        $script:uninstallTask=$null
        foreach ($name in @('RefreshInstalled','InstalledList','UninstallQueuePanel','InstallMode')) { $ui[$name].IsEnabled=$true }
        $ui.StopUninstall.Visibility='Collapsed'
        try {
            if ($task.IsFaulted) { throw $task.Exception.GetBaseException().Message }
            $result=$task.Result
            if ($operation -eq 'Inventory') {
                $script:installedApps=@($result.Apps)
                foreach ($message in $result.Warnings) { Add-UninstallLog $message }
                Set-UiValue ($ui.UninstallStatus) 'Text' $(if ($script:uninstallOutcome) { $script:uninstallOutcome } else { $installedApps.Count.ToString()+' installed apps · '+$result.Warnings.Count+' scan warnings. Review details in Removal activity.' })
                Update-InstalledFilter
            } else {
                foreach ($message in $result.Messages) { Add-UninstallLog $message }
                if ($operation -eq 'Clean') {
                    foreach ($item in $result.Results) { [OneInstallPackages]::Record('Cleanup',$item.Id,'Windows registration',$item.Name,$item.Outcome,$item.Message,$item.ExitCode,$logPath) | Out-Null }
                }
                if ($operation -eq 'Remove') {
                    foreach ($item in $result.Results) {
                        [OneInstallPackages]::Record('Remove',$item.Id,'Windows registration',$item.Name,$item.Outcome,$item.Message,$item.ExitCode,$logPath) | Out-Null
                    }
                    Refresh-LibraryInventory
                    $script:uninstallTargets=@([OneInstallUninstall]::LoadHistory())
                    Start-LeftoverScan
                } elseif ($operation -eq 'Scan') {
                    $items=@($result.Leftovers)
                    $diskCount=@($items | Where-Object Kind -eq 'Folder').Count
                    $registryCount=@($items | Where-Object Kind -eq 'Registry').Count
                    $script:uninstallOutcome=if ($items.Count -gt 0) { $items.Count.ToString()+" verified cleanup candidates ($diskCount disk / $registryCount registry). Review paths before removal." } else { 'No cleanup candidates offered (0 disk / 0 registry). Removal or ownership may be unverified; see Removal activity for reasons.' }
                    Set-UiValue ($ui.UninstallStatus) 'Text' $($script:uninstallOutcome)
                    Add-UninstallLog $script:uninstallOutcome
                    if ($items.Count -gt 0 -and (Show-RemovalReview $items $true)) {
                        $chosen=[LeftoverItem[]]@($items | Where-Object Selected)
                        if ($chosen.Count -gt 0) { Set-UninstallTask ([OneInstallUninstall]::CleanAsync($chosen)) 'Clean' }
                    }
                    if (-not $script:uninstallTask) { Refresh-InstalledApps }
                } elseif ($operation -eq 'Clean') {
                    Add-UninstallLog ('Backups and item record: '+$result.BackupFolder)
                    $script:uninstallOutcome='Cleanup finished. Review item results in Removal activity. Registry backups are available in Open backups.'
                    Set-UiValue ($ui.UninstallStatus) 'Text' $($script:uninstallOutcome)
                    Refresh-InstalledApps
                }
            }
        } catch { Add-UninstallLog $_.Exception.Message; Set-UiValue ($ui.UninstallStatus) 'Text' $('Could not complete this step. Review Removal activity and try again.') }
        Update-UninstallSelection
    })
    $ui.InstallMode.Add_Click({ Set-AppMode 'Install' })
    $ui.UninstallMode.Add_Click({ Set-AppMode 'Uninstall' })
    $ui.RefreshInstalled.Add_Click({ Refresh-InstalledApps })
    $ui.WindowsAppsSettings.Add_Click({ Start-Process 'ms-settings:appsfeatures' })
    $ui.InstalledSearch.Add_TextChanged({ Update-InstalledFilter })
    $window.FindName('ClearInstalledSearch').Add_Click({ $ui.InstalledSearch.Clear(); $ui.InstalledSearch.Focus() | Out-Null })
    foreach ($name in @('InstalledAll','InstalledDesktop','InstalledStore')) {
        $ui[$name].Add_Click({ param($sender,$eventArgs) $script:installedKind=[string]$sender.Tag; Update-InstalledFilter })
    }
    $ui.InstalledList.AddHandler([Windows.Controls.Primitives.ToggleButton]::CheckedEvent,[Windows.RoutedEventHandler]{ Update-UninstallSelection })
    $ui.InstalledList.AddHandler([Windows.Controls.Primitives.ToggleButton]::UncheckedEvent,[Windows.RoutedEventHandler]{ Update-UninstallSelection })
    $ui.ClearUninstallSelection.Add_Click({
        if ($script:uninstallTask) { return }
        $script:syncingUninstallSelection=$true
        try { foreach ($app in $script:installedApps) { if ($app.Selected) { $app.Selected=$false } } }
        finally { $script:syncingUninstallSelection=$false }
        Update-UninstallSelection
    })
    $ui.ReviewUninstall.Add_Click({
        if ($script:uninstallTask -or $SmokeTest) { return }
        $plan=[InstalledApp[]]@($script:installedApps | Where-Object { $_.Selected -and $_.CanRemove })
        if ($plan.Count -gt 0 -and (Show-RemovalReview $plan)) { $script:uninstallOutcome=''; Set-UninstallTask ([OneInstallUninstall]::RemoveAsync($plan)) 'Remove' }
    })
    $ui.StopUninstall.Add_Click({ [OneInstallUninstall]::StopRequested=$true; $ui.StopUninstall.IsEnabled=$false; Set-UiValue ($ui.UninstallStatus) 'Text' $('Waiting for the current uninstaller. The next app will be kept.') })
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
            Set-UiValue ($ui.UninstallStatus) 'Text' $('Wait for the current removal/check to finish, then close this window.')
        }
    })
    $window.Add_Closed({ $uninstallTimer.Stop() })

    $managerUI = @'
@@MANAGER_UI@@
'@
    if ($managerUI.Trim().StartsWith('@@')) { $managerUI=[IO.File]::ReadAllText((Join-Path $ResourceRoot 'src/manager-ui.ps1')) }
    . ([scriptblock]::Create($managerUI))
    Update-Selection; Set-AppMode 'Install'
    Initialize-AppSettings
    if ($nativeCards) { [OneInstall.NativeUI]::Layout($ui.Cards,$window.Width-560,$window.Height-190,0) }
    if ($StartupTest) {
        $window.Resources['BeforeShowMs']=$StartupClock.ElapsedMilliseconds
        $window.Add_Loaded({ $window.Resources['LoadedMs']=$StartupClock.ElapsedMilliseconds })
        $window.Add_ContentRendered({
            $window.Resources['RenderMs']=$StartupClock.ElapsedMilliseconds
            $window.Dispatcher.BeginInvoke([Action]{
                $window.Tag=$StartupClock.ElapsedMilliseconds

                $window.Close()
            },[Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
        })
        $window.ShowDialog() | Out-Null
        return
    }
    if ($ManagerTest) {
        $managerTestCode = @'
@@MANAGER_TEST@@
'@
        if ($managerTestCode.Trim().StartsWith('@@')) { $managerTestCode=[IO.File]::ReadAllText((Join-Path $ResourceRoot 'tests/manager-ui.ps1')) }
        . ([scriptblock]::Create($managerTestCode))
        $window.ShowDialog() | Out-Null
        'PASS: manager UI fixtures, compact library toolbar, sorted names, exact installed/unknown states, app details, history, snapshot preview, keyboard focus traversal and rendered scaling.'
        return
    }
    if ($SmokeTest) {
        if ($category -ne 'All apps' -or @($categoryGroups.Values | Where-Object IsExpanded).Count -ne 0 -or $ui.Cards.Children.Count -ne $catalog.Count) { throw 'Startup must show All apps with every category group closed.' }
        Set-GlassAppearance $false
        $window.UpdateLayout()
        foreach ($name in @('NavigationGlass','SetupGlass','RemovalGlass')) {
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
            if ($card.MinHeight -ne 140 -or $card.Content.Children.Count -ne 4 -or
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
        Set-UiValue ($ui.Search) 'Text' $('TeamSpeak')
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
        Set-UiValue ($ui.Search) 'Text' $('LocalSend')
        $script:removeButtons['affinity'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($selected.ContainsKey('affinity') -or $checks['affinity'].IsChecked -or $ui.Search.Text -ne 'LocalSend') { throw 'Setup removal did not preserve the filtered view.' }
        $script:removeButtons['apo'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($selected.ContainsKey('peace') -or $selected.ContainsKey('apo') -or $selected.Count -ne 1) { throw 'Setup removal left a broken dependency.' }
        Set-Busy $true
        if ($ui.SaveSetup.IsEnabled -or $script:removeButtons['extra_vlc'].IsEnabled) { throw 'Setup actions enabled while installing.' }
        Set-Busy $false
        Set-Selection @()
        if ($ui.SaveSetup.IsEnabled) { throw 'Empty setup can be saved.' }
        Set-UiValue ($ui.Search) 'Text' $('')
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
        if ($userProfileMenu.Items.Count -ne 3) { throw 'Missing user profile actions.' }
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
        Set-UiValue ($ui.Search) 'Text' $('LocalSend')
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
            if ($window.FontFamily.Source -ne 'Segoe UI') { throw 'Static body typography was not applied.' }
            foreach ($mode in @('Install','Uninstall')) {
                Set-AppMode $mode; Wait-WindowMessages; $window.Activate() | Out-Null
                $window.UpdateLayout()
                $panel=$window.FindName($(if ($mode -eq 'Install') { 'SetupGlass' } else { 'RemovalGlass' }))
                $origin=$panel.TranslatePoint([Windows.Point]::new(0,0),$window)
                $bounds=@($origin.X,$origin.Y,$panel.ActualWidth,$panel.ActualHeight)
                if ($mode -eq 'Install') { $setupBounds=$bounds }
                else {
                    for ($i=0; $i -lt 4; $i++) {
                        if ([Math]::Abs($bounds[$i]-$setupBounds[$i]) -gt 1) { throw 'Removal panel must occupy the same bounds as Setup.' }
                    }
                }
                $search=if ($mode -eq 'Install') { $ui.Search } else { $ui.InstalledSearch }
                $hint=$window.FindName($(if ($mode -eq 'Install') { 'SearchPlaceholder' } else { 'InstalledSearchPlaceholder' }))
                $search.Clear(); $ui.InstallMode.Focus() | Out-Null; Wait-WindowMessages
                if ($hint.Visibility -ne 'Visible') { throw 'Empty unfocused search needs its hint.' }
                $search.Focus() | Out-Null; Wait-WindowMessages
                if (-not $search.IsKeyboardFocusWithin -or $hint.Visibility -ne 'Collapsed') { throw 'Focused search hint must disappear.' }
                Set-UiValue ($search) 'Text' $('existing query'); $ui.InstallMode.Focus() | Out-Null; Wait-WindowMessages
                if ($hint.Visibility -ne 'Collapsed' -or $search.Text -ne 'existing query') { throw 'Search text must remain visible and unchanged.' }
                $search.Clear()
            }
            Set-AppMode 'Install'; Wait-WindowMessages
            $brand=$window.FindName('BrandHeader')
            if ($brand.Children.Count -ne 1 -or $brand.Children[0] -isnot [Windows.Controls.Image] -or $brand.Children[0].Source -isnot [Windows.Media.DrawingImage] -or [Windows.Automation.AutomationProperties]::GetName($brand.Children[0]) -ne '1nstall') { throw 'Brand header must contain only the accessible vector logo.' }
            if ((Get-DrawnText ([Windows.Media.VisualTreeHelper]::GetDrawing($window.FindName('SetupHeading')))) -ne 'Selection') { throw 'Integrated window controls clipped the selection heading.' }
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
                    $checks[$runtime.Key].BringIntoView(); $window.UpdateLayout(); Wait-WindowMessages
                    $title=$checks[$runtime.Key].Content.Children[0]
                    $drawn=Get-DrawnText ([Windows.Media.VisualTreeHelper]::GetDrawing($title))
                    if (($drawn -replace '\s','') -ne ($runtime.Name -replace '\s','')) { throw "Runtime version is hidden at width ${testWidth}: $($runtime.Name)." }
                }
                $ui.LibraryScroll.ScrollToTop(); $window.UpdateLayout(); Wait-WindowMessages
                # Sample the rendered background, including the translucent layers.
                $image=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $image.Render($window)
                foreach ($label in @($ui.ResultCount,$ui.SelectedCount,$visible[0].Content.Children[1])) {
                    $point=$label.TranslatePoint([Windows.Point]::new(1,$label.ActualHeight+2),$window)
                    $pixel=New-Object byte[] 4
                    if ($point.X -lt 0 -or $point.Y -lt 0 -or $point.X -ge $image.PixelWidth -or $point.Y -ge $image.PixelHeight) { throw "Contrast sample outside render: $($label.Name), point=$point, image=$($image.PixelWidth)x$($image.PixelHeight)" }; $image.CopyPixels([Windows.Int32Rect]::new([int]$point.X,[int]$point.Y,1,1),$pixel,4,0)
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
                    if ([Math]::Abs($position.X-4) -gt 1 -or [Math]::Abs($position.Y) -gt 1) { throw 'Filtered grid does not start at the first cell.' }
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
            Set-UiValue ($ui.Search) 'Text' $('LocalSend')
            $window.UpdateLayout()
            if ($ui.Cards.Children.Count -ne 1 -or $ui.Cards.Children[0].Tag -ne 'extra_localsend') { throw 'Search results did not compact.' }
            Set-UiValue ($ui.Search) 'Text' $('__no_matching_apps__')
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
                foreach ($label in @($ui.ResultCount,$ui.SelectedCount,$ui.Cards.Children[0].Content.Children[1])) {
                    $point=$label.TranslatePoint([Windows.Point]::new(1,$label.ActualHeight+2),$window)
                    $pixel=New-Object byte[] 4; if ($point.X -lt 0 -or $point.Y -lt 0 -or $point.X -ge $image.PixelWidth -or $point.Y -ge $image.PixelHeight) { throw "Contrast sample outside render: $($label.Name), point=$point, image=$($image.PixelWidth)x$($image.PixelHeight)" }; $image.CopyPixels([Windows.Int32Rect]::new([int]$point.X,[int]$point.Y,1,1),$pixel,4,0)
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
            if ($ui.InstallMode.IsEnabled -or $ui.RefreshInstalled.IsEnabled -or $ui.InstalledList.IsEnabled -or $ui.UninstallQueuePanel.IsEnabled) { throw 'Removal task did not lock conflicting actions.' }
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
            Set-UiValue ($ui.UninstallStatus) 'Text' $('Preview with fictional apps · no installed application has been removed.')
            Set-AppMode 'Uninstall'; $window.UpdateLayout(); Wait-WindowMessages
            if ($ui.InstalledList.Items.Count -ne 2 -or $ui.InstallLibrary.Visibility -ne 'Collapsed' -or $ui.CategoriesHost.Visibility -ne 'Collapsed') { throw 'Uninstall mode did not replace the library.' }
            if ($ui.InstallLibrary.Margin.Top -ne 32) { throw 'Library header lost its alignment with the sidebar wordmark.' }
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
            Set-UiValue ($ui.InstalledSearch) 'Text' $('Notes')
            if ($ui.InstalledList.Items.Count -ne 1 -or -not $fixture.Selected) { throw 'Installed search lost the removal selection.' }
            $ui.InstalledSearch.Clear(); $script:installedKind='Microsoft Store'; Update-InstalledFilter
            if ($ui.InstalledList.Items.Count -ne 1 -or $ui.InstalledList.Items[0].Kind -ne 'Microsoft Store') { throw 'Installed source filtering failed.' }
            $script:installedKind='All'
    $script:syncingUninstallSelection=$false; Update-InstalledFilter
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
                if ($script:uninstallTask -or $ui.UninstallStatus.Text -notlike '2 verified cleanup candidates (1 disk / 1 registry)*') { throw 'Mixed disk/registry scan did not open review or started cleanup without consent.' }
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
    if (-not (Test-Path variable:NativeWindow)) { [Windows.MessageBox]::Show($_.Exception.ToString(),'1nstall — error','OK','Error') | Out-Null }
    throw
}
