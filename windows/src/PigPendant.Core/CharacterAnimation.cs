namespace PigPendant.Core;

public readonly record struct FrameSample(int First, int Second, double Blend)
{
    public static FrameSample Rest => new(0, 0, 0);
}

public enum Gesture { Blink, Ears, Nuzzle }
public readonly record struct LocalPose(Gesture Gesture, int Step)
{
    public const int Steps = 72;
    public static LocalPose Rest => new(Gesture.Blink, 0);
    private double Phase => (double)Step / Steps;
    private double Envelope => Math.Pow(Math.Sin(Math.PI * Phase), 2);
    private static double Smooth(double t) { t = Math.Clamp(t, 0, 1); return t * t * (3 - 2 * t); }
    public double Blink => Gesture != Gesture.Blink ? 0 : Phase < .30 ? Smooth((Phase - .04) / .26) : Phase <= .50 ? 1 : 1 - Smooth((Phase - .50) / .44);
    public double EarAngle => Gesture == Gesture.Ears ? Math.Sin(4 * Math.PI * Phase) * Envelope * .36 : 0;
    public double Nuzzle => Gesture == Gesture.Nuzzle ? Envelope : 0;
}

public enum CharacterAction { Blink, Ears, Stretch, Moving, Falling }
public sealed class RopeCharacterAnimation
{
    private static readonly int[] blink = Enumerable.Range(0, 29).ToArray();
    private static readonly int[] ears = Enumerable.Range(0, 12).Concat(Enumerable.Range(0, 11).Reverse()).ToArray();
    private static readonly int[] stretch = Enumerable.Range(28, 24).Concat(Enumerable.Range(28, 23).Reverse()).ToArray();
    private readonly IReadOnlyList<double> durations;
    private ulong randomState;
    private double actionTime, idleRemaining, motionCooldown, motionSpeed, fallingSpeed, idleRate = 1;
    private bool wasMoving, wasFalling;
    private CharacterAction? pendingMotion;
    private int? lastIdleChoice;
    public CharacterAction? Action { get; private set; }
    public bool IsAnimating => Action.HasValue;
    public RopeCharacterAnimation(IReadOnlyList<double> durations, ulong seed)
    {
        if (durations.Count != 75 || durations.Any(x => !double.IsFinite(x) || x <= 0)) throw new ArgumentException("75 rope frames required");
        this.durations = durations; randomState = seed; Reset();
    }
    private double RandomUnit() { randomState = unchecked(randomState * 6364136223846793005UL + 1442695040888963407UL); return (randomState >> 11) / 9007199254740992.0; }
    private static int[] Frames(CharacterAction action) => action switch { CharacterAction.Blink => blink, CharacterAction.Ears or CharacterAction.Moving => ears, _ => stretch };
    private double Duration(CharacterAction action)
    {
        var frames = Frames(action);
        return (frames[0] == 0 ? 0 : .14) + frames.Sum(i => durations[i]) + (frames[^1] == 0 ? 0 : .18);
    }
    private static double Smooth(double t) => t * t * (3 - 2 * t);
    public FrameSample Sample
    {
        get
        {
            if (Action is not { } action) return FrameSample.Rest;
            var frames = Frames(action);
            var time = actionTime;
            if (frames[0] != 0) { if (time < .14) return new(0, frames[0], Smooth(time / .14)); time -= .14; }
            for (var p = 0; p < frames.Length; p++)
            {
                var index = frames[p]; var duration = durations[index];
                if (time < duration) { var next = frames[Math.Min(p + 1, frames.Length - 1)]; return new(index, next, next == index ? 0 : time / duration); }
                time -= duration;
            }
            return frames[^1] == 0 ? FrameSample.Rest : new(frames[^1], 0, Smooth(Math.Min(1, time / .18)));
        }
    }
    public LocalPose LocalPose
    {
        get
        {
            if (Action is not { } action) return LocalPose.Rest;
            var gesture = action switch { CharacterAction.Blink => Gesture.Blink, CharacterAction.Ears or CharacterAction.Moving => Gesture.Ears, _ => Gesture.Nuzzle };
            var step = (int)Math.Round(actionTime / Duration(action) * LocalPose.Steps);
            return step > 0 && step < LocalPose.Steps ? new(gesture, step) : LocalPose.Rest;
        }
    }
    public void Reset()
    {
        Action = null; actionTime = 0; idleRemaining = 1.2 + RandomUnit() * 1.3;
        motionCooldown = 0; pendingMotion = null; lastIdleChoice = null; ResetMotion();
    }
    public void ResetMotion() { motionSpeed = fallingSpeed = 0; wasMoving = wasFalling = false; pendingMotion = null; }
    public bool Advance(double elapsed, Vec anchorVelocity, Vec bobVelocity)
    {
        if (!double.IsFinite(elapsed) || elapsed <= 0 || !double.IsFinite(anchorVelocity.X + anchorVelocity.Y + bobVelocity.X + bobVelocity.Y)) return false;
        var before = Sample; var step = Math.Min(.1, elapsed); var response = 1 - Math.Exp(-12 * step);
        var speed = Math.Min(2000, Math.Max(anchorVelocity.Length, bobVelocity.Length));
        var downward = Math.Min(2000, Math.Max(0, -bobVelocity.Y));
        motionSpeed += (speed - motionSpeed) * response; fallingSpeed += (downward - fallingSpeed) * response;
        var moving = motionSpeed > (wasMoving ? 45 : 90); var falling = fallingSpeed > (wasFalling ? 55 : 110);
        if (falling && !wasFalling) pendingMotion = CharacterAction.Falling;
        else if (moving && !wasMoving && pendingMotion != CharacterAction.Falling) pendingMotion = CharacterAction.Moving;
        wasMoving = moving; wasFalling = falling; motionCooldown = Math.Max(0, motionCooldown - step);
        if (Action is null)
        {
            if (motionCooldown == 0 && (pendingMotion ?? (falling ? CharacterAction.Falling : moving ? CharacterAction.Moving : null)) is { } requested)
            { Action = requested; pendingMotion = null; actionTime = 0; }
            else if (!moving && (idleRemaining -= step) <= 0)
            {
                var choices = new[] { CharacterAction.Blink, CharacterAction.Ears, CharacterAction.Stretch };
                var index = lastIdleChoice is { } previous ? (previous + 1 + (int)(RandomUnit() * 2)) % choices.Length : (int)(RandomUnit() * choices.Length);
                Action = choices[index]; lastIdleChoice = index; idleRate = .9 + RandomUnit() * .2; actionTime = 0;
            }
        }
        if (Action is { } active)
        {
            var rate = active switch { CharacterAction.Moving => .95 + Math.Min(1, motionSpeed / 800) * .5, CharacterAction.Falling => 1.05 + Math.Min(1, fallingSpeed / 800) * .5, _ => idleRate };
            actionTime += step * rate;
            if (actionTime >= Duration(active)) { Action = null; actionTime = 0; idleRemaining = 2 + RandomUnit() * 3; motionCooldown = .6 + RandomUnit() * .6; }
        }
        return Sample != before;
    }
}

