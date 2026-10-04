# In-memory WPF operations only. Never starts an uninstaller.
param([string]$PreviewDirectory='')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
$probe={
    $window.Add_ContentRendered({
        function Pump {
            $frame=New-Object Windows.Threading.DispatcherFrame; $pumpTimer=New-Object Windows.Threading.DispatcherTimer
            $pumpTimer.Interval=[TimeSpan]::FromMilliseconds(500); $pumpTimer.Add_Tick({ $pumpTimer.Stop(); $frame.Continue=$false }); $pumpTimer.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
        }
        function App([string]$Id) { $app=New-Object InstalledApp; $app.Id=$Id; $app.Name='Queue fixture '+$Id; $app.Kind='Desktop'; $app.CanRemove=$true; $app.Selected=$true; return $app }
        function Stage([string]$Id,[string]$State) { $item=New-Object RemovalOutcome; $item.Id=$Id; $item.Name='Queue fixture '+$Id; $item.Outcome=$State; [OneInstallUninstall]::Stages.Enqueue($item); Pump }
        $originalScan=${function:Start-LeftoverScan}
        try {
            [OneInstall.Motion]::TestOverride=$false
            $script:installedApps=@((App 'first'),(App 'second')); Set-AppMode 'Uninstall'
            $script:fakeRemoval=New-Object 'System.Threading.Tasks.TaskCompletionSource[RemovalResult]'
            $script:fakeScan=New-Object 'System.Threading.Tasks.TaskCompletionSource[RemovalResult]'
            function Start-LeftoverScan { Set-UninstallTask $script:fakeScan.Task 'Scan' }
            Start-UninstallQueue ([InstalledApp[]]$script:installedApps)
            $label=$script:uninstallLabels['first']; $row=$label.Parent
            if ($ui.UninstallQueuePanel.Children.Count -ne 2 -or $ui.ReviewUninstall.IsEnabled) { throw 'Queue did not retain/lock both selected apps.' }
            Stage 'first' 'Removing…'
            if (-not [object]::ReferenceEquals($label,$script:uninstallLabels['first']) -or -not [object]::ReferenceEquals($row,$label.Parent) -or $script:uninstallProgress.Value -ne 0) { throw ('Running queue rebuilt its row or advanced before completion: sameLabel='+[object]::ReferenceEquals($label,$script:uninstallLabels['first'])+' sameParent='+[object]::ReferenceEquals($row,$label.Parent)+' progress='+$script:uninstallProgress.Value+' states='+($script:uninstallStates | ConvertTo-Json -Compress)) }
            if ($label.Tag.Visibility -ne 'Visible') { throw 'Removal phase segments missing.' }
            Stage 'first' 'Verifying…'
            if ($script:uninstallProgress.Value -ne 0 -or $script:uninstallStates['second'] -ne 'Queued') { throw 'Verification skipped or next app started prematurely.' }
            Stage 'first' 'Success'; Stage 'second' 'Removing…'
            if ($script:uninstallProgress.Value -ne 50) { throw 'Queue progress must count completed apps, not fake an uninstall percentage.' }
            $result=New-Object RemovalResult
            foreach ($pair in @(@('first','Success'),@('second','Manual action required'))) {
                $item=New-Object RemovalOutcome; $item.Id=$pair[0]; $item.Name=$pair[0]; $item.Outcome=$pair[1]; $result.Results.Add($item)
            }
            $script:fakeRemoval.SetResult($result); Pump
            if ($script:uninstallOperation -ne 'Scan' -or $ui.UninstallQueuePanel.Children.Count -ne 2) { throw 'Removal lost queue before leftover review.' }
            $script:fakeScan.SetResult((New-Object RemovalResult)); Pump
            $inventory=New-Object AppInventory; $fresh=App 'second'; $fresh.Selected=$false; $inventory.Apps.Add($fresh)
            $refresh=New-Object 'System.Threading.Tasks.TaskCompletionSource[AppInventory]'; Set-UninstallTask $refresh.Task 'Inventory'; $refresh.SetResult($inventory); Pump
            if ($ui.UninstallQueuePanel.Children.Count -ne 2 -or -not $fresh.Selected -or $script:uninstallLabels['first'].Text -ne 'Success' -or $script:uninstallLabels['second'].Text -ne 'Manual action required' -or -not $ui.ReviewUninstall.IsEnabled) { throw 'Inventory refresh erased results, selection or retry.' }
            Update-InstalledFilter; Pump
            if (@($script:uninstallQueue | Where-Object Selected).Count -ne 2) { throw 'Recycled list containers changed retained selection.' }
            # A later explicit check must update the same queue after a detached publisher finishes.
            $scan=New-Object RemovalResult; $success=New-Object RemovalOutcome; $success.Id='second'; $success.Name='second'; $success.Outcome='Success'; $scan.Results.Add($success)
            $checked=New-Object 'System.Threading.Tasks.TaskCompletionSource[RemovalResult]'; Set-UninstallTask $checked.Task 'Scan'; $checked.SetResult($scan); Pump
            if ($script:uninstallLabels['second'].Text -ne 'Success' -or $ui.ReviewUninstall.IsEnabled) { throw 'Reverified success was lost or can be removed again.' }
            if ($ui.UninstallStatus.Text -like 'Could not complete*') { throw ('Unexpected queue failure: '+$ui.UninstallLog.Text) }
            $window.Width=1040; $window.Height=540; $window.UpdateLayout(); Pump
            foreach ($name in @('ReviewUninstall','CheckLeftovers','OpenUninstallBackups')) {
                $button=$ui[$name]; $point=$button.TranslatePoint([Windows.Point]::new($button.ActualWidth,$button.ActualHeight),$window)
                if ($point.Y -gt $window.ActualHeight -or $point.X -gt $window.ActualWidth) { throw ('Compact queue clipped '+$name) }
            }
            if ($PreviewDirectory) {
                [IO.Directory]::CreateDirectory($PreviewDirectory) | Out-Null
                foreach ($theme in @('Dark','Light')) { foreach ($accent in @($false,$true)) {
                    $script:settings.Theme=$theme; $script:settings.WindowsAccent=$accent; $script:lastAccent=''; Update-WindowsAccent
                    # Render the real keyboard-focus trigger: it uses the same glass layers as hover.
                    $close=$ui.CloseWindow; $close.Focus() | Out-Null; $window.UpdateLayout(); Pump
                    $surface=$close.Template.FindName('Surface',$close)
                    if ($surface.CornerRadius.TopLeft -ne 9 -or $surface.Background -isnot [Windows.Media.GradientBrush]) { throw 'Caption glass surface missing.' }
                    $image=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32); $image.Render($window)
                    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
                    $file=Join-Path $PreviewDirectory ($theme+'-'+$accent+'.png'); $stream=[IO.File]::Create($file); try { $encoder.Save($stream) } finally { $stream.Dispose() }
                } }
            }
            $ui.ClearUninstallSelection.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            if ($script:uninstallQueue.Count -ne 0 -or $fresh.Selected -or $script:uninstallProgressPanel.Visibility -ne 'Collapsed') { throw 'Explicit clear failed.' }
            # A failed background operation must leave an honest result, not a running row forever.
            $script:installedApps=@((App 'failure')); $script:fakeRemoval=New-Object 'System.Threading.Tasks.TaskCompletionSource[RemovalResult]'
            Start-UninstallQueue ([InstalledApp[]]$script:installedApps); $script:fakeRemoval.SetException([InvalidOperationException]::new('Simulated failure')); Pump
            if ($script:uninstallStates['failure'] -ne 'Unknown' -or $script:uninstallTask -or -not $ui.ReviewUninstall.IsEnabled) { throw 'Fault left queue running or locked.' }
            Write-Host 'PASS: stable removal rows, phase updates, confirmed progress, child-pending/manual results, inventory refresh, later verification, retry, explicit clear, compact layout and task faults.'
        } finally { Set-Item function:Start-LeftoverScan $originalScan; $window.Close() }
    })
}
$source=[IO.File]::ReadAllText((Join-Path $repo 'vexan_installers.ps1'))
if (-not $source.Contains('([OneInstallUninstall]::RemoveAsync($Plan))')) { throw 'Removal seam not found; refusing to run.' }
$source=$source.Replace('([OneInstallUninstall]::RemoveAsync($Plan))','$script:fakeRemoval.Task').Replace('@@MANAGER_TEST@@',$probe.ToString())
. ([scriptblock]::Create($source)) -ResourceRoot $repo -ManagerTest
