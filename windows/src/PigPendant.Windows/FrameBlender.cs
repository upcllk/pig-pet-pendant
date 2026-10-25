using System.Runtime.CompilerServices;
using System.Windows.Media.Imaging;

namespace PigPendant.Windows;

// Mix premultiplied color and alpha before presenting one image to the layered window.
internal sealed class FrameBlender
{
    private sealed record Pixels(byte[] Data, int Width, int Height);
    private readonly ConditionalWeakTable<BitmapSource, Pixels> sourcePixels = new();
    private BitmapSource? previousFirst, previousSecond, previousResult;
    private double previousBlend;

    public BitmapSource Compose(BitmapSource first, BitmapSource? second, double blend)
    {
        if (second is null || blend <= 0 || ReferenceEquals(first, second)) return first;
        if (blend >= 1) return second;
        if (ReferenceEquals(first, previousFirst) && ReferenceEquals(second, previousSecond) &&
            blend == previousBlend && previousResult is not null) return previousResult;

        var a = sourcePixels.GetValue(first, static image => FromImage(image));
        var b = sourcePixels.GetValue(second, static image => FromImage(image));
        if (a.Width != b.Width || a.Height != b.Height) throw new InvalidOperationException("Animation frames have different canvas sizes");

        var output = new byte[a.Data.Length];
        var firstWeight = 1 - blend;
        for (var i = 0; i < output.Length; i += 4)
        {
            var alpha = (byte)Math.Clamp(Math.Round(a.Data[i + 3] * firstWeight + b.Data[i + 3] * blend), 0, 255);
            output[i + 3] = alpha;
            for (var channel = 0; channel < 3; channel++)
                output[i + channel] = (byte)Math.Min(alpha,
                    Math.Clamp(Math.Round(a.Data[i + channel] * firstWeight + b.Data[i + channel] * blend), 0, 255));
        }
        previousFirst = first; previousSecond = second; previousBlend = blend;
        previousResult = Artwork.Bitmap(output, a.Width, a.Height);
        return previousResult;
    }

    private static Pixels FromImage(BitmapSource image)
    {
        var (data, width, height) = Artwork.Pixels(image);
        return new Pixels(data, width, height);
    }
}
