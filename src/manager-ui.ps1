# WPF extension: package service communicates only through completed Tasks and DTOs.
# Embedded by both portable builders; imported JSON is data, never evaluated.
$script:libraryInventory=New-Object PackageInventory
[OneInstallPackages]::WinGetPath=$winget
$script:libraryTask=$null
$script:installRetryKey=''
$script:libraryView='All apps'
$script:preferencesPath=Join-Path ([OneInstallPackages]::DataRoot) 'preferences.json'
function Save-LibraryView {
    if ($SmokeTest) { return }
    try {
        New-Item -ItemType Directory -Path ([OneInstallPackages]::DataRoot) -Force | Out-Null
        @{View=$script:libraryView} | ConvertTo-Json | Set-Content -LiteralPath $script:preferencesPath -Encoding UTF8
    } catch { Add-Log ('Could not remember view: '+$_.Exception.Message) }
}
function Refresh-LibraryInventory {
    if ($script:libraryTask -or $SmokeTest) { return }
    $ui.RefreshLibrary.IsEnabled=$false
    $ui.RefreshLibrary.ToolTip='Checking installed apps…'
    $script:libraryTask=[OneInstallPackages]::InventoryAsync()
    $libraryTimer.Start()
}
function Update-LibraryStates {
    foreach ($app in $catalog) {
        $state=[OneInstallPackages]::InstalledState($script:libraryInventory,[string[]]$app.Ids,'winget')
        [Windows.Automation.AutomationProperties]::SetHelpText($checks[$app.Key],$app.Description+' · '+$state+' · F1 for details')
    }
    Update-Filter
}
function New-InfoDialog([string]$Title,[string]$Text) {
    $d=New-Object Windows.Window
    $d.Title=$Title+' · 1nstall'; $d.Owner=$window; $d.Icon=$window.Icon
    $d.Width=640; $d.Height=[Math]::Min(680,[Windows.SystemParameters]::WorkArea.Height-40)
    $d.MinWidth=380; $d.MinHeight=360; $d.WindowStartupLocation='CenterOwner'
    $d.WindowStyle='None'; $d.ShowInTaskbar=$false
    $d.FontFamily=$window.FontFamily; $d.FontSize=13; $d.Resources=$window.Resources
    $d.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'OpaqueWindowFill'); $d.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'TextPrimaryBrush')
    $chrome=New-Object Windows.Shell.WindowChrome; $chrome.CaptionHeight=24; $chrome.ResizeBorderThickness='6'; $chrome.GlassFrameThickness='0'; $chrome.UseAeroCaptionButtons=$false
    [Windows.Shell.WindowChrome]::SetWindowChrome($d,$chrome)
    $d.Add_SourceInitialized({ param($sender,$e) [FirstInstallWindow]::Apply([Windows.Interop.WindowInteropHelper]::new($sender).Handle) | Out-Null })
    $dock=New-Object Windows.Controls.DockPanel; $dock.Margin='24'; $d.Content=$dock
    $header=New-Object Windows.Controls.Grid; $header.Margin='0,0,0,18'
    $heading=New-Label $Title '#F3F5F7' 27; $heading.FontWeight='SemiBold'; $heading.FontFamily=$window.Resources['HeadingFont']; $heading.Margin='0,0,44,0'
    $header.Children.Add($heading) | Out-Null
    $dismiss=New-Object Windows.Controls.Button; $dismiss.Content='×'; $dismiss.Style=$window.Resources['CaptionButton']; $dismiss.Width=28; $dismiss.Height=28; $dismiss.MinHeight=28; $dismiss.HorizontalAlignment='Right'; $dismiss.VerticalAlignment='Top'; $dismiss.ToolTip='Close'
    [Windows.Automation.AutomationProperties]::SetName($dismiss,'Close details')
    [Windows.Shell.WindowChrome]::SetIsHitTestVisibleInChrome($dismiss,$true)
    $dismiss.Add_Click({ param($sender,$e) [Windows.Window]::GetWindow($sender).Close() })
    $header.Children.Add($dismiss) | Out-Null
    [Windows.Controls.DockPanel]::SetDock($header,'Top'); $dock.Children.Add($header) | Out-Null
    $close=New-Object Windows.Controls.Button; $close.Content='Close'; $close.IsCancel=$true; $close.Margin='0,16,0,0'
    $close.Add_Click({ param($sender,$e) [Windows.Window]::GetWindow($sender).Close() })
    [Windows.Controls.DockPanel]::SetDock($close,'Bottom'); $dock.Children.Add($close) | Out-Null
    $box=New-Object Windows.Controls.TextBox; $box.Text=$Text; $box.IsReadOnly=$true; $box.TextWrapping='Wrap'; $box.VerticalScrollBarVisibility='Auto'; $box.Padding='0'; $box.Background='Transparent'; $box.BorderThickness='0'; $box.FontSize=13
    $dock.Children.Add($box) | Out-Null
    return @{Window=$d;Dock=$dock;Text=$box;Close=$close}
}
function Show-AppDetails([string]$Key) {
    $app=$byKey[$Key]
    $websiteUrl=if ($app.PSObject.Properties['Website'] -and $app.Website) { $app.Website } elseif ($app.Url) { $app.Url } else { 'Not verified in this catalog' }
    $publisher=if ($app.PSObject.Properties['Publisher']) { $app.Publisher } else { 'Not verified in this catalog' }
    $license=if ($app.PSObject.Properties['License'] -and $app.License -and $app.VerifiedOn) { $app.License+' · checked '+$app.VerifiedOn } else { 'Not verified; review publisher terms' }
    $info=New-InfoDialog $app.Name ''
    $info.Dock.Children.Remove($info.Text)
    $scroll=New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility='Auto'; $scroll.HorizontalScrollBarVisibility='Disabled'
    $content=New-Object Windows.Controls.StackPanel; $content.Margin='0,0,8,0'; $scroll.Content=$content
    $description=New-Label $app.Description '#C2CADE' 14; $description.Margin='0,0,0,18'; $content.Children.Add($description) | Out-Null
    $state=[OneInstallPackages]::InstalledState($script:libraryInventory,[string[]]$app.Ids,'winget')
    $dependencies=if ($app.Requires.Count) { (@($app.Requires | ForEach-Object { $byKey[$_].Name }) -join ', ') } else { 'None declared' }
    foreach ($section in @(
        @{Title='About';Rows=@(@('Category',$app.Category),@('Publisher',$publisher),@('License',$license),@('Official website',$websiteUrl))},
        @{Title='Installation';Rows=@(@('Method',$(if ($app.Ids.Count) { 'Automatic · WinGet' } else { 'Guided · publisher website' })),@('Installed state',$state),@('Package IDs',$(if ($app.Ids.Count) { $app.Ids -join ', ' } else { 'No verified package identity' })),@('Scope','WinGet aggregate; individual scopes are not reported.'),@('Dependencies',$dependencies))}
    )) {
        $panel=New-Object Windows.Controls.Border; $panel.CornerRadius='16'; $panel.Padding='16'; $panel.Margin='0,0,0,12'; $panel.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,'ContentFill')
        $fields=New-Object Windows.Controls.StackPanel; $panel.Child=$fields
        $label=New-Label $section.Title '#F3F5F7' 16; $label.FontWeight='SemiBold'; $label.Margin='0,0,0,6'; $fields.Children.Add($label) | Out-Null
        foreach ($row in $section.Rows) {
            $label=New-Label $row[0] '#C2CADE' 12; $label.Margin='0,10,0,3'; $fields.Children.Add($label) | Out-Null
            $value=New-Label $row[1] '#F3F5F7' 13; $fields.Children.Add($value) | Out-Null
        }
        $content.Children.Add($panel) | Out-Null
    }
    $website=New-Object Windows.Controls.Button; $website.Content='Open official website ↗'; $website.Tag=$websiteUrl; $website.IsEnabled=($websiteUrl -match '^https://'); $website.Margin='0,8,0,0'
    $website.Add_Click({ param($sender,$e) if ([string]$sender.Tag -match '^https://[^\s]+$') { Start-Process ([string]$sender.Tag) } })
    [Windows.Controls.DockPanel]::SetDock($website,'Bottom'); $info.Dock.Children.Insert(1,$website)
    $info.Dock.Children.Add($scroll) | Out-Null
    if ($SmokeTest) { $info.Window.Add_ContentRendered({
        if ($info.Window.WindowStyle -ne 'None' -or [FirstInstallWindow]::ReadNativeFrameEnabled([Windows.Interop.WindowInteropHelper]::new($info.Window).Handle) -ne 0 -or $content.Children.Count -ne 3) { throw 'Details must retain structured content and seamless app chrome.' }
        if ([Windows.Media.TextOptions]::GetTextRenderingMode($info.Window) -ne 'Grayscale' -or -not $info.Window.UseLayoutRounding) { throw 'Details lost shared text smoothing.' }
        if ($ManagerTest) { Capture-TestDialog $info.Window 'details' }; $info.Window.Close()
    }) }
    $info.Window.ShowDialog() | Out-Null
}
if (-not $nativeCards) {
foreach ($app in $catalog) {
    $check=$checks[$app.Key]
    $check.MinHeight=140
    $check.Content.Children[2].Text=if ($app.Ids.Count) { 'WinGet · automatic' } else { 'Website · guided' }
    if ($nativeCards) { $detail=$check.Content.Children[3] } else {
    $detail=New-Object Windows.Controls.Button; $detail.Content='Details'; $detail.Tag=$app.Key; $detail.Margin='0,8,0,0'; $detail.Padding='6,4'; $detail.MinHeight=28
    $detail.ToolTip='App details · F1 while the card is focused'
    [Windows.Automation.AutomationProperties]::SetName($detail,'Details for '+$app.Name)
    $check.Content.Children.Add($detail) | Out-Null
    }
}
}
$ui.Cards.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent,[Windows.RoutedEventHandler]{
    param($sender,$e)
    if ($e.Source -is [Windows.Controls.Button] -and $e.Source.Tag) { $e.Handled=$true; Show-AppDetails ([string]$e.Source.Tag) }
})
$ui.Cards.Add_PreviewKeyDown({ param($sender,$e)
    if ($e.Key -ne 'F1') { return }
    $element=$e.OriginalSource
    while ($element -is [Windows.Media.Visual] -and $element -isnot [Windows.Controls.CheckBox]) { $element=[Windows.Media.VisualTreeHelper]::GetParent($element) }
    if ($element -is [Windows.Controls.CheckBox]) { $e.Handled=$true; Show-AppDetails ([string]$element.Tag) }
})
$viewbar=$window.FindName('LibraryViews')
$script:viewButtons=@{}
foreach ($view in @('All apps','Installed')) {
    $b=New-Object Windows.Controls.Button; $b.Content=$view; $b.Tag=$view; $b.Padding='10,6'; $b.FontSize=12
    $b.Add_Click({ param($sender,$e) $script:libraryView=[string]$sender.Tag; $script:category='All apps'; Save-LibraryView; Update-Filter })
    $script:viewButtons[$view]=$b; $viewbar.Children.Add($b) | Out-Null
}
$ui.RefreshLibrary=New-Object Windows.Controls.Button; $ui.RefreshLibrary.Content='Refresh'; $ui.RefreshLibrary.Padding='10,6'; $ui.RefreshLibrary.FontSize=12
$ui.RefreshLibrary.Add_Click({ Refresh-LibraryInventory }); $viewbar.Children.Add($ui.RefreshLibrary) | Out-Null
if (-not $SmokeTest) {
    $script:libraryView='All apps'
    try {
        if ((Get-Item -LiteralPath $script:preferencesPath).Length -le 4096) {
            $prefs=Get-Content -LiteralPath $script:preferencesPath -Raw | ConvertFrom-Json
            if ($prefs.View -in @('All apps','Installed')) { $script:libraryView=$prefs.View }
        }
    } catch { }
}
# Update and history pages occupy the existing content columns.
$main=$ui.InstallLibrary.Parent
$script:managerPage=New-Object Windows.Controls.Grid; $script:managerPage.Margin='18,18,14,18'; $script:managerPage.Visibility='Collapsed'
[Windows.Controls.Grid]::SetColumn($script:managerPage,1); [Windows.Controls.Grid]::SetColumnSpan($script:managerPage,2)
$main.Children.Add($script:managerPage) | Out-Null
foreach ($spec in @(,@('History','History & diagnostics'))) {
    $b=New-Object Windows.Controls.Button; $b.Content=$spec[1]; $b.Tag=$spec[0]; $b.FontSize=12; $b.Padding='8,7'; $b.Margin='0,0,0,5'
    $ui[$spec[0]+'Mode']=$b
    $b.Add_Click({ param($sender,$e) Show-ManagerPage ([string]$sender.Tag) })
    $ui.InstallMode.Parent.Children.Add($b) | Out-Null
}
function Show-ManagerPage([string]$Mode) {
    if ($script:busy -or $script:uninstallTask) { return }
    Set-AppMode 'Install'
    $script:mode=$Mode
    $ui.InstallMode.Background='Transparent'; $ui[$Mode+'Mode'].SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'AccentSurfaceBrush')
    $ui.InstallLibrary.Visibility='Collapsed'; $window.FindName('SetupGlass').Visibility='Collapsed'; $ui.CategoriesHost.Visibility='Collapsed'
    $script:managerPage.Visibility='Visible'; $script:managerPage.Children.Clear()
    $dock=New-Object Windows.Controls.DockPanel; $script:managerPage.Children.Add($dock) | Out-Null
    $top=New-Object Windows.Controls.StackPanel; [Windows.Controls.DockPanel]::SetDock($top,'Top'); $dock.Children.Add($top) | Out-Null
    $top.Children.Add((New-Label 'Operation history' '#F3F5F7' 27)) | Out-Null
    $ui.ManagerStatus=New-Label 'Timestamped results and detailed logs. Retry requires a fresh state check and review.' '#C2CADE' 13
    $ui.ManagerStatus.Margin='0,9,0,15'; $top.Children.Add($ui.ManagerStatus) | Out-Null
    $bar=New-Object Windows.Controls.WrapPanel; $top.Children.Add($bar) | Out-Null
    $scroll=New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility='Auto'; $dock.Children.Add($scroll) | Out-Null
    $ui.ManagerList=New-Object Windows.Controls.StackPanel; $ui.ManagerList.Margin='0,12,0,0'; $scroll.Content=$ui.ManagerList
    $refresh=New-Object Windows.Controls.Button; $refresh.Content='Refresh history'; $refresh.Add_Click({ Render-History }); $bar.Children.Add($refresh) | Out-Null
    $diagnostic=New-Object Windows.Controls.Button; $diagnostic.Content='Review diagnostic export…'; $diagnostic.Add_Click({ Show-Diagnostics }); $bar.Children.Add($diagnostic) | Out-Null
    $licenses=New-Object Windows.Controls.Button; $licenses.Content='Licenses & credits'; $licenses.Add_Click({ Show-ThirdPartyNotices }); $bar.Children.Add($licenses) | Out-Null
    Render-History
}
foreach ($b in @($ui.InstallMode,$ui.UninstallMode)) { $b.Add_Click({ if (-not $script:busy -and -not $script:uninstallTask) { $script:managerPage.Visibility='Collapsed' } }) }
function Render-History {
    if ($script:mode -ne 'History') { return }
    $ui.ManagerList.Children.Clear()
    $records=@([OneInstallPackages]::History() | Select-Object -Last 100); [array]::Reverse($records)
    if ([OneInstallPackages]::HistoryError) { $ui.ManagerStatus.Text=[OneInstallPackages]::HistoryError }
    if (-not $records.Count) { $ui.ManagerList.Children.Add((New-Label 'Your operation history will appear here after installation or removal.' '#C2CADE' 15)) | Out-Null }
    foreach ($record in $records) {
        $panel=New-Object Windows.Controls.StackPanel; $panel.Margin='0,0,0,18'
        $panel.Children.Add((New-Label $record.Detail '#DCE1E7' 13)) | Out-Null
        if ($record.Action -eq 'Install' -and $record.Outcome -eq 'Failed' -and $record.Source -eq 'winget') {
            $matches=@($catalog | Where-Object { $_.Ids -contains $record.Id })
            if ($matches.Count -eq 1 -and [OneInstallPackages]::InstalledState($script:libraryInventory,[string[]]$matches[0].Ids,'winget') -eq 'Not installed') {
                $retry=New-Object Windows.Controls.Button; $retry.Content='Refresh & review installation again'; $retry.Tag=$matches[0].Key; $retry.HorizontalAlignment='Left'; $retry.Margin='0,8,0,0'
                $retry.Add_Click({ param($sender,$e) $script:installRetryKey=[string]$sender.Tag; Set-AppMode 'Install'; $script:managerPage.Visibility='Collapsed'; Refresh-LibraryInventory })
                $panel.Children.Add($retry) | Out-Null
            }
        }
        if ($record.LogPath -and (Test-Path -LiteralPath $record.LogPath) -and [IO.Path]::GetFullPath($record.LogPath).StartsWith([IO.Path]::GetFullPath($logDir)+'\',[StringComparison]::OrdinalIgnoreCase)) {
            $b=New-Object Windows.Controls.Button; $b.Content='Open detailed log'; $b.Tag=$record.LogPath; $b.HorizontalAlignment='Left'; $b.Margin='0,8,0,0'
            $b.Add_Click({ param($sender,$e) Start-Process notepad.exe -ArgumentList ([OneInstallPackages]::Quote([string]$sender.Tag)) }); $panel.Children.Add($b) | Out-Null
        }
        $ui.ManagerList.Children.Add($panel) | Out-Null
    }
}
function Show-Diagnostics {
    $info=New-InfoDialog 'Review diagnostics' ([OneInstallPackages]::Diagnostics()+"`r`n`r`nNo raw logs, app data or credentials are included. Review the text for anything personal before saving or sharing. Nothing is sent automatically.")
    $save=New-Object Windows.Controls.Button; $save.Content='Save reviewed diagnostics…'; $save.Tag=$info.Text.Text
    $save.Add_Click({ param($sender,$e) $dialog=New-Object Microsoft.Win32.SaveFileDialog; $dialog.Filter='Text (*.txt)|*.txt'; $dialog.FileName='1nstall-diagnostics.txt'; if ($dialog.ShowDialog($window)) { [IO.File]::WriteAllText($dialog.FileName,[string]$sender.Tag,[Text.Encoding]::UTF8) } })
    [Windows.Controls.DockPanel]::SetDock($save,'Bottom'); $info.Dock.Children.Insert(1,$save)
    if ($ManagerTest) { $info.Window.Add_ContentRendered({ Capture-TestDialog $info.Window 'diagnostics'; $info.Window.Close() }) }
    $info.Window.ShowDialog() | Out-Null
}
function Show-SetupPreview($Rows,[string]$Title) {
    $info=New-InfoDialog $Title 'This portable setup restores an app selection. It does not back up personal files, app settings or credentials, and cannot guarantee identical versions. Package availability is checked by WinGet when installation starts.'
    $list=New-Object Windows.Controls.StackPanel
    $scroll=New-Object Windows.Controls.ScrollViewer; $scroll.Content=$list; $scroll.VerticalScrollBarVisibility='Auto'
    $info.Dock.Children.Remove($info.Text); $info.Dock.Children.Add($scroll) | Out-Null
    $list.Children.Add((New-Label $info.Text.Text '#C2CADE' 12)) | Out-Null
    $choices=New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in $Rows) {
        $c=New-Object Windows.Controls.CheckBox; $c.Style=$window.Resources['InstalledCheck']; $c.Content=$row.Name+' · '+$row.State; $c.Tag=$row.Key; $c.IsEnabled=($row.Key -ne ''); $c.IsChecked=($row.Key -ne ''); $c.Margin='0,12,0,0'; $choices.Add($c); $list.Children.Add($c) | Out-Null
    }
    $go=New-Object Windows.Controls.Button; $go.Content='Use selected apps'; $go.Margin='0,14,0,0'; $go.Add_Click({ param($sender,$e) [Windows.Window]::GetWindow($sender).DialogResult=$true })
    [Windows.Controls.DockPanel]::SetDock($go,'Bottom'); $info.Dock.Children.Insert(1,$go)
    if ($SmokeTest) { $info.Window.Add_ContentRendered({ if ($ManagerTest) { Capture-TestDialog $info.Window 'snapshot' }; $info.Window.DialogResult=$false }) }
    if ($info.Window.ShowDialog()) { return @($choices | Where-Object { $_.IsChecked -and $_.IsEnabled } | ForEach-Object { [string]$_.Tag }) }
    return $null
}
# Extend existing profile handling: legacy selection remains compatible; snapshots carry identities.
function Load-UserProfile([string]$Path) {
    $setup=[OneInstallPackages]::ReadSetup($Path)
    $rows=New-Object 'System.Collections.Generic.List[object]'
    if ($setup.Version -eq 1) {
        $plan=@(Get-Plan ([string[]]$setup.Keys)) # validate before any selection mutation
        if ($SmokeTest) { Set-Selection ([string[]]$plan.Key); return }
        foreach ($app in $plan) { $state=if ($app.Ids.Count) { [OneInstallPackages]::InstalledState($script:libraryInventory,[string[]]$app.Ids,'winget') } else { 'Manual installation required' }; $rows.Add(@{Key=$app.Key;Name=$app.Name;State=$state}) }
    } else {
        foreach ($entry in $setup.Apps) {
            $matches=@($catalog | Where-Object { $_.Ids -contains $entry.Id -and $entry.Source -eq 'winget' })
            if ($matches.Count -eq 1) {
                $app=$matches[0]; $state=[OneInstallPackages]::InstalledState($script:libraryInventory,[string[]]$app.Ids,'winget')
                if ($state -eq 'Not installed') { $state='Missing · available in catalog' }
                $rows.Add(@{Key=$app.Key;Name=$app.Name;State=$state+' · recorded version '+$entry.Version})
            } else {
                $state=[OneInstallPackages]::InstalledState($script:libraryInventory,[string[]]@($entry.Id),$entry.Source)
                $rows.Add(@{Key='';Name=$entry.Name;State=$(if ($state.StartsWith('Installed ·')) { 'Already installed · '+$state } else { 'Unavailable in this catalog · use the publisher or WinGet manually' })})
            }
        }
    }
    $keys=Show-SetupPreview $rows 'Preview portable setup'
    if ($null -ne $keys) { Set-Selection ([string[]]$keys) }
}
$snapshotItem=New-Object Windows.Controls.MenuItem; $snapshotItem.Header='Save installed setup snapshot…'
$snapshotItem.Add_Click({
    if (-not $script:libraryInventory.Complete -and -not $script:libraryInventory.Partial) { [Windows.MessageBox]::Show($window,'Refresh installed status first. A snapshot needs verified exact identities.','Inventory required') | Out-Null; return }
    $snapshotPackages=@{}
    $rows=@($script:libraryInventory.Packages | Where-Object { [OneInstallPackages]::ValidId($_.Id) -and [OneInstallPackages]::ValidSource($_.Source) -and [OneInstallPackages]::InstalledState($script:libraryInventory,[string[]]@($_.Id),$_.Source).StartsWith('Installed ·') } | ForEach-Object { $key=$_.Source+':'+$_.Id; $snapshotPackages[$key]=$_; @{Key=$key;Name=$_.Name;State='Installed · '+$_.InstalledVersion+' · '+$_.Source} })
    if (-not $rows.Count) { [Windows.MessageBox]::Show($window,'No reliably identified installed apps were found. Guided and ambiguous apps are excluded.','Nothing to save') | Out-Null; return }
    $keys=Show-SetupPreview $rows 'Select installed apps to save'
    if ($null -eq $keys -or -not @($keys).Count) { return }
    $entries=New-Object 'System.Collections.Generic.List[SetupEntry]'
    foreach ($key in $keys) { $p=$snapshotPackages[$key]; $e=New-Object SetupEntry; $e.Id=$p.Id; $e.Source=$p.Source; $e.Name=$p.Name; $e.Version=$p.InstalledVersion; $entries.Add($e) }
    $dialog=New-Object Microsoft.Win32.SaveFileDialog; $dialog.Filter='1nstall setup (*.json)|*.json'; $dialog.FileName='installed-setup.json'
    if ($dialog.ShowDialog($window)) { try { [OneInstallPackages]::SaveSetup($dialog.FileName,$entries.ToArray()); Add-Log 'Installed setup snapshot saved.' } catch { [Windows.MessageBox]::Show($window,$_.Exception.Message,'Could not save setup') | Out-Null } }
})
$userProfileMenu.Items.Add($snapshotItem) | Out-Null
$libraryTimer=New-Object Windows.Threading.DispatcherTimer; $libraryTimer.Interval=[TimeSpan]::FromMilliseconds(250)
$libraryTimer.Add_Tick({
    if ($script:libraryTask -and $script:libraryTask.IsCompleted) {
        try {
            $script:libraryInventory=$script:libraryTask.GetAwaiter().GetResult(); $ui.RefreshLibrary.ToolTip=$script:libraryInventory.Message; Add-Log $script:libraryInventory.Message; Update-LibraryStates
            if ($script:installRetryKey) {
                $key=$script:installRetryKey; $script:installRetryKey=''
                if ([OneInstallPackages]::InstalledState($script:libraryInventory,[string[]]$byKey[$key].Ids,'winget') -eq 'Not installed') { Set-Selection @($key); $ui.Status.Text='State rechecked. Review the installation again.' }
                else { $ui.Status.Text='Retry withheld: app is installed or its current identity/state is unknown.' }
            }
        } catch { $ui.RefreshLibrary.ToolTip=$_.Exception.Message; Add-Log $_.Exception.Message; $script:installRetryKey='' }
        $script:libraryTask=$null; $ui.RefreshLibrary.IsEnabled=$true
    }
    if (-not $script:libraryTask) { $libraryTimer.Stop() }
})
$window.Add_Closed({ $libraryTimer.Stop() })
$window.Add_Loaded({ Refresh-LibraryInventory })
