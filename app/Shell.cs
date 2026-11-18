// The main window: the compiled 3.6 interface, wired in C# to the Rust engine.
//
// Ported so far: the install library (cards, category list, search, selection and its plan),
// appearance, languages and the Settings page.
// Still to port from vexan_installers.ps1 and src/manager-ui.ps1: category filtering, library
// views, profiles, running the queue, the uninstall pages, and history and diagnostics.
using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using OneInstall;

// What the worker thread reads from the engine while WPF starts.
sealed class StartupData {
    public CatalogCard[] Cards;
    public string Settings, Language;
}

static class Shell {
    static Window window;
    static CatalogCard[] catalog;
    static Dictionary<string,CheckBox> checks;
    static Dictionary<string,string> texts;
    static readonly List<string> selected=new List<string>();
    static bool syncing;
    // "Install" or "Settings" so far.
    public static string Mode="Install";

    static T Find<T>(string name) where T:class { return window.FindName(name) as T; }
    public static void Show(string name,bool visible) { var element=Find<UIElement>(name); if(element!=null) element.Visibility=visible?Visibility.Visible:Visibility.Collapsed; }
    static void SetText(string name,string text) { var element=Find<TextBlock>(name); if(element!=null) I18n.Set(element,"Text",text); }

    // New-Label: a translated label in the primary or secondary text colour.
    public static TextBlock NewLabel(string text,bool secondary,double size) {
        var label=new TextBlock { FontSize=size, TextWrapping=TextWrapping.Wrap };
        I18n.Set(label,"Text",text);
        label.SetResourceReference(TextBlock.ForegroundProperty,secondary?"TextSecondaryBrush":"TextPrimaryBrush");
        label.FontFamily=size>=20?(FontFamily)window.Resources["HeadingFont"]:window.FontFamily;
        return label;
    }

    // Update-CardLayout of 3.6, for the card grid only.
    static void UpdateLayout() {
        var scroll=Find<ScrollViewer>("LibraryScroll"); var cards=Find<UniformGrid>("Cards");
        double available=scroll.ViewportWidth-8;
        if(available<=0 || double.IsInfinity(available)) return;
        NativeUI.Layout(cards,available,scroll.ViewportHeight,scroll.VerticalOffset);
        var row=Find<FrameworkElement>("InstallSearchRow"); if(row!=null) row.Width=available;
    }

