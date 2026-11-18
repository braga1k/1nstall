// The Uninstall pages: installed apps, the removal queue, its review, the leftover scan and
// the cleanup of reviewed leftovers. A port of the uninstall part of vexan_installers.ps1;
// each method names the PowerShell function it comes from.
//
// Every operation runs inside the engine, one at a time, on a thread of its own. This file asks
// it five times a second what happened, as the 3.6 timer does. Nothing here removes anything:
// it shows, asks for consent, and tells the engine what the user chose.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shell;
using System.Windows.Threading;
using OneInstall;

// One installed app, as the list shows it. The list's template binds to these properties.
sealed class InstalledApp : INotifyPropertyChanged {
    bool selected;
    public string Id { get; set; }
    public string Name { get; set; }
    public string Publisher { get; set; }
    public string Version { get; set; }
    public string Kind { get; set; }
    public long SizeKB { get; set; }
    public bool CanRemove { get; set; }
    public string Detail { get { return (Publisher ?? "Unknown publisher")+"  ·  "+Version+"  ·  "+Kind+(SizeKB>0?"  ·  "+(SizeKB/1024.0).ToString("0.#")+" MB":""); } }
    public bool Selected { get { return selected; } set { selected=value; if(PropertyChanged!=null) PropertyChanged(this,new PropertyChangedEventArgs("Selected")); } }
    public event PropertyChangedEventHandler PropertyChanged;
}

// One possible leftover of a removed app, by its position in the engine's last scan.
sealed class Leftover {
    public string Position, AppName, Kind, Confidence, Reason, Size, Path, DisplayValueName;
    public bool Machine, View32, HasValue, Selected;
}

static class Uninstall {
    static readonly string[] Working={"Queued","Preparing…","Removing…","Verifying…"};
    static Window window;
    static string logPath, backups;
    static List<InstalledApp> installedApps=new List<InstalledApp>();
    static List<InstalledApp> queue=new List<InstalledApp>();
    static readonly Dictionary<string,string> states=new Dictionary<string,string>();
    static readonly Dictionary<string,TextBlock> labels=new Dictionary<string,TextBlock>();
    static string installedKind="All", operation, outcome="";
    static bool syncing;
    static DispatcherTimer timer;
    static Border cleanupSummary;
    static TextBlock cleanupHeading, cleanupDetail;
    static StackPanel progressPanel;
    static ProgressBar progress;
    // What an operation reports before its closing "done".
    static readonly List<string[]> pending=new List<string[]>();

    public static bool Busy { get { return operation!=null; } }
    static T Find<T>(string name) where T:class { return window.FindName(name) as T; }
    static void Enable(string name,bool enabled) { var element=Find<UIElement>(name); if(element!=null) element.IsEnabled=enabled; }
    static string State(string id) { string state; return states.TryGetValue(id,out state)?state:null; }

    // Add-UninstallLog
    static void Log(string text) {
        string line="["+DateTime.Now.ToString("HH:mm:ss")+"] "+text;
        var box=Find<TextBox>("UninstallLog"); if(box!=null) { box.AppendText(line+"\r\n"); box.ScrollToEnd(); }
        try { File.AppendAllText(logPath,line+"\r\n",new UTF8Encoding(true)); } catch(IOException) { } catch(UnauthorizedAccessException) { }
    }

