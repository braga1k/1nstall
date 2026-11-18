// The install library: selection, filters, views, installed states, details, profiles and
// saved selections. A port of the library parts of vexan_installers.ps1 and src/manager-ui.ps1;
// the PowerShell function each method comes from is named in its comment.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shell;
using System.Windows.Threading;
using Microsoft.Win32;
using OneInstall;

static class Library {
    static Window window;
    static CatalogCard[] catalog;
    static readonly Dictionary<string,CatalogCard> byKey=new Dictionary<string,CatalogCard>();
    static Dictionary<string,CheckBox> checks;
    static Dictionary<string,string> texts;
    static readonly HashSet<string> selected=new HashSet<string>();
    static readonly Dictionary<string,string> statuses=new Dictionary<string,string>();
    static readonly Dictionary<string,string> states=new Dictionary<string,string>();
    static readonly Dictionary<string,Button> viewButtons=new Dictionary<string,Button>();
    static readonly List<RadioButton> categoryButtons=new List<RadioButton>();
    static readonly List<Expander> categoryGroups=new List<Expander>();
    static string category="All apps", view="All apps";
    static bool syncing, inventoryKnown;
    static Button refresh;
    static MenuItem export;
    static Task<string> inventoryTask;
    static DispatcherTimer inventoryTimer;
    // Set while a queue runs. The queue itself is not ported yet, so this stays false.
    public static bool Busy { get; set; }

    static T Find<T>(string name) where T:class { return window.FindName(name) as T; }
    static UniformGrid Cards { get { return Find<UniformGrid>("Cards"); } }
    static ScrollViewer Scroll { get { return Find<ScrollViewer>("LibraryScroll"); } }
    public static IEnumerable<CheckBox> Checks { get { return checks.Values; } }
    static string State(string key) { string state; return states.TryGetValue(key,out state)?state:"Unknown"; }
    static bool Installed(string key) { return State(key).StartsWith("Installed ·",StringComparison.Ordinal); }

    // The selected keys in the order of the sorted catalog, as 3.6 hands them to its planner.
    static string SelectedKeys() {
        var keys=new List<string>();
        foreach(var app in catalog) if(selected.Contains(app.Key)) keys.Add(app.Key);
        return String.Join("\u001F",keys);
    }

    // Animate-Value
    static void AnimateValue(Animatable target,DependencyProperty property,double from,double to,int milliseconds) {
        target.BeginAnimation(property,null);
        ((DependencyObject)target).SetValue(property,to);
        if(!Motion.Enabled || !window.IsVisible || Math.Abs(from-to)<0.001) return;
        var animation=new DoubleAnimation(from,to,new Duration(TimeSpan.FromMilliseconds(milliseconds))) { EasingFunction=new CubicEase { EasingMode=EasingMode.EaseOut }, FillBehavior=FillBehavior.Stop };
        target.BeginAnimation(property,animation,HandoffBehavior.SnapshotAndReplace);
    }
    static FrameworkElement Surface(Control card) { card.ApplyTemplate(); return card.Template==null?null:card.Template.FindName("Card",card) as FrameworkElement; }
    // Animate-CardEntrance
    static void AnimateCardEntrance(Control card,int delay) { var surface=Surface(card); if(surface!=null) Motion.Enter(surface,0,12,delay); }
    // Animate-Library
    static void AnimateLibrary() {
        if(!window.IsVisible) return;
        Cards.UpdateLayout(); int index=0;
        foreach(CheckBox card in Cards.Children) {
            double y=card.TranslatePoint(new Point(0,0),Scroll).Y;
            if(y>Scroll.ViewportHeight) break;
            if(y>=-card.ActualHeight) { AnimateCardEntrance(card,Math.Min(140,index*22)); index++; }
        }
    }
    // Animate-SelectionFlight
    static void AnimateSelectionFlight(string key,bool adding) {
        if(!window.IsVisible || !checks.ContainsKey(key)) return;
        FrameworkElement destination=Find<FrameworkElement>("SelectedCount");
        foreach(FrameworkElement row in Find<Panel>("QueuePanel").Children) if(Equals(row.Tag,key)) { destination=row; break; }
        if(adding) Motion.Fly(checks[key],destination,byKey[key].Name); else Motion.Fly(destination,checks[key],byKey[key].Name);
        Motion.Pop(Find<FrameworkElement>("SelectedCount"));
    }

