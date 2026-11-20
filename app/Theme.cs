// Appearance: theme, Windows accent colour, glass and high contrast. A port of the appearance
// functions of vexan_installers.ps1 and src/settings.ps1, kept in the same order and with the
// same names in the comments, so the two can be read side by side.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shell;
using System.Windows.Threading;

static class Preferences {
    public static string Theme="System", Language="System";
    public static bool WindowsAccent=true, AutoUpdate=true;
    // The test modes: fixed preferences, nothing read or saved, no update check.
    public static bool Test;

    public static void Load(string record) {
        string[] fields=record.Split('\u001F');
        if(fields.Length!=4) return;
        Theme=fields[0]; WindowsAccent=fields[1]=="1"; Language=fields[2]; AutoUpdate=fields[3]=="1";
    }
    // Save-AppSettings. False when the file could not be written.
    public static bool Save() {
        if(Test) return true;
        return Engine.SaveSettings(String.Join("\u001F",Theme,WindowsAccent?"1":"0",Language,AutoUpdate?"1":"0")).Length==0;
    }
}

static class Theme {
    static Window window;
    static readonly Dictionary<string,object> decorationTemplates=new Dictionary<string,object>();
    static readonly Dictionary<string,Brush> glassTemplates=new Dictionary<string,Brush>();
    static readonly Dictionary<string,Brush> glassBrushes=new Dictionary<string,Brush>();
    static bool lightMode, nativeGlass;
    static bool? lastGlass, lastContrast;
    static string lastAccent="";
    // What Windows reported at the last update: accent colour, transparency effects, light apps.
    static Color? systemAccent; static bool? advancedEffects; static bool systemLight;

    public static bool Glass { get { return lastGlass==true; } }
    public static bool Light { get { return lightMode; } }

    static Color Hex(string value) { return (Color)ColorConverter.ConvertFromString(value); }
    static Brush BrushOf(string value) { return (Brush)new BrushConverter().ConvertFromString(value); }
    // Mix-Accent. PowerShell's [byte] cast rounds to the nearest value, halves to even.
    static Color Mix(Color a,Color b,double amount) {
        return Color.FromRgb(Convert.ToByte(a.R*(1-amount)+b.R*amount),Convert.ToByte(a.G*(1-amount)+b.G*amount),Convert.ToByte(a.B*(1-amount)+b.B*amount));
    }
    static double Luminance(Color color) { return FirstInstallWindow.Luminance(color.R,color.G,color.B); }
    static T Find<T>(string name) where T:class { return window.FindName(name) as T; }

    static void ReadSystem() {
        systemAccent=null; advancedEffects=null; systemLight=false;
        try {
            string[] fields=Engine.SystemAppearance().Split('\u001F');
            if(fields.Length!=3) return;
            if(fields[0].Length==6) systemAccent=Hex("#"+fields[0]);
            if(fields[1].Length==1) advancedEffects=fields[1]=="1";
            systemLight=fields[2]=="1";
        } catch(FormatException) { }
        // Pictures of the window with a named accent, without touching the colour of Windows.
        if(Preferences.Test) {
            string named=Environment.GetEnvironmentVariable("ONEINSTALL_TEST_ACCENT");
            if(named!=null && named.Length==6) { try { systemAccent=Hex("#"+named); } catch(FormatException) { } }
        }
    }

    // Get-AppLightMode
    static bool AppLightMode() {
        if(Preferences.Theme=="Light") return true;
        if(Preferences.Theme=="Dark") return false;
        return systemLight;
    }

    // Get-WindowsAccent
    static Color WindowsAccent() {
        if(!Preferences.WindowsAccent) return Hex(AppLightMode()?"#282828":"#D0D0D0");
        if(systemAccent.HasValue) return systemAccent.Value;
        Color glass=SystemParameters.WindowGlassColor;
        return Color.FromRgb(glass.R,glass.G,glass.B);
    }