    // Update-UninstallSelection
    static void UpdateSelection() {
        if(syncing || Busy) return;
        var chosen=new List<InstalledApp>();
        foreach(var app in queue) if(app.Selected) chosen.Add(app);
        foreach(var app in installedApps) if(app.Selected && app.CanRemove && !queue.Exists(delegate(InstalledApp queued) { return queued.Id==app.Id; })) chosen.Add(app);
        labels.Clear();
        var panel=Find<Panel>("UninstallQueuePanel"); panel.Children.Clear(); panel.IsEnabled=!Busy;
        if(chosen.Count==0) {
            var hint=Shell.NewLabel("Choose installed apps to add them to your selection.",true,13); hint.Margin=new Thickness(0,15,0,0); panel.Children.Add(hint);
        }
        foreach(var app in chosen) {
            string detail=State(app.Id);
            if(detail==null) { var parts=new List<string>(); if(!String.IsNullOrEmpty(app.Kind)) parts.Add(app.Kind); if(!String.IsNullOrEmpty(app.Version)) parts.Add(app.Version); detail=String.Join(" · ",parts); }
            var row=Library.NewSelectionRow(app,app.Name,detail,delegate(object sender,RoutedEventArgs e) {
                if(Busy) return;
                string id=((InstalledApp)((FrameworkElement)sender).Tag).Id;
                foreach(var entry in installedApps) if(entry.Id==id) entry.Selected=false;
                foreach(var entry in queue) if(entry.Id==id) entry.Selected=false;
                UpdateSelection();
            },!Busy);
            panel.Children.Add(row);
            labels[app.Id]=(TextBlock)row.Children[1];
            Motion.Phase((TextBlock)row.Children[1],detail);
        }
        Shell.SetText("UninstallSelectedCount",chosen.Count+" "+(chosen.Count==1?"app":"apps")+" selected");
        int ready=0; foreach(var app in installedApps) if(app.Selected && app.CanRemove && State(app.Id)!="Success") ready++;
        Enable("ReviewUninstall",ready>0 && !Busy);
        Enable("ClearUninstallSelection",chosen.Count>0 && !Busy);
        Enable("CheckLeftovers",Engine.UninstallTargets()>0 && !Busy);
    }

    // Set-UninstallStage
    static void SetStage(string id,string state) {
        if(!queue.Exists(delegate(InstalledApp app) { return app.Id==id; })) return;
        states[id]=state;
        TextBlock label;
        if(labels.TryGetValue(id,out label)) { I18n.Set(label,"Text",state); Motion.Phase(label,state); }
        int done=0; foreach(var app in queue) if(Array.IndexOf(Working,State(app.Id))<0) done++;
        if(progress!=null) Library.AnimateValue(progress,RangeBase.ValueProperty,progress.Value,100.0*done/queue.Count,200);
    }

    // Set-UninstallTask: one operation at a time; the page waits for it.
    static void SetTask(string name,string arguments) {
        if(Busy) throw new InvalidOperationException("A removal operation is already running.");
        string refused=Engine.UninstallStart(name,arguments,logPath);
        if(refused.Length>0) throw new InvalidOperationException(refused.Substring(1));
        operation=name; pending.Clear();
        foreach(string control in new[]{"RefreshInstalled","InstalledList","UninstallQueuePanel","InstallMode","ReviewUninstall","CheckLeftovers","ClearUninstallSelection"}) Enable(control,false);
        var stop=Find<Button>("StopUninstall"); if(stop!=null) { stop.Visibility=name=="Remove"?Visibility.Visible:Visibility.Collapsed; stop.IsEnabled=true; }
        timer.Start();
    }

    // A step that could not start is reported the way a step that failed is.
    static void Try(string name,string arguments) {
        try { SetTask(name,arguments); }
        catch(InvalidOperationException error) { Log(error.Message); Shell.SetText("UninstallStatus","Could not complete this step. Review Removal activity and try again."); }
    }

    // Start-UninstallQueue
    static void StartQueue(List<InstalledApp> plan) {
        queue=new List<InstalledApp>(plan); states.Clear();
        var ids=new List<string>();
        foreach(var app in plan) { states[app.Id]="Queued"; ids.Add(app.Id); }
        progress.BeginAnimation(RangeBase.ValueProperty,null); progress.Value=0;
        progressPanel.Visibility=Visibility.Visible; cleanupSummary.Visibility=Visibility.Collapsed;
        outcome=""; UpdateSelection();
        Try("Remove",String.Join("\u001F",ids));
    }

