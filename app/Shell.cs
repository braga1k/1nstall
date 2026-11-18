// The main window: the compiled 3.6 interface, started and wired in C# over the Rust engine.
//
// The pages are in their own files: the install library (Library.cs), the install queue
// (Queue.cs), the Uninstall pages (Uninstall.cs), history and diagnostics (History.cs),
// appearance (Theme.cs), languages (I18n.cs) and the Settings page (SettingsPage.cs).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using OneInstall;

// What the worker thread reads from the engine while WPF starts.
sealed class StartupData {
    public CatalogCard[] Cards;
    public string Settings, Language, View;
}

static class Shell {
    static Window window;
    static string logDirectory, logPath;
    // "Install", "Uninstall", "History" or "Settings".
    public static string Mode="Install";

    static T Find<T>(string name) where T:class { return window.FindName(name) as T; }
    public static void Show(string name,bool visible) { var element=Find<UIElement>(name); if(element!=null) element.Visibility=visible?Visibility.Visible:Visibility.Collapsed; }
    public static void SetText(string name,string text) { var element=Find<TextBlock>(name); if(element!=null) I18n.Set(element,"Text",text); }

    // New-Label: a translated label in the primary or secondary text colour.
    public static TextBlock NewLabel(string text,bool secondary,double size) {
        var label=new TextBlock { FontSize=size, TextWrapping=TextWrapping.Wrap };
        I18n.Set(label,"Text",text);
        label.SetResourceReference(TextBlock.ForegroundProperty,secondary?"TextSecondaryBrush":"TextPrimaryBrush");
        label.FontFamily=size>=20?(FontFamily)window.Resources["HeadingFont"]:window.FontFamily;
        return label;
    }