    // Update-NativeGlass
    static void UpdateNativeGlass() {
        IntPtr handle=new WindowInteropHelper(window).Handle;
        if(handle==IntPtr.Zero) return;
        int backdrop=FirstInstallWindow.SetBackdrop(handle,lastGlass==true);
        nativeGlass=lastGlass==true && backdrop==0;
        var source=HwndSource.FromHwnd(handle);
        var chrome=WindowChrome.GetWindowChrome(window);
        var ambient=Find<UIElement>("AmbientLight");
        if(nativeGlass) {
            chrome.GlassFrameThickness=new Thickness(-1);
            source.CompositionTarget.BackgroundColor=Colors.Transparent;
            window.Background=Brushes.Transparent;
            ambient.Opacity=0.5;
        } else {
            chrome.GlassFrameThickness=new Thickness(0);
            source.CompositionTarget.BackgroundColor=Colors.Transparent;
            window.SetResourceReference(Control.BackgroundProperty,"WindowFill");
            ambient.Opacity=1;
        }
        FirstInstallWindow.Apply(handle,lightMode);
        SetAccentPalette(WindowsAccent());
        SetContrastResources();
    }

    // Set-AccentPalette
    static void SetAccentPalette(Color color) {
        // The dark theme is neutral, as the light theme is: the accent colours what is selected
        // or acts, and only tints the surfaces a little. 3.6 tinted the dark panels with the
        // inverse of the accent, over blue-grey surfaces and lavender lights.
        Color white=Colors.White, surface=Hex("#252629"), text=color;
        for(int i=0;i<20 && (Luminance(text)+0.05)/(Luminance(surface)+0.05)<4.5;i++) text=Mix(text,white,0.12);
        Color foreground=Luminance(color)>0.179?Colors.Black:white;
        window.Resources["AccentBrush"]=new SolidColorBrush(color);
        window.Resources["AccentTextBrush"]=new SolidColorBrush(text);
        window.Resources["AccentForegroundBrush"]=new SolidColorBrush(foreground);
        window.Resources["AccentMutedBrush"]=new SolidColorBrush(Mix(text,surface,0.25));
        window.Resources["AccentHoverBrush"]=new SolidColorBrush(Mix(text,white,0.15));
        window.Resources["AccentSurfaceBrush"]=new SolidColorBrush(Mix(color,surface,0.82));
        var action=new LinearGradientBrush { StartPoint=new Point(0,0), EndPoint=new Point(0.25,1) };
        Color contrast=foreground==white?Colors.Black:white;
        action.GradientStops.Add(new GradientStop(Mix(color,contrast,0.22),0));
        action.GradientStops.Add(new GradientStop(color,0.4));
        action.GradientStops.Add(new GradientStop(Mix(color,contrast,0.12),1));
        window.Resources["AccentActionBrush"]=action;
        var wash=new RadialGradientBrush { Center=new Point(0.5,0.5), GradientOrigin=new Point(0.5,0.5), RadiusX=0.75, RadiusY=0.85 };
        wash.GradientStops.Add(new GradientStop(Color.FromArgb(14,color.R,color.G,color.B),0));
        wash.GradientStops.Add(new GradientStop(Color.FromArgb(68,color.R,color.G,color.B),1));
        window.Resources["ConfirmationFill"]=wash;
        foreach(var template in glassTemplates) {
            string key=template.Key; bool edge=key=="GlassEdge" || key=="CardEdge";
            var brush=template.Value.CloneCurrentValue();
            var gradient=brush as GradientBrush;
            if(gradient!=null) {
                foreach(var stop in gradient.GradientStops) {
                    byte alpha=stop.Color.A;
                    Color tint=Mix(color,Monochrome(stop.Color),edge?EdgeTint:SurfaceTint);
                    if(key=="GlassPanelFill" || key=="ContentFill" || key=="GlassControlFill") {
                        for(int i=0;i<20 && Luminance(tint)>0.065;i++) tint=Mix(tint,Colors.Black,0.08);
                    }
                    tint.A=alpha; stop.Color=tint;
                }
            }
            var solid=brush as SolidColorBrush;
            if(solid!=null) solid.Color=Neutral(solid.Color,SurfaceTint);
            glassBrushes[key]=brush;
            if(lastGlass!=false) window.Resources[key]=brush;
        }
        lastAccent=color.ToString();
    }

