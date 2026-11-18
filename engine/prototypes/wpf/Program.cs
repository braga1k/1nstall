// Prototype 3 of 3: the 3.6 WPF interface hosted by plain C#, with no PowerShell,
// and every piece of data and logic coming from the Rust engine DLL.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

static class Engine {
    [DllImport("oneinstall_ffi.dll")] static extern IntPtr oi_catalog();
    [DllImport("oneinstall_ffi.dll", CharSet=CharSet.Unicode)] static extern IntPtr oi_plan(string keysJson);
    [DllImport("oneinstall_ffi.dll")] static extern IntPtr oi_installed();
    [DllImport("oneinstall_ffi.dll")] static extern void oi_free(IntPtr text);
    [DllImport("oneinstall_ffi.dll")] public static extern ulong oi_clock_ms();
    [DllImport("oneinstall_ffi.dll")] public static extern void oi_report(ulong renderMs, ulong readyMs);
    static string Take(IntPtr text) { try { return Marshal.PtrToStringUni(text); } finally { oi_free(text); } }
    public static string Catalog() { return Take(oi_catalog()); }
    public static string Plan(string keysJson) { return Take(oi_plan(keysJson)); }
    public static string Installed() { return Take(oi_installed()); }
}

static class Program {
    static Window window;
    static Dictionary<string,CheckBox> checks;
    static Dictionary<string,string> texts;
    static readonly List<string> selected=new List<string>();
    static readonly JavaScriptSerializer json=new JavaScriptSerializer();
    static bool syncing;

    static T Find<T>(string name) where T:class { return window.FindName(name) as T; }
    static void Show(string name,bool visible) { var element=Find<UIElement>(name); if(element!=null) element.Visibility=visible?Visibility.Visible:Visibility.Collapsed; }
    static TextBlock Label(string text,double size,bool secondary) { return OneInstall.NativeUI.Label(text,size,secondary); }
    static Color Mix(Color a,Color b,double amount) {
        return Color.FromRgb((byte)(a.R*(1-amount)+b.R*amount),(byte)(a.G*(1-amount)+b.G*amount),(byte)(a.B*(1-amount)+b.B*amount));
    }
    static double Luminance(Color color) { return FirstInstallWindow.Luminance(color.R,color.G,color.B); }

    // The accent palette of 3.6 (Set-AccentPalette), without the glass tinting.
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

    static void UpdateLayout() {
        var scroll=Find<ScrollViewer>("LibraryScroll"); var cards=Find<UniformGrid>("Cards");
        double available=scroll.ViewportWidth-8;
        if(available<=0 || double.IsInfinity(available)) return;
        OneInstall.NativeUI.Layout(cards,available,scroll.ViewportHeight,scroll.VerticalOffset);
        var row=Find<FrameworkElement>("InstallSearchRow"); if(row!=null) row.Width=available;
    }

