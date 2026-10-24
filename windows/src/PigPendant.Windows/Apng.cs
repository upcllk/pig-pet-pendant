using System.Buffers.Binary;
using System.IO;
using System.Text;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace PigPendant.Windows;

// Rebuilds each APNG subframe as a PNG, then composites it on the full canvas.
internal sealed class Apng
{
    public IReadOnlyList<BitmapSource> Frames { get; }
    public IReadOnlyList<double> Delays { get; }
    public Apng(string path)
    {
        var bytes = File.ReadAllBytes(path);
        if (!bytes.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 })) throw new InvalidDataException("PNG signature");
        var frames = new List<Frame>();
        var shared = new List<(string, byte[])>();
        byte[]? ihdr = null;
        var width = 0; var height = 0;
        Frame? current = null;
        for (var pos = 8; pos + 12 <= bytes.Length;)
        {
            var length = checked((int)BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(pos, 4)));
            if (pos + length + 12 > bytes.Length) throw new InvalidDataException("PNG chunk length");
            var type = Encoding.ASCII.GetString(bytes, pos + 4, 4);
            var data = bytes.AsSpan(pos + 8, length).ToArray();
            pos += length + 12;
            if (type == "IHDR")
            {
                ihdr = data;
                width = (int)BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(0, 4));
                height = (int)BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(4, 4));
            }
            else if (type == "fcTL")
            {
                if (current is not null) frames.Add(current);
                var denominator = BinaryPrimitives.ReadUInt16BigEndian(data.AsSpan(22, 2));
                current = new Frame
                {
                    Width = (int)BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(4, 4)),
                    Height = (int)BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(8, 4)),
                    X = (int)BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(12, 4)),
                    Y = (int)BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(16, 4)),
                    Delay = (double)BinaryPrimitives.ReadUInt16BigEndian(data.AsSpan(20, 2)) / (denominator == 0 ? 100 : denominator),
                    Dispose = data[24], Blend = data[25]
                };
            }
            else if (type == "IDAT") current?.Data.Add(data);
            else if (type == "fdAT") current?.Data.Add(data.AsSpan(4).ToArray());
            else if (type is not ("acTL" or "IEND") && current is null && type != "IHDR") shared.Add((type, data));
            if (type == "IEND") break;
        }
        if (current is not null) frames.Add(current);
        if (ihdr is null || width <= 0 || height <= 0 || frames.Count < 2) throw new InvalidDataException("APNG frames");
        var canvas = new byte[width * height * 4];
        var images = new List<BitmapSource>();
        var delays = new List<double>();
        foreach (var frame in frames)
        {
            if (frame.Width <= 0 || frame.Height <= 0 || frame.X + frame.Width > width || frame.Y + frame.Height > height || frame.Data.Count == 0)
                throw new InvalidDataException("APNG frame bounds");
            var before = frame.Dispose == 2 ? (byte[])canvas.Clone() : null;
            var header = (byte[])ihdr.Clone();
            BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(0, 4), (uint)frame.Width);
            BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(4, 4), (uint)frame.Height);
            using var stream = new MemoryStream();
            stream.Write(bytes, 0, 8);
            Chunk(stream, "IHDR", header);
            foreach (var (type, data) in shared) Chunk(stream, type, data);
            foreach (var data in frame.Data) Chunk(stream, "IDAT", data);
            Chunk(stream, "IEND", []);
            stream.Position = 0;
            var decoded = new PngBitmapDecoder(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
            var bgra = new FormatConvertedBitmap(decoded, PixelFormats.Bgra32, null, 0);
            var pixels = new byte[frame.Width * frame.Height * 4];
            bgra.CopyPixels(pixels, frame.Width * 4, 0);
            for (var y = 0; y < frame.Height; y++)
            for (var x = 0; x < frame.Width; x++)
            {
                var source = (y * frame.Width + x) * 4;
                var target = ((y + frame.Y) * width + x + frame.X) * 4;
                var alpha = pixels[source + 3];
                if (frame.Blend == 0 || alpha == 255) Array.Copy(pixels, source, canvas, target, 4);
                else if (alpha != 0)
                {
                    var oldAlpha = canvas[target + 3];
                    var outAlpha = alpha + oldAlpha * (255 - alpha) / 255;
                    for (var c = 0; c < 3; c++)
                        canvas[target + c] = (byte)((pixels[source + c] * alpha + canvas[target + c] * oldAlpha * (255 - alpha) / 255) / outAlpha);
                    canvas[target + 3] = (byte)outAlpha;
                }
            }
            var bitmap = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, canvas, width * 4);
            bitmap.Freeze();
            images.Add(bitmap);
            delays.Add(frame.Delay > 0 ? frame.Delay : .01);
            if (frame.Dispose == 1)
            {
                for (var y = frame.Y; y < frame.Y + frame.Height; y++)
                    Array.Clear(canvas, (y * width + frame.X) * 4, frame.Width * 4);
            }
            else if (before is not null) canvas = before;
        }
        Frames = images; Delays = delays;
    }
    private static void Chunk(Stream stream, string type, byte[] data)
    {
        Span<byte> size = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(size, (uint)data.Length);
        stream.Write(size);
        var name = Encoding.ASCII.GetBytes(type);
        stream.Write(name); stream.Write(data);
        uint crc = 0xffffffff;
        foreach (var value in name.Concat(data))
        {
            crc ^= value;
            for (var i = 0; i < 8; i++) crc = crc >> 1 ^ ((crc & 1) != 0 ? 0xedb88320u : 0);
        }
        BinaryPrimitives.WriteUInt32BigEndian(size, ~crc);
        stream.Write(size);
    }
    private sealed class Frame
    {
        public int Width, Height, X, Y;
        public double Delay;
        public byte Dispose, Blend;
        public List<byte[]> Data = new();
    }
}
