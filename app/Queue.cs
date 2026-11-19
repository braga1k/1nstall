// The install queue: review, start, progress, per-app status, stopping and the end of the run.
// A port of Confirm-Plan, Set-Busy, Set-AppStatus, Set-QueueProgress and the install timer of
// vexan_installers.ps1. The queue itself runs inside the engine, on a thread of its own; this
// file asks it four times a second what happened, as the 3.6 timer does.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Shell;
using System.Windows.Threading;
using OneInstall;

static partial class Library {
    static DispatcherTimer queueTimer;
    static bool queueRunning, stopRequested, queueFailed;
    static int total, completed;
    static string logDirectory;
    // The interface test mode records the pages it would open instead of opening a browser.
    static bool openPages;

    // Set-QueueProgress
    static void SetQueueProgress(double value) {
        var progress=Find<ProgressBar>("Progress"); if(progress==null) return;
        AnimateValue(progress,RangeBase.ValueProperty,progress.Value,value,200);
    }

    // Set-AppStatus
    static void SetAppStatus(string key,string text) {
        statuses[key]=text;
        TextBlock label;
        if(statusLabels.TryGetValue(key,out label)) { I18n.Set(label,"Text",text); Motion.Phase(label,text); Motion.Result(label,text=="Success"); }
        Shell.AddLog((byKey.ContainsKey(key)?byKey[key].Name:key)+": "+text);
    }

    // Set-Busy: while a queue runs, the selection cannot change.
    static void SetBusy(bool value) {
        Busy=value;
        foreach(string name in new[]{"UserProfiles","Profiles","ClearSelection","UninstallMode","HistoryMode"}) { var control=Find<Control>(name); if(control!=null) control.IsEnabled=!value; }
        if(import!=null) import.IsEnabled=!value;
        if(value) { if(profilesMenu!=null) profilesMenu.IsOpen=false; if(userMenu!=null) userMenu.IsOpen=false; }
        foreach(var check in checks.Values) check.IsEnabled=!value;
        var cancel=Find<Button>("Cancel");
        if(cancel!=null) { cancel.Visibility=value?Visibility.Visible:Visibility.Collapsed; cancel.IsEnabled=value; }
        UpdateSelection();
    }

    // Confirm-Plan: the plan, and an explicit acceptance of the licences, before anything starts.
    // Rows are key, name and whether WinGet installs the app.
    static bool ConfirmPlan(string[] rows) {
        var panes=Find<FrameworkElement>("AppPanes");
        var dialog=new Window { FlowDirection=panes.FlowDirection, Language=window.Language, WindowStyle=WindowStyle.SingleBorderWindow, Icon=window.Icon, Width=580, Height=570, Owner=window, WindowStartupLocation=WindowStartupLocation.CenterOwner, MinWidth=540, MinHeight=540, FontSize=13, FontFamily=window.FontFamily, Resources=window.Resources };
        dialog.SourceInitialized+=delegate { FirstInstallWindow.Apply(new WindowInteropHelper(dialog).Handle,Theme.Light); };
        WindowChrome.SetWindowChrome(dialog,new WindowChrome { CaptionHeight=48, ResizeBorderThickness=new Thickness(6), GlassFrameThickness=new Thickness(0), UseAeroCaptionButtons=false });
        I18n.Set(dialog,"Title","Review installation");
        dialog.SetResourceReference(Control.BackgroundProperty,"DialogFill"); dialog.SetResourceReference(Control.ForegroundProperty,"TextPrimaryBrush");
        var dock=new DockPanel { Margin=new Thickness(20) };
        dialog.Content=new Border { Style=(Style)window.Resources["GlassPanel"], Margin=new Thickness(12), Child=dock };
        var title=Shell.NewLabel("Ready to install?",false,23); title.Margin=new Thickness(0,0,0,18);
        DockPanel.SetDock(title,Dock.Top); dock.Children.Add(title);
        var bottom=new StackPanel(); DockPanel.SetDock(bottom,Dock.Bottom); dock.Children.Add(bottom);
        var info=Shell.NewLabel("Guided apps open their official websites for manual installation. For Peace, install Equalizer APO first, choose your audio device and follow any restart instructions before setting up Peace.",true,12);
        info.Margin=new Thickness(0,16,0,16); bottom.Children.Add(info);
        var agree=new CheckBox { Margin=new Thickness(0,0,0,16) };
        I18n.Set(agree,"Content","I accept the app licenses and WinGet source terms.");
        agree.SetResourceReference(Control.ForegroundProperty,"TextPrimaryBrush");
        bottom.Children.Add(agree);
        var go=new Button { IsEnabled=false }; I18n.Set(go,"Content","Start installation");
        go.SetResourceReference(Control.BackgroundProperty,"AccentBrush"); go.SetResourceReference(Control.ForegroundProperty,"AccentForegroundBrush");
        agree.Checked+=delegate { go.IsEnabled=true; }; agree.Unchecked+=delegate { go.IsEnabled=false; };
        go.Click+=delegate { dialog.DialogResult=true; }; bottom.Children.Add(go);
        var back=new Button { IsCancel=true, Margin=new Thickness(0,8,8,0) }; I18n.Set(back,"Content","Back");
        back.Click+=delegate { dialog.DialogResult=false; }; bottom.Children.Add(back);
        var list=new StackPanel();
        foreach(string record in rows) {
            string[] fields=record.Split('\u001F');
            var label=Shell.NewLabel(fields[1]+"  ·  "+(fields[2]=="1"?"Automatic":"Guided"),false,14); label.Margin=new Thickness(0,5,0,5);
            list.Children.Add(label);
        }
        dock.Children.Add(new ScrollViewer { VerticalScrollBarVisibility=ScrollBarVisibility.Auto, Content=list });
        return dialog.ShowDialog()==true;
    }

