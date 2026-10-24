using System.Windows;
using System.Windows.Media;
using PigPendant.Core;
using Point = System.Windows.Point;
using Rect = System.Windows.Rect;
using Brushes = System.Windows.Media.Brushes;
using Pen = System.Windows.Media.Pen;
using Color = System.Windows.Media.Color;

namespace PigPendant.Windows;

internal sealed class OverlayWindow : Window
{
    private readonly System.Drawing.Rectangle bounds;
    private readonly Artwork artwork;
    private PendantSimulation simulation;
    public OverlayWindow(System.Drawing.Rectangle bounds, Artwork artwork, PendantSimulation simulation)
    {
        this.bounds = bounds;
        this.artwork = artwork;
        this.simulation = simulation;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Focusable = false;
        Topmost = true;
        Left = bounds.Left; Top = bounds.Top;
        Width = bounds.Width; Height = bounds.Height;
        SourceInitialized += (_, _) => Native.ConfigureOverlay(this, bounds);
    }
    public void Refresh(PendantSimulation state) { simulation = state; InvalidateVisual(); }
    private Point P(Vec p, double scaleX, double scaleY) => new((p.X - bounds.Left) * scaleX, (-p.Y - bounds.Top) * scaleY);
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        if (!simulation.Settings.Visible) return;
        var source = PresentationSource.FromVisual(this);
        if (source?.CompositionTarget is null) return;
        var transform = source.CompositionTarget.TransformFromDevice;
        var sx = transform.M11; var sy = transform.M22;
        var mode = simulation.Settings.Mode;
        var image = artwork.Get(mode, simulation.AnimationTime);
        var size = simulation.Settings.Get(Parameter.Size);
        if (mode == DisplayMode.Ghost)
        {
            var center = P(simulation.GhostPosition, sx, sy);
            var width = size * sx; var height = size * image.PixelHeight / image.PixelWidth * sy;
            dc.DrawImage(image, new Rect(center.X - width / 2, center.Y - height / 2, width, height));
            return;
        }
        if (mode == DisplayMode.Bamboo)
        {
            DrawBamboo(dc, image, sx, sy, size);
            return;
        }
        var ropes = simulation.ActiveRopes.ToArray();
        for (var r = 0; r < ropes.Length; r++)
        {
            var rope = ropes[r];
            var geometry = new StreamGeometry();
            using (var context = geometry.Open())
            {
                context.BeginFigure(P(rope.Nodes[0], sx, sy), false, false);
                for (var i = 1; i < rope.Nodes.Length - 1; i++)
                    context.QuadraticBezierTo(P(rope.Nodes[i], sx, sy), P((rope.Nodes[i] + rope.Nodes[i + 1]) * .5, sx, sy), true, false);
                context.QuadraticBezierTo(P(rope.Nodes[^1], sx, sy), P(rope.Nodes[^1], sx, sy), true, false);
            }
            geometry.Freeze();
            dc.DrawGeometry(null, new Pen(new SolidColorBrush(Color.FromArgb(245, 70, 70, 70)), mode == DisplayMode.Balloon ? 1.2 : 1.6) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, geometry);
        }
        for (var r = 0; r < ropes.Length; r++)
        {
            var rope = ropes[r];
            var bob = P(rope.EndPoint, sx, sy);
            var width = (mode == DisplayMode.Balloon ? simulation.BalloonWidth(r) : size) * sx;
            var height = width * image.PixelHeight / image.PixelWidth * sy / sx;
            dc.PushTransform(new RotateTransform((mode == DisplayMode.Balloon ? -.45 : .70) * rope.EndAngle * 180 / Math.PI, bob.X, bob.Y));
            if (mode == DisplayMode.Balloon)
            {
                var knot = Math.Clamp(width * .07, 2, 7);
                dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(245, 145, 168)), null,
                    new Rect(bob.X - knot * .3, bob.Y - knot * 1.45, knot * .6, knot * 1.5), knot * .3, knot * .3);
                dc.DrawImage(image, new Rect(bob.X - width / 2, bob.Y - height - knot, width, height));
            }
            else if (mode == DisplayMode.Net)
                dc.DrawImage(image, new Rect(bob.X - width * 140 / 207, bob.Y, width, height));
            else if (mode == DisplayMode.Hanging)
                dc.DrawImage(image, new Rect(bob.X - width / 2, bob.Y - 6 * sy, width, height));
            else
                dc.DrawImage(image, new Rect(bob.X - width / 2, bob.Y - height / 2, width, height));
            dc.Pop();
        }
    }
    private void DrawBamboo(DrawingContext dc, System.Windows.Media.Imaging.BitmapSource image, double sx, double sy, double width)
    {
        var length = Math.Max(width * 1.5, simulation.Rope.CurrentLength);
        var progress = simulation.BambooProgress;
        var angle = -Math.PI / 2 * progress * progress * (3 - 2 * progress) + simulation.BambooSway;
        var turn = Math.PI / 2 * progress * progress * (3 - 2 * progress);
        var sway = simulation.BambooSway;
        var root = simulation.Rope.Nodes[0];
        var rootDirection = new Vec(Math.Cos(sway), Math.Sin(sway));
        var rootNormal = new Vec(-Math.Sin(sway), Math.Cos(sway));
        var horizontal = turn > .0001 ? length * Math.Sin(turn) / turn : length;
        var vertical = turn > .0001 ? length * (Math.Cos(turn) - 1) / turn : 0;
        var tip = root + rootDirection * horizontal + rootNormal * vertical;
        var handle = turn > .0001 ? length / turn * 4 / 3 * Math.Tan(turn / 4) : length / 3;
        var first = root + rootDirection * handle;
        var second = tip - new Vec(Math.Cos(angle), Math.Sin(angle)) * handle;
        var points = new Vec[25];
        for (var i = 0; i < points.Length; i++)
        {
            var t = i / 24.0; var q = 1 - t;
            points[i] = root * (q * q * q) + first * (3 * q * q * t) + second * (3 * q * t * t) + tip * (t * t * t);
        }
        var line = new StreamGeometry();
        using (var g = line.Open())
        {
            g.BeginFigure(P(points[0], sx, sy), false, false);
            for (var i = 1; i < points.Length - 1; i++)
                g.QuadraticBezierTo(P(points[i], sx, sy), P((points[i] + points[i + 1]) * .5, sx, sy), true, false);
            g.LineTo(P(tip, sx, sy), true, false);
        }
        line.Freeze();
        var thickness = Math.Clamp(width * .1, 3, 18) * (sx + sy) / 2;
        dc.DrawGeometry(null, new Pen(new SolidColorBrush(Color.FromRgb(84, 145, 46)), thickness) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round }, line);
        dc.DrawGeometry(null, new Pen(new SolidColorBrush(Color.FromRgb(122, 176, 69)), thickness * .66) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, line);
        var arc = 0.0;
        for (var i = 1; i < points.Length; i++) arc += (points[i] - points[i - 1]).Length;
        var frontFoot = new Vec(.115, .105); var rearFoot = new Vec(.747, .005);
        var gripSpan = (rearFoot - frontFoot).Length * width;
        var startDistance = Math.Min(arc * (1 - simulation.Settings.BambooPosition / 100), Math.Max(0, arc - gripSpan * 1.15));
        var eased = progress * progress * (3 - 2 * progress);
        var rearDistance = startDistance + (Math.Min(startDistance, width * .3) - startDistance) * eased;
        Vec At(double distance)
        {
            var remaining = Math.Max(0, distance);
            for (var i = points.Length - 1; i > 0; i--)
            {
                var delta = points[i - 1] - points[i];
                var segment = delta.Length;
                if (remaining <= segment && segment > 0) return points[i] + delta * (remaining / segment);
                remaining -= segment;
            }
            return points[0];
        }
        var rear = At(rearDistance);
        var low = rearDistance; var high = rearDistance + gripSpan * 1.15;
        for (var i = 0; i < 24; i++)
        {
            var mid = (low + high) / 2;
            if ((At(mid) - rear).Length < gripSpan) low = mid; else high = mid;
        }
        var front = At((low + high) / 2);
        var deltaFoot = rear - front;
        var footAngle = Math.Atan2(deltaFoot.Y, deltaFoot.X) - Math.Atan2(rearFoot.Y - frontFoot.Y, rearFoot.X - frontFoot.X);
        var localFoot = frontFoot * width;
        var offset = new Vec(localFoot.X * Math.Cos(footAngle) - localFoot.Y * Math.Sin(footAngle), localFoot.X * Math.Sin(footAngle) + localFoot.Y * Math.Cos(footAngle));
        var origin = P(front - offset, sx, sy);
        dc.PushTransform(new RotateTransform(-footAngle * 180 / Math.PI, origin.X, origin.Y));
        var imageWidth = width * sx;
        dc.DrawImage(image, new Rect(origin.X, origin.Y - width * image.PixelHeight / image.PixelWidth * sy, imageWidth, width * image.PixelHeight / image.PixelWidth * sy));
        dc.Pop();
    }
}