    // Set-GlassAppearance
    static void SetGlassAppearance(bool enabled) {
        var opaque=new Dictionary<string,string> { {"GlassPanelFill","#1C2235"}, {"GlassControlFill","#252D43"}, {"GlassEdge","#7F8BA5"}, {"GlassMenuFill","#1C2235"}, {"ContentFill","#21283B"}, {"CardEdge","#57617B"} };
        foreach(string key in new List<string>(glassBrushes.Keys)) window.Resources[key]=enabled?glassBrushes[key]:new SolidColorBrush(Neutral(Hex(opaque[key]),key=="GlassEdge" || key=="CardEdge"?EdgeTint:SurfaceTint));
        Find<UIElement>("AmbientLight").Visibility=enabled?Visibility.Visible:Visibility.Collapsed;
        window.Resources["GlassHighlightsOpacity"]=enabled?1.0:0.0;
        window.Resources["TextShadowOpacity"]=enabled?0.32:0.0;
        foreach(string name in new[]{"NavigationBackdrop","SetupBackdrop","RemovalBackdrop"}) Find<UIElement>(name).Visibility=enabled?Visibility.Visible:Visibility.Collapsed;
        foreach(string name in new[]{"NavigationGlass","SetupGlass","RemovalGlass"}) {
            var pane=Find<Border>(name);
            if(enabled) pane.Background=Brushes.Transparent; else pane.SetResourceReference(Border.BackgroundProperty,"GlassPanelFill");
        }
        lastGlass=enabled;
        UpdateNativeGlass();
    }

    // Update-WindowsAccent: follows Windows once a second, and after a preference changes.
    public static void Update() {
        ReadSystem();
        bool changed=false;
        bool light=AppLightMode();
        if(light!=lightMode) { lightMode=light; lastGlass=null; changed=true; }
        Color color=WindowsAccent();
        bool contrast=SystemParameters.HighContrast;
        if(contrast!=lastContrast) { lastGlass=null; SetAccentPalette(color); lastContrast=contrast; changed=true; }
        if(color.ToString()!=lastAccent) { SetAccentPalette(color); changed=true; }
        bool glass=!SystemParameters.HighContrast;
        if(advancedEffects.HasValue) glass=glass && advancedEffects.Value;
        if(glass!=lastGlass) { SetGlassAppearance(glass); changed=true; }
        if(changed) SetContrastResources();
    }

    // Forces the accent to be applied again, as the settings page does when the accent option changes.
    public static void ForgetAccent() { lastAccent=""; }

    // Set-ContrastResources
    static void SetContrastResources() {
        bool contrast=SystemParameters.HighContrast;
        window.Resources["TextPrimaryBrush"]=contrast?SystemColors.WindowTextBrush:BrushOf("#F3F5F7");
        window.Resources["TextSecondaryBrush"]=contrast?SystemColors.WindowTextBrush:BrushOf("#C8C9CC");
        window.Resources["InputFill"]=contrast?SystemColors.WindowBrush:BrushOf("#1D1E21");
        window.Resources["DialogFill"]=contrast?SystemColors.WindowBrush:BrushOf("#141518");
        window.Resources["FocusBrush"]=contrast?SystemColors.WindowTextBrush:Brushes.White;
        window.Resources["CheckBorderBrush"]=contrast?SystemColors.WindowTextBrush:BrushOf("#ADAFB3");
        if(contrast) {
            foreach(string key in new[]{"WindowFill","OpaqueWindowFill","DialogFill","InputFill","GlassPanelFill","GlassControlFill","GlassMenuFill","ContentFill"}) window.Resources[key]=SystemColors.WindowBrush;
            foreach(string key in new[]{"GlassEdge","CardEdge"}) window.Resources[key]=SystemColors.WindowTextBrush;
            foreach(string key in new[]{"AccentBrush","AccentActionBrush"}) window.Resources[key]=SystemColors.HighlightBrush;
            window.Resources["AccentSurfaceBrush"]=SystemColors.WindowBrush;
            window.Resources["AccentTextBrush"]=SystemColors.WindowTextBrush;
            window.Resources["AccentForegroundBrush"]=SystemColors.HighlightTextBrush;
        }
        SetAppMaterials();
    }

