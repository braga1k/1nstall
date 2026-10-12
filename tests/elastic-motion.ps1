param([string]$OutputDirectory='')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
$ui=Join-Path $repo 'dist/1nstall.UI.dll'
Add-Type -Path $ui
Add-Type -ReferencedAssemblies @('System.dll','System.Core.dll','System.Xaml','WindowsBase','PresentationCore','PresentationFramework','UIAutomationProvider','UIAutomationTypes',$ui) -TypeDefinition @'
using System;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using OneInstall;
public static class ElasticProbe {
    static void Assert(bool condition,string message) { if(!condition) throw new Exception(message); }
    static void Pump(int ms) {
        var frame=new DispatcherFrame(); var timer=new DispatcherTimer { Interval=TimeSpan.FromMilliseconds(ms) };
        timer.Tick+=delegate { timer.Stop(); frame.Continue=false; }; timer.Start(); Dispatcher.PushFrame(frame);
    }
    static void Check(ElasticMotion.Pose[] poses,double target) {
        foreach(var p in poses) Assert(!double.IsNaN(p.X) && p.X>=-3.00001 && p.X+p.Stretch<=19.00001 && p.Stretch>=0 && p.Height>0 && p.Height<=20.0/14,"Shape escaped its ring: "+p.X+" + "+p.Stretch);
        var last=poses[poses.Length-1]; Assert(last.X==target && last.Stretch==0 && last.Height==1,"Flight did not land round");
    }
    static ElasticSwitch Switch(CheckBox c) { return (ElasticSwitch)c.Template.FindName("ElasticSwitch",c); }
    public static void Run(string directory) {
        foreach(var feel in new[] { ElasticFeel.Balanced,ElasticFeel.Firm,ElasticFeel.Elastic }) {
            foreach(double target in new[] { 0.0,16.0 }) {
                var initial=new ElasticMotion.Pose(16-target,0,1);
                var flight=ElasticMotion.Flight(initial,target,feel); Check(flight,target);
                foreach(var pose in flight) {
                    var reversed=ElasticMotion.Flight(pose,16-target,feel); Check(reversed,16-target);
                    Assert(reversed[0].X==pose.X && reversed[0].Stretch==pose.Stretch && reversed[0].Height==pose.Height,"Interrupted flight jumped");
                    foreach(var again in reversed) Check(ElasticMotion.Flight(again,target,feel),target);
                }
            }
        }
        var window=new MainWindow(); var panel=new StackPanel { Margin=new Thickness(24) }; window.Content=panel;
        Motion.Initialize(window); Motion.TestOverride=false;
        var card=NativeUI.Card(window,"fixture","Elastic selection","Test category","Test selection",true); card.ClearValue(Control.TemplateProperty); panel.Children.Add(card);
        var row=new CheckBox { Content="Installed app",Style=(Style)window.Resources["AppSwitch"] }; panel.Children.Add(row);
        window.Show(); Pump(100);
        try {
            var toggle=Switch(card); Assert(toggle!=null && Switch(row)!=null,"Toggle missing after template realization");
            int changed=0,settled=0; string order="";
            toggle.Changed+=delegate { changed++; order+="c"; }; toggle.Settled+=delegate { settled++; order+="s"; };
            var peer=new CheckBoxAutomationPeer(card); var provider=(IToggleProvider)peer.GetPattern(PatternInterface.Toggle);
            provider.Toggle(); Assert(card.IsChecked==true && toggle.CurrentPose.X==16 && settled==1 && order=="cs","Reduced motion or UIA state failed");
            Motion.TestOverride=true; provider.Toggle(); Pump(90); var before=toggle.CurrentPose;
            provider.Toggle(); var after=toggle.CurrentPose;
            Assert(Math.Abs(before.X-after.X)<.001 && Math.Abs(before.Stretch-after.Stretch)<.001,"Live reversal jumped");
            Pump(850); Assert(toggle.CurrentPose.X==16 && toggle.CurrentPose.Stretch==0 && settled==2,"Interrupted callback or final pose wrong");
            var isPressed=typeof(ButtonBase).GetProperty("IsPressed");
            isPressed.SetValue(card,true,null); Pump(180); Assert(toggle.CurrentPose.X<16 && card.IsChecked==true,"Press did not lean or changed selection");
            isPressed.SetValue(card,false,null); Pump(850); Assert(toggle.CurrentPose.X==16 && settled==2,"Aborted press did not return without commit");
            toggle.PressFeedback=false; isPressed.SetValue(card,true,null); Pump(180); Assert(toggle.CurrentPose.X==16,"Disabled press feedback moved"); isPressed.SetValue(card,false,null); Pump(850);
            provider.Toggle(); Pump(70); Motion.TestOverride=false; Motion.Stop(); Assert(toggle.CurrentPose.X==0 && toggle.CurrentPose.Stretch==0 && settled==3 && Motion.ActiveAnimations==0,"Live reduced motion did not settle");
            toggle.PressFeedback=true; Motion.TestOverride=true; provider.Toggle(); Pump(70);
            isPressed.SetValue(card,true,null); Pump(50); isPressed.SetValue(card,false,null); Pump(850);
            Assert(toggle.CurrentPose.X==16 && settled==4,"An aborted press lost a pending state completion");
            provider.Toggle(); Pump(70); isPressed.SetValue(card,true,null); Pump(50);
            Motion.TestOverride=false; Motion.Stop(); Assert(toggle.CurrentPose.X==0 && toggle.CurrentPose.Height==1 && settled==5,"Reduced motion left the press pose active");
            isPressed.SetValue(card,false,null);
            card.Template=new ControlTemplate(typeof(CheckBox)); Pump(50); card.IsChecked=true; card.ClearValue(Control.TemplateProperty); Pump(100);
            Assert(Switch(card).CurrentPose.X==16,"Virtualized selection lost its state");
            row.IsChecked=true; Assert(Switch(row).CurrentPose.X==16,"Uninstall switch did not follow binding state");
            if(!string.IsNullOrEmpty(directory)) {
                Directory.CreateDirectory(directory); window.UpdateLayout();
                var bitmap=new RenderTargetBitmap((int)panel.ActualWidth,(int)panel.ActualHeight,96,96,PixelFormats.Pbgra32); bitmap.Render(panel);
                var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using(var file=File.Create(Path.Combine(directory,"elastic-toggle.png"))) encoder.Save(file);
            }
        } finally { window.Close(); Motion.TestOverride=null; }
    }
}
'@
[ElasticProbe]::Run($OutputDirectory)
'PASS: all presets, track bounds, repeated reversals, native UIA, press/cancel, reduced motion, settle callbacks and virtualization.'
