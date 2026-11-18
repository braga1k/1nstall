// The History & diagnostics page: the operations on record, the diagnostics text to review
// and the licence notices. A port of Show-ManagerPage, Render-History and Show-Diagnostics of
// src/manager-ui.ps1 and of Show-ThirdPartyNotices of vexan_installers.ps1. What the page
// shows comes from the engine (engine/ffi/src/history.rs).
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using OneInstall;

static class History {
    static Window window;
    static Grid page;
    static Button modeButton;
    static TextBlock status;
    static StackPanel list;
    static string logDirectory;

    static T Find<T>(string name) where T:class { return window.FindName(name) as T; }
    static Button NewButton(string text) { var button=new Button(); I18n.Set(button,"Content",text); return button; }

    // Show-ManagerPage
    static void Show() {
        if(Library.Busy || Uninstall.Busy) return;
        Shell.SetMode("Install"); Shell.Mode="History";
        var installMode=Find<Control>("InstallMode"); if(installMode!=null) installMode.Background=Brushes.Transparent;
        modeButton.SetResourceReference(Control.BackgroundProperty,"AccentSurfaceBrush");
        Shell.Show("InstallLibrary",false); Shell.Show("SetupGlass",false); Shell.Show("CategoriesHost",false);
        page.Visibility=Visibility.Visible; page.Children.Clear();
        var dock=new DockPanel(); page.Children.Add(dock);
        var top=new StackPanel(); DockPanel.SetDock(top,Dock.Top); dock.Children.Add(top);
        top.Children.Add(Shell.NewLabel("Operation history",false,27));
        status=Shell.NewLabel("Timestamped results and detailed logs. Retry requires a fresh state check and review.",true,13);
        status.Margin=new Thickness(0,9,0,15); top.Children.Add(status);
        var bar=new WrapPanel(); top.Children.Add(bar);
        var scroll=new ScrollViewer { VerticalScrollBarVisibility=ScrollBarVisibility.Auto }; dock.Children.Add(scroll);
        list=new StackPanel { Margin=new Thickness(0,12,0,0) }; scroll.Content=list;
        // The scroll area carries the id: a plain panel is not visible to UI Automation.
        AutomationProperties.SetAutomationId(scroll,"HistoryList");
        var refresh=NewButton("Refresh history"); refresh.Click+=delegate { Render(); }; bar.Children.Add(refresh);
        var diagnostic=NewButton("Review diagnostic export…"); diagnostic.Click+=delegate { ShowDiagnostics(); }; bar.Children.Add(diagnostic);
        var licenses=NewButton("Licenses & credits"); licenses.Click+=delegate { ShowNotices(); }; bar.Children.Add(licenses);
        Render();
        Motion.Enter(page,0,10,0);
    }

    public static void Hide() { if(page!=null) page.Visibility=Visibility.Collapsed; }

    // Render-History: the engine gives the reason the history could not be read (or nothing),
    // then one record per operation, newest first: its text, the app to review again, its log.
    static void Render() {
        if(Shell.Mode!="History") return;
        list.Children.Clear();
        string[] rows=Engine.History(logDirectory).Split('\u001E');
        if(rows[0].Length>0) I18n.Set(status,"Text",rows[0]);
        if(rows.Length==1) list.Children.Add(Shell.NewLabel("Your operation history will appear here after installation or removal.",true,15));
        for(int index=1;index<rows.Length;index++) {
            string[] fields=rows[index].Split('\u001F'); if(fields.Length!=3) continue;
            var panel=new StackPanel { Margin=new Thickness(0,0,0,18) };
            panel.Children.Add(Shell.NewLabel(fields[0],false,13));
            if(fields[1].Length>0) {
                // A failed install is never repeated blindly: the state is read again, and the
                // app is only selected for a new review if it is still known to be missing.
                var retry=NewButton("Refresh & review installation again"); retry.Tag=fields[1]; retry.HorizontalAlignment=HorizontalAlignment.Left; retry.Margin=new Thickness(0,8,0,0);
                retry.Click+=delegate(object sender,RoutedEventArgs e) { Library.RetryAfterRefresh((string)((Button)sender).Tag); Shell.SetMode("Install"); Library.RefreshInventory(); };
                panel.Children.Add(retry);
            }
            if(fields[2].Length>0) {
                var open=NewButton("Open detailed log"); open.Tag=fields[2]; open.HorizontalAlignment=HorizontalAlignment.Left; open.Margin=new Thickness(0,8,0,0);
                // The engine only names a log that exists inside the log folder; a file path holds no quotes.
                open.Click+=delegate(object sender,RoutedEventArgs e) { Process.Start("notepad.exe","\""+(string)((Button)sender).Tag+"\""); };
                panel.Children.Add(open);
            }
            list.Children.Add(panel);
        }
    }

    // Show-Diagnostics: nothing leaves the machine. The text is shown for review and may be saved.
    static void ShowDiagnostics() {
        var info=Library.NewInfoDialog("Review diagnostics",Engine.Diagnostics(Environment.OSVersion.Version.ToString())+"\r\n\r\nNo raw logs, app data or credentials are included. Review the text for anything personal before saving or sharing. Nothing is sent automatically.");
        AutomationProperties.SetAutomationId(info.Text,"DiagnosticsText");
        var save=NewButton("Save reviewed diagnostics…"); save.Tag=info.Text.Text;
        save.Click+=delegate(object sender,RoutedEventArgs e) {
            var dialog=new SaveFileDialog { Filter="Text (*.txt)|*.txt", FileName="1nstall-diagnostics.txt" };
            if(dialog.ShowDialog(window)==true) File.WriteAllText(dialog.FileName,(string)((Button)sender).Tag,Encoding.UTF8);
        };
        DockPanel.SetDock(save,Dock.Bottom); info.Dock.Children.Insert(1,save);
        info.Window.ShowDialog();
    }

    // Show-ThirdPartyNotices
    static void ShowNotices() {
        var info=Library.NewInfoDialog("Licenses & credits",Engine.Notices());
        AutomationProperties.SetAutomationId(info.Text,"NoticesText");
        info.Window.ShowDialog();
    }

    // The page shares the content columns with the library, and its button follows Install
    // and Uninstall. 3.6 creates both in code as well.
    public static void Initialize(Window target,string logs) {
        window=target; logDirectory=logs;
        page=new Grid { Margin=new Thickness(18,18,14,18), Visibility=Visibility.Collapsed };
        Grid.SetColumn(page,1); Grid.SetColumnSpan(page,2);
        ((Panel)Find<FrameworkElement>("InstallLibrary").Parent).Children.Add(page);
        modeButton=NewButton("History & diagnostics"); modeButton.FontSize=12; modeButton.Padding=new Thickness(8,7,8,7); modeButton.Margin=new Thickness(0,0,0,5);
        // Registered under the name the rest of the application looks it up by.
        window.RegisterName("HistoryMode",modeButton);
        AutomationProperties.SetAutomationId(modeButton,"HistoryMode");
        modeButton.Click+=delegate { Show(); };
        ((Panel)Find<Button>("InstallMode").Parent).Children.Add(modeButton);
    }
}