    // Update-Selection of 3.6: the count, and one row per planned app, dependencies first.
    static void UpdateSelection() {
        // Nothing selected needs no plan, which also keeps the engine call off the start-up path.
        string plan=selected.Count==0?"":Engine.Plan(String.Join("\u001F",selected));
        string error=plan.StartsWith("!",StringComparison.Ordinal)?plan.Substring(1):null;
        SetText("SelectedCount",selected.Count==1?"1 app selected":selected.Count+" apps selected");
        var install=Find<Button>("Install"); if(install!=null) install.IsEnabled=selected.Count>0;
        var save=Find<Button>("SaveSetup"); if(save!=null) save.IsEnabled=selected.Count>0;
        var queue=Find<Panel>("QueuePanel"); queue.Children.Clear();
        if(selected.Count==0) {
            var hint=NewLabel("Your next setup starts here. Select apps from the library.",true,13); hint.Margin=new Thickness(0,15,0,0); queue.Children.Add(hint);
        }
        if(error==null && plan.Length>0) foreach(string record in plan.Split('\u001E')) {
            string[] fields=record.Split('\u001F');
            string key=fields[0], name=fields[1];
            var panel=new StackPanel { Margin=new Thickness(0,8,0,9), Tag=key };
            var grid=new Grid(); grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width=GridLength.Auto });
            var title=NewLabel(name,false,13); title.FontWeight=FontWeights.SemiBold; title.Margin=new Thickness(0,0,8,0); title.VerticalAlignment=VerticalAlignment.Center;
            grid.Children.Add(title);
            var remove=new Button { Tag=key, Width=32, MinHeight=32, Padding=new Thickness(0), Margin=new Thickness(0), FontSize=18, Background=Brushes.Transparent, BorderThickness=new Thickness(0) };
            I18n.Set(remove,"Content","×"); I18n.Set(remove,"ToolTip","Remove "+name+" from selection");
            AutomationProperties.SetName(remove,"Remove "+name+" from selection");
            Theme.EnableHoverMotion(remove);
            remove.Click+=delegate(object sender,RoutedEventArgs e) {
                CheckBox check; string removed=(string)((Button)sender).Tag;
                // A dependency added by the plan has no selection of its own to clear.
                if(checks.TryGetValue(removed,out check) && check.IsChecked==true) check.IsChecked=false;
            };
            Grid.SetColumn(remove,1); grid.Children.Add(remove); panel.Children.Add(grid);
            var method=NewLabel(fields[2]=="1"?"Automatic · WinGet":"Guided · official website",true,12); method.Margin=new Thickness(0,4,0,0); panel.Children.Add(method);
            queue.Children.Add(panel);
        }
        if(error!=null) SetText("Status",error);
        else if(selected.Count>0) SetText("Status","Selection updated. Review before installing.");
    }

    static void Toggle(object sender,RoutedEventArgs e) {
        if(syncing) return;
        var check=(CheckBox)sender; string key=(string)check.Tag;
        if(check.IsChecked==true) { if(!selected.Contains(key)) selected.Add(key); } else selected.Remove(key);
        UpdateSelection();
    }

    // Update-Filter of 3.6, for the search text only: checkbox instances and their selection
    // are kept, and only the matching cards stay attached to the grid.
    static void Filter() {
        string query=Find<TextBox>("Search").Text.Trim();
        var cards=Find<UniformGrid>("Cards"); var scroll=Find<ScrollViewer>("LibraryScroll");
        var visible=new List<CheckBox>();
        foreach(var app in catalog) {
            var check=checks[app.Key];
            bool match=texts[app.Key].IndexOf(query,StringComparison.OrdinalIgnoreCase)>=0;
            var visibility=match?Visibility.Visible:Visibility.Collapsed;
            if(check.Visibility!=visibility) check.Visibility=visibility;
            if(match) visible.Add(check);
        }
        bool changed=cards.Children.Count!=visible.Count;
        for(int i=0;!changed && i<visible.Count;i++) changed=!ReferenceEquals(cards.Children[i],visible[i]);
        if(changed) { cards.Children.Clear(); foreach(var card in visible) cards.Children.Add(card); }
        SetText("ResultCount","All apps · "+visible.Count+" apps");
        SetText("Empty","No apps found. Try another search or All apps.");
        Show("Empty",visible.Count==0);
        scroll.ScrollToTop();
        NativeUI.Realize(cards,scroll);
    }

    static void BuildCategories() {
        var host=Find<Panel>("Categories"); if(host==null) return;
        var groups=new Dictionary<string,SortedSet<string>>();
        foreach(var app in catalog) {
            if(!groups.ContainsKey(app.CategoryGroup)) groups[app.CategoryGroup]=new SortedSet<string>(StringComparer.CurrentCultureIgnoreCase);
            groups[app.CategoryGroup].Add(app.Category);
        }
        var all=new RadioButton { Style=(Style)window.Resources["CategoryItem"], GroupName="LibraryCategories", Content=NewLabel("All apps",false,14), IsChecked=true, Margin=new Thickness(0,0,0,12) };
        AutomationProperties.SetName(all,"All apps"); host.Children.Add(all);
        foreach(string group in new[]{"Everyday","Create","Files & Storage","PC & Tools"}) {
            if(!groups.ContainsKey(group)) continue;
            var panel=new StackPanel { Margin=new Thickness(10,4,4,4) };
            foreach(string category in groups[group]) {
                var button=new RadioButton { Style=(Style)window.Resources["CategoryItem"], GroupName="LibraryCategories", Content=NewLabel(category,false,14) };
                AutomationProperties.SetName(button,category); panel.Children.Add(button);
            }
            var expander=new Expander { Content=panel, FontWeight=FontWeights.SemiBold, Style=(Style)window.Resources["CategoryGroup"], Margin=new Thickness(0,4,0,4), MinHeight=32 };
            I18n.Set(expander,"Header",group);
            expander.SetResourceReference(Control.ForegroundProperty,"TextPrimaryBrush");
            AutomationProperties.SetName(expander,group+" categories"); host.Children.Add(expander);
        }
    }

    // Set-AppMode of 3.6, for the Install mode; the Uninstall mode is not ported yet.
    public static void SetMode(string mode) {
        SettingsPage.Hide();
        bool changed=Mode!=mode;
        if(changed) Motion.ClearDecorations();
        Mode=mode;
        Show("InstallLibrary",true); Show("SetupGlass",true); Show("CategoriesHost",true);
        Show("UninstallNavigation",false); Show("UninstallPage",false); Show("RemovalGlass",false);
        var controls=Find<FrameworkElement>("WindowControls"); if(controls!=null) controls.Margin=new Thickness(0,30,30,0);
        SetText("NavigationHeading","LIBRARY");
        foreach(string name in new[]{"InstallMode","UninstallMode","HistoryMode"}) {
            var button=Find<Control>(name); if(button==null) continue;
            if(name==mode+"Mode") button.SetResourceReference(Control.BackgroundProperty,"AccentSurfaceBrush"); else button.Background=Brushes.Transparent;
        }
        Filter();
        if(changed && window.IsVisible) {
            Motion.Enter(Find<FrameworkElement>("InstallLibrary"),0,10,0);
            Motion.Enter(Find<FrameworkElement>("SetupGlass"),10,0,40);
        }
    }

    // Apply-AppLanguage: ask the engine for the language, then re-translate the window in place.
    public static void ApplyLanguage() {
        I18n.Load(Engine.Language(Preferences.Language,I18n.UiCulture));
        TranslateWindow();
    }
    static void TranslateWindow() {
        var cards=new List<FrameworkElement>();
        foreach(var check in checks.Values) cards.Add(check);
        I18n.Apply(window,cards,SettingsPage.Page);
        UpdateLayout();
    }

    public static void Run(bool test,bool startupTest,StartupTimer clock,StringBuilder output,Task<StartupData> loading) {
        var application=new Application { ShutdownMode=ShutdownMode.OnMainWindowClose };
        Program.Mark("application");
        window=new MainWindow { Title="1nstall 4.0" };
        Motion.Initialize(window);
        Program.Mark("window created");

        var data=loading.GetAwaiter().GetResult();
        Preferences.Test=test; Preferences.Load(data.Settings); I18n.Load(data.Language);
        Program.Mark("engine and settings ready");
        Theme.Initialize(window);
        window.SourceInitialized+=delegate { Theme.SourceInitialized(); };
        // Creating the system window now, instead of when it is shown, lets WPF start the graphics
        // device on its render thread while this thread builds the cards. The height is the one
        // the card builder sets, fixed first so the window is centred with its final size.
        window.Height=Math.Min(840,SystemParameters.WorkArea.Height-24);
        new WindowInteropHelper(window).EnsureHandle();
        Program.Mark("appearance");

        catalog=data.Cards;
        NativeUI.Filled=delegate(CheckBox card) { I18n.UpdateTree(card); };
        NativeUI.Populate(window,catalog);
        checks=(Dictionary<string,CheckBox>)window.Resources["NativeChecks"];
        texts=(Dictionary<string,string>)window.Resources["NativeSearchTexts"];
        foreach(var check in checks.Values) { check.Checked+=Toggle; check.Unchecked+=Toggle; }
        Program.Mark("cards");
        BuildCategories();

        var search=Find<TextBox>("Search");
        if(search!=null) search.TextChanged+=delegate { Filter(); };
        var clearSearch=Find<Button>("ClearSearch"); if(clearSearch!=null && search!=null) clearSearch.Click+=delegate { search.Clear(); search.Focus(); };
        var clear=Find<Button>("ClearSelection");
        if(clear!=null) clear.Click+=delegate { syncing=true; foreach(string key in selected) checks[key].IsChecked=false; syncing=false; selected.Clear(); UpdateSelection(); };
        var minimize=Find<Button>("MinimizeWindow"); if(minimize!=null) minimize.Click+=delegate { window.WindowState=WindowState.Minimized; };
        var maximize=Find<Button>("MaximizeWindow"); if(maximize!=null) maximize.Click+=delegate { window.WindowState=window.WindowState==WindowState.Maximized?WindowState.Normal:WindowState.Maximized; };
        var close=Find<Button>("CloseWindow"); if(close!=null) close.Click+=delegate { window.Close(); };
        var brand=Find<UIElement>("BrandHeader"); if(brand!=null) brand.MouseLeftButtonDown+=delegate { try { window.DragMove(); } catch(InvalidOperationException) { } };
        var donate=Find<Button>("Donate"); if(donate!=null) donate.Click+=delegate { System.Diagnostics.Process.Start("https://ko-fi.com/braga1k"); };
        var installMode=Find<Button>("InstallMode"); if(installMode!=null) installMode.Click+=delegate { SetMode("Install"); };
        var scroll=Find<ScrollViewer>("LibraryScroll");
        scroll.ScrollChanged+=delegate(object sender,ScrollChangedEventArgs e) {
            if(e.ViewportWidthChange!=0) UpdateLayout(); else NativeUI.Realize(Find<UniformGrid>("Cards"),scroll);
        };
        // The named buttons of the window follow the pointer with a light, as in 3.6.
        foreach(string name in new[]{"ClearSearch","UserProfiles","ClearSelection","SaveSetup","Import","Export","Install","Cancel","OpenLogs","MinimizeWindow","MaximizeWindow","CloseWindow","InstallMode","UninstallMode","RefreshInstalled","WindowsAppsSettings","ClearUninstallSelection","CheckLeftovers","OpenUninstallBackups","ReviewUninstall","StopUninstall","Donate"}) {
            var button=Find<Button>(name); if(button!=null) Theme.EnableHoverMotion(button);
        }
        window.Loaded+=delegate { Motion.Opening(window); UpdateLayout(); };

        SettingsPage.Initialize(window);
        UpdateSelection();
        SetMode("Install");
        TranslateWindow();
        Program.Mark("window wired");

        if(startupTest) {
            // The marks 3.6 reports: before show, loaded, content drawn, then the dispatcher idle.
            Program.Mark("before show");
            long beforeShow=clock.ElapsedMilliseconds, loaded=0, rendered=0, ready=0;
            window.Loaded+=delegate { loaded=clock.ElapsedMilliseconds; Program.Mark("loaded"); };
            window.ContentRendered+=delegate {
                rendered=clock.ElapsedMilliseconds; Program.Mark("rendered");
                window.Dispatcher.BeginInvoke(new Action(delegate { ready=clock.ElapsedMilliseconds; Program.Mark("ready"); window.Close(); }),DispatcherPriority.ApplicationIdle);
            };
            application.Run(window);
            if(ready==0) throw new Exception("Window did not reach the ready checkpoint.");
            output.AppendLine("READY "+ready); output.AppendLine("FirstFrameMs 0");
            output.AppendLine("BeforeShowMs "+beforeShow); output.AppendLine("LoadedMs "+loaded); output.AppendLine("RenderMs "+rendered);
        } else application.Run(window);
    }
}
