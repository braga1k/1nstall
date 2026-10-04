param([string]$PreviewDirectory='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
Add-Type -ReferencedAssemblies System.dll,System.Core.dll,System.Xaml,PresentationFramework,PresentationCore,WindowsBase -TypeDefinition @'
using System;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
public static class OpeningProbe {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    static void Pump(int milliseconds) {
        var frame=new DispatcherFrame(); var timer=new DispatcherTimer { Interval=TimeSpan.FromMilliseconds(milliseconds) };
        timer.Tick+=delegate { timer.Stop(); frame.Continue=false; }; timer.Start(); Dispatcher.PushFrame(frame);
    }
    public static void Check(string path,string preview) {
        var assembly=Assembly.LoadFrom(path);
        var type=assembly.GetType("StartupView",true);
        var field=type.GetField("window",BindingFlags.Instance|BindingFlags.NonPublic);
        var first=type.GetField("FirstFrameMilliseconds");
        var cancelled=type.GetProperty("Cancelled");
        using(var early=(IDisposable)Activator.CreateInstance(type,true)) { }
        Thread.Sleep(100);
        using(var opening=(IDisposable)Activator.CreateInstance(type,true)) {
            var timer=System.Diagnostics.Stopwatch.StartNew();
            while((long)first.GetValue(opening)==0 && timer.ElapsedMilliseconds<8000) Thread.Sleep(20);
            if((long)first.GetValue(opening)==0) throw new Exception("Opening did not paint independently.");
            var window=(Window)field.GetValue(opening);
            if((bool)window.Dispatcher.Invoke(new Func<bool>(delegate { return window.ShowInTaskbar; }))) throw new Exception("Opening must not create a separate taskbar entry.");
            if(!string.IsNullOrEmpty(preview)) {
                Directory.CreateDirectory(preview);
                foreach(int frame in new[]{0,220,550,950,1400}) {
                    if(frame>0) Thread.Sleep(frame==220?220:frame==550?330:frame==950?400:450);
                    window.Dispatcher.Invoke(new Action(delegate {
                        var bitmap=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);
                        bitmap.Render(window); var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                        using(var stream=File.Create(Path.Combine(preview,"startup-"+frame+".png"))) encoder.Save(stream);
                    }));
                }
            }
            window.Dispatcher.Invoke(new Action(delegate {
                if(!window.IsVisible) throw new Exception("Opening was not visible.");
                if(!string.IsNullOrEmpty(preview)) {
                    Directory.CreateDirectory(preview);
                    var bitmap=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);
                    bitmap.Render(window);
                    var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using(var stream=File.Create(Path.Combine(preview,"startup.png"))) encoder.Save(stream);
                }
                window.Close();
            }));
            if(!(bool)cancelled.GetValue(opening)) throw new Exception("Closing the opening did not cancel startup.");
        }
        using(var opening=(IDisposable)Activator.CreateInstance(type,true)) {
            var timer=System.Diagnostics.Stopwatch.StartNew();
            while((long)first.GetValue(opening)==0 && timer.ElapsedMilliseconds<8000) Thread.Sleep(20);
            if((long)first.GetValue(opening)==0) throw new Exception("Second opening did not paint.");
            var window=(Window)field.GetValue(opening);
            opening.Dispose();
            timer.Restart();
            while(!window.Dispatcher.HasShutdownFinished && timer.ElapsedMilliseconds<2000) Thread.Sleep(20);
            if(!window.Dispatcher.HasShutdownFinished || (bool)cancelled.GetValue(opening)) throw new Exception("Ready handoff did not stop its dispatcher cleanly.");
        }
        // Reproduce launching from a folder with a separate foreground opening window.
        // Cover both a foreground main window and one initially behind the opening.
        var folder=new Window { Title="Folder fixture",Width=700,Height=450 };
        try {
            folder.Show(); folder.Activate(); Pump(100);
            foreach(bool activateOnShow in new[]{false,true}) {
                using(var opening=(IDisposable)Activator.CreateInstance(type,true)) {
                    var timer=System.Diagnostics.Stopwatch.StartNew();
                    while((long)first.GetValue(opening)==0 && timer.ElapsedMilliseconds<8000) Pump(20);
                    if((long)first.GetValue(opening)==0) throw new Exception("Handoff opening did not paint.");
                    var splash=(Window)field.GetValue(opening);
                    var main=new Window { Title="1nstall handoff fixture",Width=850,Height=600,ShowActivated=activateOnShow };
                    try {
                        main.Show(); Pump(50);
                        bool closedWithOwner=false;
                        var mainHandle=new WindowInteropHelper(main).Handle;
                        IntPtr splashHandle=IntPtr.Zero;
                        splash.Dispatcher.Invoke(new Action(delegate {
                            splash.Activate(); splashHandle=new WindowInteropHelper(splash).Handle;
                            splash.Closing+=delegate { closedWithOwner=new WindowInteropHelper(splash).Owner==mainHandle; };
                        })); Pump(50);
                        bool ownsForeground=GetForegroundWindow()==splashHandle;
                        if(!ownsForeground) Console.WriteLine("SKIP: desktop foreground assertions; Windows denied activation to the background test runner.");
                        var complete=type.GetMethod("Complete");
                        if(complete==null) opening.Dispose(); else complete.Invoke(opening,new object[]{main});
                        timer.Restart();
                        while((ownsForeground && !main.IsActive || !splash.Dispatcher.HasShutdownFinished) && timer.ElapsedMilliseconds<2000) Pump(20);
                        if(!splash.Dispatcher.HasShutdownFinished || ownsForeground && (GetForegroundWindow()!=new WindowInteropHelper(main).Handle || !main.IsActive)) throw new Exception("Opening left the app behind its launching folder.");
                        if(!closedWithOwner) throw new Exception("Opening closed without its main-window owner; Explorer could take activation.");
                        if(main.Topmost || (bool)cancelled.GetValue(opening)) throw new Exception("Handoff used permanent topmost or cancelled startup.");
                        folder.Activate(); Pump(150);
                        if(ownsForeground && (!folder.IsActive || main.IsActive)) throw new Exception("App reclaimed focus after the handoff.");
                    } finally { main.Close(); }
                }
            }
        } finally { folder.Close(); }
        // Production runs the main window modally; verify ownership in that path too.
        using(var opening=(IDisposable)Activator.CreateInstance(type,true)) {
            var timer=System.Diagnostics.Stopwatch.StartNew();
            while((long)first.GetValue(opening)==0 && timer.ElapsedMilliseconds<8000) Pump(20);
            var splash=(Window)field.GetValue(opening);
            var main=new Window { Title="Modal handoff fixture",Width=850,Height=600,ShowActivated=false,Content=new System.Windows.Controls.Grid() };
            bool owned=false;
            IntPtr handle=IntPtr.Zero;
            splash.Dispatcher.BeginInvoke(new Action(delegate { splash.Closing+=delegate { owned=new WindowInteropHelper(splash).Owner==handle; }; }));
            main.ContentRendered+=delegate {
                try {
                    handle=new WindowInteropHelper(main).Handle;
                    type.GetMethod("Complete").Invoke(opening,new object[]{main}); timer.Restart();
                    while(!splash.Dispatcher.HasShutdownFinished && timer.ElapsedMilliseconds<2000) Pump(20);
                    if(!owned || !splash.Dispatcher.HasShutdownFinished || !main.IsVisible || !main.IsEnabled || main.Topmost)
                        throw new Exception("Modal handoff lost ownership or disabled its main window.");
                } finally { main.Close(); }
            };
            main.ShowDialog();
        }
        Console.WriteLine("PASS: native ownership before close, no separate taskbar entry, modal and modeless main-window handoffs.");
    }
}
'@
[OpeningProbe]::Check((Join-Path (Split-Path $PSScriptRoot) 'dist/1nstall.exe'),$PreviewDirectory)
'PASS: independent startup paint, early disposal, cancellation and handoff dispatcher cleanup. Foreground assertions run only when Windows grants foreground to the fixture; skips are reported above.'
