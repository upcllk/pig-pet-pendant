using System.Windows.Media.Imaging;
using System.IO;
using PigPendant.Core;

namespace PigPendant.Windows;

internal sealed class Artwork
{
    private readonly Dictionary<DisplayMode, BitmapSource> images = new();
    private readonly Apng net;
    public Artwork()
    {
        var names = new Dictionary<DisplayMode, string>
        {
            [DisplayMode.Rope] = "pig.png", [DisplayMode.Balloon] = "balloon.png",
            [DisplayMode.Net] = "net-pig.png", [DisplayMode.Bamboo] = "bamboo-pig.png",
            [DisplayMode.Hanging] = "hanging-pig.png", [DisplayMode.Ghost] = "ghost-pig.png"
        };
        foreach (var (mode, name) in names)
        {
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.UriSource = new Uri(Path.Combine(AppContext.BaseDirectory, "Resources", name));
            bitmap.EndInit(); bitmap.Freeze();
            images[mode] = bitmap;
        }
        net = new Apng(Path.Combine(AppContext.BaseDirectory, "Resources", "net-pig.png"));
    }
    public BitmapSource this[DisplayMode mode] => images[mode];
    public int NetFrameCount => net.Frames.Count;
    public double NetDuration => net.Delays.Sum();
    public BitmapSource Get(DisplayMode mode, double time)
    {
        if (mode != DisplayMode.Net) return images[mode];
        var phase = time % net.Delays.Sum();
        for (var i = 0; i < net.Frames.Count; i++)
        {
            phase -= net.Delays[i];
            if (phase < 0) return net.Frames[i];
        }
        return net.Frames[^1];
    }
}
