using System;
using System.Collections.Generic;
using System.IO;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using Microsoft.Win32;

// The opening and the main UI paint the same canvas, including its ambient fields.
public static class OneInstallAppearance {
    public sealed class Preferences {
        public bool Light, Accent=true, Effects=true;
        public Color Color;
    }
    static Color Hex(string value) { return (Color)ColorConverter.ConvertFromString(value); }
    static Color Mix(Color a,Color b,double amount) {
        return Color.FromRgb(Convert.ToByte(a.R*(1-amount)+b.R*amount),Convert.ToByte(a.G*(1-amount)+b.G*amount),Convert.ToByte(a.B*(1-amount)+b.B*amount));
    }
    static Color Gray(Color color) {
        byte value=Convert.ToByte(.2126*color.R+.7152*color.G+.0722*color.B);
        return Color.FromArgb(color.A,value,value,value);
    }
    static double Linear(byte value) { double c=value/255.0; return c<=.04045?c/12.92:Math.Pow((c+.055)/1.055,2.4); }
    static double Luminance(Color c) { return .2126*Linear(c.R)+.7152*Linear(c.G)+.0722*Linear(c.B); }
    public static Preferences Read() {
        var result=new Preferences(); string theme="System";
        try {
            string path=System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"1nstall","settings.json");
            if(new FileInfo(path).Length<=8192) {
                var settings=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(path));
                object value;
                if(settings!=null && settings.TryGetValue("Theme",out value) && value is string) theme=(string)value;
                if(settings!=null && settings.TryGetValue("WindowsAccent",out value) && value is bool) result.Accent=(bool)value;
            }
        } catch(IOException) { } catch(UnauthorizedAccessException) { } catch(ArgumentException) { } catch(InvalidOperationException) { }
        using(var key=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
            result.Light=theme=="Light" || theme!="Dark" && key!=null && object.Equals(key.GetValue("AppsUseLightTheme"),1);
        var glass=SystemParameters.WindowGlassColor;
        result.Color=Color.FromRgb(glass.R,glass.G,glass.B);
        try {
            var type=Type.GetType("Windows.UI.ViewManagement.UISettings, Windows.UI.ViewManagement, ContentType=WindowsRuntime",true);
            var settings=Activator.CreateInstance(type);
            var method=type.GetMethod("GetColorValue");
            object color=method.Invoke(settings,new[]{Enum.Parse(method.GetParameters()[0].ParameterType,"Accent")});
            var ct=color.GetType();
            result.Color=Color.FromRgb((byte)ct.GetProperty("R").GetValue(color,null),(byte)ct.GetProperty("G").GetValue(color,null),(byte)ct.GetProperty("B").GetValue(color,null));
            result.Effects=(bool)type.GetProperty("AdvancedEffectsEnabled").GetValue(settings,null);
        } catch { /* The same WindowGlassColor fallback as the main UI on older Windows. */ }
        result.Effects &= !SystemParameters.HighContrast;
        if(!result.Accent) result.Color=Hex(result.Light?"#282828":"#D0D0D0");
        return result;
    }
    public static Brush Background(bool light,bool accent,Color color,bool native) {
        if(SystemParameters.HighContrast) return SystemColors.WindowBrush;
        if(light) {
            var brush=new LinearGradientBrush { StartPoint=new Point(0,0),EndPoint=new Point(.8,1) };
            var colors=new[]{"#EBEDF2","#E0E4EB","#D0D7E0"}; var offsets=new[]{0,.45,1};
            for(int i=0;i<colors.Length;i++) brush.GradientStops.Add(new GradientStop(accent?Mix(Hex(colors[i]),color,.025):Gray(Hex(colors[i])),offsets[i]));
            return brush;
        }
        var tint=Color.FromRgb((byte)(255-color.R),(byte)(255-color.G),(byte)(255-color.B));
        var background=Mix(tint,Hex("#080B14"),.96);
        if(!accent) background=Gray(background);
        background.A=(byte)(native && accent?224:255);
        return new SolidColorBrush(background);
    }
    static void AddField(Window window,Grid ambient,int number,double width,double height,HorizontalAlignment x,VerticalAlignment y,Thickness margin,byte[] alphas,double[] offsets) {
        var gradient=new RadialGradientBrush();
        for(int i=0;i<alphas.Length;i++) gradient.GradientStops.Add(new GradientStop(Color.FromArgb(alphas[i],0,0,0),offsets[i]));
        ambient.Children.Add(new Ellipse { Width=width,Height=height,HorizontalAlignment=x,VerticalAlignment=y,Margin=margin,Fill=gradient });
        window.RegisterName("AmbientGradient"+number,gradient);
    }
    public static void Apply(Window window,bool light,bool accent,Color color,bool effects,bool native) {
        window.Resources["WindowFill"]=Background(light,accent,color,native);
        window.Resources["OpaqueWindowFill"]=Background(light,accent,color,false);
        var ambient=(Grid)window.FindName("AmbientLight");
        if(ambient.Children.Count==0) {
            AddField(window,ambient,1,1050,1000,HorizontalAlignment.Left,VerticalAlignment.Top,new Thickness(-430,-370,0,0),new byte[]{192,96,0},new[]{0,.4,1});
            AddField(window,ambient,2,1100,900,HorizontalAlignment.Right,VerticalAlignment.Bottom,new Thickness(0,0,-500,-450),new byte[]{149,53,0},new[]{0,.55,1});
            AddField(window,ambient,3,850,650,HorizontalAlignment.Center,VerticalAlignment.Center,new Thickness(80,-170,0,0),new byte[]{101,0},new double[]{0,1});
        }
        for(int number=1;number<=3;number++) {
            Color tint;
            if(light) { tint=Hex(number==2?"#A6BAC6":"#B1A5CA"); if(accent) tint=Mix(tint,color,.16); }
            else {
                var inverse=Color.FromRgb((byte)(255-color.R),(byte)(255-color.G),(byte)(255-color.B));
                tint=Mix(number==2?color:inverse,Hex(number==2?"#607BAA":"#AB8FE0"),.45);
                for(int i=0;i<20 && Luminance(tint)>.10;i++) tint=Mix(tint,Colors.Black,.08);
            }
            if(!accent) tint=Gray(tint);
            var brush=(RadialGradientBrush)window.FindName("AmbientGradient"+number);
            foreach(var stop in brush.GradientStops) { var shade=tint; shade.A=stop.Color.A; stop.Color=shade; }
        }
        ambient.Opacity=light?.7:native?.5:1;
        ambient.Visibility=effects && !SystemParameters.HighContrast?Visibility.Visible:Visibility.Collapsed;
    }
}
