# WPF extension: package service communicates only through completed Tasks and DTOs.
# Embedded by both portable builders; imported JSON is data, never evaluated.
$script:libraryInventory=New-Object PackageInventory
[OneInstallPackages]::WinGetPath=$winget
$script:libraryTask=$null
$script:updateScan=$null
$script:updateTask=$null
$script:updateRows=@()
$script:retryUpdates=@()
$script:installRetryKey=''
$script:installedLabels=@{}
$script:libraryView='All apps'
$script:preferencesPath=Join-Path ([OneInstallPackages]::DataRoot) 'preferences.json'
$script:essentials=@($profilesByKey['essentials'].Apps)
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
    $ui.InventoryStatus.Text='Checking installed package identities… Browsing stays available.'
    $script:libraryTask=[OneInstallPackages]::InventoryAsync()
    $libraryTimer.Start()
}
function Update-LibraryStates {
    foreach ($app in $catalog) {
        if ($script:installedLabels.ContainsKey($app.Key)) {
            $state=[OneInstallPackages]::InstalledState($script:libraryInventory,[string[]]$app.Ids,'winget')
            $script:installedLabels[$app.Key].Text=$state
            [Windows.Automation.AutomationProperties]::SetHelpText($checks[$app.Key],$app.Description+' · '+$state+' · F1 for details')
        }
    }
    Update-Filter
}
function New-InfoDialog([string]$Title,[string]$Text) {
    $d=New-Object Windows.Window
    $d.Title=$Title+' · 1nstall'; $d.Owner=$window; $d.Icon=$window.Icon
    $d.Width=640; $d.Height=[Math]::Min(620,[Windows.SystemParameters]::WorkArea.Height-40)
    $d.MinWidth=380; $d.MinHeight=360; $d.WindowStartupLocation='CenterOwner'
    $d.FontFamily=$window.FontFamily; $d.Resources=$window.Resources
    $d.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'DialogFill'); $d.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,'TextPrimaryBrush')
    $dock=New-Object Windows.Controls.DockPanel; $dock.Margin='24'; $d.Content=$dock
    $heading=New-Label $Title '#F3F5F7' 23; $heading.Margin='0,0,0,16'
    [Windows.Controls.DockPanel]::SetDock($heading,'Top'); $dock.Children.Add($heading) | Out-Null
    $close=New-Object Windows.Controls.Button; $close.Content='Close'; $close.IsCancel=$true; $close.Margin='0,16,0,0'
    $close.Add_Click({ param($sender,$e) [Windows.Window]::GetWindow($sender).Close() })
    [Windows.Controls.DockPanel]::SetDock($close,'Bottom'); $dock.Children.Add($close) | Out-Null
    $box=New-Object Windows.Controls.TextBox; $box.Text=$Text; $box.IsReadOnly=$true; $box.TextWrapping='Wrap'; $box.VerticalScrollBarVisibility='Auto'; $box.Padding='12'
    $dock.Children.Add($box) | Out-Null
    return @{Window=$d;Dock=$dock;Text=$box;Close=$close}
}
function Show-AppDetails([string]$Key) {
    $app=$byKey[$Key]
    $websiteUrl=if ($app.PSObject.Properties['Website'] -and $app.Website) { $app.Website } elseif ($app.Url) { $app.Url } else { 'Not verified in this catalog' }
    $publisher=if ($app.PSObject.Properties['Publisher']) { $app.Publisher } else { 'Not verified in this catalog' }
    $license=if ($app.PSObject.Properties['License'] -and $app.License -and $app.VerifiedOn) { $app.License+' · catalog evidence checked '+$app.VerifiedOn } else { 'Not verified; review publisher terms' }
    $text=$app.Description+"`r`n`r`nPublisher: "+$publisher+"`r`nOfficial website: "+$websiteUrl+"`r`nLicense: "+$license+"`r`n`r`nInstallation: "+$(if ($app.Ids.Count) { 'WinGet · exact IDs '+($app.Ids -join ', ') } else { 'Guided download · '+$app.Url })+"`r`nInstalled state: "+[OneInstallPackages]::InstalledState($script:libraryInventory,[string[]]$app.Ids,'winget')+"`r`nScope: WinGet aggregate; individual scopes are not reported."+"`r`nDependencies: "+$(if ($app.Requires.Count) { (@($app.Requires | ForEach-Object { $byKey[$_].Name }) -join ', ') } else { 'None declared' })+"`r`n`r`nManual steps: "+$(if ($app.Key -eq 'peace') { 'Install Equalizer APO, choose your audio device and restart when requested before installing Peace.' } elseif ($app.Url) { 'Complete the publisher download and installer yourself. Refresh afterward; guided apps stay Unknown without a verified package identity.' } else { 'Follow publisher prompts, account requirements and restart instructions.' })
    $info=New-InfoDialog $app.Name $text
    $website=New-Object Windows.Controls.Button; $website.Content='Open official website'; $website.Tag=$websiteUrl; $website.IsEnabled=($websiteUrl -match '^https://'); $website.Margin='0,8,0,0'
    $website.Add_Click({ param($sender,$e) if ([string]$sender.Tag -match '^https://[^\s]+$') { Start-Process ([string]$sender.Tag) } })
    [Windows.Controls.DockPanel]::SetDock($website,'Bottom'); $info.Dock.Children.Insert(1,$website)
    if ($SmokeTest) { $info.Window.Add_ContentRendered({ if ($ManagerTest) { Capture-TestDialog $info.Window 'details' }; $info.Window.Close() }) }
    $info.Window.ShowDialog() | Out-Null
}
foreach ($app in $catalog) {
    $check=$checks[$app.Key]
    $check.MinHeight=210
    $check.Content.Children[2].Text=if ($app.Ids.Count) { 'WinGet · automatic' } else { 'Publisher website · guided' }
    $desc=New-Label $app.Description '#C2CADE' 12; $desc.MaxHeight=48; $desc.TextTrimming='CharacterEllipsis'; $desc.Margin='0,9,0,7'
    $check.Content.Children.Add($desc) | Out-Null
    $state=New-Label 'Unknown · refresh to check' '#DCE1E7' 11; $check.Content.Children.Add($state) | Out-Null
    $script:installedLabels[$app.Key]=$state
    $detail=New-Object Windows.Controls.Button; $detail.Content='Details'; $detail.Tag=$app.Key; $detail.Margin='0,8,0,0'; $detail.Padding='6,4'; $detail.MinHeight=28
    $detail.ToolTip='App details · F1 while the card is focused'
    [Windows.Automation.AutomationProperties]::SetName($detail,'Details for '+$app.Name)
    $detail.Add_Click({ param($sender,$e) $e.Handled=$true; Show-AppDetails ([string]$sender.Tag) })
    $check.Content.Children.Add($detail) | Out-Null
    $check.Add_PreviewKeyDown({ param($sender,$e) if ($e.Key -eq 'F1') { $e.Handled=$true; Show-AppDetails ([string]$sender.Tag) } })
}
# A small view bar keeps All apps within one click. Search always searches the catalog.
$viewbar=New-Object Windows.Controls.WrapPanel; $viewbar.Margin='0,0,0,10'
$hostGrid=[Windows.Controls.Grid]$ui.InstallLibrary
$hostGrid.RowDefinitions.Insert(2,[Windows.Controls.RowDefinition]::new())
$hostGrid.RowDefinitions[2].Height='Auto'
foreach ($child in @($hostGrid.Children)) { if ([Windows.Controls.Grid]::GetRow($child) -ge 2) { [Windows.Controls.Grid]::SetRow($child,([Windows.Controls.Grid]::GetRow($child)+1)) } }
[Windows.Controls.Grid]::SetRow($viewbar,2); $hostGrid.Children.Add($viewbar) | Out-Null
$script:viewButtons=@{}
foreach ($view in @('Essentials','All apps','Installed')) {
    $b=New-Object Windows.Controls.Button; $b.Content=$view; $b.Tag=$view; $b.Padding='10,6'; $b.FontSize=12
    $b.Add_Click({ param($sender,$e) $script:libraryView=[string]$sender.Tag; $script:category='All apps'; Save-LibraryView; Update-Filter })
    $script:viewButtons[$view]=$b; $viewbar.Children.Add($b) | Out-Null
}
$ui.RefreshLibrary=New-Object Windows.Controls.Button; $ui.RefreshLibrary.Content='Refresh status'; $ui.RefreshLibrary.Padding='10,6'; $ui.RefreshLibrary.FontSize=12
$ui.RefreshLibrary.Add_Click({ Refresh-LibraryInventory }); $viewbar.Children.Add($ui.RefreshLibrary) | Out-Null
$ui.InventoryStatus=New-Label 'Installed status has not been checked.' '#C2CADE' 11
$ui.InventoryStatus.MaxWidth=450; $ui.InventoryStatus.Margin='0,5,0,8'
$ui.Cards.Parent.Children.Insert(1,$ui.InventoryStatus)
$welcome=$window.FindName('Welcome'); $welcomeProfiles=$window.FindName('WelcomeProfiles')
foreach ($key in @('essentials','office','creator','development','gaming')) {
    $p=$profilesByKey[$key]; $b=New-Object Windows.Controls.Button; $b.Content=$p.Name; $b.Tag=$key; $b.Padding='9,6'; $b.FontSize=12; $b.ToolTip=$p.Description
    $b.Add_Click({ param($sender,$e) Apply-Profile ([string]$sender.Tag) }); $welcomeProfiles.Children.Add($b) | Out-Null
}
foreach ($b in $categoryButtons) { $b.Add_Click({ $script:libraryView='All apps'; Save-LibraryView; Update-Filter }) }
if (-not $SmokeTest) {
    $script:libraryView='Essentials'
    try {
        if ((Get-Item -LiteralPath $script:preferencesPath).Length -le 4096) {
            $prefs=Get-Content -LiteralPath $script:preferencesPath -Raw | ConvertFrom-Json
            if ($prefs.View -in @('Essentials','All apps','Installed')) { $script:libraryView=$prefs.View }
        }
    } catch { }
}
# Update and history pages occupy the existing content columns.
$main=$ui.InstallLibrary.Parent
$script:managerPage=New-Object Windows.Controls.Grid; $script:managerPage.Margin='18,18,14,18'; $script:managerPage.Visibility='Collapsed'
[Windows.Controls.Grid]::SetColumn($script:managerPage,1); [Windows.Controls.Grid]::SetColumnSpan($script:managerPage,2)
$main.Children.Add($script:managerPage) | Out-Null
foreach ($spec in @(@('Updates','Updates'),@('History','History & diagnostics'))) {
    $b=New-Object Windows.Controls.Button; $b.Content=$spec[1]; $b.Tag=$spec[0]; $b.FontSize=12; $b.Padding='8,7'; $b.Margin='0,0,0,5'
    $ui[$spec[0]+'Mode']=$b
    $b.Add_Click({ param($sender,$e) Show-ManagerPage ([string]$sender.Tag) })
    $ui.InstallMode.Parent.Parent.Children.Insert(2,$b)
}
function Show-ManagerPage([string]$Mode) {
    if ($script:busy -or $script:uninstallTask) { return }
    Set-AppMode 'Install'
    $script:mode=$Mode
    $ui.InstallLibrary.Visibility='Collapsed'; $window.FindName('SetupGlass').Visibility='Collapsed'; $ui.CategoriesHost.Visibility='Collapsed'
    $script:managerPage.Visibility='Visible'; $script:managerPage.Children.Clear()
    $dock=New-Object Windows.Controls.DockPanel; $script:managerPage.Children.Add($dock) | Out-Null
    $top=New-Object Windows.Controls.StackPanel; [Windows.Controls.DockPanel]::SetDock($top,'Top'); $dock.Children.Add($top) | Out-Null
    $top.Children.Add((New-Label $(if ($Mode -eq 'Updates') { 'Update Center' } else { 'Operation history' }) '#F3F5F7' 27)) | Out-Null
    $ui.ManagerStatus=New-Label $(if ($Mode -eq 'Updates') { 'Check available updates, select packages, then review. No unattended updates.' } else { 'Timestamped results and detailed logs. Retry requires a fresh state check and review.' }) '#C2CADE' 13
    $ui.ManagerStatus.Margin='0,9,0,15'; $top.Children.Add($ui.ManagerStatus) | Out-Null
    $bar=New-Object Windows.Controls.WrapPanel; $top.Children.Add($bar) | Out-Null
    $scroll=New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility='Auto'; $dock.Children.Add($scroll) | Out-Null
    $ui.ManagerList=New-Object Windows.Controls.StackPanel; $ui.ManagerList.Margin='0,12,0,0'; $scroll.Content=$ui.ManagerList
    if ($Mode -eq 'Updates') {
        foreach ($s in @(@('CheckUpdates','Check for updates'),@('ReviewUpdates','Review & update'),@('StopUpdates','Stop after current'),@('RetryUpdates','Retry failed…'))) {
            $b=New-Object Windows.Controls.Button; $b.Content=$s[1]; $ui[$s[0]]=$b; $bar.Children.Add($b) | Out-Null
        }
        $ui.CheckUpdates.Add_Click({ Refresh-Updates })
        $ui.ReviewUpdates.Add_Click({ Start-ReviewedUpdates })
        $ui.StopUpdates.IsEnabled=$false; $ui.StopUpdates.Add_Click({ [OneInstallPackages]::StopRequested=$true; $ui.StopUpdates.IsEnabled=$false; $ui.ManagerStatus.Text='Stopping after the current installer. Remaining packages will be Cancelled.' })
        $ui.RetryUpdates.Add_Click({ $script:retryUpdates=@([OneInstallPackages]::FailedUpdates() | ForEach-Object { $_.Source+':'+$_.Id }); Refresh-Updates })
        Render-Updates
    } else {
        $refresh=New-Object Windows.Controls.Button; $refresh.Content='Refresh history'; $refresh.Add_Click({ Render-History }); $bar.Children.Add($refresh) | Out-Null
        $diagnostic=New-Object Windows.Controls.Button; $diagnostic.Content='Review diagnostic export…'; $diagnostic.Add_Click({ Show-Diagnostics }); $bar.Children.Add($diagnostic) | Out-Null
        Render-History
    }
}
foreach ($b in @($ui.InstallMode,$ui.UninstallMode)) { $b.Add_Click({ if (-not $script:busy -and -not $script:uninstallTask) { $script:managerPage.Visibility='Collapsed' } }) }
function Refresh-Updates {
    if ($script:updateScan -or $script:updateTask) { return }
    $ui.CheckUpdates.IsEnabled=$false; $ui.ReviewUpdates.IsEnabled=$false
    $ui.ManagerStatus.Text='Checking structured inventory and WinGet pins…'
    $script:updateScan=[OneInstallPackages]::UpdatesAsync($winget)
    $libraryTimer.Start()
}
function Render-Updates {
    if ($script:mode -ne 'Updates') { return }
    $ui.ManagerList.Children.Clear()
    $holds=@()
    try { $holds=@([OneInstallPackages]::Exclusions()) } catch { $ui.ManagerStatus.Text=$_.Exception.Message; foreach ($p in $script:updateRows) { $p.Held=$true; $p.Selected=$false; $p.HoldReason='Hold file cannot be read; updates withheld' } }
    $info=New-Label 'Hold applies only in 1nstall, across sources, until released. It does not create a WinGet pin. All WinGet pins are respected, including ordinary pins. Ambiguous identities, versions or pin output withhold updates.' '#C2CADE' 12
    $info.Margin='0,0,0,15'; $ui.ManagerList.Children.Add($info) | Out-Null
    foreach ($p in $script:updateRows) {
        $panel=New-Object Windows.Controls.StackPanel; $panel.Margin='12'
        $border=New-Object Windows.Controls.Border; $border.Style=$window.Resources['GlassPanel']; $border.Margin='0,0,0,10'; $border.Child=$panel
        $check=New-Object Windows.Controls.CheckBox; $check.Style=$window.Resources['InstalledCheck']; $check.Content=$p.Name; $check.FontSize=16; $check.Tag=$p; $check.IsChecked=$p.Selected; $check.IsEnabled=-not $p.Held -and -not $script:updateTask
        $check.Add_Click({ param($sender,$e) $sender.Tag.Selected=($sender.IsChecked -eq $true); Update-UpdateSelection })
        $panel.Children.Add($check) | Out-Null
        $label=New-Label $p.Detail '#C2CADE' 12; $label.Margin='30,8,0,8'; $panel.Children.Add($label) | Out-Null
        $hold=New-Object Windows.Controls.Button; $hold.Content=if ($holds -contains $p.Id) { 'Release 1nstall hold' } else { 'Hold in 1nstall' }; $hold.Tag=$p.Id; $hold.HorizontalAlignment='Left'; $hold.Padding='8,5'; $hold.IsEnabled=-not $script:updateTask
        $hold.Add_Click({ param($sender,$e) try { [OneInstallPackages]::SetHold([string]$sender.Tag,([OneInstallPackages]::Exclusions() -notcontains [string]$sender.Tag)); Refresh-Updates } catch { $ui.ManagerStatus.Text=$_.Exception.Message } })
        $panel.Children.Add($hold) | Out-Null; $ui.ManagerList.Children.Add($border) | Out-Null
    }
    if (-not $script:updateRows.Count) { $ui.ManagerList.Children.Add((New-Label 'No confirmed updates loaded. Choose Check for updates. Unknown versions and guided apps are excluded.' '#C2CADE' 14)) | Out-Null }
    Update-UpdateSelection
}
function Update-UpdateSelection {
    if ($script:mode -eq 'Updates') {
        $ui.ReviewUpdates.IsEnabled=(-not $script:updateScan -and -not $script:updateTask -and @($script:updateRows | Where-Object { $_.Selected -and -not $_.Held }).Count -gt 0)
        $ui.RetryUpdates.IsEnabled=(-not $script:updateScan -and -not $script:updateTask -and [OneInstallPackages]::FailedUpdates().Count -gt 0)
    }
}
function Start-ReviewedUpdates {
    if ($script:updateTask -or $script:busy) { return }
    $reviewed=[PackageRecord[]]@($script:updateRows | Where-Object { $_.Selected -and -not $_.Held })
    if (-not $reviewed.Count) { return }
    $text=(@($reviewed | ForEach-Object { $_.Name+' · '+$_.Id+' · '+$_.Source+' · '+$_.InstalledVersion+' → '+$_.AvailableVersion }) -join "`r`n")+"`r`n`r`nUpdate only these exact packages to the reviewed versions? Publisher prompts may appear. Continue accepts their package and source agreements. No force, pin overrides or reboot permission is passed."
    if ([Windows.MessageBox]::Show($window,$text,'Review updates','OKCancel','Information') -ne 'OK') { return }
    Set-Busy $true; $ui.StopUpdates.IsEnabled=$true; $ui.CheckUpdates.IsEnabled=$false
    $script:updateTask=[OneInstallPackages]::UpdateAsync($winget,$reviewed,$logDir)
    $libraryTimer.Start()
    $ui.ManagerStatus.Text='Updating reviewed packages. Finish any publisher dialogs.'; Render-Updates
}
function Render-History {
    if ($script:mode -ne 'History') { return }
    $ui.ManagerList.Children.Clear()
    $records=@([OneInstallPackages]::History() | Select-Object -Last 100); [array]::Reverse($records)
    if ([OneInstallPackages]::HistoryError) { $ui.ManagerStatus.Text=[OneInstallPackages]::HistoryError }
    if (-not $records.Count) { $ui.ManagerList.Children.Add((New-Label 'Your operation history will appear here after installation, updates or removal.' '#C2CADE' 15)) | Out-Null }
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
            $script:libraryInventory=$script:libraryTask.GetAwaiter().GetResult(); $ui.InventoryStatus.Text=$script:libraryInventory.Message; Update-LibraryStates
            if ($script:installRetryKey) {
                $key=$script:installRetryKey; $script:installRetryKey=''
                if ([OneInstallPackages]::InstalledState($script:libraryInventory,[string[]]$byKey[$key].Ids,'winget') -eq 'Not installed') { Set-Selection @($key); $ui.Status.Text='State rechecked. Review the installation again.' }
                else { $ui.Status.Text='Retry withheld: app is installed or its current identity/state is unknown.' }
            }
        } catch { $ui.InventoryStatus.Text=$_.Exception.Message; $script:installRetryKey='' }
        $script:libraryTask=$null; $ui.RefreshLibrary.IsEnabled=$true
    }
    if ($script:updateScan -and $script:updateScan.IsCompleted) {
        try {
            $inv=$script:updateScan.GetAwaiter().GetResult()
            $script:updateRows=if ($inv.Complete) { @($inv.Packages | Where-Object { $_.UpdateAvailable -and [OneInstallPackages]::KnownVersion($_.InstalledVersion) -and [OneInstallPackages]::KnownVersion($_.AvailableVersion) }) } else { @() }
            foreach ($p in $script:updateRows) { if (-not $p.Held -and $script:retryUpdates -contains ($p.Source+':'+$p.Id)) { $p.Selected=$true } }
            $script:retryUpdates=@(); $script:updateScan=$null
            if ($script:mode -eq 'Updates') { $ui.ManagerStatus.Text=$inv.Message; $ui.CheckUpdates.IsEnabled=$true; Render-Updates }
        } catch { $script:updateScan=$null; if ($script:mode -eq 'Updates') { $ui.ManagerStatus.Text=$_.Exception.Message; $ui.CheckUpdates.IsEnabled=$true } }
    }
    $record=$null
    while ([OneInstallPackages]::Progress.TryDequeue([ref]$record)) { Add-Log $record.Detail; if ($script:mode -eq 'Updates') { $ui.ManagerStatus.Text=$record.Name+' · '+$record.Outcome+' · '+$record.Message } }
    if ($script:updateTask -and $script:updateTask.IsCompleted) {
        try { $results=$script:updateTask.GetAwaiter().GetResult(); $summary=(@($results | Group-Object Outcome | ForEach-Object { $_.Count+' '+$_.Name }) -join ' · '); Add-Log ('Update queue finished: '+$summary) } catch { $summary=$_.Exception.Message; Add-Log $summary }
        $script:updateTask=$null; Set-Busy $false
        foreach ($p in $script:updateRows) { $p.Selected=$false }
        if ($script:mode -eq 'Updates') { $ui.ManagerStatus.Text='Queue finished · '+$summary+'. Refresh before another review.'; $ui.StopUpdates.IsEnabled=$false; $ui.CheckUpdates.IsEnabled=$true; Render-Updates }
        Refresh-LibraryInventory
    }
    if (-not $script:libraryTask -and -not $script:updateScan -and -not $script:updateTask -and [OneInstallPackages]::Progress.IsEmpty) { $libraryTimer.Stop() }
})
$window.Add_Closed({ $libraryTimer.Stop() })
$window.Add_Closing({ param($sender,$e) if ($script:updateTask) { $e.Cancel=$true; [OneInstallPackages]::StopRequested=$true; $ui.ManagerStatus.Text='Wait for the current update to finish before closing.' } })
$window.Add_Loaded({ Refresh-LibraryInventory })