    static void UpdateSelection() {
        var result=(Dictionary<string,object>)json.DeserializeObject(Engine.Plan(json.Serialize(selected)));
        var count=Find<TextBlock>("SelectedCount"); if(count!=null) count.Text=(string)result["Count"];
        var install=Find<Button>("Install"); if(install!=null) install.IsEnabled=selected.Count>0;
        var save=Find<Button>("SaveSetup"); if(save!=null) save.IsEnabled=selected.Count>0;
        var queue=Find<Panel>("QueuePanel"); queue.Children.Clear();
        if(selected.Count==0) {
            var hint=Label("Your next setup starts here. Select apps from the library.",13,true); hint.Margin=new Thickness(0,15,0,0); queue.Children.Add(hint);
        }
        foreach(Dictionary<string,object> row in (IEnumerable)result["Rows"]) {
            string key=(string)row["Key"], name=(string)row["Name"];
            var panel=new StackPanel { Margin=new Thickness(0,8,0,9), Tag=key };
            var grid=new Grid(); grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width=GridLength.Auto });
            var title=Label(name,13,false); title.FontWeight=FontWeights.SemiBold; title.Margin=new Thickness(0,0,8,0); title.VerticalAlignment=VerticalAlignment.Center;
            grid.Children.Add(title);
            var remove=new Button { Content="×", Tag=key, Width=32, MinHeight=32, Padding=new Thickness(0), Margin=new Thickness(0), FontSize=18, Background=Brushes.Transparent, BorderThickness=new Thickness(0) };
            AutomationProperties.SetName(remove,"Remove "+name+" from selection");
            remove.Click+=delegate(object sender,RoutedEventArgs e) { checks[(string)((Button)sender).Tag].IsChecked=false; };
            Grid.SetColumn(remove,1); grid.Children.Add(remove); panel.Children.Add(grid);
            var method=Label((string)row["Method"],12,true); method.Margin=new Thickness(0,4,0,0); panel.Children.Add(method);
            queue.Children.Add(panel);
        }
        var status=Find<TextBlock>("Status");
        if(status!=null) status.Text=result["Error"] as string ?? (selected.Count==0?"":"Selection updated. Review before installing.");
    }

    static void Toggle(object sender,RoutedEventArgs e) {
        if(syncing) return;
        var check=(CheckBox)sender; string key=(string)check.Tag;
        if(check.IsChecked==true) { if(!selected.Contains(key)) selected.Add(key); } else selected.Remove(key);
        UpdateSelection();
    }

    static void Filter(string query) {
        string[] words=query.ToLowerInvariant().Split(new[]{' '},StringSplitOptions.RemoveEmptyEntries);
        int shown=0;
        foreach(var pair in checks) {
            string text=texts[pair.Key].ToLowerInvariant(); bool match=true;
            foreach(string word in words) if(!text.Contains(word)) { match=false; break; }
            pair.Value.Visibility=match?Visibility.Visible:Visibility.Collapsed; if(match) shown++;
        }
        Show("Empty",shown==0);
        var scroll=Find<ScrollViewer>("LibraryScroll"); scroll.ScrollToTop();
        OneInstall.NativeUI.Realize(Find<UniformGrid>("Cards"),scroll);
        var placeholder=Find<UIElement>("SearchPlaceholder"); if(placeholder!=null) placeholder.Visibility=query.Length==0?Visibility.Visible:Visibility.Collapsed;
    }

    static void BuildCategories(string catalog) {
        var host=Find<Panel>("Categories"); if(host==null) return;
        var groups=new Dictionary<string,SortedSet<string>>();
        foreach(Dictionary<string,object> app in (IEnumerable)json.DeserializeObject(catalog)) {
            string group=(string)app["CategoryGroup"];
            if(!groups.ContainsKey(group)) groups[group]=new SortedSet<string>(StringComparer.CurrentCultureIgnoreCase);
            groups[group].Add((string)app["Category"]);
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

    [STAThread]
    static int Main(string[] args) {
        bool test=Array.IndexOf(args,"--startup-test")>=0;
        var application=new Application { ShutdownMode=ShutdownMode.OnMainWindowClose };
        window=new OneInstall.MainWindow();
        OneInstall.Motion.Initialize(window);
        Color accent=SystemParameters.WindowGlassColor; accent.A=255;
        OneInstallAppearance.Apply(window,false,true,accent,true,false);
        ApplyAccent(accent);

        string catalog=Engine.Catalog();
        OneInstall.NativeUI.Populate(window,catalog);
        checks=(Dictionary<string,CheckBox>)window.Resources["NativeChecks"];
        texts=(Dictionary<string,string>)window.Resources["NativeSearchTexts"];
        foreach(var check in checks.Values) { check.Checked+=Toggle; check.Unchecked+=Toggle; }
        BuildCategories(catalog);

        // Install mode, as Set-AppMode 'Install' leaves the window.
        Show("InstallLibrary",true); Show("SetupGlass",true); Show("CategoriesHost",true);
        Show("UninstallNavigation",false); Show("UninstallPage",false); Show("RemovalGlass",false);
        var controls=Find<FrameworkElement>("WindowControls"); if(controls!=null) controls.Margin=new Thickness(0,30,30,0);
        var heading=Find<TextBlock>("NavigationHeading"); if(heading!=null) heading.Text="LIBRARY";
        var results=Find<TextBlock>("ResultCount"); if(results!=null) results.Text="All apps · "+checks.Count+" apps";
        var installMode=Find<Control>("InstallMode"); if(installMode!=null) installMode.SetResourceReference(Control.BackgroundProperty,"AccentSurfaceBrush");
        UpdateSelection();
        int select=Array.IndexOf(args,"--select");
        if(select>=0 && select+1<args.Length) foreach(string key in args[select+1].Split(',')) { CheckBox check; if(checks.TryGetValue(key,out check)) check.IsChecked=true; }

        var search=Find<TextBox>("Search"); if(search!=null) search.TextChanged+=delegate { Filter(search.Text); };
        var clear=Find<Button>("ClearSelection");
        if(clear!=null) clear.Click+=delegate { syncing=true; foreach(string key in selected) checks[key].IsChecked=false; syncing=false; selected.Clear(); UpdateSelection(); };
        var minimize=Find<Button>("MinimizeWindow"); if(minimize!=null) minimize.Click+=delegate { window.WindowState=WindowState.Minimized; };
        var maximize=Find<Button>("MaximizeWindow"); if(maximize!=null) maximize.Click+=delegate { window.WindowState=window.WindowState==WindowState.Maximized?WindowState.Normal:WindowState.Maximized; };
        var close=Find<Button>("CloseWindow"); if(close!=null) close.Click+=delegate { window.Close(); };
        var brand=Find<UIElement>("BrandHeader"); if(brand!=null) brand.MouseLeftButtonDown+=delegate { try { window.DragMove(); } catch(InvalidOperationException) { } };
        var scroll=Find<ScrollViewer>("LibraryScroll");
        scroll.ScrollChanged+=delegate(object sender,ScrollChangedEventArgs e) {
            if(e.ViewportWidthChange!=0) UpdateLayout(); else OneInstall.NativeUI.Realize(Find<UniformGrid>("Cards"),scroll);
        };
        window.SourceInitialized+=delegate { FirstInstallWindow.Apply(new WindowInteropHelper(window).Handle,false); };
        window.Loaded+=delegate { UpdateLayout(); };

        if(test) {
            // The same two marks 3.6 reports: content drawn, then the dispatcher idle.
            window.ContentRendered+=delegate {
                ulong render=Engine.oi_clock_ms();
                window.Dispatcher.BeginInvoke(new Action(delegate { Engine.oi_report(render,Engine.oi_clock_ms()); window.Close(); }),DispatcherPriority.ApplicationIdle);
            };
        } else {
            // The slow WinGet inventory runs off the UI thread and arrives later.
            ThreadPool.QueueUserWorkItem(delegate {
                var keys=json.Deserialize<string[]>(Engine.Installed());
                window.Dispatcher.BeginInvoke(new Action(delegate {
                    foreach(string key in keys) {
                        CheckBox check; if(!checks.TryGetValue(key,out check)) continue;
                        var content=check.Content as StackPanel; if(content==null || content.Children.Count<3) continue;
                        var method=content.Children[2] as TextBlock; if(method==null) continue;
                        method.Text="Installed · "+method.Text; method.SetResourceReference(TextBlock.ForegroundProperty,"AccentTextBrush");
                    }
                }));
            });
        }
        return application.Run(window);
    }
}
