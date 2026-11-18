// The main window: the compiled 3.6 interface, wired in C# to the Rust engine.
//
// Ported so far: the install library (cards, category list, search, selection and its plan).
// Still to port from vexan_installers.ps1, src/manager-ui.ps1 and src/settings.ps1: category
// filtering, library views, profiles, running the queue, the uninstall pages, history and
// diagnostics, settings, languages and updates.
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

static class Shell {
    static Window window;
    static CatalogCard[] catalog;
    static Dictionary<string,CheckBox> checks;
    static Dictionary<string,string> texts;
    static readonly List<string> selected=new List<string>();
    static bool syncing;

    static T Find<T>(string name) where T:class { return window.FindName(name) as T; }
    static void Show(string name,bool visible) { var element=Find<UIElement>(name); if(element!=null) element.Visibility=visible?Visibility.Visible:Visibility.Collapsed; }
    static TextBlock Label(string text,double size,bool secondary) { return NativeUI.Label(text,size,secondary); }
    static Color Mix(Color a,Color b,double amount) {
        return Color.FromRgb((byte)(a.R*(1-amount)+b.R*amount),(byte)(a.G*(1-amount)+b.G*amount),(byte)(a.B*(1-amount)+b.B*amount));
    }
    static double Luminance(Color color) { return FirstInstallWindow.Luminance(color.R,color.G,color.B); }