    // The Install button.
    static void StartQueue() {
        if(Busy) return;
        string keys=SelectedKeys();
        string plan=keys.Length==0?"":Engine.Plan(keys);
        if(plan.Length==0 || plan.StartsWith("!",StringComparison.Ordinal)) return;
        string[] rows=plan.Split('\u001E');
        if(!ConfirmPlan(rows)) return;
        bool automatic=false; var names=new List<string>();
        foreach(string record in rows) { string[] fields=record.Split('\u001F'); names.Add(fields[1]); if(fields[2]=="1") automatic=true; }
        if(automatic && Engine.Winget().Length==0) {
            MessageBox.Show(window,"Install or update App Installer in the Microsoft Store, then reopen 1nstall.","WinGet missing");
            Process.Start("ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1");
            return;
        }
        total=rows.Length; completed=0; stopRequested=false; queueFailed=false;
        statuses.Clear();
        foreach(string record in rows) statuses[record.Split('\u001F')[0]]="Queued";
        SetQueueProgress(0); Shell.SetText("Status","Installation in progress…");
        SetBusy(true);
        string refused=Engine.QueueStart(keys,logDirectory);
        if(refused.Length>0) {
            Shell.AddLog(refused.Substring(1));
            SetBusy(false);
            Shell.SetText("Status","Could not start. See the logs for details.");
            return;
        }
        queueRunning=true; queueTimer.Start();
        Shell.AddLog("Queue started: "+String.Join(", ",names));
    }

    // The install timer: what the queue reported since the last tick, then the end of the run.
    static void QueueTick(object sender,EventArgs e) {
        if(!queueRunning) return;
        bool done=false;
        string events=Engine.QueueEvents();
        if(events.Length>0) foreach(string record in events.Split('\u001E')) {
            string[] fields=record.Split('\u001F'); if(fields.Length!=3) continue;
            switch(fields[0]) {
                case "status": SetAppStatus(fields[1],fields[2]); break;
                case "log": if(fields[2].Length>0) Shell.AddLog(fields[2]); break;
                case "url":
                    if(!openPages) { Shell.AddLog("Would open: "+fields[2]); break; }
                    try { Process.Start(fields[2]); } catch(Exception) { Shell.AddLog("Could not open: "+fields[2]); }
                    break;
                case "progress": completed++; SetQueueProgress(100.0*completed/total); Shell.SetText("Status",completed+" of "+total+" processed"); break;
                // The engine failed internally: the queue ended, and what was running counts as interrupted.
                case "error": queueFailed=true; Shell.AddLog("1nstall could not finish the queue: "+fields[2]); break;
                case "done": done=true; break;
            }
        }
        if(!done) return;
        queueTimer.Stop(); queueRunning=false;
        int failed=0, manual=0; bool allSucceeded=statuses.Count>0 && !stopRequested && !queueFailed;
        foreach(string key in new List<string>(statuses.Keys)) {
            string status=statuses[key];
            if(status=="Queued") status="Not started";
            else if(status.StartsWith("Installing",StringComparison.Ordinal) || status.StartsWith("Preparing",StringComparison.Ordinal) || status.StartsWith("Verifying",StringComparison.Ordinal)) status="Failed · operation interrupted";
            statuses[key]=status;
            if(status.StartsWith("Failed",StringComparison.Ordinal)) failed++;
            if(status.StartsWith("Manual",StringComparison.Ordinal)) manual++;
            if(status!="Success") allSucceeded=false;
        }
        Shell.SetText("Status","Queue finished · "+failed+" failed · "+manual+" manual installs pending.");
        if(stopRequested) Shell.SetText("Status","Queue stopped after the current app. Review the results.");
        if(queueFailed) Shell.SetText("Status","The queue ended early because of an internal error. See the logs for details.");
        SetBusy(false);
        Motion.Result(Find<FrameworkElement>("SelectedCount"),allSucceeded);
        RefreshInventory();
    }

    static void InitializeQueue(string logs,bool mayOpenPages) {
        logDirectory=logs; openPages=mayOpenPages;
        queueTimer=new DispatcherTimer { Interval=TimeSpan.FromMilliseconds(250) };
        queueTimer.Tick+=QueueTick;
        var install=Find<Button>("Install"); if(install!=null) install.Click+=delegate { StartQueue(); };
        var cancel=Find<Button>("Cancel");
        if(cancel!=null) cancel.Click+=delegate {
            if(!Busy) return;
            Engine.QueueStop(); stopRequested=true; cancel.IsEnabled=false;
            Shell.SetText("Status","Stopping after the current app.");
            Shell.AddLog("Stop requested. Waiting for the current installer.");
        };
        // A running installer is never abandoned: closing waits for it, and stops the rest.
        window.Closing+=delegate(object sender,System.ComponentModel.CancelEventArgs e) {
            if(!Busy || !queueRunning) return;
            e.Cancel=true; Engine.QueueStop(); stopRequested=true;
            Shell.SetText("Status","Wait for the current installer to finish, then close this window.");
            if(cancel!=null) cancel.IsEnabled=false;
        };
        window.Closed+=delegate { queueTimer.Stop(); };
    }
}