    // New-SelectionRow
    static StackPanel NewSelectionRow(string key,string name,string detail) {
        var panel=new StackPanel { Margin=new Thickness(0,8,0,9), Tag=key };
        var row=new Grid(); row.ColumnDefinitions.Add(new ColumnDefinition()); row.ColumnDefinitions.Add(new ColumnDefinition { Width=GridLength.Auto });
        var title=Shell.NewLabel(name,false,13); title.FontWeight=FontWeights.SemiBold; title.Margin=new Thickness(0,0,8,0); title.VerticalAlignment=VerticalAlignment.Center;
        row.Children.Add(title);
        var remove=new Button { Tag=key, Width=32, MinHeight=32, Padding=new Thickness(0), Margin=new Thickness(0), FontSize=18, Background=Brushes.Transparent, BorderThickness=new Thickness(0), IsEnabled=!Busy };
        I18n.Set(remove,"Content","×"); I18n.Set(remove,"ToolTip","Remove "+name+" from selection");
        AutomationProperties.SetName(remove,"Remove "+name+" from selection");
        Theme.EnableHoverMotion(remove);
        Grid.SetColumn(remove,1); remove.Click+=delegate(object sender,RoutedEventArgs e) { RemoveSelectedApp((string)((Button)sender).Tag); };
        row.Children.Add(remove); panel.Children.Add(row);
        var label=Shell.NewLabel(detail,true,12); label.Margin=new Thickness(0,4,0,0); panel.Children.Add(label);
        return panel;
    }

    // Update-Selection
    static void UpdateSelection() {
        syncing=true;
        foreach(var app in catalog) checks[app.Key].IsChecked=selected.Contains(app.Key);
        syncing=false;
        Shell.SetText("SelectedCount",selected.Count==1?"1 app selected":selected.Count+" apps selected");
        var install=Find<Button>("Install"); if(install!=null) install.IsEnabled=selected.Count>0 && !Busy;
        var save=Find<Button>("SaveSetup"); if(save!=null) save.IsEnabled=selected.Count>0 && !Busy;
        var queue=Find<Panel>("QueuePanel");
        var oldRows=new Dictionary<string,double>();
        foreach(FrameworkElement child in queue.Children) if(child.Tag is string) oldRows[(string)child.Tag]=child.TranslatePoint(new Point(0,0),queue).Y;
        queue.Children.Clear();
        if(selected.Count==0) {
            var hint=Shell.NewLabel("Your next setup starts here. Select apps from the library.",true,13); hint.Margin=new Thickness(0,15,0,0); queue.Children.Add(hint);
        }
        // Nothing selected needs no plan, which also keeps the engine call off the start-up path.
        string plan=selected.Count==0?"":Engine.Plan(SelectedKeys());
        if(plan.StartsWith("!",StringComparison.Ordinal)) { Shell.SetText("Status",plan.Substring(1)); plan=""; }
        if(plan.Length>0) foreach(string record in plan.Split('\u001E')) {
            string[] fields=record.Split('\u001F'); string key=fields[0], status;
            string text=statuses.TryGetValue(key,out status)?status:fields[2]=="1"?"Automatic · WinGet":"Guided · official website";
            var panel=NewSelectionRow(key,fields[1],text);
            queue.Children.Add(panel);
            Motion.Phase((TextBlock)panel.Children[1],text);
        }
        if(!window.IsVisible) return;
        queue.UpdateLayout();
        foreach(FrameworkElement row in queue.Children) {
            if(!(row.Tag is string)) continue;
            double old;
            if(oldRows.TryGetValue((string)row.Tag,out old)) {
                double delta=old-row.TranslatePoint(new Point(0,0),queue).Y;
                var move=new TranslateTransform(); row.RenderTransform=move;
                AnimateValue(move,TranslateTransform.YProperty,Math.Max(-32,Math.Min(32,delta)),0,160);
            } else Motion.Enter(row,0,5,0);
        }
    }

    static void Select(string keys) {
        selected.Clear();
        foreach(string key in keys.Split('\u001F')) if(key.Length>0) selected.Add(key);
    }

    // Remove-SelectedApp: the app leaves the selection, with every app that needed it.
    static void RemoveSelectedApp(string key) {
        if(Busy) return;
        AnimateSelectionFlight(key,false);
        Select(Engine.SelectionRemove(SelectedKeys(),key));
        foreach(string known in new List<string>(statuses.Keys)) if(!selected.Contains(known)) statuses.Remove(known);
        UpdateSelection();
        Shell.SetText("Status","Selection updated. Review before installing.");
    }

