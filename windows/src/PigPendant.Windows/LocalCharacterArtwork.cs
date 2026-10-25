using System.Windows.Media;
using System.Windows.Media.Imaging;
using PigPendant.Core;

namespace PigPendant.Windows;

internal sealed class LocalCharacterArtwork
{
    private static readonly (double X, double Y)[] balloonEyes = [(.217, .529), (.567, .454)];
    private static readonly (double X, double Y)[] bambooEyes = [(.102, .378), (.294, .391)];
    private static readonly (double X, double Y, double RX, double RY, double RootX, double RootY)[] balloonEars =
        [(.10, .27, .15, .17, .13, .46), (.68, .20, .19, .18, .68, .40)];
    private static readonly (double X, double Y, double RX, double RY, double RootX, double RootY)[] bambooEars =
        [(.10, .13, .17, .23, .14, .25), (.40, .21, .12, .17, .43, .33)];
    private static readonly (double X, double Y, double RootX, double RootY, double RX, double RY)[] hangingEars =
        [(.194, .391, .232, .425, .050, .074), (.786, .350, .745, .390, .086, .089)];
    private static readonly (double X, double Y)[] netCenters = [(.60, .79), (.23, .92)];
    private readonly record struct GhostRegion(double X, double Y, double RX, double RY, double RootX, double RootY, double Angle);
    private readonly DisplayMode mode;
    private readonly int width, height;
    private readonly byte[] pixels;
    private readonly BitmapSource rest;
    private readonly Dictionary<int, BitmapSource> cache = new();
    private readonly Queue<int> cacheOrder = new();
    private int lastKey = int.MinValue;
    private BitmapSource? lastImage;
    public LocalCharacterArtwork(BitmapSource source, DisplayMode mode)
    {
        this.mode = mode;
        width = Math.Min(mode == DisplayMode.Ghost ? 384 : 512, source.PixelWidth);
        height = (int)Math.Round((double)source.PixelHeight * width / source.PixelWidth);
        var scaled = new TransformedBitmap(source, new ScaleTransform((double)width / source.PixelWidth, (double)height / source.PixelHeight));
        scaled.Freeze();
        (pixels, _, _) = Artwork.Pixels(scaled);
        rest = Artwork.Bitmap(pixels, width, height);
    }
    public BitmapSource Render(LocalPose pose)
    {
        if (mode is DisplayMode.Net or DisplayMode.Hanging && pose.Gesture == Gesture.Blink)
            pose = pose with { Gesture = Gesture.Ears };
        if (pose.Step <= 0 || pose.Step >= LocalPose.Steps) return rest;
        var blink = pose.Blink; var ear = pose.EarAngle; var nuzzle = pose.Nuzzle;
        if (blink <= 0 && Math.Abs(ear) < 1e-6 && nuzzle <= 0) return rest;
        var step = pose.Gesture == Gesture.Blink && blink == 1 ? (int)Math.Round(.4 * LocalPose.Steps) : pose.Step;
        var key = (int)pose.Gesture * (LocalPose.Steps + 1) + step;
        return Render(key, (x, y) => SourcePoint(x, y, blink, ear, nuzzle));
    }
    public BitmapSource RenderGhost(GhostBodyPose pose)
    {
        if (mode != DisplayMode.Ghost) throw new InvalidOperationException();
        if (pose.Step == 0 && pose.Drift == 0 && pose.HemStep == 0) return rest;
        var phase = pose.Phase;
        GhostRegion[] regions =
        [
            new(.228, .238, .11, .074, .28, .19, .62 * pose.Pulse(0, .52) * Math.Sin(phase * Math.PI * 5)),
            new(.632, .320, .107, .070, .59, .27, -.58 * pose.Pulse(.04, .56) * Math.Sin((phase - .04) * Math.PI * 5)),
            new(.205, .621, .13, .095, .27, .57, .52 * pose.Pulse(.08, .72) * Math.Sin((phase - .08) * Math.PI * 3)),
            new(.690, .626, .14, .095, .75, .57, -.48 * pose.Pulse(.14, .78) * Math.Sin((phase - .14) * Math.PI * 3))
        ];
        var waves = new double[width];
        var hemAngle = pose.HemPhase * Math.PI * 2;
        for (var x = 0; x < width; x++) waves[x] = Math.Sin(hemAngle - (x + .5) / width * Math.PI * 2.4);
        var startY = pose.Step == 0 ? (int)(height * .75) : 0;
        return Render(pose.Key, (x, y) => GhostPoint(x, y, pose, regions, waves[Math.Min(width - 1, (int)(x * width))]), startY);
    }
    private BitmapSource Render(int key, Func<double, double, (double X, double Y)> map, int startY = 0)
    {
        if (key == lastKey && lastImage is not null) return lastImage;
        if (cache.TryGetValue(key, out var found)) { lastKey = key; lastImage = found; return found; }
        var output = (byte[])pixels.Clone();
        for (var y = startY; y < height; y++) for (var x = 0; x < width; x++)
        {
            var nx = (x + .5) / width; var ny = (y + .5) / height;
            var (mx, my) = map(nx, ny);
            if (mx == nx && my == ny) continue;
            var sx = mx * width - .5; var sy = my * height - .5;
            var left = (int)Math.Floor(sx); var top = (int)Math.Floor(sy);
            var fx = sx - left; var fy = sy - top;
            if (mode == DisplayMode.Net && (Protected(x, y) || Protected(left, top) || Protected(left + 1, top) || Protected(left, top + 1) || Protected(left + 1, top + 1))) continue;
            var offset = (y * width + x) * 4;
            for (var channel = 0; channel < 4; channel++)
            {
                var upper = Value(left, top, channel) * (1 - fx) + Value(left + 1, top, channel) * fx;
                var lower = Value(left, top + 1, channel) * (1 - fx) + Value(left + 1, top + 1, channel) * fx;
                output[offset + channel] = (byte)Math.Clamp(Math.Round(upper * (1 - fy) + lower * fy), 0, 255);
            }
        }
        var result = Artwork.Bitmap(output, width, height);
        cache[key] = result; cacheOrder.Enqueue(key);
        var capacity = Math.Max(1, (mode == DisplayMode.Ghost ? 3 : 24) * 1024 * 1024 / output.Length);
        while (cacheOrder.Count > capacity) cache.Remove(cacheOrder.Dequeue());
        lastKey = key; lastImage = result; return result;
    }
    private double Value(int x, int y, int channel) => x >= 0 && x < width && y >= 0 && y < height ? pixels[(y * width + x) * 4 + channel] : 0;
    private bool Protected(int x, int y)
    {
        if (x < 0 || x >= width || y < 0 || y >= height) return true;
        var i = (y * width + x) * 4; var a = pixels[i + 3];
        return a == 0 || pixels[i] > pixels[i + 2] + a * .04;
    }
    private static double Hypot(double x, double y) => Math.Sqrt(x * x + y * y);
    private static (double X, double Y) Rotate(double x, double y, double rootX, double rootY, double angle, double aspect = 1)
    {
        var dx = x - rootX; var dy = (y - rootY) * aspect;
        return (rootX + dx * Math.Cos(angle) - dy * Math.Sin(angle), rootY + (dx * Math.Sin(angle) + dy * Math.Cos(angle)) / aspect);
    }
    private (double X, double Y) SourcePoint(double x, double y, double blink, double earAngle, double nuzzle)
    {
        if (mode == DisplayMode.Hanging) return HangingPoint(x, y, earAngle, nuzzle);
        if (mode == DisplayMode.Net) return NetPoint(x, y, earAngle, nuzzle);
        if (blink > 0)
        {
            var eyes = mode == DisplayMode.Balloon ? balloonEyes : bambooEyes;
            var rx = mode == DisplayMode.Balloon ? .085 : .043; var inner = mode == DisplayMode.Balloon ? .062 : .057; var outer = mode == DisplayMode.Balloon ? .080 : .071;
            foreach (var eye in eyes)
            {
                var dx = Math.Abs(x - eye.Item1) / rx; var dy = y - eye.Item2;
                if (dx >= 1 || Math.Abs(dy) >= outer) continue;
                var edge = Math.Min(1, (1 - dx) * 4); var scale = 1 - .86 * blink * edge * edge * (3 - 2 * edge);
                var distance = Math.Abs(dy);
                var mapped = distance < inner * scale ? distance / scale : inner + (distance - inner * scale) * (outer - inner) / (outer - inner * scale);
                y = eye.Item2 + Math.CopySign(mapped, dy);
            }
        }
        if (earAngle != 0)
        {
            var ears = mode == DisplayMode.Balloon ? balloonEars : bambooEars;
            for (var index = 0; index < ears.Length; index++)
            {
                var e = ears[index]; var radius = Hypot((x - e.Item1) / e.Item3, (y - e.Item2) / e.Item4);
                if (radius >= 1) continue;
                var angle = earAngle * Math.Pow(1 - radius * radius, 2) * (index == 0 ? 1 : -1);
                (x, y) = Rotate(x, y, e.Item5, e.Item6, angle);
            }
        }
        if (nuzzle > 0)
        {
            var nose = mode == DisplayMode.Balloon ? (.365, .706) : (.166, .549);
            var radius = Hypot((x - nose.Item1) / .19, (y - nose.Item2) / .18);
            if (radius < 1) { var amount = nuzzle * Math.Pow(1 - radius * radius, 2); x = nose.Item1 + (x - nose.Item1) / (1 + .14 * amount) + .034 * amount; y = nose.Item2 + (y - nose.Item2) / (1 + .09 * amount) + .012 * amount; }
        }
        return (x, y);
    }
    private static (double X, double Y) HangingPoint(double x, double y, double ear, double nuzzle)
    {
        if (ear != 0)
        {
            var ears = hangingEars;
            for (var index = 0; index < ears.Length; index++)
            {
                var e = ears[index]; var radius = Hypot((x - e.Item1) / e.Item5, (y - e.Item2) / e.Item6);
                if (radius < 1) return Rotate(x, y, e.Item3, e.Item4, ear * 1.8 * Math.Pow(1 - radius * radius, 2) * (index == 0 ? 1 : -1));
            }
        }
        if (nuzzle > 0)
        {
            var radius = Hypot((x - .525) / .108, (y - .235) / .075);
            if (radius < 1) { var amount = nuzzle * Math.Pow(1 - radius * radius, 2); return (.525 + (x - .525) / (1 + .10 * amount) - .018 * amount, .235 + (y - .235) / (1 + .08 * amount) + .026 * amount); }
        }
        return (x, y);
    }
    private static (double X, double Y) NetPoint(double x, double y, double ear, double nuzzle)
    {
        if (ear != 0)
        {
            var centers = netCenters;
            for (var index = 0; index < centers.Length; index++)
            {
                var center = centers[index]; var radius = Hypot((x - center.Item1) / .13, (y - center.Item2) / .09);
                if (radius < 1) { var amount = ear * Math.Pow(1 - radius * radius, 2) * (index == 0 ? 1 : -1); return (x + amount * .085, y + amount * .025); }
            }
        }
        if (nuzzle > 0)
        {
            var radius = Hypot((x - .255) / .15, (y - .723) / .10);
            if (radius < 1) { var amount = nuzzle * Math.Pow(1 - radius * radius, 2); return (x + amount * .025, y + amount * .012); }
        }
        return (x, y);
    }
    private static (double X, double Y) GhostPoint(double x, double y, GhostBodyPose pose, GhostRegion[] regions, double wave)
    {
        foreach (var r in regions)
        {
            if (r.Angle == 0) continue;
            var radius = Hypot((x - r.X) / r.RX, (y - r.Y) / r.RY);
            if (radius < 1) return Rotate(x, y, r.RootX, r.RootY, r.Angle * Math.Pow(1 - radius * radius, 2), 1.5);
        }
        if (y <= .75) return (x, y);
        var t = Math.Min(1, (y - .75) / .16); var weight = t * t * (3 - 2 * t);
        var drift = (double)pose.Drift / 16;
        return (x + weight * (wave * .0035 + drift * .010), y + weight * (wave * .017 * (1 + Math.Abs(drift) * .25) + drift * (x - .5) * .012));
    }
}