    // Update-InstalledFilter
    static void UpdateInstalledFilter() {
        string query=Find<TextBox>("InstalledSearch").Text.Trim();
        var matches=new List<InstalledApp>();
        foreach(var app in installedApps) if((installedKind=="All" || app.Kind==installedKind) && (app.Name+" "+app.Publisher).IndexOf(query,StringComparison.OrdinalIgnoreCase)>=0) matches.Add(app);
        var list=Find<ListBox>("InstalledList");
        syncing=true;
        try { list.ItemsSource=matches.ToArray(); } finally { syncing=false; }
        if(window.IsVisible) Motion.Enter(list,0,7,0);
        Shell.SetText("InstalledEmpty",operation=="Inventory"?"Reading installed apps…":"No apps found. Try another search or choose Refresh.");
        Shell.Show("InstalledEmpty",matches.Count==0);
        if(Shell.Mode=="Uninstall") Shell.SetText("ResultCount","Installed · "+matches.Count+" apps");
        foreach(string name in new[]{"InstalledAll","InstalledDesktop","InstalledStore"}) {
            var button=Find<Button>(name); if(button==null) continue;
            button.SetResourceReference(Control.BackgroundProperty,(string)button.Tag==installedKind?"AccentSurfaceBrush":"GlassControlFill");
        }
    }

    // Refresh-InstalledApps
    static void Refresh() {
        if(Busy) return;
        Shell.SetText("UninstallStatus","Reading desktop and Microsoft Store apps…");
        Try("Inventory","");
        UpdateInstalledFilter();
    }

    // Start-LeftoverScan
    static void StartLeftoverScan() {
        if(cleanupSummary!=null) cleanupSummary.Visibility=Visibility.Collapsed;
        Shell.SetText("UninstallStatus","Checking removed apps and protecting shared folders...");
        Try("Scan","");
    }

    // Show-CleanupSummary
    static void ShowCleanupSummary(string heading,string detail) {
        I18n.Set(cleanupHeading,"Text",heading); I18n.Set(cleanupDetail,"Text",detail);
        cleanupSummary.SetResourceReference(Border.BackgroundProperty,"ContentFill");
        cleanupSummary.SetResourceReference(Border.BorderBrushProperty,"CardEdge");
        cleanupSummary.Visibility=Visibility.Visible; Motion.Enter(cleanupSummary,0,7,0);
    }

    static Border Surface() {
        return new Border { Background=(Brush)window.Resources["ContentFill"], BorderBrush=(Brush)window.Resources["CardEdge"], BorderThickness=new Thickness(1), CornerRadius=new CornerRadius(16), Padding=new Thickness(16), Margin=new Thickness(0,0,8,10) };
    }

