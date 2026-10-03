using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Automation;
using System.Windows.Media;
using System.Collections.Generic;
using System.Globalization;
using System.Web.Script.Serialization;

namespace OneInstall {
    public partial class MainWindow : Window {
        public MainWindow() { InitializeComponent(); }
    }
    public static class NativeUI {
        public sealed class CatalogCard {
            public string Key { get; set; }
            public string Name { get; set; }
            public string Category { get; set; }
            public string Description { get; set; }
            public string LicenseLabel { get; set; }
            public string Url { get; set; }
            public string[] Ids { get; set; }
            public string[] AlsoIn { get; set; }
        }
        static int SortGroup(string name) {
            return char.GetUnicodeCategory(name,0)==UnicodeCategory.DecimalDigitNumber?0:char.IsLetter(name,0)?1:2;
        }
        public static void Populate(Window window,string json) {
            var apps=new JavaScriptSerializer().Deserialize<CatalogCard[]>(json);
            Array.Sort(apps,delegate(CatalogCard a,CatalogCard b) {
                int group=SortGroup(a.Name).CompareTo(SortGroup(b.Name));
                return group!=0?group:StringComparer.CurrentCultureIgnoreCase.Compare(a.Name,b.Name);
            });
            var checks=new Dictionary<string,CheckBox>();
            var texts=new Dictionary<string,string>();
            var panel=(UniformGrid)window.FindName("Cards");
            foreach(var app in apps) {
                bool automatic=app.Ids.Length>0;
                string method=automatic?"Automatic · WinGet: "+string.Join(", ",app.Ids):"Guided · official website: "+app.Url;
                string help=app.Description+"\n"+app.Category+" · "+app.LicenseLabel+"\n"+method;
                if(app.AlsoIn.Length>0) help+="\nAlso in: "+string.Join(", ",app.AlsoIn);
                var card=Card(window,app.Key,app.Name,app.Category,help,automatic);
                checks.Add(app.Key,card); panel.Children.Add(card);
                texts.Add(app.Key,app.Name+" "+app.Category+" "+string.Join(" ",app.AlsoIn)+" "+app.Description);
            }
            window.Resources["NativeChecks"]=checks;
            window.Resources["NativeSearchTexts"]=texts;
            window.Height=Math.Min(840,SystemParameters.WorkArea.Height-24);
            Layout(panel,window.Width-560,window.Height-190,0);
            var content=(FrameworkElement)window.Content;
            content.Measure(new Size(window.Width,window.Height));
            content.Arrange(new Rect(0,0,window.Width,window.Height));
        }
        static readonly ControlTemplate EmptyCard = new ControlTemplate(typeof(CheckBox));
        public static TextBlock Label(string text, double size, bool secondary) {
            var label = new TextBlock { Text = text, FontSize = size, TextWrapping = TextWrapping.Wrap };
            label.SetResourceReference(TextBlock.ForegroundProperty, secondary ? "TextSecondaryBrush" : "TextPrimaryBrush");
            return label;
        }
        public static CheckBox Card(Window window, string key, string title, string category, string help, bool automatic) {
            var card = new CheckBox { Style = (Style)window.Resources["CardCheck"], Tag = key,
                Margin = new Thickness(4,0,4,8), Height = 140, MinHeight = 140, Template = EmptyCard };
            AutomationProperties.SetName(card,title);
            AutomationProperties.SetHelpText(card,help);
            var tip = new ToolTip { Padding = new Thickness(12), MaxWidth = 360, Content = Label(title+"\n\n"+help,12,false) };
            tip.SetResourceReference(Control.BackgroundProperty,"DialogFill");
            tip.SetResourceReference(Control.ForegroundProperty,"TextPrimaryBrush");
            tip.SetResourceReference(Control.BorderBrushProperty,"GlassEdge");
            card.ToolTip=tip;
            var content=new StackPanel();
            var name=Label(title,14,false);
            name.FontWeight=FontWeights.SemiBold; name.Height=36; name.LineHeight=18;
            name.LineStackingStrategy=LineStackingStrategy.BlockLineHeight;
            name.TextTrimming=TextTrimming.CharacterEllipsis; name.Margin=new Thickness(0,0,0,4);
            content.Children.Add(name);
            var cat=Label(category,11,true); cat.TextWrapping=TextWrapping.NoWrap; cat.TextTrimming=TextTrimming.CharacterEllipsis;
            content.Children.Add(cat);
            var method=Label(automatic?"WinGet · automatic":"Website · guided",11,true);
            method.TextWrapping=TextWrapping.NoWrap; method.TextTrimming=TextTrimming.CharacterEllipsis;
            method.Margin=new Thickness(0,4,0,0); content.Children.Add(method);
            var details=new Button { Content="Details", Tag=key, Margin=new Thickness(0,8,0,0), Padding=new Thickness(6,4,6,4), MinHeight=28, ToolTip="App details · F1 while the card is focused" };
            AutomationProperties.SetName(details,"Details for "+title); content.Children.Add(details);
            card.Content=content;
            return card;
        }
        // Keep lightweight card slots for scrolling and keyboard navigation; construct
        // their visual templates only around the viewport. Content and selection persist.
        public static void Realize(UniformGrid panel, ScrollViewer scroll) {
            Realize(panel,scroll.ViewportWidth,scroll.ViewportHeight,scroll.VerticalOffset);
        }
        public static void Layout(UniformGrid panel, double width, double height, double offset) {
            int columns=Math.Max(1,Math.Min(6,(int)Math.Floor((width+8)/192)));
            panel.Columns=columns;
            // Half a gap on both sides of every cell, cancelled at the outer edges.
            // UniformGrid distributes fractional widths without creating spare space.
            panel.Width=Math.Max(0,width)+8;
            Realize(panel,width,height,offset);
        }
        static void Realize(UniformGrid panel,double width,double height,double offset) {
            if (width<=0) return;
            int columns=Math.Max(1,panel.Columns);
            int first=Math.Max(0,((int)(offset/148)-1)*columns);
            int last=((int)((offset+height)/148)+2)*columns;
            for(int i=0;i<panel.Children.Count;i++) {
                var card=(CheckBox)panel.Children[i];
                bool visible=i>=first && i<last;
                if(visible && card.ReadLocalValue(Control.TemplateProperty)==EmptyCard) card.ClearValue(Control.TemplateProperty);
                else if(!visible && card.ReadLocalValue(Control.TemplateProperty)!=EmptyCard) card.Template=EmptyCard;
            }
        }
    }
}