    // Set-AccentPalette of 3.6, without the glass tinting.
    static void ApplyAccent(Color color) {
        Color white=Colors.White, surface=(Color)ColorConverter.ConvertFromString("#21283B"), text=color;
        for(int i=0;i<20 && (Luminance(text)+0.05)/(Luminance(surface)+0.05)<4.5;i++) text=Mix(text,white,0.12);
        Color foreground=Luminance(color)>0.179?Colors.Black:white;
        Color contrast=foreground==white?Colors.Black:white;
        window.Resources["AccentBrush"]=new SolidColorBrush(color);
        window.Resources["AccentTextBrush"]=new SolidColorBrush(text);
        window.Resources["AccentForegroundBrush"]=new SolidColorBrush(foreground);
        window.Resources["AccentMutedBrush"]=new SolidColorBrush(Mix(text,surface,0.25));
        window.Resources["AccentHoverBrush"]=new SolidColorBrush(Mix(text,white,0.15));
        window.Resources["AccentSurfaceBrush"]=new SolidColorBrush(Mix(color,surface,0.82));
        var action=new LinearGradientBrush { StartPoint=new Point(0,0), EndPoint=new Point(0.25,1) };
        action.GradientStops.Add(new GradientStop(Mix(color,contrast,0.22),0));
        action.GradientStops.Add(new GradientStop(color,0.4));
        action.GradientStops.Add(new GradientStop(Mix(color,contrast,0.12),1));
        window.Resources["AccentActionBrush"]=action;
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
        var count=Find<TextBlock>("SelectedCount"); if(count!=null) count.Text=selected.Count==1?"1 app selected":selected.Count+" apps selected";
        var install=Find<Button>("Install"); if(install!=null) install.IsEnabled=selected.Count>0;
        var save=Find<Button>("SaveSetup"); if(save!=null) save.IsEnabled=selected.Count>0;
        var queue=Find<Panel>("QueuePanel"); queue.Children.Clear();
        if(selected.Count==0) {
            var hint=Label("Your next setup starts here. Select apps from the library.",13,true); hint.Margin=new Thickness(0,15,0,0); queue.Children.Add(hint);
        }
        if(error==null && plan.Length>0) foreach(string record in plan.Split('\u001E')) {
            string[] fields=record.Split('\u001F');
            string key=fields[0], name=fields[1];
            var panel=new StackPanel { Margin=new Thickness(0,8,0,9), Tag=key };
            var grid=new Grid(); grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width=GridLength.Auto });
            var title=Label(name,13,false); title.FontWeight=FontWeights.SemiBold; title.Margin=new Thickness(0,0,8,0); title.VerticalAlignment=VerticalAlignment.Center;
            grid.Children.Add(title);
            var remove=new Button { Content="×", Tag=key, Width=32, MinHeight=32, Padding=new Thickness(0), Margin=new Thickness(0), FontSize=18, Background=Brushes.Transparent, BorderThickness=new Thickness(0), ToolTip="Remove "+name+" from selection" };
            AutomationProperties.SetName(remove,"Remove "+name+" from selection");
            remove.Click+=delegate(object sender,RoutedEventArgs e) {
                CheckBox check; string removed=(string)((Button)sender).Tag;
                // A dependency added by the plan has no selection of its own to clear.
                if(checks.TryGetValue(removed,out check) && check.IsChecked==true) check.IsChecked=false;
            };
            Grid.SetColumn(remove,1); grid.Children.Add(remove); panel.Children.Add(grid);
            var method=Label(fields[2]=="1"?"Automatic · WinGet":"Guided · official website",12,true); method.Margin=new Thickness(0,4,0,0); panel.Children.Add(method);
            queue.Children.Add(panel);
        }
        var status=Find<TextBlock>("Status");
        if(status!=null) status.Text=error ?? (selected.Count==0?"":"Selection updated. Review before installing.");
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
        var results=Find<TextBlock>("ResultCount"); if(results!=null) results.Text="All apps · "+visible.Count+" apps";
        var empty=Find<TextBlock>("Empty"); if(empty!=null) { empty.Text="No apps found. Try another search or All apps."; empty.Visibility=visible.Count==0?Visibility.Visible:Visibility.Collapsed; }
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
        var all=new RadioButton { Style=(Style)window.Resources["CategoryItem"], GroupName="LibraryCategories", Content=Label("All apps",14,false), IsChecked=true, Margin=new Thickness(0,0,0,12) };
        AutomationProperties.SetName(all,"All apps"); host.Children.Add(all);
        foreach(string group in new[]{"Everyday","Create","Files & Storage","PC & Tools"}) {
            if(!groups.ContainsKey(group)) continue;
            var panel=new StackPanel { Margin=new Thickness(10,4,4,4) };
            foreach(string category in groups[group]) {
                var button=new RadioButton { Style=(Style)window.Resources["CategoryItem"], GroupName="LibraryCategories", Content=Label(category,14,false) };
                AutomationProperties.SetName(button,category); panel.Children.Add(button);
            }
            var expander=new Expander { Header=group, Content=panel, FontWeight=FontWeights.SemiBold, Style=(Style)window.Resources["CategoryGroup"], Margin=new Thickness(0,4,0,4), MinHeight=32 };
            expander.SetResourceReference(Control.ForegroundProperty,"TextPrimaryBrush");
            AutomationProperties.SetName(expander,group+" categories"); host.Children.Add(expander);
        }
    }

    public static void Run(bool startupTest,StartupTimer clock,StringBuilder output,Task<CatalogCard[]> cards) {
        var application=new Application { ShutdownMode=ShutdownMode.OnMainWindowClose };
        Program.Mark("application");
        window=new MainWindow { Title="1nstall 4.0" };
        window.SourceInitialized+=delegate { FirstInstallWindow.Apply(new WindowInteropHelper(window).Handle,false); };
        // Creating the system window now, instead of when it is shown, lets WPF start the graphics
        // device on its render thread while this thread builds the cards. The height is the one
        // the card builder sets, fixed first so the window is centred with its final size.
        window.Height=Math.Min(840,SystemParameters.WorkArea.Height-24);
        new WindowInteropHelper(window).EnsureHandle();
        Program.Mark("window created");
        Motion.Initialize(window);
        Color accent=SystemParameters.WindowGlassColor; accent.A=255;
        OneInstallAppearance.Apply(window,false,true,accent,true,false);
        ApplyAccent(accent);
        Program.Mark("appearance");

        catalog=cards.GetAwaiter().GetResult();
        Program.Mark("engine and catalog ready");
        NativeUI.Populate(window,catalog);
        checks=(Dictionary<string,CheckBox>)window.Resources["NativeChecks"];
        texts=(Dictionary<string,string>)window.Resources["NativeSearchTexts"];
        foreach(var check in checks.Values) { check.Checked+=Toggle; check.Unchecked+=Toggle; }
        Program.Mark("cards");
        BuildCategories();
        Program.Mark("categories");

        // Install mode, as Set-AppMode 'Install' leaves the window.
        Show("InstallLibrary",true); Show("SetupGlass",true); Show("CategoriesHost",true);
        Show("UninstallNavigation",false); Show("UninstallPage",false); Show("RemovalGlass",false);
        var controls=Find<FrameworkElement>("WindowControls"); if(controls!=null) controls.Margin=new Thickness(0,30,30,0);
        var heading=Find<TextBlock>("NavigationHeading"); if(heading!=null) heading.Text="LIBRARY";
        var results=Find<TextBlock>("ResultCount"); if(results!=null) results.Text="All apps · "+checks.Count+" apps";
        var installMode=Find<Control>("InstallMode"); if(installMode!=null) installMode.SetResourceReference(Control.BackgroundProperty,"AccentSurfaceBrush");
        UpdateSelection();

        var search=Find<TextBox>("Search");
        if(search!=null) search.TextChanged+=delegate { Filter(); };
        var clearSearch=Find<Button>("ClearSearch"); if(clearSearch!=null && search!=null) clearSearch.Click+=delegate { search.Clear(); search.Focus(); };
        var clear=Find<Button>("ClearSelection");
        if(clear!=null) clear.Click+=delegate { syncing=true; foreach(string key in selected) checks[key].IsChecked=false; syncing=false; selected.Clear(); UpdateSelection(); };
        var minimize=Find<Button>("MinimizeWindow"); if(minimize!=null) minimize.Click+=delegate { window.WindowState=WindowState.Minimized; };
        var maximize=Find<Button>("MaximizeWindow"); if(maximize!=null) maximize.Click+=delegate { window.WindowState=window.WindowState==WindowState.Maximized?WindowState.Normal:WindowState.Maximized; };
        var close=Find<Button>("CloseWindow"); if(close!=null) close.Click+=delegate { window.Close(); };
        var brand=Find<UIElement>("BrandHeader"); if(brand!=null) brand.MouseLeftButtonDown+=delegate { try { window.DragMove(); } catch(InvalidOperationException) { } };
        var scroll=Find<ScrollViewer>("LibraryScroll");
        scroll.ScrollChanged+=delegate(object sender,ScrollChangedEventArgs e) {
            if(e.ViewportWidthChange!=0) UpdateLayout(); else NativeUI.Realize(Find<UniformGrid>("Cards"),scroll);
        };
        window.Loaded+=delegate { UpdateLayout(); };

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
