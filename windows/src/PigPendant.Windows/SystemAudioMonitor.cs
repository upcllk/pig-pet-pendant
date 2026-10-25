using System.Diagnostics;
using NAudio.Wave;
using PigPendant.Core;

namespace PigPendant.Windows;

// WASAPI loopback buffers are analyzed in memory; no audio is written to disk.
internal sealed class SystemAudioMonitor : IDisposable
{
    private readonly object gate = new();
#pragma warning disable CS0618 // The supported NAudio 3 compatibility capture has the event API needed here.
    private WasapiLoopbackCapture? capture;
#pragma warning restore CS0618
    private DrumBeatDetector? detector;
    private double beatStrength;
    private long lastBeatTicks;
    public void Start()
    {
#pragma warning disable CS0618
        var device = new WasapiLoopbackCapture();
#pragma warning restore CS0618
        try
        {
            var format = device.WaveFormat;
            if (format.Channels <= 0 || format.BitsPerSample is not (16 or 24 or 32)) throw new NotSupportedException("Unsupported system output format");
            detector = new DrumBeatDetector(format.SampleRate);
            device.DataAvailable += (_, args) => Process(args.Buffer, args.BytesRecorded, format);
            device.RecordingStopped += (_, args) => { if (args.Exception is not null) Trace.WriteLine($"System audio capture stopped: {args.Exception}"); };
            device.StartRecording();
            capture = device;
        }
        catch { device.Dispose(); throw; }
    }
    private void Process(byte[] buffer, int length, WaveFormat format)
    {
        var bytesPerSample = format.BitsPerSample / 8;
        var frameSize = bytesPerSample * format.Channels;
        if (frameSize <= 0) return;
        var frames = new float[length / frameSize];
        var isFloat = format.Encoding == WaveFormatEncoding.IeeeFloat ||
            format is WaveFormatExtensible ext && ext.SubFormat == new Guid("00000003-0000-0010-8000-00aa00389b71");
        for (var i = 0; i < frames.Length; i++)
        {
            double sum = 0;
            for (var channel = 0; channel < format.Channels; channel++)
            {
                var offset = i * frameSize + channel * bytesPerSample;
                sum += isFloat ? BitConverter.ToSingle(buffer, offset) : bytesPerSample switch
                {
                    2 => BitConverter.ToInt16(buffer, offset) / 32768.0,
                    3 => ((buffer[offset] | buffer[offset + 1] << 8 | buffer[offset + 2] << 16) << 8 >> 8) / 8388608.0,
                    4 => BitConverter.ToInt32(buffer, offset) / 2147483648.0,
                    _ => 0
                };
            }
            frames[i] = (float)(sum / format.Channels);
        }
        lock (gate)
        {
            var strength = detector?.Process(frames) ?? 0;
            if (strength > 0) { beatStrength = strength; lastBeatTicks = Stopwatch.GetTimestamp(); }
        }
    }
    public double TargetScale()
    {
        lock (gate)
        {
            if (lastBeatTicks == 0) return AudioReactiveScale.ForBeat(0, 0);
            var elapsed = (Stopwatch.GetTimestamp() - lastBeatTicks) / (double)Stopwatch.Frequency;
            return AudioReactiveScale.ForBeat(beatStrength, elapsed);
        }
    }
    public void Dispose()
    {
        if (capture is { } device) { device.StopRecording(); device.Dispose(); capture = null; }
    }
}