    // Convert-MonochromeColor
    static Color Monochrome(Color color) {
        byte gray=Convert.ToByte(Math.Round(0.2126*color.R+0.7152*color.G+0.0722*color.B));
        return Color.FromArgb(color.A,gray,gray,gray);
    }

    // How much of the accent the dark surfaces and their edges take: about what the light ones do.
    const double SurfaceTint=0.98, EdgeTint=0.94;

    // A colour of the 3.6 dark theme without its own hue, with a little of the accent.
    static Color Neutral(Color color,double amount) {
        Color tint=Mix(WindowsAccent(),Monochrome(color),amount); tint.A=color.A;
        return tint;
    }

    // The decoration of the 3.6 dark theme without its lavender.
    static object Gray(object value) {
        if(value is Color) return Monochrome((Color)value);
        var solid=value as SolidColorBrush;
        return solid==null?value:new SolidColorBrush(Monochrome(solid.Color));
    }

    // New-MaterialGradient: stops are offset and colour, in pairs.
    static LinearGradientBrush Material(object[] stops,double tint,string end) {
        var brush=new LinearGradientBrush { StartPoint=new Point(0,0), EndPoint=Point.Parse(end) };
        for(int i=0;i<stops.Length;i+=2) {
            Color color=Hex((string)stops[i+1]); byte alpha=color.A;
            if(tint>0 && Preferences.WindowsAccent) { color=Mix(color,WindowsAccent(),tint); color.A=alpha; }
            brush.GradientStops.Add(new GradientStop(color,Convert.ToDouble(stops[i])));
        }
        return brush;
    }

