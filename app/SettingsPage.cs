// The Settings page and the update check: Initialize-AppSettings, Show-AppSettings,
// Add-SettingsRow, New-SettingsChoice and Start-AppUpdateCheck of src/settings.ps1.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Threading;

static class SettingsPage {
    static Window window;
    static ScrollViewer page;
    static StackPanel content;
    static Button settingsButton, applyUpdate;
    static TextBlock status;
    static string updateStatus="Updates are checked in the background.";
    static Task<OneInstallRelease> updateTask;
    static OneInstallRelease pendingRelease;
    static bool restartAfterUpdate;
    static DispatcherTimer updateTimer;
    static readonly string dataRoot=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"1nstall");

    public static FrameworkElement Page { get { return page; } }
    static T Find<T>(string name) where T:class { return window.FindName(name) as T; }
    static void SetStatus(string text) { updateStatus=text; if(status!=null) I18n.Set(status,"Text",text); }

    static void Save() {
        if(!Preferences.Save() && status!=null) I18n.Set(status,"Text","Could not save settings. Check folder permissions.");
    }

    // Start-AppUpdateCheck
    static void StartUpdateCheck() {
        if(Preferences.Test || updateTask!=null) return;
        SetStatus("Checking for updates…");
        updateTask=OneInstallUpdate.CheckAsync(Program.Version,Path.Combine(dataRoot,"Updates"),true);
        updateTimer.Start();
    }

    // Add-SettingsRow
    static void AddRow(Panel panel,string title,string description,FrameworkElement control) {
        var surface=new Border { CornerRadius=new CornerRadius(16), Padding=new Thickness(18), Margin=new Thickness(0,0,0,12), BorderThickness=new Thickness(1) };
        surface.SetResourceReference(Border.BackgroundProperty,"ContentFill");
        surface.SetResourceReference(Border.BorderBrushProperty,"CardEdge");
        var layers=new Grid(); surface.Child=layers;
        var light=new Border { CornerRadius=new CornerRadius(15), Margin=new Thickness(-17), IsHitTestVisible=false, Opacity=0 };
        light.Background=(Brush)XamlReader.Parse("<RadialGradientBrush xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" Center=\"0.3,0.2\" GradientOrigin=\"0.3,0.2\" RadiusX=\"0.85\" RadiusY=\"1.3\"><GradientStop Color=\"{DynamicResource CardLightColor}\" Offset=\"0\"/><GradientStop Color=\"#00FFFFFF\" Offset=\"1\"/></RadialGradientBrush>");
        layers.Children.Add(light);
        var stack=new StackPanel(); layers.Children.Add(stack);
        surface.MouseEnter+=delegate { light.SetResourceReference(UIElement.OpacityProperty,"GlassHighlightsOpacity"); };
        surface.MouseLeave+=delegate { light.Opacity=0; };
        surface.MouseMove+=delegate(object sender,MouseEventArgs e) { if(Theme.Glass && OneInstall.Motion.Enabled) Theme.MoveGlassLight(light,e.GetPosition(light)); };
        var label=Shell.NewLabel(title,false,16); label.FontWeight=FontWeights.SemiBold; stack.Children.Add(label);
        AutomationProperties.SetLabeledBy(control,label);
        if(!String.IsNullOrEmpty(description)) { var detail=Shell.NewLabel(description,true,12); detail.Margin=new Thickness(0,5,0,12); stack.Children.Add(detail); }
        control.HorizontalAlignment=HorizontalAlignment.Left; stack.Children.Add(control);
        panel.Children.Add(surface);
    }

    // New-SettingsChoice: options are value and label, in pairs.
    static ComboBox NewChoice(IList<string[]> options,string selected) {
        var combo=new ComboBox { MinWidth=190, MinHeight=38 };
        foreach(string[] entry in options) {
            var item=new ComboBoxItem { Tag=entry[0] }; I18n.Set(item,"Content",entry[1]);
            combo.Items.Add(item);
            if(entry[0]==selected) combo.SelectedItem=item;
        }
        return combo;
    }

    static Button NewButton(string text) {
        var button=new Button(); I18n.Set(button,"Content",text); Theme.EnableHoverMotion(button);
        return button;
    }

    // Show-AppSettings
    static void Show() {
        Shell.SetMode("Install"); Shell.Mode="Settings";
        Shell.Show("InstallLibrary",false); Shell.Show("SetupGlass",false); Shell.Show("CategoriesHost",false);
        page.Visibility=Visibility.Visible;
        var installMode=Find<Control>("InstallMode"); if(installMode!=null) installMode.Background=Brushes.Transparent;
        settingsButton.SetResourceReference(Control.BackgroundProperty,"AccentSurfaceBrush");
        content.Children.Clear();
        var title=Shell.NewLabel("Settings",false,27); title.Margin=new Thickness(0,0,0,22); content.Children.Add(title);

        var theme=NewChoice(new[]{ new[]{"System","Use system setting"}, new[]{"Light","Light"}, new[]{"Dark","Dark"} },Preferences.Theme);
        AutomationProperties.SetAutomationId(theme,"ThemeChoice");
        theme.SelectionChanged+=delegate {
            var item=theme.SelectedItem as ComboBoxItem; if(item==null) return;
            Preferences.Theme=(string)item.Tag; Save(); Theme.Update();
        };
        AddRow(content,"Theme","Choose the appearance of 1nstall.",theme);

        var accent=new CheckBox { Style=(Style)window.Resources["InstalledCheck"], IsChecked=Preferences.WindowsAccent };
        I18n.Set(accent,"Content","Use Windows accent colour");
        AutomationProperties.SetAutomationId(accent,"AccentChoice");
        // 3.6 listens for a click on these two switches. The toggle action of UI Automation,
        // which some assistive tools use, raises no click: the switch changed on screen and
        // nothing was saved. Listening for the change itself covers pointer, keyboard and tools.
        RoutedEventHandler accentChanged=delegate { Preferences.WindowsAccent=accent.IsChecked==true; Save(); Theme.ForgetAccent(); Theme.Update(); };
        accent.Checked+=accentChanged; accent.Unchecked+=accentChanged;
        AddRow(content,"Accent colour","Turn off for black and white, keeping gradients and depth.",accent);

        var options=new List<string[]> { new[]{"System","Use system setting"} };
        var languages=new List<string[]>();
        foreach(string record in Engine.Languages().Split('\u001E')) { string[] fields=record.Split('\u001F'); if(fields.Length==3) languages.Add(new[]{fields[0],fields[1]}); }
        languages.Sort(delegate(string[] a,string[] b) { return StringComparer.CurrentCultureIgnoreCase.Compare(a[1],b[1]); });
        options.AddRange(languages);
        var language=NewChoice(options,Preferences.Language);
        AutomationProperties.SetAutomationId(language,"LanguageChoice");
        language.SelectionChanged+=delegate {
            var item=language.SelectedItem as ComboBoxItem; if(item==null) return;
            Preferences.Language=(string)item.Tag; Save(); Shell.ApplyLanguage();
        };
        AddRow(content,"Language","Changes apply immediately.",language);

        var updates=new StackPanel();
        var automatic=new CheckBox { Style=(Style)window.Resources["InstalledCheck"], IsChecked=Preferences.AutoUpdate };
        I18n.Set(automatic,"Content","Automatic updates");
        AutomationProperties.SetAutomationId(automatic,"AutoUpdateChoice");
        RoutedEventHandler automaticChanged=delegate { Preferences.AutoUpdate=automatic.IsChecked==true; Save(); if(automatic.IsChecked==true) StartUpdateCheck(); };
        automatic.Checked+=automaticChanged; automatic.Unchecked+=automaticChanged;
        updates.Children.Add(automatic);
        status=Shell.NewLabel(updateStatus,true,12); status.Margin=new Thickness(0,10,0,10); updates.Children.Add(status);
        var bar=new WrapPanel();
        var check=NewButton("Check now"); check.Click+=delegate { StartUpdateCheck(); }; bar.Children.Add(check);
        applyUpdate=NewButton("Restart and update"); applyUpdate.IsEnabled=pendingRelease!=null;
        applyUpdate.Click+=delegate { if(pendingRelease!=null) { restartAfterUpdate=true; window.Close(); } };
        bar.Children.Add(applyUpdate); updates.Children.Add(bar);
        AddRow(content,"1nstall updates","New versions download in the background and are applied when you close the app.",updates);

        var about=new WrapPanel();
        foreach(string[] spec in new[]{ new[]{"GitHub","https://github.com/braga1k/1nstall"}, new[]{"Report a problem","https://github.com/braga1k/1nstall/issues"} }) {
            var button=NewButton(spec[0]); button.Tag=spec[1];
            button.Click+=delegate(object sender,RoutedEventArgs e) { Process.Start((string)((Button)sender).Tag); };
            about.Children.Add(button);
        }
        AddRow(content,"About","1nstall "+Program.Version,about);
        int index=0;
        foreach(FrameworkElement row in content.Children) { OneInstall.Motion.Enter(row,0,9,Math.Min(140,index*28)); index++; }
    }

    public static void Hide() {
        if(page==null) return;
        page.Visibility=Visibility.Collapsed; settingsButton.Background=Brushes.Transparent;
    }

    // Initialize-AppSettings, without its last step (applying the language), which the caller
    // runs once the whole window exists.
    public static void Initialize(Window target) {
        window=target;
        if(!Preferences.Test && File.Exists(Path.Combine(dataRoot,"update-error.log"))) updateStatus="The previous update could not be applied. Move 1nstall to a writable folder and try again.";
        page=new ScrollViewer { Visibility=Visibility.Collapsed, VerticalScrollBarVisibility=ScrollBarVisibility.Auto, Margin=new Thickness(18,32,18,18) };
        Grid.SetColumn(page,1); Grid.SetColumnSpan(page,2);
        content=new StackPanel { MaxWidth=780, HorizontalAlignment=HorizontalAlignment.Stretch, Margin=new Thickness(0,0,14,0) };
        page.Content=content; ((Panel)Find<FrameworkElement>("InstallLibrary").Parent).Children.Add(page);
        settingsButton=new Button { Padding=new Thickness(8,7,8,7), Margin=new Thickness(0,8,0,0), FontSize=12 };
        I18n.Set(settingsButton,"Content","Settings");
        AutomationProperties.SetName(settingsButton,"Settings");
        settingsButton.Click+=delegate { Show(); };
        Theme.EnableHoverMotion(settingsButton);
        var donate=Find<Button>("Donate"); var dock=(Panel)donate.Parent; int position=dock.Children.IndexOf(donate); dock.Children.Remove(donate);
        var footer=new StackPanel(); DockPanel.SetDock(footer,Dock.Bottom);
        footer.Children.Add(settingsButton); footer.Children.Add(donate); dock.Children.Insert(position,footer);
        foreach(string name in new[]{"InstallMode","UninstallMode","HistoryMode"}) { var button=Find<Button>(name); if(button!=null) button.Click+=delegate { Hide(); }; }

        updateTimer=new DispatcherTimer { Interval=TimeSpan.FromSeconds(1) };
        updateTimer.Tick+=delegate {
            if(updateTask==null || !updateTask.IsCompleted) return;
            OneInstallRelease result;
            try { result=updateTask.GetAwaiter().GetResult(); }
            catch(Exception error) { result=new OneInstallRelease { Error=error.Message }; }
            updateTask=null; updateTimer.Stop();
            if(result.Error!=null) SetStatus("Could not check or download the update. Try again later.");
            else if(result.Path!=null) { pendingRelease=result; SetStatus("Update ready. It will be applied when you close 1nstall."); }
            else SetStatus("1nstall is up to date.");
            if(applyUpdate!=null) applyUpdate.IsEnabled=pendingRelease!=null;
        };
        window.ContentRendered+=delegate { if(Preferences.AutoUpdate && !Preferences.Test) StartUpdateCheck(); };
        window.Closed+=delegate {
            updateTimer.Stop();
            if(pendingRelease==null || !(Preferences.AutoUpdate || restartAfterUpdate) || Preferences.Test) return;
            try { OneInstallUpdate.Schedule(pendingRelease,Assembly.GetExecutingAssembly().Location,restartAfterUpdate); }
            catch(Exception error) { try { File.WriteAllText(Path.Combine(dataRoot,"update-error.log"),error.Message); } catch(IOException) { } catch(UnauthorizedAccessException) { } }
        };
    }
}
