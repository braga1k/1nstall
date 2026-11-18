// The library cards. This is NativeUI from src/ui-helper.cs of 3.6, with two changes for 4.0:
// it reads the engine's records instead of parsing JSON, and it builds the inside of a card
// only when the card first comes near the viewport. Names, sizes, order, automation text and
// the "NativeChecks" and "NativeSearchTexts" resources are unchanged.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;

namespace OneInstall {
    public partial class MainWindow : Window {
        public MainWindow() { InitializeComponent(); }
    }
    // What a card shows. Parsed on a worker thread at start-up, so this class holds no WPF object.
    public sealed class CatalogCard {
        public string Key, Name, Category, CategoryGroup, Description, LicenseLabel, Url;
        // The category the card currently shows: a second category of the app while that one is chosen.
        public string ShownCategory;
        public string[] Ids, AlsoIn;
        public bool Automatic { get { return Ids.Length>0; } }
        static readonly char[] Field={'\u001F'}, Record={'\u001E'}, Item={'\u001D'};
        static string[] Items(string field) { return field.Length==0?new string[0]:field.Split(Item); }

        // The engine's card records: see `cards` in engine/ffi/src/lib.rs.
        public static CatalogCard[] Parse(string records) {
            string[] rows=records.Length==0?new string[0]:records.Split(Record);
            var apps=new CatalogCard[rows.Length];
            for(int i=0;i<rows.Length;i++) {
                string[] fields=rows[i].Split(Field);
                if(fields.Length!=9) throw new FormatException("Unexpected card record.");
                apps[i]=new CatalogCard { Key=fields[0], Name=fields[1], Category=fields[2], CategoryGroup=fields[3], Description=fields[4], LicenseLabel=fields[5], Url=fields[6], Ids=Items(fields[7]), AlsoIn=Items(fields[8]) };
            }
            return apps;
        }
    }
    public static class NativeUI {
        static int SortGroup(string name) {
            return char.GetUnicodeCategory(name,0)==UnicodeCategory.DecimalDigitNumber?0:char.IsLetter(name,0)?1:2;
        }
        public static void Populate(Window window,CatalogCard[] apps) {
            Array.Sort(apps,delegate(CatalogCard a,CatalogCard b) {
                int group=SortGroup(a.Name).CompareTo(SortGroup(b.Name));
                return group!=0?group:StringComparer.CurrentCultureIgnoreCase.Compare(a.Name,b.Name);
            });
            var checks=new Dictionary<string,CheckBox>();
            var texts=new Dictionary<string,string>();
            var panel=(UniformGrid)window.FindName("Cards");
            foreach(var app in apps) {
                string method=app.Automatic?"Automatic · WinGet: "+string.Join(", ",app.Ids):"Guided · official website: "+app.Url;
                string help=app.Description+"\n"+app.Category+" · "+app.LicenseLabel+"\n"+method;
                if(app.AlsoIn.Length>0) help+="\nAlso in: "+string.Join(", ",app.AlsoIn);
                var card=Slot(window,app,help);
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
        // Called with each card once its inside has been built, so its labels can be translated.
        public static Action<CheckBox> Filled;
        // The app a slot stands for, until its content is built.
        static readonly DependencyProperty PendingProperty = DependencyProperty.RegisterAttached("Pending",typeof(CatalogCard),typeof(NativeUI));
        public static TextBlock Label(string text, double size, bool secondary) {
            var label = new TextBlock { Text = text, FontSize = size, TextWrapping = TextWrapping.Wrap };
            label.SetResourceReference(TextBlock.ForegroundProperty, secondary ? "TextSecondaryBrush" : "TextPrimaryBrush");
            return label;
        }
        // A card as the list first holds it: selectable, named for assistive tools, but empty.
        static CheckBox Slot(Window window, CatalogCard app, string help) {
            var card = new CheckBox { Style = (Style)window.Resources["CardCheck"], Tag = app.Key,
                Margin = new Thickness(4,0,4,8), Height = 140, MinHeight = 140, Template = EmptyCard };
            AutomationProperties.SetName(card,app.Name);
            AutomationProperties.SetHelpText(card,help);
            card.SetValue(PendingProperty,app);
            return card;
        }
        // The inside of a card, exactly as 3.6 builds it.
        static void Fill(CheckBox card) {
            var app=(CatalogCard)card.GetValue(PendingProperty);
            if(app==null) return;
            card.ClearValue(PendingProperty);
            var content=new StackPanel();
            var name=Label(app.Name,14,false);
            name.FontWeight=FontWeights.SemiBold; name.Height=36; name.LineHeight=18;
            name.LineStackingStrategy=LineStackingStrategy.BlockLineHeight;
            name.TextTrimming=TextTrimming.CharacterEllipsis; name.Margin=new Thickness(0,0,0,4);
            content.Children.Add(name);
            var cat=Label(app.Category,11,true); cat.TextWrapping=TextWrapping.NoWrap; cat.TextTrimming=TextTrimming.CharacterEllipsis;
            content.Children.Add(cat);
            var method=Label(app.Automatic?"WinGet · automatic":"Website · guided",11,true);
            method.TextWrapping=TextWrapping.NoWrap; method.TextTrimming=TextTrimming.CharacterEllipsis;
            method.Margin=new Thickness(0,4,0,0); content.Children.Add(method);
            var details=new Button { Content="Details", Tag=app.Key, Margin=new Thickness(0,8,0,0), Padding=new Thickness(6,4,6,4), MinHeight=28 };
            AutomationProperties.SetName(details,"Details for "+app.Name); content.Children.Add(details);
            card.Content=content;
            if(Filled!=null) Filled(card);
        }
        // Keep lightweight card slots for scrolling and keyboard navigation; construct
        // their content and visual templates only around the viewport. Selection persists.
        public static void Realize(UniformGrid panel, ScrollViewer scroll) {
            Realize(panel,scroll.ViewportWidth-8,scroll.ViewportHeight,scroll.VerticalOffset);
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
                if(visible) Fill(card);
                if(visible && card.ReadLocalValue(Control.TemplateProperty)==EmptyCard) card.ClearValue(Control.TemplateProperty);
                else if(!visible && card.ReadLocalValue(Control.TemplateProperty)!=EmptyCard) card.Template=EmptyCard;
            }
        }
    }
}