    // Set-AppMaterials
    static void SetAppMaterials() {
        // Restore the original dark decoration before applying either appearance.
        foreach(var template in decorationTemplates) window.Resources[template.Key]=template.Value;
        // Accessibility colours remain authoritative; visual effects are already disabled.
        if(SystemParameters.HighContrast) { window.Resources["InstalledCardFill"]=window.Resources["ContentFill"]; return; }
        if(lightMode) {
            var colors=new Dictionary<string,string> { {"TextPrimaryBrush","#1A1D25"}, {"TextSecondaryBrush","#414753"}, {"CheckBorderBrush","#68717F"}, {"FocusBrush","#333A48"}, {"InputFill","#F6F7FA"}, {"DialogFill","#E9EBF1"}, {"GlassMenuFill","#F4F5F8"}, {"SeparatorBrush","#87909F"}, {"GroupFill","#20FFFFFF"}, {"GroupEdge","#30838B9B"}, {"GroupHoverFill","#70FFFFFF"}, {"BevelBrush","#E6FFFFFF"}, {"HoverEdgeBrush","#717B8C"}, {"CardHoverEdgeBrush","#717B8C"}, {"ReflectionEdgeBrush","#C0FFFFFF"} };
            foreach(var entry in colors) window.Resources[entry.Key]=BrushOf(entry.Value);
            window.Resources["ContentFill"]=Material(new object[]{0,"#FFFFFF",0.42,"#F2F4F8",1,"#DBE1E9"},0.04,"0.8,1");
            window.Resources["GlassPanelFill"]=Material(new object[]{0,"#EDFDFDFF",0.32,"#D0E6EAF1",0.72,"#C4CDD6E2",1,"#E5F6F9FC"},0.055,"0.8,1");
            window.Resources["GlassControlFill"]=Material(new object[]{0,"#FAFFFFFF",0.48,"#E8F0F2F7",1,"#D4CAD4E0"},0.035,"0.25,1");
            window.Resources["GlassEdge"]=Material(new object[]{0,"#F5FFFFFF",0.18,"#DDAEB8C8",0.5,"#85758095",0.82,"#D0A4B4C7",1,"#EBFFFFFF"},0.1,"1,1");
            window.Resources["CardEdge"]=Material(new object[]{0,"#F8FFFFFF",0.35,"#80919AAA",1,"#D09AA7B9"},0.06,"0.8,1");
            Color color=WindowsAccent(), text=color;
            for(int i=0;i<30 && (Luminance(Hex("#CAD0D8"))+0.05)/(Luminance(text)+0.05)<4.5;i++) text=Mix(text,Colors.Black,0.12);
            window.Resources["AccentTextBrush"]=new SolidColorBrush(text);
            window.Resources["AccentSurfaceBrush"]=Material(new object[]{0,"#FFFFFF",0.45,"#D8DDE5",1,"#EEF0F5"},0.18,"0.8,1");
            window.Resources["AccentMutedBrush"]=new SolidColorBrush(Mix(color,Colors.White,0.25));
            window.Resources["ButtonLightColor"]=Hex("#C0FFFFFF");
            window.Resources["CardLightColor"]=Hex("#B0FFFFFF");
            window.Resources["ReflectionColor"]=Hex("#A8FFFFFF");
            window.Resources["ReflectionSoftColor"]=Hex("#28FFFFFF");
            window.Resources["GlassShadowColor"]=Hex("#76849A");
            // Crisp dark type: depth comes from the surfaces and edges, not a text shadow.
            window.Resources["TextShadowOpacity"]=0.0;
            if(lastGlass!=true) {
                foreach(string key in new[]{"GlassPanelFill","GlassControlFill","GlassEdge","CardEdge"}) {
                    var brush=(GradientBrush)((Brush)window.Resources[key]).CloneCurrentValue();
                    foreach(var stop in brush.GradientStops) { Color shade=stop.Color; shade.A=255; stop.Color=shade; }
                    window.Resources[key]=brush;
                }
            }
        }
        if(!Preferences.WindowsAccent) {
            // Desaturate every semantic material and decorative colour, retaining alpha and stops.
            foreach(object key in new ArrayList(window.Resources.Keys)) {
                object value=window.Resources[key];
                if(value is Color) window.Resources[key]=Monochrome((Color)value);
                else if(value is SolidColorBrush) {
                    var brush=((SolidColorBrush)value).CloneCurrentValue(); Color shade=Monochrome(brush.Color);
                    // Keep wallpaper colours behind the monochrome canvas.
                    if(Equals(key,"WindowFill")) shade.A=255;
                    brush.Color=shade; window.Resources[key]=brush;
                } else if(value is GradientBrush) {
                    var brush=((GradientBrush)value).CloneCurrentValue();
                    foreach(var stop in brush.GradientStops) stop.Color=Monochrome(stop.Color);
                    window.Resources[key]=brush;
                }
            }
        }
        OneInstallAppearance.Apply(window,lightMode,Preferences.WindowsAccent,WindowsAccent(),lastGlass==true,nativeGlass);
        var installed=((Brush)window.Resources["ContentFill"]).CloneCurrentValue();
        var gradient=installed as GradientBrush;
        if(gradient!=null) foreach(var stop in gradient.GradientStops) { Color shade=Monochrome(stop.Color); shade.A=255; stop.Color=shade; }
        else { var solid=(SolidColorBrush)installed; solid.Color=Monochrome(solid.Color); }
        window.Resources["InstalledCardFill"]=installed;
    }