    // Show-RemovalReview: nothing proceeds without a fresh, explicit consent. For a removal the
    // items are the apps; for leftovers each item starts unselected and the user chooses.
    static bool ShowRemovalReview(List<InstalledApp> apps,List<Leftover> leftovers,string folderSummary,string registrySummary) {
        bool reviewingLeftovers=leftovers!=null;
        var panes=Find<FrameworkElement>("AppPanes");
        var dialog=new Window { FlowDirection=panes.FlowDirection, Language=window.Language, Width=760, Height=Math.Min(660,SystemParameters.WorkArea.Height-40), MinWidth=560, MinHeight=reviewingLeftovers?520:450, Owner=window, Icon=window.Icon, WindowStartupLocation=WindowStartupLocation.CenterOwner, FontFamily=window.FontFamily, FontSize=13, ShowInTaskbar=false, Resources=window.Resources };
        I18n.Set(dialog,"Title",reviewingLeftovers?"Review leftovers · 1nstall":"Review removal · 1nstall");
        WindowChrome.SetWindowChrome(dialog,new WindowChrome { CaptionHeight=24, ResizeBorderThickness=new Thickness(6), GlassFrameThickness=new Thickness(0), UseAeroCaptionButtons=false });
        dialog.SetResourceReference(Control.BackgroundProperty,"OpaqueWindowFill"); dialog.SetResourceReference(Control.ForegroundProperty,"TextPrimaryBrush");
        dialog.SourceInitialized+=delegate { FirstInstallWindow.Apply(new WindowInteropHelper(dialog).Handle,Theme.Light); };
        var dock=new DockPanel { Margin=new Thickness(24) }; dialog.Content=dock;
        var head=new StackPanel();
        head.Children.Add(Shell.NewLabel(reviewingLeftovers?"Keep what matters":"Ready to make some room?",false,27));
        var note=Shell.NewLabel(reviewingLeftovers?"Possible leftovers need your judgment. Product folders can contain settings, saves or personal app data. Choose only what you want to remove. Files go to the Recycle Bin; registry keys are backed up first.":"These apps will be removed one at a time using their own uninstallers. Finish any dialogs they open. Microsoft Store removal affects your current Windows account. Back up app data you want to keep.",true,13);
        note.Margin=new Thickness(0,10,0,18);
        if(reviewingLeftovers) {
            var explanation=new Expander { Style=(Style)window.Resources["CategoryGroup"], Margin=new Thickness(0,6,8,10), Content=note };
            I18n.Set(explanation,"Header","Details"); head.Children.Add(explanation);
        } else head.Children.Add(note);
        DockPanel.SetDock(head,Dock.Top); dock.Children.Add(head);
        var bottom=new StackPanel(); DockPanel.SetDock(bottom,Dock.Bottom); dock.Children.Add(bottom);
        var agree=new CheckBox { Style=(Style)window.Resources["InstalledCheck"], Margin=new Thickness(0,18,0,16) };
        agree.Content=Shell.NewLabel(reviewingLeftovers?"I reviewed the selected paths and want to remove their contents.":"I reviewed this list and want to remove these apps and their app data.",false,13);
        AutomationProperties.SetAutomationId(agree,"RemovalConsent");
        bottom.Children.Add(agree);
        var actions=new WrapPanel { HorizontalAlignment=HorizontalAlignment.Right }; bottom.Children.Add(actions);
        var back=new Button { IsCancel=true }; I18n.Set(back,"Content","Keep / go back"); back.Click+=delegate { dialog.DialogResult=false; }; actions.Children.Add(back);
        var go=new Button { IsEnabled=false, Margin=new Thickness(0) };
        I18n.Set(go,"Content",reviewingLeftovers?"Remove selected leftovers":"Remove "+apps.Count+" apps");
        AutomationProperties.SetAutomationId(go,"RemovalProceed");
        go.SetResourceReference(Control.BackgroundProperty,"AccentActionBrush"); go.SetResourceReference(Control.ForegroundProperty,"AccentForegroundBrush");
        go.Click+=delegate { dialog.DialogResult=true; }; actions.Children.Add(go);
        var list=new StackPanel();
        dock.Children.Add(new ScrollViewer { VerticalScrollBarVisibility=ScrollBarVisibility.Auto, HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled, Content=list });
        Func<bool> anySelected=delegate { return leftovers.Exists(delegate(Leftover item) { return item.Selected; }); };
        if(reviewingLeftovers) {
            var summary=new UniformGrid { Columns=2, Margin=new Thickness(0,0,0,12) };
            foreach(string[] stat in new[]{ new[]{"Disk",folderSummary}, new[]{"Registry",registrySummary} }) {
                string value=stat[1];
                if(I18n.Language=="en") value=Regex.Replace(Regex.Replace(value,"^1 folders","1 folder"),"^1 keys / values$","1 key / value");
                var tile=new Border { Background=(Brush)window.Resources["ContentFill"], BorderBrush=(Brush)window.Resources["CardEdge"], BorderThickness=new Thickness(1), CornerRadius=new CornerRadius(16), Padding=new Thickness(14), Margin=new Thickness(0,0,8,0) };
                var stack=new StackPanel(); tile.Child=stack;
                stack.Children.Add(Shell.NewLabel(stat[0],true,12));
                var figure=Shell.NewLabel(value,false,18); figure.FontWeight=FontWeights.SemiBold; stack.Children.Add(figure);
                summary.Children.Add(tile);
            }
            head.Children.Add(summary);
            var bar=new WrapPanel { Margin=new Thickness(0,0,0,12) };
            Action<string,Func<Leftover,bool>> choice=delegate(string text,Func<Leftover,bool> wanted) {
                var button=new Button { Padding=new Thickness(12,6,12,6) }; I18n.Set(button,"Content",text);
                button.Click+=delegate { foreach(Border row in list.Children) { var check=(CheckBox)row.Child; check.IsChecked=wanted((Leftover)check.Tag); } };
                bar.Children.Add(button);
            };
            choice("Select linked paths",delegate(Leftover item) { return item.Confidence=="Linked path"; });
            choice("Select all",delegate { return true; });
            choice("Clear selection",delegate { return false; });
            head.Children.Add(bar);
            foreach(var entry in leftovers) {
                var surface=Surface(); var texts=new StackPanel();
                var title=Shell.NewLabel(entry.AppName+" · "+I18n.Convert(entry.Kind=="Folder"?"Disk":"Registry"),false,15); title.FontWeight=FontWeights.SemiBold; texts.Children.Add(title);
                string evidence=I18n.Convert(String.IsNullOrEmpty(entry.Confidence)?"Name match":entry.Confidence)+" · "+I18n.Convert(entry.Reason);
                if(entry.Kind=="Folder") evidence+=" · "+entry.Size;
                var badge=Shell.NewLabel(evidence,true,12); badge.Margin=new Thickness(0,6,0,0); texts.Children.Add(badge);
                string detail=(entry.Kind=="Registry"?(entry.Machine?"HKLM":"HKCU")+" · "+(entry.View32?"32-bit":"64-bit")+" · ":"")+entry.Path+(entry.HasValue?" → "+entry.DisplayValueName:"");
                var subtitle=Shell.NewLabel(detail,true,12); subtitle.Margin=new Thickness(0,7,0,0); subtitle.FlowDirection=FlowDirection.LeftToRight; texts.Children.Add(subtitle);
                var check=new CheckBox { Style=(Style)window.Resources["InstalledCheck"], Content=texts, Tag=entry };
                AutomationProperties.SetName(check,entry.AppName+" · "+entry.Path);
                entry.Selected=false;
                check.Checked+=delegate(object sender,RoutedEventArgs e) { ((Leftover)((CheckBox)sender).Tag).Selected=true; go.IsEnabled=agree.IsChecked==true && anySelected(); };
                check.Unchecked+=delegate(object sender,RoutedEventArgs e) { ((Leftover)((CheckBox)sender).Tag).Selected=false; go.IsEnabled=agree.IsChecked==true && anySelected(); };
                surface.Child=check; list.Children.Add(surface);
            }
        } else foreach(var entry in apps) {
            var surface=Surface(); var texts=new StackPanel(); surface.Child=texts;
            var title=Shell.NewLabel(entry.Name,false,15); title.FontWeight=FontWeights.SemiBold; texts.Children.Add(title);
            var subtitle=Shell.NewLabel(entry.Detail,true,12); subtitle.Margin=new Thickness(0,7,0,0); texts.Children.Add(subtitle);
            list.Children.Add(surface);
        }
        dialog.ContentRendered+=delegate { Motion.Enter(dock,0,10,0); };
        agree.Checked+=delegate { go.IsEnabled=!reviewingLeftovers || anySelected(); };
        agree.Unchecked+=delegate { go.IsEnabled=false; };
        return dialog.ShowDialog()==true;
    }

