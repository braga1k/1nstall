using System;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows.Shell;

// A small independent dispatcher paints while the main thread prepares WPF and PowerShell.
// There is no minimum display time, fake percentage, or second process.
internal sealed class StartupView : IDisposable {
    readonly Thread thread;
    volatile Dispatcher dispatcher;
    volatile bool finished;
    volatile bool cancelled;
    Window window;
    readonly OneInstallAppearance.Preferences appearance;
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr handle);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    public bool Cancelled { get { return cancelled; } }
    public long FirstFrameMilliseconds;
    readonly DateTime started=System.Diagnostics.Process.GetCurrentProcess().StartTime.ToUniversalTime();
    public StartupView() : this(null) { }
    public StartupView(OneInstallAppearance.Preferences preferences) {
        appearance=preferences;
        thread=new Thread(Show) { IsBackground=true,Name="1nstall opening" };
        thread.SetApartmentState(ApartmentState.STA); thread.Start();
    }
    void Show() {
        try {
            dispatcher=Dispatcher.CurrentDispatcher;
            if(finished) return;
            var preferences=appearance ?? OneInstallAppearance.Read();
            bool light=preferences.Light;
            Brush foreground=SystemParameters.HighContrast?SystemColors.WindowTextBrush:new SolidColorBrush((Color)ColorConverter.ConvertFromString(light?"#1A1D25":"#F3F5F7"));
            if(!preferences.Accent && !SystemParameters.HighContrast) foreground=light?Brushes.Black:Brushes.White;
            var root=new Grid { ClipToBounds=true };
            root.SetResourceReference(Panel.BackgroundProperty,"WindowFill");
            var ambient=new Grid { IsHitTestVisible=false,ClipToBounds=true }; root.Children.Add(ambient);
            var glow=new Ellipse { Width=580,Height=580,IsHitTestVisible=false,Opacity=.48 };
            glow.Fill=new RadialGradientBrush(light?Color.FromArgb(38,0,0,0):Color.FromArgb(35,255,255,255),Colors.Transparent);
            if(!SystemParameters.HighContrast) root.Children.Add(glow);
            window=new Window { Title="1nstall",Width=1240,Height=Math.Min(840,SystemParameters.WorkArea.Height-24),MinWidth=1040,MinHeight=540,
                WindowStyle=WindowStyle.None,ResizeMode=ResizeMode.NoResize,ShowInTaskbar=false,UseLayoutRounding=true,WindowStartupLocation=WindowStartupLocation.CenterScreen,Content=root,Background=Brushes.Transparent };
            NameScope.SetNameScope(window,new NameScope()); window.RegisterName("AmbientLight",ambient);
            var chrome=new WindowChrome { CaptionHeight=12,ResizeBorderThickness=new Thickness(0),GlassFrameThickness=new Thickness(0),UseAeroCaptionButtons=false,NonClientFrameEdges=NonClientFrameEdges.None };
            WindowChrome.SetWindowChrome(window,chrome);
            var native=Launcher.WindowHelper();
            OneInstallAppearance.Apply(window,light,preferences.Accent,preferences.Color,preferences.Effects,false);
            window.SourceInitialized+=delegate {
                var handle=new WindowInteropHelper(window).Handle;
                bool acrylic=preferences.Effects && (int)native.GetMethod("SetBackdrop").Invoke(null,new object[]{handle,preferences.Effects})==0;
                chrome.GlassFrameThickness=new Thickness(acrylic?-1:0);
                HwndSource.FromHwnd(handle).CompositionTarget.BackgroundColor=Colors.Transparent;
                native.GetMethod("Apply",new[]{typeof(IntPtr),typeof(bool)}).Invoke(null,new object[]{handle,light});
                OneInstallAppearance.Apply(window,light,preferences.Accent,preferences.Color,preferences.Effects,acrylic);
            };
            window.Resources["TextPrimaryBrush"]=foreground;
            // A quiet glass core, a passing reflection and a single expanding halo.
            // All decoration runs on this dispatcher; readiness never waits for it.
            var core=new Grid { Width=104,Height=104,IsHitTestVisible=false,RenderTransformOrigin=new Point(.5,.5) };
            var scale=new ScaleTransform(1,1); core.RenderTransform=scale;
            var glass=new Border { CornerRadius=new CornerRadius(30),BorderThickness=new Thickness(1),
                BorderBrush=new SolidColorBrush(light?Color.FromArgb(38,0,0,0):Color.FromArgb(55,255,255,255)),
                Background=new LinearGradientBrush(light?Color.FromArgb(180,255,255,255):Color.FromArgb(32,255,255,255),Colors.Transparent,45) };
            if(!SystemParameters.HighContrast) core.Children.Add(glass);
            using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("1nstall.Symbol")) {
                core.Children.Add(new Image { Source=(ImageSource)XamlReader.Load(stream),Width=64,Height=64,IsHitTestVisible=false });
            }
            var haloScale=new ScaleTransform(1,1);
            var halo=new Ellipse { Width=150,Height=150,Stroke=foreground,StrokeThickness=1,Opacity=0,IsHitTestVisible=false,RenderTransformOrigin=new Point(.5,.5),RenderTransform=haloScale };
            root.Children.Add(halo); root.Children.Add(core);
            var reflection=new GradientStop(light?Color.FromArgb(28,0,0,0):Color.FromArgb(80,255,255,255),.5);
            var sheen=new LinearGradientBrush { StartPoint=new Point(0,1),EndPoint=new Point(1,0) };
            sheen.GradientStops.Add(new GradientStop(Colors.Transparent,.2)); sheen.GradientStops.Add(reflection); sheen.GradientStops.Add(new GradientStop(Colors.Transparent,.8));
            var shine=new Border { CornerRadius=new CornerRadius(30),Background=sheen,Opacity=0 };
            core.Children.Add(shine);
            var close=new Button { Content="×",Width=30,Height=30,FontSize=20,HorizontalAlignment=HorizontalAlignment.Right,VerticalAlignment=VerticalAlignment.Top,Margin=new Thickness(0,24,24,0),
                Background=Brushes.Transparent,Foreground=foreground,BorderThickness=new Thickness(0),Cursor=Cursors.Hand };
            System.Windows.Automation.AutomationProperties.SetName(close,"Close 1nstall");
            close.Template=(ControlTemplate)XamlReader.Parse("<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' TargetType='Button'><Border Name='Surface' Background='Transparent' BorderBrush='Transparent' BorderThickness='1' CornerRadius='15'><ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/></Border><ControlTemplate.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='Surface' Property='BorderBrush' Value='{Binding Foreground,RelativeSource={RelativeSource TemplatedParent}}'/></Trigger><Trigger Property='IsKeyboardFocused' Value='True'><Setter TargetName='Surface' Property='BorderBrush' Value='{Binding Foreground,RelativeSource={RelativeSource TemplatedParent}}'/></Trigger></ControlTemplate.Triggers></ControlTemplate>");
            close.FocusVisualStyle=null;
            close.Click+=delegate { window.Close(); }; root.Children.Add(close);
            window.Closed+=delegate { if(!finished) cancelled=true; dispatcher.BeginInvokeShutdown(DispatcherPriority.Background); };
            window.ContentRendered+=delegate {
                FirstFrameMilliseconds=(long)(DateTime.UtcNow-started).TotalMilliseconds;
                if(SystemParameters.ClientAreaAnimation && !SystemParameters.HighContrast) {
                    var settle=new DoubleAnimationUsingKeyFrames { FillBehavior=FillBehavior.Stop };
                    settle.KeyFrames.Add(new DiscreteDoubleKeyFrame(.72,KeyTime.FromTimeSpan(TimeSpan.Zero)));
                    settle.KeyFrames.Add(new EasingDoubleKeyFrame(1.035,KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(520)),new CubicEase { EasingMode=EasingMode.EaseOut }));
                    settle.KeyFrames.Add(new EasingDoubleKeyFrame(1,KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(820)),new SineEase { EasingMode=EasingMode.EaseInOut }));
                    scale.BeginAnimation(ScaleTransform.ScaleXProperty,settle); scale.BeginAnimation(ScaleTransform.ScaleYProperty,settle);
                    core.BeginAnimation(UIElement.OpacityProperty,new DoubleAnimation(.15,1,TimeSpan.FromMilliseconds(480)) { FillBehavior=FillBehavior.Stop });
                    var expand=new DoubleAnimation(.65,1.9,TimeSpan.FromMilliseconds(1300)) { EasingFunction=new CubicEase { EasingMode=EasingMode.EaseOut },FillBehavior=FillBehavior.Stop };
                    haloScale.BeginAnimation(ScaleTransform.ScaleXProperty,expand); haloScale.BeginAnimation(ScaleTransform.ScaleYProperty,expand);
                    halo.BeginAnimation(UIElement.OpacityProperty,new DoubleAnimation(.28,0,TimeSpan.FromMilliseconds(1300)) { FillBehavior=FillBehavior.Stop });
                    reflection.BeginAnimation(GradientStop.OffsetProperty,new DoubleAnimation(-.4,1.4,TimeSpan.FromMilliseconds(950)) { FillBehavior=FillBehavior.Stop });
                    shine.BeginAnimation(UIElement.OpacityProperty,new DoubleAnimation(.65,0,TimeSpan.FromMilliseconds(1050)) { FillBehavior=FillBehavior.Stop });
                    glow.BeginAnimation(UIElement.OpacityProperty,new DoubleAnimation(.25,.65,TimeSpan.FromMilliseconds(1000)) { AutoReverse=true,RepeatBehavior=RepeatBehavior.Forever,EasingFunction=new SineEase { EasingMode=EasingMode.EaseInOut } });
                }
                if(finished) window.Close();
            };
            System.ComponentModel.PropertyChangedEventHandler preferencesChanged=delegate {
                dispatcher.BeginInvoke(new Action(delegate { if(!SystemParameters.ClientAreaAnimation || SystemParameters.HighContrast) {
                    glow.BeginAnimation(UIElement.OpacityProperty,null); glow.Opacity=0;
                    core.BeginAnimation(UIElement.OpacityProperty,null);
                    scale.BeginAnimation(ScaleTransform.ScaleXProperty,null); scale.BeginAnimation(ScaleTransform.ScaleYProperty,null);
                    halo.BeginAnimation(UIElement.OpacityProperty,null); haloScale.BeginAnimation(ScaleTransform.ScaleXProperty,null); haloScale.BeginAnimation(ScaleTransform.ScaleYProperty,null);
                    shine.BeginAnimation(UIElement.OpacityProperty,null); reflection.BeginAnimation(GradientStop.OffsetProperty,null);
                    if(SystemParameters.HighContrast) { glass.Visibility=Visibility.Collapsed; root.Background=SystemColors.WindowBrush; window.Resources["TextPrimaryBrush"]=SystemColors.WindowTextBrush; }
                } }));
            };
            SystemParameters.StaticPropertyChanged+=preferencesChanged;
            try { if(!finished) { window.Show(); Dispatcher.Run(); } }
            finally { SystemParameters.StaticPropertyChanged-=preferencesChanged; }
        } catch { /* The real application and its error reporting can still open. */ }
    }
    public void Complete(Window target) {
        var handle=new WindowInteropHelper(target).Handle;
        var current=dispatcher;
        if(current==null || current.HasShutdownStarted) return;
        current.BeginInvoke(new Action(delegate {
            if(cancelled || window==null || !window.IsVisible) return;
            // Closing an unrelated foreground HWND can return activation to Explorer.
            // Give the opening its real owner, and hand over while we still own activation.
            new WindowInteropHelper(window).Owner=handle;
            var foreground=GetForegroundWindow();
            bool activate=foreground==new WindowInteropHelper(window).Handle || foreground==handle;
            if(activate) SetForegroundWindow(handle);
            target.Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle,new Action(delegate {
                if(activate && !cancelled && target.IsVisible) target.Activate();
                Dispose();
            }));
        }));
    }
    public void Dispose() {
        finished=true;
        var current=dispatcher;
        if(current!=null && !current.HasShutdownStarted) current.BeginInvoke(new Action(delegate {
            if(window!=null) window.Close(); else current.BeginInvokeShutdown(DispatcherPriority.Background);
        }));
    }
}