public sealed class GhostBlinkAnimation
{
    public static readonly double[] KeyDurations = [.07, .10, .10, .14, .14, .13, .13, .10];
    private ulong randomState;
    private double waiting;
    private double? actionTime;
    public bool IsAnimating => actionTime.HasValue;
    public GhostBlinkAnimation(ulong seed) { randomState = seed; Reset(); }
    private double RandomUnit() { randomState = unchecked(randomState * 6364136223846793005UL + 1442695040888963407UL); return (randomState >> 11) / 9007199254740992.0; }
    public void Reset() { actionTime = null; waiting = 1.2 + RandomUnit() * 1.3; }
    public FrameSample Sample
    {
        get
        {
            if (actionTime is not { } time) return FrameSample.Rest;
            for (var i = 0; i < KeyDurations.Length; i++) { if (time < KeyDurations[i]) { var next = Math.Min(7, i + 1); return new(i, next, next == i ? 0 : time / KeyDurations[i]); } time -= KeyDurations[i]; }
            return FrameSample.Rest;
        }
    }
    public bool Advance(double elapsed)
    {
        if (!double.IsFinite(elapsed) || elapsed <= 0) return false;
        var before = Sample; var step = Math.Min(.1, elapsed);
        if (actionTime is { } time) { if (time + step >= KeyDurations.Sum()) { actionTime = null; waiting = 3 + RandomUnit() * 3; } else actionTime = time + step; }
        else if ((waiting -= step) <= 0) actionTime = Math.Max(0, -waiting);
        return Sample != before;
    }
}