    // Add-Log: the activity box, and this session's log file.
    public static void AddLog(string message) {
        string line="["+DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")+"] "+message;
        var box=Find<TextBox>("LogBox");
        if(box!=null) { box.AppendText(line+"\r\n"); box.ScrollToEnd(); }
        try { File.AppendAllText(logPath,line+"\r\n",new UTF8Encoding(true)); }
        catch(IOException) { SetText("Status","Could not save the log to disk."); }
        catch(UnauthorizedAccessException) { SetText("Status","Could not save the log to disk."); }
    }

    // Set-AppMode: the Install library or the Uninstall page.
    public static void SetMode(string mode) {
        if(Library.Busy || Uninstall.Busy) return;
        SettingsPage.Hide(); History.Hide();
        bool changed=Mode!=mode;
        if(changed) Motion.ClearDecorations();
        Mode=mode; bool uninstall=mode=="Uninstall";
        Show("InstallLibrary",!uninstall); Show("SetupGlass",!uninstall); Show("CategoriesHost",!uninstall);
        Show("UninstallNavigation",uninstall); Show("UninstallPage",uninstall);
        var controls=Find<FrameworkElement>("WindowControls"); if(controls!=null) controls.Margin=new Thickness(0,30,30,0);
        SetText("NavigationHeading",uninstall?"THIS PC":"LIBRARY");
        foreach(string name in new[]{"InstallMode","UninstallMode","HistoryMode"}) {
            var button=Find<Control>(name); if(button==null) continue;
            if(name==mode+"Mode") button.SetResourceReference(Control.BackgroundProperty,"AccentSurfaceBrush"); else button.Background=Brushes.Transparent;
        }
        if(uninstall) Uninstall.Shown(); else Library.UpdateFilter(true);
        if(changed && window.IsVisible) {
            Motion.Enter(Find<FrameworkElement>(uninstall?"UninstallPage":"InstallLibrary"),0,10,0);
            if(!uninstall) Motion.Enter(Find<FrameworkElement>("SetupGlass"),10,0,40);
        }
    }

    // An internal failure of the engine ends the action that asked, not the application: it is
    // logged and shown once. Any other unhandled error still closes the application with a message.
    static bool reporting;
    static void EngineFailed(object sender,DispatcherUnhandledExceptionEventArgs e) {
        if(!(e.Exception is EngineException)) return;
        e.Handled=true;
        AddLog("Internal error: "+e.Exception.Message);
        if(reporting) return;
        reporting=true;
        try { MessageBox.Show(window,"1nstall could not finish that action because of an internal error. Nothing else was stopped.\n\n"+e.Exception.Message+"\n\nThe details are in this session's log (Open logs).","1nstall",MessageBoxButton.OK,MessageBoxImage.Error); }
        finally { reporting=false; }
    }

    // Apply-AppLanguage: ask the engine for the language, then re-translate the window in place.
    public static void ApplyLanguage() {
        I18n.Load(Engine.Language(Preferences.Language,I18n.UiCulture));
        TranslateWindow();
    }
    static void TranslateWindow() {
        var cards=new List<FrameworkElement>();
        foreach(var check in Library.Checks) cards.Add(check);
        I18n.Apply(window,cards,SettingsPage.Page);
        Library.UpdateLayout();
    }

    public static void Run(string mode,StartupTimer clock,StringBuilder output,Task<StartupData> loading) {
        bool test=mode.Length>0, startupTest=mode=="--startup-test";
        var application=new Application { ShutdownMode=ShutdownMode.OnMainWindowClose };
        application.DispatcherUnhandledException+=EngineFailed;
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

        // Test modes keep their logs beside the executable; a normal start uses the user's profile.
        logDirectory=test?System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"test-logs"):System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"1nstall","Logs");
        try { Directory.CreateDirectory(logDirectory); } catch(IOException) { } catch(UnauthorizedAccessException) { }
        logPath=System.IO.Path.Combine(logDirectory,"session-"+DateTime.Now.ToString("yyyyMMdd-HHmmss")+"-"+Process.GetCurrentProcess().Id+".log");

        // The interface test mode leaves the WinGet inventory to its Refresh button.
        Library.Initialize(window,data.Cards,data.View,mode!="--ui-test",logDirectory);
        Program.Mark("library");

        var minimize=Find<Button>("MinimizeWindow"); if(minimize!=null) minimize.Click+=delegate { window.WindowState=WindowState.Minimized; };
        var maximize=Find<Button>("MaximizeWindow");
        if(maximize!=null) maximize.Click+=delegate { window.WindowState=window.WindowState==WindowState.Maximized?WindowState.Normal:WindowState.Maximized; };
        var close=Find<Button>("CloseWindow"); if(close!=null) close.Click+=delegate { window.Close(); };
        var brand=Find<UIElement>("BrandHeader");
        if(brand!=null) brand.MouseLeftButtonDown+=delegate(object sender,MouseButtonEventArgs e) {
            if(e.ClickCount==2) window.WindowState=window.WindowState==WindowState.Maximized?WindowState.Normal:WindowState.Maximized;
            else { try { window.DragMove(); } catch(InvalidOperationException) { } }
            e.Handled=true;
        };
        window.StateChanged+=delegate {
            bool maximized=window.WindowState==WindowState.Maximized;
            if(maximize!=null) { I18n.Set(maximize,"ToolTip",maximized?"Restore":"Maximize"); AutomationProperties.SetName(maximize,(string)maximize.ToolTip); }
            var glyph=Find<System.Windows.Shapes.Path>("MaximizeGlyph");
            if(glyph!=null) glyph.Data=Geometry.Parse(maximized?"M 2,0 L 10,0 10,8 M 0,2 L 8,2 8,10 0,10 Z":"M 0,0 L 10,0 10,10 0,10 Z");
        };
        // Ctrl+F goes to the search box.
        window.PreviewKeyDown+=delegate(object sender,KeyEventArgs e) {
            if(e.Key!=Key.F || (Keyboard.Modifiers & ModifierKeys.Control)==0) return;
            var search=Find<TextBox>(Mode=="Uninstall"?"InstalledSearch":"Search"); if(search==null) return;
            search.Focus(); search.SelectAll(); e.Handled=true;
        };
        var donate=Find<Button>("Donate"); if(donate!=null) donate.Click+=delegate { Process.Start("https://ko-fi.com/braga1k"); };
        var openLogs=Find<Button>("OpenLogs"); if(openLogs!=null) openLogs.Click+=delegate { Process.Start("explorer.exe","\""+logDirectory+"\""); };
        var installMode=Find<Button>("InstallMode"); if(installMode!=null) installMode.Click+=delegate { SetMode("Install"); };
        var uninstallMode=Find<Button>("UninstallMode"); if(uninstallMode!=null) uninstallMode.Click+=delegate { SetMode("Uninstall"); };
        // Test modes keep registry backups beside the executable too.
        Uninstall.Initialize(window,logPath,test?System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"test-data","Backups"):System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"1nstall","Backups"));
        History.Initialize(window,logDirectory);
        if(mode=="--ui-test") {
            // Only in the interface test mode: an invisible button that makes the engine fail on purpose.
            var failure=new Button { Width=1, Height=1, MinHeight=1, Opacity=0, Focusable=false, IsTabStop=false, Margin=new Thickness(0), Padding=new Thickness(0) };
            AutomationProperties.SetAutomationId(failure,"TestFailure");
            failure.Click+=delegate { Engine.TestFailure(); };
            ((Panel)installMode.Parent).Children.Add(failure);
        }
        // The named buttons of the window follow the pointer with a light, as in 3.6.
        foreach(string name in new[]{"ClearSearch","UserProfiles","Profiles","ClearSelection","SaveSetup","Install","Cancel","OpenLogs","MinimizeWindow","MaximizeWindow","CloseWindow","InstallMode","UninstallMode","RefreshInstalled","WindowsAppsSettings","ClearUninstallSelection","CheckLeftovers","OpenUninstallBackups","ReviewUninstall","StopUninstall","Donate"}) {
            var button=Find<Button>(name); if(button!=null) Theme.EnableHoverMotion(button);
        }
        window.Loaded+=delegate { Motion.Opening(window); };

        SettingsPage.Initialize(window);
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
