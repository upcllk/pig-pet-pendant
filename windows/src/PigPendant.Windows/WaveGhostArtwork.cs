using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using PigPendant.Core;

namespace PigPendant.Windows;

// Local deformation of the user supplied image; the embedded PNG is never modified.
internal sealed class WaveGhostArtwork
{
    private readonly int width, height;
    private readonly byte[] pixels;
    private readonly BitmapSource rest;
    private readonly Dictionary<int, BitmapSource> cache = new();
    private readonly Queue<int> cacheOrder = new();
    private int lastKey = int.MinValue;
    private BitmapSource? lastImage;

    public WaveGhostArtwork(BitmapSource source)
    {
        if (source.PixelWidth != 768 || source.PixelHeight != 768)
            throw new InvalidDataException("Wave ghost artwork dimensions");
        width = height = 384;
        var scaled = new TransformedBitmap(source, new ScaleTransform(.5, .5));
        scaled.Freeze();
        (pixels, _, _) = Artwork.Pixels(scaled);
        rest = Artwork.Bitmap(pixels, width, height);
    }

    public static double BlinkAmount(FrameSample sample)
    {
        ReadOnlySpan<double> closure = [0, .18, .58, 1, 1, .62, .20, 0];
        var first = Math.Clamp(sample.First, 0, closure.Length - 1);
        var second = Math.Clamp(sample.Second, 0, closure.Length - 1);
        return closure[first] + (closure[second] - closure[first]) * Math.Clamp(sample.Blend, 0, 1);
    }

    public BitmapSource Render(GhostBodyPose pose, FrameSample blinkSample)
    {
        var blinkStep = (int)Math.Round(BlinkAmount(blinkSample) * 72);
        if (pose.Step == 0 && pose.Drift == 0 && pose.HemStep == 0 && blinkStep == 0) return rest;
        var key = checked(pose.Key * 73 + blinkStep);
        if (key == lastKey && lastImage is not null) return lastImage;
        if (cache.TryGetValue(key, out var found)) { lastKey = key; lastImage = found; return found; }
        var blink = blinkStep / 72.0;
        var output = (byte[])pixels.Clone();
        for (var y = 0; y < height; y++) for (var x = 0; x < width; x++)
        {
            var nx = (x + .5) / width; var ny = (y + .5) / height;
            var (mx, my) = SourcePoint(nx, ny, pose, blink);
            if (mx == nx && my == ny) continue;
            var sx = mx * width - .5; var sy = my * height - .5;
            var left = (int)Math.Floor(sx); var top = (int)Math.Floor(sy);
            var fx = sx - left; var fy = sy - top;
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
        while (cacheOrder.Count > 20 * 1024 * 1024 / output.Length) cache.Remove(cacheOrder.Dequeue());
        lastKey = key; lastImage = result;
        return result;
    }

    private double Value(int x, int y, int channel) => x >= 0 && x < width && y >= 0 && y < height
        ? pixels[(y * width + x) * 4 + channel] : 0;

    private static (double X, double Y) SourcePoint(double x, double y, GhostBodyPose pose, double blink)
    {
        if (blink > 0)
        {
            foreach (var eye in new[] { (.239, .416), (.490, .454) })
            {
                var dx = Math.Abs(x - eye.Item1) / .058;
                var dy = y - eye.Item2;
                if (dx >= 1 || Math.Abs(dy) >= .070) continue;
                var edge = Math.Min(1, (1 - dx) * 4);
                var scale = 1 - .94 * blink * edge * edge * (3 - 2 * edge);
                var distance = Math.Abs(dy);
                const double inner = .043, outer = .070;
                var mapped = distance < inner * scale ? distance / scale
                    : inner + (distance - inner * scale) * (outer - inner) / (outer - inner * scale);
                y = eye.Item2 + Math.CopySign(mapped, dy);
            }
        }
        var phase = pose.Phase;
        var drift = pose.Drift / 16.0;
        var ears = new (double X, double Y, double RootX, double RootY, double RX, double RY, double Angle)[]
        {
            (.190, .235, .265, .292, .13, .13, .58 * pose.Pulse(0, .72) * Math.Sin(phase * Math.PI * 4) + drift * .12),
            (.720, .300, .670, .278, .14, .14, -.66 * pose.Pulse(.08, .80) * Math.Sin((phase - .08) * Math.PI * 4) - drift * .10)
        };
        foreach (var ear in ears)
        {
            if (ear.Angle == 0) continue;
            var radius = Math.Sqrt(Math.Pow((x - ear.X) / ear.RX, 2) + Math.Pow((y - ear.Y) / ear.RY, 2));
            if (radius >= 1) continue;
            var angle = ear.Angle * Math.Pow(1 - radius * radius, 2);
            var dx = x - ear.RootX; var dy = y - ear.RootY;
            (x, y) = (ear.RootX + dx * Math.Cos(angle) - dy * Math.Sin(angle),
                ear.RootY + dx * Math.Sin(angle) + dy * Math.Cos(angle));
        }
        if (pose.HemPhase != 0 && y > .69)
        {
            var t = Math.Clamp((y - .69) / .18, 0, 1);
            var weight = t * t * (3 - 2 * t);
            var wave = Math.Sin(pose.HemPhase * Math.PI * 2 - x * Math.PI * 4.4);
            y += wave * .038 * weight;
        }
        return (x, y);
    }
}