public readonly record struct GhostBodyPose(int Step, int Drift, int HemStep)
{
    public const int Steps = 144, HemSteps = 192;
    public const double HemPeriod = 3.2;
    public double Phase => (double)Step / Steps;
    public double HemPhase => (double)HemStep / HemSteps;
    public int Key => (Step * 33 + Drift + 16) * HemSteps + HemStep;
    public double Pulse(double start, double end) => Phase > start && Phase < end ? Math.Pow(Math.Sin(Math.PI * (Phase - start) / (end - start)), 2) : 0;
}
public sealed class GhostBodyAnimation
{
    private double? actionTime;
    private bool wasBlinking;
    private double drift, hemTime;
    public double HemPlaybackRate { get; private set; } = 1;
    public bool IsGesturing => actionTime is not null || Math.Abs(drift) > .015;
    public GhostBodyPose Pose { get; private set; }
    public void Reset() { actionTime = null; wasBlinking = false; drift = hemTime = 0; HemPlaybackRate = 1; Pose = default; }
    public void ResetMotion() => HemPlaybackRate = 1;
    public bool Advance(double elapsed, bool blinking, double horizontalVelocity, double mouseSpeed = 0)
    {
        if (!double.IsFinite(elapsed) || elapsed <= 0 || !double.IsFinite(horizontalVelocity) || !double.IsFinite(mouseSpeed) || mouseSpeed < 0) return false;
        var before = Pose; var step = Math.Min(.1, elapsed);
        if (elapsed > .25) ResetMotion();
        var targetRate = elapsed > .25 ? 1 : 1 + 3 * mouseSpeed / (mouseSpeed + 600);
        const double response = 8;
        var decay = Math.Exp(-step * response);
        var hemElapsed = targetRate * step + (HemPlaybackRate - targetRate) * (1 - decay) / response;
        HemPlaybackRate = targetRate + (HemPlaybackRate - targetRate) * decay;
        hemTime = (hemTime + hemElapsed) % GhostBodyPose.HemPeriod;
        if (blinking && !wasBlinking && actionTime is null) actionTime = 0;
        wasBlinking = blinking;
        if (actionTime is { } time) actionTime = time + step < 2.4 ? time + step : null;
        var target = elapsed > .25 ? 0 : Math.Tanh(horizontalVelocity / 300);
        drift += (target - drift) * (1 - Math.Exp(-step * 12));
        if (target == 0 && Math.Abs(drift) < .015) drift = 0;
        Pose = new(actionTime is { } t ? Math.Min(GhostBodyPose.Steps, (int)Math.Round(t / 2.4 * GhostBodyPose.Steps)) : 0,
            (int)Math.Round(drift * 16), (int)Math.Round(hemTime / GhostBodyPose.HemPeriod * GhostBodyPose.HemSteps) % GhostBodyPose.HemSteps);
        return Pose != before;
    }
}

public readonly record struct HaloPose(double Angle, Vec Offset);
public sealed class HaloAnimation
{
    private ulong randomState;
    private double angularVelocity, idleRemaining, idleTime, idleDirection, idlePlaneAngle;
    private Vec velocity;
    private bool idleActive;
    public HaloPose Pose { get; private set; }
    public bool IsAnimating => idleActive || Math.Abs(Pose.Angle) > .0001 || Pose.Offset.Length > .0001 || Math.Abs(angularVelocity) > .001 || velocity.Length > .001;
    public HaloAnimation(ulong seed) { randomState = seed; Reset(); }
    private double RandomUnit() { randomState = unchecked(randomState * 6364136223846793005UL + 1442695040888963407UL); return (randomState >> 11) / 9007199254740992.0; }
    public void Reset() { Pose = default; angularVelocity = 0; velocity = default; idleActive = false; idleRemaining = 5 + RandomUnit() * 4; }
    public bool Advance(double elapsed, Vec localVelocity, bool characterActive)
    {
        if (!double.IsFinite(elapsed) || elapsed <= 0 || !double.IsFinite(localVelocity.X + localVelocity.Y)) return false;
        var before = Pose; var remaining = Math.Min(.1, elapsed);
        while (remaining > 1e-7)
        {
            var step = Math.Min(1.0 / 120, remaining); remaining -= step;
            var moving = localVelocity.Length > 40;
            if (idleActive) { idleTime += step; if (idleTime >= 1.2) { idleActive = false; idleRemaining = 5 + RandomUnit() * 4; } }
            else if (!moving && !characterActive && !IsAnimating && (idleRemaining -= step) <= 0)
            { idleActive = true; idleTime = 0; idleDirection = RandomUnit() < .5 ? -1 : 1; idlePlaneAngle = RandomUnit() * 2 * Math.PI; }
            var idle = idleActive ? Math.Pow(Math.Sin(Math.PI * idleTime / 1.2), 2) : 0;
            var horizontal = Math.Tanh(localVelocity.X / 450); var vertical = Math.Tanh(localVelocity.Y / 450);
            var idleWeight = idle * (1 - Math.Max(Math.Abs(horizontal), Math.Abs(vertical)));
            var plane = idlePlaneAngle + idleDirection * (idleTime / 1.2) * Math.PI;
            var along = Math.Cos(plane) * idleWeight * .090; var across = Math.Sin(plane) * idleWeight * .056;
            var planeOffset = new Vec(.64, .77) * along + new Vec(-.77, .64) * across;
            var targetAngle = Math.Clamp(-horizontal * .2184 + idleWeight * idleDirection * .1664, -.2184, .2184);
            var targetOffset = new Vec(-horizontal * .0624, -vertical * .0728) + planeOffset;
            angularVelocity += ((targetAngle - Pose.Angle) * 100 - angularVelocity * 12) * step;
            velocity += ((targetOffset - Pose.Offset) * 100 - velocity * 12) * step;
            Pose = new(Pose.Angle + angularVelocity * step, Pose.Offset + velocity * step);
        }
        if (!IsAnimating) { Pose = default; angularVelocity = 0; velocity = default; }
        return Pose != before;
    }
}
