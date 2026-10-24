namespace PigPendant.Core;

public readonly record struct Vec(double X, double Y)
{
    public double Length => Math.Sqrt(X * X + Y * Y);
    public static Vec operator +(Vec a, Vec b) => new(a.X + b.X, a.Y + b.Y);
    public static Vec operator -(Vec a, Vec b) => new(a.X - b.X, a.Y - b.Y);
    public static Vec operator *(Vec a, double s) => new(a.X * s, a.Y * s);
    public static Vec operator /(Vec a, double s) => new(a.X / s, a.Y / s);
}

public enum DisplayMode { Rope, Balloon, Net, Bamboo, Hanging, Ghost }
public enum Parameter { Length, Size, Weight, Elasticity, Damping, Gravity }

public sealed class PendantSettings
{
    public DisplayMode Mode { get; set; } = DisplayMode.Rope;
    public bool Visible { get; set; } = true;
    public int BalloonCount { get; set; } = 2;
    public double BambooPosition { get; set; } = 50;
    public double GhostOffsetX { get; set; } = 44;
    public double GhostOffsetY { get; set; } = 32;
    public Dictionary<DisplayMode, Dictionary<Parameter, double>> Values { get; set; } = new();

    public static readonly Parameter[] Parameters = Enum.GetValues<Parameter>();
    public static (double min, double max, double initial) Spec(Parameter p) => p switch
    {
        Parameter.Length => (20, 1200, 140),
        Parameter.Size => (16, 256, 48),
        Parameter.Weight => (0, 200, 65),
        Parameter.Elasticity => (0, 200, 55),
        Parameter.Damping => (0.2, 8, -60 * Math.Log(0.985)),
        _ => (100, 10000, 1350)
    };
    public double Get(Parameter p, DisplayMode? mode = null)
    {
        var m = mode ?? Mode;
        return Values.TryGetValue(m, out var v) && v.TryGetValue(p, out var value) ? value : Spec(p).initial;
    }
    public void Set(Parameter p, double value, DisplayMode? mode = null)
    {
        if (!double.IsFinite(value)) throw new ArgumentOutOfRangeException(nameof(value));
        var (min, max, _) = Spec(p);
        var m = mode ?? Mode;
        if (!Values.TryGetValue(m, out var values)) Values[m] = values = new();
        values[p] = Math.Clamp(value, min, max);
    }
    public void Normalize()
    {
        if (!Enum.IsDefined(Mode)) Mode = DisplayMode.Rope;
        BalloonCount = Math.Clamp(BalloonCount, 1, 8);
        BambooPosition = double.IsFinite(BambooPosition) ? Math.Clamp(BambooPosition, 0, 100) : 50;
        GhostOffsetX = double.IsFinite(GhostOffsetX) ? Math.Clamp(GhostOffsetX, -300, 300) : 44;
        GhostOffsetY = double.IsFinite(GhostOffsetY) ? Math.Clamp(GhostOffsetY, -300, 300) : 32;
        Values ??= new();
        foreach (var (mode, values) in Values.ToArray())
        {
            if (!Enum.IsDefined(mode) || values is null) { Values.Remove(mode); continue; }
            foreach (var (p, value) in values.ToArray())
            {
                if (!Enum.IsDefined(p) || !double.IsFinite(value)) { values.Remove(p); continue; }
                var (min, max, _) = Spec(p);
                values[p] = Math.Clamp(value, min, max);
            }
        }
    }
}