    static List<string[]> Of(string kind) { return pending.FindAll(delegate(string[] record) { return record[0]==kind; }); }

    // The end of an operation, as the 3.6 timer handles a completed task.
    static void Finish(string finished) {
        foreach(string control in new[]{"RefreshInstalled","InstalledList","UninstallQueuePanel","InstallMode"}) Enable(control,true);
        Shell.Show("StopUninstall",false);
        var errors=Of("error");
        if(errors.Count>0) {
            if(finished=="Remove") foreach(var app in queue) if(Array.IndexOf(Working,State(app.Id))>=0) SetStage(app.Id,"Unknown");
            Log(errors[0][1]); Shell.SetText("UninstallStatus","Could not complete this step. Review Removal activity and try again.");
            UpdateSelection(); return;
        }
        if(finished=="Inventory") {
            var selectedIds=new HashSet<string>();
            foreach(var app in installedApps) if(app.Selected) selectedIds.Add(app.Id);
            foreach(var app in queue) if(app.Selected) selectedIds.Add(app.Id);
            var found=new List<InstalledApp>();
            foreach(string[] fields in Of("app")) {
                if(fields.Length!=9) continue;
                var app=new InstalledApp { Id=fields[1], Name=fields[2], Publisher=fields[3]=="1"?fields[4]:null, Version=fields[5], Kind=fields[6], CanRemove=fields[8]=="1" };
                long size; if(Int64.TryParse(fields[7],out size)) app.SizeKB=size;
                app.Selected=selectedIds.Contains(app.Id);
                found.Add(app);
            }
            installedApps=found;
            // An app the list still shows was not removed after all.
            foreach(var app in found) if(State(app.Id)=="Success") SetStage(app.Id,"Manual action required");
            var warnings=Of("warning");
            foreach(string[] warning in warnings) Log(warning[1]);
            Shell.SetText("UninstallStatus",outcome.Length>0?outcome:installedApps.Count+" installed apps · "+warnings.Count+" scan warnings. Review details in Removal activity.");
            UpdateInstalledFilter(); UpdateSelection(); return;
        }
        foreach(string[] message in Of("message")) Log(message[1]);
        if(finished=="Remove") {
            foreach(string[] result in Of("result")) SetStage(result[1],result[3]);
            Library.RefreshInventory();
            StartLeftoverScan();
        } else if(finished=="Scan") {
            foreach(string[] result in Of("result")) SetStage(result[1],result[3]);
            var scan=Of("scan"); string[] totals=scan.Count>0?scan[0]:new[]{"scan","0","0","0","0","",""};
            int scanned=Int32.Parse(totals[1]), incomplete=Int32.Parse(totals[2]);
            if(scanned>0) Library.RefreshInventory();
            var items=new List<Leftover>();
            foreach(string[] fields in Of("leftover")) if(fields.Length==12) items.Add(new Leftover { Position=fields[1], AppName=fields[2], Kind=fields[3], Confidence=fields[4], Reason=fields[5], Size=fields[6], Machine=fields[7]=="1", View32=fields[8]=="1", Path=fields[9], HasValue=fields[10]=="1", DisplayValueName=fields[11] });
            outcome=items.Count>0?totals[3]+" disk · "+totals[4]+" registry · "+totals[5]:scanned>0?"No leftovers found in the checked locations.":"No verified removals to check. See Removal activity.";
            if(incomplete>0) outcome+="\n"+incomplete+" checks incomplete. See Removal activity.";
            Shell.SetText("UninstallStatus",outcome); Log(outcome);
            if(items.Count>0) ShowCleanupSummary("Review what was found",outcome);
            if(items.Count>0 && ShowRemovalReview(null,items,totals[3]+" folders · "+totals[6],totals[4]+" keys / values")) {
                var chosen=new List<string>();
                foreach(var item in items) if(item.Selected) chosen.Add(item.Position);
                if(chosen.Count>0) Try("Clean",String.Join("\u001F",chosen));
            }
            if(!Busy) Refresh();
        } else if(finished=="Clean") {
            var clean=Of("clean"); string[] totals=clean.Count>0?clean[0]:new[]{"clean","","0","0","0",""};
            Log("Backups and item record: "+totals[1]);
            int recycled=Int32.Parse(totals[2]), removed=Int32.Parse(totals[3]), failed=Int32.Parse(totals[4]);
            outcome=recycled+" recycled · "+removed+" registry removed · "+failed+" not completed · "+totals[5];
            ShowCleanupSummary(failed==0?"Cleanup complete":"Cleanup needs attention","Recycled files remain recoverable. Registry backups are in Open backups.");
            if(recycled+removed>0 && failed==0) Motion.Result(cleanupHeading,true);
            Shell.SetText("UninstallStatus",outcome);
            Refresh();
        }
        UpdateSelection();
    }

