// Interface language: Convert-UiText, Set-UiValue, Update-UiTree and Apply-AppLanguage of
// src/settings.ps1. Every label is written in English; the English text is remembered on the
// element, so the whole window can be re-translated in place when the language changes.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Markup;

static class I18n {
    sealed class Pattern { public Regex Regex; public string Text; public int Count; }
    const string Prefix="1nstall.i18n.";
    static readonly string[] Translated={"Text","Content","Header","ToolTip"};
    // Keys are looked up without regard to case, as PowerShell looks up properties.
    static Dictionary<string,string> pack=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
    static readonly List<Pattern> patterns=new List<Pattern>();
    static readonly Dictionary<Type,PropertyInfo[]> properties=new Dictionary<Type,PropertyInfo[]>();

    public static string Language="en";
    public static bool Rtl;

    // The engine's answer for a language: code and direction, then one record per text.
    public static void Load(string records) {
        string[] rows=records.Split('\u001E');
        string[] header=rows[0].Split('\u001F');
        Language=header[0]; Rtl=header.Length>1 && header[1]=="1";
        pack=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        patterns.Clear();
        for(int i=1;i<rows.Length;i++) {
            string[] fields=rows[i].Split('\u001F');
            if(fields.Length!=2) continue;
            pack[fields[0]]=fields[1];
            // A text with {0} placeholders also translates any text that fits its shape.
            var tokens=Regex.Matches(fields[0],@"\{\d+\}");
            if(tokens.Count==0) continue;
            string pattern=Regex.Escape(fields[0]);
            foreach(Match token in tokens) pattern=pattern.Replace(Regex.Escape(token.Value),"(.+?)");
            patterns.Add(new Pattern { Regex=new Regex("^"+pattern+"$"), Text=fields[1], Count=tokens.Count });
        }
    }

    public static string Convert(string text) {
        if(String.IsNullOrEmpty(text) || Language=="en") return text;
        string exact;
        if(pack.TryGetValue(text,out exact)) return exact;
        foreach(var pattern in patterns) {
            var match=pattern.Regex.Match(text);
            if(!match.Success) continue;
            string translated=pattern.Text;
            for(int i=0;i<pattern.Count;i++) {
                string part=match.Groups[i+1].Value, known;
                if(pack.TryGetValue(part,out known)) part=known;
                translated=translated.Replace("{"+i+"}",part);
            }
            return translated;
        }
        if(text.Contains("\n")) {
            string[] lines=Regex.Split(text,"\r?\n");
            for(int i=0;i<lines.Length;i++) lines[i]=Convert(lines[i]);
            return String.Join("\n",lines);
        }
        return text;
    }

    static PropertyInfo Property(object element,int index) {
        PropertyInfo[] known; Type type=element.GetType();
        if(!properties.TryGetValue(type,out known)) {
            known=new PropertyInfo[Translated.Length];
            for(int i=0;i<Translated.Length;i++) {
                try { known[i]=type.GetProperty(Translated[i],BindingFlags.Public|BindingFlags.Instance); }
                catch(AmbiguousMatchException) { known[i]=type.GetProperty(Translated[i],BindingFlags.Public|BindingFlags.Instance|BindingFlags.DeclaredOnly); }
            }
            properties[type]=known;
        }
        return known[index];
    }

    // PowerShell's -ne: two strings are compared without regard to case.
    static bool Same(object current,object value) {
        var a=current as string; var b=value as string;
        return a!=null && b!=null?String.Equals(a,b,StringComparison.InvariantCultureIgnoreCase):Equals(current,value);
    }

    // Sets a label. The English text is kept on the element and the translation is shown.
    // An editable text box holds what the user typed, so it is never translated.
    public static void Set(object element,string property,object value) {
        int index=Array.IndexOf(Translated,property);
        var info=index>=0?Property(element,index):element.GetType().GetProperty(property);
        if(info==null) return;
        var framework=element as FrameworkElement; var text=value as string; var box=element as TextBox;
        if(framework!=null && text!=null && !(box!=null && !box.IsReadOnly)) {
            framework.Resources[Prefix+property]=text;
            value=Convert(text);
        }
        if(!Same(info.GetValue(element,null),value)) info.SetValue(element,value,null);
    }

    public static void UpdateTree(object node,HashSet<DependencyObject> seen) {
        var element=node as DependencyObject;
        if(element==null || !seen.Add(element)) return;
        var framework=element as FrameworkElement;
        if(framework!=null) {
            for(int i=0;i<Translated.Length;i++) {
                var info=Property(framework,i);
                if(info==null) continue;
                string property=Translated[i];
                var box=framework as TextBox;
                if(property=="Text" && !(framework is TextBlock) && !(box!=null && box.IsReadOnly)) continue;
                string key=Prefix+property;
                if(framework.Resources.Contains(key)) Set(framework,property,framework.Resources[key]);
                else {
                    var current=info.GetValue(framework,null) as string;
                    if(current==null) continue;
                    // Application names and other model-bound values are content, not UI labels.
                    if(property=="Text" && BindingOperations.IsDataBound(framework,TextBlock.TextProperty)) continue;
                    Set(framework,property,current);
                }
            }
        }
        foreach(object child in LogicalTreeHelper.GetChildren(element)) UpdateTree(child,seen);
    }

    // Re-translates one subtree that was built after the last full pass, such as a card's inside.
    public static void UpdateTree(object node) { UpdateTree(node,new HashSet<DependencyObject>()); }

    // Apply-AppLanguage: the texts, the layout direction and the window's language.
    public static void Apply(Window window,IEnumerable<FrameworkElement> detached,FrameworkElement settingsPage) {
        var seen=new HashSet<DependencyObject>();
        UpdateTree(window,seen);
        foreach(var element in detached) UpdateTree(element,seen);
        var panes=window.FindName("AppPanes") as FrameworkElement;
        if(panes!=null) panes.FlowDirection=Rtl?FlowDirection.RightToLeft:FlowDirection.LeftToRight;
        // Window controls and technical logs keep their physical/system direction.
        foreach(string name in new[]{"LogBox","UninstallLog"}) { var log=window.FindName(name) as FrameworkElement; if(log!=null) log.FlowDirection=FlowDirection.LeftToRight; }
        window.Language=XmlLanguage.GetLanguage(Language);
        if(settingsPage!=null) UpdateTree(settingsPage,seen);
    }

    public static string UiCulture { get { return CultureInfo.CurrentUICulture.Name; } }
}
