using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace OneInstall {
    // One native motion vocabulary. State changes never wait for decoration.
    public static class Motion {
        static Window main;
        static Canvas overlay;
        static bool registered;
        public static bool? TestOverride;
        public static bool Enabled { get { return TestOverride ?? (SystemParameters.ClientAreaAnimation && !SystemParameters.HighContrast); } }
        sealed class Track { public DependencyObject Target; public DependencyProperty Property; public AnimationClock Clock; }
        static readonly List<Track> tracks = new List<Track>();
        public static int ActiveAnimations { get { return tracks.Count; } }
        public static int Decorations { get { return overlay == null ? 0 : overlay.Children.Count; } }
        static readonly DependencyProperty TransformProperty = DependencyProperty.RegisterAttached("MotionTransform", typeof(TransformGroup), typeof(Motion));
        static TransformGroup Transform(FrameworkElement element) {
            var group = (TransformGroup)element.GetValue(TransformProperty);
            if (group == null || element.RenderTransform != group) {
                group = new TransformGroup();
                group.Children.Add(new ScaleTransform(1,1));
                group.Children.Add(new TranslateTransform());
                element.SetValue(TransformProperty,group);
                element.RenderTransformOrigin = new Point(.5,.5);
                element.RenderTransform = group;
            }
            return group;
        }
        public static void Value(Animatable target, DependencyProperty property, double from, double to, int duration, int delay) {
            Start(target,property,from,to,duration,delay,null);
        }
        static void Apply(DependencyObject target,DependencyProperty property,AnimationClock clock) {
            var visual=target as UIElement;
            if(visual!=null) visual.ApplyAnimationClock(property,clock,HandoffBehavior.SnapshotAndReplace);
            else ((Animatable)target).ApplyAnimationClock(property,clock,HandoffBehavior.SnapshotAndReplace);
        }
        static void Cancel(DependencyObject target,DependencyProperty property) {
            for(int i=tracks.Count-1;i>=0;i--) if(tracks[i].Target==target && tracks[i].Property==property) tracks.RemoveAt(i);
            Apply(target,property,null);
        }
        static void Opacity(FrameworkElement element, double from, int duration, int delay) {
            Start(element,UIElement.OpacityProperty,element.IsVisible?from:1,1,duration,delay,null);
        }
        static DoubleAnimationUsingKeyFrames Frames(double from,double to,int duration,int delay,double? overshoot) {
            var animation=new DoubleAnimationUsingKeyFrames { FillBehavior=FillBehavior.Stop };
            animation.KeyFrames.Add(new DiscreteDoubleKeyFrame(from,KeyTime.FromTimeSpan(TimeSpan.Zero)));
            if(delay>0) animation.KeyFrames.Add(new DiscreteDoubleKeyFrame(from,KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(delay))));
            var ease=new CubicEase { EasingMode=EasingMode.EaseOut };
            if(overshoot.HasValue) animation.KeyFrames.Add(new EasingDoubleKeyFrame(overshoot.Value,KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(delay+duration*.58)),ease));
            animation.KeyFrames.Add(new EasingDoubleKeyFrame(to,KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(delay+duration)),ease));
            return animation;
        }
        static void Start(DependencyObject target,DependencyProperty property,double from,double to,int duration,int delay,double? overshoot) {
            Cancel(target,property); target.SetValue(property,to);
            if(!Enabled || Math.Abs(from-to)<.0001 && !overshoot.HasValue) return;
            var clock=Frames(from,to,duration,delay,overshoot).CreateClock();
            var track=new Track { Target=target,Property=property,Clock=clock }; tracks.Add(track);
            clock.Completed+=delegate {
                // A later interaction owns this property; never clear its newer clock.
                if(tracks.Remove(track)) Apply(target,property,null);
            };
            Apply(target,property,clock);
        }
        public static void Enter(FrameworkElement element,double x,double y,int delay) {
            if(element==null) return;
            var popup=element as Control;
            if(popup is ToolTip || popup is ContextMenu) {
                popup.ApplyTemplate();
                element=popup.Template.FindName("MotionSurface",popup) as FrameworkElement ?? element;
            }
            var move=(TranslateTransform)Transform(element).Children[1];
            bool running=move.HasAnimatedProperties;
            Value(move,TranslateTransform.XProperty,running?move.X:x,0,300,delay);
            Value(move,TranslateTransform.YProperty,running?move.Y:y,0,300,delay);
            Opacity(element,element.HasAnimatedProperties?element.Opacity:.18,260,delay);
        }
        public static void Reflow(FrameworkElement element,double x,double y) {
            var move=(TranslateTransform)Transform(element).Children[1];
            Value(move,TranslateTransform.XProperty,x,0,240,0);
            Value(move,TranslateTransform.YProperty,y,0,240,0);
        }
        public static void Pop(FrameworkElement element) {
            if(element==null) return;
            Cancel(element,UIElement.OpacityProperty); element.Opacity=1;
            var scale=(ScaleTransform)Transform(element).Children[0];
            Start(scale,ScaleTransform.ScaleXProperty,scale.HasAnimatedProperties?scale.ScaleX:.973,1,300,0,1.012);
            Start(scale,ScaleTransform.ScaleYProperty,scale.HasAnimatedProperties?scale.ScaleY:.973,1,300,0,1.012);
        }
        public static void Hover(FrameworkElement element,bool over) {
            if(element==null) return;
            var popup=element as Control;
            if(popup is ToolTip || popup is ContextMenu) {
                popup.ApplyTemplate();
                element=popup.Template.FindName("MotionSurface",popup) as FrameworkElement ?? element;
            }
            var move=(TranslateTransform)Transform(element).Children[1];
            Value(move,TranslateTransform.YProperty,move.Y,over && Enabled?-1.5:0,140,0);
        }
        static FrameworkElement Surface(ButtonBase button) {
            button.ApplyTemplate();
            return button.Template==null?button:(button.Template.FindName("Card",button) as FrameworkElement ?? button);
        }
        public static void Initialize(Window window) {
            main=window; overlay=(Canvas)window.FindName("MotionOverlay");
            SystemParameters.StaticPropertyChanged+=PreferencesChanged;
            window.Closed+=delegate { Stop(); SystemParameters.StaticPropertyChanged-=PreferencesChanged; main=null; overlay=null; };
            if(registered) return;
            registered=true;
            EventManager.RegisterClassHandler(typeof(ButtonBase),UIElement.MouseEnterEvent,new MouseEventHandler(delegate(object sender,MouseEventArgs e) {
                var button=(ButtonBase)sender; if(button.IsEnabled) Hover(Surface(button),true);
            }));
            EventManager.RegisterClassHandler(typeof(ButtonBase),UIElement.MouseLeaveEvent,new MouseEventHandler(delegate(object sender,MouseEventArgs e) { Hover(Surface((ButtonBase)sender),false); }));
            EventManager.RegisterClassHandler(typeof(ButtonBase),UIElement.PreviewMouseLeftButtonDownEvent,new MouseButtonEventHandler(delegate(object sender,MouseButtonEventArgs e) {
                var button=(ButtonBase)sender;
                if(!button.IsEnabled) return;
                var scale=(ScaleTransform)Transform(Surface(button)).Children[0];
                Value(scale,ScaleTransform.ScaleXProperty,scale.ScaleX,Enabled?.98:1,90,0);
                Value(scale,ScaleTransform.ScaleYProperty,scale.ScaleY,Enabled?.98:1,90,0);
            }),true);
            EventManager.RegisterClassHandler(typeof(ButtonBase),UIElement.PreviewMouseLeftButtonUpEvent,new MouseButtonEventHandler(delegate(object sender,MouseButtonEventArgs e) { Pop(Surface((ButtonBase)sender)); }),true);
            EventManager.RegisterClassHandler(typeof(ButtonBase),UIElement.LostMouseCaptureEvent,new MouseEventHandler(delegate(object sender,MouseEventArgs e) { Pop(Surface((ButtonBase)sender)); }),true);
            EventManager.RegisterClassHandler(typeof(ButtonBase),ButtonBase.ClickEvent,new RoutedEventHandler(delegate(object sender,RoutedEventArgs e) { Pop(Surface((ButtonBase)sender)); }),true);
            EventManager.RegisterClassHandler(typeof(Expander),Expander.ExpandedEvent,new RoutedEventHandler(Expand),true);
            EventManager.RegisterClassHandler(typeof(Expander),Expander.CollapsedEvent,new RoutedEventHandler(Expand),true);
            EventManager.RegisterClassHandler(typeof(ContextMenu),ContextMenu.OpenedEvent,new RoutedEventHandler(delegate(object sender,RoutedEventArgs e) { Enter((FrameworkElement)sender,0,6,0); }));
            EventManager.RegisterClassHandler(typeof(ToolTip),ToolTip.OpenedEvent,new RoutedEventHandler(delegate(object sender,RoutedEventArgs e) { Enter((FrameworkElement)sender,0,3,0); }));
            EventManager.RegisterClassHandler(typeof(Window),FrameworkElement.LoadedEvent,new RoutedEventHandler(delegate(object sender,RoutedEventArgs e) {
                var dialog=(Window)sender; if(dialog!=main && dialog.Owner==main) Enter(dialog.Content as FrameworkElement,0,10,0);
            }));
            EventManager.RegisterClassHandler(typeof(ComboBox),FrameworkElement.LoadedEvent,new RoutedEventHandler(delegate(object sender,RoutedEventArgs e) {
                var combo=(ComboBox)sender; combo.DropDownOpened-=ComboOpened; combo.DropDownOpened+=ComboOpened;
            }));
        }
        static void ComboOpened(object sender,EventArgs e) {
            var combo=(ComboBox)sender;
            var popup=combo.Template.FindName("PART_Popup",combo) as Popup;
            if(popup!=null) Enter(combo.Template.FindName("MotionSurface",combo) as FrameworkElement,0,5,0);
        }
        static void Expand(object sender,RoutedEventArgs e) {
            var expander=(Expander)sender; expander.ApplyTemplate();
            var site=expander.Template.FindName("ExpandSite",expander) as FrameworkElement;
            if(site==null) return;
            site.ClipToBounds=true;
            double current=site.ActualHeight;
            site.BeginAnimation(FrameworkElement.HeightProperty,null);
            site.ClearValue(UIElement.VisibilityProperty); site.Height=double.NaN;
            if(!Enabled) return;
            site.Visibility=Visibility.Visible;
            site.Measure(new Size(Math.Max(1,expander.ActualWidth),double.PositiveInfinity));
            double height=Math.Max(0,site.DesiredSize.Height-site.Margin.Top-site.Margin.Bottom);
            if(expander.IsExpanded) Enter(site,0,-4,0);
            var animation=new DoubleAnimation(current,expander.IsExpanded?height:0,TimeSpan.FromMilliseconds(220)) { EasingFunction=new CubicEase { EasingMode=EasingMode.EaseOut },FillBehavior=FillBehavior.Stop };
            animation.Completed+=delegate { site.ClearValue(UIElement.VisibilityProperty); site.BeginAnimation(FrameworkElement.HeightProperty,null); };
            site.BeginAnimation(FrameworkElement.HeightProperty,animation,HandoffBehavior.SnapshotAndReplace);
        }
        static void PreferencesChanged(object sender,PropertyChangedEventArgs e) {
            if(main!=null) main.Dispatcher.BeginInvoke(new Action(delegate { if(!Enabled) Stop(); }));
        }
        static void SettleTree(DependencyObject root) {
            var element=root as FrameworkElement;
            if(element!=null) {
                element.BeginAnimation(UIElement.OpacityProperty,null);
                var group=element.GetValue(TransformProperty) as TransformGroup;
                if(group!=null) {
                    var scale=(ScaleTransform)group.Children[0]; var move=(TranslateTransform)group.Children[1];
                    scale.BeginAnimation(ScaleTransform.ScaleXProperty,null); scale.BeginAnimation(ScaleTransform.ScaleYProperty,null); scale.ScaleX=scale.ScaleY=1;
                    move.BeginAnimation(TranslateTransform.XProperty,null); move.BeginAnimation(TranslateTransform.YProperty,null); move.X=move.Y=0;
                }
                if(element.Name=="ExpandSite") { element.BeginAnimation(FrameworkElement.HeightProperty,null); element.ClearValue(UIElement.VisibilityProperty); }
            }
            for(int i=0;i<VisualTreeHelper.GetChildrenCount(root);i++) SettleTree(VisualTreeHelper.GetChild(root,i));
        }
        public static void Stop() {
            foreach(var track in tracks.ToArray()) Apply(track.Target,track.Property,null);
            tracks.Clear();
            if(main!=null) SettleTree(main);
            if(overlay!=null) overlay.Children.Clear();
        }
        public static void ClearDecorations() { if(overlay!=null) overlay.Children.Clear(); }
        static bool PointOnScreen(FrameworkElement element,out Point point) {
            point=new Point();
            if(element==null || !element.IsVisible || overlay==null || PresentationSource.FromVisual(element)!=PresentationSource.FromVisual(overlay)) return false;
            point=element.TranslatePoint(new Point(element.ActualWidth/2,element.ActualHeight/2),overlay);
            // Do not fly from cards outside a scrolling viewport.
            DependencyObject parent=element;
            while(parent!=null && parent!=main) {
                var scroll=parent as ScrollViewer;
                if(scroll!=null) {
                    var p=overlay.TranslatePoint(point,scroll);
                    if(p.X<0 || p.Y<0 || p.X>scroll.ActualWidth || p.Y>scroll.ActualHeight) return false;
                }
                parent=VisualTreeHelper.GetParent(parent);
            }
            return true;
        }
        static void Expire(FrameworkElement decoration,int milliseconds) {
            Cancel(decoration,UIElement.OpacityProperty);
            var fade=new DoubleAnimationUsingKeyFrames { FillBehavior=FillBehavior.Stop };
            fade.KeyFrames.Add(new DiscreteDoubleKeyFrame(.9,KeyTime.FromTimeSpan(TimeSpan.Zero)));
            fade.KeyFrames.Add(new EasingDoubleKeyFrame(0,KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(milliseconds)),new CubicEase { EasingMode=EasingMode.EaseIn }));
            fade.Completed+=delegate { if(overlay!=null) overlay.Children.Remove(decoration); };
            decoration.BeginAnimation(UIElement.OpacityProperty,fade);
        }
        public static void Fly(FrameworkElement source,FrameworkElement destination,string title) {
            Point from,to;
            if(!Enabled || !PointOnScreen(source,out from) || !PointOnScreen(destination,out to)) return;
            // Latest intent wins, including a quick deselect of the same app.
            foreach(FrameworkElement child in new List<FrameworkElement>(Children())) if(object.Equals(child.Tag,title)) overlay.Children.Remove(child);
            if(overlay.Children.Count>=8) overlay.Children.RemoveAt(0);
            var capsule=new Border { Width=112,Height=36,CornerRadius=new CornerRadius(18),Padding=new Thickness(10,0,10,0),BorderThickness=new Thickness(1),Tag=title,IsHitTestVisible=false };
            capsule.SetResourceReference(Border.BackgroundProperty,"GlassMenuFill"); capsule.SetResourceReference(Border.BorderBrushProperty,"GlassEdge");
            var label=new TextBlock { Text=title,FontSize=11,FontWeight=FontWeights.SemiBold,VerticalAlignment=VerticalAlignment.Center,TextTrimming=TextTrimming.CharacterEllipsis };
            label.SetResourceReference(TextBlock.ForegroundProperty,"TextPrimaryBrush"); capsule.Child=label;
            Canvas.SetLeft(capsule,from.X-56); Canvas.SetTop(capsule,from.Y-18); overlay.Children.Add(capsule);
            var move=(TranslateTransform)Transform(capsule).Children[1];
            Value(move,TranslateTransform.XProperty,0,to.X-from.X,440,0);
            Start(move,TranslateTransform.YProperty,0,to.Y-from.Y,440,0,Math.Min(-24,to.Y-from.Y-24));
            Expire(capsule,460);
        }
        static IEnumerable<FrameworkElement> Children() { foreach(FrameworkElement child in overlay.Children) yield return child; }
        public static void Confirm() {
            if(!Enabled || overlay==null || main==null) return;
            // Reuse one pulse for closely spaced results instead of stacking flashes.
            foreach(FrameworkElement child in new List<FrameworkElement>(Children()))
                if(object.Equals(child.Tag,"ConfirmationGlow")) { Cancel(child,UIElement.OpacityProperty); overlay.Children.Remove(child); }
            var glow=new Border { Tag="ConfirmationGlow",CornerRadius=new CornerRadius(25),BorderThickness=new Thickness(2),IsHitTestVisible=false,Opacity=0 };
            glow.SetResourceReference(Border.BackgroundProperty,"ConfirmationFill");
            glow.SetResourceReference(Border.BorderBrushProperty,"AccentBrush");
            glow.SetBinding(FrameworkElement.WidthProperty,new System.Windows.Data.Binding("ActualWidth") { Source=overlay });
            glow.SetBinding(FrameworkElement.HeightProperty,new System.Windows.Data.Binding("ActualHeight") { Source=overlay });
            overlay.Children.Add(glow);
            Start(glow,UIElement.OpacityProperty,0,0,1100,0,.8);
            var clock=tracks[tracks.Count-1].Clock;
            clock.Completed+=delegate { if(overlay!=null) overlay.Children.Remove(glow); };
        }
        public static void Result(FrameworkElement target,bool success) {
            if(target==null) return;
            Enter(target,0,3,0);
            if(success) Confirm();
            Point point;
            if(!success || !Enabled || !PointOnScreen(target,out point)) return;
            var ring=new Ellipse { Width=46,Height=46,StrokeThickness=1.5,IsHitTestVisible=false };
            ring.SetResourceReference(Shape.StrokeProperty,"AccentBrush");
            Canvas.SetLeft(ring,point.X-23); Canvas.SetTop(ring,point.Y-23); overlay.Children.Add(ring);
            var scale=(ScaleTransform)Transform(ring).Children[0];
            Value(scale,ScaleTransform.ScaleXProperty,.65,2.4,620,0); Value(scale,ScaleTransform.ScaleYProperty,.65,2.4,620,0); Expire(ring,640);
            var check=new Path { Data=Geometry.Parse("M 0,5 L 4,9 12,0"),StrokeThickness=2,Width=12,Height=10,IsHitTestVisible=false };
            check.SetResourceReference(Shape.StrokeProperty,"TextPrimaryBrush");
            Canvas.SetLeft(check,point.X-6); Canvas.SetTop(check,point.Y-26); overlay.Children.Add(check);
            Enter(check,0,4,0); Expire(check,640);
            Pop(target);
        }
        public static void Phase(TextBlock label,string status) {
            var panel=label==null?null:label.Parent as StackPanel;
            if(panel==null) return;
            var stages=label.Tag as UniformGrid;
            int phase=status.StartsWith("Preparing")?0:status.StartsWith("Installing")?1:status.StartsWith("Verifying")?2:status=="Success"?3:-1;
            if(stages==null && phase>=0) {
                stages=new UniformGrid { Columns=3,Width=72,Height=3,HorizontalAlignment=HorizontalAlignment.Left,Margin=new Thickness(0,7,0,0),IsHitTestVisible=false };
                for(int i=0;i<3;i++) {
                    var segment=new Border { CornerRadius=new CornerRadius(1.5),Margin=new Thickness(0,0,3,0) };
                    segment.SetResourceReference(Border.BackgroundProperty,"AccentBrush"); stages.Children.Add(segment);
                }
                label.Tag=stages; panel.Children.Add(stages);
            }
            if(stages==null) return;
            stages.Visibility=phase<0?Visibility.Collapsed:Visibility.Visible;
            for(int i=0;i<3;i++) {
                var segment=(Border)stages.Children[i]; double before=segment.Opacity;
                double target=i<=phase?1:.18;
                Start(segment,UIElement.OpacityProperty,segment.IsVisible?before:target,target,180,0,null);
            }
        }
        public static void Opening(Window window) {
            if(!Enabled) { Stop(); return; }
            Enter(window.FindName("NavigationGlass") as FrameworkElement,-12,0,0);
            Enter(window.FindName("SetupGlass") as FrameworkElement,12,0,90);
            Enter(window.FindName("InstallToolbar") as FrameworkElement,0,8,70);
            Enter(window.FindName("InstallSearchRow") as FrameworkElement,0,8,105);
            Enter(window.FindName("InstallActivity") as FrameworkElement,0,5,170);
            var logo=window.FindName("BrandLogo") as FrameworkElement;
            if(logo==null || overlay==null) return;
            var symbol=new Image { Source=(ImageSource)window.Resources["BrandSymbol"],Width=64,Height=64,IsHitTestVisible=false };
            Canvas.SetLeft(symbol,overlay.ActualWidth/2-32); Canvas.SetTop(symbol,overlay.ActualHeight/2-32); overlay.Children.Add(symbol);
            var point=logo.TranslatePoint(new Point(logo.ActualWidth/2,logo.ActualHeight/2),overlay);
            var transform=Transform(symbol); var move=(TranslateTransform)transform.Children[1]; var scale=(ScaleTransform)transform.Children[0];
            Value(move,TranslateTransform.XProperty,0,point.X-overlay.ActualWidth/2,480,0);
            Value(move,TranslateTransform.YProperty,0,point.Y-overlay.ActualHeight/2,480,0);
            Value(scale,ScaleTransform.ScaleXProperty,1,.5,480,0); Value(scale,ScaleTransform.ScaleYProperty,1,.5,480,0);
            Opacity(logo,0,100,380); Expire(symbol,510);
        }
    }
}
