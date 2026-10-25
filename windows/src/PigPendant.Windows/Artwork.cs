using System.IO;
using System.Reflection;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using PigPendant.Core;

namespace PigPendant.Windows;

internal sealed class Artwork
{
    private readonly FrameBlender frameBlender = new();
    private readonly Dictionary<DisplayMode, BitmapSource> images = new();
    private readonly Apng rope, ghostBlink;
    private readonly LocalCharacterArtwork balloonCharacter, bambooCharacter, netCharacter, hangingCharacter;
    private readonly LocalCharacterArtwork[] ghostCharacters;
    private readonly BitmapSource hangingHalo, ghostHalo;
    public (double X, double Y) HangingHaloCenter { get; }
    public (double X, double Y) GhostHaloCenter { get; }
    public IReadOnlyList<double> RopeDelays => rope.Delays;
    public int RopeFrameCount => rope.Frames.Count;
    public int GhostFrameCount => ghostBlink.Frames.Count;
    public BitmapSource this[DisplayMode mode] => images[mode];
    public static Stream Open(string name) => Assembly.GetExecutingAssembly().GetManifestResourceStream("PigPendant.Resources." + name)
        ?? throw new FileNotFoundException("Missing embedded artwork", name);
    private static BitmapSource Load(string name)
    {
        using var stream = Open(name);
        var bitmap = new BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.StreamSource = stream; bitmap.EndInit(); bitmap.Freeze(); return bitmap;
    }
    public Artwork()
    {
        images[DisplayMode.Balloon] = Load("balloon.png");
        images[DisplayMode.Bamboo] = Load("bamboo-pig.png");
        using (var stream = Open("rope-pig.png")) rope = new Apng(stream);
        using (var stream = Open("ghost-blink.png")) ghostBlink = new Apng(stream);
        if (rope.Frames.Count != 75 || ghostBlink.Frames.Count != 8) throw new InvalidDataException("Character animation frame count");
        images[DisplayMode.Rope] = rope.Frames[0];
        var netSource = Load("net-pig-custom.png");
        if (netSource.PixelWidth != 768 || netSource.PixelHeight != 768) throw new InvalidDataException("Net artwork dimensions");
        var netCrop = new CroppedBitmap(netSource, new System.Windows.Int32Rect(256, 0, 512, 768)); netCrop.Freeze();
        images[DisplayMode.Net] = RemoveNetFoot(netCrop);
        var hangingSource = Load("hanging-pig-custom.png");
        if (hangingSource.PixelWidth != 768 || hangingSource.PixelHeight != 768) throw new InvalidDataException("Hanging artwork dimensions");
        var tinted = TintHangingBand(hangingSource, rope.Frames[0]);
        (var hangingBody, var haloLayer, var hangingCenter) = SplitHangingHalo(tinted);
        images[DisplayMode.Hanging] = hangingBody; hangingHalo = haloLayer; HangingHaloCenter = hangingCenter;
        ghostHalo = Load("ghost-halo.png"); GhostHaloCenter = AlphaCenter(ghostHalo);
        images[DisplayMode.Ghost] = ghostBlink.Frames[0];
        balloonCharacter = new(images[DisplayMode.Balloon], DisplayMode.Balloon);
        bambooCharacter = new(images[DisplayMode.Bamboo], DisplayMode.Bamboo);
        netCharacter = new(images[DisplayMode.Net], DisplayMode.Net);
        hangingCharacter = new(hangingBody, DisplayMode.Hanging);
        ghostCharacters = ghostBlink.Frames.Select(frame => new LocalCharacterArtwork(frame, DisplayMode.Ghost)).ToArray();
    }
    public BitmapSource Get(DisplayMode mode, double time = 0) => images[mode];
    public (BitmapSource First, BitmapSource? Second, double Blend) Character(DisplayMode mode, PendantSimulation state, int balloonIndex = 0)
    {
        switch (mode)
        {
            case DisplayMode.Rope:
                var sample = state.RopeAnimation.Sample;
                return (rope.Frames[sample.First], sample.First == sample.Second ? null : rope.Frames[sample.Second], sample.Blend);
            case DisplayMode.Ghost:
                var blink = state.GhostBlink.Sample;
                return (ghostCharacters[blink.First].RenderGhost(state.GhostBody.Pose),
                    blink.First == blink.Second ? null : ghostCharacters[blink.Second].RenderGhost(state.GhostBody.Pose), blink.Blend);
            case DisplayMode.Balloon: return (balloonCharacter.Render(state.BalloonAnimations[balloonIndex].LocalPose), null, 0);
            case DisplayMode.Bamboo: return (bambooCharacter.Render(state.RopeAnimation.LocalPose), null, 0);
            case DisplayMode.Net: return (netCharacter.Render(state.RopeAnimation.LocalPose), null, 0);
            case DisplayMode.Hanging: return (hangingCharacter.Render(state.RopeAnimation.LocalPose), null, 0);
            default: throw new ArgumentOutOfRangeException(nameof(mode));
        }
    }
    public BitmapSource Halo(DisplayMode mode) => mode == DisplayMode.Ghost ? ghostHalo : hangingHalo;
    public BitmapSource Blend((BitmapSource First, BitmapSource? Second, double Blend) character) =>
        frameBlender.Compose(character.First, character.Second, character.Blend);
    internal static (byte[] Pixels, int Width, int Height) Pixels(BitmapSource source)
    {
        var converted = new FormatConvertedBitmap(source, PixelFormats.Pbgra32, null, 0); converted.Freeze();
        var bytes = new byte[converted.PixelWidth * converted.PixelHeight * 4];
        converted.CopyPixels(bytes, converted.PixelWidth * 4, 0);
        return (bytes, converted.PixelWidth, converted.PixelHeight);
    }
    internal static BitmapSource Bitmap(byte[] pixels, int width, int height)
    {
        var image = BitmapSource.Create(width, height, 96, 96, PixelFormats.Pbgra32, null, pixels, width * 4);
        image.Freeze(); return image;
    }
    private static BitmapSource RemoveNetFoot(BitmapSource source)
    {
        var (pixels, width, height) = Pixels(source); var changed = 0;
        for (var y = 398; y < 446; y++) for (var x = 248; x < 344; x++)
        {
            var index = (y * width + x) * 4;
            var b = pixels[index]; var g = pixels[index + 1]; var r = pixels[index + 2]; var a = pixels[index + 3];
            if (a <= 25) continue;
            var blue = b > r + a * .04;
            var pink = !blue && r > g + a * .10 && b > g + a * .02;
            var dark = !blue && r < a * .68 && g < a * .58 && b < a * .50;
            if (!pink && !dark) continue;
            pixels.AsSpan(index, 4).Clear(); changed++;
        }
        if (changed <= 800) throw new InvalidDataException($"Net foot retouch found only {changed} pixels");
        return Bitmap(pixels, width, height);
    }
    private static BitmapSource TintHangingBand(BitmapSource source, BitmapSource reference)
    {
        var (pixels, width, height) = Pixels(source);
        var (ropePixels, ropeWidth, _) = Pixels(reference);
        var sample = (70 * ropeWidth + 180) * 4;
        var alpha = ropePixels[sample + 3];
        if (alpha <= 240) throw new InvalidDataException("Rope binding reference missing");
        var brown = new[] { (double)ropePixels[sample + 2] / alpha, (double)ropePixels[sample + 1] / alpha, (double)ropePixels[sample] / alpha };
        var changed = 0;
        for (var y = (int)(height * .30); y < (int)(height * .69); y++)
        for (var x = (int)(width * .19); x < (int)(width * .78); x++)
        {
            var i = (y * width + x) * 4; var a = pixels[i + 3]; if (a == 0) continue;
            var r = (double)pixels[i + 2] / a; var g = (double)pixels[i + 1] / a; var b = (double)pixels[i] / a;
            if (b <= r + .02 || b <= g + .04) continue;
            var shade = Math.Clamp((r + g + b) / 1.44, .7, 1.3);
            pixels[i + 2] = (byte)Math.Round(Math.Min(a, brown[0] * shade * a));
            pixels[i + 1] = (byte)Math.Round(Math.Min(a, brown[1] * shade * a));
            pixels[i] = (byte)Math.Round(Math.Min(a, brown[2] * shade * a)); changed++;
        }
        if (changed <= 1000) throw new InvalidDataException($"Hanging band tint found only {changed} pixels");
        return Bitmap(pixels, width, height);
    }
    private static (BitmapSource Body, BitmapSource Halo, (double X, double Y) Center) SplitHangingHalo(BitmapSource source)
    {
        var (pixels, width, height) = Pixels(source);
        var visited = new bool[width * height]; var mask = new bool[visited.Length];
        var count = 0; var minX = width; var minY = height; var maxX = 0; var maxY = 0;
        var queue = new Queue<int>();
        for (var first = 0; first < visited.Length; first++)
        {
            if (visited[first]) continue;
            visited[first] = true;
            if (pixels[first * 4 + 3] == 0) continue;
            var component = new List<int> { first }; queue.Enqueue(first);
            var left = width; var top = height; var right = 0; var bottom = 0;
            while (queue.Count > 0)
            {
                var pixel = queue.Dequeue(); var x = pixel % width; var y = pixel / width;
                left = Math.Min(left, x); top = Math.Min(top, y); right = Math.Max(right, x + 1); bottom = Math.Max(bottom, y + 1);
                for (var dy = -1; dy <= 1; dy++) for (var dx = -1; dx <= 1; dx++)
                {
                    var nx = x + dx; var ny = y + dy;
                    if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
                    var next = ny * width + nx; if (visited[next]) continue;
                    visited[next] = true;
                    if (pixels[next * 4 + 3] == 0) continue;
                    component.Add(next); queue.Enqueue(next);
                }
            }
            if (left >= width * .64 && top >= height * .52 && right <= width * .99 && bottom <= height * .94)
            {
                foreach (var pixel in component) mask[pixel] = true;
                count += component.Count;
                minX = Math.Min(minX, left); minY = Math.Min(minY, top); maxX = Math.Max(maxX, right); maxY = Math.Max(maxY, bottom);
            }
        }
        if (count <= 4000) throw new InvalidDataException($"Hanging halo segmentation found only {count} pixels");
        var body = (byte[])pixels.Clone(); var halo = (byte[])pixels.Clone();
        for (var i = 0; i < mask.Length; i++) (mask[i] ? body : halo).AsSpan(i * 4, 4).Clear();
        return (Bitmap(body, width, height), Bitmap(halo, width, height), ((minX + maxX) / 2.0 / width, (minY + maxY) / 2.0 / height));
    }
    private static (double X, double Y) AlphaCenter(BitmapSource source)
    {
        var (pixels, width, height) = Pixels(source);
        double xTotal = 0, yTotal = 0, total = 0;
        for (var y = 0; y < height; y++) for (var x = 0; x < width; x++)
        {
            var a = pixels[(y * width + x) * 4 + 3]; xTotal += x * a; yTotal += y * a; total += a;
        }
        if (total <= 0) throw new InvalidDataException("Ghost halo empty");
        return (xTotal / total / width, yTotal / total / height);
    }
}
