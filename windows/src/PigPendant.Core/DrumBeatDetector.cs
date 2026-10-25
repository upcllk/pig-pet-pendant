namespace PigPendant.Core;

public sealed class DrumBeatDetector
{
    private const int WindowSize = 1024, HopSize = 512;
    private static readonly (double Frequency, double Weight)[] Frequencies =
    [
        (45, 1), (60, 1), (75, 1), (90, 1), (110, 1), (130, 1), (155, 1),
        (200, .45), (250, .45), (315, .45), (400, .45), (500, .45),
        (630, .45), (800, .45), (1000, .45), (1250, .45), (1600, .45),
        (2000, .45), (2500, .45), (3150, .45)
    ];
    private readonly double sampleRate;
    private readonly (double Frequency, double Weight)[] bins;
    private readonly double[] window = new double[WindowSize];
    private readonly double[] frame = new double[WindowSize];
    private readonly double[] previousLevels;
    private int count, samplePosition, lastBeatPosition = int.MinValue;
    private double averageFlux;
    private bool hasPrevious;
    public DrumBeatDetector(double sampleRate)
    {
        if (!double.IsFinite(sampleRate) || sampleRate <= 0) throw new ArgumentOutOfRangeException(nameof(sampleRate));
        this.sampleRate = sampleRate;
        bins = Frequencies.Where(x => x.Frequency < sampleRate * .45).ToArray();
        if (bins.Length < 4) throw new ArgumentOutOfRangeException(nameof(sampleRate));
        previousLevels = new double[bins.Length];
        for (var i = 0; i < WindowSize; i++) window[i] = .5 - .5 * Math.Cos(2 * Math.PI * i / (WindowSize - 1));
    }
    public double Process(ReadOnlySpan<float> samples)
    {
        var strongest = 0.0;
        foreach (var sample in samples)
        {
            if (!float.IsFinite(sample)) continue;
            frame[count++] = sample;
            if (count < WindowSize) continue;
            strongest = Math.Max(strongest, Analyze());
            Array.Copy(frame, HopSize, frame, 0, HopSize);
            count = HopSize; samplePosition += HopSize;
        }
        return strongest;
    }
    private double Analyze()
    {
        var flux = 0.0;
        for (var i = 0; i < bins.Length; i++)
        {
            var coefficient = 2 * Math.Cos(2 * Math.PI * bins[i].Frequency / sampleRate);
            double previous = 0, previousPrevious = 0;
            for (var j = 0; j < WindowSize; j++)
            {
                var value = frame[j] * window[j] + coefficient * previous - previousPrevious;
                previousPrevious = previous; previous = value;
            }
            var power = Math.Max(0, previousPrevious * previousPrevious + previous * previous - coefficient * previous * previousPrevious) / (WindowSize * WindowSize);
            var level = Math.Log(1 + power * 1000);
            if (hasPrevious) flux += Math.Max(0, level - previousLevels[i]) * bins[i].Weight;
            previousLevels[i] = level;
        }
        hasPrevious = true;
        var elapsed = (double)HopSize / sampleRate;
        var threshold = Math.Max(.12, averageFlux * 2.5);
        var strength = Math.Clamp((flux - threshold) / 1.4, 0, 1);
        averageFlux += (flux - averageFlux) * (1 - Math.Exp(-elapsed / 1.2));
        var position = samplePosition + WindowSize;
        if (strength < .08 || (long)position - lastBeatPosition < sampleRate * .12) return 0;
        lastBeatPosition = position; return strength;
    }
}

public static class AudioReactiveScale
{
    public static double ForBeat(double strength, double elapsed)
    {
        var bounded = double.IsFinite(strength) ? Math.Clamp(strength, 0, 1) : 0;
        var age = double.IsFinite(elapsed) ? Math.Max(0, elapsed) : double.MaxValue;
        return .73 + (1.6 - .73) * bounded * Math.Exp(-age / .28);
    }
    public static double Smoothed(double current, double target, double elapsed)
    {
        var step = Math.Clamp(elapsed, 0, .1);
        var response = target > current ? 8 : 12;
        return current + (target - current) * (1 - Math.Exp(-response * step));
    }
}
