param([string]$PreviewDirectory='')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
[Reflection.Assembly]::LoadFrom((Join-Path $repo 'dist/1nstall.exe')) | Out-Null
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
Add-Type -ReferencedAssemblies @('System.dll','System.Core.dll','System.Xaml','WindowsBase','PresentationCore','PresentationFramework') -TypeDefinition @'
using System;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
public static class AppearanceProbe {
    public static Assembly App;
    static RenderTargetBitmap Render(Window window,bool backgroundOnly) {
        var root=(Grid)window.Content; var ambient=(Grid)window.FindName("AmbientLight");
        var saved=new Visibility[root.Children.Count];
        for(int i=0;i<saved.Length;i++) {
            saved[i]=root.Children[i].Visibility;
            if(backgroundOnly && root.Children[i]!=ambient) root.Children[i].Visibility=Visibility.Hidden;
        }
        window.UpdateLayout();
        var image=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32); image.Render(root);
        for(int i=0;i<saved.Length;i++) root.Children[i].Visibility=saved[i];
        image.Freeze(); return image;
    }
    static void Save(BitmapSource image,string path) {
        var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image));
        using(var stream=File.Create(path)) encoder.Save(stream);
    }
    public static void Match(Window main,bool light,bool accent,Color color,bool effects,string directory) {
        var preferenceType=App.GetType("OneInstallAppearance+Preferences",true);
        var preferences=Activator.CreateInstance(preferenceType);
        preferenceType.GetField("Light").SetValue(preferences,light); preferenceType.GetField("Accent").SetValue(preferences,accent);
        preferenceType.GetField("Color").SetValue(preferences,color); preferenceType.GetField("Effects").SetValue(preferences,effects);
        var type=App.GetType("StartupView",true);
        var first=type.GetField("FirstFrameMilliseconds");
        using(var opening=(IDisposable)Activator.CreateInstance(type,new object[]{preferences})) {
            var time=System.Diagnostics.Stopwatch.StartNew();
            while((long)first.GetValue(opening)==0 && time.ElapsedMilliseconds<8000) Thread.Sleep(20);
            if((long)first.GetValue(opening)==0) throw new Exception("Opening did not render.");
            var window=(Window)type.GetField("window",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(opening);
            RenderTargetBitmap actual=null,preview=null;
            double width=main.ActualWidth,height=main.ActualHeight;
            window.Dispatcher.Invoke(new Action(delegate {
                if(window.ActualWidth!=width || window.ActualHeight!=height) throw new Exception("Opening size differs from the main UI.");
                actual=Render(window,true); preview=Render(window,false);
            }));
            var expected=Render(main,true);
            int stride=expected.PixelWidth*4; var a=new byte[stride*expected.PixelHeight]; var b=new byte[a.Length];
            actual.CopyPixels(a,stride,0); expected.CopyPixels(b,stride,0);
            int maximum=0; for(int i=0;i<a.Length;i++) maximum=Math.Max(maximum,Math.Abs(a[i]-b[i]));
            string name=(light?"light":"dark")+(accent?"-accent":"-monochrome")+(effects?"":"-opaque");
            if(!string.IsNullOrEmpty(directory)) {
                Directory.CreateDirectory(directory); Save(preview,Path.Combine(directory,name+"-opening.png"));
                Save(Render(main,false),Path.Combine(directory,name+"-app.png"));
            }
            if(maximum!=0) throw new Exception(name+" background differs by "+maximum+" channel levels.");
            Console.WriteLine("PASS: "+name+" opening and main canvas are pixel-identical.");
        }
    }
}
'@
[AppearanceProbe]::App=[Reflection.Assembly]::LoadFrom((Join-Path $repo 'dist/1nstall.exe'))
$probe={
    $window.Add_ContentRendered({
        function Paint {
            $frame=New-Object Windows.Threading.DispatcherFrame; $timer=New-Object Windows.Threading.DispatcherTimer
            $timer.Interval=[TimeSpan]::FromMilliseconds(150)
            $timer.Add_Tick({ $timer.Stop(); $frame.Continue=$false }); $timer.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame)
        }
        try {
            [OneInstall.Motion]::TestOverride=$false; [OneInstall.Motion]::Stop(); $accentTimer.Stop()
            $read=[OneInstallAppearance]::Read(); $script:settings.Theme=if ($read.Light) { 'Light' } else { 'Dark' }; $script:settings.WindowsAccent=$read.Accent
            if ($read.Color -ne (Get-WindowsAccent)) { throw 'Opening reads a different Windows accent from the main UI.' }
            $window.Width=1240; $window.Height=[Math]::Min(840,[Windows.SystemParameters]::WorkArea.Height-24)
            foreach ($light in @($false,$true)) {
                foreach ($accent in @($false,$true)) {
                    $script:settings.Theme=if ($light) { 'Light' } else { 'Dark' }; $script:settings.WindowsAccent=$accent; $script:lastAccent=''; Update-WindowsAccent
                    Paint; [AppearanceProbe]::Match($window,$light,$accent,(Get-WindowsAccent),$script:lastGlass,$PreviewDirectory)
                    Set-GlassAppearance $false; Paint
                    [AppearanceProbe]::Match($window,$light,$accent,(Get-WindowsAccent),$false,$PreviewDirectory)
                }
            }
        } finally { $window.Close() }
    })
}
$source=[IO.File]::ReadAllText((Join-Path $repo 'vexan_installers.ps1')).Replace('@@MANAGER_TEST@@',$probe.ToString())
. ([scriptblock]::Create($source)) -ResourceRoot $repo -ManagerTest
