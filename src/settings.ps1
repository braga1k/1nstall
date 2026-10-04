# Embedded in the portable executable. Preferences never change Windows settings.
$localeJson=@'
@@LOCALES@@
'@
if ($localeJson.Trim().StartsWith('@@')) { $localeJson=[IO.File]::ReadAllText((Join-Path $ResourceRoot 'locales.json')) }
$script:locales=$localeJson | ConvertFrom-Json
$script:settings=@{Theme='System'; WindowsAccent=$true; Language='System'; AutoUpdate=$true}
$script:settingsPath=Join-Path $env:LOCALAPPDATA '1nstall\settings.json'
$script:settingsTest=([bool]$SmokeTest -or [bool]$StartupTest -or [bool]$SelfTest)
if ($script:settingsTest) { $script:settings.Language='en'; $script:settings.Theme='Dark'; $script:settings.AutoUpdate=$false }
else {
    try {
        if ((Get-Item -LiteralPath $script:settingsPath).Length -le 8192) {
            $saved=Get-Content -LiteralPath $script:settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($property in $saved.PSObject.Properties) {
                switch ($property.Name) {
                    'Theme' { if ($property.Value -in @('System','Light','Dark')) { $script:settings.Theme=$property.Value } }
                    'Language' { if ($property.Value -eq 'System' -or $script:locales.PSObject.Properties.Name -contains $property.Value) { $script:settings.Language=$property.Value } }
                    'WindowsAccent' { if ($property.Value -is [bool]) { $script:settings.WindowsAccent=$property.Value } }
                    'AutoUpdate' { if ($property.Value -is [bool]) { $script:settings.AutoUpdate=$property.Value } }
                }
            }
        }
    } catch { }
}
function Save-AppSettings {
    if ($script:settingsTest) { return }
    $temporary=$script:settingsPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($script:settingsPath)) | Out-Null
        [IO.File]::WriteAllText($temporary,($script:settings | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($script:settingsPath)) { [IO.File]::Replace($temporary,$script:settingsPath,[NullString]::Value) }
        else { [IO.File]::Move($temporary,$script:settingsPath) }
        return $true
    } catch {
        if ($script:settingsStatus) { Set-UiValue $script:settingsStatus 'Text' 'Could not save settings. Check folder permissions.' }
        return $false
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Resolve-AppLanguage([string]$Choice) {
    if ($Choice -ne 'System') { return $Choice }
    $code=[Globalization.CultureInfo]::CurrentUICulture.Name.ToLowerInvariant()
    if ($code.StartsWith('pt')) { return 'pt-PT' }
    if ($code.StartsWith('zh')) { return 'zh-Hans' }
    if ($code -eq 'no' -or $code.StartsWith('no-')) { return 'nb' }
    if ($code -eq 'cnr' -or $code.StartsWith('cnr-')) { return 'sr-Latn-ME' }
    while ($code) {
        if ($script:locales.PSObject.Properties.Name -contains $code) { return $code }
        $dash=$code.LastIndexOf('-'); if ($dash -lt 0) { break }; $code=$code.Substring(0,$dash)
    }
    return 'en'
}
$script:language=Resolve-AppLanguage $script:settings.Language
$script:settingsStatus=$null
$script:translationPatterns=@()
function Convert-UiText([string]$Text) {
    if (-not $Text -or $script:language -eq 'en') { return $Text }
    $pack=$script:locales.($script:language).Strings
    $property=$pack.PSObject.Properties[$Text]
    if ($property) { return [string]$property.Value }
    foreach ($pattern in $script:translationPatterns) {
        $match=[regex]::Match($Text,$pattern.Regex)
        if ($match.Success) {
            $translated=$pattern.Text
            for ($i=0;$i -lt $pattern.Count;$i++) {
                $part=$match.Groups[$i+1].Value
                $partTranslation=$pack.PSObject.Properties[$part]
                if ($partTranslation) { $part=[string]$partTranslation.Value }
                $translated=$translated.Replace('{'+$i+'}',$part)
            }
            return $translated
        }
    }
    return $Text
}
function Set-UiValue($Element,[string]$Property,$Value) {
    if ($Element -is [Windows.FrameworkElement] -and $Value -is [string] -and
        -not ($Element -is [Windows.Controls.TextBox] -and -not $Element.IsReadOnly)) {
        $Element.Resources['1nstall.i18n.'+$Property]=$Value
        $Value=Convert-UiText $Value
    }
    if ($Element.$Property -ne $Value) { $Element.$Property=$Value }
}
function Update-UiTree($Element,$Seen) {
    if ($Element -isnot [Windows.DependencyObject] -or -not $Seen.Add($Element)) { return }
    if ($Element -is [Windows.FrameworkElement]) {
        foreach ($property in @('Text','Content','Header','ToolTip')) {
            if (-not $Element.PSObject.Properties[$property]) { continue }
            if ($property -eq 'Text' -and $Element -isnot [Windows.Controls.TextBlock] -and -not ($Element -is [Windows.Controls.TextBox] -and $Element.IsReadOnly)) { continue }
            $key='1nstall.i18n.'+$property
            if ($Element.Resources.Contains($key)) { Set-UiValue $Element $property $Element.Resources[$key] }
            elseif ($Element.$property -is [string]) {
                # Application names and other model-bound values are content, not UI labels.
                $dp=if ($property -eq 'Text') { [Windows.Controls.TextBlock]::TextProperty } else { $null }
                if ($dp -and [Windows.Data.BindingOperations]::IsDataBound($Element,$dp)) { continue }
                Set-UiValue $Element $property $Element.$property
            }
        }
    }
    foreach ($child in [Windows.LogicalTreeHelper]::GetChildren($Element)) { Update-UiTree $child $Seen }
}
function Apply-AppLanguage {
    $script:language=Resolve-AppLanguage $script:settings.Language
    $script:translationPatterns=@()
    foreach ($property in $script:locales.($script:language).Strings.PSObject.Properties) {
        $tokens=[regex]::Matches($property.Name,'\{\d+\}')
        if (-not $tokens.Count) { continue }
        $pattern=[regex]::Escape($property.Name)
        foreach ($token in $tokens) { $pattern=$pattern.Replace([regex]::Escape($token.Value),'(.+?)') }
        $script:translationPatterns+=@{Regex='^'+$pattern+'$'; Text=[string]$property.Value; Count=$tokens.Count}
    }
    $seen=New-Object 'System.Collections.Generic.HashSet[Windows.DependencyObject]'
    Update-UiTree $window $seen
    foreach ($card in $checks.Values) { Update-UiTree $card $seen }
    $direction=if ($script:locales.($script:language).Rtl) { 'RightToLeft' } else { 'LeftToRight' }
    $window.FindName('AppPanes').FlowDirection=$direction
    # Window controls and technical logs keep their physical/system direction.
    foreach ($element in @($ui.LogBox,$ui.UninstallLog)) { $element.FlowDirection='LeftToRight' }
    $window.Language=[Windows.Markup.XmlLanguage]::GetLanguage($script:language)
    if ($script:settingsPage) { Update-UiTree $script:settingsPage $seen }
    if (Get-Command Update-CardLayout -ErrorAction SilentlyContinue) { Update-CardLayout }
}
function Get-AppLightMode {
    if ($script:settings.Theme -eq 'Light') { return $true }
    if ($script:settings.Theme -eq 'Dark') { return $false }
    try { return (Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme) -ne 0 } catch { return $false }
}
function Convert-MonochromeColor([Windows.Media.Color]$Color) {
    $gray=[byte][Math]::Round(0.2126*$Color.R+0.7152*$Color.G+0.0722*$Color.B)
    return [Windows.Media.Color]::FromArgb($Color.A,$gray,$gray,$gray)
}
function New-MaterialGradient($Stops,[double]$Tint=0,[string]$End='0.8,1') {
    $brush=New-Object Windows.Media.LinearGradientBrush
    $brush.StartPoint='0,0'; $brush.EndPoint=[Windows.Point]::Parse($End)
    foreach ($stop in $Stops) {
        $color=[Windows.Media.ColorConverter]::ConvertFromString($stop[1]); $alpha=$color.A
        if ($Tint -gt 0 -and $script:settings.WindowsAccent) { $color=Mix-Accent $color (Get-WindowsAccent) $Tint; $color.A=$alpha }
        $brush.GradientStops.Add([Windows.Media.GradientStop]::new($color,[double]$stop[0]))
    }
    return $brush
}
function Set-AppMaterials {
    # Restore the original dark decoration before applying either appearance.
    foreach ($key in $script:decorationTemplates.Keys) { $window.Resources[$key]=$script:decorationTemplates[$key] }
    # Accessibility colours remain authoritative; visual effects are already disabled.
    if ([Windows.SystemParameters]::HighContrast) { $window.Resources['InstalledCardFill']=$window.Resources['ContentFill']; return }
    if ($script:lightMode) {
        $colors=@{TextPrimaryBrush='#1A1D25'; TextSecondaryBrush='#414753'; CheckBorderBrush='#68717F'; FocusBrush='#333A48'; InputFill='#F6F7FA'; DialogFill='#E9EBF1'; GlassMenuFill='#F4F5F8'; SeparatorBrush='#87909F'; GroupFill='#20FFFFFF'; GroupEdge='#30838B9B'; GroupHoverFill='#70FFFFFF'; BevelBrush='#E6FFFFFF'; HoverEdgeBrush='#717B8C'; CardHoverEdgeBrush='#717B8C'; ReflectionEdgeBrush='#C0FFFFFF'}
        foreach ($key in $colors.Keys) { $window.Resources[$key]=[Windows.Media.BrushConverter]::new().ConvertFromString($colors[$key]) }
        $window.Resources['ContentFill']=(New-MaterialGradient @(@(0,'#FFFFFF'),@(0.42,'#F2F4F8'),@(1,'#DBE1E9')) 0.04).PSObject.BaseObject
        $window.Resources['GlassPanelFill']=(New-MaterialGradient @(@(0,'#EDFDFDFF'),@(0.32,'#D0E6EAF1'),@(0.72,'#C4CDD6E2'),@(1,'#E5F6F9FC')) 0.055).PSObject.BaseObject
        $window.Resources['GlassControlFill']=(New-MaterialGradient @(@(0,'#FAFFFFFF'),@(0.48,'#E8F0F2F7'),@(1,'#D4CAD4E0')) 0.035 '0.25,1').PSObject.BaseObject
        $window.Resources['GlassEdge']=(New-MaterialGradient @(@(0,'#F5FFFFFF'),@(0.18,'#DDAEB8C8'),@(0.5,'#85758095'),@(0.82,'#D0A4B4C7'),@(1,'#EBFFFFFF')) 0.1 '1,1').PSObject.BaseObject
        $window.Resources['CardEdge']=(New-MaterialGradient @(@(0,'#F8FFFFFF'),@(0.35,'#80919AAA'),@(1,'#D09AA7B9')) 0.06).PSObject.BaseObject
        $color=Get-WindowsAccent; $black=[Windows.Media.Colors]::Black; $text=$color
        for ($i=0;$i -lt 30 -and (((Get-Luminance ([Windows.Media.ColorConverter]::ConvertFromString('#CAD0D8')))+0.05)/((Get-Luminance $text)+0.05)) -lt 4.5;$i++) { $text=Mix-Accent $text $black 0.12 }
        $window.Resources['AccentTextBrush']=[Windows.Media.SolidColorBrush]::new($text)
        $window.Resources['AccentSurfaceBrush']=(New-MaterialGradient @(@(0,'#FFFFFF'),@(0.45,'#D8DDE5'),@(1,'#EEF0F5')) 0.18).PSObject.BaseObject
        $window.Resources['AccentMutedBrush']=[Windows.Media.SolidColorBrush]::new((Mix-Accent $color ([Windows.Media.Colors]::White) 0.25))
        foreach ($key in @('ButtonLightColor','CardLightColor','ReflectionColor','ReflectionSoftColor')) {
            $value=switch ($key) { 'ButtonLightColor' {'#C0FFFFFF'} 'CardLightColor' {'#B0FFFFFF'} 'ReflectionColor' {'#A8FFFFFF'} 'ReflectionSoftColor' {'#28FFFFFF'} }
            $window.Resources[$key]=[Windows.Media.ColorConverter]::ConvertFromString($value)
        }
        $window.Resources['GlassShadowColor']=[Windows.Media.ColorConverter]::ConvertFromString('#76849A')
        # Crisp dark type: depth comes from the surfaces and edges, not a text shadow.
        $window.Resources['TextShadowOpacity']=[double]0
        if (-not $script:lastGlass) {
            foreach ($key in @('GlassPanelFill','GlassControlFill','GlassEdge','CardEdge')) {
                $brush=$window.Resources[$key].CloneCurrentValue()
                foreach ($stop in $brush.GradientStops) { $shade=$stop.Color; $shade.A=255; $stop.Color=$shade }
                $window.Resources[$key]=$brush
            }
        }
    }
    if (-not $script:settings.WindowsAccent) {
        # Desaturate every semantic material and decorative colour, retaining alpha and stops.
        foreach ($key in @($window.Resources.Keys)) {
            $value=$window.Resources[$key]
            if ($value -is [Windows.Media.Color]) { $window.Resources[$key]=(Convert-MonochromeColor $value).PSObject.BaseObject }
            elseif ($value -is [Windows.Media.SolidColorBrush]) {
                $brush=$value.CloneCurrentValue(); $shade=Convert-MonochromeColor $brush.Color
                # Keep wallpaper colours behind the monochrome canvas.
                if ($key -eq 'WindowFill') { $shade.A=255 }
                $brush.Color=$shade; $window.Resources[$key]=$brush
            } elseif ($value -is [Windows.Media.GradientBrush]) {
                $brush=$value.CloneCurrentValue()
                foreach ($stop in $brush.GradientStops) { $stop.Color=Convert-MonochromeColor $stop.Color }
                $window.Resources[$key]=$brush
            }
        }
    }
    [OneInstallAppearance]::Apply($window,$script:lightMode,$script:settings.WindowsAccent,(Get-WindowsAccent),$script:lastGlass,$script:nativeGlass)
    $installedFill=$window.Resources['ContentFill'].CloneCurrentValue()
    if ($installedFill -is [Windows.Media.GradientBrush]) {
        foreach ($stop in $installedFill.GradientStops) { $shade=Convert-MonochromeColor $stop.Color; $shade.A=255; $stop.Color=$shade }
    } else { $installedFill.Color=Convert-MonochromeColor $installedFill.Color }
    $window.Resources['InstalledCardFill']=$installedFill
}
$script:settingsPage=$null; $script:updateTask=$null; $script:pendingRelease=$null; $script:restartAfterUpdate=$false
$script:updateStatus='Updates are checked in the background.'
if (-not $script:settingsTest -and [IO.File]::Exists((Join-Path $env:LOCALAPPDATA '1nstall\update-error.log'))) { $script:updateStatus='The previous update could not be applied. Move 1nstall to a writable folder and try again.' }
$script:updateRoot=Join-Path $env:LOCALAPPDATA '1nstall\Updates'
function Start-AppUpdateCheck {
    if ($script:settingsTest -or $script:updateTask) { return }
    if (-not (Test-Path variable:AppExecutable)) {
        $script:updateStatus='Automatic updates are available in 1nstall.exe.'
        if ($script:settingsStatus) { Set-UiValue $script:settingsStatus 'Text' $script:updateStatus }
        return
    }
    $script:updateStatus='Checking for updates…'
    if ($script:settingsStatus) { Set-UiValue $script:settingsStatus 'Text' $script:updateStatus }
    $script:updateTask=[OneInstallUpdate]::CheckAsync('3.4.0',$script:updateRoot,$true)
    $script:updateTimer.Start()
}
function Add-SettingsRow($Panel,[string]$Title,[string]$Description,$Control) {
    $surface=New-Object Windows.Controls.Border; $surface.CornerRadius='16'; $surface.Padding='18'; $surface.Margin='0,0,0,12'
    $surface.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,'ContentFill')
    $surface.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty,'CardEdge'); $surface.BorderThickness='1'
    $layers=New-Object Windows.Controls.Grid; $surface.Child=$layers
    $light=New-Object Windows.Controls.Border; $light.CornerRadius='15'; $light.Margin='-17'; $light.IsHitTestVisible=$false; $light.Opacity=0
    $light.Background=[Windows.Markup.XamlReader]::Parse('<RadialGradientBrush xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Center="0.3,0.2" GradientOrigin="0.3,0.2" RadiusX="0.85" RadiusY="1.3"><GradientStop Color="{DynamicResource CardLightColor}" Offset="0"/><GradientStop Color="#00FFFFFF" Offset="1"/></RadialGradientBrush>')
    $layers.Children.Add($light) | Out-Null
    $stack=New-Object Windows.Controls.StackPanel; $layers.Children.Add($stack) | Out-Null
    $surface.Add_MouseEnter({ param($sender,$e) $sender.Child.Children[0].SetResourceReference([Windows.UIElement]::OpacityProperty,'GlassHighlightsOpacity') })
    $surface.Add_MouseLeave({ param($sender,$e) $sender.Child.Children[0].Opacity=0 })
    $surface.Add_MouseMove({ param($sender,$e) if ($script:lastGlass -and (Test-MotionEnabled)) { $highlight=$sender.Child.Children[0]; Move-GlassLight $highlight ($e.GetPosition($highlight)) } })
    $label=New-Label $Title '#F3F5F7' 16; $label.FontWeight='SemiBold'; $stack.Children.Add($label) | Out-Null
    [Windows.Automation.AutomationProperties]::SetLabeledBy($Control,$label)
    if ($Description) { $label=New-Label $Description '#C2CADE' 12; $label.Margin='0,5,0,12'; $stack.Children.Add($label) | Out-Null }
    $Control.HorizontalAlignment='Left'; $stack.Children.Add($Control) | Out-Null
    $Panel.Children.Add($surface) | Out-Null
}
function New-SettingsChoice($Options,[string]$Selected) {
    $combo=New-Object Windows.Controls.ComboBox; $combo.MinWidth=190; $combo.MinHeight=38
    foreach ($entry in $Options) {
        $item=New-Object Windows.Controls.ComboBoxItem; $item.Tag=$entry[0]; Set-UiValue $item 'Content' $entry[1]
        $combo.Items.Add($item) | Out-Null
        if ($entry[0] -eq $Selected) { $combo.SelectedItem=$item }
    }
    return $combo
}
function Show-AppSettings {
    if ($script:busy -or $script:uninstallTask) { return }
    Set-AppMode 'Install'; $script:managerPage.Visibility='Collapsed'; $script:mode='Settings'
    $ui.InstallLibrary.Visibility='Collapsed'; $window.FindName('SetupGlass').Visibility='Collapsed'
    $ui.CategoriesHost.Visibility='Collapsed'; $script:settingsPage.Visibility='Visible'
    $ui.InstallMode.Background='Transparent'; $ui.SettingsMode.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentSurfaceBrush')
    $script:settingsContent.Children.Clear()
    $title=New-Label 'Settings' '#F3F5F7' 27; $title.Margin='0,0,0,22'; $script:settingsContent.Children.Add($title) | Out-Null
    $theme=New-SettingsChoice @(@('System','Use system setting'),@('Light','Light'),@('Dark','Dark')) $script:settings.Theme
    $ui.ThemeChoice=$theme
    $theme.Add_SelectionChanged({ param($sender,$e) if ($null -eq $sender.SelectedItem) { return }; $script:settings.Theme=[string]$sender.SelectedItem.Tag; Save-AppSettings | Out-Null; Update-WindowsAccent })
    Add-SettingsRow $script:settingsContent 'Theme' 'Choose the appearance of 1nstall.' $theme
    $accent=New-Object Windows.Controls.CheckBox; $accent.Style=$window.Resources['InstalledCheck']; Set-UiValue $accent 'Content' 'Use Windows accent colour'; $accent.IsChecked=$script:settings.WindowsAccent
    $ui.AccentChoice=$accent
    $accent.Add_Click({ param($sender,$e) $script:settings.WindowsAccent=[bool]$sender.IsChecked; Save-AppSettings | Out-Null; $script:lastAccent=''; Update-WindowsAccent })
    Add-SettingsRow $script:settingsContent 'Accent colour' 'Turn off for black and white, keeping gradients and depth.' $accent
    $options=@(,@('System','Use system setting'))
    foreach ($locale in ($script:locales.PSObject.Properties | Sort-Object { $_.Value.Name })) { $options+=,@($locale.Name,$locale.Value.Name) }
    $language=New-SettingsChoice $options $script:settings.Language; $ui.LanguageChoice=$language
    $language.Add_SelectionChanged({ param($sender,$e) if ($null -eq $sender.SelectedItem) { return }; $script:settings.Language=[string]$sender.SelectedItem.Tag; Save-AppSettings | Out-Null; Apply-AppLanguage })
    Add-SettingsRow $script:settingsContent 'Language' 'Changes apply immediately.' $language
    $updates=New-Object Windows.Controls.StackPanel
    $automatic=New-Object Windows.Controls.CheckBox; $automatic.Style=$window.Resources['InstalledCheck']; Set-UiValue $automatic 'Content' 'Automatic updates'; $automatic.IsChecked=$script:settings.AutoUpdate; $ui.AutoUpdateChoice=$automatic
    $automatic.Add_Click({ param($sender,$e) $script:settings.AutoUpdate=[bool]$sender.IsChecked; Save-AppSettings | Out-Null; if ($sender.IsChecked) { Start-AppUpdateCheck } })
    $updates.Children.Add($automatic) | Out-Null
    $script:settingsStatus=New-Label $script:updateStatus '#C2CADE' 12; $script:settingsStatus.Margin='0,10,0,10'; $updates.Children.Add($script:settingsStatus) | Out-Null
    $bar=New-Object Windows.Controls.WrapPanel
    $check=New-Object Windows.Controls.Button; Set-UiValue $check 'Content' 'Check now'; $check.Add_Click({ Start-AppUpdateCheck }); Enable-HoverMotion $check; $bar.Children.Add($check) | Out-Null
    $restart=New-Object Windows.Controls.Button; Set-UiValue $restart 'Content' 'Restart and update'; $restart.IsEnabled=$null -ne $script:pendingRelease; $ui.ApplyUpdate=$restart
    $restart.Add_Click({ if ($script:pendingRelease -and -not $script:busy -and -not $script:uninstallTask) { $script:restartAfterUpdate=$true; $window.Close() } })
    Enable-HoverMotion $restart
    $bar.Children.Add($restart) | Out-Null; $updates.Children.Add($bar) | Out-Null
    Add-SettingsRow $script:settingsContent '1nstall updates' 'New versions download in the background and are applied when you close the app.' $updates
    $about=New-Object Windows.Controls.WrapPanel
    foreach ($spec in @(@('GitHub','https://github.com/braga1k/1nstall'),@('Report a problem','https://github.com/braga1k/1nstall/issues'))) {
        $button=New-Object Windows.Controls.Button; Set-UiValue $button 'Content' $spec[0]; $button.Tag=$spec[1]
        $button.Add_Click({ param($sender,$e) Start-Process ([string]$sender.Tag) }); Enable-HoverMotion $button; $about.Children.Add($button) | Out-Null
    }
    Add-SettingsRow $script:settingsContent 'About' '1nstall 3.4.0' $about
    $index=0
    foreach ($row in $script:settingsContent.Children) { [OneInstall.Motion]::Enter($row,0,9,([Math]::Min(140,$index*28))); $index++ }
}
function Initialize-AppSettings {
    $script:settingsPage=New-Object Windows.Controls.ScrollViewer; $script:settingsPage.Visibility='Collapsed'; $script:settingsPage.VerticalScrollBarVisibility='Auto'; $script:settingsPage.Margin='18,32,18,18'
    [Windows.Controls.Grid]::SetColumn($script:settingsPage,1); [Windows.Controls.Grid]::SetColumnSpan($script:settingsPage,2)
    $script:settingsContent=New-Object Windows.Controls.StackPanel; $script:settingsContent.MaxWidth=780; $script:settingsContent.HorizontalAlignment='Stretch'; $script:settingsContent.Margin='0,0,14,0'
    $script:settingsPage.Content=$script:settingsContent; $ui.InstallLibrary.Parent.Children.Add($script:settingsPage) | Out-Null
    $settingsButton=New-Object Windows.Controls.Button; Set-UiValue $settingsButton 'Content' 'Settings'; $settingsButton.Padding='8,7'; $settingsButton.Margin='0,8,0,0'; $settingsButton.FontSize=12
    [Windows.Automation.AutomationProperties]::SetName($settingsButton,'Settings')
    $settingsButton.Add_Click({ Show-AppSettings }); $ui.SettingsMode=$settingsButton
    Enable-HoverMotion $settingsButton
    $donate=$window.FindName('Donate'); $dock=$donate.Parent; $index=$dock.Children.IndexOf($donate); $dock.Children.Remove($donate)
    $footer=New-Object Windows.Controls.StackPanel; [Windows.Controls.DockPanel]::SetDock($footer,'Bottom')
    $footer.Children.Add($settingsButton) | Out-Null; $footer.Children.Add($donate) | Out-Null; $dock.Children.Insert($index,$footer)
    foreach ($button in @($ui.InstallMode,$ui.UninstallMode,$ui.HistoryMode)) { $button.Add_Click({ if (-not $script:busy -and -not $script:uninstallTask) { $script:settingsPage.Visibility='Collapsed'; $ui.SettingsMode.Background='Transparent' } }) }
    Apply-AppLanguage
    $script:updateTimer=New-Object Windows.Threading.DispatcherTimer; $script:updateTimer.Interval=[TimeSpan]::FromSeconds(1)
    $script:updateTimer.Add_Tick({
        if ($script:updateTask -and $script:updateTask.IsCompleted) {
            try { $result=$script:updateTask.GetAwaiter().GetResult() }
            catch { $result=New-Object OneInstallRelease; $result.Error=$_.Exception.Message }
            $script:updateTask=$null; $script:updateTimer.Stop()
            if ($result.Error) { $script:updateStatus='Could not check or download the update. Try again later.' }
            elseif ($result.Path) { $script:pendingRelease=$result; $script:updateStatus='Update ready. It will be applied when you close 1nstall.' }
            else { $script:updateStatus='1nstall is up to date.' }
            if ($script:settingsStatus) { Set-UiValue $script:settingsStatus 'Text' $script:updateStatus }
            if ($ui.ContainsKey('ApplyUpdate')) { $ui.ApplyUpdate.IsEnabled=$null -ne $script:pendingRelease }
        }
    })
    $window.Add_ContentRendered({ if ($script:settings.AutoUpdate -and -not $script:settingsTest) { Start-AppUpdateCheck } })
    $window.Add_Closed({
        $script:updateTimer.Stop()
        if ($script:pendingRelease -and ($script:settings.AutoUpdate -or $script:restartAfterUpdate) -and -not $script:settingsTest -and (Test-Path variable:AppExecutable)) {
            try { [OneInstallUpdate]::Schedule($script:pendingRelease,$AppExecutable,$script:restartAfterUpdate) }
            catch { [IO.File]::WriteAllText((Join-Path $env:LOCALAPPDATA '1nstall\update-error.log'),$_.Exception.Message) }
        }
    })
}