public sealed class RopePhysics
{
    public const int Segments = 12;
    public readonly Vec[] Nodes = new Vec[Segments + 1];
    private readonly Vec[] previous = new Vec[Segments + 1];
    private Vec? lastAnchor;
    private double accumulator;
    public double Length = 140, CurrentLength = 140, Gravity = 1350, Weight = 65, Elasticity = 55;
    public double DampingPerFrame = 0.985;
    public Vec ForceDirection = new(0, -1);
    public Vec Direction => ForceDirection / Math.Max(ForceDirection.Length, 0.00001);
    public double BobMass => 6 * Math.Pow(10, Weight / 100);
    public double Compliance => CurrentLength * .12 * Math.Pow(Elasticity / 100, 2) / (1350 * 40 * Segments);
    public double MaximumStretch => .12 * Math.Sqrt(Math.Min(100, Elasticity) / 100);
    public Vec EndPoint => Nodes[^1];
    public double EndAngle
    {
        get
        {
            var delta = Nodes[^1] - Nodes[^2];
            return Math.Clamp(Direction.Y > 0 ? Math.Atan2(-delta.X, delta.Y) : Math.Atan2(delta.X, -delta.Y), -.85, .85);
        }
    }
    public void Reset(Vec anchor)
    {
        CurrentLength = Length;
        var distance = CurrentLength / Segments;
        Nodes[0] = anchor;
        for (var i = 0; i < Segments; i++)
        {
            var load = BobMass + Segments - i - 1;
            var stretch = Math.Min(distance * MaximumStretch, Compliance * Gravity * load);
            Nodes[i + 1] = Nodes[i] + Direction * (distance + stretch);
        }
        Array.Copy(Nodes, previous, Nodes.Length);
        accumulator = 0;
        lastAnchor = anchor;
    }
    public void Settle()
    {
        Array.Copy(Nodes, previous, Nodes.Length);
        accumulator = 0;
        lastAnchor = Nodes[0];
    }
    public void Advance(Vec anchor, double timeStep)
    {
        if (lastAnchor is null) Reset(anchor);
        if (!double.IsFinite(anchor.X) || !double.IsFinite(anchor.Y) || !double.IsFinite(timeStep) || timeStep <= 0) return;
        var start = lastAnchor ?? anchor;
        var movement = anchor - start;
        if (timeStep > .25 || movement.Length > Math.Max(600, Length * 4))
        {
            for (var i = 0; i < Nodes.Length; i++) { Nodes[i] += movement; previous[i] += movement; }
            accumulator = 0;
            lastAnchor = anchor;
            return;
        }
        var elapsed = Math.Min(timeStep, .1);
        var carried = accumulator;
        accumulator += elapsed;
        double simulated = 0;
        while (accumulator + 1e-10 >= 1.0 / 120)
        {
            simulated += 1.0 / 120;
            Integrate(start + movement * Math.Clamp((simulated - carried) / elapsed, 0, 1));
            accumulator = Math.Max(0, accumulator - 1.0 / 120);
        }
        lastAnchor = anchor;
    }
    private void Integrate(Vec anchor)
    {
        const double h = 1.0 / 120;
        CurrentLength += (Length - CurrentLength) * (1 - Math.Exp(-8 * h));
        if (Math.Abs(Length - CurrentLength) < .01) CurrentLength = Length;
        var segmentLength = Math.Max(1, CurrentLength / Segments);
        var damping = Math.Pow(DampingPerFrame, h * 60);
        var acceleration = Direction * (Gravity * h * h);
        Nodes[0] = previous[0] = anchor;
        for (var i = 1; i < Nodes.Length; i++)
        {
            var velocity = (Nodes[i] - previous[i]) * damping;
            if (velocity.Length > 2400 * h) velocity *= 2400 * h / velocity.Length;
            previous[i] = Nodes[i];
            Nodes[i] += velocity + acceleration;
        }
        var scaledCompliance = Compliance / (h * h);
        var multipliers = new double[Segments];
        for (var iteration = 0; iteration < 40; iteration++)
        {
            Nodes[0] = anchor;
            for (var i = 0; i < Segments; i++)
            {
                var delta = Nodes[i + 1] - Nodes[i];
                var distance = delta.Length;
                if (distance <= .00001) continue;
                var firstWeight = i == 0 ? 0 : 1;
                var secondWeight = i + 1 == Segments ? 1 / BobMass : 1;
                var change = (-(distance - segmentLength) - scaledCompliance * multipliers[i]) /
                    (firstWeight + secondWeight + scaledCompliance);
                var multiplier = Math.Min(0, multipliers[i] + change);
                var correction = delta * ((multiplier - multipliers[i]) / distance);
                multipliers[i] = multiplier;
                Nodes[i] -= correction * firstWeight;
                Nodes[i + 1] += correction * secondWeight;
            }
        }
        Nodes[0] = anchor;
        var maximum = CurrentLength * (1 + MaximumStretch) / Segments;
        for (var i = 0; i < Segments; i++)
        {
            var delta = Nodes[i + 1] - Nodes[i];
            if (delta.Length > maximum) Nodes[i + 1] = Nodes[i] + delta * (maximum / delta.Length);
        }
    }
}