    // Move-GlassLight: the pointer-following highlight, at most 40 times a second.
    public static void MoveGlassLight(Border light,Point position) {
        if(light==null || light.ActualWidth<=0 || light.ActualHeight<=0) return;
        long now=DateTime.UtcNow.Ticks;
        if(light.Tag is long && now-(long)light.Tag<250000) return;
        light.Tag=now;
        var brush=light.Background as RadialGradientBrush;
        if(brush==null) return;
        if(brush.IsFrozen) { brush=brush.Clone(); light.Background=brush; }
        var point=new Point(Math.Max(0.0,Math.Min(1.0,position.X/light.ActualWidth)),Math.Max(0.0,Math.Min(1.0,position.Y/light.ActualHeight)));
        brush.Center=point; brush.GradientOrigin=point;
    }

    // Enable-HoverMotion
    public static void EnableHoverMotion(Control element) {
        element.MouseMove+=delegate(object sender,MouseEventArgs e) {
            if(!Glass || !OneInstall.Motion.Enabled) return;
            var control=(Control)sender; control.ApplyTemplate();
            var light=control.Template==null?null:control.Template.FindName("HoverLight",control) as Border;
            if(light!=null) MoveGlassLight(light,e.GetPosition(light));
        };
    }

    // Update-GlassBackdrops: each glass pane shows the ambient light that lies behind it.
    static void UpdateGlassBackdrops() {
        var ambient=Find<FrameworkElement>("AmbientLight");
        foreach(string name in new[]{"Navigation","Setup","Removal"}) {
            var pane=Find<FrameworkElement>(name+"Glass"); var backdrop=Find<Border>(name+"Backdrop");
            if(pane.ActualWidth<=0 || pane.ActualHeight<=0) continue;
            var brush=backdrop.Background as VisualBrush;
            if(brush==null) {
                brush=new VisualBrush(ambient) { ViewboxUnits=BrushMappingMode.Absolute, Stretch=Stretch.Fill, AutoLayoutContent=false };
                backdrop.Background=brush;
            }
            Point origin=pane.TranslatePoint(new Point(0,0),ambient);
            brush.Viewbox=new Rect(origin.X,origin.Y,pane.ActualWidth,pane.ActualHeight);
        }
    }

    // The start of the appearance, in the order 3.6 runs it.
    public static void Initialize(Window target) {
        window=target;
        foreach(string key in new[]{"BevelBrush","HoverEdgeBrush","CardHoverEdgeBrush","ReflectionEdgeBrush","SeparatorBrush","GroupFill","GroupEdge","GroupHoverFill","TextShadowColor","GlassShadowColor","ButtonLightColor","CardLightColor","ReflectionColor","ReflectionSoftColor"}) decorationTemplates[key]=Gray(window.Resources[key]);
        foreach(string key in new[]{"GlassPanelFill","GlassControlFill","GlassEdge","GlassMenuFill","ContentFill","CardEdge"}) glassTemplates[key]=(Brush)window.Resources[key];
        Update();
        // Poll on the dispatcher, as 3.6 does: once a second.
        var timer=new DispatcherTimer { Interval=TimeSpan.FromSeconds(1) };
        timer.Tick+=delegate { Update(); };
        window.Closed+=delegate { timer.Stop(); };
        timer.Start();
        foreach(string name in new[]{"NavigationGlass","SetupGlass","RemovalGlass"}) {
            var pane=Find<FrameworkElement>(name);
            pane.SizeChanged+=delegate { UpdateGlassBackdrops(); };
            pane.MouseMove+=delegate(object sender,MouseEventArgs e) {
                if(!Glass || !OneInstall.Motion.Enabled) return;
                var light=Find<Border>(((FrameworkElement)sender).Name.Replace("Glass","Reflection"));
                if(light!=null) MoveGlassLight(light,e.GetPosition(light));
            };
        }
        window.Loaded+=delegate { UpdateGlassBackdrops(); };
    }

    // What 3.6 does when the system window is created: square the frame, then the backdrop.
    public static void SourceInitialized() {
        FirstInstallWindow.Apply(new WindowInteropHelper(window).Handle);
        UpdateNativeGlass();
    }
}
