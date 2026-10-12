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
    public sealed class ElasticFeel {
        public readonly double Stretch, Squash, Bounce;
        public readonly int Duration;
        public ElasticFeel(double stretch,double squash,double bounce,int duration) {
            if(double.IsNaN(stretch) || double.IsInfinity(stretch) || stretch<0 || double.IsNaN(squash) || squash<0 || squash>1 || double.IsNaN(bounce) || bounce<0 || bounce>1 || duration<=0) throw new ArgumentOutOfRangeException("feel");
            Stretch=stretch; Squash=squash; Bounce=bounce; Duration=duration;
        }
        public static readonly ElasticFeel Balanced=new ElasticFeel(.2,.1,.3,720);
        public static readonly ElasticFeel Firm=new ElasticFeel(0,0,0,220);
        public static readonly ElasticFeel Elastic=new ElasticFeel(1,.22,.8,1100);
    }
    public static class ElasticMotion {
        public struct Pose {
            public double X, Stretch, Height;
            public Pose(double x,double stretch,double height) { X=x; Stretch=stretch; Height=height; }
        }
        static double Response(double t,double bounce) {
            double damping=1-.8*bounce, w=10/damping;
            if(bounce==0) return 1-(1+w*t)*Math.Exp(-w*t);
            double wd=w*Math.Sqrt(1-damping*damping);
            return 1-Math.Exp(-damping*w*t)*(Math.Cos(wd*t)+damping*w/wd*Math.Sin(wd*t));
        }
        public static double Spring(double t,double bounce) {
            if(t<=0) return 0; if(t>=1) return 1;
            return Response(t,bounce)/Response(1,bounce);
        }
        static double Speed(double t,double bounce) {
            double lo=Math.Max(0,t-.0001), hi=Math.Min(1,t+.0001);
            return (Spring(hi,bounce)-Spring(lo,bounce))/(hi-lo);
        }
        static Pose Sample(Pose from,double target,ElasticFeel feel,double bounce,double peak,double length,double t) {
            if(t==0) return from;
            if(t==1) return new Pose(target,0,1);
            bool forward=target>=from.X+from.Stretch/2;
            double tail=forward?from.X:from.X+from.Stretch;
            double p=Spring(t,bounce), x=tail+(target-tail)*p;
            double amount=Math.Min(feel.Stretch*14,Math.Abs(target-tail)*.8);
            double stretch=amount*Math.Abs(Speed(t,bounce))/peak*length;
            double remaining=Math.Abs(target-x)*.6;
            // Smooth minimum rounds the landing without a second animation or a corner.
            double soft=stretch*remaining/Math.Sqrt(stretch*stretch+remaining*remaining+1e-12);
            stretch+=(soft-stretch)*Math.Max(0,1-feel.Bounce/.5);
            double rest=1-Spring(t,0);
            // An interrupted capsule hands its existing length over to the new flight.
            stretch=stretch*(1-Math.Min(1,from.Stretch/Math.Max(amount,.0001))*rest)+from.Stretch*rest;
            double height=1-feel.Squash*(amount>0?stretch/Math.Max(amount,from.Stretch):0)
                +feel.Squash*2*Math.Max(0,Spring(t,feel.Bounce)-1);
            height+=(from.Height-1+feel.Squash*(amount>0?from.Stretch/Math.Max(amount,from.Stretch):0))*rest;
            return new Pose(forward?x:x-stretch,stretch,Math.Max(.1,height));
        }
        public static Pose[] Flight(Pose from,double target,ElasticFeel feel) {
            double bounce=feel.Bounce, peak=1, length=1;
            // Check edges at a denser resolution than the compositor's keyframes.
            for(int attempt=0;attempt<100;attempt++) {
                peak=0;
                for(int i=0;i<=400;i++) peak=Math.Max(peak,Math.Abs(Speed(i/400.0,bounce)));
                bool fits=true;
                for(int i=0;i<=400;i++) {
                    var pose=Sample(from,target,feel,bounce,peak,length,i/400.0);
                    if(pose.X < -3.00001 || pose.X+pose.Stretch>19.00001) { fits=false; break; }
                }
                if(fits) break;
                if(bounce>0) bounce=Math.Max(0,bounce-.025);
                // Reversing an already long capsule can leave less room than a resting knob.
                else length*=.8;
            }
            var poses=new Pose[41];
            for(int i=0;i<poses.Length;i++) poses[i]=Sample(from,target,feel,bounce,peak,length,i/40.0);
            return poses;
        }
    }
    // A visual inside the existing CheckBox: its native keyboard, binding and UIA toggle stay intact.
    public sealed class ElasticSwitch : Grid {
        CheckBox owner;
        readonly TranslateTransform travel=new TranslateTransform(), end=new TranslateTransform();
        readonly ScaleTransform bridge=new ScaleTransform(0,1), squash=new ScaleTransform(1,1,0,7);
        readonly Border fill;
        Border selection;
        readonly Canvas ink;
        readonly DependencyPropertyDescriptor pressed=DependencyPropertyDescriptor.FromProperty(ButtonBase.IsPressedProperty,typeof(CheckBox));
        bool connected, settlePending;
        double pressAmount=.83;
        public bool PressFeedback { get; set; }
        public double PressAmount { get { return pressAmount; } set { if(double.IsNaN(value) || value<0 || value>1) throw new ArgumentOutOfRangeException("value"); pressAmount=value; } }
        public ElasticFeel Feel { get; set; }
        public event EventHandler Changed;
        public event EventHandler Settled;
        public ElasticMotion.Pose CurrentPose { get { return new ElasticMotion.Pose(travel.X,end.X,squash.ScaleY); } }
        public ElasticSwitch() {
            Feel=ElasticFeel.Balanced; PressFeedback=true;
            Width=38; Height=22; IsHitTestVisible=false;
            Clip=new RectangleGeometry(new Rect(0,0,38,22),11,11);
            var field=new Border { CornerRadius=new CornerRadius(11) }; field.SetResourceReference(Border.BackgroundProperty,"InputFill"); Children.Add(field);
            fill=new Border { CornerRadius=new CornerRadius(11) }; fill.SetResourceReference(Border.BackgroundProperty,"TextPrimaryBrush"); Children.Add(fill);
            var knob=new Canvas { Width=14,Height=14,HorizontalAlignment=HorizontalAlignment.Left,VerticalAlignment=VerticalAlignment.Top,Margin=new Thickness(4,4,0,0) };
            var transforms=new TransformGroup(); transforms.Children.Add(squash); transforms.Children.Add(travel); knob.RenderTransform=transforms;
            knob.Children.Add(ShapeLayer("TextSecondaryBrush")); ink=ShapeLayer("TextPrimaryBrush"); knob.Children.Add(ink); Children.Add(knob);
            var ring=new Border { CornerRadius=new CornerRadius(11),BorderThickness=new Thickness(1) }; ring.SetResourceReference(Border.BorderBrushProperty,"CheckBorderBrush"); Children.Add(ring);
            Loaded+=Connect; Unloaded+=Disconnect;
        }
        Canvas ShapeLayer(string token) {
            var layer=new Canvas { Width=14,Height=14 };
            var bar=new Rectangle { Width=14,Height=14,RenderTransform=bridge }; Canvas.SetLeft(bar,7);
            var near=new Ellipse { Width=14,Height=14 };
            var far=new Ellipse { Width=14,Height=14,RenderTransform=end };
            foreach(var shape in new Shape[] { bar,near,far }) { shape.SetResourceReference(Shape.FillProperty,token); layer.Children.Add(shape); }
            return layer;
        }
        void Connect(object sender,RoutedEventArgs e) {
            if(connected) return;
            owner=TemplatedParent as CheckBox;
            if(owner==null) return;
            connected=true;
            selection=owner.Template.FindName("CardSelection",owner) as Border;
            owner.Checked+=Change; owner.Unchecked+=Change; pressed.AddValueChanged(owner,Press);
            Place();
        }
        void Disconnect(object sender,RoutedEventArgs e) {
            if(!connected) return; connected=false;
            owner.Checked-=Change; owner.Unchecked-=Change; pressed.RemoveValueChanged(owner,Press);
            settlePending=false; Place();
        }
        void Place() {
            Motion.Cancel(travel,TranslateTransform.XProperty); Motion.Cancel(end,TranslateTransform.XProperty);
            Motion.Cancel(bridge,ScaleTransform.ScaleXProperty); Motion.Cancel(squash,ScaleTransform.ScaleYProperty);
            Motion.Cancel(fill,OpacityProperty); Motion.Cancel(ink,OpacityProperty);
            if(selection!=null) { Motion.Cancel(selection,OpacityProperty); selection.Opacity=owner.IsChecked==true?1:0; }
            travel.X=owner.IsChecked==true?16:0; end.X=0; bridge.ScaleX=0; squash.ScaleY=1;
            fill.Opacity=owner.IsChecked==true?.26:0; ink.Opacity=owner.IsChecked==true?1:0;
        }
        void Change(object sender,RoutedEventArgs e) {
            if(e.OriginalSource!=owner) return;
            settlePending=true;
            double on=owner.IsChecked==true?1:0;
            Motion.Animate(fill,OpacityProperty,new double[] { fill.Opacity,on*.26 },180,null);
            Motion.Animate(ink,OpacityProperty,new double[] { ink.Opacity,on },180,null);
            if(selection!=null) Motion.Animate(selection,OpacityProperty,new double[] { selection.Opacity,on },180,null);
            bool reduced=!Motion.Enabled;
            Fly(on*16,!reduced);
            if(Changed!=null) Changed(this,EventArgs.Empty);
            if(reduced) Finish();
        }
        void Finish() { if(!settlePending) return; settlePending=false; if(Settled!=null) Settled(this,EventArgs.Empty); }
        internal void Settle() { if(owner!=null) { Place(); Finish(); } }
        void Fly(double target,bool notify) {
            var poses=Motion.Enabled?ElasticMotion.Flight(CurrentPose,target,Feel ?? ElasticFeel.Balanced):new[] { CurrentPose,new ElasticMotion.Pose(target,0,1) };
            var x=new double[poses.Length]; var extension=new double[x.Length]; var bar=new double[x.Length]; var y=new double[x.Length];
            for(int i=0;i<x.Length;i++) { x[i]=poses[i].X; extension[i]=poses[i].Stretch; bar[i]=extension[i]/14; y[i]=poses[i].Height; }
            int duration=(Feel ?? ElasticFeel.Balanced).Duration;
            Motion.Animate(travel,TranslateTransform.XProperty,x,duration,null);
            Motion.Animate(end,TranslateTransform.XProperty,extension,duration,null);
            Motion.Animate(bridge,ScaleTransform.ScaleXProperty,bar,duration,null);
            Motion.Animate(squash,ScaleTransform.ScaleYProperty,y,duration,notify?(Action)Finish:null);
        }
        void Press(object sender,EventArgs e) {
            if(!owner.IsPressed) { Fly(owner.IsChecked==true?16:0,settlePending); return; }
            if(!PressFeedback || !Motion.Enabled) return;
            double rest=owner.IsChecked==true?16:0, direction=owner.IsChecked==true?-1:1;
            Motion.Animate(travel,TranslateTransform.XProperty,new double[] { travel.X,rest+direction*2*pressAmount },150,null);
            Motion.Animate(end,TranslateTransform.XProperty,new double[] { end.X,0 },150,null);
            Motion.Animate(bridge,ScaleTransform.ScaleXProperty,new double[] { bridge.ScaleX,0 },150,null);
            Motion.Animate(squash,ScaleTransform.ScaleYProperty,new double[] { squash.ScaleY,1-.06*pressAmount },150,null);
        }
    }
    // One native motion vocabulary. State changes never wait for decoration.
    public static class Motion {
        static Window main;
        static Canvas overlay;
        static bool registered;
        public static bool? TestOverride;
        public static bool Enabled { get { return TestOverride ?? (SystemParameters.ClientAreaAnimation && !SystemParameters.HighContrast); } }
        sealed class Track { public DependencyObject Target; public DependencyProperty Property; public AnimationClock Clock; public Action Settled; public double? End; }
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
        internal static void Cancel(DependencyObject target,DependencyProperty property) {
            for(int i=tracks.Count-1;i>=0;i--) if(tracks[i].Target==target && tracks[i].Property==property) tracks.RemoveAt(i);
            Apply(target,property,null);
        }
        internal static void Animate(DependencyObject target,DependencyProperty property,double[] values,int duration,Action settled) {
            Cancel(target,property);
            if(!Enabled) { target.SetValue(property,values[values.Length-1]); if(settled!=null) settled(); return; }
            // Before WPF's first clock tick, a second input must still read the visible pose.
            target.SetValue(property,values[0]);
            var animation=new DoubleAnimationUsingKeyFrames { FillBehavior=FillBehavior.Stop };
            for(int i=0;i<values.Length;i++) animation.KeyFrames.Add(new LinearDoubleKeyFrame(values[i],KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(duration*(double)i/(values.Length-1)))));
            var clock=animation.CreateClock();
            var track=new Track { Target=target,Property=property,Clock=clock,Settled=settled,End=values[values.Length-1] }; tracks.Add(track);
            clock.Completed+=delegate { if(tracks.Remove(track)) { target.SetValue(property,track.End.Value); Apply(target,property,null); if(settled!=null) settled(); } };
            Apply(target,property,clock);
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
            double x=scale.HasAnimatedProperties?scale.ScaleX:.973, y=scale.HasAnimatedProperties?scale.ScaleY:.973;
            var xs=new double[41]; var ys=new double[41];
            for(int i=0;i<xs.Length;i++) { double p=ElasticMotion.Spring(i/40.0,.3); xs[i]=x+(1-x)*p; ys[i]=y+(1-y)*p; }
            Animate(scale,ScaleTransform.ScaleXProperty,xs,300,null);
            Animate(scale,ScaleTransform.ScaleYProperty,ys,300,null);
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
            // Layout commits once; only the revealed content moves and fades.
            if(expander.IsExpanded) Enter(site,0,-4,0);
        }
        static void PreferencesChanged(object sender,PropertyChangedEventArgs e) {
            if(main!=null) main.Dispatcher.BeginInvoke(new Action(delegate { if(!Enabled) Stop(); }));
        }
        static void SettleTree(DependencyObject root) {
            var toggle=root as ElasticSwitch;
            if(toggle!=null) toggle.Settle();
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
            var stopped=tracks.ToArray();
            foreach(var track in stopped) { if(track.End.HasValue) track.Target.SetValue(track.Property,track.End.Value); Apply(track.Target,track.Property,null); }
            tracks.Clear();
            if(main!=null) SettleTree(main);
            if(overlay!=null) overlay.Children.Clear();
            foreach(var track in stopped) if(track.Settled!=null) track.Settled();
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
            int phase=status.StartsWith("Preparing")?0:status.StartsWith("Installing")||status.StartsWith("Removing")?1:status.StartsWith("Verifying")?2:status=="Success"?3:-1;
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