public sealed class PendantSimulation
{
    public PendantSettings Settings { get; private set; }
    public RopePhysics Rope { get; } = new();
    public List<RopePhysics> Balloons { get; } = new();
    public Vec GhostPosition { get; private set; }
    public double BambooProgress { get; private set; } = 1;
    public double BambooSway { get; private set; }
    private double bendVelocity, stillTime;
    private Vec bambooMotionAnchor;
    public double AnimationTime { get; private set; }
    public IEnumerable<RopePhysics> ActiveRopes => Settings.Mode == DisplayMode.Balloon ? Balloons : [Rope];
    public PendantSimulation(PendantSettings settings) { Settings = settings; Apply(settings); }
    public void Apply(PendantSettings settings)
    {
        Settings = settings;
        Rope.Length = settings.Get(Parameter.Length);
        Rope.Gravity = settings.Get(Parameter.Gravity);
        Rope.Weight = settings.Get(Parameter.Weight);
        Rope.Elasticity = settings.Get(Parameter.Elasticity);
        Rope.DampingPerFrame = Math.Exp(-settings.Get(Parameter.Damping) / 60);
        if (Balloons.Count != settings.BalloonCount)
        {
            Balloons.Clear(); Balloons.Add(Rope);
            for (var i = 1; i < settings.BalloonCount; i++) Balloons.Add(new RopePhysics());
        }
        for (var i = 0; i < Balloons.Count; i++)
        {
            var b = Balloons[i];
            if (i > 0)
            {
                b.Length = Rope.Length * (.8 + i % 3 * .06);
                b.Gravity = Rope.Gravity; b.Weight = Rope.Weight;
                b.Elasticity = Rope.Elasticity; b.DampingPerFrame = Rope.DampingPerFrame;
            }
            var lane = settings.BalloonCount > 1 ? (double)i / (settings.BalloonCount - 1) * 2 - 1 : 0;
            b.ForceDirection = new(lane * (.45 + (settings.BalloonCount - 1) * .08), 1);
        }
        if (settings.Mode != DisplayMode.Balloon) Rope.ForceDirection = new(0, -1);
    }
    private Vec GhostTarget(Vec anchor) => anchor + new Vec(Settings.GhostOffsetX, Settings.GhostOffsetY);
    public void Reset(Vec anchor)
    {
        BambooProgress = 1; BambooSway = 0; bendVelocity = stillTime = 0;
        bambooMotionAnchor = anchor;
        GhostPosition = GhostTarget(anchor);
        AnimationTime = 0;
        foreach (var rope in ActiveRopes) rope.Reset(anchor);
    }
    public void Advance(Vec anchor, double elapsed)
    {
        if (!double.IsFinite(elapsed) || elapsed <= 0) return;
        if (Settings.Mode == DisplayMode.Net) AnimationTime += Math.Min(.1, elapsed);
        if (Settings.Mode == DisplayMode.Ghost)
        {
            var target = GhostTarget(anchor);
            GhostPosition += (target - GhostPosition) * (1 - Math.Exp(-14 * Math.Min(.1, elapsed)));
            if ((target - GhostPosition).Length < .15) GhostPosition = target;
            return;
        }
        if (Settings.Mode == DisplayMode.Bamboo)
        {
            var step = Math.Min(.1, elapsed);
            var moving = (anchor - bambooMotionAnchor).Length >= 2;
            if (moving) bambooMotionAnchor = anchor;
            stillTime = moving ? 0 : stillTime + step;
            var down = !moving && stillTime > .2;
            var target = moving ? -1.2 : down ? .62 : 0;
            var response = moving || down ? 4 : 14;
            var decay = Math.Exp(-response * step);
            var delta = target * step + (bendVelocity - target) * (1 - decay) / response;
            bendVelocity = target + (bendVelocity - target) * decay;
            BambooProgress = Math.Clamp(BambooProgress + delta, 0, 1);
            if (BambooProgress == 0 && bendVelocity < 0 || BambooProgress == 1 && bendVelocity > 0) bendVelocity = 0;
        }
        foreach (var rope in ActiveRopes) rope.Advance(anchor, elapsed);
        if (Settings.Mode == DisplayMode.Bamboo)
            BambooSway += (Rope.EndAngle * -.70 - BambooSway) * (1 - Math.Exp(-12 * Math.Min(.1, elapsed)));
    }
    public double BalloonWidth(int index)
    {
        double[] scales = [1, .8, .92, .74, 1.04, .84, .96, .78];
        return Settings.Get(Parameter.Size) * scales[index % scales.Length];
    }
}