    // Set-Selection: the given apps and everything they require. Throws when the plan is refused.
    static void SetSelection(IEnumerable<string> keys) {
        string plan=Engine.Plan(String.Join("\u001F",keys));
        if(plan.StartsWith("!",StringComparison.Ordinal)) throw new InvalidOperationException(plan.Substring(1));
        selected.Clear(); statuses.Clear();
        if(plan.Length>0) foreach(string record in plan.Split('\u001E')) selected.Add(record.Split('\u001F')[0]);
        UpdateSelection();
        Shell.SetText("Status",selected.Count>0?"Selection updated. Review before installing.":"Ready when you are.");
    }

    // The card handler of 3.6 listens for clicks only, so a card switched through UI Automation's
    // toggle action, which raises no click, never reached its selection. Listening for the
    // change itself covers pointer, keyboard and assistive tools alike.
    static void CardToggled(object sender,RoutedEventArgs e) {
        if(syncing || Busy) return;
        var card=(CheckBox)sender; string key=(string)card.Tag;
        if(card.IsChecked==true) {
            string added=Engine.SelectionAdd(SelectedKeys(),key);
            if(added.StartsWith("!",StringComparison.Ordinal)) { Shell.SetText("Status",added.Substring(1)); UpdateSelection(); return; }
            Select(added);
            UpdateSelection();
        } else RemoveSelectedApp(key);
        var surface=Surface(card); if(surface!=null) Motion.Pop(surface);
        if(card.IsChecked==true) AnimateSelectionFlight(key,true);
    }

    // What a card shows beyond its fixed text: the category it is listed under, and whether it is
    // installed. Applied when the card is filled and whenever either changes (Update-LibraryStates).
    static void Dress(CheckBox card) {
        var content=card.Content as StackPanel;
        if(content==null || content.Children.Count<3) return;
        var app=byKey[(string)card.Tag]; bool installed=inventoryKnown && Installed(app.Key);
        var name=(TextBlock)content.Children[0];
        I18n.Set(content.Children[1],"Text",app.ShownCategory ?? app.Category);
        if(!inventoryKnown) return;
        name.SetResourceReference(TextBlock.ForegroundProperty,installed?"TextSecondaryBrush":"TextPrimaryBrush");
        name.FontWeight=installed?FontWeights.Normal:FontWeights.SemiBold;
        I18n.Set(content.Children[2],"Text",installed?"✓ Installed":app.Automatic?"WinGet · automatic":"Website · guided");
    }

    // Update-LibraryStates
    static void UpdateStates() {
        inventoryKnown=true;
        foreach(var app in catalog) {
            var card=checks[app.Key]; string state=State(app.Key);
            card.SetResourceReference(Control.BackgroundProperty,Installed(app.Key)?"InstalledCardFill":"ContentFill");
            Dress(card);
            AutomationProperties.SetItemStatus(card,I18n.Convert(state));
            AutomationProperties.SetHelpText(card,app.Description+" · "+state+" · F1 for details");
        }
        UpdateFilter(false);
    }

    // Refresh-LibraryInventory
    static void RefreshInventory() {
        if(inventoryTask!=null) return;
        refresh.IsEnabled=false;
        I18n.Set(refresh,"ToolTip","Checking installed apps…");
        inventoryTask=Task.Factory.StartNew(delegate { return Engine.RefreshInventory(); });
        inventoryTimer.Start();
    }
    static void InventoryTick(object sender,EventArgs e) {
        if(inventoryTask!=null && inventoryTask.IsCompleted) {
            try {
                string message=inventoryTask.GetAwaiter().GetResult().Split('\u001F')[0];
                I18n.Set(refresh,"ToolTip",message); Shell.AddLog(message);
                states.Clear();
                foreach(string record in Engine.States().Split('\u001E')) { string[] fields=record.Split('\u001F'); if(fields.Length==2) states[fields[0]]=fields[1]; }
                UpdateStates();
            } catch(Exception error) { I18n.Set(refresh,"ToolTip",error.Message); Shell.AddLog(error.Message); }
            inventoryTask=null; refresh.IsEnabled=true;
        }
        if(inventoryTask==null) inventoryTimer.Stop();
    }

    // Save-LibraryView
    static void SaveView() {
        if(Preferences.Test) return;
        string result=Engine.SaveLibraryView(view);
        if(result.Length>0) Shell.AddLog("Could not remember view: "+result.Substring(1));
    }