    static void Tick(object sender,EventArgs e) {
        string events=Engine.UninstallEvents();
        string finished=null;
        if(events.Length>0) foreach(string record in events.Split('\u001E')) {
            string[] fields=record.Split('\u001F');
            switch(fields[0]) {
                case "progress": Shell.SetText("UninstallStatus",fields[1]); Log(fields[1]); break;
                case "stage": SetStage(fields[1],fields[2]); break;
                case "verified": Motion.Result(Find<FrameworkElement>("UninstallSelectedCount"),true); break;
                case "done": finished=fields[1]; break;
                default: pending.Add(fields); break;
            }
        }
        if(finished==null) return;
        timer.Stop(); operation=null;
        Finish(finished);
        pending.Clear();
    }

    // The pointer-following light of a row of the installed list (Get-InstalledCardLight).
    static Border RowLight(ListBox list,object source) {
        var origin=source as DependencyObject; if(origin==null) return null;
        var item=ItemsControl.ContainerFromElement(list,origin) as ListBoxItem;
        if(item==null || VisualTreeHelper.GetChildrenCount(item)==0) return null;
        var presenter=VisualTreeHelper.GetChild(item,0) as FrameworkElement;
        return presenter==null || list.ItemTemplate==null?null:list.ItemTemplate.FindName("InstalledHoverLight",presenter) as Border;
    }

