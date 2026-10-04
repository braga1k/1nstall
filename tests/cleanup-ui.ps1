# Isolated WPF fixtures. No installed app, registry or personal data is modified.
param([string]$PreviewDirectory='')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
$reviewProbe={
    $dialog.Width=560; $dialog.Height=520
    $dialog.Add_ContentRendered({
        $dialog.UpdateLayout()
        if ($Leftovers) {
            if ($scroll.ViewportHeight -lt 45) { throw ($script:language+': leftover list has insufficient room: '+$scroll.ViewportHeight) }
            foreach ($button in @($linkedOnly,$selectAll,$clearAll,$go,$back)) {
                $point=$button.TranslatePoint([Windows.Point]::new($button.ActualWidth,$button.ActualHeight),$dock)
                if ($point.X -gt $dock.ActualWidth+1 -or $point.Y -gt $dock.ActualHeight+1) { throw ($script:language+': action clipped: '+$button.Content) }
            }
            $linkedOnly.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            if (@($Items | Where-Object Selected).Count -ne @($Items | Where-Object Confidence -eq 'Linked path').Count -or $go.IsEnabled) { throw 'Linked-path selection includes name-only matches or bypasses consent.' }
            $clearAll.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            $scroll.ScrollToEnd(); $dialog.UpdateLayout()
            if ($scroll.ScrollableHeight -gt 0 -and [Math]::Abs($scroll.VerticalOffset-$scroll.ScrollableHeight) -gt 1) { throw 'Leftover list cannot reach its end.' }
        }
    })
}
$probe={
    $window.Add_ContentRendered({
        function Pump {
            $frame=New-Object Windows.Threading.DispatcherFrame; $timer=New-Object Windows.Threading.DispatcherTimer
            $timer.Interval=[TimeSpan]::FromMilliseconds(300); $timer.Add_Tick({ $timer.Stop(); $frame.Continue=$false }); $timer.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
        }
        try {
            [OneInstall.Motion]::TestOverride=$false; [OneInstall.Motion]::Stop()
            $app=New-Object InstalledApp; $app.Name='Example Editor'; $app.Id='cleanup-ui-fixture'; $app.Kind='Desktop'
            $folder=New-Object LeftoverItem; $folder.AppName=$app.Name; $folder.Owner=$app; $folder.Kind='Folder'; $folder.Path='C:\Example only\Example Editor'; $folder.Confidence='Linked path'; $folder.Reason='Recorded installation folder'; $folder.Bytes=5242880
            $key=New-Object LeftoverItem; $key.AppName=$app.Name; $key.Owner=$app; $key.Kind='Registry'; $key.Path='Software\Example Studio\Example Editor'; $key.Confidence='Name match'; $key.Reason='Exact product key; registry backup before removal'
            foreach ($language in $script:locales.PSObject.Properties.Name) {
                $script:settings.Language=$language; Apply-AppLanguage
                if (Show-RemovalReview @($folder,$key) $true) { throw 'UI check must never approve removal.' }
            }
            $script:settings.Language='en'; Apply-AppLanguage
            foreach ($single in @($folder,$key)) { if (Show-RemovalReview @($single) $true) { throw 'Single-kind review must not approve cleanup.' } }
            if ($PreviewDirectory) {
                [IO.Directory]::CreateDirectory($PreviewDirectory) | Out-Null
                foreach ($appearance in @('Dark','Light')) {
                    foreach ($accent in @($true,$false)) {
                        $script:settings.Theme=$appearance; $script:settings.WindowsAccent=$accent; $script:lastAccent=''; Update-WindowsAccent
                        $PreviewPath=Join-Path $PreviewDirectory ($appearance.ToLowerInvariant()+$(if ($accent) {''} else {'-monochrome'})+'.png')
                        Show-RemovalReview @($folder,$key) $true | Out-Null
                    }
                }
                $PreviewPath=''
            }
            Set-AppMode 'Uninstall'
            $installedCount=$ui.ResultCount.Text
            Update-LibraryStates
            if ($installedCount -notlike 'Installed*' -or $ui.ResultCount.Text -ne $installedCount) { throw ('Catalog refresh overwrote the Uninstall count: '+$installedCount+' -> '+$ui.ResultCount.Text) }
            foreach ($partial in @($false,$true)) {
                [OneInstall.Motion]::TestOverride=$true; [OneInstall.Motion]::ClearDecorations()
                $result=New-Object RemovalResult; $result.BackupFolder='Fictional preview'; $result.RecycledBytes=5242880
                $success=New-Object RemovalOutcome; $success.Id=$app.Id; $success.Name=$app.Name; $success.Kind='Folder'; $success.Outcome='Success'; $success.Message='UI fixture'; $result.Results.Add($success)
                if ($partial) { $failure=New-Object RemovalOutcome; $failure.Id=$app.Id; $failure.Name=$app.Name; $failure.Kind='Registry'; $failure.Outcome='Failed'; $failure.Message='UI fixture'; $result.Results.Add($failure) }
                $done=New-Object 'System.Threading.Tasks.TaskCompletionSource[RemovalResult]'
                Set-UninstallTask $done.Task 'Clean'; $done.SetResult($result); Pump
                if ($script:cleanupSummary.Visibility -ne 'Visible') { throw 'Cleanup result summary missing.' }
                if ($partial) {
                    if ($script:cleanupHeading.Text -ne 'Cleanup needs attention' -or $script:uninstallOutcome -notlike '*1 not completed*' -or @($window.FindName('MotionOverlay').Children | Where-Object Tag -eq 'ConfirmationGlow').Count -gt 0) { throw 'Partial cleanup shown as complete.' }
                } elseif ($script:cleanupHeading.Text -ne 'Cleanup complete' -or $script:uninstallOutcome -notlike '*1 recycled*') { throw 'Verified cleanup result missing.' }
                [OneInstall.Motion]::Stop()
            }
            Write-Host 'PASS: 51 localized cleanup reviews at 560x520, consent, linked-path selection, action bounds, scroll end, four appearances and complete/partial result summaries.'
        } finally { $window.Close() }
    })
}
$source=[IO.File]::ReadAllText((Join-Path $repo 'vexan_installers.ps1'))
$source=$source.Replace('$dialog.Add_ContentRendered({ [OneInstall.Motion]::Enter($dock,0,10,0) })',$reviewProbe.ToString())
$source=$source.Replace('@@MANAGER_TEST@@',$probe.ToString())
. ([scriptblock]::Create($source)) -ResourceRoot $repo -ManagerTest