    // Test-AppCategory
    static bool InCategory(CatalogCard app,string wanted) {
        if(wanted=="All apps" || String.Equals(app.Category,wanted,StringComparison.OrdinalIgnoreCase)) return true;
        foreach(string other in app.AlsoIn) if(String.Equals(other,wanted,StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    // Update-Filter: checkbox instances and their selection are kept, and only the matching
    // cards stay attached to the grid.
    public static void UpdateFilter(bool forceAnimation) {
        var cards=Cards; var scroll=Scroll;
        var oldCards=new Dictionary<string,Point>();
        if(window.IsVisible) foreach(CheckBox card in cards.Children) {
            Point point=card.TranslatePoint(new Point(0,0),scroll);
            if(point.Y>=0 && point.Y<scroll.ViewportHeight) oldCards[(string)card.Tag]=point;
        }
        string query=Find<TextBox>("Search").Text.Trim();
        var visible=new List<CheckBox>();
        foreach(var app in catalog) {
            var check=checks[app.Key];
            bool viewMatch=view=="All apps" || query.Length>0 || (view=="Installed" && Installed(app.Key));
            bool match=viewMatch && InCategory(app,category) && texts[app.Key].IndexOf(query,StringComparison.OrdinalIgnoreCase)>=0;
            var visibility=match?Visibility.Visible:Visibility.Collapsed;
            if(check.Visibility!=visibility) check.Visibility=visibility;
            // A card listed under a second category shows that category while it is chosen.
            bool also=false; foreach(string other in app.AlsoIn) if(String.Equals(other,category,StringComparison.OrdinalIgnoreCase)) also=true;
            app.ShownCategory=also?category:app.Category;
            var content=check.Content as StackPanel;
            if(content!=null && content.Children.Count>1) I18n.Set(content.Children[1],"Text",app.ShownCategory);
            if(match) visible.Add(check);
        }
        bool changed=cards.Children.Count!=visible.Count;
        for(int i=0;!changed && i<visible.Count;i++) changed=!ReferenceEquals(cards.Children[i],visible[i]);
        if(changed) { cards.Children.Clear(); foreach(var card in visible) cards.Children.Add(card); }
        if(Shell.Mode!="Uninstall") Shell.SetText("ResultCount",(view!="All apps" && query.Length==0?view:category)+" · "+visible.Count+" apps");
        foreach(var entry in viewButtons) {
            bool active=entry.Key==view;
            entry.Value.SetResourceReference(Control.BackgroundProperty,active?"AccentSurfaceBrush":"GlassControlFill");
            entry.Value.SetResourceReference(Control.ForegroundProperty,active?"AccentTextBrush":"TextPrimaryBrush");
        }
        foreach(var button in categoryButtons) button.IsChecked=view=="All apps" && (string)button.Tag==category;
        Shell.SetText("Empty",view=="Installed" && visible.Count==0?"No confirmed installed catalog apps. Refresh status; guided apps and unavailable inventory remain Unknown.":"No apps found. Try another search or All apps.");
        Shell.Show("Empty",visible.Count==0);
        scroll.ScrollToTop();
        NativeUI.Realize(cards,scroll);
        if(forceAnimation) AnimateLibrary();
        else if(changed && window.IsVisible) {
            cards.UpdateLayout(); int index=0;
            foreach(CheckBox card in cards.Children) {
                Point point=card.TranslatePoint(new Point(0,0),scroll);
                if(point.Y>scroll.ViewportHeight) break;
                Point old;
                if(oldCards.TryGetValue((string)card.Tag,out old)) Motion.Reflow(card,old.X-point.X,old.Y-point.Y);
                else AnimateCardEntrance(card,Math.Min(100,index*18));
                index++;
            }
            if(visible.Count==0) Motion.Enter(Find<FrameworkElement>("Empty"),0,5,0);
        }
    }

    static void SelectCategory(object sender,RoutedEventArgs e) {
        string wanted=(string)((FrameworkElement)sender).Tag;
        if(category==wanted && view=="All apps") return;
        category=wanted; view="All apps";
        SaveView(); UpdateFilter(false);
    }

    static void BuildCategories() {
        var host=Find<Panel>("Categories"); if(host==null) return;
        foreach(string group in new[]{"All apps","Everyday","Create","Files & Storage","PC & Tools"}) {
            Panel panel=host;
            var names=new SortedSet<string>(StringComparer.CurrentCultureIgnoreCase);
            if(group=="All apps") names.Add("All apps");
            else {
                panel=new StackPanel { Margin=new Thickness(10,4,4,4) };
                var expander=new Expander { Content=panel, FontWeight=FontWeights.SemiBold, Style=(Style)window.Resources["CategoryGroup"], Margin=new Thickness(0,4,0,4), MinHeight=32, IsExpanded=false };
                I18n.Set(expander,"Header",group);
                expander.Expanded+=delegate(object sender,RoutedEventArgs e) { foreach(var other in categoryGroups) if(!ReferenceEquals(other,sender)) other.IsExpanded=false; };
                expander.SetResourceReference(Control.ForegroundProperty,"TextPrimaryBrush");
                AutomationProperties.SetName(expander,group+" categories");
                categoryGroups.Add(expander); host.Children.Add(expander);
                foreach(var app in catalog) if(app.CategoryGroup==group) names.Add(app.Category);
            }
            foreach(string name in names) {
                var button=new RadioButton { Style=(Style)window.Resources["CategoryItem"], GroupName="LibraryCategories", Tag=name, Content=Shell.NewLabel(name,false,14) };
                AutomationProperties.SetName(button,name);
                if(name=="All apps") button.Margin=new Thickness(0,0,0,12);
                button.IsChecked=name==category;
                button.Checked+=SelectCategory; button.Click+=SelectCategory;
                categoryButtons.Add(button); panel.Children.Add(button);
            }
        }
    }

    static void BuildViews() {
        var bar=Find<Panel>("LibraryViews"); if(bar==null) return;
        foreach(string name in new[]{"All apps","Installed"}) {
            var button=new Button { Tag=name, Padding=new Thickness(10,6,10,6), FontSize=12 };
            I18n.Set(button,"Content",name);
            button.Click+=delegate(object sender,RoutedEventArgs e) { view=(string)((Button)sender).Tag; category="All apps"; SaveView(); UpdateFilter(false); };
            viewButtons[name]=button; bar.Children.Add(button);
        }
        refresh=new Button { Padding=new Thickness(10,6,10,6), FontSize=12 };
        I18n.Set(refresh,"Content","Refresh");
        refresh.Click+=delegate { RefreshInventory(); };
        bar.Children.Add(refresh);
    }

    sealed class InfoDialog { public Window Window; public DockPanel Dock; public TextBox Text; }

    // New-InfoDialog: a borderless window in the application's appearance.
    static InfoDialog NewInfoDialog(string title,string text) {
        var panes=Find<FrameworkElement>("AppPanes");
        var dialog=new Window { FlowDirection=panes.FlowDirection, Language=window.Language, Owner=window, Icon=window.Icon, Width=640, Height=Math.Min(680,SystemParameters.WorkArea.Height-40), MinWidth=380, MinHeight=360, WindowStartupLocation=WindowStartupLocation.CenterOwner, WindowStyle=WindowStyle.None, ShowInTaskbar=false, FontFamily=window.FontFamily, FontSize=13, Resources=window.Resources };
        I18n.Set(dialog,"Title",title+" · 1nstall");
        dialog.SetResourceReference(Control.BackgroundProperty,"OpaqueWindowFill"); dialog.SetResourceReference(Control.ForegroundProperty,"TextPrimaryBrush");
        WindowChrome.SetWindowChrome(dialog,new WindowChrome { CaptionHeight=24, ResizeBorderThickness=new Thickness(6), GlassFrameThickness=new Thickness(0), UseAeroCaptionButtons=false });
        dialog.SourceInitialized+=delegate(object sender,EventArgs e) { FirstInstallWindow.Apply(new WindowInteropHelper((Window)sender).Handle,Theme.Light); };
        var dock=new DockPanel { Margin=new Thickness(24) }; dialog.Content=dock;
        var header=new Grid { Margin=new Thickness(0,0,0,18) };
        var heading=Shell.NewLabel(title,false,27); heading.FontWeight=FontWeights.SemiBold; heading.Margin=new Thickness(0,0,44,0);
        header.Children.Add(heading);
        var dismiss=new Button { Style=(Style)window.Resources["CaptionButton"], Width=28, Height=28, MinHeight=28, HorizontalAlignment=HorizontalAlignment.Right, VerticalAlignment=VerticalAlignment.Top };
        I18n.Set(dismiss,"Content","×"); I18n.Set(dismiss,"ToolTip","Close");
        AutomationProperties.SetName(dismiss,"Close details");
        WindowChrome.SetIsHitTestVisibleInChrome(dismiss,true);
        dismiss.Click+=delegate { dialog.Close(); };
        header.Children.Add(dismiss);
        DockPanel.SetDock(header,Dock.Top); dock.Children.Add(header);
        var close=new Button { IsCancel=true, Margin=new Thickness(0,16,0,0) }; I18n.Set(close,"Content","Close");
        close.Click+=delegate { dialog.Close(); };
        DockPanel.SetDock(close,Dock.Bottom); dock.Children.Add(close);
        var box=new TextBox { IsReadOnly=true, TextWrapping=TextWrapping.Wrap, VerticalScrollBarVisibility=ScrollBarVisibility.Auto, Padding=new Thickness(0), Background=Brushes.Transparent, BorderThickness=new Thickness(0), FontSize=13 };
        I18n.Set(box,"Text",text);
        dock.Children.Add(box);
        return new InfoDialog { Window=dialog, Dock=dock, Text=box };
    }

    // Show-AppDetails
    static void ShowDetails(string key) {
        string[] rows=Engine.Details(key).Split('\u001E');
        if(rows[0].StartsWith("!",StringComparison.Ordinal)) return;
        string[] header=rows[0].Split('\u001F');
        var info=NewInfoDialog(header[0],"");
        info.Dock.Children.Remove(info.Text);
        var scroll=new ScrollViewer { VerticalScrollBarVisibility=ScrollBarVisibility.Auto, HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled };
        var content=new StackPanel { Margin=new Thickness(0,0,8,0) }; scroll.Content=content;
        var description=Shell.NewLabel(header[1],true,14); description.Margin=new Thickness(0,0,0,18); content.Children.Add(description);
        StackPanel fields=null; string section=null;
        for(int i=1;i<rows.Length;i++) {
            string[] row=rows[i].Split('\u001F'); if(row.Length!=3) continue;
            if(row[0]!=section) {
                section=row[0];
                var panel=new Border { CornerRadius=new CornerRadius(16), Padding=new Thickness(16), Margin=new Thickness(0,0,0,12) };
                panel.SetResourceReference(Border.BackgroundProperty,"ContentFill");
                fields=new StackPanel(); panel.Child=fields;
                var title=Shell.NewLabel(section,false,16); title.FontWeight=FontWeights.SemiBold; title.Margin=new Thickness(0,0,0,6); fields.Children.Add(title);
                content.Children.Add(panel);
            }
            var label=Shell.NewLabel(row[1],true,12); label.Margin=new Thickness(0,10,0,3); fields.Children.Add(label);
            fields.Children.Add(Shell.NewLabel(row[2],false,13));
        }
        var website=new Button { Tag=header[2], IsEnabled=header[3]=="1", Margin=new Thickness(0,8,0,0) };
        I18n.Set(website,"Content","Open official website ↗");
        bool openable=header[4]=="1";
        website.Click+=delegate { if(openable) Process.Start(header[2]); };
        DockPanel.SetDock(website,Dock.Bottom); info.Dock.Children.Insert(1,website);
        info.Dock.Children.Add(scroll);
        info.Window.ShowDialog();
    }

    // Show-SetupPreview: rows are key, name and state. Returns the chosen keys, or null when dismissed.
    static List<string> ShowSetupPreview(string records,string title) {
        var info=NewInfoDialog(title,"This portable setup restores an app selection. It does not back up personal files, app settings or credentials, and cannot guarantee identical versions. Package availability is checked by WinGet when installation starts.");
        var list=new StackPanel();
        var scroll=new ScrollViewer { Content=list, VerticalScrollBarVisibility=ScrollBarVisibility.Auto };
        info.Dock.Children.Remove(info.Text); info.Dock.Children.Add(scroll);
        list.Children.Add(Shell.NewLabel((string)info.Text.Resources["1nstall.i18n.Text"],true,12));
        var choices=new List<CheckBox>();
        if(records.Length>0) foreach(string record in records.Split('\u001E')) {
            string[] row=record.Split('\u001F'); if(row.Length!=3) continue;
            var choice=new CheckBox { Style=(Style)window.Resources["InstalledCheck"], Tag=row[0], IsEnabled=row[0].Length>0, IsChecked=row[0].Length>0, Margin=new Thickness(0,12,0,0) };
            I18n.Set(choice,"Content",row[1]+" · "+row[2]);
            choices.Add(choice); list.Children.Add(choice);
        }
        var go=new Button { Margin=new Thickness(0,14,0,0) }; I18n.Set(go,"Content","Use selected apps");
        go.Click+=delegate { info.Window.DialogResult=true; };
        DockPanel.SetDock(go,Dock.Bottom); info.Dock.Children.Insert(1,go);
        if(info.Window.ShowDialog()!=true) return null;
        var keys=new List<string>();
        foreach(var choice in choices) if(choice.IsChecked==true && choice.IsEnabled) keys.Add((string)choice.Tag);
        return keys;
    }

    static void Refused(string result,string title) { if(result.StartsWith("!",StringComparison.Ordinal)) throw new InvalidOperationException(result.Substring(1)); }

    // Load-UserProfile, as src/manager-ui.ps1 redefines it: preview first, then select.
    static void LoadUserProfile(string path) {
        string rows=Engine.ReadSetup(path);
        Refused(rows,null);
        var keys=ShowSetupPreview(rows,"Preview portable setup");
        if(keys!=null) SetSelection(keys);
    }

    static void SaveProfile() {
        var dialog=new SaveFileDialog { Filter="1nstall profile (*.json)|*.json", FileName="my-setup.json" };
        if(dialog.ShowDialog(window)!=true) return;
        try { Refused(Engine.SaveSelection(dialog.FileName,SelectedKeys()),null); Shell.AddLog("Profile saved."); }
        catch(Exception error) { MessageBox.Show(window,error.Message,"Could not save profile"); }
    }

    static void SaveSnapshot() {
        string rows=Engine.SnapshotRows();
        if(rows.StartsWith("!",StringComparison.Ordinal)) { string[] refusal=rows.Substring(1).Split('\u001F'); MessageBox.Show(window,refusal.Length>1?refusal[1]:refusal[0],refusal[0]); return; }
        var keys=ShowSetupPreview(rows,"Select installed apps to save");
        if(keys==null || keys.Count==0) return;
        var dialog=new SaveFileDialog { Filter="1nstall setup (*.json)|*.json", FileName="installed-setup.json" };
        if(dialog.ShowDialog(window)!=true) return;
        try { Refused(Engine.SaveSnapshot(dialog.FileName,String.Join("\u001F",keys)),null); Shell.AddLog("Installed setup snapshot saved."); }
        catch(Exception error) { MessageBox.Show(window,error.Message,"Could not save setup"); }
    }

    // The built-in profiles menu. Built when first opened: twenty profiles and their plans
    // are not needed to start.
    static ContextMenu BuildProfilesMenu(Button profilesButton) {
        var menu=new ContextMenu { Resources=window.Resources, PlacementTarget=profilesButton, Placement=PlacementMode.Bottom, MaxHeight=Math.Min(640,Math.Max(300,SystemParameters.WorkArea.Height-100)) };
        string group=null;
        foreach(string record in Engine.ProfilesMenu().Split('\u001E')) {
            string[] fields=record.Split('\u001F'); if(fields.Length!=6) continue;
            if(fields[0]!=group) {
                group=fields[0];
                if(menu.Items.Count>0) menu.Items.Add(new Separator());
                var heading=new MenuItem { IsEnabled=false, FontWeight=FontWeights.SemiBold, FontSize=11, Padding=new Thickness(10,6,10,6) };
                I18n.Set(heading,"Header",group); menu.Items.Add(heading);
            }
            string[] names=fields[4].Split('\u001D'); string name=fields[2]; string[] keys=fields[5].Split('\u001D');
            var item=new MenuItem { Tag=fields[1], Padding=new Thickness(10,6,10,6) };
            I18n.Set(item,"Header",name+" ("+names.Length+" apps)");
            var tip=Shell.NewLabel(fields[3]+"\n\n"+String.Join(", ",names),false,12); tip.MaxWidth=420; item.ToolTip=tip;
            AutomationProperties.SetName(item,name+" profile, "+names.Length+" apps");
            // Apply-Profile
            item.Click+=delegate {
                if(!Busy) { SetSelection(keys); Shell.SetText("Status",name+" profile applied. Review your apps before installing."); }
                menu.IsOpen=false;
            };
            menu.Items.Add(item);
        }
        menu.Opened+=delegate { Motion.Enter(menu,0,3,0); };
        return menu;
    }

    static void BuildProfileMenus() {
        var profilesButton=Find<Button>("Profiles");
        if(profilesButton!=null) {
            ContextMenu menu=null;
            I18n.Set(profilesButton,"ToolTip","Choose a profile to select its apps. Review and adjust before installing.");
            profilesButton.Click+=delegate { if(menu==null) menu=BuildProfilesMenu(profilesButton); menu.IsOpen=true; };
        }
        var userButton=Find<Button>("UserProfiles");
        if(userButton==null) return;
        var userMenu=new ContextMenu { Resources=window.Resources, PlacementTarget=userButton, Placement=PlacementMode.Bottom };
        userMenu.Opened+=delegate { Motion.Enter(userMenu,0,3,0); };
        export=new MenuItem(); I18n.Set(export,"Header","Save current selection..."); export.Click+=delegate { SaveProfile(); }; userMenu.Items.Add(export);
        var import=new MenuItem(); I18n.Set(import,"Header","Load saved profile...");
        import.Click+=delegate {
            var dialog=new OpenFileDialog { Filter="1nstall profile (*.json)|*.json" };
            if(dialog.ShowDialog(window)!=true) return;
            try { LoadUserProfile(dialog.FileName); Shell.AddLog("Profile imported."); }
            catch(Exception error) { MessageBox.Show(window,error.Message,"Could not import profile"); }
        };
        userMenu.Items.Add(import);
        var snapshot=new MenuItem(); I18n.Set(snapshot,"Header","Save installed setup snapshot…"); snapshot.Click+=delegate { SaveSnapshot(); }; userMenu.Items.Add(snapshot);
        userButton.Click+=delegate { export.IsEnabled=selected.Count>0; userMenu.IsOpen=true; };
        var saveSetup=Find<Button>("SaveSetup"); if(saveSetup!=null) saveSetup.Click+=delegate { SaveProfile(); };
    }

    static CheckBox CardOf(object source) {
        var element=source as DependencyObject;
        while(element is Visual && !(element is CheckBox)) element=VisualTreeHelper.GetParent(element);
        return element as CheckBox;
    }

    public static void Initialize(Window target,CatalogCard[] apps,string savedView,bool refreshOnLoad) {
        window=target; catalog=apps; view=savedView;
        NativeUI.Filled=delegate(CheckBox card) { Dress(card); I18n.UpdateTree(card); };
        foreach(var app in catalog) byKey[app.Key]=app;
        NativeUI.Populate(window,catalog);
        checks=(Dictionary<string,CheckBox>)window.Resources["NativeChecks"];
        texts=(Dictionary<string,string>)window.Resources["NativeSearchTexts"];
        foreach(var check in checks.Values) { check.Checked+=CardToggled; check.Unchecked+=CardToggled; }
        var cards=Cards;
        // The Details button of a card, and F1 on a card, open its details.
        cards.AddHandler(ButtonBase.ClickEvent,new RoutedEventHandler(delegate(object sender,RoutedEventArgs e) {
            var button=e.Source as Button;
            if(button!=null && button.Tag is string) { e.Handled=true; ShowDetails((string)button.Tag); }
        }));
        cards.PreviewKeyDown+=delegate(object sender,KeyEventArgs e) {
            if(e.Key!=Key.F1) return;
            var card=CardOf(e.OriginalSource); if(card!=null) { e.Handled=true; ShowDetails((string)card.Tag); }
        };
        cards.MouseMove+=delegate(object sender,MouseEventArgs e) {
            if(!Theme.Glass || !Motion.Enabled) return;
            var card=CardOf(e.OriginalSource); if(card==null || card.Template==null) return;
            var light=card.Template.FindName("HoverLight",card) as Border;
            if(light!=null) Theme.MoveGlassLight(light,e.GetPosition(light));
        };
        BuildCategories();
        BuildViews();
        BuildProfileMenus();
        var search=Find<TextBox>("Search");
        search.TextChanged+=delegate { UpdateFilter(false); };
        var clearSearch=Find<Button>("ClearSearch"); if(clearSearch!=null) clearSearch.Click+=delegate { search.Clear(); search.Focus(); };
        var clear=Find<Button>("ClearSelection"); if(clear!=null) clear.Click+=delegate { SetSelection(new string[0]); };
        var scroll=Scroll;
        scroll.ScrollChanged+=delegate(object sender,ScrollChangedEventArgs e) {
            if(e.ViewportWidthChange!=0) UpdateLayout(); else NativeUI.Realize(cards,scroll);
        };
        Shell.SetText("Environment",Engine.Winget().Length>0?"WinGet ready · "+catalog.Length+" apps to explore":"WinGet is missing. Install App Installer to enable automatic installs.");
        inventoryTimer=new DispatcherTimer { Interval=TimeSpan.FromMilliseconds(250) };
        inventoryTimer.Tick+=InventoryTick;
        window.Closed+=delegate { inventoryTimer.Stop(); };
        // 3.6 asks WinGet what is installed as soon as the window is loaded. The interface test
        // mode leaves that to its Refresh button, so a test decides when WinGet runs.
        window.Loaded+=delegate { UpdateLayout(); AnimateLibrary(); if(refreshOnLoad) RefreshInventory(); };
        UpdateSelection();
    }

    // Update-CardLayout, for the card grid.
    public static void UpdateLayout() {
        var scroll=Scroll;
        double available=scroll.ViewportWidth-8;
        if(available<=0 || double.IsInfinity(available)) return;
        NativeUI.Layout(Cards,available,scroll.ViewportHeight,scroll.VerticalOffset);
        var row=Find<FrameworkElement>("InstallSearchRow"); if(row!=null) row.Width=available;
    }
}