    // What Set-AppMode does when the Uninstall page is shown.
    public static void Shown() {
        UpdateInstalledFilter(); UpdateSelection();
        if(installedApps.Count==0) Refresh();
    }

    public static void Initialize(Window target,string sessionLog,string backupFolder) {
        window=target; logPath=sessionLog; backups=backupFolder;
        timer=new DispatcherTimer { Interval=TimeSpan.FromMilliseconds(200) };
        timer.Tick+=Tick;

        cleanupSummary=new Border { Background=(Brush)window.Resources["ContentFill"], BorderBrush=(Brush)window.Resources["CardEdge"], BorderThickness=new Thickness(1), CornerRadius=new CornerRadius(16), Padding=new Thickness(14,10,14,10), Margin=new Thickness(0,0,0,10), Visibility=Visibility.Collapsed };
        var summaryLabels=new StackPanel(); cleanupSummary.Child=summaryLabels;
        cleanupHeading=Shell.NewLabel("",false,16); cleanupHeading.FontWeight=FontWeights.SemiBold; summaryLabels.Children.Add(cleanupHeading);
        cleanupDetail=Shell.NewLabel("",true,12); cleanupDetail.Margin=new Thickness(0,4,0,0); summaryLabels.Children.Add(cleanupDetail);
        ((Panel)Find<FrameworkElement>("UninstallStatus").Parent).Children.Insert(0,cleanupSummary);
        progressPanel=new StackPanel { Visibility=Visibility.Collapsed };
        var caption=Shell.NewLabel("Queue progress · apps processed",true,12); caption.Margin=new Thickness(0,0,0,6); progressPanel.Children.Add(caption);
        progress=new ProgressBar { Minimum=0, Maximum=100, Height=5, BorderThickness=new Thickness(0), Margin=new Thickness(0,0,0,14) };
        progress.SetResourceReference(Control.BackgroundProperty,"SeparatorBrush"); progress.SetResourceReference(Control.ForegroundProperty,"AccentTextBrush");
        AutomationProperties.SetName(progress,"App queue progress");
        progressPanel.Children.Add(progress);
        ((Panel)Find<FrameworkElement>("RemovalGuidance").Parent).Children.Insert(1,progressPanel);

        var refresh=Find<Button>("RefreshInstalled"); if(refresh!=null) refresh.Click+=delegate { Refresh(); };
        var settings=Find<Button>("WindowsAppsSettings"); if(settings!=null) settings.Click+=delegate { Process.Start("ms-settings:appsfeatures"); };
        var search=Find<TextBox>("InstalledSearch"); search.TextChanged+=delegate { UpdateInstalledFilter(); };
        var clearSearch=Find<Button>("ClearInstalledSearch"); if(clearSearch!=null) clearSearch.Click+=delegate { search.Clear(); search.Focus(); };
        foreach(string name in new[]{"InstalledAll","InstalledDesktop","InstalledStore"}) {
            var button=Find<Button>(name); if(button==null) continue;
            button.Click+=delegate(object sender,RoutedEventArgs e) { installedKind=(string)((Button)sender).Tag; UpdateInstalledFilter(); };
        }
        var list=Find<ListBox>("InstalledList");
        // A switch of the list changed: mirror it in the queue, and fly the name to or from the count.
        RoutedEventHandler toggled=delegate(object sender,RoutedEventArgs e) {
            if(Busy) return;
            var check=e.OriginalSource as CheckBox; var app=check==null?null:check.DataContext as InstalledApp;
            if(app==null || syncing) return;
            foreach(var entry in queue) if(entry.Id==app.Id) entry.Selected=check.IsChecked==true;
            UpdateSelection();
            var count=Find<FrameworkElement>("UninstallSelectedCount");
            if(check.IsChecked==true) Motion.Fly(check,count,app.Name); else Motion.Fly(count,check,app.Name);
            Motion.Pop(count);
        };
        list.AddHandler(ToggleButton.CheckedEvent,toggled); list.AddHandler(ToggleButton.UncheckedEvent,toggled);
        list.MouseMove+=delegate(object sender,MouseEventArgs e) {
            if(!Theme.Glass || !Motion.Enabled) return;
            var light=RowLight(list,e.OriginalSource); if(light!=null) Theme.MoveGlassLight(light,e.GetPosition(light));
        };
        var clear=Find<Button>("ClearUninstallSelection");
        if(clear!=null) clear.Click+=delegate {
            if(Busy) return;
            syncing=true;
            try {
                foreach(var app in installedApps) if(app.Selected) app.Selected=false;
                foreach(var app in queue) if(app.Selected) app.Selected=false;
                queue=new List<InstalledApp>(); states.Clear(); progressPanel.Visibility=Visibility.Collapsed;
            } finally { syncing=false; }
            UpdateSelection();
        };
        var review=Find<Button>("ReviewUninstall");
        if(review!=null) review.Click+=delegate {
            if(Busy) return;
            var plan=installedApps.FindAll(delegate(InstalledApp app) { return app.Selected && app.CanRemove && State(app.Id)!="Success"; });
            if(plan.Count>0 && ShowRemovalReview(plan,null,null,null)) StartQueue(plan);
        };
        var stop=Find<Button>("StopUninstall");
        if(stop!=null) stop.Click+=delegate { Engine.UninstallStop(); stop.IsEnabled=false; Shell.SetText("UninstallStatus","Waiting for the current uninstaller. The next app will be kept."); };
        var leftovers=Find<Button>("CheckLeftovers");
        if(leftovers!=null) leftovers.Click+=delegate { if(!Busy && Engine.UninstallTargets()>0) StartLeftoverScan(); };
        var openBackups=Find<Button>("OpenUninstallBackups");
        if(openBackups!=null) openBackups.Click+=delegate {
            try { Directory.CreateDirectory(backups); } catch(IOException) { } catch(UnauthorizedAccessException) { }
            Process.Start("explorer.exe","\""+backups+"\"");
        };
        // A running uninstaller or check is never abandoned: closing waits for it.
        window.Closing+=delegate(object sender,CancelEventArgs e) {
            if(!Busy) return;
            e.Cancel=true; Engine.UninstallStop();
            Shell.SetText("UninstallStatus","Wait for the current removal/check to finish, then close this window.");
        };
        window.Closed+=delegate { timer.Stop(); };
    }
}
